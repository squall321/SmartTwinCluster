#!/bin/bash
# 전체 시스템 통합 설치 스크립트
# Phase 0 (인프라) + Phase 1 (Auth Portal) 일괄 설치

set -e

# -y 옵션 처리
AUTO_YES=false
if [[ "$1" == "-y" ]] || [[ "$1" == "--yes" ]]; then
    AUTO_YES=true
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DASHBOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DASHBOARD_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  HPC Auth Portal 통합 설치${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "다음 항목을 설치합니다:"
echo "  Phase 0: Redis, SAML-IdP, Nginx, Apptainer"
echo "  Phase 1: Auth Backend, Auth Frontend"
echo
echo "예상 소요 시간: 15-20분"
echo
echo -e "${YELLOW}주의: 이 스크립트는 sudo 권한이 필요합니다.${NC}"
echo

# 계속 진행 확인
if [[ "$AUTO_YES" == false ]]; then
    read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "설치 취소됨"
        exit 0
    fi
else
    echo "자동 설치 모드 (-y 옵션)"
fi

echo

# ============================================================================
# Step 1: 시스템 의존성 확인 및 설치
# ============================================================================

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Step 1: 시스템 의존성 설치${NC}"
echo -e "${CYAN}========================================${NC}"
echo

# Ubuntu 버전 확인
if ! grep -q "Ubuntu 22.04" /etc/os-release 2>/dev/null; then
    echo -e "${YELLOW}⚠${NC} 이 스크립트는 Ubuntu 22.04용으로 작성되었습니다."
    echo "다른 버전에서는 일부 명령이 작동하지 않을 수 있습니다."
fi

echo "필수 패키지 설치 중..."
sudo apt update

# Python 관련
if ! command -v python3 &> /dev/null; then
    sudo apt install -y python3
fi
sudo apt install -y python3-pip python3-venv

# Node.js 확인
if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Node.js가 설치되어 있지 않습니다."
    echo "Node.js 20.x를 설치합니다..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
fi

NODE_VERSION=$(node -v)
echo -e "${GREEN}✓${NC} Node.js 설치됨: $NODE_VERSION"

# XML/SAML 라이브러리
echo "XML/SAML 라이브러리 설치 중..."
sudo apt install -y libxml2-dev libxmlsec1-dev libxmlsec1-openssl pkg-config

# Git (코드 배포용)
sudo apt install -y git curl wget

echo -e "${GREEN}✓${NC} 시스템 의존성 설치 완료"
echo

sleep 2

# ============================================================================
# Step 2: Phase 0 설치
# ============================================================================

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Step 2: Phase 0 인프라 설치${NC}"
echo -e "${CYAN}========================================${NC}"
echo

if [ -f "setup_phase0_all.sh" ]; then
    echo "y" | ./setup_phase0_all.sh
    echo
    echo -e "${GREEN}✓${NC} Phase 0 설치 완료"
else
    echo -e "${RED}✗${NC} setup_phase0_all.sh를 찾을 수 없습니다."
    exit 1
fi

sleep 2

# ============================================================================
# Step 3: Phase 1 Backend 설치
# ============================================================================

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Step 3: Auth Backend 설치${NC}"
echo -e "${CYAN}========================================${NC}"
echo

cd auth_portal_4430

# Python 가상 환경 생성
if [ ! -d "venv" ]; then
    echo "Python 가상 환경 생성 중..."
    python3 -m venv venv
    echo -e "${GREEN}✓${NC} 가상 환경 생성 완료"
fi

# 의존성 설치
echo "Python 패키지 설치 중..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate

echo -e "${GREEN}✓${NC} Auth Backend 의존성 설치 완료"

# .env 파일 생성 (없는 경우)
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠${NC} .env 파일이 없습니다. 기본 설정으로 생성합니다."
    cat > .env << 'EOF'
# Flask Configuration
FLASK_ENV=development
FLASK_DEBUG=True
SECRET_KEY=$(openssl rand -hex 32)

# JWT Configuration
JWT_SECRET_KEY=$(openssl rand -hex 32)
JWT_ALGORITHM=HS256
JWT_EXPIRATION_HOURS=8

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# SAML Configuration
SAML_IDP_METADATA_URL=http://localhost:7000/metadata
SAML_SP_ENTITY_ID=auth-portal
SAML_ACS_URL=http://localhost:4430/auth/saml/acs
SAML_SLS_URL=http://localhost:4430/auth/saml/sls

# Service URLs
DASHBOARD_URL=https://localhost/dashboard/
CAE_URL=https://localhost/cae/
VNC_URL=https://localhost/vnc/

# Server Configuration
HOST=0.0.0.0
PORT=4430
EOF
    echo -e "${GREEN}✓${NC} .env 파일 생성 완료"
fi

cd ..
echo

sleep 2

# ============================================================================
# Step 4: Phase 1 Frontend 설치
# ============================================================================

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Step 4: Auth Frontend 설치${NC}"
echo -e "${CYAN}========================================${NC}"
echo

cd auth_portal_4431

# Node.js 의존성 설치
if [ ! -d "node_modules" ]; then
    echo "Node.js 패키지 설치 중..."
    npm install
    echo -e "${GREEN}✓${NC} Auth Frontend 의존성 설치 완료"
else
    echo -e "${GREEN}✓${NC} node_modules가 이미 존재합니다."
fi

cd ..
echo

sleep 2

# ============================================================================
# Step 5: 검증
# ============================================================================

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Step 5: 설치 검증${NC}"
echo -e "${CYAN}========================================${NC}"
echo

if [ -f "validate_phase0.sh" ]; then
    echo "Phase 0 검증 실행 중..."
    ./validate_phase0.sh
else
    echo -e "${YELLOW}⚠${NC} validate_phase0.sh를 찾을 수 없습니다. 검증 건너뜀."
fi

echo

# ============================================================================
# 완료
# ============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  설치 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "다음 명령으로 서비스를 시작하세요:"
echo
echo -e "  ${CYAN}./start_phase1.sh${NC}"
echo
echo "설치된 구성 요소:"
echo "  ✓ Phase 0: Redis, SAML-IdP, Nginx, Apptainer"
echo "  ✓ Phase 1: Auth Backend (Python), Auth Frontend (Node.js)"
echo
echo "문서:"
echo "  - Phase 0: ./planning_phases/Phase0_Prerequisites.md"
echo "  - Phase 1: ./PHASE1_README.md"
echo
