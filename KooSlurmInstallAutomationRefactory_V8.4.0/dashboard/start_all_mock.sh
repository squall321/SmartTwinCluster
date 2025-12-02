#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🚀 모든 서버 시작 (Mock Mode)"
echo "=========================================="
echo ""
echo "🎯 모드: Mock (테스트 데이터 사용)"
echo "   - Backend: MOCK_MODE=true"
echo "   - WebSocket: MOCK_MODE=true"
echo "   - 샘플 노드 4개 (cn01~cn04) 표시"
echo "   - 실제 Slurm 명령 미실행"
echo ""

# 포트 사용 중 확인 및 강제 종료
echo -e "${BLUE}🔍 포트 충돌 확인 중...${NC}"
PORT_CONFLICTS=0
PORTS=(3010 5010 5011 9100 9090)
KILL_PIDS=()

for PORT in "${PORTS[@]}"; do
    PIDS=$(lsof -ti :$PORT 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo -e "${YELLOW}⚠️  포트 $PORT가 사용 중입니다 (PID: $PIDS)${NC}"
        PORT_CONFLICTS=$((PORT_CONFLICTS + 1))
        KILL_PIDS+=("$PIDS")
    fi
done

if [ $PORT_CONFLICTS -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}🔧 $PORT_CONFLICTS개의 포트가 사용 중입니다. 프로세스를 종료합니다...${NC}"
    
    for PID in "${KILL_PIDS[@]}"; do
        kill -9 $PID 2>/dev/null && echo -e "${GREEN}✓ PID $PID 종료됨${NC}"
    done
    
    echo ""
    sleep 2
    echo -e "${GREEN}✓ 모든 포트 정리 완료${NC}"
else
    echo -e "${GREEN}✓ 모든 포트 사용 가능${NC}"
fi

echo ""

# 🔧 FIX: MOCK_MODE를 true로 설정하고 전파
export MOCK_MODE=true
echo -e "${GREEN}✓ MOCK_MODE 환경변수 설정: ${MOCK_MODE}${NC}"
echo ""

# Backend 시작 (MOCK_MODE 전달)
echo -e "${BLUE}▶ Backend 시작 중...${NC}"
cd "${SCRIPT_DIR}/backend_5010"
MOCK_MODE=true ./start.sh
cd "${SCRIPT_DIR}"
echo ""

# WebSocket 시작 (MOCK_MODE 전달)
echo -e "${BLUE}▶ WebSocket 시작 중...${NC}"
cd "${SCRIPT_DIR}/websocket_5011"
MOCK_MODE=true ./start.sh
cd "${SCRIPT_DIR}"
echo ""

# Frontend 시작
echo -e "${BLUE}▶ Frontend 시작 중...${NC}"
cd "${SCRIPT_DIR}/frontend_3010"
./start.sh
cd "${SCRIPT_DIR}"
echo ""

# Node Exporter 시작 (선택적)
if [ -f "node_exporter_9100/start.sh" ]; then
    echo -e "${BLUE}▶ Node Exporter 시작 중...${NC}"
    cd "${SCRIPT_DIR}/node_exporter_9100"
    ./start.sh
    cd "${SCRIPT_DIR}"
    echo ""
fi

# Prometheus 시작 (선택적)
if [ -f "prometheus_9090/start.sh" ]; then
    echo -e "${BLUE}▶ Prometheus 시작 중...${NC}"
    cd "${SCRIPT_DIR}/prometheus_9090"
    ./start.sh
    cd "${SCRIPT_DIR}"
    echo ""
fi

echo "=========================================="
echo "✅ 모든 서버 시작 완료!"
echo "=========================================="
echo ""
echo "🔗 접속 정보:"
echo "  Frontend:  http://localhost:3010"
echo "  Backend:   http://localhost:5010"
echo "  WebSocket: ws://localhost:5011/ws"
echo "  Node Exporter: http://localhost:9100/metrics"
echo "  Prometheus: http://localhost:9090"
echo ""
echo "🎯 모드: 🎭 Mock (MOCK_MODE=true)"
echo "   - 테스트 데이터 사용"
echo "   - Node Management: 샘플 노드 4개 (cn01~cn04)"
echo "   - Slurm 명령 실행 안함 (안전하게 테스트)"
echo ""
echo "📝 확인 명령어:"
echo "  Backend 로그:  tail -f backend_5010/logs/backend.log"
echo "  WebSocket 로그: tail -f websocket_5011/logs/websocket.log"
echo "  Frontend 로그:  tail -f frontend_3010/logs/frontend.log"
echo ""
echo "🔴 종료: ./stop_all.sh"
echo "🚀 Production Mode로 시작: ./start_all.sh"
