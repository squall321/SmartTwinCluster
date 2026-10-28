"""
Job Logs API
작업 로그 및 결과 파일 조회 API

Phase 1: 로그 조회 및 파일 관리
"""

import os
import json
import sqlite3
import subprocess
from datetime import datetime, timedelta
from functools import wraps
import jwt
from flask import Blueprint, request, jsonify, send_file, Response, g
from middleware.jwt_middleware import jwt_required, JWT_SECRET_KEY, JWT_ALGORITHM

# 제출 시 기록되는 result_dir 의 권위 조회용 DB (job_submit_api 와 동일 경로)
DATABASE_PATH = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')

# 단기 다운로드 티켓 — window.open 은 Authorization 헤더를 못 실으므로 download 라우트만 ?ticket= 을 받는다.
# 로그인 JWT 와 다른 키로 서명해, URL(접근 로그)에 남은 티켓이 다른 API 의 Bearer 로 쓰이지 못하게 한다.
DOWNLOAD_TICKET_SCOPE = 'job-download'
DOWNLOAD_TICKET_TTL_SEC = 120
_DOWNLOAD_TICKET_KEY = JWT_SECRET_KEY + ':' + DOWNLOAD_TICKET_SCOPE


def _db_job_owner(job_id: str):
    """job_submissions 에 기록된 제출자(user_id) 반환(없으면 None)."""
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        cur = conn.cursor()
        cur.execute(
            "SELECT user_id FROM job_submissions WHERE job_id=? ORDER BY id DESC LIMIT 1",
            (str(job_id),))
        row = cur.fetchone()
        conn.close()
        if row and row[0]:
            return row[0]
    except Exception as e:
        print(f"⚠️  owner DB lookup failed for job {job_id}: {e}")
    return None


def caller_owns_job(job_id: str) -> bool:
    """admin 은 모든 잡, 그 밖엔 제출 기록의 user_id 가 호출자 이름과 같을 때만.
    user_id 는 제출 때 _sanitize_web_user 를 지난 이름이라(정상 이름은 그대로, 아니면 'anonymous')
    그대로 비교한다. 'anonymous' 는 여러 사람이 섞이는 키라 admin 만 연다."""
    user = g.get('user') or {}
    if user.get('role') == 'admin':
        return True
    owner = _db_job_owner(job_id)
    return bool(owner) and owner != 'anonymous' and owner == user.get('username')


def job_owner_required(f):
    """잡 로그·파일 라우트의 소유 검사 — 인증 데코레이터 아래에 둔다."""
    @wraps(f)
    def wrapper(job_id, *args, **kwargs):
        if not caller_owns_job(job_id):
            return jsonify({'success': False, 'error': f'Forbidden — job {job_id} 는 호출자의 잡이 아닙니다'}), 403
        return f(job_id, *args, **kwargs)
    return wrapper


def jwt_or_download_ticket(f):
    """download·download-all 전용 인증: Authorization 헤더가 없고 ?ticket= 이 있으면 티켓으로, 아니면 jwt_required."""
    authed = jwt_required(f)

    @wraps(f)
    def wrapper(job_id, *args, **kwargs):
        ticket = request.args.get('ticket')
        if ticket and not request.headers.get('Authorization'):
            try:
                claims = jwt.decode(ticket, _DOWNLOAD_TICKET_KEY, algorithms=[JWT_ALGORITHM])
            except jwt.InvalidTokenError:
                return jsonify({'success': False, 'error': 'Invalid or expired download ticket'}), 401
            if claims.get('scope') != DOWNLOAD_TICKET_SCOPE or str(claims.get('job_id')) != str(job_id):
                return jsonify({'success': False, 'error': 'Download ticket is not for this job'}), 401
            g.user = {'username': claims.get('sub'), 'role': claims.get('role', 'user'),
                      'email': None, 'groups': [], 'permissions': []}
            return f(job_id, *args, **kwargs)
        return authed(job_id, *args, **kwargs)
    return wrapper


def _within(path: str, base: str) -> bool:
    """path 가 base 자신이거나 그 아래인가(realpath, 구분자 포함 비교 — A_12 가 A_123 을 품지 않게)."""
    real, real_base = os.path.realpath(path), os.path.realpath(base)
    return real == real_base or real.startswith(real_base + os.sep)


