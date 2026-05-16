#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT=4430
echo -e "${YELLOW}전 Step: 포트 ${PORT} 체크 및 정리...${NC}"
PID=$(lsof -ti:$PORT 2>/dev/null)
if [ ! -z "$PID" ]; then
    echo -e "${YELLOW}⚠️  포트 ${PORT} 사용 중 (PID: $PID) → 종료${NC}"
    kill -9 $PID 2>/dev/null; sleep 1
fi
[ -f ".auth_backend.pid" ] && kill $(cat .auth_backend.pid) 2>/dev/null && rm -f .auth_backend.pid

# 명시적 Python 버전 (시스템 기본 3.12)
export PYTHON_BIN=/usr/bin/python3.12

# venv 없거나 깨졌으면 ensure_venv가 재생성
source "$SCRIPT_DIR/../common/ensure_venv.sh" 2>/dev/null
[ -f "venv/bin/activate" ] && source venv/bin/activate
ensure_venv flask flask_cors jwt:PyJWT dotenv:python-dotenv redis
[ -f "venv/bin/activate" ] && source venv/bin/activate

mkdir -p logs
nohup "$SCRIPT_DIR/venv/bin/python3" app.py > logs/auth_backend.log 2>&1 &
echo $! > .auth_backend.pid
sleep 2

if ps -p $(cat .auth_backend.pid) > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Auth Backend 시작 성공!${NC}"
    echo -e "   PID: $(cat .auth_backend.pid)"
    echo -e "   URL: http://localhost:${PORT}"
    echo ""
    echo -e "${BLUE}=== Auth Backend 시작 로그 ===${NC}"
    tail -15 logs/auth_backend.log
else
    echo -e "${RED}❌ Auth Backend 시작 실패${NC}"
    echo -e "${RED}=== 에러 로그 ===${NC}"
    tail -20 logs/auth_backend.log
fi
