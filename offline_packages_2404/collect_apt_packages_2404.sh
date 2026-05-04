#!/bin/bash
################################################################################
# APT Package Collection Script for Ubuntu 24.04 (Noble Numbat)
#
# Description:
#   Downloads all required APT packages and their dependencies for offline
#   installation on Ubuntu 24.04 (noble) systems.
#   Automatically configures external repositories (PPA, NodeSource) to
#   collect the latest packages.
#
# Target OS: Ubuntu 24.04 LTS (Noble Numbat)
#
# Key differences from 22.04 (jammy) version:
#   - Python 3.12 is the system default; no deadsnakes PPA needed for 3.12
#   - python3.12-venv, python3.12-dev available as system packages
#   - deadsnakes PPA used only for Python 3.13
#   - No python3.10 references (removed entirely)
#   - Apptainer PPA supports noble (ppa:apptainer/ppa)
#   - Node.js 20.x LTS via NodeSource
#
# Features:
#   - Collects all packages needed for multi-head cluster services
#   - Automatic dependency resolution and download
#   - External repository auto-setup (Apptainer PPA, Python 3.13, Node.js LTS)
#   - .deb file packaging with local APT repository index
#
# Usage:
#   sudo ./collect_apt_packages_2404.sh [OPTIONS]
#
# Options:
#   --output-dir PATH      Output directory (default: ./apt_packages)
#   --service SERVICE      Collect specific service only
#                          (all|slurm|glusterfs|mariadb|redis|web|hpc)
#   --no-external-repos    Skip external repository setup (Apptainer, Python 3.13, etc.)
#   --dry-run              Show package list without downloading
#   --help                 Show help
#
# External Repositories:
#   - Apptainer PPA (ppa:apptainer/ppa) - noble compatible
#   - Python 3.13 (ppa:deadsnakes/ppa) - for Python 3.13 only
#   - Node.js 20.x LTS (NodeSource)
#
# Author: Claude Code
# Date: 2026-03-06
################################################################################

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/apt_packages"
SERVICE="all"
DRY_RUN=false
SKIP_CONFIRM=false
SETUP_EXTERNAL_REPOS=true  # External repos (Apptainer, Python 3.13, Node.js)

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Help
show_help() {
    head -n 40 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# Argument parsing
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
            --yes|-y|--skip-confirm)
                SKIP_CONFIRM=true
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

# Root privilege check
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Verify we are running on Ubuntu 24.04
check_os_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${VERSION_ID:-}" != "24.04" ]]; then
            log_warning "This script is designed for Ubuntu 24.04 (noble)"
            log_warning "Detected: ${PRETTY_NAME:-unknown}"
            if [[ "$SKIP_CONFIRM" == "false" ]]; then
                read -p "Continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Cancelled by user"
                    exit 0
                fi
            fi
        else
            log_success "Detected Ubuntu 24.04 (noble) - OK"
        fi
    else
        log_warning "Cannot detect OS version (/etc/os-release not found)"
    fi
}

