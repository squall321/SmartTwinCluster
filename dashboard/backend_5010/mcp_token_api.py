"""
개인 액세스 토큰(MCP 연동) API + 현재 사용자(whoami).

- GET    /api/me                  현재 인증된 사용자 신원(MCP 읽기 게이트 + 프론트 연결가이드용)
- GET    /api/me/mcp-tokens       내 토큰 목록(평문 제외)
- POST   /api/me/mcp-tokens       새 토큰 발급(평문은 이 응답에서 1회만 노출)
- DELETE /api/me/mcp-tokens/<id>  내 토큰 삭제(즉시 무효화)

모두 @jwt_required — 본인(g.user)의 토큰만 다룬다(목록/삭제가 username 으로 스코프됨).
PAT(kst_)·JWT 양쪽으로 인증 가능(jwt_middleware 가 접두사로 구분).
"""
from flask import Blueprint, request, jsonify, g
from middleware.jwt_middleware import jwt_required
import mcp_token

mcp_token_bp = Blueprint('mcp_token', __name__)


def _username():
    user = g.get('user') or {}
    return user.get('username') or 'unknown'


@mcp_token_bp.route('/api/me', methods=['GET'])
@jwt_required
def whoami():
    """현재 인증된 사용자 신원. MCP 서버의 읽기 게이트가 이 엔드포인트로 토큰을 검증하고,
    프론트는 연결 가이드의 부서/역할 표시에 쓴다."""
    user = g.get('user') or {}
    return jsonify({
        'success': True,
        'username': user.get('username'),
        'email': user.get('email'),
        'role': user.get('role', 'user'),
        'groups': user.get('groups', []),
        'permissions': user.get('permissions', []),
    }), 200


@mcp_token_bp.route('/api/me/mcp-tokens', methods=['GET'])
@jwt_required
def list_my_tokens():
    """내 토큰 목록(평문/해시 제외). 상태는 revoked_at/expires_at 로 프런트가 판단."""
    try:
        mcp_token.ensure_token_table()
        return jsonify({'success': True, 'tokens': mcp_token.list_tokens(_username())}), 200
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@mcp_token_bp.route('/api/me/mcp-tokens', methods=['POST'])
@jwt_required
def create_my_token():
    """새 토큰 발급. 평문(token)은 **이 응답에서 1회만** 노출된다(이후 조회 불가).

    Body(JSON): { name: str(필수), expires_days: int|null(기본 90) }
    """
    try:
        mcp_token.ensure_token_table()
        data = request.get_json(silent=True) or {}
        name = (data.get('name') or '').strip()
        if not name:
            return jsonify({'success': False, 'error': '토큰 이름(name)이 필요합니다.'}), 400

        expires_days = data.get('expires_days', mcp_token.DEFAULT_EXPIRES_DAYS)
        if expires_days is not None:
            try:
                expires_days = int(expires_days)
                if expires_days <= 0 or expires_days > 3650:
                    return jsonify({'success': False, 'error': 'expires_days 는 1~3650 사이여야 합니다.'}), 400
            except (TypeError, ValueError):
                return jsonify({'success': False, 'error': 'expires_days 는 정수여야 합니다.'}), 400

        info, plaintext = mcp_token.create_token(g.get('user') or {}, name, expires_days=expires_days)
        return jsonify({
            'success': True,
            'token': plaintext,  # 1회 노출
            'info': info,
            'message': '토큰이 생성되었습니다. 지금 복사하세요 — 다시 볼 수 없습니다.',
        }), 201
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@mcp_token_bp.route('/api/me/mcp-tokens/<int:token_id>', methods=['DELETE'])
@jwt_required
def delete_my_token(token_id):
    """내 토큰 삭제(즉시 무효화 + 목록에서 제거). 남의 토큰이거나 없으면 404."""
    try:
        if not mcp_token.delete_token(_username(), token_id):
            return jsonify({'success': False, 'error': '토큰을 찾을 수 없습니다.'}), 404
        return jsonify({'success': True, 'message': '토큰을 삭제했습니다.'}), 200
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
