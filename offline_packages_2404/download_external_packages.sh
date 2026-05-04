#!/bin/bash
################################################################################
# 외부 패키지 다운로드 스크립트 (Ubuntu 24.04용)
#
# 설명:
#   APT 저장소에 없거나 별도 다운로드가 필요한 패키지를 수집합니다.
#   - Grafana (apt 저장소에 없음)
#   - 최신 NVIDIA 드라이버 (RTX PRO 6000 등 신규 GPU용)
#   - CUDA 최신 버전 (.run 인스톨러)
#   - FFmpeg (Sunshine 스트리밍 빌드용)
#
# 인터넷이 연결된 환경에서 실행 후 결과를 오프라인 서버로 복사하면 됩니다.
#
# 사용법:
#   sudo ./download_external_packages.sh [OPTIONS]
#
# 옵션:
#   --grafana            Grafana .deb 다운로드
#   --nvidia VERSION     NVIDIA 드라이버 버전 (기본: 580.65.06)
#   --cuda VERSION       CUDA 버전 (기본: 12.8.0)
#   --all                위 항목 전부 다운로드
#   --skip-existing      이미 존재하는 파일은 건너뜀
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APT_DIR="${SCRIPT_DIR}/apt_packages"
GPU_DIR="${SCRIPT_DIR}/gpu"

# 기본값
GRAFANA_VERSION="10.4.0"
NVIDIA_VERSION="580.65.06"
CUDA_VERSION="12.8.0"
CUDA_DRIVER_VERSION="570.86.10"

DOWNLOAD_GRAFANA=false
DOWNLOAD_NVIDIA=false
DOWNLOAD_CUDA=false
DOWNLOAD_SUNSHINE=false
DOWNLOAD_CUDA_KEYRING=false
DOWNLOAD_CHROME=false
DOWNLOAD_VSCODE=false
SKIP_EXISTING=false

SUNSHINE_VERSION="0.23.1"

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --grafana) DOWNLOAD_GRAFANA=true; shift ;;
        --nvidia)  DOWNLOAD_NVIDIA=true; NVIDIA_VERSION="${2:-$NVIDIA_VERSION}"; shift 2 ;;
        --cuda)    DOWNLOAD_CUDA=true; CUDA_VERSION="${2:-$CUDA_VERSION}"; shift 2 ;;
        --sunshine) DOWNLOAD_SUNSHINE=true; shift ;;
        --cuda-keyring) DOWNLOAD_CUDA_KEYRING=true; shift ;;
        --chrome) DOWNLOAD_CHROME=true; shift ;;
        --vscode) DOWNLOAD_VSCODE=true; shift ;;
        --all)     DOWNLOAD_GRAFANA=true; DOWNLOAD_NVIDIA=true; DOWNLOAD_CUDA=true; DOWNLOAD_SUNSHINE=true; DOWNLOAD_CUDA_KEYRING=true; DOWNLOAD_CHROME=true; DOWNLOAD_VSCODE=true; shift ;;
        --skip-existing) SKIP_EXISTING=true; shift ;;
        --help|-h)
            head -30 "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Note: GPU 디렉토리는 22.04 prepare 스크립트가 심볼릭 링크로 만듭니다.
# 심볼릭 링크면 실제 디렉토리로 변환해서 새 파일 추가 가능하게 함
if [[ -L "$GPU_DIR" ]]; then
    real_gpu=$(readlink -f "$GPU_DIR")
    log_info "GPU 디렉토리는 심볼릭 링크: $real_gpu"
    log_info "다운로드는 실제 경로에 저장됩니다"
    GPU_DIR="$real_gpu"
fi

mkdir -p "$APT_DIR" "$GPU_DIR/nvidia"

download_file() {
    local url="$1"
    local dest="$2"
    local name=$(basename "$dest")

    if [[ -f "$dest" ]] && [[ "$SKIP_EXISTING" == "true" ]]; then
        log_info "이미 존재 (스킵): $name"
        return 0
    fi

    log_info "다운로드: $name"
    if wget --progress=bar:force -O "$dest" "$url"; then
        log_success "완료: $name ($(du -h "$dest" | cut -f1))"
    else
        log_error "실패: $url"
        rm -f "$dest"
        return 1
    fi
}

