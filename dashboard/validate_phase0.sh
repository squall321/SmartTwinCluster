#!/bin/bash
# Phase 0 종합 검증 스크립트
# 19개 항목 자동 검증

set +e  # 검증 중에는 오류로 중단하지 않음

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Phase 0 종합 검증 (19 항목)${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# 검증 함수
check_pass() {
    echo -e "${GREEN}✓ PASS${NC} $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC} $1"
    ((FAIL_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}⚠ WARN${NC} $1"
    ((WARN_COUNT++))
}

echo "=== 1. Redis 검증 ==="
echo

# 1. Redis 설치
if command -v redis-server &> /dev/null; then
    REDIS_VERSION=$(redis-server --version | awk '{print $3}' | cut -d= -f2)
    check_pass "Redis 설치됨: $REDIS_VERSION"
else
    check_fail "Redis 설치되지 않음"
fi

# 2. Redis 실행 중
if sudo systemctl is-active --quiet redis-server; then
    check_pass "Redis 서비스 실행 중"
else
    check_fail "Redis 서비스 중지됨"
fi

# 3. Redis 응답
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    check_pass "Redis 응답 정상 (PING → PONG)"
else
    check_fail "Redis 응답 없음"
fi

# 4. Redis 설정
if sudo grep -q "^bind 127.0.0.1" /etc/redis/redis.conf 2>/dev/null; then
    check_pass "Redis localhost 바인딩 설정"
else
    check_warn "Redis 바인딩 설정 확인 필요"
fi

# 5. Redis 메모리 설정
if sudo grep -q "^maxmemory 512mb" /etc/redis/redis.conf 2>/dev/null; then
    check_pass "Redis maxmemory 512mb 설정"
else
    check_warn "Redis maxmemory 설정 확인 필요"
fi

echo
echo "=== 2. SAML Identity Provider 검증 ==="
echo

# 6. saml-idp 설치
if npm list -g saml-idp &>/dev/null; then
    SAML_VERSION=$(npm list -g saml-idp 2>/dev/null | grep saml-idp | awk '{print $2}' | sed 's/@//')
    check_pass "saml-idp 설치됨: $SAML_VERSION"
else
    check_fail "saml-idp 설치되지 않음"
fi

# 7. IdP 디렉토리 존재
if [ -d "./saml_idp_7000" ]; then
    check_pass "saml_idp_7000 디렉토리 존재"
else
    check_fail "saml_idp_7000 디렉토리 없음"
fi

# 8. IdP 인증서 존재
if [ -f "./saml_idp_7000/certs/idp-cert.pem" ] && [ -f "./saml_idp_7000/certs/idp-key.pem" ]; then
    check_pass "IdP 인증서 파일 존재"
else
    check_fail "IdP 인증서 파일 없음"
fi

# 9. IdP 실행 중
if curl -s -o /dev/null -w "%{http_code}" http://localhost:7000/metadata 2>/dev/null | grep -qE "200|302"; then
    check_pass "SAML IdP 실행 중 (포트 7000)"
else
    check_warn "SAML IdP 응답 없음 (start_idp.sh 실행 필요)"
fi

# 10. IdP 메타데이터
if [ -f "./saml_idp_7000/idp_metadata.xml" ]; then
    check_pass "IdP 메타데이터 파일 존재"
else
    check_warn "IdP 메타데이터 파일 없음"
fi

echo
echo "=== 3. Nginx 및 SSL 검증 ==="
echo

# 11. Nginx 설치
if command -v nginx &> /dev/null; then
    NGINX_VERSION=$(nginx -v 2>&1 | awk '{print $3}')
    check_pass "Nginx 설치됨: $NGINX_VERSION"
else
    check_fail "Nginx 설치되지 않음"
fi

# 12. Nginx 실행 중
if sudo systemctl is-active --quiet nginx; then
    check_pass "Nginx 서비스 실행 중"
else
    check_fail "Nginx 서비스 중지됨"
fi

# 13. SSL 인증서
if sudo test -f "/etc/ssl/certs/nginx-selfsigned.crt" && sudo test -f "/etc/ssl/private/nginx-selfsigned.key"; then
    check_pass "SSL 인증서 파일 존재"
else
    check_fail "SSL 인증서 파일 없음"
fi

# 14. DH 파라미터
if sudo test -f "/etc/ssl/certs/dhparam.pem"; then
    check_pass "DH 파라미터 파일 존재"
else
    check_fail "DH 파라미터 파일 없음"
fi

# 15. Nginx 설정 파일
if sudo test -f "/etc/nginx/conf.d/auth-portal.conf"; then
    check_pass "auth-portal.conf 설정 파일 존재"
else
    check_fail "auth-portal.conf 설정 파일 없음"
fi

# 16. HTTPS 응답
HTTPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost 2>/dev/null)
if echo "$HTTPS_CODE" | grep -qE "200|502|503"; then
    check_pass "HTTPS 응답 정상 (코드: $HTTPS_CODE)"
else
    check_warn "HTTPS 응답 확인 필요 (코드: $HTTPS_CODE)"
fi

# 17. HTTP → HTTPS 리다이렉트
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null)
if [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "302" ]; then
    check_pass "HTTP → HTTPS 리다이렉트 동작 (코드: $HTTP_CODE)"
