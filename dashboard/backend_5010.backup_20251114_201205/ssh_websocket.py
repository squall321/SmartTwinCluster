"""
SSH WebSocket Handler
Handles WebSocket connections for real-time SSH terminal sessions
"""

from flask_socketio import SocketIO, emit, join_room, leave_room
from flask import request
import paramiko
import threading
import logging
import os
import select
import time

logger = logging.getLogger(__name__)

# SSH connection storage
ssh_connections = {}

# SSH configuration
SSH_KEY_PATH = os.path.expanduser('~/.ssh/id_rsa')


def init_ssh_websocket(socketio):
    """
    Initialize SSH WebSocket handlers
    socketio: Flask-SocketIO instance
    """

    @socketio.on('connect', namespace='/ssh-ws')
    def handle_connect():
        """WebSocket connection established"""
        client_id = request.sid
        logger.info(f"[SSH-WS] Client connected: {client_id}")
        emit('status', {'message': 'Connected to SSH WebSocket server'})

    @socketio.on('start_session', namespace='/ssh-ws')
    def handle_start_session(data):
        """
        Start SSH session
        data = {
            'session_id': str,
            'node_hostname': str,
            'username': str,
            'rows': int,
            'cols': int
        }
        """
        session_id = data.get('session_id')
        node_hostname = data.get('node_hostname')
        # ADMIN ONLY: Use system user (koopark) for Slurm cluster management
        # Regular user SSH will be implemented later with Apptainer integration
        username = os.getenv('USER', 'koopark')  # Slurm admin user
        rows = data.get('rows', 24)
        cols = data.get('cols', 80)
        client_id = request.sid

        if not all([session_id, node_hostname]):
            logger.error("[SSH-WS] Missing required parameters")
            emit('error', {'message': 'Missing required parameters'})
            return

        logger.info(f"[SSH-WS] Starting session {session_id}: {username}@{node_hostname}")

        try:
            # Create Paramiko SSH client
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

            # Load SSH private key
            if not os.path.exists(SSH_KEY_PATH):
                raise Exception(f'SSH key not found at {SSH_KEY_PATH}')

            pkey = paramiko.RSAKey.from_private_key_file(SSH_KEY_PATH)

            # Connect to node
            logger.info(f"[SSH-WS] Connecting to {node_hostname}...")
            ssh.connect(
                hostname=node_hostname,
                username=username,
                pkey=pkey,
                timeout=10,
                look_for_keys=False,
                allow_agent=False
            )

            # Open PTY channel
            channel = ssh.invoke_shell(
                term='xterm-256color',
                width=cols,
                height=rows
            )

            # Set non-blocking mode
            channel.settimeout(0.0)

            # Join room for this session
            join_room(session_id)

            # Store connection
            ssh_connections[session_id] = {
                'ssh': ssh,
                'channel': channel,
                'client_id': client_id,
                'username': username,
                'node_hostname': node_hostname,
                'active': True
            }

            logger.info(f"[SSH-WS] Session {session_id} connected successfully")
            emit('connected', {'message': 'SSH session established'})

            # Start output reading thread
            def read_output():
                """Background thread to read SSH output and send to client"""
                try:
                    while ssh_connections.get(session_id, {}).get('active', False):
                        try:
                            # Use select to check if data is available
                            if channel.recv_ready():
                                data = channel.recv(4096)
                                if data:
                                    output = data.decode('utf-8', errors='replace')
                                    socketio.emit('output',
                                                {'data': output},
                                                room=session_id,
                                                namespace='/ssh-ws')

                            # Check if channel is closed
                            if channel.exit_status_ready():
                                logger.info(f"[SSH-WS] Channel closed for session {session_id}")
                                socketio.emit('disconnected',
                                            {'message': 'SSH session ended'},
                                            room=session_id,
                                            namespace='/ssh-ws')
                                break

                            # Small sleep to prevent CPU spinning
                            time.sleep(0.01)

                        except Exception as e:
                            logger.error(f"[SSH-WS] Error reading output: {e}")
                            break

                except Exception as e:
                    logger.error(f"[SSH-WS] Output thread error for session {session_id}: {e}")
                finally:
                    # Cleanup on thread exit
                    if session_id in ssh_connections:
                        logger.info(f"[SSH-WS] Cleaning up session {session_id}")
                        ssh_connections[session_id]['active'] = False

            thread = threading.Thread(target=read_output, daemon=True, name=f"ssh-output-{session_id}")
            thread.start()

        except paramiko.AuthenticationException as e:
            logger.error(f"[SSH-WS] Authentication failed: {e}")
            emit('error', {'message': f'Authentication failed: {str(e)}'})
        except paramiko.SSHException as e:
            logger.error(f"[SSH-WS] SSH error: {e}")
            emit('error', {'message': f'SSH error: {str(e)}'})
        except Exception as e:
            logger.error(f"[SSH-WS] Connection failed: {e}")
            emit('error', {'message': f'Failed to connect: {str(e)}'})

    @socketio.on('input', namespace='/ssh-ws')
    def handle_input(data):
        """
        Handle terminal input from client
        data = {
            'session_id': str,
            'data': str
        }
        """
        session_id = data.get('session_id')
        input_data = data.get('data')

        if not session_id or input_data is None:
            return

        conn = ssh_connections.get(session_id)
        if conn and conn.get('active'):
            try:
                channel = conn['channel']
                channel.send(input_data.encode('utf-8'))
            except Exception as e:
                logger.error(f"[SSH-WS] Error sending input for session {session_id}: {e}")
                emit('error', {'message': f'Failed to send input: {str(e)}'})

    @socketio.on('resize', namespace='/ssh-ws')
    def handle_resize(data):
        """
        Handle terminal resize
        data = {
            'session_id': str,
            'cols': int,
            'rows': int
        }
        """
        session_id = data.get('session_id')
        cols = data.get('cols', 80)
        rows = data.get('rows', 24)

        if not session_id:
            return

        conn = ssh_connections.get(session_id)
        if conn and conn.get('active'):
            try:
                channel = conn['channel']
                channel.resize_pty(width=cols, height=rows)
                logger.info(f"[SSH-WS] Resized session {session_id} to {cols}x{rows}")
            except Exception as e:
                logger.error(f"[SSH-WS] Error resizing terminal for session {session_id}: {e}")

    @socketio.on('disconnect', namespace='/ssh-ws')
    def handle_disconnect():
        """WebSocket connection closed"""
        client_id = request.sid
        logger.info(f"[SSH-WS] Client disconnected: {client_id}")

        # Find and cleanup sessions for this client
        sessions_to_cleanup = []
        for session_id, conn in list(ssh_connections.items()):
            if conn.get('client_id') == client_id:
                sessions_to_cleanup.append(session_id)

        for session_id in sessions_to_cleanup:
            cleanup_session(session_id)

    def cleanup_session(session_id):
        """Clean up SSH connection resources"""
        if session_id not in ssh_connections:
            return

        try:
            conn = ssh_connections[session_id]
            conn['active'] = False

            # Close channel
            channel = conn.get('channel')
            if channel:
                try:
                    channel.close()
                except Exception as e:
                    logger.warning(f"[SSH-WS] Error closing channel for {session_id}: {e}")

            # Close SSH connection
            ssh = conn.get('ssh')
            if ssh:
                try:
                    ssh.close()
                except Exception as e:
                    logger.warning(f"[SSH-WS] Error closing SSH for {session_id}: {e}")

            # Remove from storage
            del ssh_connections[session_id]
            logger.info(f"[SSH-WS] Session {session_id} cleaned up")

        except Exception as e:
            logger.error(f"[SSH-WS] Error cleaning up session {session_id}: {e}")

    # Register cleanup function to be accessible
    socketio.cleanup_ssh_session = cleanup_session

    logger.info("[SSH-WS] SSH WebSocket handlers initialized")
