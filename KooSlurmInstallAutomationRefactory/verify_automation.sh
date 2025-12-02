#!/bin/bash
################################################################################
# 자동화 개선 사항 검증 스크립트
################################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔍 웹 서비스 자동화 개선 검증${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# 테스트 함수
test_check() {
    local name="$1"
    local condition="$2"

    if eval "$condition"; then
        echo -e "${GREEN}✅ $name${NC}"
        ((PASS_COUNT++))
        return 0
    else
        echo -e "${RED}❌ $name${NC}"
        ((FAIL_COUNT++))
        return 1
    fi
}

echo "📋 1. 프로젝트 루트 실행 지원"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_check "start.sh 존재" "[ -f './start.sh' ]"
test_check "start.sh 실행 권한" "[ -x './start.sh' ]"
test_check "stop.sh 존재" "[ -f './stop.sh' ]"
test_check "stop.sh 실행 권한" "[ -x './stop.sh' ]"
test_check "setup_web_services.sh 존재" "[ -f './setup_web_services.sh' ]"
test_check "setup_web_services.sh 실행 권한" "[ -x './setup_web_services.sh' ]"
test_check "generate_env_files.sh 존재" "[ -f './generate_env_files.sh' ]"
test_check "generate_env_files.sh 실행 권한" "[ -x './generate_env_files.sh' ]"
test_check "health_check.sh 존재" "[ -f './health_check.sh' ]"
test_check "health_check.sh 실행 권한" "[ -x './health_check.sh' ]"
echo ""

echo "📋 2. setup_web_services.sh 개선 사항"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_check "setup_web_services.sh 존재" "[ -f 'web_services/scripts/setup_web_services.sh' ]"
test_check "--auto-start 옵션 존재" "grep -q 'AUTO_START' web_services/scripts/setup_web_services.sh"
test_check "Python venv 자동 생성 코드" "grep -q 'python3 -m venv venv' web_services/scripts/setup_web_services.sh"
test_check "npm install 자동 실행 코드" "grep -q 'npm install --silent' web_services/scripts/setup_web_services.sh"
test_check "websocket_5011 포함" "grep -q 'websocket_5011' web_services/scripts/setup_web_services.sh"
echo ""

echo "📋 3. install_dependencies.sh 개선 사항"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_check "install_dependencies.sh 존재" "[ -f 'web_services/scripts/install_dependencies.sh' ]"
test_check "Redis 대화형 프롬프트 제거" "! grep -q 'read -p.*Redis' web_services/scripts/install_dependencies.sh"
test_check "Redis 자동 설치 코드" "grep -q 'apt install -y redis-server' web_services/scripts/install_dependencies.sh"
echo ""

echo "📋 4. 문서 업데이트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_check "README.md 업데이트" "grep -q './start.sh' README.md"
test_check "README.md --auto-start 추가" "grep -q 'auto-start' README.md"
test_check "QUICKSTART_WEB.md 존재" "[ -f 'QUICKSTART_WEB.md' ]"
test_check "QUICKSTART_WEB.md --auto-start 추가" "grep -q 'auto-start' QUICKSTART_WEB.md"
test_check "AUTOMATION_SUMMARY.md 존재" "[ -f 'AUTOMATION_SUMMARY.md' ]"
echo ""

echo "📋 5. Python 서비스 venv 상태"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
PYTHON_SERVICES=(
    "dashboard/auth_portal_4430"
    "dashboard/backend_5010"
    "dashboard/websocket_5011"
    "dashboard/kooCAEWebServer_5000"
    "dashboard/kooCAEWebAutomationServer_5001"
)

for SERVICE_DIR in "${PYTHON_SERVICES[@]}"; do
    if [ -d "$SERVICE_DIR" ]; then
        SERVICE_NAME=$(basename "$SERVICE_DIR")
        if [ -d "$SERVICE_DIR/venv" ]; then
            echo -e "${GREEN}✅ $SERVICE_NAME venv 존재${NC}"
            ((PASS_COUNT++))
        else
            echo -e "${YELLOW}⚠️  $SERVICE_NAME venv 없음 (setup_web_services.sh 실행 시 자동 생성)${NC}"
        fi
    fi
done
echo ""

echo "📋 6. Node.js 서비스 node_modules 상태"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
NODE_SERVICES=(
    "dashboard/auth_portal_4431"
    "dashboard/frontend_3010"
    "dashboard/kooCAEWeb_5173"
    "dashboard/vnc_service_8002"
)

for SERVICE_DIR in "${NODE_SERVICES[@]}"; do
    if [ -d "$SERVICE_DIR" ]; then
        SERVICE_NAME=$(basename "$SERVICE_DIR")
        if [ -d "$SERVICE_DIR/node_modules" ]; then
            echo -e "${GREEN}✅ $SERVICE_NAME node_modules 존재${NC}"
            ((PASS_COUNT++))
        else
            echo -e "${YELLOW}⚠️  $SERVICE_NAME node_modules 없음 (setup_web_services.sh 실행 시 자동 설치)${NC}"
        fi
    fi
done
echo ""

echo "📋 7. 자동화 레벨 테스트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# setup_web_services.sh --help 실행
if web_services/scripts/setup_web_services.sh --help 2>&1 | grep -q "auto-start"; then
    echo -e "${GREEN}✅ setup_web_services.sh --help에 --auto-start 옵션 표시${NC}"
    ((PASS_COUNT++))
else
    echo -e "${RED}❌ --auto-start 옵션이 --help에 없음${NC}"
    ((FAIL_COUNT++))
fi

echo ""

# 최종 결과
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
PASS_RATE=$((PASS_COUNT * 100 / TOTAL))

echo -e "${BLUE}📊 검증 결과${NC}"
echo "  통과: ${PASS_COUNT}/${TOTAL}"
echo "  실패: ${FAIL_COUNT}/${TOTAL}"
echo "  성공률: ${PASS_RATE}%"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ 모든 자동화 개선 사항이 정상적으로 적용되었습니다!${NC}"
    echo ""
    echo "📋 다음 단계:"
    echo "  1. 환경 변수 생성:"
    echo "     ./generate_env_files.sh development"
    echo ""
    echo "  2. 웹 서비스 설치 + 자동 시작:"
    echo "     ./setup_web_services.sh development --auto-start"
    echo ""
    echo "  3. 헬스 체크:"
    echo "     ./health_check.sh"
    exit 0
else
    echo -e "${YELLOW}⚠️  일부 항목이 실패했습니다.${NC}"
    echo "  자세한 내용은 위의 실패 항목을 확인하세요."
    exit 1
fi
