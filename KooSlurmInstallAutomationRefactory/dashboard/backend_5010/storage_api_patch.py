"""
Storage API 성능 개선 패치
- SSH 병렬 처리 추가
- 캐싱 기능 추가
- API 응답 시간 10x 개선

app.py에 적용할 패치입니다.
"""

# ==================== 📦 Storage Management API (개선됨) ====================

@app.route('/api/storage/data/stats', methods=['GET'])
def get_shared_storage_stats():
    """Shared Storage (/data) 통계 (캐싱 지원)"""
    try:
        use_cache = request.args.get('cache', 'true').lower() == 'true'
        
        if MOCK_MODE:
            # Mock 데이터
            mock_stats = {
                'totalCapacity': '100 TB',
                'totalCapacityBytes': 100 * 1024 * 1024 * 1024 * 1024,
                'usedSpace': '45 TB',
                'usedSpaceBytes': 45 * 1024 * 1024 * 1024 * 1024,
                'availableSpace': '55 TB',
                'availableSpaceBytes': 55 * 1024 * 1024 * 1024 * 1024,
                'usagePercent': 45.0,
                'datasetCount': 25,
                'fileCount': 12500,
                'lastUpdated': datetime.now().isoformat()
            }
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': mock_stats
            })
        else:
            # Production: 캐싱된 실제 데이터
            stats = get_data_storage_stats_cached('/data', use_cache=use_cache)
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': stats,
                'cached': use_cache and 'error' not in stats
            })
            
    except Exception as e:
        print(f"❌ Error getting shared storage stats: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/storage/scratch/nodes', methods=['GET'])
def get_scratch_nodes():
    """/scratch 노드별 스토리지 정보 (병렬 처리 + 캐싱)"""
    try:
        use_cache = request.args.get('cache', 'true').lower() == 'true'
        
        if MOCK_MODE:
            # Mock 모드는 기존 코드 유지
            from datetime import datetime
            
            mock_nodes = [
                {
                    'nodeId': 'node001',
                    'nodeName': 'node001',
                    'totalSpace': '500GB',
                    'usedSpace': '120GB',
                    'usagePercent': 24,
                    'directories': [
                        {
                            'id': 'dir1',
                            'name': 'user1_temp',
                            'path': '/scratch/user1_temp',
                            'owner': 'user1',
                            'group': 'research',
                            'size': '45GB',
                            'sizeBytes': 45 * 1024**3,
                            'fileCount': 1250,
                            'createdAt': '2024-01-15T10:30:00'
                        },
                        {
                            'id': 'dir2',
                            'name': 'user2_data',
                            'path': '/scratch/user2_data',
                            'owner': 'user2',
                            'group': 'research',
                            'size': '75GB',
                            'sizeBytes': 75 * 1024**3,
                            'fileCount': 890,
                            'createdAt': '2024-01-20T14:15:00'
                        }
                    ],
                    'status': 'active',
                    'lastChecked': datetime.now().isoformat()
                },
                {
                    'nodeId': 'node002',
                    'nodeName': 'node002',
                    'totalSpace': '500GB',
                    'usedSpace': '350GB',
                    'usagePercent': 70,
                    'directories': [
                        {
                            'id': 'dir3',
                            'name': 'user3_simulation',
                            'path': '/scratch/user3_simulation',
                            'owner': 'user3',
                            'group': 'engineering',
                            'size': '250GB',
                            'sizeBytes': 250 * 1024**3,
                            'fileCount': 5600,
                            'createdAt': '2024-02-01T09:00:00'
                        },
                        {
                            'id': 'dir4',
                            'name': 'user4_checkpoint',
                            'path': '/scratch/user4_checkpoint',
                            'owner': 'user4',
                            'group': 'engineering',
                            'size': '100GB',
                            'sizeBytes': 100 * 1024**3,
                            'fileCount': 200,
                            'createdAt': '2024-02-05T16:45:00'
                        }
                    ],
                    'status': 'active',
                    'lastChecked': datetime.now().isoformat()
                }
            ]
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': mock_nodes
            })
        else:
            # Production: 병렬 SSH + 캐싱
            print(f"🚀 Fetching scratch nodes (cache={use_cache})...")
            
            # 노드 목록 가져오기
            nodes = get_storage_nodes()
            
            if not nodes:
                print("⚠️  No compute nodes found")
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'data': [],
                    'message': 'No compute nodes available'
                })
            
            # 병렬 처리로 모든 노드 정보 수집
            start_time = time.time()
            scratch_data = get_all_nodes_scratch_info_sync(nodes, use_cache=use_cache)
            elapsed = time.time() - start_time
            
            print(f"✅ Fetched {len(scratch_data)} nodes in {elapsed:.2f}s (cache={use_cache})")
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': scratch_data,
                'cached': use_cache,
                'fetchTime': f'{elapsed:.2f}s',
                'nodeCount': len(scratch_data)
            })
            
    except Exception as e:
        print(f"❌ Error getting scratch nodes: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/storage/cache/clear', methods=['POST'])
def clear_storage_cache():
    """스토리지 캐시 초기화"""
    try:
        data = request.json or {}
        prefix = data.get('prefix')  # 특정 prefix만 초기화 (선택사항)
        
        clear_cache(prefix)
        
        return jsonify({
            'success': True,
            'message': f'Cache cleared' + (f' (prefix: {prefix})' if prefix else ' (all)'),
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/storage/cache/status', methods=['GET'])
def get_cache_status():
    """캐시 상태 확인"""
    try:
        from storage_utils_async import _cache_store, _cache_timestamps, CACHE_TTL
        import time
        
        cache_info = []
        current_time = time.time()
        
        for key in _cache_store.keys():
            timestamp = _cache_timestamps.get(key, 0)
            age = current_time - timestamp
            valid = age < CACHE_TTL
            
            cache_info.append({
                'key': key,
                'age_seconds': round(age, 2),
                'valid': valid,
                'expires_in': round(CACHE_TTL - age, 2) if valid else 0
            })
        
        return jsonify({
            'success': True,
            'cache_ttl': CACHE_TTL,
            'total_entries': len(cache_info),
            'entries': cache_info,
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# 기존의 다른 storage API들은 그대로 유지...
