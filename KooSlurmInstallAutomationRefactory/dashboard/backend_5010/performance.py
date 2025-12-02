"""
성능 최적화: Redis 캐싱 + 병렬 처리
"""

import redis
import json
import time
import hashlib
import os
from typing import Optional, Any, Callable, List, Dict
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import wraps
import logging

logger = logging.getLogger(__name__)

# Redis 연결 (없으면 None)
try:
    redis_client = redis.Redis(
        host=os.getenv('REDIS_HOST', 'localhost'),
        port=int(os.getenv('REDIS_PORT', 6379)),
        db=int(os.getenv('REDIS_DB', 0)),
        password=os.getenv('REDIS_PASSWORD', None),
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2
    )
    # 연결 테스트
    redis_client.ping()
    REDIS_AVAILABLE = True
    logger.info("✅ Redis connected successfully")
except Exception as e:
    redis_client = None
    REDIS_AVAILABLE = False
    logger.warning(f"⚠️  Redis not available: {e}. Caching disabled.")


# 캐시 설정
DEFAULT_TTL = 300  # 5분
SCRATCH_CACHE_TTL = 180  # 3분 (더 자주 변경됨)
NODE_LIST_TTL = 600  # 10분 (노드 목록은 자주 변경되지 않음)


def get_cache_key(prefix: str, *args, **kwargs) -> str:
    """캐시 키 생성"""
    key_parts = [prefix]
    
    # args 추가
    for arg in args:
        if isinstance(arg, (dict, list)):
            key_parts.append(hashlib.md5(json.dumps(arg, sort_keys=True).encode()).hexdigest()[:8])
        else:
            key_parts.append(str(arg))
    
    # kwargs 추가 (정렬된 순서)
    for k, v in sorted(kwargs.items()):
        if isinstance(v, (dict, list)):
            key_parts.append(f"{k}:{hashlib.md5(json.dumps(v, sort_keys=True).encode()).hexdigest()[:8]}")
        else:
            key_parts.append(f"{k}:{v}")
    
    return ":".join(key_parts)


