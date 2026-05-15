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

    # offline_packages 자동 탐색
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

    local apt_dir="$pkg_dir/apt_packages"
    local sys_py_ver=$(/usr/bin/python3 -c "import sys;print(f'{sys.version_info.major}.{sys.version_info.minor}')")

    # 시스템 python3-venv / pip-whl 보장 (ensurepip 동작에 필수)
    if ! /usr/bin/python3 -c "import ensurepip" 2>/dev/null; then
        echo -e "\033[1;33m   • python${sys_py_ver}-venv 미설치 → offline dpkg 설치\033[0m"
        if [ -d "$apt_dir" ]; then
            sudo dpkg -i $(ls "$apt_dir"/python3-pip-whl_*.deb 2>/dev/null | tail -1) \
                        $(ls "$apt_dir"/python${sys_py_ver}-venv_*.deb 2>/dev/null | tail -1) \
                        $(ls "$apt_dir"/python3-venv_*.deb 2>/dev/null | tail -1) 2>/dev/null || true
        fi
    fi

    # venv 깨짐(activate/pip 없음) 감지 → 재생성
    local venv_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)/venv"
    [ ! -d "$venv_dir" ] && venv_dir="$(pwd)/venv"
    if [ ! -f "$venv_dir/bin/activate" ] || ! "$venv_dir/bin/python3" -m pip --version >/dev/null 2>&1; then
        echo -e "\033[1;33m   • venv 깨짐 → 재생성: $venv_dir\033[0m"
        deactivate 2>/dev/null || true
        sudo rm -rf "$venv_dir"
        /usr/bin/python3 -m venv "$venv_dir" || { echo -e "\033[0;31m❌ venv 생성 실패\033[0m"; return 1; }
        # 소유자 원복 (sudo 실행이었을 경우)
        local owner="${SUDO_USER:-$(whoami)}"
        sudo chown -R "$owner":"$owner" "$venv_dir" 2>/dev/null || true
        source "$venv_dir/bin/activate"
    fi

    local py_ver=$(python3 -c "import sys;print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    local wheels="$pkg_dir/python_wheels/python${py_ver}"
    [ ! -d "$wheels" ] && wheels="$pkg_dir/python_wheels"

    # venv 내부의 pip 사용 (시스템 PEP 668 회피)
    local PIP="$venv_dir/bin/python3 -m pip"
    if [ -f requirements.txt ]; then
        $PIP install --no-index --find-links="$wheels" -r requirements.txt && return 0
        $PIP install --find-links="$wheels" -r requirements.txt && return 0
    fi
    $PIP install --no-index --find-links="$wheels" "${missing[@]}" && return 0
    $PIP install --find-links="$wheels" "${missing[@]}"
}
