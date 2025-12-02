"""
파일 업로드/다운로드 핸들러
대용량 파일 지원, 청크 전송, 진행률 추적
"""

import os
import shutil
import hashlib
import tempfile
from pathlib import Path
from typing import Optional, Dict, BinaryIO
from werkzeug.utils import secure_filename
from flask import Response, stream_with_context
import subprocess
import logging

logger = logging.getLogger(__name__)

# 설정
MAX_CHUNK_SIZE = 8 * 1024 * 1024  # 8MB chunks
UPLOAD_TEMP_DIR = '/tmp/dashboard_uploads'
ALLOWED_EXTENSIONS = {'txt', 'pdf', 'png', 'jpg', 'jpeg', 'gif', 'zip', 
                      'tar', 'gz', 'py', 'sh', 'csv', 'json', 'log'}

# 임시 디렉토리 생성
os.makedirs(UPLOAD_TEMP_DIR, exist_ok=True)


def allowed_file(filename: str) -> bool:
    """허용된 파일 확장자 체크"""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def generate_file_id(filename: str) -> str:
    """파일 고유 ID 생성"""
    timestamp = str(int(os.times().elapsed * 1000))
    return hashlib.md5(f"{filename}{timestamp}".encode()).hexdigest()


class ChunkedUploadHandler:
    """청크 단위 업로드 핸들러"""
    
    def __init__(self, upload_id: str, filename: str, total_size: int):
        self.upload_id = upload_id
        self.filename = secure_filename(filename)
        self.total_size = total_size
        self.temp_path = os.path.join(UPLOAD_TEMP_DIR, f"{upload_id}_{self.filename}")
        self.chunks_received = 0
        self.bytes_received = 0
        
    def write_chunk(self, chunk_data: bytes, chunk_index: int) -> Dict:
        """청크 데이터 쓰기"""
        try:
            mode = 'ab' if os.path.exists(self.temp_path) else 'wb'
            
            with open(self.temp_path, mode) as f:
                f.write(chunk_data)
            
            self.chunks_received += 1
            self.bytes_received += len(chunk_data)
            
            progress = (self.bytes_received / self.total_size) * 100 if self.total_size > 0 else 0
            
            return {
                'success': True,
                'chunk_index': chunk_index,
                'chunks_received': self.chunks_received,
                'bytes_received': self.bytes_received,
                'progress': round(progress, 2),
                'completed': self.bytes_received >= self.total_size
            }
        except Exception as e:
            logger.error(f"Failed to write chunk {chunk_index}: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def finalize(self, destination: str) -> Dict:
        """업로드 완료 처리"""
        try:
            # 대상 디렉토리 생성
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            
            # 임시 파일을 최종 위치로 이동
            shutil.move(self.temp_path, destination)
            
            # 파일 정보 반환
            file_stats = os.stat(destination)
            
            return {
                'success': True,
                'filename': self.filename,
                'path': destination,
                'size': file_stats.st_size,
                'chunks_total': self.chunks_received,
                'bytes_total': self.bytes_received
            }
        except Exception as e:
            logger.error(f"Failed to finalize upload: {e}")
            # 임시 파일 정리
            if os.path.exists(self.temp_path):
                os.remove(self.temp_path)
            return {
                'success': False,
                'error': str(e)
            }
    
    def cleanup(self):
        """임시 파일 정리"""
        if os.path.exists(self.temp_path):
            try:
                os.remove(self.temp_path)
            except Exception as e:
                logger.warning(f"Failed to cleanup temp file: {e}")


class FileDownloadHandler:
    """파일 다운로드 핸들러"""
    
    @staticmethod
    def stream_file(file_path: str, chunk_size: int = MAX_CHUNK_SIZE):
        """파일 스트리밍 생성기"""
        try:
            with open(file_path, 'rb') as f:
                while True:
                    chunk = f.read(chunk_size)
                    if not chunk:
                        break
                    yield chunk
        except Exception as e:
            logger.error(f"Error streaming file {file_path}: {e}")
            raise
    
    @staticmethod
    def create_download_response(file_path: str, filename: Optional[str] = None) -> Response:
        """다운로드 응답 생성"""
        if not os.path.exists(file_path):
            return Response("File not found", status=404)
        
        if not filename:
            filename = os.path.basename(file_path)
        
        file_size = os.path.getsize(file_path)
        
        response = Response(
            stream_with_context(FileDownloadHandler.stream_file(file_path)),
            mimetype='application/octet-stream'
        )
        
        response.headers['Content-Disposition'] = f'attachment; filename="{filename}"'
        response.headers['Content-Length'] = str(file_size)
        response.headers['X-File-Size'] = str(file_size)
        
        return response


class RemoteFileTransfer:
    """원격 노드 파일 전송 (SCP/rsync)"""
    
    @staticmethod
    def upload_to_node(local_path: str, node: str, remote_path: str, 
                       use_rsync: bool = True) -> Dict:
        """로컬 → 원격 노드 업로드"""
        try:
            if use_rsync:
                # rsync로 전송 (재개 가능, 진행률 표시)
                cmd = [
                    'rsync',
                    '-avz',
                    '--progress',
                    local_path,
                    f'{node}:{remote_path}'
                ]
            else:
                # scp로 전송
                cmd = [
                    'scp',
                    '-r',
                    local_path,
                    f'{node}:{remote_path}'
                ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300  # 5분 타임아웃
            )
            
            if result.returncode == 0:
                return {
                    'success': True,
                    'node': node,
                    'local_path': local_path,
                    'remote_path': remote_path,
                    'output': result.stdout
                }
            else:
                return {
                    'success': False,
                    'error': result.stderr,
                    'node': node
                }
                
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'error': 'Transfer timeout (5 minutes)',
                'node': node
            }
        except Exception as e:
            logger.error(f"Upload to {node} failed: {e}")
            return {
                'success': False,
                'error': str(e),
                'node': node
            }
    
    @staticmethod
    def download_from_node(node: str, remote_path: str, local_path: str,
                          use_rsync: bool = True) -> Dict:
        """원격 노드 → 로컬 다운로드"""
        try:
            # 로컬 디렉토리 생성
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            
            if use_rsync:
                cmd = [
                    'rsync',
                    '-avz',
                    '--progress',
                    f'{node}:{remote_path}',
                    local_path
                ]
            else:
                cmd = [
                    'scp',
                    '-r',
                    f'{node}:{remote_path}',
                    local_path
                ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            if result.returncode == 0:
                return {
                    'success': True,
                    'node': node,
                    'remote_path': remote_path,
                    'local_path': local_path,
                    'size': os.path.getsize(local_path) if os.path.isfile(local_path) else 0
                }
            else:
                return {
                    'success': False,
                    'error': result.stderr,
                    'node': node
                }
                
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'error': 'Download timeout (5 minutes)',
                'node': node
            }
        except Exception as e:
            logger.error(f"Download from {node} failed: {e}")
            return {
                'success': False,
                'error': str(e),
                'node': node
            }
    
    @staticmethod
    def get_transfer_progress(node: str, pid: int) -> Dict:
        """전송 진행률 조회"""
        try:
            # rsync 프로세스 상태 확인
            cmd = f"ssh {node} 'ps -p {pid} -o pid,pcpu,rss,etime'"
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode == 0:
                return {
                    'success': True,
                    'running': True,
                    'details': result.stdout
                }
            else:
                return {
                    'success': True,
                    'running': False
                }
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }


