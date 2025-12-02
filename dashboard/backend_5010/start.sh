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
