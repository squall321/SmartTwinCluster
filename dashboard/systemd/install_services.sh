#!/bin/bash
################################################################################
# HPC Backend Services - systemd 설치 스크립트
#
# 기능:
#   - 기존 서비스 정지 및 비활성화
#   - systemd 서비스 파일 설치/업데이트
#   - venv 생성 및 패키지 설치 (오프라인 지원)
#   - 서비스 시작 및 활성화
#
# 사용법:
#   sudo ./install_services.sh              # 전체 설치
#   sudo ./install_services.sh --reinstall  # venv 재설치 포함
#   sudo ./install_services.sh --status     # 상태만 확인
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DASHBOARD_DIR")"

# OS 감지 기반 오프라인 패키지 디렉토리 설정
source "${PROJECT_ROOT}/cluster/utils/detect_os.sh"
detect_os_version
set_offline_pkg_dir "$PROJECT_ROOT"
WHEELS_BASE="${OFFLINE_PKG_DIR}/python_wheels"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# python_wheels.tar.gz 자동 압축 해제
WHEELS_TARBALL="${OFFLINE_PKG_DIR}/python_wheels.tar.gz"
if [ -f "$WHEELS_TARBALL" ] && [ ! -d "$WHEELS_BASE/python3.12" ]; then
    echo -e "${BLUE}[사전준비] python_wheels.tar.gz 압축 해제 중...${NC}"
    tar -xzf "$WHEELS_TARBALL" -C "${OFFLINE_PKG_DIR}/"
    echo -e "${GREEN}✓ 압축 해제 완료${NC}"
fi

# 관리자 (install 실행 계정)
ADMIN_USER="${SUDO_USER:-$(whoami)}"

# 서비스 실행 계정 결정 우선순위 (phase5_web.sh 와 정렬):
#   1. 환경변수 SERVICE_USER (명시 지정 시)
#   2. yaml 의 web_services.service_user  (canonical, phase5_web.sh 와 동일)
#   3. yaml 의 users.ssh_user             (대체 필드)
#   4. 폴백: ADMIN_USER
RUN_USER=""
if [ -n "${SERVICE_USER:-}" ]; then
    RUN_USER="$SERVICE_USER"
else
    for _yaml in \
        "${CLUSTER_YAML:-}" \
        "$SCRIPT_DIR/../../my_multihead_cluster.yaml" \
        "/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_multihead_cluster.yaml"; do
        [ -n "$_yaml" ] && [ -f "$_yaml" ] || continue
        RUN_USER=$(python3 -c "
import yaml
try:
    c = yaml.safe_load(open('$_yaml')) or {}
    # 1) web_services.service_user 우선
    u = ((c.get('web_services') or {}).get('service_user') or
         (c.get('users') or {}).get('ssh_user') or '')
    print(u)
except Exception: pass
" 2>/dev/null)
        [ -n "$RUN_USER" ] && break
    done
    [ -z "$RUN_USER" ] && RUN_USER="$ADMIN_USER"
fi
# 결정된 계정이 존재하는지 검증, 없으면 ADMIN_USER 폴백
if ! id "$RUN_USER" &>/dev/null; then
    echo "  ⚠️  SERVICE_USER='$RUN_USER' 가 시스템에 없음 → ADMIN_USER 폴백"
    RUN_USER="$ADMIN_USER"
fi
RUN_GROUP=$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")
echo "  → ADMIN_USER=$ADMIN_USER, SERVICE_USER=$RUN_USER (group=$RUN_GROUP)"

# ADMIN_USER 가 RUN_USER 와 다르면 RUN_GROUP 에 추가 (관리 권한 부여)
if [ "$ADMIN_USER" != "$RUN_USER" ] && id "$ADMIN_USER" &>/dev/null; then
    if ! id -nG "$ADMIN_USER" | tr ' ' '\n' | grep -qx "$RUN_GROUP"; then
        echo "  → $ADMIN_USER 를 $RUN_GROUP 그룹에 추가 (관리 권한)"
        usermod -aG "$RUN_GROUP" "$ADMIN_USER"
    fi
fi

# 서비스 정의 (서비스명:디렉토리:Python버전:앱모듈)
# phase5_web.sh에서 생성하는 실제 서비스 이름과 일치
# Python 버전:
#   - auth_portal_4430, websocket_5011: Python 3.10 (22.04) / 3.12 (24.04)
#   - backend_5010: Python 3.12 (pandas/numpy 최적화)
#   - kooCAEWebServer_5000, kooCAEWebAutomationServer_5001: Python 3.13
# 24.04(noble)에서는 Python 3.10이 없으므로 3.12로 통합
PY_LEGACY="3.10"
if [[ "$OS_VERSION" == "24.04" || "$OS_CODENAME" == "noble" ]]; then
    PY_LEGACY="3.12"
fi
declare -A SERVICES=(
    ["auth_backend"]="auth_portal_4430:${PY_LEGACY}:app:app"
    ["dashboard_backend"]="backend_5010:3.12:app:app"
    ["websocket_service"]="websocket_5011:${PY_LEGACY}:websocket_server_enhanced:py"
    ["cae_backend"]="kooCAEWebServer_5000:3.13:app:create_app()"
    ["cae_automation"]="kooCAEWebAutomationServer_5001:3.13:app:app"
)

# 옵션 파싱
REINSTALL_VENV=false
STATUS_ONLY=false

for arg in "$@"; do
    case $arg in
        --reinstall)
            REINSTALL_VENV=true
            ;;
        --status)
            STATUS_ONLY=true
            ;;
        --help|-h)
            echo "사용법: sudo $0 [옵션]"
            echo ""
            echo "옵션:"
            echo "  --reinstall  venv 재설치 포함"
            echo "  --status     상태만 확인"
            echo "  --help       도움말"
            exit 0
            ;;
    esac
