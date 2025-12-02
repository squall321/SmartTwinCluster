#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 포트 번호 (폴더 이름에서 추출)
PORT=9090

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
[ -f ".prometheus.pid" ] && kill $(cat .prometheus.pid) 2>/dev/null && rm -f .prometheus.pid

mkdir -p data
nohup ./prometheus --config.file=prometheus.yml --storage.tsdb.path=./data > prometheus.log 2>&1 &
echo $! > .prometheus.pid
sleep 1

ps -p $(cat .prometheus.pid) > /dev/null 2>&1 && \
    echo -e "${GREEN}✅ Prometheus 시작 (PID: $(cat .prometheus.pid))${NC}\n🔗 http://localhost:${PORT}" || \
    (echo -e "${RED}❌ 시작 실패${NC}" && tail -20 prometheus.log)
