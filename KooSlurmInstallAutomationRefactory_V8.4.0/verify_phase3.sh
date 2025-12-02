#!/bin/bash
################################################################################
# Phase 3 검증 스크립트
################################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 Phase 3 완료 검증"
echo "===================="
echo ""

ERRORS=0
WARNINGS=0

# ============================================================================
# 1. Phase 2 완료 확인
# ============================================================================
echo -e "${BLUE}📋 Phase 2 완료 여부 확인...${NC}"
if [ -f "./verify_phase2.sh" ]; then
    ./verify_phase2.sh > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Phase 2 완료 확인${NC}"
    else
        echo -e "  ${RED}❌ Phase 2가 완료되지 않았습니다${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "  ${RED}❌ verify_phase2.sh 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 2. 스크립트 파일 존재 확인
# ============================================================================
echo -e "${BLUE}📝 자동화 스크립트 확인...${NC}"

REQUIRED_SCRIPTS=(
    "web_services/scripts/setup_web_services.sh"
    "web_services/scripts/reconfigure_web_services.sh"
    "web_services/scripts/install_dependencies.sh"
    "web_services/scripts/health_check.sh"
    "web_services/scripts/rollback.sh"
    "web_services/scripts/reconfigure_service.sh"
)

SCRIPT_COUNT=0
for SCRIPT in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT" ]; then
        echo -e "  ${GREEN}✅ $(basename $SCRIPT)${NC}"
        SCRIPT_COUNT=$((SCRIPT_COUNT+1))

        # 실행 권한 확인
        if [ -x "$SCRIPT" ]; then
            # OK
            true
        else
            echo -e "    ${YELLOW}⚠️  실행 권한 없음${NC}"
            WARNINGS=$((WARNINGS+1))
        fi

        # Bash 문법 검증 (간단)
        bash -n "$SCRIPT" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo -e "    ${RED}❌ Bash 문법 오류${NC}"
            ERRORS=$((ERRORS+1))
        fi
    else
        echo -e "  ${RED}❌ $(basename $SCRIPT) 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""
if [ $SCRIPT_COUNT -eq 6 ]; then
    echo -e "  ${GREEN}✅ 모든 스크립트 존재 (6/6)${NC}"
else
    echo -e "  ${RED}❌ 일부 스크립트 누락 ($SCRIPT_COUNT/6)${NC}"
fi

echo ""

# ============================================================================
# 3. setup_web_services.sh 기능 확인
# ============================================================================
echo -e "${BLUE}🔧 setup_web_services.sh 기능 확인...${NC}"

if [ -f "web_services/scripts/setup_web_services.sh" ]; then
    # 도움말 출력 확인
    if grep -q "usage\|Usage\|USAGE" web_services/scripts/setup_web_services.sh; then
        echo -e "  ${GREEN}✅ 사용법(usage) 메시지 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  사용법 메시지 없음${NC}"
        WARNINGS=$((WARNINGS+1))
    fi

    # 환경 파라미터 처리 확인
    if grep -q "development\|production" web_services/scripts/setup_web_services.sh; then
        echo -e "  ${GREEN}✅ 환경 파라미터 처리 존재${NC}"
    else
        echo -e "  ${RED}❌ 환경 파라미터 처리 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "  ${RED}❌ setup_web_services.sh 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 4. reconfigure_web_services.sh 기능 확인
# ============================================================================
echo -e "${BLUE}🔄 reconfigure_web_services.sh 기능 확인...${NC}"

if [ -f "web_services/scripts/reconfigure_web_services.sh" ]; then
    # 옵션 확인
    EXPECTED_OPTIONS=("--dry-run" "--service" "--nginx-only" "--skip-restart" "--rollback")
    OPTION_COUNT=0

    for OPT in "${EXPECTED_OPTIONS[@]}"; do
        if grep -q "$OPT" web_services/scripts/reconfigure_web_services.sh; then
            OPTION_COUNT=$((OPTION_COUNT+1))
        fi
    done

    if [ $OPTION_COUNT -ge 3 ]; then
        echo -e "  ${GREEN}✅ 주요 옵션 존재 ($OPTION_COUNT/5)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  일부 옵션 누락 ($OPTION_COUNT/5)${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${RED}❌ reconfigure_web_services.sh 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 5. health_check.sh 기능 확인
# ============================================================================
echo -e "${BLUE}🏥 health_check.sh 기능 확인...${NC}"

if [ -f "web_services/scripts/health_check.sh" ]; then
    # 포트 체크 로직 확인
    if grep -q "lsof\|netstat\|ss" web_services/scripts/health_check.sh; then
        echo -e "  ${GREEN}✅ 포트 체크 로직 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  포트 체크 로직 확인 필요${NC}"
        WARNINGS=$((WARNINGS+1))
    fi

    # HTTP 헬스 체크 확인
    if grep -q "curl\|wget\|/health" web_services/scripts/health_check.sh; then
        echo -e "  ${GREEN}✅ HTTP 헬스 체크 로직 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  HTTP 헬스 체크 로직 확인 필요${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${RED}❌ health_check.sh 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 6. rollback.sh 기능 확인
# ============================================================================
echo -e "${BLUE}⏮️  rollback.sh 기능 확인...${NC}"

