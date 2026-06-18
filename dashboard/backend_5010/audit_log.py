"""
감사 로그 — 변경계(mutating) Slurm 관리 작업을 누가·언제·무엇을 했는지 기록.

노드 drain/down/reboot, 파티션 state 전환, 잡 hold/release/cancel/requeue 등
실제 클러스터를 바꾸는 작업의 추적 기록. 변경계 REST 를 외부(웹/MCP)에 노출했으므로
운영 보안상 필수.

설계 원칙:
- ★기록 실패가 본 작업을 깨뜨리지 않는다★ — 모든 함수는 예외를 삼키고 로그만 남긴다.
- DB 경로는 다른 모듈과 동일한 DATABASE_PATH(없으면 기본). 별도 의존 없이 sqlite 직접.
- dry_run 호출은 실제 변경이 아니므로 기록하지 않는다(호출측이 판단).
"""
import os
import json
import sqlite3
from datetime import datetime

try:
    from flask import g, request, has_request_context
except Exception:  # flask 없는 컨텍스트(테스트 등)
    g = None
    request = None
    def has_request_context():
        return False

DB_PATH = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')


def _connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def ensure_audit_table():
    """audit_log 테이블 보장(멱등). 앱 기동 시 1회 호출."""
    try:
        conn = _connect()
        conn.execute("""
            CREATE TABLE IF NOT EXISTS audit_log (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP,
                username    TEXT,
                action      TEXT NOT NULL,
                target      TEXT,
                detail      TEXT,
                result      TEXT DEFAULT 'success',
                source_ip   TEXT
            )
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_audit_username ON audit_log(username)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action)")
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[audit] ensure_audit_table failed: {e}")


def _current_username():
    try:
        if has_request_context() and g is not None:
            user = g.get('user') or {}
            return user.get('username') or user.get('id') or 'anonymous'
    except Exception:
        pass
    return 'anonymous'


def _current_ip():
    try:
        if has_request_context() and request is not None:
            return request.headers.get('X-Forwarded-For', request.remote_addr)
    except Exception:
        pass
    return None


def log_admin_action(action, target=None, detail=None, result='success'):
    """변경계 작업 1건 기록. 실패해도 예외를 던지지 않는다(본 작업 보호).

    Args:
        action: 점 표기 동작명 (예: 'node.drain', 'partition.update', 'job.cancel').
        target: 대상 식별자 (노드명/파티션명/잡ID).
        detail: 추가 정보(dict → JSON 저장). 예: {'reason': ..., 'command': ...}.
        result: 'success' | 'fail'.
    """
    try:
        conn = _connect()
        conn.execute(
            "INSERT INTO audit_log (username, action, target, detail, result, source_ip) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                _current_username(),
                str(action),
                str(target) if target is not None else None,
                json.dumps(detail, ensure_ascii=False) if detail is not None else None,
                result,
                _current_ip(),
            ),
        )
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[audit] log_admin_action failed (action={action}): {e}")


def audit_from_scontrol_args(args):
    """slurm_admin_api 의 _run_scontrol_mutation args 튜플 → (action, target).

    args 예: ('requeue','123')→('job.requeue','123');
             ('update','job=123','TimeLimit=1:0:0')→('job.update','123');
             ('update','PartitionName=normal','State=UP')→('partition.update','normal').
    """
    a = list(args) if args else []
    verb = a[0] if a else '?'
    if verb in ('requeue', 'requeuehold', 'hold', 'release', 'top'):
        return f'job.{verb}', (a[1] if len(a) > 1 else None)
    if verb == 'update' and len(a) > 1:
        kv = a[1]
        if kv.startswith('job='):
            return 'job.update', kv[len('job='):]
        if kv.startswith('PartitionName='):
            return 'partition.update', kv[len('PartitionName='):]
    return f'slurm.{verb}', (a[1] if len(a) > 1 else None)
