"""
JWT Token Handler
Generates and validates JWT tokens for authenticated users
"""
import jwt
import redis
from datetime import datetime, timedelta
from config.config import Config


class JWTHandler:
    """JWT token generation and validation"""

    def __init__(self):
        """Initialize Redis connection"""
        self.redis_client = redis.Redis(
            host=Config.REDIS_HOST,
            port=Config.REDIS_PORT,
            db=Config.REDIS_DB,
            password=Config.REDIS_PASSWORD if Config.REDIS_PASSWORD else None,
            decode_responses=True
        )

    def create_token(self, user_info):
        """
        Create JWT token for authenticated user

        Args:
            user_info (dict): User information from SAML assertion
                {
                    'username': str,
                    'email': str,
                    'groups': list[str],
                    'attributes': dict
                }

        Returns:
            str: JWT token
        """
        groups = user_info.get('groups', [])
        permissions = Config.get_permissions_for_groups(groups)

        payload = {
            'sub': user_info['username'],
            'email': user_info.get('email', ''),
            'groups': groups,
            'permissions': permissions,
            'iat': datetime.utcnow(),
            'exp': datetime.utcnow() + timedelta(hours=Config.JWT_EXPIRATION_HOURS),
            'iss': 'auth-portal'
        }

        token = jwt.encode(payload, Config.JWT_SECRET_KEY, algorithm=Config.JWT_ALGORITHM)

        # Store token in Redis with expiration
        self._store_token(user_info['username'], token)

        return token

    def verify_token(self, token):
        """
        Verify JWT token

        Args:
            token (str): JWT token

        Returns:
            dict: Decoded payload if valid, None otherwise
        """
        try:
            payload = jwt.decode(
                token,
                Config.JWT_SECRET_KEY,
                algorithms=[Config.JWT_ALGORITHM]
            )

            # Check if token exists in Redis
            username = payload.get('sub')
            stored_token = self.redis_client.get(f"jwt:{username}")

            if stored_token != token:
                return None

            return payload

        except jwt.ExpiredSignatureError:
            return None
        except jwt.InvalidTokenError:
            return None

    def revoke_token(self, token):
        """
        Revoke JWT token by removing from Redis

        Args:
            token (str): JWT token to revoke

        Returns:
            bool: True if revoked successfully
        """
        try:
            payload = jwt.decode(
                token,
                Config.JWT_SECRET_KEY,
                algorithms=[Config.JWT_ALGORITHM],
                options={"verify_exp": False}  # Don't verify expiration for revocation
            )

            username = payload.get('sub')
            self.redis_client.delete(f"jwt:{username}")
            return True

        except jwt.InvalidTokenError:
            return False

    def _store_token(self, username, token):
        """
        Store JWT token in Redis

        Args:
            username (str): Username
            token (str): JWT token
        """
        expiration_seconds = Config.JWT_EXPIRATION_HOURS * 3600
        self.redis_client.setex(
            f"jwt:{username}",
            expiration_seconds,
            token
        )

    def get_user_token(self, username):
        """
        Get stored token for username

        Args:
            username (str): Username

        Returns:
            str: JWT token or None
        """
        return self.redis_client.get(f"jwt:{username}")