else
    check_warn "HTTP → HTTPS 리다이렉트 확인 필요 (코드: $HTTP_CODE)"
fi

echo
echo "=== 4. Apptainer 검증 ==="
echo

# 18. Apptainer Sandbox 디렉토리
SANDBOX_DIR="/scratch/apptainer_sandboxes"
if [ -d "$SANDBOX_DIR" ]; then
    OWNER=$(stat -c '%U:%G' "$SANDBOX_DIR" 2>/dev/null)
    PERMS=$(stat -c '%a' "$SANDBOX_DIR" 2>/dev/null)

    if [ "$OWNER" == "slurm:slurm" ] && [ "$PERMS" == "755" ]; then
        check_pass "Apptainer Sandbox 디렉토리 (slurm:slurm, 755)"
    else
        check_fail "Apptainer Sandbox 권한 오류 ($OWNER, $PERMS)"
    fi
else
    check_fail "Apptainer Sandbox 디렉토리 없음"
fi

# 19. my_cluster.yaml 설정
CLUSTER_YAML="../my_cluster.yaml"
if [ -f "$CLUSTER_YAML" ]; then
    if grep -q "sandbox_path: /scratch/apptainer_sandboxes" "$CLUSTER_YAML"; then
        check_pass "my_cluster.yaml sandbox_path 설정"
    else
        check_warn "my_cluster.yaml sandbox_path 미설정"
    fi

    if grep -q "enabled: true" "$CLUSTER_YAML" | grep -A1 "nvidia:" | grep -q "enabled: true"; then
        check_pass "my_cluster.yaml GPU 활성화 (nvidia.enabled: true)"
    else
        check_warn "my_cluster.yaml GPU 설정 확인 필요"
    fi

    if grep -q "name: vnc" "$CLUSTER_YAML"; then
        check_pass "my_cluster.yaml VNC 파티션 설정"
    else
        check_warn "my_cluster.yaml VNC 파티션 미설정"
    fi
else
    check_fail "my_cluster.yaml 파일 없음"
fi

# 최종 결과
echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  검증 결과 요약${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${GREEN}✓ PASS: $PASS_COUNT${NC}"
echo -e "${RED}✗ FAIL: $FAIL_COUNT${NC}"
echo -e "${YELLOW}⚠ WARN: $WARN_COUNT${NC}"
echo

if [ $FAIL_COUNT -eq 0 ]; then
    if [ $WARN_COUNT -eq 0 ]; then
        echo -e "${GREEN}✓✓✓ Phase 0 검증 완료! 모든 항목 통과! ✓✓✓${NC}"
        echo
        echo "다음 단계:"
        echo "  1. Phase 1 시작: Auth Portal 개발"
        echo "  2. 참고 문서: planning_phases/Phase1_Auth_Portal.md"
        exit 0
    else
        echo -e "${YELLOW}⚠⚠⚠ Phase 0 검증 완료 (경고 있음) ⚠⚠⚠${NC}"
        echo
        echo "경고 항목이 있지만 Phase 1 진행 가능합니다."
        echo "다음 단계:"
        echo "  1. Phase 1 시작: Auth Portal 개발"
        echo "  2. 참고 문서: planning_phases/Phase1_Auth_Portal.md"
        exit 0
    fi
else
    echo -e "${RED}✗✗✗ Phase 0 검증 실패! ✗✗✗${NC}"
    echo
    echo "실패한 항목을 수정한 후 다시 검증해주세요:"
    echo "  ./validate_phase0.sh"
    exit 1
fi
