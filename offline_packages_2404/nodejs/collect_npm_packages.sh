#!/bin/bash
################################################################################
# npm 글로벌 패키지 오프라인 수집 스크립트 (의존성 포함)
#
# 사용법:
#   ./collect_npm_packages.sh
#
# 설명:
#   온라인 환경에서 실행하여 npm 글로벌 패키지들을 의존성 포함하여 수집합니다.
#   수집된 패키지는 오프라인 환경에서 install_nodejs.sh로 설치할 수 있습니다.
#
# 방식:
#   1. 임시 디렉토리에 패키지 설치 (의존성 포함)
#   2. npm registry에서 직접 tarball 다운로드
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
TEMP_DIR="$SCRIPT_DIR/.npm_temp_install"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║    npm 글로벌 패키지 오프라인 수집 (의존성 포함)          ║"
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
# AI 관련 패키지 제외: @google/gemini-cli, claude, etc.
PACKAGES=(
    "typescript"
    "ts-node"
    "vite"
    "@vitejs/plugin-react"
    "terser"
    "cssnano-cli"
    "pnpm"
)

# 제외할 패키지 (AI 관련)
EXCLUDED_PATTERNS=(
    "gemini"
    "claude"
    "openai"
    "anthropic"
    "gpt"
    "llama"
    "ollama"
)

log_info "Packages to collect (excluding AI tools):"
for pkg in "${PACKAGES[@]}"; do
    echo "  - $pkg"
done
echo ""

# 이전 수집 파일 정리
rm -rf "$NPM_CACHE_DIR" "$TEMP_DIR"
mkdir -p "$NPM_CACHE_DIR" "$TEMP_DIR"

# 임시 package.json 생성
log_info "Creating temporary package.json for dependency resolution..."
cd "$TEMP_DIR"

cat > package.json << 'EOF'
{
  "name": "offline-npm-cache",
  "version": "1.0.0",
  "private": true,
  "description": "Temporary package for collecting npm dependencies"
}
EOF

# 각 패키지를 로컬 설치 (의존성 포함, 빌드 스크립트 무시)
log_info "Installing packages locally (with dependencies, ignoring scripts)..."
for package in "${PACKAGES[@]}"; do
    log_info "Installing: $package"
    npm install "$package" --save --ignore-scripts 2>&1 | grep -v "^npm WARN" || {
        log_warning "Failed to install: $package"
    }
done

echo ""
log_info "Collecting all packages from npm registry..."

# node_modules의 모든 패키지 정보 수집
cd "$TEMP_DIR/node_modules"

# 패키지 수집 (scoped 패키지 포함) - npm registry에서 직접 다운로드
collect_package() {
    local pkg_name="$1"
    local pkg_version="$2"

    # 제외 패턴 확인
    for pattern in "${EXCLUDED_PATTERNS[@]}"; do
        if echo "$pkg_name" | grep -qi "$pattern"; then
            return 0
        fi
    done

    # 파일명 생성 (scoped 패키지는 @를 제거)
    local safe_name="${pkg_name#@}"
    safe_name="${safe_name//\//-}"
    local filename="${safe_name}-${pkg_version}.tgz"

    # 이미 다운로드되어 있으면 스킵
    if [[ -f "$NPM_CACHE_DIR/$filename" ]]; then
        return 0
    fi

    # npm registry에서 다운로드
    local tarball_url=$(npm view "${pkg_name}@${pkg_version}" dist.tarball 2>/dev/null)
    if [[ -n "$tarball_url" ]]; then
        curl -sL "$tarball_url" -o "$NPM_CACHE_DIR/$filename" 2>/dev/null && \
            echo "  Downloaded: $pkg_name@$pkg_version"
    fi
}

export -f collect_package
export NPM_CACHE_DIR
export EXCLUDED_PATTERNS

# 모든 패키지 정보 수집 (일반 패키지)
find . -maxdepth 1 -mindepth 1 -type d ! -name '@*' ! -name '.bin' | while read pkg_dir; do
    pkg_json="$pkg_dir/package.json"
    [[ -f "$pkg_json" ]] || continue

    pkg_name=$(jq -r '.name // empty' "$pkg_json" 2>/dev/null)
    pkg_version=$(jq -r '.version // empty' "$pkg_json" 2>/dev/null)

    if [[ -z "$pkg_name" ]] || [[ -z "$pkg_version" ]]; then
        continue
    fi

    # 제외 패턴 확인
    skip=false
    for pattern in "${EXCLUDED_PATTERNS[@]}"; do
        if echo "$pkg_name" | grep -qi "$pattern"; then
            skip=true
            break
        fi
    done
    [[ "$skip" == "true" ]] && continue

    # 파일명 생성
    filename="${pkg_name}-${pkg_version}.tgz"

    # 이미 다운로드되어 있으면 스킵
    [[ -f "$NPM_CACHE_DIR/$filename" ]] && continue

    # npm registry에서 다운로드
    tarball_url=$(npm view "${pkg_name}@${pkg_version}" dist.tarball 2>/dev/null)
    if [[ -n "$tarball_url" ]]; then
        if curl -sL "$tarball_url" -o "$NPM_CACHE_DIR/$filename" 2>/dev/null; then
            echo "  Downloaded: $pkg_name@$pkg_version"
        fi
    fi
