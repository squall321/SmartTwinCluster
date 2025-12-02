"""
Async Storage Management Utilities with Caching (FIXED VERSION)
SSH 병렬 처리 및 캐싱 기능이 추가된 비동기 유틸리티 - 버그 수정됨
"""

import asyncio
import asyncssh
import time
import logging
from typing import List, Dict, Optional
from datetime import datetime
from collections import OrderedDict
from storage_utils import (
    format_size, 
    get_disk_usage, 
    get_file_info,
    count_files_recursive,
    get_directory_size
)

# 로깅 설정
logger = logging.getLogger(__name__)

# 캐시 설정
CACHE_TTL = 300  # 5분 (초 단위)
MAX_CACHE_SIZE = 1000  # 최대 캐시 항목 수
_cache_store = OrderedDict()
_cache_timestamps = OrderedDict()


def get_cache_key(prefix: str, *args) -> str:
    """캐시 키 생성"""
    return f"{prefix}:{'_'.join(str(arg) for arg in args)}"


def is_cache_valid(key: str) -> bool:
    """캐시 유효성 확인"""
    if key not in _cache_timestamps:
        return False
    
    elapsed = time.time() - _cache_timestamps[key]
    return elapsed < CACHE_TTL


def get_cached(key: str) -> Optional[any]:
    """캐시에서 데이터 가져오기"""
    if is_cache_valid(key):
        # 최근 사용한 항목으로 이동 (LRU)
        _cache_store.move_to_end(key)
        _cache_timestamps.move_to_end(key)
        return _cache_store.get(key)
    return None


def set_cache(key: str, value: any) -> None:
    """캐시에 데이터 저장 (LRU eviction)"""
    # 크기 제한 확인
    if len(_cache_store) >= MAX_CACHE_SIZE:
        # 가장 오래된 항목 제거 (OrderedDict의 첫 번째 항목)
        oldest_key = next(iter(_cache_store))
        _cache_store.pop(oldest_key, None)
        _cache_timestamps.pop(oldest_key, None)
        logger.debug(f"Cache eviction: removed {oldest_key}")
    
    _cache_store[key] = value
    _cache_timestamps[key] = time.time()
    
    # 최신 항목으로 이동
    _cache_store.move_to_end(key)
    _cache_timestamps.move_to_end(key)


def clear_cache(prefix: Optional[str] = None) -> None:
    """캐시 초기화 (prefix가 있으면 해당 prefix만)"""
    if prefix is None:
        _cache_store.clear()
        _cache_timestamps.clear()
        logger.info("All cache cleared")
    else:
        keys_to_delete = [k for k in _cache_store.keys() if k.startswith(prefix)]
        for key in keys_to_delete:
            _cache_store.pop(key, None)
            _cache_timestamps.pop(key, None)
        logger.info(f"Cache cleared for prefix: {prefix} ({len(keys_to_delete)} items)")


async def run_ssh_command(node: str, command: str, timeout: int = 10) -> Optional[Dict]:
    """
    비동기 SSH 명령 실행
    Returns: {'success': bool, 'output': str, 'error': str}
    """
    try:
        import os
        
        # SSH known_hosts 파일 경로
        known_hosts_path = os.path.expanduser('~/.ssh/known_hosts')
        skip_host_check = os.getenv('SKIP_SSH_HOST_KEY_CHECK', 'false').lower() == 'true'
        
        async with asyncssh.connect(
            node,
            known_hosts=None if skip_host_check else (known_hosts_path if os.path.exists(known_hosts_path) else None),
            username=None,  # 현재 사용자
            connect_timeout=5
        ) as conn:
            result = await asyncio.wait_for(
                conn.run(command, check=False),
                timeout=timeout
            )
            
            return {
                'success': result.exit_status == 0,
                'output': result.stdout.strip() if result.stdout else '',
                'error': result.stderr.strip() if result.stderr else '',
                'node': node
            }
    except asyncio.TimeoutError:
        logger.warning(f"SSH timeout for {node} after {timeout}s")
        return {
            'success': False,
            'output': '',
            'error': f'Timeout after {timeout}s',
            'node': node
        }
    except Exception as e:
        logger.error(f"SSH error for {node}: {e}")
        return {
            'success': False,
            'output': '',
            'error': str(e),
            'node': node
        }


