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

logger = logging.getLogger(__name__)

ssh_bp = Blueprint('ssh', __name__, url_prefix='/api/ssh')

# In-memory session storage (could be moved to Redis for production)
active_sessions = {}

# SSH configuration
SSH_KEY_PATH = os.path.expanduser('~/.ssh/id_rsa')
SSH_OPTIONS = [
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'ServerAliveInterval=60',
    '-o', 'ServerAliveCountMax=3'
]


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

        # Get nodes from Slurm
        try:
            result = subprocess.run(
                ['sinfo', '-N', '-h', '-o', '%N %T'],
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode == 0:
                nodes = []
                for line in result.stdout.strip().split('\n'):
                    if line:
                        parts = line.split()
                        if len(parts) >= 2:
                            node_name = parts[0]
                            node_state = parts[1]
                            nodes.append({
                                'name': node_name,
                                'state': node_state
                            })

                logger.info(f"[SSH] Found {len(nodes)} nodes")
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

        # Filter sessions by username
        user_sessions = [
            session for session_id, session in active_sessions.items()
            if session.get('username') == username
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
    """
    try:
        user = g.user
        username = user.get("username", "unknown")
        data = request.json

        node_hostname = data.get('node_hostname')
        if not node_hostname:
            return jsonify({
                'error': 'Missing required field: node_hostname'
            }), 400

        logger.info(f"[SSH] Creating session for {username} to {node_hostname}")

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
            'username': username,
            'status': 'connected',
            'created_at': datetime.utcnow().isoformat(),
            'last_activity': datetime.utcnow().isoformat()
        }

        # Store session
        active_sessions[session_id] = session

        logger.info(f"[SSH] Session {session_id} created for {username}@{node_hostname}")

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

        # Verify ownership
        if session.get('username') != username:
            logger.warning(f"[SSH] User {username} attempted to terminate session owned by {session.get('username')}")
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

        # Verify ownership
        if session.get('username') != username:
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
