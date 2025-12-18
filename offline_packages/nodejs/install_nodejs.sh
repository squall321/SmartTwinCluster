#!/bin/bash
################################################################################
# Node.js 오프라인 설치 스크립트
#
# 사용법:
#   sudo ./install_nodejs.sh
#
# 설명:
#   오프라인 환경에서 Node.js와 npm을 설치합니다.
#   NodeSource 20.x LTS 버전 기반입니다.
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Node.js 오프라인 설치                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Root 권한 확인
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# 기존 Node.js 확인
if command -v node &>/dev/null; then
    existing_version=$(node -v 2>/dev/null || echo "unknown")
    log_info "Existing Node.js detected: $existing_version"
fi

# deb 파일 찾기
NODEJS_DEB=$(ls "$SCRIPT_DIR"/nodejs_*.deb 2>/dev/null | head -1)

if [[ -z "$NODEJS_DEB" || ! -f "$NODEJS_DEB" ]]; then
    log_error "nodejs_*.deb not found in $SCRIPT_DIR"
    exit 1
fi

log_info "Installing from: $(basename $NODEJS_DEB)"

# 의존성 확인 (Node.js 20.x는 의존성이 적음)
log_info "Checking dependencies..."
required_deps=(libc6 libgcc1 libstdc++6 python3 ca-certificates)
missing_deps=()

for dep in "${required_deps[@]}"; do
    if ! dpkg -l "$dep" &>/dev/null; then
        missing_deps+=("$dep")
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_warning "Missing dependencies: ${missing_deps[*]}"
    log_info "Attempting to install via apt..."
    apt-get update -qq 2>/dev/null || true
    apt-get install -y "${missing_deps[@]}" 2>/dev/null || {
        log_warning "Could not install all dependencies, proceeding anyway..."
    }
fi

# Node.js 설치
log_info "Installing Node.js..."
if dpkg -i "$NODEJS_DEB"; then
    log_success "Node.js installed successfully"
else
    log_warning "dpkg had issues, trying to fix dependencies..."
    apt-get install -f -y 2>/dev/null || true
fi

# npm은 Node.js 20.x에 내장되어 있음
if command -v npm &>/dev/null; then
    log_success "npm is available (bundled with Node.js)"
else
    log_warning "npm not found, may need separate installation"
fi

# 버전 확인
echo ""
log_info "Installed versions:"
echo "  Node.js: $(node -v 2>/dev/null || echo 'not installed')"
echo "  npm:     $(npm -v 2>/dev/null || echo 'not installed')"

# 오프라인 npm 글로벌 패키지 설치
NPM_CACHE_DIR="$SCRIPT_DIR/npm_global_cache"
if [[ -d "$NPM_CACHE_DIR" ]] && ls "$NPM_CACHE_DIR"/*.tgz &>/dev/null; then
    echo ""
    log_info "Installing offline npm global packages..."

    # 패키지 목록
    pkg_count=$(ls "$NPM_CACHE_DIR"/*.tgz 2>/dev/null | wc -l)
    log_info "Found $pkg_count packages in offline cache"

    # 각 패키지 설치
    for tgz in "$NPM_CACHE_DIR"/*.tgz; do
        pkg_name=$(basename "$tgz" | sed 's/-[0-9].*\.tgz$//')
        log_info "Installing: $pkg_name"
        npm install -g "$tgz" 2>/dev/null || {
            log_warning "  Failed to install: $pkg_name (may have dependency issues)"
        }
    done

    log_success "Offline npm packages installation attempted"
else
    # 온라인 fallback: TypeScript 글로벌 설치
    if command -v npm &>/dev/null; then
        log_info "No offline cache found, trying online installation..."
        log_info "Installing TypeScript globally..."
        npm install -g typescript 2>/dev/null && {
            log_success "TypeScript installed: $(tsc -v 2>/dev/null || echo 'installed')"
        } || {
            log_warning "TypeScript installation failed (may need internet or cache)"
            log_info "You can install manually: npm install -g typescript"
        }
    fi
fi

# 설치된 글로벌 패키지 확인
echo ""
log_info "Installed global packages:"
npm list -g --depth=0 2>/dev/null || echo "  (could not list packages)"

echo ""
log_info "Key commands available:"
echo "  Node.js: $(node -v 2>/dev/null || echo 'not installed')"
echo "  npm:     $(npm -v 2>/dev/null || echo 'not installed')"
echo "  tsc:     $(tsc -v 2>/dev/null || echo 'not installed')"
echo "  vite:    $(vite --version 2>/dev/null || echo 'not installed')"

echo ""
log_success "Node.js offline installation complete!"
echo ""
log_info "Next steps:"
echo "  1. Source profile or restart shell: source /etc/profile"
echo "  2. Verify: node -v && npm -v && tsc -v"
echo "  3. Install project dependencies: npm install"
