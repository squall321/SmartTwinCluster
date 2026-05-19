#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 옵션 파싱
CLUSTER_YAML="${REPO_ROOT}/my_multihead_cluster.yaml"
BUILD_MODE="auto"   # auto | force | skip
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)        CLUSTER_YAML="$2"; shift 2 ;;
        --config=*)      CLUSTER_YAML="${1#*=}"; shift ;;
        --force-build)   BUILD_MODE="force"; shift ;;
        --skip-build)    BUILD_MODE="skip"; shift ;;
        -h|--help)
            echo "Usage: $0 [--config <cluster.yaml>] [--force-build|--skip-build]"
            echo "  --config <path>   클러스터 YAML (기본: my_multihead_cluster.yaml)"
            echo "  --force-build     변경 여부와 무관하게 모든 프론트엔드 빌드"
            echo "  --skip-build      빌드 감지 스킵 (기존 dist 사용)"
            echo "  (기본) auto       src 변경 감지 시 자동 빌드"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# 상대경로면 절대경로 변환
[[ "$CLUSTER_YAML" != /* ]] && CLUSTER_YAML="$(cd "$(dirname "$CLUSTER_YAML")" && pwd)/$(basename "$CLUSTER_YAML")"

if [ ! -f "$CLUSTER_YAML" ]; then
    echo -e "\033[0;31m❌ 클러스터 YAML을 찾을 수 없음: $CLUSTER_YAML\033[0m"
    exit 1
fi

export CLUSTER_YAML_PATH="$CLUSTER_YAML"
export CLUSTER_CONFIG_PATH="$CLUSTER_YAML"
echo -e "\033[0;34m📄 Cluster YAML: $CLUSTER_YAML\033[0m"

# 외부 접속 주소: YAML public_url(도메인/IP) 우선 → hostname -I
HOST_IP=""
SSL_CERT_PATH=""
SSL_KEY_PATH=""
if command -v python3 >/dev/null 2>&1; then
    eval $(python3 -c "
import yaml
try:
    with open('$CLUSTER_YAML') as f: c = yaml.safe_load(f)
    web = c.get('web', {}) or {}
    pub = c.get('access', {}).get('public_url') or c.get('public_url') or web.get('public_url') or ''
    ssl = web.get('ssl', {}) or {}
    print(f'HOST_IP=\"{pub}\"')
    print(f'SSL_CERT_PATH=\"{ssl.get(\"cert_path\",\"\")}\"')
    print(f'SSL_KEY_PATH=\"{ssl.get(\"key_path\",\"\")}\"')
except Exception: pass
" 2>/dev/null)
fi
[ -z "$HOST_IP" ] && HOST_IP="$(hostname -I | awk '{print $1}')"
[ -z "$HOST_IP" ] && HOST_IP="localhost"

# 도메인 vs IP 판별
IS_DOMAIN=0
REAL_IP=""
if [[ "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IS_DOMAIN=0
    REAL_IP="$HOST_IP"
else
    IS_DOMAIN=1
    REAL_IP=$(getent ahosts "$HOST_IP" 2>/dev/null | awk '{print $1}' | head -1)
    [ -z "$REAL_IP" ] && REAL_IP="$(hostname -I | awk '{print $1}')"
fi
echo -e "\033[0;34m🌐 외부 접속 주소: $HOST_IP $([ "$IS_DOMAIN" = "1" ] && echo "(도메인, IP=$REAL_IP)" || echo "(IP)")\033[0m"

# 오프라인 APT 저장소 보장 (의존성 해결용)
ensure_offline_apt_repo() {
    local repo_list="/etc/apt/sources.list.d/offline-local.list"
    [ -f "$repo_list" ] && return 0
    local apt_dir=""
    for d in "${REPO_ROOT}/offline_packages_2404/apt_packages" "${REPO_ROOT}/offline_packages/apt_packages"; do
        [ -f "$d/Packages.gz" ] && apt_dir="$d" && break
    done
    [ -z "$apt_dir" ] && { echo -e "\033[1;33m⚠️ 오프라인 apt 저장소 디렉토리 없음 (Packages.gz)\033[0m"; return 1; }
    echo -e "\033[0;34m📦 오프라인 APT 저장소 등록: $apt_dir\033[0m"
    echo "deb [trusted=yes] file://$apt_dir ./" | sudo tee "$repo_list" >/dev/null
    sudo apt-get update -o Dir::Etc::sourcelist="$repo_list" \
        -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null \
        || sudo apt-get update 2>/dev/null || true
}
ensure_offline_apt_repo

# 시스템 python venv 패키지 보장 (24.04에서 venv 재생성 가능하게)
if ! /usr/bin/python3 -c "import ensurepip" 2>/dev/null; then
    SYS_PY=$(/usr/bin/python3 -c "import sys;print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    echo -e "\033[1;33m🔧 python${SYS_PY}-venv 미설치 → offline dpkg 설치\033[0m"
    APT_DIR="${REPO_ROOT}/offline_packages_2404/apt_packages"
    [ ! -d "$APT_DIR" ] && APT_DIR="${REPO_ROOT}/offline_packages/apt_packages"
    if [ -d "$APT_DIR" ]; then
        VENV_DEBS=()
        for pat in "python3-pip-whl_*.deb" "python${SYS_PY}-venv_*.deb" "python3-venv_*.deb"; do
            f=$(ls "$APT_DIR"/$pat 2>/dev/null | tail -1)
            [ -n "$f" ] && VENV_DEBS+=("$f")
        done
        if [ ${#VENV_DEBS[@]} -gt 0 ]; then
            if sudo apt install -y "${VENV_DEBS[@]}" 2>/dev/null; then
                echo -e "\033[0;32m   ✓ venv 패키지 설치 완료 (apt)\033[0m"
            elif sudo dpkg -i --force-depends "${VENV_DEBS[@]}" 2>/dev/null; then
                echo -e "\033[0;32m   ✓ venv 패키지 설치 완료 (dpkg --force-depends)\033[0m"
            else
                echo -e "\033[0;31m   ⚠️ venv 패키지 설치 실패\033[0m"
            fi
        fi
    fi
fi

echo "=========================================="
echo "🚀 모든 서버 시작 (Production Mode)"
echo "=========================================="
echo ""

# ── 프론트엔드 빌드 변경 감지 ──────────────────────────────────────
# 비교 대상: src/, package.json, vite/tsconfig vs dist/index.html AND nginx 배포본
declare -A NGINX_PATHS=(
    ["auth_portal_4431"]="/var/www/html/auth_portal"
    ["frontend_3010"]="/var/www/html/dashboard"
    ["vnc_service_8002"]="/var/www/html/vnc_service_8002"
    ["moonlight_frontend_8003"]="/var/www/html/moonlight"
    ["kooCAEWeb_5173"]="/var/www/html/cae"
    ["app_5174"]="/var/www/html/app_5174"
)

needs_rebuild() {
    local fe="$1"
    local dir="${SCRIPT_DIR}/${fe}"
    local nginx_idx="${NGINX_PATHS[$fe]}/index.html"
    # dist 또는 nginx 배포본이 없으면 빌드
    [ ! -f "$dir/dist/index.html" ] && return 0
    [ ! -f "$nginx_idx" ] && return 0
    # src/config가 dist보다 최신이면 빌드
    find "$dir/src" "$dir/index.html" "$dir/package.json" \
        "$dir/vite.config.ts" "$dir/vite.config.js" "$dir/tailwind.config.js" "$dir/tsconfig.json" \
        "$dir/.env" "$dir/.env.production" \
        -type f -newer "$dir/dist/index.html" -print -quit 2>/dev/null | grep -q . && return 0
    # dist가 nginx 배포본보다 최신이면 빌드(배포 누락)
    [ "$dir/dist/index.html" -nt "$nginx_idx" ] && return 0
    return 1
}

if [ "$BUILD_MODE" != "skip" ]; then
    FRONTENDS=("auth_portal_4431" "frontend_3010" "vnc_service_8002" "moonlight_frontend_8003" "kooCAEWeb_5173" "app_5174")
    TO_BUILD=()
    if [ "$BUILD_MODE" = "force" ]; then
        TO_BUILD=("${FRONTENDS[@]}")
        echo -e "${YELLOW}🔨 --force-build: 모든 프론트엔드 빌드 강제${NC}"
    else
        echo -e "${BLUE}🔍 프론트엔드 빌드 변경 감지 중...${NC}"
        for fe in "${FRONTENDS[@]}"; do
            [ ! -d "${SCRIPT_DIR}/${fe}" ] && continue
            if needs_rebuild "$fe"; then
                TO_BUILD+=("$fe")
                echo -e "${YELLOW}   • ${fe}: 변경 감지${NC}"
            else
                echo -e "${GREEN}   • ${fe}: 최신${NC}"
            fi
        done
    fi
    if [ ${#TO_BUILD[@]} -gt 0 ]; then
        echo -e "${BLUE}🔨 빌드 실행: ${TO_BUILD[*]}${NC}"
        for fe in "${TO_BUILD[@]}"; do
            "${SCRIPT_DIR}/build_all_frontends.sh" --frontend "$fe" || {
                echo -e "${RED}❌ ${fe} 빌드 실패${NC}"; exit 1; }
        done
        echo -e "${GREEN}✅ 빌드 완료${NC}"
    fi
    echo ""
fi
# ────────────────────────────────────────────────────────────────

# ── Nginx 443 보장 (sites-enabled 심볼릭 + SSL 인증서 + 시작/리로드) ────
echo -e "${BLUE}🔧 Nginx 443 상태 확인...${NC}"

# nginx ulimit (Too many open files 방지) — systemd override + worker_rlimit_nofile
NGINX_OVERRIDE=/etc/systemd/system/nginx.service.d/override.conf
if [ ! -f "$NGINX_OVERRIDE" ] || ! grep -q "LimitNOFILE=65536" "$NGINX_OVERRIDE" 2>/dev/null; then
    sudo mkdir -p /etc/systemd/system/nginx.service.d
    echo -e "[Service]\nLimitNOFILE=65536" | sudo tee "$NGINX_OVERRIDE" >/dev/null
    sudo systemctl daemon-reload
    echo -e "${GREEN}   ✓ nginx LimitNOFILE=65536 설정${NC}"
fi
if [ -f /etc/nginx/nginx.conf ] && ! grep -q "^worker_rlimit_nofile" /etc/nginx/nginx.conf; then
    sudo sed -i '1a worker_rlimit_nofile 65536;' /etc/nginx/nginx.conf
    echo -e "${GREEN}   ✓ nginx.conf worker_rlimit_nofile 추가${NC}"
fi

# nginx 패키지 자체 설치 확인
if ! command -v nginx >/dev/null 2>&1; then
    echo -e "${YELLOW}   • nginx 미설치 → apt 설치 시도${NC}"
    for d in "${REPO_ROOT}/offline_packages_2404/apt_packages" "${REPO_ROOT}/offline_packages/apt_packages"; do
        if [ -d "$d" ]; then
            NGINX_DEBS=( $(ls "$d"/nginx_*.deb "$d"/nginx-common_*.deb "$d"/nginx-core_*.deb "$d"/libnginx-*.deb 2>/dev/null) )
            [ ${#NGINX_DEBS[@]} -gt 0 ] && sudo apt install -y "${NGINX_DEBS[@]}"
            command -v nginx >/dev/null && break
        fi
    done
    if ! command -v nginx >/dev/null 2>&1; then
        sudo apt install -y nginx 2>/dev/null || echo -e "${RED}   ⚠️ nginx 설치 실패${NC}"
    fi
fi
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/snippets
NGINX_CONF_SRC="${SCRIPT_DIR}/nginx/hpc-portal.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/hpc-portal.conf"
SELF_SIGNED_SNIPPET="/etc/nginx/snippets/self-signed.conf"
SSL_PARAMS_SNIPPET="/etc/nginx/snippets/ssl-params.conf"
SS_CRT="/etc/ssl/certs/nginx-selfsigned.crt"
SS_KEY="/etc/ssl/private/nginx-selfsigned.key"
SS_DH="/etc/nginx/dhparam.pem"

# SSL 인증서: YAML 의 web.ssl.cert_path 우선 → 자체서명
USE_REAL_CERT=0
if [ -n "$SSL_CERT_PATH" ] && [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
    USE_REAL_CERT=1
    SS_CRT="$SSL_CERT_PATH"
    SS_KEY="$SSL_KEY_PATH"
    echo -e "${GREEN}   ✓ 정식 인증서 사용: $SS_CRT${NC}"
fi

if [ "$USE_REAL_CERT" = "0" ]; then
    # 자체서명 — 도메인+IP SAN 모두 포함
    SAN_ENTRIES="DNS:localhost,IP:127.0.0.1"
    if [ "$IS_DOMAIN" = "1" ]; then
        SAN_ENTRIES="DNS:${HOST_IP},${SAN_ENTRIES}"
        [ -n "$REAL_IP" ] && SAN_ENTRIES="${SAN_ENTRIES},IP:${REAL_IP}"
    else
        SAN_ENTRIES="IP:${HOST_IP},${SAN_ENTRIES}"
    fi

    REGEN_CERT=0
    if [ ! -f "$SS_CRT" ] || [ ! -f "$SS_KEY" ]; then
        REGEN_CERT=1
    else
        CERT_INFO=$(sudo openssl x509 -in "$SS_CRT" -noout -subject -ext subjectAltName 2>/dev/null)
        if ! echo "$CERT_INFO" | grep -qF "$HOST_IP"; then
            echo -e "${YELLOW}   • 인증서가 ${HOST_IP} 미포함 → 재발급${NC}"
            REGEN_CERT=1
        fi
    fi
    if [ "$REGEN_CERT" = "1" ]; then
        echo -e "${YELLOW}   • 자체서명 인증서 생성 (CN=${HOST_IP}, SAN=${SAN_ENTRIES})...${NC}"
        sudo mkdir -p /etc/ssl/private /etc/nginx/snippets
        sudo openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
            -keyout "$SS_KEY" -out "$SS_CRT" \
            -subj "/C=KR/ST=Local/L=Local/O=HPC/CN=${HOST_IP}" \
            -addext "subjectAltName=${SAN_ENTRIES}" 2>/dev/null \
            && echo -e "${GREEN}   ✓ 자체서명 인증서 발급 완료: $SS_CRT${NC}"
    fi
fi
if [ ! -f "$SELF_SIGNED_SNIPPET" ]; then
    echo -e "${YELLOW}   • self-signed.conf 스니펫 생성${NC}"
    sudo tee "$SELF_SIGNED_SNIPPET" >/dev/null <<EOF
ssl_certificate $SS_CRT;
ssl_certificate_key $SS_KEY;
EOF
fi
if [ ! -f "$SSL_PARAMS_SNIPPET" ]; then
    echo -e "${YELLOW}   • ssl-params.conf 스니펫 생성${NC}"
    sudo tee "$SSL_PARAMS_SNIPPET" >/dev/null <<'EOF'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
EOF
fi

# 도메인 사용 시 nginx server_name 자동 업데이트 (default_server 유지)
if [ "$IS_DOMAIN" = "1" ]; then
    if ! grep -q "server_name ${HOST_IP}" "$NGINX_CONF_SRC"; then
        echo -e "${YELLOW}   • nginx server_name 에 ${HOST_IP} 추가${NC}"
        sudo sed -i "s|server_name _;|server_name ${HOST_IP} ${REAL_IP} _;|g" "$NGINX_CONF_SRC"
        CONF_CHANGED=1
    fi
fi

# 프론트엔드 .env.production 자동 작성 (도메인/IP 기반 API URL)
SCHEME="https"
PUBLIC_BASE="${SCHEME}://${HOST_IP}"
for fe in frontend_3010 auth_portal_4431; do
    fe_dir="${SCRIPT_DIR}/${fe}"
    [ ! -d "$fe_dir" ] && continue
    cat > "${fe_dir}/.env.production" <<EOF
# Auto-generated by start_all.sh — 도메인/IP 변경 시 자동 갱신
VITE_API_URL=/api
VITE_WS_URL=/ws
VITE_AUTH_URL=/auth
VITE_PUBLIC_URL=${PUBLIC_BASE}
EOF
done

# auth_portal_4430 .env 의 SAML/CORS URL 자동 업데이트
AUTH_ENV="${SCRIPT_DIR}/auth_portal_4430/.env"
if [ -f "$AUTH_ENV" ]; then
    sudo sed -i \
        -e "s|^SAML_ACS_URL=.*|SAML_ACS_URL=${PUBLIC_BASE}/auth/saml/acs|" \
        -e "s|^SAML_SLS_URL=.*|SAML_SLS_URL=${PUBLIC_BASE}/auth/saml/sls|" \
        -e "s|^CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=${PUBLIC_BASE}|" \
        -e "s|^PUBLIC_URL=.*|PUBLIC_URL=${PUBLIC_BASE}|" \
        "$AUTH_ENV"
    grep -q "^PUBLIC_URL=" "$AUTH_ENV" || echo "PUBLIC_URL=${PUBLIC_BASE}" | sudo tee -a "$AUTH_ENV" >/dev/null
fi

# sites-enabled가 소스(dashboard/nginx/hpc-portal.conf)를 가리키도록 강제
NGINX_AVAILABLE=/etc/nginx/sites-available/hpc-portal.conf
NGINX_SRC_RESOLVED=$(readlink -f "$NGINX_CONF_SRC")
NGINX_ENABLED_RESOLVED=$(readlink -f "$NGINX_ENABLED" 2>/dev/null)
if [ "$NGINX_ENABLED_RESOLVED" != "$NGINX_SRC_RESOLVED" ]; then
    echo -e "${YELLOW}   • sites-enabled 가 소스 가리키지 않음 → 심볼릭 재설정${NC}"
    sudo rm -f "$NGINX_ENABLED" "$NGINX_AVAILABLE"
    sudo ln -sf "$NGINX_CONF_SRC" "$NGINX_AVAILABLE"
    sudo ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"
    CONF_CHANGED=1  # 설정 바뀜 → restart 강제
fi
if ! sudo systemctl is-active --quiet nginx; then
    echo -e "${YELLOW}   • nginx 미실행 → 시작${NC}"
    sudo systemctl enable --now nginx 2>/dev/null || sudo systemctl start nginx
fi
# 문제 일으키는 동적 모듈 비활성화 (perl: strict.pm 24, nchan: memstore assertion)
MODULES_CHANGED=0
for mod in /etc/nginx/modules-enabled/*perl*.conf /etc/nginx/modules-enabled/*nchan*.conf; do
    [ -f "$mod" ] || continue
    echo -e "${YELLOW}   • 문제 모듈 비활성화: $(basename "$mod")${NC}"
    sudo mv "$mod" "${mod}.disabled" 2>/dev/null && MODULES_CHANGED=1
done

# 현재 마스터가 perl/nchan 메모리에 들고 있나? (이전 실행에서 비활성화했어도 안 빠짐)
MASTER_PID=$(pgrep -f 'nginx: master' | head -1)
STALE_MODULES=0
if [ -n "$MASTER_PID" ] && sudo grep -qE "ngx_http_perl_module|nchan_module" "/proc/$MASTER_PID/maps" 2>/dev/null; then
    STALE_MODULES=1
    echo -e "${YELLOW}   • 옛 마스터(PID $MASTER_PID)에 perl/nchan 잔존 → 강제 재시작 필요${NC}"
fi

if sudo nginx -t 2>/dev/null; then
    CUR_LIMIT=$(cat /proc/$(pgrep -f 'nginx: worker' 2>/dev/null | head -1)/limits 2>/dev/null | awk '/Max open files/{print $4}')
    if [ "$MODULES_CHANGED" = "1" ] || [ "$STALE_MODULES" = "1" ] || [ "${CONF_CHANGED:-0}" = "1" ] || [ "${CUR_LIMIT:-0}" -lt 65536 ]; then
        # stop + pkill + start (systemctl restart가 옛 마스터 못 죽이는 경우 대비)
        sudo systemctl stop nginx 2>/dev/null
        sleep 1
        sudo pkill -9 nginx 2>/dev/null; sleep 1
        sudo systemctl start nginx && echo -e "${GREEN}   ✓ nginx 강제 재시작${NC}"
        sleep 1
        NEW_LIMIT=$(cat /proc/$(pgrep -f 'nginx: worker' 2>/dev/null | head -1)/limits 2>/dev/null | awk '/Max open files/{print $4}')
        echo -e "${GREEN}   ✓ 워커 nofile: ${NEW_LIMIT:-?}${NC}"
    else
        sudo systemctl reload nginx && echo -e "${GREEN}   ✓ nginx reload (nofile=$CUR_LIMIT, 모듈 OK)${NC}"
    fi
else
    echo -e "${RED}   ⚠️ nginx 설정 오류 — sudo nginx -t 로 확인${NC}"
    sudo nginx -t 2>&1 | tail -5
fi
if ss -tln 2>/dev/null | grep -qE ":443\s"; then
    echo -e "${GREEN}   ✓ 443 LISTEN${NC}"
else
    echo -e "${RED}   ✗ 443 미점유 — 인증서/설정 확인 필요${NC}"
fi
echo ""
# ────────────────────────────────────────────────────────────────

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
[ -f "${SCRIPT_DIR}/auth_portal_4430/start.sh" ] && \
    cd "${SCRIPT_DIR}/auth_portal_4430" && ./start.sh && cd "${SCRIPT_DIR}" && echo ""

echo -e "${BLUE}ℹ️  Auth Frontend(4431): 빌드된 dist를 nginx가 서빙 (dev server 생략)${NC}"
echo ""

cd "${SCRIPT_DIR}/backend_5010" && ./start.sh && cd "${SCRIPT_DIR}"
echo ""
cd "${SCRIPT_DIR}/websocket_5011" && ./start.sh && cd "${SCRIPT_DIR}"
echo ""
echo -e "${BLUE}ℹ️  Frontend(3010): 빌드된 dist를 nginx가 서빙 (dev server 생략)${NC}"
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
echo "🔗 접속 정보 (외부 접속용):"
echo "  메인(SSO):   https://${HOST_IP}/        (→ /auth_portal/ 자동 진입)"
echo "  Dashboard:  https://${HOST_IP}/dashboard/"
echo "  (백엔드 디버그) http://${HOST_IP}:5010"
echo ""
echo "💡 외부 접속이 안 되면 방화벽 확인:"
echo "   sudo ufw allow 80,443,3010,5010,5011,9090,9100/tcp"
echo ""
echo "🎯 모드: 🚀 Production (MOCK_MODE=false)"
echo "   - 실제 Slurm 명령 실행"
echo "   - Node Management: 실제 노드 Drain/Resume 가능"
echo "   - sinfo, scontrol 명령 사용"
echo ""
echo "🔴 종료: ./stop_all.sh"
echo "🎭 Mock Mode로 시작: ./start_all_mock.sh"
