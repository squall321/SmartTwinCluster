"""
VNC Session Management API
GPU 기반 원격 데스크톱 세션 생성 및 관리
"""

import os
import re
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

# Slurm 명령어 및 시스템 명령어 (절대 경로)
try:
    from slurm_commands import SBATCH, SCANCEL, SQUEUE, SCONTROL, SSH, KILL, RM
    from slurm_commands import SSH_KEY_PATH as SLURM_SSH_KEY_PATH
    from slurm_commands import get_ssh_opts as slurm_get_ssh_opts
    SLURM_AVAILABLE = True
except ImportError:
    SLURM_AVAILABLE = False
    SLURM_SSH_KEY_PATH = None
    slurm_get_ssh_opts = None
    # Fallback paths
    SSH = '/usr/bin/ssh'
    KILL = '/bin/kill'
    RM = '/bin/rm'

# YAML에서 기본 SSH 사용자 조회 (VNC 세션용)
try:
    from yaml_node_loader import get_ssh_user_for_node, load_yaml_config
    def get_default_system_user():
        """YAML에서 기본 시스템 사용자 가져오기"""
        config = load_yaml_config()
        if config:
            # controllers의 첫 번째 ssh_user 사용
            controllers = config.get('nodes', {}).get('controllers', [])
            if controllers:
                return controllers[0].get('ssh_user', 'koopark')
        return 'koopark'
except ImportError:
    def get_default_system_user():
        return 'koopark'

# Mock 모드
MOCK_MODE = os.getenv('MOCK_MODE', 'false').lower() == 'true'

# SSH 키 설정 - slurm_commands에서 가져온 값 사용
# slurm_commands 모듈이 SSH 키 자동 탐지를 담당
if SLURM_AVAILABLE and SLURM_SSH_KEY_PATH:
    SSH_KEY_PATH = SLURM_SSH_KEY_PATH
    get_ssh_opts = slurm_get_ssh_opts
    print(f"✅ VNC SSH key (from slurm_commands): {SSH_KEY_PATH}")
else:
    # Fallback: 직접 탐지
    def _get_ssh_key_path():
        """SSH 키 경로 자동 탐지 (fallback)"""
        import pwd
        # 환경변수
        env_key = os.getenv('SSH_KEY_FILE') or os.getenv('SSH_KEY_PATH')
        if env_key and os.path.exists(env_key):
            return env_key
        # SUDO_USER
        sudo_user = os.getenv('SUDO_USER')
        if sudo_user:
            try:
                user_home = pwd.getpwnam(sudo_user).pw_dir
                key_path = os.path.join(user_home, '.ssh', 'id_rsa')
                if os.path.exists(key_path):
                    return key_path
            except KeyError:
                pass
        # 현재 사용자
        home = os.path.expanduser('~')
        key_path = os.path.join(home, '.ssh', 'id_rsa')
        if os.path.exists(key_path):
            return key_path
        # 일반적인 서비스 계정
        for user in ['koopark', 'hpcadmin', 'slurm']:
            try:
                user_home = pwd.getpwnam(user).pw_dir
                key_path = os.path.join(user_home, '.ssh', 'id_rsa')
                if os.path.exists(key_path):
                    return key_path
            except KeyError:
                continue
        return None

    SSH_KEY_PATH = _get_ssh_key_path()
    if SSH_KEY_PATH:
        print(f"✅ VNC SSH key (fallback): {SSH_KEY_PATH}")
    else:
        print("⚠️  No SSH key found - SSH connections may fail")

    def get_ssh_opts():
        """SSH 공통 옵션 반환"""
        opts = [
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=/dev/null',
            '-o', 'LogLevel=ERROR',
            '-o', 'BatchMode=yes',
        ]
        if SSH_KEY_PATH:
            opts = ['-i', SSH_KEY_PATH] + opts
        return opts

# VNC 설정
VNC_PORT_RANGE_START = 5901
VNC_PORT_RANGE_END = 5999
NOVNC_PORT_OFFSET = 1000  # noVNC 포트 = VNC 포트 + 1000

# VNC 이미지 및 작업 디렉토리 경로 (새 구조)
VNC_IMAGES_DIR = "/opt/apptainers"           # 읽기 전용 이미지 저장소
VNC_SANDBOXES_DIR = "/scratch/vnc_sandboxes" # 쓰기 가능 샌드박스
VNC_HOME_BASE = "/mnt/gluster/vnc_home"      # 영속 공유 홈 베이스(GlusterFS 마운트, /shared 심볼릭 아님). phase0_storage.sh에서 chmod 1777 생성.
VNC_SESSIONS_DIR = "/scratch/vnc_sessions"   # 세션 데이터
VNC_LOG_DIR = "/scratch/vnc_logs"            # 로그 — 노드 로컬(항상 존재, [4.5]에서 1777).
                                             # /shared(GlusterFS 심볼릭)는 마운트 실패 시 #SBATCH
                                             # --output 못써서 잡 exit 1 하므로 로컬 경로 사용.

# Health check용 기본 SIF 이미지 경로
SIF_IMAGE_PATH = f"{VNC_IMAGES_DIR}/vnc_desktop.sif"

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

# 노드명 -> IP 매핑 (YAML에서 동적으로 로드)
def load_node_ip_map():
    """YAML 설정에서 노드 IP 매핑 로드"""
    node_map = {}
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
                    nodes_config = config.get('nodes', {})

                    # compute_nodes에서 노드 정보 추출
                    for node in nodes_config.get('compute_nodes', []):
                        hostname = node.get('hostname')
                        ip = node.get('ip_address')
                        if hostname and ip:
                            node_map[hostname] = ip

                    # visualization nodes (node_type: viz)
                    for node in nodes_config.get('compute_nodes', []):
                        if node.get('node_type') == 'viz':
                            hostname = node.get('hostname')
                            ip = node.get('ip_address')
                            if hostname and ip:
                                node_map[hostname] = ip

                    # controllers도 추가
                    for ctrl in nodes_config.get('controllers', []):
                        hostname = ctrl.get('hostname')
                        ip = ctrl.get('ip_address')
                        if hostname and ip:
                            node_map[hostname] = ip

                    if node_map:
                        print(f"✅ Loaded {len(node_map)} nodes from YAML")
                        return node_map
            except Exception as e:
                print(f"⚠️  Failed to load node IP map from YAML: {e}")

    # Fallback: 기본 하드코딩 값
    print("⚠️  Using fallback node IP map")
    return {
        'viz-node001': '192.168.122.252',
        'node001': '192.168.122.90',
        'node002': '192.168.122.103',
    }

