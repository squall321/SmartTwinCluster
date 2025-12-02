#!/bin/bash
################################################################################
# Phase 0 검증 스크립트
################################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 Phase 0 완료 검증"
echo "===================="
echo ""

ERRORS=0

# 1. 디렉토리 구조 확인
echo "📁 디렉토리 구조 확인..."
REQUIRED_DIRS=(
    "web_services/scripts"
    "web_services/templates/env"
    "web_services/templates/nginx"
    "web_services/templates/systemd"
    "web_services/config"
    "web_services/docs"
    "backups"
)

for DIR in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        echo -e "  ${GREEN}✅ $DIR${NC}"
    else
        echo -e "  ${RED}❌ $DIR 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""

# 2. 문서 확인
echo "📄 문서 파일 확인..."
REQUIRED_DOCS=(
    "MIGRATION_PLAN.md"
    "CURRENT_STATE.md"
    "PHASE0_GUIDE.md"
    "web_services/docs/port_mapping.yaml"
)

for DOC in "${REQUIRED_DOCS[@]}"; do
    if [ -f "$DOC" ]; then
        echo -e "  ${GREEN}✅ $DOC${NC}"
    else
        echo -e "  ${RED}❌ $DOC 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""

# 3. 스크립트 확인
echo "📜 스크립트 파일 확인..."
REQUIRED_SCRIPTS=(
    "collect_current_state.sh"
    "create_directory_structure.sh"
    "verify_phase0.sh"
)

for SCRIPT in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; then
        echo -e "  ${GREEN}✅ $SCRIPT (실행 가능)${NC}"
    elif [ -f "$SCRIPT" ]; then
        echo -e "  ${YELLOW}⚠️  $SCRIPT (실행 권한 없음)${NC}"
        chmod +x "$SCRIPT"
        echo -e "     실행 권한 부여 완료${NC}"
    else
        echo -e "  ${RED}❌ $SCRIPT 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""

# 4. README 확인
echo "📖 README 파일 확인..."
if [ -f "web_services/README.md" ] && \
   [ -f "web_services/scripts/README.md" ] && \
   [ -f "web_services/templates/README.md" ]; then
    echo -e "  ${GREEN}✅ 모든 README 파일 생성 완료${NC}"
else
    echo -e "  ${YELLOW}⚠️  일부 README 누락${NC}"
fi

echo ""

# 5. 최종 결과
echo "========================================"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅✅✅ Phase 0 완료!${NC}"
    echo "========================================"
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE1_GUIDE.md"
    echo ""
    exit 0
else
    echo -e "${RED}❌ $ERRORS 개 항목 미완료${NC}"
    echo "========================================"
    echo ""
    echo "💡 수정 방법:"
    echo "   1. 누락된 디렉토리: bash create_directory_structure.sh"
    echo "   2. 누락된 문서: PHASE0_GUIDE.md 참조"
    echo ""
    exit 1
fi
