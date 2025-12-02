"""
Storage Management Utilities
파일 시스템 작업을 위한 유틸리티 함수들
"""

import os
import shutil
import subprocess
from datetime import datetime
from typing import List, Dict, Optional, Tuple
import pwd
import grp
import stat

def get_disk_usage(path: str) -> Dict:
    """디스크 사용량 조회"""
    try:
        stat_info = os.statvfs(path)
        total = stat_info.f_blocks * stat_info.f_frsize
        free = stat_info.f_bfree * stat_info.f_frsize
        used = total - free
        usage_percent = (used / total * 100) if total > 0 else 0
        
        return {
            'total': format_size(total),
            'totalBytes': total,
            'used': format_size(used),
            'usedBytes': used,
            'available': format_size(free),
            'availableBytes': free,
            'usagePercent': round(usage_percent, 1)
        }
    except Exception as e:
        print(f"Error getting disk usage for {path}: {e}")
        return {
            'total': '0 B',
            'totalBytes': 0,
            'used': '0 B',
            'usedBytes': 0,
            'available': '0 B',
            'availableBytes': 0,
            'usagePercent': 0
        }

def format_size(bytes_size: int) -> str:
    """바이트를 읽기 쉬운 형식으로 변환"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB', 'PB']:
        if bytes_size < 1024.0:
            if unit == 'B':
                return f"{int(bytes_size)} {unit}"
            return f"{bytes_size:.1f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.1f} PB"

def get_file_info(path: str) -> Optional[Dict]:
    """파일/디렉토리 정보 조회"""
    try:
        if not os.path.exists(path):
            return None
            
        stat_info = os.stat(path)
        
        # 소유자 및 그룹 정보
        try:
            owner = pwd.getpwuid(stat_info.st_uid).pw_name
        except:
            owner = str(stat_info.st_uid)
        
        try:
            group = grp.getgrgid(stat_info.st_gid).gr_name
        except:
            group = str(stat_info.st_gid)
        
        # 권한
        permissions = stat.filemode(stat_info.st_mode)
        
        # MIME 타입 추측
        mime_type = None
        extension = None
        if os.path.isfile(path):
            extension = os.path.splitext(path)[1]
            mime_type = guess_mime_type(extension)
        
        return {
            'id': f"item-{abs(hash(path))}",
            'name': os.path.basename(path),
            'path': path,
            'type': 'directory' if os.path.isdir(path) else 'file',
            'size': format_size(stat_info.st_size),
            'sizeBytes': stat_info.st_size,
            'permissions': permissions,
            'owner': owner,
            'group': group,
            'modifiedAt': datetime.fromtimestamp(stat_info.st_mtime).isoformat(),
            'isSymlink': os.path.islink(path),
            'mimeType': mime_type,
            'extension': extension
        }
    except Exception as e:
        print(f"Error getting file info for {path}: {e}")
        return None

def guess_mime_type(extension: str) -> Optional[str]:
    """파일 확장자로 MIME 타입 추측"""
    mime_types = {
        '.txt': 'text/plain',
        '.log': 'text/plain',
        '.md': 'text/markdown',
        '.py': 'text/x-python',
        '.js': 'text/javascript',
        '.jsx': 'text/javascript',
        '.ts': 'text/typescript',
        '.tsx': 'text/typescript',
        '.cpp': 'text/x-c++src',
        '.c': 'text/x-csrc',
        '.h': 'text/x-chdr',
        '.java': 'text/x-java',
        '.csv': 'text/csv',
        '.json': 'application/json',
        '.xml': 'application/xml',
        '.yaml': 'application/yaml',
        '.yml': 'application/yaml',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.gif': 'image/gif',
        '.svg': 'image/svg+xml',
        '.pdf': 'application/pdf',
        '.zip': 'application/zip',
        '.tar': 'application/x-tar',
        '.gz': 'application/gzip',
        '.rar': 'application/x-rar',
        '.mp3': 'audio/mpeg',
        '.wav': 'audio/wav',
        '.mp4': 'video/mp4',
        '.avi': 'video/x-msvideo',
        '.h5': 'application/x-hdf',
        '.dat': 'application/octet-stream',
    }
    return mime_types.get(extension.lower())

def list_directory(path: str, include_hidden: bool = False) -> List[Dict]:
    """디렉토리 내용 목록"""
    try:
        if not os.path.exists(path) or not os.path.isdir(path):
            return []
        
        items = []
        for entry in os.listdir(path):
            if not include_hidden and entry.startswith('.'):
                continue
            
            full_path = os.path.join(path, entry)
            file_info = get_file_info(full_path)
            if file_info:
                items.append(file_info)
        
        return items
    except PermissionError:
        print(f"Permission denied: {path}")
        return []
    except Exception as e:
        print(f"Error listing directory {path}: {e}")
        return []

def count_files_recursive(path: str) -> Tuple[int, int]:
    """재귀적으로 파일 및 디렉토리 수 계산"""
    try:
        if not os.path.exists(path):
            return 0, 0
        
        if os.path.isfile(path):
            return 1, 0
        
        file_count = 0
        dir_count = 0
        
        for root, dirs, files in os.walk(path):
            file_count += len(files)
            dir_count += len(dirs)
        
        return file_count, dir_count
    except Exception as e:
        print(f"Error counting files in {path}: {e}")
        return 0, 0

def get_directory_size(path: str) -> int:
    """디렉토리 전체 크기 계산 (바이트)"""
    try:
        if not os.path.exists(path):
            return 0
        
        if os.path.isfile(path):
            return os.path.getsize(path)
        
        total_size = 0
        for root, dirs, files in os.walk(path):
            for file in files:
                file_path = os.path.join(root, file)
                try:
                    if not os.path.islink(file_path):
                        total_size += os.path.getsize(file_path)
                except:
                    pass
        
        return total_size
    except Exception as e:
        print(f"Error calculating directory size for {path}: {e}")
        return 0

def safe_path_join(base_path: str, relative_path: str) -> Optional[str]:
    """안전한 경로 결합 (경로 순회 공격 방지)"""
    try:
        # 절대 경로로 변환
        base_path = os.path.abspath(base_path)
        full_path = os.path.abspath(os.path.join(base_path, relative_path))
        
        # 결과 경로가 base_path 안에 있는지 확인
        if not full_path.startswith(base_path):
            print(f"Security: Path traversal attempt blocked: {relative_path}")
            return None
        
        return full_path
    except Exception as e:
        print(f"Error in safe_path_join: {e}")
        return None

def is_path_accessible(path: str, check_read: bool = True, check_write: bool = False) -> bool:
    """경로 접근 가능 여부 확인"""
    try:
        if not os.path.exists(path):
            return False
        
        if check_read and not os.access(path, os.R_OK):
            return False
        
        if check_write and not os.access(path, os.W_OK):
            return False
        
        return True
    except:
        return False

def search_files(base_path: str, query: str, max_results: int = 100) -> List[Dict]:
    """파일 검색"""
    try:
        if not os.path.exists(base_path) or not os.path.isdir(base_path):
            return []
        
        results = []
        query_lower = query.lower()
        
        for root, dirs, files in os.walk(base_path):
            # 디렉토리 검색
            for dir_name in dirs:
                if query_lower in dir_name.lower():
                    full_path = os.path.join(root, dir_name)
                    file_info = get_file_info(full_path)
                    if file_info:
                        results.append(file_info)
                        if len(results) >= max_results:
                            return results
            
            # 파일 검색
            for file_name in files:
                if query_lower in file_name.lower():
                    full_path = os.path.join(root, file_name)
                    file_info = get_file_info(full_path)
                    if file_info:
                        results.append(file_info)
                        if len(results) >= max_results:
                            return results
        
        return results
    except Exception as e:
        print(f"Error searching files in {base_path}: {e}")
        return []

def get_slurm_nodes() -> List[str]:
    """Slurm 노드 목록 조회"""
    try:
        result = subprocess.run(
            ['sinfo', '-N', '-h', '-o', '%N'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            nodes = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
            return nodes
        return []
    except Exception as e:
        print(f"Error getting slurm nodes: {e}")
        return []

def run_remote_command(node: str, command: str, timeout: int = 10) -> Optional[str]:
    """원격 노드에서 명령 실행"""
    try:
        ssh_command = ['ssh', '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=5', node, command]
        result = subprocess.run(
            ssh_command,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        if result.returncode == 0:
            return result.stdout
        print(f"Remote command failed on {node}: {result.stderr}")
        return None
    except Exception as e:
        print(f"Error running remote command on {node}: {e}")
        return None
