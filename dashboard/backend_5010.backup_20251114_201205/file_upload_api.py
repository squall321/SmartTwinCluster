"""
File Upload API v2
대용량 파일 업로드 및 관리 API

Features:
- 청크 기반 업로드 (Resumable Upload)
- 자동 파일 분류
- WebSocket 진행률 업데이트
- 파일 유효성 검증
- Job 및 User별 저장 경로 관리

Endpoints:
- POST   /api/v2/files/upload/init        # 업로드 세션 초기화
- POST   /api/v2/files/upload/chunk       # 청크 업로드
- POST   /api/v2/files/upload/complete    # 업로드 완료
- GET    /api/v2/files/uploads             # 업로드 목록
- GET    /api/v2/files/uploads/{id}        # 업로드 상세
- DELETE /api/v2/files/uploads/{id}        # 업로드 취소/삭제
"""

from flask import Blueprint, jsonify, request, g
from file_classifier import get_file_classifier
from middleware.jwt_middleware import jwt_required, permission_required
from middleware.rate_limiter import rate_limit
import logging
import sqlite3
import os
import hashlib
import time
from pathlib import Path
from typing import Dict, Optional, List
import json

# Blueprint 생성
file_upload_bp = Blueprint('file_upload', __name__)

# 로깅 설정
logger = logging.getLogger(__name__)

# 업로드 설정
UPLOAD_BASE_PATH = "/shared/uploads"
CHUNK_SIZE = 5 * 1024 * 1024  # 5MB
MAX_FILE_SIZE = 50 * 1024 * 1024 * 1024  # 50GB


def get_db_connection():
    """DB 연결 가져오기"""
    db_path = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def broadcast_upload_progress(upload_id: str, progress_data: Dict):
    """
    WebSocket으로 업로드 진행률 전송

    Args:
        upload_id: 업로드 ID
        progress_data: 진행률 데이터
    """
    try:
        # WebSocket 브로드캐스트 (실제 구현은 WebSocket 서버와 연동 필요)
        from websocket_server import broadcast_message

        broadcast_message('upload_progress', {
            'upload_id': upload_id,
            **progress_data
        })

    except ImportError:
        logger.warning("WebSocket server not available for progress updates")
    except Exception as e:
        logger.error(f"Failed to broadcast upload progress: {e}")