done

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ root 권한이 필요합니다. sudo로 실행하세요.${NC}"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 HPC Backend Services - systemd 설치"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  실행 사용자: $RUN_USER"
echo "  프로젝트 경로: $PROJECT_ROOT"
echo "  오프라인 wheels: $WHEELS_BASE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 상태만 확인
if [ "$STATUS_ONLY" = true ]; then
    echo -e "${BLUE}[서비스 상태]${NC}"
    for service_name in "${!SERVICES[@]}"; do
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} $service_name: $(systemctl is-active $service_name)"
        else
            echo -e "  ${RED}○${NC} $service_name: $(systemctl is-active $service_name 2>/dev/null || echo 'not installed')"
        fi
    done
    exit 0
fi

################################################################################
# 1. 기존 서비스 정지
################################################################################
echo -e "${BLUE}[1/5] 기존 서비스 정지 중...${NC}"

for service_name in "${!SERVICES[@]}"; do
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo "  → $service_name 정지 중..."
        systemctl stop "$service_name" 2>/dev/null || true
        echo -e "    ${GREEN}✓${NC} 정지됨"
    fi

    # 기존 서비스 비활성화
    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        systemctl disable "$service_name" 2>/dev/null || true
    fi
done

# 기존 수동 프로세스 정리
echo "  → 기존 gunicorn/python 프로세스 정리..."
pkill -f "gunicorn.*auth_portal_4430" 2>/dev/null || true
pkill -f "gunicorn.*backend_5010" 2>/dev/null || true
pkill -f "gunicorn.*kooCAEWebServer_5000" 2>/dev/null || true
pkill -f "gunicorn.*kooCAEWebAutomationServer_5001" 2>/dev/null || true
pkill -f "gunicorn.*backend_moonlight_8004" 2>/dev/null || true
pkill -f "websocket_5011.*python" 2>/dev/null || true
sleep 2

echo -e "${GREEN}✅ 기존 서비스 정지 완료${NC}"
echo ""

################################################################################
# 2. venv 설정 및 패키지 설치
################################################################################
echo -e "${BLUE}[2/5] Python venv 설정 및 패키지 설치...${NC}"

