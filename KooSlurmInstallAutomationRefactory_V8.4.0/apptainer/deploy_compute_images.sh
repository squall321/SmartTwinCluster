#!/bin/bash
################################################################################
# Compute Node Apptainer 이미지 배포 스크립트
# /apptainer/compute-node-images에 있는 .sif 파일들을 모든 compute node에 배포
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정
CONFIG_FILE="${1:-$PROJECT_ROOT/my_multihead_cluster.yaml}"
SOURCE_DIR="$SCRIPT_DIR/compute-node-images"
TARGET_DIR="/opt/apptainers/compute"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

echo "=========================================="
echo "Compute Node Apptainer Image Deployment"
echo "=========================================="
echo ""

# 설정 파일 확인
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

echo "Configuration: $CONFIG_FILE"
echo "Source:        $SOURCE_DIR"
echo "Target:        $TARGET_DIR (on compute nodes)"
echo ""

# Python YAML 모듈 확인
if ! python3 -c "import yaml" 2>/dev/null; then
    echo -e "${RED}❌ Python yaml module required: pip3 install pyyaml${NC}"
    exit 1
fi

# SIF 파일 찾기
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}❌ Source directory not found: $SOURCE_DIR${NC}"
    exit 1
fi

SIF_FILES=$(find "$SOURCE_DIR" -maxdepth 1 -name "*.sif" 2>/dev/null)

if [ -z "$SIF_FILES" ]; then
    echo -e "${YELLOW}⚠️  No .sif files found in $SOURCE_DIR${NC}"
    echo ""
    echo "Build images first or place .sif files in:"
    echo "  $SOURCE_DIR/"
    exit 0
fi

echo -e "${GREEN}Found images:${NC}"
for sif in $SIF_FILES; do
    SIZE=$(du -h "$sif" | cut -f1)
    echo "  - $(basename $sif) ($SIZE)"
done
echo ""

# YAML에서 compute node 목록 추출
echo "Extracting compute nodes from YAML..."

COMPUTE_NODES=$(python3 << EOPY
import yaml
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)

    nodes = config.get('nodes', {}).get('compute_nodes', [])

    if not nodes:
        print("", file=sys.stderr)
        sys.exit(0)

    for node in nodes:
        hostname = node.get('hostname', '')
        ip = node.get('ip_address', '')
        user = node.get('ssh_user', 'koopark')

        if hostname and ip:
            print(f"{hostname}|{ip}|{user}")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOPY
)

if [ -z "$COMPUTE_NODES" ]; then
    echo -e "${YELLOW}⚠️  No compute nodes defined in YAML${NC}"
    echo ""
    echo "Add compute nodes to $CONFIG_FILE:"
    echo "  nodes:"
    echo "    compute_nodes:"
    echo "      - hostname: node001"
    echo "        ip_address: 192.168.122.90"
    echo "        ssh_user: koopark"
    exit 0
fi

echo -e "${GREEN}Compute nodes:${NC}"
echo "$COMPUTE_NODES" | while IFS='|' read -r hostname ip user; do
    echo "  - $hostname ($ip)"
done
echo ""

# 각 compute node에 배포
SUCCESS_COUNT=0
FAIL_COUNT=0

echo "$COMPUTE_NODES" | while IFS='|' read -r hostname ip user; do
    echo -e "${YELLOW}==========================================${NC}"
    echo -e "${YELLOW}Deploying to $hostname ($ip)${NC}"
    echo -e "${YELLOW}==========================================${NC}"

    # SSH 연결 테스트
    echo "Testing SSH connection..."
    if ! ssh $SSH_OPTS -o ConnectTimeout=5 ${user}@${ip} "echo 'SSH OK'" &>/dev/null; then
        echo -e "${RED}❌ Cannot connect to $hostname ($ip)${NC}"
        echo ""
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    echo -e "${GREEN}✅ SSH connection successful${NC}"

    # 타겟 디렉토리 생성
    echo "Creating target directory: $TARGET_DIR"
    if ! ssh $SSH_OPTS ${user}@${ip} "sudo mkdir -p $TARGET_DIR && sudo chown ${user}:${user} $TARGET_DIR" 2>/dev/null; then
        echo -e "${RED}❌ Failed to create directory on $hostname${NC}"
        echo ""
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # 각 .sif 파일 배포
    for sif in $SIF_FILES; do
        SIF_NAME=$(basename "$sif")
        SIZE=$(du -h "$sif" | cut -f1)

        echo ""
        echo "Deploying: $SIF_NAME ($SIZE)"

        # /tmp에 먼저 복사 (권한 문제 방지)
        echo "  Copying to /tmp..."
        if ! scp $SSH_OPTS "$sif" ${user}@${ip}:/tmp/${SIF_NAME} 2>/dev/null; then
            echo -e "${RED}  ❌ Failed to copy $SIF_NAME${NC}"
            continue
        fi

        # sudo로 /opt로 이동 및 권한 설정
        echo "  Moving to $TARGET_DIR..."
        if ! ssh $SSH_OPTS ${user}@${ip} "sudo mv /tmp/${SIF_NAME} ${TARGET_DIR}/ && \
            sudo chown root:root ${TARGET_DIR}/${SIF_NAME} && \
            sudo chmod 755 ${TARGET_DIR}/${SIF_NAME}" 2>/dev/null; then
            echo -e "${RED}  ❌ Failed to move $SIF_NAME to $TARGET_DIR${NC}"
            continue
        fi

        echo -e "${GREEN}  ✅ $SIF_NAME deployed successfully${NC}"
    done

    # 배포 확인
    echo ""
    echo "Verifying deployment..."
    ssh $SSH_OPTS ${user}@${ip} "sudo ls -lh $TARGET_DIR/*.sif 2>/dev/null || echo '  No images found'"

    echo -e "${GREEN}✅ Deployment to $hostname complete${NC}"
    echo ""
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
done

# 배포 요약
echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="

echo "$COMPUTE_NODES" | while IFS='|' read -r hostname ip user; do
    echo ""
    echo "Node: $hostname ($ip)"

    if ssh $SSH_OPTS -o ConnectTimeout=5 ${user}@${ip} "test -d $TARGET_DIR" &>/dev/null; then
        echo "Images:"
        ssh $SSH_OPTS ${user}@${ip} "sudo find $TARGET_DIR -maxdepth 1 -name '*.sif' -exec du -h {} \;" 2>/dev/null | \
            awk '{print "  - " $2 " (" $1 ")"}'

        if [ $? -ne 0 ]; then
            echo -e "${RED}  ❌ Not accessible or no images${NC}"
        fi
    else
        echo -e "${RED}  ❌ Not accessible${NC}"
    fi
done

echo ""
echo "=========================================="
echo -e "${GREEN}Deployment Complete!${NC}"
echo "=========================================="
echo ""
echo "Images deployed to: $TARGET_DIR on all compute nodes"
echo ""
echo "Test deployment:"
echo "  ssh node001 'sudo ls -lh $TARGET_DIR/*.sif'"
echo ""
