#!/bin/bash
# Phase 0 통합 설치 스크립트
# Redis, SAML-IdP, Nginx, Apptainer 순차 설치 및 검증

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Phase 0 통합 설치 시작${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "다음 구성 요소를 순차적으로 설치합니다:"
echo "  1. Redis 7+ (세션 저장소)"
echo "  2. SAML Identity Provider (테스트용 IdP)"
echo "  3. Nginx + SSL (리버스 프록시)"
echo "  4. Apptainer Sandbox (컨테이너 디렉토리)"
echo
echo "예상 소요 시간: 5-10분"
echo "  (DH 파라미터 생성 시 1-5분 추가 소요)"
echo
echo -e "${YELLOW}주의: sudo 권한이 필요합니다.${NC}"
echo

# 계속 진행 확인
read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "설치 취소됨"
    exit 0
fi

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  1/4: Redis 설치 및 설정${NC}"
echo -e "${CYAN}========================================${NC}"
echo

if ./setup_phase0_redis.sh; then
    echo
    echo -e "${GREEN}✓ Redis 설치 완료${NC}"
else
    echo
    echo -e "${RED}✗ Redis 설치 실패${NC}"
    exit 1
fi

sleep 2

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  2/4: SAML Identity Provider 설정${NC}"
echo -e "${CYAN}========================================${NC}"
echo

if ./setup_phase0_saml_idp.sh; then
    echo
    echo -e "${GREEN}✓ SAML IdP 설치 완료${NC}"
else
    echo
    echo -e "${RED}✗ SAML IdP 설치 실패${NC}"
    exit 1
fi

sleep 2

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  3/4: Nginx 및 SSL 설정${NC}"
echo -e "${CYAN}========================================${NC}"
echo

if ./setup_phase0_nginx.sh; then
    echo
    echo -e "${GREEN}✓ Nginx 설치 완료${NC}"
else
    echo
    echo -e "${RED}✗ Nginx 설치 실패${NC}"
    exit 1
fi

sleep 2

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  4/4: Apptainer Sandbox 설정${NC}"
echo -e "${CYAN}========================================${NC}"
echo

if ./setup_phase0_apptainer.sh; then
    echo
    echo -e "${GREEN}✓ Apptainer Sandbox 설치 완료${NC}"
else
    echo
    echo -e "${RED}✗ Apptainer Sandbox 설치 실패${NC}"
    exit 1
fi

sleep 2

echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Phase 0 설치 완료!${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "설치된 구성 요소:"
echo -e "  ${GREEN}✓${NC} Redis 7+ (localhost:6379)"
echo -e "  ${GREEN}✓${NC} SAML IdP (localhost:7000)"
echo -e "  ${GREEN}✓${NC} Nginx + SSL (https://localhost)"
echo -e "  ${GREEN}✓${NC} Apptainer Sandbox (/scratch/apptainer_sandboxes)"
echo

# 서비스 상태 요약
echo "서비스 상태:"
if sudo systemctl is-active --quiet redis-server; then
    echo -e "  Redis:    ${GREEN}● 실행 중${NC}"
else
    echo -e "  Redis:    ${RED}● 중지됨${NC}"
fi

if curl -s -o /dev/null -w "%{http_code}" http://localhost:7000/metadata 2>/dev/null | grep -qE "200|302"; then
    echo -e "  SAML IdP: ${GREEN}● 실행 중${NC}"
else
    echo -e "  SAML IdP: ${YELLOW}● 대기 중${NC} (./saml_idp_7000/start_idp.sh 실행)"
fi

if sudo systemctl is-active --quiet nginx; then
    echo -e "  Nginx:    ${GREEN}● 실행 중${NC}"
else
    echo -e "  Nginx:    ${RED}● 중지됨${NC}"
fi

echo
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  다음: 종합 검증 실행${NC}"
echo -e "${YELLOW}========================================${NC}"
echo
echo "Phase 0 설치가 완료되었습니다."
echo "종합 검증 스크립트를 실행하여 모든 항목이 정상 동작하는지 확인하세요:"
echo
echo -e "  ${CYAN}./validate_phase0.sh${NC}"
echo
echo "검증 통과 후 Phase 1 (Auth Portal 개발)로 진행할 수 있습니다."
echo
