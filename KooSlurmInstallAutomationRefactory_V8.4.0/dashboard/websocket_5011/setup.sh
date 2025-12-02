#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🔌 WebSocket 독립 환경 설정 (Python 3.13)"
echo "=========================================="
echo ""

# Python 3.13 강제 확인
if ! command -v python3.13 &> /dev/null; then
    echo -e "${RED}❌ Python 3.13이 설치되어 있지 않습니다!${NC}"
    echo ""
    echo "설치 방법:"
    echo "  sudo apt update"
    echo "  sudo apt install python3.13 python3.13-venv python3.13-dev"
    echo ""
    exit 1
fi

PYTHON_CMD="python3.13"
echo -e "${GREEN}✓ Python 3.13: $(python3.13 --version)${NC}"
echo ""

# 기존 venv 삭제
if [ -d "venv" ]; then
    echo -e "${YELLOW}⚠️  기존 venv 삭제 중...${NC}"
    rm -rf venv
fi

# venv 생성
echo -e "${BLUE}🔨 WebSocket 전용 venv 생성 중...${NC}"
$PYTHON_CMD -m venv venv

# venv 생성 확인
if [ ! -f "venv/bin/activate" ]; then
    echo -e "${RED}❌ venv 생성 실패!${NC}"
    echo ""
    echo "다음 명령어로 필요한 패키지를 설치하세요:"
    echo "  sudo apt install python3.13-venv"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ venv 생성 완료${NC}"
echo ""

# venv 활성화
source venv/bin/activate

# pip 업그레이드
echo -e "${BLUE}📦 pip 업그레이드 중...${NC}"
python -m pip install --upgrade pip > /dev/null 2>&1
echo -e "${GREEN}✓ pip 업그레이드 완료${NC}"
echo ""

# 패키지 설치
echo -e "${BLUE}📦 패키지 설치 중...${NC}"
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ requirements.txt 설치 완료${NC}"
    else
        echo -e "${RED}❌ requirements.txt 설치 실패${NC}"
        deactivate
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  requirements.txt 없음, 기본 패키지 설치${NC}"
    pip install websockets aiohttp flask-cors
    pip freeze > requirements.txt
    echo -e "${GREEN}✓ 기본 패키지 설치 완료${NC}"
fi

# Python 버전 확인
echo ""
echo -e "${BLUE}📋 설치된 Python 버전:${NC}"
python --version

deactivate

echo ""
echo "=========================================="
echo -e "${GREEN}✅ WebSocket 독립 환경 설정 완료!${NC}"
echo "=========================================="
echo ""
echo "💡 Python 3.13 전용 venv 생성됨"
echo "💡 Backend 없이도 단독 실행 가능"
echo ""
echo "다음 단계: ./start.sh"
