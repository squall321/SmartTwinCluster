"""
Unified Authentication Handler
Supports both SAML and OIDC authentication based on configuration
"""
import logging
from config.config import Config

logger = logging.getLogger(__name__)


class AuthHandler:
    """
    Unified authentication handler that delegates to SAML or OIDC handler
    based on configuration
    """

    _saml_handler = None
    _oidc_handler = None
    _initialized = False

    @classmethod
    def init_app(cls, app):
        """
        Initialize authentication handlers based on config

        Args:
            app: Flask application instance
        """
        if cls._initialized:
            return

        sso_type = Config.SSO_TYPE
        sso_enabled = Config.SSO_ENABLED

        logger.info(f"Initializing AuthHandler: SSO enabled={sso_enabled}, type={sso_type}")

        if not sso_enabled:
            logger.info("SSO disabled, using mock authentication")
            cls._initialized = True
            return

        if sso_type == 'saml':
            from saml_handler import SAMLHandler
            cls._saml_handler = SAMLHandler
            logger.info("SAML authentication handler initialized")

        elif sso_type == 'oidc':
            from oidc_handler import OIDCHandler
            OIDCHandler.init_app(app)
            cls._oidc_handler = OIDCHandler
            logger.info("OIDC authentication handler initialized")

        else:
            logger.warning(f"Unknown SSO type: {sso_type}, falling back to SAML")
            from saml_handler import SAMLHandler
            cls._saml_handler = SAMLHandler

        cls._initialized = True

    @classmethod
    def get_sso_type(cls):
        """
        Get current SSO type

        Returns:
            str: 'saml', 'oidc', or 'mock'
        """
        if not Config.SSO_ENABLED:
            return 'mock'
        return Config.SSO_TYPE

    @classmethod
    def is_saml(cls):
        """Check if using SAML authentication"""
        return Config.SSO_ENABLED and Config.SSO_TYPE == 'saml'

    @classmethod
    def is_oidc(cls):
        """Check if using OIDC authentication"""
        return Config.SSO_ENABLED and Config.SSO_TYPE == 'oidc'

    @classmethod
    def is_mock(cls):
        """Check if using mock authentication"""
        return not Config.SSO_ENABLED

    # =========================================================================
    # SAML Methods (delegated to SAMLHandler)
    # =========================================================================

    @classmethod
    def init_saml_auth(cls, request):
        """Initialize SAML auth (SAML only)"""
        if cls._saml_handler is None:
            raise RuntimeError("SAML handler not initialized")
        return cls._saml_handler.init_saml_auth(request)

    @classmethod
    def get_saml_settings(cls):
        """Get SAML settings (SAML only)"""
        if cls._saml_handler is None:
            raise RuntimeError("SAML handler not initialized")
        return cls._saml_handler.get_saml_settings()

    @classmethod
    def extract_saml_user_info(cls, saml_attributes):
        """Extract user info from SAML attributes"""
        if cls._saml_handler is None:
            raise RuntimeError("SAML handler not initialized")
        return cls._saml_handler.extract_user_info(saml_attributes)

    # =========================================================================
    # OIDC Methods (delegated to OIDCHandler)
    # =========================================================================

    @classmethod
    def get_oidc_authorize_redirect(cls, redirect_uri):
        """Get OIDC authorization redirect (OIDC only)"""
        if cls._oidc_handler is None:
            raise RuntimeError("OIDC handler not initialized")
        return cls._oidc_handler.get_authorize_redirect(redirect_uri)

    @classmethod
    def oidc_authorize_access_token(cls):
        """Exchange OIDC authorization code for tokens"""
        if cls._oidc_handler is None:
            raise RuntimeError("OIDC handler not initialized")
        return cls._oidc_handler.authorize_access_token()

    @classmethod
    def get_oidc_userinfo(cls, token):
        """Get user info from OIDC provider"""
        if cls._oidc_handler is None:
            raise RuntimeError("OIDC handler not initialized")
        return cls._oidc_handler.get_userinfo(token)

    @classmethod
    def extract_oidc_user_info(cls, token_response, userinfo=None):
        """Extract user info from OIDC response"""
        if cls._oidc_handler is None:
            raise RuntimeError("OIDC handler not initialized")
        return cls._oidc_handler.extract_user_info(token_response, userinfo)

    @classmethod
    def get_oidc_logout_url(cls, post_logout_redirect_uri=None):
        """Get OIDC logout URL"""
        if cls._oidc_handler is None:
            return None
        return cls._oidc_handler.logout_url(post_logout_redirect_uri)

    # =========================================================================
    # Common Methods
    # =========================================================================

    @classmethod
    def extract_user_info(cls, auth_response, sso_type=None):
        """
        Extract user information from authentication response

        Args:
            auth_response: Authentication response (SAML attributes or OIDC token)
            sso_type: Override SSO type (optional)

        Returns:
            dict: Normalized user information
        """
        sso_type = sso_type or cls.get_sso_type()

        if sso_type == 'saml':
            return cls.extract_saml_user_info(auth_response)
        elif sso_type == 'oidc':
            return cls.extract_oidc_user_info(auth_response)
        else:
            # Mock - auth_response is already user_info dict
            return auth_response

    @classmethod
    def get_login_url(cls):
        """
        Get login URL based on SSO type

        Returns:
            str: Login URL path
        """
        sso_type = cls.get_sso_type()

        if sso_type == 'saml':
            return '/auth/saml/login'
        elif sso_type == 'oidc':
            return '/auth/oidc/login'
        else:
            return '/auth/test/login'

    @classmethod
    def get_logout_url(cls):
        """
        Get logout URL based on SSO type

        Returns:
            str: Logout URL path
        """
        sso_type = cls.get_sso_type()

        if sso_type == 'saml':
            return '/auth/saml/sls'
        elif sso_type == 'oidc':
            return '/auth/oidc/logout'
        else:
            return '/auth/logout'

    @classmethod
    def get_auth_info(cls):
        """
        Get authentication configuration info

        Returns:
            dict: Authentication configuration
        """
        return {
            'sso_enabled': Config.SSO_ENABLED,
            'sso_type': cls.get_sso_type(),
            'login_url': cls.get_login_url(),
            'logout_url': cls.get_logout_url()
        }
