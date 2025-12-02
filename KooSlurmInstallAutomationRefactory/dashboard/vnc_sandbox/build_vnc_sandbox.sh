#!/bin/bash

# VNC Sandbox 빌드 스크립트
# 예상 소요 시간: 10-20분

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEF_FILE="$SCRIPT_DIR/vnc_desktop.def"
SANDBOX_DIR="/scratch/apptainer_sandboxes/vnc_desktop"
LOG_FILE="$SCRIPT_DIR/build.log"

echo "=== VNC Sandbox Build Script ==="
echo "Definition file: $DEF_FILE"
echo "Sandbox directory: $SANDBOX_DIR"
echo "Build log: $LOG_FILE"
echo

# 디렉토리 확인
if [ ! -d "/scratch/apptainer_sandboxes" ]; then
    echo "ERROR: /scratch/apptainer_sandboxes does not exist"
    echo "Creating directory..."
    sudo mkdir -p /scratch/apptainer_sandboxes
    sudo chown $USER:$USER /scratch/apptainer_sandboxes
fi

# 기존 샌드박스 백업
if [ -d "$SANDBOX_DIR" ]; then
    echo "WARNING: Sandbox already exists at $SANDBOX_DIR"
    echo "Creating backup..."
    BACKUP_DIR="${SANDBOX_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    mv "$SANDBOX_DIR" "$BACKUP_DIR"
    echo "Backup created: $BACKUP_DIR"
fi

# 빌드 시작
echo "Starting sandbox build..."
echo "This will take 10-20 minutes. Please wait..."
echo

# fakeroot 모드로 빌드 (sudo 불필요)
apptainer build --sandbox "$SANDBOX_DIR" "$DEF_FILE" 2>&1 | tee "$LOG_FILE"

BUILD_STATUS=$?

echo
echo "=== Build Result ==="

if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ Sandbox build SUCCESSFUL"
    echo
    echo "Sandbox location: $SANDBOX_DIR"
    echo "Size: $(du -sh $SANDBOX_DIR | cut -f1)"
    echo
    echo "Next steps:"
    echo "  1. Test GPU: apptainer exec --nv $SANDBOX_DIR nvidia-smi"
    echo "  2. Test VNC: ./test_vnc_sandbox.sh"
    exit 0
else
    echo "❌ Sandbox build FAILED"
    echo "Check log file: $LOG_FILE"
    exit 1
fi
