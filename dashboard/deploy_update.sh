#!/bin/bash
################################################################################
# Dashboard 서비스 선택적 업데이트 배포 스크립트
#
# - git diff 기반으로 변경된 서비스만 자동 감지
# - 프론트엔드: 빌드 + nginx 배포
# - 백엔드: requirements 변경 시 venv 재설치 + systemd restart
# - Slurm 등 스케줄러 서비스는 일절 건드리지 않음
#
# 사용법:
#   sudo ./deploy_update.sh                     # 변경된 서비스만 자동 배포
#   sudo ./deploy_update.sh --all               # 전체 강제 배포
#   sudo ./deploy_update.sh --service backend_5010   # 특정 서비스만
#   sudo ./deploy_update.sh --dry-run           # 변경 감지만 (배포 안 함)
#   sudo ./deploy_update.sh --status            # 현재 서비스 상태만 출력
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_DIR="$SCRIPT_DIR/.deploy_state"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${CYAN}[....] $1${NC}"; }

# ── 서비스 정의 ──────────────────────────────────────────────────────────────
# 형식: "타입|디렉토리|systemd서비스명|nginx배포경로"
# 타입: frontend / backend
declare -A SERVICES=(
    # 프론트엔드 (빌드 후 nginx 배포)
    ["auth_portal_4431"]="frontend|auth_portal_4431||/var/www/html/auth_portal"
    ["frontend_3010"]="frontend|frontend_3010||/var/www/html/dashboard"
    ["vnc_service_8002"]="frontend|vnc_service_8002||/var/www/html/vnc_service_8002"
    ["moonlight_frontend_8003"]="frontend|moonlight_frontend_8003||/var/www/html/moonlight"
    ["kooCAEWeb_5173"]="frontend|kooCAEWeb_5173||/var/www/html/cae"
    ["app_5174"]="frontend|app_5174||/var/www/html/app_5174"

    # 백엔드 (venv + systemd restart)
    ["auth_portal_4430"]="backend|auth_portal_4430|auth_backend|"
    ["backend_5010"]="backend|backend_5010|dashboard_backend|"
    ["websocket_5011"]="backend|websocket_5011|websocket_service|"
    ["kooCAEWebServer_5000"]="backend|kooCAEWebServer_5000|cae_backend|"
    ["kooCAEWebAutomationServer_5001"]="backend|kooCAEWebAutomationServer_5001|cae_automation|"
)

# ── 옵션 파싱 ────────────────────────────────────────────────────────────────
FORCE_ALL=false
TARGET_SERVICE=""
DRY_RUN=false
STATUS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)        FORCE_ALL=true; shift ;;
        --service)    TARGET_SERVICE="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --status)     STATUS_ONLY=true; shift ;;
        --help|-h)
            head -20 "$0" | grep "^#" | sed 's/^# \?//'; exit 0 ;;
        *)
            log_error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ $EUID -ne 0 && "$STATUS_ONLY" != "true" && "$DRY_RUN" != "true" ]] && {
    log_error "배포 시 root 권한 필요 (sudo 사용)"; exit 1
}

RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
mkdir -p "$STATE_DIR"

# ── 상태 출력 ────────────────────────────────────────────────────────────────
show_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " 서비스 상태"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for svc_key in $(echo "${!SERVICES[@]}" | tr ' ' '\n' | sort); do
        IFS='|' read -r svc_type svc_dir systemd_svc nginx_path <<< "${SERVICES[$svc_key]}"
        local last_deploy="없음"
        [[ -f "$STATE_DIR/${svc_key}.commit" ]] && last_deploy=$(cat "$STATE_DIR/${svc_key}.commit")

        if [[ "$svc_type" == "backend" && -n "$systemd_svc" ]]; then
            local state
            state=$(systemctl is-active "$systemd_svc" 2>/dev/null || echo "not-installed")
            if [[ "$state" == "active" ]]; then
                echo -e "  ${GREEN}● ${svc_key}${NC} ($systemd_svc: active) — 마지막 배포: ${last_deploy:0:8}"
            else
                echo -e "  ${RED}○ ${svc_key}${NC} ($systemd_svc: $state) — 마지막 배포: ${last_deploy:0:8}"
            fi
        else
            local deployed="없음"
            [[ -d "${nginx_path}" ]] && deployed="배포됨"
            echo -e "  ${CYAN}⬡ ${svc_key}${NC} (nginx: $deployed) — 마지막 배포: ${last_deploy:0:8}"
        fi
    done
    echo ""
}

