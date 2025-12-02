#!/bin/bash
# Phase 1: Auth Portal 종료 스크립트
# Auth Frontend, Auth Backend, SAML-IdP를 순차적으로 종료합니다.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DASHBOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DASHBOARD_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Phase 1: Auth Portal 종료${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# 1. Auth Frontend 종료
echo -e "${BLUE}[1/3] Auth Frontend 종료 중...${NC}"

# PID 파일로 종료
if [ -f "auth_portal_4430/logs/frontend.pid" ]; then
    FRONTEND_PID=$(cat auth_portal_4430/logs/frontend.pid)
    if ps -p $FRONTEND_PID > /dev/null 2>&1; then
        kill -9 $FRONTEND_PID 2>/dev/null
        echo -e "${GREEN}✓${NC} Auth Frontend 종료됨 (PID: $FRONTEND_PID)"
    fi
    rm -f auth_portal_4430/logs/frontend.pid
fi

# 프로세스 검색으로 종료
FRONTEND_PIDS=$(ps aux | grep "auth_portal_4431" | grep -v grep | awk '{print $2}')
if [ -n "$FRONTEND_PIDS" ]; then
    echo "$FRONTEND_PIDS" | xargs -r kill -9 2>/dev/null
    echo -e "${GREEN}✓${NC} Auth Frontend 프로세스 종료됨"
fi

sleep 1
echo

# 2. Auth Backend 종료
echo -e "${BLUE}[2/3] Auth Backend 종료 중...${NC}"

# PID 파일로 종료
if [ -f "auth_portal_4430/logs/backend.pid" ]; then
    BACKEND_PID=$(cat auth_portal_4430/logs/backend.pid)
    if ps -p $BACKEND_PID > /dev/null 2>&1; then
        kill -9 $BACKEND_PID 2>/dev/null
        echo -e "${GREEN}✓${NC} Auth Backend 종료됨 (PID: $BACKEND_PID)"
    fi
    rm -f auth_portal_4430/logs/backend.pid
fi

# 프로세스 검색으로 종료
BACKEND_PIDS=$(ps aux | grep "python.*auth_portal_4430" | grep -v grep | awk '{print $2}')
if [ -n "$BACKEND_PIDS" ]; then
    echo "$BACKEND_PIDS" | xargs -r kill -9 2>/dev/null
    echo -e "${GREEN}✓${NC} Auth Backend 프로세스 종료됨"
fi

sleep 1
echo

# 3. SAML-IdP 종료
echo -e "${BLUE}[3/3] SAML-IdP 종료 중...${NC}"
cd saml_idp_7000
./stop_idp.sh 2>/dev/null || echo -e "${YELLOW}⚠${NC} SAML-IdP가 실행 중이지 않습니다."
cd ..
echo

# 최종 상태 확인
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Phase 1 서비스 종료 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# 남은 프로세스 확인
REMAINING=$(ps aux | grep -E "(auth_portal|saml-idp.*7000)" | grep -v grep | wc -l)
if [ $REMAINING -gt 0 ]; then
    echo -e "${YELLOW}⚠ 경고: 일부 프로세스가 아직 실행 중일 수 있습니다.${NC}"
    echo
    ps aux | grep -E "(auth_portal|saml-idp.*7000)" | grep -v grep | awk '{print "  PID " $2 ": " $11 " " $12}'
else
    echo -e "${GREEN}✓ 모든 Phase 1 프로세스가 종료되었습니다.${NC}"
fi

echo
echo "재시작: ./start_phase1.sh"
