"""
Auth Portal Backend - Main Application
Flask server for SSO authentication (SAML/OIDC) and JWT token issuance
"""
from flask import Flask, request, jsonify, redirect, session, url_for
from flask_cors import CORS
from config.config import Config
from auth_handler import AuthHandler
from jwt_handler import JWTHandler
import logging
import os

# Initialize Flask app
app = Flask(__name__)
app.config.from_object(Config)
app.secret_key = Config.SECRET_KEY

# Enable CORS
CORS(app, supports_credentials=True)

# Initialize handlers
jwt_handler = JWTHandler()
AuthHandler.init_app(app)

# Setup logging
logging.basicConfig(
    level=logging.DEBUG if Config.DEBUG else logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/auth_portal.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


# ============================================================================
# Health Check & Auth Info
# ============================================================================

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'auth-portal',
        'version': '2.0.0',
        'sso_type': AuthHandler.get_sso_type()
    }), 200


@app.route('/auth/info', methods=['GET'])
def auth_info():
    """Get authentication configuration info"""
    return jsonify(AuthHandler.get_auth_info()), 200


# ============================================================================
# SAML SSO Routes
# ============================================================================

@app.route('/auth/saml/login', methods=['GET'])
def saml_login():
    """
    Initiate SAML SSO login
    Redirects user to IdP for authentication
    """
    if not AuthHandler.is_saml():
        return jsonify({'error': 'SAML not enabled'}), 400

    try:
        from saml_handler import SAMLHandler
        auth = SAMLHandler.init_saml_auth(request)
        return redirect(auth.login())
    except Exception as e:
        logger.error(f"SAML login error: {str(e)}")
        return jsonify({'error': 'SAML login failed', 'message': str(e)}), 500


@app.route('/auth/saml/acs', methods=['POST'])
def saml_acs():
    """
    Assertion Consumer Service
    Receives SAML response from IdP after authentication
    """
    if not AuthHandler.is_saml():
        return jsonify({'error': 'SAML not enabled'}), 400

    try:
        from saml_handler import SAMLHandler
        auth = SAMLHandler.init_saml_auth(request)
        auth.process_response()

        errors = auth.get_errors()
        if errors:
            logger.error(f"SAML ACS errors: {errors}")
            return jsonify({
                'error': 'SAML authentication failed',
                'details': errors
            }), 401

        if not auth.is_authenticated():
            logger.warning("SAML authentication failed - not authenticated")
            return jsonify({'error': 'Authentication failed'}), 401

        # Extract user information from SAML assertion
        saml_attributes = auth.get_attributes()
        saml_nameid = auth.get_nameid()

        logger.info(f"SAML attributes received: {saml_attributes}")

        user_info = SAMLHandler.extract_user_info(saml_attributes)
        if not user_info['username']:
            user_info['username'] = saml_nameid

        logger.info(f"User authenticated: {user_info['username']}, groups: {user_info['groups']}")

        # Generate JWT token
        jwt_token = jwt_handler.create_token(user_info)

        # Store user info in session
        session['user_info'] = user_info
        session['jwt_token'] = jwt_token

        # Redirect to frontend with token
        frontend_url = f"http://localhost:4431/auth/callback"
        return redirect(f"{frontend_url}?token={jwt_token}")

    except Exception as e:
        logger.error(f"SAML ACS error: {str(e)}", exc_info=True)
        return jsonify({'error': 'SAML processing failed', 'message': str(e)}), 500


@app.route('/auth/saml/sls', methods=['GET'])
def saml_sls():
    """
    Single Logout Service
    Handles logout requests
    """
    if not AuthHandler.is_saml():
        return jsonify({'error': 'SAML not enabled'}), 400

    try:
        from saml_handler import SAMLHandler
        auth = SAMLHandler.init_saml_auth(request)

        # Get current JWT token and revoke it
        jwt_token = session.get('jwt_token')
        if jwt_token:
            jwt_handler.revoke_token(jwt_token)

        # Clear session
        session.clear()

        # Initiate SAML logout
        return redirect(auth.logout())

    except Exception as e:
        logger.error(f"SAML SLS error: {str(e)}")
        return jsonify({'error': 'Logout failed', 'message': str(e)}), 500


