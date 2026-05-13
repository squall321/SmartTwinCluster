#!/bin/bash

################################################################################
# Phase 8: Container Images Deployment Script
#
# This script deploys Apptainer binary + .sif images to cluster nodes:
# - viz-node-images/*.sif → viz nodes at /opt/apptainers/
# - compute-node-images/*.sif → compute nodes at /opt/apptainers/
# - /scratch/{vnc_sandboxes,vnc_sessions,vnc_logs} 디렉토리 생성
#
# Note: Both viz and compute nodes use /opt/apptainers/ directly
#       to maintain compatibility with backend expectations.
#
# Usage:
#   sudo ./phase8_containers.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml (default: ../../my_multihead_cluster.yaml)
#   --dry-run           Preview actions without executing
#   --force             Deprecated: Use --mode overwrite instead
#   --mode MODE         SIF deployment mode: skip | overwrite | update (overrides YAML setting)
#   --skip-install      Apptainer 바이너리 설치 스킵 (이미지만 배포)
#   --image FILE        특정 SIF 이미지만 모든 노드에 배포
#   --parallel N        병렬 처리 노드 수 (기본: 8)
#   --help              Show this help message
#
# Deployment Modes (from YAML container_support.apptainer.sif_deployment_mode):
#   skip      Skip if file exists (fastest, no change detection)
#   overwrite Force overwrite all files (slowest)
#   update    Compare size/mtime, copy only if different (default, recommended)
#
# Example:
#   sudo ./phase8_containers.sh --config ../my_multihead_cluster.yaml
#   sudo ./phase8_containers.sh --dry-run
#   sudo ./phase8_containers.sh --mode overwrite
#   sudo ./phase8_containers.sh --skip-install
#   sudo ./phase8_containers.sh --image vnc_gnome.sif
#   sudo ./phase8_containers.sh --parallel 16
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
CONFIG_PATH="$PROJECT_ROOT/my_multihead_cluster.yaml"
DRY_RUN=false
FORCE=false
SIF_DEPLOYMENT_MODE=""  # Will be read from YAML (skip | overwrite | update)
SKIP_INSTALL=false
TARGET_IMAGE=""
# 병렬 수: 환경변수 PHASE8_PARALLEL > CLI > 기본값 4 (대역폭 보호)
PARALLEL="${PHASE8_PARALLEL:-4}"
LOG_FILE="/var/log/cluster_containers_deployment.log"

# Container images paths
VIZ_IMAGES_SOURCE="$PROJECT_ROOT/apptainer/viz-node-images"
COMPUTE_IMAGES_SOURCE="$PROJECT_ROOT/apptainer/compute-node-images"

# Deployment target paths (both use same directory for consistency)
VIZ_TARGET_PATH="/opt/apptainers"
COMPUTE_TARGET_PATH="/opt/apptainers"

# SSH options (includes GSSAPIAuthentication=no to prevent Kerberos delays)
#
# IMPORTANT: When running with sudo, we need to use the original user's SSH key
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)

# Find SSH key: try id_rsa, id_ed25519, id_ecdsa in order
SSH_KEY_FILE=""
for _key in "${ORIGINAL_HOME}/.ssh/id_rsa" "${ORIGINAL_HOME}/.ssh/id_ed25519" "${ORIGINAL_HOME}/.ssh/id_ecdsa"; do
    if [[ -f "$_key" ]]; then
        SSH_KEY_FILE="$_key"
        break
    fi
done
# Also try stcx user's key if running as root and no key found yet
if [[ -z "$SSH_KEY_FILE" && "$(whoami)" == "root" ]]; then
    for _key in /home/stcx/.ssh/id_rsa /home/stcx/.ssh/id_ed25519; do
        if [[ -f "$_key" ]]; then
            SSH_KEY_FILE="$_key"
            break
        fi
    done
fi

# Base SSH/SCP options (no auth method specified — determined per-node at runtime)
SSH_BASE="-n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o GSSAPIAuthentication=no"
SCP_BASE="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o GSSAPIAuthentication=no"

# Per-node SSH command variables (set by setup_node_ssh before each deployment)
SSH_CMD="ssh $SSH_BASE"
SCP_CMD="scp $SCP_BASE"
SSH_PASSWORD=""
export HAS_SSHPASS=false

