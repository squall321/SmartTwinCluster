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

# 모니터링 데몬 (phase5_web.sh가 systemd로 생성·enable함)
# step6 의 전용 로직(446~484행)이 기동을 담당하므로 BACKEND_SERVICES 에 넣지 않음
# (넣으면 step5 와 step6 가 이중 기동). 여기서는 상태/진단 표시용으로만 사용.
MONITORING_SERVICES=(
    "prometheus"
    "node_exporter"
)

# 선택적 데몬 — systemd 에 설치돼있으면 시작, 없으면 조용히 스킵
#   saml_idp(7000): SSO on 일 때만 (yaml sso.enabled 보고 조건부 포함)
# 주: cae_service(8001) 는 index.html 만 있는 죽은 서비스(npm run dev 불가) — 제외.
#     cae 는 nginx static(/cae/ → /var/www/html/cae)으로 동작하므로 8001 불필요.
OPTIONAL_SERVICES=()
# yaml sso.enabled 면 saml_idp 도 선택적 시작 대상에 추가
_SSO=$(python3 -c "
import yaml
try:
    c=yaml.safe_load(open('$SCRIPT_DIR/../my_multihead_cluster.yaml')) or {}
    print(str((c.get('sso') or {}).get('enabled', False)).lower())
except Exception: print('false')
" 2>/dev/null)
[ "$_SSO" = "true" ] && OPTIONAL_SERVICES+=("saml_idp")

echo "=========================================="
echo "🚀 HPC Cluster Production 모드 시작 (systemd)"
echo "=========================================="
echo ""

# ==================== 1. 기존 프로세스 정리 (가장 먼저) ====================
echo -e "${BLUE}[1/7] 기존 백그라운드 프로세스 정리...${NC}"

# systemd로 관리되는 모든 서비스 먼저 중지 (상태 일관성 보장)
echo "  → systemd 백엔드 서비스 중지..."
for service in "${BACKEND_SERVICES[@]}" "${OPTIONAL_SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "    $service 중지 중..."
        sudo systemctl stop "$service" 2>/dev/null || true
    fi
done
# SSO off 인데 saml_idp 가 떠있으면 중지 (불필요하게 7000 점유)
if [ "$_SSO" != "true" ] && systemctl is-active --quiet "saml_idp" 2>/dev/null; then
    echo "    saml_idp 중지 (SSO off — 불필요)..."
    sudo systemctl stop "saml_idp" 2>/dev/null || true
fi

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

# 프론트엔드 디렉토리 목록 (build_all_frontends.sh 의 실제 디렉토리명과 일치)
FRONTEND_DIRS=(
    "frontend_3010"
    "auth_portal_4431"
    "kooCAEWeb_5173"
    "moonlight_frontend_8003"
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

# ==================== 4.5 VNC 작업 디렉토리 권한 보장 (헤드 + viz 노드) ====================
# VNC 잡은 system_user(stcx)로 viz 노드에서 실행됨. 노드 로컬 /scratch/vnc_*
# 가 root 소유면 apptainer build --sandbox 실패 → 잡 exit 1.
# 헤드만 chmod 해선 안 되고 각 viz 노드에 SSH 로 적용해야 함.
echo -e "${BLUE}[4.5] VNC 작업 디렉토리 권한 보장...${NC}"
# 헤드 즉시 (공유 /shared/logs 포함)
for _d in /shared/logs /scratch/vnc_sandboxes /scratch/vnc_sessions /scratch/vnc_logs; do
    sudo mkdir -p "$_d" 2>/dev/null || true
    sudo chmod 1777 "$_d" 2>/dev/null || true
done
# viz/hybrid 노드 전체 (전용 스크립트 — yaml 기반 SSH 1777)
_FIXVNC="$SCRIPT_DIR/../fix_vnc_node_permissions.sh"
if [ -f "$_FIXVNC" ]; then
    bash "$_FIXVNC" --config "$SCRIPT_DIR/../my_multihead_cluster.yaml" --parallel 10 2>&1 | tr -d '\r' | sed 's/^/  /'
else
    echo "  ⚠ fix_vnc_node_permissions.sh 없음 — 헤드만 적용됨 (viz 노드 권한 미보장)"
fi
echo ""

# ==================== 5. Backend 서비스 시작 (systemd) ====================
echo -e "${BLUE}[5/7] Backend 서비스 시작 (systemd)...${NC}"

# systemd 데몬 리로드 (서비스 파일 변경 시 반영)
echo "  → systemd 데몬 리로드..."
sudo systemctl daemon-reload 2>/dev/null || true

# 필수 백엔드 + 선택적 데몬(설치된 것만) 모두 시작
for service in "${BACKEND_SERVICES[@]}" "${OPTIONAL_SERVICES[@]}"; do
    # 선택적 서비스는 systemd 에 설치 안 됐으면 스킵
    if [[ " ${OPTIONAL_SERVICES[*]} " == *" $service "* ]]; then
        systemctl list-unit-files "${service}.service" &>/dev/null \
            || { echo "  → $service: (미설치 — 스킵)"; continue; }
    fi
    echo -n "  → $service: "
    # dashboard_backend 는 gunicorn preload_app=True 라 앱 코드를 마스터가 메모리에
    # 캐싱한다. systemctl restart 만으로는 옛 마스터/잔존 워커가 안 죽고 옛
    # generate_vnc_job_script 가 그대로 남는 사례가 있어, 완전 종료 + .pyc 캐시
    # 제거 후 start 로 새 코드를 강제 로드한다(VNC '준비중' 반복의 근본 원인).
    # dashboard_backend 는 gunicorn preload_app=True 라 마스터가 app(vnc_api 포함)을
    # 메모리에 import 해두고 워커에 fork 한다(reload=False). 코드 갱신 = 마스터 교체가
    # 유일 경로다. systemctl restart 만으로는 옛 마스터/잔존 워커가 안 죽고 옛
    # generate_vnc_job_script 가 메모리에 남는 사례가 있다(VNC '준비중' 반복 근본원인).
    # → reset-failed → stop → gunicorn 완전소멸 확인 → pyc 제거 → (respawn 됐으면 재차
    # 소멸) → start(restart 아님) 로 새 코드를 무조건 import 시킨다.
    _svc_started_fresh=0
    if [ "$service" = "dashboard_backend" ]; then
        # 설치된 유닛은 Restart=always 라, pkill -9(SIGKILL)는 비정상종료로 간주돼
        # RestartSec 후 systemd 가 옛 마스터를 되살릴 수 있다. reset-failed 로 재기동
        # 카운터를 비우고 stop 으로 유닛을 inactive 화한다(stop 중에는 Restart 무시).
        sudo systemctl reset-failed "$service" 2>/dev/null || true
        sudo systemctl stop "$service" 2>/dev/null || true
        # gunicorn 마스터/워커가 완전히 죽을 때까지 확인(최대 10초). pgrep break 조건과
        # pkill 대상 패턴을 동일 ERE('gunicorn.*app:app')로 통일 — 0개 될 때까지 반복해야
        # 옛 preload 메모리코드가 확실히 사라진다.
        for _k in $(seq 1 10); do
            if ! pgrep -f 'gunicorn.*app:app' >/dev/null 2>&1; then break; fi
            sudo pkill -9 -f 'gunicorn.*app:app' 2>/dev/null || true
            sleep 1
        done
        # 바이트코드 캐시 제거 (옛 .pyc 가 import 되는 것 방지)
        sudo find "$SCRIPT_DIR/backend_5010" "$SCRIPT_DIR/common" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
        # SIGKILL→systemd-respawn 레이스 차단: start 전에 혹시 systemd 가 이미 옛 마스터를
        # 되살렸으면(active) start 가 no-op 이 되어 옛 코드가 남는다. 그땐 한 번 더
        # 완전히 죽이고서 start 한다(이미 inactive 면 그대로 진행).
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            sudo systemctl reset-failed "$service" 2>/dev/null || true
            sudo systemctl stop "$service" 2>/dev/null || true
            for _k in $(seq 1 10); do
                if ! pgrep -f 'gunicorn.*app:app' >/dev/null 2>&1; then break; fi
                sudo pkill -9 -f 'gunicorn.*app:app' 2>/dev/null || true
                sleep 1
            done
        fi
        # 완전히 죽은 상태에서 start → 마스터가 새로 import = 새 코드 보장
        if sudo systemctl start "$service" 2>/dev/null; then _svc_started_fresh=1; fi
    fi
    if [ "$_svc_started_fresh" = "1" ] || sudo systemctl restart "$service" 2>/dev/null; then
        sleep 2
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✓ 실행 중${NC}"
            # dashboard_backend: 새로 뜬 마스터가 정말 새 코드를 import 했는지 자가검증.
            # 마스터 시작시각이 vnc_api.py 수정시각 이후면(방금 stop→kill→start 했으니 항상
            # 그래야 정상) OK. 그렇지 않으면 옛 마스터가 살아남은 것 → 경고.
            if [ "$service" = "dashboard_backend" ]; then
                _vp="$SCRIPT_DIR/backend_5010/vnc_api.py"
                _np=$(pgrep -f 'gunicorn.*app:app' 2>/dev/null | head -1)
                if [ -n "$_np" ]; then
                    _ne=$(date -d "$(ps -o lstart= -p "$_np" 2>/dev/null)" +%s 2>/dev/null || echo 0)
                    _ve=$(stat -c '%Y' "$_vp" 2>/dev/null || echo 0)
                    if [ "$_ne" -ge "$_ve" ] 2>/dev/null; then
                        echo -e "      ${GREEN}↳ 새 마스터(PID $_np)가 vnc_api.py 이후 시작 — 새 코드 로드 확인${NC}"
                    else
                        echo -e "      ${RED}↳ 옛 마스터(PID $_np)가 살아있음 — 새 코드 미반영! 재기동 시퀀스 재확인 필요${NC}"
                    fi
                fi
            fi
        else
            echo -e "${RED}✗ 시작 실패${NC}"
            sudo journalctl -u "$service" -n 5 --no-pager 2>/dev/null | tail -5 | sed 's/^/      /'
        fi
    else
        echo -e "${RED}✗ 시작 실패${NC}"
        sudo journalctl -u "$service" -n 5 --no-pager 2>/dev/null | tail -5 | sed 's/^/      /'
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
    # data 디렉토리 권한 정리 — 반드시 prometheus 완전 정지 후 chown
    # (실행 중이면 lock/queries.active 를 잡고 있어 chown/unlink permission denied)
    _PROM_DATA="$SCRIPT_DIR/prometheus_9090/data"
    _PROM_USER=$(systemctl show -p User --value "$PROMETHEUS_SYSTEMD" 2>/dev/null)
    [ -z "$_PROM_USER" ] && _PROM_USER="$RUN_USER"
    _PROM_GROUP=$(id -gn "$_PROM_USER" 2>/dev/null || echo "$_PROM_USER")

    # 1) 확실히 정지 (systemd + 잔여 프로세스)
    sudo systemctl stop "$PROMETHEUS_SYSTEMD" 2>/dev/null || true
    { sudo pkill -9 -f "prometheus.*--config" 2>/dev/null; true; } </dev/null 2>/dev/null || true
    sleep 1

    if [ -d "$_PROM_DATA" ]; then
        # 2) data 전체 + lock/queries.active 명시 소유권 정렬 (서비스 계정)
        sudo chown -R "${_PROM_USER}:${_PROM_GROUP}" "$_PROM_DATA" 2>/dev/null || true
        # 잡고 있던 lock/queries.active 가 못 바뀌면 삭제 (재생성됨)
        sudo rm -f "$_PROM_DATA/lock" "$_PROM_DATA/queries.active" 2>/dev/null || true
        # 손상/삭제대기 블록 정리
        sudo find "$_PROM_DATA" -maxdepth 2 -name "*.tmp-for-deletion" -exec rm -rf {} + 2>/dev/null || true
        # wal/chunks_head 도 서비스 계정 소유 보장
        sudo chown -R "${_PROM_USER}:${_PROM_GROUP}" "$_PROM_DATA"/wal "$_PROM_DATA"/chunks_head 2>/dev/null || true
    fi
    sudo rm -f "$SCRIPT_DIR/prometheus_9090/.prometheus.pid" 2>/dev/null || true

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

    # SSO 모드 읽기 — 어느 nginx 템플릿이 정본인지 결정
    #   SSO on  → auth-portal.conf (/ → 4431 auth_frontend)
    #   SSO off → hpc-portal.conf  (/ → 3010 frontend)
    SSO_ENABLED=$(python3 -c "
import yaml
try:
    c = yaml.safe_load(open('$_YAML')) or {}
    print(str((c.get('sso') or {}).get('enabled', False)).lower())
except Exception: print('false')
" 2>/dev/null)
    if [ "$SSO_ENABLED" = "true" ]; then
        _ACTIVE_CONF=/etc/nginx/conf.d/auth-portal.conf
        _OTHER_CONF=/etc/nginx/conf.d/hpc-portal.conf
        _TPL="$SCRIPT_DIR/nginx/auth-portal.conf"
        _SN_FROM="server_name auth.hpc.local;"
    else
        _ACTIVE_CONF=/etc/nginx/conf.d/hpc-portal.conf
        _OTHER_CONF=/etc/nginx/conf.d/auth-portal.conf
        _TPL="$SCRIPT_DIR/nginx/hpc-portal.conf"
        _SN_FROM="server_name localhost;"
    fi
    echo "  → SSO=$SSO_ENABLED → 정본 conf: $(basename "$_ACTIVE_CONF")"

    # 충돌 방지: 반대편 conf 가 active 면 비활성화 (server_name 중복 → 502 유발)
    if [ -f "$_OTHER_CONF" ]; then
        sudo mv "$_OTHER_CONF" "${_OTHER_CONF}.disabled_$(date +%s)" 2>/dev/null \
            && echo "    ✓ 충돌 conf 비활성화: $(basename "$_OTHER_CONF")"
    fi

    # 정본 conf 에 VNC 라우팅 없거나 파일 없으면 템플릿으로 재생성
    if [ ! -f "$_ACTIVE_CONF" ] || ! grep -q 'vncproxy' "$_ACTIVE_CONF" 2>/dev/null; then
        echo "  → $(basename "$_ACTIVE_CONF") 재생성 (VNC 라우팅 + 도메인)"
        if [ -f "$_TPL" ]; then
            _PROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
            sudo bash -c "sed \
                -e 's|$_SN_FROM|server_name $DOMAIN localhost;|g' \
                -e 's|server_name auth.hpc.local;|server_name $DOMAIN localhost;|g' \
                -e 's|server_name _;|server_name $DOMAIN localhost;|g' \
                -e 's|/home/koopark/claude/KooSlurmInstallAutomationRefactory/|$_PROOT/|g' \
                -e 's|{{DOMAIN}}|$DOMAIN|g' -e 's|{{PUBLIC_URL}}|$DOMAIN|g' \
                '$_TPL' > '$_ACTIVE_CONF'"
            echo "    ✓ $(basename "$_ACTIVE_CONF") 재생성 완료"
        else
            echo "    ⚠ 템플릿 없음: $_TPL"
        fi
    fi
    # 활성 nginx site config 들에서 server_name 갱신 (도메인 + localhost 유지)
    # DOMAIN 을 정규식에 안전하게 쓰기 위해 메타문자 이스케이프 (IP의 '.' 등)
    _DOMAIN_RE=$(printf '%s' "$DOMAIN" | sed 's/[.[\*^$/]/\\&/g')
    _changed=0
    for _conf in /etc/nginx/sites-available/* /etc/nginx/conf.d/*.conf; do
        [ -f "$_conf" ] || continue
        # hpc/auth/web 관련 conf 만 (기본 default 제외)
        grep -qE "auth|hpc|web_services|dashboard|portal" "$_conf" 2>/dev/null || continue
        if grep -qE "server_name" "$_conf" 2>/dev/null; then
            # 이미 도메인 있으면 도메인 삽입은 스킵하되, 아래 '_' 정리는 항상 수행
            if ! grep -qE "server_name[^;]*(^|[[:space:]])${_DOMAIN_RE}([[:space:]]|;)" "$_conf" 2>/dev/null; then
                sudo cp "$_conf" "${_conf}.bak.$(date +%s)" 2>/dev/null
                # server_name 라인에 도메인을 맨 앞에 추가 (기존 토큰 보존)
                sudo sed -i -E "s|(server_name)[[:space:]]+([^;]*);|\1 $DOMAIN \2;|" "$_conf"
                # placeholder 도 치환
                sudo sed -i "s|{{DOMAIN}}|$DOMAIN|g; s|{{PUBLIC_URL}}|$DOMAIN|g" "$_conf"
                _changed=1
                echo "    ✓ server_name 갱신: $(basename "$_conf")"
            fi
            # bare catch-all '_' 토큰 정리 (server_name <도메인> _; → server_name <도메인>;)
            # default_server 는 listen 지시어가 담당하므로 server_name 의 '_' 는 불필요/혼란.
            if grep -qE "server_name[^;]*[[:space:]]_[[:space:]]*;|server_name[[:space:]]+_[[:space:]]*;" "$_conf" 2>/dev/null; then
                # 1) 다른 토큰과 함께 있는 '_' 제거:  server_name a b _ ;  → server_name a b;
                sudo sed -i -E "s|(server_name[^;]*[^[:space:]_])[[:space:]]+_([[:space:]]*;)|\1\2|g" "$_conf"
                # 2) '_' 만 단독으로 남은 경우 도메인으로 치환:  server_name _;  → server_name <도메인> localhost;
                sudo sed -i -E "s|(server_name)[[:space:]]+_[[:space:]]*;|\1 $DOMAIN localhost;|g" "$_conf"
                _changed=1
                echo "    ✓ server_name 의 bare '_' 정리: $(basename "$_conf")"
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
for service in "${BACKEND_SERVICES[@]}" "${MONITORING_SERVICES[@]}" "${OPTIONAL_SERVICES[@]}"; do
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
echo ""

# ==================== 자동 진단 (문제 발생 시 그대로 복사해서 분석 의뢰) ====================
echo "════════════════════════════════════════════════════════════════"
echo "🩺 자동 진단 (문제 시 아래 블록 통째로 복사)"
echo "════════════════════════════════════════════════════════════════"

echo ""
echo "── [1] 포트 LISTEN 상태 (안 떠있으면 502 원인) ──"
for _p in 3010:frontend 4430:auth_backend 4431:auth_frontend 5010:dashboard_be \
          5011:websocket 8001:cae 8002:vnc 5000:kooCAE_web 5001:kooCAE_auto \
          7000:saml_idp 9090:prometheus 9100:node_exporter; do
    _port="${_p%%:*}"; _name="${_p##*:}"
    if sudo ss -tlnp 2>/dev/null | grep -q ":${_port} "; then
        echo "  ✓ $_port ($_name) LISTEN"
    else
        echo "  ✗ $_port ($_name) 안 떠있음"
    fi
done

echo ""
echo "── [2] systemd 서비스 상태 ──"
for service in "${BACKEND_SERVICES[@]}" "${MONITORING_SERVICES[@]}" "${OPTIONAL_SERVICES[@]}"; do
    _st=$(systemctl is-active "$service" 2>/dev/null || echo unknown)
    _sub=$(systemctl show -p SubState --value "$service" 2>/dev/null)
    echo "  $service: $_st ($_sub)"
done

echo ""
echo "── [3] nginx 활성 라우팅 (location / proxy_pass / server_name) ──"
sudo nginx -T 2>/dev/null | grep -nE "server_name |location [/~]|proxy_pass|X-Frame-Options" \
    | grep -vE "#|server_name_in_redirect|server_names_hash" | head -30

echo ""
echo "── [4] nginx 설정 테스트 ──"
sudo nginx -t 2>&1 | sed 's/^/  /'

echo ""
echo "── [5] 핵심 엔드포인트 HTTP 응답 코드 (502/404 확인) ──"
for _path in / /dashboard/ /vnc/ /auth/ /cae/; do
    _code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost${_path}" 2>/dev/null || echo "ERR")
    echo "  http://localhost${_path}  → $_code"
done

echo ""
echo "── [6] nginx 에러 로그 (최근 5분만 — 옛 로그 제외) ──"
_now_epoch=$(date +%s)
_recent=$(sudo awk -v cutoff="$((_now_epoch - 300))" '
    /^[0-9]{4}\/[0-9]{2}\/[0-9]{2}/ {
        # 2026/06/03 00:16:05 형식 → epoch 비교
        split($1, d, "/"); split($2, t, ":");
        cmd="date -d \""d[1]"-"d[2]"-"d[3]" "$2"\" +%s 2>/dev/null"; cmd | getline ep; close(cmd);
        if (ep+0 >= cutoff) print
    }' /var/log/nginx/error.log 2>/dev/null | tail -10)
if [ -n "$_recent" ]; then
    echo "$_recent" | sed 's/^/  /'
else
    echo "  ✓ 최근 5분 내 nginx 에러 없음 (이전 에러는 무시)"
fi

echo ""
echo "── [7] 활성 nginx conf 파일 + vncproxy/도메인 유무 ──"
for _c in /etc/nginx/conf.d/*.conf; do
    [ -f "$_c" ] || continue
    case "$_c" in *.disabled*|*.bak*) continue;; esac
    _vnc=$(grep -qE "vncproxy" "$_c" 2>/dev/null && echo "vncproxy✓" || echo "vncproxy✗")
    _sn=$(grep -oE "server_name [^;]+;" "$_c" 2>/dev/null | head -1)
    echo "  $(basename "$_c"): $_vnc | $_sn"
done

echo ""
echo "── [8] VNC 체인 (viz 노드/이미지/엔드포인트/터널) ──"
# viz 파티션: 상태별 노드 수 (idle 이 1개 이상이어야 잡 가능)
if command -v sinfo &>/dev/null; then
    echo "  viz 파티션 상태별:"
    sinfo -h -p viz -o "    %t: %D개 (%N)" 2>/dev/null | head -5
    _viz_idle=$(sinfo -h -p viz -t idle -o "%D" 2>/dev/null | head -1)
    echo "  → 잡 가능 idle 노드: ${_viz_idle:-0}개"
else
    echo "  sinfo 없음 (slurm PATH 확인 필요)"
fi
# VNC 백엔드 엔드포인트 (vnc_api.py 실제 라우트: /health /images /nodes /sessions)
echo "  /api/vnc/health: $(curl -s --max-time 5 http://localhost:5010/api/vnc/health 2>&1 | head -c 120)"
echo "  /api/vnc/images: $(curl -s --max-time 5 http://localhost:5010/api/vnc/images 2>&1 | python3 -c 'import sys,json; d=json.load(sys.stdin); print(str(len(d.get("images",[])))+"개 이미지")' 2>/dev/null || echo '응답이상')"
echo "  /api/vnc/nodes:  $(curl -s --max-time 5 http://localhost:5010/api/vnc/nodes 2>&1 | head -c 150)"
# 활성 VNC 세션의 터널 포트가 controller localhost 에 LISTEN 중인가
echo "  noVNC 터널 포트 LISTEN (68xx/69xx):"
_tp=$(sudo ss -ltnp 2>/dev/null | grep -oE ":6[89][0-9][0-9] " | sort -u | tr '\n' ' ')
echo "    ${_tp:-(없음 — 활성 세션 없거나 터널 미생성)}"
# 실행중 VNC 잡
if command -v squeue &>/dev/null; then
    _vj=$(squeue -h -n vnc_session -o '%i %t %N' 2>/dev/null | head -3 | tr '\n' '|')
    echo "  실행중 VNC 잡: ${_vj:-없음}"
fi
# /opt/apptainers VNC sif 이미지 존재 (잡 게이트)
echo "  /opt/apptainers VNC sif: $(ls /opt/apptainers/vnc_*.sif 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ' || echo '없음')"

# ── vnc_api.py 코드 반영 여부 (실행중 백엔드가 최신 websockify 코드인가) ──
# websockify '준비중' 수정이 운영에 반영됐는지 자동확인. bash -lc 제거 여부로 판별.
_vapi="$SCRIPT_DIR/backend_5010/vnc_api.py"
# 멀티라인 판정: websockify 직전 줄에 '--env PATH'(새) 인가 'bash -lc'(옛) 인가.
# (한 줄 grep 은 역슬래시 줄바꿈을 못 잡아 오탐 → 파이썬으로 블록 검사)
_codever=$(python3 -c "
src=open('$_vapi').read()
import re
# websockify 기동 블록 추출(echo Starting ~ WEBSOCKIFY_PID)
m=re.search(r'Starting noVNC websockify.*?WEBSOCKIFY_PID', src, re.S)
blk=m.group(0) if m else ''
if '--env PATH' in blk and 'websockify --web' in blk:
    print('NEW')
elif 'bash -lc' in blk:
    print('OLD')
else:
    print('UNKNOWN')
" 2>/dev/null)
case "$_codever" in
    NEW) echo "  vnc_api.py 코드: ✓ 최신(websockify 직접 exec, --env PATH) — 반영됨" ;;
    OLD) echo "  vnc_api.py 코드: ✗ 옛버전(bash -lc 래핑) — git pull 필요!" ;;
    *)   echo "  vnc_api.py 코드: ? 판별불가 (websockify 블록 형태 확인 필요)" ;;
esac
# 실행중 backend 프로세스 시작시각 vs vnc_api.py 수정시각 (restart 누락 감지)
_bpid=$(pgrep -f 'gunicorn.*app:app' 2>/dev/null | head -1)
if [ -n "$_bpid" ]; then
    _bstart=$(ps -o lstart= -p "$_bpid" 2>/dev/null)
    _vmod=$(stat -c '%y' "$_vapi" 2>/dev/null | cut -d. -f1)
    _bepoch=$(date -d "$_bstart" +%s 2>/dev/null || echo 0)
    _vepoch=$(stat -c '%Y' "$_vapi" 2>/dev/null || echo 0)
    if [ "$_vepoch" -gt "$_bepoch" ] 2>/dev/null; then
        echo "  ⚠ backend 프로세스가 vnc_api.py 수정보다 먼저 시작됨 → 옛 코드로 동작중! (vnc_api 수정:$_vmod) sudo systemctl restart dashboard_backend"
    else
        echo "  backend 프로세스: vnc_api.py 최신 수정 이후 시작됨 (코드 반영 OK)"
    fi
fi
# ★ 런타임 코드 검증 — 파일/시작시각이 아니라 메모리에 실제 로드된 코드를 확인.
# /api/vnc/health 의 code_markers(inspect.getsource 로 노출)로 잡 제출 없이 판정.
# preload 옛코드가 메모리에 남았으면 여기서 즉시 잡힌다(파일 grep 은 못 잡는 케이스).
# 마커: ok=전부true / partial=일부만 / none=마커이전버전. 마커 개수 늘어도 안 깨지게 일반화.
# 분자=분모면 ok. 빠진 마커명도 같이 출력(어느 수정이 메모리에 안 올라왔는지 즉시 확인).
_cm=$(curl -s --max-time 5 http://localhost:5010/api/vnc/health 2>/dev/null \
    | python3 -c '
import sys,json
try:
    m=(json.load(sys.stdin).get("code_markers")) or {}
except Exception:
    m={}
if not m: print("none")
else:
    miss=[k for k,v in m.items() if not v]
    print("ok %d/%d"%(len(m),len(m)) if not miss else "partial %d/%d %s"%(len(m)-len(miss),len(m),",".join(miss)))
' 2>/dev/null)
case "$_cm" in
    ok\ *)   echo "  ★ 런타임 코드(메모리): ✓ 완전최신 ${_cm#ok } — websockify직접exec + WS_LOG헤더 + SESSION_MANAGER차단 + /ready갱신 모두 로드됨" ;;
    none|"") echo "  ★ 런타임 코드(메모리): code_markers 없음 — vnc_api.py 가 health 마커 이전 버전(git pull 필요)" ;;
    *)       echo "  ★ 런타임 코드(메모리): ✗ 일부만(${_cm#partial }) — backend 가 옛 코드 메모리 보유! 완전 재기동 필요 ([5] 재실행)" ;;
esac

# Redis 연결 상태 — VNC 세션 저장에 필수. false 면 진짜 에러까지 자동 출력
_redis_ok=$(curl -s --max-time 5 http://localhost:5010/api/vnc/health 2>/dev/null \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("redis_available"))' 2>/dev/null)
echo "  Redis 연결 (vnc 세션 저장용): redis_available=$_redis_ok"
if [ "$_redis_ok" != "True" ] && [ "$_redis_ok" != "true" ]; then
    echo "    ✗ Redis 연결 실패 — 원인 자동 진단:"
    # 1) redis 서버 직접 ping (비번 .env 에서)
    _rpw=$(grep -oP '^REDIS_PASSWORD=\K.*' "$SCRIPT_DIR/backend_5010/.env" 2>/dev/null)
    _rhost=$(grep -oP '^REDIS_HOST=\K.*' "$SCRIPT_DIR/backend_5010/.env" 2>/dev/null); _rhost="${_rhost:-localhost}"
    _rport=$(grep -oP '^REDIS_PORT=\K.*' "$SCRIPT_DIR/backend_5010/.env" 2>/dev/null); _rport="${_rport:-6379}"
    echo "      .env: HOST=$_rhost PORT=$_rport PW=$([ -n "$_rpw" ] && echo '설정됨' || echo '없음')"
    if command -v redis-cli &>/dev/null; then
        # PONG 만 추려서 성공/실패 명확히 (Warning 줄 제거)
        _p1=$(redis-cli -h "$_rhost" -p "$_rport" ${_rpw:+-a "$_rpw"} ping 2>/dev/null | grep -iE 'PONG|NOAUTH|WRONGPASS|error' | head -1)
        echo "      redis-cli ping (.env 비번): ${_p1:-무응답}"
    fi
    # 2) 서버 실제 requirepass 와 .env 비번 직접 비교 (★ 진짜 원인: 둘이 다르면 그게 문제)
    _real_pw=$(sudo grep -oP '^\s*requirepass\s+\K\S+' /etc/redis/redis.conf 2>/dev/null | tr -d '"'"'"\' | head -1)
    if [ -n "$_real_pw" ]; then
        if [ "$_real_pw" = "$_rpw" ]; then
            echo "      requirepass 비교: ✓ .env 비번 == redis.conf requirepass (비번 일치 — 원인 다른데 있음)"
        else
            echo "      requirepass 비교: ✗ 불일치! redis.conf requirepass='${_real_pw}' ≠ .env REDIS_PASSWORD='${_rpw}'"
            echo "        → 해결: .env 의 REDIS_PASSWORD 를 '${_real_pw}' 로 맞추고 dashboard_backend restart"
            # 진짜 비번으로 ping 검증
            echo "      redis-cli ping (redis.conf 비번): $(redis-cli -h "$_rhost" -p "$_rport" -a "$_real_pw" ping 2>/dev/null | grep -iE 'PONG|NOAUTH|WRONGPASS' | head -1)"
        fi
    else
        echo "      requirepass 비교: redis.conf 에서 requirepass 못읽음 (sudo 권한 또는 다른 설정파일)"
    fi
    # 3) systemd redis 상태
    echo "      redis 서비스: $(systemctl is-active redis-server 2>/dev/null || systemctl is-active redis 2>/dev/null || echo unknown)"
    # 3) vnc_api 가 찍은 진짜 에러 (Redis not available: <원인>)
    echo "      vnc_api 에러 로그:"
    sudo journalctl -u dashboard_backend --since "10 min ago" --no-pager 2>/dev/null \
        | grep -iE "Redis not available|RedisSession|VNC Redis|redis.*error|cluster" | tail -4 | sed 's/^/        /'
fi

echo ""
echo "── [9] 실패 서비스 journalctl 마지막 5줄 (active 아닌 것만) ──"
_any_fail=0
for service in "${BACKEND_SERVICES[@]}" "${MONITORING_SERVICES[@]}" "${OPTIONAL_SERVICES[@]}"; do
    systemctl list-unit-files "${service}.service" &>/dev/null || continue
    _st=$(systemctl is-active "$service" 2>/dev/null || echo unknown)
    if [ "$_st" != "active" ]; then
        _any_fail=1
        echo "  ▸ $service ($_st):"
        sudo journalctl -u "$service" -n 5 --no-pager 2>/dev/null | tail -5 | sed 's/^/      /'
    fi
done
[ "$_any_fail" = "0" ] && echo "  ✓ 모든 서비스 active (실패 없음)"

echo ""
echo "── [10] dashboard_backend 최근 5분 VNC/터널 로그 (옛 로그 제외) ──"
_d10=$(sudo journalctl -u dashboard_backend --since "5 min ago" --no-pager 2>/dev/null \
    | grep -iE "tunnel|vnc|novnc|image.*not|sbatch|partition|traceback|error" | tail -12)
if [ -n "$_d10" ]; then
    echo "$_d10" | sed 's/^/  /'
else
    echo "  (최근 5분 내 관련 로그 없음 — 정상이거나 VNC 미사용)"
fi

echo ""
echo "── [11] VNC 실제 세션 제출 테스트 (자동 — 끝나면 정리) ──"
if [ "${SKIP_VNC_TEST:-0}" = "1" ]; then
    echo "  (SKIP_VNC_TEST=1 — 스킵)"
elif ! command -v sbatch &>/dev/null; then
    echo "  (slurm 없음 — 스킵)"
else
    # 1) SSO off mock 토큰 발급 (test/login) — 응답 키: token / access_token 둘 다 시도
    # auth_backend 가 막 재시작됐으면 5초 안에 응답 못 줄 수 있어 최대 3회 재시도.
    _tok=""; _tlogin_code=""; _tlogin_body=""
    for _t in 1 2 3; do
        _tlogin_body=$(curl -s --max-time 8 -w '\n%{http_code}' -X POST http://localhost:4430/auth/test/login \
            -H "Content-Type: application/json" \
            -d '{"username":"vnctest","groups":["HPC-Users","HPC-Admins","GPU-Users"]}' 2>/dev/null)
        _tlogin_code=$(echo "$_tlogin_body" | tail -1)
        _tok=$(echo "$_tlogin_body" | sed '$d' | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("token") or d.get("access_token") or "")' 2>/dev/null)
        [ -n "$_tok" ] && break
        sleep 2
    done
    if [ -z "$_tok" ]; then
        echo "  ⚠ 토큰 발급 실패 (HTTP=$_tlogin_code) — SSO on(403)/test/login막힘/auth_backend 미기동"
        echo "    응답: $(echo "$_tlogin_body" | sed '$d' | head -c 200)"
    else
        echo "  ✓ 테스트 토큰 발급됨"
        # 2) VNC 세션 생성 요청
        _cr=$(curl -s --max-time 30 -X POST http://localhost:5010/api/vnc/sessions \
            -H "Authorization: Bearer $_tok" -H "Content-Type: application/json" \
            -d '{"image_id":"xfce4","geometry":"1280x720","duration_hours":1,"gpu_count":0}' 2>/dev/null)
        _sid=$(echo "$_cr" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)
        _jid=$(echo "$_cr" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("job_id",""))' 2>/dev/null)
        if [ -z "$_sid" ]; then
            echo "  ✗ 세션 생성 실패. 응답:"
            echo "$_cr" | head -c 400 | sed 's/^/      /'; echo
        else
            echo "  ✓ 세션 생성: session=$_sid job=$_jid"
            # 3) 잡이 RUNNING 될 때까지 최대 40초 대기
            _state=""
            for _i in $(seq 1 20); do
                _state=$(squeue -h -j "$_jid" -o "%t" 2>/dev/null | head -1)
                [ "$_state" = "R" ] && break
                [ -z "$_state" ] && { _state="GONE"; break; }
                sleep 2
            done
            echo "  잡 상태: ${_state:-알수없음} ($(squeue -h -j "$_jid" -o '%N %R' 2>/dev/null | head -1))"
            # sacct 최종 종료코드 — RUNNING 까지 갔다가 watchdog 의 exit 1 로 죽는
            # 케이스(--nv/instance start 실패)는 _state=R 이어도 ExitCode=1:0 으로 잡힌다.
            _exitcode=""
            if command -v sacct &>/dev/null; then
                _exitcode=$(sacct -n -j "${_jid}.batch" --format=ExitCode 2>/dev/null | head -1 | tr -d ' ')
                [ -z "$_exitcode" ] && _exitcode=$(sacct -n -j "$_jid" --format=ExitCode 2>/dev/null | grep -vE '^\s*$' | tail -1 | tr -d ' ')
            fi
            # GONE(RUNNING 못 됨) 또는 ExitCode 가 0:0 이 아니면(=비정상 종료) 실패 진단 출력
            if [ "$_state" != "R" ] || { [ -n "$_exitcode" ] && [ "$_exitcode" != "0:0" ]; }; then
                echo "  ✗ 잡 비정상 (state=$_state exitcode=${_exitcode:-?}) — 실패 이유 자동 진단:"
                # 잡이 실제 떨어진 노드 (sacct NodeList, 없으면 squeue %N 폴백) — ssh 로그 긁기에 먼저 필요
                _jnode=$(sacct -n -j "$_jid" --format=NodeList 2>/dev/null | grep -vE 'None|^\s*$' | head -1 | tr -d ' ')
                [ -z "$_jnode" ] && _jnode=$(squeue -h -j "$_jid" -o '%N' 2>/dev/null | head -1 | tr -d ' ')
                # --- cluster yaml + ssh 비번(cluster_info.ssh_password) + 잡노드 hostname→ip|ssh_user 해석 ---
                _JYAML="$SCRIPT_DIR/../my_multihead_cluster.yaml"
                [ -f "$_JYAML" ] || _JYAML="$SCRIPT_DIR/../my_multihead_cluster_2.yaml"
                export SSHPASS=$(python3 -c "
import yaml
c=yaml.safe_load(open('$_JYAML')) or {}
print((c.get('cluster_info') or {}).get('ssh_password',''))
" 2>/dev/null)
                _jtarget=""
                if [ -n "$_jnode" ] && [ "$_jnode" != "None" ]; then
                    _ji=$(python3 -c "
import yaml,sys
c=yaml.safe_load(open('$_JYAML')) or {}
n=c.get('nodes',{}) or {}
hn='$_jnode'
for v in n.values():
    if isinstance(v,list):
        for x in v:
            if isinstance(x,dict) and x.get('hostname')==hn:
                print('%s|%s'%(x.get('ip_address') or hn, x.get('ssh_user','koopark'))); sys.exit()
print('%s|koopark'%hn)
" 2>/dev/null)
                    _jip=${_ji%%|*}; _juser=${_ji##*|}
                    [ -z "$_jip" ] && _jip="$_jnode"; [ -z "$_juser" ] && _juser="koopark"
                    _jtarget="${_juser}@${_jip}"
                fi
                # sacct: 종료 상태 + 코드
                if command -v sacct &>/dev/null; then
                    echo "    sacct: $(sacct -n -j "$_jid" --format=State%20,ExitCode,Reason%40 2>/dev/null | head -2 | tr '\n' '|')"
                fi
                # scontrol: 상세 (실행 전 거부 이유)
                command -v scontrol &>/dev/null && \
                    scontrol show job "$_jid" 2>/dev/null | grep -oE "(JobState|Reason|ExitCode)=[^ ]+" | sed 's/^/    /'
                # sbatch --output 로그 (vnc_api: /shared/logs/vnc-<user>-<jobid>.out/.err)
                # username 은 system_user(yaml ssh_user) — 패턴으로 jobid 매칭
                echo "    잡 출력 로그 (vnc-*-${_jid}.out/.err):"
                _found_log=0
                # vnc_api VNC_LOG_DIR=/scratch/vnc_logs (신) + /shared/logs(구) 둘 다
                for _lg in /scratch/vnc_logs/vnc-*-${_jid}.err /scratch/vnc_logs/vnc-*-${_jid}.out \
                           /shared/logs/vnc-*-${_jid}.err /shared/logs/vnc-*-${_jid}.out \
                           "/scratch/vnc_sessions/$_sid"/*.log "slurm-${_jid}.out"; do
                    if [ -f "$_lg" ]; then
                        echo "      ── $_lg ──"
                        sudo tail -25 "$_lg" 2>/dev/null | sed 's/^/      /'
                        _found_log=1
                    fi
                done
                # 잡 노드 로컬 로그도 (ssh) — /scratch 는 노드-로컬이라 헤드엔 없음. 원격 잡노드를 직접 긁는다.
                if [ "$_found_log" = "0" ] && [ -n "$_jtarget" ]; then
                    _SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
                    # key-first 프로브 → 실패 시 sshpass -e 폴백 (절대 sshpass -p 금지)
                    _SSH="ssh -n $_SSHO"
                    if ! ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$_jtarget" "echo OK" &>/dev/null; then
                        if [ -n "$SSHPASS" ] && command -v sshpass &>/dev/null; then
                            _SSH="sshpass -e ssh -n $_SSHO -o PreferredAuthentications=password -o PubkeyAuthentication=no"
                        else
                            echo "      잡 노드($_jnode) SSH 인증 불가"; _SSH=""
                        fi
                    fi
                    if [ -n "$_SSH" ]; then
                        echo "      잡 노드($_jnode -> $_jtarget) 로그:"
                        # 원격: 파일별 [ -f ] 체크 후 plain tail → sudo -n → echo PW|sudo -S 3단 폴백.
                        # glob 은 heredoc 안에서 \$_g 로 원격 확장(헤드 아닌 노드에서 username 세그먼트 매칭).
                        # .err 만 있고 .out 없는 정상케이스에서도 읽히도록 ls 단일가드 대신 파일별 순회.
                        _out=$($_SSH "$_jtarget" "
_any=0
for _g in /scratch/vnc_logs/vnc-*-${_jid}.err /scratch/vnc_logs/vnc-*-${_jid}.out; do
  for _f in \$_g; do
    [ -f \"\$_f\" ] || continue
    echo \"── \$_f ──\"
    tail -25 \"\$_f\" 2>/dev/null || sudo -n tail -25 \"\$_f\" 2>/dev/null || echo '$SSHPASS' | sudo -S -p '' tail -25 \"\$_f\" 2>/dev/null
    _any=1
  done
done
[ \"\$_any\" = \"0\" ] && echo '(로그 파일 없음)'
" 2>/dev/null)
                        if [ -n "$_out" ]; then
                            echo "$_out" | sed 's/^/      /'
                            echo "$_out" | grep -q '로그 파일 없음' || _found_log=1
                        fi
                    fi
                fi
                [ "$_found_log" = "0" ] && echo "      (로그 파일 없음)"
                # 디렉토리 존재/권한 (잡 실패 흔한 원인)
                echo "    경로 점검(헤드기준 — 잡은 viz노드서 실행, 노드권한은 [4.5] 참고):"
                echo "      $(for d in /scratch/vnc_logs /scratch/vnc_sandboxes /scratch/vnc_sessions; do [ -d "$d" ] && echo "$d($(stat -c %a "$d" 2>/dev/null),$(stat -c %U "$d" 2>/dev/null))" || echo "$d(없음)"; done | tr '\n' ' ')"
                # 잡이 실제 떨어진 노드의 sandbox 권한 (있으면) — 위에서 해석한 $_SSH/$_jtarget 재사용
                if [ -n "$_jtarget" ] && [ -n "${_SSH:-}" ]; then
                    echo "      잡 노드($_jnode) /scratch/vnc_sandboxes: $($_SSH "$_jtarget" 'stat -c %a /scratch/vnc_sandboxes 2>/dev/null || echo 없음' 2>/dev/null || echo 'ssh실패')"
                fi
            fi
            # 4) 세션 상세 (novnc_url) + ready 확인
            # novnc_url 은 detail 핸들러가 잡 RUNNING 일 때만 채운다. 잡이 R 되고
            # apptainer instance start(수십초)+VNC서버 기동까지 시간이 걸리므로
            # novnc_url 이 채워질 때까지 최대 ~30초 폴링(없으면 원인 출력).
            _det=""; _nurl=""
            for _d in $(seq 1 10); do
                _det=$(curl -s --max-time 10 -H "Authorization: Bearer $_tok" \
                    "http://localhost:5010/api/vnc/sessions/$_sid" 2>/dev/null)
                _nurl=$(echo "$_det" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("novnc_url") or (d.get("session") or {}).get("novnc_url") or "")' 2>/dev/null)
                [ -n "$_nurl" ] && break
                sleep 3
            done
            echo "  novnc_url: ${_nurl:-(없음)}"
            # novnc_url 이 안 채워졌으면 detail 응답에서 원인 단서 출력 (status/node/error)
            if [ -z "$_nurl" ]; then
                echo "$_det" | python3 -c '
import sys,json
try:
    d=json.load(sys.stdin); s=d.get("session") or d
    print("    detail status=%s node=%s error=%s redis=%s"%(
        s.get("status"), s.get("node"), s.get("error"),
        d.get("redis_available")))
except Exception as e:
    print("    detail 파싱 실패: %s / 원본: %s"%(e, sys.stdin.read()[:200] if hasattr(sys.stdin,"read") else ""))
' 2>/dev/null || echo "    detail 원본: $(echo "$_det" | head -c 300)"
                echo "    (novnc_url 없음 원인 후보: ① 잡 R 직후 VNC서버 기동 전 ② Redis false 라 멀티워커 세션 불일치 ③ SSH터널 생성 실패 — 위 error/redis 확인)"
            fi
            # 5) novnc_url 의 포트가 localhost 에 실제 응답하나
            # ★ 잡이 websockify 줄까지 도달하는 데 시간이 걸린다:
            #   start_script 시작 → sleep 10 → VNC LISTEN 대기(최대 30s) → websockify 기동.
            #   즉 잡 R 직후 ~20~50초 후에야 noVNC 포트가 뜬다. 30초만 보고 포기하면
            #   실제론 정상인데 '안됨'으로 오판(테스트 타이밍 문제). 최대 ~80초 폴링.
            _np=$(echo "$_nurl" | grep -oE "/vncproxy/[0-9]+/" | grep -oE "[0-9]+")
            if [ -n "$_np" ]; then
                _hc="000"
                echo -n "  noVNC 포트 $_np 응답 대기(최대 80초, websockify 기동까지): "
                for _p in $(seq 1 16); do
                    _hc=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:$_np/vnc.html" 2>/dev/null)
                    [ "$_hc" = "200" ] && break
                    echo -n "."
                    sleep 5
                done
                echo ""
                echo "  noVNC 포트 $_np 직접응답: $_hc $([ "$_hc" = "200" ] && echo '✓ noVNC 웹페이지(정적) 응답 — ※실제 화면접속(RFB) 가능여부는 아래 [RFB 핸드셰이크]로 판정' || echo '✗ 80초 내 미응답 — 아래 진단 확인')"
            fi

            # ── (★) '준비중' 멈춤 자동 진단: /ready API + 잡노드 실제 포트 + 컨테이너 로그 ──
            # 프론트는 novnc_url 있어도 /ready=true 가 돼야 화면을 띄운다(App.tsx).
            # ready 가 false 인데 화면 안 뜨면 여기서 어느 단계인지 자동으로 짚는다.
            echo "  ── 준비중(ready) 체인 자동검증 ──"
            # /ready API 결과 (vnc_port_ready / novnc_port_ready)
            _rdy=$(curl -s --max-time 8 -H "Authorization: Bearer $_tok" \
                "http://localhost:5010/api/vnc/sessions/$_sid/ready" 2>/dev/null)
            echo "$_rdy" | python3 -c '
import sys,json
try:
    d=json.load(sys.stdin)
    print("    /ready: ready=%s vnc_port_ready=%s novnc_port_ready=%s reason=%s"%(
        d.get("ready"), d.get("vnc_port_ready"), d.get("novnc_port_ready"),
        d.get("reason") or d.get("message") or d.get("error") or ""))
except Exception as e:
    print("    /ready 파싱실패: %s"%(sys.stdin.read()[:150] if hasattr(sys.stdin,"read") else e))
' 2>/dev/null || echo "    /ready 응답: $(echo "$_rdy" | head -c 150)"
            # 잡 노드(viz)의 실제 포트 LISTEN 을 ssh 로 직접 확인 → /ready 가 틀린건지 VNC가 안뜬건지 구분
            _vp=$(echo "$_det" | python3 -c 'import sys,json; d=json.load(sys.stdin); s=d.get("session") or d; print(s.get("vnc_port",""))' 2>/dev/null)
            _vnp=$(echo "$_det" | python3 -c 'import sys,json; d=json.load(sys.stdin); s=d.get("session") or d; print(s.get("novnc_port",""))' 2>/dev/null)
            _vnode=$(squeue -h -j "$_jid" -o '%N' 2>/dev/null | head -1 | tr -d ' ')
            if [ -n "$_vnode" ] && [ "$_vnode" != "None" ]; then
                # 잡 노드 ssh user = yaml ssh_user (stcx). 키→sshpass 폴백.
                _vuser=$(python3 -c "
import yaml,sys
c=yaml.safe_load(open('$SCRIPT_DIR/../my_multihead_cluster.yaml')) or {}
n=c.get('nodes',{}) or {}
hn='$_vnode'
for v in n.values():
    if isinstance(v,list):
        for x in v:
            if isinstance(x,dict) and x.get('hostname')==hn:
                print(x.get('ssh_user','stcx')); sys.exit()
print((c.get('nodes',{}).get('controllers') or [{}])[0].get('ssh_user','stcx'))
" 2>/dev/null)
                export SSHPASS=$(python3 -c "import yaml;c=yaml.safe_load(open('$SCRIPT_DIR/../my_multihead_cluster.yaml')) or {};print((c.get('cluster_info') or {}).get('ssh_password',''))" 2>/dev/null)
                _vssho="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"
                _vssh="ssh -n $_vssho"
                ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$_vuser@$_vnode" "echo OK" &>/dev/null \
                    || { [ -n "$SSHPASS" ] && command -v sshpass &>/dev/null && _vssh="sshpass -e ssh -n $_vssho -o PreferredAuthentications=password -o PubkeyAuthentication=no"; }
                echo "    잡 노드($_vnode) 실제 포트 LISTEN (vnc=$_vp novnc=$_vnp):"
                $_vssh "$_vuser@$_vnode" "ss -ltn 2>/dev/null | grep -E ':($_vp|$_vnp)\b' || echo '      (vnc/novnc 포트 LISTEN 안됨 — 컨테이너 VNC서버 미기동)'" 2>/dev/null | tr -d '\r' | sed 's/^/      /'

                # ── (★ 'Target closed' 자동진단) Xtigervnc 직접 RFB 핸드셰이크 ──
                # 브라우저 에러 "Connection closed (code:1000, reason: Target closed)" =
                #   websockify 가 target(localhost:vnc_port=Xtigervnc)에 붙었는데 그게 닫혔다는 뜻.
                #   nc -z(LISTEN) / curl vnc.html(정적HTTP) 로는 절대 못잡는다(RFB 협상을 안하니까).
                # 노드에서 진짜 RFB 핸드셰이크를 단계별로 돌려 어디서 끊는지/완전정상인지 이분한다.
                #   - 중간에 끊김 → Xtigervnc/세션 문제 (어느 단계인지 + /tmp/Xtigervnc 로그가 이유)
                #   - ServerInit 까지 성공 → Xtigervnc 정상, 버그는 websockify/nginx/WebSocket 계층
                _RFBPROBE_B64=$(base64 -w0 <<'PYRFB'
import socket, sys, struct
port = int(sys.argv[1])
def recv_n(s, n):
    b = b""
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise EOFError("서버가 %d바이트 중 %d만 보내고 닫음" % (n, len(b)))
        b += c
    return b
def fail(step, e):
    print("RFB ✗ [%s] 에서 끊김/실패: %s" % (step, e))
    print("→ Xtigervnc 가 RFB '%s' 단계에서 연결을 닫음 = 브라우저 'Target closed' 의 정체" % step)
    print("→ 같은 잡의 /tmp/Xtigervnc_*.log (아래) 에서 서버측 사유 확인")
    sys.exit(2)
try:
    s = socket.create_connection(("127.0.0.1", port), timeout=5); s.settimeout(5)
except Exception as e:
    print("RFB ✗ TCP 연결자체 실패(%s) — 포트는 LISTEN 인데 connect 안됨" % e); sys.exit(2)
try: pv = recv_n(s, 12)
except Exception as e: fail("ProtocolVersion수신", e)
print("RFB ✓ ProtocolVersion: %r" % pv)
if not pv.startswith(b"RFB "):
    print("RFB ✗ 배너가 'RFB ' 아님 → Xtigervnc 가 아니거나 비정상 출력"); sys.exit(2)
try: s.sendall(pv)
except Exception as e: fail("ProtocolVersion송신", e)
try: sec = recv_n(s, 1)
except Exception as e: fail("SecurityTypes수신", e)
ntypes = sec[0]
if ntypes == 0:
    try:
        L = struct.unpack(">I", recv_n(s, 4))[0]; reason = recv_n(s, L)
        print("RFB ✗ 서버가 보안협상 거부: %r" % reason)
    except Exception as e: fail("실패사유수신", e)
    sys.exit(2)
try: types = recv_n(s, ntypes)
except Exception as e: fail("SecurityTypes목록수신", e)
print("RFB ✓ SecurityTypes(%d): %r" % (ntypes, list(types)))
if 1 not in types:
    print("RFB ✗ None(1) 보안타입 미제공 %r → noVNC 인증불일치로 끊김" % list(types)); sys.exit(2)
try: s.sendall(b"\x01")
except Exception as e: fail("보안타입선택(None)송신", e)
try: code = struct.unpack(">I", recv_n(s, 4))[0]
except Exception as e: fail("SecurityResult수신", e)
if code != 0:
    print("RFB ✗ SecurityResult 실패(code=%d)" % code); sys.exit(2)
print("RFB ✓ SecurityResult OK(None 인증통과)")
try: s.sendall(b"\x01")
except Exception as e: fail("ClientInit송신", e)
try:
    si = recv_n(s, 24); w, h = struct.unpack(">HH", si[:4])
except Exception as e: fail("ServerInit수신", e)
print("RFB ✓✓✓ ServerInit 완료 — 화면 %dx%d. Xtigervnc 완전정상!" % (w, h))
print("=> RFB 전구간 성공. 'Target closed' 는 Xtigervnc 아님 →")
print("   websockify/nginx/WebSocket 계층 문제 (아래 websockify WS테스트 + 로그 확인)")
s.close()
PYRFB
)
                echo "    ── [RFB 핸드셰이크] Xtigervnc 직접검증 (localhost:$_vp) — 'Target closed' 원인 이분 ──"
                $_vssh "$_vuser@$_vnode" "echo $_RFBPROBE_B64 | base64 -d | python3 - $_vp 2>&1" 2>/dev/null | tr -d '\r' | sed 's/^/      /'
                echo "    ── [websockify WS업그레이드] noVNC 포트 $_vnp (101=정상, 그외=WS핸들링 문제) ──"
                $_vssh "$_vuser@$_vnode" "curl -s -o /dev/null -w 'HTTP %{http_code}' --max-time 5 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Version: 13' http://127.0.0.1:$_vnp/websockify 2>/dev/null; echo" 2>/dev/null | tr -d '\r' | sed 's/^/      /'

                echo "    apptainer instance + VNC/websockify 로그 tail:"
                $_vssh "$_vuser@$_vnode" "apptainer instance list 2>/dev/null | tail -3; echo '--- websockify 프로세스(ps) ---'; ps -ef | grep -E 'websockif[y]' || echo '  (websockify 프로세스 없음 → 기동 안됨/즉사)'; echo '--- 잡노드 /tmp 환경(noexec/private/권한 — 개발↔서버 차이 점검) ---'; mount 2>/dev/null | grep -E ' /tmp ' || echo '  (/tmp 별도 마운트 아님=루트와 공유)'; ls -ld /tmp /tmp/runtime-root 2>/dev/null; echo '--- 잡 .out (websockify 영역 도달여부) ---'; tail -25 /scratch/vnc_logs/vnc-*-${_jid}.out 2>/dev/null || echo '  (잡 .out 없음)'; echo '--- vnc 로그 ---'; tail -12 /scratch/vnc_logs/vnc-*-${_jid}.err 2>/dev/null; echo '--- websockify 로그파일 존재/권한 ---'; ls -la /scratch/vnc_logs/websockify-*-${_vnp}.log 2>/dev/null || echo '  (websockify 로그파일 자체가 없음 → 기동 라인이 실행 안됨/옛코드)'; echo '--- websockify 로그 내용 ---'; tail -15 /scratch/vnc_logs/websockify-*-${_vnp}.log 2>/dev/null; echo '--- 컨테이너 내부 vnc 로그(start_vnc.sh=xfce4-session 출력) ---'; tail -10 /tmp/vnc_*_*.log 2>/dev/null; echo '--- Xtigervnc 서버 로그 (RFB 닫는 이유/세션크래시 — Target closed 핵심) ---'; tail -25 /tmp/Xtigervnc_*.log 2>/dev/null || echo '  (/tmp/Xtigervnc_*.log 없음)'; echo '--- xfce4-session/Xtigervnc 생존(instance 내부) ---'; for inst in \$(apptainer instance list 2>/dev/null | awk 'NR>1{print \$1}'); do echo \"  [\$inst]\"; apptainer exec instance://\$inst sh -c 'pgrep -a Xtigervnc; pgrep -a xfce4-session || echo \"    xfce4-session 죽음/없음\"' 2>/dev/null; done" 2>/dev/null | tr -d '\r' | sed 's/^/      /'
                # 잡이 실제 사용한 sbatch 스크립트로 옛/새 코드 명확 판정
                # (백엔드 코드는 최신이어도 gunicorn 이 옛 generate_vnc_job_script 를
                #  메모리에 들고 있으면 제출 sbatch 는 옛버전 → WS_LOG 헤더 유무로 확정)
                _jscript=$(ls -t /tmp/vnc_job_*.sh 2>/dev/null | head -1)
                if [ -n "$_jscript" ]; then
                    echo "      ── 실제 제출 sbatch($_jscript) 새코드 마커 판정 ──"
                    # 최신 코드의 두 마커: WS_LOG 헤더(websockify 수정) + SESSION_MANAGER=(XFCE 검은화면 수정)
                    _has_wslog=$(grep -qc 'echo "=== websockify launch' "$_jscript" 2>/dev/null && echo 1 || echo 0)
                    _has_sm=$(grep -qc 'SESSION_MANAGER=,DBUS' "$_jscript" 2>/dev/null && echo 1 || echo 0)
                    if [ "$_has_wslog" = "1" ] && [ "$_has_sm" = "1" ]; then
                        echo "        ✓ 완전 최신 코드 (WS_LOG 헤더 + SESSION_MANAGER 차단 둘 다) — 백엔드 새코드 확정"
                    elif [ "$_has_wslog" = "1" ]; then
                        echo "        △ WS_LOG 는 있으나 SESSION_MANAGER 차단 없음 — vnc_api.py 가 cf735e8 이전 (git pull 필요)"
                    elif grep -q 'bash -lc' "$_jscript" 2>/dev/null; then
                        echo "        ✗ 옛 코드(bash -lc) — 백엔드가 옛 generate_vnc_job_script 메모리 보유 (이번 [5] 완전재기동으로 풀려야 함)"
                    else
                        echo "        ? 마커 불일치 — 실행줄 직접 확인:"
                    fi
                    grep -nE 'websockify|WS_LOG=|--env PATH|SESSION_MANAGER|bash -lc' "$_jscript" 2>/dev/null | head -10 | sed 's/^/          /'
                fi
                # 컨트롤러에 터널 포트 떴나
                echo "    컨트롤러 터널 포트($_vnp) LISTEN: $(ss -ltn 2>/dev/null | grep -qE ":$_vnp\b" && echo '✓ 떠있음' || echo '✗ 없음(SSH터널 미생성)')"
            fi
            echo "  ── 판정: 포트 LISTEN✗=컨테이너VNC미기동 / 포트O+ready✗=ready체크(lsof/ssh)버그 / 터널✗=SSH터널실패 ──"

            # 6) 테스트 세션 정리 (잡 취소)
            curl -s --max-time 10 -X DELETE -H "Authorization: Bearer $_tok" \
                "http://localhost:5010/api/vnc/sessions/$_sid" >/dev/null 2>&1
            scancel "$_jid" 2>/dev/null
            echo "  ✓ 테스트 세션 정리됨 (job $_jid 취소)"
        fi
    fi
fi

echo "════════════════════════════════════════════════════════════════"
echo "🩺 진단 끝 — 위 [1]~[11] 블록을 복사해서 문제 분석 요청"
echo "════════════════════════════════════════════════════════════════"
