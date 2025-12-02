#!/bin/bash
# Phase 1: Auth Portal 시작 스크립트
# Auth Backend, Auth Frontend, SAML-IdP를 순차적으로 시작합니다.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DASHBOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DASHBOARD_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Phase 1: Auth Portal 시작${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Redis 확인
echo "Redis 상태 확인 중..."
if ! redis-cli ping &>/dev/null; then
    echo -e "${RED}✗${NC} Redis가 실행되지 않습니다."
    echo "Redis를 먼저 시작해주세요: sudo systemctl start redis-server"
    exit 1
fi
echo -e "${GREEN}✓${NC} Redis 실행 중"
echo

# 1. SAML-IdP 시작
echo -e "${BLUE}[1/3] SAML-IdP 시작 중...${NC}"
if pgrep -f "saml-idp.*7000" > /dev/null; then
    echo -e "${YELLOW}⚠${NC} SAML-IdP가 이미 실행 중입니다."
else
    cd saml_idp_7000
    ./start_idp.sh
    cd ..
fi
echo

sleep 2

# 2. Auth Backend 시작
echo -e "${BLUE}[2/3] Auth Backend 시작 중...${NC}"
if pgrep -f "python.*auth_portal_4430.*app.py" > /dev/null; then
    echo -e "${YELLOW}⚠${NC} Auth Backend가 이미 실행 중입니다."
else
    cd auth_portal_4430
    source venv/bin/activate
    nohup python3 app.py > logs/backend.log 2>&1 &
    BACKEND_PID=$!
    echo $BACKEND_PID > logs/backend.pid
    cd ..

    sleep 3

    if curl -s http://localhost:4430/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Auth Backend 시작됨 (PID: $BACKEND_PID, Port: 4430)"
    else
        echo -e "${RED}✗${NC} Auth Backend 시작 실패"
        exit 1
    fi
fi
echo

# 3. Auth Frontend 시작
echo -e "${BLUE}[3/3] Auth Frontend 시작 중...${NC}"
if pgrep -f "vite.*auth_portal_4431" > /dev/null; then
    echo -e "${YELLOW}⚠${NC} Auth Frontend가 이미 실행 중입니다."
else
    cd auth_portal_4431
    nohup npm run dev > ../auth_portal_4430/logs/frontend.log 2>&1 &
    FRONTEND_PID=$!
    echo $FRONTEND_PID > ../auth_portal_4430/logs/frontend.pid
    cd ..

    sleep 5

    if curl -s http://localhost:4431 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Auth Frontend 시작됨 (PID: $FRONTEND_PID, Port: 4431)"
    else
        echo -e "${RED}✗${NC} Auth Frontend 시작 실패"
        exit 1
    fi
fi
echo

# 최종 상태 확인
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Phase 1 서비스 시작 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "실행 중인 서비스:"
echo -e "  ${GREEN}●${NC} SAML-IdP:      http://localhost:7000"
echo -e "  ${GREEN}●${NC} Auth Backend:  http://localhost:4430"
echo -e "  ${GREEN}●${NC} Auth Frontend: http://localhost:4431"
echo
echo "로그 파일:"
echo "  - IdP:      $DASHBOARD_DIR/saml_idp_7000/logs/idp.log"
echo "  - Backend:  $DASHBOARD_DIR/auth_portal_4430/logs/backend.log"
echo "  - Frontend: $DASHBOARD_DIR/auth_portal_4430/logs/frontend.log"
echo
echo "종료: ./stop_phase1.sh"