# Package list definitions
define_package_lists() {
    # Base system packages
    # Note: On 24.04, python3 is Python 3.12 by default
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
        python3.12-venv         # System Python 3.12 venv (native on 24.04)
        python3.12-dev          # System Python 3.12 dev headers (native on 24.04)
        jq
        sshpass
        chrony
        pkg-config
        software-properties-common
        dpkg-dev                # Required for local APT repo creation (dpkg-scanpackages)
    )

    # Slurm build dependencies
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

    # Slurm runtime packages - not used (source build 23.x only)
    # apt packages for Slurm 21.x are not supported.
    # Use offline_packages/slurm/build_slurm_package.sh instead.
    SLURM_RUNTIME_PACKAGES=(
        # slurm-wlm     # Removed - use source build
        # slurmctld     # Removed - use source build
        # slurmd        # Removed - use source build
        # slurmdbd      # Removed - use source build
    )

    # GlusterFS packages
    GLUSTERFS_PACKAGES=(
        glusterfs-server
        glusterfs-client
        glusterfs-common
        attr
        autofs
    )

    # MariaDB Galera packages
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

    # Redis packages
    REDIS_PACKAGES=(
        redis-server
        redis-tools
        redis-sentinel
    )

    # Keepalived packages
    KEEPALIVED_PACKAGES=(
        keepalived
        ipvsadm
    )

    # Web service packages
    # Note: npm is not included because NodeSource Node.js already includes npm
    WEB_PACKAGES=(
        nginx
        nodejs
        certbot
        python3-certbot-nginx
    )

    # Python packages (system apt packages)
    PYTHON_PACKAGES=(
        python3-pymysql
        python3-redis
        python3-requests
        python3-flask
        python3-jwt
    )

    # Python package build dependencies (for C extensions like xmlsec, lxml)
    PYTHON_BUILD_DEPS=(
        libxml2-dev
        libxmlsec1-dev
        libxmlsec1t64-openssl     # 24.04 명명 (22.04: libxmlsec1-openssl)
        libxslt1-dev
        pkg-config
    )

    # HPC packages (MPI, containers)
    HPC_PACKAGES=(
        # OpenMPI
        openmpi-bin
        libopenmpi-dev
        openmpi-common
        # MPICH (alternative)
        mpich
        libmpich-dev
        # PMIx (필수 - Slurm --with-pmix 빌드용)
        libpmix-dev
        libpmix2t64
        # Apptainer 의존성 (PPA에서 apptainer 본체 + 아래 의존성)
        squashfuse
        fuse-overlayfs
        crun
        uidmap
        squashfs-tools
        # Apptainer (Singularity) - added via PPA in add_external_packages()
        # apptainer
    )

    # NFS (공유 파일시스템 - /home, /scratch 마운트용)
    NFS_PACKAGES=(
        nfs-kernel-server
        nfs-common
        rpcbind
        autofs
    )

    # Monitoring (Prometheus, Node Exporter, Grafana)
    MONITORING_PACKAGES=(
        prometheus
        prometheus-node-exporter
        prometheus-alertmanager
        prometheus-mysqld-exporter
        # Grafana은 별도 .deb 다운로드 (apt에 없음)
    )

    # VNC 서버 + noVNC (대시보드 VNC 세션용)
    VNC_PACKAGES=(
        tigervnc-standalone-server
        tigervnc-common
        tigervnc-tools
        novnc
        websockify
        xvfb
        xauth
        x11-xkb-utils
        xfonts-base
        xkb-data
        dbus-x11
    )

    # Ubuntu Desktop (전체) — VNC 컨테이너 빌드 + 헤드노드 그래픽 환경
    UBUNTU_DESKTOP_PACKAGES=(
        ubuntu-desktop-minimal
        gdm3
        gnome-session
        gnome-terminal
        gnome-shell
        gnome-control-center
        gnome-system-monitor
        nautilus
        # X11 코어
        xorg
        xserver-xorg
        xserver-xorg-core
        xserver-xorg-input-all
        xserver-xorg-video-all
        # 글꼴/테마
        fonts-noto
        fonts-noto-cjk
        fonts-liberation
    )

    # XFCE4 데스크톱 (경량 — Apptainer SIF 빌드용)
    XFCE4_PACKAGES=(
        xfce4
        xfce4-goodies
        xfce4-terminal
        xfce4-panel
        xfce4-session
        xfwm4
        xfdesktop4
        xfce4-screensaver
    )

    # 시스템 운영 도구 (관리/디버깅에 필요)
    SYSTEM_TOOLS_PACKAGES=(
        htop
        iotop
        iftop
        tmux
        screen
        byobu
        tree
        ncdu
        nmon
        atop
        sysstat
        lsof
        strace
        psmisc
        unzip
        zip
        p7zip-full
        bash-completion
    )

    # 네트워크 도구
    NETWORK_TOOLS_PACKAGES=(
        nmap
        tcpdump
        traceroute
        dnsutils
        iproute2
        net-tools
        ethtool
        bridge-utils
        ipset
        iptables
        ufw
    )

    # 추가 빌드 의존성 (소스 빌드 시 필요)
    EXTRA_BUILD_DEPS=(
        autoconf
        automake
        libtool
        bison
        flex
        gettext
        m4
        gawk
        # 추가 라이브러리 (Slurm + 기타)
        libffi-dev
        zlib1g-dev
        liblz4-dev
        libzstd-dev
        libnl-3-dev
        libnl-route-3-dev
        libcurl4-openssl-dev
        libjson-c-dev
        libyaml-dev
        # XML/Crypto (python3-saml 빌드용)
        libxmlsec1-dev
        libxml2-utils
    )

    # 미디어/스트리밍 라이브러리 (Sunshine, FFmpeg)
    MEDIA_PACKAGES=(
        # FFmpeg 6 (24.04 기본)
        ffmpeg
        libavcodec60
        libavformat60
        libavutil58
        libswscale7
        libavfilter9
        libavdevice60
        # 오디오
        pulseaudio
        pulseaudio-utils
        alsa-utils
        libpulse0
        libopus0
        # 비디오 인코딩
        libx264-dev
        libx265-dev
        libvpx-dev
        # Boost 1.83 (24.04 기본 — Sunshine 의존성)
        libboost-filesystem1.83.0
        libboost-log1.83.0
        libboost-program-options1.83.0
        libboost-thread1.83.0
        # 입력 디바이스
        libevdev2
    )

    # X11 / Wayland 라이브러리 (VNC, GUI 컨테이너용)
    X11_LIBS=(
        libx11-6
        libxfixes3
        libxft2
        libxi6
        libxmu6
        libxpm4
        libxrandr2
        libxtst6
        libxcb1
        libxcb-glx0
        libxcb-icccm4
        libxcb-image0
        libxcb-keysyms1
        libxcb-randr0
        libxcb-render-util0
        libxcb-shape0
        libxcb-sync1
        libxcb-xfixes0
        libxcb-xkb1
        libxkbcommon-x11-0
        libdrm2
        libgl1
        libgl1-mesa-dri
        libgles2
        libegl1
        mesa-utils
        mesa-vulkan-drivers
        vulkan-tools
        libwayland-client0
        libwayland-server0
        x11-apps
        x11-utils
        x11-xserver-utils
        xserver-xorg-video-dummy
        xserver-xorg-input-libinput
        # glmark2 — universe 저장소 활성화 필요 (현재 미수집, GPU 벤치마크 선택사항)
    )

    # 폰트 (한글 + 이모지 + 영문 보강)
    FONTS_EXTRAS=(
        fonts-noto
        fonts-noto-cjk
        fonts-noto-color-emoji
        fonts-liberation
        fonts-dejavu
        fonts-nanum
        fonts-nanum-coding
    )

    # 데스크톱 애플리케이션 (VNC 컨테이너 내 사용자 도구)
    DESKTOP_APPS=(
        firefox
        gedit
        gnome-system-monitor
        file-roller
        nautilus
        thunar
        mousepad
        gvfs
        gvfs-backends
        vim
        nano
    )

    # CAE/LS-PrePost 의존성 (시뮬레이션 도구)
    CAE_DEPS=(
        # OpenMP 런타임
        libomp-dev
        libgomp1
        # Fortran 런타임 (LS-DYNA)
        libgfortran5
        libquadmath0
        # 수치 라이브러리
        libnuma1
        libcap2
        # Tcl/Tk (LS-PrePost GUI)
        tcl
        tk
        # 기타 GUI 라이브러리
        libxcb-cursor0
    )

    # CRITICAL 패키지 (22.04 install 스크립트의 필수 항목 — 24.04 명명 반영)
    CRITICAL_24_PACKAGES=(
        # PMIx (Slurm 통신)
        libpmix2t64
        libpmix-dev
        # hwloc (CPU 토폴로지)
        libhwloc15
        hwloc
        hwloc-nox
        libhwloc-plugins
        libhwloc-dev
        # munge (Slurm 인증)
        libmunge2
        libmunge-dev
        munge
        # FUSE (Apptainer)
        libfuse2t64
        libfuse3-3
        fuse3
        squashfuse
        libsquashfuse0
        squashfs-tools
        # 시스템 도구
        autofs
        net-tools
        jq
        libjq1
        socat
        pv
        sshpass
    )

    # SSL/인증서/시간대 (Sunshine + 일반 시스템)
    SECURITY_TZ_PACKAGES=(
        ca-certificates
        apt-transport-https
        gnupg
        gnupg2
        libssl3t64                # 24.04 명명 (22.04: libssl3)
        locales
        tzdata
    )
}

