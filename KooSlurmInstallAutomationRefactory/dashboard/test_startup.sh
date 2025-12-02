#!/bin/bash
################################################################################
# 시작 후 시스템 상태 확인 스크립트
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🔍 시스템 상태 확인"
echo "=========================================="
echo ""

PASS=0
FAIL=0

# ==================== 1. 포트 확인 ====================
echo -e "${BLUE}[1/5] 서비스 포트 확인${NC}"
PORTS=(4430 4431 5000 5001 5010 5011)
PORT_NAMES=("Auth Backend" "Auth Frontend" "CAE Backend" "CAE Automation" "Dashboard API" "WebSocket")

for i in "${!PORTS[@]}"; do
    port=${PORTS[$i]}
    name=${PORT_NAMES[$i]}
    if lsof -ti:$port >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $name (Port $port)${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌ $name (Port $port)${NC}"
        FAIL=$((FAIL + 1))
    fi
done
echo ""

# ==================== 2. Redis 확인 ====================
echo -e "${BLUE}[2/5] Redis 확인${NC}"
if redis-cli ping >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ Redis 실행 중${NC}"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}❌ Redis 미실행${NC}"
    FAIL=$((FAIL + 1))
fi
echo ""

# ==================== 3. 프론트엔드 빌드 확인 ====================
echo -e "${BLUE}[3/5] 프론트엔드 빌드 확인${NC}"
FRONTEND_DIRS=("frontend_3010" "vnc_service_8002" "kooCAEWeb_5173")
FRONTEND_NAMES=("Dashboard" "VNC Service" "CAE Frontend")

for i in "${!FRONTEND_DIRS[@]}"; do
    dir=${FRONTEND_DIRS[$i]}
    name=${FRONTEND_NAMES[$i]}
    if [ -f "$dir/dist/index.html" ]; then
        echo -e "  ${GREEN}✅ $name 빌드 파일 존재${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌ $name 빌드 파일 없음${NC}"
        FAIL=$((FAIL + 1))
    fi
done
echo ""

# ==================== 4. Backend 설정 확인 ====================
echo -e "${BLUE}[4/5] Backend 설정 확인${NC}"
if [ -f "backend_5010/.env" ]; then
    if grep -q "^MOCK_MODE=false" backend_5010/.env; then
        echo -e "  ${GREEN}✅ MOCK_MODE=false 설정됨${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌ MOCK_MODE 설정 오류${NC}"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "  ${RED}❌ backend_5010/.env 파일 없음${NC}"
    FAIL=$((FAIL + 1))
fi
echo ""

# ==================== 5. 웹 접근성 확인 ====================
echo -e "${BLUE}[5/5] 웹 서비스 접근성 확인${NC}"

# Dashboard API 확인
if curl -s http://localhost:5010/api/health >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ Dashboard API 응답${NC}"
    PASS=$((PASS + 1))
else
    echo -e "  ${YELLOW}⚠  Dashboard API 미응답 (health endpoint 없을 수 있음)${NC}"
fi

# Nginx를 통한 접근 확인
if curl -s http://110.15.177.120/ >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ Nginx 메인 포털 접근 가능${NC}"
    PASS=$((PASS + 1))
else
    echo -e "  ${YELLOW}⚠  Nginx 메인 포털 접근 불가${NC}"
fi

echo ""

# ==================== 결과 ====================
echo "=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ 모든 검사 통과! ($PASS/$TOTAL)${NC}"
    echo "=========================================="
    echo ""
    echo "🔗 서비스 URL:"
    echo "  • 메인 포털:    http://110.15.177.120/"
    echo "  • Dashboard:    http://110.15.177.120/dashboard/"
    echo "  • VNC Service:  http://110.15.177.120/vnc/"
    echo "  • CAE Frontend: http://110.15.177.120/cae/"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠  일부 검사 실패 (통과: $PASS, 실패: $FAIL)${NC}"
    echo "=========================================="
    echo ""
    exit 1
fi
