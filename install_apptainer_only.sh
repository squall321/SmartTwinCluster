#!/bin/bash
################################################################################
# apptainer 단독 설치 스크립트 (오프라인 APT 저장소 사용)
#
# 설명:
#   오프라인 환경에서 로컬 APT 저장소를 사용하여 apptainer만 설치합니다.
#   compute/viz 노드에서 apptainer만 빠르게 설치/재설치할 때 사용합니다.
#
# 사용법:
#   sudo ./install_apptainer_only.sh
#
# 전제조건:
#   - /etc/apt/sources.list.d/offline-local.list가 설정되어 있어야 함
#   - 또는 오프라인 패키지 디렉토리 경로 지정
#
# 작성자: Claude Code
# 날짜: 2026-01-21
################################################################################

set -euo pipefail

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
    log_error "This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║       apptainer 단독 설치 (오프라인 APT 저장소)           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# APT 로컬 저장소 경로
REPO_LIST="/etc/apt/sources.list.d/offline-local.list"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# OS 감지 및 오프라인 패키지 디렉토리 자동 선택
source "${SCRIPT_DIR}/cluster/utils/detect_os.sh"
detect_os_version
set_offline_pkg_dir "$SCRIPT_DIR"
OFFLINE_PKG_DIR="${OFFLINE_PKG_DIR}/apt_packages"

# 1. apptainer가 이미 설치되어 있는지 확인
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 1: Checking current apptainer installation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v apptainer &>/dev/null; then
    CURRENT_VERSION=$(apptainer --version 2>/dev/null || echo "unknown")
    log_info "apptainer is already installed: $CURRENT_VERSION"
    echo ""
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    log_warning "Proceeding with reinstallation..."
else
    log_info "apptainer is not installed"
fi
echo ""

# 2. APT 로컬 저장소 확인
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 2: Checking offline APT repository..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -f "$REPO_LIST" ]]; then
    log_success "Offline APT repository found: $REPO_LIST"
    cat "$REPO_LIST"
    echo ""
    USE_APT=true
else
    log_warning "Offline APT repository not configured: $REPO_LIST"

    # 로컬 저장소 자동 설정 시도
    if [[ -d "$OFFLINE_PKG_DIR" ]] && ls "$OFFLINE_PKG_DIR"/*.deb &>/dev/null; then
        log_info "Found offline packages directory: $OFFLINE_PKG_DIR"
        echo ""
        read -p "Do you want to set up local APT repository now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            log_info "Setting up local APT repository..."

            # Packages.gz 생성
            if ! command -v dpkg-scanpackages &>/dev/null; then
                log_warning "dpkg-scanpackages not found, installing dpkg-dev..."
                if ls "$OFFLINE_PKG_DIR"/dpkg-dev*.deb &>/dev/null; then
                    dpkg -i "$OFFLINE_PKG_DIR"/dpkg-dev*.deb 2>/dev/null || apt-get install -f -y
                fi
            fi

            if command -v dpkg-scanpackages &>/dev/null; then
                cd "$OFFLINE_PKG_DIR"
                dpkg-scanpackages . /dev/null > Packages
                gzip -k -f Packages
                cd - > /dev/null

                # 저장소 등록
                echo "deb [trusted=yes] file://$OFFLINE_PKG_DIR ./" > "$REPO_LIST"
                apt-get update -o Dir::Etc::sourcelist="$REPO_LIST" \
                               -o Dir::Etc::sourceparts="-" \
                               -o APT::Get::List-Cleanup="0" 2>/dev/null || apt-get update
                log_success "Local APT repository configured"
                USE_APT=true
            else
                log_error "Failed to set up APT repository"
                USE_APT=false
            fi
        else
            USE_APT=false
        fi
    else
        log_error "Offline packages not found: $OFFLINE_PKG_DIR"
        USE_APT=false
    fi
fi
echo ""

# 3. apptainer 설치
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 3: Installing apptainer..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$USE_APT" == true ]]; then
    # APT 로컬 저장소로 설치 (권장)
    log_info "Installing via APT (local offline repository)..."

    APT_OPTS=(-o Dir::Etc::sourcelist="$REPO_LIST" -o Dir::Etc::sourceparts="-")

    if apt-get "${APT_OPTS[@]}" install -y apptainer 2>&1 | tee /tmp/apptainer_install.log; then
        log_success "apptainer installed successfully via APT"
    else
        log_warning "APT install failed, trying with all sources..."
        if apt-get install -y apptainer 2>&1 | tee -a /tmp/apptainer_install.log; then
            log_success "apptainer installed via APT (all sources)"
        else
            log_error "APT installation failed"
            echo "See log: /tmp/apptainer_install.log"
            exit 1
        fi
    fi
else
    # Fallback: dpkg 직접 설치
    log_warning "Falling back to dpkg direct installation..."

    APPTAINER_DEB=$(ls "$OFFLINE_PKG_DIR"/apptainer_*.deb 2>/dev/null | head -1)

    if [[ -f "$APPTAINER_DEB" ]]; then
        log_info "Found: $APPTAINER_DEB"

        if dpkg -i "$APPTAINER_DEB" 2>&1 | tee /tmp/apptainer_install.log; then
            log_success "apptainer installed via dpkg"
        else
            log_warning "dpkg install failed, resolving dependencies..."
            if apt-get install -f -y 2>&1 | tee -a /tmp/apptainer_install.log; then
                log_success "Dependencies resolved, apptainer installed"
            else
                log_error "Installation failed"
                echo "See log: /tmp/apptainer_install.log"
                exit 1
            fi
        fi
    else
        log_error "apptainer package not found in $OFFLINE_PKG_DIR"
        exit 1
    fi
fi
echo ""

# 4. 설치 확인
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 4: Verifying installation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v apptainer &>/dev/null; then
    VERSION=$(apptainer --version)
    log_success "apptainer installed: $VERSION"

    # 설정 파일 확인
    if [[ -f /etc/apptainer/apptainer.conf ]]; then
        log_success "Configuration file exists: /etc/apptainer/apptainer.conf"
    else
        log_error "Configuration file missing: /etc/apptainer/apptainer.conf"
        echo "This may cause runtime errors!"
    fi

    # 간단한 테스트
    echo ""
    log_info "Running basic test..."
    if timeout 10 apptainer --version &>/dev/null; then
        log_success "Basic test passed"
    else
        log_warning "Basic test failed or timed out"
    fi
else
    log_error "apptainer installation verification failed"
    exit 1
fi
echo ""

# 5. /scratch/vnc_sandboxes 디렉토리 생성
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 5: Creating sandbox directory..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p /scratch/vnc_sandboxes
chmod 1777 /scratch/vnc_sandboxes
log_success "/scratch/vnc_sandboxes created with permissions 1777"
ls -ld /scratch/vnc_sandboxes
echo ""

# 완료
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          ✅ apptainer 설치 완료!                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Installation summary:"
echo "  Version: $VERSION"
echo "  Binary: $(which apptainer)"
echo "  Config: /etc/apptainer/apptainer.conf"
echo "  Sandbox: /scratch/vnc_sandboxes"
echo ""
log_info "You can now run Slurm jobs with apptainer containers!"
echo ""
