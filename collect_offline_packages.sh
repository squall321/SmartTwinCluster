#!/bin/bash
################################################################################
# 오프라인 패키지 통합 수집 스크립트 (OS 버전 자동 감지)
#
# 설명:
#   현재 실행 중인 OS를 감지하여 해당 버전에 맞는 오프라인 패키지를 수집합니다.
#   22.04 → offline_packages/
#   24.04 → offline_packages_2404/
#   기타  → offline_packages_{codename}/
#
# 수집 항목:
#   Phase 1: APT 패키지 (.deb) + 의존성
#   Phase 2: Slurm 소스 빌드 → 프리빌드 tarball
#   Phase 3: Python wheels (dashboard 서비스용)
#   Phase 4: GPU 드라이버 (NVIDIA)
#   Phase 5: Prometheus + Node Exporter
#   Phase 6: Munge 키 생성
#
# 사용법:
#   sudo ./collect_offline_packages.sh [OPTIONS]
#
# 옵션:
#   --yes, -y              확인 없이 자동 실행
#   --skip-slurm-build     Slurm 빌드 건너뛰기 (기존 tarball 사용)
#   --skip-gpu             GPU 패키지 건너뛰기
#   --skip-python          Python wheels 건너뛰기
#   --apt-only             APT 패키지만 수집
#   --help                 도움말 표시
#
# 작성자: Claude Code
# 날짜: 2026-03-18
################################################################################

set -uo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 로깅 함수
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase()   { echo -e "${CYAN}[PHASE $1]${NC} $2"; }

# 스크립트 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# OS 감지
source "${SCRIPT_DIR}/cluster/utils/detect_os.sh"
detect_os_version
set_offline_pkg_dir "$SCRIPT_DIR"

# 옵션
AUTO_YES=false
SKIP_SLURM_BUILD=false
SKIP_GPU=false
SKIP_PYTHON=false
APT_ONLY=false
SLURM_VERSION="23.11.10"

# 통계
PHASE_SUCCESS=0
PHASE_FAIL=0
PHASE_SKIP=0
FAILED_PHASES=()

################################################################################
# 인자 파싱
################################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --skip-slurm-build)
            SKIP_SLURM_BUILD=true
            shift
            ;;
        --skip-gpu)
            SKIP_GPU=true
            shift
            ;;
        --skip-python)
            SKIP_PYTHON=true
            shift
            ;;
        --apt-only)
            APT_ONLY=true
            shift
            ;;
        --help|-h)
            head -n 35 "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            log_info "Use --help for usage"
            exit 1
            ;;
    esac
done

################################################################################
# 사전 검사
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)"
        exit 1
    fi
}

check_internet() {
    log_info "Checking internet connection..."
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null || ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        log_success "Internet connection available"
    else
        log_error "No internet connection. This script requires internet to download packages."
        exit 1
    fi
}

