#!/bin/bash
################################################################################
# HPC Cluster Production 시작 스크립트
# - 프론트엔드: Nginx를 통한 static 파일 서빙 (dev 서버 없음)
# - 백엔드: Python 서비스만 실행
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🚀 HPC Cluster Production 모드 시작"
echo "=========================================="
echo ""

# ==================== 0. 프론트엔드 빌드 ====================
echo -e "${BLUE}[0/8] 프론트엔드 빌드 중...${NC}"
if [ -f "./build_all_frontends.sh" ]; then
    ./build_all_frontends.sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 프론트엔드 빌드 실패. 계속 진행합니다...${NC}"
    fi
else
    echo -e "${YELLOW}⚠  빌드 스크립트 없음. 기존 빌드 파일 사용${NC}"
fi
echo ""

# ==================== 1. 기존 서비스 종료 ====================
echo -e "${BLUE}[1/8] 기존 서비스 종료 중...${NC}"

# 먼저 모든 dev 서버 포트를 강제로 해제 (Production 우선)
echo "  → Dev 서버 포트 강제 종료 (3010, 8002, 5173, 5174)..."
fuser -k 3010/tcp 2>/dev/null
fuser -k 8002/tcp 2>/dev/null
fuser -k 5173/tcp 2>/dev/null
fuser -k 5174/tcp 2>/dev/null
sleep 1

# 모든 vite/npm dev 프로세스 강제 종료
pkill -9 -f "vite.*3010" 2>/dev/null
pkill -9 -f "vite.*8002" 2>/dev/null
pkill -9 -f "vite.*5173" 2>/dev/null
pkill -9 -f "vite.*5174" 2>/dev/null
pkill -9 -f "npm.*dev.*3010" 2>/dev/null
pkill -9 -f "npm.*dev.*8002" 2>/dev/null
pkill -9 -f "npm.*dev.*5173" 2>/dev/null
pkill -9 -f "npm.*dev.*5174" 2>/dev/null
sleep 1

# Snap Prometheus 종료 (포트 충돌 방지)
echo "  → Snap Prometheus 종료 중..."
sudo snap stop prometheus 2>/dev/null && echo "    ✓ Snap Prometheus 중지됨"
sudo snap disable prometheus 2>/dev/null

# 백엔드 서비스 종료
pkill -f "auth_portal_4430.*app.py" 2>/dev/null
pkill -f "backend_5010.*app.py" 2>/dev/null
pkill -f "websocket_5011.*python" 2>/dev/null
pkill -f "prometheus.*9090" 2>/dev/null
pkill -f "node_exporter.*9100" 2>/dev/null
pkill -f "kooCAEWebServer_5000.*python" 2>/dev/null
pkill -f "kooCAEWebAutomationServer_5001.*python" 2>/dev/null

# Auth Frontend는 유지 (개발 진행 중)
# pkill -f "auth_portal_4431.*vite" 2>/dev/null

# 최종 확인: dev 서버 포트 및 백엔드 포트가 완전히 해제되었는지 확인
for port in 3010 8002 5173 5174 5000 5001; do
    if lsof -ti:$port >/dev/null 2>&1; then
        echo "  → 포트 $port 강제 해제 중..."
        lsof -ti:$port | xargs -r kill -9 2>/dev/null
    fi
done

sleep 3
echo -e "${GREEN}✅ 기존 서비스 종료 완료 (Dev 서버 포트: 3010, 8002, 5173, 5174 해제됨)${NC}"
echo ""

# ==================== 2. Redis 확인 ====================
echo -e "${BLUE}[2/8] Redis 확인 중...${NC}"
if ! redis-cli ping &>/dev/null; then
    echo -e "${RED}❌ Redis가 실행되지 않습니다.${NC}"
    echo "Redis를 먼저 시작해주세요: sudo systemctl start redis-server"
    exit 1
fi
echo -e "${GREEN}✅ Redis 실행 중${NC}"
echo ""

# ==================== 3. SAML-IdP 시작 ====================
echo -e "${BLUE}[3/8] SAML-IdP 시작 중...${NC}"
if pgrep -f "saml-idp.*7000" > /dev/null; then
    echo -e "${YELLOW}⚠  SAML-IdP가 이미 실행 중입니다.${NC}"
else
    if [ -d "saml_idp_7000" ]; then
        cd saml_idp_7000
        ./start_idp.sh > /dev/null 2>&1
        cd "$SCRIPT_DIR"
        echo -e "${GREEN}✅ SAML-IdP 시작됨${NC}"
    else
        echo -e "${YELLOW}⚠  saml_idp_7000 디렉토리 없음${NC}"
    fi
fi
echo ""

# ==================== 4. Auth Backend 시작 ====================
echo -e "${BLUE}[4/8] Auth Backend 시작 중...${NC}"
if pgrep -f "python.*auth_portal_4430.*app.py" > /dev/null; then
    echo -e "${YELLOW}  → Auth Backend 재시작 중...${NC}"
    pkill -f "python.*auth_portal_4430.*app.py"
    sleep 1
