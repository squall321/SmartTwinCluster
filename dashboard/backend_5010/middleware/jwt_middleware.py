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
    """
    Load SSO configuration

    우선순위:
    1. 환경변수 SSO_ENABLED (true/false)
    2. YAML 파일 (my_multihead_cluster.yaml)
    3. 기본값: True (SSO enabled)
    """
    # 1. 환경변수 확인 (최우선)
    env_sso = os.getenv('SSO_ENABLED', '').lower()
    if env_sso in ('true', 'false'):
        enabled = env_sso == 'true'
        print(f"[SSO Config] Loaded from environment variable: SSO_ENABLED={enabled}")
        return enabled

    # 2. YAML 파일 확인
    try:
        # 환경변수로 YAML 경로 지정 가능
        yaml_path_str = os.getenv('CLUSTER_CONFIG_PATH')
        if yaml_path_str:
            yaml_path = Path(yaml_path_str)
        else:
            yaml_path = Path(__file__).parent.parent.parent.parent / 'my_multihead_cluster.yaml'

        if yaml_path.exists():
            with open(yaml_path) as f:
                config = yaml.safe_load(f)
                enabled = config.get('sso', {}).get('enabled', True)
                print(f"[SSO Config] Loaded from YAML ({yaml_path}): sso.enabled={enabled}")
                return enabled
        else:
            print(f"[SSO Config] YAML file not found: {yaml_path}")
    except Exception as e:
        print(f"[SSO Config] Error loading YAML: {e}")

    # 3. 기본값
    print("[SSO Config] Using default: SSO enabled")
    return True  # Default to SSO enabled

SSO_ENABLED = _load_sso_config()

# SSO false 모드에서 사용할 전체 권한 사용자
FULL_ACCESS_USER = {
    'username': 'admin',
    'email': 'admin@local',
    'groups': ['admin', 'users', 'GPU-Users', 'HPC-Admins'],
    'permissions': ['admin', 'user', 'read', 'write', 'execute', 'delete', 'dashboard', 'app', 'vnc', 'cae'],
    'role': 'admin'
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
            'permissions': payload.get('permissions', []),
            'role': payload.get('role', 'user')
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
                'permissions': payload.get('permissions', []),
                'role': payload.get('role', 'user')
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
                    'permissions': payload.get('permissions', []),
                    'role': payload.get('role', 'user')
                }
            except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
                # 토큰이 유효하지 않으면 무시하고 진행
                g.user = None
        else:
            g.user = None

        return f(*args, **kwargs)

    return decorated_function


# ============================================================================
# 권한모델 Phase3-A: role 기반 파티션 접근제어 (shadow 모드)
# ============================================================================
# YAML(SoT)의 roles.definitions 를 로드. _load_sso_config 와 동일한 경로해석 재사용.
# 런타임 변경 미반영(재기동 필요) = SSO_ENABLED 와 동일 성질이라 일관.

def _load_role_definitions():
    """YAML roles.definitions(role -> allowed_partitions/allowed_qos/can_manage_nodes) 로드."""
    try:
        yaml_path_str = os.getenv('CLUSTER_CONFIG_PATH')
        if yaml_path_str:
            yaml_path = Path(yaml_path_str)
        else:
            yaml_path = Path(__file__).parent.parent.parent.parent / 'my_multihead_cluster.yaml'
        if yaml_path.exists():
            with open(yaml_path) as fp:
                config = yaml.safe_load(fp) or {}
                defs = (config.get('roles') or {}).get('definitions') or {}
                if defs:
                    print(f"[Role Config] Loaded {len(defs)} role definitions from {yaml_path}")
                return defs
    except Exception as e:
        print(f"[Role Config] Error loading role definitions: {e}")
    return {}

ROLE_DEFINITIONS = _load_role_definitions()

# 운영 판별: MOCK_MODE=false = production (app.py 와 동일 변수 재사용).
IS_PROD = os.getenv('MOCK_MODE', 'true').lower() == 'false'

