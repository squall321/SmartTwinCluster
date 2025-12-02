#!/bin/bash
# 전체 시스템 통합 종료 스크립트

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🛑 HPC Cluster 전체 시스템 종료"
echo "=========================================="
echo ""

# ==================== 1. SSH 터널 정리 ====================
echo -e "${BLUE}[1/5] SSH 터널 정리 중...${NC}"
SSH_TUNNELS=$(ps aux | grep "ssh.*-L.*localhost:.*" | grep -v grep | awk '{print $2}')
if [ -n "$SSH_TUNNELS" ]; then
    echo "$SSH_TUNNELS" | xargs -r kill 2>/dev/null
    echo -e "${GREEN}✅ SSH 터널 종료됨${NC}"
else
    echo -e "${YELLOW}⚠  실행 중인 SSH 터널 없음${NC}"
fi
echo ""

# ==================== 2. Phase 1 종료 ====================
echo -e "${BLUE}[2/5] Phase 1 종료 중...${NC}"
if [ -f "./stop_phase1.sh" ]; then
    ./stop_phase1.sh
fi
echo ""

# ==================== 3. Phase 2-4 종료 ====================
echo -e "${BLUE}[3/5] Phase 2-4 종료 중...${NC}"
if [ -f "./stop_all.sh" ]; then
    ./stop_all.sh
fi
echo ""

# ==================== 4. VNC Service 종료 ====================
echo -e "${BLUE}[4/5] VNC Service 종료 중...${NC}"
if [ -f "vnc_service_8002/.vnc_service.pid" ]; then
    kill $(cat vnc_service_8002/.vnc_service.pid) 2>/dev/null
    rm -f vnc_service_8002/.vnc_service.pid
    echo -e "${GREEN}✅ VNC Service 종료${NC}"
fi

# CAE Services 종료
echo -e "${BLUE}CAE Services 종료 중...${NC}"

# CAE Backend 5000
if [ -f "kooCAEWebServer_5000/.cae_backend.pid" ]; then
    kill $(cat kooCAEWebServer_5000/.cae_backend.pid) 2>/dev/null
    rm -f kooCAEWebServer_5000/.cae_backend.pid
    echo -e "${GREEN}✅ CAE Backend (5000) 종료${NC}"
fi

# CAE Automation 5001
if [ -f "kooCAEWebAutomationServer_5001/.cae_automation.pid" ]; then
    kill $(cat kooCAEWebAutomationServer_5001/.cae_automation.pid) 2>/dev/null
    rm -f kooCAEWebAutomationServer_5001/.cae_automation.pid
    echo -e "${GREEN}✅ CAE Automation (5001) 종료${NC}"
fi

# CAE Frontend 5173
if [ -f "kooCAEWeb_5173/.cae_frontend.pid" ]; then
    kill $(cat kooCAEWeb_5173/.cae_frontend.pid) 2>/dev/null
    rm -f kooCAEWeb_5173/.cae_frontend.pid
    echo -e "${GREEN}✅ CAE Frontend (5173) 종료${NC}"
fi

# ==================== 5. 남은 프로세스 정리 ====================
echo ""
echo -e "${BLUE}[5/5] 남은 프로세스 정리 중...${NC}"

# Backend 서비스
pkill -f "auth_portal_4430.*app.py" 2>/dev/null && echo "  → Auth Backend 종료"
pkill -f "backend_5010.*app.py" 2>/dev/null && echo "  → Dashboard Backend 종료"
pkill -f "websocket_5011.*python" 2>/dev/null && echo "  → WebSocket Server 종료"
pkill -f "kooCAEWebServer_5000.*app.py" 2>/dev/null && echo "  → CAE Backend 종료"
pkill -f "kooCAEWebAutomationServer_5001.*app.py" 2>/dev/null && echo "  → CAE Automation 종료"

# Frontend Dev 서버 (있다면)
pkill -f "auth_portal_4431.*vite" 2>/dev/null && echo "  → Auth Frontend 종료"
pkill -f "frontend_3010.*vite" 2>/dev/null && echo "  → Dashboard Frontend Dev 종료"
pkill -f "vnc_service_8002.*vite" 2>/dev/null && echo "  → VNC Service Dev 종료"
pkill -f "kooCAEWeb_5173.*vite" 2>/dev/null && echo "  → CAE Frontend Dev 종료"

# 모니터링
pkill -f "prometheus.*9090" 2>/dev/null && echo "  → Prometheus 종료"
pkill -f "node_exporter.*9100" 2>/dev/null && echo "  → Node Exporter 종료"

# 추가 SSH 터널 정리 (혹시 남아있는 것)
pkill -f "ssh.*-L.*6[0-9][0-9][0-9].*192.168.122" 2>/dev/null && echo "  → 남은 SSH 터널 정리"

sleep 2
echo -e "${GREEN}✅ 프로세스 정리 완료${NC}"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ 전체 시스템 종료 완료!${NC}"
echo "=========================================="
echo ""
echo "💡 다시 시작하려면: ./start_complete.sh"
echo ""
