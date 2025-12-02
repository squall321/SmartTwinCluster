#!/bin/bash
################################################################################
# Standalone Test Script
# - 빌드 없이 빠르게 테스트
# - Mock 백엔드 포함
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🧪 Standalone Test Mode${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Mock 백엔드 체크
echo -e "${BLUE}1. 백엔드 서버 체크...${NC}"
if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ kooCAEWebServer_5000 실행 중${NC}"
else
    echo -e "${YELLOW}⚠  kooCAEWebServer_5000이 실행되지 않았습니다${NC}"
    echo "   Mock 모드로 계속 진행합니다."
fi

echo ""
echo -e "${BLUE}2. 프론트엔드 빌드 (개발 모드)...${NC}"
export VITE_API_BASE_URL=http://localhost:5000
export VITE_MOCK_MODE=true

echo ""
echo -e "${GREEN}✅ 테스트 서버 시작!${NC}"
echo ""
echo "  Frontend: http://localhost:5174"
echo "  Backend:  http://localhost:5000 (필요 시)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

npm run dev
