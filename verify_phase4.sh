#!/bin/bash
################################################################################
# Phase 4 검증 스크립트
################################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 Phase 4 완료 검증"
echo "===================="
echo ""

ERRORS=0
WARNINGS=0

# ============================================================================
# 1. Phase 3 완료 확인
# ============================================================================
echo -e "${BLUE}📋 Phase 3 완료 여부 확인...${NC}"
if [ -f "./verify_phase3.sh" ]; then
    ./verify_phase3.sh > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Phase 3 완료 확인${NC}"
    else
        echo -e "  ${RED}❌ Phase 3이 완료되지 않았습니다${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "  ${RED}❌ verify_phase3.sh 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 2. Nginx 설치 확인
# ============================================================================
echo -e "${BLUE}🌐 Nginx 설치 확인...${NC}"

if command -v nginx &> /dev/null; then
    NGINX_VERSION=$(nginx -v 2>&1 | awk -F'/' '{print $2}')
    echo -e "  ${GREEN}✅ Nginx 설치됨 (버전: $NGINX_VERSION)${NC}"
else
    echo -e "  ${YELLOW}⚠️  Nginx 미설치${NC}"
    echo -e "     ${YELLOW}sudo apt install nginx${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ============================================================================
# 3. Nginx 템플릿 파일 확인
# ============================================================================
echo -e "${BLUE}📝 Nginx 템플릿 파일 확인...${NC}"

NGINX_TEMPLATES=(
    "web_services/templates/nginx/main.conf.j2"
)

TEMPLATE_COUNT=0
for TEMPLATE in "${NGINX_TEMPLATES[@]}"; do
    if [ -f "$TEMPLATE" ]; then
        echo -e "  ${GREEN}✅ $(basename $TEMPLATE)${NC}"
        TEMPLATE_COUNT=$((TEMPLATE_COUNT+1))

        # Jinja2 변수 사용 확인
        if grep -q "{{.*}}\|{%.*%}" "$TEMPLATE"; then
            # OK
            true
        else
            echo -e "    ${YELLOW}⚠️  Jinja2 변수 사용 안 함${NC}"
            WARNINGS=$((WARNINGS+1))
        fi

        # 주요 location 블록 확인
        if grep -q "location /auth" "$TEMPLATE" && \
           grep -q "location /api" "$TEMPLATE" && \
           grep -q "location /ws" "$TEMPLATE"; then
            echo -e "    ${GREEN}✅ 주요 라우팅 존재${NC}"
        else
            echo -e "    ${RED}❌ 라우팅 누락${NC}"
            ERRORS=$((ERRORS+1))
        fi
    else
        echo -e "  ${RED}❌ $(basename $TEMPLATE) 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""

# ============================================================================
# 4. Nginx 스크립트 확인
# ============================================================================
echo -e "${BLUE}🔧 Nginx 스크립트 확인...${NC}"

NGINX_SCRIPTS=(
    "web_services/scripts/setup_nginx.sh"
    "web_services/scripts/generate_nginx_config.py"
)

SCRIPT_COUNT=0
for SCRIPT in "${NGINX_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT" ]; then
        echo -e "  ${GREEN}✅ $(basename $SCRIPT)${NC}"
        SCRIPT_COUNT=$((SCRIPT_COUNT+1))

        # 실행 권한 확인
        if [ -x "$SCRIPT" ] || [[ "$SCRIPT" == *.py ]]; then
            # OK
            true
        else
            echo -e "    ${YELLOW}⚠️  실행 권한 없음${NC}"
            WARNINGS=$((WARNINGS+1))
        fi
    else
        echo -e "  ${RED}❌ $(basename $SCRIPT) 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""

# ============================================================================
# 5. SSL 인증서 스크립트 확인
# ============================================================================
echo -e "${BLUE}🔐 SSL 인증서 스크립트 확인...${NC}"

SSL_SCRIPTS=(
    "web_services/scripts/generate_self_signed_cert.sh"
)

SSL_COUNT=0
for SCRIPT in "${SSL_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT" ]; then
        echo -e "  ${GREEN}✅ $(basename $SCRIPT)${NC}"
        SSL_COUNT=$((SSL_COUNT+1))
    else
        echo -e "  ${YELLOW}⚠️  $(basename $SCRIPT) 없음 (선택사항)${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
done

# Let's Encrypt 스크립트 (선택사항)
if [ -f "web_services/scripts/setup_letsencrypt.sh" ]; then
    echo -e "  ${GREEN}✅ setup_letsencrypt.sh (선택)${NC}"
fi

echo ""

# ============================================================================
# 6. generate_nginx_config.py 기능 확인
# ============================================================================
echo -e "${BLUE}🐍 generate_nginx_config.py 기능 확인...${NC}"

if [ -f "web_services/scripts/generate_nginx_config.py" ]; then
    # Python 문법 검증
    python3 -m py_compile web_services/scripts/generate_nginx_config.py 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Python 문법 검증 성공${NC}"
    else
        echo -e "  ${RED}❌ Python 문법 오류${NC}"
        ERRORS=$((ERRORS+1))
    fi

    # 필수 import 확인
    if grep -q "import yaml" web_services/scripts/generate_nginx_config.py && \
       grep -q "from jinja2 import Template" web_services/scripts/generate_nginx_config.py; then
        echo -e "  ${GREEN}✅ 필수 import 존재${NC}"
    else
        echo -e "  ${RED}❌ 필수 import 누락${NC}"
        ERRORS=$((ERRORS+1))
    fi