# Set SSH_CMD/SCP_CMD for a specific node: key auth first, sshpass fallback
# Same pattern as deploy_to_compute_node.sh
# Key priority: ssh_user's own key → ORIGINAL_USER's key → sshpass fallback
setup_node_ssh() {
    local user="$1" ip="$2"

    # Find the best key for this ssh_user
    # If deploying as stcx, use stcx's key (bootstrap registered stcx's key on remote nodes)
    local user_home
    user_home=$(getent passwd "$user" | cut -d: -f6 2>/dev/null || echo "")
    local try_keys=()
    [[ -n "$user_home" ]] && {
        try_keys+=("${user_home}/.ssh/id_rsa" "${user_home}/.ssh/id_ed25519")
    }
    # Also try ORIGINAL_USER's key as fallback
    [[ -n "$SSH_KEY_FILE" ]] && try_keys+=("$SSH_KEY_FILE")

    for _key in "${try_keys[@]}"; do
        [[ -f "$_key" ]] || continue
        if ssh -n -i "$_key" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
               "${user}@${ip}" "echo OK" &>/dev/null; then
            SSH_CMD="ssh -i $_key $SSH_BASE"
            SCP_CMD="scp -i $_key $SCP_BASE"
            return 0
        fi
    done

    # Key auth failed — try sshpass
    if [[ -n "$SSH_PASSWORD" && "$HAS_SSHPASS" == "true" ]]; then
        export SSHPASS="$SSH_PASSWORD"
        if SSHPASS="$SSH_PASSWORD" sshpass -e ssh -n -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
               "${user}@${ip}" "echo OK" &>/dev/null; then
            SSH_CMD="sshpass -e ssh $SSH_BASE"
            SCP_CMD="sshpass -e scp $SCP_BASE"
            return 0
        else
            log_warning "  sshpass auth also failed for ${user}@${ip} — wrong password or PasswordAuthentication disabled"
        fi
    fi

    return 1
}

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_phase() {
    echo -e "${CYAN}[PHASE 8]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to show help
show_help() {
    grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//'
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_PATH="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                log_warning "--force is deprecated, using --mode overwrite instead"
                FORCE=true
                SIF_DEPLOYMENT_MODE="overwrite"
                shift
                ;;
            --mode)
                SIF_DEPLOYMENT_MODE="$2"
                if [[ ! "$SIF_DEPLOYMENT_MODE" =~ ^(skip|overwrite|update)$ ]]; then
                    log_error "Invalid mode: $SIF_DEPLOYMENT_MODE (must be skip, overwrite, or update)"
                    exit 1
                fi
                shift 2
                ;;
            --skip-install)
                SKIP_INSTALL=true
                shift
                ;;
            --image)
                TARGET_IMAGE="$2"
                SKIP_INSTALL=true
                shift 2
                ;;
            --parallel)
                PARALLEL="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Initialize log file
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/cluster_containers_deployment.log"
    chmod 644 "$LOG_FILE" 2>/dev/null || true
}

# Function to validate config file
validate_config() {
    log_info "Validating configuration file: $CONFIG_PATH"

    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error "Config file not found: $CONFIG_PATH"
        exit 1
    fi

    # Check if Python and yaml module are available
    if ! python3 -c "import yaml" 2>/dev/null; then
        log_error "Python3 yaml module required: pip3 install pyyaml"
        exit 1
    fi

    log_success "Configuration file validated"
}

# Function to read SIF deployment mode from YAML (if not overridden by CLI)
load_sif_deployment_mode() {
    # If already set by CLI, use that value
    if [[ -n "$SIF_DEPLOYMENT_MODE" ]]; then
        log_info "Using deployment mode from CLI: $SIF_DEPLOYMENT_MODE"
        return
    fi

    # Read from YAML
    local yaml_mode=$(python3 << EOPY
import yaml
import sys

try:
    with open('$CONFIG_PATH', 'r') as f:
        config = yaml.safe_load(f)

    mode = config.get('container_support', {}).get('apptainer', {}).get('sif_deployment_mode', 'update')

    # Validate mode
    if mode not in ['skip', 'overwrite', 'update']:
        print('update', file=sys.stderr)
        sys.exit(1)

    print(mode)

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    print('update')  # Default to update on error
    sys.exit(1)
EOPY
)

    if [[ -z "$yaml_mode" ]]; then
        yaml_mode="update"
        log_warning "Failed to read sif_deployment_mode from YAML, using default: update"
    fi

    SIF_DEPLOYMENT_MODE="$yaml_mode"
    log_info "Using deployment mode from YAML: $SIF_DEPLOYMENT_MODE"
}

# Function to get viz nodes from YAML
get_viz_nodes() {
    python3 << EOPY
import yaml
import sys

try:
    with open('$CONFIG_PATH', 'r') as f:
        config = yaml.safe_load(f)

    nodes = config.get('nodes', {})

    # First check if viz_nodes section exists
    viz_nodes = nodes.get('viz_nodes', [])

    # If not, check compute_nodes for node_type=viz or hybrid
    if not viz_nodes:
        compute_nodes = nodes.get('compute_nodes', [])
        viz_nodes = [n for n in compute_nodes if n.get('node_type') in ('viz', 'hybrid')]

    if not viz_nodes:
        sys.exit(0)

    for node in viz_nodes:
        hostname = node.get('hostname', '')
        ip = node.get('ip_address', '')
        user = node.get('ssh_user', 'root')
        node_type = node.get('node_type', 'viz')

        if hostname and ip:
            print(f"{hostname}|{ip}|{user}|{node_type}")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOPY
}

# Function to get compute nodes from YAML
get_compute_nodes() {
    python3 << EOPY
import yaml
import sys

try:
    with open('$CONFIG_PATH', 'r') as f:
        config = yaml.safe_load(f)

    nodes = config.get('nodes', {})
    all_compute_nodes = nodes.get('compute_nodes', [])

    # Filter compute type nodes: include 'compute' and 'hybrid' (exclude pure viz nodes)
    compute_nodes = [n for n in all_compute_nodes if n.get('node_type', 'compute') in ('compute', 'hybrid')]

    if not compute_nodes:
        sys.exit(0)

    for node in compute_nodes:
        hostname = node.get('hostname', '')
        ip = node.get('ip_address', '')
        user = node.get('ssh_user', 'root')
        node_type = node.get('node_type', 'compute')

        if hostname and ip:
            print(f"{hostname}|{ip}|{user}|{node_type}")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOPY
}

# Function to get GlusterFS mount point from YAML (for shared metadata storage)
get_gluster_mount_point() {
    python3 << EOPY
import yaml
import sys

try:
    with open('$CONFIG_PATH', 'r') as f:
        config = yaml.safe_load(f)

    # Get shared_storage.glusterfs.mount_point
    mount_point = config.get('shared_storage', {}).get('glusterfs', {}).get('mount_point', '/mnt/gluster')
    print(mount_point)

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    print('/mnt/gluster')  # Default fallback
    sys.exit(0)
EOPY
}

