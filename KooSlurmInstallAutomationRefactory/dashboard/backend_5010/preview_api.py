"""
파일 미리보기 API
텍스트, 이미지, 로그 파일 지원
"""

from flask import Blueprint, jsonify, request, send_file
import os
import mimetypes
from pathlib import Path
import subprocess

preview_bp = Blueprint('preview', __name__)

# 지원되는 텍스트 파일 확장자
TEXT_EXTENSIONS = {
    '.txt', '.log', '.py', '.sh', '.js', '.jsx', '.ts', '.tsx',
    '.json', '.xml', '.yaml', '.yml', '.md', '.conf', '.cfg',
    '.ini', '.properties', '.env', '.gitignore', '.c', '.cpp',
    '.h', '.java', '.go', '.rs', '.rb', '.php', '.html', '.css'
}

# 지원되는 이미지 파일 확장자
IMAGE_EXTENSIONS = {
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp'
}

MAX_TEXT_SIZE = 10 * 1024 * 1024  # 10MB
MAX_TAIL_LINES = 1000


def is_text_file(filepath: str) -> bool:
    """텍스트 파일 여부 확인"""
    ext = Path(filepath).suffix.lower()
    return ext in TEXT_EXTENSIONS


def is_image_file(filepath: str) -> bool:
    """이미지 파일 여부 확인"""
    ext = Path(filepath).suffix.lower()
    return ext in IMAGE_EXTENSIONS


@preview_bp.route('/api/preview/type', methods=['POST'])
def get_file_type():
    """
    파일 타입 확인
    
    Request:
        {
            "path": "/path/to/file.txt"
        }
    
    Response:
        {
            "success": true,
            "type": "text" | "image" | "unsupported",
            "mime_type": "text/plain",
            "size": 1234,
            "previewable": true
        }
    """
    try:
        data = request.json
        filepath = data.get('path')
        
        if not filepath or not os.path.exists(filepath):
            return jsonify({
                'success': False,
                'error': 'File not found'
            }), 404
        
        file_size = os.path.getsize(filepath)
        mime_type, _ = mimetypes.guess_type(filepath)
        
        file_type = 'unsupported'
        previewable = False
        
        if is_text_file(filepath):
            file_type = 'text'
            previewable = file_size <= MAX_TEXT_SIZE
        elif is_image_file(filepath):
            file_type = 'image'
            previewable = True
        
        return jsonify({
            'success': True,
            'type': file_type,
            'mime_type': mime_type,
            'size': file_size,
            'previewable': previewable,
            'too_large': file_size > MAX_TEXT_SIZE if file_type == 'text' else False
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@preview_bp.route('/api/preview/text', methods=['POST'])
def preview_text():
    """
    텍스트 파일 미리보기
    
    Request:
        {
            "path": "/path/to/file.txt",
            "lines": 100,  // optional, default all
            "tail": false  // optional, show last N lines
        }
    """
    try:
        data = request.json
        filepath = data.get('path')
        max_lines = data.get('lines')
        use_tail = data.get('tail', False)
        
        if not filepath or not os.path.exists(filepath):
            return jsonify({
                'success': False,
                'error': 'File not found'
            }), 404
        
        if not is_text_file(filepath):
            return jsonify({
                'success': False,
                'error': 'Not a text file'
            }), 400
        
        file_size = os.path.getsize(filepath)
        
        if file_size > MAX_TEXT_SIZE:
            return jsonify({
                'success': False,
                'error': f'File too large (max {MAX_TEXT_SIZE / 1024 / 1024:.0f}MB)'
            }), 400
        
        # 파일 읽기
        if use_tail and max_lines:
            # tail 명령어 사용
            try:
                result = subprocess.run(
                    ['tail', '-n', str(max_lines), filepath],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                content = result.stdout
                total_lines = int(subprocess.run(
                    ['wc', '-l', filepath],
                    capture_output=True,
                    text=True
                ).stdout.split()[0])
            except:
                # fallback
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                    content = ''.join(lines[-max_lines:] if max_lines else lines)
                    total_lines = len(lines)
        else:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                if max_lines:
                    lines = [f.readline() for _ in range(max_lines) if f.readline()]
                    content = ''.join(lines)
                else:
                    content = f.read()
            
            total_lines = content.count('\n') + 1
        
        return jsonify({
            'success': True,
            'content': content,
            'size': file_size,
            'lines': total_lines,
            'truncated': bool(max_lines and total_lines > max_lines)
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@preview_bp.route('/api/preview/image', methods=['GET'])
def preview_image():
    """
    이미지 파일 미리보기 (바이너리 전송)
    
    Query:
        ?path=/path/to/image.png
    """
    try:
        filepath = request.args.get('path')
        
        if not filepath or not os.path.exists(filepath):
            return jsonify({
                'success': False,
                'error': 'File not found'
            }), 404
        
        if not is_image_file(filepath):
            return jsonify({
                'success': False,
                'error': 'Not an image file'
            }), 400
        
        mime_type, _ = mimetypes.guess_type(filepath)
        return send_file(filepath, mimetype=mime_type or 'image/png')
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@preview_bp.route('/api/preview/tail', methods=['POST'])
def tail_file():
    """
    로그 파일 실시간 tail (마지막 N줄)
    
    Request:
        {
            "path": "/path/to/file.log",
            "lines": 100
        }
    """
    try:
        data = request.json
        filepath = data.get('path')
        lines = data.get('lines', 100)
        
        if not filepath or not os.path.exists(filepath):
            return jsonify({
                'success': False,
                'error': 'File not found'
            }), 404
        
        # tail 명령어 사용
        result = subprocess.run(
            ['tail', '-n', str(lines), filepath],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            return jsonify({
                'success': True,
                'content': result.stdout,
                'lines': lines
            })
        else:
            return jsonify({
                'success': False,
                'error': result.stderr
            }), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'error': 'Command timeout'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
