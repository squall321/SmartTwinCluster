"""
Redis Caching Decorator for Backend API (Enhanced Version)
개선된 Redis 캐싱 데코레이터 - 환경 변수 지원, 연결 풀, 에러 핸들링 강화
"""

import functools
import json
import hashlib
import os
import redis
from typing import Any, Callable, Optional
from flask import request, has_request_context
from redis.connection import ConnectionPool

# ==================== 환경 변수 설정 ====================
REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
REDIS_DB = int(os.getenv('REDIS_DB', 0))
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', None)
REDIS_SOCKET_TIMEOUT = int(os.getenv('REDIS_SOCKET_TIMEOUT', 2))
REDIS_SOCKET_CONNECT_TIMEOUT = int(os.getenv('REDIS_SOCKET_CONNECT_TIMEOUT', 2))
CACHE_ENABLED = os.getenv('CACHE_ENABLED', 'true').lower() == 'true'

# ==================== Connection Pool ====================
# 연결 풀을 사용하여 성능 향상 및 연결 재사용
redis_pool = None
redis_client = None
REDIS_AVAILABLE = False

def initialize_redis():
    """Redis 연결 초기화 (앱 시작 시 한 번만 실행)"""
    global redis_pool, redis_client, REDIS_AVAILABLE

    if not CACHE_ENABLED:
        print("[Cache] Caching is disabled via CACHE_ENABLED=false")
        return

    try:
        redis_pool = ConnectionPool(
            host=REDIS_HOST,
            port=REDIS_PORT,
            db=REDIS_DB,
            password=REDIS_PASSWORD,
            decode_responses=True,
            socket_connect_timeout=REDIS_SOCKET_CONNECT_TIMEOUT,
            socket_timeout=REDIS_SOCKET_TIMEOUT,
            max_connections=50  # 최대 연결 수
        )

        redis_client = redis.Redis(connection_pool=redis_pool)

        # 연결 테스트
        redis_client.ping()
        REDIS_AVAILABLE = True
        print(f"[Cache] Redis connected: {REDIS_HOST}:{REDIS_PORT} (DB: {REDIS_DB})")
        print(f"[Cache] Connection pool initialized (max: 50)")

    except (redis.ConnectionError, redis.TimeoutError) as e:
        redis_client = None
        redis_pool = None
        REDIS_AVAILABLE = False
        print(f"[Cache] Redis not available: {e}")
        print(f"[Cache] Falling back to no-cache mode")

# 초기화 (모듈 import 시 자동 실행)
initialize_redis()


def cache(
    ttl: int = 60,
    key_prefix: str = 'api',
    include_user: bool = False,
    include_args: bool = True,
    include_kwargs: bool = True,
    exclude_params: list = None
):
    """
    Redis 캐싱 데코레이터 (Enhanced)

    Args:
        ttl: Time-to-live (초)
        key_prefix: 캐시 키 접두사
        include_user: 사용자 정보를 캐시 키에 포함 (사용자별 캐싱)
        include_args: 함수 인자를 캐시 키에 포함
        include_kwargs: 함수 키워드 인자를 캐시 키에 포함
        exclude_params: 캐시 키에서 제외할 파라미터 리스트 (예: ['timestamp'])

    Example:
        @cache(ttl=5, key_prefix='slurm', include_user=False)
        def get_node_status():
            return sinfo_command()

        @cache(ttl=60, key_prefix='user', include_user=True, exclude_params=['timestamp'])
        def get_user_data(user_id, timestamp=None):
            return db.query(...)
    """
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            # 캐싱 비활성화 조건
            if not CACHE_ENABLED or not REDIS_AVAILABLE or redis_client is None:
                return func(*args, **kwargs)

            # exclude_params 처리
            filtered_kwargs = kwargs.copy()
            if exclude_params:
                for param in exclude_params:
                    filtered_kwargs.pop(param, None)

            # 캐시 키 생성
            cache_key = _generate_cache_key(
                func=func,
                args=args if include_args else (),
                kwargs=filtered_kwargs if include_kwargs else {},
                key_prefix=key_prefix,
                include_user=include_user
            )

            try:
                # 캐시 확인
                cached_data = redis_client.get(cache_key)
                if cached_data:
                    try:
                        result = json.loads(cached_data)
                        print(f"[Cache HIT] {cache_key} (TTL: {ttl}s)")
                        return result
                    except json.JSONDecodeError as e:
                        print(f"[Cache] Invalid JSON in cache: {cache_key}, error: {e}")
                        redis_client.delete(cache_key)

                # 캐시 미스 - 원본 함수 실행
                print(f"[Cache MISS] {cache_key}")
                result = func(*args, **kwargs)

                # 결과 캐싱 (None도 캐싱 가능)
                try:
                    redis_client.setex(
                        cache_key,
                        ttl,
                        json.dumps(result, ensure_ascii=False, default=str)
                    )
                    print(f"[Cache SET] {cache_key} (TTL: {ttl}s)")
                except (TypeError, ValueError) as e:
                    print(f"[Cache] Cannot serialize result for {cache_key}: {e}")

                return result

            except redis.RedisError as e:
                print(f"[Cache ERROR] Redis error for {cache_key}: {e}")
                # Redis 오류 시 원본 함수 실행
                return func(*args, **kwargs)

        return wrapper
    return decorator