NODE_IP_MAP = load_node_ip_map()

# Visualization 노드 목록 (YAML에서 동적으로 로드)
def get_viz_nodes():
    """YAML 설정에서 viz/hybrid 노드 목록 가져오기"""
    viz_nodes = []
    # 환경변수 CLUSTER_YAML 우선, 없으면 my_multihead_cluster.yaml
    yaml_paths = []
    env_path = os.getenv('CLUSTER_YAML')
    if env_path:
        yaml_paths.append(env_path)
    yaml_paths += [
        os.path.join(os.path.dirname(__file__), '..', '..', 'my_multihead_cluster.yaml'),
        '/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_multihead_cluster.yaml',
    ]

    for yaml_path in yaml_paths:
        if os.path.exists(yaml_path):
            try:
                import yaml
                with open(yaml_path) as f:
                    config = yaml.safe_load(f)
                    nodes_config = config.get('nodes', {}) or {}

                    # viz_nodes 섹션이 있으면 거기서
                    for node in (nodes_config.get('viz_nodes') or []):
                        viz_nodes.append({
                            'hostname': node.get('hostname'),
                            'ip_address': node.get('ip_address'),
                            'hardware': node.get('hardware', {})
                        })
                    # compute_nodes 중 node_type == 'viz' 또는 'hybrid' 도 viz 자격
                    for node in (nodes_config.get('compute_nodes') or []):
                        nt = node.get('node_type', 'compute')
                        if nt in ('viz', 'hybrid'):
                            viz_nodes.append({
                                'hostname': node.get('hostname'),
                                'ip_address': node.get('ip_address'),
                                'hardware': node.get('hardware', {})
                            })

                    if viz_nodes:
                        print(f"✅ Found {len(viz_nodes)} viz/hybrid nodes from {yaml_path}")
                        return viz_nodes
            except Exception as e:
                print(f"⚠️  Failed to load viz nodes from {yaml_path}: {e}")

    # Fallback
    print("⚠️  Using fallback viz node (yaml 매칭 실패)")
    return [{'hostname': 'viz-node001', 'ip_address': '192.168.122.252', 'hardware': {}}]

VIZ_NODES = get_viz_nodes()
DEFAULT_VIZ_NODE = VIZ_NODES[0]['hostname'] if VIZ_NODES else 'viz-node001'

# 외부 접근용 IP 주소 - 동적으로 감지
def get_external_ip():
    """외부 접속 주소(도메인 또는 IP) 결정.
    우선순위: 환경변수 EXTERNAL_IP > yaml web.public_url(도메인 발급 시 여기) >
              nodes.controllers[현재호스트].public_ip > 시스템 IP > localhost
    """
    # 1. 환경변수
    if os.getenv('EXTERNAL_IP'):
        return os.getenv('EXTERNAL_IP')

    # 2. YAML — web.public_url 이 정본 (도메인 stcx.sec.samsung.net 등이 여기 들어감)
    yaml_paths = []
    if os.getenv('CLUSTER_YAML'):
        yaml_paths.append(os.getenv('CLUSTER_YAML'))
    yaml_paths += [
        os.path.join(os.path.dirname(__file__), '..', '..', 'my_multihead_cluster.yaml'),
        '/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_multihead_cluster.yaml',
    ]
    for yaml_path in yaml_paths:
        if not yaml_path or not os.path.exists(yaml_path):
            continue
        try:
            import yaml
            with open(yaml_path) as f:
                config = yaml.safe_load(f) or {}
            # (a) web.public_url — 도메인/공개 IP 정본
            pub = ((config.get('web') or {}).get('public_url') or '').strip()
            pub = pub.replace('https://', '').replace('http://', '').rstrip('/')
            if pub and pub not in ('localhost', '127.0.0.1'):
                return pub
            # (b) nodes.controllers 의 현재 호스트 public_ip
            hostname = subprocess.getoutput('hostname').strip()
            for ctrl in (config.get('nodes', {}) or {}).get('controllers', []) or []:
                if ctrl.get('hostname') == hostname and ctrl.get('public_ip'):
                    return ctrl['public_ip']
            # (c) network.public_ip (구버전 호환)
            np = (config.get('network', {}) or {}).get('public_ip')
            if np:
                return np
        except Exception:
            pass

    # 3. 시스템 기본 인터페이스 IP
    try:
        result = subprocess.getoutput("hostname -I | awk '{print $1}'").strip()
        if result and result != '127.0.0.1':
            return result
    except Exception:
        pass

    # 4. Fallback
    return 'localhost'

EXTERNAL_IP = get_external_ip()

# SSH 터널 관리 (PID 저장)
SSH_TUNNEL_PIDS = {}  # {session_id: pid}

# Blueprint 생성
vnc_bp = Blueprint('vnc', __name__, url_prefix='/api/vnc')


# ==================== Helper Functions ====================