fi

cd auth_portal_4430
if [ -d "venv" ]; then
    nohup venv/bin/python3 app.py > logs/backend.log 2>&1 &
else
    nohup python3 app.py > logs/backend.log 2>&1 &
fi
BACKEND_PID=$!
echo $BACKEND_PID > logs/backend.pid
cd "$SCRIPT_DIR"
sleep 3
echo -e "${GREEN}✅ Auth Backend 시작됨 (PID: $BACKEND_PID, Port: 4430)${NC}"
echo ""

# ==================== 5. Auth Frontend (Dev 서버 - UI 개발용) ====================
echo -e "${BLUE}[5/8] Auth Frontend 시작 중...${NC}"
if pgrep -f "vite.*auth_portal_4431" > /dev/null; then
    echo -e "${YELLOW}  → Auth Frontend 재시작 중...${NC}"
    pkill -f "vite.*auth_portal_4431"
    sleep 1
fi

cd auth_portal_4431
mkdir -p logs
nohup npm run dev > logs/frontend.log 2>&1 &
FRONTEND_PID=$!
echo $FRONTEND_PID > logs/frontend.pid
cd "$SCRIPT_DIR"
sleep 5
echo -e "${GREEN}✅ Auth Frontend 시작됨 (PID: $FRONTEND_PID, Port: 4431)${NC}"
echo ""

# ==================== 6. Dashboard Backend + WebSocket ====================
echo -e "${BLUE}[6/8] Dashboard Backend + WebSocket 시작 중...${NC}"

# Dashboard Backend (MOCK_MODE=false for Production)
if pgrep -f "backend_5010.*app.py" > /dev/null; then
    echo -e "${YELLOW}  → Dashboard Backend 재시작 중...${NC}"
    pkill -f "backend_5010.*app.py"
    sleep 1
fi

cd backend_5010
# Clean up old log file to avoid permission issues
rm -f dashboard_backend.log
if [ -d "venv" ]; then
    MOCK_MODE=false nohup venv/bin/python app.py > dashboard_backend.log 2>&1 &
else
    MOCK_MODE=false nohup python3 app.py > dashboard_backend.log 2>&1 &
fi
DB_BACKEND_PID=$!
echo $DB_BACKEND_PID > .backend.pid
cd "$SCRIPT_DIR"
echo -e "${GREEN}✅ Dashboard Backend 시작됨 (PID: $DB_BACKEND_PID, Port: 5010)${NC}"

# WebSocket Server
if pgrep -f "websocket_5011.*python" > /dev/null; then
    echo -e "${YELLOW}  → WebSocket Server 재시작 중...${NC}"
    pkill -f "websocket_5011.*python"
    sleep 1
fi

cd websocket_5011
# Clean up old log file to avoid permission issues
rm -f websocket.log
if [ -d "venv" ]; then
    nohup venv/bin/python websocket_server_enhanced.py > websocket.log 2>&1 &
else
    nohup python3 websocket_server_enhanced.py > websocket.log 2>&1 &
fi
WS_PID=$!
echo $WS_PID > .websocket.pid
cd "$SCRIPT_DIR"
echo -e "${GREEN}✅ WebSocket Server 시작됨 (PID: $WS_PID, Port: 5011)${NC}"

# Prometheus (선택사항)
if [ -d "prometheus_9090" ] && [ -f "prometheus_9090/start.sh" ]; then
    cd prometheus_9090
    ./start.sh > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ Prometheus 시작됨 (Port: 9090)${NC}"
fi

# Node Exporter (선택사항)
if [ -d "node_exporter_9100" ] && [ -f "node_exporter_9100/start.sh" ]; then
    cd node_exporter_9100
    ./start.sh > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ Node Exporter 시작됨 (Port: 9100)${NC}"
fi

echo ""

# ==================== 7. Backend .env 확인 ====================
echo -e "${BLUE}[7/8] Backend 설정 확인 중...${NC}"

# MOCK_MODE=false 확인
if [ -f "backend_5010/.env" ]; then
    if grep -q "^MOCK_MODE=false" backend_5010/.env; then
        echo -e "${GREEN}✅ Backend MOCK_MODE=false 설정됨${NC}"
    else
        echo -e "${YELLOW}⚠  Backend .env에 MOCK_MODE=false 설정 추가${NC}"
        if ! grep -q "^MOCK_MODE=" backend_5010/.env; then
            echo "MOCK_MODE=false" >> backend_5010/.env
        else
            sed -i 's/^MOCK_MODE=.*/MOCK_MODE=false/' backend_5010/.env
        fi
        echo -e "${GREEN}✅ MOCK_MODE=false 설정 완료${NC}"
    fi
else
    echo -e "${YELLOW}⚠  backend_5010/.env 파일이 없습니다${NC}"
    echo "MOCK_MODE=false" > backend_5010/.env
    echo -e "${GREEN}✅ .env 파일 생성 완료${NC}"
fi

echo ""

