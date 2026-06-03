"""
JWT Token Handler
Generates and validates JWT tokens for authenticated users
"""
import jwt
import redis
import logging
from datetime import datetime, timedelta
from config.config import Config

logger = logging.getLogger(__name__)


class JWTHandler:
    """JWT token generation and validation"""

    def __init__(self):
        """Initialize Redis connection (lazy, with fallback)"""
        self._redis_client = None
        self._redis_available = None  # None = not checked, True/False = checked

    @property
    def redis_client(self):
        """Lazy Redis connection with fallback"""
        if self._redis_client is None:
            try:
                if Config.REDIS_SENTINEL_HOSTS:
                    # Sentinel(HA) 모드: master_for() 가 현재 master 연결을 주고 failover 시 자동 재해석.
                    from redis.sentinel import Sentinel
                    _hosts = [(h.rsplit(':', 1)[0], int(h.rsplit(':', 1)[1]) if ':' in h else 26379)
                              for h in Config.REDIS_SENTINEL_HOSTS.split(',') if h.strip()]
                    _pw = Config.REDIS_PASSWORD or None
                    _sentinel = Sentinel(
                        _hosts,
                        sentinel_kwargs={'password': _pw} if _pw else {},
                        password=_pw,
                        socket_connect_timeout=2, socket_timeout=2,
                    )
                    self._redis_client = _sentinel.master_for(
                        Config.REDIS_MASTER_NAME, db=Config.REDIS_DB,
                        decode_responses=True, password=_pw,
                    )
                else:
                    self._redis_client = redis.Redis(
                        host=Config.REDIS_HOST,
                        port=Config.REDIS_PORT,
                        db=Config.REDIS_DB,
                        password=Config.REDIS_PASSWORD if Config.REDIS_PASSWORD else None,
                        decode_responses=True,
                        socket_connect_timeout=2,
                        socket_timeout=2
                    )
                # Test connection
                self._redis_client.ping()
                self._redis_available = True
                logger.info("Redis connection established")
            except Exception as e:
                logger.warning(f"Redis connection failed: {e}. Running without token revocation support.")
                self._redis_available = False
                self._redis_client = None
        return self._redis_client

    @property
    def redis_available(self):
        """Check if Redis is available"""
        if self._redis_available is None:
            # Trigger lazy connection check
            _ = self.redis_client
        return self._redis_available

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

        # Store token in Redis with expiration (if available)
        if self.redis_available:
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

            # Check if token exists in Redis (if available)
            if self.redis_available:
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
        if not self.redis_available:
            logger.warning("Redis not available, token revocation skipped")
            return True  # Return True anyway since token is not stored

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
        if not self.redis_available:
            return None
        return self.redis_client.get(f"jwt:{username}")
