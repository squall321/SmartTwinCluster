#!/bin/bash
################################################################################
# Dashboard 서비스 상태 점검 + 에러 로그 통합 출력
#
# 사용법:
#   ./check_services.sh               # 전체 상태 + 최근 에러
#   ./check_services.sh --service backend_5010   # 특정 서비스만
#   ./check_services.sh --lines 50    # 에러 로그 출력 줄 수 (기본 20)
#   ./check_services.sh --errors-only # 에러 있는 서비스만 출력
#   ./check_services.sh --watch       # 5초마다 갱신
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# ── 서비스 정의: "systemd서비스명|디렉토리|포트|HealthURL" ──────────────────
declare -A SERVICES=(
    ["auth_portal_4430"]="auth_backend|auth_portal_4430|4430|http://localhost:4430/health"
    ["auth_portal_4431"]="||4431|http://localhost:4431"
    ["backend_5010"]="dashboard_backend|backend_5010|5010|http://localhost:5010/api/health"
    ["websocket_5011"]="websocket_service|websocket_5011|5011|"
    ["kooCAEWebServer_5000"]="cae_backend|kooCAEWebServer_5000|5000|http://localhost:5000/health"
    ["kooCAEWebAutomationServer_5001"]="cae_automation|kooCAEWebAutomationServer_5001|5001|"
    ["frontend_3010"]="||3010|http://localhost:3010"
    ["moonlight_frontend_8003"]="||8003|http://localhost:8003"
    ["vnc_service_8002"]="||8002|"
)

# ── 서비스별 에러 로그 파일 목록 ─────────────────────────────────────────────
declare -A ERROR_LOGS=(
    ["auth_portal_4430"]="auth_portal_4430/logs/auth_backend.log auth_portal_4430/logs/gunicorn_error.log"
    ["backend_5010"]="backend_5010/backend.log backend_5010/logs/gunicorn_error.log"
    ["websocket_5011"]="websocket_5011/logs/websocket_error.log websocket_5011/websocket.log"
    ["kooCAEWebServer_5000"]="kooCAEWebServer_5000/logs/gunicorn_error.log kooCAEWebServer_5000/app.log"
    ["kooCAEWebAutomationServer_5001"]="kooCAEWebAutomationServer_5001/logs/gunicorn_error.log"
)

# ── 옵션 파싱 ────────────────────────────────────────────────────────────────
TARGET_SERVICE=""
LOG_LINES=20
ERRORS_ONLY=false
WATCH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --service)     TARGET_SERVICE="$2"; shift 2 ;;
        --lines)       LOG_LINES="$2"; shift 2 ;;
        --errors-only) ERRORS_ONLY=true; shift ;;
        --watch)       WATCH=true; shift ;;
        --help|-h)     head -15 "$0" | grep "^#" | sed 's/^# \?//'; exit 0 ;;
        *) shift ;;
    esac
done

# ── 헬퍼 ─────────────────────────────────────────────────────────────────────
port_listening() {
    ss -tlnp 2>/dev/null | grep -q ":$1 " || \
    netstat -tlnp 2>/dev/null | grep -q ":$1 "
}

http_ok() {
    [[ -z "$1" ]] && return 1
    curl -sf --max-time 2 "$1" -o /dev/null
}

extract_errors() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && return
    grep -n "ERROR\|CRITICAL\|Traceback\|Exception\|Error:" "$log_file" 2>/dev/null | \
        tail -"$LOG_LINES" | sed 's/^/    /'
}

journal_errors() {
    local svc="$1"
    [[ -z "$svc" ]] && return
    journalctl -u "$svc" --no-pager -p err -n "$LOG_LINES" 2>/dev/null | \
        grep -v "^--" | sed 's/^/    /'
}

