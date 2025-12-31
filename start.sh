#!/bin/bash
################################################################################
# HPC 웹 서비스 시작 스크립트 (프로젝트 루트용)
#
# 사용법:
#   ./start.sh                    # Production Mode (기본, 빌드 건너뛰기)
#   ./start.sh --rebuild          # Production Mode (프론트엔드 재빌드)
#   ./start.sh --mock             # Mock Mode (테스트용)
#   ./start.sh --help             # 도움말
################################################################################

cd "$(dirname "$0")"
PROJECT_ROOT="$(pwd)"

echo ""
echo "============================================"
echo "  HPC 웹 서비스 시작 스크립트"
echo "  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# sudo로 실행 시 실제 사용자 찾기
RUN_USER="${SUDO_USER:-$(whoami)}"
RUN_GROUP=$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")

# ============================================================================
# PID 파일 정리 (stale PID 문제 방지) - 가장 먼저 실행됨
# ============================================================================
cleanup_pid_files() {
    local dashboard_dir="$PROJECT_ROOT/dashboard"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🧹 기존 PID 파일 정리 중..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 모든 gunicorn PID 파일 경로
    local pid_files=(
        "$dashboard_dir/auth_portal_4430/logs/gunicorn.pid"
        "$dashboard_dir/backend_5010/logs/gunicorn.pid"
        "$dashboard_dir/kooCAEWebServer_5000/logs/gunicorn.pid"
        "$dashboard_dir/kooCAEWebAutomationServer_5001/logs/gunicorn.pid"
        "$dashboard_dir/MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.pid"
        "$dashboard_dir/websocket_5011/.websocket.pid"
    )

    local cleaned=0
    for pid_file in "${pid_files[@]}"; do
        if [[ -f "$pid_file" ]]; then
            rm -f "$pid_file" 2>/dev/null || sudo rm -f "$pid_file" 2>/dev/null || true
            echo "  🗑️  삭제: ${pid_file#$dashboard_dir/}"
            ((cleaned++))
        fi
    done

    if [[ $cleaned -eq 0 ]]; then
        echo "  ✅ 정리할 PID 파일 없음"
    else
        echo "  ✅ $cleaned 개 PID 파일 정리 완료"
    fi
    echo ""
}

# PID 파일 정리 실행 (가장 먼저 실행)
cleanup_pid_files

# ============================================================================
# Slurm 경로 통합 (심볼릭 링크 생성)
# /usr/bin에 Slurm이 설치된 경우 /usr/local/slurm/bin으로 심볼릭 링크 생성
# ============================================================================
setup_slurm_paths() {
    local target_bin_path="/usr/local/slurm/bin"
    local source_bin_path="/usr/bin"

    # YAML에서 bin_path 읽기 시도
    if [[ -f "$PROJECT_ROOT/my_cluster.yaml" ]]; then
        local yaml_bin_path=$(grep -E "^\s+bin_path:" "$PROJECT_ROOT/my_cluster.yaml" 2>/dev/null | head -1 | awk '{print $2}')
        if [[ -n "$yaml_bin_path" ]]; then
            target_bin_path="$yaml_bin_path"
        fi
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 Slurm 경로 확인 및 통합..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  대상 경로: $target_bin_path"

    # Slurm 명령어 목록
    local slurm_commands=("sinfo" "squeue" "sbatch" "scancel" "scontrol" "sacct" "sacctmgr" "sreport" "srun")

    # 대상 경로에 이미 Slurm이 있는지 확인
    if [[ -x "$target_bin_path/sinfo" ]]; then
        echo "  ✅ Slurm이 $target_bin_path에 이미 존재함"
        echo ""
        return 0
    fi

    # /usr/bin에 Slurm이 있는지 확인
    if [[ -x "$source_bin_path/sinfo" ]]; then
        echo "  ⚠️  Slurm이 $source_bin_path에 설치됨 (패키지 설치 방식)"
        echo "  → $target_bin_path로 심볼릭 링크 생성 중..."

        # 대상 디렉토리 생성
        if [[ ! -d "$target_bin_path" ]]; then
            sudo mkdir -p "$target_bin_path" 2>/dev/null || {
                echo "  ❌ 디렉토리 생성 실패 (sudo 권한 필요): $target_bin_path"
                echo ""
                return 1
            }
        fi

        local linked=0
        local failed=0
        for cmd in "${slurm_commands[@]}"; do
            if [[ -x "$source_bin_path/$cmd" ]]; then
                if [[ ! -e "$target_bin_path/$cmd" ]]; then
                    if sudo ln -sf "$source_bin_path/$cmd" "$target_bin_path/$cmd" 2>/dev/null; then
                        ((linked++))
                    else
                        ((failed++))
                    fi
                fi
            fi
        done

        # sbin 명령어도 처리 (slurmctld, slurmd 등)
        local sbin_commands=("slurmctld" "slurmd" "slurmdbd")
        local target_sbin_path="${target_bin_path%/bin}/sbin"
        if [[ ! -d "$target_sbin_path" ]]; then
            sudo mkdir -p "$target_sbin_path" 2>/dev/null || true
        fi
        for cmd in "${sbin_commands[@]}"; do
            if [[ -x "/usr/sbin/$cmd" ]] && [[ ! -e "$target_sbin_path/$cmd" ]]; then
                sudo ln -sf "/usr/sbin/$cmd" "$target_sbin_path/$cmd" 2>/dev/null || true
            fi
        done

        if [[ $linked -gt 0 ]]; then
            echo "  ✅ $linked개 심볼릭 링크 생성 완료"
        fi
        if [[ $failed -gt 0 ]]; then
            echo "  ⚠️  $failed개 링크 생성 실패 (권한 문제일 수 있음)"
        fi
    else
        echo "  ❌ Slurm을 찾을 수 없음 ($source_bin_path, $target_bin_path)"
        echo "     Slurm이 설치되지 않았거나 다른 경로에 있습니다."
    fi
    echo ""
}

# Slurm 경로 통합 실행
setup_slurm_paths

