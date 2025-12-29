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
WHEELS_BASE="$PROJECT_ROOT/offline_packages/python_wheels"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 실행 사용자 (sudo로 실행 시 실제 사용자)
RUN_USER="${SUDO_USER:-$(whoami)}"
RUN_GROUP=$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")

# 서비스 정의 (서비스명:디렉토리:Python버전:앱모듈)
declare -A SERVICES=(
    ["hpc-auth-backend"]="auth_portal_4430:3.10:app:app"
    ["hpc-dashboard-backend"]="backend_5010:3.10:app:app"
    ["hpc-websocket"]="websocket_5011:3.10:websocket_server_enhanced:py"
    ["hpc-cae-backend"]="kooCAEWebServer_5000:3.10:app:create_app()"
    ["hpc-cae-automation"]="kooCAEWebAutomationServer_5001:3.10:app:app"
    ["hpc-moonlight-backend"]="MoonlightSunshine_8004/backend_moonlight_8004:3.10:app:app"
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

        # 기존 venv 삭제
        if [ -d "$full_path/venv" ]; then
            rm -rf "$full_path/venv"
        fi

        # venv 생성 (실제 사용자로)
        sudo -u "$RUN_USER" $python_cmd -m venv "$full_path/venv"

        if [ $? -ne 0 ]; then
            echo -e "    ${RED}❌ venv 생성 실패${NC}"
            return 1
        fi
    fi

    # 패키지 설치
    if [ -f "$full_path/requirements.txt" ]; then
        local actual_version=$("$full_path/venv/bin/python" --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "$py_version")
        local wheels_dir="${WHEELS_BASE}/python${actual_version}"

        echo "    → 패키지 설치 중 (Python ${actual_version})..."

        # logs 디렉토리 생성
        sudo -u "$RUN_USER" mkdir -p "$full_path/logs"

        if [ -d "$wheels_dir" ]; then
            # 오프라인 설치
            if sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install --no-index --find-links="$wheels_dir" -r "$full_path/requirements.txt" > "$full_path/logs/pip_install.log" 2>&1; then
                echo -e "    ${GREEN}✓ 오프라인 설치 완료${NC}"
            else
                # 온라인 fallback
                echo -e "    ${YELLOW}⚠ 오프라인 실패, 온라인 시도...${NC}"
                if sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install -r "$full_path/requirements.txt" >> "$full_path/logs/pip_install.log" 2>&1; then
                    echo -e "    ${GREEN}✓ 온라인 설치 완료${NC}"
                else
                    echo -e "    ${RED}❌ 설치 실패 (로그: $full_path/logs/pip_install.log)${NC}"
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
        # gunicorn 서비스
        cat > "$service_file" << EOF
[Unit]
Description=HPC Backend - $service_name
After=network.target redis.service
Wants=redis.service

[Service]
Type=notify
User=$RUN_USER
Group=$RUN_GROUP
WorkingDirectory=$full_path
Environment="PATH=$full_path/venv/bin"
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
    "hpc-auth-backend"
    "hpc-dashboard-backend"
    "hpc-websocket"
    "hpc-cae-backend"
    "hpc-cae-automation"
    "hpc-moonlight-backend"
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
echo "  sudo systemctl status hpc-auth-backend"
echo "  sudo systemctl restart hpc-dashboard-backend"
echo "  sudo systemctl stop hpc-websocket"
echo "  journalctl -u hpc-cae-backend -f"
echo ""
