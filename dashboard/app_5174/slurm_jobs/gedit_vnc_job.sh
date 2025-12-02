#!/bin/bash
#SBATCH --job-name=gedit_vnc
#SBATCH --partition=viz
#SBATCH --nodes=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=2G
#SBATCH --time=02:00:00
#SBATCH --output=/tmp/gedit_vnc_%j.out
#SBATCH --error=/tmp/gedit_vnc_%j.err

# ===================================================================
# GEdit VNC Job for Slurm
#
# 이 스크립트는 가시화 노드에서 실행됩니다.
# Apptainer 컨테이너로 GEdit + VNC를 실행합니다.
# ===================================================================

# 환경 변수 (Backend에서 전달)
SESSION_ID=${SESSION_ID:-"test-session"}
VNC_PORT=${VNC_PORT:-6080}
APPTAINER_IMAGE="/opt/apptainers/apps/gedit/gedit.sif"

echo "====================================================================="
echo "GEdit VNC Job Starting"
echo "====================================================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Session ID: $SESSION_ID"
echo "VNC Port: $VNC_PORT"
echo "Apptainer Image: $APPTAINER_IMAGE"
echo "====================================================================="

# 실행 노드 정보 저장 (Backend가 읽을 수 있도록)
JOB_INFO_FILE="/tmp/app_session_${SESSION_ID}.info"
cat > "$JOB_INFO_FILE" << EOF
JOB_ID=$SLURM_JOB_ID
NODE=$SLURMD_NODENAME
VNC_PORT=$VNC_PORT
SESSION_ID=$SESSION_ID
STATUS=running
START_TIME=$(date +%s)
NODE_IP=$(hostname -I | awk '{print $1}')
EOF

echo "Job info saved to: $JOB_INFO_FILE"
cat "$JOB_INFO_FILE"

# VNC 홈 디렉토리 생성 (컨테이너 내부에서 /root를 사용)
VNC_HOME="/tmp/vnc_home_${SLURM_JOB_ID}"
mkdir -p "$VNC_HOME"

# Apptainer 이미지 존재 확인
if [ ! -f "$APPTAINER_IMAGE" ]; then
    echo "ERROR: Apptainer image not found: $APPTAINER_IMAGE"
    exit 1
fi

# Instance 이름 생성
INSTANCE_NAME="gedit-${SLURM_JOB_ID}"

# 기존 Instance가 있으면 정리
if apptainer instance list | grep -q "$INSTANCE_NAME"; then
    echo "Cleaning up existing instance..."
    apptainer instance stop "$INSTANCE_NAME" 2>/dev/null || true
    sleep 2
fi

# Apptainer Instance 시작 (지속적 실행)
# 아키텍처:
#   - TigerVNC 서버는 5901 포트에서 실행 (VNC_PORT=5901)
#   - websockify는 $VNC_PORT (백엔드 전달값)에서 HTTP/WebSocket을 받아 localhost:5901로 프록시
#   - SSH 터널: controller:8xxx → viz-node:$VNC_PORT (websockify)
echo "Starting Apptainer instance: $INSTANCE_NAME (WebSocket on port $VNC_PORT)"
apptainer instance start \
    --cleanenv \
    --home "$VNC_HOME:/root" \
    --bind /tmp:/tmp \
    --bind /opt/scripts:/opt/scripts \
    "$APPTAINER_IMAGE" \
    "$INSTANCE_NAME"

# Instance 시작 대기
sleep 3

# Instance가 정상적으로 시작되었는지 확인
if ! apptainer instance list | grep -q "$INSTANCE_NAME"; then
    echo "ERROR: Failed to start apptainer instance"
    exit 1
fi

echo "Instance started successfully. Running minimal GEdit start script..."
echo "  VNC_PORT=5901 (TigerVNC server)"
echo "  WEBSOCKIFY_PORT=$VNC_PORT (WebSocket/HTTP proxy)"
echo "  VNC_RESOLUTION=1280x720"
echo "  DISPLAY=:1"

# Instance 내부에서 start-gedit-working.sh 실행 (VNC Service와 동일한 패턴)
apptainer exec --cleanenv instance://"$INSTANCE_NAME" /bin/bash -c "VNC_PORT=5901 WEBSOCKIFY_PORT=$VNC_PORT VNC_RESOLUTION=1280x720 /opt/scripts/start-gedit-working.sh 1" &
START_SCRIPT_PID=$!

echo "Start script launched (PID: $START_SCRIPT_PID)"

# VNC 서버가 완전히 시작될 때까지 대기
echo "Waiting for VNC server to be ready..."
sleep 15

# 정리 함수
cleanup() {
    echo "====================================================================="
    echo "Cleaning up GEdit VNC Job..."
    echo "====================================================================="

    # start-gedit.sh 프로세스 종료
    if [ -n "$START_SCRIPT_PID" ]; then
        kill $START_SCRIPT_PID 2>/dev/null || true
    fi

    # Instance 종료
    echo "Stopping instance: $INSTANCE_NAME"
    apptainer instance stop "$INSTANCE_NAME" 2>/dev/null || true

    # 임시 파일 정리
    rm -f "$JOB_INFO_FILE"
    rm -rf "$VNC_HOME"

    echo "Cleanup complete"
}

# 시그널 핸들러 등록
trap cleanup EXIT INT TERM

# Job이 종료될 때까지 대기 (Instance가 살아있는 동안 계속 실행)
echo "====================================================================="
echo "GEdit VNC is running. Instance: $INSTANCE_NAME"
echo "Press Ctrl+C or use scancel to terminate"
echo "====================================================================="

# Instance가 살아있는지 주기적으로 확인
while true; do
    if ! apptainer instance list | grep -q "$INSTANCE_NAME"; then
        echo "ERROR: Instance stopped unexpectedly"
        exit 1
    fi
    sleep 10
done
