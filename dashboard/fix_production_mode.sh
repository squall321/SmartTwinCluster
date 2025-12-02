#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "🔧 Production Mode 완전 재설정"
echo "=========================================="
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# Step 1: 완전 종료
echo -e "${BLUE}Step 1: 모든 서비스 완전 종료...${NC}"
./stop_all.sh
sleep 2

# PID 파일 삭제
rm -f backend_5010/.backend.pid
rm -f websocket_5011/.websocket.pid
rm -f frontend_3010/.frontend.pid

# 포트 강제 정리
for port in 3010 5010 5011 9100 9090; do
    pid=$(lsof -ti :$port 2>/dev/null)
    if [ -n "$pid" ]; then
        echo "  포트 $port 정리 (PID: $pid)"
        kill -9 $pid 2>/dev/null
    fi
done

sleep 2
echo -e "${GREEN}✅ 완전 종료 완료${NC}"
echo ""

# Step 2: start_all.sh 실행 (Production Mode)
echo -e "${BLUE}Step 2: start_all.sh로 Production Mode 시작...${NC}"
./start_all.sh

sleep 5
echo ""

# Step 3: 검증
echo -e "${BLUE}Step 3: Production Mode 검증...${NC}"
echo ""

# API 모드 확인
echo "  🔍 API 모드 확인:"
api_response=$(curl -s http://localhost:5010/api/nodes)
api_mode=$(echo "$api_response" | jq -r '.mode' 2>/dev/null)
api_count=$(echo "$api_response" | jq -r '.count' 2>/dev/null)

echo "    Mode: $api_mode"
echo "    Node Count: $api_count"

if [ "$api_mode" = "production" ]; then
    echo -e "    ${GREEN}✅ Production Mode 확인!${NC}"
else
    echo -e "    ${RED}❌ 여전히 Mock Mode${NC}"
    echo ""
    echo "  Backend 로그 확인:"
    tail -20 backend_5010/logs/backend.log | grep -i "mock\|production"
    echo ""
    echo -e "${YELLOW}  해결 방법: Backend를 수동으로 Production Mode로 시작${NC}"
    echo "    cd backend_5010"
    echo "    ./stop.sh"
    echo "    MOCK_MODE=false ./start.sh"
    exit 1
fi

echo ""

# Step 4: 실제 노드 확인
echo "  🔍 실제 Slurm 노드 확인:"
if [ "$api_mode" = "production" ]; then
    if command -v sinfo &> /dev/null; then
        echo "    sinfo 명령어 사용 가능 ✅"
        echo ""
        echo "    실제 노드 목록:"
        sinfo -N -o "%N %T %C" | head -5
    else
        echo -e "    ${YELLOW}⚠️  sinfo 명령어 없음 (Slurm 미설치)${NC}"
        echo "    Mock Mode를 사용하려면: ./start_all_mock.sh"
    fi
fi

echo ""

# Step 5: 브라우저 안내
echo "=========================================="
echo -e "${GREEN}✅ 설정 완료!${NC}"
echo "=========================================="
echo ""
echo "📱 브라우저 확인 방법:"
echo ""
echo "  1. 브라우저를 열고 다음 중 하나 실행:"
echo "     - Chrome/Edge: Ctrl + Shift + Delete → 캐시 삭제"
echo "     - 또는 시크릿 모드로 열기"
echo ""
echo "  2. 접속: http://localhost:3010"
echo ""
echo "  3. Node Management 탭 클릭"
echo ""
echo "  4. 우측 상단의 Mode Badge 확인:"
if [ "$api_mode" = "production" ]; then
    echo "     🚀 PRODUCTION (초록색) 이어야 함"
else
    echo "     🎭 MOCK MODE (노란색)"
fi
echo ""
echo "  5. Hard Refresh (캐시 무시):"
echo "     - Windows/Linux: Ctrl + F5"
echo "     - Mac: Cmd + Shift + R"
echo ""
echo "💡 여전히 Mock Mode로 표시되면:"
echo "   - 브라우저 캐시를 완전히 삭제하세요"
echo "   - 또는 시크릿/프라이빗 모드로 여세요"
echo ""
