#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 포트 번호
PORT=5001

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
[ -f ".cae_automation.pid" ] && kill $(cat .cae_automation.pid) 2>/dev/null && rm -f .cae_automation.pid

# venv 없거나 깨졌으면 ensure_venv가 재생성
source "$SCRIPT_DIR/../common/ensure_venv.sh" 2>/dev/null
[ -f "venv/bin/activate" ] && source venv/bin/activate
ensure_venv flask flask_cors dotenv:python-dotenv jwt:PyJWT yaml:PyYAML
[ -f "venv/bin/activate" ] && source venv/bin/activate

export FLASK_APP=app.py FLASK_ENV=production

# MOCK_MODE 환경변수 설정
if [ -z "$MOCK_MODE" ]; then
    export MOCK_MODE=false
    echo -e "${YELLOW}⚠️  MOCK_MODE 환경변수 없음. 기본값(false) 사용${NC}"
else
    echo -e "${GREEN}✓ MOCK_MODE 환경변수 감지: ${MOCK_MODE}${NC}"
fi

mkdir -p logs

# nohup 실행 시 env를 사용하여 환경변수 명시적 전달
nohup env MOCK_MODE=$MOCK_MODE python3 app.py > logs/automation.log 2>&1 &
echo $! > .cae_automation.pid
sleep 2

# 시작 확인
if ps -p $(cat .cae_automation.pid) > /dev/null 2>&1; then
    echo -e "${GREEN}✅ CAE Automation 시작 성공!${NC}"
    echo -e "   PID: $(cat .cae_automation.pid)"
    echo -e "   URL: http://localhost:${PORT}"
    echo -e "   Mode: ${MOCK_MODE}"
    echo ""
    echo -e "${BLUE}📝 로그 확인:${NC}"
    echo -e "   tail -f logs/automation.log"
    echo ""
    # 시작 로그 출력
    sleep 1
    echo -e "${BLUE}=== CAE Automation 시작 로그 ===${NC}"
    tail -20 logs/automation.log
else
    echo -e "${RED}❌ CAE Automation 시작 실패${NC}"
    echo -e "${RED}=== 에러 로그 ===${NC}"
    tail -20 logs/automation.log
fi

deactivate
