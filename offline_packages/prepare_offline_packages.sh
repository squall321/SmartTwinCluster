#!/bin/bash
################################################################################
# 오프라인 패키지 통합 준비 스크립트
#
# 설명:
#   오프라인 클러스터 설치를 위한 모든 패키지를 준비합니다.
#
# 기능:
#   - Slurm 프리빌드 패키징
#   - APT 패키지 수집
#   - 로컬 APT 미러 구축 (선택)
#   - Munge 키 생성 및 패키징
#   - 모든 패키지 통합 tarball 생성
#
# 요구사항:
#   - 인터넷 연결 (헤드 노드에서만, 1회 실행)
#   - 최소 30GB 디스크 공간
#
# 사용법:
#   sudo ./prepare_offline_packages.sh [OPTIONS]
#
# 옵션:
#   --all                모든 서비스 패키징
#   --slurm-only         Slurm만 패키징
#   --setup-apt-mirror   로컬 APT 미러 구축
#   --skip-slurm-build   Slurm 빌드 건너뛰기
#   --output-dir PATH    출력 디렉토리 (기본: .)
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
CYAN='\033[0;36m'
NC='\033[0m'

# 기본값
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}"
PACKAGE_ALL=false
SLURM_ONLY=false
SETUP_APT_MIRROR=false
SKIP_SLURM_BUILD=false

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase() { echo -e "${CYAN}[PHASE $1]${NC} $2"; }

# 도움말
show_help() {
    head -n 30 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# 인자 파싱
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                PACKAGE_ALL=true
                shift
                ;;
            --slurm-only)
                SLURM_ONLY=true
                shift
                ;;
            --setup-apt-mirror)
                SETUP_APT_MIRROR=true
                shift
                ;;
            --skip-slurm-build)
                SKIP_SLURM_BUILD=true
                shift
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
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

    # 기본값: --all
    if [[ "$PACKAGE_ALL" == "false" ]] && [[ "$SLURM_ONLY" == "false" ]]; then
        PACKAGE_ALL=true
    fi
}

# Root 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# 인터넷 연결 확인
check_internet() {
    log_info "Checking internet connection..."

    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_success "Internet connection available"
    else
        log_error "No internet connection"
        log_error "This script requires internet to download packages"
        exit 1
    fi
}

