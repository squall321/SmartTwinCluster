"""
VNC Session Management API
GPU 기반 원격 데스크톱 세션 생성 및 관리
"""

import os
import sys
import json
import time
import random
import subprocess
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify, g
from middleware.jwt_middleware import jwt_required, group_required

# Add common module to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Redis Session Manager import
try:
    from common import RedisSessionManager, get_redis_client
    REDIS_AVAILABLE = True
    # Initialize session manager for VNC sessions with LEGACY key pattern
    vnc_session_manager = RedisSessionManager('vnc', ttl=28800, legacy_key_pattern=True)  # 8 hours, vnc:session:{id}
    print("✅ VNC Redis session manager initialized (legacy key pattern: vnc:session:*)")
except Exception as e:
    REDIS_AVAILABLE = False
    print(f"⚠️  Redis not available: {e}")
    print("⚠️  VNC sessions will be stored in memory")
    vnc_sessions_memory = {}
    vnc_session_manager = None

# Slurm 명령어
try:
    from slurm_commands import SBATCH, SCANCEL, SQUEUE, SCONTROL
    SLURM_AVAILABLE = True
except ImportError:
    SLURM_AVAILABLE = False

# Mock 모드
MOCK_MODE = os.getenv('MOCK_MODE', 'false').lower() == 'true'

# VNC 설정
VNC_PORT_RANGE_START = 5901
VNC_PORT_RANGE_END = 5999
NOVNC_PORT_OFFSET = 1000  # noVNC 포트 = VNC 포트 + 1000

# VNC 이미지 및 작업 디렉토리 경로 (새 구조)
VNC_IMAGES_DIR = "/opt/apptainers"           # 읽기 전용 이미지 저장소
VNC_SANDBOXES_DIR = "/scratch/vnc_sandboxes" # 쓰기 가능 샌드박스
VNC_SESSIONS_DIR = "/scratch/vnc_sessions"   # 세션 데이터
VNC_LOG_DIR = "/scratch/vnc_logs"            # 로그 (재부팅 후에도 유지)

# 사용 가능한 VNC 이미지 목록
VNC_IMAGES = {
    "xfce4": {
        "name": "XFCE4 Desktop",
        "description": "Lightweight desktop environment with XFCE4",
        "sif_path": f"{VNC_IMAGES_DIR}/vnc_desktop.sif",
        "start_script": "/opt/scripts/start_vnc.sh",
        "desktop_env": "XFCE4",
        "icon": "🖥️",
        "default": True
    },
    "gnome": {
        "name": "GNOME Desktop",
        "description": "Full-featured Ubuntu GNOME desktop environment",
        "sif_path": f"{VNC_IMAGES_DIR}/vnc_gnome.sif",
        "start_script": "/opt/scripts/start_vnc_gnome.sh",
        "desktop_env": "GNOME",
        "icon": "🎨",
        "default": False
    },
    "gnome_lsprepost": {
        "name": "GNOME + LS-PrePost 4.12",
        "description": "GNOME Desktop with LS-PrePost 4.12.8 pre-installed",
        "sif_path": f"{VNC_IMAGES_DIR}/vnc_gnome_lsprepost.sif",
        "start_script": "/opt/scripts/start_vnc_gnome.sh",
        "desktop_env": "GNOME",
        "icon": "🔧",
        "default": False
    }
}

# 노드명 -> IP 매핑 (DNS가 없는 경우를 위한 하드코딩)
NODE_IP_MAP = {
    'viz-node001': '192.168.122.252',
    'node001': '192.168.122.90',
    'node002': '192.168.122.103',
}

# 외부 접근용 IP 주소 - 동적으로 감지
def get_external_ip():
    """Get external IP from environment, YAML config, or system detection."""
    # 1. 환경변수에서 먼저 확인
    if os.getenv('EXTERNAL_IP'):
        return os.getenv('EXTERNAL_IP')

    # 2. YAML 설정 파일에서 확인
    yaml_paths = [
        os.path.join(os.path.dirname(__file__), '..', '..', 'my_multihead_cluster.yaml'),
        '/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_multihead_cluster.yaml',
    ]
    for yaml_path in yaml_paths:
        if os.path.exists(yaml_path):
            try:
                import yaml
                with open(yaml_path) as f:
                    config = yaml.safe_load(f)
                    # controllers 섹션에서 현재 호스트의 public_ip 가져오기
                    controllers = config.get('controllers', [])
                    hostname = subprocess.getoutput('hostname').strip()
                    for ctrl in controllers:
                        if ctrl.get('hostname') == hostname and ctrl.get('public_ip'):
                            return ctrl['public_ip']
                    # network 섹션에서 public_ip 가져오기
                    public_ip = config.get('network', {}).get('public_ip')
                    if public_ip:
                        return public_ip
            except Exception:
                pass

    # 3. 시스템에서 기본 네트워크 인터페이스 IP 감지
    try:
        result = subprocess.getoutput("hostname -I | awk '{print $1}'").strip()
        if result and result != '127.0.0.1':
            return result
    except Exception:
        pass

    # 4. Fallback - localhost
    return 'localhost'

