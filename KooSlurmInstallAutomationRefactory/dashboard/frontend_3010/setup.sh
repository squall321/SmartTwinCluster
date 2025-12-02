#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "⚛️  Frontend 환경 설정 (Node.js)"
echo "=========================================="

command -v node &> /dev/null || (echo -e "${RED}❌ Node.js 없음${NC}" && exit 1)
command -v npm &> /dev/null || (echo -e "${RED}❌ npm 없음${NC}" && exit 1)

echo "Node.js: $(node --version)"
echo "npm: $(npm --version)"
echo ""

[ -d "node_modules" ] && rm -rf node_modules
npm install

echo -e "${GREEN}✅ Frontend 환경 설정 완료!${NC}"
echo "다음: ./start.sh"
