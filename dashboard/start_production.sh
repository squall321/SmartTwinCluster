#!/bin/bash
################################################################################
# HPC Cluster Production 시작 스크립트 (systemd)
# - 프론트엔드: Nginx를 통한 static 파일 서빙
# - 백엔드: systemd 서비스로 관리
#
# 사용법:
#   ./start_production.sh                  # 기본: 빌드 건너뛰기
#   ./start_production.sh --rebuild        # 모든 프론트엔드 재빌드
#   ./start_production.sh --skip-build     # 명시적으로 빌드 건너뛰기
#   ./start_production.sh --install        # systemd 서비스 설치 (최초 1회)
#   ./start_production.sh --reinstall      # venv 재설치 포함
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "============================================"
echo "  start_production.sh 실행됨"
echo "  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  스크립트 위치: $SCRIPT_DIR"
echo "============================================"
echo ""

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# sudo로 실행 시 실제 사용자 찾기
RUN_USER="${SUDO_USER:-$(whoami)}"
RUN_GROUP=$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")

echo "실행 사용자: $RUN_USER (그룹: $RUN_GROUP)"
echo ""

# 인자 파싱
REBUILD_FRONTENDS=false
INSTALL_SERVICES=false
REINSTALL_VENV=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild)
            REBUILD_FRONTENDS=true
            shift
            ;;
        --skip-build)
            REBUILD_FRONTENDS=false
            shift
            ;;
        --install)
            INSTALL_SERVICES=true
            shift
            ;;
        --reinstall)
            INSTALL_SERVICES=true
            REINSTALL_VENV=true
            shift
            ;;
        --help|-h)
            echo "사용법: $0 [옵션]"
            echo ""
            echo "옵션:"
            echo "  --rebuild      프론트엔드 재빌드"
            echo "  --skip-build   프론트엔드 빌드 건너뛰기 (기본)"
            echo "  --install      systemd 서비스 설치 (최초 1회)"
            echo "  --reinstall    venv 재설치 포함 설치"
            echo "  --help         도움말"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--rebuild | --skip-build | --install | --reinstall]"
            exit 1
            ;;
    esac
done

# systemd 서비스 목록 (phase5_web.sh에서 생성하는 실제 서비스 이름과 일치)
BACKEND_SERVICES=(
    "auth_backend"
    "dashboard_backend"
    "websocket_service"
    "cae_backend"
    "cae_automation"
)

echo "=========================================="
echo "🚀 HPC Cluster Production 모드 시작 (systemd)"
echo "=========================================="
echo ""

# ==================== 0. 프론트엔드 빌드 ====================
echo -e "${BLUE}[0/6] 프론트엔드 빌드 확인 중...${NC}"
if [ "$REBUILD_FRONTENDS" = true ]; then
    echo "  → 프론트엔드 재빌드 진행 (--rebuild 플래그 사용)"
    if [ -f "./build_all_frontends.sh" ]; then
        ./build_all_frontends.sh
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ 프론트엔드 빌드 실패. 계속 진행합니다...${NC}"
        fi
    else
        echo -e "${RED}❌ build_all_frontends.sh를 찾을 수 없습니다${NC}"
    fi
else
    echo "  → 프론트엔드 빌드 건너뛰기 (기존 빌드 파일 사용)"
    echo "  → 재빌드가 필요하면: ./start_production.sh --rebuild"
fi
echo ""

# ==================== 1. systemd 서비스 설치 확인 ====================
echo -e "${BLUE}[1/6] systemd 서비스 상태 확인...${NC}"

# 서비스가 설치되어 있는지 확인
SERVICES_INSTALLED=true
for service in "${BACKEND_SERVICES[@]}"; do
    if [ ! -f "/etc/systemd/system/${service}.service" ]; then
        SERVICES_INSTALLED=false
        break
    fi
done

