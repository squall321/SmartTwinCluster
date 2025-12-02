#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 포트 번호
PORT=5000

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
[ -f ".cae_backend.pid" ] && kill $(cat .cae_backend.pid) 2>/dev/null && rm -f .cae_backend.pid

[ ! -f "venv/bin/activate" ] && echo -e "${RED}❌ venv 없음. ./setup.sh 실행${NC}" && exit 1

source venv/bin/activate
export FLASK_APP=app.py FLASK_ENV=production

# Load Redis configuration from .env file if exists
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
    echo -e "${GREEN}✓ Redis 설정 로드 (.env)${NC}"
fi

# MOCK_MODE 환경변수 설정
if [ -z "$MOCK_MODE" ]; then
    export MOCK_MODE=false
    echo -e "${YELLOW}⚠️  MOCK_MODE 환경변수 없음. 기본값(false) 사용${NC}"
else
    echo -e "${GREEN}✓ MOCK_MODE 환경변수 감지: ${MOCK_MODE}${NC}"
fi

mkdir -p logs

# nohup 실행 시 env를 사용하여 환경변수 명시적 전달
nohup env MOCK_MODE=$MOCK_MODE python app.py > logs/cae_backend.log 2>&1 &
echo $! > .cae_backend.pid
sleep 2

# 시작 확인
if ps -p $(cat .cae_backend.pid) > /dev/null 2>&1; then
    echo -e "${GREEN}✅ CAE Backend 시작 성공!${NC}"
    echo -e "   PID: $(cat .cae_backend.pid)"
    echo -e "   URL: http://localhost:${PORT}"
    echo -e "   Mode: ${MOCK_MODE}"
    echo ""
    echo -e "${BLUE}📝 로그 확인:${NC}"
    echo -e "   tail -f logs/cae_backend.log"
    echo ""
    # 시작 로그 출력
    sleep 1
    echo -e "${BLUE}=== CAE Backend 시작 로그 ===${NC}"
    tail -20 logs/cae_backend.log
else
    echo -e "${RED}❌ CAE Backend 시작 실패${NC}"
    echo -e "${RED}=== 에러 로그 ===${NC}"
    tail -20 logs/cae_backend.log
fi

deactivate
