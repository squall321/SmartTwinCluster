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
