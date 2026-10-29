# 공유 비밀을 쥔 게이트웨이·DynaForge 에 그 사람의 kst_ PAT 를 내주는 표준 위임 창구(/api/auth/sso)
"""표준 위임 창구 — HWAX 게이트웨이(per_user_sso)·DynaForge 가 사용자 대신 대시보드를 부를 kst_ 를 받는다.

규격은 게이트웨이가 이미 부르는 꼴(HWAXMcpGateway gateway.py `_sso_headers`·`_mint_user_pat`)을 따른다.
결정 근거: docs/sso_enable_20261029/context-notes.md

- `POST /api/auth/sso/verify` — 비밀만 대조. 구성 없음 404 · 맞음 204 · 틀림 401. 사용자·토큰은 건드리지 않는다.
- `POST /api/auth/sso` — 위임 이메일의 kst_ 발급. 200 {access_token, token_type, expires_in, username, client}.
  같은 (사람, 클라이언트)의 직전 토큰은 지운다(클라이언트당 활성 1개, 다른 클라이언트 토큰은 그대로).
"""
import hmac
import os
import re

from flask import Blueprint, Response, g, jsonify, request

import mcp_token
from audit_log import log_admin_action
from middleware.rate_limiter import rate_limit_by_ip

sso_delegate_bp = Blueprint('sso_delegate', __name__)

DELEGATE_TTL_SEC = 3600
# 위임 토큰은 "그 사람의 잡을 그 사람 대신" 다루는 최소 권한 — 웹에서 admin 이어도 user 다.
DELEGATE_IDENTITY = {'role': 'user', 'permissions': ['dashboard'], 'groups': []}
# SSO 꺼짐 동안의 잡·결과·업로드가 전부 admin 명의라, 이 이름으로 발급하면 그 전부가 열린다.
RESERVED_USERNAMES = {'admin', 'anonymous', 'root'}
_USERNAME_RE = re.compile(r'[a-z0-9._-]{1,32}')


def _secret() -> str:
    return os.getenv('HEAX_GATEWAY_SECRET', '')


def _allowed_clients() -> set:
    raw = os.getenv('SSO_DELEGATE_CLIENTS', 'dynaforge,gateway')
    return {c.strip().lower() for c in raw.split(',') if c.strip()}


def _secret_matches(secret: str) -> bool:
    return hmac.compare_digest(request.headers.get('X-Heax-Gateway-Secret', ''), secret)


def username_for_email(email: str):
    """이메일 → 대시보드 사용자 이름(@ 앞부분, 소문자). 규칙에 안 맞거나 예약 이름이면 None.
    운영 SAML uid(JWT sub)가 이메일 앞부분과 같다는 가정 — context-notes 참조."""
    email = (email or '').strip().lower()
    if email.count('@') != 1:
        return None
    local, domain = email.split('@')
    if not domain or not _USERNAME_RE.fullmatch(local) or local.startswith('.') or local in RESERVED_USERNAMES:
        return None
    return local


@sso_delegate_bp.route('/api/auth/sso/verify', methods=['POST'])
def sso_verify():
    secret = _secret()
    if not secret:
        return jsonify({'error': 'SSO 위임이 구성되어 있지 않습니다(HEAX_GATEWAY_SECRET)'}), 404
    if not _secret_matches(secret):
        return jsonify({'error': '게이트웨이 비밀 불일치'}), 401
    return Response(status=204)


@sso_delegate_bp.route('/api/auth/sso', methods=['POST'])
@rate_limit_by_ip(max_requests=120, window_seconds=60)
def sso_delegate():
    secret = _secret()
    if not secret:
        return jsonify({'error': 'SSO 위임이 구성되어 있지 않습니다(HEAX_GATEWAY_SECRET)'}), 404
    if not _secret_matches(secret):
        return jsonify({'error': '게이트웨이 비밀 불일치'}), 401

    # Caddy 경로에서는 X-Heax-User-Email 이 서비스 토큰 주인으로 덮일 수 있어 위임 헤더가 정본이다.
    email = (request.headers.get('X-Hwax-Delegate-Email') or request.headers.get('X-Heax-User-Email') or '').strip().lower()
    username = username_for_email(email)
    if username is None:
        return jsonify({'error': f'위임할 수 없는 이메일: {email!r} — @ 앞부분이 [a-z0-9._-] 1~32자여야 하고 '
                                 f'{sorted(RESERVED_USERNAMES)} 는 받지 않는다'}), 400
    client = (request.headers.get('X-Heax-Client') or '').strip().lower()
    allowed = _allowed_clients()
    if client not in allowed:
        return jsonify({'error': f'알 수 없는 클라이언트: {client!r} (허용: {", ".join(sorted(allowed))})'}), 400

    identity = {'username': username, 'email': email, **DELEGATE_IDENTITY}
    _info, plaintext = mcp_token.rotate_token(identity, f'위임: {client}', DELEGATE_TTL_SEC)
    g.user = {'username': f'delegate:{client}'}   # 감사 행위자
    log_admin_action('token.delegate', target=username, detail={'client': client, 'email': email,
                                                                  'expires_in': DELEGATE_TTL_SEC})
    return jsonify({'access_token': plaintext, 'token_type': 'bearer', 'expires_in': DELEGATE_TTL_SEC,
                    'username': username, 'client': client})