############################
# Grafana
############################
if [[ "$DOWNLOAD_GRAFANA" == "true" ]]; then
    log_info "=== Grafana ${GRAFANA_VERSION} ==="
    download_file \
        "https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb" \
        "${APT_DIR}/grafana_${GRAFANA_VERSION}_amd64.deb"

    # APT repo 인덱스 갱신 (있는 경우)
    if [[ -f "${APT_DIR}/Packages.gz" ]]; then
        log_info "APT 인덱스 갱신 중..."
        (cd "$APT_DIR" && dpkg-scanpackages . /dev/null 2>/dev/null > Packages && gzip -k -f Packages)
        log_success "Packages.gz 갱신 완료"
    fi
fi

############################
# NVIDIA 드라이버 (최신 — RTX PRO 6000 / RTX 50 시리즈용)
############################
if [[ "$DOWNLOAD_NVIDIA" == "true" ]]; then
    log_info "=== NVIDIA 드라이버 ${NVIDIA_VERSION} ==="
    download_file \
        "https://us.download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_VERSION}/NVIDIA-Linux-x86_64-${NVIDIA_VERSION}.run" \
        "${GPU_DIR}/nvidia/NVIDIA-Linux-x86_64-${NVIDIA_VERSION}.run"

    # 실행 권한 부여
    chmod +x "${GPU_DIR}/nvidia/NVIDIA-Linux-x86_64-${NVIDIA_VERSION}.run"
fi

############################
# CUDA Toolkit
############################
if [[ "$DOWNLOAD_CUDA" == "true" ]]; then
    log_info "=== CUDA Toolkit ${CUDA_VERSION} ==="
    # CUDA .run 파일 명명 규칙: cuda_<버전>_<드라이버>_linux.run
    download_file \
        "https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/cuda_${CUDA_VERSION}_${CUDA_DRIVER_VERSION}_linux.run" \
        "${GPU_DIR}/nvidia/cuda_${CUDA_VERSION}_${CUDA_DRIVER_VERSION}_linux.run"

    chmod +x "${GPU_DIR}/nvidia/cuda_${CUDA_VERSION}_${CUDA_DRIVER_VERSION}_linux.run"
fi

############################
# Sunshine (게임 스트리밍 서버 — Apptainer SIF 빌드용)
############################
if [[ "$DOWNLOAD_SUNSHINE" == "true" ]]; then
    log_info "=== Sunshine ${SUNSHINE_VERSION} (Ubuntu 24.04) ==="
    download_file \
        "https://github.com/LizardByte/Sunshine/releases/download/v${SUNSHINE_VERSION}/sunshine-ubuntu-24.04-amd64.deb" \
        "${APT_DIR}/sunshine-ubuntu-24.04-amd64.deb"
fi

############################
# CUDA Keyring (Apptainer SIF 빌드 시 NVIDIA APT 저장소 등록용)
############################
if [[ "$DOWNLOAD_CUDA_KEYRING" == "true" ]]; then
    log_info "=== CUDA Keyring ==="
    download_file \
        "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb" \
        "${APT_DIR}/cuda-keyring_1.1-1_all.deb"
fi

############################
# Google Chrome (.deb)
############################
if [[ "$DOWNLOAD_CHROME" == "true" ]]; then
    log_info "=== Google Chrome (stable) ==="
    download_file \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
        "${APT_DIR}/google-chrome-stable_current_amd64.deb"
fi

############################
# Visual Studio Code (.deb)
############################
if [[ "$DOWNLOAD_VSCODE" == "true" ]]; then
    log_info "=== Visual Studio Code (stable, x64) ==="
    download_file \
        "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" \
        "${APT_DIR}/code_latest_amd64.deb"
fi

############################
# 요약
############################
log_success ""
log_success "=== 다운로드 완료 ==="
[[ "$DOWNLOAD_GRAFANA" == "true" ]] && ls -lh "${APT_DIR}/grafana_"*.deb 2>/dev/null
[[ "$DOWNLOAD_NVIDIA" == "true" || "$DOWNLOAD_CUDA" == "true" ]] && ls -lh "${GPU_DIR}/nvidia/"*.run 2>/dev/null

log_info ""
log_info "총 GPU 디렉토리 크기: $(du -sh "$GPU_DIR" 2>/dev/null | cut -f1)"
log_info "총 APT 디렉토리 크기: $(du -sh "$APT_DIR" 2>/dev/null | cut -f1)"