if [[ "$STATUS_ONLY" == "true" ]]; then
    show_status; exit 0
fi

# ── 변경 감지 ────────────────────────────────────────────────────────────────
has_changes() {
    local svc_key="$1"
    local svc_dir="$2"
    local state_file="$STATE_DIR/${svc_key}.commit"
    local full_path="$SCRIPT_DIR/$svc_dir"

    [[ ! -d "$full_path" ]] && return 1

    # 마지막 배포 커밋 없으면 → 변경 있음
    if [[ ! -f "$state_file" ]]; then
        return 0
    fi

    local last_commit
    last_commit=$(cat "$state_file")
    local current_commit
    current_commit=$(git -C "$PROJECT_ROOT" log -1 --format="%H" -- "dashboard/$svc_dir" 2>/dev/null || echo "")

    # git 이력 없거나 커밋이 다르면 → 변경 있음
    [[ -z "$current_commit" || "$current_commit" != "$last_commit" ]]
}

record_deploy() {
    local svc_key="$1"
    local svc_dir="$2"
    local current_commit
    current_commit=$(git -C "$PROJECT_ROOT" log -1 --format="%H" -- "dashboard/$svc_dir" 2>/dev/null || date +%s)
    echo "$current_commit" > "$STATE_DIR/${svc_key}.commit"
}

