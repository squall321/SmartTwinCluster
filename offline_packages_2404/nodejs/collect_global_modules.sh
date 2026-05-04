#!/bin/bash
################################################################################
# npm 글로벌 모듈 수집 스크립트 (100% 오프라인 보장)
#
# 사용법:
#   ./collect_global_modules.sh
#
# 설명:
#   온라인 환경에서 npm 글로벌 패키지를 설치하고,
#   전체 글로벌 node_modules를 압축하여 오프라인 배포용으로 준비합니다.
#
#   이 방식은 의존성 문제 없이 100% 오프라인 설치를 보장합니다.
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
OUTPUT_DIR="$SCRIPT_DIR/npm_global_bundle"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║    npm 글로벌 모듈 수집 (100% 오프라인 보장)              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# npm/node 확인
if ! command -v npm &>/dev/null; then
    log_error "npm not found. Install Node.js first."
    exit 1
fi

log_info "npm version: $(npm -v)"
log_info "node version: $(node -v)"
echo ""

# 설치할 글로벌 패키지 목록
GLOBAL_PACKAGES=(
    "typescript"
    "ts-node"
    "pnpm"
    "terser"
    "vite"
)

log_info "Packages to install globally:"
for pkg in "${GLOBAL_PACKAGES[@]}"; do
    echo "  - $pkg"
done
echo ""

# 기존 글로벌 패키지 백업 (선택적)
NPM_GLOBAL_PREFIX=$(npm config get prefix)
log_info "npm global prefix: $NPM_GLOBAL_PREFIX"

# 임시 디렉토리에 새 글로벌 환경 구성
TEMP_NPM_PREFIX="$SCRIPT_DIR/.npm_global_temp"
rm -rf "$TEMP_NPM_PREFIX"
mkdir -p "$TEMP_NPM_PREFIX/lib/node_modules"
mkdir -p "$TEMP_NPM_PREFIX/bin"

log_info "Creating isolated global environment in: $TEMP_NPM_PREFIX"

# 임시 환경에 패키지 설치
export PATH="$TEMP_NPM_PREFIX/bin:$PATH"
export npm_config_prefix="$TEMP_NPM_PREFIX"

echo ""
log_info "Installing packages to isolated environment..."

for pkg in "${GLOBAL_PACKAGES[@]}"; do
    log_info "Installing: $pkg"
    npm install -g "$pkg" 2>&1 | grep -E "^(added|npm ERR)" || true
done

echo ""
log_info "Installed packages:"
npm list -g --depth=0 2>/dev/null || true

# 출력 디렉토리 준비
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# node_modules와 bin 복사
log_info "Copying global modules..."
cp -r "$TEMP_NPM_PREFIX/lib/node_modules" "$OUTPUT_DIR/"
cp -r "$TEMP_NPM_PREFIX/bin" "$OUTPUT_DIR/"

# 심볼릭 링크 정리 (bin 폴더의 링크들을 상대 경로로 수정)
log_info "Fixing symlinks for portability..."
cd "$OUTPUT_DIR/bin"
for link in *; do
    if [[ -L "$link" ]]; then
        target=$(readlink "$link")
        # 절대 경로를 상대 경로로 변환
        if [[ "$target" == /* ]]; then
            # node_modules 내 경로 추출
            rel_target=$(echo "$target" | sed "s|$TEMP_NPM_PREFIX/lib/||")
            rm "$link"
            ln -s "../node_modules/${rel_target#node_modules/}" "$link" 2>/dev/null || \
            ln -s "../$rel_target" "$link" 2>/dev/null || true
        fi
    fi
done
cd "$SCRIPT_DIR"

# 메타데이터 생성
cat > "$OUTPUT_DIR/INSTALL_INFO.txt" << EOF
npm Global Modules Bundle (100% Offline)
=========================================

Collected on: $(date)
Node version: $(node -v)
npm version:  $(npm -v)

Installed packages:
$(printf '  - %s\n' "${GLOBAL_PACKAGES[@]}")

Total size: $(du -sh "$OUTPUT_DIR" | cut -f1)

Installation:
  1. Run install_nodejs.sh (installs Node.js)
  2. Global packages are auto-restored from this bundle

Manual restoration:
  sudo cp -r node_modules/* /usr/lib/node_modules/
  sudo cp -r bin/* /usr/bin/

Note: This bundle contains complete node_modules with all dependencies.
      No internet connection required for installation.
EOF

# 압축 생성
log_info "Creating archive..."
cd "$SCRIPT_DIR"
tar -czf npm_global_bundle.tar.gz -C "$OUTPUT_DIR" .

# 정리
rm -rf "$TEMP_NPM_PREFIX"

# 결과 출력
echo ""
log_success "Global modules bundle created!"
echo ""
log_info "Output files:"
echo "  Directory: $OUTPUT_DIR"
echo "  Archive:   $SCRIPT_DIR/npm_global_bundle.tar.gz"
echo ""
log_info "Archive size: $(du -h "$SCRIPT_DIR/npm_global_bundle.tar.gz" | cut -f1)"
log_info "Directory size: $(du -sh "$OUTPUT_DIR" | cut -f1)"
echo ""
log_info "Contents:"
ls -la "$OUTPUT_DIR/"
echo ""
log_info "Installed commands:"
ls "$OUTPUT_DIR/bin/" 2>/dev/null | head -20
echo ""
log_success "Done! Use install_nodejs.sh to install on offline nodes."