# Apptainer 바이너리 설치 (없을 때만, 누락 파일 자동 복구)
install_apptainer_on_node() {
    local hostname=$1
    local ip=$2
    local user=$3

    local binary_tar="$PROJECT_ROOT/apptainer/apptainer-binary-1.3.3.tar.gz"
    if [[ ! -f "$binary_tar" ]]; then
        log_warning "[$hostname] apptainer-binary-1.3.3.tar.gz 없음 — 설치 스킵"
        return 0
    fi

    local needs_install=false
    if ! $SSH_CMD ${user}@${ip} "command -v apptainer" &>/dev/null; then
        needs_install=true
    else
        # 누락 파일 체크
        for check_path in \
            "/usr/local/etc/apptainer/apptainer.conf" \
            "/usr/local/libexec/apptainer/bin/starter" \
            "/usr/local/etc/apptainer/capability.json" \
            "/usr/local/var/apptainer/mnt/session"; do
            if ! $SSH_CMD ${user}@${ip} "sudo test -e $check_path" &>/dev/null; then
                log_info "[$hostname] 누락 감지: $check_path"
                needs_install=true
                break
            fi
        done
        if ! $SSH_CMD ${user}@${ip} "command -v squashfuse_ll" &>/dev/null; then
            needs_install=true
        fi
    fi

    if [[ "$needs_install" == "false" ]]; then
        log_success "[$hostname] Apptainer 이미 설치됨"
        return 0
    fi

    log_info "[$hostname] Apptainer 설치 중..."
    log_info "[$hostname] SCP_CMD: $SCP_CMD"
    log_info "[$hostname] SSH_PASSWORD set: $([[ -n "$SSH_PASSWORD" ]] && echo yes || echo no), SSHPASS set: $([[ -n "$SSHPASS" ]] && echo yes || echo no)"
    if ! timeout 120 $SCP_CMD "$binary_tar" "${user}@${ip}:/tmp/"; then
        log_error "[$hostname] Apptainer 바이너리 복사 실패"
        return 1
    fi

    # sudo -S reads password from stdin; pass SSH_PASSWORD if set (for nodes without NOPASSWD)
    local sudo_cmd="sudo"
    local sudo_prefix=""
    if [[ -n "$SSH_PASSWORD" ]]; then
        sudo_prefix="echo '$SSH_PASSWORD' | sudo -S"
        sudo_cmd="echo '$SSH_PASSWORD' | sudo -S"
    fi

    $SSH_CMD "${user}@${ip}" "
        set -e
        cd /tmp && tar -xzf apptainer-binary-1.3.3.tar.gz
        $sudo_cmd install -m 755 apptainer /usr/local/bin/
        $sudo_cmd install -m 755 squashfuse_ll /usr/local/bin/
        $sudo_cmd sh -c 'cp -a lib/libfuse.so* /lib/x86_64-linux-gnu/ 2>/dev/null; ldconfig'
        $sudo_cmd mkdir -p /usr/local/etc && $sudo_cmd cp -r etc/apptainer /usr/local/etc/
        $sudo_cmd mkdir -p /usr/local/libexec && $sudo_cmd cp -r libexec/apptainer /usr/local/libexec/
        $sudo_cmd chmod 755 /usr/local/libexec/apptainer/bin/starter
        $sudo_cmd mkdir -p /usr/local/var && $sudo_cmd cp -r var/apptainer /usr/local/var/
        rm -rf apptainer squashfuse_ll lib etc libexec var apptainer-binary-1.3.3.tar.gz
        apptainer --version
    " && log_success "[$hostname] Apptainer 설치 완료" || log_warning "[$hostname] Apptainer 설치 실패 — 계속 진행"
}

# /scratch 및 /opt/apptainers 디렉토리 생성 (이미 있으면 그냥 넘어감)
setup_node_dirs() {
    local hostname=$1
    local ip=$2
    local user=$3
    local target_path=$4

    local _sudo="sudo"
    [[ -n "$SSH_PASSWORD" ]] && _sudo="echo '$SSH_PASSWORD' | sudo -S"
    $SSH_CMD "${user}@${ip}" "
        $_sudo mkdir -p ${target_path} && $_sudo chown root:root ${target_path} &&
        $_sudo mkdir -p /scratch/vnc_sandboxes /scratch/vnc_sessions /scratch/vnc_logs &&
        $_sudo chmod 1777 /scratch /scratch/vnc_sandboxes /scratch/vnc_sessions /scratch/vnc_logs
    " 2>/dev/null && log_success "[$hostname] 디렉토리 준비 완료" || {
        log_warning "[$hostname] 디렉토리 생성 실패"
        return 1
    }
}