@app.route('/auth/saml/metadata', methods=['GET'])
def saml_metadata():
    """
    SP Metadata endpoint
    Returns SAML SP metadata XML
    """
    try:
        from saml_handler import SAMLHandler
        saml_settings = SAMLHandler.get_saml_settings()
        from onelogin.saml2.settings import OneLogin_Saml2_Settings

        settings_obj = OneLogin_Saml2_Settings(saml_settings)
        metadata = settings_obj.get_sp_metadata()

        errors = settings_obj.validate_metadata(metadata)
        if errors:
            logger.error(f"Metadata validation errors: {errors}")
            return jsonify({'error': 'Invalid metadata', 'details': errors}), 500

        return metadata, 200, {'Content-Type': 'application/xml'}

    except Exception as e:
        logger.error(f"Metadata generation error: {str(e)}")
        return jsonify({'error': 'Metadata generation failed', 'message': str(e)}), 500


# ============================================================================
# OIDC Routes
# ============================================================================

@app.route('/auth/oidc/login', methods=['GET'])
def oidc_login():
    """
    Initiate OIDC login
    Redirects user to IdP for authentication
    """
    if not AuthHandler.is_oidc():
        return jsonify({'error': 'OIDC not enabled'}), 400

    try:
        redirect_uri = url_for('oidc_callback', _external=True)
        return AuthHandler.get_oidc_authorize_redirect(redirect_uri)
    except Exception as e:
        logger.error(f"OIDC login error: {str(e)}")
        return jsonify({'error': 'OIDC login failed', 'message': str(e)}), 500


@app.route('/auth/oidc/callback', methods=['GET'])
def oidc_callback():
    """
    OIDC callback endpoint
    Receives authorization code and exchanges for tokens
    """
    if not AuthHandler.is_oidc():
        return jsonify({'error': 'OIDC not enabled'}), 400

    try:
        # Exchange authorization code for tokens
        token = AuthHandler.oidc_authorize_access_token()

        # Get user info
        userinfo = AuthHandler.get_oidc_userinfo(token)

        # Extract user information
        user_info = AuthHandler.extract_oidc_user_info(token, userinfo)

        logger.info(f"OIDC user authenticated: {user_info['username']}, groups: {user_info['groups']}")

        # Generate JWT token
        jwt_token = jwt_handler.create_token(user_info)

        # Store user info in session
        session['user_info'] = user_info
        session['jwt_token'] = jwt_token

        # Redirect to frontend with token
        frontend_url = f"http://localhost:4431/auth/callback"
        return redirect(f"{frontend_url}?token={jwt_token}")

    except Exception as e:
        logger.error(f"OIDC callback error: {str(e)}", exc_info=True)
        return jsonify({'error': 'OIDC authentication failed', 'message': str(e)}), 500


@app.route('/auth/oidc/logout', methods=['GET', 'POST'])
def oidc_logout():
    """
    OIDC logout endpoint
    """
    try:
        # Revoke JWT token
        jwt_token = session.get('jwt_token')
        if jwt_token:
            jwt_handler.revoke_token(jwt_token)

        # Clear session
        session.clear()

        # Get OIDC logout URL if available
        if AuthHandler.is_oidc():
            logout_url = AuthHandler.get_oidc_logout_url(
                post_logout_redirect_uri=url_for('health_check', _external=True)
            )
            if logout_url:
                return redirect(logout_url)

        return jsonify({'message': 'Logged out successfully'}), 200

    except Exception as e:
        logger.error(f"OIDC logout error: {str(e)}")
        return jsonify({'error': 'Logout failed', 'message': str(e)}), 500


# ============================================================================
# JWT Token Management
# ============================================================================

@app.route('/auth/verify', methods=['POST'])
def verify_token():
    """
    Verify JWT token
    Used by other services to validate user tokens
    """
    try:
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'No authorization header'}), 401

        token = auth_header.split(' ')[1]
        payload = jwt_handler.verify_token(token)

        if not payload:
            return jsonify({'error': 'Invalid or expired token'}), 401

        return jsonify({
            'valid': True,
            'user': payload
        }), 200

    except Exception as e:
        logger.error(f"Token verification error: {str(e)}")
        return jsonify({'error': 'Verification failed', 'message': str(e)}), 500


@app.route('/auth/refresh', methods=['POST'])
def refresh_token():
    """
    Refresh JWT token
    Issues new token with extended expiration
    """
    try:
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'No authorization header'}), 401

        old_token = auth_header.split(' ')[1]
        payload = jwt_handler.verify_token(old_token)

        if not payload:
            return jsonify({'error': 'Invalid or expired token'}), 401

        # Create new token with same user info
        user_info = {
            'username': payload['sub'],
            'email': payload['email'],
            'groups': payload['groups']
        }

        new_token = jwt_handler.create_token(user_info)

        return jsonify({
            'token': new_token
        }), 200

    except Exception as e:
        logger.error(f"Token refresh error: {str(e)}")
        return jsonify({'error': 'Refresh failed', 'message': str(e)}), 500