@file_upload_bp.route('/api/v2/files/upload/init', methods=['POST'])
@jwt_required
@permission_required('dashboard')
@rate_limit(max_requests=20, window_seconds=60)  # 분당 20회 제한 (파일 초기화)
def init_upload():
    """
    업로드 세션 초기화 (JWT 인증 필요)

    Request Body:
        {
            "filename": str,         # 파일명
            "file_size": int,        # 파일 크기 (bytes)
            "job_id": str,           # 작업 ID (선택)
            "file_type": str,        # 파일 타입 (선택, 자동 분류됨)
            "chunk_size": int        # 청크 크기 (선택, 기본 5MB)
        }

    Returns:
        JSON: {
            "upload_id": str,
            "chunk_size": int,
            "total_chunks": int,
            "storage_path": str,
            "file_info": dict
        }
    """
    try:
        data = request.get_json()

        # 필수 파라미터 검증
        if not data or 'filename' not in data or 'file_size' not in data:
            return jsonify({'error': 'Missing required fields: filename, file_size'}), 400

        filename = data['filename']
        file_size = data['file_size']

        # user_id는 JWT에서 추출 (보안!)
        user = g.user
        user_id = user['username']

        job_id = data.get('job_id')
        chunk_size = data.get('chunk_size', CHUNK_SIZE)

        # 파일 크기 검증
        if file_size > MAX_FILE_SIZE:
            return jsonify({
                'error': f'File size {file_size} exceeds maximum {MAX_FILE_SIZE}'
            }), 400

        # 파일 분류
        classifier = get_file_classifier()
        file_info = classifier.classify_file(filename)

        # 저장 경로 결정
        storage_path = classifier.get_storage_path(
            file_info['type'],
            user_id,
            job_id
        )

        # 저장 디렉토리 생성
        os.makedirs(storage_path, exist_ok=True)

        # 고유 업로드 ID 생성
        upload_id = hashlib.sha256(
            f"{filename}_{user_id}_{time.time()}".encode()
        ).hexdigest()[:16]

        # 총 청크 수 계산
        total_chunks = (file_size + chunk_size - 1) // chunk_size

        # 임시 청크 디렉토리 생성
        chunk_dir = os.path.join(storage_path, '.chunks', upload_id)
        os.makedirs(chunk_dir, exist_ok=True)

        # DB에 업로드 세션 저장
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO file_uploads (
                upload_id, filename, file_size, file_type,
                user_id, job_id, storage_path, chunk_size,
                total_chunks, uploaded_chunks, status,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ''', (
            upload_id, filename, file_size, file_info['type'],
            user_id, job_id, storage_path, chunk_size,
            total_chunks, 0, 'initialized'
        ))

        conn.commit()
        conn.close()

        logger.info(f"Upload initialized: {upload_id} ({filename}, {file_size} bytes)")

        return jsonify({
            'upload_id': upload_id,
            'chunk_size': chunk_size,
            'total_chunks': total_chunks,
            'storage_path': storage_path,
            'file_info': file_info
        }), 201

    except Exception as e:
        logger.error(f"Failed to initialize upload: {e}")
        return jsonify({'error': str(e)}), 500


@file_upload_bp.route('/api/v2/files/upload/chunk', methods=['POST'])
@jwt_required
@permission_required('dashboard')
@rate_limit(max_requests=2000, window_seconds=60)  # 분당 2000 청크 (대용량 파일용)
def upload_chunk():
    """
    청크 업로드 (JWT 인증 필요)

    Request (multipart/form-data):
        - upload_id: 업로드 ID
        - chunk_index: 청크 인덱스 (0부터 시작)
        - chunk: 청크 파일 데이터
        - checksum: 청크 체크섬 (선택, MD5)

    Returns:
        JSON: {
            "message": str,
            "uploaded_chunks": int,
            "total_chunks": int,
            "progress": float  # 0-100
        }
    """
    try:
        upload_id = request.form.get('upload_id')
        chunk_index = request.form.get('chunk_index')
        checksum = request.form.get('checksum')

        if not upload_id or chunk_index is None:
            return jsonify({'error': 'Missing upload_id or chunk_index'}), 400

        chunk_index = int(chunk_index)

        # 청크 데이터 가져오기
        if 'chunk' not in request.files:
            return jsonify({'error': 'No chunk data provided'}), 400

        chunk_file = request.files['chunk']
        chunk_data = chunk_file.read()

        # 체크섬 검증 (선택적)
        if checksum:
            calculated_checksum = hashlib.md5(chunk_data).hexdigest()
            if calculated_checksum != checksum:
                return jsonify({'error': 'Chunk checksum mismatch'}), 400

        # DB에서 업로드 세션 조회
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute('''
            SELECT storage_path, total_chunks, uploaded_chunks, status
            FROM file_uploads
            WHERE upload_id = ?
        ''', (upload_id,))

        row = cursor.fetchone()

        if not row:
            conn.close()
            return jsonify({'error': 'Upload session not found'}), 404

        storage_path = row['storage_path']
        total_chunks = row['total_chunks']
        uploaded_chunks = row['uploaded_chunks']
        status = row['status']

        if status == 'completed':
            conn.close()
            return jsonify({'error': 'Upload already completed'}), 400

        if status == 'cancelled':
            conn.close()
            return jsonify({'error': 'Upload was cancelled'}), 400

        # 청크 저장
        chunk_dir = os.path.join(storage_path, '.chunks', upload_id)
        chunk_path = os.path.join(chunk_dir, f'chunk_{chunk_index:06d}')

        with open(chunk_path, 'wb') as f:
            f.write(chunk_data)

        # 업로드된 청크 수 업데이트
        new_uploaded_chunks = uploaded_chunks + 1
        progress = (new_uploaded_chunks / total_chunks) * 100

        cursor.execute('''
            UPDATE file_uploads
            SET uploaded_chunks = ?,
                status = 'uploading',
                updated_at = datetime('now')
            WHERE upload_id = ?
        ''', (new_uploaded_chunks, upload_id))

        conn.commit()
        conn.close()

        # WebSocket 진행률 전송
        broadcast_upload_progress(upload_id, {
            'uploaded_chunks': new_uploaded_chunks,
            'total_chunks': total_chunks,
            'progress': progress
        })

        logger.debug(f"Chunk {chunk_index} uploaded for {upload_id} ({progress:.1f}%)")

        return jsonify({
            'message': 'Chunk uploaded successfully',
            'uploaded_chunks': new_uploaded_chunks,
            'total_chunks': total_chunks,
            'progress': progress
        }), 200

    except Exception as e:
        logger.error(f"Failed to upload chunk: {e}")
        return jsonify({'error': str(e)}), 500


@file_upload_bp.route('/api/v2/files/upload/complete', methods=['POST'])
@jwt_required
@permission_required('dashboard')
@rate_limit(max_requests=20, window_seconds=60)  # 분당 20회 제한 (완료 요청)
def complete_upload():
    """
    업로드 완료 및 파일 병합 (JWT 인증 필요)

    Request Body:
        {
            "upload_id": str,
            "verify_checksum": bool  # 전체 파일 체크섬 검증 (선택)
        }

    Returns:
        JSON: {
            "message": str,
            "file_path": str,
            "file_info": dict
        }
    """
    try:
        data = request.get_json()

        if not data or 'upload_id' not in data:
            return jsonify({'error': 'Missing upload_id'}), 400

        upload_id = data['upload_id']

        # DB에서 업로드 세션 조회
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute('''
            SELECT filename, storage_path, total_chunks, uploaded_chunks, status
            FROM file_uploads
            WHERE upload_id = ?
        ''', (upload_id,))

        row = cursor.fetchone()

        if not row:
            conn.close()
            return jsonify({'error': 'Upload session not found'}), 404

        filename = row['filename']
        storage_path = row['storage_path']
        total_chunks = row['total_chunks']
        uploaded_chunks = row['uploaded_chunks']
        status = row['status']

        # 업로드 완료 여부 확인
        if uploaded_chunks < total_chunks:
            conn.close()
            return jsonify({
                'error': f'Upload incomplete: {uploaded_chunks}/{total_chunks} chunks'
            }), 400

        if status == 'completed':
            conn.close()
            return jsonify({'error': 'Upload already completed'}), 400

        # 청크 병합
        chunk_dir = os.path.join(storage_path, '.chunks', upload_id)
        final_path = os.path.join(storage_path, filename)

        with open(final_path, 'wb') as output_file:
            for i in range(total_chunks):
                chunk_path = os.path.join(chunk_dir, f'chunk_{i:06d}')

                if not os.path.exists(chunk_path):
                    # 청크 파일이 없으면 롤백
                    output_file.close()
                    os.remove(final_path)
                    conn.close()
                    return jsonify({
                        'error': f'Missing chunk {i}'
                    }), 500

                with open(chunk_path, 'rb') as chunk_file:
                    output_file.write(chunk_file.read())

        # 청크 파일 정리
        import shutil
        shutil.rmtree(chunk_dir)

        # 파일 정보 재분류 (실제 파일 크기 포함)
        classifier = get_file_classifier()
        file_info = classifier.classify_file(filename, final_path)

        # 보안 검증 수행
        security_check = classifier.validate_file_security(filename, final_path)

        if not security_check['safe']:
            # 보안 검증 실패 시 파일 삭제 및 롤백
            os.remove(final_path)
            cursor.execute('''
                UPDATE file_uploads
                SET status = 'failed',
                    error_message = ?
                WHERE upload_id = ?
            ''', (security_check['reason'], upload_id))
            conn.commit()
            conn.close()

            logger.warning(f"Security check failed for {upload_id}: {security_check['reason']}")

            # WebSocket 실패 알림
            broadcast_upload_progress(upload_id, {
                'status': 'failed',
                'error': security_check['reason'],
                'risk_level': security_check['risk_level'],
                'recommendations': security_check['recommendations']
            })

            return jsonify({
                'error': 'Security validation failed',
                'reason': security_check['reason'],
                'risk_level': security_check['risk_level'],
                'recommendations': security_check['recommendations']
            }), 403

        # 보안 검증 통과 - 경고가 있으면 로그 기록
        if security_check['risk_level'] != 'safe':
            logger.info(f"File {filename} uploaded with risk level: {security_check['risk_level']}")
            logger.info(f"Recommendations: {security_check['recommendations']}")

        # DB 업데이트
        cursor.execute('''
            UPDATE file_uploads
            SET status = 'completed',
                file_path = ?,
                completed_at = datetime('now')
            WHERE upload_id = ?
        ''', (final_path, upload_id))

        conn.commit()
        conn.close()

        # WebSocket 완료 알림
        broadcast_upload_progress(upload_id, {
            'status': 'completed',
            'file_path': final_path,
            'progress': 100
        })

        logger.info(f"Upload completed: {upload_id} -> {final_path}")

        return jsonify({
            'message': 'Upload completed successfully',
            'file_path': final_path,
            'file_info': file_info
        }), 200

    except Exception as e:
        logger.error(f"Failed to complete upload: {e}")
        return jsonify({'error': str(e)}), 500


@file_upload_bp.route('/api/v2/files/uploads', methods=['GET'])
@jwt_required
@rate_limit(max_requests=100, window_seconds=60)  # 분당 100회 제한 (목록 조회)
def list_uploads():
    """
    업로드 목록 조회 (JWT 인증 필요)

    Query Parameters:
        user_id (str): 사용자 ID 필터
        job_id (str): 작업 ID 필터
        status (str): 상태 필터 (initialized, uploading, completed, cancelled)

    Returns:
        JSON: {
            "uploads": [...],
            "total": int
        }
    """
    try:
        # JWT에서 사용자 정보 추출
        user = g.user
        authenticated_user_id = user['username']
        is_admin = 'HPC-Admins' in user.get('groups', [])

        # 권한 검증: 본인 파일만 조회 가능 (관리자 예외)
        user_id_param = request.args.get('user_id')
        if user_id_param and user_id_param != authenticated_user_id and not is_admin:
            return jsonify({
                'error': 'Forbidden',
                'message': 'You can only view your own uploads'
            }), 403

        # 일반 사용자는 자동으로 본인 파일만 조회
        user_id = user_id_param if is_admin else authenticated_user_id

        job_id = request.args.get('job_id')
        status = request.args.get('status')

        conn = get_db_connection()
        cursor = conn.cursor()

        # 동적 쿼리 생성
        query = 'SELECT * FROM file_uploads WHERE 1=1'
        params = []

        if user_id:
            query += ' AND user_id = ?'
            params.append(user_id)

        if job_id:
            query += ' AND job_id = ?'
            params.append(job_id)

        if status:
            query += ' AND status = ?'
            params.append(status)

        query += ' ORDER BY created_at DESC'

        cursor.execute(query, params)
        rows = cursor.fetchall()

        uploads = [dict(row) for row in rows]

        conn.close()

        return jsonify({
            'uploads': uploads,
            'total': len(uploads)
        }), 200

    except Exception as e:
        logger.error(f"Failed to list uploads: {e}")
        return jsonify({'error': str(e)}), 500


@file_upload_bp.route('/api/v2/files/uploads/<upload_id>', methods=['GET'])
@jwt_required
@rate_limit(max_requests=100, window_seconds=60)  # 분당 100회 제한 (상세 조회)
def get_upload(upload_id: str):
    """
    업로드 상세 조회 (JWT 인증 필요)

    Args:
        upload_id: 업로드 ID

    Returns:
        JSON: 업로드 정보
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute('SELECT * FROM file_uploads WHERE upload_id = ?', (upload_id,))
        row = cursor.fetchone()

        conn.close()

        if not row:
            return jsonify({'error': 'Upload not found'}), 404

        # JWT에서 사용자 정보 추출
        user = g.user
        user_id = user['username']
        is_admin = 'HPC-Admins' in user.get('groups', [])

        # 권한 검증: 본인 파일만 조회 가능 (관리자 예외)
        if row['user_id'] != user_id and not is_admin:
            return jsonify({
                'error': 'Forbidden',
                'message': 'You can only view your own uploads'
            }), 403

        return jsonify(dict(row)), 200

    except Exception as e:
        logger.error(f"Failed to get upload {upload_id}: {e}")
        return jsonify({'error': str(e)}), 500


@file_upload_bp.route('/api/v2/files/uploads/<upload_id>', methods=['DELETE'])
@jwt_required
@permission_required('dashboard')
@rate_limit(max_requests=50, window_seconds=60)  # 분당 50회 제한 (취소/삭제)
def cancel_upload(upload_id: str):
    """
    업로드 취소 및 정리 (JWT 인증 필요)

    Args:
        upload_id: 업로드 ID

    Returns:
        JSON: {
            "message": str,
            "upload_id": str
        }
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute('''
            SELECT storage_path, status, file_path, user_id
            FROM file_uploads
            WHERE upload_id = ?
        ''', (upload_id,))

        row = cursor.fetchone()

        if not row:
            conn.close()
            return jsonify({'error': 'Upload not found'}), 404

        # JWT에서 사용자 정보 추출
        user = g.user
        user_id = user['username']
        is_admin = 'HPC-Admins' in user.get('groups', [])

        # 권한 검증: 본인 파일만 삭제 가능 (관리자 예외)
        if row['user_id'] != user_id and not is_admin:
            conn.close()
            return jsonify({
                'error': 'Forbidden',
                'message': 'You can only delete your own uploads'
            }), 403

        storage_path = row['storage_path']
        status = row['status']
        file_path = row['file_path']

        # 청크 디렉토리 삭제
        chunk_dir = os.path.join(storage_path, '.chunks', upload_id)
        if os.path.exists(chunk_dir):
            import shutil
            shutil.rmtree(chunk_dir)

        # 완료된 파일 삭제 (선택적)
        if status == 'completed' and file_path and os.path.exists(file_path):
            os.remove(file_path)

        # DB 업데이트
        cursor.execute('''
            UPDATE file_uploads
            SET status = 'cancelled',
                updated_at = datetime('now')
            WHERE upload_id = ?
        ''', (upload_id,))

        conn.commit()
        conn.close()

        logger.info(f"Upload cancelled: {upload_id}")

        return jsonify({
            'message': 'Upload cancelled successfully',
            'upload_id': upload_id
        }), 200

    except Exception as e:
        logger.error(f"Failed to cancel upload {upload_id}: {e}")
        return jsonify({'error': str(e)}), 500