# Function to deploy images to a single node
deploy_to_node() {
    local hostname=$1
    local ip=$2
    local user=$3
    local source_dir=$4
    local target_path=$5
    local node_type=$6  # "viz" or "compute"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_phase "Deploying $node_type images to $hostname ($ip)"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check if source directory exists
    if [[ ! -d "$source_dir" ]]; then
        log_warning "Source directory not found: $source_dir"
        return 1
    fi

    # Find .sif files
    local sif_files=$(find "$source_dir" -name "*.sif" 2>/dev/null)

    if [[ -z "$sif_files" ]]; then
        log_warning "No .sif files found in $source_dir"
        return 1
    fi

    log_info "Found $(echo "$sif_files" | wc -l) .sif file(s)"

    # Test SSH connection (key auth first, sshpass fallback — same as deploy_to_compute_node.sh)
    log_info "Testing SSH connection to $hostname..."
    if ! setup_node_ssh "$user" "$ip"; then
        log_error "Cannot connect to $hostname ($ip) via SSH"
        log_error "  Tried key auth and sshpass fallback. Check ssh_password in YAML."
        return 1
    fi
    log_success "SSH connection successful"

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$SKIP_INSTALL" != "true" ]]; then
            log_warning "DRY-RUN: Would install Apptainer binary"
        fi
        log_warning "DRY-RUN: Would deploy the following images:"
        for sif in $sif_files; do
            local size=$(du -h "$sif" | cut -f1)
            log_info "  - $(basename $sif) ($size)"
        done
        return 0
    fi

    # Apptainer 바이너리 설치
    if [[ "$SKIP_INSTALL" != "true" ]]; then
        install_apptainer_on_node "$hostname" "$ip" "$user"
    fi

    # 디렉토리 생성 (/opt/apptainers + /scratch)
    setup_node_dirs "$hostname" "$ip" "$user" "$target_path" || return 1

    # Deploy each .sif file
    local success_count=0
    local fail_count=0

    for sif in $sif_files; do
        local sif_name=$(basename "$sif")
        local size=$(du -h "$sif" | cut -f1)
        local remote_path="${target_path}/${sif_name}"

        # Metadata JSON file
        local json_file="${sif%.sif}.json"
        local json_name="${sif_name%.sif}.json"
        local json_remote_path="${target_path}/${json_name}"

        log_info "Deploying: $sif_name ($size) [mode: $SIF_DEPLOYMENT_MODE]"

        # Check deployment mode and decide whether to deploy
        local should_deploy=true

        case "$SIF_DEPLOYMENT_MODE" in
            skip)
                # Skip if file already exists
                if timeout 10 $SSH_CMD ${user}@${ip} "sudo test -f $remote_path" 2>/dev/null; then
                    log_warning "  Already exists, skipping (mode: skip)"
                    ((success_count++))
                    should_deploy=false
                fi
                ;;
            overwrite)
                # Always deploy, even if file exists
                if timeout 10 $SSH_CMD ${user}@${ip} "sudo test -f $remote_path" 2>/dev/null; then
                    log_info "  File exists, will overwrite (mode: overwrite)"
                fi
                ;;
            update)
                # Compare size and mtime, only deploy if different
                if timeout 10 $SSH_CMD ${user}@${ip} "sudo test -f $remote_path" 2>/dev/null; then
                    local local_size=$(stat -c%s "$sif" 2>/dev/null || echo "0")
                    local local_mtime=$(stat -c%Y "$sif" 2>/dev/null || echo "0")

                    local remote_info=$($SSH_CMD ${user}@${ip} "sudo stat -c'%s %Y' $remote_path" 2>/dev/null || echo "0 0")
                    local remote_size=$(echo "$remote_info" | awk '{print $1}')
                    local remote_mtime=$(echo "$remote_info" | awk '{print $2}')

                    if [[ "$local_size" == "$remote_size" ]] && [[ "$local_mtime" -le "$remote_mtime" ]]; then
                        log_info "  File up-to-date, skipping (mode: update, size: $local_size)"
                        ((success_count++))
                        should_deploy=false
                    else
                        log_info "  File outdated, will update (mode: update, local: $local_size/${local_mtime}, remote: $remote_size/${remote_mtime})"
                    fi
                else
                    log_info "  File does not exist, will deploy (mode: update)"
                fi
                ;;
        esac

        # Skip deployment if not needed
        if [[ "$should_deploy" != "true" ]]; then
            continue
        fi

        # Determine staging directory (/scratch preferred for large files, /tmp as fallback)
        local staging_dir
        if timeout 5 $SSH_CMD ${user}@${ip} "test -d /scratch && test -w /scratch" 2>/dev/null; then
            staging_dir="/scratch"
        else
            staging_dir="/tmp"
        fi

        # Copy to staging directory first (user writable)
        # Use timeout and show progress for large files
        local sif_size=$(du -h "$sif" | cut -f1)
        log_info "  Copying .sif to ${staging_dir}... (${sif_size})"

        # Use scp with compression and show error output (SCP_OPTS doesn't have -n)
        if ! timeout 600 scp -C $SCP_OPTS "$sif" ${user}@${ip}:${staging_dir}/${sif_name}; then
            log_error "  Failed to copy $sif_name (check disk space on target ${staging_dir})"
            # Check target disk space
            $SSH_CMD ${user}@${ip} "df -h ${staging_dir} /opt 2>/dev/null" || true
            ((fail_count++))
            continue
        fi

        # Copy metadata JSON if it exists
        if [[ -f "$json_file" ]]; then
            log_info "  Copying metadata JSON to ${staging_dir}..."
            $SCP_CMD "$json_file" ${user}@${ip}:${staging_dir}/${json_name} 2>/dev/null || \
                log_warning "  Failed to copy metadata $json_name"
        fi

        # Move to target with sudo
        log_info "  Moving to $target_path..."
        if timeout 30 $SSH_CMD ${user}@${ip} "sudo mv ${staging_dir}/${sif_name} $remote_path && \
            sudo chown root:root $remote_path && \
            sudo chmod 755 $remote_path" 2>/dev/null; then
            log_success "  ✅ $sif_name deployed successfully"
            ((success_count++))

            # Move metadata JSON if it was copied
            if [[ -f "$json_file" ]]; then
                $SSH_CMD ${user}@${ip} "sudo test -f ${staging_dir}/${json_name} && \
                    sudo mv ${staging_dir}/${json_name} $json_remote_path && \
                    sudo chown root:root $json_remote_path && \
                    sudo chmod 644 $json_remote_path" 2>/dev/null || \
                    log_warning "  Metadata not deployed"
            fi
        else
            log_error "  Failed to move $sif_name to target (timeout or permission denied)"
            # Clean up temp files if move failed
            $SSH_CMD ${user}@${ip} "rm -f ${staging_dir}/${sif_name} ${staging_dir}/${json_name}" 2>/dev/null || true
            ((fail_count++))
        fi
    done

    # Verification
    log_info "Verifying deployment..."
    local deployed_files=$(timeout 10 $SSH_CMD ${user}@${ip} "sudo ls -lh $target_path/*.sif 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    log_info "Deployed files on $hostname: $deployed_files"

    if [[ $fail_count -gt 0 ]]; then
        log_warning "Deployment to $hostname completed with failures (Success: $success_count, Failed: $fail_count)"
        return 1
    else
        log_success "Deployment to $hostname complete (Success: $success_count, Failed: $fail_count)"
        return 0
    fi
}

