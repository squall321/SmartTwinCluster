#!/bin/bash
# GEdit Apptainer 이미지 빌드 및 배포 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="gedit"
DEF_FILE="$SCRIPT_DIR/apptainer/app/${APP_NAME}/${APP_NAME}.def"
SIF_FILE="$SCRIPT_DIR/${APP_NAME}.sif"
VIZ_NODE="viz-node001"
VIZ_NODE_IP="192.168.122.252"
SSH_USER="koopark"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# 배포 대상 경로
REMOTE_IMAGE_DIR="/opt/apptainers/apps/${APP_NAME}"
REMOTE_IMAGE_PATH="${REMOTE_IMAGE_DIR}/${APP_NAME}.sif"

echo "=========================================="
echo "GEdit Apptainer 빌드 및 배포"
echo "=========================================="

# 1. 정의 파일 확인
if [ ! -f "$DEF_FILE" ]; then
    echo "❌ 정의 파일 없음: $DEF_FILE"
    exit 1
fi

echo "✅ 정의 파일: $DEF_FILE"

# 2. 이미지 빌드 (선택적)
if [ "$1" == "--build" ] || [ ! -f "$SIF_FILE" ]; then
    echo ""
    echo "🔨 이미지 빌드 중..."
    sudo apptainer build "$SIF_FILE" "$DEF_FILE"
    echo "✅ 빌드 완료: $SIF_FILE"
    echo "   크기: $(du -h "$SIF_FILE" | cut -f1)"
fi

# 3. 이미지 확인
if [ ! -f "$SIF_FILE" ]; then
    echo "❌ 이미지 파일 없음: $SIF_FILE"
    echo "💡 --build 옵션으로 빌드하세요: $0 --build"
    exit 1
fi

echo ""
echo "📦 배포할 이미지: $SIF_FILE ($(du -h "$SIF_FILE" | cut -f1))"

# 4. viz-node001 접속 확인
echo ""
echo "🔍 viz-node001 접속 확인..."
if ! ssh $SSH_OPTS ${SSH_USER}@${VIZ_NODE_IP} "exit" 2>/dev/null; then
    echo "❌ SSH 접속 실패: ${VIZ_NODE_IP}"
    exit 1
fi
echo "✅ SSH 접속 성공"

# 5. 원격 디렉토리 생성
echo ""
echo "📁 원격 디렉토리 생성: ${REMOTE_IMAGE_DIR}"
ssh $SSH_OPTS ${SSH_USER}@${VIZ_NODE_IP} "sudo mkdir -p ${REMOTE_IMAGE_DIR}"

# 6. 이미지 전송
echo ""
echo "📤 이미지 전송 중..."
echo "   From: $SIF_FILE"
echo "   To:   ${VIZ_NODE}:${REMOTE_IMAGE_PATH}"

# /tmp에 먼저 복사
scp $SSH_OPTS "$SIF_FILE" ${SSH_USER}@${VIZ_NODE_IP}:/tmp/${APP_NAME}.sif

# sudo로 /opt로 이동
ssh $SSH_OPTS ${SSH_USER}@${VIZ_NODE_IP} "sudo mv /tmp/${APP_NAME}.sif ${REMOTE_IMAGE_PATH} && \
    sudo chown root:root ${REMOTE_IMAGE_PATH} && \
    sudo chmod 755 ${REMOTE_IMAGE_PATH}"

echo "✅ 전송 완료"

# 7. 배포 확인
echo ""
echo "🔍 배포 확인:"
ssh $SSH_OPTS ${SSH_USER}@${VIZ_NODE_IP} "sudo ls -lh ${REMOTE_IMAGE_DIR}/"

echo ""
echo "=========================================="
echo "✅ GEdit 배포 완료!"
echo "=========================================="
echo ""
echo "📍 배포 위치: ${VIZ_NODE}:${REMOTE_IMAGE_PATH}"
echo ""
echo "🧪 테스트 방법:"
echo "  cd slurm_jobs"
echo "  sbatch --export SESSION_ID=test,VNC_PORT=6080 gedit_vnc_job.sh"
echo ""
