#!/bin/bash
################################################################################
# Phase 10: Compute Node Deployment
#
# Description:
#   Deploys offline packages and services to all compute nodes.
#   This phase should run after all controller/headnode setup is complete.
#
# Deployed Components:
#   - APT packages (offline)
#   - Slurm (slurmd)
#   - Munge authentication
#   - GlusterFS client + autofs
#
# Usage:
#   sudo ./phase10_compute_deploy.sh --config <path_to_yaml>
#
# Options:
#   --config PATH        Path to YAML configuration file
#   --node HOSTNAME      Deploy to specific node only
#   --parallel N         Number of parallel deployments (default: 3)
#   --dry-run            Preview actions without executing
#   --force              Force deployment even if already configured
#   --yes, -y            Skip confirmation prompts
#   --help               Show this help message
#
# Author: Claude Code
# Date: 2025-01-05
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# OS 감지 기반 오프라인 패키지 디렉토리 설정
source "${PROJECT_ROOT}/cluster/utils/detect_os.sh"
detect_os_version
set_offline_pkg_dir "$PROJECT_ROOT"

# Default values
CONFIG_PATH=""
SPECIFIC_NODE=""
PARALLEL=3
DRY_RUN=false
FORCE=false
AUTO_YES=false

# Log file
LOG_DIR="/var/log/cluster_setup"
LOG_FILE="${LOG_DIR}/phase10_compute_deploy.log"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $1"; }
log_phase() { echo -e "${CYAN}[PHASE 10]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${CYAN}[PHASE 10]${NC} $1"; }

# SSH with retry and exponential backoff
ssh_with_retry() {
    local max_retries=5
    local delay=2
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        if "$@" ; then
            return 0
        fi
        if [[ $attempt -eq $max_retries ]]; then
            return 1
        fi
        log_warning "SSH attempt $attempt/$max_retries failed, retrying in ${delay}s..."
        sleep "$delay"
        delay=$(( delay * 2 ))
        attempt=$(( attempt + 1 ))
    done
    return 1
}

# Show help
show_help() {
    grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//' | head -30
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_PATH="$2"
                shift 2
                ;;
            --node)
                SPECIFIC_NODE="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL="$2"
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
            --yes|-y)
                AUTO_YES=true
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

    # Convert to absolute path
    if [[ -n "$CONFIG_PATH" && "${CONFIG_PATH:0:1}" != "/" ]]; then
        CONFIG_PATH="$(cd "$(dirname "$CONFIG_PATH")" 2>/dev/null && pwd)/$(basename "$CONFIG_PATH")"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Initialize log file
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/phase10_compute_deploy.log"

    # Check config
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error "Configuration file not found: $CONFIG_PATH"
        exit 1
    fi

    # Check offline packages directory
    local pkg_dir="${OFFLINE_PKG_DIR}"
    if [[ ! -d "$pkg_dir" ]]; then
        log_error "Offline packages directory not found: $pkg_dir"
        log_error "Run package collection scripts first"
        exit 1
    fi

    # Check for required package directories
    local required_dirs=("apt_packages" "slurm" "munge")
    local missing_dirs=()
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$pkg_dir/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_warning "Missing package directories: ${missing_dirs[*]}"
        log_warning "Some components may not be deployed"
    fi

    # Check Python3
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# SSH/sshpass configuration (exported for parallel deployment)
export SSH_PASSWORD=""
export HAS_SSHPASS=false
export SSHPASS=""

setup_ssh_auth() {
    log_info "Setting up SSH authentication..."

    # Get ssh_password from YAML
    SSH_PASSWORD=$(python3 << EOPY
import yaml
with open('$CONFIG_PATH', 'r') as f:
    config = yaml.safe_load(f)
print(config.get('cluster_info', {}).get('ssh_password', ''))
EOPY
    )
    export SSH_PASSWORD

    # Check sshpass
    if command -v sshpass &> /dev/null; then
        HAS_SSHPASS=true
    else
        log_info "Installing sshpass..."
        apt-get install -y sshpass > /dev/null 2>&1 || yum install -y sshpass > /dev/null 2>&1 || true
        if command -v sshpass &> /dev/null; then
            HAS_SSHPASS=true
        fi
    fi
    export HAS_SSHPASS

    if [[ -n "$SSH_PASSWORD" ]]; then
        export SSHPASS="$SSH_PASSWORD"
        log_success "SSH password loaded from YAML config"
        if [[ "$HAS_SSHPASS" == "true" ]]; then
            log_success "sshpass available - passwordless remote sudo enabled"
        else
            log_warning "sshpass not available - may need manual password input"
        fi
    else
        log_info "No ssh_password in YAML - assuming passwordless sudo is configured"
    fi
}

