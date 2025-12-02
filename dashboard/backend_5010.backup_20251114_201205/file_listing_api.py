"""
File Listing API for FileBrowser Component

서버 파일 시스템 탐색을 위한 안전한 API
"""

from flask import Blueprint, request, jsonify
import os
import stat
from datetime import datetime
from pathlib import Path
import fnmatch

# Blueprint setup
file_listing_bp = Blueprint('file_listing', __name__, url_prefix='/api/files')

# Allowed base directories (보안을 위해 허용된 경로만)
ALLOWED_BASES = [
    '/home',
    '/Data',
    '/shared',
    '/tmp',
]


def is_safe_path(path: str) -> bool:
    """Check if path is within allowed directories"""
    try:
        abs_path = os.path.abspath(path)

        # Check if path is within any allowed base
        for base in ALLOWED_BASES:
            if abs_path.startswith(base):
                return True

        return False
    except:
        return False


def get_file_metadata(filepath: str) -> dict:
    """Get file metadata"""
    try:
        file_stat = os.stat(filepath)

        return {
            'name': os.path.basename(filepath),
            'path': filepath,
            'type': 'directory' if stat.S_ISDIR(file_stat.st_mode) else 'file',
            'size': file_stat.st_size,
            'modified': datetime.fromtimestamp(file_stat.st_mtime).isoformat(),
            'permissions': oct(file_stat.st_mode)[-3:],
        }
    except Exception as e:
        return {
            'name': os.path.basename(filepath),
            'path': filepath,
            'type': 'unknown',
            'error': str(e),
        }


