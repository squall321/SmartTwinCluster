"""
Cache Management API
스토리지 캐시 관리 및 통계
"""

from flask import Blueprint, jsonify, request
from datetime import datetime
import os

cache_bp = Blueprint('cache', __name__, url_prefix='/api/cache')

MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# 간단한 인메모리 캐시 (실제로는 Redis 등을 사용)
cache_store = {}
cache_stats = {
    'hits': 0,
    'misses': 0,
    'size': 0
}

@cache_bp.route('/stats', methods=['GET'])
def get_cache_stats():
    """캐시 통계 조회"""
    return jsonify({
        'success': True,
        'data': {
            'enabled': True,
            'hits': cache_stats['hits'],
            'misses': cache_stats['misses'],
            'size': cache_stats['size'],
            'hit_rate': round(cache_stats['hits'] / max(cache_stats['hits'] + cache_stats['misses'], 1) * 100, 2),
            'entries': len(cache_store)
        }
    })

@cache_bp.route('/invalidate', methods=['POST'])
def invalidate_cache():
    """캐시 무효화"""
    data = request.json
    pattern = data.get('pattern', '*')
    
    if pattern == '*':
        # 전체 캐시 삭제
        cache_store.clear()
        count = len(cache_store)
    else:
        # 패턴에 맞는 캐시만 삭제
        keys_to_delete = [k for k in cache_store.keys() if pattern.replace('*', '') in k]
        for key in keys_to_delete:
            del cache_store[key]
        count = len(keys_to_delete)
    
    cache_stats['size'] = len(cache_store)
    
    return jsonify({
        'success': True,
        'message': f'Invalidated {count} cache entries',
        'pattern': pattern
    })

print("✅ Cache API initialized")
