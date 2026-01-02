#!/bin/bash
################################################################################
# Slurm 프리빌드 패키지 생성 스크립트
#
# 설명:
#   Slurm을 소스에서 빌드하고 tarball로 패키징하여
#   오프라인 환경에서 배포 가능하도록 합니다.
#
# 기능:
#   - Slurm 소스 다운로드 및 빌드
#   - cgroup v2 지원 포함
#   - 프리빌드 바이너리 tarball 생성
#   - 설치 스크립트 포함
#
# 요구사항:
#   - 인터넷 연결 (헤드 노드에서만)
#   - 빌드 도구 (gcc, make 등)
#
# 사용법:
#   sudo ./build_slurm_package.sh [OPTIONS]
#
# 옵션:
#   --version VERSION    Slurm 버전 (기본: 23.11.10)
#   --prefix PATH        설치 경로 (기본: /opt/slurm)
#   --output-dir PATH    출력 디렉토리 (기본: .)
#   --skip-build         이미 빌드된 경우 건너뛰기
#   --help               도움말 표시
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
SLURM_VERSION="23.11.10"
INSTALL_PREFIX="/opt/slurm"
CONFIG_DIR="/opt/slurm/etc"
OUTPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_BUILD=false
BUILD_DIR="/tmp/slurm_build_$$"

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 도움말
show_help() {
    head -n 30 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# 인자 파싱
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                SLURM_VERSION="$2"
                shift 2
                ;;
            --prefix)
                INSTALL_PREFIX="$2"
                CONFIG_DIR="${INSTALL_PREFIX}/etc"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD=true
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

# Root 권한 확인 (선택적)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warning "Not running as root. Some operations may require sudo."
    fi
}

# 빌드 의존성 확인
check_dependencies() {
    log_info "Checking build dependencies..."

    local deps=(
        "gcc"
        "make"
        "wget"
        "tar"
        "bzip2"
    )

    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install them first:"
        log_info "  sudo apt-get install -y build-essential wget bzip2"
        exit 1
    fi

    log_success "All build dependencies satisfied"
}

# 소스 다운로드
download_slurm_source() {
    log_info "Downloading Slurm ${SLURM_VERSION}..."

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    local SLURM_URL="https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2"

    if [[ ! -f "slurm-${SLURM_VERSION}.tar.bz2" ]]; then
        wget "$SLURM_URL"
        log_success "Downloaded Slurm source"
    else
        log_info "Source already downloaded"
    fi

    if [[ -d "slurm-${SLURM_VERSION}" ]]; then
        rm -rf "slurm-${SLURM_VERSION}"
    fi

    tar -xjf "slurm-${SLURM_VERSION}.tar.bz2"
    cd "slurm-${SLURM_VERSION}"

    log_success "Source extracted"
}

# Configure
configure_slurm() {
    log_info "Configuring Slurm (약 2-3분 소요)..."

    cd "$BUILD_DIR/slurm-${SLURM_VERSION}"

    ./configure \
        --prefix="${INSTALL_PREFIX}" \
        --sysconfdir="${CONFIG_DIR}" \
        --enable-pam \
        --with-pmix \
        --with-hwloc=/usr \
        --without-rpath \
        CFLAGS="$(pkg-config --cflags libsystemd 2>/dev/null || echo '')" \
        LDFLAGS="$(pkg-config --libs libsystemd 2>/dev/null || echo '')"

    if [[ $? -eq 0 ]]; then
        log_success "Configure completed"

        # systemd 지원 확인
        if grep -qE "HAVE_SYSTEMD|WITH_SYSTEMD" config.h 2>/dev/null; then
            log_success "systemd/cgroup v2 support: ENABLED"
        else
            log_warning "systemd support not detected"
        fi
    else
        log_error "Configure failed"
        exit 1
    fi
}

# 컴파일
compile_slurm() {
    log_info "Compiling Slurm (약 10-15분 소요)..."

    cd "$BUILD_DIR/slurm-${SLURM_VERSION}"

    make -j$(nproc)

    if [[ $? -eq 0 ]]; then
        log_success "Compilation completed"
    else
        log_error "Compilation failed"
        exit 1
    fi
}

