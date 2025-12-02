"""
SAML Authentication Handler
Handles SAML 2.0 SSO authentication flow
"""
import os
from onelogin.saml2.auth import OneLogin_Saml2_Auth
from onelogin.saml2.utils import OneLogin_Saml2_Utils
from config.config import Config


class SAMLHandler:
    """SAML authentication handler"""

    @staticmethod
    def init_saml_auth(request):
        """
        Initialize SAML authentication

        Args:
            request: Flask request object

        Returns:
            OneLogin_Saml2_Auth: SAML Auth object
        """
        saml_settings = SAMLHandler.get_saml_settings()

        # Prepare Flask request data for python3-saml
        request_data = SAMLHandler.prepare_flask_request(request)

        auth = OneLogin_Saml2_Auth(request_data, saml_settings)
        return auth

    @staticmethod
    def prepare_flask_request(request):
        """
        Prepare Flask request for python3-saml

        Args:
            request: Flask request object

        Returns:
            dict: Request data formatted for python3-saml
        """
        url_data = {
            'https': 'on' if request.scheme == 'https' else 'off',
            'http_host': request.host,
            'server_port': str(request.environ.get('SERVER_PORT', 80)),
            'script_name': request.path,
            'get_data': request.args.copy(),
            'post_data': request.form.copy()
        }

        # Handle reverse proxy headers
        if 'X-Forwarded-For' in request.headers:
            url_data['http_x_forwarded_for'] = request.headers['X-Forwarded-For']
        if 'X-Forwarded-Proto' in request.headers:
            url_data['https'] = 'on' if request.headers['X-Forwarded-Proto'] == 'https' else 'off'
        if 'X-Forwarded-Host' in request.headers:
            url_data['http_host'] = request.headers['X-Forwarded-Host']

        return url_data

    @staticmethod
    def get_saml_settings():
        """
        Get SAML SP settings

        Returns:
            dict: SAML settings
        """
        saml_path = Config.SAML_PATH
        cert_path = os.path.join(saml_path, 'certs')
        metadata_path = os.path.join(saml_path, 'metadata')

        # Check if SP certificates exist, if not create them
        sp_cert_file = os.path.join(cert_path, 'sp-cert.pem')
        sp_key_file = os.path.join(cert_path, 'sp-key.pem')

        if not os.path.exists(sp_cert_file) or not os.path.exists(sp_key_file):
            SAMLHandler._generate_sp_certificates(cert_path)

        # Read SP certificates
        with open(sp_cert_file, 'r') as f:
            sp_cert = f.read()
        with open(sp_key_file, 'r') as f:
            sp_key = f.read()

        # Read IdP metadata (we'll handle this dynamically)
        idp_metadata_url = Config.SAML_IDP_METADATA_URL

        settings = {
            'strict': False,
            'debug': Config.DEBUG,
            'sp': {
                'entityId': Config.SAML_SP_ENTITY_ID,
                'assertionConsumerService': {
                    'url': Config.SAML_ACS_URL,
                    'binding': 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST'
                },
                'singleLogoutService': {
                    'url': Config.SAML_SLS_URL,
                    'binding': 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
                },
                'NameIDFormat': 'urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified',
                'x509cert': sp_cert,
                'privateKey': sp_key
            },
            'idp': {
                'entityId': 'http://localhost:7000/metadata',
                'singleSignOnService': {
                    'url': 'http://localhost:7000/saml/sso',
                    'binding': 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
                },
                'singleLogoutService': {
                    'url': 'http://localhost:7000/saml/slo',
                    'binding': 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
                },
                'x509cert': ''  # Will be filled from IdP metadata
            }
        }

        return settings

    @staticmethod
    def _generate_sp_certificates(cert_path):
        """
        Generate SP certificates if they don't exist

        Args:
            cert_path (str): Path to certificates directory
        """
        import subprocess

        os.makedirs(cert_path, exist_ok=True)

        sp_key_file = os.path.join(cert_path, 'sp-key.pem')
        sp_cert_file = os.path.join(cert_path, 'sp-cert.pem')

        # Generate private key
        subprocess.run([
            'openssl', 'req', '-new', '-x509', '-days', '3650',
            '-keyout', sp_key_file, '-out', sp_cert_file,
            '-nodes',
            '-subj', '/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/CN=auth-portal'
        ], check=True)

        print(f"Generated SP certificates: {sp_cert_file}, {sp_key_file}")

    @staticmethod
    def extract_user_info(saml_attributes):
        """
        Extract user information from SAML attributes

        Args:
            saml_attributes (dict): SAML attributes

        Returns:
            dict: User information
                {
                    'username': str,
                    'email': str,
                    'groups': list[str],
                    'attributes': dict
                }
        """
        # Extract username (from NameID or uid attribute)
        username = saml_attributes.get('uid', [''])[0] or saml_attributes.get('User.Username', [''])[0]

        # Extract email
        email = saml_attributes.get('email', [''])[0] or saml_attributes.get('User.email', [''])[0]

        # Extract groups
        groups = saml_attributes.get('groups', []) or saml_attributes.get('Group', [])
        if isinstance(groups, str):
            groups = [groups]

        user_info = {
            'username': username,
            'email': email,
            'groups': groups,
            'attributes': saml_attributes
        }

        return user_info
