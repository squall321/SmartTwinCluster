#!/bin/bash
# Production Mode 강제 재시작 스크립트

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "🚀 Production Mode로 강제 재시작"
echo "=========================================="
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 1. 모든 서버 종료
echo -e "${YELLOW}1. 모든 서버 종료...${NC}"
./stop_all.sh
sleep 3

# 2. Production Mode 확인
echo ""
echo -e "${BLUE}2. Production Mode 환경변수 설정...${NC}"
export MOCK_MODE=false
echo "MOCK_MODE=$MOCK_MODE"

# 3. Backend 시작 (Production Mode)
echo ""
echo -e "${BLUE}3. Backend 시작 (Production Mode)...${NC}"
cd backend_5010
MOCK_MODE=false ./start.sh
sleep 3

# 4. 확인
echo ""
echo -e "${BLUE}4. 모드 확인...${NC}"
curl -s http://localhost:5010/api/nodes | jq -r '.mode' 2>/dev/null
api_mode=$(curl -s http://localhost:5010/api/nodes | jq -r '.mode' 2>/dev/null)

if [ "$api_mode" = "production" ]; then
    echo -e "${GREEN}✅ Production Mode 확인됨!${NC}"
else
    echo -e "${RED}❌ 여전히 Mock Mode: $api_mode${NC}"
    echo ""
    echo "Backend 로그 확인:"
    tail -10 logs/backend.log
    exit 1
fi

cd ..

# 5. WebSocket 시작
echo ""
echo -e "${BLUE}5. WebSocket 시작...${NC}"
cd websocket_5011
MOCK_MODE=false ./start.sh
sleep 2
cd ..

# 6. Frontend 시작
echo ""
echo -e "${BLUE}6. Frontend 시작...${NC}"
cd frontend_3010
./start.sh
sleep 2
cd ..

# 7. Prometheus & Node Exporter 시작
echo ""
echo -e "${BLUE}7. Monitoring 시작...${NC}"
[ -f "node_exporter_9100/start.sh" ] && cd node_exporter_9100 && ./start.sh && cd ..
[ -f "prometheus_9090/start.sh" ] && cd prometheus_9090 && ./start.sh && cd ..

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Production Mode 시작 완료!${NC}"
echo "=========================================="
echo ""
echo "🔗 접속: http://localhost:3010"
echo "🎯 모드: Production (MOCK_MODE=false)"
echo ""
echo "확인 방법:"
echo "  1. 브라우저 Hard Refresh (Ctrl+F5 또는 Cmd+Shift+R)"
echo "  2. Node Management 탭 확인"
echo "  3. Mode Badge가 🚀 PRODUCTION으로 표시되어야 함"
echo ""
