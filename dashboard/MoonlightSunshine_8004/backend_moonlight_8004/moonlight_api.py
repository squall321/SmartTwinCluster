"""
Moonlight/Sunshine Session Management API
❌ backend_5010/vnc_api.py를 수정하지 않음!
✅ 완전히 독립된 새 파일

기존 VNC와의 차이점:
1. 디렉토리: /scratch/sunshine_* (VNC는 /scratch/vnc_*)
2. Redis 키: moonlight:session:* (VNC는 vnc:session:*)
3. Display: :10+ (VNC는 :1-:9)
4. QoS: moonlight (VNC는 QoS 없음)
5. 포트: 47989-48010 (VNC는 5900-5999, 6900-6999)
6. 프로토콜: GameStream/WebRTC (VNC는 RFB/WebSocket)
"""

from flask import Blueprint, request, jsonify
import sys
import subprocess
import os
import time
import json
import random

# Add common module to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

# Redis Session Manager import
try:
    from common import RedisSessionManager, get_redis_client
    REDIS_AVAILABLE = True
    # Initialize session manager for Moonlight sessions with moonlight:session:* pattern
    moonlight_session_manager = RedisSessionManager('moonlight', ttl=28800, legacy_key_pattern=True)  # 8 hours
    print("✅ Moonlight Redis session manager initialized (pattern: moonlight:session:*)")
except Exception as e:
    REDIS_AVAILABLE = False
    print(f"⚠️  Redis not available: {e}")
    print("⚠️  Moonlight sessions will be stored in memory")
    moonlight_sessions_memory = {}
    moonlight_session_manager = None

# Create blueprint (no url_prefix - Nginx will add /api/moonlight/)
moonlight_bp = Blueprint('moonlight', __name__)

# Moonlight 전용 설정
SUNSHINE_IMAGES_DIR = "/opt/apptainers"
SUNSHINE_SANDBOXES_DIR = "/scratch/sunshine_sandboxes"
SUNSHINE_SESSIONS_DIR = "/scratch/sunshine_sessions"
SUNSHINE_LOG_DIR = "/scratch/sunshine_logs"

# Sunshine 이미지 목록 (VNC와 완전 독립)
# 네이밍 규칙: sunshine_*.sif (VNC는 vnc_*.sif)
SUNSHINE_IMAGES = {
    "desktop": {  # vnc_desktop.sif → sunshine_desktop.sif
        "name": "XFCE4 Desktop (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_desktop.sif",
        "description": "Lightweight XFCE4 desktop with Sunshine streaming",
        "icon": "🖥️",
        "desktop_env": "xfce4",
        "start_cmd": "startxfce4",
        "default": True
    },
    "gnome": {  # vnc_gnome.sif → sunshine_gnome.sif
        "name": "GNOME Desktop (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_gnome.sif",
        "description": "Full-featured GNOME desktop with Sunshine streaming",
        "icon": "🎨",
        "desktop_env": "gnome",
        "start_cmd": "gnome-session",
        "default": False
    },
    "gnome_lsprepost": {  # vnc_gnome_lsprepost.sif → sunshine_gnome_lsprepost.sif
        "name": "GNOME + LS-PrePost (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_gnome_lsprepost.sif",
        "description": "GNOME desktop with LS-PrePost CAE software and Sunshine streaming",
        "icon": "🔧",
        "desktop_env": "gnome",
        "start_cmd": "gnome-session",
        "cae_app": "lsprepost",
        "default": False
    }
}

# Display number allocation (VNC uses :1-:9, Moonlight uses :10+)
DISPLAY_START = 10
DISPLAY_END = 99


def get_job_status(job_id):
    """Slurm Job 상태 조회"""
    if not job_id:
        return 'UNKNOWN'

    # squeue로 작업 상태 조회
    result = subprocess.run(
        ['squeue', '--job', str(job_id), '--noheader', '--format=%T'],
        capture_output=True,
        text=True,
        timeout=5
    )

    if result.returncode != 0 or not result.stdout.strip():
        # Job이 완료되었거나 없음
        return 'COMPLETED'

    return result.stdout.strip()


@moonlight_bp.route('/images', methods=['GET'])
def list_images():
    """사용 가능한 Sunshine 이미지 목록 반환"""
    images = []
    for image_id, info in SUNSHINE_IMAGES.items():
        images.append({
            'id': image_id,
            'name': info['name'],
            'description': info['description'],
            'icon': info['icon'],
            'default': info['default'],
            'available': os.path.exists(info['sif_path'])
        })

    return jsonify({'images': images}), 200