if [ "$SERVICES_INSTALLED" = false ] || [ "$INSTALL_SERVICES" = true ]; then
    echo -e "${YELLOW}  → systemd 서비스 설치가 필요합니다.${NC}"

    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ 서비스 설치에는 root 권한이 필요합니다.${NC}"
        echo "  sudo $0 --install"
        exit 1
    fi

    echo "  → systemd 서비스 설치 중..."
    if [ "$REINSTALL_VENV" = true ]; then
        "$SCRIPT_DIR/systemd/install_services.sh" --reinstall
    else
        "$SCRIPT_DIR/systemd/install_services.sh"
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 서비스 설치 실패${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ systemd 서비스 설치 완료${NC}"
else
    echo -e "${GREEN}✅ systemd 서비스 설치됨${NC}"
fi
echo ""

# ==================== 2. Redis 확인 ====================
echo -e "${BLUE}[2/6] Redis 상태 확인...${NC}"

if pgrep -x redis-server > /dev/null; then
    echo -e "${GREEN}✅ Redis 실행 중${NC}"
else
    echo -e "${YELLOW}  → Redis 시작 중...${NC}"
    if sudo systemctl start redis-server 2>/dev/null; then
        echo -e "${GREEN}✅ Redis 시작됨${NC}"
    else
        # 수동 시작 시도
        redis-server --daemonize yes 2>/dev/null || true
        sleep 1
        if pgrep -x redis-server > /dev/null; then
            echo -e "${GREEN}✅ Redis 시작됨 (수동)${NC}"
        else
            echo -e "${RED}❌ Redis 시작 실패${NC}"
        fi
    fi
fi
echo ""

# ==================== 3. 기존 프로세스 정리 ====================
echo -e "${BLUE}[3/6] 기존 백그라운드 프로세스 정리...${NC}"

# 서비스별 포트 정의
SERVICE_PORTS=(
    "4430:auth_portal"
    "5010:backend"
    "5000:cae_server"
    "5001:cae_automation"
    "5011:websocket"
    "9090:prometheus"
    "9100:node_exporter"
)

# PID 파일 정리
PID_FILES=(
    "auth_portal_4430/logs/gunicorn.pid"
    "backend_5010/logs/gunicorn.pid"
    "kooCAEWebServer_5000/logs/gunicorn.pid"
    "kooCAEWebAutomationServer_5001/logs/gunicorn.pid"
    "MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.pid"
    "websocket_5011/.websocket.pid"
    "prometheus_9090/.prometheus.pid"
    "node_exporter_9100/.node_exporter.pid"
)

for pid_file in "${PID_FILES[@]}"; do
    if [[ -f "$SCRIPT_DIR/$pid_file" ]]; then
        rm -f "$SCRIPT_DIR/$pid_file" 2>/dev/null || sudo rm -f "$SCRIPT_DIR/$pid_file" 2>/dev/null || true
    fi
done

# 1단계: 프로세스 이름 기반 정리
echo "  → 프로세스 이름 기반 정리..."
pkill -f "gunicorn.*auth_portal_4430" 2>/dev/null || true
pkill -f "gunicorn.*backend_5010" 2>/dev/null || true
pkill -f "gunicorn.*kooCAEWebServer_5000" 2>/dev/null || true
pkill -f "gunicorn.*kooCAEWebAutomationServer_5001" 2>/dev/null || true
pkill -f "gunicorn.*backend_moonlight_8004" 2>/dev/null || true
pkill -f "websocket_5011.*python" 2>/dev/null || true
pkill -f "websocket_server_enhanced" 2>/dev/null || true

# 2단계: 포트 기반 정리 (다른 방식으로 실행된 프로세스도 정리)
echo "  → 포트 기반 정리..."
for port_info in "${SERVICE_PORTS[@]}"; do
    port="${port_info%%:*}"
    name="${port_info##*:}"

    # 해당 포트를 사용하는 프로세스 찾기
    pids=$(lsof -t -i :$port 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "    포트 $port ($name): PID $pids 종료 중..."
        for pid in $pids; do
            kill $pid 2>/dev/null || sudo kill $pid 2>/dev/null || true
        done
    fi
done

# 프로세스가 종료될 시간 확보
sleep 2

# 3단계: 강제 종료 (아직 남아있는 경우)
echo "  → 잔여 프로세스 강제 종료..."
for port_info in "${SERVICE_PORTS[@]}"; do
    port="${port_info%%:*}"
    pids=$(lsof -t -i :$port 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            kill -9 $pid 2>/dev/null || sudo kill -9 $pid 2>/dev/null || true
        done
    fi
done

sleep 1

# 4단계: 클린 상태 확인
echo "  → 클린 상태 확인..."
clean_state=true
for port_info in "${SERVICE_PORTS[@]}"; do
    port="${port_info%%:*}"
    name="${port_info##*:}"

    if lsof -i :$port > /dev/null 2>&1; then
        echo -e "    ${RED}⚠️  포트 $port ($name) 여전히 사용 중${NC}"
        lsof -i :$port 2>/dev/null | head -3
        clean_state=false
    fi
done

if [[ "$clean_state" == true ]]; then
    echo -e "${GREEN}✅ 모든 포트 정리 완료${NC}"
else
    echo -e "${YELLOW}⚠️  일부 포트가 정리되지 않았습니다. 계속 진행합니다...${NC}"
fi
echo ""

# ==================== 4. Backend 서비스 시작 (systemd) ====================
echo -e "${BLUE}[4/6] Backend 서비스 시작 (systemd)...${NC}"

for service in "${BACKEND_SERVICES[@]}"; do
    echo -n "  → $service: "

    # 서비스 재시작
    if sudo systemctl restart "$service" 2>/dev/null; then
        sleep 2
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✓ 실행 중${NC}"
        else
            echo -e "${RED}✗ 시작 실패${NC}"
            echo "    journalctl -u $service -n 10"
        fi
    else
        echo -e "${RED}✗ 재시작 실패${NC}"
    fi
done
echo ""

# ==================== 5. Prometheus & Node Exporter ====================
echo -e "${BLUE}[5/6] 모니터링 서비스...${NC}"

# Prometheus (systemd로 관리되는 경우 건너뜀)
if systemctl is-active --quiet prometheus 2>/dev/null; then
    echo -e "${GREEN}✅ Prometheus 이미 실행 중 (systemd)${NC}"
elif [ -d "prometheus_9090" ] && [ -f "prometheus_9090/start.sh" ]; then
    # 이미 실행 중인지 확인
    if nc -z localhost 9090 2>/dev/null; then
        echo -e "${GREEN}✅ Prometheus 이미 실행 중 (Port: 9090)${NC}"
    else
        cd prometheus_9090
        ./start.sh > /dev/null 2>&1
        cd "$SCRIPT_DIR"
        sleep 1
        if nc -z localhost 9090 2>/dev/null; then
            echo -e "${GREEN}✅ Prometheus 시작됨 (Port: 9090)${NC}"
        else
            echo -e "${RED}❌ Prometheus 시작 실패${NC}"
        fi
    fi
fi

# Node Exporter (systemd로 관리되는 경우 건너뜀)
if systemctl is-active --quiet node_exporter 2>/dev/null; then
    echo -e "${GREEN}✅ Node Exporter 이미 실행 중 (systemd)${NC}"
elif [ -d "node_exporter_9100" ] && [ -f "node_exporter_9100/start.sh" ]; then
    # 이미 실행 중인지 확인
    if nc -z localhost 9100 2>/dev/null; then
        echo -e "${GREEN}✅ Node Exporter 이미 실행 중 (Port: 9100)${NC}"
    else
        cd node_exporter_9100
        ./start.sh > /dev/null 2>&1
        cd "$SCRIPT_DIR"
        sleep 1
        if nc -z localhost 9100 2>/dev/null; then
            echo -e "${GREEN}✅ Node Exporter 시작됨 (Port: 9100)${NC}"
        else
            echo -e "${RED}❌ Node Exporter 시작 실패${NC}"
        fi
    fi
fi
echo ""

# ==================== 6. Nginx 재시작 ====================
echo -e "${BLUE}[6/6] Nginx 재시작...${NC}"
if sudo nginx -t > /dev/null 2>&1; then
    sudo systemctl reload nginx
    echo -e "${GREEN}✅ Nginx 재시작 완료${NC}"
else
    echo -e "${RED}❌ Nginx 설정 오류${NC}"
    sudo nginx -t
fi
echo ""

# ==================== 완료 ====================
echo "=========================================="
echo -e "${GREEN}✅ Production 모드 시작 완료! (systemd)${NC}"
echo "=========================================="
echo ""

# 외부 접속 주소를 YAML에서 동적으로 읽기
YAML_PATH="$SCRIPT_DIR/../my_multihead_cluster.yaml"
if [ -f "$YAML_PATH" ]; then
    PUBLIC_URL=$(python3 -c "
import yaml
with open('$YAML_PATH') as f:
    config = yaml.safe_load(f)
public_url = config.get('web', {}).get('public_url', '')
if public_url:
    print(public_url)
else:
    print(config.get('network', {}).get('vip', {}).get('address', 'localhost'))
" 2>/dev/null)
    if [ -z "$PUBLIC_URL" ]; then
        PUBLIC_URL="localhost"
    fi
else
    PUBLIC_URL=$(hostname -I | awk '{print $1}')
fi

echo "🔗 접속 정보 (Nginx Reverse Proxy):"
echo ""
echo "  ● 메인 포털:        http://$PUBLIC_URL/"
echo "  ● Dashboard:        http://$PUBLIC_URL/dashboard/"
echo "  ● VNC Service:      http://$PUBLIC_URL/vnc/"
echo "  ● CAE Frontend:     http://$PUBLIC_URL/cae/"
echo "  ● Moonlight:        http://$PUBLIC_URL/moonlight/"
echo ""
echo "📊 Backend Services (systemd):"
for service in "${BACKEND_SERVICES[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
    if [ "$status" = "active" ]; then
        echo -e "  ${GREEN}●${NC} $service: $status"
    else
        echo -e "  ${RED}○${NC} $service: $status"
    fi
done
echo ""
echo "🔧 관리 명령어:"
echo "  sudo systemctl status auth_backend"
echo "  sudo systemctl restart dashboard_backend"
echo "  journalctl -u websocket_service -f"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
