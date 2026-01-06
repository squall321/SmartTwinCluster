"""
SSH Session Management API
Provides endpoints for managing SSH sessions to cluster nodes
"""

from flask import Blueprint, jsonify, request, g
from middleware.jwt_middleware import jwt_required
import subprocess
import uuid
import logging
from datetime import datetime
import os

# 절대 경로 import (systemd 환경에서 PATH 제한)
try:
    from slurm_commands import SINFO
except ImportError:
    SLURM_BIN_DIR = os.getenv('SLURM_BIN_DIR', '/usr/local/slurm/bin')
    SINFO = os.path.join(SLURM_BIN_DIR, 'sinfo')

# YAML에서 노드별 SSH 사용자 조회
try:
    from yaml_node_loader import get_ssh_user_for_node
except ImportError:
    def get_ssh_user_for_node(hostname):
        return 'koopark'

logger = logging.getLogger(__name__)

ssh_bp = Blueprint('ssh', __name__, url_prefix='/api/ssh')

# In-memory session storage (could be moved to Redis for production)
active_sessions = {}

# SSH 키 설정 (웹 서비스가 다른 사용자로 실행될 때를 위해)
def get_ssh_key_path():
    """SSH 키 경로 자동 탐지"""
    # 1. 환경변수로 명시적 지정
    if os.getenv('SSH_KEY_PATH'):
        key_path = os.getenv('SSH_KEY_PATH')
        if os.path.exists(key_path):
            return key_path

    # 2. SUDO_USER가 있으면 그 사용자의 키 사용
    sudo_user = os.getenv('SUDO_USER')
    if sudo_user:
        import pwd
        try:
            user_home = pwd.getpwnam(sudo_user).pw_dir
            key_path = os.path.join(user_home, '.ssh', 'id_rsa')
            if os.path.exists(key_path):
                return key_path
        except KeyError:
            pass

    # 3. 현재 사용자의 홈 디렉토리에서 탐색
    home = os.path.expanduser('~')
    key_path = os.path.join(home, '.ssh', 'id_rsa')
    if os.path.exists(key_path):
        return key_path

    # 4. 일반적인 서비스 계정 경로
    for user in ['koopark', 'hpcadmin', 'slurm']:
        import pwd
        try:
            user_home = pwd.getpwnam(user).pw_dir
            key_path = os.path.join(user_home, '.ssh', 'id_rsa')
            if os.path.exists(key_path):
                return key_path
        except KeyError:
            continue

    return None

SSH_KEY_PATH = get_ssh_key_path()
if SSH_KEY_PATH:
    logger.info(f"SSH key found: {SSH_KEY_PATH}")
else:
    logger.warning("No SSH key found - SSH connections may fail")

SSH_OPTIONS = [
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'ServerAliveInterval=60',
    '-o', 'ServerAliveCountMax=3'
]
if SSH_KEY_PATH:
    SSH_OPTIONS = ['-i', SSH_KEY_PATH] + SSH_OPTIONS


