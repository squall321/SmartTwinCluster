#!/bin/bash
################################################################################
# Embedding Test Script
# - iframe, Web Component 임베딩 테스트
# - 빌드 후 테스트 페이지 제공
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}🔗 Embedding Test Mode${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 빌드
echo -e "${BLUE}1. 빌드 중...${NC}"
npm run build

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 빌드 실패${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 빌드 완료${NC}"
echo ""

# 테스트 서버 시작
echo -e "${BLUE}2. 테스트 서버 시작...${NC}"

# 간단한 HTTP 서버 (Python 사용)
PORT=8080

if lsof -ti:$PORT >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠  포트 $PORT 정리 중...${NC}"
    lsof -ti:$PORT | xargs -r kill -9
    sleep 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Embedding 테스트 준비 완료!${NC}"
echo ""
echo "  테스트 페이지:"
echo ""
echo "  📄 Standalone:     http://localhost:$PORT/index.html"
echo "  🖼️  iframe:         http://localhost:$PORT/embed-examples/iframe.html"
echo "  🔷 Web Component:  http://localhost:$PORT/embed-examples/webcomponent.html"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd dist
python3 -m http.server $PORT
