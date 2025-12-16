"""
Redis Caching Decorator for Backend API
성능 최적화를 위한 Redis 캐싱 데코레이터
"""

import functools
import json
import hashlib
import redis
from typing import Any, Callable, Optional
from flask import request, has_request_context

# Redis 클라이언트 초기화
try:
    redis_client = redis.Redis(
        host='localhost',
        port=6379,
        db=0,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2
    )
    # 연결 테스트
    redis_client.ping()
    REDIS_AVAILABLE = True
    print("[Cache] Redis connection established")
except (redis.ConnectionError, redis.TimeoutError) as e:
    redis_client = None
    REDIS_AVAILABLE = False
    print(f"[Cache] Redis not available: {e}")


def cache(
    ttl: int = 60,
    key_prefix: str = 'api',
    include_user: bool = False,
    include_args: bool = True,
    include_kwargs: bool = True
):
    """
    Redis 캐싱 데코레이터

    Args:
        ttl: Time-to-live (초)
        key_prefix: 캐시 키 접두사
        include_user: 사용자 정보를 캐시 키에 포함 (사용자별 캐싱)
        include_args: 함수 인자를 캐시 키에 포함
        include_kwargs: 함수 키워드 인자를 캐시 키에 포함

    Example:
        @cache(ttl=5, key_prefix='slurm', include_user=False)
        def get_node_status():
            return sinfo_command()

        @cache(ttl=60, key_prefix='user', include_user=True)
        def get_user_permissions(user_id):
            return db.query(...)
    """
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            # Redis 비활성화 시 원본 함수 실행
            if not REDIS_AVAILABLE or redis_client is None:
                return func(*args, **kwargs)

            # 캐시 키 생성
            cache_key = _generate_cache_key(
                func=func,
                args=args if include_args else (),
                kwargs=kwargs if include_kwargs else {},
                key_prefix=key_prefix,
                include_user=include_user
            )

            try:
                # 캐시 확인
                cached_data = redis_client.get(cache_key)
                if cached_data:
                    try:
                        result = json.loads(cached_data)
                        print(f"[Cache HIT] {cache_key}")
                        return result
                    except json.JSONDecodeError:
                        print(f"[Cache] Invalid JSON in cache: {cache_key}")
                        redis_client.delete(cache_key)

                # 캐시 미스 - 원본 함수 실행
                print(f"[Cache MISS] {cache_key}")
                result = func(*args, **kwargs)

                # 결과 캐싱
                try:
                    redis_client.setex(
                        cache_key,
                        ttl,
                        json.dumps(result, ensure_ascii=False, default=str)
                    )
                    print(f"[Cache SET] {cache_key} (TTL: {ttl}s)")
                except (TypeError, ValueError) as e:
                    print(f"[Cache] Cannot serialize result: {e}")

                return result

            except redis.RedisError as e:
                print(f"[Cache ERROR] {e}")
                # Redis 오류 시 원본 함수 실행
                return func(*args, **kwargs)

        return wrapper
    return decorator


def cache_invalidate(key_pattern: str):
    """
    캐시 무효화

    Args:
        key_pattern: 삭제할 캐시 키 패턴 (예: "slurm:*")

    Example:
        cache_invalidate("slurm:get_node_status:*")
    """
    if not REDIS_AVAILABLE or redis_client is None:
        return 0

    try:
        keys = redis_client.keys(key_pattern)
        if keys:
            count = redis_client.delete(*keys)
            print(f"[Cache] Invalidated {count} keys matching '{key_pattern}'")
            return count
        return 0
    except redis.RedisError as e:
        print(f"[Cache ERROR] Failed to invalidate: {e}")
        return 0


def _generate_cache_key(
    func: Callable,
    args: tuple,
    kwargs: dict,
    key_prefix: str,
    include_user: bool
) -> str:
    """캐시 키 생성"""
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

        args_hash = hashlib.md5(args_str.encode()).hexdigest()[:8]
        parts.append(args_hash)

    return ':'.join(parts)


def get_cache_stats() -> dict:
    """캐시 통계 조회"""
    if not REDIS_AVAILABLE or redis_client is None:
        return {'available': False}

    try:
        info = redis_client.info('stats')
        return {
            'available': True,
            'total_commands_processed': info.get('total_commands_processed', 0),
            'keyspace_hits': info.get('keyspace_hits', 0),
            'keyspace_misses': info.get('keyspace_misses', 0),
            'hit_rate': _calculate_hit_rate(info),
            'used_memory_human': redis_client.info('memory').get('used_memory_human', 'N/A')
        }
    except redis.RedisError as e:
        return {'available': False, 'error': str(e)}


def _calculate_hit_rate(info: dict) -> float:
    """캐시 적중률 계산"""
    hits = info.get('keyspace_hits', 0)
    misses = info.get('keyspace_misses', 0)
    total = hits + misses

    if total == 0:
        return 0.0

    return round((hits / total) * 100, 2)


# ==================== 사용 예시 ====================

if __name__ == '__main__':
    # 테스트 함수
    @cache(ttl=5, key_prefix='test')
    def expensive_operation(n: int) -> dict:
        """비용이 큰 연산 시뮬레이션"""
        import time
        time.sleep(1)
        return {'result': n * 2, 'computed': True}

    # 첫 호출 - 캐시 미스 (1초 소요)
    print("First call:")
    result1 = expensive_operation(10)
    print(f"Result: {result1}\n")

    # 두 번째 호출 - 캐시 히트 (즉시 반환)
    print("Second call (cached):")
    result2 = expensive_operation(10)
    print(f"Result: {result2}\n")

    # 다른 인자 - 캐시 미스 (1초 소요)
    print("Different argument:")
    result3 = expensive_operation(20)
    print(f"Result: {result3}\n")

    # 캐시 통계
    print("Cache stats:")
    print(get_cache_stats())

    # 캐시 무효화
    print("\nInvalidating cache...")
    cache_invalidate("test:*")
