#!/bin/bash
# GPU 드라이버 오프라인 패키지 다운로드 스크립트
# NVIDIA CUDA/Driver 및 AMD ROCm 패키지
#
# 사용법: ./download_gpu_packages.sh [nvidia|rocm|all]
#
# 다운로드: 공식 사이트에서 최신 버전 다운로드 (runfile/deb)
# 설치: apt 방식으로 (dpkg -i + apt-get -f install)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIDIA_DIR="$SCRIPT_DIR/nvidia"
ROCM_DIR="$SCRIPT_DIR/rocm"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# NVIDIA 패키지 다운로드 (공식 사이트에서)
# ============================================================================
download_nvidia() {
    log_info "=== NVIDIA CUDA/Driver 패키지 다운로드 ==="

    mkdir -p "$NVIDIA_DIR"
    cd "$NVIDIA_DIR"

    # Ubuntu 22.04 용 NVIDIA 드라이버 및 CUDA
    # 최신 안정 버전 (공식 사이트에서 확인)
    NVIDIA_DRIVER_VERSION="550.127.05"
    CUDA_VERSION="12.4.1"

    log_info "NVIDIA 저장소 키 다운로드..."
    # CUDA keyring (저장소 등록용)
    if [ ! -f cuda-keyring_1.1-1_all.deb ]; then
        wget -q --show-progress https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb || {
            log_warning "cuda-keyring 다운로드 실패"
        }
    fi

    # 저장소 등록하여 deb 패키지 다운로드
    log_info "NVIDIA 저장소 등록 중..."
    if [ -f cuda-keyring_1.1-1_all.deb ]; then
        sudo dpkg -i cuda-keyring_1.1-1_all.deb 2>/dev/null || true
        sudo apt-get update -qq 2>/dev/null || true
    fi

    log_info "NVIDIA 드라이버 deb 패키지 다운로드..."
    # apt download로 의존성 포함 다운로드
    local nvidia_packages=(
        "nvidia-driver-550"
        "nvidia-utils-550"
        "libnvidia-gl-550"
        "nvidia-kernel-common-550"
        "nvidia-dkms-550"
    )

    for pkg in "${nvidia_packages[@]}"; do
        if ! ls "${pkg}"*.deb &>/dev/null; then
            log_info "  다운로드: $pkg"
            apt-get download "$pkg" 2>/dev/null || log_warning "  $pkg 다운로드 실패"
            # 의존성도 다운로드
            apt-cache depends "$pkg" 2>/dev/null | grep -E "^\s+Depends:" | awk '{print $2}' | while read dep; do
                [[ -z "$dep" ]] && continue
                [[ "$dep" == *"<"* ]] && continue
                apt-get download "$dep" 2>/dev/null || true
            done
        else
            log_info "  이미 존재: $pkg"
        fi
    done

    log_info "CUDA Toolkit deb 패키지 다운로드..."
    local cuda_packages=(
        "cuda-toolkit-12-4"
        "cuda-libraries-12-4"
        "cuda-compiler-12-4"
        "cuda-nvcc-12-4"
    )

    for pkg in "${cuda_packages[@]}"; do
        if ! ls "${pkg}"*.deb &>/dev/null; then
            log_info "  다운로드: $pkg"
            apt-get download "$pkg" 2>/dev/null || log_warning "  $pkg 다운로드 실패 (CUDA 저장소 필요)"
        else
            log_info "  이미 존재: $pkg"
        fi
    done

    # 설치 스크립트 생성 (apt 방식)
    cat > install_nvidia.sh << 'INSTALL_EOF'
#!/bin/bash
# NVIDIA 드라이버 및 CUDA 오프라인 설치 스크립트 (apt deb 방식)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== NVIDIA 드라이버/CUDA 오프라인 설치 (apt) ==="

# 이미 NVIDIA 드라이버가 설치되어 있는지 확인
if nvidia-smi &>/dev/null; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    echo "NVIDIA 드라이버가 이미 설치되어 있습니다 (버전: $DRIVER_VER)"

    if [ "$1" != "--force" ]; then
        echo "재설치하려면 --force 옵션을 사용하세요"
        echo ""
        nvidia-smi
        exit 0
    fi
    echo "--force 옵션 감지: 재설치 진행..."
fi

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

# deb 파일 확인
DEB_COUNT=$(ls -1 *.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -eq 0 ]; then
    echo "ERROR: deb 패키지가 없습니다."
    echo "온라인 환경에서 download_gpu_packages.sh를 먼저 실행하세요."
    exit 1
fi

echo "발견된 deb 패키지: $DEB_COUNT 개"

# dpkg로 deb 패키지 설치
echo ""
echo "NVIDIA 드라이버 패키지 설치 중..."
for deb in *.deb; do
    [ -f "$deb" ] || continue
    echo "  설치: $deb"
    dpkg -i "$deb" 2>/dev/null || true
done

# 의존성 해결
echo ""
echo "의존성 해결 중..."
apt-get -f install -y 2>/dev/null || {
    echo "WARNING: 일부 의존성 해결 실패 (오프라인 환경에서는 정상)"
}

# 환경변수 설정
if [ -d /usr/local/cuda ]; then
    cat > /etc/profile.d/cuda.sh << 'ENVEOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
ENVEOF
    echo "CUDA 환경변수 설정 완료"
fi

# 확인
echo ""
echo "=== 설치 확인 ==="
nvidia-smi || echo "nvidia-smi 실행 실패 (재부팅 필요할 수 있음)"
nvcc --version 2>/dev/null || echo "nvcc 없음 (CUDA 미설치 또는 경로 미설정)"

echo ""
echo "설치 완료! 시스템 재부팅을 권장합니다."
INSTALL_EOF
    chmod +x install_nvidia.sh

    log_success "NVIDIA 패키지 다운로드 완료: $NVIDIA_DIR"
    ls -lh "$NVIDIA_DIR"
}