# 디스크 공간 확인
check_disk_space() {
    log_info "Checking disk space..."

    local available_gb=$(df -BG "$OUTPUT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ $available_gb -lt 30 ]]; then
        log_warning "Low disk space: ${available_gb}GB available"
        log_warning "Recommended: 30GB minimum"

        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Disk space: ${available_gb}GB available"
    fi
}

# Phase 1: Slurm 프리빌드
build_slurm() {
    log_phase "1" "Building Slurm prebuilt package"

    if [[ "$SKIP_SLURM_BUILD" == "true" ]]; then
        log_warning "Skipping Slurm build (--skip-slurm-build)"
        return 0
    fi

    local slurm_build_script="${SCRIPT_DIR}/slurm/build_slurm_package.sh"

    if [[ ! -f "$slurm_build_script" ]]; then
        log_error "Slurm build script not found: $slurm_build_script"
        return 1
    fi

    chmod +x "$slurm_build_script"

    if bash "$slurm_build_script" --output-dir "${SCRIPT_DIR}/slurm"; then
        log_success "Slurm prebuilt package created"
    else
        log_error "Slurm build failed"
        return 1
    fi
}

# Phase 2: APT 패키지 수집
collect_apt_packages() {
    log_phase "2" "Collecting APT packages"

    local collect_script="${SCRIPT_DIR}/collect_apt_packages.sh"

    if [[ ! -f "$collect_script" ]]; then
        log_error "APT collection script not found: $collect_script"
        return 1
    fi

    chmod +x "$collect_script"

    local service="all"
    if [[ "$SLURM_ONLY" == "true" ]]; then
        service="slurm"
    fi

    if bash "$collect_script" --service "$service" --output-dir "${SCRIPT_DIR}/apt_packages"; then
        log_success "APT packages collected"
    else
        log_error "APT package collection failed"
        return 1
    fi
}

# Phase 3: Munge 키 생성
create_munge_key() {
    log_phase "3" "Creating Munge authentication key"

    local munge_dir="${SCRIPT_DIR}/munge"
    mkdir -p "$munge_dir"

    # Munge 설치 확인
    if ! command -v mungekey &> /dev/null; then
        log_info "Installing Munge..."
        apt-get update
        apt-get install -y munge
    fi

    # Munge 키 생성
    if [[ ! -f "${munge_dir}/munge.key" ]]; then
        log_info "Generating Munge key..."

        # 임시로 /etc/munge에 생성
        if [[ ! -f /etc/munge/munge.key ]]; then
            sudo -u munge mungekey -c -f || mungekey -c -f
        fi

        # 복사
        cp /etc/munge/munge.key "${munge_dir}/"
        chmod 400 "${munge_dir}/munge.key"

        log_success "Munge key created"
    else
        log_info "Munge key already exists"
    fi

    # Munge 배포 스크립트 생성
    cat > "${munge_dir}/deploy_munge.sh" << 'EOFMUNGE'
#!/bin/bash
# Munge 오프라인 배포 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Deploying Munge..."

# Munge 사용자 생성
if ! id munge &>/dev/null; then
    groupadd -g 1002 munge
    useradd -u 1002 -g 1002 -s /bin/false munge
fi

# 키 설치
mkdir -p /etc/munge
cp "${SCRIPT_DIR}/munge.key" /etc/munge/
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

# 서비스 시작
systemctl enable munge
systemctl restart munge

echo "✅ Munge deployed successfully"
EOFMUNGE

    chmod +x "${munge_dir}/deploy_munge.sh"

    log_success "Munge key and deployment script ready"
}

# Phase 4: 로컬 APT 미러 (선택)
setup_apt_mirror() {
    if [[ "$SETUP_APT_MIRROR" == "false" ]]; then
        log_info "Skipping APT mirror setup (use --setup-apt-mirror to enable)"
        return 0
    fi

    log_phase "4" "Setting up local APT mirror"

    local mirror_script="${SCRIPT_DIR}/setup_local_apt_mirror.sh"

    if [[ ! -f "$mirror_script" ]]; then
        log_error "APT mirror script not found: $mirror_script"
        return 1
    fi

    chmod +x "$mirror_script"

    if bash "$mirror_script" --mirror-dir "${SCRIPT_DIR}/apt_mirror"; then
        log_success "APT mirror setup complete"
    else
        log_warning "APT mirror setup failed (continuing anyway)"
    fi
}

# Phase 5: Prometheus & Node Exporter 다운로드
download_monitoring_tools() {
    log_phase "5" "Downloading Prometheus & Node Exporter"

    local monitoring_dir="${SCRIPT_DIR}/monitoring"
    mkdir -p "$monitoring_dir"

    # 버전 설정 (GitHub API에서 최신 버전 가져오기 또는 고정 버전 사용)
    local PROMETHEUS_VERSION="2.47.2"
    local NODE_EXPORTER_VERSION="1.7.0"

    # 아키텍처 확인
    local ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) log_error "Unsupported architecture: $ARCH"; return 1 ;;
    esac

    log_info "Downloading for architecture: $ARCH"

    # Prometheus 다운로드
    local prometheus_file="prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
    local prometheus_url="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${prometheus_file}"

    if [[ ! -f "${monitoring_dir}/${prometheus_file}" ]]; then
        log_info "Downloading Prometheus ${PROMETHEUS_VERSION}..."
        if wget -q --show-progress -O "${monitoring_dir}/${prometheus_file}" "$prometheus_url"; then
            log_success "Prometheus downloaded"
        else
            log_error "Failed to download Prometheus"
            return 1
        fi
    else
        log_info "Prometheus already downloaded"
    fi

    # Node Exporter 다운로드
    local node_exporter_file="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
    local node_exporter_url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${node_exporter_file}"

    if [[ ! -f "${monitoring_dir}/${node_exporter_file}" ]]; then
        log_info "Downloading Node Exporter ${NODE_EXPORTER_VERSION}..."
        if wget -q --show-progress -O "${monitoring_dir}/${node_exporter_file}" "$node_exporter_url"; then
            log_success "Node Exporter downloaded"
        else
            log_error "Failed to download Node Exporter"
            return 1
        fi
    else
        log_info "Node Exporter already downloaded"
    fi

    # 배포 스크립트 생성
    cat > "${monitoring_dir}/deploy_monitoring.sh" << 'EOFMONITORING'
#!/bin/bash
# Prometheus & Node Exporter 오프라인 배포 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="${1:-/opt/dashboard}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Deploying Prometheus & Node Exporter..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Prometheus 설치
PROMETHEUS_DIR="$DASHBOARD_DIR/prometheus_9090"
mkdir -p "$PROMETHEUS_DIR"

prometheus_tarball=$(find "$SCRIPT_DIR" -name "prometheus-*.tar.gz" | head -1)
if [[ -n "$prometheus_tarball" ]]; then
    echo "📦 Installing Prometheus..."
    tar -xzf "$prometheus_tarball" -C /tmp/
    prometheus_extracted=$(find /tmp -maxdepth 1 -type d -name "prometheus-*" | head -1)

    if [[ -n "$prometheus_extracted" ]]; then
        cp "$prometheus_extracted/prometheus" "$PROMETHEUS_DIR/"
        cp "$prometheus_extracted/promtool" "$PROMETHEUS_DIR/"
        cp -r "$prometheus_extracted/consoles" "$PROMETHEUS_DIR/" 2>/dev/null || true
        cp -r "$prometheus_extracted/console_libraries" "$PROMETHEUS_DIR/" 2>/dev/null || true

        # 기본 설정 파일 생성 (없는 경우)
        if [[ ! -f "$PROMETHEUS_DIR/prometheus.yml" ]]; then
            cat > "$PROMETHEUS_DIR/prometheus.yml" << 'PROMCFG'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'dashboard-backend'
    static_configs:
      - targets: ['localhost:5010']
    metrics_path: '/metrics'
PROMCFG
        fi

        chmod +x "$PROMETHEUS_DIR/prometheus" "$PROMETHEUS_DIR/promtool"
        rm -rf "$prometheus_extracted"
        echo "✅ Prometheus installed to $PROMETHEUS_DIR"
    fi
else
    echo "⚠️  Prometheus tarball not found"
fi

# Node Exporter 설치
NODE_EXPORTER_DIR="$DASHBOARD_DIR/node_exporter_9100"
mkdir -p "$NODE_EXPORTER_DIR"

node_exporter_tarball=$(find "$SCRIPT_DIR" -name "node_exporter-*.tar.gz" | head -1)
if [[ -n "$node_exporter_tarball" ]]; then
    echo "📦 Installing Node Exporter..."
    tar -xzf "$node_exporter_tarball" -C /tmp/
    node_exporter_extracted=$(find /tmp -maxdepth 1 -type d -name "node_exporter-*" | head -1)

    if [[ -n "$node_exporter_extracted" ]]; then
        cp "$node_exporter_extracted/node_exporter" "$NODE_EXPORTER_DIR/"
        chmod +x "$NODE_EXPORTER_DIR/node_exporter"
        rm -rf "$node_exporter_extracted"
        echo "✅ Node Exporter installed to $NODE_EXPORTER_DIR"
    fi
else
    echo "⚠️  Node Exporter tarball not found"
fi

# 시작 스크립트 생성
cat > "$PROMETHEUS_DIR/start.sh" << 'STARTPROM'
#!/bin/bash
cd "$(dirname "$0")"
./prometheus --config.file=prometheus.yml --storage.tsdb.path=./data &
echo $! > .prometheus.pid
echo "Prometheus started (PID: $(cat .prometheus.pid))"
STARTPROM
chmod +x "$PROMETHEUS_DIR/start.sh"

cat > "$NODE_EXPORTER_DIR/start.sh" << 'STARTNODE'
#!/bin/bash
cd "$(dirname "$0")"
./node_exporter &
echo $! > .node_exporter.pid
echo "Node Exporter started (PID: $(cat .node_exporter.pid))"
STARTNODE
chmod +x "$NODE_EXPORTER_DIR/start.sh"

echo ""
echo "✅ Monitoring tools deployed successfully!"
echo ""
echo "To start manually:"
echo "  $PROMETHEUS_DIR/start.sh"
echo "  $NODE_EXPORTER_DIR/start.sh"
EOFMONITORING

    chmod +x "${monitoring_dir}/deploy_monitoring.sh"

    log_success "Monitoring tools downloaded and deploy script created"
}

