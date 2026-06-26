#!/bin/bash
# 프론트엔드만 재시작하는 스크립트

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "🔄 Frontend 재시작 (Node Management 수정 반영)"
echo "=========================================="
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/frontend_3010

# Frontend 중지
echo -e "${BLUE}1. Frontend 중지...${NC}"
./stop.sh
sleep 2

# Frontend 시작
echo -e "${BLUE}2. Frontend 시작...${NC}"
./start.sh
sleep 3

# 상태 확인
echo ""
echo -e "${BLUE}3. 상태 확인...${NC}"
if curl -s http://localhost:3010 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Frontend: Running${NC}"
else
    echo -e "${RED}❌ Frontend: Not running${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Frontend 재시작 완료!${NC}"
echo "=========================================="
echo ""
echo "📱 다음 단계:"
echo ""
echo "  1. 브라우저 Hard Refresh:"
echo "     - Windows/Linux: Ctrl + F5"
echo "     - Mac: Cmd + Shift + R"
echo ""
echo "  2. 접속: http://localhost:3010"
echo ""
echo "  3. Node Management 탭 클릭"
echo ""
echo "  4. 개발자 도구(F12) → Console 확인:"
echo "     [NodeManagement] API Response - Mode: production"
echo ""
echo "  5. Mode Badge 확인:"
echo "     - ⏳ Loading... (잠시 표시)"
echo "     - 🚀 PRODUCTION (초록색)"
echo ""
