#!/bin/bash
################################################################################
# 오프라인 패키지 설치 스크립트 (로컬 APT 저장소 방식)
#
# 이 스크립트는 dpkg 대신 apt를 사용하여 패키지를 설치합니다.
# apt는 의존성을 자동으로 해결하므로 dpkg보다 안전합니다.
#
# 사용법:
#   sudo ./install_offline_packages.sh [PACKAGE...]
#
# 예시:
#   sudo ./install_offline_packages.sh                # 모든 패키지 설치
#   sudo ./install_offline_packages.sh nginx nodejs   # 특정 패키지만 설치
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="offline-local"
REPO_LIST="/etc/apt/sources.list.d/${REPO_NAME}.list"

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

# Root 권한 확인
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          오프라인 패키지 설치 (APT 저장소 방식)            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Package directory: $SCRIPT_DIR"

# .deb 파일 개수 확인
DEB_COUNT=$(find "$SCRIPT_DIR" -name "*.deb" | wc -l)
log_info "Found $DEB_COUNT .deb files"

if [[ $DEB_COUNT -eq 0 ]]; then
    log_error "No .deb files found in $SCRIPT_DIR"
    exit 1
fi

# Packages.gz 확인 (없으면 생성)
if [[ ! -f "$SCRIPT_DIR/Packages.gz" ]]; then
    log_warning "Packages.gz not found. Creating repository index..."

    if ! command -v dpkg-scanpackages &> /dev/null; then
        log_info "Installing dpkg-dev for dpkg-scanpackages..."
        # 먼저 dpkg-dev가 로컬에 있는지 확인
        if ls "$SCRIPT_DIR"/dpkg-dev*.deb &>/dev/null; then
            dpkg -i "$SCRIPT_DIR"/dpkg-dev*.deb 2>/dev/null || apt-get install -f -y
        else
            log_error "dpkg-dev not found. Please ensure dpkg-dev is in the package collection."
            exit 1
        fi
    fi

    cd "$SCRIPT_DIR"
    dpkg-scanpackages . /dev/null > Packages
    gzip -k -f Packages
    cd - > /dev/null
    log_success "Repository index created"
fi

echo ""
log_info "Step 1: Setting up local APT repository..."

# 기존 온라인 저장소 백업 및 비활성화 (선택사항)
if [[ -f /etc/apt/sources.list ]]; then
    if [[ ! -f /etc/apt/sources.list.backup-offline ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup-offline
        log_info "  Backed up /etc/apt/sources.list"
    fi
fi

# 로컬 저장소 추가
echo "deb [trusted=yes] file://$SCRIPT_DIR ./" > "$REPO_LIST"
log_success "  Local repository configured: $REPO_LIST"

echo ""
log_info "Step 2: Updating APT cache..."
apt-get update -o Dir::Etc::sourcelist="$REPO_LIST" \
               -o Dir::Etc::sourceparts="-" \
               -o APT::Get::List-Cleanup="0" 2>/dev/null || apt-get update

log_success "  APT cache updated"

echo ""
log_info "Step 3: Installing packages..."

# ============================================================================
# 소스 빌드 Slurm 23.x 감지 시 slurm 관련 apt 패키지 설치 건너뜀
# ============================================================================
SKIP_SLURM_PACKAGES=false
for prefix in /usr/local/slurm /opt/slurm; do
    if [[ -x "$prefix/bin/sinfo" ]]; then
        slurm_version=$("$prefix/bin/sinfo" --version 2>/dev/null | head -1)
        major_version=$(echo "$slurm_version" | grep -oP 'slurm \K[0-9]+' | head -1)
        if [[ "$major_version" -ge 23 ]]; then
            log_info "  Source-built Slurm detected: $slurm_version at $prefix"
            log_info "  Skipping slurm-related apt packages to avoid conflicts"
            SKIP_SLURM_PACKAGES=true
            break
        fi
    fi
done

# 특정 패키지 지정 여부 확인
if [[ $# -gt 0 ]]; then
    # 지정된 패키지만 설치
    PACKAGES_TO_INSTALL=("$@")
    log_info "  Installing specified packages: ${PACKAGES_TO_INSTALL[*]}"
else
    # 모든 패키지 설치 (package_list.txt 사용)
    if [[ -f "$SCRIPT_DIR/package_list.txt" ]]; then
        # package_list.txt에서 패키지 이름 추출
        PACKAGES_TO_INSTALL=()
        while IFS= read -r deb_file; do
            # .deb 파일명에서 패키지 이름 추출 (패키지명_버전_아키텍처.deb)
            pkg_name=$(echo "$deb_file" | sed 's/_.*$//')
            PACKAGES_TO_INSTALL+=("$pkg_name")
        done < "$SCRIPT_DIR/package_list.txt"
        log_info "  Installing all ${#PACKAGES_TO_INSTALL[@]} packages from package_list.txt"
    else
        log_error "No package list found and no packages specified"
        log_info "Usage: $0 [PACKAGE...]"
        exit 1
    fi
fi

# 소스 빌드 Slurm이 있으면 slurm 관련 패키지 제외
if [[ "$SKIP_SLURM_PACKAGES" == "true" ]]; then
    FILTERED_PACKAGES=()
    for pkg in "${PACKAGES_TO_INSTALL[@]}"; do
        # slurm 관련 패키지 필터링 (libslurm, slurm-wlm, slurmctld, slurmd, slurmdbd 등)
        if [[ "$pkg" =~ ^(lib)?slurm ]]; then
            log_warning "  Skipping $pkg (source-built Slurm detected)"
        else
            FILTERED_PACKAGES+=("$pkg")
        fi
    done
    PACKAGES_TO_INSTALL=("${FILTERED_PACKAGES[@]}")
    log_info "  Packages after filtering: ${#PACKAGES_TO_INSTALL[@]}"
fi

# 중복 제거
PACKAGES_TO_INSTALL=($(printf '%s\n' "${PACKAGES_TO_INSTALL[@]}" | sort -u))

# apt install 실행 (의존성 자동 해결)
log_info "  Running: apt-get install -y ${#PACKAGES_TO_INSTALL[@]} packages..."
apt-get install -y --no-install-recommends "${PACKAGES_TO_INSTALL[@]}" 2>&1 || {
    log_warning "Some packages may have failed. Retrying with -f flag..."
    apt-get install -f -y
}

echo ""
log_info "Step 4: Cleanup..."

# 로컬 저장소 설정 유지 (나중에 추가 패키지 설치 가능)
# 제거하려면 아래 주석 해제:
# rm -f "$REPO_LIST"
# apt-get update

log_info "  Local repository kept at: $REPO_LIST"
log_info "  To remove: sudo rm $REPO_LIST && sudo apt-get update"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          ✅ 오프라인 패키지 설치 완료!                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Installed packages summary:"
echo "  Total installed: $(dpkg -l | grep "^ii" | wc -l)"
echo ""
log_info "Tips:"
echo "  - To restore online repos: sudo mv /etc/apt/sources.list.backup-offline /etc/apt/sources.list"
echo "  - To install more packages: sudo apt-get install <package-name>"
echo "  - Repository will use local .deb files first"
echo ""