# Phase 6: README 생성
create_readme() {
    log_phase "6" "Creating README"

    cat > "${SCRIPT_DIR}/README_OFFLINE.txt" << 'EOFREADME'
═══════════════════════════════════════════════════════════════
    오프라인 클러스터 설치 패키지
═══════════════════════════════════════════════════════════════

이 디렉토리에는 오프라인 환경에서 HPC 클러스터를 설치하기 위한
모든 필요한 패키지가 포함되어 있습니다.

디렉토리 구조:
───────────────────────────────────────────────────────────────
  slurm/               Slurm 프리빌드 패키지
    └─ slurm-*-prebuilt.tar.gz
    └─ build_slurm_package.sh

  apt_packages/        모든 APT .deb 패키지
    └─ *.deb (수백 개)
    └─ install_offline_packages.sh

  munge/               Munge 인증 키
    └─ munge.key
    └─ deploy_munge.sh

  apt_mirror/          로컬 APT 미러 (선택사항)
    └─ mirror/
    └─ setup_client.sh

  system_deps/         기타 시스템 의존성


설치 방법:
───────────────────────────────────────────────────────────────

【헤드 노드】

1. 전체 디렉토리를 헤드 노드로 복사:
   rsync -avz offline_packages/ user@headnode:/opt/offline_packages/

2. 메인 설치 스크립트 실행:
   cd /opt/offline_packages/..
   sudo ./setup_cluster_full_multihead_offline.sh

3. 또는 수동 설치:
   a. APT 패키지 설치:
      cd apt_packages/
      sudo bash install_offline_packages.sh

   b. Slurm 배포:
      cd slurm/
      tar -xzf slurm-*-prebuilt.tar.gz
      sudo bash deploy_slurm.sh

   c. Munge 배포:
      cd munge/
      sudo bash deploy_munge.sh


【계산 노드】

헤드 노드에서 자동 배포:
  cd /opt/offline_packages/..
  sudo ./offline_deploy/deploy_to_compute_node.sh --config my_multihead_cluster.yaml


로컬 APT 미러 사용 (선택):
───────────────────────────────────────────────────────────────

헤드 노드에서 APT 미러 서비스 시작:
  sudo systemctl start apache2

각 계산 노드에서:
  bash /opt/offline_packages/apt_mirror/setup_client.sh


문제 해결:
───────────────────────────────────────────────────────────────

1. 패키지 의존성 오류:
   sudo apt-get install -f

2. Munge 인증 실패:
   sudo systemctl restart munge
   munge -n | unmunge

3. Slurm 서비스 시작 실패:
   journalctl -u slurmctld -n 50

═══════════════════════════════════════════════════════════════
EOFREADME

    log_success "README created: ${SCRIPT_DIR}/README_OFFLINE.txt"
}

