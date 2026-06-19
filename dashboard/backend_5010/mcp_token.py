"""
개인 액세스 토큰(Personal Access Token) — MCP 등 외부 클라이언트용. 발급·조회·삭제·검증.

Claude(Claude Code/Desktop) 의 MCP 클라이언트가 `Authorization: Bearer kst_...` 로 쓴다.
평문은 발급 시 1회만 반환하고 DB 엔 sha256 해시만 둔다. 인증 미들웨어(jwt_middleware)가
접두사(kst_)로 JWT 와 구분해 resolve_token 을 호출한다.

설계 원칙(이 프로젝트 관례):
- DB 는 다른 모듈과 동일한 raw sqlite(DATABASE_PATH). SQLAlchemy 미사용 — audit_log.py 와 동일 스타일.
- users 테이블이 없다(신원은 Auth Portal JWT 기반). 따라서 PAT 는 발급 시점의 **신원 스냅샷**
  (username/email/groups/permissions/role)을 저장하고, resolve 시 그대로 g.user 로 복원한다.
  → 발급 후 그룹/역할이 바뀌어도 토큰은 옛 권한 유지(취소·만료로 통제). v1 의 의도된 단순화.
"""
import os
import json
import hashlib
import secrets
import sqlite3
from datetime import datetime, timedelta

DB_PATH = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')

TOKEN_PREFIX = "kst_"  # Koo Slurm Token — JWT 와 구분되는 접두사
DEFAULT_EXPIRES_DAYS = 90
# last_used_at 잦은 갱신 억제(인증 경로 쓰기 최소화). 분 단위.
_TOUCH_INTERVAL_MIN = 10


def _connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def _hash(plaintext: str) -> str:
    return hashlib.sha256(plaintext.encode("utf-8")).hexdigest()


def ensure_token_table():
    """personal_access_tokens 테이블 보장(멱등). 앱 기동 시 1회 호출.
    schema.sql 에도 동일 정의가 있으나, 신규 배포/기존 DB 양쪽에서 안전하도록 여기서도 보장."""
    try:
        conn = _connect()
        conn.execute("""
            CREATE TABLE IF NOT EXISTS personal_access_tokens (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                username         TEXT NOT NULL,
                name             TEXT NOT NULL,
                token_prefix     TEXT NOT NULL,
                token_hash       TEXT NOT NULL UNIQUE,
                email            TEXT,
                groups_json      TEXT,
                permissions_json TEXT,
                role             TEXT,
                created_at       DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_used_at     DATETIME,
                expires_at       DATETIME,
                revoked_at       DATETIME
            )
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_pat_username ON personal_access_tokens(username)")
        conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_pat_token_hash ON personal_access_tokens(token_hash)")
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[mcp_token] ensure_token_table failed: {e}")


def create_token(identity: dict, name: str, expires_days=DEFAULT_EXPIRES_DAYS):
    """새 토큰 발급. (info dict, 평문) 반환 — 평문은 호출부가 1회만 사용자에게 노출.

    Args:
        identity: 발급자 신원(g.user) — username/email/groups/permissions/role 스냅샷.
        name: 토큰 라벨(예: '내 노트북').
        expires_days: 만료일수(None 이면 무기한).
    """
    plaintext = TOKEN_PREFIX + secrets.token_urlsafe(32)
    now = datetime.utcnow()
    expires_at = (now + timedelta(days=expires_days)) if expires_days else None
    username = (identity.get('username') or 'unknown')

    conn = _connect()
    cur = conn.execute(
        "INSERT INTO personal_access_tokens "
        "(username, name, token_prefix, token_hash, email, groups_json, permissions_json, role, "
        " created_at, expires_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            username,
            (name or "MCP 토큰").strip()[:100],
            plaintext[:12],  # 표시용(kst_ + 앞 8자)
            _hash(plaintext),
            identity.get('email'),
            json.dumps(identity.get('groups') or [], ensure_ascii=False),
            json.dumps(identity.get('permissions') or [], ensure_ascii=False),
            identity.get('role') or 'user',
            now.isoformat(sep=' ', timespec='seconds'),
            expires_at.isoformat(sep=' ', timespec='seconds') if expires_at else None,
        ),
    )
    conn.commit()
    row = conn.execute(
        "SELECT * FROM personal_access_tokens WHERE id = ?", (cur.lastrowid,)
    ).fetchone()
    conn.close()
    return _public(row), plaintext


def list_tokens(username: str):
    """해당 사용자의 **유효한**(취소 안 된) 토큰만, 최신순. 평문/해시는 제외."""
    conn = _connect()
    rows = conn.execute(
        "SELECT * FROM personal_access_tokens "
        "WHERE username = ? AND revoked_at IS NULL ORDER BY id DESC",
        (username,),
    ).fetchall()
    conn.close()
    return [_public(r) for r in rows]


def delete_token(username: str, token_id: int) -> bool:
    """토큰 삭제 — 즉시 무효화 + 행 제거. 남의 토큰/미존재면 False."""
    conn = _connect()
    cur = conn.execute(
        "DELETE FROM personal_access_tokens WHERE id = ? AND username = ?",
        (token_id, username),
    )
    conn.commit()
    deleted = cur.rowcount > 0
    conn.close()
    return deleted


def resolve_token(plaintext: str):
    """평문 토큰 → 신원 dict(jwt_middleware 가 g.user 로 사용). 취소·만료·미존재면 None.
    유효하면 last_used_at 을 가끔 갱신(인증 경로라 쓰기 최소화). 절대 예외를 던지지 않는다."""
    try:
        if not plaintext or not plaintext.startswith(TOKEN_PREFIX):
            return None
        conn = _connect()
        row = conn.execute(
            "SELECT * FROM personal_access_tokens WHERE token_hash = ?",
            (_hash(plaintext),),
        ).fetchone()
        if row is None or row['revoked_at'] is not None:
            conn.close()
            return None
        now = datetime.utcnow()
        if row['expires_at']:
            try:
                if datetime.fromisoformat(row['expires_at']) <= now:
                    conn.close()
                    return None
            except (ValueError, TypeError):
                pass  # 파싱 실패 시 만료로 취급하지 않음(보수적)
        # last_used_at 갱신(throttle)
        try:
            last = datetime.fromisoformat(row['last_used_at']) if row['last_used_at'] else None
        except (ValueError, TypeError):
            last = None
        if last is None or (now - last) > timedelta(minutes=_TOUCH_INTERVAL_MIN):
            conn.execute(
                "UPDATE personal_access_tokens SET last_used_at = ? WHERE id = ?",
                (now.isoformat(sep=' ', timespec='seconds'), row['id']),
            )
            conn.commit()
        conn.close()
        return {
            'username': row['username'],
            'email': row['email'],
            'groups': _loads(row['groups_json']),
            'permissions': _loads(row['permissions_json']),
            'role': row['role'] or 'user',
        }
    except Exception as e:
        print(f"[mcp_token] resolve_token failed: {e}")
        return None


def _loads(s):
    try:
        return json.loads(s) if s else []
    except (ValueError, TypeError):
        return []


def _public(row) -> dict:
    """평문/해시 제외한 토큰 메타. 상태는 revoked_at/expires_at 로 프런트가 판단."""
    return {
        'id': row['id'],
        'name': row['name'],
        'token_prefix': row['token_prefix'],
        'created_at': row['created_at'],
        'last_used_at': row['last_used_at'],
        'expires_at': row['expires_at'],
        'revoked_at': row['revoked_at'],
    }
