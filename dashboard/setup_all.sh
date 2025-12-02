#!/bin/bash
# 전체 서버 환경 설정 스크립트

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "🚀 Dashboard 전체 환경 설정"
echo "=========================================="
echo ""

# 먼저 모든 스크립트에 실행 권한 부여
echo -e "${BLUE}[0/4] 모든 스크립트 실행 권한 부여...${NC}"
echo ""

# 최상위 스크립트
chmod +x *.sh 2>/dev/null
echo -e "${GREEN}✓ 최상위 스크립트 (start_all.sh, stop_all.sh 등)${NC}"

# Backend 스크립트
if [ -d "backend_5010" ]; then
    chmod +x backend_5010/*.sh 2>/dev/null
    echo -e "${GREEN}✓ Backend 스크립트${NC}"
fi

# WebSocket 스크립트
if [ -d "websocket_5011" ]; then
    chmod +x websocket_5011/*.sh 2>/dev/null
    echo -e "${GREEN}✓ WebSocket 스크립트${NC}"
fi

# Frontend 스크립트
if [ -d "frontend_3010" ]; then
    chmod +x frontend_3010/*.sh 2>/dev/null
    echo -e "${GREEN}✓ Frontend 스크립트${NC}"
fi

# Prometheus 스크립트
if [ -d "prometheus_9090" ]; then
    chmod +x prometheus_9090/*.sh 2>/dev/null
    echo -e "${GREEN}✓ Prometheus 스크립트${NC}"
fi

# Node Exporter 스크립트
if [ -d "node_exporter_9100" ]; then
    chmod +x node_exporter_9100/*.sh 2>/dev/null
    echo -e "${GREEN}✓ Node Exporter 스크립트${NC}"
fi

echo -e "${GREEN}✅ 모든 스크립트 실행 권한 부여 완료${NC}"
echo ""

# Python 버전 확인
if command -v python3.12 &> /dev/null; then
    PYTHON_VER="$(python3.12 --version)"
    echo -e "${GREEN}✓ Python: $PYTHON_VER${NC}"
elif command -v python3 &> /dev/null; then
    PYTHON_VER="$(python3 --version)"
    echo -e "${YELLOW}⚠️  Python 3.12 권장, 현재: $PYTHON_VER${NC}"
else
    echo -e "${RED}❌ Python 없음${NC}"
    exit 1
fi

# Node.js 버전 확인
if command -v node &> /dev/null; then
    NODE_VER="$(node --version)"
    echo -e "${GREEN}✓ Node.js: $NODE_VER${NC}"
else
    echo -e "${RED}❌ Node.js 없음${NC}"
    exit 1
fi

echo ""

# 1. Backend 설정
echo -e "${BLUE}[1/4] Backend 설정 중...${NC}"
cd backend_5010
if [ -f "setup.sh" ]; then
    ./setup.sh
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Backend 설정 완료${NC}"
    else
        echo -e "${RED}❌ Backend 설정 실패${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ backend_5010/setup.sh 없음${NC}"
    exit 1
fi
cd ..
echo ""

# 2. WebSocket 설정
echo -e "${BLUE}[2/4] WebSocket 설정 중...${NC}"
cd websocket_5011
if [ -f "setup.sh" ]; then
    ./setup.sh
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ WebSocket 설정 완료${NC}"
    else
        echo -e "${RED}❌ WebSocket 설정 실패${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ websocket_5011/setup.sh 없음${NC}"
    exit 1
fi
cd ..
echo ""

# 3. Frontend 설정
echo -e "${BLUE}[3/4] Frontend 설정 중...${NC}"
cd frontend_3010
if [ -f "setup.sh" ]; then
    ./setup.sh
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Frontend 설정 완료${NC}"
    else
        echo -e "${RED}❌ Frontend 설정 실패${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ frontend_3010/setup.sh 없음${NC}"
    exit 1
fi
cd ..
echo ""

# 4. Prometheus/Node Exporter는 바이너리이므로 설정 불필요
echo -e "${BLUE}[참고] Prometheus와 Node Exporter는 바이너리 실행${NC}"
echo -e "  - prometheus_9090/: 이미 준비됨"
echo -e "  - node_exporter_9100/: 이미 준비됨"
echo ""

# 5. 데이터베이스 초기화
echo -e "${BLUE}[4/4] 데이터베이스 초기화...${NC}"
cd backend_5010
if [ -f "init_db.py" ]; then
    source venv/bin/activate
    python init_db.py <<EOF
n
EOF
    deactivate
    echo -e "${GREEN}✅ 데이터베이스 초기화 완료${NC}"
fi
cd ..
echo ""

echo "=========================================="
echo -e "${GREEN}🎉 전체 환경 설정 완료!${NC}"
echo "=========================================="
echo ""
echo "다음 단계:"
echo "  1. 전체 서버 시작: ./start_all.sh"
echo "  2. 전체 서버 중지: ./stop_all.sh"
echo "  3. 서비스 상태 확인: ./check_services.sh"
echo ""
echo "개별 서버 시작:"
echo "  - Backend:  cd backend_5010 && ./start.sh"
echo "  - WebSocket: cd websocket_5011 && ./start.sh"
echo "  - Frontend:  cd frontend_3010 && ./start.sh"
echo "  - Prometheus: cd prometheus_9090 && ./start.sh"
echo "  - Node Exporter: cd node_exporter_9100 && ./start.sh"
echo ""