# ============================================================================
# Slurm 설정 파일 호환성 검사 및 수정
# /etc/slurm/slurm.conf와 /usr/local/slurm/etc/slurm.conf 중 NodeName 정의가 있는 파일 사용
# ============================================================================
setup_slurm_conf() {
    local CONFIG_DIR="/usr/local/slurm/etc"
    local ETC_CONF="/etc/slurm/slurm.conf"
    local LOCAL_CONF="$CONFIG_DIR/slurm.conf"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Slurm 설정 파일 검증 및 동기화..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 두 설정 파일 존재 여부 확인
    local etc_exists=false
    local local_exists=false
    [[ -f "$ETC_CONF" || -L "$ETC_CONF" ]] && etc_exists=true
    [[ -f "$LOCAL_CONF" || -L "$LOCAL_CONF" ]] && local_exists=true

    if [[ "$etc_exists" == false && "$local_exists" == false ]]; then
        echo "  ⚠️  slurm.conf 파일이 없습니다"
        echo "     Slurm 설치가 필요합니다"
        echo ""
        return 0
    fi

    # NodeName 정의 확인 (tr -d로 개행 제거)
    local etc_nodes=0
    local local_nodes=0
    [[ "$etc_exists" == true ]] && etc_nodes=$(grep -c "^NodeName=" "$ETC_CONF" 2>/dev/null | tr -d '\n' || echo 0)
    [[ "$local_exists" == true ]] && local_nodes=$(grep -c "^NodeName=" "$LOCAL_CONF" 2>/dev/null | tr -d '\n' || echo 0)

    echo "  /etc/slurm/slurm.conf: $([ "$etc_exists" == true ] && echo "존재 (NodeName: ${etc_nodes}개)" || echo "없음")"
    echo "  $LOCAL_CONF: $([ "$local_exists" == true ] && echo "존재 (NodeName: ${local_nodes}개)" || echo "없음")"

    # 케이스 1: /etc/slurm에 NodeName이 없고, /usr/local/slurm/etc에 있는 경우
    #          -> /usr/local/slurm/etc/slurm.conf를 /etc/slurm/으로 복사
    if [[ "$etc_exists" == true && "$local_exists" == true &&
          "$etc_nodes" -eq 0 && "$local_nodes" -gt 0 ]]; then
        echo ""
        echo "  ⚠️  /etc/slurm/slurm.conf에 NodeName 정의가 없습니다!"
        echo "  → $LOCAL_CONF를 /etc/slurm/으로 복사 중..."
        sudo mv "$ETC_CONF" "${ETC_CONF}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        sudo cp "$LOCAL_CONF" "$ETC_CONF"
        sudo chown slurm:slurm "$ETC_CONF" 2>/dev/null || true
        echo "  ✅ 복사 완료: $LOCAL_CONF -> $ETC_CONF"

    # 케이스 2: /etc/slurm에 NodeName이 있고, /usr/local/slurm/etc에 없거나 다른 경우
    #          -> /etc/slurm/slurm.conf를 /usr/local/slurm/etc/로 복사
    elif [[ "$etc_exists" == true && "$etc_nodes" -gt 0 ]]; then
        echo ""
        if [[ "$local_exists" == false ]]; then
            echo "  → /etc/slurm/slurm.conf를 $CONFIG_DIR/로 복사 중..."
            sudo mkdir -p "$CONFIG_DIR"
            sudo cp "$ETC_CONF" "$LOCAL_CONF"
            sudo chown slurm:slurm "$LOCAL_CONF" 2>/dev/null || true
            echo "  ✅ 복사 완료: $ETC_CONF -> $LOCAL_CONF"
        elif [[ "$local_nodes" -eq 0 ]]; then
            echo "  → /etc/slurm/slurm.conf를 $CONFIG_DIR/로 복사 중..."
            sudo mv "$LOCAL_CONF" "${LOCAL_CONF}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            sudo cp "$ETC_CONF" "$LOCAL_CONF"
            sudo chown slurm:slurm "$LOCAL_CONF" 2>/dev/null || true
            echo "  ✅ 복사 완료: $ETC_CONF -> $LOCAL_CONF"
        else
            echo "  ✅ 양쪽 모두 NodeName 정의가 있습니다"
        fi

    # 케이스 3: /etc/slurm만 있고 NodeName 없음
    elif [[ "$etc_exists" == true && "$local_exists" == false && "$etc_nodes" -eq 0 ]]; then
        echo ""
        echo "  ⚠️  /etc/slurm/slurm.conf에 NodeName 정의가 없습니다!"
        echo "     올바른 slurm.conf를 $LOCAL_CONF에 배치하세요"

    # 케이스 4: /usr/local/slurm/etc만 있음
    #          -> /etc/slurm/으로 복사
    elif [[ "$etc_exists" == false && "$local_exists" == true ]]; then
        echo ""
        echo "  ℹ️  $LOCAL_CONF만 존재합니다"
        if [[ "$local_nodes" -gt 0 ]]; then
            echo "  → /etc/slurm/으로 복사 중..."
            sudo mkdir -p /etc/slurm
            sudo cp "$LOCAL_CONF" "$ETC_CONF"
            sudo chown slurm:slurm "$ETC_CONF" 2>/dev/null || true
            echo "  ✅ 복사 완료: $LOCAL_CONF -> $ETC_CONF"
        fi
    fi

    echo ""
}

# Slurm 설정 파일 호환성 검사 실행
setup_slurm_conf