# Phase 6: 통합 tarball 생성
create_master_tarball() {
    log_phase "6" "Creating master tarball"

    local tarball_name="offline_cluster_packages_$(date +%Y%m%d).tar.gz"
    local tarball_path="/tmp/${tarball_name}"

    log_info "Creating: $tarball_path"
    log_warning "This may take 10-20 minutes..."

    cd "$(dirname "$SCRIPT_DIR")"

    tar -czf "$tarball_path" \
        --exclude='*.log' \
        --exclude='tmp/*' \
        "$(basename "$SCRIPT_DIR")"

    if [[ -f "$tarball_path" ]]; then
        local size=$(du -sh "$tarball_path" | cut -f1)
        log_success "Master tarball created: $tarball_path ($size)"

        # 체크섬
        md5sum "$tarball_path" > "${tarball_path}.md5"
        log_info "MD5: ${tarball_path}.md5"
    else
        log_error "Failed to create master tarball"
        return 1
    fi
}

# 요약
print_summary() {
    local slurm_tarball=$(find "${SCRIPT_DIR}/slurm" -name "slurm-*-prebuilt.tar.gz" 2>/dev/null | head -1)
    local apt_count=$(find "${SCRIPT_DIR}/apt_packages" -name "*.deb" 2>/dev/null | wc -l)
    local total_size=$(du -sh "$SCRIPT_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          오프라인 패키지 준비 완료!                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Package Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Slurm:           $(basename "$slurm_tarball" 2>/dev/null || echo "N/A")"
    echo "  APT Packages:    $apt_count .deb files"
    echo "  Munge:           ✓ Key generated"
    echo "  Total Size:      $total_size"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Next Steps:"
    echo "  1. Transfer to offline environment:"
    echo "     rsync -avz ${SCRIPT_DIR}/ user@offline-cluster:/opt/offline_packages/"
    echo ""
    echo "  2. Or use master tarball:"
    echo "     scp /tmp/offline_cluster_packages_*.tar.gz user@offline-cluster:/tmp/"
    echo ""
    echo "  3. Run offline installation:"
    echo "     sudo ./setup_cluster_full_multihead_offline.sh"
    echo ""
    log_success "All packages ready for offline deployment!"
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          오프라인 패키지 통합 준비                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    check_internet
    check_disk_space

    log_info "Mode: $(if [[ "$PACKAGE_ALL" == "true" ]]; then echo "All services"; else echo "Slurm only"; fi)"
    log_info "Output: $SCRIPT_DIR"
    echo ""

    read -p "Continue with package preparation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled by user"
        exit 0
    fi

    # 실행
    build_slurm || { log_error "Phase 1 failed"; exit 1; }
    echo ""

    collect_apt_packages || { log_error "Phase 2 failed"; exit 1; }
    echo ""

    create_munge_key || { log_error "Phase 3 failed"; exit 1; }
    echo ""

    setup_apt_mirror
    echo ""

    create_readme
    echo ""

    create_master_tarball
    echo ""

    print_summary

    log_success "Offline packages ready!"
}

main "$@"