@ssh_bp.route('/nodes', methods=['GET'])
@jwt_required
def get_available_nodes():
    """
    Get list of available nodes for SSH connection
    Uses sinfo to get node list from Slurm
    """
    try:
        user = g.user
        username = user.get('username', 'unknown')
        logger.info(f"[SSH] Getting available nodes for user: {username}")

        # Get nodes from Slurm (절대 경로 사용)
        try:
            result = subprocess.run(
                [SINFO, '-N', '-h', '-o', '%N %T'],
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode == 0:
                nodes = []
                seen_nodes = set()  # 중복 제거용
                for line in result.stdout.strip().split('\n'):
                    if line:
                        parts = line.split()
                        if len(parts) >= 2:
                            node_name = parts[0]
                            node_state = parts[1]
                            # 노드가 여러 partition에 속하면 sinfo에서 중복 출력됨
                            # 첫 번째 출현만 사용 (가장 좋은 상태를 보통 먼저 출력)
                            if node_name not in seen_nodes:
                                seen_nodes.add(node_name)
                                nodes.append({
                                    'name': node_name,
                                    'state': node_state
                                })

                logger.info(f"[SSH] Found {len(nodes)} unique nodes")
                return jsonify({
                    'nodes': nodes,
                    'count': len(nodes)
                })
            else:
                logger.warning(f"[SSH] sinfo command failed: {result.stderr}")
                # Fallback to static list
                return jsonify({
                    'nodes': [
                        {'name': 'node001', 'state': 'idle'},
                        {'name': 'node002', 'state': 'idle'},
                        {'name': 'viz-node001', 'state': 'idle'}
                    ],
                    'count': 3
                })
        except subprocess.TimeoutExpired:
            logger.error("[SSH] sinfo command timed out")
            return jsonify({
                'nodes': [
                    {'name': 'node001', 'state': 'idle'},
                    {'name': 'node002', 'state': 'idle'},
                    {'name': 'viz-node001', 'state': 'idle'}
                ],
                'count': 3
            })
        except Exception as e:
            logger.error(f"[SSH] Error getting nodes: {e}")
            return jsonify({
                'nodes': [
                    {'name': 'node001', 'state': 'idle'},
                    {'name': 'node002', 'state': 'idle'},
                    {'name': 'viz-node001', 'state': 'idle'}
                ],
                'count': 3
            })

    except Exception as e:
        logger.error(f"[SSH] Error in get_available_nodes: {e}")
        return jsonify({
            'error': 'Failed to get nodes',
            'message': str(e)
        }), 500


@ssh_bp.route('/sessions', methods=['GET'])
@jwt_required
def get_sessions():
    """
    Get all SSH sessions for the current user
    """
    try:
        user = g.user
        username = user.get("username", "unknown")
        logger.info(f"[SSH] Getting sessions for user: {username}")

        # Filter sessions by web_user (웹 로그인 사용자 기준으로 필터)
        user_sessions = [
            session for session_id, session in active_sessions.items()
            if session.get('web_user') == username
        ]

        logger.info(f"[SSH] Found {len(user_sessions)} sessions for user {username}")
        return jsonify({
            'sessions': user_sessions,
            'count': len(user_sessions)
        })

    except Exception as e:
        logger.error(f"[SSH] Error getting sessions: {e}")
        return jsonify({
            'error': 'Failed to get sessions',
            'message': str(e)
        }), 500


@ssh_bp.route('/sessions', methods=['POST'])
@jwt_required
def create_session():
    """
    Create a new SSH session to a node
    SSH 사용자는 YAML 설정의 ssh_user를 사용 (계정명 기반)
    """
    try:
        user = g.user
        web_username = user.get("username", "unknown")  # 웹 로그인 사용자 (관리용)
        data = request.json

        node_hostname = data.get('node_hostname')
        if not node_hostname:
            return jsonify({
                'error': 'Missing required field: node_hostname'
            }), 400

        # YAML에서 해당 노드의 SSH 사용자 조회
        ssh_username = get_ssh_user_for_node(node_hostname)
        logger.info(f"[SSH] Creating session for web user {web_username}, SSH user {ssh_username} to {node_hostname}")

        # Check if SSH key exists
        if not os.path.exists(SSH_KEY_PATH):
            logger.warning(f"[SSH] SSH key not found at {SSH_KEY_PATH}")
            return jsonify({
                'error': 'SSH key not configured',
                'message': f'SSH key not found at {SSH_KEY_PATH}'
            }), 500


        # Create session
        session_id = str(uuid.uuid4())
        session = {
            'id': session_id,
            'node_hostname': node_hostname,
            'username': ssh_username,  # YAML의 ssh_user 사용
            'web_user': web_username,  # 웹 로그인 사용자 (감사 추적용)
            'status': 'connected',
            'created_at': datetime.utcnow().isoformat(),
            'last_activity': datetime.utcnow().isoformat()
        }

        # Store session
        active_sessions[session_id] = session

        logger.info(f"[SSH] Session {session_id} created: {ssh_username}@{node_hostname} (web user: {web_username})")

        return jsonify({
            'session': session,
            'message': 'SSH session created successfully'
        }), 201

    except Exception as e:
        logger.error(f"[SSH] Error creating session: {e}")
        return jsonify({
            'error': 'Failed to create session',
            'message': str(e)
        }), 500


@ssh_bp.route('/sessions/<session_id>', methods=['DELETE'])
@jwt_required
def terminate_session(session_id):
    """
    Terminate an SSH session
    """
    try:
        user = g.user
        username = user.get("username", "unknown")
        logger.info(f"[SSH] Terminating session {session_id} for user {username}")

        # Check if session exists
        if session_id not in active_sessions:
            return jsonify({
                'error': 'Session not found'
            }), 404

        session = active_sessions[session_id]

        # Verify ownership (web_user 기준으로 소유권 확인)
        if session.get('web_user') != username:
            logger.warning(f"[SSH] User {username} attempted to terminate session owned by {session.get('web_user')}")
            return jsonify({
                'error': 'Permission denied',
                'message': 'You can only terminate your own sessions'
            }), 403

        # Remove session
        del active_sessions[session_id]

        logger.info(f"[SSH] Session {session_id} terminated")

        return jsonify({
            'message': 'Session terminated successfully',
            'session_id': session_id
        })

    except Exception as e:
        logger.error(f"[SSH] Error terminating session: {e}")
        return jsonify({
            'error': 'Failed to terminate session',
            'message': str(e)
        }), 500


@ssh_bp.route('/sessions/<session_id>', methods=['GET'])
@jwt_required
def get_session_details(session_id):
    """
    Get details of a specific SSH session
    """
    try:
        user = g.user
        username = user.get("username", "unknown")

        if session_id not in active_sessions:
            return jsonify({
                'error': 'Session not found'
            }), 404

        session = active_sessions[session_id]

        # Verify ownership (web_user 기준으로 소유권 확인)
        if session.get('web_user') != username:
            return jsonify({
                'error': 'Permission denied'
            }), 403

        return jsonify({
            'session': session
        })

    except Exception as e:
        logger.error(f"[SSH] Error getting session details: {e}")
        return jsonify({
            'error': 'Failed to get session details',
            'message': str(e)
        }), 500


# Health check endpoint
@ssh_bp.route('/health', methods=['GET'])
def health_check():
    """
    Health check endpoint for SSH API
    """
    return jsonify({
        'status': 'healthy',
        'service': 'ssh_api',
        'active_sessions': len(active_sessions)
    })
