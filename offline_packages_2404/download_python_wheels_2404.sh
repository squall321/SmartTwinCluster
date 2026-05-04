#!/bin/bash
################################################################################
# Python Wheel Download Script for Ubuntu 24.04 (Noble Numbat)
#
# Description:
#   Downloads Python wheel packages for all dashboard services for offline
#   installation. This script runs INSIDE an Ubuntu 24.04 VM (or system)
#   and uses pip download to fetch wheels compatible with 24.04's Python
#   environment.
#
# Target OS: Ubuntu 24.04 LTS (Noble Numbat)
#
# Key differences from 22.04 version:
#   - Python 3.12 is the system default (no deadsnakes PPA needed for 3.12)
#   - Python 3.13 from deadsnakes PPA
#   - No Python 3.10 (not available on 24.04 without extra effort)
#   - Services previously on 3.10 now use 3.12
#   - Does NOT rely on existing venvs; uses pip download directly
#
# Python Version Mapping (24.04):
#   Python 3.12: auth_portal_4430, websocket_5011,
#                backend_moonlight_8004, backend_5010
#   Python 3.13: kooCAEWebServer_5000, kooCAEWebAutomationServer_5001
#
# Requirements staging directory:
#   requirements/
#   ├── python3.12/
#   │   ├── auth_portal_4430_requirements.txt
#   │   ├── websocket_5011_requirements.txt
#   │   ├── backend_5010_requirements.txt
#   │   └── backend_moonlight_8004_requirements.txt
#   └── python3.13/
#       ├── kooCAEWebServer_5000_requirements.txt
#       └── kooCAEWebAutomationServer_5001_requirements.txt
#
# Usage:
#   sudo ./download_python_wheels_2404.sh [OPTIONS]
#
# Options:
#   --output-dir PATH          Output directory for wheels (default: ./python_wheels)
#   --requirements-dir PATH    Directory with staged requirements files (default: ./requirements)
#   --requirements FILE        Add a single requirements file (can be repeated)
#   --skip-install-python      Skip Python installation step
#   --skip-confirm             Skip confirmation prompt (non-interactive)
#   --help                     Show help
#
# Author: Claude Code
# Date: 2026-03-06
################################################################################

set -euo pipefail

################################################################################
# Constants
################################################################################

# Python versions used by dashboard services on Ubuntu 24.04
# Python 3.12: system default on noble
# Python 3.13: from deadsnakes PPA
PYTHON_VERSIONS=("3.12" "3.13")

# Service-to-Python-version mapping
# On 22.04, auth_portal, websocket, moonlight used 3.10. On 24.04, they use 3.12.
declare -A SERVICE_PYTHON_MAP=(
    ["auth_portal_4430"]="3.12"
    ["websocket_5011"]="3.12"
    ["backend_moonlight_8004"]="3.12"
    ["backend_5010"]="3.12"
    ["kooCAEWebServer_5000"]="3.13"
    ["kooCAEWebAutomationServer_5001"]="3.13"
)

################################################################################
# Defaults
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELS_DIR="${SCRIPT_DIR}/python_wheels"
REQUIREMENTS_DIR="${SCRIPT_DIR}/requirements"
EXTRA_REQUIREMENTS_FILES=()
SKIP_INSTALL_PYTHON=false
SKIP_CONFIRM=false

################################################################################
# Color definitions
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

################################################################################
# Logging functions
################################################################################

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase()   { echo -e "${CYAN}[PHASE $1]${NC} $2"; }

################################################################################
# Help
################################################################################

show_help() {
    head -n 48 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

################################################################################
# Argument parsing
################################################################################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output-dir)
                WHEELS_DIR="$2"
                shift 2
                ;;
            --requirements-dir)
                REQUIREMENTS_DIR="$2"
                shift 2
                ;;
            --requirements)
                EXTRA_REQUIREMENTS_FILES+=("$2")
                shift 2
                ;;
            --skip-install-python)
                SKIP_INSTALL_PYTHON=true
                shift
                ;;
            --skip-confirm)
                SKIP_CONFIRM=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

################################################################################
# Pre-checks
################################################################################

# Internet connectivity check
check_internet() {
    log_info "Checking internet connection..."
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        log_success "Internet connection available"
    elif curl -s --max-time 5 https://pypi.org/ &>/dev/null; then
        log_success "Internet connection available (via HTTPS)"
    else
        log_error "No internet connection. This script requires internet to download packages."
        exit 1
    fi
}