# Function to deploy viz-node images
deploy_viz_images() {
    log_phase "=== Deploying Viz-Node Images ==="
    echo ""

    if [[ ! -d "$VIZ_IMAGES_SOURCE" ]]; then
        log_warning "Viz-node images directory not found: $VIZ_IMAGES_SOURCE"
        log_info "Skipping viz-node image deployment"
        return 0
    fi

    local sif_count=$(find "$VIZ_IMAGES_SOURCE" -name "*.sif" 2>/dev/null | wc -l)
    log_info "Source directory: $VIZ_IMAGES_SOURCE"
    log_info "Found $sif_count .sif file(s)"

    if [[ $sif_count -eq 0 ]]; then
        log_warning "No .sif files to deploy"
        return 0
    fi

    # Get viz nodes from YAML
    local viz_nodes=$(get_viz_nodes)

    if [[ -z "$viz_nodes" ]]; then
        log_warning "No viz nodes defined in YAML config"
        return 0
    fi

    log_info "Target nodes:"
    while IFS= read -r node_info; do
        [[ -z "$node_info" ]] && continue
        local hostname=$(echo "$node_info" | cut -d'|' -f1)
        local ip=$(echo "$node_info" | cut -d'|' -f2)
        log_info "  - $hostname ($ip)"
    done <<< "$viz_nodes"
    echo ""

    # 병렬 배포
    local total_success=0
    local total_fail=0
    local pids=()
    local results_dir
    results_dir=$(mktemp -d)

    local node_index=0
    while IFS= read -r node_info; do
        [[ -z "$node_info" ]] && continue
        local hostname=$(echo "$node_info" | cut -d'|' -f1)
        local ip=$(echo "$node_info" | cut -d'|' -f2)
        local user=$(echo "$node_info" | cut -d'|' -f3)
        node_index=$((node_index + 1))

        # 병렬 실행
        (
            if deploy_to_node "$hostname" "$ip" "$user" "$VIZ_IMAGES_SOURCE" "$VIZ_TARGET_PATH" "viz"; then
                echo "ok" > "$results_dir/$hostname"
            else
                echo "fail" > "$results_dir/$hostname"
            fi
        ) &
        pids+=($!)

        # PARALLEL 수 도달 시 대기
        if [[ ${#pids[@]} -ge $PARALLEL ]]; then
            for pid in "${pids[@]}"; do wait "$pid" || true; done
            pids=()
        fi
    done <<< "$viz_nodes"

    # 나머지 대기
    for pid in "${pids[@]}"; do wait "$pid" || true; done

    # 결과 집계
    for result_file in "$results_dir"/*; do
        [[ -f "$result_file" ]] || continue
        if [[ "$(cat "$result_file")" == "ok" ]]; then
            ((total_success++))
        else
            ((total_fail++))
        fi
    done
    rm -rf "$results_dir"

    if [[ $total_fail -gt 0 ]]; then
        log_warning "Viz-node image deployment completed with failures (Success: $total_success nodes, Failed: $total_fail nodes)"
        return 1
    else
        log_success "Viz-node image deployment complete (Success: $total_success nodes)"
        return 0
    fi
    echo ""
}

# Function to deploy compute-node images
deploy_compute_images() {
    log_phase "=== Deploying Compute-Node Images ==="
    echo ""

    if [[ ! -d "$COMPUTE_IMAGES_SOURCE" ]]; then
        log_warning "Compute-node images directory not found: $COMPUTE_IMAGES_SOURCE"
        log_info "Skipping compute-node image deployment"
        return 0
    fi

    local sif_count=$(find "$COMPUTE_IMAGES_SOURCE" -name "*.sif" 2>/dev/null | wc -l)
    log_info "Source directory: $COMPUTE_IMAGES_SOURCE"
    log_info "Found $sif_count .sif file(s)"

    if [[ $sif_count -eq 0 ]]; then
        log_warning "No .sif files to deploy"
        return 0
    fi

    # Get compute nodes from YAML
    local compute_nodes=$(get_compute_nodes)

    if [[ -z "$compute_nodes" ]]; then
        log_warning "No compute nodes defined in YAML config"
        return 0
    fi

    log_info "Target nodes:"
    while IFS= read -r node_info; do
        [[ -z "$node_info" ]] && continue
        local hostname=$(echo "$node_info" | cut -d'|' -f1)
        local ip=$(echo "$node_info" | cut -d'|' -f2)
        log_info "  - $hostname ($ip)"
    done <<< "$compute_nodes"
    echo ""

    # 병렬 배포
    local total_success=0
    local total_fail=0
    local pids=()
    local results_dir
    results_dir=$(mktemp -d)

    while IFS= read -r node_info; do
        [[ -z "$node_info" ]] && continue
        local hostname=$(echo "$node_info" | cut -d'|' -f1)
        local ip=$(echo "$node_info" | cut -d'|' -f2)
        local user=$(echo "$node_info" | cut -d'|' -f3)

        (
            if deploy_to_node "$hostname" "$ip" "$user" "$COMPUTE_IMAGES_SOURCE" "$COMPUTE_TARGET_PATH" "compute"; then
                echo "ok" > "$results_dir/$hostname"
            else
                echo "fail" > "$results_dir/$hostname"
            fi
        ) &
        pids+=($!)

        if [[ ${#pids[@]} -ge $PARALLEL ]]; then
            for pid in "${pids[@]}"; do wait "$pid" || true; done
            pids=()
        fi
    done <<< "$compute_nodes"

    for pid in "${pids[@]}"; do wait "$pid" || true; done

    for result_file in "$results_dir"/*; do
        [[ -f "$result_file" ]] || continue
        if [[ "$(cat "$result_file")" == "ok" ]]; then
            ((total_success++))
        else
            ((total_fail++))
        fi
    done
    rm -rf "$results_dir"

    if [[ $total_fail -gt 0 ]]; then
        log_warning "Compute-node image deployment completed with failures (Success: $total_success nodes, Failed: $total_fail nodes)"
        return 1
    else
        log_success "Compute-node image deployment complete (Success: $total_success nodes)"
        return 0
    fi
    echo ""
}

# Function to show deployment summary
show_summary() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_phase "Deployment Summary"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Viz nodes summary
    local viz_nodes=$(get_viz_nodes)
    if [[ -n "$viz_nodes" ]]; then
        log_info "Viz Nodes (viz images):"
        while IFS= read -r node_info; do
            [[ -z "$node_info" ]] && continue
            local hostname=$(echo "$node_info" | cut -d'|' -f1)
            local ip=$(echo "$node_info" | cut -d'|' -f2)
            local user=$(echo "$node_info" | cut -d'|' -f3)
            local ntype=$(echo "$node_info" | cut -d'|' -f4)
            local label=""
            [[ "$ntype" == "hybrid" ]] && label=" [hybrid]"

            echo "  📍 $hostname ($ip)$label:"
            if setup_node_ssh "$user" "$ip" &>/dev/null; then
                if $SSH_CMD ${user}@${ip} "sudo test -d $VIZ_TARGET_PATH" 2>/dev/null; then
                    $SSH_CMD ${user}@${ip} "sudo find $VIZ_TARGET_PATH -name '*.sif' -exec du -h {} \;" 2>/dev/null | \
                        awk '{print "     - " $2 " (" $1 ")"}' || echo "     ⚠️  Error reading files"
                else
                    echo "     ❌ Directory not accessible"
                fi
            else
                echo "     ⚠️  SSH unreachable — skipping"
            fi
        done <<< "$viz_nodes"
        echo ""
    fi

    # Compute nodes summary
    local compute_nodes=$(get_compute_nodes)
    if [[ -n "$compute_nodes" ]]; then
        log_info "Compute Nodes (compute images):"
        while IFS= read -r node_info; do
            [[ -z "$node_info" ]] && continue
            local hostname=$(echo "$node_info" | cut -d'|' -f1)
            local ip=$(echo "$node_info" | cut -d'|' -f2)
            local user=$(echo "$node_info" | cut -d'|' -f3)
            local ntype=$(echo "$node_info" | cut -d'|' -f4)
            local label=""
            [[ "$ntype" == "hybrid" ]] && label=" [hybrid]"

            echo "  📍 $hostname ($ip)$label:"
            if setup_node_ssh "$user" "$ip" &>/dev/null; then
                if $SSH_CMD ${user}@${ip} "sudo test -d $COMPUTE_TARGET_PATH" 2>/dev/null; then
                    $SSH_CMD ${user}@${ip} "sudo find $COMPUTE_TARGET_PATH -name '*.sif' -exec du -h {} \;" 2>/dev/null | \
                        awk '{print "     - " $2 " (" $1 ")"}' || echo "     ⚠️  Error reading files"
                else
                    echo "     ❌ Directory not accessible"
                fi
            else
                echo "     ⚠️  SSH unreachable — skipping"
            fi
        done <<< "$compute_nodes"
        echo ""
    fi

    log_success "Phase 8: Container Images Deployment Complete! 🎉"
}

################################################################################
# Function to deploy metadata JSON files to headnode
################################################################################
deploy_metadata_to_headnode() {
    log_phase "=== Deploying Metadata to Headnode ==="
    echo ""

    # 철학: 같은 이름 = 같은 이미지, 하나의 대표 경로만 사용
    # 구조: {gluster_mount}/apptainer/metadata/*.json (flat, partition은 JSON 내부 필드로 구분)
    #
    # 메타데이터 배포 경로 결정:
    # 1. GlusterFS 마운트 포인트가 있으면 → {mount_point}/apptainer/metadata/ (클러스터 공유)
    # 2. GlusterFS가 없으면 → /opt/apptainers/ (로컬 fallback)
    local metadata_dir=""
    local gluster_mount=$(get_gluster_mount_point)

    log_info "GlusterFS mount point from YAML: $gluster_mount"

    # Check if GlusterFS mount exists and is accessible
    # 마운트 체크 방식:
    # 1. mountpoint -q: 실제 마운트 포인트인지 확인 (가장 정확)
    # 2. 쓰기 테스트: 마운트 포인트가 아니더라도 쓰기 가능하면 사용 (GlusterFS 마운트 지연 대응)
    local gluster_available=false

    if [[ -d "$gluster_mount" ]]; then
        if mountpoint -q "$gluster_mount" 2>/dev/null; then
            log_info "GlusterFS mount detected: $gluster_mount (mountpoint check passed)"
            gluster_available=true
        elif sudo test -w "$gluster_mount" 2>/dev/null; then
            # 디렉토리는 존재하고 쓰기 가능하지만 mountpoint가 아닌 경우
            # GlusterFS가 마운트되어 있을 수 있음 (fuse 마운트는 mountpoint 체크 실패 가능)
            log_info "GlusterFS directory exists and writable: $gluster_mount (using directory)"
            gluster_available=true
        fi
    fi

    if [[ "$gluster_available" == "true" ]]; then
        metadata_dir="$gluster_mount/apptainer/metadata"
        if sudo mkdir -p "$metadata_dir" 2>/dev/null; then
            log_info "Deploying metadata JSON files to $metadata_dir (GlusterFS shared storage)"
        else
            log_warning "Failed to create $metadata_dir, falling back to local storage"
            metadata_dir="/opt/apptainers"
        fi
    else
        # GlusterFS가 없는 환경 (단일 노드 또는 GlusterFS 미설정)
        metadata_dir="/opt/apptainers"
        log_warning "GlusterFS mount ($gluster_mount) not available, deploying metadata to $metadata_dir (local fallback)"
    fi

    if ! sudo mkdir -p "$metadata_dir" 2>/dev/null; then
        log_error "Failed to create metadata directory: $metadata_dir"
        return 1
    fi

    sudo chown root:root "$metadata_dir"
    sudo chmod 755 "$metadata_dir"

    local copied_count=0

    # Copy compute node metadata
    # 메타데이터 JSON 내에 "partition": "compute" 필드가 포함됨
    if [[ -d "$COMPUTE_IMAGES_SOURCE" ]]; then
        shopt -s nullglob  # Prevent error if no .json files exist
        for json_file in "$COMPUTE_IMAGES_SOURCE"/*.json; do
            if [[ -f "$json_file" ]]; then
                local json_name=$(basename "$json_file")
                log_info "  Copying $json_name (compute)"
                if sudo cp "$json_file" "$metadata_dir/$json_name" 2>/dev/null; then
                    sudo chown root:root "$metadata_dir/$json_name"
                    sudo chmod 644 "$metadata_dir/$json_name"
                    copied_count=$((copied_count + 1))
                else
                    log_warning "  Failed to copy $json_name"
                fi
            fi
        done
        shopt -u nullglob
    fi

    # Copy viz node metadata
    # 메타데이터 JSON 내에 "partition": "viz" 필드가 포함됨
    if [[ -d "$VIZ_IMAGES_SOURCE" ]]; then
        shopt -s nullglob
        for json_file in "$VIZ_IMAGES_SOURCE"/*.json; do
            if [[ -f "$json_file" ]]; then
                local json_name=$(basename "$json_file")
                log_info "  Copying $json_name (viz)"
                if sudo cp "$json_file" "$metadata_dir/$json_name" 2>/dev/null; then
                    sudo chown root:root "$metadata_dir/$json_name"
                    sudo chmod 644 "$metadata_dir/$json_name"
                    copied_count=$((copied_count + 1))
                else
                    log_warning "  Failed to copy $json_name"
                fi
            fi
        done
        shopt -u nullglob
    fi

    if [[ $copied_count -gt 0 ]]; then
        log_success "Deployed $copied_count metadata file(s) to headnode"
        log_info "Metadata location: $metadata_dir"
        log_info "Note: Partition info is stored in each JSON's 'partition' field"
    else
        log_warning "No metadata files found to deploy"
    fi

    echo ""
}

################################################################################
# Main execution
################################################################################

main() {
    # Parse arguments
    parse_args "$@"

    # Check root
    check_root

    # Show banner
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║  Phase 8: Container Images Deployment                         ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Config: $CONFIG_PATH"
    log_info "Dry-run: $DRY_RUN"
    log_info "Skip Apptainer install: $SKIP_INSTALL"
    log_info "Parallel: $PARALLEL"
    [[ -n "$TARGET_IMAGE" ]] && log_info "Target image: $TARGET_IMAGE"
    echo ""

    # Validate config
    validate_config
    echo ""

    # Read ssh_password from YAML (same as deploy_to_compute_node.sh)
    SSH_PASSWORD=$(python3 -c "
import yaml
with open('$CONFIG_PATH') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('cluster_info', {}).get('ssh_password', '') or cfg.get('nodes', {}).get('ssh_password', ''))
" 2>/dev/null || true)
    export SSH_PASSWORD
    if [[ -n "$SSH_PASSWORD" ]]; then
        export SSHPASS="$SSH_PASSWORD"
        if command -v sshpass &>/dev/null; then
            HAS_SSHPASS=true
            log_info "ssh_password loaded + sshpass available (fallback enabled)"
        else
            log_warning "ssh_password set but sshpass not installed — installing..."
            apt-get install -y sshpass &>/dev/null || true
            command -v sshpass &>/dev/null && HAS_SSHPASS=true
        fi
    fi
    export HAS_SSHPASS

    # Load SIF deployment mode from YAML (or use CLI override)
    load_sif_deployment_mode
    log_info "SIF Deployment Mode: $SIF_DEPLOYMENT_MODE"
    echo ""

    # --image 단일 이미지 배포 모드
    if [[ -n "$TARGET_IMAGE" ]]; then
        log_phase "=== 단일 이미지 배포 모드: $TARGET_IMAGE ==="
        local image_file=""
        for search_dir in "$COMPUTE_IMAGES_SOURCE" "$VIZ_IMAGES_SOURCE"; do
            if [[ -f "${search_dir}/${TARGET_IMAGE}" ]]; then
                image_file="${search_dir}/${TARGET_IMAGE}"
                break
            fi
        done
        if [[ -z "$image_file" ]]; then
            log_error "이미지 파일을 찾을 수 없음: $TARGET_IMAGE"
            log_info "검색 경로: $COMPUTE_IMAGES_SOURCE, $VIZ_IMAGES_SOURCE"
            exit 1
        fi
        log_info "이미지 경로: $image_file ($(du -h "$image_file" | cut -f1))"

        local all_nodes
        all_nodes=$(python3 << EOPY
import yaml
with open('$CONFIG_PATH') as f:
    cfg = yaml.safe_load(f)
nodes = cfg.get('nodes', {})
for n in nodes.get('compute_nodes', []) + nodes.get('viz_nodes', []):
    print(f"{n['hostname']}|{n['ip_address']}|{n.get('ssh_user','root')}")
EOPY
)
        local pids=() results_dir
        results_dir=$(mktemp -d)
        while IFS= read -r node_info; do
            [[ -z "$node_info" ]] && continue
            local hostname=$(echo "$node_info" | cut -d'|' -f1)
            local ip=$(echo "$node_info" | cut -d'|' -f2)
            local user=$(echo "$node_info" | cut -d'|' -f3)
            (
                setup_node_ssh "$user" "$ip" &>/dev/null
                if ! $SSH_CMD ${user}@${ip} "exit" &>/dev/null; then
                    log_warning "[$hostname] SSH 실패 — 스킵"
                    echo "fail" > "$results_dir/$hostname"; exit
                fi
                local img_name=$(basename "$image_file")
                local remote_path="/opt/apptainers/$img_name"
                $SSH_CMD ${user}@${ip} "sudo mkdir -p /opt/apptainers" 2>/dev/null
                local local_size=$(stat -c%s "$image_file")
                local remote_size=$($SSH_CMD ${user}@${ip} "sudo stat -c%s $remote_path 2>/dev/null || echo 0" 2>/dev/null)
                if [[ "$local_size" == "$remote_size" ]]; then
                    log_info "[$hostname] $img_name — 동일, 스킵"
                    echo "ok" > "$results_dir/$hostname"; exit
                fi
                if timeout 600 $SCP_CMD "$image_file" ${user}@${ip}:/tmp/ && \
                   $SSH_CMD ${user}@${ip} "sudo mv /tmp/$img_name $remote_path && sudo chown root:root $remote_path && sudo chmod 755 $remote_path"; then
                    log_success "[$hostname] ✅ $img_name 배포 완료"
                    echo "ok" > "$results_dir/$hostname"
                else
                    log_error "[$hostname] ❌ 배포 실패"
                    echo "fail" > "$results_dir/$hostname"
                fi
            ) &
            pids+=($!)
            if [[ ${#pids[@]} -ge $PARALLEL ]]; then
                for pid in "${pids[@]}"; do wait "$pid" || true; done
                pids=()
            fi
        done <<< "$all_nodes"
        for pid in "${pids[@]}"; do wait "$pid" || true; done
        local ok=0 fail=0
        for f in "$results_dir"/*; do
            [[ "$(cat "$f" 2>/dev/null)" == "ok" ]] && ((ok++)) || ((fail++))
        done
        rm -rf "$results_dir"
        log_success "단일 이미지 배포 완료: 성공 ${ok}, 실패 ${fail}"
        exit 0
    fi

    # Deploy viz-node images
    local viz_result=0
    deploy_viz_images || viz_result=$?

    # Deploy compute-node images
    local compute_result=0
    deploy_compute_images || compute_result=$?

    # Deploy metadata to headnode
    deploy_metadata_to_headnode

    # Trigger Apptainer metadata scan to populate DB
    # This ensures the web UI can display the deployed images
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Triggering Apptainer metadata scan to populate DB..."
        if curl -s -X POST http://localhost:5010/api/apptainer/scan -o /dev/null 2>/dev/null; then
            log_success "Apptainer metadata scan triggered successfully"
        else
            log_warning "Failed to trigger Apptainer scan (backend_5010 may not be running yet)"
            log_info "Tip: Run 'curl -X POST http://localhost:5010/api/apptainer/scan' after starting web services"
        fi
    fi

    # Show summary
    if [[ "$DRY_RUN" != "true" ]]; then
        show_summary || true  # Don't fail on summary errors
    else
        log_warning "DRY-RUN mode: No actual deployment performed"
    fi

    echo ""

    # Check if any deployment failed
    if [[ $viz_result -ne 0 ]] || [[ $compute_result -ne 0 ]]; then
        log_error "Phase 8 completed with failures"
        log_info "  - Viz nodes: $([ $viz_result -eq 0 ] && echo 'Success' || echo 'Failed')"
        log_info "  - Compute nodes: $([ $compute_result -eq 0 ] && echo 'Success' || echo 'Failed')"
        echo ""
        exit 1
    fi

    log_success "Phase 8 complete!"
    echo ""
}

# Run main function
main "$@"