def cache_invalidate(key_pattern: str) -> int:
    """
    캐시 무효화

    Args:
        key_pattern: 삭제할 캐시 키 패턴 (예: "slurm:*", "user:get_permissions:*")

    Returns:
        삭제된 키 개수

    Example:
        # 특정 사용자 캐시 무효화
        cache_invalidate("user:get_user_data:john:*")

        # 모든 Slurm 관련 캐시 무효화
        cache_invalidate("slurm:*")
    """
    if not REDIS_AVAILABLE or redis_client is None:
        print("[Cache] Redis not available, cannot invalidate cache")
        return 0

    try:
        keys = redis_client.keys(key_pattern)
        if keys:
            count = redis_client.delete(*keys)
            print(f"[Cache] Invalidated {count} keys matching '{key_pattern}'")
            return count
        else:
            print(f"[Cache] No keys found matching '{key_pattern}'")
        return 0
    except redis.RedisError as e:
        print(f"[Cache ERROR] Failed to invalidate '{key_pattern}': {e}")
        return 0


def cache_invalidate_by_prefix(prefix: str) -> int:
    """
    특정 prefix의 모든 캐시 무효화

    Args:
        prefix: 키 prefix (예: "slurm", "user")

    Returns:
        삭제된 키 개수
    """
    return cache_invalidate(f"{prefix}:*")


def _generate_cache_key(
    func: Callable,
    args: tuple,
    kwargs: dict,
    key_prefix: str,
    include_user: bool
) -> str:
    """캐시 키 생성 (내부 함수)"""
    # 기본 키: prefix:function_name
    parts = [key_prefix, func.__name__]

    # 사용자 정보 추가
    if include_user and has_request_context():
        username = request.headers.get('X-Username', 'anonymous')
        parts.append(username)

    # 인자 해시 추가
    if args or kwargs:
        # 인자를 JSON으로 직렬화 후 해시
        args_str = json.dumps({
            'args': args,
            'kwargs': sorted(kwargs.items())  # dict를 정렬하여 일관성 유지
        }, sort_keys=True, default=str)

        args_hash = hashlib.md5(args_str.encode()).hexdigest()[:12]  # 8 → 12 (충돌 감소)
        parts.append(args_hash)

    return ':'.join(parts)


