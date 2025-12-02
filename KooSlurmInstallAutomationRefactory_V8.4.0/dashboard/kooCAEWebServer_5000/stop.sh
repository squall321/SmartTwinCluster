#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT=5000

echo -e "${YELLOW}CAE Backend 중지 중...${NC}"

# PID 파일로 종료
if [ -f ".cae_backend.pid" ]; then
    PID=$(cat .cae_backend.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID 2>/dev/null
        sleep 1
        if ps -p $PID > /dev/null 2>&1; then
            kill -9 $PID 2>/dev/null
        fi
        echo -e "${GREEN}✅ CAE Backend 중지 완료 (PID: $PID)${NC}"
    fi
    rm -f .cae_backend.pid
fi

# 포트로 종료
PID=$(lsof -ti:$PORT 2>/dev/null)
if [ ! -z "$PID" ]; then
    echo -e "${YELLOW}포트 ${PORT}에서 실행 중인 프로세스 종료 (PID: $PID)${NC}"
    kill -9 $PID 2>/dev/null
    echo -e "${GREEN}✅ 포트 ${PORT} 정리 완료${NC}"
fi
