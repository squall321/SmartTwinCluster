#!/bin/bash
################################################################################
# HTTP 설정 점검 스크립트 (SSO 비활성화 시)
# 다른 서버에서 실행하여 HTTP 설정이 올바른지 확인
################################################################################

echo "=============================================="
echo "HTTP 설정 점검 (SSO 비활성화 환경)"
echo "=============================================="
echo ""

PROJECT_ROOT="/home/koopark/claude/KooSlurmInstallAutomationRefactory"
DASHBOARD_DIR="$PROJECT_ROOT/dashboard"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass_count=0
fail_count=0

check_pass() {
    echo -e "${GREEN}✓ PASS${NC} $1"
    ((pass_count++))
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC} $1"
    ((fail_count++))
}

check_warn() {
    echo -e "${YELLOW}⚠ WARN${NC} $1"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. YAML 설정 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "$PROJECT_ROOT/my_multihead_cluster.yaml" ]; then
    SSO_ENABLED=$(grep -A 1 "^sso:" "$PROJECT_ROOT/my_multihead_cluster.yaml" | grep "enabled:" | awk '{print $2}')
    PUBLIC_URL=$(grep "public_url:" "$PROJECT_ROOT/my_multihead_cluster.yaml" | awk '{print $2}' | tr -d '"')

    echo "SSO Enabled: $SSO_ENABLED"
    echo "Public URL: $PUBLIC_URL"

    if [ "$SSO_ENABLED" = "false" ]; then
        check_pass "SSO 비활성화 (Mock IdP 사용)"
    else
        check_warn "SSO 활성화됨 - HTTP 설정 필요 없을 수 있음"
    fi

    if [ -n "$PUBLIC_URL" ]; then
        check_pass "Public URL 설정됨: $PUBLIC_URL"
    else
        check_fail "Public URL 미설정"
    fi
else
    check_fail "my_multihead_cluster.yaml 없음"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Frontend .env 파일 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

frontends=("frontend_3010" "auth_portal_4431" "vnc_service_8002" "kooCAEWeb_5173")

for frontend in "${frontends[@]}"; do
    env_file="$DASHBOARD_DIR/$frontend/.env"
    echo ""
    echo "▶ $frontend"

    if [ -f "$env_file" ]; then
        check_pass ".env 파일 존재"

        # HTTP URL 확인
        if grep -q "http://" "$env_file"; then
            check_pass "HTTP URL 사용 중"
        else
            check_fail "HTTPS URL 사용 또는 URL 없음"
        fi

        # URL 표시
        grep "VITE_" "$env_file" 2>/dev/null | while read line; do
            echo "    $line"
        done
    else
        check_fail ".env 파일 없음"
    fi
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Frontend 빌드 상태 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for frontend in "${frontends[@]}"; do
    dist_dir="$DASHBOARD_DIR/$frontend/dist"
    echo ""
    echo "▶ $frontend"

    if [ -d "$dist_dir" ]; then
        file_count=$(find "$dist_dir" -type f | wc -l)
        if [ $file_count -gt 0 ]; then
            check_pass "빌드됨 (파일 $file_count개)"
        else
            check_fail "dist 폴더가 비어있음"
        fi
    else
        check_fail "dist 폴더 없음 - 빌드 필요"
    fi
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Nginx 설정 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

nginx_conf="/etc/nginx/conf.d/hpc-portal.conf"

if [ -f "$nginx_conf" ]; then
    check_pass "Nginx 설정 파일 존재"

    # HTTP 포트 확인
    if grep -q "listen 80" "$nginx_conf"; then
        check_pass "HTTP(80) 포트 리스닝"
    else
        check_fail "HTTP 포트 설정 없음"
    fi

    # HTTPS 리다이렉트 확인
    if grep -q "listen 443\|return 301 https" "$nginx_conf"; then
        check_warn "HTTPS 설정 발견 - HTTP 접속 시 리다이렉트 발생 가능"
    else
        check_pass "HTTPS 강제 없음"
    fi

    # server_name 확인
    server_name=$(grep "server_name" "$nginx_conf" | head -1 | awk '{print $2}' | tr -d ';')
    echo "    server_name: $server_name"

else
    check_fail "Nginx 설정 파일 없음"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. 서비스 상태 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

services=("nginx" "auth_backend" "dashboard_backend" "saml_idp")

for service in "${services[@]}"; do
    echo ""
    echo "▶ $service"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        check_pass "실행 중"
    else
        check_fail "중지됨 또는 설치 안됨"
    fi
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. 포트 리스닝 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ports=("80:nginx" "4430:auth_backend" "5010:dashboard_backend" "7000:saml_idp")

for port_info in "${ports[@]}"; do
    port="${port_info%%:*}"
    service="${port_info##*:}"

    if netstat -tln 2>/dev/null | grep -q ":$port " || ss -tln 2>/dev/null | grep -q ":$port "; then
        check_pass "포트 $port ($service) 리스닝 중"
    else
        check_fail "포트 $port ($service) 리스닝 안함"
    fi
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. 로컬 HTTP 접속 테스트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Nginx 루트
echo ""
echo "▶ HTTP 루트 접속 (Nginx)"
if curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null | grep -q "200\|301\|302"; then
    check_pass "응답 받음"
else
    check_fail "응답 없음"
fi

# Auth Backend
echo ""
echo "▶ Auth Backend 헬스체크"
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4430/health 2>/dev/null)
if [ "$response" = "200" ]; then
    check_pass "정상 (200 OK)"
else
    check_fail "실패 (HTTP $response)"
fi

# SAML IdP
echo ""
echo "▶ SAML IdP 메타데이터"
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:7000/metadata 2>/dev/null)
if [ "$response" = "200" ]; then
    check_pass "정상 (200 OK)"
else
    check_fail "실패 (HTTP $response)"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. HTTPS 리다이렉트 테스트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

redirect_location=$(curl -s -I http://localhost/dashboard 2>/dev/null | grep -i "^Location:" | awk '{print $2}')

if [ -n "$redirect_location" ]; then
    if echo "$redirect_location" | grep -q "https://"; then
        check_fail "HTTPS로 리다이렉트 발생: $redirect_location"
        echo "    → ERR_SSL_PROTOCOL_ERROR의 원인!"
    else
        check_pass "HTTP 리다이렉트 또는 직접 응답"
    fi
else
    check_pass "리다이렉트 없음 (직접 응답)"
fi
echo ""

echo "=============================================="
echo "점검 결과 요약"
echo "=============================================="
echo -e "${GREEN}통과: $pass_count${NC}"
echo -e "${RED}실패: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 점검 통과! HTTP 설정이 올바릅니다.${NC}"
    exit 0
else
    echo -e "${RED}✗ $fail_count개 항목 실패. 위 내용을 확인하세요.${NC}"
    exit 1
fi