done

# Scoped 패키지 수집 (@로 시작하는 패키지)
find . -maxdepth 1 -mindepth 1 -type d -name '@*' | while read scope_dir; do
    find "$scope_dir" -maxdepth 1 -mindepth 1 -type d | while read pkg_dir; do
        pkg_json="$pkg_dir/package.json"
        [[ -f "$pkg_json" ]] || continue

        pkg_name=$(jq -r '.name // empty' "$pkg_json" 2>/dev/null)
        pkg_version=$(jq -r '.version // empty' "$pkg_json" 2>/dev/null)

        if [[ -z "$pkg_name" ]] || [[ -z "$pkg_version" ]]; then
            continue
        fi

        # 제외 패턴 확인
        skip=false
        for pattern in "${EXCLUDED_PATTERNS[@]}"; do
            if echo "$pkg_name" | grep -qi "$pattern"; then
                skip=true
                break
            fi
        done
        [[ "$skip" == "true" ]] && continue

        # 파일명 생성 (scoped 패키지: @scope/name -> scope-name-version.tgz)
        safe_name="${pkg_name#@}"
        safe_name="${safe_name//\//-}"
        filename="${safe_name}-${pkg_version}.tgz"

        # 이미 다운로드되어 있으면 스킵
        [[ -f "$NPM_CACHE_DIR/$filename" ]] && continue

        # npm registry에서 다운로드
        tarball_url=$(npm view "${pkg_name}@${pkg_version}" dist.tarball 2>/dev/null)
        if [[ -n "$tarball_url" ]]; then
            if curl -sL "$tarball_url" -o "$NPM_CACHE_DIR/$filename" 2>/dev/null; then
                echo "  Downloaded: $pkg_name@$pkg_version"
            fi
        fi
    done
done

# 다운로드된 파일 수 확인
pkg_count=$(ls "$NPM_CACHE_DIR"/*.tgz 2>/dev/null | wc -l)

echo ""
log_info "Collected $pkg_count packages"

# 파일 목록 (크기순 정렬)
echo ""
log_info "Collected packages (by size):"
ls -lhS "$NPM_CACHE_DIR"/*.tgz 2>/dev/null | head -20 | while read line; do
    echo "  $line"
done
if [[ $pkg_count -gt 20 ]]; then
    echo "  ... and $((pkg_count - 20)) more packages"
fi

# 패키지 목록 저장
ls "$NPM_CACHE_DIR"/*.tgz 2>/dev/null | xargs -n1 basename | sed 's/-[0-9].*\.tgz$//' | sort -u > "$NPM_CACHE_DIR/package_list.txt"

# 메타데이터 생성
cat > "$NPM_CACHE_DIR/INSTALL_INFO.txt" << EOF
npm Global Packages Offline Cache (with dependencies)
======================================================

Collected on: $(date)
Node version: $(node -v)
npm version:  $(npm -v)

Top-level packages:
$(printf '  - %s\n' "${PACKAGES[@]}")

Total packages (including dependencies): $pkg_count
Total size: $(du -sh "$NPM_CACHE_DIR" | cut -f1)

Excluded patterns (AI-related):
$(printf '  - %s\n' "${EXCLUDED_PATTERNS[@]}")

Installation:
  1. Run install_nodejs.sh first
  2. Global packages will be auto-installed from this cache

Manual install (if needed):
  cd npm_global_cache
  npm install -g typescript-*.tgz vite-*.tgz ts-node-*.tgz

Note: Dependencies are included, so offline installation should work.
EOF

# 정리
cd "$SCRIPT_DIR"
rm -rf "$TEMP_DIR"

echo ""
log_success "npm packages collected to: $NPM_CACHE_DIR"
echo ""
log_info "Total packages: $pkg_count"
log_info "Total size: $(du -sh "$NPM_CACHE_DIR" | cut -f1)"
echo ""
log_info "To test installation:"
echo "  npm install -g $NPM_CACHE_DIR/typescript-*.tgz"