@moonlight_bp.route('/sessions', methods=['GET'])
def list_sessions():
    """현재 사용자의 Moonlight 세션 목록 조회"""
    # TODO: JWT 토큰에서 username 추출
    username = request.headers.get('X-Username', 'testuser')

    if not REDIS_AVAILABLE or moonlight_session_manager is None:
        # Fallback to memory storage
        sessions = [s for s in moonlight_sessions_memory.values() if s.get('username') == username]
        return jsonify({'sessions': sessions}), 200

    # Redis에서 사용자 세션 조회 및 실시간 상태 업데이트
    try:
        # Get all sessions for this user (using legacy pattern: moonlight:session:ml-{username}-*)
        redis_client = get_redis_client()
        session_keys = redis_client.keys(f'moonlight:session:ml-{username}-*')

        sessions = []
        for key in session_keys:
            session_data = redis_client.hgetall(key)
            if session_data:
                # Update status from Slurm in real-time
                job_id = session_data.get('slurm_job_id')
                current_status = session_data.get('status', 'unknown')

                if job_id:
                    try:
                        slurm_status = get_job_status(job_id)
                        updated_status = slurm_status.lower()

                        # Update Redis if status changed
                        if current_status != updated_status:
                            redis_client.hset(key, 'status', updated_status)
                            current_status = updated_status

                        # If job completed/failed, set TTL for cleanup
                        if updated_status in ['completed', 'failed', 'cancelled', 'timeout']:
                            redis_client.expire(key, 300)  # 5분 후 자동 삭제
                    except Exception as e:
                        print(f"⚠️  Failed to update status for {job_id}: {e}")

                sessions.append({
                    'session_id': session_data.get('session_id'),
                    'image_id': session_data.get('image_id'),
                    'status': current_status,
                    'sunshine_port': session_data.get('sunshine_port'),
                    'web_url': session_data.get('web_url'),
                    'created_at': session_data.get('created_at'),
                    'slurm_job_id': session_data.get('slurm_job_id')
                })

        return jsonify({'sessions': sessions}), 200
    except Exception as e:
        print(f"❌ Error listing sessions: {e}")
        return jsonify({'error': str(e), 'sessions': []}), 500


@moonlight_bp.route('/sessions', methods=['POST'])
def create_session():
    """새로운 Moonlight/Sunshine 세션 생성"""
    data = request.get_json()

    # TODO: JWT 토큰에서 username 추출
    username = request.headers.get('X-Username', 'testuser')
    image_id = data.get('image_id', 'desktop')

    # 이미지 검증
    if image_id not in SUNSHINE_IMAGES:
        return jsonify({'error': f'Invalid image_id: {image_id}'}), 400

    image_info = SUNSHINE_IMAGES[image_id]
    if not os.path.exists(image_info['sif_path']):
        return jsonify({'error': f'Image not found: {image_info["sif_path"]}'}), 404

    # 세션 ID 생성
    timestamp = int(time.time())
    session_id = f"ml-{username}-{timestamp}"

    # Display 번호 할당
    display_num = allocate_display_number()
    if display_num is None:
        return jsonify({'error': 'No available display numbers'}), 503

    # Sunshine 포트 할당 (47989-48010)
    sunshine_port = 47989 + (display_num - DISPLAY_START)

    # Slurm Job 제출
    try:
        slurm_job_id = submit_moonlight_job(
            username=username,
            session_id=session_id,
            image_id=image_id,
            image_info=image_info,
            display_num=display_num,
            sunshine_port=sunshine_port
        )
    except Exception as e:
        return jsonify({'error': f'Failed to submit Slurm job: {str(e)}'}), 500

    # Redis에 세션 정보 저장
    session_data = {
        'session_id': session_id,
        'username': username,
        'image_id': image_id,
        'display_num': display_num,
        'sunshine_port': sunshine_port,
        'slurm_job_id': slurm_job_id,
        'status': 'starting',
        'created_at': timestamp,
        'web_url': f'https://110.15.177.120/moonlight/{session_id}'
    }

    if REDIS_AVAILABLE and moonlight_session_manager:
        # Use session manager to store
        redis_client = get_redis_client()
        session_key = f'moonlight:session:{session_id}'
        redis_client.hset(session_key, mapping=session_data)
        redis_client.expire(session_key, 86400)  # 24시간 TTL
    else:
        # Fallback to memory
        moonlight_sessions_memory[session_id] = session_data

    return jsonify({
        'session_id': session_id,
        'status': 'starting',
        'web_url': session_data['web_url'],
        'sunshine_port': sunshine_port,
        'slurm_job_id': slurm_job_id
    }), 201