# Package selection
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
                "${PYTHON_BUILD_DEPS[@]}"
                "${HPC_PACKAGES[@]}"
                "${NFS_PACKAGES[@]}"
                "${MONITORING_PACKAGES[@]}"
                "${VNC_PACKAGES[@]}"
                "${UBUNTU_DESKTOP_PACKAGES[@]}"
                "${XFCE4_PACKAGES[@]}"
                "${SYSTEM_TOOLS_PACKAGES[@]}"
                "${NETWORK_TOOLS_PACKAGES[@]}"
                "${EXTRA_BUILD_DEPS[@]}"
                "${MEDIA_PACKAGES[@]}"
                "${X11_LIBS[@]}"
                "${FONTS_EXTRAS[@]}"
                "${DESKTOP_APPS[@]}"
                "${CAE_DEPS[@]}"
                "${CRITICAL_24_PACKAGES[@]}"
                "${SECURITY_TZ_PACKAGES[@]}"
            )
            ;;
        media)
            packages+=("${MEDIA_PACKAGES[@]}")
            ;;
        x11)
            packages+=("${X11_LIBS[@]}" "${FONTS_EXTRAS[@]}")
            ;;
        critical)
            packages+=("${CRITICAL_24_PACKAGES[@]}")
            ;;
        cae)
            packages+=("${CAE_DEPS[@]}" "${X11_LIBS[@]}" "${MEDIA_PACKAGES[@]}")
            ;;
        desktop)
            packages+=(
                "${UBUNTU_DESKTOP_PACKAGES[@]}"
                "${XFCE4_PACKAGES[@]}"
                "${VNC_PACKAGES[@]}"
            )
            ;;
        vnc)
            packages+=("${VNC_PACKAGES[@]}")
            ;;
        nfs)
            packages+=("${NFS_PACKAGES[@]}")
            ;;
        monitoring)
            packages+=("${MONITORING_PACKAGES[@]}")
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
                "${PYTHON_BUILD_DEPS[@]}"
            )
            ;;
        *)
            log_error "Unknown service: $SERVICE"
            log_info "Valid services: all, slurm, glusterfs, mariadb, redis, keepalived, web, hpc, desktop, vnc, nfs, monitoring, media, x11, critical, cae"
            exit 1
            ;;
    esac

    # Remove duplicates
    SELECTED_PACKAGES=($(printf '%s\n' "${packages[@]}" | sort -u))
}

