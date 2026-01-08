#!/bin/bash
# AMD ROCm 오프라인 설치 스크립트

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== AMD ROCm 오프라인 설치 ==="

# amdgpu-install 설치
if [ -f amdgpu-install_*.deb ]; then
    echo "amdgpu-install 설치 중..."
    dpkg -i amdgpu-install_*.deb || apt-get -f install -y
fi

# ROCm deb 패키지 설치
echo "ROCm 패키지 설치 중..."
for deb in *.deb; do
    if [ -f "$deb" ] && [ "$deb" != "amdgpu-install_*.deb" ]; then
        echo "  설치: $deb"
        dpkg -i "$deb" 2>/dev/null || true
    fi
done

# 의존성 해결
apt-get -f install -y 2>/dev/null || true

# 환경변수 설정
cat >> /etc/profile.d/rocm.sh << 'ENVEOF'
export PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:$LD_LIBRARY_PATH
ENVEOF

# 사용자를 render/video 그룹에 추가
for user in $(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}'); do
    usermod -aG render,video "$user" 2>/dev/null || true
done

echo ""
echo "=== 설치 확인 ==="
rocm-smi 2>/dev/null || echo "rocm-smi 실행 실패 (GPU가 없거나 드라이버 미설치)"
rocminfo 2>/dev/null | head -20 || echo "rocminfo 실행 실패"

echo ""
echo "설치 완료! 시스템 재부팅을 권장합니다."
