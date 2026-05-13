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

# Packages.gz 확인 (헤드노드에서 미리 생성된 인덱스 사용)
if [[ ! -f "$SCRIPT_DIR/Packages.gz" ]] || [[ ! -f "$SCRIPT_DIR/Packages" ]]; then
    log_warning "Packages.gz not found. Creating repository index..."

    if ! command -v dpkg-scanpackages &> /dev/null; then
        log_info "Installing dpkg-dev for dpkg-scanpackages..."
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
    chmod 644 Packages Packages.gz
    cd - > /dev/null
    log_success "Repository index created"
else
    # Ensure Packages files are readable by apt (root may have created them with 600)
    chmod 644 "$SCRIPT_DIR/Packages" "$SCRIPT_DIR/Packages.gz" 2>/dev/null || true
    log_success "Using pre-built repository index (Packages.gz)"
fi

echo ""
log_info "Step 1: Setting up local APT repository..."

# 기존 온라인 저장소 백업 및 비활성화 (오프라인 환경 필수)
if [[ -f /etc/apt/sources.list ]]; then
    if [[ ! -f /etc/apt/sources.list.backup-offline ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup-offline
        log_info "  Backed up /etc/apt/sources.list"
    fi
    # 온라인 저장소 완전 비활성화 (오프라인 환경)
    echo "# Disabled for offline installation" > /etc/apt/sources.list
    log_info "  Disabled online repositories in /etc/apt/sources.list"
fi

# sources.list.d의 온라인 저장소도 비활성화
if ls /etc/apt/sources.list.d/*.list &>/dev/null; then
    for f in /etc/apt/sources.list.d/*.list; do
        # offline-local.list는 제외
        if [[ "$f" != "$REPO_LIST" ]]; then
            mv "$f" "$f.disabled-offline" 2>/dev/null || true
        fi
    done
    log_info "  Disabled online repositories in /etc/apt/sources.list.d/"
fi

# 로컬 저장소 추가
echo "deb [trusted=yes] file://$SCRIPT_DIR ./" > "$REPO_LIST"
log_success "  Local repository configured: $REPO_LIST"

echo ""
log_info "Step 2: Updating APT cache (local repository only)..."

# APT 캐시 완전 초기화 (이전 온라인 저장소 캐시가 남아있으면 로컬 패키지를 못 찾음)
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
apt-get clean 2>/dev/null || true

apt-get update 2>&1 | grep -v "^W:" || true

# 로컬 저장소에서 패키지를 인식하는지 확인
LOCAL_PKG_COUNT=$(apt-cache pkgnames 2>/dev/null | wc -l)
log_info "  APT recognizes $LOCAL_PKG_COUNT packages from local repository"

log_success "  APT cache updated"

echo ""
log_info "Step 3: Installing packages..."

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

# ============================================================================
# Slurm apt 패키지 무조건 제외 (소스 빌드 23.x만 사용)
# apt 패키지의 Slurm 21.x는 지원하지 않음
# ============================================================================
FILTERED_PACKAGES=()
for pkg in "${PACKAGES_TO_INSTALL[@]}"; do
    # slurm 관련 패키지 필터링 (libslurm, slurm-wlm, slurmctld, slurmd, slurmdbd 등)
    if [[ "$pkg" =~ ^(lib)?slurm ]]; then
        log_warning "  Skipping $pkg (apt slurm packages not supported - use source-built Slurm 23.x)"
    else
        FILTERED_PACKAGES+=("$pkg")
    fi
done
PACKAGES_TO_INSTALL=("${FILTERED_PACKAGES[@]}")
log_info "  Packages after filtering: ${#PACKAGES_TO_INSTALL[@]}"

# 중복 제거
PACKAGES_TO_INSTALL=($(printf '%s\n' "${PACKAGES_TO_INSTALL[@]}" | sort -u))

# apt install 실행 (의존성 자동 해결)
# 중요: 오프라인 환경에서는 로컬 저장소만 사용 (온라인 저장소는 이미 비활성화됨)
log_info "  Running: apt-get install -y ${#PACKAGES_TO_INSTALL[@]} packages..."

# 온라인 저장소가 이미 비활성화되었으므로 일반 apt-get 사용
apt-get install -y --no-install-recommends "${PACKAGES_TO_INSTALL[@]}" 2>&1 || {
    log_warning "Some packages may have failed. Retrying with -f flag..."
    apt-get install -f -y 2>&1 || true
}

# ============================================================================
# apt-get 일괄 설치 실패 시 핵심 패키지 개별 재시도 (apt-get만 사용)
# 일괄 설치에서 일부가 실패하면 전체가 스킵될 수 있으므로,
# 핵심 패키지를 개별적으로 apt-get install 시도
# ============================================================================
CRITICAL_PACKAGES=(
    "libpmix2"
    "libpmix-dev"
    "libhwloc15"
    "hwloc-nox"
    "libhwloc-plugins"
    "libmunge2"
    "libmunge-dev"
    "munge"
    "autofs"
    "net-tools"
    "jq"
    "libjq1"
    "socat"
    "pv"
    "sshpass"
    "squashfuse"
    "libsquashfuse0"
    "libfuse2"
    "fuse2fs"
)

RETRY_COUNT=0
for pkg in "${CRITICAL_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
        log_info "  Retrying critical package: $pkg"
        apt-get install -y --no-install-recommends "$pkg" 2>&1 || {
            log_warning "  Failed to install $pkg (may not be available in local repository)"
        }
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

if [[ $RETRY_COUNT -gt 0 ]]; then
    log_info "  Retried $RETRY_COUNT critical packages individually"
fi

echo ""
log_info "Step 4: Cleanup..."

# 로컬 저장소 설정 유지 (나중에 추가 패키지 설치 가능)
# 제거하려면 아래 주석 해제:
# rm -f "$REPO_LIST"
# apt-get update

log_info "  Local repository kept at: $REPO_LIST"
log_info "  Online repositories disabled (backed up)"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          ✅ 오프라인 패키지 설치 완료!                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Installed packages summary:"
echo "  Total installed: $(dpkg -l | grep "^ii" | wc -l)"
echo ""
log_info "Tips:"
echo "  - To restore online repos:"
echo "    sudo mv /etc/apt/sources.list.backup-offline /etc/apt/sources.list"
echo "    sudo mv /etc/apt/sources.list.d/*.disabled-offline /etc/apt/sources.list.d/ (remove .disabled-offline)"
echo "    sudo apt-get update"
echo "  - To install more packages: sudo apt-get install <package-name>"
echo "  - Repository is using local .deb files only (offline mode)"
echo ""