# Get GlusterFS configuration
get_glusterfs_config() {
    python3 << EOPY
import yaml
import json

with open('$CONFIG_PATH', 'r') as f:
    config = yaml.safe_load(f)

# GlusterFS settings
gluster = config.get('shared_storage', {}).get('glusterfs', {})
mount_point = gluster.get('mount_point', '/mnt/gluster')
volume_name = gluster.get('volume_name', 'shared_data')

# First controller IP (GlusterFS server)
controllers = config.get('nodes', {}).get('controllers', [])
gluster_server = controllers[0]['ip_address'] if controllers else ''

result = {
    'mount_point': mount_point,
    'volume_name': volume_name,
    'gluster_server': gluster_server
}

print(json.dumps(result))
EOPY
}

# Deploy to a single node
deploy_to_node() {
    local node_hostname="$1"
    local node_ip="$2"
    local node_user="$3"
    local gluster_server="$4"
    local gluster_volume="$5"
    local gluster_mount="$6"
    local pkg_dir="${OFFLINE_PKG_DIR}"

    log_info "[$node_hostname] Starting deployment..."

    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[$node_hostname] DRY-RUN: Would deploy to $node_user@$node_ip"
        log_warning "[$node_hostname] DRY-RUN: GlusterFS: $gluster_server:/$gluster_volume -> $gluster_mount"
        return 0
    fi

    # SSH command construction
    local ssh_cmd="ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=10"
    local ssh_cmd_stdin="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
    local scp_cmd="scp -o StrictHostKeyChecking=no"

    if [[ -n "$SSH_PASSWORD" && "$HAS_SSHPASS" == "true" ]]; then
        export SSHPASS="$SSH_PASSWORD"
        ssh_cmd="sshpass -e ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=10"
        ssh_cmd_stdin="sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
        scp_cmd="sshpass -e scp -o StrictHostKeyChecking=no"
    fi

    # Test SSH connection with retry
    if ! ssh_with_retry $ssh_cmd "$node_user@$node_ip" "echo OK" &>/dev/null; then
        log_error "[$node_hostname] SSH connection failed after retries"
        return 1
    fi
    log_success "[$node_hostname] SSH connection OK"

    # 원격 $HOME 절대경로 조회 (scp는 ~/$HOME 확장 보장 안 됨)
    local REMOTE_HOME
    REMOTE_HOME=$($ssh_cmd "$node_user@$node_ip" 'echo $HOME' 2>/dev/null | tr -d '\r')
    if [[ -z "$REMOTE_HOME" ]]; then
        log_error "[$node_hostname] Failed to resolve remote \$HOME"
        return 1
    fi
    local REMOTE_PKG_DIR="$REMOTE_HOME/offline_packages"

    # Create remote directory
    $ssh_cmd "$node_user@$node_ip" "mkdir -p $REMOTE_PKG_DIR" || true

    log_info "[$node_hostname] Transferring packages..."

    # Transfer packages (skip munge.key - will copy from controller)
    for subdir in "$pkg_dir"/*; do
        [[ ! -e "$subdir" ]] && continue
        local name=$(basename "$subdir")

        if [[ "$name" == "munge" ]]; then
            # Only deploy_munge.sh
            $ssh_cmd "$node_user@$node_ip" "mkdir -p $REMOTE_PKG_DIR/munge" || true
            if [[ -f "$subdir/deploy_munge.sh" ]]; then
                $scp_cmd "$subdir/deploy_munge.sh" "$node_user@$node_ip:$REMOTE_PKG_DIR/munge/" || true
            fi
            continue
        fi

        if [[ "$name" == "slurm" ]]; then
            $ssh_cmd "$node_user@$node_ip" "mkdir -p $REMOTE_PKG_DIR/slurm" || true
            for tarfile in "$subdir"/*.tar.gz; do
                [[ -f "$tarfile" ]] && $scp_cmd "$tarfile" "$node_user@$node_ip:$REMOTE_PKG_DIR/slurm/" || true
            done
            for shfile in "$subdir"/*.sh; do
                [[ -f "$shfile" ]] && $scp_cmd "$shfile" "$node_user@$node_ip:$REMOTE_PKG_DIR/slurm/" || true
            done
            continue
        fi

        $scp_cmd -r "$subdir" "$node_user@$node_ip:$REMOTE_PKG_DIR/" 2>/dev/null || {
            log_warning "[$node_hostname] Failed to transfer $name"
        }
    done

    # Transfer slurm.conf from controller
    log_info "[$node_hostname] Transferring slurm.conf from controller..."
    local SLURM_CONF_LOCAL="/etc/slurm/slurm.conf"
    if [[ -f "$SLURM_CONF_LOCAL" ]]; then
        $scp_cmd "$SLURM_CONF_LOCAL" "$node_user@$node_ip:$REMOTE_PKG_DIR/slurm.conf" || {
            log_warning "[$node_hostname] Failed to transfer slurm.conf"
        }
    else
        log_warning "[$node_hostname] Controller slurm.conf not found"
    fi

    # Transfer munge.key from controller (보안: /tmp 대신 직접 /etc/munge로 전송)
    log_info "[$node_hostname] Transferring munge.key from controller..."
    local MUNGE_KEY_LOCAL="/etc/munge/munge.key"
    if /usr/bin/sudo test -f "$MUNGE_KEY_LOCAL"; then
        $ssh_cmd "$node_user@$node_ip" 'sudo mkdir -p /etc/munge && sudo chmod 700 /etc/munge' || true
        # munge 유저가 없으면 패키지가 아직 설치 안 된 상태 → root:root로 임시 저장
        # 나중에 install_offline_packages.sh가 munge 설치 후 deploy_munge.sh가 정상 chown
        local _munge_chown_cmd
        if $ssh_cmd "$node_user@$node_ip" 'id munge' &>/dev/null; then
            _munge_chown_cmd='sudo chown munge:munge /etc/munge/munge.key'
        else
            log_info "[$node_hostname] munge 유저 미존재 — 패키지 설치 후 chown 예정"
            _munge_chown_cmd='sudo chown root:root /etc/munge/munge.key'
        fi
        /usr/bin/sudo cat "$MUNGE_KEY_LOCAL" | $ssh_cmd_stdin "$node_user@$node_ip" \
            "sudo tee /etc/munge/munge.key > /dev/null && $_munge_chown_cmd && sudo chmod 400 /etc/munge/munge.key" || {
            log_warning "[$node_hostname] Failed to transfer munge.key"
        }
        # deploy 스크립트용 백업 복사 (원격 \$HOME 절대경로 사용)
        local _remote_home
        _remote_home=$($ssh_cmd "$node_user@$node_ip" 'echo $HOME' 2>/dev/null | tr -d '\r')
        if [[ -n "$_remote_home" ]]; then
            $ssh_cmd "$node_user@$node_ip" "mkdir -p $_remote_home/offline_packages/munge" || true
            $ssh_cmd "$node_user@$node_ip" "sudo cp /etc/munge/munge.key $_remote_home/offline_packages/munge/munge.key 2>/dev/null" || true
        fi
    else
        log_warning "[$node_hostname] Controller munge.key not found"
    fi

    log_success "[$node_hostname] Packages transferred"

    # Remote installation
    log_info "[$node_hostname] Installing packages..."

    local encoded_pass=""
    if [[ -n "$SSH_PASSWORD" ]]; then
        encoded_pass=$(echo -n "$SSH_PASSWORD" | base64)
    fi

    $ssh_cmd_stdin "$node_user@$node_ip" bash -s "$gluster_server" "$gluster_volume" "$gluster_mount" "$encoded_pass" << 'EOFREMOTE'
set -e

GLUSTER_SERVER="$1"
GLUSTER_VOLUME="$2"
GLUSTER_MOUNT="$3"
SUDO_PASS_B64="$4"
PKG_DIR="$HOME/offline_packages"

# Decode sudo password
SUDO_PASS=""
if [[ -n "$SUDO_PASS_B64" ]]; then
    SUDO_PASS=$(echo "$SUDO_PASS_B64" | base64 -d)
fi

# Sudo wrapper function
run_sudo() {
    if [[ -n "$SUDO_PASS" ]]; then
        echo "$SUDO_PASS" | sudo -S "$@"
    else
        sudo "$@"
    fi
}

echo "═══════════════════════════════════════════════════════════"
echo "  Offline Package Installation (Phase 10: Compute Node)"
echo "  Package directory: $PKG_DIR"
echo "═══════════════════════════════════════════════════════════"

# 1. APT packages
if [[ -f "$PKG_DIR/apt_packages/install_offline_packages.sh" ]]; then
    echo ""
    echo "Step 1: Installing APT packages..."
    cd "$PKG_DIR/apt_packages"
    run_sudo bash install_offline_packages.sh
else
    echo "WARNING: APT packages not found"
fi

# 2. Slurm deployment
SLURM_PKG=$(ls "$PKG_DIR/slurm"/slurm-*-prebuilt.tar.gz 2>/dev/null | head -1 || true)
if [[ -n "$SLURM_PKG" && -f "$SLURM_PKG" ]]; then
    echo ""
    echo "Step 2: Deploying Slurm..."
    cd "$PKG_DIR/slurm"
    tar -xzf "$SLURM_PKG" --exclude='*.sh'
    if [[ -f "deploy_slurm.sh" ]]; then
        run_sudo bash deploy_slurm.sh
    fi
else
    echo "WARNING: Slurm package not found"
fi

# 2.5. slurm.conf from controller
echo ""
echo "Step 2.5: Configuring slurm.conf..."
SLURM_CONF_SRC="$PKG_DIR/slurm.conf"
if [[ -f "$SLURM_CONF_SRC" ]]; then
    run_sudo mkdir -p /etc/slurm /usr/local/slurm/etc
    run_sudo cp "$SLURM_CONF_SRC" /etc/slurm/slurm.conf
    run_sudo cp "$SLURM_CONF_SRC" /usr/local/slurm/etc/slurm.conf
    run_sudo chown slurm:slurm /etc/slurm/slurm.conf /usr/local/slurm/etc/slurm.conf 2>/dev/null || true
    run_sudo chmod 644 /etc/slurm/slurm.conf /usr/local/slurm/etc/slurm.conf
    echo "  ✓ slurm.conf installed"
else
    echo "  WARNING: slurm.conf not found"
fi

# 3. Munge
if [[ -f "$PKG_DIR/munge/deploy_munge.sh" ]]; then
    echo ""
    echo "Step 3: Deploying Munge..."
    cd "$PKG_DIR/munge"
    run_sudo bash deploy_munge.sh
else
    echo "WARNING: Munge package not found"
fi

# 4. GlusterFS client + autofs
echo ""
echo "Step 4: Setting up GlusterFS client with autofs..."

if [[ -n "$GLUSTER_SERVER" ]] && [[ -n "$GLUSTER_VOLUME" ]]; then
    # Check glusterfs-client
    if ! dpkg -l | grep -q glusterfs-client; then
        echo "  WARNING: glusterfs-client not installed"
        if ls "$PKG_DIR/apt_packages"/glusterfs*.deb &>/dev/null; then
            run_sudo dpkg -i "$PKG_DIR/apt_packages"/glusterfs*.deb 2>/dev/null || true
        fi
    else
        echo "  ✓ glusterfs-client already installed"
    fi

    # Check autofs
    if ! dpkg -l | grep -q autofs; then
        if ls "$PKG_DIR/apt_packages"/autofs*.deb &>/dev/null; then
            run_sudo dpkg -i "$PKG_DIR/apt_packages"/autofs*.deb 2>/dev/null || true
        fi
    else
        echo "  ✓ autofs already installed"
    fi

    # Configure autofs
    AUTOFS_MASTER="/etc/auto.master"
    AUTOFS_GLUSTER="/etc/auto.gluster"
    MOUNT_PARENT=$(dirname "$GLUSTER_MOUNT")
    MOUNT_NAME=$(basename "$GLUSTER_MOUNT")

    if ! grep -q "auto.gluster" "$AUTOFS_MASTER" 2>/dev/null; then
        echo "" | run_sudo tee -a "$AUTOFS_MASTER" > /dev/null
        echo "# GlusterFS autofs mount (Phase 10)" | run_sudo tee -a "$AUTOFS_MASTER" > /dev/null
        echo "$MOUNT_PARENT /etc/auto.gluster --timeout=300 --ghost" | run_sudo tee -a "$AUTOFS_MASTER" > /dev/null
    fi

    run_sudo tee "$AUTOFS_GLUSTER" > /dev/null << EOFAUTOFS
# GlusterFS autofs map
$MOUNT_NAME  -fstype=glusterfs,log-level=WARNING,backup-volfile-servers=$GLUSTER_SERVER  $GLUSTER_SERVER:/$GLUSTER_VOLUME
EOFAUTOFS

    run_sudo systemctl enable autofs
    run_sudo systemctl restart autofs

    echo "  ✓ autofs configured for GlusterFS"

    # Test mount
    if ls "$GLUSTER_MOUNT" &>/dev/null; then
        echo "  ✓ GlusterFS mount accessible at $GLUSTER_MOUNT"
    else
        echo "  WARNING: GlusterFS mount test failed (will auto-mount on access)"
    fi

    # Create /shared symlink to GlusterFS mount point
    if [[ ! -L /shared ]]; then
        run_sudo rm -rf /shared 2>/dev/null || true
        run_sudo ln -sf "$GLUSTER_MOUNT" /shared
        echo "  ✓ /shared -> $GLUSTER_MOUNT symlink created"
    else
        echo "  ✓ /shared symlink already exists"
    fi
else
    echo "  Skipping GlusterFS setup (no server configured)"
fi

# 5. Start slurmd service
echo ""
echo "Step 5: Starting slurmd service..."

# slurmd.service 생성/재생성 (잘못된 경로나 Type=forking 문제 방지)
SLURMD_SERVICE="/etc/systemd/system/slurmd.service"
SLURMD_NEEDS_UPDATE=false

# 서비스 파일이 없거나, /usr/sbin 경로 사용하거나, Type=forking이면 재생성
if [[ ! -f "$SLURMD_SERVICE" ]]; then
    SLURMD_NEEDS_UPDATE=true
elif grep -q "/usr/sbin/slurmd" "$SLURMD_SERVICE" 2>/dev/null; then
    echo "  ℹ slurmd.service uses /usr/sbin path, recreating..."
    SLURMD_NEEDS_UPDATE=true
elif grep -q "Type=forking" "$SLURMD_SERVICE" 2>/dev/null; then
    echo "  ℹ slurmd.service has Type=forking, recreating..."
    SLURMD_NEEDS_UPDATE=true
fi

if [[ "$SLURMD_NEEDS_UPDATE" == "true" ]]; then
    run_sudo tee "$SLURMD_SERVICE" > /dev/null << 'EOFSVC'
[Unit]
Description=Slurm node daemon
After=network-online.target munge.service
Wants=network-online.target
ConditionPathExists=/etc/slurm/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStart=/usr/local/slurm/sbin/slurmd -D $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOFSVC
    run_sudo systemctl daemon-reload
    echo "  ✓ slurmd.service created/updated"
fi

# Create /run/slurm
run_sudo mkdir -p /run/slurm
run_sudo chown slurm:slurm /run/slurm 2>/dev/null || true

# Unmask slurmd if masked (controller에서 mask되었을 수 있음)
run_sudo systemctl unmask slurmd 2>/dev/null || true

# Start slurmd
run_sudo systemctl stop slurmd 2>/dev/null || true
sleep 1
run_sudo systemctl daemon-reload
run_sudo systemctl start slurmd
run_sudo systemctl enable slurmd 2>/dev/null || true

if systemctl is-active --quiet slurmd; then
    echo "  ✓ slurmd started successfully"
    SLURMD_VERSION=$(/usr/local/slurm/sbin/slurmd -V 2>/dev/null || echo "unknown")
    echo "  ✓ slurmd version: $SLURMD_VERSION"
else
    echo "  ✗ slurmd failed to start"
    run_sudo journalctl -u slurmd -n 5 --no-pager 2>&1 || true
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ Phase 10: Compute node deployment complete!"
echo "═══════════════════════════════════════════════════════════"
EOFREMOTE

    if [[ $? -eq 0 ]]; then
        log_success "[$node_hostname] Deployment complete!"
        return 0
    else
        log_error "[$node_hostname] Deployment failed"
        return 1
    fi
}

# Deploy to all compute nodes
deploy_all_nodes() {
    local gluster_server="$1"
    local gluster_volume="$2"
    local gluster_mount="$3"

    # Get compute nodes from YAML
    local nodes_list_file="/tmp/phase10_nodes_$$.txt"

    python3 << EOPY > "$nodes_list_file"
import yaml
import sys

try:
    with open('$CONFIG_PATH', 'r') as f:
        config = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: Failed to read config: {e}", file=sys.stderr)
    sys.exit(1)

# compute_nodes
compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
for node in compute_nodes:
    hostname = node.get('hostname', '')
    ip = node.get('ip_address', '')
    user = node.get('ssh_user', 'koopark')
    if hostname and ip:
        print(f"{hostname}|{ip}|{user}")

# viz_nodes (slurmd도 필요)
viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
for node in viz_nodes:
    hostname = node.get('hostname', '')
    ip = node.get('ip_address', '')
    user = node.get('ssh_user', 'koopark')
    if hostname and ip:
        print(f"{hostname}|{ip}|{user}")
EOPY

    if [[ $? -ne 0 ]] || [[ ! -s "$nodes_list_file" ]]; then
        log_error "Failed to extract node list from YAML"
        rm -f "$nodes_list_file"
        return 1
    fi

    local total_nodes
    total_nodes=$(wc -l < "$nodes_list_file")
    total_nodes=${total_nodes//[^0-9]/}

    if [[ -z "$total_nodes" ]] || [[ "$total_nodes" -eq 0 ]]; then
        log_error "No compute nodes found in configuration"
        rm -f "$nodes_list_file"
        return 1
    fi

    log_info "Total compute nodes: $total_nodes"
    log_info "GlusterFS: $gluster_server:/$gluster_volume -> $gluster_mount"

    # Auto-scale parallelism for large clusters (cap at 10)
    if [[ $total_nodes -gt 20 && $PARALLEL -lt 5 ]]; then
        PARALLEL=5
        log_info "Auto-scaled parallelism to $PARALLEL for $total_nodes nodes"
    fi
    if [[ $PARALLEL -gt 10 ]]; then
        PARALLEL=10
        log_warning "Capped parallelism at 10 to avoid SSH overload"
    fi
    log_info "Parallel deployments: $PARALLEL"

    if [[ -n "$SPECIFIC_NODE" ]]; then
        log_info "Deploying to specific node only: $SPECIFIC_NODE"
    fi

    local success_count=0
    local failed_count=0
    local pids=()

    # Deploy to each node
    while IFS='|' read -r hostname ip user; do
        [[ -z "$hostname" ]] && continue

        # Skip if specific node is set and this isn't it
        if [[ -n "$SPECIFIC_NODE" ]] && [[ "$hostname" != "$SPECIFIC_NODE" ]]; then
            continue
        fi

        # Parallel limit
        while [[ ${#pids[@]} -ge $PARALLEL ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[$i]'
                fi
            done
            pids=("${pids[@]}")
            sleep 1
        done

        # Background deployment
        (
            if deploy_to_node "$hostname" "$ip" "$user" "$gluster_server" "$gluster_volume" "$gluster_mount"; then
                echo "SUCCESS:$hostname" >> /tmp/phase10_results_$$.txt
            else
                echo "FAILED:$hostname" >> /tmp/phase10_results_$$.txt
            fi
        ) < /dev/null &
        pids+=($!)

        log_info "Launched deployment for $hostname (PID: $!)"

    done < "$nodes_list_file"

    rm -f "$nodes_list_file"

    # Wait for all deployments
    log_info "Waiting for all deployments to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    # Collect results
    if [[ -f /tmp/phase10_results_$$.txt ]]; then
        success_count=$(grep -c "^SUCCESS:" /tmp/phase10_results_$$.txt 2>/dev/null || true)
        failed_count=$(grep -c "^FAILED:" /tmp/phase10_results_$$.txt 2>/dev/null || true)
        success_count=${success_count//[^0-9]/}
        failed_count=${failed_count//[^0-9]/}
        [[ -z "$success_count" ]] && success_count=0
        [[ -z "$failed_count" ]] && failed_count=0
        rm -f /tmp/phase10_results_$$.txt
    fi

    echo ""
    log_info "Deployment Summary:"
    log_success "  Successful: $success_count nodes"

    if [[ "$failed_count" -gt 0 ]]; then
        log_error "  Failed: $failed_count nodes"
        return 1
    fi

    return 0
}

# Print summary
print_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║      Phase 10: Compute Node Deployment Complete!          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Installed components:"
    echo "  ✓ APT packages (offline)"
    echo "  ✓ Slurm (slurmd)"
    echo "  ✓ Munge authentication"
    echo "  ✓ GlusterFS client + autofs"
    echo ""
    log_info "Verification commands:"
    echo "  - Check Munge: ssh <node> 'munge -n | unmunge'"
    echo "  - Check Slurm: ssh <node> 'slurmd -V'"
    echo "  - Check GlusterFS: ssh <node> 'ls /mnt/gluster'"
    echo "  - Check slurmd: ssh <node> 'systemctl status slurmd'"
    echo ""
    log_info "autofs features:"
    echo "  - Auto-mount on first access"
    echo "  - Auto-unmount after 5min idle"
    echo "  - Graceful boot without GlusterFS dependency"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║      Phase 10: Compute Node Deployment                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    setup_ssh_auth

    log_info "Config:       $CONFIG_PATH"
    log_info "Package Dir:  ${OFFLINE_PKG_DIR}"
    log_info "Parallel:     $PARALLEL"
    log_info "Dry-run:      $DRY_RUN"
    echo ""

    # Confirmation
    if [[ "$DRY_RUN" == "false" ]] && [[ "$AUTO_YES" == "false" ]]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi

    # Get GlusterFS configuration
    log_info "Getting GlusterFS configuration..."
    local gluster_config=$(get_glusterfs_config)

    local gluster_server=$(python3 -c "import json; print(json.loads('''$gluster_config''')['gluster_server'])" 2>/dev/null || echo "")
    local gluster_volume=$(python3 -c "import json; print(json.loads('''$gluster_config''')['volume_name'])" 2>/dev/null || echo "shared_data")
    local gluster_mount=$(python3 -c "import json; print(json.loads('''$gluster_config''')['mount_point'])" 2>/dev/null || echo "/mnt/gluster")

    if [[ -z "$gluster_server" ]]; then
        log_warning "GlusterFS server not found - using first controller IP"
        gluster_server=$(python3 -c "
import yaml
with open('$CONFIG_PATH', 'r') as f:
    config = yaml.safe_load(f)
controllers = config.get('nodes', {}).get('controllers', [])
if controllers:
    print(controllers[0].get('ip_address', ''))
" 2>/dev/null || echo "")
    fi

    log_info "GlusterFS Server: $gluster_server"
    log_info "GlusterFS Volume: $gluster_volume"
    log_info "Mount Point:      $gluster_mount"
    echo ""

    if deploy_all_nodes "$gluster_server" "$gluster_volume" "$gluster_mount"; then
        print_summary
        log_success "Phase 10 completed successfully!"
        exit 0
    else
        log_error "Phase 10 completed with errors"
        exit 1
    fi
}

main "$@"