# ==================== 8. CAE Services ====================
echo -e "${BLUE}[8/9] CAE Services 시작 중...${NC}"

# CAE Backend (5000)
if pgrep -f "kooCAEWebServer_5000.*python" > /dev/null; then
    echo -e "${YELLOW}  → CAE Backend 재시작 중...${NC}"
    pkill -f "kooCAEWebServer_5000.*python"
    sleep 1
fi

if [ -d "kooCAEWebServer_5000" ]; then
    cd kooCAEWebServer_5000
    # Clean up old log file to avoid permission issues
    rm -f cae_backend.log
    if [ -d "venv" ]; then
        nohup venv/bin/python app.py > cae_backend.log 2>&1 &
    else
        nohup python3 app.py > cae_backend.log 2>&1 &
    fi
    CAE_BACKEND_PID=$!
    echo $CAE_BACKEND_PID > .cae_backend.pid
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ CAE Backend 시작됨 (PID: $CAE_BACKEND_PID, Port: 5000)${NC}"
fi

# CAE Automation (5001)
if pgrep -f "kooCAEWebAutomationServer_5001.*python" > /dev/null; then
    echo -e "${YELLOW}  → CAE Automation 재시작 중...${NC}"
    pkill -f "kooCAEWebAutomationServer_5001.*python"
    sleep 1
fi

if [ -d "kooCAEWebAutomationServer_5001" ]; then
    cd kooCAEWebAutomationServer_5001
    # Clean up old log file to avoid permission issues
    rm -f cae_automation.log
    if [ -d "venv" ]; then
        nohup venv/bin/python app.py > cae_automation.log 2>&1 &
    else
        nohup python3 app.py > cae_automation.log 2>&1 &
    fi
    CAE_AUTO_PID=$!
    echo $CAE_AUTO_PID > .cae_automation.pid
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ CAE Automation 시작됨 (PID: $CAE_AUTO_PID, Port: 5001)${NC}"
fi


# App Service Backend (kooCAEWebServer_5000 - already started above)
# No additional backend needed
echo ""

echo ""

echo "" 

# ==================== 9. Reload Nginx ====================
echo -e "${BLUE}[9/9] Nginx 재시작 중...${NC}"
sudo nginx -t && sudo systemctl reload nginx
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Nginx 재시작 완료${NC}"
else
    echo -e "${RED}❌ Nginx 재시작 실패${NC}"
fi
echo ""


# ==================== 최종 상태 확인 ====================
echo "=========================================="
echo -e "${GREEN}✅ Production 모드 시작 완료!${NC}"
echo "=========================================="
echo ""

# VIP 주소를 YAML에서 동적으로 읽기
YAML_PATH="../my_multihead_cluster.yaml"
if [ -f "$YAML_PATH" ]; then
    VIP_ADDRESS=$(python3 -c "import yaml; config=yaml.safe_load(open('$YAML_PATH')); print(config.get('network', {}).get('vip', {}).get('address', 'localhost'))" 2>/dev/null)
    if [ -z "$VIP_ADDRESS" ]; then
        VIP_ADDRESS="localhost"
    fi
else
    # YAML이 없으면 현재 서버 IP 사용
    VIP_ADDRESS=$(hostname -I | awk '{print $1}')
fi

echo "🔗 접속 정보 (Nginx Reverse Proxy through Port 80):"
echo ""
echo -e "  ${GREEN}●${NC} 메인 포털:      http://$VIP_ADDRESS/"
echo -e "  ${GREEN}●${NC} Dashboard:       http://$VIP_ADDRESS/dashboard/"
echo -e "  ${GREEN}●${NC} VNC Service:     http://$VIP_ADDRESS/vnc/"
echo -e "  ${GREEN}●${NC} CAE Frontend:    http://$VIP_ADDRESS/cae/"
echo ""
echo "📊 Backend Services:"
echo -e "  ${BLUE}●${NC} Auth Backend:    http://localhost:4430"
echo -e "  ${BLUE}●${NC} Dashboard API:   http://localhost:5010"
echo -e "  ${BLUE}●${NC} WebSocket:       ws://localhost:5011/ws"
echo -e "  ${BLUE}●${NC} CAE Backend:     http://localhost:5000"
echo -e "  ${BLUE}●${NC} CAE Automation:  http://localhost:5001"
echo ""
echo "📝 프론트엔드 모드:"
echo -e "  ${GREEN}●${NC} Dashboard, VNC, CAE: Static files (Nginx 서빙)"
echo -e "  ${GREEN}●${NC} App Service:      http://$VIP_ADDRESS/app/"
echo -e "  ${YELLOW}●${NC} Auth Portal: Dev server (개발 중)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 사용 방법:"
echo "   1. http://$VIP_ADDRESS/ 에서 로그인"
echo "   2. 서비스 메뉴에서 원하는 서비스 선택"
echo "   3. 모든 서비스는 포트 80으로 통합 접근"
echo ""
echo "🔴 전체 종료: ./stop_complete.sh"
echo ""
