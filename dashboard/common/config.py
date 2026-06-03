"""
Redis Configuration for Dashboard Services

Centralized Redis configuration for all dashboard services.
"""

import os
import redis
from typing import Optional
from dotenv import load_dotenv

# Load environment variables.
# 인자 없는 load_dotenv() 는 CWD 의 .env 만 봐서 REDIS_PASSWORD 를 못 읽고
# NOAUTH 로 Redis 연결 실패하는 문제가 있었음.
_DASHBOARD_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # .../dashboard
_ENV_CANDIDATES = [
    os.path.join(_DASHBOARD_DIR, n, '.env')
    for n in ('backend_5010', 'auth_portal_4430', 'common')
]
for _envp in _ENV_CANDIDATES:
    if os.path.exists(_envp):
        load_dotenv(_envp, override=False)
load_dotenv(override=False)  # CWD 의 .env 도

# .env 파일에서 KEY 값을 직접 파싱 (systemd 가 빈 환경변수를 주입하면
# load_dotenv(override=False) 가 못 덮어쓰므로, 환경변수가 비어있으면 파일에서 직접 읽음)
def _env_or_file(key, default=None):
    val = os.getenv(key)
    if val:  # 비어있지 않으면 그대로
        return val
    for _envp in _ENV_CANDIDATES:
        if not os.path.exists(_envp):
            continue
        try:
            for line in open(_envp):
                line = line.strip()
                if line.startswith(f"{key}=") and not line.startswith("#"):
                    v = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if v:
                        return v
        except Exception:
            pass
    return default

# Redis connection settings
REDIS_HOST = _env_or_file('REDIS_HOST', 'localhost')
REDIS_PORT = int(_env_or_file('REDIS_PORT', 6379))
REDIS_PASSWORD = _env_or_file('REDIS_PASSWORD', None)
REDIS_DB = int(_env_or_file('REDIS_DB', 0))

# Sentinel(HA) 설정 — REDIS_SENTINEL_HOSTS 가 있으면 Sentinel 모드, 없으면 단일 Redis(하위호환).
# 형식: "host1:26379,host2:26379,host3:26379" (포트 생략 시 26379)
REDIS_SENTINEL_HOSTS = _env_or_file('REDIS_SENTINEL_HOSTS', None)
REDIS_MASTER_NAME = _env_or_file('REDIS_MASTER_NAME', 'mymaster')


def _parse_sentinel_hosts(raw):
    """'h1:26379,h2,h3:26379' → [(h1,26379),(h2,26379),(h3,26379)]"""
    out = []
    for h in (raw or '').split(','):
        h = h.strip()
        if not h:
            continue
        if ':' in h:
            host, port = h.rsplit(':', 1)
            out.append((host, int(port)))
        else:
            out.append((h, 26379))
    return out

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
        if REDIS_SENTINEL_HOSTS:
            # Sentinel(HA) 모드: master_for() 는 단일 master 연결을 주므로
            # 기존 단일키/멀티키 연산이 그대로 동작하고 failover 시 자동 재해석된다.
            from redis.sentinel import Sentinel
            sentinel = Sentinel(
                _parse_sentinel_hosts(REDIS_SENTINEL_HOSTS),
                sentinel_kwargs={'password': REDIS_PASSWORD} if REDIS_PASSWORD else {},
                password=REDIS_PASSWORD or None,
                socket_timeout=REDIS_SOCKET_TIMEOUT,
                socket_connect_timeout=REDIS_SOCKET_CONNECT_TIMEOUT,
            )
            _redis_client = sentinel.master_for(
                REDIS_MASTER_NAME, db=REDIS_DB,
                decode_responses=True, password=REDIS_PASSWORD or None,
            )
        else:
            pool = get_redis_pool()
            _redis_client = redis.Redis(connection_pool=pool)

        # Test connection
        try:
            _redis_client.ping()
        except redis.ConnectionError as e:
            _target = (f"sentinel {REDIS_SENTINEL_HOSTS} (master={REDIS_MASTER_NAME})"
                       if REDIS_SENTINEL_HOSTS else f"{REDIS_HOST}:{REDIS_PORT}")
            raise redis.ConnectionError(
                f"Failed to connect to Redis at {_target}. "
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