@moonlight_bp.route('/sessions/<session_id>', methods=['DELETE'])
def delete_session(session_id):
    """Moonlight 세션 삭제"""
    if not REDIS_AVAILABLE or moonlight_session_manager is None:
        # Fallback to memory
        if session_id in moonlight_sessions_memory:
            session_data = moonlight_sessions_memory[session_id]
            del moonlight_sessions_memory[session_id]
        else:
            return jsonify({'error': 'Session not found'}), 404
    else:
        # Use Redis
        redis_client = get_redis_client()
        session_key = f'moonlight:session:{session_id}'
        session_data = redis_client.hgetall(session_key)

        if not session_data:
            return jsonify({'error': 'Session not found'}), 404

        # Redis에서 세션 삭제
        redis_client.delete(session_key)

    # Slurm Job 취소
    slurm_job_id = session_data.get('slurm_job_id')
    if slurm_job_id:
        try:
            subprocess.run(['scancel', slurm_job_id], check=True)
        except subprocess.CalledProcessError as e:
            # Job이 이미 종료된 경우 무시
            pass

    return jsonify({'message': 'Session deleted successfully'}), 200


def allocate_display_number():
    """사용 가능한 Display 번호 할당 (:10-:99)"""
    used_displays = set()

    if REDIS_AVAILABLE and moonlight_session_manager:
        # Redis에서 현재 사용 중인 Display 번호 조회
        redis_client = get_redis_client()
        for key in redis_client.keys('moonlight:session:*'):
            display_num = redis_client.hget(key, 'display_num')
            if display_num:
                used_displays.add(int(display_num))
    else:
        # Memory fallback
        for session in moonlight_sessions_memory.values():
            display_num = session.get('display_num')
            if display_num:
                used_displays.add(int(display_num))

    # 사용 가능한 Display 번호 찾기
    for display_num in range(DISPLAY_START, DISPLAY_END + 1):
        if display_num not in used_displays:
            return display_num

    return None  # 사용 가능한 Display 없음


