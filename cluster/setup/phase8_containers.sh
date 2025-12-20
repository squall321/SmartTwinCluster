#!/bin/bash

################################################################################
# Phase 8: Container Images Deployment Script
#
# This script deploys Apptainer .sif images to cluster nodes:
# - viz-node-images/*.sif → viz nodes at /opt/apptainers/
# - compute-node-images/*.sif → compute nodes at /opt/apptainers/
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
#   --help              Show this help message
#
# Deployment Modes (from YAML container_support.apptainer.sif_deployment_mode):
#   skip      Skip if file exists (default, fastest)
#   overwrite Force overwrite all files (slowest)
#   update    Compare size/mtime, copy only if different (medium)
#
# Example:
#   sudo ./phase8_containers.sh --config ../my_multihead_cluster.yaml
#   sudo ./phase8_containers.sh --dry-run
#   sudo ./phase8_containers.sh --mode overwrite
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
SSH_KEY_FILE="${ORIGINAL_HOME}/.ssh/id_rsa"

# SSH options: -n prevents reading from stdin (critical for while read loops!)
# SCP options: -n is NOT supported by scp, so we need separate options
if [[ -f "$SSH_KEY_FILE" ]]; then
    SSH_OPTS="-n -i $SSH_KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o BatchMode=yes -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
    SCP_OPTS="-i $SSH_KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o BatchMode=yes -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
else
    SSH_OPTS="-n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o BatchMode=yes -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
    SCP_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o BatchMode=yes -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
fi

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

    mode = config.get('container_support', {}).get('apptainer', {}).get('sif_deployment_mode', 'skip')

    # Validate mode
    if mode not in ['skip', 'overwrite', 'update']:
        print('skip', file=sys.stderr)
        sys.exit(1)

    print(mode)

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    print('skip')  # Default to skip on error
    sys.exit(1)
