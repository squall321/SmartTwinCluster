#!/bin/bash
################################################################################
# Python Wheel 패키지 다운로드 스크립트 (오프라인 설치용)
#
# 설명:
#   모든 dashboard 서비스의 requirements.txt를 읽어서
#   Python 버전별로 필요한 wheel 파일들을 다운로드합니다.
#
# 사용법:
#   ./download_python_wheels.sh
#
# 요구사항:
#   - 인터넷 연결 필요
#   - Python 3.12 및 3.13 설치 필요
#
# 작성자: Claude Code
# 날짜: 2025-12-24
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 스크립트 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WHEELS_DIR="${SCRIPT_DIR}/python_wheels"

# Python 버전 목록 (Dashboard 서비스들이 사용하는 버전)
# auth_portal_4430, websocket_5011, backend_moonlight: Python 3.10
# backend_5010: Python 3.12
# kooCAEWebServer_5000, kooCAEWebAutomationServer_5001: Python 3.13
PYTHON_VERSIONS=("3.10" "3.12" "3.13")

# 인터넷 연결 확인
check_internet() {
    log_info "Checking internet connection..."
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_success "Internet connection available"
    else
        log_error "No internet connection. This script requires internet to download packages."
        exit 1
    fi
}

# Wheels 디렉토리 생성 (Python 버전별)
setup_wheels_dir() {
    log_info "Setting up wheels directories..."

    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local ver_dir="${WHEELS_DIR}/python${py_ver}"
        mkdir -p "$ver_dir"
        log_info "  ✓ $ver_dir"
    done

    log_success "Wheels directories ready"
}

# 모든 requirements 파일 찾기
# 우선순위: requirements_actual.txt > requirements.txt > autowebserverrequirements.txt
find_requirements_files() {
    log_info "Finding all requirements files in dashboard..." >&2

    local requirements_files=()
    local processed_dirs=()

    # 각 서비스 디렉토리별로 최적의 requirements 파일 선택
    while IFS= read -r service_dir; do
        local dir_name=$(basename "$service_dir")

        # 이미 처리한 디렉토리 스킵
        local skip=false
        for processed in "${processed_dirs[@]}"; do
            if [[ "$processed" == "$service_dir" ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == true ]] && continue

        # 우선순위에 따라 requirements 파일 선택
        local req_file=""
        if [[ -f "$service_dir/requirements_actual.txt" ]]; then
            req_file="$service_dir/requirements_actual.txt"
            log_info "  Using requirements_actual.txt for $dir_name (actual installed packages)" >&2
        elif [[ -f "$service_dir/requirements.txt" ]]; then
            req_file="$service_dir/requirements.txt"
        elif [[ -f "$service_dir/autowebserverrequirements.txt" ]]; then
            req_file="$service_dir/autowebserverrequirements.txt"
        fi

        if [[ -n "$req_file" ]]; then
            requirements_files+=("$req_file")
            processed_dirs+=("$service_dir")
        fi
    done < <(find "${PROJECT_ROOT}/dashboard" -type d | grep -v -E "\.backup|/venv/|/node_modules/" | sort -u)

    # Return files separated by newlines to avoid word splitting issues
    printf '%s\n' "${requirements_files[@]}"
}

