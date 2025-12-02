"""
디렉토리 크기 계산 API
재귀적 크기 계산, 캐싱
"""

from flask import Blueprint, jsonify, request
import os
import subprocess

# Optional: performance 모듈 (Redis)
try:
    from performance import cache_result
    CACHING_ENABLED = True
except ImportError:
    # Redis 없으면 더미 데코레이터
    def cache_result(ttl=300, prefix="cache"):
        def decorator(func):
            return func
        return decorator
    CACHING_ENABLED = False

directory_bp = Blueprint('directory', __name__)


def format_size(bytes_size):
    """바이트를 읽기 쉬운 형식으로 변환"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"


@directory_bp.route('/api/directory/size', methods=['POST'])
@cache_result(ttl=300, prefix="dir_size")
def calculate_directory_size():
    """
    디렉토리 크기 계산
    
    Request:
        {
            "path": "/data/datasets"
        }
    
    Response:
        {
            "success": true,
            "path": "/data/datasets",
            "size_bytes": 1073741824,
            "size_human": "1.0 GB",
            "file_count": 1234,
            "dir_count": 56
        }
    """
    try:
        data = request.json
        path = data.get('path')
        
        if not path or not os.path.exists(path):
            return jsonify({
                'success': False,
                'error': 'Path not found'
            }), 404
        
        if not os.path.isdir(path):
            return jsonify({
                'success': False,
                'error': 'Not a directory'
            }), 400
        
        # du 명령어로 크기 계산 (빠름)
        du_result = subprocess.run(
            ['du', '-sb', path],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if du_result.returncode != 0:
            return jsonify({
                'success': False,
                'error': 'Failed to calculate size'
            }), 500
        
        size_bytes = int(du_result.stdout.split()[0])
        
        # 파일/디렉토리 카운트
        find_result = subprocess.run(
            ['find', path, '-maxdepth', '5'],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        items = find_result.stdout.strip().split('\n')
        file_count = 0
        dir_count = 0
        
        for item in items:
            if item and os.path.exists(item):
                if os.path.isfile(item):
                    file_count += 1
                elif os.path.isdir(item):
                    dir_count += 1
        
        return jsonify({
            'success': True,
            'path': path,
            'size_bytes': size_bytes,
            'size_human': format_size(size_bytes),
            'file_count': file_count,
            'dir_count': dir_count
        })
        
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'error': 'Calculation timeout'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@directory_bp.route('/api/directory/breakdown', methods=['POST'])
def get_directory_breakdown():
    """
    디렉토리별 크기 분석 (1단계 서브디렉토리)
    
    Request:
        {
            "path": "/data"
        }
    
    Response:
        {
            "success": true,
            "items": [
                {
                    "name": "datasets",
                    "path": "/data/datasets",
                    "size_bytes": 1073741824,
                    "size_human": "1.0 GB",
                    "type": "directory"
                }
            ]
        }
    """
    try:
        data = request.json
        path = data.get('path')
        
        if not path or not os.path.exists(path):
            return jsonify({
                'success': False,
                'error': 'Path not found'
            }), 404
        
        items = []
        
        # 1단계 서브 항목
        for item_name in os.listdir(path):
            item_path = os.path.join(path, item_name)
            
            try:
                if os.path.isdir(item_path):
                    # du로 크기 계산
                    du_result = subprocess.run(
                        ['du', '-sb', item_path],
                        capture_output=True,
                        text=True,
                        timeout=10
                    )
                    
                    if du_result.returncode == 0:
                        size_bytes = int(du_result.stdout.split()[0])
                        items.append({
                            'name': item_name,
                            'path': item_path,
                            'size_bytes': size_bytes,
                            'size_human': format_size(size_bytes),
                            'type': 'directory'
                        })
                else:
                    # 파일
                    stat = os.stat(item_path)
                    items.append({
                        'name': item_name,
                        'path': item_path,
                        'size_bytes': stat.st_size,
                        'size_human': format_size(stat.st_size),
                        'type': 'file'
                    })
            except:
                continue
        
        # 크기순 정렬
        items.sort(key=lambda x: x['size_bytes'], reverse=True)
        
        return jsonify({
            'success': True,
            'path': path,
            'items': items,
            'count': len(items)
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
