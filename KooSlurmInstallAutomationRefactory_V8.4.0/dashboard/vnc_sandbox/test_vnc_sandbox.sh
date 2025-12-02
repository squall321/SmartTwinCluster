#!/bin/bash

# VNC Sandbox 테스트 스크립트

set -e

SANDBOX_DIR="/scratch/apptainer_sandboxes/vnc_desktop"

echo "=== VNC Sandbox Test Script ==="
echo

# 샌드박스 존재 확인
if [ ! -d "$SANDBOX_DIR" ]; then
    echo "❌ ERROR: Sandbox not found at $SANDBOX_DIR"
    echo "Please build the sandbox first: ./build_vnc_sandbox.sh"
    exit 1
fi

echo "✅ Sandbox found: $SANDBOX_DIR"
echo "Size: $(du -sh $SANDBOX_DIR | cut -f1)"
echo

# Test 1: GPU 접근
echo "Test 1: GPU Access"
echo "Running: apptainer exec --nv $SANDBOX_DIR nvidia-smi"
apptainer exec --nv "$SANDBOX_DIR" nvidia-smi
echo "✅ GPU access successful"
echo

# Test 2: OpenGL 가속
echo "Test 2: OpenGL Acceleration"
echo "Running: glxinfo | grep 'OpenGL renderer'"
apptainer exec --nv "$SANDBOX_DIR" glxinfo | grep "OpenGL renderer" || echo "⚠️  glxinfo not available, skipping"
echo

# Test 3: 기본 명령어
echo "Test 3: Basic Commands"
apptainer exec "$SANDBOX_DIR" which vncserver
apptainer exec "$SANDBOX_DIR" which websockify
apptainer exec "$SANDBOX_DIR" which firefox
echo "✅ Basic commands available"
echo

# Test 4: X11 설정
echo "Test 4: X11 Configuration"
apptainer exec "$SANDBOX_DIR" ls -la /root/.vnc/
echo

echo "=== All Tests Passed ==="
echo
echo "Next steps:"
echo "  1. Start VNC server manually:"
echo "     apptainer exec --nv $SANDBOX_DIR vncserver :1 -geometry 1920x1080"
echo "  2. Set VNC password (if not set):"
echo "     apptainer exec $SANDBOX_DIR vncpasswd"
echo "  3. Test via Slurm job: See vnc_test_job.sh"