EOPY
)

    if [[ -z "$yaml_mode" ]]; then
        yaml_mode="skip"
        log_warning "Failed to read sif_deployment_mode from YAML, using default: skip"
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

    # If not, check compute_nodes for node_type=viz
    if not viz_nodes:
        compute_nodes = nodes.get('compute_nodes', [])
        viz_nodes = [n for n in compute_nodes if n.get('node_type') == 'viz']

    if not viz_nodes:
        sys.exit(0)

    for node in viz_nodes:
        hostname = node.get('hostname', '')
        ip = node.get('ip_address', '')
        user = node.get('ssh_user', 'koopark')

        if hostname and ip:
            print(f"{hostname}|{ip}|{user}")

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

    # Filter only compute type nodes (exclude viz nodes)
    compute_nodes = [n for n in all_compute_nodes if n.get('node_type', 'compute') == 'compute']

    if not compute_nodes:
        sys.exit(0)

    for node in compute_nodes:
        hostname = node.get('hostname', '')
        ip = node.get('ip_address', '')
        user = node.get('ssh_user', 'koopark')

        if hostname and ip:
            print(f"{hostname}|{ip}|{user}")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOPY
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

    # Test SSH connection
    log_info "Testing SSH connection to $hostname..."
    if ! ssh $SSH_OPTS ${user}@${ip} "exit" 2>/dev/null; then
        log_error "Cannot connect to $hostname ($ip) via SSH"
        return 1
    fi
    log_success "SSH connection successful"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN: Would deploy the following images:"
        for sif in $sif_files; do
            local size=$(du -h "$sif" | cut -f1)
            log_info "  - $(basename $sif) ($size)"
        done
        return 0
    fi

    # Create target directory on remote node
    log_info "Creating target directory: $target_path"
    if ! timeout 30 ssh $SSH_OPTS ${user}@${ip} "sudo mkdir -p $target_path" 2>/dev/null; then
        log_error "Failed to create directory on $hostname (timeout or permission denied)"
        return 1
    fi

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
                if timeout 10 ssh $SSH_OPTS ${user}@${ip} "sudo test -f $remote_path" 2>/dev/null; then
                    log_warning "  Already exists, skipping (mode: skip)"
                    ((success_count++))
                    should_deploy=false
                fi
                ;;
            overwrite)
                # Always deploy, even if file exists
                if timeout 10 ssh $SSH_OPTS ${user}@${ip} "sudo test -f $remote_path" 2>/dev/null; then
                    log_info "  File exists, will overwrite (mode: overwrite)"
                fi
                ;;
            update)
                # Compare size and mtime, only deploy if different
                if timeout 10 ssh $SSH_OPTS ${user}@${ip} "sudo test -f $remote_path" 2>/dev/null; then
                    local local_size=$(stat -c%s "$sif" 2>/dev/null || echo "0")
                    local local_mtime=$(stat -c%Y "$sif" 2>/dev/null || echo "0")

                    local remote_info=$(ssh $SSH_OPTS ${user}@${ip} "sudo stat -c'%s %Y' $remote_path" 2>/dev/null || echo "0 0")
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
        if timeout 5 ssh $SSH_OPTS ${user}@${ip} "test -d /scratch && test -w /scratch" 2>/dev/null; then
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
            ssh $SSH_OPTS ${user}@${ip} "df -h ${staging_dir} /opt 2>/dev/null" || true
            ((fail_count++))
            continue
        fi

        # Copy metadata JSON if it exists
        if [[ -f "$json_file" ]]; then
            log_info "  Copying metadata JSON to ${staging_dir}..."
            scp $SCP_OPTS "$json_file" ${user}@${ip}:${staging_dir}/${json_name} 2>/dev/null || \
                log_warning "  Failed to copy metadata $json_name"
        fi

        # Move to target with sudo
        log_info "  Moving to $target_path..."
        if timeout 30 ssh $SSH_OPTS ${user}@${ip} "sudo mv ${staging_dir}/${sif_name} $remote_path && \
            sudo chown root:root $remote_path && \
            sudo chmod 755 $remote_path" 2>/dev/null; then
            log_success "  ✅ $sif_name deployed successfully"
            ((success_count++))

            # Move metadata JSON if it was copied
            if [[ -f "$json_file" ]]; then
                ssh $SSH_OPTS ${user}@${ip} "sudo test -f ${staging_dir}/${json_name} && \
                    sudo mv ${staging_dir}/${json_name} $json_remote_path && \
                    sudo chown root:root $json_remote_path && \
                    sudo chmod 644 $json_remote_path" 2>/dev/null || \
                    log_warning "  Metadata not deployed"
            fi
        else
            log_error "  Failed to move $sif_name to target (timeout or permission denied)"
            # Clean up temp files if move failed
            ssh $SSH_OPTS ${user}@${ip} "rm -f ${staging_dir}/${sif_name} ${staging_dir}/${json_name}" 2>/dev/null || true
            ((fail_count++))
        fi
    done

    # Verification
    log_info "Verifying deployment..."
    local deployed_files=$(timeout 10 ssh $SSH_OPTS ${user}@${ip} "sudo ls -lh $target_path/*.sif 2>/dev/null | wc -l" 2>/dev/null || echo "0")
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

    # Deploy to each viz node
    local total_success=0
    local total_fail=0

    while IFS= read -r node_info; do
        [[ -z "$node_info" ]] && continue
        local hostname=$(echo "$node_info" | cut -d'|' -f1)
        local ip=$(echo "$node_info" | cut -d'|' -f2)
        local user=$(echo "$node_info" | cut -d'|' -f3)

        if deploy_to_node "$hostname" "$ip" "$user" "$VIZ_IMAGES_SOURCE" "$VIZ_TARGET_PATH" "viz"; then
            ((total_success++))
        else
            ((total_fail++))
        fi

        echo ""
    done <<< "$viz_nodes"

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

    # Deploy to each compute node
    local total_success=0
    local total_fail=0

    while IFS= read -r node_info; do
        [[ -z "$node_info" ]] && continue
        local hostname=$(echo "$node_info" | cut -d'|' -f1)
        local ip=$(echo "$node_info" | cut -d'|' -f2)
        local user=$(echo "$node_info" | cut -d'|' -f3)

        if deploy_to_node "$hostname" "$ip" "$user" "$COMPUTE_IMAGES_SOURCE" "$COMPUTE_TARGET_PATH" "compute"; then
            ((total_success++))
        else
            ((total_fail++))
        fi

        echo ""
    done <<< "$compute_nodes"

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
        log_info "Viz Nodes:"
        while IFS= read -r node_info; do
            [[ -z "$node_info" ]] && continue
            local hostname=$(echo "$node_info" | cut -d'|' -f1)
            local ip=$(echo "$node_info" | cut -d'|' -f2)
            local user=$(echo "$node_info" | cut -d'|' -f3)

            echo "  📍 $hostname ($ip):"
            if ssh $SSH_OPTS ${user}@${ip} "sudo test -d $VIZ_TARGET_PATH" 2>/dev/null; then
                ssh $SSH_OPTS ${user}@${ip} "sudo find $VIZ_TARGET_PATH -name '*.sif' -exec du -h {} \;" 2>/dev/null | \
                    awk '{print "     - " $2 " (" $1 ")"}' || echo "     ⚠️  Error reading files"
            else
                echo "     ❌ Directory not accessible"
            fi
        done <<< "$viz_nodes"
        echo ""
    fi

    # Compute nodes summary
    local compute_nodes=$(get_compute_nodes)
    if [[ -n "$compute_nodes" ]]; then
        log_info "Compute Nodes:"
        while IFS= read -r node_info; do
            [[ -z "$node_info" ]] && continue
            local hostname=$(echo "$node_info" | cut -d'|' -f1)
            local ip=$(echo "$node_info" | cut -d'|' -f2)
            local user=$(echo "$node_info" | cut -d'|' -f3)

            echo "  📍 $hostname ($ip):"
            if ssh $SSH_OPTS ${user}@${ip} "sudo test -d $COMPUTE_TARGET_PATH" 2>/dev/null; then
                ssh $SSH_OPTS ${user}@${ip} "sudo find $COMPUTE_TARGET_PATH -name '*.sif' -exec du -h {} \;" 2>/dev/null | \
                    awk '{print "     - " $2 " (" $1 ")"}' || echo "     ⚠️  Error reading files"
            else
                echo "     ❌ Directory not accessible"
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

    log_info "Deploying metadata JSON files to /shared/apptainer/metadata/"

    # Create metadata directory on headnode
    local metadata_dir="/shared/apptainer/metadata"
    if ! sudo mkdir -p "$metadata_dir" 2>/dev/null; then
        log_error "Failed to create metadata directory: $metadata_dir"
        return 1
    fi

    local copied_count=0

    # Copy compute node metadata
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
    echo ""

    # Validate config
    validate_config
    echo ""

    # Load SIF deployment mode from YAML (or use CLI override)
    load_sif_deployment_mode
    log_info "SIF Deployment Mode: $SIF_DEPLOYMENT_MODE"
    echo ""

    # Deploy viz-node images
    local viz_result=0
    deploy_viz_images || viz_result=$?

    # Deploy compute-node images
    local compute_result=0
    deploy_compute_images || compute_result=$?

    # Deploy metadata to headnode
    deploy_metadata_to_headnode

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
