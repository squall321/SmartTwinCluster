#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🚀 모든 서버 시작 (Production Mode)"
echo "=========================================="
echo ""
echo "🎯 모드: Production (실제 Slurm 명령 실행)"
echo "   - Backend: MOCK_MODE=false"
echo "   - WebSocket: MOCK_MODE=false"
echo "   - 실제 노드 조회, Drain/Resume 기능 사용 가능"
echo ""

# 포트 사용 중 확인 및 강제 종료 (강화 버전)
echo -e "${BLUE}🔍 포트 충돌 확인 중...${NC}"
PORTS=(3010 5000 5001 5010 5011 9100 9090)
PORT_CONFLICTS=0

# 각 포트별로 프로세스 확인 및 종료
for PORT in "${PORTS[@]}"; do
    PIDS=$(lsof -ti :$PORT 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo -e "${YELLOW}⚠️  포트 $PORT 사용 중 (PID: $PIDS)${NC}"
        PORT_CONFLICTS=$((PORT_CONFLICTS + 1))
        
        # 각 PID에 대해 종료 시도
        for PID in $PIDS; do
            # 프로세스 이름 확인
            PROC_NAME=$(ps -p $PID -o comm= 2>/dev/null || echo "unknown")
            echo -e "${YELLOW}   프로세스: $PROC_NAME (PID: $PID)${NC}"
            
            # 1차: SIGTERM으로 정상 종료 시도
            kill $PID 2>/dev/null
            sleep 0.5
            
            # 프로세스가 여전히 살아있는지 확인
            if ps -p $PID > /dev/null 2>&1; then
                # 2차: SIGKILL로 강제 종료
                echo -e "${YELLOW}   강제 종료 중...${NC}"
                kill -9 $PID 2>/dev/null
                sleep 0.3
            fi
            
            # 최종 확인
            if ps -p $PID > /dev/null 2>&1; then
                echo -e "${RED}   ✗ PID $PID 종료 실패${NC}"
            else
                echo -e "${GREEN}   ✓ PID $PID 종료 완료${NC}"
            fi
        done
    fi
done

# Prometheus와 Node Exporter는 특별히 처리
echo -e "${BLUE}🔧 특수 프로세스 정리 중...${NC}"

# Snap Prometheus 종료 (포트 충돌 방지)
echo -e "${YELLOW}⚠️  Snap Prometheus 종료 중...${NC}"
sudo snap stop prometheus 2>/dev/null && echo -e "${GREEN}   ✓ Snap Prometheus 중지됨${NC}"
sudo snap disable prometheus 2>/dev/null

# Prometheus 프로세스 강제 종료
PROM_PIDS=$(pgrep -f "prometheus.*--config.file" 2>/dev/null)
if [ -n "$PROM_PIDS" ]; then
    echo -e "${YELLOW}⚠️  Prometheus 프로세스 발견${NC}"
    for PID in $PROM_PIDS; do
        echo -e "${YELLOW}   종료 중: PID $PID${NC}"
        kill -9 $PID 2>/dev/null
    done
    PORT_CONFLICTS=$((PORT_CONFLICTS + 1))
fi

# Node Exporter 프로세스 강제 종료
NODE_EXP_PIDS=$(pgrep -f "node_exporter" 2>/dev/null)
if [ -n "$NODE_EXP_PIDS" ]; then
    echo -e "${YELLOW}⚠️  Node Exporter 프로세스 발견${NC}"
    for PID in $NODE_EXP_PIDS; do
        echo -e "${YELLOW}   종료 중: PID $PID${NC}"
        kill -9 $PID 2>/dev/null
    done
    PORT_CONFLICTS=$((PORT_CONFLICTS + 1))
fi

# Python 기반 서버들 정리 (auth_portal 제외)
PYTHON_SERVERS=$(pgrep -f "python.*app.py" 2>/dev/null | while read pid; do
    # auth_portal_4430과 auth_portal_4431은 제외
    if ! ps -p $pid -o args= | grep -q "auth_portal"; then
        echo $pid
    fi
done)
if [ -n "$PYTHON_SERVERS" ]; then
    echo -e "${YELLOW}⚠️  Python 서버 프로세스 발견${NC}"
    for PID in $PYTHON_SERVERS; do
        echo -e "${YELLOW}   종료 중: PID $PID${NC}"
        kill -9 $PID 2>/dev/null
    done
    PORT_CONFLICTS=$((PORT_CONFLICTS + 1))
fi

# Node.js 기반 서버 정리
NODE_SERVERS=$(pgrep -f "node.*server" 2>/dev/null)
if [ -n "$NODE_SERVERS" ]; then
    echo -e "${YELLOW}⚠️  Node.js 서버 프로세스 발견${NC}"
    for PID in $NODE_SERVERS; do
        echo -e "${YELLOW}   종료 중: PID $PID${NC}"
        kill -9 $PID 2>/dev/null
    done
    PORT_CONFLICTS=$((PORT_CONFLICTS + 1))
fi

# PID 파일들도 정리
echo -e "${BLUE}🔧 PID 파일 정리 중...${NC}"
find . -name "*.pid" -type f -exec rm -f {} \; 2>/dev/null

if [ $PORT_CONFLICTS -gt 0 ]; then
    echo ""
    sleep 2
    echo -e "${GREEN}✅ 포트 정리 완료 (총 $PORT_CONFLICTS개 해결)${NC}"
    
    # 최종 확인
    echo -e "${BLUE}🔍 포트 상태 최종 확인...${NC}"
    for PORT in "${PORTS[@]}"; do
        if lsof -ti :$PORT >/dev/null 2>&1; then
            echo -e "${RED}   ✗ 포트 $PORT 여전히 사용 중${NC}"
        else
            echo -e "${GREEN}   ✓ 포트 $PORT 사용 가능${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ 모든 포트 사용 가능${NC}"
fi

echo ""

# MOCK_MODE를 false로 설정
export MOCK_MODE=false

# Auth Services (must start first for nginx)
echo -e "${YELLOW}전 Step: 포트 4430, 4431 체크 및 정리...${NC}"
if [ -d "${SCRIPT_DIR}/auth_portal_4430" ]; then
    cd "${SCRIPT_DIR}/auth_portal_4430"
    echo -e "${GREEN}✅ Auth Backend 시작${NC}"
    echo "   🔗 http://localhost:4430"
    echo "   💡 venv 사용"
    ./venv/bin/python app.py > logs/auth_backend.log 2>&1 &
    AUTH_BACKEND_PID=$!
    echo "   PID: $AUTH_BACKEND_PID"
    cd "${SCRIPT_DIR}"
    echo ""
fi

if [ -d "${SCRIPT_DIR}/auth_portal_4431" ]; then
    cd "${SCRIPT_DIR}/auth_portal_4431"
    echo -e "${GREEN}✅ Auth Frontend 시작${NC}"
    echo "   🔗 http://localhost:4431"
    npm run dev > logs/auth_frontend.log 2>&1 &
    cd "${SCRIPT_DIR}"
    echo ""
fi

cd "${SCRIPT_DIR}/backend_5010" && ./start.sh && cd "${SCRIPT_DIR}"
echo ""
cd "${SCRIPT_DIR}/websocket_5011" && ./start.sh && cd "${SCRIPT_DIR}"
echo ""
cd "${SCRIPT_DIR}/frontend_3010" && ./start.sh && cd "${SCRIPT_DIR}"
echo ""

# CAE Services
[ -f "kooCAEWebServer_5000/start.sh" ] && cd "${SCRIPT_DIR}/kooCAEWebServer_5000" && ./start.sh && cd "${SCRIPT_DIR}" && echo ""
[ -f "kooCAEWebAutomationServer_5001/start.sh" ] && cd "${SCRIPT_DIR}/kooCAEWebAutomationServer_5001" && ./start.sh && cd "${SCRIPT_DIR}" && echo ""

[ -f "node_exporter_9100/start.sh" ] && cd "${SCRIPT_DIR}/node_exporter_9100" && ./start.sh && cd "${SCRIPT_DIR}" && echo ""
[ -f "prometheus_9090/start.sh" ] && cd "${SCRIPT_DIR}/prometheus_9090" && ./start.sh && cd "${SCRIPT_DIR}" && echo ""

echo "=========================================="
echo "✅ 모든 서버 시작 완료!"
echo "=========================================="
echo ""
echo "🔗 접속 정보:"
echo "  Frontend:  http://localhost:3010"
echo "  Backend:   http://localhost:5010"
echo "  WebSocket: ws://localhost:5011/ws"
echo "  Node Exporter: http://localhost:9100/metrics"
echo "  Prometheus: http://localhost:9090"
echo ""
echo "🎯 모드: 🚀 Production (MOCK_MODE=false)"
echo "   - 실제 Slurm 명령 실행"
echo "   - Node Management: 실제 노드 Drain/Resume 가능"
echo "   - sinfo, scontrol 명령 사용"
echo ""
echo "🔴 종료: ./stop_all.sh"
echo "🎭 Mock Mode로 시작: ./start_all_mock.sh"