setup_venv() {
    local service_dir="$1"
    local py_version="$2"
    local full_path="$DASHBOARD_DIR/$service_dir"

    if [ ! -d "$full_path" ]; then
        echo -e "    ${YELLOW}⚠ 디렉토리 없음: $service_dir${NC}"
        return 1
    fi

    # Python 명령어 결정
    local python_cmd="python3"
    if command -v "python${py_version}" &>/dev/null; then
        python_cmd="python${py_version}"
    elif command -v "python3" &>/dev/null; then
        python_cmd="python3"
    fi

    # venv 생성/재생성
    if [ "$REINSTALL_VENV" = true ] || [ ! -d "$full_path/venv" ]; then
        echo "    → venv 생성 중 ($python_cmd)..."

        # 기존 venv 삭제 (권한 문제 방지를 위해 소유권 먼저 변경)
        if [ -d "$full_path/venv" ]; then
            chown -R "$RUN_USER:$RUN_GROUP" "$full_path/venv" 2>/dev/null || true
            rm -rf "$full_path/venv"
        fi

        # 서비스 디렉토리 자체에 RUN_USER 가 쓸 수 있도록 그룹쓰기 부여
        # (koopark 소유인 채로 그룹만 stcx로 → stcx 가 venv 생성 가능, koopark 도 작업 가능)
        chgrp "$RUN_GROUP" "$full_path"
        chmod g+rwx "$full_path"
        chmod g+s "$full_path"   # 새로 생기는 venv 도 group=$RUN_GROUP 상속

        # venv 생성 (실제 사용자로)
        sudo -u "$RUN_USER" $python_cmd -m venv "$full_path/venv"

        if [ $? -ne 0 ]; then
            echo -e "    ${RED}❌ venv 생성 실패${NC}"
            return 1
        fi

        # 빌드 의존성 부트스트랩 — pip/setuptools/wheel 을 오프라인 wheels 에서 먼저 설치
        # (이게 없으면 일부 패키지가 빌드 의존성 해결 못해 ERROR: No matching distribution for 'wheel')
        local _bootstrap_actual_ver=$("$full_path/venv/bin/python" --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "$py_version")
        local _bootstrap_wheels="${WHEELS_BASE}/python${_bootstrap_actual_ver}"
        if [ -d "$_bootstrap_wheels" ]; then
            echo "    → 빌드 의존성 부트스트랩 (pip/setuptools/wheel) ..."
            if sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install --no-index --find-links="$_bootstrap_wheels" \
                    --upgrade pip setuptools wheel 2>&1 | tail -5 | sed 's/^/      /'; then
                echo "      ✓ pip/setuptools/wheel 준비 완료"
            else
                echo "      ⚠ 부트스트랩 일부 실패 (계속 진행)"
            fi
        fi
    fi

    # 패키지 설치
    if [ -f "$full_path/requirements.txt" ]; then
        local actual_version=$("$full_path/venv/bin/python" --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "$py_version")
        local wheels_dir="${WHEELS_BASE}/python${actual_version}"

        echo "    → 패키지 설치 중 (Python ${actual_version})..."
        echo "    → Wheels 경로: $wheels_dir"

        # logs 디렉토리 생성 + 소유권/그룹쓰기 강제 + setgid
        mkdir -p "$full_path/logs"
        chown -R "$RUN_USER:$RUN_GROUP" "$full_path/logs"
        chmod -R u+rwX,g+rwX "$full_path/logs"
        chmod g+s "$full_path/logs"

        # 공용 /var/log/web_services/ 도 RUN_USER 그룹 쓰기 + setgid
        if [ -d /var/log/web_services ]; then
            chown -R "$RUN_USER:$RUN_GROUP" /var/log/web_services 2>/dev/null || true
            chmod -R u+rwX,g+rwX /var/log/web_services 2>/dev/null || true
            chmod g+s /var/log/web_services 2>/dev/null || true
        fi

        if [ -d "$wheels_dir" ]; then
            # wheels 디렉토리 내용 확인
            local wheel_count=$(find "$wheels_dir" -name "*.whl" 2>/dev/null | wc -l)
            echo "    → Wheels 파일 수: $wheel_count"

            # Flask wheel 존재 확인
            if ls "$wheels_dir"/[Ff]lask*.whl &>/dev/null; then
                echo "    → Flask wheel: $(ls "$wheels_dir"/[Ff]lask*.whl 2>/dev/null | head -1)"
            else
                echo -e "    ${YELLOW}⚠ Flask wheel 없음!${NC}"
            fi

            # 오프라인 설치 — --no-build-isolation 로 PEP 517 격리환경의 wheel 부재 회피
            # (격리환경은 --find-links 못 봐서 'wheel' 패키지 못 찾음 → 빌드 실패)
            if sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install --no-index --find-links="$wheels_dir" \
                    --no-build-isolation -r "$full_path/requirements.txt" > "$full_path/logs/pip_install.log" 2>&1; then
                echo -e "    ${GREEN}✓ 오프라인 설치 완료${NC}"
            else
                # 온라인 fallback
                echo -e "    ${YELLOW}⚠ 오프라인 실패, 온라인 시도...${NC}"
                echo "    → pip 로그 마지막 10줄:"
                tail -10 "$full_path/logs/pip_install.log" 2>/dev/null | sed 's/^/      /'
                if sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install -r "$full_path/requirements.txt" >> "$full_path/logs/pip_install.log" 2>&1; then
                    echo -e "    ${GREEN}✓ 온라인 설치 완료${NC}"
                else
                    echo -e "    ${RED}❌ 설치 실패 (로그: $full_path/logs/pip_install.log)${NC}"
                    tail -20 "$full_path/logs/pip_install.log" 2>/dev/null | sed 's/^/      /'
                    return 1
                fi
            fi
        else
            # 온라인 설치
            echo -e "    ${YELLOW}⚠ 오프라인 wheels 없음, 온라인 시도...${NC}"
            if sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install -r "$full_path/requirements.txt" > "$full_path/logs/pip_install.log" 2>&1; then
                echo -e "    ${GREEN}✓ 온라인 설치 완료${NC}"
            else
                echo -e "    ${RED}❌ 설치 실패${NC}"
                return 1
            fi
        fi
    fi

    # gunicorn 확인 (websocket 제외)
    if [[ "$service_dir" != *"websocket"* ]]; then
        if [ ! -f "$full_path/venv/bin/gunicorn" ]; then
            echo -e "    ${RED}❌ gunicorn이 설치되지 않음${NC}"
            return 1
        fi
    fi

    return 0
}

