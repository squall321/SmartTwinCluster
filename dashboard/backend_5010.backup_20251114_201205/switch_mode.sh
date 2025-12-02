#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🔄 Backend Mode Switcher"
echo "=========================================="
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# 현재 모드 확인
current_pid=$(cat .backend.pid 2>/dev/null)
if [ -n "$current_pid" ] && ps -p $current_pid > /dev/null 2>&1; then
    echo -e "${BLUE}현재 Backend가 실행 중입니다 (PID: $current_pid)${NC}"
    
    # 로그에서 현재 모드 확인
    current_mode=$(grep "Running in" logs/backend.log | tail -1)
    echo "현재 모드: $current_mode"
    echo ""
fi

# 모드 선택
echo "실행할 모드를 선택하세요:"
echo "  1) Mock Mode (개발/테스트용)"
echo "  2) Production Mode (실제 Slurm 사용)"
echo ""
read -p "선택 (1 or 2): " choice

case $choice in
    1)
        MODE="mock"
        MOCK_MODE="true"
        echo -e "${YELLOW}🎭 Mock Mode로 시작합니다...${NC}"
        ;;
    2)
        MODE="production"
        MOCK_MODE="false"
        echo -e "${GREEN}🚀 Production Mode로 시작합니다...${NC}"
        ;;
    *)
        echo -e "${RED}❌ 잘못된 선택입니다${NC}"
        exit 1
        ;;
esac

echo ""

# Backend 중지
echo "1. Backend 중지..."
./stop.sh
sleep 2

# Backend 시작 (선택한 모드로)
echo ""
echo "2. Backend 시작 ($MODE mode)..."
MOCK_MODE=$MOCK_MODE ./start.sh
sleep 3

# 확인
echo ""
echo "3. 상태 확인:"
if curl -s http://localhost:5010/api/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Backend: Running${NC}"
    
    # API 모드 확인
    api_mode=$(curl -s http://localhost:5010/api/nodes | jq -r '.mode' 2>/dev/null)
    echo -e "API Mode: ${BLUE}$api_mode${NC}"
else
    echo -e "${RED}❌ Backend: Not running${NC}"
fi

echo ""
echo "=========================================="
echo "✅ 모드 전환 완료!"
echo "=========================================="
echo ""
echo "브라우저에서 확인하세요:"
echo "http://localhost:3010"
echo ""
echo "Node Management 탭에서 Mode Badge를 확인하세요:"
if [ "$MODE" = "mock" ]; then
    echo "  🎭 MOCK MODE - 4개 샘플 노드 표시"
else
    echo "  🚀 PRODUCTION - 실제 Slurm 노드 표시"
fi
