"""
강력한 파일 검색 API
전체 스토리지 검색, 고급 필터
+ 통합 검색 (GlobalSearch)
"""

from flask import Blueprint, jsonify, request
import os
import subprocess
from pathlib import Path
from datetime import datetime
import re

search_bp = Blueprint('search', __name__)

# 검색 가능한 기본 경로
SEARCHABLE_PATHS = ['/data', '/scratch']

# Mock 모드
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'


@search_bp.route('/api/search/files', methods=['POST'])
def search_files():
    """
    파일 검색
    
    Request:
        {
            "query": "filename",
            "path": "/data",  // optional
            "extension": ".py",  // optional
            "min_size": 1024,  // optional (bytes)
            "max_size": 10485760,  // optional (bytes)
            "modified_after": "2024-01-01",  // optional
            "case_sensitive": false,  // optional
            "regex": false,  // optional
            "max_results": 100  // optional
        }
    
    Response:
        {
            "success": true,
            "results": [
                {
                    "path": "/data/file.txt",
                    "name": "file.txt",
                    "size": 1234,
                    "modified": "2024-10-07T12:00:00",
                    "type": "file" | "directory"
                }
            ],
            "count": 10,
            "truncated": false
        }
    """
    try:
        data = request.json
        query = data.get('query', '').strip()
        search_path = data.get('path', '/data')
        extension = data.get('extension', '')
        min_size = data.get('min_size')
        max_size = data.get('max_size')
        modified_after = data.get('modified_after')
        case_sensitive = data.get('case_sensitive', False)
        use_regex = data.get('regex', False)
        max_results = data.get('max_results', 100)
        
        if not query:
            return jsonify({
                'success': False,
                'error': 'Query is required'
            }), 400
        
        # 경로 검증
        if not any(search_path.startswith(p) for p in SEARCHABLE_PATHS):
            return jsonify({
                'success': False,
                'error': 'Invalid search path'
            }), 400
        
        # find 명령어 구성
        find_cmd = ['find', search_path]
        
        # 파일명 패턴
        if use_regex:
            find_cmd.extend(['-regex', f'.*{query}.*'])
        else:
            name_pattern = f'*{query}*'
            if case_sensitive:
                find_cmd.extend(['-name', name_pattern])
            else:
                find_cmd.extend(['-iname', name_pattern])
        
        # 확장자 필터
        if extension:
            find_cmd.extend(['-name', f'*{extension}'])
        
        # 크기 필터
        if min_size is not None:
            find_cmd.extend(['-size', f'+{min_size}c'])
        if max_size is not None:
            find_cmd.extend(['-size', f'-{max_size}c'])
        
        # 수정 날짜 필터
        if modified_after:
            find_cmd.extend(['-newermt', modified_after])
        
        # 최대 결과 수
        find_cmd.extend(['-maxdepth', '10'])  # 깊이 제한
        
        # 실행
        result = subprocess.run(
            find_cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0 and result.returncode != 1:  # 1 = no results
            return jsonify({
                'success': False,
                'error': f'Search failed: {result.stderr}'
            }), 500
        
        # 결과 파싱
        paths = [p.strip() for p in result.stdout.split('\n') if p.strip()]
        paths = paths[:max_results]
        
        results = []
        for path in paths:
            try:
                stat = os.stat(path)
                is_dir = os.path.isdir(path)
                
                results.append({
                    'path': path,
                    'name': os.path.basename(path),
                    'size': stat.st_size if not is_dir else 0,
                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    'type': 'directory' if is_dir else 'file'
                })
            except:
                continue
        
        return jsonify({
            'success': True,
            'results': results,
            'count': len(results),
            'truncated': len(paths) >= max_results,
            'search_query': query,
            'search_path': search_path
        })
        
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'error': 'Search timeout (30s)'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# 통합 검색 API (GlobalSearch)
# ============================================

@search_bp.route('/api/search/global', methods=['GET'])
def global_search():
    """
    통합 검색 - 작업, 노드, 파일, 템플릿 검색
    
    Query params:
        - q: 검색어 (required)
        - type: all | jobs | nodes | files | templates (default: all)
        - limit: 최대 결과 수 (default: 50)
    
    Response:
        {
            "success": true,
            "query": "search term",
            "results": {
                "jobs": [...],
                "nodes": [...],
                "files": [...],
                "templates": [...]
            },
            "total": 25
        }
    """
    try:
        query = request.args.get('q', '').strip().lower()
        search_type = request.args.get('type', 'all')
        limit = int(request.args.get('limit', 50))
        
        if not query:
            return jsonify({
                'success': False,
                'error': 'Query parameter "q" is required'
            }), 400
        
        results = {
            'jobs': [],
            'nodes': [],
            'files': [],
            'templates': []
        }
        
        # Mock 모드
        if MOCK_MODE:
            results = search_mock_data(query, search_type, limit)
        else:
            # Production: 실제 검색
            if search_type in ['all', 'jobs']:
                results['jobs'] = search_jobs(query, limit)
            if search_type in ['all', 'nodes']:
                results['nodes'] = search_nodes(query, limit)
            if search_type in ['all', 'files']:
                results['files'] = search_files_quick(query, limit)
            if search_type in ['all', 'templates']:
                results['templates'] = search_templates(query, limit)
        
        total = sum(len(v) for v in results.values())
        
        return jsonify({
            'success': True,
            'query': query,
            'results': results,
            'total': total,
            'mode': 'mock' if MOCK_MODE else 'production'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def search_mock_data(query, search_type, limit):
    """Mock 데이터 검색"""
    results = {
        'jobs': [],
        'nodes': [],
        'files': [],
        'templates': []
    }
    
    # Mock Jobs
    if search_type in ['all', 'jobs']:
        mock_jobs = [
            {
                'id': '12345',
                'name': f'training_job_{query}',
                'user': 'user01',
                'state': 'RUNNING',
                'partition': 'gpu',
                'nodes': 2,
                'type': 'job'
            },
            {
                'id': '12346',
                'name': f'simulation_{query}_test',
                'user': 'user02',
                'state': 'PENDING',
                'partition': 'cpu',
                'nodes': 4,
                'type': 'job'
            }
        ]
        results['jobs'] = [j for j in mock_jobs if query in j['name'].lower()][:limit]
    
    # Mock Nodes
    if search_type in ['all', 'nodes']:
        mock_nodes = [
            {
                'hostname': f'node-{query}-01',
                'state': 'idle',
                'cpus': 128,
                'memory': '512GB',
                'partition': 'gpu',
                'type': 'node'
            },
            {
                'hostname': f'compute-{query}',
                'state': 'allocated',
                'cpus': 64,
                'memory': '256GB',
                'partition': 'cpu',
                'type': 'node'
            }
        ]
        results['nodes'] = [n for n in mock_nodes if query in n['hostname'].lower()][:limit]
    
    # Mock Files
    if search_type in ['all', 'files']:
        mock_files = [
            {
                'name': f'{query}_dataset.csv',
                'path': f'/data/datasets/{query}_dataset.csv',
                'size': '1.2 GB',
                'modified': '2025-10-01',
                'type': 'file'
            },
            {
                'name': f'model_{query}.py',
                'path': f'/data/scripts/model_{query}.py',
                'size': '15 KB',
                'modified': '2025-10-05',
                'type': 'file'
            }
        ]
        results['files'] = [f for f in mock_files if query in f['name'].lower()][:limit]
    
    # Mock Templates
    if search_type in ['all', 'templates']:
        mock_templates = [
            {
                'id': 'tpl-001',
                'name': f'{query.title()} Training',
                'category': 'ml',
                'description': f'Standard {query} model training',
                'usage_count': 45,
                'type': 'template'
            },
            {
                'id': 'tpl-002',
                'name': f'{query.title()} Simulation',
                'category': 'simulation',
                'description': f'{query} dynamics simulation',
                'usage_count': 23,
                'type': 'template'
            }
        ]
        results['templates'] = [t for t in mock_templates if query in t['name'].lower()][:limit]
    
    return results


def search_jobs(query, limit):
    """작업 검색 (Production)"""
    try:
        result = subprocess.run(
            ['squeue', '-h', '-o', '%i|%j|%u|%T|%P|%D'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        jobs = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            parts = line.split('|')
            if len(parts) >= 6:
                job_id, name, user, state, partition, nodes = parts[:6]
                if query in name.lower() or query in job_id.lower():
                    jobs.append({
                        'id': job_id,
                        'name': name,
                        'user': user,
                        'state': state,
                        'partition': partition,
                        'nodes': nodes,
                        'type': 'job'
                    })
        
        return jobs[:limit]
    except:
        return []


def search_nodes(query, limit):
    """노드 검색 (Production)"""
    try:
        result = subprocess.run(
            ['sinfo', '-h', '-N', '-o', '%n|%T|%c|%m|%P'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        nodes = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            parts = line.split('|')
            if len(parts) >= 5:
                hostname, state, cpus, memory, partition = parts[:5]
                if query in hostname.lower():
                    nodes.append({
                        'hostname': hostname,
                        'state': state,
                        'cpus': cpus,
                        'memory': memory,
                        'partition': partition,
                        'type': 'node'
                    })
        
        return nodes[:limit]
    except:
        return []


def search_files_quick(query, limit):
    """파일 빠른 검색 (Production)"""
    try:
        results = []
        for base_path in SEARCHABLE_PATHS:
            if not os.path.exists(base_path):
                continue
            
            result = subprocess.run(
                ['find', base_path, '-maxdepth', '5', '-iname', f'*{query}*', '-type', 'f'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            for path in result.stdout.strip().split('\n')[:limit]:
                if not path:
                    continue
                try:
                    stat = os.stat(path)
                    size = stat.st_size
                    if size < 1024:
                        size_str = f'{size} B'
                    elif size < 1024 * 1024:
                        size_str = f'{size / 1024:.1f} KB'
                    elif size < 1024 * 1024 * 1024:
                        size_str = f'{size / (1024 * 1024):.1f} MB'
                    else:
                        size_str = f'{size / (1024 * 1024 * 1024):.1f} GB'
                    
                    results.append({
                        'name': os.path.basename(path),
                        'path': path,
                        'size': size_str,
                        'modified': datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d'),
                        'type': 'file'
                    })
                except:
                    continue
        
        return results[:limit]
    except:
        return []


def search_templates(query, limit):
    """템플릿 검색 (Database)"""
    try:
        # SQLite 데이터베이스에서 검색
        from database import get_db_connection
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT id, name, category, description, usage_count
            FROM templates
            WHERE LOWER(name) LIKE ? OR LOWER(description) LIKE ?
            ORDER BY usage_count DESC
            LIMIT ?
        """, (f'%{query}%', f'%{query}%', limit))
        
        templates = []
        for row in cursor.fetchall():
            templates.append({
                'id': row[0],
                'name': row[1],
                'category': row[2],
                'description': row[3],
                'usage_count': row[4],
                'type': 'template'
            })
        
        conn.close()
        return templates
    except:
        return []


@search_bp.route('/api/search/content', methods=['POST'])
def search_content():
    """
    파일 내용 검색 (grep)
    
    Request:
        {
            "query": "search text",
            "path": "/data",
            "file_pattern": "*.py",  // optional
            "case_sensitive": false,
            "max_results": 50
        }
    """
    try:
        data = request.json
        query = data.get('query', '').strip()
        search_path = data.get('path', '/data')
        file_pattern = data.get('file_pattern', '*')
        case_sensitive = data.get('case_sensitive', False)
        max_results = data.get('max_results', 50)
        
        if not query:
            return jsonify({
                'success': False,
                'error': 'Query is required'
            }), 400
        
        # grep 명령어
        grep_cmd = ['grep', '-r']
        
        if not case_sensitive:
            grep_cmd.append('-i')
        
        grep_cmd.extend([
            '-l',  # 파일명만
            '--include', file_pattern,
            query,
            search_path
        ])
        
        result = subprocess.run(
            grep_cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        paths = [p.strip() for p in result.stdout.split('\n') if p.strip()]
        paths = paths[:max_results]
        
        results = []
        for path in paths:
            try:
                stat = os.stat(path)
                results.append({
                    'path': path,
                    'name': os.path.basename(path),
                    'size': stat.st_size,
                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat()
                })
            except:
                continue
        
        return jsonify({
            'success': True,
            'results': results,
            'count': len(results),
            'truncated': len(paths) >= max_results
        })
        
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'error': 'Search timeout (30s)'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
