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

# ==================== 1. 기존 서비스 종료 ====================
echo -e "${BLUE}[1/7] 기존 서비스 종료 중...${NC}"

# 모든 관련 프로세스 강제 종료
pkill -f "auth_portal_4430.*app.py" 2>/dev/null
pkill -f "auth_portal_4431.*vite" 2>/dev/null
pkill -f "auth_portal_4431.*npm" 2>/dev/null
pkill -f "backend_5010.*app.py" 2>/dev/null
pkill -f "websocket_5011.*python" 2>/dev/null
pkill -f "frontend_3010.*vite" 2>/dev/null
pkill -f "frontend_3010.*npm" 2>/dev/null
pkill -f "vnc_service_8002.*vite" 2>/dev/null
pkill -f "vnc_service_8002.*npm" 2>/dev/null
pkill -f "kooCAEWeb_5173.*vite" 2>/dev/null
pkill -f "kooCAEWeb_5173.*npm" 2>/dev/null
pkill -f "prometheus.*9090" 2>/dev/null
pkill -f "node_exporter.*9100" 2>/dev/null
pkill -f "kooCAEWebServer_5000.*python" 2>/dev/null
pkill -f "kooCAEWebAutomationServer_5001.*python" 2>/dev/null

# 포트 강제 해제
fuser -k 3010/tcp 8002/tcp 5173/tcp 2>/dev/null

sleep 3
echo -e "${GREEN}✅ 기존 서비스 종료 완료${NC}"
echo ""

# ==================== 2. Redis 확인 ====================
echo -e "${BLUE}[2/7] Redis 확인 중...${NC}"
if ! redis-cli ping &>/dev/null; then
    echo -e "${RED}❌ Redis가 실행되지 않습니다.${NC}"
    echo "Redis를 먼저 시작해주세요: sudo systemctl start redis-server"
    exit 1
fi
echo -e "${GREEN}✅ Redis 실행 중${NC}"
echo ""

# ==================== 3. SAML-IdP 시작 ====================
echo -e "${BLUE}[3/7] SAML-IdP 시작 중...${NC}"
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
echo -e "${BLUE}[4/7] Auth Backend 시작 중...${NC}"
if pgrep -f "python.*auth_portal_4430.*app.py" > /dev/null; then
    echo -e "${YELLOW}⚠  Auth Backend가 이미 실행 중입니다.${NC}"
else
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
fi
echo ""

# ==================== 5. Auth Frontend (Dev 서버 - UI 개발용) ====================
echo -e "${BLUE}[5/7] Auth Frontend 시작 중...${NC}"
if pgrep -f "vite.*auth_portal_4431" > /dev/null; then
    echo -e "${YELLOW}⚠  Auth Frontend가 이미 실행 중입니다.${NC}"
else
    cd auth_portal_4431
    mkdir -p logs
    nohup npm run dev > logs/frontend.log 2>&1 &
    FRONTEND_PID=$!
    echo $FRONTEND_PID > logs/frontend.pid
    cd "$SCRIPT_DIR"
    sleep 5
    echo -e "${GREEN}✅ Auth Frontend 시작됨 (PID: $FRONTEND_PID, Port: 4431)${NC}"
fi
echo ""

# ==================== 6. Dashboard Backend + WebSocket ====================
echo -e "${BLUE}[6/7] Dashboard Backend + WebSocket 시작 중...${NC}"

# Dashboard Backend
if pgrep -f "backend_5010.*app.py" > /dev/null; then
    echo -e "${YELLOW}⚠  Dashboard Backend가 이미 실행 중입니다.${NC}"
else
    cd backend_5010
    nohup python3 app.py > /tmp/dashboard_backend_5010.log 2>&1 &
    DB_BACKEND_PID=$!
    echo $DB_BACKEND_PID > .backend.pid
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ Dashboard Backend 시작됨 (PID: $DB_BACKEND_PID, Port: 5010)${NC}"
fi

# WebSocket Server
if pgrep -f "websocket_5011.*python" > /dev/null; then
    echo -e "${YELLOW}⚠  WebSocket Server가 이미 실행 중입니다.${NC}"
else
    cd websocket_5011
    nohup python3 app.py > /tmp/websocket_5011.log 2>&1 &
    WS_PID=$!
    echo $WS_PID > .websocket.pid
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ WebSocket Server 시작됨 (PID: $WS_PID, Port: 5011)${NC}"
fi

# Prometheus (선택사항)
if [ -d "prometheus_9090" ] && [ -f "prometheus_9090/start.sh" ]; then
    cd prometheus_9090
    ./start.sh > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ Prometheus 시작됨 (Port: 9090)${NC}"
fi

echo ""

# ==================== 7. CAE Services ====================
echo -e "${BLUE}[7/7] CAE Services 시작 중...${NC}"

# CAE Backend (5000)
if pgrep -f "kooCAEWebServer_5000.*python" > /dev/null; then
    echo -e "${YELLOW}⚠  CAE Backend가 이미 실행 중입니다.${NC}"
else
    if [ -d "kooCAEWebServer_5000" ]; then
        cd kooCAEWebServer_5000
        if [ -d "venv" ]; then
            nohup venv/bin/python app.py > /tmp/cae_backend_5000.log 2>&1 &
        else
            nohup python3 app.py > /tmp/cae_backend_5000.log 2>&1 &
        fi
        CAE_BACKEND_PID=$!
        echo $CAE_BACKEND_PID > .cae_backend.pid
        cd "$SCRIPT_DIR"
        echo -e "${GREEN}✅ CAE Backend 시작됨 (PID: $CAE_BACKEND_PID, Port: 5000)${NC}"
    fi
fi

# CAE Automation (5001)
if pgrep -f "kooCAEWebAutomationServer_5001.*python" > /dev/null; then
    echo -e "${YELLOW}⚠  CAE Automation이 이미 실행 중입니다.${NC}"
else
    if [ -d "kooCAEWebAutomationServer_5001" ]; then
        cd kooCAEWebAutomationServer_5001
        if [ -d "venv" ]; then
            nohup venv/bin/python app.py > /tmp/cae_automation_5001.log 2>&1 &
        else
            nohup python3 app.py > /tmp/cae_automation_5001.log 2>&1 &
        fi
        CAE_AUTO_PID=$!
        echo $CAE_AUTO_PID > .cae_automation.pid
        cd "$SCRIPT_DIR"
        echo -e "${GREEN}✅ CAE Automation 시작됨 (PID: $CAE_AUTO_PID, Port: 5001)${NC}"
    fi
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