# Verify we are running on Ubuntu 24.04 (warning only)
check_os_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${VERSION_ID:-}" != "24.04" ]]; then
            log_warning "This script is designed for Ubuntu 24.04 (noble)"
            log_warning "Detected: ${PRETTY_NAME:-unknown}"
            log_warning "Downloaded wheels may not be compatible with 24.04 if run elsewhere."
        else
            log_success "Detected Ubuntu 24.04 (noble) - OK"
        fi
    else
        log_warning "Cannot detect OS version (/etc/os-release not found)"
    fi
}

################################################################################
# Phase 1: Install Python interpreters
################################################################################

install_python() {
    log_phase "1" "Ensuring Python interpreters are available"

    if [[ "$SKIP_INSTALL_PYTHON" == "true" ]]; then
        log_info "Skipping Python installation (--skip-install-python)"
        return 0
    fi

    # ── Python 3.12 (system default on 24.04) ──
    log_info "Checking Python 3.12 (system default on noble)..."
    if command -v python3.12 &>/dev/null; then
        log_success "  Python 3.12 already installed: $(python3.12 --version 2>&1)"
    else
        log_info "  Installing Python 3.12 (system packages)..."
        apt-get update -qq
        apt-get install -y python3.12 python3.12-venv python3.12-dev python3-pip
        log_success "  Python 3.12 installed: $(python3.12 --version 2>&1)"
    fi

    # Ensure pip is available for Python 3.12
    if ! python3.12 -m pip --version &>/dev/null; then
        log_info "  Installing pip for Python 3.12..."
        apt-get install -y python3-pip 2>/dev/null || true
        # Fallback: bootstrap pip
        if ! python3.12 -m pip --version &>/dev/null; then
            python3.12 -m ensurepip --upgrade 2>/dev/null || {
                curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12
            }
        fi
        log_success "  pip installed for Python 3.12: $(python3.12 -m pip --version 2>&1)"
    fi

    # ── Python 3.13 (from deadsnakes PPA) ──
    log_info "Checking Python 3.13 (deadsnakes PPA)..."
    if command -v python3.13 &>/dev/null; then
        log_success "  Python 3.13 already installed: $(python3.13 --version 2>&1)"
    else
        log_info "  Adding deadsnakes PPA for Python 3.13..."
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:deadsnakes/ppa
        apt-get update -qq
        apt-get install -y python3.13 python3.13-venv python3.13-dev
        log_success "  Python 3.13 installed: $(python3.13 --version 2>&1)"
    fi

    # Ensure pip is available for Python 3.13
    if ! python3.13 -m pip --version &>/dev/null; then
        log_info "  Installing pip for Python 3.13..."
        python3.13 -m ensurepip --upgrade 2>/dev/null || {
            curl -sS https://bootstrap.pypa.io/get-pip.py | python3.13
        }
        log_success "  pip installed for Python 3.13: $(python3.13 -m pip --version 2>&1)"
    fi

    echo ""
    log_info "Python interpreter summary:"
    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local py_cmd="python${py_ver}"
        if command -v "$py_cmd" &>/dev/null; then
            log_success "  $py_cmd: $($py_cmd --version 2>&1) | pip: $($py_cmd -m pip --version 2>&1 | head -1)"
        else
            log_error "  $py_cmd: NOT FOUND"
        fi
    done
}

################################################################################
# Phase 2: Set up wheels directories
################################################################################

setup_wheels_dir() {
    log_phase "2" "Setting up wheels directories"

    mkdir -p "$WHEELS_DIR"

    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local ver_dir="${WHEELS_DIR}/python${py_ver}"
        mkdir -p "$ver_dir"
        log_info "  Created: $ver_dir"
    done

    log_success "Wheels directories ready: $WHEELS_DIR"
}

################################################################################
# Phase 3: Discover requirements files
################################################################################

