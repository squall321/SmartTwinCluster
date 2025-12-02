#!/bin/bash
# WebSocket 서버 강제 재설정 스크립트
# prometheus_client가 없어서 에러나는 경우 사용

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/websocket_5011"

echo -e "${YELLOW}WebSocket 서버 재설정 중...${NC}"

# 1. 서버 중지
if [ -f "stop.sh" ]; then
    ./stop.sh
fi

# 2. venv 확인 및 prometheus_client 설치
if [ -d "venv" ]; then
    echo -e "${YELLOW}기존 venv에 prometheus_client 설치...${NC}"
    source venv/bin/activate
    pip install prometheus_client>=0.19.0 --quiet
    deactivate
    echo -e "${GREEN}✅ prometheus_client 설치 완료${NC}"
else
    echo -e "${RED}❌ venv 없음. ./setup.sh 먼저 실행하세요${NC}"
    exit 1
fi

# 3. 서버 시작
echo -e "${YELLOW}WebSocket 서버 시작...${NC}"
./start.sh

# 4. 테스트
sleep 2
echo ""
echo -e "${YELLOW}Metrics 엔드포인트 테스트...${NC}"
if curl -s http://localhost:5011/metrics | head -5 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ WebSocket /metrics 정상 작동!${NC}"
else
    echo -e "${RED}❌ WebSocket /metrics 여전히 에러${NC}"
    echo ""
    echo "로그 확인:"
    tail -20 websocket.log
fi

cd ..
