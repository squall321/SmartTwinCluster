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
# 방법 1: 번들 디렉토리에서 복원 (100% 오프라인 보장)
NPM_BUNDLE_DIR="$SCRIPT_DIR/npm_global_bundle"
NPM_BUNDLE_TAR="$SCRIPT_DIR/npm_global_bundle.tar.gz"

install_from_bundle() {
    local source_dir="$1"

    # npm 글로벌 경로 확인
    NPM_GLOBAL_PREFIX=$(npm config get prefix 2>/dev/null || echo "/usr")
    log_info "npm global prefix: $NPM_GLOBAL_PREFIX"

    # node_modules 복사
    if [[ -d "$source_dir/node_modules" ]]; then
        log_info "Copying global node_modules..."
        mkdir -p "$NPM_GLOBAL_PREFIX/lib/node_modules"
        cp -r "$source_dir/node_modules/"* "$NPM_GLOBAL_PREFIX/lib/node_modules/" 2>/dev/null || {
            # /usr/lib/node_modules 시도
            mkdir -p /usr/lib/node_modules
            cp -r "$source_dir/node_modules/"* /usr/lib/node_modules/
        }
        log_success "Global node_modules installed"
    fi

    # bin 파일 복사 (심볼릭 링크 재생성)
    if [[ -d "$source_dir/bin" ]]; then
        log_info "Setting up global binaries..."

        # 각 바이너리에 대해 심볼릭 링크 생성
        for cmd in "$source_dir/bin/"*; do
            [[ -e "$cmd" ]] || continue
            cmd_name=$(basename "$cmd")

            # 실제 실행 파일 경로 찾기
            if [[ -L "$cmd" ]]; then
                # 심볼릭 링크의 대상 확인
                target=$(readlink "$cmd")
                # node_modules 경로 추출
                if [[ "$target" == *"node_modules"* ]]; then
                    pkg_path="${target#*node_modules/}"
                    real_path="$NPM_GLOBAL_PREFIX/lib/node_modules/$pkg_path"

                    if [[ -f "$real_path" ]]; then
                        ln -sf "$real_path" "/usr/bin/$cmd_name" 2>/dev/null || \
                        ln -sf "$real_path" "$NPM_GLOBAL_PREFIX/bin/$cmd_name" 2>/dev/null || true
                    fi
                fi
            else
                # 일반 파일이면 직접 복사
                cp "$cmd" "/usr/bin/$cmd_name" 2>/dev/null || \
                cp "$cmd" "$NPM_GLOBAL_PREFIX/bin/$cmd_name" 2>/dev/null || true
            fi
        done

        # 주요 명령어 심볼릭 링크 직접 생성
        create_symlink() {
            local cmd="$1"
            local pkg="$2"
            local bin_file="$3"

            local full_path="$NPM_GLOBAL_PREFIX/lib/node_modules/$pkg/$bin_file"
            [[ -f "$full_path" ]] || full_path="/usr/lib/node_modules/$pkg/$bin_file"

            if [[ -f "$full_path" ]]; then
                ln -sf "$full_path" "/usr/bin/$cmd" 2>/dev/null || true
                log_info "  Linked: $cmd"
            fi
        }

        create_symlink "tsc" "typescript" "bin/tsc"
        create_symlink "tsserver" "typescript" "bin/tsserver"
        create_symlink "ts-node" "ts-node" "dist/bin.js"
        create_symlink "pnpm" "pnpm" "bin/pnpm.cjs"
        create_symlink "pnpx" "pnpm" "bin/pnpx.cjs"
        create_symlink "terser" "terser" "bin/terser"
        create_symlink "vite" "vite" "bin/vite.js"

        log_success "Global binaries configured"
    fi

    return 0
}

if [[ -d "$NPM_BUNDLE_DIR" ]] && [[ -d "$NPM_BUNDLE_DIR/node_modules" ]]; then
    echo ""
    log_info "Found npm global bundle directory"
    install_from_bundle "$NPM_BUNDLE_DIR"

elif [[ -f "$NPM_BUNDLE_TAR" ]]; then
    echo ""
    log_info "Found npm global bundle archive, extracting..."

    TEMP_EXTRACT="$SCRIPT_DIR/.npm_bundle_temp"
    rm -rf "$TEMP_EXTRACT"
    mkdir -p "$TEMP_EXTRACT"

    tar -xzf "$NPM_BUNDLE_TAR" -C "$TEMP_EXTRACT"
    install_from_bundle "$TEMP_EXTRACT"

    rm -rf "$TEMP_EXTRACT"

else
    # 방법 2: tgz 캐시에서 설치 시도 (온라인 fallback 포함)
    NPM_CACHE_DIR="$SCRIPT_DIR/npm_global_cache"

    if [[ -d "$NPM_CACHE_DIR" ]] && ls "$NPM_CACHE_DIR"/*.tgz &>/dev/null 2>&1; then
        echo ""
        log_info "Found npm cache, attempting cache-based installation..."
        log_warning "Note: This method may not work in completely offline environments"

        # npm 캐시에 추가
        for tgz in "$NPM_CACHE_DIR"/*.tgz; do
            npm cache add "$tgz" 2>/dev/null || true
        done

        # 핵심 패키지만 설치 시도
        for pkg in typescript pnpm terser; do
            pkg_file=$(ls "$NPM_CACHE_DIR"/${pkg}-[0-9]*.tgz 2>/dev/null | head -1)
            if [[ -f "$pkg_file" ]]; then
                log_info "Installing: $pkg"
                npm install -g "$pkg_file" --prefer-offline 2>&1 | grep -v "^npm WARN" || true
            fi
        done
    else
        # 온라인 fallback
        if command -v npm &>/dev/null; then
            log_info "No offline packages found"
            log_info "You can install packages manually when online:"
            echo "  npm install -g typescript ts-node pnpm terser vite"
        fi
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
echo "  pnpm:    $(pnpm -v 2>/dev/null || echo 'not installed')"
echo "  terser:  $(terser --version 2>/dev/null || echo 'not installed')"
echo "  vite:    $(vite --version 2>/dev/null || echo 'not installed')"

echo ""
log_success "Node.js offline installation complete!"
echo ""
log_info "Next steps:"
echo "  1. Source profile or restart shell: source /etc/profile"
echo "  2. Verify: node -v && npm -v && tsc -v"
echo "  3. Install project dependencies: npm install"