# ============================================================================
# Nginx 설정 검증 및 수정 (default_server 충돌 방지)
# ============================================================================
setup_nginx_default_server() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌐 Nginx 설정 검증 및 수정..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # nginx 설치 확인
    if ! command -v nginx &>/dev/null; then
        echo "  ⚠️  nginx가 설치되지 않음 - 건너뜀"
        echo ""
        return 0
    fi

    local changed=false

    # 1. 충돌하는 sites-enabled 사이트 비활성화
    local CONFLICTING_SITES=("default" "ubuntu-mirror")
    for site in "${CONFLICTING_SITES[@]}"; do
        if [ -L "/etc/nginx/sites-enabled/$site" ] || [ -f "/etc/nginx/sites-enabled/$site" ]; then
            echo "  ⚠️  충돌 사이트 발견: $site - 비활성화 중..."
            sudo rm -f "/etc/nginx/sites-enabled/$site" 2>/dev/null || true
            echo "  ✅ $site 비활성화 완료"
            changed=true
        fi
    done

    # 2. hpc-portal.conf가 conf.d에 있는지 확인
    local HPC_CONF_SRC="$PROJECT_ROOT/dashboard/nginx/hpc-portal.conf"
    local HPC_CONF_DST="/etc/nginx/conf.d/hpc-portal.conf"

    if [ -f "$HPC_CONF_SRC" ]; then
        # 소스 파일에 default_server가 있는지 확인
        if grep -q "default_server" "$HPC_CONF_SRC"; then
            # conf.d에 복사 (최신 버전 유지)
            if ! diff -q "$HPC_CONF_SRC" "$HPC_CONF_DST" &>/dev/null 2>&1; then
                echo "  → hpc-portal.conf를 /etc/nginx/conf.d/에 복사 중..."
                sudo cp "$HPC_CONF_SRC" "$HPC_CONF_DST" 2>/dev/null || true
                changed=true
            fi
        else
            echo "  ⚠️  hpc-portal.conf에 default_server가 없음"
            echo "     ./dashboard/setup_nginx_symlink.sh 실행을 권장합니다"
        fi
    fi

    # 3. 프로젝트 디렉토리 권한 설정 (www-data가 static 파일 접근 가능하도록)
    # nginx가 alias로 프로젝트 내 dist/ 디렉토리를 서빙하므로 실행 권한 필요
    echo "  → 프로젝트 디렉토리 권한 확인..."
    local dir_path="$PROJECT_ROOT"
    while [ "$dir_path" != "/" ]; do
        if [ ! -x "$dir_path" ]; then
            echo "    → $dir_path 실행 권한 추가..."
            sudo chmod o+x "$dir_path" 2>/dev/null || true
            changed=true
        fi
        dir_path=$(dirname "$dir_path")
    done

    # dashboard 하위 dist 디렉토리들도 권한 확인
    for dist_dir in "$PROJECT_ROOT/dashboard"/*/dist; do
        if [ -d "$dist_dir" ]; then
            if [ ! -r "$dist_dir" ] || [ ! -x "$dist_dir" ]; then
                echo "    → $(basename $(dirname $dist_dir))/dist 권한 수정..."
                sudo chmod -R o+rx "$dist_dir" 2>/dev/null || true
                changed=true
            fi
        fi
    done

    # 4. 설정 변경이 있었으면 nginx 리로드
    if [ "$changed" = true ]; then
        echo "  → nginx 설정 테스트 중..."
        if sudo nginx -t &>/dev/null; then
            echo "  → nginx 리로드 중..."
            sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null || true
            echo "  ✅ nginx 설정 적용 완료"
        else
            echo "  ❌ nginx 설정 오류 - 수동 확인 필요"
            sudo nginx -t
        fi
    else
        echo "  ✅ nginx 설정 정상"
    fi
    echo ""
}

# Nginx 설정 검증 및 수정 실행
setup_nginx_default_server

# ============================================================================
# Slurm sudoers 설정 (scontrol 명령 실행 권한)
# ============================================================================
setup_slurm_sudoers() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔐 Slurm sudoers 설정 확인..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # scontrol 경로 찾기
    local SCONTROL_PATH=""
    for path in /usr/bin/scontrol /usr/local/bin/scontrol /usr/local/slurm/bin/scontrol; do
        if [ -x "$path" ]; then
            SCONTROL_PATH="$path"
            break
        fi
    done

    if [ -z "$SCONTROL_PATH" ]; then
        echo "  ⚠️  scontrol을 찾을 수 없음 - Slurm이 설치되지 않았거나 경로가 다름"
        echo ""
        return 0
    fi

    echo "  scontrol 경로: $SCONTROL_PATH"
    echo "  웹 서버 사용자: $RUN_USER"

    # sudoers 파일 경로
    local SUDOERS_FILE="/etc/sudoers.d/slurm-web"

    # 이미 설정되어 있는지 확인
    if [ -f "$SUDOERS_FILE" ] && grep -q "$RUN_USER" "$SUDOERS_FILE" 2>/dev/null; then
        echo "  ✅ sudoers 설정 이미 존재함"
        echo ""
        return 0
    fi

    # sudo 권한 확인
    if ! sudo -n true 2>/dev/null; then
        echo "  ⚠️  sudo 권한 없음 - sudoers 설정 건너뜀"
        echo "     수동으로 실행: sudo ./dashboard/setup_slurm_sudoers.sh $RUN_USER"
        echo ""
        return 0
    fi

    echo "  → sudoers 설정 생성 중..."

    # sudoers 파일 생성
    local SUDOERS_CONTENT="# Allow web server user to manage Slurm partitions without password
# Created by start.sh at $(date)

# scontrol commands for partition management
$RUN_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH create *
$RUN_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH update *
$RUN_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH delete *
"

    # 임시 파일에 작성 후 검증
    local TEMP_FILE=$(mktemp)
    echo "$SUDOERS_CONTENT" > "$TEMP_FILE"
    chmod 440 "$TEMP_FILE"

    # visudo로 문법 검증
    if sudo visudo -c -f "$TEMP_FILE" &>/dev/null; then
        sudo cp "$TEMP_FILE" "$SUDOERS_FILE"
        sudo chmod 440 "$SUDOERS_FILE"
        echo "  ✅ sudoers 설정 완료"
        echo "     $RUN_USER 사용자가 scontrol 명령을 실행할 수 있습니다"
    else
        echo "  ❌ sudoers 문법 오류 - 설정 실패"
    fi

    rm -f "$TEMP_FILE"
    echo ""
}

# Slurm sudoers 설정 실행
setup_slurm_sudoers

# ============================================================================
# Python venv 체크 및 설치 (오프라인 환경 지원)
# ============================================================================
setup_python_venvs() {
    local dashboard_dir="$PROJECT_ROOT/dashboard"
    local wheels_base="$PROJECT_ROOT/offline_packages/python_wheels"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🐍 Python venv 체크 및 설치..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Service to Python version mapping
    local service_python_map=(
        "auth_portal_4430:3.10"
        "backend_5010:3.12"
        "websocket_5011:3.10"
        "kooCAEWebServer_5000:3.13"
        "kooCAEWebAutomationServer_5001:3.13"
        "MoonlightSunshine_8004/backend_moonlight_8004:3.10"
    )

    local need_install=false

    for mapping in "${service_python_map[@]}"; do
        local service="${mapping%%:*}"
        local py_version="${mapping##*:}"
        local service_dir="$dashboard_dir/$service"

        if [[ ! -d "$service_dir" ]]; then
            continue
        fi

        # venv가 없거나 gunicorn이 없으면 설치 필요
        if [[ ! -d "$service_dir/venv" ]] || [[ ! -f "$service_dir/venv/bin/gunicorn" ]]; then
            need_install=true
            echo "  ⚠️  $service: venv 또는 gunicorn 없음 → 설치 필요"

            # Python 명령어 결정
            local python_cmd="python3"
            if command -v "python${py_version}" &>/dev/null; then
                python_cmd="python${py_version}"
            elif command -v "python3.${py_version#3.}" &>/dev/null; then
                python_cmd="python3.${py_version#3.}"
            fi

            # venv 생성 (실제 사용자로 실행)
            if [[ ! -d "$service_dir/venv" ]]; then
                echo "     → venv 생성 중 ($python_cmd)..."
                if ! sudo -u "$RUN_USER" $python_cmd -m venv "$service_dir/venv" 2>/dev/null; then
                    echo "     ❌ venv 생성 실패: $service"
                    continue
                fi
            fi

            # requirements.txt에서 패키지 설치
            if [[ -f "$service_dir/requirements.txt" ]]; then
                local actual_version=$("$service_dir/venv/bin/python" --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "$py_version")
                local wheels_dir="${wheels_base}/python${actual_version}"

                echo "     → 패키지 설치 중 (Python ${actual_version})..."

                if [[ -d "$wheels_dir" ]]; then
                    # 오프라인 설치 시도 (실제 사용자로 실행)
                    local pip_log="$service_dir/logs/pip_install.log"
                    sudo -u "$RUN_USER" mkdir -p "$service_dir/logs"
                    if sudo -u "$RUN_USER" "$service_dir/venv/bin/pip" install --no-index --find-links="$wheels_dir" -r "$service_dir/requirements.txt" 2>&1 | tee "$pip_log" | grep -q "Successfully installed\|already satisfied"; then
                        echo "     ✅ 오프라인 설치 완료"
                    else
                        # 온라인 fallback
                        echo "     ⚠️  오프라인 실패, 온라인 시도..."
                        echo "     ⚠️  오프라인 에러 로그: $pip_log"
                        if sudo -u "$RUN_USER" "$service_dir/venv/bin/pip" install -r "$service_dir/requirements.txt" 2>&1 | tee "$pip_log"; then
                            echo "     ✅ 온라인 설치 완료"
                        else
                            echo "     ❌ 설치 실패: $service"
                            echo "     ❌ 에러 로그: $pip_log"
                        fi
                    fi
                else
                    # wheels 디렉토리 없으면 온라인 설치 (실제 사용자로 실행)
                    echo "     ⚠️  오프라인 wheels 없음 ($wheels_dir), 온라인 시도..."
                    local pip_log="$service_dir/logs/pip_install.log"
                    sudo -u "$RUN_USER" mkdir -p "$service_dir/logs"
                    if sudo -u "$RUN_USER" "$service_dir/venv/bin/pip" install -r "$service_dir/requirements.txt" 2>&1 | tee "$pip_log"; then
                        echo "     ✅ 온라인 설치 완료"
                    else
                        echo "     ❌ 설치 실패: $service"
                        echo "     ❌ 에러 로그: $pip_log"
                    fi
                fi
            fi
        else
            echo "  ✅ $service: venv 준비됨"
        fi
    done

    if [[ "$need_install" == false ]]; then
        echo "  ✅ 모든 서비스 venv 준비 완료"
    fi
    echo ""
}

# venv 관련 옵션 파싱
SKIP_VENV=false
for arg in "$@"; do
    if [[ "$arg" == "--skip-venv" ]]; then
        SKIP_VENV=true
    fi
done

# systemd 서비스 설치 옵션이 있으면 venv 체크 건너뛰기 (install_services.sh가 담당)
for arg in "$@"; do
    if [[ "$arg" == "--install" ]] || [[ "$arg" == "--reinstall" ]]; then
        SKIP_VENV=true
        break
    fi
done

if [[ "$SKIP_VENV" == false ]]; then
    setup_python_venvs
fi

# ============================================================================
# logs 디렉토리 생성 및 권한 수정
# ============================================================================
setup_logs_directories() {
    local dashboard_dir="$PROJECT_ROOT/dashboard"
    # sudo로 실행 시 실제 사용자 찾기 (SUDO_USER 또는 whoami)
    local current_user="${SUDO_USER:-$(whoami)}"
    local current_group=$(id -gn "$current_user" 2>/dev/null || echo "$current_user")

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📁 logs 디렉토리 준비..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 모든 백엔드 서비스 목록
    local services=(
        "auth_portal_4430"
        "backend_5010"
        "websocket_5011"
        "kooCAEWebServer_5000"
        "kooCAEWebAutomationServer_5001"
        "MoonlightSunshine_8004/backend_moonlight_8004"
    )

    for service in "${services[@]}"; do
        local service_dir="$dashboard_dir/$service"
        local logs_dir="$service_dir/logs"

        if [[ ! -d "$service_dir" ]]; then
            continue
        fi

        # logs 디렉토리 생성 (실제 사용자로 실행)
        if [[ ! -d "$logs_dir" ]]; then
            sudo -u "$current_user" mkdir -p "$logs_dir" 2>/dev/null || mkdir -p "$logs_dir"
            sudo chown "$current_user:$current_group" "$logs_dir" 2>/dev/null || true
            echo "  ✅ $service/logs 생성됨"
        fi

        # 권한 수정 (현재 사용자가 쓸 수 있도록)
        if [[ -d "$logs_dir" ]]; then
            # 쓰기 불가능한 파일이 있으면 삭제 후 재생성 (소유자 문제 해결)
            local unwritable_files=$(find "$logs_dir" -type f ! -writable 2>/dev/null)
            if [[ -n "$unwritable_files" ]]; then
                echo "  🔧 $service/logs: 쓰기 불가 파일 삭제 중..."
                # sudo로 삭제 시도, 실패하면 일반 삭제
                for f in $unwritable_files; do
                    sudo rm -f "$f" 2>/dev/null || rm -f "$f" 2>/dev/null || true
                done
                echo "  ✅ $service/logs: 권한 문제 해결됨"
            fi

            # 디렉토리 권한 확인 및 수정
            if [[ ! -w "$logs_dir" ]]; then
                sudo chmod 755 "$logs_dir" 2>/dev/null || chmod 755 "$logs_dir" 2>/dev/null || true
                sudo chown "$current_user:$current_group" "$logs_dir" 2>/dev/null || true
                echo "  🔧 $service/logs 디렉토리 권한 수정됨"
            fi
        fi
    done

    echo "  ✅ logs 디렉토리 준비 완료"
    echo ""
}

# logs 디렉토리 준비 실행
setup_logs_directories

# ============================================================================
# Prometheus 데이터 정리 (WAL 손상 방지)
# ============================================================================
cleanup_prometheus_data() {
    local prometheus_dir="$PROJECT_ROOT/dashboard/prometheus_9090"
    local data_dir="$prometheus_dir/data"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 Prometheus 데이터 정리..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ ! -d "$data_dir" ]]; then
        echo "  ℹ️  Prometheus 데이터 디렉토리 없음 (새로운 설치)"
        echo ""
        return 0
    fi

    # WAL 및 chunks_head 정리 (손상 방지)
    local cleaned=0

    # WAL 디렉토리 정리
    if [[ -d "$data_dir/wal" ]]; then
        local wal_count=$(find "$data_dir/wal" -type f 2>/dev/null | wc -l)
        if [[ $wal_count -gt 0 ]]; then
            echo "  → WAL 파일 정리 중 ($wal_count 개 파일)..."
            rm -rf "$data_dir/wal"/* 2>/dev/null || sudo rm -rf "$data_dir/wal"/* 2>/dev/null || true
            ((cleaned++))
        fi
    fi

    # chunks_head 디렉토리 정리
    if [[ -d "$data_dir/chunks_head" ]]; then
        local chunks_count=$(find "$data_dir/chunks_head" -type f 2>/dev/null | wc -l)
        if [[ $chunks_count -gt 0 ]]; then
            echo "  → chunks_head 파일 정리 중 ($chunks_count 개 파일)..."
            rm -rf "$data_dir/chunks_head"/* 2>/dev/null || sudo rm -rf "$data_dir/chunks_head"/* 2>/dev/null || true
            ((cleaned++))
        fi
    fi

    # lock 파일 정리
    if [[ -f "$data_dir/lock" ]]; then
        echo "  → lock 파일 정리..."
        rm -f "$data_dir/lock" 2>/dev/null || sudo rm -f "$data_dir/lock" 2>/dev/null || true
        ((cleaned++))
    fi

    # 임시 삭제 디렉토리 정리 (.tmp-for-deletion)
    local tmp_dirs=$(find "$data_dir" -type d -name "*.tmp-for-deletion" 2>/dev/null)
    if [[ -n "$tmp_dirs" ]]; then
        echo "  → 임시 삭제 디렉토리 정리..."
        echo "$tmp_dirs" | while read dir; do
            rm -rf "$dir" 2>/dev/null || sudo rm -rf "$dir" 2>/dev/null || true
        done
        ((cleaned++))
    fi

    if [[ $cleaned -eq 0 ]]; then
        echo "  ✅ 정리할 데이터 없음"
    else
        echo "  ✅ Prometheus 데이터 정리 완료"
    fi
    echo ""
}

# ============================================================================
# 기존 프로세스 정리 (포트 기반)
# ============================================================================
cleanup_existing_processes() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🧹 기존 프로세스 정리..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 서비스별 포트 정의 (백엔드 + 프론트엔드 dev 서버 포함)
    local SERVICE_PORTS=(
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

    # 1단계: 프로세스 이름 기반 정리
    echo "  → 프로세스 이름 기반 정리..."
    pkill -f "gunicorn.*auth_portal" 2>/dev/null || true
    pkill -f "gunicorn.*backend_5010" 2>/dev/null || true
    pkill -f "gunicorn.*kooCAEWebServer" 2>/dev/null || true
    pkill -f "gunicorn.*kooCAEWebAutomation" 2>/dev/null || true
    pkill -f "websocket_server_enhanced" 2>/dev/null || true
    pkill -f "vite.*3010" 2>/dev/null || true
    pkill -f "vite.*4431" 2>/dev/null || true
    pkill -f "vite.*5173" 2>/dev/null || true
    pkill -f "vite.*5174" 2>/dev/null || true
    pkill -f "node.*vite" 2>/dev/null || true

    # 2단계: 포트 기반 정리
    echo "  → 포트 기반 정리..."
    for port_info in "${SERVICE_PORTS[@]}"; do
        local port="${port_info%%:*}"
        local name="${port_info##*:}"

        local pids=$(lsof -t -i :$port 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            echo "    포트 $port ($name): PID $pids 종료 중..."
            for pid in $pids; do
                kill $pid 2>/dev/null || sudo kill $pid 2>/dev/null || true
            done
        fi
    done

    sleep 2

    # 3단계: 강제 종료 (아직 남아있는 경우)
    echo "  → 잔여 프로세스 강제 종료..."
    for port_info in "${SERVICE_PORTS[@]}"; do
        local port="${port_info%%:*}"
        local pids=$(lsof -t -i :$port 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            for pid in $pids; do
                kill -9 $pid 2>/dev/null || sudo kill -9 $pid 2>/dev/null || true
            done
        fi
    done

    sleep 1

    # 4단계: 클린 상태 확인
    echo "  → 클린 상태 확인..."
    local clean_state=true
    local occupied_ports=()
    for port_info in "${SERVICE_PORTS[@]}"; do
        local port="${port_info%%:*}"
        local name="${port_info##*:}"

        if lsof -i :$port > /dev/null 2>&1; then
            occupied_ports+=("$port($name)")
            clean_state=false
        fi
    done

    if [[ "$clean_state" == true ]]; then
        echo "  ✅ 모든 서비스 포트 정리 완료"
    else
        echo "  ⚠️  일부 포트가 여전히 사용 중: ${occupied_ports[*]}"
        echo "     계속 진행합니다..."
    fi
    echo ""
}

# ============================================================================
# 서비스 상태 체크 및 테스트
# ============================================================================
check_services_health() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 서비스 상태 체크 및 테스트..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 잠시 대기 (서비스 시작 시간 확보)
    sleep 3

    local all_ok=true
    local failed_services=()

    # 서비스 정의: "이름:포트:헬스체크경로:설명"
    local services=(
        "Auth Portal:4430:/health:인증 서비스"
        "Backend API:5010:/api/health:메인 백엔드"
        "WebSocket:5011:/health:WebSocket 서비스"
        "Prometheus:9090:/-/healthy:모니터링"
        "Node Exporter:9100:/metrics:노드 메트릭"
        "CAE Server:5000:/health:CAE 웹서버"
        "CAE Automation:5001:/health:CAE 자동화"
    )

    for service_info in "${services[@]}"; do
        IFS=':' read -r name port path desc <<< "$service_info"
        check_single_service "$name" "$port" "$path" "$desc"
        if [[ $? -ne 0 ]]; then
            all_ok=false
            failed_services+=("$name")
        fi
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$all_ok" == true ]]; then
        echo "✅ 모든 서비스 정상 작동 중"
    else
        echo "⚠️  일부 서비스 문제 발견:"
        for svc in "${failed_services[@]}"; do
            echo "   - $svc"
        done
        echo ""
        echo "💡 문제 해결 팁:"
        echo "   - journalctl -u <서비스명> -n 50  # systemd 로그 확인"
        echo "   - cat dashboard/<서비스>/logs/*.log  # 앱 로그 확인"
        echo "   - systemctl status <서비스명>  # 서비스 상태 확인"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 단일 서비스 체크
check_single_service() {
    local name="$1"
    local port="$2"
    local path="$3"
    local desc="$4"
    local url="http://localhost:${port}${path}"

    printf "  %-20s (:%s) ... " "$name" "$port"

    # 1. 포트가 열려있는지 확인
    if ! nc -z localhost "$port" 2>/dev/null; then
        echo "❌ 포트 닫힘"
        diagnose_service_failure "$name" "$port"
        return 1
    fi

    # 2. HTTP 헬스체크
    local response
    local http_code
    response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "$url" 2>/dev/null)
    http_code=$?

    if [[ $http_code -ne 0 ]]; then
        echo "❌ 연결 실패"
        diagnose_service_failure "$name" "$port"
        return 1
    fi

    case "$response" in
        200|204)
            echo "✅ 정상"
            return 0
            ;;
        401|403)
            echo "✅ 정상 (인증 필요)"
            return 0
            ;;
        404)
            # 헬스체크 엔드포인트가 없지만 서버는 응답함
            echo "⚠️  응답 (헬스체크 없음)"
            return 0
            ;;
        5*)
            echo "❌ 서버 에러 ($response)"
            diagnose_service_failure "$name" "$port"
            return 1
            ;;
        *)
            echo "⚠️  HTTP $response"
            return 0
            ;;
    esac
}

# 서비스 실패 진단
diagnose_service_failure() {
    local name="$1"
    local port="$2"
    local dashboard_dir="$PROJECT_ROOT/dashboard"

    echo ""
    echo "     ┌─────────────────────────────────────────────────"
    echo "     │ 📋 $name 진단 정보"
    echo "     ├─────────────────────────────────────────────────"

    # 서비스 디렉토리 매핑 (phase5_web.sh에서 생성하는 실제 서비스 이름과 일치)
    local service_dir=""
    local systemd_name=""
    case "$name" in
        "Auth Portal")
            service_dir="$dashboard_dir/auth_portal_4430"
            systemd_name="auth_backend"
            ;;
        "Backend API")
            service_dir="$dashboard_dir/backend_5010"
            systemd_name="dashboard_backend"
            ;;
        "WebSocket")
            service_dir="$dashboard_dir/websocket_5011"
            systemd_name="websocket_service"
            ;;
        "Prometheus")
            service_dir="$dashboard_dir/prometheus_9090"
            # 여러 가능한 서비스 이름 체크
            for svc in "prometheus" "prometheus-server"; do
                if systemctl is-active --quiet "$svc" 2>/dev/null; then
                    systemd_name="$svc"
                    break
                fi
            done
            [[ -z "$systemd_name" ]] && systemd_name="prometheus"
            ;;
        "Node Exporter")
            service_dir="$dashboard_dir/node_exporter_9100"
            # apt 설치 시 prometheus-node-exporter 이름 사용
            for svc in "node_exporter" "prometheus-node-exporter" "node-exporter"; do
                if systemctl is-active --quiet "$svc" 2>/dev/null; then
                    systemd_name="$svc"
                    break
                fi
            done
            [[ -z "$systemd_name" ]] && systemd_name="node_exporter"
            ;;
        "CAE Server")
            service_dir="$dashboard_dir/kooCAEWebServer_5000"
            systemd_name="cae_backend"
            ;;
        "CAE Automation")
            service_dir="$dashboard_dir/kooCAEWebAutomationServer_5001"
            systemd_name="cae_automation"
            ;;
    esac

    # 1. 프로세스 확인
    local pid_count
    pid_count=$(lsof -i :"$port" 2>/dev/null | grep -c LISTEN 2>/dev/null || true)
    pid_count=${pid_count:-0}
    pid_count=$(echo "$pid_count" | tr -d '[:space:]')
    if [[ -z "$pid_count" ]] || [[ "$pid_count" -eq 0 ]]; then
        echo "     │ ❌ 원인: 프로세스가 실행되지 않음"
    else
        echo "     │ ✓ 프로세스 실행 중 (${pid_count}개)"
    fi

    # 2. systemd 서비스 상태 확인
    if systemctl is-active --quiet "$systemd_name" 2>/dev/null; then
        echo "     │ ✓ systemd 서비스 활성화됨"
    else
        local status=$(systemctl is-active "$systemd_name" 2>/dev/null || echo "unknown")
        if [[ "$status" != "unknown" ]]; then
            echo "     │ ❌ systemd 상태: $status"
            # 최근 에러 로그
            local error_log=$(journalctl -u "$systemd_name" -n 3 --no-pager 2>/dev/null | tail -3)
            if [[ -n "$error_log" ]]; then
                echo "     │ 📜 최근 로그:"
                echo "$error_log" | while read line; do
                    echo "     │    $line"
                done
            fi
        fi
    fi

    # 3. 바이너리/venv 존재 확인
    if [[ -n "$service_dir" ]] && [[ -d "$service_dir" ]]; then
        # Python 서비스
        if [[ -d "$service_dir/venv" ]]; then
            if [[ ! -f "$service_dir/venv/bin/gunicorn" ]]; then
                echo "     │ ❌ gunicorn 미설치: $service_dir/venv/bin/gunicorn"
            fi
        elif [[ -f "$service_dir/prometheus" ]] || [[ -f "$service_dir/node_exporter" ]]; then
            # Prometheus/Node Exporter 바이너리
            local binary=""
            if [[ -f "$service_dir/prometheus" ]]; then
                binary="$service_dir/prometheus"
            elif [[ -f "$service_dir/node_exporter" ]]; then
                binary="$service_dir/node_exporter"
            fi
            if [[ -n "$binary" ]] && [[ ! -x "$binary" ]]; then
                echo "     │ ❌ 바이너리 실행 권한 없음: $binary"
            fi
        else
            echo "     │ ❌ venv 또는 바이너리 없음: $service_dir"
        fi

        # 4. 로그 파일 확인
        if [[ -d "$service_dir/logs" ]]; then
            local latest_log=$(ls -t "$service_dir/logs"/*.log 2>/dev/null | head -1)
            if [[ -n "$latest_log" ]]; then
                local last_error=$(grep -i "error\|exception\|failed\|traceback" "$latest_log" 2>/dev/null | tail -3)
                if [[ -n "$last_error" ]]; then
                    echo "     │ 📜 최근 에러 로그 ($latest_log):"
                    echo "$last_error" | while read line; do
                        echo "     │    ${line:0:60}..."
                    done
                fi
            fi
        fi
    fi

    # 5. 포트 충돌 확인
    local other_process=$(lsof -i :$port 2>/dev/null | grep -v "^COMMAND" | head -1)
    if [[ -n "$other_process" ]]; then
        local proc_name=$(echo "$other_process" | awk '{print $1}')
        local proc_pid=$(echo "$other_process" | awk '{print $2}')
        echo "     │ ℹ️  포트 $port 사용 중: $proc_name (PID: $proc_pid)"
    fi

    # 6. 의존성 확인 (Redis, Slurm 등)
    case "$name" in
        "Backend API"|"WebSocket"|"Auth Portal")
            if ! nc -z localhost 6379 2>/dev/null; then
                echo "     │ ⚠️  Redis (6379) 연결 불가 - 세션 관리 영향"
            fi
            ;;
        "Backend API")
            # Slurm 확인
            local slurm_bin="${SLURM_BIN_DIR:-/usr/local/slurm/bin}"
            if [[ ! -x "$slurm_bin/sinfo" ]]; then
                echo "     │ ⚠️  Slurm 명령어 없음: $slurm_bin/sinfo"
            fi
            # Prometheus 확인
            if ! nc -z localhost 9090 2>/dev/null; then
                echo "     │ ⚠️  Prometheus (9090) 연결 불가 - 모니터링 영향"
            fi
            ;;
    esac

    echo "     └─────────────────────────────────────────────────"
    echo ""
}

# 도움말 출력
show_help() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 HPC 웹 서비스 시작 스크립트"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "사용법:"
    echo "  ./start.sh                    Production Mode (기본)"
    echo ""
    echo "Production Mode 옵션:"
    echo "  ./start.sh --install          systemd 서비스 최초 설치"
    echo "  ./start.sh --reinstall        venv 재설치 + 서비스 설치"
    echo "  ./start.sh --rebuild          프론트엔드 재빌드"
    echo "  ./start.sh --skip-build       프론트엔드 빌드 건너뛰기"
    echo ""
    echo "진단 옵션:"
    echo "  ./start.sh --check            서비스 상태만 체크 (시작 없이)"
    echo ""
    echo "기타 옵션:"
    echo "  ./start.sh --dev              Development Mode (Flask dev server)"
    echo "  ./start.sh --mock             Mock Mode (테스트용)"
    echo "  ./start.sh --help             이 도움말 표시"
    echo ""
    echo "모드 설명:"
    echo "  🏭 Production Mode (기본):"
    echo "     - Gunicorn WSGI 서버"
    echo "     - 리소스 제한 적용 가능"
    echo "     - 실제 Slurm 클러스터 연동"
    echo "     - 프로덕션 환경용"
    echo "     - --rebuild: 프론트엔드 재빌드 (5-10분 소요)"
    echo "     - --skip-build: 빌드 건너뛰기 (빠른 재시작, 기본값)"
    echo ""
    echo "  🔧 Development Mode:"
    echo "     - Flask 개발 서버"
    echo "     - 코드 변경 시 자동 재시작"
    echo "     - 디버깅 활성화"
    echo "     - 개발 환경용"
    echo ""
    echo "  🎭 Mock Mode:"
    echo "     - Flask 개발 서버"
    echo "     - Slurm 없이 실행 가능"
    echo "     - 고정된 테스트 데이터"
    echo "     - 개발/테스트/데모용"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 인자 파싱
MODE="production"  # Default: production
EXTRA_ARGS=()      # start_production.sh에 전달할 추가 인자
CHECK_ONLY=false   # --check 옵션용

for arg in "$@"; do
    case $arg in
        --dev)
            MODE="development"
            shift
            ;;
        --mock)
            MODE="mock"
            shift
            ;;
        --production)
            MODE="production"
            shift
            ;;
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --rebuild|--skip-build|--install|--reinstall)
            # Production 모드 전용 플래그는 start_production.sh로 전달
            EXTRA_ARGS+=("$arg")
            shift
            ;;
        --skip-venv)
            # start.sh에서만 처리하는 옵션 (이미 위에서 파싱됨, 전달하지 않음)
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            # 알 수 없는 인자는 그대로 전달 (호환성 유지)
            EXTRA_ARGS+=("$arg")
            shift
            ;;
    esac
done

# --check 옵션: 서비스 상태만 체크하고 종료
if [[ "$CHECK_ONLY" == true ]]; then
    check_services_health
    exit 0
fi

# 모드 선택
case $MODE in
    development)
        if [ -f "dashboard/start_dev.sh" ]; then
            echo "🔧 HPC 웹 서비스 시작 중 (Development Mode - Flask)..."
            cleanup_existing_processes
            ./dashboard/start_dev.sh
        else
            echo "❌ 오류: dashboard/start_dev.sh 파일을 찾을 수 없습니다."
            echo "   현재 디렉토리: $(pwd)"
            exit 1
        fi
        ;;
    mock)
        if [ -f "dashboard/start_mock.sh" ]; then
            echo "🎭 HPC 웹 서비스 시작 중 (Mock Mode - Flask)..."
            cleanup_existing_processes
            ./dashboard/start_mock.sh
        else
            echo "❌ 오류: dashboard/start_mock.sh 파일을 찾을 수 없습니다."
            echo "   현재 디렉토리: $(pwd)"
            exit 1
        fi
        ;;
    production)
        if [ -f "dashboard/start_production.sh" ]; then
            echo "🏭 HPC 웹 서비스 시작 중 (Production Mode - Gunicorn)..."

            # 기존 프로세스 정리 (start.sh 단독 실행 또는 --skip-cleanup 없을 때)
            cleanup_existing_processes

            # Prometheus 데이터 정리 (WAL 손상 방지)
            cleanup_prometheus_data

            ./dashboard/start_production.sh "${EXTRA_ARGS[@]}"

            # 서비스 시작 후 상태 체크
            echo ""
            check_services_health

            # YAML 기반 Slurm 파티션 초기화
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "🔧 YAML 기반 노드 그룹 및 Slurm 파티션 초기화..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            sleep 2  # 백엔드 서비스가 완전히 시작될 때까지 대기

            # Backend API가 응답하는지 확인
            if curl -s --connect-timeout 5 http://127.0.0.1:5010/api/health > /dev/null 2>&1; then
                # YAML 기반 초기화 API 호출
                INIT_RESULT=$(curl -s -X POST http://127.0.0.1:5010/api/yaml/init-startup 2>&1)

                if echo "$INIT_RESULT" | grep -q '"success": true\|"success":true'; then
                    echo ""
                    echo "  ┌─ 노드 그룹 초기화 결과 ─────────────────────"

                    # YAML 파일 경로 출력
                    YAML_PATH=$(echo "$INIT_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('yaml_path',''))" 2>/dev/null)
                    if [[ -n "$YAML_PATH" ]]; then
                        echo "  │ 📄 YAML 파일: $YAML_PATH"
                    fi

                    # 노드 그룹 정보 출력
                    echo "$INIT_RESULT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    groups = d.get('groups', [])
    if groups:
        print(f'  │ 📊 노드 그룹: {len(groups)}개')
        for g in groups:
            name = g.get('name', 'Unknown')
            partition = g.get('partitionName', '-')
            nodes = g.get('nodes', [])
            color = g.get('color', '')
            print(f'  │    • {name} (파티션: {partition}, 노드: {len(nodes)}개)')
except:
    pass
" 2>/dev/null

                    # 총 노드 수 출력
                    echo "$INIT_RESULT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    summary = d.get('summary', {})
    total = summary.get('totalNodes', 0)
    compute = summary.get('computeNodes', 0)
    viz = summary.get('vizNodes', 0)
    controller = summary.get('controllerNodes', 0)
    if total > 0:
        print(f'  │ 🖥️  총 노드: {total}개 (Compute: {compute}, VIZ: {viz}, Controller: {controller})')
except:
    pass
" 2>/dev/null

                    echo "  │"

                    # Slurm 동기화 결과 확인
                    if echo "$INIT_RESULT" | grep -q '"slurm_available": true\|"slurm_available":true'; then
                        echo "  │ ✅ Slurm 파티션 동기화"

                        # 파티션별 상세 결과 출력
                        echo "$INIT_RESULT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    slurm = d.get('slurm_sync', {})
    partitions = slurm.get('partitions', {})
    for name, info in partitions.items():
        success = info.get('success', False)
        message = info.get('message', '')
        nodes = info.get('nodes', 0)
        status = '✅' if success else '❌'
        print(f'  │    {status} {name}: {message}')
except:
    pass
" 2>/dev/null
                    elif echo "$INIT_RESULT" | grep -q 'Slurm not available'; then
                        echo "  │ ⚠️  Slurm이 설치되지 않았거나 사용 불가능"
                        echo "  │    파티션 동기화를 건너뜁니다"
                    else
                        echo "  │ ℹ️  Slurm 동기화 정보 없음"
                    fi

                    echo "  └───────────────────────────────────────────"
                else
                    echo "  ⚠️  초기화 실패 또는 YAML 파일 없음"
                    # 에러 상세 출력
                    ERROR_MSG=$(echo "$INIT_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null)
                    if [[ -n "$ERROR_MSG" ]]; then
                        echo "     에러: $ERROR_MSG"
                    else
                        echo "     응답: ${INIT_RESULT:0:200}"
                    fi
                fi
            else
                echo "  ⚠️  Backend API (5010) 응답 없음 - 초기화 건너뜀"
            fi
            echo ""
        else
            echo "❌ 오류: dashboard/start_production.sh 파일을 찾을 수 없습니다."
            echo "   현재 디렉토리: $(pwd)"
            exit 1
        fi
        ;;
esac
