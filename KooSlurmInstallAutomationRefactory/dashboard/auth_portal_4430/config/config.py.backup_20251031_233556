"""
Auth Portal Configuration
"""
import os
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

    # SAML
    SAML_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'saml')
    SAML_IDP_METADATA_URL = os.getenv('SAML_IDP_METADATA_URL', 'http://localhost:7000/metadata')
    SAML_SP_ENTITY_ID = os.getenv('SAML_SP_ENTITY_ID', 'auth-portal')
    SAML_ACS_URL = os.getenv('SAML_ACS_URL', 'http://localhost:4430/auth/saml/acs')
    SAML_SLS_URL = os.getenv('SAML_SLS_URL', 'http://localhost:4430/auth/saml/sls')

    # Service URLs - Nginx reverse proxy paths
    DASHBOARD_URL = os.getenv('DASHBOARD_URL', '/dashboard')
    CAE_URL = os.getenv('CAE_URL', '/cae')
    VNC_URL = os.getenv('VNC_URL', '/vnc')
    APP_URL = os.getenv('APP_URL', '/app')

    # Server
    HOST = os.getenv('HOST', '0.0.0.0')
    PORT = int(os.getenv('PORT', '4430'))

    # Group-based permissions
    GROUP_PERMISSIONS = {
        'HPC-Admins': ['dashboard', 'cae', 'vnc', 'app', 'admin'],
        'DX-Users': ['dashboard', 'vnc', 'app'],
        'CAEG-Users': ['dashboard', 'cae', 'vnc', 'app'],
    }

    @classmethod
    def get_permissions_for_groups(cls, groups):
        """Get all permissions for given groups"""
        permissions = set()
        for group in groups:
            if group in cls.GROUP_PERMISSIONS:
                permissions.update(cls.GROUP_PERMISSIONS[group])
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
