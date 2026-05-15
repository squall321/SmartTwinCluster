#!/bin/bash
# venv에 핵심 모듈이 있는지 검사, 없으면 오프라인 휠로 자동 설치.
# 사용:
#   source ../common/ensure_venv.sh
#   ensure_venv "aiohttp" "flask"      # 검사할 import 모듈명들
#
# 가정: 호출 직전에 cd "$SCRIPT_DIR" + source venv/bin/activate 완료 상태

ensure_venv() {
    local missing=()
    for mod in "$@"; do
        python3 -c "import ${mod//-/_}" 2>/dev/null || missing+=("$mod")
    done
    [ ${#missing[@]} -eq 0 ] && return 0

    echo -e "\033[1;33m⚠️  누락된 모듈: ${missing[*]} → 오프라인 휠로 설치 시도\033[0m"

    # pip 자체가 깨져 있으면 ensurepip / get-pip / venv 재생성
    if ! python3 -m pip --version >/dev/null 2>&1; then
        echo -e "\033[1;33m   • pip 깨짐 → ensurepip로 복구\033[0m"
        if ! python3 -m ensurepip --upgrade >/dev/null 2>&1; then
            echo -e "\033[1;33m   • ensurepip 실패 → venv 재생성\033[0m"
            local venv_dir="$(dirname "$(dirname "$(command -v python3)")")"
            # venv_dir가 ./venv를 가리키는지 검증
            if [[ "$venv_dir" == *"/venv" ]]; then
                deactivate 2>/dev/null || true
                rm -rf "$venv_dir"
                python3 -m venv "$venv_dir" || /usr/bin/python3 -m venv "$venv_dir"
                source "$venv_dir/bin/activate"
            fi
        fi
    fi

    # OFFLINE_PKG_DIR 또는 자동 탐색
    local pkg_dir="${OFFLINE_PKG_DIR:-}"
    if [ -z "$pkg_dir" ]; then
        for candidate in \
            "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/offline_packages_2404" \
            "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/offline_packages" \
            /home/koopark/claude/KooSlurmInstallAutomationRefactory/offline_packages_2404 \
            /home/koopark/claude/KooSlurmInstallAutomationRefactory/offline_packages; do
            [ -d "$candidate/python_wheels" ] && pkg_dir="$candidate" && break
        done
    fi
    if [ -z "$pkg_dir" ]; then
        echo -e "\033[0;31m❌ offline_packages 못 찾음\033[0m"
        return 1
    fi

    local py_ver=$(python3 -c "import sys;print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    local wheels="$pkg_dir/python_wheels/python${py_ver}"
    [ ! -d "$wheels" ] && wheels="$pkg_dir/python_wheels"

    # pip 명령 대신 python3 -m pip 사용 (pip 스크립트가 깨져도 동작)
    local PIP="python3 -m pip"
    if [ -f requirements.txt ]; then
        $PIP install --no-index --find-links="$wheels" -r requirements.txt && return 0
        $PIP install --find-links="$wheels" -r requirements.txt && return 0
    fi
    $PIP install --no-index --find-links="$wheels" "${missing[@]}" && return 0
    $PIP install --find-links="$wheels" "${missing[@]}"
}
