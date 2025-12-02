#!/bin/bash
################################################################################
# Phase 2 검증 스크립트
################################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 Phase 2 완료 검증"
echo "===================="
echo ""

ERRORS=0
WARNINGS=0

# ============================================================================
# 1. Phase 1 완료 확인
# ============================================================================
echo -e "${BLUE}📋 Phase 1 완료 여부 확인...${NC}"
if [ -f "./verify_phase1.sh" ]; then
    ./verify_phase1.sh > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Phase 1 완료 확인${NC}"
    else
        echo -e "  ${RED}❌ Phase 1이 완료되지 않았습니다${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "  ${RED}❌ verify_phase1.sh 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 2. Python 패키지 확인
# ============================================================================
echo -e "${BLUE}🐍 Python 패키지 확인...${NC}"

if command -v python3 &> /dev/null; then
    echo -e "  ${GREEN}✅ python3 설치됨${NC}"

    # PyYAML
    python3 -c "import yaml" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ PyYAML 설치됨${NC}"
    else
        echo -e "  ${RED}❌ PyYAML 미설치${NC}"
        echo -e "     ${YELLOW}pip3 install pyyaml${NC}"
        ERRORS=$((ERRORS+1))
    fi

    # Jinja2
    python3 -c "import jinja2" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Jinja2 설치됨${NC}"
    else
        echo -e "  ${RED}❌ Jinja2 미설치${NC}"
        echo -e "     ${YELLOW}pip3 install jinja2${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "  ${RED}❌ python3 미설치${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 3. generate_env_files.py 스크립트 확인
# ============================================================================
echo -e "${BLUE}📝 generate_env_files.py 스크립트 확인...${NC}"

SCRIPT_PATH="web_services/scripts/generate_env_files.py"

if [ -f "$SCRIPT_PATH" ]; then
    echo -e "  ${GREEN}✅ $SCRIPT_PATH 존재${NC}"

    # 실행 권한 확인
    if [ -x "$SCRIPT_PATH" ]; then
        echo -e "  ${GREEN}✅ 실행 권한 있음${NC}"
    else
        echo -e "  ${YELLOW}⚠️  실행 권한 없음 (chmod +x로 추가 가능)${NC}"
        WARNINGS=$((WARNINGS+1))
    fi

    # Python 문법 검증
    python3 -m py_compile "$SCRIPT_PATH" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Python 문법 검증 성공${NC}"
    else
        echo -e "  ${RED}❌ Python 문법 오류${NC}"
        ERRORS=$((ERRORS+1))
    fi

    # 필수 import 확인
    if grep -q "import yaml" "$SCRIPT_PATH" && \
       grep -q "from jinja2 import Template" "$SCRIPT_PATH"; then
        echo -e "  ${GREEN}✅ 필수 import 존재${NC}"
    else
        echo -e "  ${RED}❌ 필수 import 누락 (yaml, jinja2)${NC}"
        ERRORS=$((ERRORS+1))
    fi

    # 파일 크기 확인
    FILE_SIZE=$(stat -c%s "$SCRIPT_PATH" 2>/dev/null || stat -f%z "$SCRIPT_PATH" 2>/dev/null)
    if [ "$FILE_SIZE" -gt 1000 ]; then
        echo -e "  ${GREEN}✅ 파일 크기 적절 (${FILE_SIZE} bytes)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  파일 크기 작음 (${FILE_SIZE} bytes)${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${RED}❌ $SCRIPT_PATH 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 4. 코드 수정 확인 (하드코딩된 localhost 제거)
# ============================================================================
echo -e "${BLUE}🔧 코드 수정 확인...${NC}"

# 4-1. saml_handler.py
if [ -f "dashboard/auth_portal_4430/saml_handler.py" ]; then
    if grep -q "localhost:4431" dashboard/auth_portal_4430/saml_handler.py; then
        echo -e "  ${YELLOW}⚠️  saml_handler.py: localhost:4431 하드코딩 여전히 존재${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo -e "  ${GREEN}✅ saml_handler.py: localhost 하드코딩 제거됨${NC}"
    fi
fi

# 4-2. ServiceMenuPage.tsx
if [ -f "dashboard/auth_portal_4431/src/pages/ServiceMenuPage.tsx" ]; then
    # URL 처리 로직 존재 확인
    if grep -q "window.location.href" dashboard/auth_portal_4431/src/pages/ServiceMenuPage.tsx; then
        echo -e "  ${GREEN}✅ ServiceMenuPage.tsx: URL 처리 로직 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  ServiceMenuPage.tsx: URL 처리 확인 필요${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
fi

# 4-3. App.tsx (VNC Service)
if [ -f "dashboard/vnc_service_8002/src/App.tsx" ]; then
    if grep -q "localhost:4431" dashboard/vnc_service_8002/src/App.tsx; then
        echo -e "  ${YELLOW}⚠️  vnc_service/App.tsx: localhost:4431 하드코딩 여전히 존재${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo -e "  ${GREEN}✅ vnc_service/App.tsx: localhost 하드코딩 제거됨${NC}"
    fi
fi

echo ""

# ============================================================================
# 5. .env 파일 생성 테스트
# ============================================================================
echo -e "${BLUE}🧪 .env 파일 생성 테스트...${NC}"

if [ -f "$SCRIPT_PATH" ] && command -v python3 &> /dev/null; then
    # development 환경으로 .env 파일 생성 시도
    python3 "$SCRIPT_PATH" development > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ generate_env_files.py 실행 성공${NC}"

        # 생성된 .env 파일 확인
        ENV_FILES=(
            "dashboard/auth_portal_4430/.env"
            "dashboard/auth_portal_4431/.env"
            "dashboard/backend_5010/.env"
            "dashboard/frontend_3010/.env"
            "dashboard/kooCAEWebServer_5000/.env"
            "dashboard/kooCAEWebAutomationServer_5001/.env"
            "dashboard/kooCAEWeb_5173/.env"
            "dashboard/vnc_service_8002/.env"
        )

        ENV_COUNT=0
        for ENV_FILE in "${ENV_FILES[@]}"; do
            if [ -f "$ENV_FILE" ]; then
                ENV_COUNT=$((ENV_COUNT+1))
            fi
        done

        if [ $ENV_COUNT -eq 8 ]; then
            echo -e "  ${GREEN}✅ 모든 .env 파일 생성 완료 (8/8)${NC}"
        else
            echo -e "  ${YELLOW}⚠️  일부 .env 파일 누락 ($ENV_COUNT/8)${NC}"
            WARNINGS=$((WARNINGS+1))
        fi

        # .env 파일 내용 확인 (샘플)
        if [ -f "dashboard/auth_portal_4430/.env" ]; then
            if grep -q "FLASK_ENV=development" dashboard/auth_portal_4430/.env && \
               grep -q "JWT_SECRET_KEY=" dashboard/auth_portal_4430/.env; then
                echo -e "  ${GREEN}✅ .env 파일 내용 정상 (샘플 확인)${NC}"
            else
                echo -e "  ${YELLOW}⚠️  .env 파일 내용 확인 필요${NC}"
                WARNINGS=$((WARNINGS+1))
            fi
        fi
    else
        echo -e "  ${RED}❌ generate_env_files.py 실행 실패${NC}"
        echo -e "     ${YELLOW}python3 $SCRIPT_PATH development${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "  ${YELLOW}⚠️  스크립트 또는 python3 없음 - 테스트 스킵${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ============================================================================
# 6. .gitignore 확인 (.env 제외 여부)
# ============================================================================
echo -e "${BLUE}📄 .gitignore 확인...${NC}"

if [ -f ".gitignore" ]; then
    if grep -q "\.env" .gitignore; then
        echo -e "  ${GREEN}✅ .env 파일이 .gitignore에 포함됨${NC}"
    else
        echo -e "  ${YELLOW}⚠️  .env 파일을 .gitignore에 추가 권장${NC}"
        echo -e "     ${YELLOW}echo '.env' >> .gitignore${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${YELLOW}⚠️  .gitignore 파일 없음${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ============================================================================
# 7. 백업 확인 (사용자가 직접 수행)
# ============================================================================
echo -e "${BLUE}💾 백업 확인...${NC}"
echo -e "  ${YELLOW}ℹ️  백업은 사용자가 직접 수행 (Git commit 등)${NC}"
echo -e "  ${YELLOW}ℹ️  수정된 5개 파일을 백업했는지 확인하세요${NC}"
echo ""

# ============================================================================
# 8. 최종 결과
# ============================================================================
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅✅✅ Phase 2 완료!${NC}"
    echo "========================================"
    echo ""
    echo "📋 수정/생성된 파일:"
    echo "   ✓ web_services/scripts/generate_env_files.py"
    echo "   ✓ 5개 코드 파일 수정"
    echo "   ✓ 8개 .env 파일 생성"
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE3_GUIDE.md"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ] && [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Phase 2 완료 (경고 $WARNINGS 개)${NC}"
    echo "========================================"
    echo ""
    echo "💡 경고는 무시하고 진행 가능하지만, 검토를 권장합니다."
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE3_GUIDE.md"
    echo ""
    exit 0
else
    echo -e "${RED}❌ $ERRORS 개 오류, $WARNINGS 개 경고${NC}"
    echo "========================================"
    echo ""
    echo "💡 수정 방법:"
    echo ""

    if ! python3 -c "import yaml" 2>/dev/null; then
        echo "   1. PyYAML 설치:"
        echo "      pip3 install pyyaml"
        echo ""
    fi

    if ! python3 -c "import jinja2" 2>/dev/null; then
        echo "   2. Jinja2 설치:"
        echo "      pip3 install jinja2"
        echo ""
    fi

    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "   3. generate_env_files.py 작성:"
        echo "      PHASE2_GUIDE.md의 섹션 참조"
        echo ""
    fi

    echo "   자세한 내용: cat PHASE2_GUIDE.md"
    echo ""
    exit 1
fi
