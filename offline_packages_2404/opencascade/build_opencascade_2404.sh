#!/bin/bash
################################################################################
# OpenCASCADE 7.7.0 빌드 (Ubuntu 24.04용)
#
# 24.04 apt에는 7.6.3만 있고 (libocct-*-7.6t64), 7.7.0은 없음.
# SmartTwinPreprocessor 등이 7.7.0 ABI에 맞춰 빌드되어 있어서 7.7.0 필요.
#
# 사용법 (VM 안에서):
#   sudo bash build_opencascade_2404.sh
#
# 결과:
#   /opt/opencascade-7.7.0/  (cmake, lib, include 등)
#   ./opencascade-7.7.0-noble-prebuilt.tar.gz  (재배포용)
#
# 요구사항: 8 vCPU, 16GB RAM, 30GB 디스크 (빌드 중간)
# 소요 시간: 2~4시간
################################################################################

set -euo pipefail

OCCT_VERSION="7.7.0"
OCCT_TAG="V7_7_0"
INSTALL_PREFIX="/opt/opencascade-${OCCT_VERSION}"
BUILD_DIR="/tmp/occt-build"
# GitHub archive tarball은 V_7_7_0 태그 → OCCT-7_7_0 디렉토리로 풀림
SOURCE_DIR="/tmp/OCCT-7_7_0"
JOBS=$(nproc)

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

[[ $EUID -ne 0 ]] && { log_error "root 필요 (sudo)"; exit 1; }

############################
# 1. 빌드 의존성 설치
############################
log_info "[1/5] 빌드 의존성 설치..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential cmake git wget \
    libfreetype-dev libfreeimage-dev \
    libtbb-dev libtcl8.6 tcl8.6-dev libtk8.6 tk8.6-dev \
    libxmu-dev libxi-dev libgl1-mesa-dev libglu1-mesa-dev \
    libxcomposite-dev libxcursor-dev \
    rapidjson-dev \
    2>&1 | tail -5
log_success "의존성 설치 완료"

############################
# 2. 소스 다운로드
############################
log_info "[2/5] OpenCASCADE ${OCCT_VERSION} 소스 다운로드..."
if [[ ! -d "$SOURCE_DIR" ]]; then
    cd /tmp
    # GitHub mirror (안정적)
    wget -q --show-progress \
        "https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/${OCCT_TAG}.tar.gz" \
        -O OCCT-${OCCT_TAG}.tar.gz
    tar -xzf OCCT-${OCCT_TAG}.tar.gz
    rm OCCT-${OCCT_TAG}.tar.gz
fi
log_success "소스 준비 완료: $SOURCE_DIR"

############################
# 3. CMake 구성
############################
log_info "[3/5] CMake 구성..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$SOURCE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DBUILD_LIBRARY_TYPE=Shared \
    -DBUILD_MODULE_Draw=ON \
    -DBUILD_MODULE_DataExchange=ON \
    -DBUILD_MODULE_FoundationClasses=ON \
    -DBUILD_MODULE_ModelingAlgorithms=ON \
    -DBUILD_MODULE_ModelingData=ON \
    -DBUILD_MODULE_Visualization=ON \
    -DBUILD_MODULE_ApplicationFramework=ON \
    -DUSE_FREEIMAGE=ON \
    -DUSE_TBB=OFF \
    -DUSE_VTK=OFF \
    -DUSE_RAPIDJSON=ON \
    -DBUILD_DOC_Overview=OFF \
    2>&1 | tail -10
log_success "CMake 구성 완료"

############################
# 4. 빌드 (가장 오래 걸림 — 2~4시간)
############################
log_info "[4/5] 빌드 시작 (job=$JOBS, 예상 2~4시간)..."
make -j"$JOBS" 2>&1 | tail -3 &
BUILD_PID=$!

# 진행 상황 표시
while kill -0 $BUILD_PID 2>/dev/null; do
    sleep 60
    log_info "  빌드 진행 중... ($(date +%H:%M:%S))"
done
wait $BUILD_PID
log_success "빌드 완료"

############################
# 5. 설치 + 압축
############################
log_info "[5/5] 설치 + 압축..."
make install 2>&1 | tail -3
log_success "설치: $INSTALL_PREFIX"

# 결과 크기
log_info "설치 크기: $(du -sh $INSTALL_PREFIX | cut -f1)"

# tar.gz 압축 (재배포용)
TARBALL_DIR="$(dirname "$0")"
TARBALL="${TARBALL_DIR}/opencascade-${OCCT_VERSION}-noble-prebuilt.tar.gz"
log_info "압축 중: $TARBALL"
tar -czf "$TARBALL" -C "$(dirname "$INSTALL_PREFIX")" "$(basename "$INSTALL_PREFIX")"
log_success "압축 완료: $(du -h "$TARBALL" | cut -f1)"

# md5
md5sum "$TARBALL" > "${TARBALL}.md5"

# 정리
rm -rf "$BUILD_DIR" "$SOURCE_DIR"

echo ""
log_success "=== OpenCASCADE 7.7.0 빌드 완료 ==="
log_info "설치 경로: $INSTALL_PREFIX"
log_info "tarball:   $TARBALL"
log_info "md5:       $(cat ${TARBALL}.md5 | awk '{print $1}')"
log_info ""
log_info "다른 노드 배포:"
log_info "  scp $TARBALL user@node:/tmp/"
log_info "  ssh user@node 'sudo tar -xzf /tmp/$(basename $TARBALL) -C /opt/'"
