"""
Common utilities for Dashboard services

Provides unified session management and Redis configuration
"""

from .session_manager import RedisSessionManager
from .config import (
    get_redis_client,
    get_redis_pool,
    check_redis_health,
    close_redis_connection,
    DEFAULT_SESSION_TTL,
    MAX_SESSION_TTL,
    REDIS_HOST,
    REDIS_PORT,
)

__all__ = [
    'RedisSessionManager',
    'get_redis_client',
    'get_redis_pool',
    'check_redis_health',
    'close_redis_connection',
    'DEFAULT_SESSION_TTL',
    'MAX_SESSION_TTL',
    'REDIS_HOST',
    'REDIS_PORT',
]

__version__ = '1.0.0'