fi

echo ""

# ============================================================================
# 7. web_services_config.yaml에 Nginx 설정 확인
# ============================================================================
echo -e "${BLUE}⚙️  web_services_config.yaml Nginx 설정 확인...${NC}"

if [ -f "web_services_config.yaml" ]; then
    if grep -q "^nginx:" web_services_config.yaml; then
        echo -e "  ${GREEN}✅ nginx 섹션 존재${NC}"

        # routes 정의 확인
        if grep -q "routes:" web_services_config.yaml; then
            echo -e "  ${GREEN}✅ routes 정의 존재${NC}"
        else
            echo -e "  ${YELLOW}⚠️  routes 정의 확인 필요${NC}"
            WARNINGS=$((WARNINGS+1))
        fi

        # SSL 설정 확인
        if grep -q "ssl:" web_services_config.yaml; then
            echo -e "  ${GREEN}✅ SSL 설정 존재${NC}"
        else
            echo -e "  ${YELLOW}⚠️  SSL 설정 없음${NC}"
            WARNINGS=$((WARNINGS+1))
        fi
    else
        echo -e "  ${RED}❌ nginx 섹션 없음${NC}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "  ${RED}❌ web_services_config.yaml 없음${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""

# ============================================================================
# 8. Nginx 설정 디렉토리 확인
# ============================================================================
echo -e "${BLUE}📁 Nginx 설정 디렉토리 확인...${NC}"

if [ -d "/etc/nginx" ]; then
    echo -e "  ${GREEN}✅ /etc/nginx 존재${NC}"

    if [ -d "/etc/nginx/sites-available" ]; then
        echo -e "  ${GREEN}✅ /etc/nginx/sites-available 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  /etc/nginx/sites-available 없음${NC}"
        WARNINGS=$((WARNINGS+1))
    fi

    if [ -d "/etc/nginx/sites-enabled" ]; then
        echo -e "  ${GREEN}✅ /etc/nginx/sites-enabled 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠️  /etc/nginx/sites-enabled 없음${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "  ${YELLOW}⚠️  /etc/nginx 없음 (Nginx 미설치)${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ============================================================================
# 9. Nginx 상태 확인 (실행 중이면)
# ============================================================================
echo -e "${BLUE}🚦 Nginx 상태 확인...${NC}"

if command -v nginx &> /dev/null; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "  ${GREEN}✅ Nginx 실행 중${NC}"

        # 설정 검증
        sudo nginx -t &>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✅ Nginx 설정 검증 성공${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Nginx 설정에 문제 있음${NC}"
            echo -e "     ${YELLOW}sudo nginx -t${NC}"
            WARNINGS=$((WARNINGS+1))
        fi
    else
        echo -e "  ${YELLOW}⚠️  Nginx 중지됨 (정상 - 아직 설정 전)${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  Nginx 미설치${NC}"
fi

echo ""

# ============================================================================
# 10. 최종 결과
# ============================================================================
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅✅✅ Phase 4 완료!${NC}"
    echo "========================================"
    echo ""
    echo "📋 생성된 파일:"
    echo "   ✓ Nginx 설정 템플릿 (main.conf.j2)"
    echo "   ✓ setup_nginx.sh"
    echo "   ✓ generate_nginx_config.py"
    echo "   ✓ SSL 인증서 스크립트"
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE5_GUIDE.md"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ] && [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Phase 4 완료 (경고 $WARNINGS 개)${NC}"
    echo "========================================"
    echo ""
    echo "💡 경고는 무시하고 진행 가능하지만, 검토를 권장합니다."
    echo ""
    echo "📋 다음 단계:"
    echo "   cat PHASE5_GUIDE.md"
    echo ""
    exit 0
else
    echo -e "${RED}❌ $ERRORS 개 오류, $WARNINGS 개 경고${NC}"
    echo "========================================"
    echo ""
    echo "💡 수정 방법:"
    echo ""

    if [ ! -f "web_services/templates/nginx/main.conf.j2" ]; then
        echo "   1. Nginx 템플릿 작성:"
        echo "      PHASE4_GUIDE.md 섹션 1 참조"
        echo ""
    fi

    if [ ! -f "web_services/scripts/setup_nginx.sh" ]; then
        echo "   2. setup_nginx.sh 작성:"
        echo "      PHASE4_GUIDE.md 섹션 2 참조"
        echo ""
    fi

    if [ ! -f "web_services/scripts/generate_nginx_config.py" ]; then
        echo "   3. generate_nginx_config.py 작성:"
        echo "      PHASE4_GUIDE.md 섹션 2 참조"
        echo ""
    fi

    if ! command -v nginx &> /dev/null; then
        echo "   4. Nginx 설치:"
        echo "      sudo apt install nginx"
        echo ""
    fi

    echo "   자세한 내용: cat PHASE4_GUIDE.md"
    echo ""
    exit 1
fi
