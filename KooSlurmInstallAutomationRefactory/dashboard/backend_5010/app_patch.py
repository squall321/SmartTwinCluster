"""
app.py에 업로드/다운로드 및 성능 최적화 기능 통합을 위한 패치

기존 app.py 파일 끝부분(if __name__ == '__main__': 위)에 아래 코드를 추가하세요:
"""

# ==================== 파일 업로드/다운로드 통합 ====================

from upload_api import upload_bp

# Blueprint 등록
app.register_blueprint(upload_bp)

print("  📤 Upload/Download API enabled")

# ==================== 성능 최적화 통합 ====================

from storage_api_optimized import (
    get_data_stats_cached,
    get_slurm_nodes_cached,
    get_scratch_info_parallel,
    get_scratch_directories_parallel,
    invalidate_storage_cache,
    warm_storage_cache
)

from performance import get_cache_stats

# 기존 /api/storage/data/stats 엔드포인트를 캐싱 버전으로 교체
@app.route('/api/storage/data/stats', methods=['GET'])
def get_data_storage_stats_optimized():
    """
    /data 디스크 사용량 조회 (캐싱 적용)
    """
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': {
                    'path': '/data',
                    'total': '10TB',
                    'used': '4.5TB',
                    'available': '5.5TB',
                    'use_percent': 45
                }
            })
        else:
            stats = get_data_stats_cached()
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': stats,
                'cached': True
            })
    except Exception as e:
        print(f"❌ Error getting data storage stats: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# 기존 /api/storage/scratch/nodes 엔드포인트를 최적화 버전으로 교체
@app.route('/api/storage/scratch/nodes', methods=['GET'])
def get_scratch_nodes_optimized():
    """
    Scratch 스토리지 노드 조회 (병렬 처리 + 캐싱)
    
    Performance:
        - 기존: 4-6초 (2노드, 순차 SSH)
        - 개선: 2-3초 (병렬 SSH + 캐싱)
        - 캐시 히트: ~100ms
    """
    try:
        if MOCK_MODE:
            from data.mockStorageData import mockScratchNodes
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': mockScratchNodes
            })
        else:
            # 1. 노드 목록 조회 (캐싱)
            nodes = get_slurm_nodes_cached()
            
            if not nodes:
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'data': [],
                    'message': 'No compute nodes found'
                })
            
            # 2. 활성 노드만 필터링
            active_nodes = [
                n['hostname'] for n in nodes 
                if n.get('state') in ['idle', 'allocated', 'mixed']
            ]
            
            if not active_nodes:
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'data': [],
                    'message': 'No active nodes'
                })
            
            # 3. Scratch 정보 병렬 수집 (캐싱)
            scratch_info = get_scratch_info_parallel(active_nodes)
            
            # 4. 디렉토리 목록 병렬 수집 (캐싱)
            directories = get_scratch_directories_parallel(active_nodes)
            
            # 5. 데이터 결합
            result = []
            for info in scratch_info:
                node_name = info.get('node')
                node_dirs = [d for d in directories if d.get('node') == node_name]
                
                result.append({
                    'id': node_name,
                    'name': node_name,
                    'status': info.get('status', 'unknown'),
                    'diskUsage': {
                        'total': info.get('total', 'N/A'),
                        'used': info.get('used', 'N/A'),
                        'available': info.get('available', 'N/A'),
                        'usePercent': info.get('use_percent', 0)
                    },
                    'directories': node_dirs
                })
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': result,
                'cached': True,
                'node_count': len(result)
            })
            
    except Exception as e:
        print(f"❌ Error getting scratch nodes: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# 캐시 통계 엔드포인트
@app.route('/api/cache/stats', methods=['GET'])
def get_cache_statistics():
    """캐시 통계 조회"""
    try:
        stats = get_cache_stats()
        return jsonify({
            'success': True,
            'data': stats
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# 캐시 무효화 엔드포인트
@app.route('/api/cache/invalidate', methods=['POST'])
def invalidate_cache_endpoint():
    """캐시 무효화"""
    try:
        invalidate_storage_cache()
        return jsonify({
            'success': True,
            'message': 'Storage cache invalidated'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# 앱 시작 시 캐시 워밍 (Production 모드만)
if not MOCK_MODE:
    import threading
    
    def warm_cache_background():
        import time
        time.sleep(2)  # 앱 시작 후 2초 대기
        print("🔥 Warming up cache...")
        warm_storage_cache()
        print("✅ Cache warming completed")
    
    # 백그라운드 스레드로 실행
    warming_thread = threading.Thread(target=warm_cache_background, daemon=True)
    warming_thread.start()


print("  ⚡ Performance optimizations enabled (Redis caching + parallel SSH)")
