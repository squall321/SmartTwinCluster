#!/bin/bash
################################################################################
# HPC Cluster Production 시작 스크립트 (Gunicorn)
# - 프론트엔드: Nginx를 통한 static 파일 서빙
# - 백엔드: Gunicorn WSGI 서버로 실행
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0;33m'

echo "=========================================="
echo "🚀 HPC Cluster Production 모드 시작 (Gunicorn)"
echo "=========================================="
echo ""

# ==================== 0. 프론트엔드 빌드 ====================
echo -e "${BLUE}[0/9] 프론트엔드 빌드 중...${NC}"
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
echo -e "${BLUE}[1/9] 기존 서비스 종료 중...${NC}"

# Dev 서버 포트 강제 종료
echo "  → Dev 서버 포트 강제 종료 (3010, 8002, 5173, 5174, 8003)..."
fuser -k 3010/tcp 2>/dev/null
fuser -k 8002/tcp 2>/dev/null
fuser -k 5173/tcp 2>/dev/null
fuser -k 5174/tcp 2>/dev/null
fuser -k 8003/tcp 2>/dev/null  # Moonlight Frontend Dev Server

# Snap prometheus 종료
if command -v snap &> /dev/null; then
    echo "  → Snap Prometheus 종료 중..."
    snap stop prometheus 2>/dev/null || true
    echo "    ✓ Snap Prometheus 중지됨"
fi

echo -e "${GREEN}✅ 기존 서비스 종료 완료${NC}"
echo ""

# ==================== 2. Redis 확인 ====================
echo -e "${BLUE}[2/9] Redis 확인 중...${NC}"
if pgrep -x redis-server > /dev/null; then
    echo -e "${GREEN}✅ Redis 실행 중${NC}"
else
    echo -e "${YELLOW}⚠  Redis가 실행되지 않음. 시작을 시도합니다...${NC}"
    redis-server --daemonize yes 2>/dev/null || echo -e "${RED}❌ Redis 시작 실패${NC}"
fi
echo ""

# ==================== 3. SAML-IdP 시작 ====================
echo -e "${BLUE}[3/9] SAML-IdP 시작 중...${NC}"
if [ -d "saml_idp_8080" ]; then
    cd saml_idp_8080
    if [ -f "start.sh" ]; then
        if pgrep -f "saml_idp.*8080" > /dev/null; then
            echo -e "${YELLOW}⚠  SAML-IdP가 이미 실행 중입니다.${NC}"
        else
            ./start.sh > /dev/null 2>&1 &
            sleep 2
            echo -e "${GREEN}✅ SAML-IdP 시작됨 (Port: 8080)${NC}"
        fi
    fi
    cd "$SCRIPT_DIR"
fi
echo ""

# ==================== 4. Auth Backend (Gunicorn) ====================
echo -e "${BLUE}[4/9] Auth Backend 시작 중 (Gunicorn)...${NC}"

# 기존 Auth Backend 프로세스 정리
echo -e "${YELLOW}  → 기존 Auth Backend 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*auth_portal_4430" 2>/dev/null || true
sleep 1

# 2. 포트 4430 사용 중인 프로세스 강제 종료
fuser -k -9 4430/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "auth_portal_4430/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat auth_portal_4430/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 4430/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

cd auth_portal_4430
mkdir -p logs

# Python 캐시 삭제
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# 기존 로그 백업
if [ -f "logs/gunicorn.log" ]; then
    mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
fi

if [ -d "venv" ]; then
    nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
else
    nohup gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
fi
BACKEND_PID=$!
echo $BACKEND_PID > logs/gunicorn.pid
cd "$SCRIPT_DIR"