def get_cache_stats() -> dict:
    """
    캐시 통계 조회 (향상된 버전)

    Returns:
        dict: 캐시 통계 정보
    """
    if not REDIS_AVAILABLE or redis_client is None:
        return {
            'available': False,
            'enabled': CACHE_ENABLED
        }

    try:
        info_stats = redis_client.info('stats')
        info_memory = redis_client.info('memory')
        info_clients = redis_client.info('clients')

        hits = info_stats.get('keyspace_hits', 0)
        misses = info_stats.get('keyspace_misses', 0)

        return {
            'available': True,
            'enabled': CACHE_ENABLED,
            'host': REDIS_HOST,
            'port': REDIS_PORT,
            'db': REDIS_DB,
            'total_commands_processed': info_stats.get('total_commands_processed', 0),
            'keyspace_hits': hits,
            'keyspace_misses': misses,
            'hit_rate': _calculate_hit_rate(info_stats),
            'used_memory_human': info_memory.get('used_memory_human', 'N/A'),
            'used_memory_peak_human': info_memory.get('used_memory_peak_human', 'N/A'),
            'connected_clients': info_clients.get('connected_clients', 0),
            'total_keys': _count_total_keys()
        }
    except redis.RedisError as e:
        return {
            'available': False,
            'enabled': CACHE_ENABLED,
            'error': str(e)
        }


def _calculate_hit_rate(info: dict) -> float:
    """캐시 적중률 계산"""
    hits = info.get('keyspace_hits', 0)
    misses = info.get('keyspace_misses', 0)
    total = hits + misses

    if total == 0:
        return 0.0

    return round((hits / total) * 100, 2)


def _count_total_keys() -> int:
    """Redis 내 총 키 개수"""
    try:
        return redis_client.dbsize()
    except:
        return 0


def clear_all_cache() -> bool:
    """
    모든 캐시 삭제 (주의: 현재 DB의 모든 키 삭제)

    Returns:
        bool: 성공 여부
    """
    if not REDIS_AVAILABLE or redis_client is None:
        return False

    try:
        redis_client.flushdb()
        print("[Cache] All cache cleared (FLUSHDB)")
        return True
    except redis.RedisError as e:
        print(f"[Cache ERROR] Failed to clear all cache: {e}")
        return False


# ==================== Flask 통합 (선택적) ====================

def register_cache_routes(app):
    """
    Flask app에 캐시 관련 API 엔드포인트 등록

    Usage:
        from utils.cache_decorator_v2 import register_cache_routes
        register_cache_routes(app)
    """
    @app.route('/api/cache/stats', methods=['GET'])
    def cache_stats_endpoint():
        """캐시 통계 조회"""
        return get_cache_stats()

    @app.route('/api/cache/clear', methods=['POST'])
    def cache_clear_endpoint():
        """모든 캐시 삭제 (관리자 전용)"""
        # TODO: 권한 체크 필요
        success = clear_all_cache()
        return {'success': success}

    @app.route('/api/cache/invalidate/<prefix>', methods=['POST'])
    def cache_invalidate_endpoint(prefix):
        """특정 prefix 캐시 무효화"""
        # TODO: 권한 체크 필요
        count = cache_invalidate_by_prefix(prefix)
        return {'invalidated': count}


# ==================== 사용 예시 ====================

if __name__ == '__main__':
    # 환경 변수 설정 예시
    # export REDIS_HOST=localhost
    # export REDIS_PORT=6379
    # export CACHE_ENABLED=true

    # 테스트 함수
    @cache(ttl=5, key_prefix='test')
    def expensive_operation(n: int) -> dict:
        """비용이 큰 연산 시뮬레이션"""
        import time
        time.sleep(1)
        return {'result': n * 2, 'computed': True}

    # 첫 호출 - 캐시 미스 (1초 소요)
    print("\n=== First call ===")
    result1 = expensive_operation(10)
    print(f"Result: {result1}\n")

    # 두 번째 호출 - 캐시 히트 (즉시 반환)
    print("=== Second call (cached) ===")
    result2 = expensive_operation(10)
    print(f"Result: {result2}\n")

    # 캐시 통계
    print("=== Cache stats ===")
    stats = get_cache_stats()
    for key, value in stats.items():
        print(f"  {key}: {value}")

    # 캐시 무효화
    print("\n=== Invalidating cache ===")
    cache_invalidate("test:*")