# ============================================================================
# AMD ROCm 패키지 다운로드
# ============================================================================
download_rocm() {
    log_info "=== AMD ROCm 패키지 다운로드 ==="

    mkdir -p "$ROCM_DIR"
    cd "$ROCM_DIR"

    # ROCm 6.x 기준 (Ubuntu 22.04)
    ROCM_VERSION="6.0.2"

    log_info "ROCm 저장소 설정 패키지 다운로드..."
    # ROCm 저장소 키 및 설정
    if [ ! -f amdgpu-install_6.0.60002-1_all.deb ]; then
        wget -q --show-progress "https://repo.radeon.com/amdgpu-install/${ROCM_VERSION}/ubuntu/jammy/amdgpu-install_6.0.60002-1_all.deb" || {
            log_warning "amdgpu-install 다운로드 실패"
        }
    fi

    log_info "필수 ROCm deb 패키지 다운로드..."
    # 필수 패키지 목록
    ROCM_PACKAGES=(
        "rocm-smi-lib"
        "rocminfo"
        "rocm-device-libs"
        "hip-runtime-amd"
        "rocm-core"
    )

    # apt를 사용하여 의존성과 함께 다운로드 (온라인 환경에서 실행)
    log_info "ROCm 패키지를 apt로 다운로드하려면 먼저 ROCm 저장소를 추가해야 합니다."
    log_info "온라인 환경에서 다음 명령 실행:"
    echo ""
    echo "  # ROCm 저장소 추가"
    echo "  sudo dpkg -i amdgpu-install_6.0.60002-1_all.deb"
    echo "  sudo amdgpu-install --usecase=rocm --no-dkms -y"
    echo ""
    echo "  # 또는 직접 deb 다운로드"
    echo "  cd $ROCM_DIR"
    echo "  apt download rocm-smi rocminfo hip-runtime-amd rocm-core 2>/dev/null"
    echo ""

    # 설치 스크립트 생성
    cat > install_rocm.sh << 'INSTALL_EOF'
#!/bin/bash
# AMD ROCm 오프라인 설치 스크립트

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== AMD ROCm 오프라인 설치 ==="

# 이미 ROCm이 설치되어 있는지 확인
if rocm-smi &>/dev/null; then
    ROCM_VER=$(cat /opt/rocm/.info/version 2>/dev/null || echo "unknown")
    echo "AMD ROCm이 이미 설치되어 있습니다 (버전: $ROCM_VER)"
    echo "재설치하려면 --force 옵션을 사용하세요"

    if [ "$1" != "--force" ]; then
        echo ""
        rocm-smi --showproductname 2>/dev/null | head -10 || true
        exit 0
    fi
    echo "--force 옵션 감지: 재설치 진행..."
fi

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
INSTALL_EOF
    chmod +x install_rocm.sh

    log_success "ROCm 패키지 준비 완료: $ROCM_DIR"
    ls -lh "$ROCM_DIR"
}

# ============================================================================
# 메인
# ============================================================================
main() {
    local target="${1:-all}"

    echo "========================================"
    echo "  GPU 드라이버 오프라인 패키지 다운로드"
    echo "========================================"
    echo ""

    case "$target" in
        nvidia)
            download_nvidia
            ;;
        rocm)
            download_rocm
            ;;
        all)
            download_nvidia
            echo ""
            download_rocm
            ;;
        *)
            echo "사용법: $0 [nvidia|rocm|all]"
            exit 1
            ;;
    esac

    echo ""
    log_success "=== 완료 ==="
    echo ""
    echo "패키지 위치:"
    echo "  NVIDIA: $NVIDIA_DIR"
    echo "  ROCm:   $ROCM_DIR"
    echo ""
    echo "오프라인 설치:"
    echo "  NVIDIA: cd $NVIDIA_DIR && sudo ./install_nvidia.sh"
    echo "  ROCm:   cd $ROCM_DIR && sudo ./install_rocm.sh"
}

main "$@"
