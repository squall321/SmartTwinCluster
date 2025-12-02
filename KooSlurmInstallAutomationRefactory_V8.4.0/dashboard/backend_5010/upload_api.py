"""
Job File Upload API
작업 제출 시 파일 업로드 처리
"""

from flask import Blueprint, request, jsonify
from werkzeug.utils import secure_filename
import os
import hashlib
from datetime import datetime

# Create Blueprint
upload_bp = Blueprint('upload', __name__, url_prefix='/api/jobs')

# 파일 업로드 설정
UPLOAD_BASE_DIR = '/data/results'
ALLOWED_EXTENSIONS = {'*'}  # 모든 확장자 허용
MAX_FILE_SIZE = 10 * 1024 * 1024 * 1024  # 10GB

MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

def allowed_file(filename):
    """파일 확장자 검증 (현재는 모두 허용)"""
    return True

def get_file_hash(file_path):
    """파일의 MD5 해시 계산"""
    hash_md5 = hashlib.md5()
    try:
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    except Exception as e:
        print(f"Error calculating hash: {e}")
        return None

@upload_bp.route('/upload-file', methods=['POST'])
def upload_file():
    """
    파일 업로드 API
    
    POST /api/jobs/upload-file
    Form Data:
        - file: 업로드할 파일
        - jobId: Job ID (임시 또는 실제)
    
    Returns:
        {
            "success": true,
            "fileId": "file-xxx",
            "fileName": "data.csv",
            "filePath": "/data/results/tmp-xxx/data.csv",
            "size": 12345,
            "hash": "abc123...",
            "uploadTime": "2025-10-10T12:00:00Z"
        }
    """
    
    if MOCK_MODE:
        # Mock 모드: 파일을 실제로 저장하지 않음
        file = request.files.get('file')
        job_id = request.form.get('jobId', 'tmp-mock')
        
        if not file:
            return jsonify({
                'success': False,
                'error': 'No file provided'
            }), 400
        
        filename = secure_filename(file.filename)
        file_path = f"{UPLOAD_BASE_DIR}/{job_id}/{filename}"
        
        return jsonify({
            'success': True,
            'mode': 'mock',
            'fileId': f"mock-file-{datetime.now().timestamp()}",
            'fileName': filename,
            'filePath': file_path,
            'size': 0,  # Mock에서는 크기 0
            'hash': 'mock-hash',
            'uploadTime': datetime.now().isoformat()
        })
    
    # Production 모드
    try:
        # 파일 체크
        if 'file' not in request.files:
            return jsonify({
                'success': False,
                'error': 'No file part in request'
            }), 400
        
        file = request.files['file']
        job_id = request.form.get('jobId')
        
        if not job_id:
            return jsonify({
                'success': False,
                'error': 'Job ID is required'
            }), 400
        
        if file.filename == '':
            return jsonify({
                'success': False,
                'error': 'No file selected'
            }), 400
        
        if not allowed_file(file.filename):
            return jsonify({
                'success': False,
                'error': 'File type not allowed'
            }), 400
        
        # 파일명 안전하게 변환
        filename = secure_filename(file.filename)
        
        # Job 디렉토리 생성
        job_dir = os.path.join(UPLOAD_BASE_DIR, job_id)
        os.makedirs(job_dir, exist_ok=True)
        
        # 파일 저장 경로
        file_path = os.path.join(job_dir, filename)
        
        # 파일 저장
        file.save(file_path)
        
        # 파일 정보
        file_size = os.path.getsize(file_path)
        file_hash = get_file_hash(file_path)
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'fileId': f"file-{datetime.now().timestamp()}",
            'fileName': filename,
            'filePath': file_path,
            'size': file_size,
            'hash': file_hash,
            'uploadTime': datetime.now().isoformat()
        })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@upload_bp.route('/delete-file', methods=['POST'])
def delete_file():
    """
    파일 삭제 API
    
    POST /api/jobs/delete-file
    Body:
        {
            "jobId": "tmp-xxx",
            "fileName": "data.csv"
        }
    """
    
    if MOCK_MODE:
        return jsonify({
            'success': True,
            'mode': 'mock',
            'message': 'File deleted (mock)'
        })
    
    try:
        data = request.get_json()
        job_id = data.get('jobId')
        file_name = data.get('fileName')
        
        if not job_id or not file_name:
            return jsonify({
                'success': False,
                'error': 'Job ID and file name are required'
            }), 400
        
        # 파일 경로
        file_path = os.path.join(UPLOAD_BASE_DIR, job_id, secure_filename(file_name))
        
        # 파일 존재 확인
        if not os.path.exists(file_path):
            return jsonify({
                'success': False,
                'error': 'File not found'
            }), 404
        
        # 파일 삭제
        os.remove(file_path)
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': f'File {file_name} deleted'
        })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@upload_bp.route('/list-files/<job_id>', methods=['GET'])
def list_files(job_id):
    """
    Job 디렉토리의 파일 목록 조회
    
    GET /api/jobs/list-files/<job_id>
    """
    
    if MOCK_MODE:
        return jsonify({
            'success': True,
            'mode': 'mock',
            'jobId': job_id,
            'files': []
        })
    
    try:
        job_dir = os.path.join(UPLOAD_BASE_DIR, job_id)
        
        if not os.path.exists(job_dir):
            return jsonify({
                'success': True,
                'mode': 'production',
                'jobId': job_id,
                'files': []
            })
        
        files = []
        for filename in os.listdir(job_dir):
            file_path = os.path.join(job_dir, filename)
            if os.path.isfile(file_path):
                files.append({
                    'name': filename,
                    'path': file_path,
                    'size': os.path.getsize(file_path),
                    'modifiedTime': datetime.fromtimestamp(os.path.getmtime(file_path)).isoformat()
                })
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'jobId': job_id,
            'files': files
        })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@upload_bp.route('/rename-job-dir', methods=['POST'])
def rename_job_dir():
    """
    임시 Job ID를 실제 Job ID로 변경
    
    POST /api/jobs/rename-job-dir
    Body:
        {
            "oldJobId": "tmp-xxx",
            "newJobId": "12345"
        }
    """
    
    if MOCK_MODE:
        return jsonify({
            'success': True,
            'mode': 'mock',
            'message': 'Directory renamed (mock)'
        })
    
    try:
        data = request.get_json()
        old_job_id = data.get('oldJobId')
        new_job_id = data.get('newJobId')
        
        if not old_job_id or not new_job_id:
            return jsonify({
                'success': False,
                'error': 'Both old and new job IDs are required'
            }), 400
        
        old_dir = os.path.join(UPLOAD_BASE_DIR, old_job_id)
        new_dir = os.path.join(UPLOAD_BASE_DIR, new_job_id)
        
        # 이전 디렉토리 존재 확인
        if not os.path.exists(old_dir):
            return jsonify({
                'success': False,
                'error': 'Old directory not found'
            }), 404
        
        # 새 디렉토리가 이미 존재하는 경우
        if os.path.exists(new_dir):
            return jsonify({
                'success': False,
                'error': 'New directory already exists'
            }), 400
        
        # 디렉토리 이름 변경
        os.rename(old_dir, new_dir)
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': f'Directory renamed from {old_job_id} to {new_job_id}',
            'newPath': new_dir
        })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
