"""
JWT Authentication Middleware
Validates JWT tokens from Auth Portal for API access
"""
from functools import wraps
from flask import request, jsonify, g
import jwt
import os
import yaml
from pathlib import Path
from typing import Dict, Optional

# JWT 설정 (Auth Portal과 동일한 SECRET_KEY 사용)
JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'dev-jwt-secret-please-change')
JWT_ALGORITHM = os.getenv('JWT_ALGORITHM', 'HS256')

# SSO 설정 로드
def _load_sso_config():
    """Load SSO configuration from YAML"""
    try:
        yaml_path = Path(__file__).parent.parent.parent.parent / 'my_multihead_cluster.yaml'
        if yaml_path.exists():
            with open(yaml_path) as f:
                config = yaml.safe_load(f)
                return config.get('sso', {}).get('enabled', True)
    except Exception:
        pass
    return True  # Default to SSO enabled

SSO_ENABLED = _load_sso_config()

# SSO false 모드에서 사용할 전체 권한 사용자
FULL_ACCESS_USER = {
    'username': 'admin',
    'email': 'admin@local',
    'groups': ['admin', 'users', 'GPU-Users', 'HPC-Admins'],
    'permissions': ['admin', 'user', 'read', 'write', 'execute', 'delete']
}


def verify_jwt_token(token: str) -> Optional[Dict]:
    """
    JWT 토큰 검증 (WebSocket 등에서 사용)

    Args:
        token: JWT 토큰 문자열

    Returns:
        dict: 검증된 사용자 정보
        None: 검증 실패

    Raises:
        jwt.ExpiredSignatureError: 토큰 만료
        jwt.InvalidTokenError: 유효하지 않은 토큰
    """
    try:
        # JWT 토큰 검증
        payload = jwt.decode(
            token,
            JWT_SECRET_KEY,
            algorithms=[JWT_ALGORITHM]
        )

        # 사용자 정보 반환
        return {
            'username': payload.get('sub'),
            'email': payload.get('email'),
            'groups': payload.get('groups', []),
            'permissions': payload.get('permissions', [])
        }

    except jwt.ExpiredSignatureError:
        raise
    except jwt.InvalidTokenError:
        raise


def jwt_required(f):
    """
    JWT 토큰 검증 데코레이터
    Authorization 헤더에서 Bearer 토큰을 추출하고 검증

    SSO가 비활성화된 경우, 모든 요청에 전체 권한 부여
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # SSO가 비활성화된 경우, 전체 권한 사용자로 자동 로그인
        if not SSO_ENABLED:
            g.user = FULL_ACCESS_USER.copy()
            return f(*args, **kwargs)

        # SSO 활성화 모드: JWT 검증 진행
        # Authorization 헤더 확인
        auth_header = request.headers.get('Authorization')

        if not auth_header:
            return jsonify({
                'error': 'No authorization header',
                'message': 'Authorization header is required'
            }), 401

        if not auth_header.startswith('Bearer '):
            return jsonify({
                'error': 'Invalid authorization header',
                'message': 'Authorization header must start with "Bearer "'
            }), 401

        # 토큰 추출
        token = auth_header.split(' ')[1]

        try:
            # JWT 토큰 검증
            payload = jwt.decode(
                token,
                JWT_SECRET_KEY,
                algorithms=[JWT_ALGORITHM]
            )

            # 검증된 사용자 정보를 Flask g 객체에 저장
            g.user = {
                'username': payload.get('sub'),
                'email': payload.get('email'),
                'groups': payload.get('groups', []),
                'permissions': payload.get('permissions', [])
            }

            return f(*args, **kwargs)

        except jwt.ExpiredSignatureError:
            return jsonify({
                'error': 'Token expired',
                'message': 'Your session has expired. Please log in again.'
            }), 401

        except jwt.InvalidTokenError as e:
            return jsonify({
                'error': 'Invalid token',
                'message': f'Token validation failed: {str(e)}'
            }), 401

    return decorated_function


def permission_required(*required_permissions):
    """
    권한 검증 데코레이터
    사용자가 필요한 권한을 가지고 있는지 확인

    Usage:
        @app.route('/api/admin/users')
        @jwt_required
        @permission_required('admin')
        def admin_users():
            ...
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            user = g.get('user')

            if not user:
                return jsonify({
                    'error': 'Unauthorized',
                    'message': 'User information not found'
                }), 401

            user_permissions = user.get('permissions', [])

            # 필요한 권한 중 하나라도 가지고 있으면 허용
            has_permission = any(perm in user_permissions for perm in required_permissions)

            if not has_permission:
                return jsonify({
                    'error': 'Forbidden',
                    'message': f'Required permissions: {", ".join(required_permissions)}',
                    'user_permissions': user_permissions
                }), 403

            return f(*args, **kwargs)

        return decorated_function
    return decorator


def group_required(*required_groups):
    """
    그룹 검증 데코레이터
    사용자가 특정 그룹에 속해있는지 확인

    Usage:
        @app.route('/api/gpu/jobs')
        @jwt_required
        @group_required('GPU-Users', 'HPC-Admins')
        def gpu_jobs():
            ...
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            user = g.get('user')

            if not user:
                return jsonify({
                    'error': 'Unauthorized',
                    'message': 'User information not found'
                }), 401

            user_groups = user.get('groups', [])

            # 필요한 그룹 중 하나라도 속해있으면 허용
            is_member = any(group in user_groups for group in required_groups)

            if not is_member:
                return jsonify({
                    'error': 'Forbidden',
                    'message': f'Required groups: {", ".join(required_groups)}',
                    'user_groups': user_groups
                }), 403

            return f(*args, **kwargs)

        return decorated_function
    return decorator


def optional_jwt(f):
    """
    선택적 JWT 검증 데코레이터
    토큰이 있으면 검증하지만, 없어도 요청을 허용
    토큰이 있으면 g.user에 사용자 정보 저장

    SSO가 비활성화된 경우, 항상 전체 권한 사용자로 설정

    Usage:
        @app.route('/api/public/data')
        @optional_jwt
        def public_data():
            if g.get('user'):
                # 인증된 사용자
                return jsonify({'data': 'premium'})
            else:
                # 비인증 사용자
                return jsonify({'data': 'basic'})
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # SSO가 비활성화된 경우, 전체 권한 사용자로 자동 설정
        if not SSO_ENABLED:
            g.user = FULL_ACCESS_USER.copy()
            return f(*args, **kwargs)

        # SSO 활성화 모드: 선택적 JWT 검증
        auth_header = request.headers.get('Authorization')

        if auth_header and auth_header.startswith('Bearer '):
            token = auth_header.split(' ')[1]

            try:
                payload = jwt.decode(
                    token,
                    JWT_SECRET_KEY,
                    algorithms=[JWT_ALGORITHM]
                )

                g.user = {
                    'username': payload.get('sub'),
                    'email': payload.get('email'),
                    'groups': payload.get('groups', []),
                    'permissions': payload.get('permissions', [])
                }
            except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
                # 토큰이 유효하지 않으면 무시하고 진행
                g.user = None
        else:
            g.user = None

        return f(*args, **kwargs)

    return decorated_function
