"""
App Framework Routes
리눅스 앱을 웹에서 실행하기 위한 세션 관리 API
"""

from flask import Blueprint, request, jsonify, g
from services.app_session_service import AppSessionService
from middleware.jwt_middleware import jwt_required
import traceback

app_bp = Blueprint('app', __name__, url_prefix='/api/app')

# 세션 서비스 초기화
session_service = AppSessionService()


@app_bp.route('/health', methods=['GET'])
def health_check():
    """
    헬스 체크 엔드포인트
    """
    return jsonify({
        'status': 'healthy',
        'service': 'app-framework',
        'version': '1.0.0'
    }), 200


@app_bp.route('/apps', methods=['GET'])
@jwt_required
def list_apps():
    """
    사용 가능한 앱 목록 조회
    GET /api/app/apps
    """
    try:
        apps = session_service.list_available_apps()
        return jsonify({
            'success': True,
            'apps': apps
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500


@app_bp.route('/apps/<app_id>', methods=['GET'])
@jwt_required
def get_app_info(app_id):
    """
    특정 앱 정보 조회
    GET /api/app/apps/{app_id}
    """
    try:
        app_info = session_service.get_app_info(app_id)
        if app_info:
            return jsonify({
                'success': True,
                'app': app_info
            }), 200
        else:
            return jsonify({
                'success': False,
                'error': f'App {app_id} not found'
            }), 404
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500


@app_bp.route('/sessions', methods=['POST'])
@jwt_required
def create_session():
    """
    세션 생성 및 앱 시작
    POST /api/app/sessions

    Body:
    {
        "appId": "gedit",
        "config": {
            "resources": {"cpus": 2, "memory": "4Gi"},
            "display": {"type": "novnc", "width": 1280, "height": 720}
        }
    }
    """
    try:
        data = request.get_json()
        app_id = data.get('appId')
        config = data.get('config', {})

        if not app_id:
            return jsonify({
                'success': False,
                'error': 'appId is required'
            }), 400

        # JWT에서 사용자 정보 가져오기
        username = g.user.get('username')

        # 세션 생성 (사용자 정보 포함)
        session = session_service.create_session(app_id, config, username=username)

        return jsonify({
            'success': True,
            'session': session
        }), 201

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500


@app_bp.route('/sessions', methods=['GET'])
@jwt_required
def list_sessions():
    """
    세션 목록 조회 (사용자별 필터링)
    GET /api/app/sessions

    일반 사용자: 자신의 세션만 조회
    관리자(HPC-Admins): 모든 세션 조회
    """
    try:
        username = g.user.get('username')
        groups = g.user.get('groups', [])

        # 모든 세션 가져오기
        all_sessions = session_service.list_sessions()

        # 관리자는 모든 세션 조회 가능
        if 'HPC-Admins' in groups:
            return jsonify({
                'success': True,
                'sessions': all_sessions,
                'total': len(all_sessions),
                'filter': 'admin'
            }), 200

        # 일반 사용자는 자신의 세션만 조회
        my_sessions = [s for s in all_sessions if s.get('username') == username]

        return jsonify({
            'success': True,
            'sessions': my_sessions,
            'total': len(my_sessions),
            'filter': 'user'
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500


@app_bp.route('/sessions/<session_id>', methods=['GET'])
@jwt_required
def get_session(session_id):
    """
    특정 세션 상태 조회 (실시간 Job 상태 체크 포함)
    GET /api/app/sessions/{session_id}

    권한 확인: 자신의 세션이거나 관리자만 조회 가능
    """
    try:
        username = g.user.get('username')
        groups = g.user.get('groups', [])

        session = session_service.get_session(session_id)
        if session:
            # 권한 확인: 자신의 세션이 아니고 관리자도 아니면 거부
            if session.get('username') != username and 'HPC-Admins' not in groups:
                return jsonify({
                    'success': False,
                    'error': 'Permission denied: You can only access your own sessions'
                }), 403
            # Job 상태를 실시간으로 확인하여 업데이트
            job_id = session.get('job_id')
            if job_id:
                import subprocess
                # squeue로 Job 상태 확인
                result = subprocess.run(
                    ['squeue', '--job', str(job_id), '--noheader', '--format=%T'],
                    capture_output=True,
                    text=True,
                    timeout=5
                )

                if result.returncode == 0 and result.stdout.strip():
                    # Job이 살아있음
                    job_status = result.stdout.strip()
                    if job_status == 'RUNNING' and session['status'] != 'running':
                        # DB에는 running인데 아직 세션에 반영 안됨 - 그대로 유지
                        pass
                else:
                    # Job이 이미 종료됨 (scancel되었거나 시간 만료 등)
                    # 세션 상태를 'cancelled'로 업데이트
                    if session['status'] in ['creating', 'pending', 'running']:
                        session['status'] = 'cancelled'
                        session_service.sessions[session_id]['status'] = 'cancelled'
                        print(f"[API] Job {job_id} not found in queue - marking session as cancelled")

            return jsonify({
                'success': True,
                'session': session
            }), 200
        else:
            return jsonify({
                'success': False,
                'error': f'Session {session_id} not found'
            }), 404
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500


@app_bp.route('/sessions/<session_id>', methods=['DELETE'])
@jwt_required
def delete_session(session_id):
    """
    세션 종료 및 삭제
    DELETE /api/app/sessions/{session_id}

    권한 확인: 자신의 세션이거나 관리자만 삭제 가능
    """
    try:
        username = g.user.get('username')
        groups = g.user.get('groups', [])

        # 먼저 세션 조회
        session = session_service.get_session(session_id)
        if not session:
            return jsonify({
                'success': False,
                'error': f'Session {session_id} not found'
            }), 404

        # 권한 확인
        if session.get('username') != username and 'HPC-Admins' not in groups:
            return jsonify({
                'success': False,
                'error': 'Permission denied: You can only delete your own sessions'
            }), 403

        # 세션 삭제
        success = session_service.delete_session(session_id)
        if success:
            return jsonify({
                'success': True,
                'message': f'Session {session_id} deleted'
            }), 200
        else:
            return jsonify({
                'success': False,
                'error': f'Failed to delete session {session_id}'
            }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500


@app_bp.route('/sessions/<session_id>/restart', methods=['POST'])
@jwt_required
def restart_session(session_id):
    """
    세션 재시작
    POST /api/app/sessions/{session_id}/restart

    권한 확인: 자신의 세션이거나 관리자만 재시작 가능
    """
    try:
        username = g.user.get('username')
        groups = g.user.get('groups', [])

        # 먼저 세션 조회
        existing_session = session_service.get_session(session_id)
        if not existing_session:
            return jsonify({
                'success': False,
                'error': f'Session {session_id} not found'
            }), 404

        # 권한 확인
        if existing_session.get('username') != username and 'HPC-Admins' not in groups:
            return jsonify({
                'success': False,
                'error': 'Permission denied: You can only restart your own sessions'
            }), 403

        # 세션 재시작
        session = session_service.restart_session(session_id)
        if session:
            return jsonify({
                'success': True,
                'session': session
            }), 200
        else:
            return jsonify({
                'success': False,
                'error': f'Failed to restart session {session_id}'
            }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500
