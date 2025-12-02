#!/bin/bash
################################################################################
# Phase 1 검증 스크립트
################################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 Phase 1 완료 검증"
echo "===================="
echo ""

ERRORS=0
WARNINGS=0

# ============================================================================
# 1. Phase 0 완료 확인
# ============================================================================
echo -e "${BLUE}📋 Phase 0 완료 여부 확인...${NC}"
if [ -f "./verify_phase0.sh" ]; then
    ./verify_phase0.sh > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Phase 0 완료 확인${NC}"
    else
        echo -e "  ${RED}❌ Phase 0가 완료되지 않았습니다${NC}"
        echo -e "  ${YELLOW}   먼저 ./verify_phase0.sh를 실행하여 Phase 0를 완료하세요${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "  ${RED}❌ verify_phase0.sh 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 2. 마스터 구성 파일 확인
# ============================================================================
echo -e "${BLUE}📄 마스터 구성 파일 확인...${NC}"

# 2-1. web_services_config.yaml 존재 확인
if [ -f "web_services_config.yaml" ]; then
    echo -e "  ${GREEN}✅ web_services_config.yaml 존재${NC}"

    # YAML 문법 검증
    if command -v python3 &> /dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('web_services_config.yaml'))" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✅ YAML 문법 검증 성공${NC}"
        else
            echo -e "  ${RED}❌ YAML 문법 오류${NC}"
            echo -e "  ${YELLOW}   python3 -c \"import yaml; yaml.safe_load(open('web_services_config.yaml'))\" 실행하여 오류 확인${NC}"
            ERRORS=$((ERRORS+1))
        fi
    else
        echo -e "  ${YELLOW}⚠️  python3 없음 - YAML 검증 스킵${NC}"
        WARNINGS=$((WARNINGS+1))
    fi

    # 필수 섹션 존재 확인
    if grep -q "^environments:" web_services_config.yaml && \
       grep -q "^services:" web_services_config.yaml && \
       grep -q "^nginx:" web_services_config.yaml; then
        echo -e "  ${GREEN}✅ 필수 섹션 존재 (environments, services, nginx)${NC}"
    else
        echo -e "  ${RED}❌ 필수 섹션 누락${NC}"
        ERRORS=$((ERRORS+1))
    fi

    # 파일 크기 확인 (너무 작으면 내용이 없을 가능성)
    FILE_SIZE=$(stat -c%s "web_services_config.yaml" 2>/dev/null || stat -f%z "web_services_config.yaml" 2>/dev/null)
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo -e "  ${GREEN}✅ 파일 크기 적절 (${FILE_SIZE} bytes)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  파일 크기 작음 (${FILE_SIZE} bytes) - 내용 확인 필요${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${RED}❌ web_services_config.yaml 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 3. 포트 매핑 문서 확인
# ============================================================================
echo -e "${BLUE}🔌 포트 매핑 문서 확인...${NC}"

