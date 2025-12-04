#!/bin/bash
################################################################################
# 스마트 오프라인 패키지 설치 스크립트
#
# 기능:
#   - Skip 리스트 기반 설치 (apt_skip_list.txt)
#   - 이미 설치된 패키지 자동 건너뛰기
#   - Critical 패키지 보호
#   - 설치 전후 검증
#
# 사용법:
#   bash install_offline_packages_smart.sh [옵션]
#
# 옵션:
#   --deb-dir DIR       .deb 파일이 있는 디렉토리
#   --skip-installed    이미 설치된 패키지 건너뛰기
#   --skip-list FILE    Skip 리스트 파일 (기본: apt_skip_list.txt)
#   --dry-run           실제 설치 없이 계획만 표시
#   --force             경고 무시하고 강제 설치
#
# 작성자: Claude Code
# 날짜: 2025-12-04
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_skip() { echo -e "${CYAN}[SKIP]${NC} $1"; }

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 기본값
DEB_DIR="${SCRIPT_DIR}/offline_packages/apt_packages"
SKIP_INSTALLED=false
SKIP_LIST_FILE=""
DRY_RUN=false
FORCE=false

# Critical 시스템 패키지 (절대 건드리면 안됨)
CRITICAL_PACKAGES=(
    "systemd"
    "init"
    "libc6"
    "libc-bin"
    "base-files"
    "base-passwd"
    "dpkg"
    "apt"
    "coreutils"
    "bash"
    "dash"
    "util-linux"
    "libsystemd0"
    "udev"
    "mount"
    "login"
)

# 통계
declare -i TOTAL_DEBS=0
declare -i SKIPPED_COUNT=0
declare -i INSTALLED_COUNT=0
declare -i FAILED_COUNT=0

# Skip 리스트 로드
declare -A SKIP_MAP

load_skip_list() {
    if [ -n "$SKIP_LIST_FILE" ] && [ -f "$SKIP_LIST_FILE" ]; then
        log_info "Loading skip list: $SKIP_LIST_FILE"

        while IFS= read -r line; do
            # 주석과 빈 줄 건너뛰기
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue

            # Trim
            line=$(echo "$line" | xargs)
            SKIP_MAP["$line"]=1
        done < "$SKIP_LIST_FILE"

        log_success "Loaded ${#SKIP_MAP[@]} packages in skip list"
    fi
}

# 패키지가 설치되어 있는지 확인
is_package_installed() {
    local pkg_name="$1"
    dpkg-query -W -f='${Status}' "$pkg_name" 2>/dev/null | grep -q "install ok installed"
}

# 패키지가 Critical인지 확인
is_critical_package() {
    local pkg_name="$1"
    for critical in "${CRITICAL_PACKAGES[@]}"; do
        if [[ "$pkg_name" == "$critical" ]]; then
            return 0
        fi
    done
    return 1
}

# 패키지가 Skip 리스트에 있는지 확인
is_in_skip_list() {
    local pkg_name="$1"
    [[ -n "${SKIP_MAP[$pkg_name]:-}" ]]
}

# deb 파일에서 패키지 이름 추출
get_package_name_from_deb() {
    local deb_file="$1"
    dpkg-deb -f "$deb_file" Package 2>/dev/null || echo ""
}

# 도움말
show_help() {
    head -n 30 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --deb-dir)
            DEB_DIR="$2"
            shift 2
            ;;
        --skip-installed)
            SKIP_INSTALLED=true
            shift
            ;;
        --skip-list)
            SKIP_LIST_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# 배너
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          스마트 오프라인 APT 패키지 설치                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# deb 디렉토리 확인
if [ ! -d "$DEB_DIR" ]; then
    log_error "Directory not found: $DEB_DIR"
    exit 1
fi

log_info "Using deb directory: $DEB_DIR"

# Skip 리스트 자동 검색
if [ -z "$SKIP_LIST_FILE" ]; then
    # 현재 디렉토리에서 찾기
    if [ -f "apt_skip_list.txt" ]; then
        SKIP_LIST_FILE="apt_skip_list.txt"
    # deb 디렉토리에서 찾기
    elif [ -f "$DEB_DIR/apt_skip_list.txt" ]; then
        SKIP_LIST_FILE="$DEB_DIR/apt_skip_list.txt"
    fi
fi

# Skip 리스트 로드
load_skip_list

