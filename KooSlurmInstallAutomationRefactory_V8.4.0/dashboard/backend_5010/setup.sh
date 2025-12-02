#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🐍 Backend 환경 설정 (Python 3.12)"
echo "=========================================="
echo ""

if command -v python3.12 &> /dev/null; then
    PYTHON_CMD="python3.12"
    echo -e "${GREEN}✓ Python 3.12: $(python3.12 --version)${NC}"
elif command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    echo -e "${YELLOW}⚠️  Python 3.12 없음, $(python3 --version) 사용${NC}"
else
    echo -e "${RED}❌ Python 없음${NC}"
    exit 1
fi

[ -d "venv" ] && rm -rf venv
echo -e "${BLUE}가상환경 생성 중...${NC}"
$PYTHON_CMD -m venv venv

if [ ! -f "venv/bin/activate" ]; then
    echo -e "${RED}❌ venv 생성 실패! python3-venv 설치: sudo apt install python3-venv${NC}"
    exit 1
fi

source venv/bin/activate
python -m pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt
deactivate

echo -e "${GREEN}✅ Backend 환경 설정 완료!${NC}"
echo "다음: ./start.sh"