async def get_node_scratch_info_async(node: str, use_cache: bool = True, max_retries: int = 3) -> Optional[Dict]:
    """
    단일 노드의 scratch 정보를 비동기로 가져오기 (캐싱 + 재시도 지원)
    """
    # 캐시 확인
    if use_cache:
        cache_key = get_cache_key('node_scratch', node)
        cached_data = get_cached(cache_key)
        if cached_data:
            logger.debug(f"Cache hit for node {node}")
            return cached_data
    
    # 재시도 루프
    for attempt in range(max_retries):
        try:
            # 병렬로 여러 명령 실행
            commands = {
                'df': 'df -h /scratch | tail -n 1',
                'du': 'du -sh /scratch 2>/dev/null || echo "0"',
                'dirs': 'find /scratch -maxdepth 1 -type d ! -path /scratch 2>/dev/null | wc -l',
                'files': 'find /scratch -type f 2>/dev/null | wc -l'
            }
            
            tasks = [run_ssh_command(node, cmd) for cmd in commands.values()]
            results = await asyncio.gather(*tasks)
            
            # 결과 파싱
            df_result, du_result, dirs_result, files_result = results
            
            if not df_result['success']:
                if attempt < max_retries - 1:
                    logger.warning(f"Node {node} df command failed (attempt {attempt + 1}/{max_retries}), retrying...")
                    await asyncio.sleep(1)
                    continue
                else:
                    logger.error(f"Node {node} df command failed after {max_retries} attempts")
                    return None
            
            # df 출력 파싱
            df_line = df_result['output'].split()
            if len(df_line) >= 5:
                total_space = df_line[1]
                used_space = df_line[2]
                usage_percent = int(df_line[4].rstrip('%'))
            else:
                logger.error(f"Node {node} df output format invalid: {df_result['output']}")
                return None
            
            # 디렉토리 상세 정보 가져오기
            directories = await get_node_directories_async(node)
            
            node_info = {
                'nodeId': node,
                'nodeName': node,
                'totalSpace': total_space,
                'usedSpace': used_space,
                'usagePercent': usage_percent,
                'directories': directories,
                'status': 'active',
                'lastChecked': datetime.now().isoformat()
            }
            
            # 캐시 저장
            if use_cache:
                cache_key = get_cache_key('node_scratch', node)
                set_cache(cache_key, node_info)
            
            return node_info
            
        except asyncio.TimeoutError:
            logger.warning(f"Timeout for node {node} (attempt {attempt + 1}/{max_retries})")
            if attempt == max_retries - 1:
                logger.error(f"Node {node} timed out after {max_retries} attempts")
                return None
            await asyncio.sleep(1)
            
        except Exception as e:
            logger.error(f"Error getting scratch info for {node} (attempt {attempt + 1}/{max_retries}): {e}", exc_info=True)
            if attempt == max_retries - 1:
                return None
            await asyncio.sleep(1)
    
    return None


async def get_node_directories_async(node: str) -> List[Dict]:
    """노드의 /scratch 디렉토리 목록 가져오기"""
    try:
        # /scratch 디렉토리 목록
        cmd = 'ls -lh /scratch 2>/dev/null | tail -n +2'
        result = await run_ssh_command(node, cmd)
        
        if not result['success']:
            logger.warning(f"Failed to list directories on {node}: {result['error']}")
            return []
        
        directories = []
        for line in result['output'].split('\n'):
            if not line.strip():
                continue
            
            parts = line.split()
            if len(parts) < 9:
                continue
            
            permissions = parts[0]
            if not permissions.startswith('d'):
                continue
            
            owner = parts[2]
            group = parts[3]
            size = parts[4]
            name = parts[8]
            
            directories.append({
                'id': f"{node}-{name}",
                'name': name,
                'path': f"/scratch/{name}",
                'owner': owner,
                'group': group,
                'size': size,
                'sizeBytes': 0,
                'fileCount': 0,
                'createdAt': datetime.now().isoformat(),
                'node': node
            })
        
        return directories
        
    except Exception as e:
        logger.error(f"Error getting directories for {node}: {e}", exc_info=True)
        return []


async def get_all_nodes_scratch_info(nodes: List[str], use_cache: bool = True) -> List[Dict]:
    """
    모든 노드의 scratch 정보를 병렬로 가져오기
    기존 방식: 순차 실행 (N * 2-5초)
    새 방식: 병렬 실행 (~5초)
    """
    if not nodes:
        return []
    
    logger.info(f"Fetching scratch info for {len(nodes)} nodes in parallel...")
    start_time = time.time()
    
    # 모든 노드에 대해 동시에 작업 실행
    tasks = [get_node_scratch_info_async(node, use_cache) for node in nodes]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    # 성공한 결과만 필터링
    valid_results = []
    for i, result in enumerate(results):
        if isinstance(result, Exception):
            logger.error(f"Node {nodes[i]} failed with exception: {result}")
        elif result is not None:
            valid_results.append(result)
        else:
            logger.warning(f"Node {nodes[i]} returned None")
    
    elapsed = time.time() - start_time
    logger.info(f"Fetched {len(valid_results)}/{len(nodes)} nodes in {elapsed:.2f}s")
    
    return valid_results