def get_viz_partition_resources():
    """
    viz 파티션의 노드당 CPU 및 메모리를 동적으로 가져옴
    - CPU: 16코어 이상이면 16 사용, 아니면 사용 가능한 최대 CPU 수
    - 메모리: 노드 메모리의 90% 사용 (시스템 예약 고려)

    Returns:
        tuple: (cpus, memory_gb)
    """
    try:
        # sinfo로 viz 파티션의 노드별 CPU 및 메모리 확인
        cpu_result = subprocess.run(
            ['sinfo', '-N', '-p', 'viz', '-o', '%c', '--noheader'],
            capture_output=True,
            text=True,
            timeout=5
        )

        mem_result = subprocess.run(
            ['sinfo', '-N', '-p', 'viz', '-o', '%m', '--noheader'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if cpu_result.returncode == 0 and mem_result.returncode == 0:
            # CPU 개수 파싱
            cpu_counts = [int(line.strip()) for line in cpu_result.stdout.strip().split('\n') if line.strip().isdigit()]
            # 메모리 파싱 (MB 단위)
            mem_counts = [int(line.strip()) for line in mem_result.stdout.strip().split('\n') if line.strip().isdigit()]

            if cpu_counts and mem_counts:
                min_cpus = min(cpu_counts)
                min_mem_mb = min(mem_counts)

                # CPU: 16코어 이상이면 16, 아니면 최대 사용 가능한 수
                cpus = 16 if min_cpus >= 16 else min_cpus

                # 메모리: 노드 메모리의 90% 사용 (GB 단위, 최소 1GB)
                memory_gb = max(1, int(min_mem_mb * 0.9 / 1024))

                return (cpus, memory_gb)
    except Exception as e:
        print(f"⚠️  Failed to get viz partition resources: {e}")

    # 기본값: 2 CPU, 2GB (viz 파티션이 작을 경우 안전한 기본값)
    return (2, 2)


def submit_moonlight_job(username, session_id, image_id, image_info, display_num, sunshine_port):
    """
    Slurm에 Moonlight/Sunshine Job 제출

    ✅ Apptainer 컨테이너 내부에서 실행:
    - QoS: moonlight (VNC는 QoS 없음)
    - Sandbox: /scratch/sunshine_sandboxes/ (VNC는 /scratch/vnc_sandboxes/)
    - Display: :10+ (VNC는 :1-:9)
    - 포트: 47989-48010 (VNC는 5900-5999, 6900-6999)
    """

    # 이미지 정보에서 데스크톱 환경 추출
    desktop_env = image_info.get('desktop_env', 'xfce4')
    start_cmd = image_info.get('start_cmd', 'startxfce4')
    image_path = image_info['sif_path']

    # viz 파티션의 리소스(CPU, 메모리) 동적으로 가져오기
    cpus, memory = get_viz_partition_resources()

    # Slurm 배치 스크립트 생성
    script = f"""#!/bin/bash
#SBATCH --job-name=moonlight-{username}
#SBATCH --partition=viz
#SBATCH --nodes=1
#SBATCH --cpus-per-task={cpus}
#SBATCH --mem={memory}G
#SBATCH --time=08:00:00
#SBATCH --output={SUNSHINE_LOG_DIR}/{session_id}.log

echo "=========================================="
echo "Moonlight/Sunshine Session Starting"
echo "Session ID: {session_id}"
echo "User: {username}"
echo "Image: {image_id}"
echo "Desktop: {desktop_env}"
echo "Display: :{display_num}"
echo "Sunshine Port: {sunshine_port}"
echo "=========================================="

# Sunshine 전용 Sandbox (VNC와 완전 분리)
SANDBOX_BASE={SUNSHINE_SANDBOXES_DIR}
USER_SANDBOX=$SANDBOX_BASE/{username}_{image_id}
SESSION_DIR={SUNSHINE_SESSIONS_DIR}/{session_id}

# 세션 디렉토리 생성
mkdir -p $SESSION_DIR/config
mkdir -p $SESSION_DIR/logs
mkdir -p $SESSION_DIR/tmp
mkdir -p $SESSION_DIR/home

# Sunshine 설정 파일 생성
cat > $SESSION_DIR/config/sunshine.conf <<'SUNEOF'
# Sunshine Configuration for Session {session_id}
port = {sunshine_port}
address_family = ipv4
channels = 5

# Video Settings
encoder = nvenc
codec = h264
fps = 60
min_threads = 1

# Audio Settings (disabled for now)
audio_sink =

# Input Settings
gamepad = disabled

# Logging
min_log_level = info
SUNEOF

# Sandbox가 없으면 생성
if [ ! -d "$USER_SANDBOX" ]; then
    echo "Creating Sunshine sandbox for {username}..."
    mkdir -p $SANDBOX_BASE
    apptainer build --sandbox $USER_SANDBOX {image_path}
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create sandbox"
        redis-cli HSET moonlight:session:{session_id} status failed error "Sandbox creation failed"
        exit 1
    fi
    echo "Sandbox created successfully"
fi

# X11 Display 설정
DISPLAY_NUM={display_num}
export DISPLAY=:$DISPLAY_NUM
export XAUTHORITY=$SESSION_DIR/.Xauthority

# Xauthority 파일 생성
touch $XAUTHORITY
xauth add :$DISPLAY_NUM . $(xxd -l 16 -p /dev/urandom)

echo "Starting Xorg on display :$DISPLAY_NUM..."

# Xorg 시작 (호스트에서, GPU 접근 필요)
Xorg :$DISPLAY_NUM -config /etc/X11/xorg.conf.nvidia -nolisten tcp &
XORG_PID=$!

# Xorg 시작 대기
sleep 3

# Xorg 실행 확인
if ! ps -p $XORG_PID > /dev/null; then
    echo "ERROR: Failed to start Xorg"
    redis-cli HSET moonlight:session:{session_id} status failed error "Xorg failed to start"
    exit 1
fi

echo "Xorg started successfully (PID: $XORG_PID)"

# Apptainer 컨테이너 내부에서 데스크톱 환경 + Sunshine 실행
echo "Starting desktop environment and Sunshine inside container..."

apptainer exec \\
    --nv \\
    --writable \\
    --bind /tmp/.X11-unix:/tmp/.X11-unix \\
    --bind $SESSION_DIR:/session \\
    --bind $XAUTHORITY:$XAUTHORITY \\
    --env DISPLAY=:$DISPLAY_NUM \\
    --env XAUTHORITY=$XAUTHORITY \\
    --env HOME=/session/home \\
    --env SUNSHINE_CONFIG_DIR=/session/config \\
    $USER_SANDBOX \\
    /bin/bash <<'CONTAINEREOF'
# 컨테이너 내부 스크립트

# 환경 변수 확인
export DISPLAY=:{display_num}
export XAUTHORITY=/session/.Xauthority
export HOME=/session/home

echo "Container environment:"
echo "  DISPLAY=$DISPLAY"
echo "  HOME=$HOME"
echo "  SUNSHINE_CONFIG_DIR=$SUNSHINE_CONFIG_DIR"

# GPU 확인
echo "Checking GPU..."
nvidia-smi || echo "WARNING: nvidia-smi failed"

# 데스크톱 환경 시작
echo "Starting {desktop_env} desktop environment..."
{start_cmd} > /session/logs/desktop.log 2>&1 &
DESKTOP_PID=$!

# 데스크톱 시작 대기
sleep 5

# 데스크톱 프로세스 확인
if ! ps -p $DESKTOP_PID > /dev/null; then
    echo "ERROR: Desktop environment failed to start"
    redis-cli HSET moonlight:session:{session_id} status failed error "Desktop failed"
    exit 1
fi

echo "Desktop environment started (PID: $DESKTOP_PID)"

# Sunshine 시작
echo "Starting Sunshine streaming server..."
sunshine --config /session/config/sunshine.conf > /session/logs/sunshine.log 2>&1 &
SUNSHINE_PID=$!

# Sunshine 시작 대기
sleep 3

# Sunshine 프로세스 확인
if ! ps -p $SUNSHINE_PID > /dev/null; then
    echo "ERROR: Sunshine failed to start"
    redis-cli HSET moonlight:session:{session_id} status failed error "Sunshine failed"
    exit 1
fi

echo "Sunshine started (PID: $SUNSHINE_PID)"

# Redis 상태 업데이트
redis-cli HSET moonlight:session:{session_id} status running
redis-cli HSET moonlight:session:{session_id} desktop_pid $DESKTOP_PID
redis-cli HSET moonlight:session:{session_id} sunshine_pid $SUNSHINE_PID
redis-cli HSET moonlight:session:{session_id} xorg_pid $XORG_PID

echo "=========================================="
echo "Session is ready!"
echo "Display: :$DISPLAY_NUM"
echo "Desktop PID: $DESKTOP_PID"
echo "Sunshine PID: $SUNSHINE_PID"
echo "Sunshine Port: {sunshine_port}"
echo "=========================================="

# Job 종료 시 정리
function cleanup {{
    echo "Cleaning up session..."
    redis-cli HSET moonlight:session:{session_id} status stopped
    kill $SUNSHINE_PID $DESKTOP_PID 2>/dev/null
    echo "Cleanup completed"
}}

trap cleanup EXIT SIGTERM SIGINT

# Sunshine 프로세스 유지
wait $SUNSHINE_PID
CONTAINEREOF

CONTAINER_EXIT=$?

# 컨테이너 종료 시 Xorg 정리
echo "Container exited with code $CONTAINER_EXIT"
echo "Cleaning up Xorg..."
kill $XORG_PID 2>/dev/null

# 최종 상태 업데이트
redis-cli HSET moonlight:session:{session_id} status stopped
redis-cli HSET moonlight:session:{session_id} ended_at $(date +%s)

echo "Session {session_id} ended"
exit $CONTAINER_EXIT
"""

    # 임시 파일에 스크립트 저장
    script_path = f'/tmp/moonlight_{session_id}.sh'
    with open(script_path, 'w') as f:
        f.write(script)

    # Slurm에 제출
    result = subprocess.run(
        ['sbatch', script_path],
        capture_output=True,
        text=True,
        check=True
    )

    # Job ID 추출 (예: "Submitted batch job 12345")
    job_id = result.stdout.strip().split()[-1]

    # 임시 파일 삭제
    os.remove(script_path)

    return job_id
