#!/bin/bash
# NVIDIA 드라이버 및 CUDA 오프라인 설치 스크립트

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== NVIDIA 드라이버/CUDA 오프라인 설치 ==="

# Nouveau 드라이버 비활성화
if lsmod | grep -q nouveau; then
    echo "Nouveau 드라이버 비활성화 중..."
    cat > /etc/modprobe.d/blacklist-nouveau.conf << EOF
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u
    echo "시스템 재부팅 후 다시 실행하세요"
    exit 1
fi

# NVIDIA 드라이버 설치
DRIVER_FILE=$(ls -1 NVIDIA-Linux-x86_64-*.run 2>/dev/null | head -1)
if [ -n "$DRIVER_FILE" ] && [ -f "$DRIVER_FILE" ]; then
    echo "NVIDIA 드라이버 설치: $DRIVER_FILE"
    chmod +x "$DRIVER_FILE"
    ./"$DRIVER_FILE" --silent --no-questions --ui=none || {
        echo "드라이버 설치 실패 - 그래픽 모드에서 재시도..."
        ./"$DRIVER_FILE" || exit 1
    }
    echo "NVIDIA 드라이버 설치 완료"
else
    echo "NVIDIA 드라이버 파일 없음"
fi

# CUDA Toolkit 설치
CUDA_FILE=$(ls -1 cuda_*.run 2>/dev/null | head -1)
if [ -n "$CUDA_FILE" ] && [ -f "$CUDA_FILE" ]; then
    echo "CUDA Toolkit 설치: $CUDA_FILE"
    chmod +x "$CUDA_FILE"
    ./"$CUDA_FILE" --silent --toolkit --no-drm || {
        echo "CUDA 설치 실패"
        exit 1
    }

    # 환경변수 설정
    cat >> /etc/profile.d/cuda.sh << 'ENVEOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
ENVEOF

    echo "CUDA Toolkit 설치 완료"
else
    echo "CUDA Toolkit 파일 없음"
fi

# 확인
echo ""
echo "=== 설치 확인 ==="
nvidia-smi || echo "nvidia-smi 실행 실패"
nvcc --version 2>/dev/null || echo "nvcc 없음 (CUDA 미설치)"

echo ""
echo "설치 완료! 시스템 재부팅을 권장합니다."
