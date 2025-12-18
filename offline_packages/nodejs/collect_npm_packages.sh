#!/bin/bash
################################################################################
# npm 글로벌 패키지 오프라인 수집 스크립트
#
# 사용법:
#   ./collect_npm_packages.sh
#
# 설명:
#   온라인 환경에서 실행하여 npm 글로벌 패키지들을 tarball로 수집합니다.
#   수집된 패키지는 오프라인 환경에서 install_nodejs.sh로 설치할 수 있습니다.
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
NPM_CACHE_DIR="$SCRIPT_DIR/npm_global_cache"
PACKAGES_LIST="$SCRIPT_DIR/global_packages.txt"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          npm 글로벌 패키지 오프라인 수집                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# npm 확인
if ! command -v npm &>/dev/null; then
    log_error "npm not found. Install Node.js first."
    exit 1
fi

log_info "npm version: $(npm -v)"
log_info "node version: $(node -v)"
echo ""

# 필수 글로벌 패키지 목록 (프론트엔드 빌드에 필요한 것들)
REQUIRED_PACKAGES=(
    "typescript"
    "ts-node"
    "vite"
    "@vitejs/plugin-react"
)

# 현재 글로벌 패키지 목록 저장
log_info "Collecting installed global packages..."
npm list -g --depth=0 --json 2>/dev/null | jq -r '.dependencies | keys[]' > "$PACKAGES_LIST" 2>/dev/null || true

# 필수 패키지 추가
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! grep -qx "$pkg" "$PACKAGES_LIST" 2>/dev/null; then
        echo "$pkg" >> "$PACKAGES_LIST"
    fi
done

# 중복 제거
sort -u "$PACKAGES_LIST" -o "$PACKAGES_LIST"

log_info "Packages to collect:"
cat "$PACKAGES_LIST" | while read pkg; do echo "  - $pkg"; done
echo ""

# npm cache 디렉토리 생성
rm -rf "$NPM_CACHE_DIR"
mkdir -p "$NPM_CACHE_DIR"

# 각 패키지를 tarball로 다운로드
log_info "Downloading packages as tarballs..."
cd "$NPM_CACHE_DIR"

while IFS= read -r package; do
    if [[ -n "$package" ]]; then
        log_info "Downloading: $package"
        npm pack "$package" 2>/dev/null || {
            log_warning "Failed to pack: $package"
        }
    fi
done < "$PACKAGES_LIST"

# 다운로드된 파일 목록
echo ""
log_info "Downloaded packages:"
ls -lh "$NPM_CACHE_DIR"/*.tgz 2>/dev/null | while read line; do
    echo "  $line"
done

# 메타데이터 생성
cat > "$NPM_CACHE_DIR/INSTALL_INFO.txt" << EOF
npm Global Packages Offline Cache
==================================

Collected on: $(date)
Node version: $(node -v)
npm version:  $(npm -v)

Packages included:
$(cat "$PACKAGES_LIST" | sed 's/^/  - /')

Installation:
  1. Run install_nodejs.sh first
  2. Then run: ./install_npm_packages.sh

Manual install:
  npm install -g *.tgz
EOF

log_success "npm packages collected to: $NPM_CACHE_DIR"
echo ""
log_info "Total packages: $(ls "$NPM_CACHE_DIR"/*.tgz 2>/dev/null | wc -l)"
log_info "Total size: $(du -sh "$NPM_CACHE_DIR" | cut -f1)"