# ── 프론트엔드 빌드 + nginx 배포 ─────────────────────────────────────────────
deploy_frontend() {
    local svc_key="$1"
    local svc_dir="$2"
    local nginx_path="$3"
    local full_path="$SCRIPT_DIR/$svc_dir"

    log_step "$svc_key: 빌드 중..."

    [[ ! -d "$full_path" ]] && { log_warn "  디렉토리 없음: $svc_dir — 스킵"; return 1; }
    [[ ! -d "$full_path/node_modules" ]] && { log_warn "  node_modules 없음 — npm install 먼저 필요"; return 1; }

    cd "$full_path"

    # 빌드
    rm -f tsconfig.tsbuildinfo 2>/dev/null || true
    rm -rf dist 2>/dev/null || sudo rm -rf dist 2>/dev/null || true

    local build_log="/tmp/${svc_key}_build.log"
    if ! npm run build > "$build_log" 2>&1; then
        log_error "  빌드 실패 — 로그: $build_log"
        tail -20 "$build_log" | sed 's/^/    /'
        cd "$SCRIPT_DIR"
        return 1
    fi

    # app_5174: landing.html → dist/index.html
    [[ "$svc_key" == "app_5174" && -f "landing.html" ]] && cp landing.html dist/index.html 2>/dev/null || true

    # nginx 배포
    sudo rm -rf "$nginx_path" 2>/dev/null || true
    sudo mkdir -p "$nginx_path"
    sudo cp -r dist/* "$nginx_path/"
    sudo chown -R www-data:www-data "$nginx_path" 2>/dev/null || \
        sudo chown -R nginx:nginx "$nginx_path" 2>/dev/null || true
    sudo chmod -R 755 "$nginx_path"

    cd "$SCRIPT_DIR"
    log_success "  $svc_key → $nginx_path"
}

# ── 백엔드 venv + systemd restart ────────────────────────────────────────────
deploy_backend() {
    local svc_key="$1"
    local svc_dir="$2"
    local systemd_svc="$3"
    local full_path="$SCRIPT_DIR/$svc_dir"

    log_step "$svc_key: 배포 중..."

    [[ ! -d "$full_path" ]] && { log_warn "  디렉토리 없음: $svc_dir — 스킵"; return 1; }

    # requirements.txt 변경 여부 확인 → 변경 시 pip 재설치
    local req_hash_file="$STATE_DIR/${svc_key}.req_hash"
    local req_file="$full_path/requirements.txt"
    local needs_pip=false

    if [[ -f "$req_file" ]]; then
        local current_hash
        current_hash=$(md5sum "$req_file" | cut -d' ' -f1)
        local stored_hash=""
        [[ -f "$req_hash_file" ]] && stored_hash=$(cat "$req_hash_file")

        if [[ "$current_hash" != "$stored_hash" || ! -d "$full_path/venv" ]]; then
            needs_pip=true
        fi
    fi

    if [[ "$needs_pip" == "true" ]]; then
        log_info "  requirements.txt 변경 감지 — pip 재설치..."

        # Python 버전 자동 결정
        local py_cmd="python3"
        for v in 3.13 3.12 3.10; do
            command -v "python${v}" &>/dev/null && { py_cmd="python${v}"; break; }
        done

        [[ ! -d "$full_path/venv" ]] && sudo -u "$RUN_USER" $py_cmd -m venv "$full_path/venv"
        sudo -u "$RUN_USER" mkdir -p "$full_path/logs"

        # 오프라인 wheels 시도 → 실패 시 온라인
        local actual_ver
        actual_ver=$("$full_path/venv/bin/python" --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "3.12")
        local wheels_dir
        # OS 감지 없이 경로 탐색
        for candidate in \
            "$PROJECT_ROOT/offline_packages_2404/python_wheels/python${actual_ver}" \
            "$PROJECT_ROOT/offline_packages/python_wheels/python${actual_ver}"; do
            [[ -d "$candidate" ]] && { wheels_dir="$candidate"; break; }
        done

        local pip_log="$full_path/logs/pip_install.log"
        if [[ -n "${wheels_dir:-}" && -d "$wheels_dir" ]]; then
            sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install \
                --no-index --find-links="$wheels_dir" \
                -r "$req_file" > "$pip_log" 2>&1 || \
            sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install \
                -r "$req_file" >> "$pip_log" 2>&1 || {
                log_error "  pip 설치 실패 (로그: $pip_log)"; return 1
            }
        else
            sudo -u "$RUN_USER" "$full_path/venv/bin/pip" install \
                -r "$req_file" > "$pip_log" 2>&1 || {
                log_error "  pip 설치 실패 (로그: $pip_log)"; return 1
            }
        fi

        echo "$current_hash" > "$req_hash_file"
        log_success "  pip 설치 완료"
    fi

    # systemd restart (서비스가 등록되어 있으면)
    if [[ -n "$systemd_svc" ]]; then
        if systemctl is-enabled --quiet "$systemd_svc" 2>/dev/null; then
            log_info "  $systemd_svc restart..."
            systemctl restart "$systemd_svc" && \
                log_success "  $systemd_svc 재시작됨" || \
                log_error "  $systemd_svc 재시작 실패 (journalctl -u $systemd_svc -n 30)"
        else
            log_warn "  $systemd_svc 미등록 — systemd/install_services.sh 먼저 실행 필요"
        fi
    fi
}

# ── 메인 루프 ────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$DRY_RUN" == "true" ]]; then
    echo " Dashboard 변경 감지 (dry-run)"
else
    echo " Dashboard 선택적 업데이트 배포"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DEPLOYED=0
SKIPPED=0
FAILED=0

for svc_key in $(echo "${!SERVICES[@]}" | tr ' ' '\n' | sort); do
    # --service 필터
    if [[ -n "$TARGET_SERVICE" && "$svc_key" != "$TARGET_SERVICE" ]]; then
        continue
    fi

    IFS='|' read -r svc_type svc_dir systemd_svc nginx_path <<< "${SERVICES[$svc_key]}"

    # 변경 감지
    if [[ "$FORCE_ALL" == "false" ]] && ! has_changes "$svc_key" "$svc_dir"; then
        log_info "$svc_key: 변경 없음 — 스킵"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "$svc_key: 변경 감지됨 (dry-run, 실제 배포 안 함)"
        continue
    fi

    # 배포
    if [[ "$svc_type" == "frontend" ]]; then
        if deploy_frontend "$svc_key" "$svc_dir" "$nginx_path"; then
            record_deploy "$svc_key" "$svc_dir"
            DEPLOYED=$((DEPLOYED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    else
        if deploy_backend "$svc_key" "$svc_dir" "$systemd_svc"; then
            record_deploy "$svc_key" "$svc_dir"
            DEPLOYED=$((DEPLOYED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    fi
done

# nginx reload (프론트엔드 배포 있었을 때만)
if [[ "$DEPLOYED" -gt 0 && "$DRY_RUN" == "false" ]]; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
        nginx -t 2>/dev/null && systemctl reload nginx && \
            log_success "nginx reload 완료" || log_warn "nginx reload 실패"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "dry-run 완료 — 실제 배포하려면 --dry-run 제거"
else
    log_success "배포 완료: 성공 ${DEPLOYED}, 스킵 ${SKIPPED}, 실패 ${FAILED}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