# 시작 확인
sleep 3
if pgrep -f "gunicorn.*auth_portal_4430" > /dev/null; then
    HEALTH_STATUS=$(curl -s http://localhost:4430/health 2>/dev/null | grep -o '"status":"healthy"' || echo "")
    if [ -n "$HEALTH_STATUS" ]; then
        echo -e "${GREEN}✅ Auth Backend 시작됨 (Gunicorn, PID: $BACKEND_PID, Port: 4430)${NC}"
        echo -e "${GREEN}   API 상태: 정상${NC}"
    else
        echo -e "${YELLOW}⚠  Auth Backend 시작됨 but API 응답 없음${NC}"
    fi
else
    echo -e "${RED}❌ Auth Backend 시작 실패 - logs/gunicorn.log 확인 필요${NC}"
fi
echo ""

# ==================== 5. Auth Frontend (Dev 서버 - UI 개발용) ====================
echo -e "${BLUE}[5/9] Auth Frontend 시작 중...${NC}"
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

# ==================== 6. Dashboard Backend (Gunicorn) ====================
echo -e "${BLUE}[6/9] Dashboard Backend + WebSocket 시작 중...${NC}"

# 기존 Dashboard Backend 프로세스 정리
echo -e "${YELLOW}  → 기존 Dashboard Backend 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*backend_5010" 2>/dev/null || true
sleep 1

# 2. 포트 5010 사용 중인 프로세스 강제 종료
fuser -k -9 5010/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "backend_5010/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat backend_5010/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 5010/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

cd backend_5010
mkdir -p logs

# Python 캐시 삭제
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# 기존 로그 백업
if [ -f "logs/gunicorn.log" ]; then
    mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
fi

if [ -d "venv" ]; then
    MOCK_MODE=false nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
else
    MOCK_MODE=false nohup gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
fi
DB_BACKEND_PID=$!
echo $DB_BACKEND_PID > logs/gunicorn.pid
cd "$SCRIPT_DIR"

# 시작 확인
sleep 3
if pgrep -f "gunicorn.*backend_5010" > /dev/null; then
    HEALTH_STATUS=$(curl -s http://localhost:5010/api/health 2>/dev/null | grep -o '"status":"healthy"' || echo "")
    if [ -n "$HEALTH_STATUS" ]; then
        echo -e "${GREEN}✅ Dashboard Backend 시작됨 (Gunicorn, PID: $DB_BACKEND_PID, Port: 5010)${NC}"
        echo -e "${GREEN}   API 상태: 정상${NC}"
    else
        echo -e "${YELLOW}⚠  Dashboard Backend 시작됨 but API 응답 없음${NC}"
    fi
else
    echo -e "${RED}❌ Dashboard Backend 시작 실패 - logs/gunicorn.log 확인 필요${NC}"
fi

# WebSocket Server (Flask dev - WebSocket용)
if pgrep -f "websocket_5011.*python" > /dev/null; then
    echo -e "${YELLOW}  → WebSocket Server 재시작 중...${NC}"
    pkill -f "websocket_5011.*python"
    sleep 1
fi

cd websocket_5011
mkdir -p logs
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

# ==================== 7. Backend 설정 확인 ====================
echo -e "${BLUE}[7/9] Backend 설정 확인 중...${NC}"
if [ ! -f "backend_5010/.env" ]; then
    echo "MOCK_MODE=false" > backend_5010/.env
    echo -e "${GREEN}✅ .env 파일 생성 완료${NC}"
fi
echo ""

# ==================== 8. Moonlight Backend (Gunicorn) ====================
echo -e "${BLUE}[8/10] Moonlight Backend 시작 중 (Gunicorn)...${NC}"

# 기존 Moonlight 프로세스 정리
echo -e "${YELLOW}  → 기존 Moonlight Backend 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*backend_moonlight_8004" 2>/dev/null || true
sleep 1

# 2. 포트 8004 사용 중인 프로세스 강제 종료
fuser -k -9 8004/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 8004/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -d "MoonlightSunshine_8004/backend_moonlight_8004" ]; then
    cd MoonlightSunshine_8004/backend_moonlight_8004
    mkdir -p logs

    # Python 캐시 삭제 (코드 변경사항 즉시 반영 위해)
    echo -e "${YELLOW}  → Python 캐시 삭제 중...${NC}"
    find . -type f -name "*.pyc" -delete 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

    # 기존 로그 백업
    if [ -f "logs/gunicorn.log" ]; then
        mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
    fi

    if [ -d "venv" ]; then
        REDIS_PASSWORD=changeme nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
    else
        REDIS_PASSWORD=changeme nohup gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
    fi
    MOONLIGHT_PID=$!
    echo $MOONLIGHT_PID > logs/gunicorn.pid

    # 시작 확인 (프로세스 + API 테스트)
    sleep 3
    if pgrep -f "gunicorn.*backend_moonlight_8004" > /dev/null; then
        # API Health Check
        HEALTH_STATUS=$(curl -s http://localhost:8004/health 2>/dev/null | grep -o '"status":"healthy"' || echo "")
        if [ -n "$HEALTH_STATUS" ]; then
            echo -e "${GREEN}✅ Moonlight Backend 시작됨 (Gunicorn, PID: $MOONLIGHT_PID, Port: 8004)${NC}"
            echo -e "${GREEN}   API 상태: 정상${NC}"
        else
            echo -e "${YELLOW}⚠  Moonlight Backend 시작됨 but API 응답 없음 - 확인 필요${NC}"
        fi
    else
        echo -e "${RED}❌ Moonlight Backend 시작 실패 - logs/gunicorn.log 확인 필요${NC}"
    fi
    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}⚠  Moonlight Backend 디렉토리 없음${NC}"
fi
echo ""

# ==================== 9. CAE Services (Gunicorn) ====================
echo -e "${BLUE}[9/10] CAE Services 시작 중 (Gunicorn)...${NC}"

# ===== CAE Backend (5000) =====
echo -e "${YELLOW}  → 기존 CAE Backend 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*kooCAEWebServer_5000" 2>/dev/null || true
sleep 1

# 2. 포트 5000 사용 중인 프로세스 강제 종료
fuser -k -9 5000/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "kooCAEWebServer_5000/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat kooCAEWebServer_5000/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 5000/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -d "kooCAEWebServer_5000" ]; then
    cd kooCAEWebServer_5000
    mkdir -p logs

    # Python 캐시 삭제
    find . -type f -name "*.pyc" -delete 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

    # 기존 로그 백업
    if [ -f "logs/gunicorn.log" ]; then
        mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
    fi

    if [ -d "venv" ]; then
        nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
    else
        nohup gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
    fi
    CAE_BACKEND_PID=$!
    echo $CAE_BACKEND_PID > logs/gunicorn.pid
    cd "$SCRIPT_DIR"

    # 시작 확인
    sleep 3
    if pgrep -f "gunicorn.*kooCAEWebServer_5000" > /dev/null; then
        echo -e "${GREEN}✅ CAE Backend 시작됨 (Gunicorn, PID: $CAE_BACKEND_PID, Port: 5000)${NC}"
    else
        echo -e "${RED}❌ CAE Backend 시작 실패 - logs/gunicorn.log 확인 필요${NC}"
    fi
fi

# ===== CAE Automation (5001) =====
echo -e "${YELLOW}  → 기존 CAE Automation 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*kooCAEWebAutomationServer_5001" 2>/dev/null || true
sleep 1

# 2. 포트 5001 사용 중인 프로세스 강제 종료
fuser -k -9 5001/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "kooCAEWebAutomationServer_5001/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat kooCAEWebAutomationServer_5001/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 5001/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -d "kooCAEWebAutomationServer_5001" ]; then
    cd kooCAEWebAutomationServer_5001
    mkdir -p logs

    # Python 캐시 삭제
    find . -type f -name "*.pyc" -delete 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

    # 기존 로그 백업
    if [ -f "logs/gunicorn.log" ]; then
        mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
    fi

    if [ -d "venv" ]; then
        nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
    else
        nohup gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
    fi
    CAE_AUTO_PID=$!
    echo $CAE_AUTO_PID > logs/gunicorn.pid
    cd "$SCRIPT_DIR"

    # 시작 확인
    sleep 3
    if pgrep -f "gunicorn.*kooCAEWebAutomationServer_5001" > /dev/null; then
        echo -e "${GREEN}✅ CAE Automation 시작됨 (Gunicorn, PID: $CAE_AUTO_PID, Port: 5001)${NC}"
    else
        echo -e "${RED}❌ CAE Automation 시작 실패 - logs/gunicorn.log 확인 필요${NC}"
    fi
fi
echo ""

# ==================== 9. Nginx 재시작 ====================
echo -e "${BLUE}[10/10] Nginx 재시작 중...${NC}"
sudo nginx -t && sudo systemctl reload nginx
echo -e "${GREEN}✅ Nginx 재시작 완료${NC}"
echo ""

echo "=========================================="
echo -e "${GREEN}✅ Production 모드 시작 완료! (Gunicorn)${NC}"
echo "=========================================="
echo ""
echo "🔗 접속 정보 (Nginx Reverse Proxy):"
echo ""
echo "  ● 메인 포털:        http://110.15.177.120/"
echo "  ● Dashboard:        http://110.15.177.120/dashboard/"
echo "  ● VNC Service:      http://110.15.177.120/vnc/"
echo "  ● CAE Frontend:     http://110.15.177.120/cae/"
echo "  ● Moonlight:        http://110.15.177.120/moonlight/"
echo ""
echo "📊 Backend Services (Gunicorn):"
echo "  ● Auth Backend:     http://localhost:4430 (Gunicorn)"
echo "  ● Dashboard API:    http://localhost:5010 (Gunicorn)"
echo "  ● WebSocket:        ws://localhost:5011/ws"
echo "  ● CAE Backend:      http://localhost:5000 (Gunicorn)"
echo "  ● CAE Automation:   http://localhost:5001 (Gunicorn)"
echo "  ● Moonlight API:    http://localhost:8004 (Gunicorn)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