async def get_scratch_storage_stats(use_cache: bool = True) -> Dict:
    """
    전체 scratch 스토리지 통계 (캐싱 지원)
    """
    cache_key = get_cache_key('scratch_stats')
    
    if use_cache:
        cached_data = get_cached(cache_key)
        if cached_data:
            logger.debug("Cache hit for scratch stats")
            return cached_data
    
    try:
        # Slurm 노드 목록 가져오기
        from storage_utils import get_slurm_nodes
        nodes = get_slurm_nodes()
        
        if not nodes:
            logger.warning("No Slurm nodes found")
            return {
                'totalNodes': 0,
                'activeNodes': 0,
                'totalCapacity': '0 GB',
                'totalUsed': '0 GB',
                'averageUsage': 0,
                'nodeDetails': []
            }
        
        # 병렬로 모든 노드 정보 수집
        node_infos = await get_all_nodes_scratch_info(nodes, use_cache)
        
        # 통계 계산
        total_usage = 0
        active_nodes = len(node_infos)
        
        for info in node_infos:
            total_usage += info.get('usagePercent', 0)
        
        avg_usage = total_usage / active_nodes if active_nodes > 0 else 0
        
        stats = {
            'totalNodes': len(nodes),
            'activeNodes': active_nodes,
            'averageUsage': round(avg_usage, 1),
            'nodeDetails': node_infos,
            'lastUpdated': datetime.now().isoformat()
        }
        
        # 캐시 저장
        if use_cache:
            set_cache(cache_key, stats)
        
        return stats
        
    except Exception as e:
        logger.error(f"Error getting scratch storage stats: {e}", exc_info=True)
        return {
            'totalNodes': 0,
            'activeNodes': 0,
            'averageUsage': 0,
            'nodeDetails': [],
            'error': str(e)
        }


def get_data_storage_stats_cached(path: str = "/data", use_cache: bool = True) -> Dict:
    """
    /data 스토리지 통계 (캐싱 지원)
    """
    cache_key = get_cache_key('data_stats', path)
    
    if use_cache:
        cached_data = get_cached(cache_key)
        if cached_data:
            logger.debug(f"Cache hit for data stats: {path}")
            return cached_data
    
    try:
        # 디스크 사용량
        disk_info = get_disk_usage(path)
        
        # 데이터셋 수 (하위 디렉토리)
        import os
        dataset_count = 0
        if os.path.exists(path):
            dataset_count = len([d for d in os.listdir(path) 
                               if os.path.isdir(os.path.join(path, d))])
        
        # 파일 수
        file_count, dir_count = count_files_recursive(path)
        
        stats = {
            'totalCapacity': disk_info['total'],
            'totalCapacityBytes': disk_info['totalBytes'],
            'usedSpace': disk_info['used'],
            'usedSpaceBytes': disk_info['usedBytes'],
            'availableSpace': disk_info['available'],
            'availableSpaceBytes': disk_info['availableBytes'],
            'usagePercent': disk_info['usagePercent'],
            'datasetCount': dataset_count,
            'fileCount': file_count,
            'lastUpdated': datetime.now().isoformat()
        }
        
        # 캐시 저장
        if use_cache:
            set_cache(cache_key, stats)
        
        return stats
        
    except Exception as e:
        logger.error(f"Error getting data storage stats: {e}", exc_info=True)
        return {
            'totalCapacity': '0 GB',
            'usedSpace': '0 GB',
            'usagePercent': 0,
            'datasetCount': 0,
            'fileCount': 0,
            'error': str(e)
        }


def run_async_safe(coro):
    """
    안전한 비동기 함수 실행 래퍼
    기존 이벤트 루프와 충돌 방지
    """
    try:
        # 현재 실행 중인 루프 확인
        loop = asyncio.get_running_loop()
        # 이미 루프가 실행 중이면 별도 스레드에서 실행
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor() as executor:
            future = executor.submit(asyncio.run, coro)
            return future.result()
    except RuntimeError:
        # 루프가 없음 - 안전하게 실행
        return asyncio.run(coro)


# Sync wrapper for backward compatibility
def get_all_nodes_scratch_info_sync(nodes: List[str], use_cache: bool = True) -> List[Dict]:
    """
    동기 래퍼 함수 (기존 코드와 호환성 유지) - FIXED
    """
    return run_async_safe(get_all_nodes_scratch_info(nodes, use_cache))


def get_scratch_storage_stats_sync(use_cache: bool = True) -> Dict:
    """
    동기 래퍼 함수 (기존 코드와 호환성 유지) - FIXED
    """
    return run_async_safe(get_scratch_storage_stats(use_cache))
