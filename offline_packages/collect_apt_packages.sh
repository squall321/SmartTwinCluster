#!/bin/bash
################################################################################
# APT 패키지 수집 스크립트
#
# 설명:
#   오프라인 설치를 위해 필요한 모든 APT 패키지와 의존성을 다운로드합니다.
#   외부 저장소(PPA, NodeSource)도 자동으로 설정하여 최신 패키지를 수집합니다.
#
# 기능:
#   - 멀티헤드 클러스터 서비스에 필요한 모든 패키지 수집
#   - 의존성 자동 해결 및 다운로드
#   - 외부 저장소 자동 설정 (Apptainer PPA, Python 3.12, Node.js LTS)
#   - .deb 파일 패키징
#
# 사용법:
#   sudo ./collect_apt_packages.sh [OPTIONS]
#
# 옵션:
#   --output-dir PATH      출력 디렉토리 (기본: ./apt_packages)
#   --service SERVICE      특정 서비스만 수집 (all|slurm|glusterfs|mariadb|redis|web|hpc)
#   --no-external-repos    외부 저장소 설정 건너뛰기 (Apptainer, Python 3.12 등)
#   --dry-run              실제 다운로드 없이 목록만 표시
#   --help                 도움말 표시
#
# 외부 저장소:
#   - Apptainer PPA (ppa:apptainer/ppa)
#   - Python 3.12 (ppa:deadsnakes/ppa)
#   - Node.js 20.x LTS (NodeSource)
#
# 작성자: Claude Code
# 날짜: 2025-11-17
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 기본값
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/apt_packages"
SERVICE="all"
DRY_RUN=false
SETUP_EXTERNAL_REPOS=true  # 외부 저장소 (Apptainer, Python 3.12, Node.js) 설정

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 도움말
show_help() {
    head -n 25 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# 인자 파싱
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --service)
                SERVICE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-external-repos)
                SETUP_EXTERNAL_REPOS=false
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
}

# Root 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# 패키지 목록 정의
define_package_lists() {
    # 기본 시스템 패키지
    SYSTEM_PACKAGES=(
        build-essential
        gcc
        g++
        make
        cmake
        git
        wget
        curl
        rsync
        vim
        net-tools
        iputils-ping
        openssh-server
        python3
        python3-pip
        python3-venv
        python3-dev
        python3-yaml
        jq
        sshpass
        chrony
        pkg-config
        software-properties-common
    )

    # Slurm 빌드 의존성
    SLURM_BUILD_DEPS=(
        bzip2
        munge
        libmunge-dev
        libmunge2
        libpam0g-dev
        libreadline-dev
        libssl-dev
        libnuma-dev
        libhwloc-dev
        libdbus-1-dev
        libsystemd-dev
    )

    # Slurm 런타임 패키지 (apt로 설치하는 경우)
    SLURM_RUNTIME_PACKAGES=(
        slurm-wlm
        slurmctld
        slurmd
        slurmdbd
    )

    # GlusterFS 패키지
    GLUSTERFS_PACKAGES=(
        glusterfs-server
        glusterfs-client
        glusterfs-common
        attr
    )

    # MariaDB Galera 패키지
    MARIADB_PACKAGES=(
        mariadb-server
        mariadb-client
        mariadb-backup
        galera-4
        rsync
        socat
        pv
        libmariadb-dev
        libmariadb-dev-compat
    )

    # Redis 패키지
    REDIS_PACKAGES=(
        redis-server
        redis-tools
        redis-sentinel
    )

    # Keepalived 패키지
    KEEPALIVED_PACKAGES=(
        keepalived
        ipvsadm
    )

    # 웹 서비스 패키지
    WEB_PACKAGES=(
        nginx
        nodejs
        npm
        certbot
        python3-certbot-nginx
    )

    # Python 패키지 (시스템)
    PYTHON_PACKAGES=(
        python3-pymysql
        python3-redis
        python3-requests
        python3-flask
        python3-jwt
    )

    # HPC 패키지 (MPI, 컨테이너)
    HPC_PACKAGES=(
        # OpenMPI
        openmpi-bin
        libopenmpi-dev
        openmpi-common
        # MPICH (대안)
        mpich
        libmpich-dev
        # Apptainer (Singularity) - PPA 필요
        # apptainer
    )
}