for service_name in "${!SERVICES[@]}"; do
    IFS=':' read -r service_dir py_version app_module <<< "${SERVICES[$service_name]}"
    echo "  📦 $service_name ($service_dir)"
    setup_venv "$service_dir" "$py_version"
done

echo -e "${GREEN}✅ venv 설정 완료${NC}"
echo ""

################################################################################
# 3. systemd 서비스 파일 생성
################################################################################
echo -e "${BLUE}[3/5] systemd 서비스 파일 생성...${NC}"

generate_service_file() {
    local service_name="$1"
    local service_dir="$2"
    local app_module="$3"
    local full_path="$DASHBOARD_DIR/$service_dir"
    local service_file="/etc/systemd/system/${service_name}.service"

    # SSH 키 경로 결정 (실행 사용자의 홈 디렉토리)
    local run_user_home=$(getent passwd "$RUN_USER" | cut -d: -f6)
    local ssh_key_path="${run_user_home}/.ssh/id_rsa"

    # SSH 키 존재 확인 (첫 번째 서비스에서만 경고)
    if [ "$SSH_KEY_WARNED" != "true" ] && [ ! -f "$ssh_key_path" ]; then
        echo -e "  ${YELLOW}⚠ SSH 키 없음: $ssh_key_path${NC}"
        echo -e "  ${YELLOW}  viz 노드 SSH 연결이 필요한 기능(VNC 등)이 작동하지 않을 수 있습니다.${NC}"
        echo -e "  ${YELLOW}  해결: ssh-keygen -t rsa -N '' -f $ssh_key_path${NC}"
        SSH_KEY_WARNED="true"
    fi

    # websocket은 python 직접 실행
    if [[ "$service_dir" == *"websocket"* ]]; then
        cat > "$service_file" << EOF
[Unit]
Description=HPC WebSocket Server
After=network.target redis.service
Wants=redis.service

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_GROUP
WorkingDirectory=$full_path
Environment="PATH=$full_path/venv/bin"
Environment="SSH_KEY_PATH=$ssh_key_path"
Environment="HOME=$run_user_home"
EnvironmentFile=-$full_path/.env
ExecStart=$full_path/venv/bin/python websocket_server_enhanced.py
Restart=on-failure
RestartSec=5
KillMode=mixed
TimeoutStopSec=30

StandardOutput=append:$full_path/logs/websocket.log
StandardError=append:$full_path/logs/websocket_error.log

[Install]
WantedBy=multi-user.target
EOF
    else
        # gunicorn 서비스 (Type=simple 사용 - notify보다 안정적)
        cat > "$service_file" << EOF
[Unit]
Description=HPC Backend - $service_name
After=network.target redis.service
Wants=redis.service

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_GROUP
WorkingDirectory=$full_path
Environment="PATH=$full_path/venv/bin"
Environment="SSH_KEY_PATH=$ssh_key_path"
Environment="HOME=$run_user_home"
EnvironmentFile=-$full_path/.env
ExecStart=$full_path/venv/bin/gunicorn -c gunicorn_config.py '$app_module'
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
RestartSec=5
KillMode=mixed
TimeoutStopSec=30

StandardOutput=append:$full_path/logs/gunicorn.log
StandardError=append:$full_path/logs/gunicorn_error.log

[Install]
WantedBy=multi-user.target
EOF
    fi

    echo -e "  ${GREEN}✓${NC} $service_file"
}