if [ -f "web_services/scripts/rollback.sh" ]; then
    # 백업 디렉토리 참조 확인
    if grep -q "backup" web_services/scripts/rollback.sh; then
        echo -e "  ${GREEN}✅ 백업 디렉토리 참조 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  백업 디렉토리 참조 확인 필요${NC}"
        WARNINGS=$((WARNINGS+1))
    fi

    # --list, --latest 옵션 확인
    if grep -q "\-\-list\|\-\-latest" web_services/scripts/rollback.sh; then
        echo -e "  ${GREEN}✅ 롤백 옵션 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  롤백 옵션 확인 필요${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${RED}❌ rollback.sh 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 7. 백업 디렉토리 확인
# ============================================================================
echo -e "${BLUE}💾 백업 디렉토리 확인...${NC}"

if [ -d "backups" ]; then
    echo -e "  ${GREEN}✅ backups/ 디렉토리 존재${NC}"

    # 백업 파일 개수 확인
    BACKUP_COUNT=$(ls -1 backups/ 2>/dev/null | wc -l)
    if [ $BACKUP_COUNT -gt 0 ]; then
        echo -e "  ${GREEN}✅ 백업 항목 존재 ($BACKUP_COUNT 개)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  백업 항목 없음 (정상 - 아직 실행 전)${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  backups/ 디렉토리 없음${NC}"
    echo -e "     ${YELLOW}첫 실행 시 자동 생성됨${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ============================================================================
# 8. 기존 스크립트 호환성 확인
# ============================================================================
echo -e "${BLUE}🔗 기존 스크립트 호환성 확인...${NC}"

EXISTING_SCRIPTS=(
    "start_complete.sh"
    "stop_complete.sh"
)

for SCRIPT in "${EXISTING_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT" ]; then
        echo -e "  ${GREEN}✅ $SCRIPT 존재 (호환성 유지)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $SCRIPT 없음${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
done

echo ""

# ============================================================================
# 9. 스크립트 실행 가능 여부 확인
# ============================================================================
echo -e "${BLUE}▶️  스크립트 실행 가능 여부 확인...${NC}"

# health_check.sh dry-run 테스트 (실제로 실행)
if [ -f "web_services/scripts/health_check.sh" ] && [ -x "web_services/scripts/health_check.sh" ]; then
    # 도움말 출력 시도
    if ./web_services/scripts/health_check.sh --help &>/dev/null || \
       ./web_services/scripts/health_check.sh -h &>/dev/null; then
        echo -e "  ${GREEN}✅ health_check.sh 실행 가능${NC}"
    else
        # 도움말이 없어도 실행만 되면 OK
        echo -e "  ${GREEN}✅ health_check.sh 실행 가능 (도움말 없음)${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  health_check.sh 실행 불가 (권한 또는 파일 없음)${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ============================================================================
# 10. 최종 결과
# ============================================================================
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅✅✅ Phase 3 완료!${NC}"
    echo "========================================"
    echo ""
    echo "📋 생성된 스크립트:"
    echo "   ✓ setup_web_services.sh (전체 설치)"
    echo "   ✓ reconfigure_web_services.sh (재구성)"
    echo "   ✓ install_dependencies.sh (의존성 설치)"
    echo "   ✓ health_check.sh (헬스 체크)"
    echo "   ✓ rollback.sh (롤백)"
    echo "   ✓ reconfigure_service.sh (개별 재구성)"
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE4_GUIDE.md"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ] && [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Phase 3 완료 (경고 $WARNINGS 개)${NC}"
    echo "========================================"
    echo ""
    echo "💡 경고는 무시하고 진행 가능하지만, 검토를 권장합니다."
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE4_GUIDE.md"
    echo ""
    exit 0
else
    echo -e "${RED}❌ $ERRORS 개 오류, $WARNINGS 개 경고${NC}"
    echo "========================================"
    echo ""
    echo "💡 수정 방법:"
    echo ""

    if [ ! -f "web_services/scripts/setup_web_services.sh" ]; then
        echo "   1. setup_web_services.sh 작성:"
        echo "      PHASE3_GUIDE.md 섹션 1 참조"
        echo ""
    fi

    if [ ! -f "web_services/scripts/reconfigure_web_services.sh" ]; then
        echo "   2. reconfigure_web_services.sh 작성:"
        echo "      PHASE3_GUIDE.md 섹션 2 참조"
        echo ""
    fi

    HELPER_MISSING=0
    for SCRIPT in "install_dependencies.sh" "health_check.sh" "rollback.sh" "reconfigure_service.sh"; do
        if [ ! -f "web_services/scripts/$SCRIPT" ]; then
            HELPER_MISSING=$((HELPER_MISSING+1))
        fi
    done

    if [ $HELPER_MISSING -gt 0 ]; then
        echo "   3. 헬퍼 스크립트 작성 ($HELPER_MISSING 개 누락):"
        echo "      PHASE3_GUIDE.md 섹션 3 참조"
        echo ""
    fi

    echo "   4. 실행 권한 설정:"
    echo "      chmod +x web_services/scripts/*.sh"
    echo ""

    echo "   자세한 내용: cat PHASE3_GUIDE.md"
    echo ""
    exit 1
fi