# 패키지 선택
select_packages() {
    local packages=()

    case "$SERVICE" in
        all)
            packages+=(
                "${SYSTEM_PACKAGES[@]}"
                "${SLURM_BUILD_DEPS[@]}"
                "${GLUSTERFS_PACKAGES[@]}"
                "${MARIADB_PACKAGES[@]}"
                "${REDIS_PACKAGES[@]}"
                "${KEEPALIVED_PACKAGES[@]}"
                "${WEB_PACKAGES[@]}"
                "${PYTHON_PACKAGES[@]}"
                "${HPC_PACKAGES[@]}"
            )
            ;;
        hpc)
            packages+=(
                "${HPC_PACKAGES[@]}"
            )
            ;;
        slurm)
            packages+=(
                "${SYSTEM_PACKAGES[@]}"
                "${SLURM_BUILD_DEPS[@]}"
            )
            ;;
        glusterfs)
            packages+=("${GLUSTERFS_PACKAGES[@]}")
            ;;
        mariadb)
            packages+=("${MARIADB_PACKAGES[@]}")
            ;;
        redis)
            packages+=("${REDIS_PACKAGES[@]}")
            ;;
        keepalived)
            packages+=("${KEEPALIVED_PACKAGES[@]}")
            ;;
        web)
            packages+=(
                "${WEB_PACKAGES[@]}"
                "${PYTHON_PACKAGES[@]}"
            )
            ;;
        *)
            log_error "Unknown service: $SERVICE"
            log_info "Valid services: all, slurm, glusterfs, mariadb, redis, keepalived, web, hpc"
            exit 1
            ;;
    esac

    # 중복 제거
    SELECTED_PACKAGES=($(printf '%s\n' "${packages[@]}" | sort -u))
}

