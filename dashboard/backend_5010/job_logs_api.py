"""
Job Logs API
작업 로그 및 결과 파일 조회 API

Phase 1: 로그 조회 및 파일 관리
"""

import os
import json
import subprocess
from datetime import datetime
from flask import Blueprint, request, jsonify, send_file, Response
from middleware.jwt_middleware import jwt_required, permission_required, optional_jwt

# Slurm 명령어 경로
from slurm_commands import get_sacct, get_scontrol

job_logs_bp = Blueprint('job_logs', __name__, url_prefix='/api/jobs')

# 로그 및 작업 디렉토리 경로
# GlusterFS 마운트 경로 (클러스터 공유 스토리지)
LOGS_DIR = os.getenv('JOB_LOGS_DIR', '/mnt/gluster/logs')
JOBS_DIR = os.getenv('JOB_WORK_DIR', '/mnt/gluster/jobs')

# 대체 경로 (로컬 fallback)
ALT_LOGS_DIR = '/shared/logs'
ALT_JOBS_DIR = '/shared/jobs'


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
@optional_jwt
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
@optional_jwt
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
@optional_jwt
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
@optional_jwt
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
@optional_jwt
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

        # 특수 경로 처리 (stdout, stderr)
        if file_path in ['stdout', 'out']:
            actual_path = get_log_path(job_id, 'out')
        elif file_path in ['stderr', 'err']:
            actual_path = get_log_path(job_id, 'err')
        else:
            job_dir = get_job_dir(job_id)
            if job_dir:
                actual_path = os.path.join(job_dir, file_path)
            else:
                actual_path = None

        if not actual_path or not os.path.exists(actual_path):
            return jsonify({'success': False, 'error': f'File not found: {file_path}'}), 404

        # 경로 검증 (path traversal 방지)
        job_dir = get_job_dir(job_id)
        if job_dir:
            real_job_dir = os.path.realpath(job_dir)
            real_file_path = os.path.realpath(actual_path)
            if not real_file_path.startswith(real_job_dir) and \
               not real_file_path.startswith(os.path.realpath(LOGS_DIR)) and \
               not real_file_path.startswith(os.path.realpath(ALT_LOGS_DIR)):
                return jsonify({'success': False, 'error': 'Access denied'}), 403

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


@job_logs_bp.route('/<job_id>/files/download', methods=['GET'])
@optional_jwt
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

        # 특수 경로 처리 (stdout, stderr)
        if file_path in ['stdout', 'out']:
            actual_path = get_log_path(job_id, 'out')
        elif file_path in ['stderr', 'err']:
            actual_path = get_log_path(job_id, 'err')
        else:
            # 작업 디렉토리 기준 상대 경로
            job_dir = get_job_dir(job_id)
            if job_dir:
                actual_path = os.path.join(job_dir, file_path)
            else:
                actual_path = None

        if not actual_path or not os.path.exists(actual_path):
            return jsonify({
                'success': False,
                'error': f'File not found: {file_path}'
            }), 404

        # 경로 검증 (path traversal 방지)
        if job_dir:
            real_job_dir = os.path.realpath(job_dir)
            real_file_path = os.path.realpath(actual_path)
            if not real_file_path.startswith(real_job_dir) and \
               not real_file_path.startswith(os.path.realpath(LOGS_DIR)) and \
               not real_file_path.startswith(os.path.realpath(ALT_LOGS_DIR)):
                return jsonify({
                    'success': False,
                    'error': 'Access denied'
                }), 403

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


@job_logs_bp.route('/<job_id>/logs/stream', methods=['GET'])
@optional_jwt
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