# ── 단일 서비스 점검 ──────────────────────────────────────────────────────────
check_service() {
    local svc_key="$1"
    IFS='|' read -r systemd_svc svc_dir port health_url <<< "${SERVICES[$svc_key]}"

    # 상태 판정
    local status="—"
    local sd_label=""
    if [[ -n "$systemd_svc" ]]; then
        status=$(systemctl is-active "$systemd_svc" 2>/dev/null || echo "inactive")
        if [[ "$status" == "active" ]]; then
            sd_label="${GREEN}active${NC}"
        else
            sd_label="${RED}${status}${NC}"
        fi
    fi

    local port_ok=false
    [[ -n "$port" ]] && port_listening "$port" && port_ok=true

    local http_label="${GRAY}—${NC}"
    if [[ -n "$health_url" ]]; then
        http_ok "$health_url" && http_label="${GREEN}OK${NC}" || http_label="${RED}FAIL${NC}"
    fi

    # 에러 수집
    local has_error=false
    [[ "$status" != "active" && "$status" != "—" ]] && has_error=true
    [[ "$port_ok" == "false" && -n "$port" ]] && has_error=true

    local file_errors=""
    for log_file in ${ERROR_LOGS[$svc_key]:-}; do
        local extracted
        extracted=$(extract_errors "$SCRIPT_DIR/$log_file")
        if [[ -n "$extracted" ]]; then
            file_errors+="  ${GRAY}── $(basename "$log_file") ──${NC}\n${extracted}\n"
            has_error=true
        fi
    done

    local journal_out=""
    if [[ -n "$systemd_svc" ]]; then
        journal_out=$(journal_errors "$systemd_svc")
        [[ -n "$journal_out" ]] && has_error=true
    fi

    [[ "$ERRORS_ONLY" == "true" && "$has_error" == "false" ]] && return

    # 헤더
    if [[ "$status" == "active" && "$port_ok" == "true" ]]; then
        echo -e "${GREEN}● ${svc_key}${NC}"
    elif [[ "$status" == "active" || "$port_ok" == "true" ]]; then
        echo -e "${YELLOW}◐ ${svc_key}${NC}"
    else
        echo -e "${RED}○ ${svc_key}${NC}"
    fi

    # 상태 줄
    local port_label="${GRAY}—${NC}"
    if [[ -n "$port" ]]; then
        [[ "$port_ok" == "true" ]] && port_label="${GREEN}:${port}${NC}" || port_label="${RED}:${port} 닫힘${NC}"
    fi
    [[ -n "$systemd_svc" ]] && echo -e "  systemd: $sd_label  포트: $port_label  HTTP: $http_label" \
                             || echo -e "  포트: $port_label  HTTP: $http_label"

    # 에러 로그
    if [[ -n "$file_errors" ]]; then
        echo -e "  ${RED}▼ 에러 로그 (최근 ${LOG_LINES}줄)${NC}"
        echo -e "$file_errors"
    fi
    if [[ -n "$journal_out" ]]; then
        echo -e "  ${RED}▼ journalctl 에러${NC}"
        echo -e "$journal_out"
        echo ""
    fi
    [[ "$has_error" == "false" ]] && echo -e "  ${GRAY}에러 없음${NC}"

    echo ""
}

# ── 메인 ─────────────────────────────────────────────────────────────────────
run_check() {
    clear 2>/dev/null || true
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN} Dashboard 서비스 상태  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    [[ "$ERRORS_ONLY" == "true" ]] && echo -e "${YELLOW} (에러 있는 서비스만)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    for svc_key in $(echo "${!SERVICES[@]}" | tr ' ' '\n' | sort); do
        [[ -n "$TARGET_SERVICE" && "$svc_key" != "$TARGET_SERVICE" ]] && continue
        check_service "$svc_key"
    done

    # nginx
    if [[ -z "$TARGET_SERVICE" ]]; then
        echo -e "${CYAN}── nginx ──────────────────────────────────────────${NC}"
        if systemctl is-active --quiet nginx 2>/dev/null; then
            echo -e "${GREEN}● nginx: active${NC}"
            local nginx_err
            nginx_err=$(journalctl -u nginx --no-pager -p err -n 5 2>/dev/null | grep -v "^--" | sed 's/^/  /')
            [[ -n "$nginx_err" ]] && echo -e "  ${RED}▼ 최근 에러:${NC}\n$nginx_err"
        else
            echo -e "${RED}○ nginx: $(systemctl is-active nginx 2>/dev/null || echo inactive)${NC}"
        fi
        echo ""
    fi

    [[ "$WATCH" == "true" ]] && echo -e "${GRAY}(5초마다 갱신 — Ctrl+C 종료)${NC}"
}

if [[ "$WATCH" == "true" ]]; then
    while true; do run_check; sleep 5; done
else
    run_check
fi