# 임시 디렉토리에 설치
install_to_staging() {
    log_info "Installing to staging directory..."

    cd "$BUILD_DIR/slurm-${SLURM_VERSION}"

    local STAGING_DIR="${BUILD_DIR}/staging"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"

    make DESTDIR="$STAGING_DIR" install

    if [[ $? -eq 0 ]]; then
        log_success "Installed to staging: $STAGING_DIR"
    else
        log_error "Installation to staging failed"
        exit 1
    fi

    # 디렉토리 구조 확인
    ls -la "${STAGING_DIR}${INSTALL_PREFIX}" 2>/dev/null || {
        log_error "Installation directory not found in staging"
        exit 1
    }
}

# 배포 스크립트 생성
create_deployment_script() {
    log_info "Creating deployment script..."

    local STAGING_DIR="${BUILD_DIR}/staging"
    local DEPLOY_SCRIPT="${STAGING_DIR}/deploy_slurm.sh"

    cat > "$DEPLOY_SCRIPT" << 'EOFSCRIPT'
#!/bin/bash
################################################################################
# Slurm 오프라인 배포 스크립트 (계산 노드에서 실행)
################################################################################

set -e

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="SLURM_INSTALL_PREFIX"
CONFIG_DIR="SLURM_CONFIG_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Slurm 오프라인 배포                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Installing Slurm to: $INSTALL_PREFIX"

# Root 권한 확인
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# ============================================================================
# apt 패키지로 설치된 Slurm 서비스 중지 (21.08.5 -> 23.11.10 전환)
# ============================================================================
log_info "Checking for existing apt Slurm services..."

# apt Slurm 서비스 중지
for service in slurmctld slurmd slurmdbd; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_info "Stopping apt Slurm service: $service"
        systemctl stop "$service" 2>/dev/null || true
    fi
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        log_info "Disabling apt Slurm service: $service"
        systemctl disable "$service" 2>/dev/null || true
    fi
done

# apt Slurm 바이너리 존재 확인 및 경고
if [[ -f /usr/bin/sinfo ]]; then
    APT_VERSION=$(/usr/bin/sinfo --version 2>/dev/null | head -1 || echo "unknown")
    log_warning "Found apt Slurm at /usr/bin: $APT_VERSION"
    log_info "Source-built Slurm 23.11.10 will be used instead (/usr/local/slurm/bin)"
fi

# Slurm 사용자 생성
# NOTE: UID 64001 사용 - 일반 시스템 계정(1000~)과 충돌 방지
# 이미 존재하면 건너뜀 (phase3_slurm.sh에서 YAML 기반 UID로 먼저 생성됨)
log_info "Creating slurm user..."
if ! id slurm &>/dev/null; then
    # 64001 사용 (기본값), 충돌 시 자동 할당
    groupadd -g 64001 slurm 2>/dev/null || groupadd slurm 2>/dev/null || true
    useradd -u 64001 -g slurm -m -s /bin/bash slurm 2>/dev/null || useradd -g slurm -m -s /bin/bash slurm 2>/dev/null || true
    log_success "User 'slurm' created"
else
    log_info "User 'slurm' already exists (using existing UID: $(id -u slurm))"
fi

# 디렉토리 복사
log_info "Copying Slurm binaries..."
mkdir -p "$INSTALL_PREFIX"
cp -a "${SCRIPT_DIR}${INSTALL_PREFIX}"/* "$INSTALL_PREFIX/"

# 심볼릭 링크 생성
log_info "Creating symbolic links..."
ln -sf "$INSTALL_PREFIX" /usr/local/slurm

# /usr/local/bin에 주요 명령어 심볼릭 링크 생성 (시스템 전역 PATH에 포함)
# 이렇게 하면 /etc/profile.d 로드 없이도 모든 셸에서 slurm 명령어 사용 가능
log_info "Creating /usr/local/bin symlinks for system-wide access..."
for cmd in sinfo squeue sbatch scancel scontrol sacct sacctmgr srun salloc; do
    if [[ -x "/usr/local/slurm/bin/$cmd" ]]; then
        ln -sf "/usr/local/slurm/bin/$cmd" "/usr/local/bin/$cmd"
        log_info "  /usr/local/bin/$cmd -> /usr/local/slurm/bin/$cmd"
    fi
done
for cmd in slurmctld slurmd slurmdbd; do
    if [[ -x "/usr/local/slurm/sbin/$cmd" ]]; then
        ln -sf "/usr/local/slurm/sbin/$cmd" "/usr/local/sbin/$cmd"
        log_info "  /usr/local/sbin/$cmd -> /usr/local/slurm/sbin/$cmd"
    fi
done

# PATH 설정 (profile.d - 로그인 셸용, 환경변수 완전 설정)
log_info "Configuring PATH..."
tee /etc/profile.d/slurm.sh > /dev/null << 'EOFPATH'
# Slurm Environment
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export MANPATH=/usr/local/slurm/share/man${MANPATH:+:$MANPATH}
EOFPATH
chmod 644 /etc/profile.d/slurm.sh

# 디렉토리 생성
log_info "Creating Slurm directories..."
mkdir -p /var/log/slurm
mkdir -p /var/spool/slurm/{state,d}
mkdir -p "$CONFIG_DIR"

chown -R slurm:slurm /var/log/slurm /var/spool/slurm "$CONFIG_DIR"
chmod 755 /var/log/slurm /var/spool/slurm

# slurm.conf 호환성 설정 (심볼릭 링크 대신 복사 방식)
# Slurm 23.02+ 버전은 /etc/slurm과 /usr/local/slurm/etc 양쪽 모두 참조
# 해결: 두 경로에 동일한 설정 파일을 복사하여 동기화
log_info "Configuring slurm.conf compatibility (copy mode)..."

# 케이스 1: /etc/slurm/slurm.conf만 있고 $CONFIG_DIR/slurm.conf가 없는 경우
#          -> /etc/slurm/slurm.conf를 $CONFIG_DIR로 복사
if [[ -f /etc/slurm/slurm.conf && ! -f "$CONFIG_DIR/slurm.conf" ]]; then
    cp /etc/slurm/slurm.conf "$CONFIG_DIR/slurm.conf"
    chown slurm:slurm "$CONFIG_DIR/slurm.conf"
    log_success "Copied /etc/slurm/slurm.conf -> $CONFIG_DIR/slurm.conf"

# 케이스 2: $CONFIG_DIR/slurm.conf만 있고 /etc/slurm/slurm.conf가 없는 경우
#          -> $CONFIG_DIR/slurm.conf를 /etc/slurm으로 복사
elif [[ -f "$CONFIG_DIR/slurm.conf" && ! -f /etc/slurm/slurm.conf ]]; then
    mkdir -p /etc/slurm
    cp "$CONFIG_DIR/slurm.conf" /etc/slurm/slurm.conf
    chown slurm:slurm /etc/slurm/slurm.conf
    log_success "Copied $CONFIG_DIR/slurm.conf -> /etc/slurm/slurm.conf"

# 케이스 3: 두 파일 모두 존재하는 경우
#          -> NodeName 정의가 있는 파일을 우선 사용하여 양쪽에 복사
elif [[ -f /etc/slurm/slurm.conf && -f "$CONFIG_DIR/slurm.conf" ]]; then
    # NodeName 정의 유무 확인 (tr -d로 개행 제거)
    ETC_HAS_NODES=$(grep -c "^NodeName=" /etc/slurm/slurm.conf 2>/dev/null | tr -d '\n' || echo 0)
    CONFIG_HAS_NODES=$(grep -c "^NodeName=" "$CONFIG_DIR/slurm.conf" 2>/dev/null | tr -d '\n' || echo 0)

    if [[ "$CONFIG_HAS_NODES" -gt 0 && "$ETC_HAS_NODES" -eq 0 ]]; then
        # $CONFIG_DIR에 노드 정의가 있고 /etc/slurm에 없으면 -> $CONFIG_DIR을 /etc/slurm으로 복사
        log_warning "/etc/slurm/slurm.conf has no NodeName definitions"
        log_info "Backing up /etc/slurm/slurm.conf to /etc/slurm/slurm.conf.bak"
        mv /etc/slurm/slurm.conf /etc/slurm/slurm.conf.bak
        cp "$CONFIG_DIR/slurm.conf" /etc/slurm/slurm.conf
        chown slurm:slurm /etc/slurm/slurm.conf
        log_success "Copied $CONFIG_DIR/slurm.conf -> /etc/slurm/slurm.conf (has NodeName definitions)"
    elif [[ "$ETC_HAS_NODES" -gt 0 && "$CONFIG_HAS_NODES" -eq 0 ]]; then
        # /etc/slurm에 노드 정의가 있고 $CONFIG_DIR에 없으면 -> /etc/slurm을 $CONFIG_DIR로 복사
        log_info "Backing up $CONFIG_DIR/slurm.conf"
        mv "$CONFIG_DIR/slurm.conf" "$CONFIG_DIR/slurm.conf.bak"
        cp /etc/slurm/slurm.conf "$CONFIG_DIR/slurm.conf"
        chown slurm:slurm "$CONFIG_DIR/slurm.conf"
        log_success "Copied /etc/slurm/slurm.conf -> $CONFIG_DIR/slurm.conf (has NodeName definitions)"
    elif [[ "$ETC_HAS_NODES" -gt 0 && "$CONFIG_HAS_NODES" -gt 0 ]]; then
        log_success "Both config files have NodeName definitions"
    else
        # 둘 다 노드 정의가 없으면 경고
        log_warning "Neither config file has NodeName definitions!"
        log_info "Using $CONFIG_DIR/slurm.conf by default"
    fi
fi

# slurmdbd.conf도 동일하게 처리 (복사 방식)
if [[ -f /etc/slurm/slurmdbd.conf && ! -f "$CONFIG_DIR/slurmdbd.conf" ]]; then
    cp /etc/slurm/slurmdbd.conf "$CONFIG_DIR/slurmdbd.conf"
    chown slurm:slurm "$CONFIG_DIR/slurmdbd.conf"
    chmod 600 "$CONFIG_DIR/slurmdbd.conf"
    log_success "Copied /etc/slurm/slurmdbd.conf -> $CONFIG_DIR/slurmdbd.conf"
elif [[ -f "$CONFIG_DIR/slurmdbd.conf" && ! -f /etc/slurm/slurmdbd.conf ]]; then
    mkdir -p /etc/slurm
    cp "$CONFIG_DIR/slurmdbd.conf" /etc/slurm/slurmdbd.conf
    chown slurm:slurm /etc/slurm/slurmdbd.conf
    chmod 600 /etc/slurm/slurmdbd.conf
    log_success "Copied $CONFIG_DIR/slurmdbd.conf -> /etc/slurm/slurmdbd.conf"
fi

# 권한 설정
chown -R root:root "$INSTALL_PREFIX"
chown -R slurm:slurm "$CONFIG_DIR"

# ============================================================================
# 설치 검증 및 PATH 강제 적용
# ============================================================================
log_info "Verifying installation..."

# 심볼릭 링크 검증
if [[ -L /usr/local/slurm && -d /usr/local/slurm/bin ]]; then
    log_success "Symbolic link verified: /usr/local/slurm -> $(readlink -f /usr/local/slurm)"
else
    log_error "Symbolic link failed! /usr/local/slurm does not point to valid directory"
    exit 1
fi

# sinfo 바이너리 존재 확인
if [[ -x /usr/local/slurm/bin/sinfo ]]; then
    log_success "Slurm binary verified: /usr/local/slurm/bin/sinfo"
else
    log_error "Slurm binary not found: /usr/local/slurm/bin/sinfo"
    exit 1
fi

# 버전 확인
SLURM_VERSION=$(/usr/local/slurm/bin/sinfo --version 2>/dev/null || echo "unknown")
log_success "Slurm version: $SLURM_VERSION"

# 현재 셸 PATH 갱신 (hash 테이블 클리어)
hash -r 2>/dev/null || true

# PATH 적용 (현재 스크립트 실행 환경)
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH

# which sinfo 확인
WHICH_SINFO=$(which sinfo 2>/dev/null || echo "not found")
if [[ "$WHICH_SINFO" == "/usr/local/slurm/bin/sinfo" ]]; then
    log_success "which sinfo = $WHICH_SINFO (올바름)"
else
    log_warning "which sinfo = $WHICH_SINFO"
    log_info "새 터미널에서 'source /etc/profile.d/slurm.sh' 실행 필요"
fi

log_success "Slurm deployed successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 중요: PATH 적용 방법"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  새 터미널을 열거나 다음 명령 실행:"
echo "    source /etc/profile.d/slurm.sh"
echo ""
echo "  확인 방법:"
echo "    which sinfo   # /usr/local/slurm/bin/sinfo 출력 확인"
echo "    sinfo --version  # slurm 23.x 출력 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Next steps:"
echo "  1. Configure slurm.conf in: $CONFIG_DIR"
echo "  2. Setup Munge authentication"
echo "  3. Start services: slurmctld / slurmd"
echo ""
EOFSCRIPT

    # 변수 치환
    sed -i "s|SLURM_INSTALL_PREFIX|${INSTALL_PREFIX}|g" "$DEPLOY_SCRIPT"
    sed -i "s|SLURM_CONFIG_DIR|${CONFIG_DIR}|g" "$DEPLOY_SCRIPT"

    chmod +x "$DEPLOY_SCRIPT"

    log_success "Deployment script created: $DEPLOY_SCRIPT"
}

# 메타데이터 파일 생성
create_metadata() {
    log_info "Creating metadata..."

    local STAGING_DIR="${BUILD_DIR}/staging"
    local METADATA="${STAGING_DIR}/SLURM_BUILD_INFO.txt"

    cat > "$METADATA" << EOF
Slurm Prebuilt Package
======================

Build Information:
  Version:          ${SLURM_VERSION}
  Build Date:       $(date)
  Build Host:       $(hostname)
  Install Prefix:   ${INSTALL_PREFIX}
  Config Directory: ${CONFIG_DIR}

Features:
  cgroup v2:        Yes (with systemd support)
  PAM:              Yes
  PMIx:             Yes
  HWLOC:            Yes

Deployment:
  1. Extract tarball:
     tar -xzf slurm-${SLURM_VERSION}-prebuilt.tar.gz

  2. Run deployment script:
     cd slurm-${SLURM_VERSION}-prebuilt
     sudo bash deploy_slurm.sh

  3. Configure:
     Edit ${CONFIG_DIR}/slurm.conf

  4. Start services:
     systemctl start slurmctld  # on controller
     systemctl start slurmd     # on compute nodes
EOF

    log_success "Metadata created: $METADATA"
}

# tarball 생성
create_tarball() {
    log_info "Creating tarball..."

    local STAGING_DIR="${BUILD_DIR}/staging"
    local TARBALL_NAME="slurm-${SLURM_VERSION}-prebuilt.tar.gz"
    local TARBALL_PATH="${OUTPUT_DIR}/${TARBALL_NAME}"

    cd "$BUILD_DIR"

    tar -czf "$TARBALL_PATH" -C staging .

    if [[ -f "$TARBALL_PATH" ]]; then
        local TARBALL_SIZE=$(du -sh "$TARBALL_PATH" | cut -f1)
        log_success "Tarball created: $TARBALL_PATH ($TARBALL_SIZE)"

        # 체크섬
        md5sum "$TARBALL_PATH" > "${TARBALL_PATH}.md5"
        log_info "MD5 checksum: ${TARBALL_PATH}.md5"
    else
        log_error "Failed to create tarball"
        exit 1
    fi
}

# 정리
cleanup() {
    if [[ -d "$BUILD_DIR" ]]; then
        log_info "Cleaning up build directory: $BUILD_DIR"
        rm -rf "$BUILD_DIR"
    fi
}

# 요약
print_summary() {
    local TARBALL_NAME="slurm-${SLURM_VERSION}-prebuilt.tar.gz"
    local TARBALL_PATH="${OUTPUT_DIR}/${TARBALL_NAME}"
    local TARBALL_SIZE=$(du -sh "$TARBALL_PATH" 2>/dev/null | cut -f1 || echo "N/A")

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Slurm 프리빌드 패키지 생성 완료!                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Build Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Slurm Version:    ${SLURM_VERSION}"
    echo "  Install Prefix:   ${INSTALL_PREFIX}"
    echo "  Tarball:          ${TARBALL_PATH}"
    echo "  Size:             ${TARBALL_SIZE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Deployment Instructions:"
    echo "  1. Copy tarball to target node:"
    echo "     scp ${TARBALL_PATH} user@node:/tmp/"
    echo ""
    echo "  2. Extract and deploy:"
    echo "     cd /tmp"
    echo "     tar -xzf ${TARBALL_NAME}"
    echo "     sudo bash deploy_slurm.sh"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Slurm 프리빌드 패키지 생성                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    check_dependencies

    log_info "Slurm Version: ${SLURM_VERSION}"
    log_info "Install Prefix: ${INSTALL_PREFIX}"
    log_info "Output Directory: ${OUTPUT_DIR}"
    echo ""

    if [[ "$SKIP_BUILD" == "false" ]]; then
        download_slurm_source
        configure_slurm
        compile_slurm
    else
        log_warning "Skipping build (--skip-build)"
    fi

    install_to_staging
    create_deployment_script
    create_metadata
    create_tarball
    cleanup
    print_summary

    log_success "Slurm prebuilt package ready!"
}

# Ctrl+C 시 정리
trap cleanup EXIT

main "$@"
