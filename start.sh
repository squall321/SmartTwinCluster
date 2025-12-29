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

# sudo로 실행 시 실제 사용자 찾기
RUN_USER="${SUDO_USER:-$(whoami)}"
RUN_GROUP=$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")

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

        # venv가 없거나 gunicorn이 없거나 --force-install 옵션이 있으면 설치 필요
        if [[ ! -d "$service_dir/venv" ]] || [[ ! -f "$service_dir/venv/bin/gunicorn" ]] || [[ "$FORCE_INSTALL" == true ]]; then
            need_install=true
            if [[ "$FORCE_INSTALL" == true ]]; then
                echo "  🔄 $service: 강제 재설치 (--force-install)"
            else
                echo "  ⚠️  $service: venv 또는 gunicorn 없음 → 설치 필요"
            fi

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
FORCE_INSTALL=false
for arg in "$@"; do
    if [[ "$arg" == "--skip-venv" ]]; then
        SKIP_VENV=true
    fi
    if [[ "$arg" == "--force-install" ]]; then
        FORCE_INSTALL=true
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

# 도움말 출력
show_help() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 HPC 웹 서비스 시작 스크립트"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "사용법:"
    echo "  ./start.sh                 Production Mode (기본, 빌드 건너뛰기)"
    echo "  ./start.sh --rebuild       Production Mode (프론트엔드 재빌드)"
    echo "  ./start.sh --skip-build    Production Mode (명시적으로 빌드 건너뛰기)"
    echo "  ./start.sh --skip-venv     venv 체크/설치 건너뛰기"
    echo "  ./start.sh --force-install 모든 venv 패키지 강제 재설치"
    echo "  ./start.sh --dev           Development Mode (Flask dev server)"
    echo "  ./start.sh --mock          Mock Mode (테스트용)"
    echo "  ./start.sh --help          이 도움말 표시"
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
        --rebuild|--skip-build)
            # Production 모드 전용 플래그는 start_production.sh로 전달
            EXTRA_ARGS+=("$arg")
            shift
            ;;
        --skip-venv|--force-install)
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

# 모드 선택
case $MODE in
    development)
        if [ -f "dashboard/start_dev.sh" ]; then
            echo "🔧 HPC 웹 서비스 시작 중 (Development Mode - Flask)..."
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
            ./dashboard/start_production.sh "${EXTRA_ARGS[@]}"
        else
            echo "❌ 오류: dashboard/start_production.sh 파일을 찾을 수 없습니다."
            echo "   현재 디렉토리: $(pwd)"
            exit 1
        fi
        ;;
esac