# 전역 업로드 세션 관리
_upload_sessions: Dict[str, ChunkedUploadHandler] = {}


def get_upload_session(upload_id: str) -> Optional[ChunkedUploadHandler]:
    """업로드 세션 조회"""
    return _upload_sessions.get(upload_id)


def create_upload_session(filename: str, total_size: int) -> str:
    """업로드 세션 생성"""
    upload_id = generate_file_id(filename)
    handler = ChunkedUploadHandler(upload_id, filename, total_size)
    _upload_sessions[upload_id] = handler
    return upload_id


def cleanup_upload_session(upload_id: str):
    """업로드 세션 정리"""
    if upload_id in _upload_sessions:
        handler = _upload_sessions[upload_id]
        handler.cleanup()
        del _upload_sessions[upload_id]


def cleanup_old_uploads(max_age_hours: int = 24):
    """오래된 임시 파일 정리"""
    try:
        import time
        current_time = time.time()
        
        for filename in os.listdir(UPLOAD_TEMP_DIR):
            filepath = os.path.join(UPLOAD_TEMP_DIR, filename)
            if os.path.isfile(filepath):
                age_hours = (current_time - os.path.getmtime(filepath)) / 3600
                if age_hours > max_age_hours:
                    os.remove(filepath)
                    logger.info(f"Cleaned up old upload: {filename}")
    except Exception as e:
        logger.warning(f"Failed to cleanup old uploads: {e}")
