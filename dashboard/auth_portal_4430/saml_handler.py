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

        # IdP 설정: env(YAML→generate_sso_env) 우선, 없으면 dev 기본값(localhost:7000).
        idp_entity_id = Config.SAML_IDP_ENTITY_ID or 'http://localhost:7000/metadata'
        idp_sso_url = Config.SAML_IDP_SSO_URL or 'http://localhost:7000/saml/sso'
        idp_slo_url = Config.SAML_IDP_SLO_URL or 'http://localhost:7000/saml/slo'

        # IdP 서명검증용 인증서: 직접 값(SAML_IDP_CERTIFICATE) 또는 파일 경로에서 로드.
        # 인증서가 있어야 assertion 서명 검증이 가능하다(없으면 위조 차단 불가).
        idp_cert = Config.SAML_IDP_CERTIFICATE
        if not idp_cert and Config.SAML_IDP_CERTIFICATE_FILE:
            try:
                with open(Config.SAML_IDP_CERTIFICATE_FILE, 'r') as f:
                    idp_cert = f.read()
            except OSError as e:
                print(f"[saml] IdP certificate file read failed: {e}")
                idp_cert = ''

        settings = {
            'strict': Config.SAML_STRICT,
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
                'entityId': idp_entity_id,
                'singleSignOnService': {
                    'url': idp_sso_url,
                    'binding': 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
                },
                'singleLogoutService': {
                    'url': idp_slo_url,
                    'binding': 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
                },
                'x509cert': idp_cert
            },
            # 보안: IdP 인증서가 설정돼 있으면 assertion 서명 검증을 강제(위조 차단).
            # 인증서 미설정(dev) 시엔 서명요구를 끄되 strict(조건/타임스탬프/replay) 는 유지.
            'security': {
                'wantAssertionsSigned': bool(idp_cert),
                'wantMessagesSigned': False,
                'wantNameId': False,
                'requestedAuthnContext': False,
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

        # 시스템 명령어 절대 경로 (systemd 환경에서 PATH 제한)
        OPENSSL = '/usr/bin/openssl'

        os.makedirs(cert_path, exist_ok=True)

        sp_key_file = os.path.join(cert_path, 'sp-key.pem')
        sp_cert_file = os.path.join(cert_path, 'sp-cert.pem')

        # Generate private key
        subprocess.run([
            OPENSSL, 'req', '-new', '-x509', '-days', '3650',
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
        # 속성 매핑(설정 기준) + IdP 변형 폴백. OIDC 핸들러와 동일하게 Config 매핑을 따른다.
        attr_map = Config.get_attribute_mapping()

        def _first(*names):
            """주어진 속성명들 중 처음 값이 있는 것을 반환(리스트면 첫 원소)."""
            for n in names:
                if not n:
                    continue
                v = saml_attributes.get(n)
                if v:
                    return v[0] if isinstance(v, list) else v
            return ''

        # username: 매핑값 우선, 그 외 흔한 IdP 속성명 폴백(uid/userName/User.Username)
        username = _first(attr_map.get('username', 'uid'), 'uid', 'userName', 'User.Username')
        email = _first(attr_map.get('email', 'email'), 'email', 'User.email')
        display_name = _first(attr_map.get('display_name', 'displayName'), 'displayName')
        department = _first(attr_map.get('department', 'department'), 'department')

        # groups: 여러 값이라 리스트 유지(매핑 속성명 우선, groups/Group 폴백)
        groups_attr = attr_map.get('groups', 'groups')
        groups = saml_attributes.get(groups_attr) or saml_attributes.get('groups') or saml_attributes.get('Group') or []
        if isinstance(groups, str):
            groups = [groups]

        user_info = {
            'username': username,
            'email': email,
            'groups': groups,
            'display_name': display_name,
            'department': department,
            'attributes': saml_attributes
        }

        return user_info