def _db_result_dir(job_id: str):
    """job_submissions 에 기록된 result_dir 반환(없으면 None).
    제출 경로(Path A/B/전각도)가 결과 위치를 권위 있게 남긴 값 — sacct WorkDir 폴백보다 정확."""
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        cur = conn.cursor()
        cur.execute(
            "SELECT result_dir FROM job_submissions WHERE job_id=? ORDER BY id DESC LIMIT 1",
            (str(job_id),))
        row = cur.fetchone()
        conn.close()
        if row and row[0]:
            return row[0]
    except Exception as e:
        print(f"⚠️  result_dir DB lookup failed for job {job_id}: {e}")
    return None

# Slurm 명령어 경로
from slurm_commands import get_sacct, get_scontrol

job_logs_bp = Blueprint('job_logs', __name__, url_prefix='/api/jobs')

# 로그 및 작업 디렉토리 경로
# 공유 스토리지 베이스 — 제출(job_submit/lsdyna/app.py)이 쓰는 위치와 동일 규칙.
# 운영은 /shared(=GlusterFS), gluster 미마운트 환경은 SHARED_BASE(예: /data).
SHARED_BASE = os.getenv('SHARED_BASE', '/shared')
LOGS_DIR = os.getenv('JOB_LOGS_DIR', os.path.join(SHARED_BASE, 'logs'))
JOBS_DIR = os.getenv('JOB_WORK_DIR', os.path.join(SHARED_BASE, 'jobs'))

# 대체 경로 (다른 마운트 규칙/레거시 fallback)
ALT_LOGS_DIR = '/mnt/gluster/logs'
ALT_JOBS_DIR = '/mnt/gluster/jobs'


def get_log_path(job_id: str, log_type: str = 'out') -> str:
    """
    Job 로그 파일 경로 반환

    Args:
        job_id: Slurm Job ID
        log_type: 'out' 또는 'err'

    Returns:
        로그 파일 경로 (존재하면)
    """
    # 우선순위: LOGS_DIR -> ALT_LOGS_DIR -> sacct에서 조회
    ext = 'out' if log_type == 'out' else 'err'

    # 1. 기본 경로 확인
    path = os.path.join(LOGS_DIR, f"{job_id}.{ext}")
    if os.path.exists(path):
        return path

    # 2. 대체 경로 확인
    path = os.path.join(ALT_LOGS_DIR, f"{job_id}.{ext}")
    if os.path.exists(path):
        return path

    # 3. Slurm 기본 출력 패턴 확인 (slurm-{job_id}.out)
    for base_dir in [LOGS_DIR, ALT_LOGS_DIR, '/home', '/tmp']:
        path = os.path.join(base_dir, f"slurm-{job_id}.{ext}")
        if os.path.exists(path):
            return path

    return None


def get_job_dir(job_id: str) -> str:
    """
    Job 작업 디렉토리 경로 반환

    Args:
        job_id: Slurm Job ID

    Returns:
        작업 디렉토리 경로 (존재하면)
    """
    # 0. DB 에 기록된 result_dir 우선(권위) — 제출 시점에 정확히 남긴 결과 위치.
    #    Path A(/data/single/...), 전각도(<업로드>/output), Path B(SHARED_BASE/jobs/<id>) 공통.
    rd = _db_result_dir(job_id)
    if rd and os.path.isdir(rd):
        return rd

    # 1. 기본 경로 확인
    path = os.path.join(JOBS_DIR, job_id)
    if os.path.exists(path):
        return path

    # 2. 대체 경로 확인
    path = os.path.join(ALT_JOBS_DIR, job_id)
    if os.path.exists(path):
        return path

    # 3. sacct에서 WorkDir 조회
    try:
        result = get_sacct(
            '-j', job_id, '-X', '-n', '-P',
            '--format=WorkDir',
            timeout=5
        )
        work_dir = result.stdout.strip().split('\n')[0].strip()
        if work_dir and os.path.isdir(work_dir):
            return work_dir
    except Exception as e:
        print(f"⚠️  sacct WorkDir lookup failed for job {job_id}: {e}")

    return None


def _resolve_job_file(job_id: str, file_path: str):
    """path 쿼리 → (실제 경로 또는 None, 거부 여부). stdout/stderr 는 잡 id 로 찾은 로그,
    그 밖은 잡 폴더 기준 상대 경로이고 폴더 밖(../, 절대경로, 바깥을 가리키는 심링크)은 거부한다."""
    if file_path in ('stdout', 'out'):
        return get_log_path(job_id, 'out'), False
    if file_path in ('stderr', 'err'):
        return get_log_path(job_id, 'err'), False
    job_dir = get_job_dir(job_id)
    if not job_dir:
        return None, False
    actual_path = os.path.join(job_dir, file_path)
    if not _within(actual_path, job_dir):
        return None, True
    return actual_path, False