# 외부 저장소 설정 (PPA, NodeSource 등)
setup_external_repositories() {
    log_info "Setting up external repositories for additional packages..."

    # 1. Apptainer PPA
    log_info "  Adding Apptainer PPA..."
    if ! grep -q "apptainer" /etc/apt/sources.list.d/* 2>/dev/null; then
        add-apt-repository -y ppa:apptainer/ppa 2>/dev/null || {
            log_warning "  Failed to add Apptainer PPA (may not be available)"
        }
    else
        log_info "  Apptainer PPA already configured"
    fi

    # 2. Python 3.12 (deadsnakes PPA)
    log_info "  Adding Python deadsnakes PPA..."
    if ! grep -q "deadsnakes" /etc/apt/sources.list.d/* 2>/dev/null; then
        add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || {
            log_warning "  Failed to add deadsnakes PPA"
        }
    else
        log_info "  deadsnakes PPA already configured"
    fi

    # 3. Node.js (NodeSource)
    log_info "  Adding NodeSource repository (Node.js LTS)..."
    if ! grep -q "nodesource" /etc/apt/sources.list.d/* 2>/dev/null; then
        # Node.js 20.x LTS
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null || {
            log_warning "  Failed to add NodeSource repository"
        }
    else
        log_info "  NodeSource repository already configured"
    fi

    log_success "External repositories configured"
}

# 외부 저장소 패키지 목록 추가
add_external_packages() {
    log_info "Adding packages from external repositories..."

    # Apptainer
    if apt-cache show apptainer &>/dev/null; then
        SELECTED_PACKAGES+=("apptainer")
        log_success "  Added: apptainer"
    fi

    # Python 3.12
    if apt-cache show python3.12 &>/dev/null; then
        SELECTED_PACKAGES+=(
            "python3.12"
            "python3.12-venv"
            "python3.12-dev"
            "python3.12-distutils"
        )
        log_success "  Added: python3.12, python3.12-venv, python3.12-dev"
    fi

    # Node.js (최신 LTS)
    if apt-cache show nodejs &>/dev/null; then
        # NodeSource 버전은 npm 포함
        log_info "  nodejs already in package list"
    fi

    log_success "External packages added to collection list"
}

# APT 캐시 업데이트
update_apt_cache() {
    log_info "Updating APT cache..."
    apt-get update
    log_success "APT cache updated"
}

# 패키지 다운로드
download_packages() {
    log_info "Downloading ${#SELECTED_PACKAGES[@]} packages and their dependencies..."

    mkdir -p "$OUTPUT_DIR"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN mode: not actually downloading"
        log_info "Would download the following packages:"
        printf '  - %s\n' "${SELECTED_PACKAGES[@]}"
        return 0
    fi

    # apt-get download with dependencies
    cd "$OUTPUT_DIR"

    # 방법 1: apt-get download (의존성 자동 해결)
    log_info "Method 1: Using apt-get download..."

    local failed_packages=()

    for package in "${SELECTED_PACKAGES[@]}"; do
        log_info "  Downloading: $package"

        if apt-get download "$package" 2>/dev/null; then
            log_success "    ✓ $package"
        else
            log_warning "    ✗ $package (not available)"
            failed_packages+=("$package")
        fi
    done

    # 의존성 다운로드
    log_info "Downloading dependencies using apt-rdepends..."

    if ! command -v apt-rdepends &> /dev/null; then
        log_info "Installing apt-rdepends..."
        apt-get install -y apt-rdepends
    fi

    for package in "${SELECTED_PACKAGES[@]}"; do
        # Skip failed packages
        if [[ " ${failed_packages[@]} " =~ " ${package} " ]]; then
            continue
        fi

        log_info "  Resolving dependencies for: $package"

        # Get all dependencies
        local deps=$(apt-rdepends "$package" 2>/dev/null | grep -v "^ " | grep -v "^$package$" || true)

        for dep in $deps; do
            if [[ ! -f "${dep}_"*.deb ]]; then
                apt-get download "$dep" 2>/dev/null || true
            fi
        done
    done

    cd - > /dev/null

    # 통계
    local total_debs=$(find "$OUTPUT_DIR" -name "*.deb" | wc -l)
    local total_size=$(du -sh "$OUTPUT_DIR" | cut -f1)

    log_success "Downloaded packages: $total_debs"
    log_info "Total size: $total_size"

    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_warning "Failed to download ${#failed_packages[@]} packages:"
        printf '  - %s\n' "${failed_packages[@]}"
    fi
}

# 패키지 목록 파일 생성
create_package_list() {
    log_info "Creating package list file..."

    local list_file="${OUTPUT_DIR}/package_list.txt"

    find "$OUTPUT_DIR" -name "*.deb" -exec basename {} \; | sort > "$list_file"

    log_success "Package list created: $list_file"
}

# 설치 스크립트 생성
create_install_script() {
    log_info "Creating installation script..."

    local install_script="${OUTPUT_DIR}/install_offline_packages.sh"

    cat > "$install_script" << 'EOF'
#!/bin/bash
################################################################################
# 오프라인 패키지 설치 스크립트 (계산 노드에서 실행)
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing packages from: $SCRIPT_DIR"

# .deb 파일 개수 확인
DEB_COUNT=$(find "$SCRIPT_DIR" -name "*.deb" | wc -l)
echo "Found $DEB_COUNT .deb files"

if [[ $DEB_COUNT -eq 0 ]]; then
    echo "ERROR: No .deb files found in $SCRIPT_DIR"
    exit 1
fi

# 순서 중요: 의존성 문제 해결을 위해 여러 번 시도
echo ""
echo "Step 1: Installing packages (may show dependency errors - this is normal)"
sudo dpkg -i "$SCRIPT_DIR"/*.deb 2>&1 | tee /tmp/dpkg_install.log || true

echo ""
echo "Step 2: Fixing dependencies"
sudo apt-get install -f -y --no-install-recommends

echo ""
echo "Step 3: Retry installation"
sudo dpkg -i "$SCRIPT_DIR"/*.deb

echo ""
echo "Step 4: Final dependency check"
sudo apt-get install -f -y

echo ""
echo "✅ Offline package installation complete!"
echo ""
echo "Installed packages:"
dpkg -l | grep "^ii" | wc -l
EOF

    chmod +x "$install_script"

    log_success "Installation script created: $install_script"
}

# tarball 생성
create_tarball() {
    log_info "Creating tarball..."

    local tarball_name="apt-packages-$(date +%Y%m%d).tar.gz"
    local tarball_path="${SCRIPT_DIR}/${tarball_name}"

    cd "$(dirname "$OUTPUT_DIR")"
    tar -czf "$tarball_path" "$(basename "$OUTPUT_DIR")"
    cd - > /dev/null

    local tarball_size=$(du -sh "$tarball_path" | cut -f1)

    log_success "Tarball created: $tarball_path ($tarball_size)"
}

# MD5 체크섬 생성
create_checksums() {
    log_info "Creating checksums..."

    local checksum_file="${OUTPUT_DIR}/checksums.md5"

    cd "$OUTPUT_DIR"
    find . -name "*.deb" -exec md5sum {} \; > "$checksum_file"
    cd - > /dev/null

    log_success "Checksums created: $checksum_file"
}

# 요약 정보
print_summary() {
    local total_debs=$(find "$OUTPUT_DIR" -name "*.deb" 2>/dev/null | wc -l)
    local total_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          APT 패키지 수집 완료!                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Collection Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Service:         $SERVICE"
    echo "  Output:          $OUTPUT_DIR"
    echo "  Packages:        $total_debs .deb files"
    echo "  Total Size:      $total_size"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Next Steps:"
    echo "  1. Copy to offline environment:"
    echo "     rsync -avz $OUTPUT_DIR user@offline-node:/tmp/"
    echo ""
    echo "  2. Install on offline node:"
    echo "     cd /tmp/$(basename $OUTPUT_DIR)"
    echo "     sudo bash install_offline_packages.sh"
    echo ""
    echo "  3. Or use tarball:"
    echo "     tar -xzf apt-packages-*.tar.gz"
    echo "     cd apt_packages"
    echo "     sudo bash install_offline_packages.sh"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          APT 패키지 수집 스크립트                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    define_package_lists
    select_packages

    log_info "Service: $SERVICE"
    log_info "Output: $OUTPUT_DIR"
    log_info "Packages to collect: ${#SELECTED_PACKAGES[@]}"
    echo ""

    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Continue with package collection? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi

    # 외부 저장소 설정 (Apptainer, Python 3.12, Node.js LTS)
    if [[ "$SETUP_EXTERNAL_REPOS" == "true" ]]; then
        setup_external_repositories
        update_apt_cache
        # 외부 저장소 패키지 추가
        add_external_packages
    else
        log_info "Skipping external repository setup (--no-external-repos)"
        update_apt_cache
    fi

    download_packages
    create_package_list
    create_install_script
    create_checksums
    create_tarball
    print_summary

    log_success "Package collection complete!"
}

main "$@"