def cache_result(ttl: int = DEFAULT_TTL, prefix: str = "cache"):
    """
    함수 결과 캐싱 데코레이터
    
    Usage:
        @cache_result(ttl=300, prefix="scratch")
        def expensive_function(node_id):
            ...
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            if not REDIS_AVAILABLE:
                # Redis 없으면 바로 함수 실행
                return func(*args, **kwargs)
            
            # 캐시 키 생성
            cache_key = get_cache_key(prefix, func.__name__, *args, **kwargs)
            
            try:
                # 캐시 조회
                cached = redis_client.get(cache_key)
                if cached:
                    logger.debug(f"Cache HIT: {cache_key}")
                    return json.loads(cached)
                
                logger.debug(f"Cache MISS: {cache_key}")
                
            except Exception as e:
                logger.warning(f"Cache read error: {e}")
            
            # 함수 실행
            result = func(*args, **kwargs)
            
            try:
                # 결과 캐싱
                redis_client.setex(
                    cache_key,
                    ttl,
                    json.dumps(result)
                )
                logger.debug(f"Cached result: {cache_key} (TTL: {ttl}s)")
            except Exception as e:
                logger.warning(f"Cache write error: {e}")
            
            return result
        
        return wrapper
    return decorator


def invalidate_cache(prefix: str, *args, **kwargs):
    """특정 캐시 무효화"""
    if not REDIS_AVAILABLE:
        return
    
    try:
        cache_key = get_cache_key(prefix, *args, **kwargs)
        redis_client.delete(cache_key)
        logger.debug(f"Invalidated cache: {cache_key}")
    except Exception as e:
        logger.warning(f"Cache invalidation error: {e}")


def invalidate_pattern(pattern: str):
    """패턴 매칭으로 캐시 무효화"""
    if not REDIS_AVAILABLE:
        return
    
    try:
        keys = redis_client.keys(pattern)
        if keys:
            redis_client.delete(*keys)
            logger.info(f"Invalidated {len(keys)} cache keys matching: {pattern}")
    except Exception as e:
        logger.warning(f"Pattern invalidation error: {e}")


class ParallelExecutor:
    """병렬 실행 헬퍼"""
    
    def __init__(self, max_workers: int = 10):
        self.max_workers = max_workers
        self.executor = ThreadPoolExecutor(max_workers=max_workers)
    
    def execute_parallel(self, func: Callable, items: List[Any], 
                        timeout: Optional[float] = None) -> List[Dict]:
        """
        여러 아이템에 대해 함수를 병렬 실행
        
        Args:
            func: 실행할 함수 (단일 아이템 처리)
            items: 처리할 아이템 리스트
            timeout: 개별 작업 타임아웃 (초)
        
        Returns:
            결과 리스트 (성공/실패 포함)
        """
        results = []
        futures = {}
        
        # 작업 제출
        for item in items:
            future = self.executor.submit(func, item)
            futures[future] = item
        
        # 결과 수집
        for future in as_completed(futures, timeout=timeout):
            item = futures[future]
            try:
                result = future.result(timeout=timeout)
                results.append({
                    'success': True,
                    'item': item,
                    'result': result
                })
            except Exception as e:
                logger.error(f"Parallel execution failed for {item}: {e}")
                results.append({
                    'success': False,
                    'item': item,
                    'error': str(e)
                })
        
        return results
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.executor.shutdown(wait=True)


# SSH 병렬 실행 헬퍼
def run_ssh_parallel(nodes: List[str], command: str, timeout: int = 30) -> Dict[str, Dict]:
    """
    여러 노드에서 SSH 명령을 병렬 실행
    
    Returns:
        {node: {success: bool, output: str, error: str}}
    """
    import subprocess
    
    def run_on_node(node: str) -> Dict:
        try:
            cmd = ['ssh', '-o', 'ConnectTimeout=5', node, command]
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            
            return {
                'success': result.returncode == 0,
                'output': result.stdout,
                'error': result.stderr if result.returncode != 0 else None,
                'node': node
            }
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'error': f'SSH timeout ({timeout}s)',
                'node': node
            }
        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'node': node
            }
    
    with ParallelExecutor(max_workers=min(len(nodes), 10)) as executor:
        results = executor.execute_parallel(run_on_node, nodes, timeout=timeout)
    
    # 결과를 딕셔너리로 변환
    return {
        r['item']: {
            'success': r['success'],
            'output': r.get('result', {}).get('output', ''),
            'error': r.get('result', {}).get('error') or r.get('error')
        }
        for r in results
    }


# 캐시 통계
def get_cache_stats() -> Dict:
    """캐시 통계 조회"""
    if not REDIS_AVAILABLE:
        return {
            'enabled': False,
            'message': 'Redis not available'
        }
    
    try:
        info = redis_client.info('stats')
        keyspace = redis_client.info('keyspace')
        
        return {
            'enabled': True,
            'connected': True,
            'total_keys': sum(v.get('keys', 0) for v in keyspace.values()),
            'hits': info.get('keyspace_hits', 0),
            'misses': info.get('keyspace_misses', 0),
            'hit_rate': info.get('keyspace_hits', 0) / max(
                info.get('keyspace_hits', 0) + info.get('keyspace_misses', 0), 
                1
            ) * 100
        }
    except Exception as e:
        return {
            'enabled': True,
            'connected': False,
            'error': str(e)
        }


# 프리로딩 (백그라운드 캐시 워밍)
class CacheWarmer:
    """백그라운드 캐시 워밍"""
    
    def __init__(self):
        self.executor = ThreadPoolExecutor(max_workers=2)
        self.tasks = []
    
    def schedule(self, func: Callable, *args, **kwargs):
        """백그라운드 작업 스케줄"""
        future = self.executor.submit(func, *args, **kwargs)
        self.tasks.append(future)
        return future
    
    def wait_all(self, timeout: Optional[float] = None):
        """모든 작업 대기"""
        for future in as_completed(self.tasks, timeout=timeout):
            try:
                future.result()
            except Exception as e:
                logger.warning(f"Cache warming task failed: {e}")
        
        self.tasks.clear()
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.executor.shutdown(wait=False)


# 전역 인스턴스
cache_warmer = CacheWarmer()


# 프로그레시브 로딩 헬퍼
class ProgressiveLoader:
    """점진적 데이터 로딩"""
    
    def __init__(self, total_items: int, batch_size: int = 10):
        self.total_items = total_items
        self.batch_size = batch_size
        self.loaded = 0
    
    def get_next_batch(self) -> Optional[range]:
        """다음 배치 범위 반환"""
        if self.loaded >= self.total_items:
            return None
        
        start = self.loaded
        end = min(self.loaded + self.batch_size, self.total_items)
        self.loaded = end
        
        return range(start, end)
    
    def progress_percent(self) -> float:
        """진행률 (%)"""
        return (self.loaded / self.total_items) * 100 if self.total_items > 0 else 100
    
    def is_complete(self) -> bool:
        """로딩 완료 여부"""
        return self.loaded >= self.total_items
