#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 포트 번호 (폴더 이름에서 추출)
PORT=5011

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
[ -f ".websocket.pid" ] && kill $(cat .websocket.pid) 2>/dev/null && rm -f .websocket.pid

[ ! -f "venv/bin/activate" ] && echo -e "${RED}❌ venv 없음. ./setup.sh 실행${NC}" && exit 1

source venv/bin/activate

# 누락 모듈 자동 복구 (오프라인 휠)
source "$SCRIPT_DIR/../common/ensure_venv.sh" 2>/dev/null && ensure_venv aiohttp aiohttp_cors

# MOCK_MODE 환경변수 상속 (start_all.sh에서 설정됨)
export MOCK_MODE=${MOCK_MODE:-false}

nohup "$SCRIPT_DIR/venv/bin/python3" websocket_server_enhanced.py > websocket.log 2>&1 &
echo $! > .websocket.pid
sleep 2

ps -p $(cat .websocket.pid) > /dev/null 2>&1 && \
    echo -e "${GREEN}✅ WebSocket 시작 (PID: $(cat .websocket.pid))${NC}\n🔗 ws://localhost:${PORT}/ws\n💡 독립 venv 사용\n🎯 MOCK_MODE=${MOCK_MODE}" || \
    (echo -e "${RED}❌ 시작 실패${NC}" && tail -20 websocket.log)
deactivate
