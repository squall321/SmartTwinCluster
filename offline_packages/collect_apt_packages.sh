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
        dpkg-dev              # 로컬 APT 저장소 생성에 필요 (dpkg-scanpackages)
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
        autofs
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
    # Note: npm is not included because NodeSource Node.js already includes npm
    WEB_PACKAGES=(
        nginx
        nodejs
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
    # Note: python3.12-distutils is removed in Python 3.12, use setuptools instead
    if apt-cache show python3.12 &>/dev/null; then
        SELECTED_PACKAGES+=(
            "python3.12"
            "python3.12-venv"
            "python3.12-dev"
        )
        log_success "  Added: python3.12, python3.12-venv, python3.12-dev"
    fi

    # Add setuptools for Python 3.12 (replaces distutils)
    if apt-cache show python3-setuptools &>/dev/null; then
        SELECTED_PACKAGES+=("python3-setuptools")
        log_success "  Added: python3-setuptools (replaces distutils)"
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

# 로컬 APT 저장소 인덱스 생성
create_local_repo_index() {
    log_info "Creating local APT repository index (Packages.gz)..."

    cd "$OUTPUT_DIR"

    # dpkg-scanpackages로 Packages 파일 생성
    if command -v dpkg-scanpackages &> /dev/null; then
        dpkg-scanpackages . /dev/null > Packages
        gzip -k -f Packages
        log_success "  Created: Packages, Packages.gz"
    else
        log_warning "dpkg-scanpackages not found, installing dpkg-dev..."
        apt-get install -y dpkg-dev
        dpkg-scanpackages . /dev/null > Packages
        gzip -k -f Packages
        log_success "  Created: Packages, Packages.gz"
    fi

    # Release 파일 생성 (선택사항이지만 일부 apt 버전에서 필요)
    cat > Release << RELEASE_EOF
Origin: Offline-Local
Label: Offline-Local
Suite: stable
Codename: offline
Architectures: amd64
Components: main
Description: Local offline APT repository
RELEASE_EOF

    log_success "  Created: Release"

    cd - > /dev/null
}

# 설치 스크립트 생성 (로컬 APT 저장소 방식)
create_install_script() {
    log_info "Creating installation script (local APT repository method)..."

    local install_script="${OUTPUT_DIR}/install_offline_packages.sh"

    cat > "$install_script" << 'EOF'
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
    create_local_repo_index    # APT 저장소 인덱스 생성 (Packages.gz)
    create_install_script      # 로컬 APT 저장소 방식 설치 스크립트
    create_checksums
    create_tarball
    print_summary

    log_success "Package collection complete!"
}

main "$@"