for service_name in "${!SERVICES[@]}"; do
    IFS=':' read -r service_dir py_version app_module_part1 app_module_part2 <<< "${SERVICES[$service_name]}"

    # app:app 또는 app:create_app() 형태 처리
    if [ "$app_module_part2" = "py" ]; then
        app_module=""  # websocket
    else
        app_module="${app_module_part1}:${app_module_part2}"
    fi

    generate_service_file "$service_name" "$service_dir" "$app_module"
done

echo -e "${GREEN}✅ 서비스 파일 생성 완료${NC}"
echo ""

################################################################################
# 4. systemd 데몬 리로드 및 서비스 활성화
################################################################################
echo -e "${BLUE}[4/5] systemd 데몬 리로드 및 서비스 활성화...${NC}"

systemctl daemon-reload

for service_name in "${!SERVICES[@]}"; do
    echo "  → $service_name 활성화..."
    systemctl enable "$service_name" 2>/dev/null || true
done

echo -e "${GREEN}✅ 서비스 활성화 완료${NC}"
echo ""

################################################################################
# 5. 서비스 시작
################################################################################
echo -e "${BLUE}[5/5] 서비스 시작...${NC}"

# 시작 순서: Redis → Auth → 나머지
START_ORDER=(
    "auth_backend"
    "dashboard_backend"
    "websocket_service"
    "cae_backend"
    "cae_automation"
)

for service_name in "${START_ORDER[@]}"; do
    if [ -n "${SERVICES[$service_name]}" ]; then
        echo "  → $service_name 시작..."
        if systemctl start "$service_name"; then
            sleep 2
            if systemctl is-active --quiet "$service_name"; then
                echo -e "    ${GREEN}✓ 시작됨${NC}"
            else
                echo -e "    ${RED}✗ 시작 실패${NC}"
                echo "    로그: journalctl -u $service_name -n 20"
            fi
        else
            echo -e "    ${RED}✗ 시작 명령 실패${NC}"
        fi
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ 설치 완료!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 서비스 상태 확인:"
for service_name in "${!SERVICES[@]}"; do
    if systemctl is-active --quiet "$service_name"; then
        echo -e "  ${GREEN}●${NC} $service_name: active"
    else
        echo -e "  ${RED}○${NC} $service_name: $(systemctl is-active $service_name 2>/dev/null || echo 'failed')"
    fi
done
echo ""
echo "🔧 관리 명령어:"
echo "  sudo systemctl status auth_backend"
echo "  sudo systemctl restart dashboard_backend"
echo "  sudo systemctl stop websocket_service"
echo "  journalctl -u cae_backend -f"
echo ""