if [ -f "web_services/docs/port_mapping.yaml" ]; then
    echo -e "  ${GREEN}✅ port_mapping.yaml 존재${NC}"

    # YAML 문법 검증
    if command -v python3 &> /dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('web_services/docs/port_mapping.yaml'))" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✅ YAML 문법 검증 성공${NC}"
        else
            echo -e "  ${RED}❌ YAML 문법 오류${NC}"
            ERRORS=$((ERRORS+1))
        fi
    fi

    # 11개 주요 포트 정의 확인
    REQUIRED_PORTS=(3010 4430 4431 5000 5001 5010 5011 5173 8002 9090 9100)
    MISSING_PORTS=()

    for PORT in "${REQUIRED_PORTS[@]}"; do
        if grep -q "port: $PORT" web_services/docs/port_mapping.yaml; then
            true  # 포트 존재
        else
            MISSING_PORTS+=($PORT)
        fi
    done

    if [ ${#MISSING_PORTS[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✅ 모든 주요 포트 정의됨 (11개)${NC}"
    else
        echo -e "  ${RED}❌ 누락된 포트: ${MISSING_PORTS[*]}${NC}"
        ERRORS=$((ERRORS+1))
    fi

    # Nginx 라우팅 정의 확인
    if grep -q "nginx_routes:" web_services/docs/port_mapping.yaml; then
        echo -e "  ${GREEN}✅ Nginx 라우팅 정의 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Nginx 라우팅 정의 없음${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${RED}❌ web_services/docs/port_mapping.yaml 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 4. 환경 변수 템플릿 확인
# ============================================================================
echo -e "${BLUE}📝 환경 변수 템플릿 확인...${NC}"

REQUIRED_TEMPLATES=(
    "web_services/templates/env/auth_portal_4430.env.j2"
    "web_services/templates/env/auth_portal_4431.env.j2"
    "web_services/templates/env/backend_5010.env.j2"
    "web_services/templates/env/frontend_3010.env.j2"
    "web_services/templates/env/cae_backend_5000.env.j2"
    "web_services/templates/env/cae_automation_5001.env.j2"
    "web_services/templates/env/cae_frontend_5173.env.j2"
    "web_services/templates/env/vnc_service_8002.env.j2"
)

TEMPLATE_COUNT=0
for TEMPLATE in "${REQUIRED_TEMPLATES[@]}"; do
    if [ -f "$TEMPLATE" ]; then
        echo -e "  ${GREEN}✅ $(basename $TEMPLATE)${NC}"
        TEMPLATE_COUNT=$((TEMPLATE_COUNT+1))

        # Jinja2 변수 사용 확인 ({{ variable }} 형식)
        if grep -q "{{.*}}" "$TEMPLATE"; then
            # Jinja2 변수 사용 중
            true
        else
            echo -e "    ${YELLOW}⚠️  Jinja2 변수 사용 안 함 - 정적 값만 있을 수 있음${NC}"
            WARNINGS=$((WARNINGS+1))
        fi
    else
        echo -e "  ${RED}❌ $(basename $TEMPLATE) 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""
if [ $TEMPLATE_COUNT -eq 8 ]; then
    echo -e "  ${GREEN}✅ 모든 템플릿 생성 완료 (8/8)${NC}"
else
    echo -e "  ${RED}❌ 일부 템플릿 누락 ($TEMPLATE_COUNT/8)${NC}"
fi

echo ""

# ============================================================================
# 5. 문서 업데이트 확인
# ============================================================================
echo -e "${BLUE}📚 문서 업데이트 확인...${NC}"

if [ -f "web_services/docs/README.md" ]; then
    echo -e "  ${GREEN}✅ web_services/docs/README.md 존재${NC}"

    # Phase 1 관련 내용 포함 여부 (선택사항)
    if grep -qi "phase 1\|Phase 1\|PHASE 1" web_services/docs/README.md; then
        echo -e "  ${GREEN}✅ Phase 1 내용 포함${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Phase 1 내용 미포함 (선택사항)${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${YELLOW}⚠️  web_services/docs/README.md 없음${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ============================================================================
# 6. Jinja2 변수 일관성 확인
# ============================================================================
echo -e "${BLUE}🔍 Jinja2 변수 일관성 확인...${NC}"

# 모든 템플릿에서 사용된 Jinja2 변수 추출 (간단한 체크)
if command -v grep &> /dev/null; then
    JINJA_VARS=$(grep -rh "{{.*}}" web_services/templates/env/ 2>/dev/null | \
                 sed 's/.*{{\s*\([^}]*\)\s*}}.*/\1/g' | \
                 sort -u | wc -l)

    if [ "$JINJA_VARS" -gt 0 ]; then
        echo -e "  ${GREEN}✅ Jinja2 변수 사용 중 (약 $JINJA_VARS 개 고유 변수)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Jinja2 변수 사용 안 함${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${YELLOW}⚠️  grep 명령 없음 - 검증 스킵${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ============================================================================
# 7. 파일 권한 확인
# ============================================================================
echo -e "${BLUE}🔒 파일 권한 확인...${NC}"

# YAML 파일들은 읽기 가능해야 함
YAML_FILES=(
    "web_services_config.yaml"
    "web_services/docs/port_mapping.yaml"
)

for YAML_FILE in "${YAML_FILES[@]}"; do
    if [ -f "$YAML_FILE" ] && [ -r "$YAML_FILE" ]; then
        echo -e "  ${GREEN}✅ $YAML_FILE 읽기 가능${NC}"
    elif [ -f "$YAML_FILE" ]; then
        echo -e "  ${RED}❌ $YAML_FILE 읽기 불가${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""

# ============================================================================
# 8. Python 패키지 확인 (Jinja2 필요)
# ============================================================================
echo -e "${BLUE}🐍 Python 패키지 확인...${NC}"

if command -v python3 &> /dev/null; then
    echo -e "  ${GREEN}✅ python3 설치됨${NC}"

    # PyYAML 확인
    python3 -c "import yaml" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ PyYAML 설치됨${NC}"
    else
        echo -e "  ${YELLOW}⚠️  PyYAML 미설치 - Phase 2에서 필요${NC}"
        echo -e "     pip3 install pyyaml"
        WARNINGS=$((WARNINGS+1))
    fi

    # Jinja2 확인
    python3 -c "import jinja2" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Jinja2 설치됨${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Jinja2 미설치 - Phase 2에서 필요${NC}"
        echo -e "     pip3 install jinja2"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${RED}❌ python3 미설치${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 9. 디렉토리 구조 재확인
# ============================================================================
echo -e "${BLUE}📁 디렉토리 구조 재확인...${NC}"

PHASE1_DIRS=(
    "web_services/templates/env"
    "web_services/docs"
)

for DIR in "${PHASE1_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        FILE_COUNT=$(ls -1 "$DIR" 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✅ $DIR ($FILE_COUNT 파일)${NC}"
    else
        echo -e "  ${RED}❌ $DIR 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""

# ============================================================================
# 10. 최종 결과
# ============================================================================
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅✅✅ Phase 1 완료!${NC}"
    echo "========================================"
    echo ""
    echo "📋 생성된 파일 목록:"
    echo "   ✓ web_services_config.yaml"
    echo "   ✓ web_services/docs/port_mapping.yaml"
    echo "   ✓ 8개 환경 변수 템플릿 (.env.j2)"
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE2_GUIDE.md"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ] && [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Phase 1 완료 (경고 $WARNINGS 개)${NC}"
    echo "========================================"
    echo ""
    echo "💡 경고는 무시하고 진행 가능하지만, 검토를 권장합니다."
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE2_GUIDE.md"
    echo ""
    exit 0
else
    echo -e "${RED}❌ $ERRORS 개 오류, $WARNINGS 개 경고${NC}"
    echo "========================================"
    echo ""
    echo "💡 수정 방법:"
    echo ""
    if ! grep -q "environments:" web_services_config.yaml 2>/dev/null; then
        echo "   1. web_services_config.yaml 생성:"
        echo "      PHASE1_GUIDE.md 참조"
        echo ""
    fi

    if [ ! -f "web_services/docs/port_mapping.yaml" ]; then
        echo "   2. port_mapping.yaml 생성:"
        echo "      PHASE1_GUIDE.md 참조"
        echo ""
    fi

    TEMPLATE_MISSING=$(ls web_services/templates/env/*.env.j2 2>/dev/null | wc -l)
    if [ "$TEMPLATE_MISSING" -lt 8 ]; then
        echo "   3. 환경 변수 템플릿 생성:"
        echo "      PHASE1_GUIDE.md의 3단계 참조"
        echo "      현재 $(ls web_services/templates/env/*.env.j2 2>/dev/null | wc -l)/8 개 생성됨"
        echo ""
    fi

    if ! command -v python3 &> /dev/null; then
        echo "   4. Python3 설치:"
        echo "      sudo apt install python3 python3-pip"
        echo ""
    fi

    echo "   자세한 내용: cat PHASE1_GUIDE.md"
    echo ""
    exit 1
fi