# 파일 열람 불가 확장자 (바이너리/대용량)
NON_VIEWABLE_EXTENSIONS = {
    '.sif', '.tar', '.gz', '.zip', '.bz2', '.xz', '.7z',
    '.bin', '.o', '.so', '.a', '.dll', '.exe',
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff', '.svg',
    '.mp4', '.avi', '.mov', '.mkv', '.mp3', '.wav',
    '.h5', '.hdf5', '.nc', '.npy', '.npz',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx',
    '.d3plot', '.binout',
}

# d3plot 패턴 (d3plot01, d3plot02 등)
def is_viewable_file(filename: str, size: int) -> bool:
    """파일이 웹에서 열람 가능한지 확인"""
    if size > 10 * 1024 * 1024:  # 10MB 초과
        return False
    name_lower = filename.lower()
    if 'd3plot' in name_lower or 'binout' in name_lower:
        return False
    _, ext = os.path.splitext(name_lower)
    return ext not in NON_VIEWABLE_EXTENSIONS


def get_job_info_from_slurm(job_id: str) -> dict:
    """
    Slurm에서 Job 정보 조회

    Args:
        job_id: Slurm Job ID

    Returns:
        Job 정보 딕셔너리
    """
    try:
        result = get_sacct(
            '-j', job_id,
            '-X', '-n', '-P',
            '--format=JobID,JobName,User,State,ExitCode,Start,End,Elapsed,Partition,NNodes,NCPUs,ReqMem',
            timeout=5
        )

        if result.stdout.strip():
            parts = result.stdout.strip().split('|')
            if len(parts) >= 8:
                return {
                    'jobId': parts[0],
                    'jobName': parts[1],
                    'user': parts[2],
                    'state': parts[3],
                    'exitCode': parts[4],
                    'startTime': parts[5],
                    'endTime': parts[6],
                    'elapsed': parts[7],
                    'partition': parts[8] if len(parts) > 8 else 'N/A',
                    'nodes': parts[9] if len(parts) > 9 else '1',
                    'cpus': parts[10] if len(parts) > 10 else '1',
                    'memory': parts[11] if len(parts) > 11 else 'N/A'
                }
    except Exception as e:
        print(f"⚠️  Error getting job info from Slurm: {e}")

    return None