EXTERNAL_IP = get_external_ip()

# SSH 터널 관리 (PID 저장)
SSH_TUNNEL_PIDS = {}  # {session_id: pid}

# Blueprint 생성
vnc_bp = Blueprint('vnc', __name__, url_prefix='/api/vnc')


# ==================== Helper Functions ====================

def check_image_exists_on_remote_node(sif_path, node='viz-node001', partition='viz'):
    """
    원격 노드에서 이미지 파일 존재 확인

    Args:
        sif_path: SIF 파일 경로 (예: /opt/apptainers/vnc_desktop.sif)
        node: 확인할 노드 (기본값: viz-node001)
        partition: 파티션 타입 (viz 또는 compute)

    Returns:
        bool: 파일 존재 여부

    Note:
        - VNC 이미지는 viz-node에만 존재
        - Compute 이미지는 compute-node에 존재
        - Backend(headnode)에는 메타데이터(JSON)만 존재
    """
    try:
        # SSH로 원격 노드에서 파일 존재 확인
        # timeout 5초로 빠르게 확인
        result = subprocess.run(
            ['ssh', '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=no',
             node, f'test -f {sif_path} && echo "exists"'],
            capture_output=True,
            text=True,
            timeout=5
        )

        exists = 'exists' in result.stdout

        if exists:
            print(f"✅ Image found on {node}: {sif_path}")
        else:
            print(f"⚠️  Image NOT found on {node}: {sif_path}")

        return exists

    except subprocess.TimeoutExpired:
        print(f"⚠️  SSH timeout checking image on {node}: {sif_path}")
        return False
    except Exception as e:
        print(f"❌ Error checking image on {node}: {e}")
        return False


