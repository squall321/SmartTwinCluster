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