@job_logs_bp.route('/<job_id>/info', methods=['GET'])
@jwt_required
@job_owner_required
def get_job_info(job_id: str):
    """
    Job 상세 정보 조회

    Returns:
        {
            "success": true,
            "job": {
                "jobId": "123",
                "jobName": "my_job",
                "state": "COMPLETED",
                "exitCode": "0:0",
                ...
            }
        }
    """
    try:
        job_info = get_job_info_from_slurm(job_id)

        if not job_info:
            return jsonify({
                'success': False,
                'error': f'Job {job_id} not found'
            }), 404

        # 로그 파일 존재 여부 추가
        job_info['hasStdout'] = get_log_path(job_id, 'out') is not None
        job_info['hasStderr'] = get_log_path(job_id, 'err') is not None

        # 작업 디렉토리 존재 여부
        job_dir = get_job_dir(job_id)
        job_info['hasWorkDir'] = job_dir is not None

        return jsonify({
            'success': True,
            'job': job_info
        })

    except Exception as e:
        print(f"❌ Error getting job info: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@job_logs_bp.route('/<job_id>/logs', methods=['GET'])
@jwt_required
@job_owner_required
def get_job_logs(job_id: str):
    """
    Job 로그 조회 (stdout)

    Query params:
        - type: 'out' 또는 'err' (기본: 'out')
        - tail: 마지막 N줄만 반환 (기본: 전체)
        - offset: 시작 줄 번호 (기본: 0)

    Returns:
        {
            "success": true,
            "jobId": "123",
            "logType": "out",
            "content": "...",
            "lines": 100,
            "totalLines": 500,
            "truncated": false
        }
    """
    try:
        log_type = request.args.get('type', 'out')
        tail_lines = request.args.get('tail', type=int)
        offset = request.args.get('offset', 0, type=int)

        # 로그 파일 경로 찾기
        log_path = get_log_path(job_id, log_type)

        if not log_path:
            # 로그 파일이 없는 경우 - Job 상태 확인
            job_info = get_job_info_from_slurm(job_id)

            if not job_info:
                return jsonify({
                    'success': False,
                    'error': f'Job {job_id} not found'
                }), 404

            # Job은 있지만 로그 파일이 없음
            state = job_info.get('state', 'UNKNOWN')

            if state in ['PENDING', 'RUNNING']:
                return jsonify({
                    'success': True,
                    'jobId': job_id,
                    'logType': log_type,
                    'content': f'[Job is {state} - logs not yet available]\n',
                    'lines': 1,
                    'totalLines': 1,
                    'truncated': False,
                    'state': state
                })
            else:
                return jsonify({
                    'success': True,
                    'jobId': job_id,
                    'logType': log_type,
                    'content': f'[Log file not found for job {job_id}]\n'
                              f'[Job state: {state}]\n'
                              f'[Expected path: {LOGS_DIR}/{job_id}.{log_type}]\n',
                    'lines': 3,
                    'totalLines': 3,
                    'truncated': False,
                    'state': state
                })

        # 파일 읽기
        with open(log_path, 'r', errors='replace') as f:
            lines = f.readlines()

        total_lines = len(lines)

        # tail 처리
        if tail_lines:
            lines = lines[-tail_lines:]
        elif offset > 0:
            lines = lines[offset:]

        content = ''.join(lines)

        # 너무 큰 경우 truncate (1MB 제한)
        max_size = 1024 * 1024
        truncated = len(content) > max_size
        if truncated:
            content = content[:max_size] + '\n\n[... truncated ...]\n'

        return jsonify({
            'success': True,
            'jobId': job_id,
            'logType': log_type,
            'content': content,
            'lines': len(lines),
            'totalLines': total_lines,
            'truncated': truncated,
            'logPath': log_path
        })

    except Exception as e:
        print(f"❌ Error reading job logs: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@job_logs_bp.route('/<job_id>/logs/tail', methods=['GET'])
@jwt_required
@job_owner_required
def tail_job_logs(job_id: str):
    """
    실시간 로그 조회 (tail -f 방식)

    Query params:
        - lines: 반환할 줄 수 (기본: 100)
        - type: 'out' 또는 'err' (기본: 'out')

    Returns:
        {
            "success": true,
            "jobId": "123",
            "content": "...",
            "lines": 100
        }
    """
    try:
        lines_count = request.args.get('lines', 100, type=int)
        log_type = request.args.get('type', 'out')

        log_path = get_log_path(job_id, log_type)

        if not log_path:
            return jsonify({
                'success': False,
                'error': f'Log file not found for job {job_id}'
            }), 404

        # tail 명령 사용
        try:
            result = subprocess.run(
                ['tail', '-n', str(lines_count), log_path],
                capture_output=True,
                text=True,
                timeout=5
            )
            content = result.stdout
        except:
            # fallback: Python으로 읽기
            with open(log_path, 'r', errors='replace') as f:
                all_lines = f.readlines()
                content = ''.join(all_lines[-lines_count:])

        return jsonify({
            'success': True,
            'jobId': job_id,
            'logType': log_type,
            'content': content,
            'lines': lines_count
        })

    except Exception as e:
        print(f"❌ Error tailing job logs: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@job_logs_bp.route('/<job_id>/files', methods=['GET'])
@jwt_required
@job_owner_required
def list_job_files(job_id: str):
    """
    Job 작업 디렉토리의 파일 목록 조회

    Returns:
        {
            "success": true,
            "jobId": "123",
            "workDir": "/shared/jobs/123",
            "files": [
                {
                    "name": "result.csv",
                    "path": "results/result.csv",
                    "size": 12345,
                    "modified": "2025-01-08T12:00:00",
                    "type": "file"
                },
                ...
            ]
        }
    """
    try:
        job_dir = get_job_dir(job_id)

        # 작업 디렉토리가 없으면 로그 파일만 반환
        files = []

        # 1. 로그 파일 추가
        stdout_path = get_log_path(job_id, 'out')
        stderr_path = get_log_path(job_id, 'err')

        if stdout_path and os.path.exists(stdout_path):
            stat = os.stat(stdout_path)
            files.append({
                'name': os.path.basename(stdout_path),
                'path': stdout_path,
                'size': stat.st_size,
                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                'type': 'log',
                'logType': 'stdout',
                'isViewable': True
            })

        if stderr_path and os.path.exists(stderr_path):
            stat = os.stat(stderr_path)
            files.append({
                'name': os.path.basename(stderr_path),
                'path': stderr_path,
                'size': stat.st_size,
                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                'type': 'log',
                'logType': 'stderr',
                'isViewable': True
            })

        # 2. 작업 디렉토리 파일 추가
        if job_dir and os.path.exists(job_dir):
            for root, dirs, filenames in os.walk(job_dir):
                for filename in filenames:
                    filepath = os.path.join(root, filename)
                    relpath = os.path.relpath(filepath, job_dir)
                    stat = os.stat(filepath)

                    files.append({
                        'name': filename,
                        'path': relpath,
                        'fullPath': filepath,
                        'size': stat.st_size,
                        'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                        'type': 'file',
                        'isViewable': is_viewable_file(filename, stat.st_size)
                    })

        return jsonify({
            'success': True,
            'jobId': job_id,
            'workDir': job_dir,
            'logsDir': LOGS_DIR,
            'files': files,
            'fileCount': len(files)
        })

    except Exception as e:
        print(f"❌ Error listing job files: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@job_logs_bp.route('/<job_id>/files/view', methods=['GET'])
@jwt_required
@job_owner_required
def view_job_file(job_id: str):
    """
    Job 파일 내용 조회 (텍스트 파일만)

    Query params:
        - path: 파일 경로 (작업 디렉토리 기준 상대 경로 또는 'stdout', 'stderr')

    Returns:
        { "success": true, "content": "...", "fileName": "...", "size": 123 }
    """
    try:
        file_path = request.args.get('path')
        if not file_path:
            return jsonify({'success': False, 'error': 'path parameter required'}), 400

        actual_path, denied = _resolve_job_file(job_id, file_path)
        if denied:
            return jsonify({'success': False, 'error': 'Access denied'}), 403
        if not actual_path or not os.path.exists(actual_path):
            return jsonify({'success': False, 'error': f'File not found: {file_path}'}), 404

        # 파일 크기 및 viewable 확인
        stat = os.stat(actual_path)
        filename = os.path.basename(actual_path)
        if not is_viewable_file(filename, stat.st_size):
            return jsonify({
                'success': False,
                'error': f'File is not viewable (binary or too large): {filename} ({stat.st_size} bytes)'
            }), 400

        # 파일 읽기 (최대 1MB)
        max_size = 1024 * 1024
        with open(actual_path, 'r', errors='replace') as f:
            content = f.read(max_size + 1)

        truncated = len(content) > max_size
        if truncated:
            content = content[:max_size] + '\n\n[... truncated at 1MB ...]\n'

        return jsonify({
            'success': True,
            'content': content,
            'fileName': filename,
            'size': stat.st_size,
            'truncated': truncated
        })

    except Exception as e:
        print(f"❌ Error viewing file: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500


@job_logs_bp.route('/<job_id>/files/download-ticket', methods=['POST'])
@jwt_required
@job_owner_required
def issue_download_ticket(job_id: str):
    """download·download-all 에 ?ticket= 으로 붙일 단기 티켓 발급(브라우저 다운로드 버튼용).

    Returns: { "success": true, "ticket": "...", "expires_in": 120 }
    """
    user = g.get('user') or {}
    now = datetime.utcnow()
    ticket = jwt.encode({
        'sub': user.get('username'),
        'role': user.get('role', 'user'),
        'job_id': str(job_id),
        'scope': DOWNLOAD_TICKET_SCOPE,
        'iat': now,
        'exp': now + timedelta(seconds=DOWNLOAD_TICKET_TTL_SEC),
    }, _DOWNLOAD_TICKET_KEY, algorithm=JWT_ALGORITHM)
    return jsonify({'success': True, 'ticket': ticket, 'expires_in': DOWNLOAD_TICKET_TTL_SEC})


@job_logs_bp.route('/<job_id>/files/download', methods=['GET'])
@jwt_or_download_ticket
@job_owner_required
def download_job_file(job_id: str):
    """
    Job 파일 다운로드

    Query params:
        - path: 파일 경로 (작업 디렉토리 기준 상대 경로 또는 'stdout', 'stderr')

    Returns:
        파일 다운로드
    """
    try:
        file_path = request.args.get('path')

        if not file_path:
            return jsonify({
                'success': False,
                'error': 'path parameter required'
            }), 400

        actual_path, denied = _resolve_job_file(job_id, file_path)
        if denied:
            return jsonify({
                'success': False,
                'error': 'Access denied'
            }), 403
        if not actual_path or not os.path.exists(actual_path):
            return jsonify({
                'success': False,
                'error': f'File not found: {file_path}'
            }), 404

        # 파일 전송
        return send_file(
            actual_path,
            as_attachment=True,
            download_name=os.path.basename(actual_path)
        )

    except Exception as e:
        print(f"❌ Error downloading file: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@job_logs_bp.route('/<job_id>/files/download-all', methods=['GET'])
@jwt_or_download_ticket
@job_owner_required
def download_job_files_zip(job_id: str):
    """잡 작업 디렉토리의 결과 파일 ★전체를 ZIP★ 으로 묶어 다운로드.

    대용량(d3plot 등) 대비 메모리 대신 디스크 임시파일에 압축 후 전송, 전송 뒤 정리.
    심볼릭링크/경로탈출은 realpath 검증으로 차단(작업 디렉토리 내부 파일만 포함).
    """
    import zipfile
    import tempfile
    from flask import after_this_request
    try:
        job_dir = get_job_dir(job_id)
        if not job_dir or not os.path.exists(job_dir):
            return jsonify({'success': False, 'error': f'Work directory not found for job {job_id}'}), 404
        real_job_dir = os.path.realpath(job_dir)

        tmp = tempfile.NamedTemporaryFile(prefix=f'job_{job_id}_', suffix='.zip', delete=False)
        tmp_path = tmp.name
        tmp.close()

        count = 0
        with zipfile.ZipFile(tmp_path, 'w', zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
            for root, _dirs, filenames in os.walk(job_dir):
                for fn in filenames:
                    fp = os.path.join(root, fn)
                    if not _within(fp, real_job_dir):
                        continue  # 심볼릭링크로 디렉토리 밖을 가리키는 파일 제외
                    try:
                        zf.write(fp, os.path.relpath(fp, job_dir))
                        count += 1
                    except OSError:
                        continue

        if count == 0:
            try:
                os.remove(tmp_path)
            except OSError:
                pass
            return jsonify({'success': False, 'error': 'No files to download'}), 404

        @after_this_request
        def _cleanup(response):
            # Linux: 전송 중 unlink 해도 열린 fd 가 데이터 유지 → 전송 완료 후 자동 삭제.
            try:
                os.remove(tmp_path)
            except OSError:
                pass
            return response

        return send_file(
            tmp_path,
            as_attachment=True,
            download_name=f'job_{job_id}_results.zip',
            mimetype='application/zip',
        )
    except Exception as e:
        print(f"❌ Error zipping job files: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500


@job_logs_bp.route('/<job_id>/logs/stream', methods=['GET'])
@jwt_required
@job_owner_required
def stream_job_logs(job_id: str):
    """
    SSE(Server-Sent Events)를 통한 실시간 로그 스트리밍

    Query params:
        - type: 'out' 또는 'err' (기본: 'out')

    Returns:
        SSE 스트림
    """
    log_type = request.args.get('type', 'out')
    log_path = get_log_path(job_id, log_type)

    if not log_path:
        def error_stream():
            yield f"data: {json.dumps({'error': 'Log file not found'})}\n\n"
        return Response(error_stream(), mimetype='text/event-stream')

    def generate():
        """로그 파일 변경 감지 및 스트리밍"""
        last_position = 0

        try:
            # 초기 내용 전송 (마지막 50줄)
            with open(log_path, 'r', errors='replace') as f:
                lines = f.readlines()
                initial_content = ''.join(lines[-50:])
                last_position = f.tell()

            yield f"data: {json.dumps({'type': 'initial', 'content': initial_content})}\n\n"

            # 파일 변경 감지 루프
            import time
            while True:
                try:
                    with open(log_path, 'r', errors='replace') as f:
                        f.seek(last_position)
                        new_content = f.read()
                        new_position = f.tell()

                    if new_content:
                        last_position = new_position
                        yield f"data: {json.dumps({'type': 'update', 'content': new_content})}\n\n"

                    time.sleep(1)  # 1초마다 체크
                except FileNotFoundError:
                    yield f"data: {json.dumps({'type': 'error', 'message': 'File deleted'})}\n\n"
                    break

        except GeneratorExit:
            pass
        except Exception as e:
            yield f"data: {json.dumps({'type': 'error', 'message': str(e)})}\n\n"

    return Response(generate(), mimetype='text/event-stream')


print("✅ Job Logs API initialized")