def create_ssh_tunnel(node, remote_port, local_port, session_id):
    """
    SSH 포트포워딩 터널 생성

    Controller에서 viz-node로 SSH 터널 생성:
    Controller:local_port → SSH → viz-node:remote_port

    이렇게 하면 외부에서 Controller:local_port로 접속하면
    자동으로 viz-node:remote_port로 포워딩됨
    """
    try:
        # SSH 터널 명령어 (-f: 백그라운드, -N: 명령 실행 안함, -T: TTY 할당 안함, -g: 외부 접속 허용)
        cmd = [
            'ssh',
            '-f',  # 백그라운드 실행
            '-N',  # 원격 명령 실행 안함 (터널만)
            '-T',  # TTY 할당 안함
            '-g',  # GatewayPorts - 외부에서 포트포워딩 접속 허용
            '-o', 'StrictHostKeyChecking=no',  # SSH key 확인 스킵 (내부 네트워크)
            '-o', 'ServerAliveInterval=60',     # Keep-alive 60초
            '-o', 'ServerAliveCountMax=3',      # 3번 실패 시 종료
            '-L', f'0.0.0.0:{local_port}:localhost:{remote_port}',  # 포트포워딩 (모든 인터페이스에서 접속 가능)
            node
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise Exception(f"SSH tunnel failed: {result.stderr}")

        # SSH 터널 프로세스 PID 찾기 (포트 기반)
        # ssh -f 는 PID를 직접 반환하지 않으므로, ps로 찾아야 함
        ps_cmd = ['ps', 'aux']
        ps_result = subprocess.run(ps_cmd, capture_output=True, text=True)

        for line in ps_result.stdout.split('\n'):
            if f'ssh -f -N -T -g' in line and f'0.0.0.0:{local_port}:localhost:{remote_port}' in line and node in line:
                pid = int(line.split()[1])
                SSH_TUNNEL_PIDS[session_id] = pid
                print(f"✅ SSH tunnel created: {node}:{remote_port} → 0.0.0.0:{local_port} (PID: {pid})")
                return pid

        print(f"⚠️  SSH tunnel created but PID not found for session {session_id}")
        return None

    except Exception as e:
        print(f"❌ Failed to create SSH tunnel: {e}")
        raise


def close_ssh_tunnel(session_id):
    """SSH 터널 종료"""
    try:
        pid = SSH_TUNNEL_PIDS.get(session_id)
        if pid:
            subprocess.run(['kill', str(pid)], check=False)
            del SSH_TUNNEL_PIDS[session_id]
            print(f"✅ SSH tunnel closed for session {session_id} (PID: {pid})")
        else:
            print(f"⚠️  No SSH tunnel PID found for session {session_id}")
    except Exception as e:
        print(f"❌ Failed to close SSH tunnel: {e}")


def get_available_vnc_port():
    """사용 가능한 VNC 포트 찾기"""
    # Redis에서 사용 중인 포트 조회
    if REDIS_AVAILABLE and vnc_session_manager:
        used_ports = set()
        all_sessions = vnc_session_manager.list_sessions()
        for session in all_sessions:
            if session.get('vnc_port'):
                used_ports.add(session['vnc_port'])
    else:
        used_ports = {s.get('vnc_port') for s in vnc_sessions_memory.values() if s.get('vnc_port')}

    # 랜덤 포트 할당
    for _ in range(100):  # 최대 100번 시도
        port = random.randint(VNC_PORT_RANGE_START, VNC_PORT_RANGE_END)
        if port not in used_ports:
            return port

    raise Exception("No available VNC ports")


def generate_vnc_job_script(username, session_id, vnc_port, novnc_port, geometry, duration_hours, sif_image_path, start_script, desktop_env, image_id):
    """VNC 세션용 Slurm Job 스크립트 생성"""

    display_num = vnc_port - 5900

    script = f"""#!/bin/bash
#SBATCH --job-name=vnc-{username}
#SBATCH --partition=viz
#SBATCH --nodes=1
#SBATCH --time={duration_hours}:00:00
#SBATCH --chdir=/tmp
#SBATCH --output={VNC_LOG_DIR}/vnc-{username}-%j.out
#SBATCH --error={VNC_LOG_DIR}/vnc-{username}-%j.err

# 로그 디렉토리 생성
mkdir -p {VNC_LOG_DIR}

echo "========================================"
echo "VNC Session Starting"
echo "User: {username}"
echo "Session ID: {session_id}"
echo "VNC Port: {vnc_port}"
echo "noVNC Port: {novnc_port}"
echo "Display: :{display_num}"
echo "Geometry: {geometry}"
echo "Image: {sif_image_path}"
echo "Node: $(hostname)"
echo "========================================"

# 사용자+이미지별 Sandbox 디렉토리 (viz-node에 저장)
SANDBOX_BASE={VNC_SANDBOXES_DIR}
USER_SANDBOX=$SANDBOX_BASE/{username}_{image_id}
INSTANCE_NAME="vnc-{username}-{image_id}"

# Sandbox가 존재하지 않으면 생성
if [ ! -d "$USER_SANDBOX" ]; then
    echo "Creating user sandbox for {username}..."
    mkdir -p $SANDBOX_BASE
    apptainer build --sandbox $USER_SANDBOX {sif_image_path}
    echo "Sandbox created at $USER_SANDBOX"
else
    echo "Using existing sandbox at $USER_SANDBOX"
    # 기존 sandbox의 세션 정보 정리
    echo "Cleaning up old session files in sandbox..."
    rm -rf $USER_SANDBOX/tmp/.X*-lock 2>/dev/null || true
    rm -rf $USER_SANDBOX/tmp/.X11-unix/* 2>/dev/null || true
    rm -rf $USER_SANDBOX/home/*/.cache/sessions/* 2>/dev/null || true
    rm -rf $USER_SANDBOX/root/.cache/sessions/* 2>/dev/null || true
fi

# 기존 Instance가 있으면 중지 (완전히 재시작)
echo "Checking for existing apptainer instance: $INSTANCE_NAME"
if apptainer instance list | grep -q $INSTANCE_NAME; then
    echo "Stopping existing instance and killing all processes..."
    # Instance 내부의 모든 VNC/XFCE 프로세스 강제 종료
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfce4-session 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfce4-panel 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfwm4 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfdesktop 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfce4-screensaver 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfconfd 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 dbus-daemon 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 dbus-launch 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 Xtigervnc 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 gnome-session 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 gnome-shell 2>/dev/null || true
    sleep 2
    # Instance 종료
    apptainer instance stop $INSTANCE_NAME 2>/dev/null || true
    sleep 2
fi

# 사용자별 홈 디렉토리 설정
USER_HOME_DIR="/home/{username}"
echo "Setting up user home directory: $USER_HOME_DIR"
mkdir -p $USER_SANDBOX$USER_HOME_DIR

# Apptainer Instance 시작 (지속적 실행, 사용자 홈 디렉토리 바인드)
echo "Starting apptainer instance: $INSTANCE_NAME"
apptainer instance start --writable --nv --home $USER_SANDBOX$USER_HOME_DIR:$USER_HOME_DIR $USER_SANDBOX $INSTANCE_NAME

# Instance 내부에서 세션 소켓 파일 정리 (매우 중요!)
echo "Cleaning up session socket files inside instance..."
apptainer exec instance://$INSTANCE_NAME /bin/bash -c "rm -rf /tmp/.ICE-unix/* /tmp/.X11-unix/* /tmp/.X*-lock 2>/dev/null || true"

# Instance 내부에서 VNC + Desktop 시작 (이미지별 스크립트 사용)
echo "Starting VNC + {desktop_env} using {start_script} script..."
apptainer exec --cleanenv instance://$INSTANCE_NAME /bin/bash -c "VNC_PORT={vnc_port} VNC_GEOMETRY={geometry} {start_script} {display_num}" > /tmp/vnc_{username}_{display_num}.log 2>&1 &

sleep 10
echo 'VNC server and {desktop_env} started in instance'

# noVNC websockify 시작 (호스트에서 실행)
echo 'Starting noVNC websockify on port {novnc_port}...'
apptainer exec instance://$INSTANCE_NAME websockify --web=/opt/noVNC {novnc_port} localhost:{vnc_port} &
WEBSOCKIFY_PID=$!

echo 'noVNC websockify started'
echo '========================================'
echo 'VNC Session Ready'
echo 'VNC URL: vnc://$(hostname):{vnc_port}'
echo 'noVNC URL: http://$(hostname):{novnc_port}/vnc.html'
echo '========================================'

# Cleanup handler
cleanup() {{
    echo 'Terminating VNC session...'
    apptainer exec instance://$INSTANCE_NAME vncserver -kill :{display_num} 2>/dev/null || true
    kill $WEBSOCKIFY_PID 2>/dev/null || true
    apptainer instance stop $INSTANCE_NAME 2>/dev/null || true
    echo 'VNC session and instance terminated'
}}

trap cleanup EXIT INT TERM

# Job이 종료될 때까지 대기
echo 'VNC session is running. Press Ctrl+C or scancel to terminate.'
while true; do
    # Instance가 살아있는지 확인
    if ! apptainer instance list | grep -q $INSTANCE_NAME; then
        echo 'ERROR: Instance stopped unexpectedly'
        exit 1
    fi
    sleep 10
done

# 정리 (Instance 종료, Sandbox는 재사용을 위해 유지)
echo "VNC Session Terminated (Sandbox preserved for reuse)"
"""
    return script


def submit_vnc_job(username, session_id, vnc_port, novnc_port, geometry, duration_hours, sif_image_path, start_script, desktop_env, image_id):
    """Slurm Job 제출"""

    if MOCK_MODE:
        # Mock 모드: 가짜 Job ID 반환
        mock_job_id = random.randint(10000, 99999)
        print(f"[MOCK] VNC Job submitted: {mock_job_id}")
        return mock_job_id

    # 실제 Slurm Job 제출
    job_script = generate_vnc_job_script(
        username, session_id, vnc_port, novnc_port, geometry, duration_hours, sif_image_path, start_script, desktop_env, image_id
    )

    # 임시 파일에 스크립트 저장
    script_path = f"/tmp/vnc_job_{session_id}.sh"
    with open(script_path, 'w') as f:
        f.write(job_script)

    # sbatch 실행
    result = subprocess.run(
        [SBATCH, script_path],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        raise Exception(f"Job submission failed: {result.stderr}")

    # Job ID 추출
    job_id = int(result.stdout.strip().split()[-1])

    # 스크립트 파일 보존 (디버깅용)
    # os.remove(script_path)

    return job_id


def get_job_status(job_id):
    """Slurm Job 상태 조회"""

    if MOCK_MODE:
        # Mock 모드: 랜덤 상태 반환
        statuses = ['PENDING', 'RUNNING', 'RUNNING', 'RUNNING']  # RUNNING 확률 높게
        return random.choice(statuses)

    # 실제 squeue 실행
    result = subprocess.run(
        [SQUEUE, '--job', str(job_id), '--noheader', '--format=%T'],
        capture_output=True,
        text=True
    )

    if result.returncode != 0 or not result.stdout.strip():
        # Job이 완료되었거나 없음
        return 'COMPLETED'

    return result.stdout.strip()


def get_job_node(job_id):
    """Job이 실행 중인 노드 조회 - IP 주소 반환"""

    if MOCK_MODE:
        # Mock 모드: 가짜 노드 반환
        return random.choice(['node001', 'node002'])

    # 실제 scontrol 실행
    result = subprocess.run(
        [SCONTROL, 'show', 'job', str(job_id)],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        return None

    # NodeList 추출 (ReqNodeList, ExcNodeList 제외)
    node_name = None
    for line in result.stdout.split('\n'):
        # 정확히 "NodeList="만 찾고, ReqNodeList와 ExcNodeList는 제외
        if 'NodeList=' in line and 'ReqNodeList=' not in line and 'ExcNodeList=' not in line:
            node_name = line.split('NodeList=')[1].split()[0]
            break

    if not node_name:
        return None

    # 노드의 IP 주소 조회 (SSH 연결용)
    node_result = subprocess.run(
        [SCONTROL, 'show', 'node', node_name],
        capture_output=True,
        text=True
    )

    if node_result.returncode == 0:
        for line in node_result.stdout.split('\n'):
            if 'NodeAddr=' in line:
                # NodeAddr 추출
                node_addr = line.split('NodeAddr=')[1].split()[0]
                print(f"📍 Node {node_name} IP: {node_addr}")
                return node_addr

    # IP를 못 찾으면 호스트명 반환
    return node_name


def save_vnc_session(session_id, session_data, ttl_hours=8):
    """VNC 세션 정보 저장"""

    if REDIS_AVAILABLE and vnc_session_manager:
        # Use RedisSessionManager with custom TTL
        vnc_session_manager.create_session(session_id, session_data, ttl=ttl_hours * 3600)
    else:
        vnc_sessions_memory[session_id] = session_data


def get_vnc_session(session_id):
    """VNC 세션 정보 조회"""

    if REDIS_AVAILABLE and vnc_session_manager:
        return vnc_session_manager.get_session(session_id)
    else:
        return vnc_sessions_memory.get(session_id)


def get_user_vnc_sessions(username):
    """사용자의 모든 VNC 세션 조회"""

    sessions = []

    if REDIS_AVAILABLE and vnc_session_manager:
        # Get all sessions and filter by username
        all_sessions = vnc_session_manager.list_sessions()
        sessions = [s for s in all_sessions if s.get('username') == username]
    else:
        sessions = [s for s in vnc_sessions_memory.values() if s.get('username') == username]

    return sessions


def delete_vnc_session(session_id):
    """VNC 세션 삭제"""

    if REDIS_AVAILABLE and vnc_session_manager:
        vnc_session_manager.delete_session(session_id)
    else:
        if session_id in vnc_sessions_memory:
            del vnc_sessions_memory[session_id]


# ==================== API Endpoints ====================

@vnc_bp.route('/sessions', methods=['POST'])
@jwt_required
@group_required('HPC-Admins', 'HPC-Users', 'GPU-Users')
def create_vnc_session():
    """
    VNC 세션 생성

    Request Body:
    {
        "image_id": "xfce4",           # 선택사항, 기본값: "xfce4" (또는 "gnome")
        "geometry": "1920x1080",       # 선택사항, 기본값: 1920x1080
        "duration_hours": 4,           # 선택사항, 기본값: 4시간
        "gpu_count": 1                 # 선택사항, 기본값: 1
    }

    Response:
    {
        "session_id": "vnc-user01-1729123456",
        "job_id": 12345,
        "image_id": "xfce4",
        "vnc_port": 5901,
        "novnc_port": 6901,
        "status": "pending",
        "created_at": "2025-10-16T22:30:00Z"
    }
    """

    user = g.user
    data = request.json or {}

    # 파라미터
    image_id = data.get('image_id', 'xfce4')
    geometry = data.get('geometry', '1920x1080')
    duration_hours = int(data.get('duration_hours', 4))
    gpu_count = int(data.get('gpu_count', 1))

    # 이미지 유효성 검사
    if image_id not in VNC_IMAGES:
        return jsonify({'error': f'Invalid image_id: {image_id}'}), 400

    image_config = VNC_IMAGES[image_id]
    sif_image_path = image_config['sif_path']

    # SIF 이미지 파일 존재 확인 (viz-node에서 확인)
    # Headnode에는 메타데이터(JSON)만 있고, 실제 .sif 파일은 viz-node에만 존재
    if not check_image_exists_on_remote_node(sif_image_path, node='viz-node001', partition='viz'):
        return jsonify({'error': f'Image file not found on viz-node: {sif_image_path}'}), 500

    # 세션 ID 생성
    timestamp = int(time.time())
    session_id = f"vnc-{user['username']}-{timestamp}"

    # VNC 포트 할당
    try:
        vnc_port = get_available_vnc_port()
        novnc_port = vnc_port + NOVNC_PORT_OFFSET
    except Exception as e:
        return jsonify({'error': str(e)}), 500

    # Slurm Job 제출
    try:
        job_id = submit_vnc_job(
            user['username'],
            session_id,
            vnc_port,
            novnc_port,
            geometry,
            duration_hours,
            sif_image_path,
            image_config['start_script'],
            image_config['desktop_env'],
            image_id
        )
    except Exception as e:
        return jsonify({'error': f'Job submission failed: {str(e)}'}), 500

    # 세션 정보 생성
    session_data = {
        'session_id': session_id,
        'job_id': job_id,
        'username': user['username'],
        'email': user.get('email', ''),
        'image_id': image_id,
        'image_name': image_config['name'],
        'vnc_port': vnc_port,
        'novnc_port': novnc_port,
        'geometry': geometry,
        'duration_hours': duration_hours,
        'gpu_count': gpu_count,
        'status': 'pending',
        'node': None,
        'novnc_url': None,
        'created_at': datetime.utcnow().isoformat()
    }

    # Redis에 저장
    save_vnc_session(session_id, session_data, ttl_hours=duration_hours + 1)

    return jsonify(session_data), 201


@vnc_bp.route('/sessions', methods=['GET'])
@jwt_required
def list_vnc_sessions():
    """
    사용자의 VNC 세션 목록 조회

    Response:
    {
        "sessions": [
            {
                "session_id": "vnc-user01-1729123456",
                "job_id": 12345,
                "status": "running",
                "node": "node001",
                "novnc_url": "http://node001:6901/vnc.html",
                "created_at": "2025-10-16T22:30:00Z"
            }
        ]
    }
    """

    user = g.user

    # 사용자의 세션 조회
    sessions = get_user_vnc_sessions(user['username'])

    # Job 상태 업데이트 및 완료된 세션 정리
    active_sessions = []
    for session in sessions:
        job_id = session.get('job_id')

        if job_id:
            # Slurm Job 상태 조회
            status = get_job_status(job_id)
            session['status'] = status.lower()

            # COMPLETED, FAILED, CANCELLED, COMPLETING 상태면 세션 자동 삭제
            if status in ['COMPLETED', 'COMPLETING', 'FAILED', 'CANCELLED', 'TIMEOUT', 'NODE_FAIL']:
                print(f"🗑️  Auto-deleting VNC session {session['session_id']} (Job {job_id} status: {status})")
                # SSH 터널 종료
                close_ssh_tunnel(session['session_id'])
                # Redis에서 세션 삭제
                delete_vnc_session(session['session_id'])
                # 이 세션은 목록에 포함하지 않음
                continue

            # RUNNING 상태이면 노드 정보 조회 및 SSH 터널 생성
            if status == 'RUNNING':
                node = get_job_node(job_id)
                if node:
                    session['node'] = node
                    novnc_port = session['novnc_port']
                    session_id = session['session_id']

                    # SSH 터널이 아직 생성되지 않았으면 생성
                    if session_id not in SSH_TUNNEL_PIDS:
                        try:
                            # Controller에서 viz-node로 SSH 터널 생성
                            # viz-node:novnc_port → Controller:novnc_port
                            create_ssh_tunnel(node, novnc_port, novnc_port, session_id)
                            print(f"📡 SSH tunnel created for session {session_id}: {node}:{novnc_port} → localhost:{novnc_port}")
                        except Exception as e:
                            print(f"⚠️  SSH tunnel creation failed for {session_id}: {e}")

                    # 외부 접근 가능한 URL 생성 (nginx reverse proxy 경로 사용)
                    # autoconnect=true: 자동 연결
                    # resize=scale: 브라우저 창 크기에 맞게 자동 스케일링
                    # nginx에서 /vncproxy/<port>/ 로 프록시됨
                    session['novnc_url'] = f"/vncproxy/{novnc_port}/vnc.html?autoconnect=true&resize=scale"

            # 세션 상태 업데이트 (모든 상태에 대해 저장)
            save_vnc_session(session['session_id'], session)

        # 활성 세션 목록에 추가
        active_sessions.append(session)

    return jsonify({'sessions': active_sessions}), 200


@vnc_bp.route('/sessions/<session_id>', methods=['GET'])
@jwt_required
def get_vnc_session_detail(session_id):
    """
    VNC 세션 상세 정보 조회
    """

    user = g.user

    # 세션 조회
    session = get_vnc_session(session_id)

    if not session:
        return jsonify({'error': 'Session not found'}), 404

    # 권한 확인 (본인 또는 관리자)
    if session['username'] != user['username'] and 'HPC-Admins' not in user.get('groups', []):
        return jsonify({'error': 'Permission denied'}), 403

    # Job 상태 업데이트
    job_id = session.get('job_id')
    if job_id:
        status = get_job_status(job_id)
        session['status'] = status.lower()

        if status == 'RUNNING':
            node = get_job_node(job_id)
            if node:
                session['node'] = node
                novnc_port = session['novnc_port']

                # SSH 터널이 아직 생성되지 않았으면 생성
                if session_id not in SSH_TUNNEL_PIDS:
                    try:
                        # Controller에서 viz-node로 SSH 터널 생성
                        create_ssh_tunnel(node, novnc_port, novnc_port, session_id)
                        print(f"📡 SSH tunnel created for session {session_id}: {node}:{novnc_port} → localhost:{novnc_port}")
                    except Exception as e:
                        print(f"⚠️  SSH tunnel creation failed for {session_id}: {e}")

                # 외부 접근 가능한 URL 생성 (nginx reverse proxy 경로 사용)
                # autoconnect=true: 자동 연결
                # resize=scale: 브라우저 창 크기에 맞게 자동 스케일링
                # nginx에서 /vncproxy/<port>/ 로 프록시됨
                session['novnc_url'] = f"/vncproxy/{novnc_port}/vnc.html?autoconnect=true&resize=scale"

    return jsonify(session), 200


@vnc_bp.route('/sessions/<session_id>', methods=['DELETE'])
@jwt_required
def delete_vnc_session_endpoint(session_id):
    """
    VNC 세션 종료
    """

    user = g.user

    # 세션 조회
    session = get_vnc_session(session_id)

    if not session:
        return jsonify({'error': 'Session not found'}), 404

    # 권한 확인 (본인 또는 관리자)
    if session['username'] != user['username'] and 'HPC-Admins' not in user.get('groups', []):
        return jsonify({'error': 'Permission denied'}), 403

    # Slurm Job 취소
    job_id = session.get('job_id')
    if job_id:
        if MOCK_MODE:
            print(f"[MOCK] Cancelling VNC Job: {job_id}")
        else:
            subprocess.run([SCANCEL, str(job_id)], capture_output=True)

    # SSH 터널 종료
    close_ssh_tunnel(session_id)

    # Redis 세션 삭제
    delete_vnc_session(session_id)

    return jsonify({'message': 'Session terminated successfully'}), 200


# ==================== Session Reset/Delete Endpoint ====================

@vnc_bp.route('/sessions/<session_id>/reset', methods=['POST'])
@jwt_required
def reset_vnc_sandbox(session_id):
    """
    VNC 세션의 Sandbox를 삭제하고 초기화

    다음 세션 생성 시 Sandbox가 새로 생성됩니다.
    현재 실행 중인 세션은 종료됩니다.
    """

    user = g.user

    # 세션 조회
    session = get_vnc_session(session_id)

    if not session:
        return jsonify({'error': 'Session not found'}), 404

    # 권한 확인 (본인 또는 관리자)
    if session['username'] != user['username'] and 'HPC-Admins' not in user.get('groups', []):
        return jsonify({'error': 'Permission denied'}), 403

    # Slurm Job 취소
    job_id = session.get('job_id')
    if job_id:
        if MOCK_MODE:
            print(f"[MOCK] Cancelling VNC Job: {job_id}")
        else:
            subprocess.run([SCANCEL, str(job_id)], capture_output=True)

    # Sandbox 삭제 (viz-node에서 실행)
    username = session['username']
    sandbox_path = f"{VNC_SANDBOXES_DIR}/{username}"

    try:
        if MOCK_MODE:
            print(f"[MOCK] Deleting sandbox: {sandbox_path}")
        else:
            # SSH로 viz-node에서 실행 (또는 로컬에서 직접 삭제)
            result = subprocess.run(
                ['rm', '-rf', sandbox_path],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return jsonify({'error': f'Failed to delete sandbox: {result.stderr}'}), 500

    except Exception as e:
        return jsonify({'error': f'Failed to delete sandbox: {str(e)}'}), 500

    # Redis 세션 삭제
    delete_vnc_session(session_id)

    return jsonify({
        'message': 'Sandbox reset successfully',
        'sandbox_path': sandbox_path,
        'deleted': True
    }), 200


# ==================== Images Endpoint ====================

@vnc_bp.route('/images', methods=['GET'])
@jwt_required
def list_vnc_images():
    """
    사용 가능한 VNC 이미지 목록 조회

    Response:
    {
        "images": [
            {
                "id": "xfce4",
                "name": "XFCE4 Desktop",
                "description": "Lightweight desktop environment with XFCE4",
                "icon": "🖥️",
                "default": true,
                "available": true
            }
        ]
    }
    """

    images_list = []

    for image_id, config in VNC_IMAGES.items():
        # VNC 이미지는 viz-node에 존재하므로 원격에서 확인
        # (Headnode에는 메타데이터(JSON)만 존재)
        image_available = check_image_exists_on_remote_node(
            config['sif_path'],
            node='viz-node001',
            partition='viz'
        )

        image_info = {
            'id': image_id,
            'name': config['name'],
            'description': config['description'],
            'icon': config.get('icon', '🖥️'),
            'default': config.get('default', False),
            'available': image_available
        }
        images_list.append(image_info)

    return jsonify({'images': images_list}), 200


# ==================== Admin Endpoints ====================

@vnc_bp.route('/sessions/all', methods=['GET'])
@jwt_required
@group_required('HPC-Admins')
def list_all_vnc_sessions():
    """
    모든 VNC 세션 조회 (관리자 전용)
    """

    all_sessions = []

    if REDIS_AVAILABLE and vnc_session_manager:
        # Use RedisSessionManager to list all sessions
        all_sessions = vnc_session_manager.list_sessions(include_data=True)

        # Update job status for each session
        for session in all_sessions:
            job_id = session.get('job_id')
            if job_id:
                status = get_job_status(job_id)
                session['status'] = status.lower()
    else:
        all_sessions = list(vnc_sessions_memory.values())

        # Update job status for memory sessions too
        for session in all_sessions:
            job_id = session.get('job_id')
            if job_id:
                status = get_job_status(job_id)
                session['status'] = status.lower()

    return jsonify({'sessions': all_sessions, 'total': len(all_sessions)}), 200


# VNC Readiness Check - 실제로 VNC 포트가 listening하는지 확인
@vnc_bp.route('/sessions/<session_id>/ready', methods=['GET'])
@jwt_required
def check_vnc_readiness(session_id):
    """
    VNC 세션이 실제로 연결 가능한지 확인

    노드에 SSH로 접속해서 VNC 포트가 listening하는지 확인
    """
    user = g.user

    # 세션 조회
    session = get_vnc_session(session_id)

    if not session:
        return jsonify({'error': 'Session not found'}), 404

    # 권한 확인
    if session['username'] != user['username'] and 'HPC-Admins' not in user.get('groups', []):
        return jsonify({'error': 'Permission denied'}), 403

    # Status가 running이 아니면 not ready
    if session.get('status', '').lower() != 'running':
        return jsonify({
            'ready': False,
            'reason': f"Session status is {session.get('status', 'unknown')}"
        }), 200

    # 노드와 포트 정보
    node = session.get('node')
    vnc_port = session.get('vnc_port')
    novnc_port = session.get('novnc_port')

    if not node or not vnc_port:
        return jsonify({
            'ready': False,
            'reason': 'Node or port information not available'
        }), 200

    # VNC 포트 체크 (SSH를 통해 원격 노드에서 확인)
    try:
        # lsof로 VNC 포트가 listening하는지 확인 (빠른 체크)
        check_cmd = f"ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=no {os.getenv('USER')}@{node} 'lsof -i :{vnc_port} | grep LISTEN' 2>/dev/null"
        result = subprocess.run(
            check_cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=2
        )

        vnc_ready = result.returncode == 0 and 'LISTEN' in result.stdout

        # noVNC 포트도 체크 (빠른 체크)
        check_novnc_cmd = f"ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=no {os.getenv('USER')}@{node} 'lsof -i :{novnc_port} | grep LISTEN' 2>/dev/null"
        result_novnc = subprocess.run(
            check_novnc_cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=2
        )

        novnc_ready = result_novnc.returncode == 0 and 'LISTEN' in result_novnc.stdout

        ready = vnc_ready and novnc_ready

        return jsonify({
            'ready': ready,
            'vnc_port_ready': vnc_ready,
            'novnc_port_ready': novnc_ready,
            'node': node,
            'vnc_port': vnc_port,
            'novnc_port': novnc_port
        }), 200

    except subprocess.TimeoutExpired:
        return jsonify({
            'ready': False,
            'reason': 'Timeout while checking ports'
        }), 200
    except Exception as e:
        return jsonify({
            'ready': False,
            'reason': f'Error checking readiness: {str(e)}'
        }), 200


# Health Check
@vnc_bp.route('/health', methods=['GET'])
def vnc_health():
    """VNC API Health Check"""

    return jsonify({
        'status': 'healthy',
        'mock_mode': MOCK_MODE,
        'slurm_available': SLURM_AVAILABLE,
        'redis_available': REDIS_AVAILABLE,
        'sif_image_path': SIF_IMAGE_PATH,
        'sif_image_exists': os.path.exists(SIF_IMAGE_PATH),
        'sessions_dir': VNC_SESSIONS_DIR,
        'sessions_dir_exists': os.path.exists(VNC_SESSIONS_DIR)
    }), 200