check_disk_space() {
    local available_gb
    available_gb=$(df -BG "$SCRIPT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    log_info "Disk space: ${available_gb}GB available"

    if [[ $available_gb -lt 10 ]]; then
        log_error "Insufficient disk space. Need at least 10GB, have ${available_gb}GB"
        exit 1
    elif [[ $available_gb -lt 30 ]]; then
        log_warning "Low disk space: ${available_gb}GB (recommended: 30GB)"
    fi
}

confirm_proceed() {
    if [[ "$AUTO_YES" == "true" ]]; then
        return 0
    fi

    echo ""
    read -p "Proceed with package collection? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled by user"
        exit 0
    fi
}

################################################################################
# Phase 1: APT 패키지 수집
################################################################################

phase_apt_packages() {
    log_phase "1" "APT 패키지 수집"

    local apt_dir="${OFFLINE_PKG_DIR}/apt_packages"
    mkdir -p "$apt_dir"

    # 기존 collect_apt_packages.sh가 있으면 사용
    local collect_script="${SCRIPT_DIR}/offline_packages/collect_apt_packages.sh"
    if [[ -f "$collect_script" ]]; then
        log_info "Using existing collect script: $collect_script"
        chmod +x "$collect_script"
        if bash "$collect_script" --service all --output-dir "$apt_dir"; then
            log_success "APT packages collected via existing script"
            return 0
        fi
        log_warning "Existing script failed, falling back to built-in collection"
    fi

    # 내장 수집 로직
    log_info "Collecting APT packages directly..."
    cd "$apt_dir"

    # 필수 패키지 목록
    local PACKAGES=(
        # 빌드 도구
        build-essential gcc g++ make bzip2 wget curl rsync vim

        # Munge 인증
        munge libmunge-dev libmunge2

        # Slurm 빌드 의존성
        libpam0g-dev libreadline-dev libssl-dev libnuma-dev
        libhwloc-dev libdbus-1-dev libsystemd-dev pkg-config

        # PMIx (Slurm MPI 지원 — 핵심!)
        libpmix-dev

        # MariaDB (slurmdbd용)
        mariadb-server mariadb-client libmariadb-dev libmariadb-dev-compat

        # Python
        python3 python3-pip python3-yaml python3-paramiko python3-venv

        # Redis
        redis-server redis-tools

        # 네트워크/유틸리티
        net-tools jq socat pv sshpass autofs ntp ntpdate chrony
        openssh-server openssh-client
        hwloc libhwloc15

        # Nginx
        nginx

        # Apptainer
        apptainer

        # Node.js 빌드 도구
        nodejs npm
    )

    # 24.04 특화 패키지명 변환
    if [[ "$OS_VERSION" == "24.04" || "$OS_CODENAME" == "noble" ]]; then
        # libpmix2 → libpmix2t64 on 24.04
        PACKAGES+=("libpmix2t64")
        log_info "OS: Ubuntu 24.04 (${OS_CODENAME}) — using 24.04-specific package names"
    else
        PACKAGES+=("libpmix2")
        log_info "OS: Ubuntu ${OS_VERSION} (${OS_CODENAME})"
    fi

    apt-get update -qq 2>&1 | grep -v "^W:" || true

    # 의존성 포함 전체 패키지 목록
    log_info "Resolving dependencies..."
    local ALL_DEPS
    ALL_DEPS=$(apt-cache depends --recurse --no-recommends --no-suggests \
               --no-conflicts --no-breaks --no-replaces --no-enhances \
               "${PACKAGES[@]}" 2>/dev/null | grep "^\w" | sort -u || true)

    local UNIQUE_DEPS
    readarray -t UNIQUE_DEPS <<< "$ALL_DEPS"
    log_info "Total packages (with dependencies): ${#UNIQUE_DEPS[@]}"

    # 배치 다운로드
    local DOWNLOADED=0
    local SKIPPED=0
    local BATCH_SIZE=20

    for ((i=0; i<${#UNIQUE_DEPS[@]}; i+=BATCH_SIZE)); do
        local batch=("${UNIQUE_DEPS[@]:i:BATCH_SIZE}")
        local real_packages=()

        for pkg in "${batch[@]}"; do
            [[ -z "$pkg" ]] && continue
            [[ ! "$pkg" =~ ^[a-zA-Z0-9] ]] && continue
            # 이미 다운로드된 건 스킵
            if ls "${pkg}"_*.deb &>/dev/null 2>&1; then
                SKIPPED=$((SKIPPED + 1))
                continue
            fi
            if apt-cache show "$pkg" &>/dev/null 2>&1; then
                real_packages+=("$pkg")
            else
                SKIPPED=$((SKIPPED + 1))
            fi
        done

        if [[ ${#real_packages[@]} -gt 0 ]]; then
            apt-get download "${real_packages[@]}" >/dev/null 2>&1 || true
            DOWNLOADED=$((DOWNLOADED + ${#real_packages[@]}))
        fi

        local progress=$(( (i + BATCH_SIZE) * 100 / ${#UNIQUE_DEPS[@]} ))
        [[ $progress -gt 100 ]] && progress=100
        echo -ne "\r  Progress: ${progress}% (${DOWNLOADED} downloaded, ${SKIPPED} skipped)    "
    done
    echo ""

    # APT 인덱스 생성
    log_info "Creating APT repository index..."
    if command -v dpkg-scanpackages &>/dev/null; then
        dpkg-scanpackages . /dev/null > Packages 2>/dev/null
        gzip -k -f Packages
        log_success "Repository index created (Packages.gz)"
    else
        log_warning "dpkg-dev not installed, skipping index creation"
    fi

    # package_list.txt 생성
    ls -1 *.deb 2>/dev/null | sort > package_list.txt

    # install_offline_packages.sh 복사 (22.04 기본 것 복사 후 필요시 패키지명 조정)
    local install_script_src="${SCRIPT_DIR}/offline_packages/apt_packages/install_offline_packages.sh"
    if [[ -f "$install_script_src" && ! -f "${apt_dir}/install_offline_packages.sh" ]]; then
        cp "$install_script_src" "${apt_dir}/install_offline_packages.sh"
        chmod +x "${apt_dir}/install_offline_packages.sh"

        # 24.04에서는 CRITICAL_PACKAGES의 libpmix2 → libpmix2t64 치환
        if [[ "$OS_VERSION" == "24.04" || "$OS_CODENAME" == "noble" ]]; then
            sed -i 's/"libpmix2"/"libpmix2t64"/' "${apt_dir}/install_offline_packages.sh"
        fi
        log_success "install_offline_packages.sh copied and adjusted"
    fi

    local deb_count
    deb_count=$(find "$apt_dir" -name "*.deb" | wc -l)
    local deb_size
    deb_size=$(du -sh "$apt_dir" | cut -f1)
    log_success "APT packages collected: ${deb_count} packages (${deb_size})"
}

################################################################################
# Phase 2: Slurm 프리빌드
################################################################################

phase_slurm_build() {
    log_phase "2" "Slurm 프리빌드 패키지 생성"

    local slurm_dir="${OFFLINE_PKG_DIR}/slurm"
    mkdir -p "$slurm_dir"

    # 이미 빌드된 tarball이 있는지 확인
    if ls "$slurm_dir"/slurm-*-prebuilt.tar.gz &>/dev/null; then
        log_info "Slurm prebuilt tarball already exists:"
        ls -lh "$slurm_dir"/slurm-*-prebuilt.tar.gz
        if [[ "$SKIP_SLURM_BUILD" == "true" ]]; then
            log_info "Skipping rebuild (--skip-slurm-build)"
            return 0
        fi
        log_info "Rebuilding (remove existing tarball to skip)"
    fi

    if [[ "$SKIP_SLURM_BUILD" == "true" ]]; then
        log_warning "Skipping Slurm build (--skip-slurm-build)"
        log_warning "No existing tarball found — compute nodes will not have Slurm!"
        return 0
    fi

    # build_slurm_package.sh 사용
    local build_script="${SCRIPT_DIR}/offline_packages/slurm/build_slurm_package.sh"
    if [[ ! -f "$build_script" ]]; then
        log_error "Slurm build script not found: $build_script"
        return 1
    fi

    chmod +x "$build_script"

    log_info "Building Slurm ${SLURM_VERSION} from source (15~20 min)..."
    if bash "$build_script" --version "$SLURM_VERSION" --output-dir "$slurm_dir"; then
        log_success "Slurm prebuilt package created"
    else
        log_error "Slurm build failed"
        return 1
    fi
}

################################################################################
# Phase 3: Python wheels
################################################################################

phase_python_wheels() {
    log_phase "3" "Python wheels 수집"

    if [[ "$SKIP_PYTHON" == "true" ]]; then
        log_info "Skipping Python wheels (--skip-python)"
        return 0
    fi

    local wheels_script="${SCRIPT_DIR}/offline_packages/download_python_wheels.sh"
    if [[ -f "$wheels_script" ]]; then
        log_info "Using existing download script"
        chmod +x "$wheels_script"
        # --yes 모드면 자동 응답
        if [[ "$AUTO_YES" == "true" ]]; then
            echo "y" | bash "$wheels_script"
        else
            bash "$wheels_script"
        fi
        return $?
    fi

    # 내장 다운로드: 각 dashboard 서비스의 requirements.txt에서 wheel 수집
    local wheels_dir="${OFFLINE_PKG_DIR}/python_wheels"
    mkdir -p "$wheels_dir"

    local py_version
    py_version=$(python3 --version 2>&1 | grep -oP '\d+\.\d+' || echo "3.12")
    local ver_dir="${wheels_dir}/python${py_version}"
    mkdir -p "$ver_dir"

    log_info "Collecting wheels for Python ${py_version}..."

    local req_count=0
    while IFS= read -r req_file; do
        [[ -z "$req_file" ]] && continue
        local service_name
        service_name=$(basename "$(dirname "$req_file")")
        log_info "  ${service_name}: $(basename "$req_file")"
        pip3 download -r "$req_file" --dest "$ver_dir" >/dev/null 2>&1 || {
            log_warning "  Some packages failed for ${service_name}"
        }
        req_count=$((req_count + 1))
    done < <(find "${SCRIPT_DIR}/dashboard" -maxdepth 2 \
             \( -name "requirements_actual.txt" -o -name "requirements.txt" \) \
             -not -path "*/venv/*" -not -path "*/node_modules/*" -not -path "*.backup*" \
             2>/dev/null | sort -u)

    local wheel_count
    wheel_count=$(find "$ver_dir" \( -name "*.whl" -o -name "*.tar.gz" \) 2>/dev/null | wc -l)
    log_success "Python wheels collected: ${wheel_count} packages from ${req_count} services"
}

################################################################################
# Phase 4: GPU 패키지
################################################################################

phase_gpu_packages() {
    log_phase "4" "GPU 드라이버 패키지"

    if [[ "$SKIP_GPU" == "true" ]]; then
        log_info "Skipping GPU packages (--skip-gpu)"
        return 0
    fi

    local gpu_dir="${OFFLINE_PKG_DIR}/gpu"
    mkdir -p "$gpu_dir"

    local gpu_script="${SCRIPT_DIR}/offline_packages/gpu/download_gpu_packages.sh"
    if [[ -f "$gpu_script" ]]; then
        log_info "Using existing GPU download script"
        chmod +x "$gpu_script"
        bash "$gpu_script" nvidia
        return $?
    fi

    log_warning "GPU download script not found: $gpu_script"
    log_info "Download manually: https://developer.nvidia.com/cuda-downloads"
    return 0
}

################################################################################
# Phase 5: Prometheus + Node Exporter
################################################################################

phase_monitoring() {
    log_phase "5" "Prometheus + Node Exporter"

    local monitoring_dir="${OFFLINE_PKG_DIR}/monitoring"
    mkdir -p "$monitoring_dir"

    local ARCH
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac

    local PROMETHEUS_VERSION="2.47.2"
    local NODE_EXPORTER_VERSION="1.7.0"

    # Prometheus
    local prom_file="prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
    if [[ ! -f "${monitoring_dir}/${prom_file}" ]]; then
        log_info "Downloading Prometheus ${PROMETHEUS_VERSION}..."
        wget -q --show-progress -O "${monitoring_dir}/${prom_file}" \
            "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${prom_file}" || {
            log_warning "Prometheus download failed"
        }
    else
        log_info "Prometheus already downloaded"
    fi

    # Node Exporter
    local ne_file="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
    if [[ ! -f "${monitoring_dir}/${ne_file}" ]]; then
        log_info "Downloading Node Exporter ${NODE_EXPORTER_VERSION}..."
        wget -q --show-progress -O "${monitoring_dir}/${ne_file}" \
            "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${ne_file}" || {
            log_warning "Node Exporter download failed"
        }
    else
        log_info "Node Exporter already downloaded"
    fi

    log_success "Monitoring tools collected"
}

################################################################################
# Phase 6: Munge 키
################################################################################

phase_munge_key() {
    log_phase "6" "Munge 인증 키"

    local munge_dir="${OFFLINE_PKG_DIR}/munge"
    mkdir -p "$munge_dir"

    if [[ -f "${munge_dir}/munge.key" ]]; then
        log_info "Munge key already exists"
        return 0
    fi

    if ! command -v mungekey &>/dev/null && ! command -v munge &>/dev/null; then
        log_info "Installing munge for key generation..."
        apt-get install -y munge >/dev/null 2>&1 || true
    fi

    if [[ -f /etc/munge/munge.key ]]; then
        cp /etc/munge/munge.key "${munge_dir}/"
        chmod 400 "${munge_dir}/munge.key"
        log_success "Munge key copied from /etc/munge/"
    elif command -v mungekey &>/dev/null; then
        mungekey -c -f -k "${munge_dir}/munge.key" 2>/dev/null || {
            dd if=/dev/urandom bs=1 count=1024 > "${munge_dir}/munge.key" 2>/dev/null
        }
        chmod 400 "${munge_dir}/munge.key"
        log_success "Munge key generated"
    else
        log_warning "Cannot generate munge key (munge not installed)"
        return 0
    fi
}

################################################################################
# 요약
################################################################################

print_summary() {
    local pkg_dir="$OFFLINE_PKG_DIR"
    local apt_count
    apt_count=$(find "${pkg_dir}/apt_packages" -name "*.deb" 2>/dev/null | wc -l)
    local slurm_tarball
    slurm_tarball=$(ls "${pkg_dir}/slurm"/slurm-*-prebuilt.tar.gz 2>/dev/null | head -1)
    local wheel_count
    wheel_count=$(find "${pkg_dir}/python_wheels" \( -name "*.whl" -o -name "*.tar.gz" \) 2>/dev/null | wc -l)
    local total_size
    total_size=$(du -sh "$pkg_dir" 2>/dev/null | cut -f1)
    local total_phases=$((PHASE_SUCCESS + PHASE_FAIL + PHASE_SKIP))

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          오프라인 패키지 수집 완료!                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  OS:              Ubuntu ${OS_VERSION} (${OS_CODENAME})"
    echo "  Output:          ${pkg_dir}"
    echo "  Total Size:      ${total_size}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  APT Packages:    ${apt_count} .deb files"
    echo -e "  Slurm:           $(basename "$slurm_tarball" 2>/dev/null || echo "N/A")"
    echo -e "  Python Wheels:   ${wheel_count} packages"
    echo -e "  Munge Key:       $(if [[ -f "${pkg_dir}/munge/munge.key" ]]; then echo "OK"; else echo "N/A"; fi)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  Phase Results:   ${GREEN}${PHASE_SUCCESS} success${NC}, ${RED}${PHASE_FAIL} failed${NC}, ${YELLOW}${PHASE_SKIP} skipped${NC}"

    if [[ ${#FAILED_PHASES[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${RED}Failed Phases:${NC}"
        for phase in "${FAILED_PHASES[@]}"; do
            echo -e "    ${RED}✗ ${phase}${NC}"
        done
    fi

    echo ""
    echo "  Next Steps:"
    echo "    1. Transfer project to offline server:"
    echo "       rsync -avz ${SCRIPT_DIR}/ user@offline-server:/path/to/project/"
    echo ""
    echo "    2. Run cluster setup on offline server:"
    echo "       sudo ./setup_cluster_full_multihead_offline.sh"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    오프라인 패키지 통합 수집 (OS 자동 감지)               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    check_internet
    check_disk_space

    log_info "Detected OS:      Ubuntu ${OS_VERSION} (${OS_CODENAME})"
    log_info "Package Dir:      ${OFFLINE_PKG_DIR}"
    log_info "Slurm Version:    ${SLURM_VERSION}"
    echo ""

    if [[ "$APT_ONLY" == "true" ]]; then
        log_info "Mode: APT packages only"
    else
        log_info "Mode: Full collection (APT + Slurm + Python + GPU + Monitoring + Munge)"
    fi

    confirm_proceed

    # Phase 1: APT 패키지 (항상 실행)
    if phase_apt_packages; then
        PHASE_SUCCESS=$((PHASE_SUCCESS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        FAILED_PHASES+=("Phase 1: APT packages")
    fi
    echo ""

    if [[ "$APT_ONLY" == "true" ]]; then
        print_summary
        return
    fi

    # Phase 2: Slurm 빌드
    if phase_slurm_build; then
        PHASE_SUCCESS=$((PHASE_SUCCESS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        FAILED_PHASES+=("Phase 2: Slurm build")
    fi
    echo ""

    # Phase 3: Python wheels
    if phase_python_wheels; then
        PHASE_SUCCESS=$((PHASE_SUCCESS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        FAILED_PHASES+=("Phase 3: Python wheels")
    fi
    echo ""

    # Phase 4: GPU
    if phase_gpu_packages; then
        PHASE_SUCCESS=$((PHASE_SUCCESS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        FAILED_PHASES+=("Phase 4: GPU packages")
    fi
    echo ""

    # Phase 5: Monitoring
    if phase_monitoring; then
        PHASE_SUCCESS=$((PHASE_SUCCESS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        FAILED_PHASES+=("Phase 5: Monitoring")
    fi
    echo ""

    # Phase 6: Munge
    if phase_munge_key; then
        PHASE_SUCCESS=$((PHASE_SUCCESS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        FAILED_PHASES+=("Phase 6: Munge key")
    fi
    echo ""

    print_summary
}

main "$@"