discover_requirements() {
    log_phase "3" "Discovering requirements files"

    # Associative array: python_version -> space-separated list of requirements files
    declare -gA REQUIREMENTS_BY_VERSION

    local found_count=0

    # ── Method 1: Staged requirements directory ──
    if [[ -d "$REQUIREMENTS_DIR" ]]; then
        log_info "Scanning staged requirements directory: $REQUIREMENTS_DIR"

        for py_ver in "${PYTHON_VERSIONS[@]}"; do
            local ver_dir="${REQUIREMENTS_DIR}/python${py_ver}"
            if [[ -d "$ver_dir" ]]; then
                local files=()
                while IFS= read -r -d '' req_file; do
                    files+=("$req_file")
                    found_count=$((found_count + 1))
                done < <(find "$ver_dir" -name "*.txt" -type f -print0 | sort -z)

                if [[ ${#files[@]} -gt 0 ]]; then
                    REQUIREMENTS_BY_VERSION["$py_ver"]="${files[*]}"
                    log_info "  Python ${py_ver}: ${#files[@]} requirements file(s)"
                    for f in "${files[@]}"; do
                        log_info "    - $(basename "$f")"
                    done
                fi
            fi
        done
    else
        log_info "Requirements directory not found: $REQUIREMENTS_DIR"
        log_info "Will look for --requirements arguments or embedded defaults."
    fi

    # ── Method 2: Extra requirements files (--requirements arguments) ──
    if [[ ${#EXTRA_REQUIREMENTS_FILES[@]} -gt 0 ]]; then
        log_info "Processing ${#EXTRA_REQUIREMENTS_FILES[@]} --requirements argument(s)"

        for req_file in "${EXTRA_REQUIREMENTS_FILES[@]}"; do
            if [[ ! -f "$req_file" ]]; then
                log_warning "  Requirements file not found: $req_file (skipping)"
                continue
            fi

            # Try to detect Python version from the path (e.g., python3.12/ parent dir)
            local py_ver=""
            if [[ "$req_file" == *"python3.12"* ]]; then
                py_ver="3.12"
            elif [[ "$req_file" == *"python3.13"* ]]; then
                py_ver="3.13"
            else
                # Try to infer from service name in filename
                for service in "${!SERVICE_PYTHON_MAP[@]}"; do
                    if [[ "$(basename "$req_file")" == *"$service"* ]]; then
                        py_ver="${SERVICE_PYTHON_MAP[$service]}"
                        break
                    fi
                done
            fi

            # Default to 3.12 if we cannot determine the version
            if [[ -z "$py_ver" ]]; then
                py_ver="3.12"
                log_warning "  Cannot determine Python version for $(basename "$req_file"), defaulting to ${py_ver}"
            fi

            # Append to existing list
            local existing="${REQUIREMENTS_BY_VERSION[$py_ver]:-}"
            if [[ -n "$existing" ]]; then
                REQUIREMENTS_BY_VERSION["$py_ver"]="${existing} ${req_file}"
            else
                REQUIREMENTS_BY_VERSION["$py_ver"]="$req_file"
            fi

            found_count=$((found_count + 1))
            log_info "  $(basename "$req_file") -> Python ${py_ver}"
        done
    fi

    # ── Validation ──
    if [[ $found_count -eq 0 ]]; then
        log_error "No requirements files found."
        log_error ""
        log_error "Please provide requirements files via one of these methods:"
        log_error ""
        log_error "  Method 1: Staged directory (recommended)"
        log_error "    mkdir -p ${REQUIREMENTS_DIR}/python3.12"
        log_error "    mkdir -p ${REQUIREMENTS_DIR}/python3.13"
        log_error "    cp <service>/requirements.txt ${REQUIREMENTS_DIR}/python3.12/<service>_requirements.txt"
        log_error ""
        log_error "  Method 2: --requirements flag"
        log_error "    $0 --requirements /path/to/requirements.txt"
        log_error ""
        log_error "  Service -> Python version mapping:"
        for service in $(echo "${!SERVICE_PYTHON_MAP[@]}" | tr ' ' '\n' | sort); do
            log_error "    ${service} -> Python ${SERVICE_PYTHON_MAP[$service]}"
        done
        exit 1
    fi

    echo ""
    log_success "Found $found_count requirements file(s) total"

    # Summary
    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local files_str="${REQUIREMENTS_BY_VERSION[$py_ver]:-}"
        if [[ -n "$files_str" ]]; then
            local count
            count=$(echo "$files_str" | wc -w)
            log_info "  Python ${py_ver}: ${count} file(s)"
        else
            log_info "  Python ${py_ver}: 0 files"
        fi
    done
}

################################################################################
# Phase 4: Download wheels
################################################################################

download_wheels() {
    log_phase "4" "Downloading Python wheels"

    local total_success=0
    local total_fail=0

    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local files_str="${REQUIREMENTS_BY_VERSION[$py_ver]:-}"
        if [[ -z "$files_str" ]]; then
            log_info "Python ${py_ver}: No requirements files, skipping"
            continue
        fi

        local py_cmd="python${py_ver}"
        local ver_dir="${WHEELS_DIR}/python${py_ver}"

        # Verify Python interpreter is available
        if ! command -v "$py_cmd" &>/dev/null; then
            log_error "Python interpreter not found: $py_cmd"
            log_error "Please install Python ${py_ver} first."
            total_fail=$((total_fail + 1))
            continue
        fi

        echo ""
        echo "================================================================"
        log_info "Downloading wheels for Python ${py_ver}"
        log_info "Interpreter: $($py_cmd --version 2>&1)"
        log_info "Destination: $ver_dir"
        echo "================================================================"
        echo ""

        mkdir -p "$ver_dir"

        # Process each requirements file
        local files=()
        read -ra files <<< "$files_str"

        for req_file in "${files[@]}"; do
            local req_basename
            req_basename=$(basename "$req_file")

            # Extract service name from filename (e.g., auth_portal_4430_requirements.txt -> auth_portal_4430)
            local service_name
            service_name=$(echo "$req_basename" | sed 's/_requirements.*\.txt$//' | sed 's/requirements.*\.txt$/unknown/')

            log_info "--- ${service_name} (${req_basename}) ---"

            # Count lines in requirements (excluding comments and blanks)
            local pkg_count
            pkg_count=$(grep -v -E '^\s*#|^\s*$' "$req_file" 2>/dev/null | wc -l)
            log_info "  Packages in requirements: $pkg_count"

            # Download wheels using pip download
            # --dest: target directory
            # --python-version is NOT used because we run with the actual interpreter
            local pip_log
            pip_log=$(mktemp)

            if $py_cmd -m pip download \
                -r "$req_file" \
                --dest "$ver_dir" \
                --prefer-binary \
                2>&1 | tee "$pip_log"; then

                log_success "  Downloaded wheels for ${service_name}"
                total_success=$((total_success + 1))
            else
                log_warning "  Some packages may have failed for ${service_name}"
                log_warning "  See log output above for details"
                total_fail=$((total_fail + 1))

                # Attempt individual package download for failed packages
                log_info "  Retrying failed packages individually..."
                while IFS= read -r line; do
                    # Skip comments and empty lines
                    [[ "$line" =~ ^[[:space:]]*# ]] && continue
                    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

                    # Clean up the package spec (remove extras, whitespace)
                    local pkg_spec
                    pkg_spec=$(echo "$line" | sed 's/#.*//' | xargs)
                    [[ -z "$pkg_spec" ]] && continue

                    $py_cmd -m pip download \
                        "$pkg_spec" \
                        --dest "$ver_dir" \
                        --prefer-binary \
                        2>/dev/null || {
                        log_warning "    Failed: $pkg_spec"
                    }
                done < "$req_file"
            fi

            rm -f "$pip_log"

            # Intermediate count
            local current_count
            current_count=$(find "$ver_dir" \( -name "*.whl" -o -name "*.tar.gz" -o -name "*.zip" \) 2>/dev/null | wc -l)
            log_info "  Cumulative wheels in python${py_ver}/: $current_count"
            echo ""
        done
    done

    echo ""
    log_info "Download results: ${total_success} succeeded, ${total_fail} had issues"
}

################################################################################
# Phase 5: Deduplicate wheels
################################################################################

deduplicate_wheels() {
    log_phase "5" "Deduplicating wheel files"

    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local ver_dir="${WHEELS_DIR}/python${py_ver}"
        if [[ ! -d "$ver_dir" ]]; then
            continue
        fi

        local before_count
        before_count=$(find "$ver_dir" \( -name "*.whl" -o -name "*.tar.gz" -o -name "*.zip" \) 2>/dev/null | wc -l)

        # Find and remove exact duplicates (same filename)
        # pip download already avoids downloading existing files, but just in case
        local dupes_removed=0
        local seen_files=()

        while IFS= read -r -d '' wheel_file; do
            local basename_file
            basename_file=$(basename "$wheel_file")

            if [[ " ${seen_files[*]:-} " == *" ${basename_file} "* ]]; then
                rm -f "$wheel_file"
                dupes_removed=$((dupes_removed + 1))
            else
                seen_files+=("$basename_file")
            fi
        done < <(find "$ver_dir" \( -name "*.whl" -o -name "*.tar.gz" -o -name "*.zip" \) -print0 | sort -z)

        local after_count
        after_count=$(find "$ver_dir" \( -name "*.whl" -o -name "*.tar.gz" -o -name "*.zip" \) 2>/dev/null | wc -l)

        if [[ $dupes_removed -gt 0 ]]; then
            log_info "  Python ${py_ver}: removed $dupes_removed duplicates ($before_count -> $after_count)"
        else
            log_info "  Python ${py_ver}: no duplicates found ($after_count files)"
        fi
    done

    log_success "Deduplication complete"
}

################################################################################
# Phase 6: Create offline install helper script
################################################################################

create_install_script() {
    log_phase "6" "Creating offline installation helper script"

    cat > "${WHEELS_DIR}/install_offline.sh" << 'INSTALL_EOF'
#!/bin/bash
################################################################################
# Python Wheels Offline Installation Script
# Target: Ubuntu 24.04 (Noble Numbat)
#
# This script installs Python packages from pre-downloaded wheel files.
# It auto-detects the Python version and selects the correct wheels directory.
#
# Usage:
#   ./install_offline.sh <requirements.txt>
#   ./install_offline.sh --python-version 3.13 <requirements.txt>
#
# Examples:
#   cd /path/to/service
#   /opt/offline_packages_2404/python_wheels/install_offline.sh requirements.txt
#
#   # Force Python 3.13 wheels:
#   /opt/offline_packages_2404/python_wheels/install_offline.sh \
#       --python-version 3.13 requirements.txt
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
PY_VERSION_OVERRIDE=""
REQUIREMENTS_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --python-version)
            PY_VERSION_OVERRIDE="$2"
            shift 2
            ;;
        *)
            REQUIREMENTS_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$REQUIREMENTS_FILE" ]]; then
    echo "Usage: $0 [--python-version X.Y] <requirements.txt>"
    exit 1
fi

if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
    log_error "Requirements file not found: $REQUIREMENTS_FILE"
    exit 1
fi

# Detect Python version
if [[ -n "$PY_VERSION_OVERRIDE" ]]; then
    PY_MAJOR_MINOR="$PY_VERSION_OVERRIDE"
    log_info "Using specified Python version: ${PY_MAJOR_MINOR}"
else
    PY_MAJOR_MINOR=$(python3 --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "3.12")
    log_info "Detected Python version: ${PY_MAJOR_MINOR}"
fi

# Select wheels directory
WHEELS_SUBDIR="${SCRIPT_DIR}/python${PY_MAJOR_MINOR}"

if [[ ! -d "$WHEELS_SUBDIR" ]]; then
    log_warning "No wheels directory for Python ${PY_MAJOR_MINOR}"
    # Try fallback to 3.12
    if [[ "$PY_MAJOR_MINOR" != "3.12" && -d "${SCRIPT_DIR}/python3.12" ]]; then
        WHEELS_SUBDIR="${SCRIPT_DIR}/python3.12"
        log_warning "Falling back to python3.12 wheels"
    else
        log_error "No suitable wheels directory found for Python ${PY_MAJOR_MINOR}"
        log_error "Available directories:"
        ls -d "${SCRIPT_DIR}"/python*/ 2>/dev/null || echo "  (none)"
        exit 1
    fi
fi

WHEEL_COUNT=$(find "$WHEELS_SUBDIR" \( -name "*.whl" -o -name "*.tar.gz" -o -name "*.zip" \) 2>/dev/null | wc -l)

echo ""
log_info "Installing packages from: $REQUIREMENTS_FILE"
log_info "Python version: ${PY_MAJOR_MINOR}"
log_info "Wheels directory: $WHEELS_SUBDIR ($WHEEL_COUNT files)"
echo ""

pip install --no-index --find-links="$WHEELS_SUBDIR" -r "$REQUIREMENTS_FILE"

echo ""
log_success "Offline installation complete!"
INSTALL_EOF

    chmod +x "${WHEELS_DIR}/install_offline.sh"
    log_success "Created: ${WHEELS_DIR}/install_offline.sh"
}

################################################################################
# Phase 7: Summary
################################################################################

print_summary() {
    log_phase "7" "Summary"

    local total_files=0
    local total_size
    total_size=$(du -sh "$WHEELS_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo "================================================================"
    echo "   Python Wheels Download Complete!"
    echo "   Ubuntu 24.04 (Noble Numbat)"
    echo "================================================================"
    echo ""

    echo "  Output directory:  $WHEELS_DIR"
    echo "  Total size:        $total_size"
    echo ""

    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local ver_dir="${WHEELS_DIR}/python${py_ver}"

        if [[ -d "$ver_dir" ]]; then
            local wheel_count
            wheel_count=$(find "$ver_dir" -name "*.whl" 2>/dev/null | wc -l)
            local sdist_count
            sdist_count=$(find "$ver_dir" \( -name "*.tar.gz" -o -name "*.zip" \) 2>/dev/null | wc -l)
            local ver_size
            ver_size=$(du -sh "$ver_dir" 2>/dev/null | cut -f1)

            local pkg_total=$((wheel_count + sdist_count))
            total_files=$((total_files + pkg_total))

            echo "  Python ${py_ver}:"
            echo "    Wheel files (.whl):    $wheel_count"
            echo "    Source dists (.tar.gz): $sdist_count"
            echo "    Total packages:        $pkg_total"
            echo "    Size:                  $ver_size"
            echo ""

            # List services that use this version
            local services=()
            for service in $(echo "${!SERVICE_PYTHON_MAP[@]}" | tr ' ' '\n' | sort); do
                if [[ "${SERVICE_PYTHON_MAP[$service]}" == "$py_ver" ]]; then
                    services+=("$service")
                fi
            done
            if [[ ${#services[@]} -gt 0 ]]; then
                echo "    Services:"
                for svc in "${services[@]}"; do
                    echo "      - $svc"
                done
                echo ""
            fi
        fi
    done

    echo "  Total packages:    $total_files"
    echo ""

    echo "  Directory structure:"
    echo "    ${WHEELS_DIR}/"
    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        local ver_dir="${WHEELS_DIR}/python${py_ver}"
        if [[ -d "$ver_dir" ]]; then
            local count
            count=$(find "$ver_dir" \( -name "*.whl" -o -name "*.tar.gz" -o -name "*.zip" \) 2>/dev/null | wc -l)
            echo "    ├── python${py_ver}/          ($count files)"
        fi
    done
    echo "    └── install_offline.sh   (helper script)"
    echo ""

    echo "  Usage on target system:"
    echo "    cd /path/to/service"
    echo "    /opt/offline_packages_2404/python_wheels/install_offline.sh requirements.txt"
    echo ""
    echo "  Or manually:"
    echo "    pip install --no-index --find-links=/opt/offline_packages_2404/python_wheels/python3.12 -r requirements.txt"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "================================================================"
    echo "   Python Wheels Downloader"
    echo "   Ubuntu 24.04 (Noble Numbat)"
    echo "   For Offline Dashboard Installation"
    echo "================================================================"
    echo ""

    # Pre-checks
    check_internet
    check_os_version
    echo ""

    # Show configuration
    log_info "Configuration:"
    log_info "  Output directory:      $WHEELS_DIR"
    log_info "  Requirements directory: $REQUIREMENTS_DIR"
    log_info "  Python versions:       ${PYTHON_VERSIONS[*]}"
    if [[ ${#EXTRA_REQUIREMENTS_FILES[@]} -gt 0 ]]; then
        log_info "  Extra requirements:    ${#EXTRA_REQUIREMENTS_FILES[@]} file(s)"
    fi
    echo ""

    log_info "Service -> Python version mapping (24.04):"
    for service in $(echo "${!SERVICE_PYTHON_MAP[@]}" | tr ' ' '\n' | sort); do
        log_info "  ${service} -> Python ${SERVICE_PYTHON_MAP[$service]}"
    done
    echo ""

    # Confirmation
    if [[ "$SKIP_CONFIRM" == "false" ]]; then
        read -p "Continue with wheel download? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
        echo ""
    fi

    # Phase 1: Install Python
    install_python
    echo ""

    # Phase 2: Setup directories
    setup_wheels_dir
    echo ""

    # Phase 3: Discover requirements
    discover_requirements
    echo ""

    # Phase 4: Download wheels
    download_wheels
    echo ""

    # Phase 5: Deduplicate
    deduplicate_wheels
    echo ""

    # Phase 6: Create install script
    create_install_script
    echo ""

    # Phase 7: Summary
    print_summary

    log_success "All Python wheels downloaded successfully!"
    log_info "Next: Transfer ${WHEELS_DIR}/ to target server"
    echo ""
}

main "$@"