@app.route('/auth/logout', methods=['POST'])
def logout():
    """
    Logout endpoint
    Revokes JWT token and clears session
    """
    try:
        auth_header = request.headers.get('Authorization')
        if auth_header and auth_header.startswith('Bearer '):
            token = auth_header.split(' ')[1]
            jwt_handler.revoke_token(token)

        session.clear()

        return jsonify({'message': 'Logged out successfully'}), 200

    except Exception as e:
        logger.error(f"Logout error: {str(e)}")
        return jsonify({'error': 'Logout failed', 'message': str(e)}), 500


# ============================================================================
# User Info and Services
# ============================================================================

@app.route('/auth/user', methods=['GET'])
def get_user_info():
    """
    Get current user information
    Requires valid JWT token
    """
    try:
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'No authorization header'}), 401

        token = auth_header.split(' ')[1]
        payload = jwt_handler.verify_token(token)

        if not payload:
            return jsonify({'error': 'Invalid or expired token'}), 401

        return jsonify({
            'username': payload['sub'],
            'email': payload['email'],
            'groups': payload['groups'],
            'permissions': payload['permissions']
        }), 200

    except Exception as e:
        logger.error(f"Get user info error: {str(e)}")
        return jsonify({'error': 'Failed to get user info', 'message': str(e)}), 500


@app.route('/auth/services', methods=['GET'])
@app.route('/services', methods=['GET'])
def get_services():
    """
    Get available services for current user
    Based on user's group memberships
    """
    try:
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'No authorization header'}), 401

        token = auth_header.split(' ')[1]
        payload = jwt_handler.verify_token(token)

        if not payload:
            return jsonify({'error': 'Invalid or expired token'}), 401

        services = Config.get_services_for_groups(payload['groups'])

        return jsonify({
            'services': services
        }), 200

    except Exception as e:
        logger.error(f"Get services error: {str(e)}")
        return jsonify({'error': 'Failed to get services', 'message': str(e)}), 500


# ============================================================================
# Test/Debug Endpoints (for Mock authentication)
# ============================================================================

@app.route('/auth/test/login', methods=['POST'])
@app.route('/test/login', methods=['POST'])
def test_login():
    """
    Test login endpoint (bypasses SSO)
    Used for testing JWT flow without real IdP

    POST body: {
        "username": "test_user",
        "email": "test@example.com",
        "groups": ["HPC-Users", "GPU-Users"]
    }
    """
    # Only allow when SSO is disabled (mock mode)
    if Config.SSO_ENABLED:
        return jsonify({'error': 'Test login disabled when SSO is enabled'}), 403

    try:
        data = request.get_json()

        if not data or 'username' not in data:
            return jsonify({'error': 'Username required'}), 400

        user_info = {
            'username': data['username'],
            'email': data.get('email', f"{data['username']}@hpc.local"),
            'groups': data.get('groups', ['HPC-Users'])
        }

        # Generate JWT token
        jwt_token = jwt_handler.create_token(user_info)

        # Get available services
        services = Config.get_services_for_groups(user_info['groups'])

        logger.info(f"Test login: {user_info['username']}, groups: {user_info['groups']}")

        return jsonify({
            'success': True,
            'token': jwt_token,
            'user': user_info,
            'services': services
        }), 200

    except Exception as e:
        logger.error(f"Test login error: {str(e)}")
        return jsonify({'error': 'Test login failed', 'message': str(e)}), 500


# ============================================================================
# Main
# ============================================================================

if __name__ == '__main__':
    # Ensure log directory exists
    os.makedirs('logs', exist_ok=True)

    logger.info(f"Starting Auth Portal on {Config.HOST}:{Config.PORT}")
    logger.info(f"Debug mode: {Config.DEBUG}")
    logger.info(f"SSO enabled: {Config.SSO_ENABLED}")
    logger.info(f"SSO type: {Config.SSO_TYPE}")

    if Config.SSO_TYPE == 'saml':
        logger.info(f"SAML IdP: {Config.SAML_IDP_METADATA_URL}")
    elif Config.SSO_TYPE == 'oidc':
        logger.info(f"OIDC Issuer: {Config.OIDC_ISSUER}")

    app.run(
        host=Config.HOST,
        port=Config.PORT,
        debug=Config.DEBUG
    )