# External repository setup (PPA, NodeSource, etc.)
setup_external_repositories() {
    log_info "Setting up external repositories for additional packages..."

    # 1. Apptainer PPA (supports noble/24.04)
    log_info "  Adding Apptainer PPA (noble)..."
    if ! grep -q "apptainer" /etc/apt/sources.list.d/* 2>/dev/null; then
        add-apt-repository -y ppa:apptainer/ppa 2>/dev/null || {
            log_warning "  Failed to add Apptainer PPA (may not be available for noble yet)"
        }
    else
        log_info "  Apptainer PPA already configured"
    fi

    # 2. Python 3.13 (deadsnakes PPA)
    # Note: Python 3.12 is the system default on 24.04, no PPA needed for it.
    #       deadsnakes PPA is used ONLY for Python 3.13.
    log_info "  Adding Python deadsnakes PPA (for Python 3.13 only)..."
    if ! grep -q "deadsnakes" /etc/apt/sources.list.d/* 2>/dev/null; then
        add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || {
            log_warning "  Failed to add deadsnakes PPA"
        }
    else
        log_info "  deadsnakes PPA already configured"
    fi

    # 3. Node.js (NodeSource)
    log_info "  Adding NodeSource repository (Node.js 20.x LTS)..."
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

# Add packages from external repositories
add_external_packages() {
    log_info "Adding packages from external repositories..."

    # Apptainer (from PPA)
    if apt-cache show apptainer &>/dev/null; then
        SELECTED_PACKAGES+=("apptainer")
        log_success "  Added: apptainer"
    fi

    # Python 3.13 (from deadsnakes PPA)
    if apt-cache show python3.13 &>/dev/null; then
        SELECTED_PACKAGES+=(
            "python3.13"
            "python3.13-venv"
            "python3.13-dev"
        )
        log_success "  Added: python3.13, python3.13-venv, python3.13-dev"
    fi

    # Add setuptools (replaces deprecated distutils)
    if apt-cache show python3-setuptools &>/dev/null; then
        SELECTED_PACKAGES+=("python3-setuptools")
        log_success "  Added: python3-setuptools (replaces distutils)"
    fi

    # Node.js (latest LTS from NodeSource)
    if apt-cache show nodejs &>/dev/null; then
        # NodeSource version includes npm
        log_info "  nodejs already in package list"
    fi

    log_success "External packages added to collection list"
}

# Update APT cache
update_apt_cache() {
    log_info "Updating APT cache..."
    apt-get update
    log_success "APT cache updated"
}

# Download packages
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

    # Method 1: apt-get download (direct package download)
    log_info "Method 1: Using apt-get download..."

    local failed_packages=()

    for package in "${SELECTED_PACKAGES[@]}"; do
        log_info "  Downloading: $package"

        if apt-get download "$package" 2>/dev/null; then
            log_success "    OK $package"
        else
            log_warning "    FAIL $package (not available)"
            failed_packages+=("$package")
        fi
    done

    # Download dependencies
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

    # Statistics
    local total_debs=$(find "$OUTPUT_DIR" -name "*.deb" | wc -l)
    local total_size=$(du -sh "$OUTPUT_DIR" | cut -f1)

    log_success "Downloaded packages: $total_debs"
    log_info "Total size: $total_size"

    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_warning "Failed to download ${#failed_packages[@]} packages:"
        printf '  - %s\n' "${failed_packages[@]}"
    fi
}

# Create package list file
create_package_list() {
    log_info "Creating package list file..."

    local list_file="${OUTPUT_DIR}/package_list.txt"

    find "$OUTPUT_DIR" -name "*.deb" -exec basename {} \; | sort > "$list_file"

    log_success "Package list created: $list_file"
}

# Create local APT repository index
create_local_repo_index() {
    log_info "Creating local APT repository index (Packages.gz)..."

    cd "$OUTPUT_DIR"

    # Generate Packages file with dpkg-scanpackages
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

    # Create Release file (optional but required by some apt versions)
    cat > Release << RELEASE_EOF
Origin: Offline-Local
Label: Offline-Local
Suite: noble
Codename: noble
Architectures: amd64
Components: main
Description: Local offline APT repository for Ubuntu 24.04
RELEASE_EOF

    log_success "  Created: Release"

    cd - > /dev/null
}

# Create installation script (local APT repository method)
create_install_script() {
    log_info "Creating installation script (local APT repository method)..."

    local install_script="${OUTPUT_DIR}/install_offline_packages.sh"

    cat > "$install_script" << 'EOF'
#!/bin/bash
################################################################################
# Offline Package Installation Script (Local APT Repository Method)
# Target: Ubuntu 24.04 (Noble Numbat)
#
# This script uses apt instead of dpkg to install packages.
# apt automatically resolves dependencies, making it safer than dpkg.
#
# Usage:
#   sudo ./install_offline_packages.sh [PACKAGE...]
#
# Examples:
#   sudo ./install_offline_packages.sh                # Install all packages
#   sudo ./install_offline_packages.sh nginx nodejs   # Install specific packages
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="offline-local"
REPO_LIST="/etc/apt/sources.list.d/${REPO_NAME}.list"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Root privilege check
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

echo ""
echo "================================================================"
echo "   Offline Package Installation (APT Repository Method)"
echo "   Target OS: Ubuntu 24.04 (Noble Numbat)"
echo "================================================================"
echo ""

log_info "Package directory: $SCRIPT_DIR"

# Count .deb files
DEB_COUNT=$(find "$SCRIPT_DIR" -name "*.deb" | wc -l)
log_info "Found $DEB_COUNT .deb files"

if [[ $DEB_COUNT -eq 0 ]]; then
    log_error "No .deb files found in $SCRIPT_DIR"
    exit 1
fi

# Check for Packages.gz (create if missing)
if [[ ! -f "$SCRIPT_DIR/Packages.gz" ]]; then
    log_warning "Packages.gz not found. Creating repository index..."

    if ! command -v dpkg-scanpackages &> /dev/null; then
        log_info "Installing dpkg-dev for dpkg-scanpackages..."
        # Check if dpkg-dev is available locally
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

# Backup existing sources.list
if [[ -f /etc/apt/sources.list ]]; then
    if [[ ! -f /etc/apt/sources.list.backup-offline ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup-offline
        log_info "  Backed up /etc/apt/sources.list"
    fi
fi

# Add local repository
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

# Check if specific packages are specified
if [[ $# -gt 0 ]]; then
    # Install only specified packages
    PACKAGES_TO_INSTALL=("$@")
    log_info "  Installing specified packages: ${PACKAGES_TO_INSTALL[*]}"
else
    # Install all packages (using package_list.txt)
    if [[ -f "$SCRIPT_DIR/package_list.txt" ]]; then
        # Extract package names from .deb filenames
        PACKAGES_TO_INSTALL=()
        while IFS= read -r deb_file; do
            # Extract package name from filename (name_version_architecture.deb)
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

# Remove duplicates
PACKAGES_TO_INSTALL=($(printf '%s\n' "${PACKAGES_TO_INSTALL[@]}" | sort -u))

# Run apt install (automatic dependency resolution)
log_info "  Running: apt-get install -y ${#PACKAGES_TO_INSTALL[@]} packages..."
apt-get install -y --no-install-recommends "${PACKAGES_TO_INSTALL[@]}" 2>&1 || {
    log_warning "Some packages may have failed. Retrying with -f flag..."
    apt-get install -f -y
}

echo ""
log_info "Step 4: Cleanup..."

# Keep local repository configuration (allows installing additional packages later)
# To remove, uncomment below:
# rm -f "$REPO_LIST"
# apt-get update

log_info "  Local repository kept at: $REPO_LIST"
log_info "  To remove: sudo rm $REPO_LIST && sudo apt-get update"

echo ""
echo "================================================================"
echo "   Offline Package Installation Complete!"
echo "   Ubuntu 24.04 (Noble Numbat)"
echo "================================================================"
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

# Create tarball
create_tarball() {
    log_info "Creating tarball..."

    local tarball_name="apt-packages-2404-$(date +%Y%m%d).tar.gz"
    local tarball_path="${SCRIPT_DIR}/${tarball_name}"

    cd "$(dirname "$OUTPUT_DIR")"
    tar -czf "$tarball_path" "$(basename "$OUTPUT_DIR")"
    cd - > /dev/null

    local tarball_size=$(du -sh "$tarball_path" | cut -f1)

    log_success "Tarball created: $tarball_path ($tarball_size)"
}

# Create MD5 checksums
create_checksums() {
    log_info "Creating checksums..."

    local checksum_file="${OUTPUT_DIR}/checksums.md5"

    cd "$OUTPUT_DIR"
    find . -name "*.deb" -exec md5sum {} \; > "$checksum_file"
    cd - > /dev/null

    log_success "Checksums created: $checksum_file"
}

# Print summary
print_summary() {
    local total_debs=$(find "$OUTPUT_DIR" -name "*.deb" 2>/dev/null | wc -l)
    local total_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo "================================================================"
    echo "   APT Package Collection Complete!"
    echo "   Ubuntu 24.04 (Noble Numbat)"
    echo "================================================================"
    echo ""
    log_info "Collection Summary:"
    echo "------------------------------------------------------------"
    echo "  Service:         $SERVICE"
    echo "  Output:          $OUTPUT_DIR"
    echo "  Packages:        $total_debs .deb files"
    echo "  Total Size:      $total_size"
    echo "------------------------------------------------------------"
    echo ""
    log_info "Python versions collected:"
    echo "  - Python 3.12 (system default on 24.04)"
    echo "  - Python 3.13 (from deadsnakes PPA)"
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
    echo "     tar -xzf apt-packages-2404-*.tar.gz"
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
    echo "================================================================"
    echo "   APT Package Collection Script"
    echo "   Ubuntu 24.04 (Noble Numbat)"
    echo "================================================================"
    echo ""

    check_root
    check_os_version
    define_package_lists
    select_packages

    log_info "Service: $SERVICE"
    log_info "Output: $OUTPUT_DIR"
    log_info "Packages to collect: ${#SELECTED_PACKAGES[@]}"
    echo ""

    if [[ "$DRY_RUN" == "false" && "$SKIP_CONFIRM" == "false" ]]; then
        read -p "Continue with package collection? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi

    # External repository setup (Apptainer, Python 3.13, Node.js LTS)
    if [[ "$SETUP_EXTERNAL_REPOS" == "true" ]]; then
        setup_external_repositories
        update_apt_cache
        # Add external repository packages
        add_external_packages
    else
        log_info "Skipping external repository setup (--no-external-repos)"
        update_apt_cache
    fi

    download_packages
    create_package_list
    create_local_repo_index    # APT repository index (Packages.gz)
    create_install_script      # Local APT repository install script
    create_checksums
    create_tarball
    print_summary

    log_success "Package collection complete!"
}

main "$@"