def check_image_exists(sif_path, node=None, partition='viz'):
    """
    이미지 파일 존재 확인 (로컬 우선, 원격 fallback)

    Args:
        sif_path: SIF 파일 경로 (예: /opt/apptainers/vnc_desktop.sif)
        node: 확인할 노드 (기본값: DEFAULT_VIZ_NODE)
        partition: 파티션 타입 (viz 또는 compute)

    Returns:
        bool: 파일 존재 여부

    Note:
        - 공유 스토리지(/opt/apptainers)를 사용하는 경우 로컬에서 확인
        - 공유 스토리지가 없으면 원격 노드에서 SSH로 확인
    """
    # 1. 먼저 로컬에서 확인 (공유 스토리지 사용 시)
    if os.path.exists(sif_path):
        print(f"✅ Image found locally: {sif_path}")
        return True

    # 2. 로컬에 없으면 원격 노드에서 확인
    if node is None:
        node = DEFAULT_VIZ_NODE

    # localhost면 로컬 체크만으로 충분
    if node in ['localhost', '127.0.0.1']:
        print(f"⚠️  Image NOT found locally: {sif_path}")
        return False

    try:
        # SSH로 원격 노드에서 파일 존재 확인
        # timeout 3초로 빠르게 확인
        ssh_cmd = [SSH] + get_ssh_opts() + ['-o', 'ConnectTimeout=3', node, f'test -f {sif_path} && echo "exists"']
        result = subprocess.run(
            ssh_cmd,
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
        # SSH 타임아웃 시 로컬 체크 결과 반환 (이미 위에서 False)
        return False
    except Exception as e:
        print(f"❌ Error checking image on {node}: {e}")
        return False


# 이전 함수명 호환성 유지
check_image_exists_on_remote_node = check_image_exists


def _is_local_node(node):
    """node(IP 또는 hostname) 가 이 백엔드가 도는 controller 자신인지 판정.
    controller==viz 동일 물리호스트 환경에서 self-SSH 터널 실패 회피용."""
    try:
        import socket
        # 로컬 호스트네임 + 모든 로컬 IP 수집
        local_names = {socket.gethostname(), socket.getfqdn(), 'localhost', '127.0.0.1'}
        try:
            local_ips = subprocess.getoutput("hostname -I").split()
            local_names.update(local_ips)
        except Exception:
            pass
        if str(node) in local_names:
            return True
        # node 가 hostname 이면 IP 로 해석해서 비교
        try:
            node_ip = socket.gethostbyname(str(node))
            if node_ip in local_names:
                return True
        except Exception:
            pass
    except Exception:
        pass
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
        # node 가 controller 자신(백엔드가 도는 호스트)이면 SSH 터널 불필요.
        # websockify 가 이미 localhost:remote_port 에 떠있고, /vncproxy 는 controller
        # localhost 로 프록시하므로 local_port==remote_port 면 그대로 도달 가능.
        # (controller==viz 동일 물리호스트 환경 — bare ssh self-tunnel 실패 회피)
        if _is_local_node(node):
            if str(local_port) == str(remote_port):
                print(f"ℹ️  {node} 는 controller 자신 — SSH 터널 불필요 (localhost:{remote_port} 직접 사용)")
                SSH_TUNNEL_PIDS[session_id] = None
                return None
            else:
                # 포트가 다르면 로컬 포트포워딩만 (socat 대신 ssh localhost 로 가볍게)
                print(f"ℹ️  {node} 는 controller 자신 — 로컬 포트포워딩 {local_port}→{remote_port}")

        # SSH 터널 명령어 (-f: 백그라운드, -N: 명령 실행 안함, -T: TTY 할당 안함, -g: 외부 접속 허용)
        # SSH 키 경로 포함
        cmd = [SSH]
        if SSH_KEY_PATH:
            cmd += ['-i', SSH_KEY_PATH]
        cmd += [
            '-f',  # 백그라운드 실행
            '-N',  # 원격 명령 실행 안함 (터널만)
            '-T',  # TTY 할당 안함
            '-g',  # GatewayPorts - 외부에서 포트포워딩 접속 허용
            '-o', 'StrictHostKeyChecking=no',  # SSH key 확인 스킵 (내부 네트워크)
            '-o', 'UserKnownHostsFile=/dev/null',
            '-o', 'LogLevel=ERROR',
            '-o', 'ServerAliveInterval=60',     # Keep-alive 60초
            '-o', 'ServerAliveCountMax=3',      # 3번 실패 시 종료
            '-L', f'0.0.0.0:{local_port}:localhost:{remote_port}',  # 포트포워딩 (모든 인터페이스에서 접속 가능)
            f'{get_default_system_user()}@{node}'  # 접속성 체크(1061)와 동일한 user@host 형식으로 통일
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise Exception(f"SSH tunnel failed: {result.stderr}")

        # SSH 터널 프로세스 PID 찾기 (포트 기반)
        # ssh -f 는 PID를 직접 반환하지 않으므로, ps로 찾아야 함
        ps_cmd = ['ps', 'aux']
        ps_result = subprocess.run(ps_cmd, capture_output=True, text=True)

        for line in ps_result.stdout.split('\n'):
            if SSH in line and '-f' in line and '-N' in line and f'0.0.0.0:{local_port}:localhost:{remote_port}' in line and node in line:
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
            subprocess.run([KILL, str(pid)], check=False)
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


def _detect_gpu_type():
    """Slurm gres.conf에서 GPU 타입 자동 감지 (nvidia, amd 등)"""
    try:
        # scontrol show config에서 GresTypes 확인
        result = subprocess.run(
            [SCONTROL, 'show', 'config'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'GresTypes' in line and 'gpu' in line.lower():
                    break

        # gres.conf에서 타입 추출
        for gres_path in ['/etc/slurm/gres.conf', '/opt/slurm/etc/gres.conf', '/usr/local/slurm/etc/gres.conf']:
            try:
                with open(gres_path, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith('#') or not line:
                            continue
                        # NodeName=xxx Name=gpu Type=nvidia File=...
                        if 'Name=gpu' in line and 'Type=' in line:
                            gpu_type = line.split('Type=')[1].split()[0]
                            print(f"GPU type detected from {gres_path}: {gpu_type}")
                            return gpu_type
            except FileNotFoundError:
                continue
    except Exception as e:
        print(f"GPU type detection failed: {e}")
    return None


def _sanitize_web_user(raw):
    """JWT 유래 web_user 를 셸 경로/인스턴스명에 박기 전에 검증+정제.
    허용: [A-Za-z0-9._-] 1~32자. 빈값/'.'/'..'/선행점 거부. 안전치 못하면 None(→400)."""
    if not raw or not isinstance(raw, str):
        return None
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,32}', raw):
        return None
    if raw in ('.', '..') or raw.startswith('.'):
        return None
    return raw


def generate_vnc_job_script(username, session_id, vnc_port, novnc_port, geometry, duration_hours, sif_image_path, start_script, desktop_env, image_id, web_user, gpu_count=0, partition='viz'):
    """VNC 세션용 Slurm Job 스크립트 생성

    username = 시스템 사용자(YAML ssh_user) — Slurm/SSH 식별용(sbatch 프로세스 소유자).
    web_user = 웹 로그인 사용자(JWT sub, sanitize 완료) — sandbox/instance/home 격리 키.
    """

    display_num = vnc_port - 5900

    # GPU 요청 라인 생성 (gpu_count > 0 일 때만)
    # Slurm에서 GPU 타입을 자동 감지 (gres.conf에 gpu:nvidia:N 등으로 등록된 경우 타입 필요)
    gpu_line = ""
    if gpu_count > 0:
        gpu_type = _detect_gpu_type()
        if gpu_type:
            gpu_line = f"#SBATCH --gres=gpu:{gpu_type}:{gpu_count}"
        else:
            gpu_line = f"#SBATCH --gres=gpu:{gpu_count}"

    # apptainer instance start 의 --nv 플래그.
    # gpu_count==0 (GPU 없는 viz 노드)에서 --nv 를 박으면 nvidia-container-cli /
    # libnvidia 를 못 찾아 instance start 가 실패하고, watchdog 가 'exit 1' 로 죽는다.
    # gres 라인과 동일하게 GPU 요청이 있을 때만 --nv 를 넣는다.
    nv_flag = "--nv" if gpu_count > 0 else ""

    script = f"""#!/bin/bash
#SBATCH --job-name=vnc-{web_user}
#SBATCH --partition={partition}
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
{gpu_line}
#SBATCH --time={duration_hours}:00:00
#SBATCH --chdir=/tmp
#SBATCH --output={VNC_LOG_DIR}/vnc-{web_user}-%j.out
#SBATCH --error={VNC_LOG_DIR}/vnc-{web_user}-%j.err

# PATH 명시 — slurm 비대화형 잡은 빈 PATH 로 실행될 수 있어 mkdir/hostname/apptainer
# 등 기본명령조차 'command not found'(rc=127)로 실패한다. apptainer 는 /usr/local/bin.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 로그 디렉토리 생성
mkdir -p {VNC_LOG_DIR}

echo "========================================"
echo "VNC Session Starting"
echo "User: {web_user} (system_user: {username})"
echo "Session ID: {session_id}"
echo "VNC Port: {vnc_port}"
echo "noVNC Port: {novnc_port}"
echo "Display: :{display_num}"
echo "Geometry: {geometry}"
echo "CPU Cores: 16"
echo "Memory: 128G"
echo "GPU Count: {gpu_count}"
echo "Image: {sif_image_path}"
echo "Node: $(hostname)"
echo "========================================"

# 사용자+이미지별 Sandbox 디렉토리 (viz-node에 저장)
SANDBOX_BASE={VNC_SANDBOXES_DIR}
USER_SANDBOX=$SANDBOX_BASE/{web_user}_{image_id}
INSTANCE_NAME="vnc-{web_user}-{image_id}"

# Sandbox가 존재하지 않으면 생성
if [ ! -d "$USER_SANDBOX" ]; then
    echo "Creating user sandbox for {web_user}..."
    mkdir -p $SANDBOX_BASE
    apptainer build --sandbox $USER_SANDBOX {sif_image_path}
    echo "Sandbox created at $USER_SANDBOX"
else
    echo "Using existing sandbox at $USER_SANDBOX"
    # 기존 sandbox의 세션 정보 정리
    echo "Cleaning up old session files in sandbox..."
    rm -rf $USER_SANDBOX/tmp/.X*-lock 2>/dev/null || true
    rm -rf $USER_SANDBOX/tmp/.X11-unix/* 2>/dev/null || true
    rm -rf $USER_SANDBOX/tmp/.ICE-unix/* 2>/dev/null || true
    rm -rf $USER_SANDBOX/tmp/dbus-* 2>/dev/null || true
    # xfce4-session 'Another session manager is already running' 재발 방지 —
    # 재사용 sandbox 홈 안의 저장된 세션/세션락/xfconf 잔재 제거(영속 홈은 아래서 별도 처리).
    for _shome in $USER_SANDBOX/home/* $USER_SANDBOX/root; do
        rm -rf "$_shome/.cache/sessions"/* 2>/dev/null || true
        rm -rf "$_shome/.config/xfce4/sessions"/* 2>/dev/null || true
        rm -rf "$_shome/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" 2>/dev/null || true
        rm -rf "$_shome/.ICEauthority" 2>/dev/null || true
        rm -rf "$_shome/.dbus" 2>/dev/null || true
    done
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

# 사용자별 영속 홈 디렉토리 (GlusterFS 공유 마운트 → 재로그인/재부팅 후에도 보존)
USER_HOME_DIR="/home/{web_user}"
PERSIST_HOME="{VNC_HOME_BASE}/{web_user}"
echo "Setting up user home directory: $USER_HOME_DIR (persist src: $PERSIST_HOME)"
# /mnt/gluster 가 실제 마운트돼 있을 때만 영속 홈 사용. 실패 시 노드-로컬로 폴백(비영속).
if mountpoint -q /mnt/gluster 2>/dev/null; then
    mkdir -p "$PERSIST_HOME" 2>/dev/null
fi
if [ -d "$PERSIST_HOME" ] && touch "$PERSIST_HOME/.vnc_write_test" 2>/dev/null; then
    rm -f "$PERSIST_HOME/.vnc_write_test" 2>/dev/null || true
    HOME_BIND_SRC="$PERSIST_HOME"
    echo "Using PERSISTENT home: $PERSIST_HOME"
else
    HOME_BIND_SRC="$USER_SANDBOX$USER_HOME_DIR"
    mkdir -p "$HOME_BIND_SRC"
    echo "WARNING: {VNC_HOME_BASE} unavailable — NODE-LOCAL home (NON-PERSISTENT): $HOME_BIND_SRC"
fi

# Apptainer Instance 시작 (지속적 실행, 사용자 홈 디렉토리 바인드)
echo "Starting apptainer instance: $INSTANCE_NAME"
apptainer instance start --writable {nv_flag} --home $HOME_BIND_SRC:$USER_HOME_DIR $USER_SANDBOX $INSTANCE_NAME
_START_RC=$?

# instance start 가 실패했으면 즉시 명확히 죽는다 (watchdog 의 모호한 exit 1 대신 진짜 원인 출력).
# set -e 가 없으므로 명시적으로 검사: 종료코드 != 0 이거나 instance 목록에 안 보이면 실패.
if [ $_START_RC -ne 0 ] || ! apptainer instance list 2>/dev/null | grep -q $INSTANCE_NAME; then
    echo "ERROR: apptainer instance start failed (rc=$_START_RC) — instance '$INSTANCE_NAME' not running"
    echo "  nv_flag='{nv_flag}' gpu_count={gpu_count}  (gpu_count=0 인데 --nv 가 들어갔다면 GPU 없는 노드에서 실패)"
    echo "  현재 instance 목록:"
    apptainer instance list 2>&1 | sed 's/^/    /'
    echo "  --- apptainer instance start 로그 ($HOME/.apptainer/instances/logs) ---"
    cat $HOME/.apptainer/instances/logs/$(hostname)/*/$INSTANCE_NAME.err 2>/dev/null | tail -30 | sed 's/^/    /'
    exit 1
fi

# Instance 내부에서 세션 소켓 파일 정리 (매우 중요!)
# 런타임의 /tmp 는 호스트 /tmp 바인드라 sandbox 내부 /tmp 청소는 소용없음 → 여기서(instance 안) 청소.
# 추가로 LIVE 홈($USER_HOME_DIR = 영속 홈 또는 노드-로컬)의 xfce 저장세션/세션락도 제거한다.
# 'Another session manager is already running' 의 실제 원인인 ICE/세션 잔재를 확실히 없앤다.
# 주의: 세션락/ICE 만 지운다 — 사용자 데이터(영속 홈)는 절대 건드리지 않는다.
echo "Cleaning up session socket files inside instance..."
apptainer exec instance://$INSTANCE_NAME /bin/bash -c "rm -rf /tmp/.ICE-unix/* /tmp/.X11-unix/* /tmp/.X*-lock /tmp/dbus-* /tmp/runtime-root/* 2>/dev/null || true"
apptainer exec instance://$INSTANCE_NAME /bin/bash -c 'rm -rf "$HOME/.cache/sessions"/* "$HOME/.config/xfce4/sessions"/* "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" "$HOME/.ICEauthority" "$HOME/.dbus" 2>/dev/null || true'

# Instance 내부에서 VNC + Desktop 시작 (이미지별 스크립트 사용)
echo "Starting VNC + {desktop_env} using {start_script} script..."
# GNOME은 D-Bus, systemd 등 환경변수가 필요하므로 --cleanenv 대신 --env로 필요한 변수만 설정.
# SESSION_MANAGER / DBUS_SESSION_BUS_ADDRESS 를 빈 값으로 강제 주입 — sbatch(호스트) 프로세스의
# SESSION_MANAGER 가 컨테이너로 새면 startxfce4 -> xfce4-session 이 그 ICE 소켓을 보고
# 'Another session manager is already running' 으로 죽는다. xfce start_vnc.sh 는 SESSION_MANAGER 를
# unset 하지 않으므로(gnome 스크립트와 달리) 여기서 빈 값으로 덮어써 누수를 차단한다.
apptainer exec --env "SESSION_MANAGER=,DBUS_SESSION_BUS_ADDRESS=,VNC_PORT={vnc_port},VNC_GEOMETRY={geometry},DISPLAY=:{display_num},XDG_RUNTIME_DIR=/tmp/runtime-root" instance://$INSTANCE_NAME /bin/bash -c "{start_script} {display_num}" > /tmp/vnc_{web_user}_{display_num}.log 2>&1 &

sleep 10
echo 'VNC server and {desktop_env} started in instance'

# websockify 가 VNC 포트({vnc_port})에 붙기 전에 VNC 서버가 실제 LISTEN 하는지 확인.
# (race: VNC 아직 안 떴는데 websockify 가 붙으려다 죽으면 novnc 포트 영영 안 뜸 → '준비중')
echo 'Waiting for VNC server to LISTEN on {vnc_port}...'
for _v in $(seq 1 30); do
    if ss -ltn 2>/dev/null | grep -qE ":{vnc_port}\\b"; then
        echo "VNC server LISTEN on {vnc_port} (after ${{_v}}s)"
        break
    fi
    sleep 1
done
if ! ss -ltn 2>/dev/null | grep -qE ":{vnc_port}\\b"; then
    echo "WARNING: VNC server 가 {vnc_port} 에 LISTEN 안함 (start_script 실패 가능) — /tmp 로그:" >&2
    tail -20 /tmp/vnc_{web_user}_{display_num}.log 2>/dev/null | sed 's/^/    /' >&2
fi

# noVNC websockify 시작 (컨테이너 안에서 — 로그를 남겨 실패 시 원인 추적)
echo 'Starting noVNC websockify on port {novnc_port}...'
WS_LOG="{VNC_LOG_DIR}/websockify-{web_user}-{novnc_port}.log"
# 로그 디렉토리/파일을 기동 전에 무조건 만든다. 파일이 통째로 없으면
# '기동 라인이 실행 안됨/옛코드'와 구분이 안 돼 진단이 헷갈렸다(파일 부재 = 혼란 신호).
# 헤더를 먼저 써서 파일은 항상 존재 → 이후 apptainer exec 출력은 >> 로 append.
mkdir -p "{VNC_LOG_DIR}" 2>/dev/null || true
echo "=== websockify launch (job $SLURM_JOB_ID) cmd: apptainer exec --env PATH instance://$INSTANCE_NAME websockify --web=/opt/noVNC {novnc_port} localhost:{vnc_port} ===" > "$WS_LOG"
# 검증된 방식: bash -lc 로 감싸지 않고 apptainer exec 가 websockify 를 직접 실행.
# PATH 는 --env 로 주입(bash -lc 는 컨테이너에서 멈출 수 있어 로그조차 안 남던 원인).
# 컨테이너는 호스트 네트워크를 공유하므로 novnc_port 가 노드에 그대로 LISTEN 된다.
apptainer exec --env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    instance://$INSTANCE_NAME \
    websockify --web=/opt/noVNC {novnc_port} localhost:{vnc_port} >> "$WS_LOG" 2>&1 &
WEBSOCKIFY_PID=$!
echo "websockify backgrounded (pid=$WEBSOCKIFY_PID), log: $WS_LOG"

# 짧게 쉰 뒤 프로세스가 살아있는지(kill -0) 즉시 확인 — 즉사하면 바로 사유 남긴다.
sleep 2
if ! kill -0 $WEBSOCKIFY_PID 2>/dev/null; then
    echo "=== websockify process (pid=$WEBSOCKIFY_PID) DIED within 2s — see reason above ===" >> "$WS_LOG"
    echo "ERROR: websockify 프로세스가 2초 내 죽음 (pid=$WEBSOCKIFY_PID) — 로그:" >&2
    tail -20 "$WS_LOG" 2>/dev/null | sed 's/^/    /' >&2
fi

# websockify 가 실제 포트를 LISTEN 할 때까지 대기(최대 ~15초). 안 뜨면 로그 출력.
for _w in $(seq 1 15); do
    if ss -ltn 2>/dev/null | grep -qE ":{novnc_port}\\b" || \
       apptainer exec instance://$INSTANCE_NAME ss -ltn 2>/dev/null | grep -qE ":{novnc_port}\\b"; then
        echo "noVNC websockify LISTEN on {novnc_port} (after ${{_w}}s)"
        break
    fi
    sleep 1
done
# 최종 판정: 포트 LISTEN 안 하면 프로세스 생사 + 로그를 함께 남긴다(타임아웃이어도 exit 안 함).
if ! ss -ltn 2>/dev/null | grep -qE ":{novnc_port}\\b"; then
    if kill -0 $WEBSOCKIFY_PID 2>/dev/null; then
        _wsalive="ALIVE(pid=$WEBSOCKIFY_PID)"
    else
        _wsalive="DEAD(pid=$WEBSOCKIFY_PID)"
    fi
    echo "=== websockify did NOT LISTEN on {novnc_port} after 15s — process $_wsalive ===" >> "$WS_LOG"
    echo "ERROR: websockify 가 {novnc_port} 에 LISTEN 안함 — 프로세스 $_wsalive — 로그:" >&2
    tail -20 "$WS_LOG" 2>/dev/null | sed 's/^/    /' >&2
fi

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


def submit_vnc_job(username, session_id, vnc_port, novnc_port, geometry, duration_hours, sif_image_path, start_script, desktop_env, image_id, web_user, gpu_count=0, partition='viz'):
    """Slurm Job 제출. Returns (job_id, warning_message)

    username = 시스템 사용자(sbatch 실행 식별), web_user = 웹 사용자(격리 키, sanitize 완료)."""

    if MOCK_MODE:
        mock_job_id = random.randint(10000, 99999)
        print(f"[MOCK] VNC Job submitted: {mock_job_id}")
        return mock_job_id, None

    warning = None

    # 실제 Slurm Job 제출
    job_script = generate_vnc_job_script(
        username, session_id, vnc_port, novnc_port, geometry, duration_hours, sif_image_path, start_script, desktop_env, image_id, web_user, gpu_count, partition
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

    # GPU 요청 실패 시 CPU 모드로 fallback
    if result.returncode != 0 and gpu_count > 0 and 'gres' in result.stderr.lower():
        print(f"⚠️  GPU 요청 실패, CPU 모드로 재시도: {result.stderr.strip()}")
        warning = f"GPU를 이용할 수 없습니다 (GPU {gpu_count}개 요청 실패). CPU 모드로 실행합니다."

        # GPU 없이 재생성
        job_script = generate_vnc_job_script(
            username, session_id, vnc_port, novnc_port, geometry, duration_hours, sif_image_path, start_script, desktop_env, image_id, web_user, gpu_count=0
        )
        with open(script_path, 'w') as f:
            f.write(job_script)

        result = subprocess.run(
            [SBATCH, script_path],
            capture_output=True,
            text=True
        )

    if result.returncode != 0:
        raise Exception(f"Job submission failed: {result.stderr}")

    # Job ID 추출
    job_id = int(result.stdout.strip().split()[-1])

    return job_id, warning


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
    """사용자의 모든 VNC 세션 조회

    웹 로그인 사용자(web_user) 또는 시스템 사용자(username)로 세션 검색
    """

    sessions = []

    if REDIS_AVAILABLE and vnc_session_manager:
        # Get all sessions and filter by username or web_user
        all_sessions = vnc_session_manager.list_sessions()
        print(f"🔍 [GET_SESSIONS] Total sessions in Redis: {len(all_sessions)}")
        for s in all_sessions:
            print(f"🔍 [GET_SESSIONS] Session: {s.get('session_id')}, username={s.get('username')}, web_user={s.get('web_user')}")
        sessions = [s for s in all_sessions
                    if s.get('username') == username or s.get('web_user') == username]
        print(f"🔍 [GET_SESSIONS] Filtered sessions for '{username}': {len(sessions)}")
    else:
        sessions = [s for s in vnc_sessions_memory.values()
                    if s.get('username') == username or s.get('web_user') == username]
        print(f"🔍 [GET_SESSIONS] Using memory, filtered sessions for '{username}': {len(sessions)}")

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
    gpu_count = int(data.get('gpu_count', 0))  # 기본값 0: GPU 없이 VNC 세션 시작
    partition = data.get('partition', 'viz')  # 파티션 선택 (viz, gpu 등)

    # 시스템 사용자 (YAML의 ssh_user) - VNC 세션 실행용
    # 웹 로그인 사용자(admin 등)가 아닌 실제 시스템 사용자 사용
    system_user = get_default_system_user()
    web_user = user['username']  # 웹 로그인 사용자 (감사 추적용)
    # web_user 는 JWT sub(또는 SSO 비활성 시 'admin')이며 셸 경로/인스턴스명에 박히므로
    # 경로순회/셸인젝션 방지를 위해 반드시 sanitize 후 사용한다.
    web_user = _sanitize_web_user(web_user)
    if not web_user:
        return jsonify({'error': 'Invalid or missing user identity'}), 400

    print(f"🔍 [VNC CREATE] JWT user: {user}")
    print(f"🔍 [VNC CREATE] web_user: {web_user}, system_user: {system_user}")

    # 이미지 유효성 검사
    if image_id not in VNC_IMAGES:
        return jsonify({'error': f'Invalid image_id: {image_id}'}), 400

    image_config = VNC_IMAGES[image_id]
    sif_image_path = image_config['sif_path']

    # SIF 이미지 파일 존재 확인 (viz-node에서 확인)
    # Headnode에는 메타데이터(JSON)만 있고, 실제 .sif 파일은 viz-node에만 존재
    if not check_image_exists_on_remote_node(sif_image_path, node=DEFAULT_VIZ_NODE, partition='viz'):
        return jsonify({'error': f'Image file not found on viz-node ({DEFAULT_VIZ_NODE}): {sif_image_path}'}), 500

    # 세션 ID 생성 (시스템 사용자 기반)
    timestamp = int(time.time())
    session_id = f"vnc-{system_user}-{timestamp}"

    # VNC 포트 할당
    try:
        vnc_port = get_available_vnc_port()
        novnc_port = vnc_port + NOVNC_PORT_OFFSET
    except Exception as e:
        return jsonify({'error': str(e)}), 500

    # Slurm Job 제출 (시스템 사용자로 실행)
    try:
        job_id, gpu_warning = submit_vnc_job(
            system_user,  # YAML의 ssh_user 사용 (sbatch 실행 식별)
            session_id,
            vnc_port,
            novnc_port,
            geometry,
            duration_hours,
            sif_image_path,
            image_config['start_script'],
            image_config['desktop_env'],
            image_id,
            web_user,  # 웹 사용자 격리 키 (sandbox/instance/home)
            gpu_count,
            partition
        )
    except Exception as e:
        return jsonify({'error': f'Job submission failed: {str(e)}'}), 500

    # GPU fallback 시 실제 gpu_count를 0으로 반영
    actual_gpu_count = 0 if gpu_warning else gpu_count

    # 세션 정보 생성
    session_data = {
        'session_id': session_id,
        'job_id': job_id,
        'username': web_user,       # 소유권/격리 키 (웹 로그인 사용자) — 권한검사 기준
        'system_user': system_user, # 시스템 사용자 (sbatch/SSH 실행 식별)
        'web_user': web_user,       # 웹 로그인 사용자 (감사 추적용, username과 동일)
        'email': user.get('email', ''),
        'image_id': image_id,
        'image_name': image_config['name'],
        'vnc_port': vnc_port,
        'novnc_port': novnc_port,
        'geometry': geometry,
        'duration_hours': duration_hours,
        'gpu_count': actual_gpu_count,
        'status': 'pending',
        'node': None,
        'novnc_url': None,
        'created_at': datetime.utcnow().isoformat()
    }

    if gpu_warning:
        session_data['warning'] = gpu_warning

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

    print(f"🔍 [VNC LIST] JWT user: {user}")
    print(f"🔍 [VNC LIST] Searching sessions for username: {user['username']}")

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
                    vnc_port = session['vnc_port']
                    session_id = session['session_id']

                    # 에러 및 접속 가능 여부 초기화
                    session['error'] = None
                    session['is_accessible'] = False

                    # SSH 터널이 아직 생성되지 않았으면 생성
                    if session_id not in SSH_TUNNEL_PIDS:
                        try:
                            # Controller에서 viz-node로 SSH 터널 생성
                            # viz-node:novnc_port → Controller:novnc_port
                            create_ssh_tunnel(node, novnc_port, novnc_port, session_id)
                            print(f"📡 SSH tunnel created for session {session_id}: {node}:{novnc_port} → localhost:{novnc_port}")
                        except Exception as e:
                            error_msg = f"SSH tunnel creation failed: {str(e)}"
                            print(f"⚠️  {error_msg}")
                            session['error'] = error_msg

                    # 외부 접근 가능한 URL 생성 (nginx reverse proxy 경로 사용)
                    # autoconnect=true: 자동 연결
                    # resize=scale: 브라우저 창 크기에 맞게 자동 스케일링
                    # nginx에서 /vncproxy/<port>/ 로 프록시됨
                    session['novnc_url'] = f"/vncproxy/{novnc_port}/vnc.html?autoconnect=true&resize=scale"

                    # VNC 포트 접속 가능 여부 체크 (원격 노드에서 확인)
                    try:
                        import socket
                        # SSH를 통해 원격 노드의 VNC 포트 체크
                        ssh_opts = get_ssh_opts()
                        check_cmd = f"nc -zv localhost {vnc_port}"
                        result = subprocess.run(
                            [SSH] + ssh_opts + [f'{get_default_system_user()}@{node}', check_cmd],
                            capture_output=True,
                            timeout=5
                        )
                        # nc 명령어는 성공 시 exit code 0 반환
                        if result.returncode == 0:
                            session['is_accessible'] = True
                        else:
                            session['error'] = f"VNC server not listening on port {vnc_port}"
                            print(f"⚠️  VNC port {vnc_port} not accessible on {node}")
                    except Exception as e:
                        session['error'] = f"Failed to check VNC accessibility: {str(e)}"
                        print(f"⚠️  VNC accessibility check failed: {e}")
                else:
                    # Job은 RUNNING인데 노드 정보를 못 가져온 경우
                    session['error'] = "Cannot determine node allocation"
                    print(f"⚠️  Job {job_id} is RUNNING but node is unknown")

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
    # 잡 스크립트는 {web_user}_{image_id} 로 sandbox를 만든다(generate_vnc_job_script).
    # 동일 규칙으로 삭제해야 실제 디렉토리와 일치한다(기존엔 image_id 누락+system_user라 불일치).
    sandbox_owner = session.get('web_user') or session['username']
    sandbox_image = session.get('image_id', '')
    sandbox_path = f"{VNC_SANDBOXES_DIR}/{sandbox_owner}_{sandbox_image}"

    try:
        if MOCK_MODE:
            print(f"[MOCK] Deleting sandbox: {sandbox_path}")
        else:
            # SSH로 viz-node에서 실행 (또는 로컬에서 직접 삭제)
            result = subprocess.run(
                [RM, '-rf', sandbox_path],
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
            node=DEFAULT_VIZ_NODE,
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


# ==================== Nodes Endpoints ====================

@vnc_bp.route('/nodes', methods=['GET'])
@jwt_required
def list_viz_nodes():
    """
    사용 가능한 Visualization 노드 목록 조회
    YAML 설정에서 동적으로 로드
    """
    return jsonify({
        'success': True,
        'nodes': VIZ_NODES,
        'default_node': DEFAULT_VIZ_NODE,
        'count': len(VIZ_NODES)
    })


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

    # ── (★ 준비중 무한대기 근본수정) Slurm 으로 status/node 갱신 후 저장 ──
    # 세션은 생성 시 status='pending', node=None 으로 저장되고, list/detail 을
    # 호출해야만 squeue/scontrol 로 갱신된다. /ready 는 get_vnc_session(저장값)만 보던
    # 탓에 잡이 실제 RUNNING 이고 포트가 다 떠도 영영 status='pending' → 즉시 not ready →
    # 프론트 '준비중' 무한폴링. detail(1289~)과 동일하게 여기서도 갱신하고, detail 이
    # 빠뜨린 '저장'까지 해서 다음 호출에도 반영되게 한다.
    job_id = session.get('job_id')
    if job_id:
        status = get_job_status(job_id)
        session['status'] = status.lower()
        if status == 'RUNNING' and not session.get('node'):
            node = get_job_node(job_id)
            if node:
                session['node'] = node
        # 갱신된 status/node 를 메모리/Redis 에 반영 (detail 은 이걸 안 해서 매번 pending 으로 복귀)
        save_vnc_session(session_id, session)

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
        # SSH 키 옵션 생성
        # list_vnc_sessions(1158~)와 동일한 검증된 패턴 사용 — get_ssh_opts() + system_user@node + nc.
        # 기존엔 'ssh {node} lsof'(user 미지정 + lsof 미설치/권한 문제)라 잡 노드 포트가 떠도
        # 영영 not ready → 프론트 '준비중' 무한대기. system_user(stcx)로 nc 포트체크로 통일.
        ssh_opts = get_ssh_opts() if callable(get_ssh_opts) else [
            '-o', 'ConnectTimeout=2', '-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes']
        _suser = get_default_system_user()

        # VNC 포트 (컨테이너가 호스트넷 공유 → 노드 localhost:vnc_port 에 LISTEN)
        result = subprocess.run(
            [SSH] + ssh_opts + [f'{_suser}@{node}', f'nc -z -w1 localhost {vnc_port}'],
            capture_output=True, text=True, timeout=4
        )
        vnc_ready = result.returncode == 0

        # noVNC(websockify) 포트
        result_novnc = subprocess.run(
            [SSH] + ssh_opts + [f'{_suser}@{node}', f'nc -z -w1 localhost {novnc_port}'],
            capture_output=True, text=True, timeout=4
        )
        novnc_ready = result_novnc.returncode == 0

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

    # 런타임에 메모리로 로드된 generate_vnc_job_script 의 코드 마커를 노출 →
    # 잡 제출 없이 backend 가 새 코드인지(websockify 직접 exec + SESSION_MANAGER 차단)
    # 즉시 검증 가능. ([8] 이 파일 grep 이 아니라 실제 실행코드를 확인하게 됨)
    try:
        import inspect
        _src = inspect.getsource(generate_vnc_job_script)
        _ready_src = inspect.getsource(check_vnc_readiness)
        _code_markers = {
            'websockify_direct_exec': ('--env PATH' in _src and 'websockify --web' in _src),
            'ws_log_header': ('=== websockify launch' in _src),
            'session_manager_fix': ('SESSION_MANAGER=,DBUS' in _src),
            # /ready 가 squeue/scontrol 로 status·node 를 갱신·저장하는지 (준비중 무한대기 수정)
            'ready_slurm_refresh': ('get_job_status(job_id)' in _ready_src and 'save_vnc_session' in _ready_src),
            # /ready 의 ssh 호출이 절대경로 [SSH] 인지 (bare 'ssh' → systemd PATH 의존 FileNotFoundError 차단)
            'ready_ssh_abspath': ('[SSH]' in _ready_src and "['ssh']" not in _ready_src),
        }
    except Exception:
        _code_markers = {}

    return jsonify({
        'status': 'healthy',
        'mock_mode': MOCK_MODE,
        'slurm_available': SLURM_AVAILABLE,
        'redis_available': REDIS_AVAILABLE,
        'sif_image_path': SIF_IMAGE_PATH,
        'sif_image_exists': os.path.exists(SIF_IMAGE_PATH),
        'sessions_dir': VNC_SESSIONS_DIR,
        'sessions_dir_exists': os.path.exists(VNC_SESSIONS_DIR),
        'code_markers': _code_markers
    }), 200