# deb 파일 목록
mapfile -t DEB_FILES < <(find "$DEB_DIR" -name "*.deb" | sort)
TOTAL_DEBS=${#DEB_FILES[@]}

if [ $TOTAL_DEBS -eq 0 ]; then
    log_error "No .deb files found in $DEB_DIR"
    exit 1
fi

log_info "Found $TOTAL_DEBS .deb files"
echo ""

# 설치 계획 분석
log_info "Analyzing installation plan..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

declare -a TO_INSTALL=()
declare -a TO_SKIP=()
declare -a CRITICAL_BLOCKED=()

for deb_file in "${DEB_FILES[@]}"; do
    pkg_name=$(get_package_name_from_deb "$deb_file")

    if [ -z "$pkg_name" ]; then
        log_warning "Failed to extract package name: $(basename "$deb_file")"
        continue
    fi

    # Critical 패키지 체크
    if is_critical_package "$pkg_name"; then
        CRITICAL_BLOCKED+=("$pkg_name")
        log_error "CRITICAL: $pkg_name - BLOCKED"
        continue
    fi

    # Skip 리스트 체크
    if is_in_skip_list "$pkg_name"; then
        TO_SKIP+=("$pkg_name")
        log_skip "$pkg_name (in skip list)"
        ((SKIPPED_COUNT++))
        continue
    fi

    # 설치 여부 체크
    if [ "$SKIP_INSTALLED" = true ] && is_package_installed "$pkg_name"; then
        TO_SKIP+=("$pkg_name")
        log_skip "$pkg_name (already installed)"
        ((SKIPPED_COUNT++))
        continue
    fi

    # 설치 대상
    TO_INSTALL+=("$deb_file")
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 통계 출력
log_info "Installation Plan:"
echo "  Total packages:        $TOTAL_DEBS"
echo "  To install:            ${#TO_INSTALL[@]}"
echo "  To skip:               ${#TO_SKIP[@]}"
echo "  Critical blocked:      ${#CRITICAL_BLOCKED[@]}"
echo ""

# Critical 패키지가 있으면 중단
if [ ${#CRITICAL_BLOCKED[@]} -gt 0 ]; then
    log_error "CRITICAL packages detected! Installation aborted."
    echo ""
    echo "다음 패키지들을 오프라인 패키지 디렉토리에서 제거하세요:"
    echo ""
    for pkg in "${CRITICAL_BLOCKED[@]}"; do
        echo "  rm -f $DEB_DIR/${pkg}_*.deb"
    done
    echo ""
    log_error "제거 후 다시 실행하세요."
    exit 1
fi

# Dry-run 모드
if [ "$DRY_RUN" = true ]; then
    log_warning "DRY-RUN mode: No actual installation"
    echo ""
    echo "설치될 패키지 목록:"
    for deb_file in "${TO_INSTALL[@]}"; do
        pkg_name=$(get_package_name_from_deb "$deb_file")
        echo "  - $pkg_name"
    done
    exit 0
fi

# 사용자 확인
if [ "$FORCE" = false ]; then
    echo ""
    read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
fi

# 설치 시작
echo ""
log_info "Starting installation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for deb_file in "${TO_INSTALL[@]}"; do
    pkg_name=$(get_package_name_from_deb "$deb_file")

    echo -n "Installing $pkg_name ... "

    if dpkg -i "$deb_file" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((INSTALLED_COUNT++))
    else
        echo -e "${RED}✗${NC}"
        ((FAILED_COUNT++))

        # 의존성 문제는 나중에 한번에 해결
        log_warning "$pkg_name failed (will fix dependencies later)"
    fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 의존성 해결
if [ $FAILED_COUNT -gt 0 ]; then
    log_info "Fixing package dependencies..."

    if apt-get install -f -y --no-install-recommends > /dev/null 2>&1; then
        log_success "Dependencies fixed"
    else
        log_warning "Some dependencies could not be resolved"
    fi
fi

# 최종 설정
log_info "Configuring packages..."
dpkg --configure -a > /dev/null 2>&1 || true

# 설치 검증
log_info "Verifying installation..."

declare -i VERIFIED_COUNT=0
for deb_file in "${TO_INSTALL[@]}"; do
    pkg_name=$(get_package_name_from_deb "$deb_file")

    if is_package_installed "$pkg_name"; then
        ((VERIFIED_COUNT++))
    fi
done

# 최종 리포트
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          설치 완료                                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_info "Installation Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total packages:           $TOTAL_DEBS"
echo "  Installed:                $INSTALLED_COUNT"
echo "  Verified:                 $VERIFIED_COUNT"
echo "  Skipped:                  $SKIPPED_COUNT"
echo "  Failed:                   $FAILED_COUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $VERIFIED_COUNT -eq $INSTALLED_COUNT ]; then
    log_success "All packages installed successfully!"
    exit 0
else
    log_warning "Some packages failed to install"
    log_info "Check logs for details: /var/log/dpkg.log"
    exit 1
fi
