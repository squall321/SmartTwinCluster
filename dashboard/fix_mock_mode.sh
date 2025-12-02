#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "🔧 Mock Mode 수정"
echo "=========================================="
echo ""

# 1. 기존 프로세스 종료
echo -e "${BLUE}1️⃣  기존 프로세스 종료 중...${NC}"
cd "$SCRIPT_DIR"
./stop_all.sh 2>/dev/null
sleep 2
echo -e "${GREEN}✓ 기존 프로세스 종료 완료${NC}"
echo ""

# 2. Backend start.sh 수정
echo -e "${BLUE}2️⃣  Backend start.sh 수정 중...${NC}"
cat > backend_5010/start.sh << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 포트 번호
PORT=5010

echo -e "${YELLOW}전 Step: 포트 ${PORT} 체크 및 정리...${NC}"

# 해당 포트를 사용 중인 프로세스 강제 종료
PID=$(lsof -ti:$PORT 2>/dev/null)
if [ ! -z "$PID" ]; then
    echo -e "${YELLOW}⚠️  포트 ${PORT}에서 실행 중인 프로세스 발견 (PID: $PID)${NC}"
    kill -9 $PID 2>/dev/null
    sleep 1
    echo -e "${GREEN}✅ 포트 ${PORT} 정리 완료${NC}"
fi

# PID 파일로 기록된 프로세스도 종료
[ -f ".backend.pid" ] && kill $(cat .backend.pid) 2>/dev/null && rm -f .backend.pid

[ ! -f "venv/bin/activate" ] && echo -e "${RED}❌ venv 없음. ./setup.sh 실행${NC}" && exit 1

source venv/bin/activate
export FLASK_APP=app.py FLASK_ENV=production

# 🔧 FIX: MOCK_MODE 환경변수 강제 설정
# 부모 스크립트(start_all_mock.sh)에서 export MOCK_MODE=true를 하더라도
# nohup으로 실행되면서 환경변수가 유실될 수 있음
# 따라서 여기서 명시적으로 다시 설정
if [ -z "$MOCK_MODE" ]; then
    # 환경변수가 없으면 기본값 사용 (false = Production)
    export MOCK_MODE=false
    echo -e "${YELLOW}⚠️  MOCK_MODE 환경변수 없음. 기본값(false) 사용${NC}"
else
    # 환경변수가 있으면 사용
    echo -e "${GREEN}✓ MOCK_MODE 환경변수 감지: ${MOCK_MODE}${NC}"
fi

# 🔧 FIX: Python 실행 시 환경변수 전달 보장
mkdir -p logs

# nohup 실행 시 env를 사용하여 환경변수 명시적 전달
nohup env MOCK_MODE=$MOCK_MODE python app.py > logs/backend.log 2>&1 &
echo $! > .backend.pid
sleep 2

# 시작 확인
if ps -p $(cat .backend.pid) > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Backend 시작 성공!${NC}"
    echo -e "   PID: $(cat .backend.pid)"
    echo -e "   URL: http://localhost:${PORT}"
    echo -e "   Mode: ${MOCK_MODE}"
    echo ""
    echo -e "${BLUE}📝 로그 확인:${NC}"
    echo -e "   tail -f logs/backend.log"
    echo ""
    # 시작 로그 출력
    sleep 1
    echo -e "${BLUE}=== Backend 시작 로그 ===${NC}"
    tail -20 logs/backend.log
else
    echo -e "${RED}❌ Backend 시작 실패${NC}"
    echo -e "${RED}=== 에러 로그 ===${NC}"
    tail -20 logs/backend.log
fi

deactivate
EOF

chmod +x backend_5010/start.sh
echo -e "${GREEN}✓ Backend start.sh 수정 완료${NC}"
echo ""

# 3. start_all_mock.sh 수정 (MOCK_MODE export 위치 변경)
echo -e "${BLUE}3️⃣  start_all_mock.sh 수정 중...${NC}"
cat > start_all_mock.sh << 'EOF'
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
EOF

chmod +x start_all_mock.sh
echo -e "${GREEN}✓ start_all_mock.sh 수정 완료${NC}"
echo ""

# 4. Mock Mode로 재시작
echo -e "${BLUE}4️⃣  Mock Mode로 재시작 중...${NC}"
echo ""
./start_all_mock.sh

echo ""
echo "=========================================="
echo "✅ Mock Mode 수정 완료!"
echo "=========================================="
echo ""
echo "🎯 다음 단계:"
echo ""
echo "1️⃣  Backend 로그 확인:"
echo "   tail -f backend_5010/logs/backend.log"
echo ""
echo "   다음 문구가 나와야 함:"
echo -e "   ${GREEN}⚠️  Running in MOCK MODE${NC}"
echo ""
echo "2️⃣  Frontend 접속:"
echo "   http://localhost:3010"
echo ""
echo "3️⃣  Node Management로 이동:"
echo "   - 왼쪽 메뉴: Node Management 클릭"
echo "   - 우측 상단: 🎭 MOCK MODE 배지 확인"
echo "   - 노드 목록: cn01, cn02, cn03 표시 확인"
echo ""
echo "4️⃣  API 직접 테스트:"
echo "   curl http://localhost:5010/api/nodes | jq"
echo ""
echo "   예상 출력:"
echo "   {\"mode\": \"mock\", \"nodes\": [{\"name\": \"cn01\", ...}]}"
echo ""
