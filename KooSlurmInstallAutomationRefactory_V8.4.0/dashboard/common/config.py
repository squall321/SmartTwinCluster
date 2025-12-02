"""
Redis Configuration for Dashboard Services

Centralized Redis configuration for all dashboard services.
"""

import os
import redis
from typing import Optional
from dotenv import load_dotenv

# Load environment variables from .env file (if exists)
load_dotenv()

# Redis connection settings
REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', None)
REDIS_DB = int(os.getenv('REDIS_DB', 0))

# Connection pool settings
REDIS_MAX_CONNECTIONS = int(os.getenv('REDIS_MAX_CONNECTIONS', 50))
REDIS_SOCKET_TIMEOUT = int(os.getenv('REDIS_SOCKET_TIMEOUT', 5))
REDIS_SOCKET_CONNECT_TIMEOUT = int(os.getenv('REDIS_SOCKET_CONNECT_TIMEOUT', 5))

# Session settings
DEFAULT_SESSION_TTL = int(os.getenv('DEFAULT_SESSION_TTL', 7200))  # 2 hours
MAX_SESSION_TTL = int(os.getenv('MAX_SESSION_TTL', 86400))  # 24 hours

# Redis connection pool (shared across all services)
_redis_pool: Optional[redis.ConnectionPool] = None
_redis_client: Optional[redis.Redis] = None


def get_redis_pool() -> redis.ConnectionPool:
    """
    Get or create Redis connection pool (singleton pattern)

    Returns:
        redis.ConnectionPool: Shared connection pool
    """
    global _redis_pool

    if _redis_pool is None:
        _redis_pool = redis.ConnectionPool(
            host=REDIS_HOST,
            port=REDIS_PORT,
            password=REDIS_PASSWORD,
            db=REDIS_DB,
            max_connections=REDIS_MAX_CONNECTIONS,
            socket_timeout=REDIS_SOCKET_TIMEOUT,
            socket_connect_timeout=REDIS_SOCKET_CONNECT_TIMEOUT,
            decode_responses=True  # Auto decode bytes to str
        )

    return _redis_pool


def get_redis_client() -> redis.Redis:
    """
    Get or create Redis client (singleton pattern)

    Returns:
        redis.Redis: Redis client instance

    Raises:
        redis.ConnectionError: If Redis is not available
    """
    global _redis_client

    if _redis_client is None:
        pool = get_redis_pool()
        _redis_client = redis.Redis(connection_pool=pool)

        # Test connection
        try:
            _redis_client.ping()
        except redis.ConnectionError as e:
            raise redis.ConnectionError(
                f"Failed to connect to Redis at {REDIS_HOST}:{REDIS_PORT}. "
                f"Make sure Redis is running and accessible. Error: {e}"
            )

    return _redis_client


def check_redis_health() -> tuple[bool, Optional[str]]:
    """
    Check Redis health status

    Returns:
        tuple: (is_healthy: bool, error_message: Optional[str])
    """
    try:
        client = get_redis_client()
        client.ping()
        return True, None
    except redis.ConnectionError as e:
        return False, str(e)
    except Exception as e:
        return False, f"Unexpected error: {e}"


def close_redis_connection():
    """
    Close Redis connection (cleanup)
    """
    global _redis_pool, _redis_client

    if _redis_client:
        _redis_client.close()
        _redis_client = None

    if _redis_pool:
        _redis_pool.disconnect()
        _redis_pool = None
