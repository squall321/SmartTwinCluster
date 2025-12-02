#!/bin/bash

################################################################################
# Apptainer 동기화 테스트 스크립트
# 
# 실제 복사 없이 동기화 프로세스를 시뮬레이션합니다.
################################################################################

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BLUE}==================================================================${NC}"
echo -e "${BLUE}  Apptainer 동기화 테스트 (DRY-RUN)${NC}"
echo -e "${BLUE}==================================================================${NC}"
echo ""

echo -e "${CYAN}ℹ️  이 스크립트는 실제 파일을 복사하지 않습니다.${NC}"
echo -e "${CYAN}   동기화 과정만 시뮬레이션합니다.${NC}"
echo ""

# 스크립트 존재 확인
if [ ! -f "sync_apptainers_to_nodes.sh" ]; then
    echo -e "${YELLOW}⚠️  sync_apptainers_to_nodes.sh 파일이 없습니다.${NC}"
    exit 1
fi

# 실행 권한 확인
if [ ! -x "sync_apptainers_to_nodes.sh" ]; then
    echo -e "${YELLOW}⚠️  실행 권한이 없습니다. 권한을 부여합니다...${NC}"
    chmod +x sync_apptainers_to_nodes.sh
fi

# DRY-RUN 모드로 실행
echo -e "${GREEN}→ DRY-RUN 모드로 동기화 테스트 시작...${NC}"
echo ""

./sync_apptainers_to_nodes.sh --dry-run

echo ""
echo -e "${BLUE}==================================================================${NC}"
echo -e "${GREEN}  테스트 완료!${NC}"
echo -e "${BLUE}==================================================================${NC}"
echo ""

echo -e "${CYAN}다음 단계:${NC}"
echo ""
echo "1. 실제 동기화를 실행하려면:"
echo "   ./sync_apptainers_to_nodes.sh"
echo ""
echo "2. 기존 파일을 강제로 덮어쓰려면:"
echo "   ./sync_apptainers_to_nodes.sh --force"
echo ""
echo "3. 도움말을 보려면:"
echo "   ./sync_apptainers_to_nodes.sh --help"
echo ""
