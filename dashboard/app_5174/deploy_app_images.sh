#!/bin/bash
# App Framework Apptainer 이미지 배포 스크립트
# 가시화 노드에 앱 이미지를 배포합니다

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "App Framework Image Deployment"
echo "=========================================="

# 이미지 소스 디렉토리
APP_IMAGES_SOURCE="$SCRIPT_DIR/apptainer/app"

# 배포 대상 경로 (가시화 노드의 /opt/apptainers/apps)
TARGET_PATH="/opt/apptainers/apps"

# 가시화 노드 목록
declare -A VIZ_NODES
VIZ_NODES[viz-node001]="192.168.122.252"

echo ""
echo "Source: $APP_IMAGES_SOURCE"
echo "Target: $TARGET_PATH (on viz nodes)"
echo ""

# SIF 파일 찾기
SIF_FILES=$(find "$APP_IMAGES_SOURCE" -name "*.sif" 2>/dev/null)

if [ -z "$SIF_FILES" ]; then
    echo -e "${RED}❌ No .sif files found in $APP_IMAGES_SOURCE${NC}"
    echo "Please build the images first:"
    echo "  cd $APP_IMAGES_SOURCE"
    echo "  ./build.sh"
    exit 1
fi

echo "Found images:"
for sif in $SIF_FILES; do
    SIZE=$(du -h "$sif" | cut -f1)
    echo "  - $(basename $sif) ($SIZE)"
done
echo ""

# 각 가시화 노드에 배포
for node in "${!VIZ_NODES[@]}"; do
    IP="${VIZ_NODES[$node]}"

    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Deploying to $node ($IP)${NC}"
    echo -e "${YELLOW}========================================${NC}"

    # SSH 연결 테스트
    if ! ssh -o ConnectTimeout=5 "$IP" "echo 'SSH OK'" &>/dev/null; then
        echo -e "${RED}❌ Cannot connect to $node ($IP)${NC}"
        continue
    fi

    # 타겟 디렉토리 생성
    echo "Creating target directory..."
    ssh "$IP" "sudo mkdir -p $TARGET_PATH && sudo chown koopark:koopark $TARGET_PATH" || {
        echo -e "${RED}❌ Failed to create directory on $node${NC}"
        continue
    }

    # 각 앱 이미지 배포
    for sif in $SIF_FILES; do
        APP_NAME=$(basename $(dirname "$sif"))
        SIF_NAME=$(basename "$sif")

        echo ""
        echo "Deploying: $APP_NAME/$SIF_NAME"

        # 원격에 앱 디렉토리 생성
        ssh "$IP" "mkdir -p $TARGET_PATH/$APP_NAME"

        # 이미지 복사
        echo "  Copying image..."
        scp "$sif" "$IP:$TARGET_PATH/$APP_NAME/" || {
            echo -e "${RED}  ❌ Failed to copy $SIF_NAME${NC}"
            continue
        }

        # 시작 스크립트도 복사 (있으면)
        START_SCRIPT=$(dirname "$sif")/start-${APP_NAME}.sh
        if [ -f "$START_SCRIPT" ]; then
            echo "  Copying start script..."
            scp "$START_SCRIPT" "$IP:$TARGET_PATH/$APP_NAME/"
            ssh "$IP" "chmod +x $TARGET_PATH/$APP_NAME/start-${APP_NAME}.sh"
        fi

        echo -e "${GREEN}  ✅ $SIF_NAME deployed successfully${NC}"
    done

    echo ""
    echo "Verifying deployment..."
    ssh "$IP" "ls -lh $TARGET_PATH/*/*.sif 2>/dev/null || echo 'No images found'"

    echo -e "${GREEN}✅ Deployment to $node complete${NC}"
done

echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="

for node in "${!VIZ_NODES[@]}"; do
    IP="${VIZ_NODES[$node]}"
    echo ""
    echo "Node: $node ($IP)"

    if ssh -o ConnectTimeout=5 "$IP" "test -d $TARGET_PATH" &>/dev/null; then
        echo "Images:"
        ssh "$IP" "find $TARGET_PATH -name '*.sif' -exec du -h {} \;" 2>/dev/null | \
            awk '{print "  - " $2 " (" $1 ")"}'
    else
        echo -e "${RED}  ❌ Not accessible${NC}"
    fi
done

echo ""
echo "=========================================="
echo -e "${GREEN}Deployment complete!${NC}"
echo "=========================================="
echo ""
echo "Images are located at: $TARGET_PATH on viz nodes"
echo ""
echo "Test deployment:"
echo "  ssh viz-node001 'ls -lh $TARGET_PATH/*/*.sif'"
echo ""
