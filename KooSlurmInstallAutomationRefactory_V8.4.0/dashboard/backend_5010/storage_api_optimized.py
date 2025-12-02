"""
Storage API에 성능 최적화 적용 (캐싱 + 병렬 처리)
"""

from storage_utils import (
    get_disk_usage,
    get_slurm_nodes,
    run_remote_command
)

from performance import (
    cache_result,
    run_ssh_parallel,
    invalidate_pattern,
    SCRATCH_CACHE_TTL,
    NODE_LIST_TTL,
    DEFAULT_TTL
)

import logging

logger = logging.getLogger(__name__)


# ==================== 캐싱 적용된 함수들 ====================

@cache_result(ttl=DEFAULT_TTL, prefix="storage")
def get_data_stats_cached():
    """
    /data 디스크 사용량 조회 (캐싱)
    """
    return get_disk_usage('/data')


@cache_result(ttl=NODE_LIST_TTL, prefix="nodes")
def get_slurm_nodes_cached():
    """
    Slurm 노드 목록 조회 (캐싱)
    """
    return get_slurm_nodes()


@cache_result(ttl=SCRATCH_CACHE_TTL, prefix="scratch")
def get_scratch_info_parallel(nodes: list):
    """
    여러 노드의 /scratch 정보를 병렬로 수집 (캐싱)
    
    Performance:
        - 기존: 2초 * N노드 = 4초 (2노드)
        - 개선: max(2초) = 2초 (병렬 처리)
    """
    if not nodes:
        return []
    
    # 병렬로 df 명령 실행
    results = run_ssh_parallel(
        nodes,
        "df -h /scratch | tail -1",
        timeout=10
    )
    
    scratch_data = []
    
    for node in nodes:
        result = results.get(node, {})
        
        if result.get('success') and result.get('output'):
            try:
                # df 출력 파싱
                parts = result['output'].split()
                if len(parts) >= 6:
                    scratch_data.append({
                        'node': node,
                        'total': parts[1],
                        'used': parts[2],
                        'available': parts[3],
                        'use_percent': parts[4].rstrip('%'),
                        'mount': parts[5],
                        'status': 'online'
                    })
                else:
                    scratch_data.append({
                        'node': node,
                        'status': 'error',
                        'error': 'Invalid df output'
                    })
            except Exception as e:
                logger.error(f"Failed to parse scratch data for {node}: {e}")
                scratch_data.append({
                    'node': node,
                    'status': 'error',
                    'error': str(e)
                })
        else:
            scratch_data.append({
                'node': node,
                'status': 'offline' if 'timeout' in str(result.get('error', '')) else 'error',
                'error': result.get('error', 'Unknown error')
            })
    
    return scratch_data


@cache_result(ttl=SCRATCH_CACHE_TTL, prefix="scratch_dirs")
def get_scratch_directories_parallel(nodes: list):
    """
    여러 노드의 /scratch 디렉토리 목록을 병렬로 수집
    """
    if not nodes:
        return []
    
    # 병렬로 ls 명령 실행
    results = run_ssh_parallel(
        nodes,
        "ls -lhA /scratch 2>/dev/null | tail -n +2",  # 헤더 제외
        timeout=15
    )
    
    all_directories = []
    
    for node in nodes:
        result = results.get(node, {})
        
        if result.get('success') and result.get('output'):
            try:
                lines = result['output'].strip().split('\n')
                for line in lines:
                    if not line:
                        continue
                    
                    parts = line.split()
                    if len(parts) >= 9 and parts[0].startswith('d'):
                        # 디렉토리인 경우
                        dir_name = ' '.join(parts[8:])
                        size = parts[4]
                        modified = ' '.join(parts[5:8])
                        
                        all_directories.append({
                            'id': f"{node}:/scratch/{dir_name}",
                            'node': node,
                            'name': dir_name,
                            'size': size,
                            'modified': modified,
                            'path': f"/scratch/{dir_name}"
                        })
            except Exception as e:
                logger.error(f"Failed to parse directories for {node}: {e}")
    
    return all_directories


def invalidate_storage_cache():
    """Storage 관련 캐시 무효화"""
    invalidate_pattern('storage:*')
    invalidate_pattern('scratch:*')
    invalidate_pattern('nodes:*')
    logger.info("Storage cache invalidated")


# ==================== 백그라운드 워밍 ====================

def warm_storage_cache():
    """
    백그라운드에서 캐시 프리로드
    API 첫 요청 전에 실행하면 즉시 응답 가능
    """
    from performance import cache_warmer
    
    logger.info("Starting cache warming...")
    
    # /data 통계
    cache_warmer.schedule(get_data_stats_cached)
    
    # 노드 목록
    nodes_future = cache_warmer.schedule(get_slurm_nodes_cached)
    
    # 노드 목록이 로드되면 scratch 정보도 수집
    try:
        nodes = nodes_future.result(timeout=5)
        if nodes:
            node_names = [n['hostname'] for n in nodes if n.get('state') == 'idle' or n.get('state') == 'allocated']
            if node_names:
                cache_warmer.schedule(get_scratch_info_parallel, node_names)
                cache_warmer.schedule(get_scratch_directories_parallel, node_names)
    except Exception as e:
        logger.warning(f"Cache warming failed: {e}")
    
    logger.info("Cache warming completed")


# ==================== 프로그레시브 로딩 ====================

def get_scratch_progressive(nodes: list, batch_size: int = 5):
    """
    점진적으로 노드 정보 로드
    
    첫 5개 노드 → 즉시 반환
    나머지 노드 → 백그라운드 로드
    """
    if not nodes:
        return [], None
    
    # 첫 배치 즉시 반환
    first_batch = nodes[:batch_size]
    remaining = nodes[batch_size:]
    
    first_results = get_scratch_info_parallel(first_batch)
    
    # 나머지는 백그라운드에서 로드
    from performance import cache_warmer
    
    remaining_future = None
    if remaining:
        remaining_future = cache_warmer.schedule(
            get_scratch_info_parallel,
            remaining
        )
    
    return first_results, remaining_future
