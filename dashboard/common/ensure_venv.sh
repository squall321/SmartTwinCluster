#!/bin/bash
# venv에 핵심 모듈이 있는지 검사, 없으면 오프라인 휠로 자동 설치.
# 사용:
#   source ../common/ensure_venv.sh
#   ensure_venv "aiohttp" "flask"      # 검사할 import 모듈명들
#
# 가정: 호출 직전에 cd "$SCRIPT_DIR" + source venv/bin/activate 완료 상태

ensure_venv() {
    local script_dir="$(pwd)"
    local venv_dir="$script_dir/venv"
    # venv 있으면 활성화 후 모듈 검사
    if [ -f "$venv_dir/bin/activate" ]; then
        source "$venv_dir/bin/activate" 2>/dev/null || true
    fi
    # 인자: "module" 또는 "module:pip-name" 형식 (pip 이름이 다를 때)
    local missing=()         # pip install용 (pkg 이름)
    local missing_imports=() # 표시용 (import 이름)
    if [ -f "$venv_dir/bin/python3" ]; then
        for arg in "$@"; do
            local imp_name="${arg%%:*}"
            local pip_name="${arg##*:}"
            [ "$imp_name" = "$pip_name" ] && pip_name="$imp_name"
            "$venv_dir/bin/python3" -c "import ${imp_name//-/_}" 2>/dev/null || {
                missing+=("$pip_name")
                missing_imports+=("$imp_name")
            }
        done
    else
        for arg in "$@"; do
            local pip_name="${arg##*:}"
            [ -z "$pip_name" ] && pip_name="$arg"
            missing+=("$pip_name")
        done
        missing_imports=("${missing[@]}")
    fi
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
            local debs=()
            for pat in "python3-pip-whl_*.deb" "python${sys_py_ver}-venv_*.deb" "python3-venv_*.deb"; do
                local f=$(ls "$apt_dir"/$pat 2>/dev/null | tail -1)
                [ -n "$f" ] && debs+=("$f")
            done
            if [ ${#debs[@]} -gt 0 ]; then
                sudo apt install -y "${debs[@]}" 2>/dev/null \
                    || sudo dpkg -i --force-depends "${debs[@]}" 2>/dev/null || true
            fi
        fi
    fi

    # venv 검증/재생성: 깨졌거나 PYTHON_BIN 버전과 다르면 재생성
    local venv_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)/venv"
    [ ! -d "$venv_dir" ] && venv_dir="$(pwd)/venv"
    local target_py="${PYTHON_BIN:-/usr/bin/python3}"
    [ ! -x "$target_py" ] && target_py="/usr/bin/python3"
    local target_ver=$("$target_py" -c "import sys;print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)

    local need_recreate=0
    if [ ! -f "$venv_dir/bin/activate" ] || ! "$venv_dir/bin/python3" -m pip --version >/dev/null 2>&1; then
        need_recreate=1
        echo -e "\033[1;33m   • venv 깨짐 → 재생성\033[0m"
    else
        local cur_ver=$("$venv_dir/bin/python3" -c "import sys;print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
        if [ -n "$target_ver" ] && [ "$cur_ver" != "$target_ver" ]; then
            need_recreate=1
            echo -e "\033[1;33m   • venv python 버전 불일치 ($cur_ver → $target_ver) → 재생성\033[0m"
        fi
    fi

    if [ "$need_recreate" = "1" ]; then
        deactivate 2>/dev/null || true
        sudo rm -rf "$venv_dir"
        "$target_py" -m venv "$venv_dir" || { echo -e "\033[0;31m❌ venv 생성 실패 ($target_py)\033[0m"; return 1; }
        local owner="${SUDO_USER:-$(whoami)}"
        sudo chown -R "$owner":"$owner" "$venv_dir" 2>/dev/null || true
        source "$venv_dir/bin/activate"
    fi

    local py_ver=$(python3 -c "import sys;print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    local wheels1="$pkg_dir/python_wheels/python${py_ver}"
    local wheels2="$pkg_dir/python_wheels"
    [ ! -d "$wheels1" ] && wheels1="$wheels2"

    # venv 내부의 pip 사용 (시스템 PEP 668 회피)
    local PIP="$venv_dir/bin/python3 -m pip"
    # 부모/버전별 wheels 둘 다 --find-links로 (중복 OK)
    local FL="--find-links=$wheels1 --find-links=$wheels2"

    # 1) requirements.txt 그대로 (핀 일치 시)
    if [ -f requirements.txt ]; then
        $PIP install --no-index $FL -r requirements.txt 2>&1 | tail -5
        echo -e "\033[1;33m   • requirements 결과와 무관하게 요청 모듈 강제 설치 (venv 정상화)\033[0m"
    fi
    # 2) 요청된 모듈은 항상 venv에 강제 설치 (check를 통과했더라도 시스템 패키지 잡혔을 수 있음)
    $PIP install --no-index --upgrade $FL "${missing[@]}" 2>&1 | tail -5
    # 3) 못 받은 모듈 마지막 시도: 온라인 fallback
    $PIP install --upgrade $FL "${missing[@]}" 2>&1 | tail -5
    return 0
}