# 파티션 접근제어 enforce 토글: 기본 'false'=shadow(로그만+통과) 유지 → 무중단 배포.
# PARTITION_ENFORCE=true 로 켜면 위반 요청을 403 으로 차단(코드 재배포 없이 env 토글).
PARTITION_ENFORCE = os.getenv('PARTITION_ENFORCE', 'false').lower() == 'true'

# SSO-off 전권 가드: 운영에서 SSO 비활성이면 모든 요청이 admin 전권(인증 무력화).
# 기동거부까진 하지 않고(기존 동작 보존) 모듈 로드 시 1회 경고만 출력.
if IS_PROD and not SSO_ENABLED:
    print(
        "[SECURITY][WARNING] SSO_ENABLED=false + MOCK_MODE=false(production): "
        "모든 요청이 FULL_ACCESS_USER(admin 전권)로 통과합니다 — 인증/인가가 무력화된 상태입니다. "
        "운영에서는 sso.enabled=true 를 권장합니다."
    )


def is_partition_allowed(role, partition):
    """role 의 allowed_partitions 기준 partition 허용 여부 (순수 판정 — 로그/차단 없음).

    Returns (allowed: bool, allowed_partitions: list).
    partition 미지정(빈값) / 와일드카드('*') / 허용목록 포함 → (True, list).
    데코레이터(@partition_allowed)와 잡 제출 경로(generate_slurm_script)가 공유한다.
    """
    # ★안전장치★: 권한모델 미배포(YAML roles 없음 → ROLE_DEFINITIONS 비었음)이거나
    # 해당 role 정의가 없으면 강제하지 않는다(전부 허용). YAML roles 를 운영서에
    # 반영하기 전 PARTITION_ENFORCE 를 켜도 정상 제출이 막히지 않게(무중단).
    if not ROLE_DEFINITIONS or role not in ROLE_DEFINITIONS:
        return True, []
    allowed = (ROLE_DEFINITIONS.get(role) or {}).get('allowed_partitions', [])
    if not partition or '*' in allowed or partition in allowed:
        return True, allowed
    return False, allowed


def partition_allowed(partition_arg='partition'):
    """잡 제출 등에서 요청 파티션이 g.user.role 의 allowed_partitions 에 있는지 검사.

    ★shadow→enforce 전환 가능★: PARTITION_ENFORCE 환경변수로 동작 토글.
    - PARTITION_ENFORCE=false (기본): shadow 모드 — 위반해도 차단하지 않고 'DENY-WOULD-BE'
      WARN 로그만 남기고 통과(실트래픽으로 룰 검증). 이번 배포는 기존 동작 그대로 = 무중단.
    - PARTITION_ENFORCE=true: enforce 모드 — 위반 시 'DENY' 로그 후 403 차단.
    운영이 룰 검증 후 env 토글만으로(코드 재배포 없이) 차단 시작 가능.

    Args:
        partition_arg: 요청 JSON body 또는 view kwarg 에서 파티션명을 읽을 키 이름.
    """
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            user = g.get('user') or {}
            role = user.get('role', 'user')
            # 요청 파티션 추출 (body 우선, 없으면 view kwarg). 없으면 클러스터 기본값 사용 → 통과.
            body = request.get_json(silent=True) or {}
            part = body.get(partition_arg) or kwargs.get(partition_arg)
            ok, allowed = is_partition_allowed(role, part)
            if not ok:
                # enforce/shadow 공통으로 위반을 로그. prefix 로 모드 구분.
                prefix = 'DENY' if PARTITION_ENFORCE else 'DENY-WOULD-BE'
                print(
                    f"[partition {'enforce' if PARTITION_ENFORCE else 'shadow'}] {prefix} "
                    f"user={user.get('username')} role={role} partition={part} "
                    f"allowed={allowed} path={request.path}"
                )
                if PARTITION_ENFORCE:
                    # enforce: 위반 차단
                    return jsonify({
                        'success': False,
                        'error': 'partition not allowed for your role',
                        'role': role,
                        'partition': part,
                        'allowed_partitions': allowed,
                    }), 403
            # shadow(기본) 또는 위반 아님: 통과
            return f(*args, **kwargs)
        return wrapper
    return decorator