@file_listing_bp.route('/list', methods=['GET'])
def list_files():
    """
    List files in a directory

    Query params:
        - path: Directory path to list
        - pattern: File pattern to filter (e.g., *.k, *.py)
        - show_hidden: Show hidden files (default: false)

    Response:
        {
            "success": true,
            "path": "/home/user",
            "entries": [
                {
                    "name": "file.txt",
                    "path": "/home/user/file.txt",
                    "type": "file",
                    "size": 1024,
                    "modified": "2025-11-10T00:00:00"
                }
            ]
        }
    """
    try:
        path = request.args.get('path', '/home')
        pattern = request.args.get('pattern', '*')
        show_hidden = request.args.get('show_hidden', 'false').lower() == 'true'

        # Security check
        if not is_safe_path(path):
            return jsonify({
                'success': False,
                'error': f'Access denied: {path} is not in allowed directories',
                'allowed_bases': ALLOWED_BASES,
            }), 403

        # Check if path exists
        if not os.path.exists(path):
            return jsonify({
                'success': False,
                'error': f'Path does not exist: {path}'
            }), 404

        # Check if path is a directory
        if not os.path.isdir(path):
            return jsonify({
                'success': False,
                'error': f'Path is not a directory: {path}'
            }), 400

        entries = []

        # Add parent directory entry if not at root
        if path != '/' and is_safe_path(os.path.dirname(path)):
            entries.append({
                'name': '..',
                'path': os.path.dirname(path),
                'type': 'directory',
            })

        # List directory contents
        try:
            items = os.listdir(path)
        except PermissionError:
            return jsonify({
                'success': False,
                'error': f'Permission denied: {path}'
            }), 403

        for item in sorted(items):
            # Skip hidden files unless requested
            if item.startswith('.') and not show_hidden:
                continue

            item_path = os.path.join(path, item)

            # Get file metadata
            metadata = get_file_metadata(item_path)

            # Apply pattern filter (only to files, not directories)
            if metadata['type'] == 'file':
                if not fnmatch.fnmatch(item, pattern):
                    continue

            entries.append(metadata)

        # Sort: directories first, then files
        entries.sort(key=lambda x: (x['type'] != 'directory', x['name'].lower()))

        return jsonify({
            'success': True,
            'path': path,
            'entries': entries,
            'count': len(entries),
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@file_listing_bp.route('/info', methods=['GET'])
def file_info():
    """
    Get detailed information about a file

    Query params:
        - path: File path

    Response:
        {
            "success": true,
            "file": {
                "name": "file.txt",
                "path": "/path/to/file.txt",
                "type": "file",
                "size": 1024,
                "modified": "2025-11-10T00:00:00",
                "permissions": "644",
                "owner": "user",
                "group": "group"
            }
        }
    """
    try:
        path = request.args.get('path')

        if not path:
            return jsonify({
                'success': False,
                'error': 'Path parameter required'
            }), 400

        # Security check
        if not is_safe_path(path):
            return jsonify({
                'success': False,
                'error': f'Access denied: {path} is not in allowed directories'
            }), 403

        # Check if path exists
        if not os.path.exists(path):
            return jsonify({
                'success': False,
                'error': f'Path does not exist: {path}'
            }), 404

        # Get detailed metadata
        file_stat = os.stat(path)

        file_info = {
            'name': os.path.basename(path),
            'path': path,
            'type': 'directory' if stat.S_ISDIR(file_stat.st_mode) else 'file',
            'size': file_stat.st_size,
            'modified': datetime.fromtimestamp(file_stat.st_mtime).isoformat(),
            'created': datetime.fromtimestamp(file_stat.st_ctime).isoformat(),
            'accessed': datetime.fromtimestamp(file_stat.st_atime).isoformat(),
            'permissions': oct(file_stat.st_mode)[-3:],
            'uid': file_stat.st_uid,
            'gid': file_stat.st_gid,
        }

        # Try to get owner and group names
        try:
            import pwd
            import grp
            file_info['owner'] = pwd.getpwuid(file_stat.st_uid).pw_name
            file_info['group'] = grp.getgrgid(file_stat.st_gid).gr_name
        except:
            pass

        return jsonify({
            'success': True,
            'file': file_info,
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@file_listing_bp.route('/search', methods=['GET'])
def search_files():
    """
    Search files in a directory

    Query params:
        - path: Directory to search in
        - query: Search query (filename contains)
        - pattern: File pattern (e.g., *.k)
        - recursive: Search subdirectories (default: false)
        - max_results: Maximum results to return (default: 100)

    Response:
        {
            "success": true,
            "results": [...],
            "count": 42
        }
    """
    try:
        path = request.args.get('path', '/home')
        query = request.args.get('query', '')
        pattern = request.args.get('pattern', '*')
        recursive = request.args.get('recursive', 'false').lower() == 'true'
        max_results = int(request.args.get('max_results', '100'))

        # Security check
        if not is_safe_path(path):
            return jsonify({
                'success': False,
                'error': f'Access denied: {path} is not in allowed directories'
            }), 403

        results = []

        if recursive:
            # Recursive search
            for root, dirs, files in os.walk(path):
                # Limit depth to prevent performance issues
                if len(results) >= max_results:
                    break

                for filename in files:
                    if len(results) >= max_results:
                        break

                    # Apply pattern and query filters
                    if not fnmatch.fnmatch(filename, pattern):
                        continue

                    if query and query.lower() not in filename.lower():
                        continue

                    filepath = os.path.join(root, filename)
                    results.append(get_file_metadata(filepath))
        else:
            # Non-recursive search
            try:
                items = os.listdir(path)

                for item in items:
                    if len(results) >= max_results:
                        break

                    item_path = os.path.join(path, item)

                    if not os.path.isfile(item_path):
                        continue

                    # Apply pattern and query filters
                    if not fnmatch.fnmatch(item, pattern):
                        continue

                    if query and query.lower() not in item.lower():
                        continue

                    results.append(get_file_metadata(item_path))
            except PermissionError:
                return jsonify({
                    'success': False,
                    'error': f'Permission denied: {path}'
                }), 403

        return jsonify({
            'success': True,
            'results': results,
            'count': len(results),
            'truncated': len(results) >= max_results,
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# Health check
@file_listing_bp.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'file_listing_api',
        'timestamp': datetime.now().isoformat(),
        'allowed_bases': ALLOWED_BASES,
    })


def register_blueprint(app):
    """Register blueprint with Flask app"""
    app.register_blueprint(file_listing_bp)
