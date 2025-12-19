"""
OIDC Authentication Handler
Handles OpenID Connect authentication flow

OIDC vs SAML Claim 요청 차이:
- SAML: AttributeConsumingService에서 명시적으로 속성 요청 가능
- OIDC: scope 파라미터로 요청하지만, 실제 클레임은 IdP가 결정
        claims 파라미터로 개별 클레임 요청 가능 (IdP 지원 필요)

이 핸들러는 OIDC claims 파라미터를 지원하여 SAML처럼 명시적 클레임 요청이 가능합니다.
"""
import json
import logging
from authlib.integrations.flask_client import OAuth
from authlib.jose import jwt as jose_jwt
from config.config import Config

logger = logging.getLogger(__name__)


class OIDCHandler:
    """OIDC authentication handler with claims request support"""

    _oauth = None
    _client = None
    _claims_request = None

    @classmethod
    def init_app(cls, app):
        """
        Initialize OIDC with Flask app

        Args:
            app: Flask application instance
        """
        if not Config.SSO_ENABLED or Config.SSO_TYPE != 'oidc':
            logger.info("OIDC not enabled, skipping initialization")
            return

        cls._oauth = OAuth(app)

        oidc_config = Config.get_oidc_config()

        # Build claims request (SAML처럼 명시적 클레임 요청)
        # https://openid.net/specs/openid-connect-core-1_0.html#ClaimsParameter
        cls._claims_request = cls._build_claims_request(oidc_config)

        client_kwargs = {
            'scope': ' '.join(oidc_config.get('scopes', ['openid', 'profile', 'email', 'groups']))
        }

        # Add claims parameter if configured
        if cls._claims_request:
            client_kwargs['claims'] = json.dumps(cls._claims_request)
            logger.info(f"OIDC claims request configured: {list(cls._claims_request.get('userinfo', {}).keys())}")

        # Register OIDC client
        cls._client = cls._oauth.register(
            name='oidc',
            client_id=oidc_config.get('client_id'),
            client_secret=oidc_config.get('client_secret'),
            server_metadata_url=f"{oidc_config.get('issuer')}/.well-known/openid-configuration",
            client_kwargs=client_kwargs
        )

        logger.info(f"OIDC initialized with issuer: {oidc_config.get('issuer')}")
        logger.info(f"OIDC scopes: {client_kwargs['scope']}")

    @classmethod
    def _build_claims_request(cls, oidc_config):
        """
        Build OIDC claims request parameter

        SAML에서는 AttributeConsumingService로 원하는 속성을 요청하지만,
        OIDC에서는 claims 파라미터로 동일한 기능을 수행합니다.

        Returns:
            dict: Claims request object or None if not configured
        """
        requested_claims = oidc_config.get('requested_claims', [])

        if not requested_claims:
            # 기본 클레임 (attribute_mapping에서 추출)
            attr_map = Config.get_attribute_mapping()
            requested_claims = [
                attr_map.get('username', 'preferred_username'),
                attr_map.get('email', 'email'),
                attr_map.get('groups', 'groups'),
                attr_map.get('display_name', 'name'),
                attr_map.get('department', 'department'),
            ]

        if not requested_claims:
            return None

        # Build claims request object
        # https://openid.net/specs/openid-connect-core-1_0.html#ClaimsParameter
        claims_request = {
            'userinfo': {},
            'id_token': {}
        }

        for claim in requested_claims:
            if claim:
                # essential=True means "I really need this claim"
                # null means "I want this claim if available"
                claims_request['userinfo'][claim] = {'essential': False}
                claims_request['id_token'][claim] = {'essential': False}

        # groups는 essential로 설정 (권한 매핑에 필수)
        groups_claim = Config.get_attribute_mapping().get('groups', 'groups')
        if groups_claim:
            claims_request['userinfo'][groups_claim] = {'essential': True}

        return claims_request

    @classmethod
    def get_authorize_redirect(cls, redirect_uri):
        """
        Get authorization redirect URL

        Args:
            redirect_uri: Callback URL after authentication

        Returns:
            Redirect response to IdP
        """
        if cls._client is None:
            raise RuntimeError("OIDC client not initialized")

        return cls._client.authorize_redirect(redirect_uri)

    @classmethod
    def authorize_access_token(cls):
        """
        Exchange authorization code for tokens

        Returns:
            dict: Token response containing access_token, id_token, etc.
        """
        if cls._client is None:
            raise RuntimeError("OIDC client not initialized")

        return cls._client.authorize_access_token()

    @classmethod
    def get_userinfo(cls, token):
        """
        Get user information from userinfo endpoint

        Args:
            token: Token response from authorize_access_token

        Returns:
            dict: User information
        """
        if cls._client is None:
            raise RuntimeError("OIDC client not initialized")

        # Try to get userinfo from token first (if id_token contains claims)
        if 'userinfo' in token:
            return token['userinfo']

        # Otherwise fetch from userinfo endpoint
        return cls._client.userinfo(token=token)

    @classmethod
    def parse_id_token(cls, token):
        """
        Parse and validate ID token

        Args:
            token: Token response containing id_token

        Returns:
            dict: Decoded ID token claims
        """
        if 'id_token' not in token:
            return None

        # The id_token is already validated by authlib
        # Just decode it to get claims
        id_token = token.get('id_token')

        # authlib stores parsed userinfo
        if 'userinfo' in token:
            return token['userinfo']

        return None

    @classmethod
    def extract_user_info(cls, token_response, userinfo=None):
        """
        Extract user information from OIDC response

        Args:
            token_response: Token response from authorize_access_token
            userinfo: Optional userinfo from userinfo endpoint

        Returns:
            dict: User information
                {
                    'username': str,
                    'email': str,
                    'groups': list[str],
                    'attributes': dict
                }
        """
        # Get userinfo from token or separate call
        info = userinfo or token_response.get('userinfo', {})

        # Get attribute mapping from config
        attr_map = Config.SSO_ATTRIBUTE_MAPPING

        # Extract username
        username_attr = attr_map.get('username', 'preferred_username')
        username = info.get(username_attr) or info.get('sub', '')

        # Extract email
        email_attr = attr_map.get('email', 'email')
        email = info.get(email_attr, '')

        # Extract groups
        groups_attr = attr_map.get('groups', 'groups')
        groups = info.get(groups_attr, [])

        # Handle string groups (comma-separated)
        if isinstance(groups, str):
            groups = [g.strip() for g in groups.split(',')]

        # Extract optional attributes
        display_name_attr = attr_map.get('display_name', 'name')
        display_name = info.get(display_name_attr, '')

        department_attr = attr_map.get('department', 'department')
        department = info.get(department_attr, '')

        user_info = {
            'username': username,
            'email': email,
            'groups': groups,
            'display_name': display_name,
            'department': department,
            'attributes': info
        }

        logger.info(f"OIDC user info extracted: username={username}, groups={groups}")

        return user_info

    @classmethod
    def logout_url(cls, post_logout_redirect_uri=None):
        """
        Get logout URL for OIDC provider

        Args:
            post_logout_redirect_uri: URL to redirect after logout

        Returns:
            str: Logout URL or None if not available
        """
        if cls._client is None:
            return None

        try:
            # Get end_session_endpoint from metadata
            metadata = cls._client.load_server_metadata()
            end_session_endpoint = metadata.get('end_session_endpoint')

            if end_session_endpoint and post_logout_redirect_uri:
                return f"{end_session_endpoint}?post_logout_redirect_uri={post_logout_redirect_uri}"

            return end_session_endpoint
        except Exception as e:
            logger.warning(f"Could not get logout URL: {e}")
            return None