# Python 버전별 Wheel 다운로드
# 각 requirements 파일별로 따로 다운로드하여 버전 충돌 방지
download_wheels() {
    local requirements_files=("$@")

    log_info "Downloading wheels for ${#requirements_files[@]} services..."
    log_info "Python versions: ${PYTHON_VERSIONS[*]}"
    log_info "Strategy: Download using each service's venv pip"
    echo ""

    # Python 버전별로 다운로드
    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        log_info "=== Python ${py_ver} ==="
        local ver_dir="${WHEELS_DIR}/python${py_ver}"

        # Python 버전에 맞는 서비스 필터링
        local services_for_version=()
        for req_file in "${requirements_files[@]}"; do
            local service_dir=$(dirname "$req_file")

            # venv의 Python 버전 확인
            if [[ -f "$service_dir/venv/bin/python" ]]; then
                local venv_py_ver=$("$service_dir/venv/bin/python" --version 2>&1 | grep -oP 'Python \K\d+\.\d+')
                if [[ "$venv_py_ver" == "$py_ver" ]]; then
                    services_for_version+=("$req_file")
                fi
            fi
        done

        if [[ ${#services_for_version[@]} -eq 0 ]]; then
            log_warning "  ⚠ No services using Python ${py_ver}, skipping..."
            echo ""
            continue
        fi

        log_info "  Found ${#services_for_version[@]} services using Python ${py_ver}"
        echo ""

        # 각 requirements 파일별로 다운로드
        for req_file in "${services_for_version[@]}"; do
            local service_dir=$(dirname "$req_file")
            local service_name=$(basename "$service_dir")
            local req_basename=$(basename "$req_file")
            local venv_pip="$service_dir/venv/bin/pip"

            log_info "  Downloading $service_name ($req_basename)..."

            cd "$ver_dir"

            # venv의 pip 사용하여 다운로드
            if [[ -f "$venv_pip" ]]; then
                if $venv_pip download -r "$req_file" --dest . >/dev/null 2>&1; then
                    log_success "    ✓ Downloaded for $service_name"
                else
                    log_warning "    ⚠ Some packages failed for $service_name"
                fi
            else
                log_warning "    ⚠ venv pip not found for $service_name"
            fi
        done

        local wheel_count=$(find "$ver_dir" -name "*.whl" -o -name "*.tar.gz" | wc -l)
        log_success "  Total wheels for Python ${py_ver}: $wheel_count"
        echo ""
    done

    log_success "All wheels downloaded"
}

# 중복 제거 및 요약
summarize_wheels() {
    log_info "Summarizing downloaded wheels..."

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Python Wheels 다운로드 완료!                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    local total_size=$(du -sh "$WHEELS_DIR" | cut -f1)
    echo "  Total size:     $total_size"
    echo "  Location:       $WHEELS_DIR"
    echo ""

    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local ver_dir="${WHEELS_DIR}/python${py_ver}"

        if [[ -d "$ver_dir" ]]; then
            local wheel_count=$(find "$ver_dir" -name "*.whl" -o -name "*.tar.gz" 2>/dev/null | wc -l)
            local ver_size=$(du -sh "$ver_dir" 2>/dev/null | cut -f1)

            echo "  Python ${py_ver}:"
            echo "    Packages: $wheel_count"
            echo "    Size:     $ver_size"
            echo ""
        fi
    done

    echo ""
}

# 설치 스크립트 생성
create_install_script() {
    log_info "Creating offline installation script..."

    cat > "${WHEELS_DIR}/install_offline.sh" << 'EOFINSTALL'
#!/bin/bash
################################################################################
# Python Wheels 오프라인 설치 스크립트
#
# 사용법:
#   ./install_offline.sh <requirements.txt>
#
# 예:
#   cd /path/to/service
#   /opt/offline_packages/python_wheels/install_offline.sh requirements.txt
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <requirements.txt>"
    exit 1
fi

REQUIREMENTS_FILE="$1"

if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
    echo "Error: Requirements file not found: $REQUIREMENTS_FILE"
    exit 1
fi

# Python 버전 감지
PY_VERSION=$(python --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "3.12")
PY_MAJOR_MINOR="${PY_VERSION%.*}.${PY_VERSION#*.}"

# Python 버전에 맞는 wheels 디렉토리 선택
WHEELS_SUBDIR="${SCRIPT_DIR}/python${PY_MAJOR_MINOR}"

if [[ ! -d "$WHEELS_SUBDIR" ]]; then
    echo "Warning: No wheels directory for Python ${PY_MAJOR_MINOR}, trying python3.12..."
    WHEELS_SUBDIR="${SCRIPT_DIR}/python3.12"
fi

if [[ ! -d "$WHEELS_SUBDIR" ]]; then
    echo "Error: No wheels directory found for Python ${PY_MAJOR_MINOR}"
    exit 1
fi

echo "Installing packages from $REQUIREMENTS_FILE using offline wheels..."
echo "Python version: ${PY_MAJOR_MINOR}"
echo "Wheels directory: $WHEELS_SUBDIR"

pip install --no-index --find-links="$WHEELS_SUBDIR" -r "$REQUIREMENTS_FILE"

echo "✅ Offline installation complete!"
EOFINSTALL

    chmod +x "${WHEELS_DIR}/install_offline.sh"

    log_success "Installation script created: ${WHEELS_DIR}/install_offline.sh"
}

# README 생성
create_readme() {
    log_info "Creating README..."

    cat > "${WHEELS_DIR}/README.md" << 'EOFREADME'
# Python Wheels for Offline Installation

This directory contains all Python package wheels needed for offline dashboard installation.

## Directory Structure

```
python_wheels/
├── python3.10/          # Wheels for Python 3.10 (auth_portal, websocket, moonlight)
│   ├── *.whl
│   └── *.tar.gz
├── python3.12/          # Wheels for Python 3.12 (backend_5010)
│   ├── *.whl
│   └── *.tar.gz
├── python3.13/          # Wheels for Python 3.13 (CAE servers)
│   ├── *.whl
│   └── *.tar.gz
├── install_offline.sh   # Auto-detect Python version installer
└── README.md            # This file
```

## Python Version Mapping

- **Python 3.10**: auth_portal_4430, websocket_5011, backend_moonlight_8004
- **Python 3.12**: backend_5010
- **Python 3.13**: kooCAEWebServer_5000, kooCAEWebAutomationServer_5001

## Usage

### Method 1: Using the helper script (Recommended)

The script automatically detects your Python version and uses the correct wheels:

```bash
cd /path/to/service
/opt/offline_packages/python_wheels/install_offline.sh requirements.txt
```

### Method 2: Manual pip install

For Python 3.10:
```bash
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.10 -r requirements.txt
```

For Python 3.12:
```bash
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.12 -r requirements.txt
```

For Python 3.13:
```bash
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.13 -r requirements.txt
```

## Generated

Created by: `download_python_wheels.sh`
Date: $(date)

All packages from dashboard services' requirements.txt are included.
EOFREADME

    log_success "README created: ${WHEELS_DIR}/README.md"
}

################################################################################
# Main
################################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Python Wheels Downloader                         ║"
    echo "║          (For Offline Installation)                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    check_internet
    setup_wheels_dir

    # 모든 requirements.txt 찾기
    local requirements_files=()
    mapfile -t requirements_files < <(find_requirements_files)

    if [[ ${#requirements_files[@]} -eq 0 ]]; then
        log_error "No requirements.txt files found in dashboard/"
        exit 1
    fi

    log_info "Found ${#requirements_files[@]} requirements.txt files"
    for req_file in "${requirements_files[@]}"; do
        echo "  - $req_file"
    done
    echo ""

    read -p "Download all wheels? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled by user"
        exit 0
    fi

    # 다운로드
    download_wheels "${requirements_files[@]}"

    # 요약
    summarize_wheels

    # 스크립트 생성
    create_install_script
    create_readme

    echo ""
    log_success "All wheels downloaded successfully!"
    log_info "Next: Transfer offline_packages/python_wheels/ to target server"
    echo ""
}

main "$@"
