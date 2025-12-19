"""
Auth Portal Configuration
Supports SAML and OIDC authentication
"""
import os
import json
from dotenv import load_dotenv

load_dotenv()


class Config:
    """Base configuration"""

    # Flask
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key-please-change')
    DEBUG = os.getenv('FLASK_DEBUG', 'False') == 'True'

    # JWT
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'dev-jwt-secret-please-change')
    JWT_ALGORITHM = os.getenv('JWT_ALGORITHM', 'HS256')
    JWT_EXPIRATION_HOURS = int(os.getenv('JWT_EXPIRATION_HOURS', '8'))

    # Redis
    REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
    REDIS_PORT = int(os.getenv('REDIS_PORT', '6379'))
    REDIS_DB = int(os.getenv('REDIS_DB', '0'))
    REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', '')

    # ==========================================================================
    # SSO Configuration (SAML or OIDC)
    # ==========================================================================

    # SSO 활성화 여부 (false면 Mock IdP 사용)
    SSO_ENABLED = os.getenv('SSO_ENABLED', 'false').lower() == 'true'

    # SSO 타입: saml | oidc
    SSO_TYPE = os.getenv('SSO_TYPE', 'saml')

    # ==========================================================================
    # SAML Configuration
    # ==========================================================================

    SAML_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'saml')
    SAML_IDP_METADATA_URL = os.getenv('SAML_IDP_METADATA_URL', 'http://localhost:7000/metadata')
    SAML_SP_ENTITY_ID = os.getenv('SAML_SP_ENTITY_ID', 'auth-portal')
    SAML_ACS_URL = os.getenv('SAML_ACS_URL', 'http://localhost:4430/auth/saml/acs')
    SAML_SLS_URL = os.getenv('SAML_SLS_URL', 'http://localhost:4430/auth/saml/sls')

    # SAML IdP 설정 (개별 설정 시 사용)
    SAML_IDP_ENTITY_ID = os.getenv('SAML_IDP_ENTITY_ID', '')
    SAML_IDP_SSO_URL = os.getenv('SAML_IDP_SSO_URL', '')
    SAML_IDP_SLO_URL = os.getenv('SAML_IDP_SLO_URL', '')
    SAML_IDP_CERTIFICATE = os.getenv('SAML_IDP_CERTIFICATE', '')

    # ==========================================================================
    # OIDC Configuration
    # ==========================================================================

    OIDC_ISSUER = os.getenv('OIDC_ISSUER', '')
    OIDC_CLIENT_ID = os.getenv('OIDC_CLIENT_ID', '')
    OIDC_CLIENT_SECRET = os.getenv('OIDC_CLIENT_SECRET', '')
    OIDC_SCOPES = os.getenv('OIDC_SCOPES', 'openid,profile,email,groups').split(',')

    # OIDC Claims 요청 (SAML의 AttributeConsumingService와 유사)
    # SAML은 IdP에게 원하는 속성을 명시적으로 요청하지만,
    # OIDC는 scope로 요청하고 실제 클레임은 IdP가 결정함.
    # 여기서 명시적 클레임 요청을 설정하면 claims 파라미터로 전달됨.
    # 형식: 쉼표로 구분된 클레임 이름 목록
    # 예: "preferred_username,email,groups,department"
    OIDC_REQUESTED_CLAIMS = os.getenv('OIDC_REQUESTED_CLAIMS', '').split(',') if os.getenv('OIDC_REQUESTED_CLAIMS') else []

    @classmethod
    def get_oidc_config(cls):
        """Get OIDC configuration dictionary"""
        return {
            'issuer': cls.OIDC_ISSUER,
            'client_id': cls.OIDC_CLIENT_ID,
            'client_secret': cls.OIDC_CLIENT_SECRET,
            'scopes': cls.OIDC_SCOPES,
            'requested_claims': cls.OIDC_REQUESTED_CLAIMS
        }

    # Alias for property-style access
    OIDC_CONFIG = property(lambda self: Config.get_oidc_config())

    # ==========================================================================
    # SSO Attribute Mapping (공통)
    # ==========================================================================

    # 기본 속성 매핑
    _DEFAULT_ATTRIBUTE_MAPPING = {
        'username': 'uid',           # SAML: uid, OIDC: preferred_username
        'email': 'email',
        'groups': 'groups',          # SAML: memberOf, OIDC: groups
        'display_name': 'displayName',
        'department': 'department'
    }

    @classmethod
    def get_attribute_mapping(cls):
        """Get attribute mapping from environment or defaults"""
        mapping_json = os.getenv('SSO_ATTRIBUTE_MAPPING', '')
        if mapping_json:
            try:
                return json.loads(mapping_json)
            except json.JSONDecodeError:
                pass
        return cls._DEFAULT_ATTRIBUTE_MAPPING

    # Alias for property-style access
    SSO_ATTRIBUTE_MAPPING = property(lambda self: Config.get_attribute_mapping())

    # ==========================================================================
    # Service URLs - Nginx reverse proxy paths
    # ==========================================================================

    DASHBOARD_URL = os.getenv('DASHBOARD_URL', '/dashboard')
    CAE_URL = os.getenv('CAE_URL', '/cae')
    VNC_URL = os.getenv('VNC_URL', '/vnc')
    APP_URL = os.getenv('APP_URL', '/app')

    # Server
    HOST = os.getenv('HOST', '0.0.0.0')
    PORT = int(os.getenv('PORT', '4430'))

    # ==========================================================================
    # Group-based permissions
    # ==========================================================================

    # 기본 그룹 권한 (환경변수로 오버라이드 가능)
    _DEFAULT_GROUP_PERMISSIONS = {
        'HPC-Admins': ['dashboard', 'cae', 'vnc', 'app', 'admin'],
        'DX-Users': ['dashboard', 'vnc', 'app'],
        'CAEG-Users': ['dashboard', 'cae', 'vnc', 'app'],
    }

    @classmethod
    def get_group_permissions(cls):
        """Get group permissions from environment or defaults"""
        permissions_json = os.getenv('SSO_GROUP_PERMISSIONS', '')
        if permissions_json:
            try:
                return json.loads(permissions_json)
            except json.JSONDecodeError:
                pass
        return cls._DEFAULT_GROUP_PERMISSIONS

    # Alias for backwards compatibility
    GROUP_PERMISSIONS = property(lambda self: Config.get_group_permissions())

    @classmethod
    def get_permissions_for_groups(cls, groups):
        """Get all permissions for given groups"""
        group_permissions = cls.get_group_permissions()
        permissions = set()

        for group in groups:
            # 정확한 매칭
            if group in group_permissions:
                permissions.update(group_permissions[group])
            else:
                # CN= 형식에서 그룹명만 추출해서 매칭 시도
                # 예: "CN=HPC-Admins,OU=Groups,DC=company,DC=com" -> "HPC-Admins"
                if group.startswith('CN='):
                    cn = group.split(',')[0].replace('CN=', '')
                    if cn in group_permissions:
                        permissions.update(group_permissions[cn])

        return list(permissions)

    @classmethod
    def get_services_for_groups(cls, groups):
        """Get available services for given groups"""
        permissions = cls.get_permissions_for_groups(groups)
        services = []

        if 'dashboard' in permissions:
            services.append({
                'name': 'Smart Twin Flow',
                'url': cls.DASHBOARD_URL,
                'description': 'HPC Dashboard for DX Division',
                'icon': 'flow'
            })

        if 'cae' in permissions:
            services.append({
                'name': 'Smart Twin Cluster Extreme',
                'url': cls.CAE_URL,
                'description': 'MX 스마트폰 전각도 낙하 해석 자동화 시스템',
                'icon': 'cluster'
            })

        if 'vnc' in permissions:
            services.append({
                'name': 'Smart Twin Desktop',
                'url': cls.VNC_URL,
                'description': 'VNC Desktop',
                'icon': 'desktop'
            })

        if 'app' in permissions:
            services.append({
                'name': 'Smart Twin App',
                'url': cls.APP_URL,
                'description': 'Application Service with Remote Desktop',
                'icon': 'app'
            })

        return services
