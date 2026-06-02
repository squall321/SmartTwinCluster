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

# ==================== 1. 기존 프로세스 정리 (가장 먼저) ====================
echo -e "${BLUE}[1/7] 기존 백그라운드 프로세스 정리...${NC}"

# systemd로 관리되는 모든 서비스 먼저 중지 (상태 일관성 보장)
echo "  → systemd 백엔드 서비스 중지..."
for service in "${BACKEND_SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "    $service 중지 중..."
        sudo systemctl stop "$service" 2>/dev/null || true
    fi
done

echo "  → systemd 모니터링 서비스 중지..."
for svc_name in "node_exporter" "prometheus-node-exporter" "node-exporter"; do
    if systemctl is-active --quiet "$svc_name" 2>/dev/null; then
        echo "    $svc_name 중지 중..."
        sudo systemctl stop "$svc_name" 2>/dev/null || true
    fi
done
for svc_name in "prometheus" "prometheus-server"; do
    if systemctl is-active --quiet "$svc_name" 2>/dev/null; then
        echo "    $svc_name 중지 중..."
        sudo systemctl stop "$svc_name" 2>/dev/null || true
    fi
done

# 서비스별 포트 정의 (백엔드 + 프론트엔드 dev 서버 포함)
SERVICE_PORTS=(
    # 백엔드 서비스
    "4430:auth_portal_backend"
    "5010:backend"
    "5000:cae_server"
    "5001:cae_automation"
    "5011:websocket"
    "9090:prometheus"
    "9100:node_exporter"
    # 프론트엔드 dev 서버 (vite)
    "3010:frontend_dev"
    "4431:auth_portal_frontend_dev"
    "5173:kooCAEWeb_dev"
    "5174:app_dev"
    # 기타 서비스
    "7000:saml_idp"
    "8001:cae_service"
    "8002:vnc_service"
    "8003:moonlight_frontend"
    "8004:moonlight_backend"
    "8005:webrtc_nvenc"
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

# ==================== 2. 프론트엔드 빌드 ====================
echo -e "${BLUE}[2/7] 프론트엔드 빌드 확인 중...${NC}"

# 빌드 필요 여부 자동 감지 함수
check_frontend_needs_build() {
    local frontend_dir="$1"
    local src_dir="$frontend_dir/src"
    local dist_dir="$frontend_dir/dist"

    # dist 디렉토리가 없으면 빌드 필요
    if [ ! -d "$dist_dir" ]; then
        return 0  # 빌드 필요
    fi

    # dist 디렉토리가 비어있으면 빌드 필요
    if [ -z "$(ls -A "$dist_dir" 2>/dev/null)" ]; then
        return 0  # 빌드 필요
    fi

    # src 디렉토리가 없으면 빌드 불필요 (소스 없음)
    if [ ! -d "$src_dir" ]; then
        return 1  # 빌드 불필요
    fi

    # src 내 파일 중 dist보다 새로운 파일이 있는지 확인
    local newest_src=$(find "$src_dir" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.css" -o -name "*.scss" \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
    local newest_dist=$(find "$dist_dir" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1)

    # package.json 변경 확인
    local pkg_time=$(stat -c %Y "$frontend_dir/package.json" 2>/dev/null || echo "0")

    if [ -z "$newest_src" ] || [ -z "$newest_dist" ]; then
        return 0  # 비교 불가, 빌드 필요
    fi

    # src가 dist보다 새롭거나 package.json이 dist보다 새로우면 빌드 필요
    if (( $(echo "$newest_src > $newest_dist" | bc -l) )) || (( pkg_time > ${newest_dist%.*} )); then
        return 0  # 빌드 필요
    fi

    return 1  # 빌드 불필요
}

# 프론트엔드 디렉토리 목록
FRONTEND_DIRS=(
    "frontend_3010"
    "auth_portal_4431"
    "kooCAEWeb"
)

NEEDS_BUILD=false

if [ "$REBUILD_FRONTENDS" = true ]; then
    echo "  → 강제 재빌드 모드 (--rebuild 플래그)"
    NEEDS_BUILD=true
else
    echo "  → 빌드 필요 여부 자동 감지 중..."
    for dir in "${FRONTEND_DIRS[@]}"; do
        if [ -d "$SCRIPT_DIR/$dir" ]; then
            if check_frontend_needs_build "$SCRIPT_DIR/$dir"; then
                echo "    $dir: 빌드 필요 (소스 변경 감지)"
                NEEDS_BUILD=true
            else
                echo "    $dir: 빌드 최신 상태"
            fi
        fi
    done
fi

if [ "$NEEDS_BUILD" = true ]; then
    echo "  → 프론트엔드 빌드 진행..."
    if [ -f "./build_all_frontends.sh" ]; then
        ./build_all_frontends.sh
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ 프론트엔드 빌드 실패. 계속 진행합니다...${NC}"
        else
            echo -e "${GREEN}✅ 프론트엔드 빌드 완료${NC}"
        fi
    else
        echo -e "${RED}❌ build_all_frontends.sh를 찾을 수 없습니다${NC}"
    fi
else
    echo -e "${GREEN}✅ 모든 프론트엔드 빌드가 최신 상태입니다${NC}"
fi
echo ""

# ==================== 3. systemd 서비스 설치 확인 ====================
echo -e "${BLUE}[3/7] systemd 서비스 상태 확인...${NC}"

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

# ==================== 4. Redis 확인 ====================
echo -e "${BLUE}[4/7] Redis 상태 확인...${NC}"

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

# ==================== 5. Backend 서비스 시작 (systemd) ====================
echo -e "${BLUE}[5/7] Backend 서비스 시작 (systemd)...${NC}"

# systemd 데몬 리로드 (서비스 파일 변경 시 반영)
echo "  → systemd 데몬 리로드..."
sudo systemctl daemon-reload 2>/dev/null || true

for service in "${BACKEND_SERVICES[@]}"; do
    echo -n "  → $service: "

    # 서비스 시작 (Step 1에서 이미 중지됨)
    if sudo systemctl start "$service" 2>/dev/null; then
        sleep 2
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✓ 실행 중${NC}"
        else
            echo -e "${RED}✗ 시작 실패${NC}"
            echo "    journalctl -u $service -n 10"
        fi
    else
        echo -e "${RED}✗ 시작 실패${NC}"
        # 실패 원인 출력
        journalctl -u "$service" -n 5 --no-pager 2>/dev/null || true
    fi
done
echo ""

# ==================== 6. Prometheus & Node Exporter ====================
echo -e "${BLUE}[6/7] 모니터링 서비스...${NC}"

# Node Exporter - systemd 서비스 확인 및 시작
# 여러 가능한 서비스 이름 체크
NODE_EXPORTER_SYSTEMD=""
for svc_name in "node_exporter" "prometheus-node-exporter" "node-exporter"; do
    if systemctl list-unit-files "${svc_name}.service" &>/dev/null; then
        NODE_EXPORTER_SYSTEMD="$svc_name"
        break
    fi
done

if [ -n "$NODE_EXPORTER_SYSTEMD" ]; then
    # systemd 서비스로 관리됨 - 시작 (Step 1에서 이미 중지됨)
    echo -n "  → Node Exporter ($NODE_EXPORTER_SYSTEMD): "
    if sudo systemctl start "$NODE_EXPORTER_SYSTEMD" 2>/dev/null; then
        sleep 1
        if systemctl is-active --quiet "$NODE_EXPORTER_SYSTEMD"; then
            echo -e "${GREEN}✓ 실행 중 (systemd)${NC}"
        else
            echo -e "${RED}✗ 시작 실패${NC}"
        fi
    else
        echo -e "${RED}✗ 시작 실패${NC}"
    fi
elif nc -z localhost 9100 2>/dev/null; then
    echo -e "${GREEN}✅ Node Exporter 이미 실행 중 (Port: 9100)${NC}"
elif [ -d "node_exporter_9100" ] && [ -f "node_exporter_9100/start.sh" ]; then
    # 로컬 바이너리로 실행
    cd node_exporter_9100
    ./start.sh
    cd "$SCRIPT_DIR"
    sleep 1
    if nc -z localhost 9100 2>/dev/null; then
        echo -e "${GREEN}✅ Node Exporter 시작됨 (Port: 9100)${NC}"
    else
        echo -e "${RED}❌ Node Exporter 시작 실패${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Node Exporter 없음 (선택적)${NC}"
fi

# Prometheus - systemd 서비스 확인 및 시작
PROMETHEUS_SYSTEMD=""
for svc_name in "prometheus" "prometheus-server"; do
    if systemctl list-unit-files "${svc_name}.service" &>/dev/null; then
        PROMETHEUS_SYSTEMD="$svc_name"
        break
    fi
done

if [ -n "$PROMETHEUS_SYSTEMD" ]; then
    # systemd 서비스로 관리됨 - 시작 (Step 1에서 이미 중지됨)
    echo -n "  → Prometheus ($PROMETHEUS_SYSTEMD): "
    if sudo systemctl start "$PROMETHEUS_SYSTEMD" 2>/dev/null; then
        sleep 2
        if systemctl is-active --quiet "$PROMETHEUS_SYSTEMD"; then
            echo -e "${GREEN}✓ 실행 중 (systemd)${NC}"
        else
            echo -e "${RED}✗ 시작 실패${NC}"
        fi
    else
        echo -e "${RED}✗ 시작 실패${NC}"
    fi
elif nc -z localhost 9090 2>/dev/null; then
    echo -e "${GREEN}✅ Prometheus 이미 실행 중 (Port: 9090)${NC}"
elif [ -d "prometheus_9090" ] && [ -f "prometheus_9090/start.sh" ]; then
    # 로컬 바이너리로 실행
    cd prometheus_9090
    ./start.sh
    cd "$SCRIPT_DIR"
    sleep 2
    if nc -z localhost 9090 2>/dev/null; then
        echo -e "${GREEN}✅ Prometheus 시작됨 (Port: 9090)${NC}"
    else
        echo -e "${RED}❌ Prometheus 시작 실패${NC}"
        echo "  → 로그 확인: tail -50 prometheus_9090/prometheus.log"
    fi
else
    echo -e "${YELLOW}⚠️  Prometheus 없음 (선택적)${NC}"
fi
echo ""

# ==================== 7. Nginx 도메인 반영 + 재시작 ====================
echo -e "${BLUE}[7/7] Nginx 도메인 반영 + 재시작...${NC}"

# yaml 의 web.public_url(도메인/IP) 을 읽어 nginx server_name 에 자동 반영
_YAML="$SCRIPT_DIR/../my_multihead_cluster.yaml"
[ -f "$_YAML" ] || _YAML="$SCRIPT_DIR/../my_multihead_cluster_2.yaml"
DOMAIN=$(python3 -c "
import yaml
try:
    c = yaml.safe_load(open('$_YAML')) or {}
    u = (c.get('web', {}) or {}).get('public_url', '') or ''
    u = u.replace('https://','').replace('http://','').strip()
    print(u)
except Exception: pass
" 2>/dev/null)

if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "localhost" ] && [ "$DOMAIN" != "127.0.0.1" ]; then
    echo "  → 도메인/공개주소: $DOMAIN"
    # 활성 conf 에 VNC 라우팅(vncproxy) 이 없으면 phase5 완성 템플릿으로 전체 재생성
    # (start_production 단독 실행 시 phase0 placeholder 가 active 일 수 있음 → VNC 404 방지)
    _ACTIVE_CONF=/etc/nginx/conf.d/auth-portal.conf
    if [ ! -f "$_ACTIVE_CONF" ] || ! grep -q 'vncproxy' "$_ACTIVE_CONF" 2>/dev/null; then
        echo "  → 활성 nginx conf 에 VNC 라우팅 없음 → 전체 템플릿 재생성"
        _TPL="$SCRIPT_DIR/nginx/auth-portal.conf"
        if [ -f "$_TPL" ]; then
            _PROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
            sudo bash -c "sed \
                -e 's|server_name auth.hpc.local;|server_name $DOMAIN localhost;|g' \
                -e 's|server_name _;|server_name $DOMAIN localhost;|g' \
                -e 's|/home/koopark/claude/KooSlurmInstallAutomationRefactory/|$_PROOT/|g' \
                -e 's|{{DOMAIN}}|$DOMAIN|g' -e 's|{{PUBLIC_URL}}|$DOMAIN|g' \
                '$_TPL' > '$_ACTIVE_CONF'"
            echo "    ✓ auth-portal.conf 재생성 (도메인 + VNC 라우팅 포함)"
        else
            echo "    ⚠ 템플릿 없음: $_TPL"
        fi
    fi
    # 활성 nginx site config 들에서 server_name 갱신 (도메인 + localhost 유지)
    _changed=0
    for _conf in /etc/nginx/sites-available/* /etc/nginx/conf.d/*.conf; do
        [ -f "$_conf" ] || continue
        # hpc/auth/web 관련 conf 만 (기본 default 제외)
        grep -qE "auth|hpc|web_services|dashboard|portal" "$_conf" 2>/dev/null || continue
        if grep -qE "server_name" "$_conf" 2>/dev/null; then
            # 이미 도메인 있으면 스킵
            if ! grep -qE "server_name[^;]*\b$DOMAIN\b" "$_conf" 2>/dev/null; then
                sudo cp "$_conf" "${_conf}.bak.$(date +%s)" 2>/dev/null
                # server_name 라인에 도메인을 맨 앞에 추가 (기존 토큰 보존)
                sudo sed -i -E "s|(server_name)[[:space:]]+([^;]*);|\1 $DOMAIN \2;|" "$_conf"
                # placeholder 도 치환
                sudo sed -i "s|{{DOMAIN}}|$DOMAIN|g; s|{{PUBLIC_URL}}|$DOMAIN|g" "$_conf"
                _changed=1
                echo "    ✓ server_name 갱신: $(basename "$_conf")"
            fi
        fi
    done
    # X-Frame-Options DENY 가 남아있으면 SAMEORIGIN 으로 (VNC iframe 허용)
    if grep -rqE "X-Frame-Options[^;]*DENY" /etc/nginx/ 2>/dev/null; then
        sudo find /etc/nginx -type f \( -name '*.conf' -o -path '*/sites-*/*' -o -path '*/snippets/*' \) \
            -exec sudo sed -i 's|X-Frame-Options DENY|X-Frame-Options SAMEORIGIN|g; s|X-Frame-Options "DENY"|X-Frame-Options "SAMEORIGIN"|g' {} + 2>/dev/null
        echo "    ✓ X-Frame-Options DENY → SAMEORIGIN (VNC iframe 허용)"
        _changed=1
    fi
    [ "$_changed" = "1" ] && echo "  → nginx config 갱신됨" || echo "  → 이미 도메인 반영됨 (변경 없음)"
else
    echo "  → web.public_url 미설정/localhost — nginx server_name 갱신 스킵"
fi

if sudo nginx -t > /dev/null 2>&1; then
    sudo systemctl reload nginx
    echo -e "${GREEN}✅ Nginx 재시작 완료${NC}"
else
    echo -e "${RED}❌ Nginx 설정 오류 — 백업으로 복원 가능 (.bak.*)${NC}"
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
