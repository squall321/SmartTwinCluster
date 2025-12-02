#!/bin/bash
################################################################################
# App Framework Development Server
# - Port 5174에서 개발 서버 실행
# - Hot Module Replacement (HMR) 지원
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🚀 App Framework Development Server${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 포트 체크
PORT=5174
if lsof -ti:$PORT >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠  포트 $PORT가 이미 사용 중입니다.${NC}"
    echo "  기존 프로세스를 종료하시겠습니까? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        lsof -ti:$PORT | xargs -r kill -9
        sleep 1
        echo -e "${GREEN}✅ 포트 정리 완료${NC}"
    else
        echo "종료합니다."
        exit 1
    fi
fi

echo -e "${GREEN}📦 Dependencies 확인 중...${NC}"
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}⚠  node_modules가 없습니다. npm install 실행 중...${NC}"
    npm install
fi

echo ""
echo -e "${BLUE}🔧 개발 서버 시작 중...${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ 서버 준비 완료!${NC}"
echo ""
echo "  Local:   http://localhost:5174"
echo "  Network: http://$(hostname -I | awk '{print $1}'):5174"
echo ""
echo "  kooCAEWebServer: http://localhost:5000"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

npm run dev
