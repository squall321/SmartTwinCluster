#!/bin/bash

#############################################################################
# Phase 3: Slurm Multi-Master Setup
#############################################################################
# Description:
#   Sets up Slurm with multi-master configuration for high availability
#   VIP owner acts as primary controller, others as backups
#
# Features:
#   - Multi-master slurmctld configuration
#   - VIP-based primary controller selection
#   - Shared state directory via GlusterFS
#   - Dynamic slurm.conf generation from template
#   - SlurmDBD integration with MariaDB Galera
#   - Integration with my_multihead_cluster.yaml
#
# Usage:
#   sudo ./cluster/setup/phase3_slurm.sh [OPTIONS]
#
# Options:
#   --config PATH     Path to my_multihead_cluster.yaml
#   --controller      Setup as controller (slurmctld)
#   --compute         Setup as compute node (slurmd)
#   --dbd             Setup SlurmDBD (accounting database daemon)
#   --dry-run         Show what would be done without executing
#   --help            Show this help message
#
# Author: Claude Code
# Date: 2025-10-27
#############################################################################

set -euo pipefail

#############################################################################
# Configuration
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/ssh_helpers.sh" 2>/dev/null || true
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# OS 감지 기반 오프라인 패키지 디렉토리 설정
source "${PROJECT_ROOT}/cluster/utils/detect_os.sh"
detect_os_version
set_offline_pkg_dir "$PROJECT_ROOT"

CONFIG_FILE="${PROJECT_ROOT}/my_multihead_cluster.yaml"
PARSER_SCRIPT="${PROJECT_ROOT}/cluster/config/parser.py"
DISCOVERY_SCRIPT="${PROJECT_ROOT}/cluster/discovery/auto_discovery.sh"
SLURM_TEMPLATE="${PROJECT_ROOT}/cluster/config/slurm_template.conf"
SLURM_CONFIG="/etc/slurm/slurm.conf"
SLURMDBD_CONFIG="/etc/slurm/slurmdbd.conf"
LOG_FILE="/var/log/cluster_slurm_setup.log"

# Default values
SETUP_CONTROLLER=false
SETUP_COMPUTE=false
SETUP_DBD=false
AUTO_DEPLOY_COMPUTE=false
DRY_RUN=false

# GlusterFS settings (will be set based on availability)
USE_GLUSTERFS=false
GLUSTERFS_ENABLED=false
SLURM_STATE_DIR="/var/spool/slurmctld"
SLURM_LOG_DIR="/var/log/slurm"

# SSH options for secure remote connections
# GSSAPIAuthentication=no: Disable Kerberos to prevent delays
# PreferredAuthentications=publickey: Only try publickey auth
#
# IMPORTANT: When running with sudo, we need to use the original user's SSH key
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
SSH_KEY_FILE="${ORIGINAL_HOME}/.ssh/id_rsa"

_SSH_BASE_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o ServerAliveInterval=15 -o ServerAliveCountMax=3"

if [[ -f "$SSH_KEY_FILE" ]]; then
    SSH_OPTS="-n -i $SSH_KEY_FILE -o BatchMode=yes $_SSH_BASE_OPTS -o PreferredAuthentications=publickey"
    SCP_OPTS="-i $SSH_KEY_FILE -o BatchMode=yes $_SSH_BASE_OPTS"
else
    SSH_OPTS="-n -o BatchMode=yes $_SSH_BASE_OPTS -o PreferredAuthentications=publickey"
    SCP_OPTS="-o BatchMode=yes $_SSH_BASE_OPTS"
fi

# per-node SSH 명령 결정: 대상 user의 키 우선, fallback sshpass
# 전역 SSH_OPTS/SCP_OPTS를 node별로 오버라이드
setup_node_ssh_opts() {
    local user="$1" ip="$2"
    local user_home
    user_home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || echo "")
    for _k in "${user_home}/.ssh/id_ed25519" "${user_home}/.ssh/id_rsa" "$SSH_KEY_FILE"; do
        [[ -f "$_k" ]] || continue
        if ssh -n -i "$_k" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
               "$user@$ip" "exit" &>/dev/null; then
            SSH_OPTS="-n -i $_k -o BatchMode=yes $_SSH_BASE_OPTS"
            SCP_OPTS="-i $_k -o BatchMode=yes $_SSH_BASE_OPTS"
            return 0
        fi
    done
    # sshpass fallback
    local _pass
    _pass=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('cluster_info',{}).get('ssh_password',''))" 2>/dev/null || echo "")
    if [[ -n "$_pass" ]] && command -v sshpass &>/dev/null; then
        if SSHPASS="$_pass" sshpass -e ssh -n -o BatchMode=no -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no "$user@$ip" "exit" &>/dev/null; then
            export SSHPASS="$_pass"
            SSH_OPTS="-n -o BatchMode=no $_SSH_BASE_OPTS"
            SCP_OPTS="-o BatchMode=no $_SSH_BASE_OPTS"
            # sshpass는 별도로 앞에 붙여야 함 — 호출부에서 처리
            return 0
        fi
    fi
    return 1
}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#############################################################################
# Functions
#############################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Color based on level
    local color=$NC
    case $level in
        ERROR) color=$RED ;;
        SUCCESS) color=$GREEN ;;
        WARNING) color=$YELLOW ;;
        INFO) color=$BLUE ;;
    esac

    # Log to file
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi

    # Log to console with color
    echo -e "${color}[$level]${NC} $message"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --config PATH           Path to my_multihead_cluster.yaml (default: $CONFIG_FILE)
  --controller            Setup as controller (slurmctld)
  --compute               Setup as compute node (slurmd)
  --dbd                   Setup SlurmDBD (accounting database daemon)
  --auto-deploy-compute   Automatically deploy Slurm to all compute nodes
  --dry-run               Show what would be done without executing
  --help                  Show this help message

Examples:
  # Setup controller with auto-detection
  sudo $0 --controller

  # Setup compute node
  sudo $0 --compute

  # Setup SlurmDBD on first controller
  sudo $0 --dbd

  # Setup both controller and DBD
  sudo $0 --controller --dbd

  # Dry-run to preview changes
  $0 --controller --dry-run
EOF
}

run_command() {
    local cmd="$*"
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Install package from offline repository
# Usage: install_offline_package <package_name> [package_name2...]
# Returns: 0 on success, 1 on failure
install_offline_package() {
    local packages=("$@")
    local offline_pkg_dir="${OFFLINE_PKG_DIR}/apt_packages"

    if [[ ! -d "$offline_pkg_dir" ]]; then
        log ERROR "Offline package directory not found: $offline_pkg_dir"
        return 1
    fi

    # Check if Packages.gz exists for local APT repo
    if [[ ! -f "$offline_pkg_dir/Packages.gz" ]]; then
        log WARNING "Packages.gz not found, creating repository index..."
        if command -v dpkg-scanpackages &> /dev/null; then
            (cd "$offline_pkg_dir" && dpkg-scanpackages . /dev/null > Packages && gzip -k -f Packages)
        else
            log WARNING "dpkg-scanpackages not available, trying direct dpkg install..."
        fi
    fi

    # Setup local APT repository if Packages.gz exists
    local repo_list="/etc/apt/sources.list.d/offline-local.list"
    if [[ -f "$offline_pkg_dir/Packages.gz" ]]; then
        log INFO "Setting up local APT repository..."
        echo "deb [trusted=yes] file://$offline_pkg_dir ./" > "$repo_list"
        apt-get update -o Dir::Etc::sourcelist="$repo_list" \
                       -o Dir::Etc::sourceparts="-" \
                       -o APT::Get::List-Cleanup="0" 2>/dev/null || true

        # Try apt install with local repo
        log INFO "Installing packages via local APT repository: ${packages[*]}"
        if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}" 2>&1; then
            log SUCCESS "Packages installed successfully via local APT repo"
            return 0
        else
            log WARNING "APT install failed, trying direct dpkg install..."
        fi
    fi

    # Fallback: Direct dpkg install
    local installed=0
    for pkg in "${packages[@]}"; do
        # Find matching .deb files
        local deb_files=("$offline_pkg_dir"/${pkg}_*.deb "$offline_pkg_dir"/${pkg}-*.deb)
        for deb_file in "${deb_files[@]}"; do
            if [[ -f "$deb_file" ]]; then
                log INFO "Installing $(basename "$deb_file") via dpkg..."
                if dpkg -i "$deb_file" 2>&1; then
                    installed=$((installed + 1))
                else
                    # Try to fix dependencies
                    apt-get install -f -y 2>/dev/null || true
                fi
            fi
        done
    done

    if [[ $installed -gt 0 ]]; then
        log SUCCESS "Installed $installed package(s) via dpkg"
        return 0
    else
        log ERROR "Failed to install packages: ${packages[*]}"
        log ERROR "Ensure offline packages are available in: $offline_pkg_dir"
        return 1
    fi
}

# Install package on remote node using offline packages (APT method)
# Usage: install_offline_package_remote <remote_user> <remote_ip> <package_name> [package_name2...]
install_offline_package_remote() {
    local remote_user="$1"
    local remote_ip="$2"
    shift 2
    local packages=("$@")
    local offline_pkg_dir="${OFFLINE_PKG_DIR}/apt_packages"
    local remote_pkg_dir="/tmp/offline_packages"
    local repo_list="/etc/apt/sources.list.d/offline-local.list"

    if [[ ! -d "$offline_pkg_dir" ]]; then
        log ERROR "Offline package directory not found: $offline_pkg_dir"
        return 1
    fi

    # Create temp directory on remote
    ssh $SSH_OPTS "$remote_user@$remote_ip" "sudo mkdir -p '$remote_pkg_dir' && sudo chmod 777 '$remote_pkg_dir'" 2>/dev/null || true

    # Copy Packages.gz first (for APT)
    if [[ -f "$offline_pkg_dir/Packages.gz" ]]; then
        scp $SCP_OPTS "$offline_pkg_dir/Packages.gz" "$remote_user@$remote_ip:$remote_pkg_dir/" 2>/dev/null || true
        scp $SCP_OPTS "$offline_pkg_dir/Packages" "$remote_user@$remote_ip:$remote_pkg_dir/" 2>/dev/null || true
    fi

    # Copy packages and their dependencies
    local copied=0
    for pkg in "${packages[@]}"; do
        for deb_file in "$offline_pkg_dir"/${pkg}_*.deb "$offline_pkg_dir"/${pkg}-*.deb "$offline_pkg_dir"/lib${pkg}*.deb; do
            if [[ -f "$deb_file" ]]; then
                log INFO "  Copying $(basename "$deb_file") to $remote_ip..."
                scp $SCP_OPTS "$deb_file" "$remote_user@$remote_ip:$remote_pkg_dir/" 2>/dev/null && copied=$((copied + 1))
            fi
        done
    done

    if [[ $copied -eq 0 ]]; then
        log WARNING "No packages found for: ${packages[*]}"
        return 1
    fi

    # Install on remote using APT (not dpkg directly)
    log INFO "Installing packages on $remote_ip via APT..."
    ssh $SSH_OPTS "$remote_user@$remote_ip" "
        cd '$remote_pkg_dir'

        # Generate Packages.gz if not exists
        if [ ! -f Packages.gz ]; then
            if command -v dpkg-scanpackages &>/dev/null; then
                dpkg-scanpackages . /dev/null > Packages 2>/dev/null
                gzip -k -f Packages
            fi
        fi

        # Setup local APT repository
        echo 'deb [trusted=yes] file://$remote_pkg_dir ./' | sudo tee '$repo_list' > /dev/null

        # Update APT cache with local repo
        sudo apt-get update -o Dir::Etc::sourcelist='$repo_list' \
                            -o Dir::Etc::sourceparts='-' \
                            -o APT::Get::List-Cleanup='0' 2>/dev/null || true

        # Install packages via APT (handles dependencies automatically)
        sudo apt-get install -y --no-install-recommends ${packages[*]} 2>/dev/null || {
            # Fallback: fix dependencies
            sudo apt-get install -f -y 2>/dev/null || true
        }

        # Keep repo for future use (don't cleanup)
    " 2>/dev/null

    return 0
}

# Setup offline APT repository on remote node via SCP
# Fallback method when GlusterFS is not available
# Usage: setup_scp_offline_repo_remote <remote_user> <remote_ip>
setup_scp_offline_repo_remote() {
    local remote_user="$1"
    local remote_ip="$2"
    local local_offline_pkg="${OFFLINE_PKG_DIR}/apt_packages"
    local remote_offline_pkg="/tmp/offline_packages"
    local repo_list="/etc/apt/sources.list.d/offline-local.list"

    log INFO "  Setting up offline APT repository via SCP on $remote_ip..."

    if [[ ! -d "$local_offline_pkg" ]]; then
        log ERROR "  Local offline package directory not found: $local_offline_pkg"
        return 1
    fi

    # Create remote directory
    ssh $SSH_OPTS "$remote_user@$remote_ip" "sudo mkdir -p '$remote_offline_pkg' && sudo chmod 777 '$remote_offline_pkg'" 2>/dev/null || {
        log ERROR "  Failed to create remote directory on $remote_ip"
        return 1
    }

    # Copy Packages.gz and essential files first (smaller, faster)
    log INFO "  Copying APT index files..."
    for file in Packages Packages.gz Release package_list.txt; do
        if [[ -f "$local_offline_pkg/$file" ]]; then
            scp $SCP_OPTS "$local_offline_pkg/$file" "$remote_user@$remote_ip:$remote_offline_pkg/" 2>/dev/null || true
        fi
    done

    # Copy all .deb files using rsync for efficiency (with progress)
    log INFO "  Copying .deb packages (this may take a while)..."
    if command -v rsync &>/dev/null; then
        rsync -az --progress -e "ssh $SSH_OPTS" "$local_offline_pkg/"*.deb "$remote_user@$remote_ip:$remote_offline_pkg/" 2>/dev/null || {
            # Fallback to scp if rsync fails
            log WARNING "  rsync failed, falling back to scp..."
            scp $SCP_OPTS "$local_offline_pkg/"*.deb "$remote_user@$remote_ip:$remote_offline_pkg/" 2>/dev/null || {
                log ERROR "  Failed to copy packages to $remote_ip"
                return 1
            }
        }
    else
        scp $SCP_OPTS "$local_offline_pkg/"*.deb "$remote_user@$remote_ip:$remote_offline_pkg/" 2>/dev/null || {
            log ERROR "  Failed to copy packages to $remote_ip"
            return 1
        }
    fi

    # Generate Packages.gz on remote if not copied
    log INFO "  Setting up APT repository on $remote_ip..."
    ssh $SSH_OPTS "$remote_user@$remote_ip" "
        cd '$remote_offline_pkg'

        # Generate Packages.gz if not exists
        if [ ! -f Packages.gz ]; then
            if command -v dpkg-scanpackages &>/dev/null; then
                dpkg-scanpackages . /dev/null > Packages 2>/dev/null
                gzip -k -f Packages
            else
                # Try to install dpkg-dev from local packages
                if ls dpkg-dev*.deb &>/dev/null; then
                    sudo dpkg -i dpkg-dev*.deb 2>/dev/null || true
                    sudo apt-get install -f -y 2>/dev/null || true
                    dpkg-scanpackages . /dev/null > Packages 2>/dev/null
                    gzip -k -f Packages
                fi
            fi
        fi

        # Setup local APT repository
        echo 'deb [trusted=yes] file://$remote_offline_pkg ./' | sudo tee '$repo_list' > /dev/null

        # Update APT cache
        sudo apt-get update -o Dir::Etc::sourcelist='$repo_list' \
                            -o Dir::Etc::sourceparts='-' \
                            -o APT::Get::List-Cleanup='0' 2>/dev/null || sudo apt-get update
    " 2>/dev/null || {
        log WARNING "  APT update had some warnings (may be normal for offline)"
    }

    log SUCCESS "  Offline APT repository configured on $remote_ip via SCP"
    return 0
}

# Setup GlusterFS-based offline APT repository on remote node
# This is the most maintainable solution for offline compute nodes
# Falls back to SCP if GlusterFS is not available
# Usage: setup_glusterfs_offline_repo_remote <remote_user> <remote_ip>
setup_glusterfs_offline_repo_remote() {
    local remote_user="$1"
    local remote_ip="$2"
    local gluster_offline_pkg_path="${GLUSTER_MOUNT}/offline_packages/apt_packages"
    local repo_list="/etc/apt/sources.list.d/glusterfs-offline.list"

    log INFO "  Setting up GlusterFS-based offline APT repository on $remote_ip..."

    # Check if GlusterFS is mounted on the remote node
    if ! ssh $SSH_OPTS "$remote_user@$remote_ip" "mount | grep -q '$GLUSTER_MOUNT'" 2>/dev/null; then
        log WARNING "  GlusterFS not mounted on $remote_ip at $GLUSTER_MOUNT"
        log INFO "  Attempting to mount GlusterFS..."

        # Try to mount GlusterFS on remote node
        ssh $SSH_OPTS "$remote_user@$remote_ip" "
            sudo mkdir -p '$GLUSTER_MOUNT'
            # Try mounting from VIP first, then from any controller
            if ! sudo mount -t glusterfs ${VIP_ADDRESS}:/gv0 '$GLUSTER_MOUNT' 2>/dev/null; then
                if ! sudo mount -t glusterfs ${CURRENT_IP}:/gv0 '$GLUSTER_MOUNT' 2>/dev/null; then
                    echo 'Failed to mount GlusterFS'
                    exit 1
                fi
            fi
        " 2>/dev/null || {
            log WARNING "  GlusterFS mount failed on $remote_ip, falling back to SCP method..."
            # Fallback to SCP-based installation
            setup_scp_offline_repo_remote "$remote_user" "$remote_ip"
            return $?
        }
    fi

    # Check if offline packages exist on GlusterFS
    if ! ssh $SSH_OPTS "$remote_user@$remote_ip" "[ -d '$gluster_offline_pkg_path' ]" 2>/dev/null; then
        log WARNING "  Offline packages not found at $gluster_offline_pkg_path on $remote_ip"
        log INFO "  Copying offline packages to GlusterFS..."

        # Copy from local offline_packages to GlusterFS if it doesn't exist
        local local_offline_pkg="${OFFLINE_PKG_DIR}/apt_packages"
        if [[ -d "$local_offline_pkg" ]]; then
            mkdir -p "${GLUSTER_MOUNT}/offline_packages"
            rsync -a "$local_offline_pkg" "${GLUSTER_MOUNT}/offline_packages/" 2>/dev/null || {
                log ERROR "  Failed to copy offline packages to GlusterFS"
                return 1
            }
            log SUCCESS "  Offline packages copied to GlusterFS"
        else
            log ERROR "  Local offline package directory not found: $local_offline_pkg"
            return 1
        fi
    fi

    # Generate Packages.gz if not exists
    if ! ssh $SSH_OPTS "$remote_user@$remote_ip" "[ -f '$gluster_offline_pkg_path/Packages.gz' ]" 2>/dev/null; then
        log INFO "  Generating APT package index on $remote_ip..."
        ssh $SSH_OPTS "$remote_user@$remote_ip" "
            cd '$gluster_offline_pkg_path'
            if command -v dpkg-scanpackages &>/dev/null; then
                sudo dpkg-scanpackages . /dev/null > Packages 2>/dev/null
                sudo gzip -k -f Packages
            else
                # dpkg-scanpackages not available, try to install dpkg-dev first
                if [ -f dpkg-dev*.deb ]; then
                    sudo dpkg -i dpkg-dev*.deb 2>/dev/null || true
                    sudo apt-get install -f -y 2>/dev/null || true
                    sudo dpkg-scanpackages . /dev/null > Packages 2>/dev/null
                    sudo gzip -k -f Packages
                fi
            fi
        " 2>/dev/null || log WARNING "  Could not generate Packages.gz (may already exist or dpkg-dev missing)"
    fi

    # Setup local APT repository pointing to GlusterFS
    log INFO "  Configuring APT to use GlusterFS offline repository..."
    ssh $SSH_OPTS "$remote_user@$remote_ip" "
        # Create repo list file
        echo 'deb [trusted=yes] file://$gluster_offline_pkg_path ./' | sudo tee '$repo_list' > /dev/null

        # Update APT cache with local repo only
        sudo apt-get update -o Dir::Etc::sourcelist='$repo_list' \
                            -o Dir::Etc::sourceparts='-' \
                            -o APT::Get::List-Cleanup='0' 2>/dev/null || sudo apt-get update
    " 2>/dev/null || {
        log WARNING "  APT update had some warnings (may be normal for offline)"
    }

    log SUCCESS "  GlusterFS-based offline APT repository configured on $remote_ip"
    return 0
}

# Sync offline packages to GlusterFS shared storage (run once on controller)
# This ensures all compute nodes can access offline packages
sync_offline_packages_to_glusterfs() {
    local gluster_offline_pkg_path="${GLUSTER_MOUNT}/offline_packages/apt_packages"
    local local_offline_pkg="${OFFLINE_PKG_DIR}/apt_packages"

    if [[ ! -d "$local_offline_pkg" ]]; then
        log WARNING "Local offline package directory not found: $local_offline_pkg"
        return 1
    fi

    if [[ "$USE_GLUSTERFS" != "true" ]]; then
        log WARNING "GlusterFS not available, skipping sync"
        return 1
    fi

    log INFO "Syncing offline packages to GlusterFS..."

    # Create directory structure
    mkdir -p "${GLUSTER_MOUNT}/offline_packages"

    # Sync packages
    if rsync -a --delete "$local_offline_pkg" "${GLUSTER_MOUNT}/offline_packages/"; then
        log SUCCESS "Offline packages synced to GlusterFS: $gluster_offline_pkg_path"

        # Generate Packages.gz
        if command -v dpkg-scanpackages &>/dev/null; then
            (cd "$gluster_offline_pkg_path" && dpkg-scanpackages . /dev/null > Packages && gzip -k -f Packages)
            log SUCCESS "APT package index generated"
        fi
        return 0
    else
        log ERROR "Failed to sync offline packages to GlusterFS"
        return 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
        log ERROR "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_dependencies() {
    log INFO "Checking dependencies..."

    local deps=("python3" "jq" "munge")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log ERROR "Required dependency not found: $dep"
            log INFO "Install dependencies first"
            exit 1
        fi
    done

    # Check if slurm template exists
    if [[ ! -f "$SLURM_TEMPLATE" ]]; then
        log ERROR "Slurm template not found: $SLURM_TEMPLATE"
        exit 1
    fi

    log SUCCESS "All dependencies satisfied"
}

load_config() {
    log INFO "Loading configuration from $CONFIG_FILE..."

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Get current controller info
    CURRENT_CONTROLLER=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --current 2>/dev/null)
    if [[ -z "$CURRENT_CONTROLLER" ]]; then
        log ERROR "Could not detect current controller. Make sure this server's IP is in the config."
        exit 1
    fi

    # Extract current node info
    CURRENT_IP=$(echo "$CURRENT_CONTROLLER" | jq -r '.ip_address')
    CURRENT_HOSTNAME=$(echo "$CURRENT_CONTROLLER" | jq -r '.hostname')

    # Check if Slurm service is enabled for this controller
    SLURM_ENABLED=$(echo "$CURRENT_CONTROLLER" | jq -r '.services.slurm // false')
    if [[ "$SLURM_ENABLED" != "true" ]] && [[ "$SETUP_COMPUTE" == "false" ]]; then
        log ERROR "Slurm service is not enabled for this controller in the config"
        exit 1
    fi

    log INFO "Current node: $CURRENT_HOSTNAME ($CURRENT_IP)"

    # Get all Slurm-enabled controllers
    SLURM_CONTROLLERS=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --service slurm 2>/dev/null)
    TOTAL_SLURM_NODES=$(echo "$SLURM_CONTROLLERS" | jq '. | length')

    log INFO "Total Slurm-enabled controllers: $TOTAL_SLURM_NODES"

    # Get cluster name - try cluster_info.cluster_name first (multi-head config), then cluster.name as fallback
    CLUSTER_NAME=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cluster_info.cluster_name 2>/dev/null)
    if [[ -z "$CLUSTER_NAME" ]]; then
        CLUSTER_NAME=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cluster.name 2>/dev/null || echo "multihead_cluster")
    fi
    # Slurm ClusterName doesn't allow hyphens - replace with underscores
    CLUSTER_NAME="${CLUSTER_NAME//-/_}"
    log INFO "Cluster name: $CLUSTER_NAME"

    # Get VIP configuration
    VIP_ADDRESS=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get network.vip.address 2>/dev/null || echo "")
    VIP_OWNER_IP=$(echo "$SLURM_CONTROLLERS" | jq -r '.[] | select(.vip_owner == true) | .ip_address' | head -1)

    log INFO "VIP address: $VIP_ADDRESS"
    log INFO "VIP owner: $VIP_OWNER_IP"

    # GlusterFS mount point - try both 'shared_storage' and 'storage' paths for compatibility
    GLUSTER_MOUNT=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get shared_storage.glusterfs.mount_point 2>/dev/null || \
                    python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get storage.glusterfs.mount_point 2>/dev/null || \
                    echo "/mnt/gluster")

    # Also check if GlusterFS service is enabled for this controller
    GLUSTERFS_ENABLED=$(echo "$CURRENT_CONTROLLER" | jq -r '.services.glusterfs // false')
    log INFO "GlusterFS enabled: $GLUSTERFS_ENABLED"
    log INFO "GlusterFS mount point: $GLUSTER_MOUNT"

    # MariaDB config for SlurmDBD with validation
    DB_HOST=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.host 2>/dev/null || echo "$VIP_ADDRESS")
    DB_ROOT_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.root_password 2>/dev/null)

    # Get Slurm DB password from YAML
    # First try: database.mariadb.databases[0].password (where name=slurm_acct_db)
    DB_SLURM_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get "database.mariadb.databases.0.password" 2>/dev/null || echo "")

    # Expand environment variable reference if needed (e.g., "${DB_SLURM_PASSWORD}")
    if [[ "$DB_SLURM_PASSWORD" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
        local env_var="${BASH_REMATCH[1]}"
        # Try shell environment first
        if [[ -n "${!env_var:-}" ]]; then
            DB_SLURM_PASSWORD="${!env_var}"
            log INFO "DB_SLURM_PASSWORD loaded from shell environment: $env_var"
        else
            # Try YAML environment section
            DB_SLURM_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get "environment.$env_var" 2>/dev/null)
            [[ -n "$DB_SLURM_PASSWORD" ]] && log INFO "DB_SLURM_PASSWORD loaded from YAML environment.$env_var"
        fi
    fi

    # Fallback: use root password if slurm password not configured
    if [[ -z "$DB_SLURM_PASSWORD" || "$DB_SLURM_PASSWORD" == "null" ]]; then
        DB_SLURM_PASSWORD="$DB_ROOT_PASSWORD"
        log INFO "DB_SLURM_PASSWORD not set, using root_password as fallback"
    fi

    # Also keep DB_PASSWORD for backward compatibility
    DB_PASSWORD="$DB_ROOT_PASSWORD"

    # Validate password
    if [[ -z "$DB_ROOT_PASSWORD" || "$DB_ROOT_PASSWORD" == "changeme" ]]; then
        log WARNING "⚠️  database.mariadb.root_password is not set or uses insecure default!"
        log WARNING "   This should have been configured in Phase 1 (database setup)"
        DB_ROOT_PASSWORD="changeme"
        DB_PASSWORD="changeme"
    fi

    log INFO "DB_HOST: ${DB_HOST:-localhost}"
    log INFO "DB_SLURM_PASSWORD: [configured from YAML]"

    # Load cgroup configuration
    CGROUP_ENABLED=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cgroup.enabled 2>/dev/null || echo "false")
    CGROUP_CONSTRAIN_RAM=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cgroup.constrain_ram 2>/dev/null || echo "true")
    CGROUP_CONSTRAIN_SWAP=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cgroup.constrain_swap 2>/dev/null || echo "true")
    CGROUP_CONSTRAIN_DEVICES=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cgroup.constrain_devices 2>/dev/null || echo "true")
    CGROUP_CONSTRAIN_CORES=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cgroup.constrain_cores 2>/dev/null || echo "true")
    CGROUP_ALLOWED_RAM=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cgroup.allowed_ram_percent 2>/dev/null || echo "100")
    CGROUP_ALLOWED_SWAP=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cgroup.allowed_swap_percent 2>/dev/null || echo "0")

    # Convert to yes/no for cgroup.conf
    [[ "$CGROUP_CONSTRAIN_RAM" == "true" || "$CGROUP_CONSTRAIN_RAM" == "True" ]] && CGROUP_CONSTRAIN_RAM="yes" || CGROUP_CONSTRAIN_RAM="no"
    [[ "$CGROUP_CONSTRAIN_SWAP" == "true" || "$CGROUP_CONSTRAIN_SWAP" == "True" ]] && CGROUP_CONSTRAIN_SWAP="yes" || CGROUP_CONSTRAIN_SWAP="no"
    [[ "$CGROUP_CONSTRAIN_DEVICES" == "true" || "$CGROUP_CONSTRAIN_DEVICES" == "True" ]] && CGROUP_CONSTRAIN_DEVICES="yes" || CGROUP_CONSTRAIN_DEVICES="no"
    [[ "$CGROUP_CONSTRAIN_CORES" == "true" || "$CGROUP_CONSTRAIN_CORES" == "True" ]] && CGROUP_CONSTRAIN_CORES="yes" || CGROUP_CONSTRAIN_CORES="no"

    log INFO "Cgroup enabled: $CGROUP_ENABLED"
    if [[ "$CGROUP_ENABLED" == "true" || "$CGROUP_ENABLED" == "True" ]]; then
        log INFO "  ConstrainRAMSpace: $CGROUP_CONSTRAIN_RAM"
        log INFO "  ConstrainSwapSpace: $CGROUP_CONSTRAIN_SWAP"
        log INFO "  ConstrainDevices: $CGROUP_CONSTRAIN_DEVICES"
        log INFO "  ConstrainCores: $CGROUP_CONSTRAIN_CORES"
    fi

    log SUCCESS "Configuration loaded successfully"
}

detect_os() {
    log INFO "Detecting operating system..."

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log INFO "Detected OS: $OS $OS_VERSION"
    else
        log ERROR "Cannot detect operating system"
        exit 1
    fi
}

check_slurm_installed() {
    log INFO "Checking if Slurm is installed..."

    if command -v slurmctld &> /dev/null || command -v slurmd &> /dev/null; then
        log SUCCESS "Slurm is already installed"
        SLURM_INSTALLED=true

        # Check version
        SLURM_VERSION=$(slurmctld -V 2>/dev/null | grep -oP '(?<=slurm )[\d.]+' || slurmd -V 2>/dev/null | grep -oP '(?<=slurm )[\d.]+' || echo "unknown")
        log INFO "Slurm version: $SLURM_VERSION"
    else
        log WARNING "Slurm is not installed"
        SLURM_INSTALLED=false
    fi
}

fix_systemd_service_files() {
    # Fix systemd service files to use source-built Slurm 23.x paths
    # 소스 빌드 Slurm은 /usr/local/slurm/sbin에 설치됨
    # apt 패키지 경로(/usr/sbin)가 있으면 소스 빌드 경로로 수정

    log INFO "Checking systemd service files for correct paths..."

    local needs_reload=false
    local SLURM_SBIN="/usr/local/slurm/sbin"

    # Verify source-built Slurm exists
    if [[ ! -x "$SLURM_SBIN/slurmctld" ]]; then
        log WARNING "Source-built slurmctld not found at $SLURM_SBIN/slurmctld"
        log INFO "Skipping systemd service file fixes"
        return 0
    fi

    log INFO "Using source-built Slurm at: $SLURM_SBIN"

    # ==========================================================================
    # Type=forking → Type=simple 마이그레이션
    # 기존 forking 서비스가 실행 중이면 중지하고 simple로 교체
    # ==========================================================================
    log INFO "Checking for Type=forking services (will convert to Type=simple)..."

    for service in slurmctld slurmd slurmdbd; do
        if [[ -f /etc/systemd/system/${service}.service ]]; then
            if grep -q "Type=forking" /etc/systemd/system/${service}.service 2>/dev/null; then
                log WARNING "Found ${service}.service with Type=forking - will convert to Type=simple"

                # 서비스 중지
                if systemctl is-active --quiet "$service" 2>/dev/null; then
                    log INFO "Stopping ${service} service..."
                    systemctl stop "$service" 2>/dev/null || true
                fi

                # 프로세스 강제 종료 (좀비 방지)
                pkill -9 "$service" 2>/dev/null || true
                sleep 1
            fi
        fi
    done

    # /run/slurm 디렉토리 생성 (PID 파일용)
    mkdir -p /run/slurm
    chown slurm:slurm /run/slurm 2>/dev/null || true
    chmod 755 /run/slurm

    # Check slurmctld service file - create if missing, fix if pointing to wrong path
    local slurmctld_needs_create=false
    if [[ ! -f /etc/systemd/system/slurmctld.service ]]; then
        log INFO "slurmctld.service not found, creating..."
        slurmctld_needs_create=true
    elif grep -q "/usr/sbin/slurmctld" /etc/systemd/system/slurmctld.service 2>/dev/null || \
         grep -q "Type=forking" /etc/systemd/system/slurmctld.service 2>/dev/null; then
        log WARNING "Found slurmctld.service needs update (apt path or Type=forking)"
        cp /etc/systemd/system/slurmctld.service /etc/systemd/system/slurmctld.service.backup.$(date +%Y%m%d_%H%M%S)
        slurmctld_needs_create=true
    fi

    if [[ "$slurmctld_needs_create" == "true" ]]; then
        cat > /etc/systemd/system/slurmctld.service << SLURMCTLD_SERVICE
[Unit]
Description=Slurm controller daemon
After=network.target munge.service slurmdbd.service
Wants=slurmdbd.service
Requires=munge.service
ConditionPathExists=/etc/slurm/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmctld
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStartPre=-/bin/bash -c 'mkdir -p /mnt/gluster/slurm/state /mnt/gluster/slurm/log /mnt/gluster/slurm/spool && chown -R slurm:slurm /mnt/gluster/slurm 2>/dev/null && chmod 755 /mnt/gluster/slurm/state /mnt/gluster/slurm/log /mnt/gluster/slurm/spool 2>/dev/null; true'
ExecStart=$SLURM_SBIN/slurmctld -D \$SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SLURMCTLD_SERVICE
        log SUCCESS "slurmctld.service created with $SLURM_SBIN/slurmctld"
        needs_reload=true
    fi

    # Check slurmdbd service file
    # Check slurmdbd service file - fix if pointing to /usr/sbin (apt package path) OR Type=forking
    if [[ -f /etc/systemd/system/slurmdbd.service ]]; then
        if grep -q "/usr/sbin/slurmdbd" /etc/systemd/system/slurmdbd.service 2>/dev/null || \
           grep -q "Type=forking" /etc/systemd/system/slurmdbd.service 2>/dev/null; then
            log WARNING "Found slurmdbd.service needs update (apt path or Type=forking)"
            log INFO "Updating slurmdbd.service to use source-built path with Type=simple..."

            # Backup old service file
            cp /etc/systemd/system/slurmdbd.service /etc/systemd/system/slurmdbd.service.backup.$(date +%Y%m%d_%H%M%S)

            # Create new service file with source-built paths
            cat > /etc/systemd/system/slurmdbd.service << SLURMDBD_SERVICE
[Unit]
Description=Slurm DBD accounting daemon
After=network.target munge.service mariadb.service mysql.service
Requires=munge.service
ConditionPathExists=/etc/slurm/slurmdbd.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmdbd
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStartPre=/bin/sh -c 'pkill -9 slurmdbd || true'
ExecStartPre=/bin/sleep 1
ExecStart=$SLURM_SBIN/slurmdbd -D \$SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
LimitNOFILE=65536
LimitMEMLOCK=infinity
LimitSTACK=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SLURMDBD_SERVICE
            log SUCCESS "slurmdbd.service updated to use $SLURM_SBIN/slurmdbd"
            needs_reload=true
        fi
    fi

    # Check slurmd service file - fix if pointing to /usr/sbin (apt package path) OR Type=forking
    if [[ -f /etc/systemd/system/slurmd.service ]]; then
        if grep -q "/usr/sbin/slurmd" /etc/systemd/system/slurmd.service 2>/dev/null || \
           grep -q "Type=forking" /etc/systemd/system/slurmd.service 2>/dev/null; then
            log WARNING "Found slurmd.service needs update (apt path or Type=forking)"
            log INFO "Updating slurmd.service to use source-built path with Type=simple..."

            # Backup old service file
            cp /etc/systemd/system/slurmd.service /etc/systemd/system/slurmd.service.backup.$(date +%Y%m%d_%H%M%S)

            # Create new service file with source-built paths
            cat > /etc/systemd/system/slurmd.service << SLURMD_SERVICE
[Unit]
Description=Slurm node daemon
After=network.target munge.service remote-fs.target
Requires=munge.service
ConditionPathExists=/etc/slurm/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStart=$SLURM_SBIN/slurmd -D \$SLURMD_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SLURMD_SERVICE
            log SUCCESS "slurmd.service updated to use $SLURM_SBIN/slurmd"
            needs_reload=true
        fi
    fi

    # Create /run/slurm directory if it doesn't exist
    if [[ ! -d /run/slurm ]]; then
        mkdir -p /run/slurm
        chown slurm:slurm /run/slurm
        chmod 755 /run/slurm
    fi

    # Reload systemd if any changes were made
    if [[ "$needs_reload" == "true" ]]; then
        log INFO "Reloading systemd daemon..."
        systemctl daemon-reload
        log SUCCESS "systemd daemon reloaded"
    else
        log SUCCESS "systemd service files already correct"
    fi
}

install_slurm() {
    log INFO "Installing/checking Slurm packages..."

    # ============================================================================
    # 런타임 라이브러리 보장 (소스 빌드 Slurm 의 dlopen 의존성)
    # libpmix2t64, libevent, libhwloc, libucx — 24.04 t64 suffix 주의
    # ============================================================================
    ensure_slurm_runtime_libs() {
        log INFO "Ensuring Slurm runtime libraries (pmix, event, hwloc, ucx)..."
        local need_install=()
        # 24.04 (t64 suffix) / 22.04 (no suffix) 자동 판별
        local OS_VER=$(. /etc/os-release && echo "$VERSION_ID")
        local TSUF=""
        [[ "$OS_VER" == "24.04" ]] && TSUF="t64"

        # 패키지명: libpmix2t64 (24.04) / libpmix2 (22.04)
        local pkgs=(
            "libpmix2${TSUF}"
            "libevent-2.1-7${TSUF}"
            "libevent-core-2.1-7${TSUF}"
            "libhwloc15"
            "libucx0"
            "libmunge2"
            "libnl-3-200"
            "libnl-route-3-200"
        )
        for pkg in "${pkgs[@]}"; do
            if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                need_install+=("$pkg")
            fi
        done

        if [[ ${#need_install[@]} -gt 0 ]]; then
            log INFO "  설치할 패키지: ${need_install[*]}"
            # 오프라인 저장소 우선 (offline-local.list가 등록되어 있으면 apt 가 자동 사용)
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${need_install[@]}" 2>&1 | tail -10 || {
                # 직접 .deb 시도
                local apt_dir="${OFFLINE_PKG_DIR}/apt_packages"
                if [[ -d "$apt_dir" ]]; then
                    local debs=()
                    for p in "${need_install[@]}"; do
                        local f=$(ls "$apt_dir"/${p}_*.deb 2>/dev/null | tail -1)
                        [[ -n "$f" ]] && debs+=("$f")
                    done
                    [[ ${#debs[@]} -gt 0 ]] && \
                        DEBIAN_FRONTEND=noninteractive apt-get install -y "${debs[@]}" 2>&1 | tail -10
                fi
            }
            ldconfig
            log SUCCESS "Slurm 런타임 라이브러리 설치 완료"
        else
            log SUCCESS "Slurm 런타임 라이브러리 모두 존재"
        fi

        # Slurm pmix 플러그인이 .so 잘 찾는지 검증
        local pmix_plugin="/usr/local/slurm/lib/slurm/mpi_pmix_v4.so"
        [[ ! -f "$pmix_plugin" ]] && pmix_plugin="/usr/local/slurm/lib/slurm/mpi_pmix.so"
        if [[ -f "$pmix_plugin" ]]; then
            if ldd "$pmix_plugin" 2>&1 | grep -q "not found"; then
                log WARNING "  $pmix_plugin 의 dlopen 의존성 미해결:"
                ldd "$pmix_plugin" 2>&1 | grep "not found" | head -5
            else
                log SUCCESS "  $pmix_plugin dlopen 의존성 OK"
            fi
        fi
    }
    ensure_slurm_runtime_libs

    # ============================================================================
    # 기존 apt/yum Slurm 패키지 제거 (소스 빌드 23.x만 사용)
    # /usr/bin에 있는 apt 패키지 slurm 바이너리가 충돌을 일으킬 수 있음
    # ============================================================================
    cleanup_apt_slurm() {
        log INFO "Checking for existing apt/yum Slurm packages to remove..."

        local apt_slurm_found=false

        # apt slurm 패키지 확인
        local apt_slurm_packages=(
            "slurm-wlm"
            "slurm-wlm-basic-plugins"
            "slurm-client"
            "slurmctld"
            "slurmd"
            "slurmdbd"
            "libslurm37"
            "libslurm-dev"
            "libslurmdb37"
            "libpmi0"
            "libpmi2-0"
        )

        for pkg in "${apt_slurm_packages[@]}"; do
            if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                apt_slurm_found=true
                log WARNING "Found apt Slurm package: $pkg"
            fi
        done

        if [[ "$apt_slurm_found" == "true" ]]; then
            log WARNING "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log WARNING "apt Slurm 패키지가 설치되어 있습니다. 제거합니다..."
            log WARNING "(소스 빌드 Slurm 23.x와 충돌 방지)"
            log WARNING "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            # apt slurm 패키지만 명시 제거 (autoremove/hold 미사용)
            # 사유: autoremove + apt-mark hold 조합이 실패 시 hold 누수로
            # "pkgProblemResolver::Resolve generated breaks" 유발
            # 소스 빌드 slurm은 /usr/local에 설치되므로 /usr/lib의 잔여 라이브러리는
            # 충돌하지 않음 → autoremove 불필요
            DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge \
                slurm-wlm slurm-wlm-basic-plugins slurm-client \
                slurmctld slurmd slurmdbd \
                libslurm37 libslurm-dev libslurmdb37 \
                libpmi0 libpmi2-0 2>/dev/null || true

            log SUCCESS "apt Slurm 패키지 제거 완료 (autoremove 미실행 — 시스템 패키지 보호)"
        fi

        # apt 패키지의 플러그인 디렉토리 제거 (소스빌드 23.x와 충돌 방지)
        # 이 디렉토리가 남아있으면 Slurm이 잘못된 플러그인을 로드함
        local apt_plugin_dirs=(
            "/usr/lib/x86_64-linux-gnu/slurm-wlm"
            "/usr/lib/x86_64-linux-gnu/slurm"
            "/usr/lib/slurm-wlm"
            "/usr/lib/slurm"
        )
        for plugin_dir in "${apt_plugin_dirs[@]}"; do
            if [[ -d "$plugin_dir" ]]; then
                log WARNING "Removing apt Slurm plugin directory: $plugin_dir"
                rm -rf "$plugin_dir"
                log INFO "  Removed: $plugin_dir"
            fi
        done

        # /usr/bin에 남아있는 slurm 바이너리 제거
        local usr_bin_slurm_binaries=(
            "/usr/bin/sinfo"
            "/usr/bin/squeue"
            "/usr/bin/scontrol"
            "/usr/bin/srun"
            "/usr/bin/sbatch"
            "/usr/bin/scancel"
            "/usr/bin/sacct"
            "/usr/bin/sacctmgr"
            "/usr/bin/salloc"
            "/usr/bin/sstat"
            "/usr/bin/sshare"
            "/usr/bin/sprio"
            "/usr/bin/sreport"
            "/usr/bin/sdiag"
            "/usr/bin/strigger"
            "/usr/sbin/slurmctld"
            "/usr/sbin/slurmd"
            "/usr/sbin/slurmdbd"
        )

        local orphan_binaries_found=false
        for binary in "${usr_bin_slurm_binaries[@]}"; do
            if [[ -f "$binary" ]] || [[ -L "$binary" ]]; then
                orphan_binaries_found=true
                log WARNING "Found orphan Slurm binary: $binary"
            fi
        done

        if [[ "$orphan_binaries_found" == "true" ]]; then
            log WARNING "Removing orphan Slurm binaries from /usr/bin and /usr/sbin..."
            for binary in "${usr_bin_slurm_binaries[@]}"; do
                if [[ -f "$binary" ]] || [[ -L "$binary" ]]; then
                    rm -f "$binary"
                    log INFO "  Removed: $binary"
                fi
            done

            # hash table 갱신
            hash -r 2>/dev/null || true
            log SUCCESS "Orphan Slurm binaries removed"
        fi

        if [[ "$apt_slurm_found" == "false" ]] && [[ "$orphan_binaries_found" == "false" ]]; then
            log INFO "No apt Slurm packages or orphan binaries found. Clean system."
        fi
    }

    # apt slurm 정리 실행
    cleanup_apt_slurm

    # ============================================================================
    # 소스 빌드 Slurm 23.x 확인 (우선순위 높음)
    # /usr/local/slurm/bin 또는 /opt/slurm/bin에 Slurm 23.x가 있으면 apt 패키지 설치 건너뜀
    # ============================================================================
    local SOURCE_SLURM_BIN=""
    local SOURCE_SLURM_SBIN=""
    local SLURM_PREFIX=""

    # 소스 빌드 Slurm 경로 자동 감지 (/usr/local/slurm 또는 /opt/slurm)
    for prefix in /usr/local/slurm /opt/slurm; do
        if [[ -x "$prefix/bin/sinfo" ]]; then
            local slurm_version=$("$prefix/bin/sinfo" --version 2>/dev/null | head -1)
            local major_version=$(echo "$slurm_version" | grep -oP 'slurm \K[0-9]+' | head -1)

            if [[ "$major_version" -ge 23 ]]; then
                SLURM_PREFIX="$prefix"
                SOURCE_SLURM_BIN="$prefix/bin"
                SOURCE_SLURM_SBIN="$prefix/sbin"
                log SUCCESS "Source-built Slurm detected at $prefix: $slurm_version"
                break
            else
                log WARNING "Slurm at $prefix is too old: $slurm_version (need 23.x+)"
            fi
        fi
    done

    # 소스 빌드 Slurm 23.x가 있으면 apt 패키지 설치 건너뜀
    if [[ -n "$SLURM_PREFIX" ]]; then
        log INFO "Using source-built Slurm from $SLURM_PREFIX (skipping apt package installation)"

        # PATH에 소스 빌드 Slurm 추가 (현재 스크립트 환경)
        export PATH="$SOURCE_SLURM_BIN:$SOURCE_SLURM_SBIN:$PATH"

        # hash table 갱신 (bash가 올바른 경로 사용하도록)
        hash -r 2>/dev/null || true

        # /etc/profile.d/slurm.sh 확인 및 생성
        if [[ ! -f /etc/profile.d/slurm.sh ]] || ! grep -q "^export PATH=$SOURCE_SLURM_BIN" /etc/profile.d/slurm.sh 2>/dev/null; then
            log INFO "Creating/updating /etc/profile.d/slurm.sh..."
            cat > /etc/profile.d/slurm.sh << EOFPATH
# Slurm Environment (source-built Slurm 23.x)
# Automatically generated by phase3_slurm.sh
export PATH=$SOURCE_SLURM_BIN:$SOURCE_SLURM_SBIN:\$PATH
export LD_LIBRARY_PATH=$SLURM_PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
export MANPATH=$SLURM_PREFIX/share/man\${MANPATH:+:\$MANPATH}
EOFPATH
            chmod 644 /etc/profile.d/slurm.sh
            log SUCCESS "Created /etc/profile.d/slurm.sh"
        fi

        # 현재 쉘에서도 바로 사용할 수 있도록 source
        source /etc/profile.d/slurm.sh 2>/dev/null || true

        # 설치 확인
        log INFO "Verifying Slurm installation..."
        log INFO "  sinfo: $(which sinfo 2>/dev/null || echo 'not found')"
        log INFO "  slurmctld: $(which slurmctld 2>/dev/null || echo 'not found')"
        log INFO "  slurmd: $(which slurmd 2>/dev/null || echo 'not found')"
        log INFO "  slurmdbd: $(which slurmdbd 2>/dev/null || echo 'not found')"

        return 0
    fi

    # ============================================================================
    # 소스 빌드 Slurm 23.x 자동 설치 (오프라인 프리빌드 패키지 사용)
    # ============================================================================
    log INFO "소스 빌드 Slurm 23.x가 없습니다. 오프라인 프리빌드 패키지에서 설치합니다..."

    local SLURM_PREBUILT_DIR="${OFFLINE_PKG_DIR}/slurm"
    local SLURM_TARBALL=""
    local DEPLOY_SCRIPT=""

    # 프리빌드 tarball 찾기
    for tarball in "$SLURM_PREBUILT_DIR"/slurm-*-prebuilt.tar.gz; do
        if [[ -f "$tarball" ]]; then
            SLURM_TARBALL="$tarball"
            break
        fi
    done

    if [[ -z "$SLURM_TARBALL" ]]; then
        log ERROR "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log ERROR "Slurm 프리빌드 패키지를 찾을 수 없습니다!"
        log ERROR "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log ERROR ""
        log ERROR "  예상 경로: ${SLURM_PREBUILT_DIR}/slurm-*-prebuilt.tar.gz"
        log ERROR ""
        log ERROR "  빌드 방법:"
        log ERROR "     cd ${SLURM_PREBUILT_DIR}"
        log ERROR "     bash build_slurm_package.sh"
        log ERROR ""
        exit 1
    fi

    log INFO "프리빌드 패키지 발견: $(basename "$SLURM_TARBALL")"

    # tarball 압축 해제
    log INFO "프리빌드 패키지 압축 해제 중..."
    cd "$SLURM_PREBUILT_DIR"
    tar -xzf "$SLURM_TARBALL"

    # deploy_slurm.sh 찾기
    if [[ -f "$SLURM_PREBUILT_DIR/deploy_slurm.sh" ]]; then
        DEPLOY_SCRIPT="$SLURM_PREBUILT_DIR/deploy_slurm.sh"
    else
        log ERROR "deploy_slurm.sh를 찾을 수 없습니다!"
        log ERROR "프리빌드 패키지가 손상되었거나 형식이 올바르지 않습니다."
        exit 1
    fi

    # deploy_slurm.sh 실행
    log INFO "Slurm 23.x 설치 중... (deploy_slurm.sh)"
    if bash "$DEPLOY_SCRIPT"; then
        log SUCCESS "Slurm 23.x 설치 완료!"
    else
        log ERROR "Slurm 설치 실패!"
        exit 1
    fi

    # PATH 설정 적용
    log INFO "PATH 설정 적용 중..."
    if [[ -f /etc/profile.d/slurm.sh ]]; then
        source /etc/profile.d/slurm.sh 2>/dev/null || true
    fi
    hash -r 2>/dev/null || true

    # 설치 확인
    log INFO "Slurm 바이너리 확인 중..."
    local installed_version=""
    for prefix in /usr/local/slurm /opt/slurm; do
        log INFO "  확인: $prefix/bin/sinfo"
        if [[ -x "$prefix/bin/sinfo" ]]; then
            # sinfo --version은 slurm.conf 없어도 동작함
            # 하지만 pipefail 때문에 || true로 보호
            installed_version=$("$prefix/bin/sinfo" --version 2>&1 | head -1 || true)
            if [[ -z "$installed_version" ]]; then
                # --version 실패 시 바이너리 존재만 확인
                installed_version="binary exists (version check failed)"
            fi
            SLURM_PREFIX="$prefix"
            SOURCE_SLURM_BIN="$prefix/bin"
            SOURCE_SLURM_SBIN="$prefix/sbin"
            log INFO "  → 발견: $installed_version"
            break
        else
            log INFO "  → 없음"
        fi
    done

    if [[ -n "$installed_version" ]]; then
        log SUCCESS "Slurm 설치 확인: $installed_version"
        log INFO "  설치 경로: $SLURM_PREFIX"
        log INFO "  sinfo: $(which sinfo 2>/dev/null || echo "$SOURCE_SLURM_BIN/sinfo")"
        log INFO "  slurmctld: $(which slurmctld 2>/dev/null || echo "$SOURCE_SLURM_SBIN/slurmctld")"
        log INFO "  slurmd: $(which slurmd 2>/dev/null || echo "$SOURCE_SLURM_SBIN/slurmd")"
        log INFO "  slurmdbd: $(which slurmdbd 2>/dev/null || echo "$SOURCE_SLURM_SBIN/slurmdbd")"

        # PATH 설정
        export PATH="$SOURCE_SLURM_BIN:$SOURCE_SLURM_SBIN:$PATH"
    else
        log ERROR "Slurm 설치 후에도 바이너리를 찾을 수 없습니다!"
        log ERROR "  /usr/local/slurm/bin/sinfo 존재 여부: $(ls -la /usr/local/slurm/bin/sinfo 2>&1 || echo '없음')"
        log ERROR "  /opt/slurm/bin/sinfo 존재 여부: $(ls -la /opt/slurm/bin/sinfo 2>&1 || echo '없음')"
        exit 1
    fi

    cd "$PROJECT_ROOT"

    # Fix systemd service files if they point to wrong paths
    # This happens when a custom-compiled Slurm was previously installed
    fix_systemd_service_files

    # Disable slurmd on controller nodes (only run slurmctld)
    # UNLESS this controller is also a compute/viz node
    if [[ "$SETUP_CONTROLLER" == "true" ]] && [[ "$SETUP_COMPUTE" == "false" ]]; then
        # Check if this controller is also in compute_nodes (for GPU/viz usage)
        local hostname=$(hostname)
        local is_also_compute=false

        if [[ -f "$CONFIG_FILE" ]]; then
            is_also_compute=$(python3 << EOPY
import yaml
import sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
    hostname = '$hostname'
    compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
    for node in compute_nodes:
        if node.get('hostname') == hostname:
            print('true')
            sys.exit(0)
    print('false')
except:
    print('false')
EOPY
)
        fi

        if [[ "$is_also_compute" == "true" ]]; then
            log INFO "Controller node also used as compute/viz - keeping slurmd enabled"
            log INFO "Installing compute node requirements (apptainer, etc.)..."

            # Install apptainer if not present
            if ! command -v apptainer &>/dev/null; then
                log INFO "Installing apptainer for job execution..."
                apt-get update >/dev/null 2>&1
                apt-get install -y apptainer 2>&1 | grep -v "^W:" || {
                    log WARNING "apptainer installation failed - may need manual installation"
                }
                if command -v apptainer &>/dev/null; then
                    log SUCCESS "apptainer installed: $(apptainer --version)"
                fi
            else
                log SUCCESS "apptainer already installed: $(apptainer --version)"
            fi

            # Create /scratch/vnc_sandboxes for VNC jobs
            mkdir -p /scratch/vnc_sandboxes
            chmod 1777 /scratch/vnc_sandboxes
            log SUCCESS "/scratch/vnc_sandboxes created"

            # Ensure slurmd is enabled and started
            systemctl unmask slurmd 2>/dev/null || true
            systemctl enable slurmd 2>/dev/null || true
            systemctl restart slurmd 2>/dev/null || true

            if systemctl is-active --quiet slurmd; then
                log SUCCESS "slurmd enabled and running on controller+compute node"
            else
                log WARNING "slurmd failed to start - check systemctl status slurmd"
            fi
        else
            log INFO "Controller-only node: disabling slurmd service"
            systemctl stop slurmd 2>/dev/null || true
            systemctl disable slurmd 2>/dev/null || true
            systemctl mask slurmd 2>/dev/null || true
            log SUCCESS "slurmd disabled on controller"
        fi
    fi

    # Disable slurmctld on compute-only nodes
    if [[ "$SETUP_COMPUTE" == "true" ]] && [[ "$SETUP_CONTROLLER" == "false" ]]; then
        log INFO "Compute node: disabling slurmctld service"
        systemctl stop slurmctld 2>/dev/null || true
        systemctl disable slurmctld 2>/dev/null || true
        systemctl mask slurmctld 2>/dev/null || true
        log SUCCESS "slurmctld disabled on compute node"
    fi
}

create_slurm_user() {
    log INFO "Creating slurm user..."

    # Get UID/GID from YAML config (default to 64001 to avoid conflicts with system accounts)
    local target_slurm_uid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('users',{}).get('slurm_uid', 64001))" 2>/dev/null || echo 64001)
    local target_slurm_gid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('users',{}).get('slurm_gid', 64001))" 2>/dev/null || echo 64001)

    log INFO "  Target UID/GID: $target_slurm_uid/$target_slurm_gid"

    if id "slurm" &>/dev/null; then
        local existing_uid=$(id -u slurm)
        local existing_gid=$(id -g slurm)
        log INFO "User 'slurm' already exists (UID=$existing_uid, GID=$existing_gid)"

        # Check if UID/GID matches
        if [[ "$existing_uid" != "$target_slurm_uid" ]] || [[ "$existing_gid" != "$target_slurm_gid" ]]; then
            log WARNING "Existing slurm user UID/GID ($existing_uid/$existing_gid) differs from target ($target_slurm_uid/$target_slurm_gid)"
            log INFO "Keeping existing user to avoid breaking system"
        fi
    else
        # Create group first
        if ! getent group slurm &>/dev/null; then
            run_command "groupadd -g $target_slurm_gid slurm 2>/dev/null || groupadd slurm" "Create slurm group"
        fi

        # Create user with specific UID if possible
        if run_command "useradd -r -u $target_slurm_uid -g slurm -s /bin/false -d /nonexistent slurm 2>/dev/null || useradd -r -g slurm -s /bin/false -d /nonexistent slurm" "Create slurm user"; then
            log SUCCESS "User 'slurm' created (UID=$(id -u slurm), GID=$(id -g slurm))"
        fi
    fi

    # Create directories
    run_command "mkdir -p /var/spool/slurmd /var/spool/slurmctld /var/log/slurm"
    run_command "chown -R slurm:slurm /var/spool/slurmd /var/spool/slurmctld /var/log/slurm"
    run_command "chmod 755 /var/spool/slurmd /var/spool/slurmctld /var/log/slurm"
}

setup_munge() {
    log INFO "Setting up Munge authentication..."

    # Clean up existing munge state first to ensure fresh start
    log INFO "Cleaning up existing munge state..."
    systemctl stop munge 2>/dev/null || true

    # Remove old munge key (will be regenerated or synced)
    if [[ -f /etc/munge/munge.key ]]; then
        log INFO "  Removing existing munge key..."
        rm -f /etc/munge/munge.key
    fi

    # Clean up munge runtime files
    rm -rf /var/run/munge/* 2>/dev/null || true
    rm -rf /run/munge/* 2>/dev/null || true

    # Ensure munge directories exist with correct permissions
    mkdir -p /etc/munge /var/lib/munge /var/log/munge /var/run/munge /run/munge
    chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /var/run/munge /run/munge 2>/dev/null || true
    chmod 700 /etc/munge /var/lib/munge
    chmod 755 /var/log/munge /var/run/munge /run/munge

    log SUCCESS "Munge state cleaned up"

    # Determine if this is the first (primary) controller
    local first_controller_ip=$(echo "$SLURM_CONTROLLERS" | jq -r '.[0].ip_address')
    local is_first_controller=false

    if [[ "$CURRENT_IP" == "$first_controller_ip" ]]; then
        is_first_controller=true
        log INFO "This is the first controller - will generate munge key"
    else
        log INFO "This is a secondary controller - will sync munge key from first controller"
    fi

    if [[ "$is_first_controller" == "true" ]]; then
        # First controller: Always generate new munge key (we just deleted the old one)
        log INFO "Generating munge key on primary controller..."

        # Try multiple methods to generate munge key (different distros use different commands)
        if [[ "$DRY_RUN" == "false" ]]; then
            local key_generated=false

            # Method 1: mungekey (Ubuntu/Debian standard)
            if command -v mungekey &> /dev/null; then
                log INFO "  Using mungekey command..."
                mungekey --create --force 2>/dev/null && key_generated=true
            fi

            # Method 2: create-munge-key (RHEL/CentOS)
            if [[ "$key_generated" == "false" ]] && command -v create-munge-key &> /dev/null; then
                log INFO "  Using create-munge-key command..."
                create-munge-key -f 2>/dev/null && key_generated=true
            fi

            # Method 3: /usr/sbin/mungekey (explicit path)
            if [[ "$key_generated" == "false" ]] && [[ -x /usr/sbin/mungekey ]]; then
                log INFO "  Using /usr/sbin/mungekey..."
                /usr/sbin/mungekey --create --force 2>/dev/null && key_generated=true
            fi

            # Method 4: /usr/sbin/create-munge-key (explicit path)
            if [[ "$key_generated" == "false" ]] && [[ -x /usr/sbin/create-munge-key ]]; then
                log INFO "  Using /usr/sbin/create-munge-key..."
                /usr/sbin/create-munge-key -f 2>/dev/null && key_generated=true
            fi

            # Method 5: dd (fallback - works on any Linux)
            if [[ "$key_generated" == "false" ]]; then
                log INFO "  Using dd to generate key (fallback)..."
                dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key 2>/dev/null && key_generated=true
            fi

            if [[ "$key_generated" == "false" ]]; then
                log ERROR "Failed to generate munge key with any method"
                exit 1
            fi

            log SUCCESS "Munge key generated successfully"
        else
            log INFO "[DRY-RUN] Would generate munge key"
        fi
    else
        # Secondary controller: Sync munge key from first controller
        log INFO "Synchronizing munge key from primary controller ($first_controller_ip)..."
        log INFO ""

        local first_controller_user=$(echo "$SLURM_CONTROLLERS" | jq -r '.[0].ssh_user // "root"')

        if [[ "$DRY_RUN" == "false" ]]; then
            # First, test SSH connectivity to primary controller
            log INFO "  Testing SSH connectivity to primary controller..."
            setup_node_ssh_opts "$first_controller_user" "$first_controller_ip" || true
            local ssh_test_output=""
            local ssh_test_exit=0
            ssh_test_output=$(ssh $SSH_OPTS "$first_controller_user@$first_controller_ip" "echo 'SSH OK'" 2>&1) || ssh_test_exit=$?

            if [[ $ssh_test_exit -ne 0 ]]; then
                log WARNING "  ⚠️  Primary controller ($first_controller_ip) 도달 불가 — 로컬 fallback 사용"
                log WARNING "  진단: ssh $first_controller_user@$first_controller_ip"
                log WARNING ""

                # Generate local key as fallback
                if [[ ! -f /etc/munge/munge.key ]]; then
                    log WARNING "Generating local munge key as fallback (NOT RECOMMENDED)"
                    log WARNING "⚠️  Slurm authentication will fail between controllers!"
                    # Try multiple methods
                    if command -v mungekey &> /dev/null; then
                        mungekey --create --force 2>/dev/null
                    elif [[ -x /usr/sbin/mungekey ]]; then
                        /usr/sbin/mungekey --create --force 2>/dev/null
                    elif command -v create-munge-key &> /dev/null; then
                        create-munge-key -f 2>/dev/null
                    else
                        dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key 2>/dev/null
                    fi
                fi
            else
                log SUCCESS "  SSH connectivity OK"

                # Backup existing key if present
                if [[ -f /etc/munge/munge.key ]]; then
                    cp /etc/munge/munge.key /etc/munge/munge.key.backup.$(date +%Y%m%d_%H%M%S)
                    log INFO "  Existing munge key backed up"
                fi

                # Copy munge key from first controller
                local max_attempts=3
                local attempt=1
                local synced=false

                while [[ $attempt -le $max_attempts ]]; do
                    log INFO "  Attempt $attempt/$max_attempts: Fetching munge key..."

                    local scp_error=""
                    local scp_exit=0
                    scp_error=$(scp $SCP_OPTS "$first_controller_user@$first_controller_ip:/etc/munge/munge.key" /tmp/munge.key.sync 2>&1) || scp_exit=$?

                    if [[ $scp_exit -eq 0 ]]; then
                        # Verify key is valid (non-empty)
                        if [[ -s /tmp/munge.key.sync ]]; then
                            mv /tmp/munge.key.sync /etc/munge/munge.key
                            log SUCCESS "  ✅ Munge key synchronized from primary controller"
                            synced=true
                            break
                        else
                            log WARNING "  Received empty munge key, retrying..."
                            rm -f /tmp/munge.key.sync
                        fi
                    else
                        log WARNING "  SCP failed: $scp_error"
                        log WARNING "  Retrying..."
                    fi

                    attempt=$((attempt + 1))
                    sleep 2
                done

                if [[ "$synced" == "false" ]]; then
                    log ERROR ""
                    log ERROR "❌ Failed to synchronize munge key after $max_attempts attempts"
                    log ERROR ""
                    log ERROR "⚠️  Slurm authentication will fail between controllers!"
                    log ERROR ""
                    log ERROR "Manual fix options:"
                    log ERROR "  Option 1: Copy directly"
                    log ERROR "    scp $first_controller_user@$first_controller_ip:/etc/munge/munge.key /etc/munge/"
                    log ERROR ""
                    log ERROR "  Option 2: Base64 encoding (if scp fails)"
                    log ERROR "    On primary controller: base64 /etc/munge/munge.key"
                    log ERROR "    On this node: echo '<base64_output>' | base64 -d > /etc/munge/munge.key"
                    log ERROR ""

                    # Generate a local key as fallback (will cause auth issues but won't crash)
                    if [[ ! -f /etc/munge/munge.key ]]; then
                        log WARNING "Generating local munge key as fallback (NOT RECOMMENDED)"
                        # Try multiple methods
                        if command -v mungekey &> /dev/null; then
                            mungekey --create --force 2>/dev/null
                        elif [[ -x /usr/sbin/mungekey ]]; then
                            /usr/sbin/mungekey --create --force 2>/dev/null
                        elif command -v create-munge-key &> /dev/null; then
                            create-munge-key -f 2>/dev/null
                        else
                            dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key 2>/dev/null
                        fi
                    fi
                fi
            fi
        else
            log INFO "[DRY-RUN] Would sync munge key from $first_controller_ip"
        fi
    fi

    # Set permissions
    run_command "chown munge:munge /etc/munge/munge.key"
    run_command "chmod 400 /etc/munge/munge.key"

    # Enable and start munge
    run_command "systemctl enable munge"
    run_command "systemctl restart munge"

    # Test munge
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 1  # Give munge a moment to start
        if munge -n | unmunge &>/dev/null; then
            log SUCCESS "Munge is working"
        else
            log ERROR "Munge test failed"
            log ERROR "Check: journalctl -u munge -n 20"
            exit 1
        fi
    fi

    # If first controller, sync key to all other controllers
    if [[ "$is_first_controller" == "true" ]] && [[ "$DRY_RUN" == "false" ]]; then
        log INFO "Distributing munge key to other controllers..."
        log INFO ""

        local sync_count=0
        local fail_count=0
        local total_other_controllers=0
        local failed_controllers=()

        while IFS= read -r controller; do
            local ctrl_ip=$(echo "$controller" | jq -r '.ip_address')
            local ctrl_hostname=$(echo "$controller" | jq -r '.hostname')
            local ctrl_user=$(echo "$controller" | jq -r '.ssh_user // "root"')

            # Skip self
            if [[ "$ctrl_ip" == "$CURRENT_IP" ]]; then
                continue
            fi

            total_other_controllers=$((total_other_controllers + 1))
            log INFO "  [$total_other_controllers] Syncing munge key to $ctrl_hostname ($ctrl_ip)..."

            # First verify SSH connectivity to the target controller
            log INFO "      Testing SSH connectivity..."
            # ctrl_user의 키 자동 탐색 (stcx 등 deploy 계정 케이스) — SSH_OPTS 오버라이드
            setup_node_ssh_opts "$ctrl_user" "$ctrl_ip" || true
            local ssh_test_output=""
            local ssh_test_exit=0
            ssh_test_output=$(ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "echo 'SSH OK'" 2>&1) || ssh_test_exit=$?

            if [[ $ssh_test_exit -ne 0 ]]; then
                log WARNING "      ⚠️  $ctrl_hostname ($ctrl_ip) 도달 불가 (exit=$ssh_test_exit) — 스킵"
                log WARNING "      ssh stderr: ${ssh_test_output:0:200}"
                fail_count=$((fail_count + 1))
                failed_controllers+=("$ctrl_hostname")
                continue
            fi
            log SUCCESS "      SSH connectivity OK"

            # Use a temporary variable to capture scp errors
            # Note: munge.key is owned by munge:munge with 400 permissions
            # We need to read it as root (which we are since script runs with sudo)
            log INFO "      Copying munge key..."

            # First check if we can read the local munge key
            if [[ ! -r /etc/munge/munge.key ]]; then
                log ERROR "      Cannot read /etc/munge/munge.key (permission denied)"
                fail_count=$((fail_count + 1))
                failed_controllers+=("$ctrl_hostname")
                continue
            fi

            # Check if munge is installed on remote, if not copy offline packages
            local munge_installed
            munge_installed=$(ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "dpkg -l | grep -q '^ii.*munge ' && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")

            if [[ "$munge_installed" == "no" ]]; then
                log INFO "      Munge not installed on $ctrl_hostname, copying offline packages..."
                local offline_pkg_dir="${OFFLINE_PKG_DIR}/apt_packages"
                local remote_pkg_dir="/tmp/munge_packages"
                local repo_list="/etc/apt/sources.list.d/offline-munge.list"

                if [[ -d "$offline_pkg_dir" ]]; then
                    # Create temp directory on remote
                    ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "sudo mkdir -p '$remote_pkg_dir' && sudo chmod 777 '$remote_pkg_dir'" 2>/dev/null || true

                    # Copy Packages.gz for APT
                    if [[ -f "$offline_pkg_dir/Packages.gz" ]]; then
                        scp $SCP_OPTS "$offline_pkg_dir/Packages.gz" "$ctrl_user@$ctrl_ip:$remote_pkg_dir/" 2>/dev/null || true
                        scp $SCP_OPTS "$offline_pkg_dir/Packages" "$ctrl_user@$ctrl_ip:$remote_pkg_dir/" 2>/dev/null || true
                    fi

                    # Copy munge packages
                    local munge_pkgs=("munge_"*.deb "libmunge2_"*.deb "libmunge-dev_"*.deb)
                    for pkg_pattern in "${munge_pkgs[@]}"; do
                        for pkg_file in "$offline_pkg_dir"/$pkg_pattern; do
                            if [[ -f "$pkg_file" ]]; then
                                log INFO "        Copying $(basename "$pkg_file")..."
                                scp $SCP_OPTS "$pkg_file" "$ctrl_user@$ctrl_ip:$remote_pkg_dir/" 2>/dev/null || true
                            fi
                        done
                    done

                    # Install packages on remote using APT (not dpkg directly)
                    log INFO "      Installing munge packages on $ctrl_hostname via APT..."
                    ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "
                        cd '$remote_pkg_dir'

                        # Generate Packages.gz if not exists
                        if [ ! -f Packages.gz ]; then
                            if command -v dpkg-scanpackages &>/dev/null; then
                                dpkg-scanpackages . /dev/null > Packages 2>/dev/null
                                gzip -k -f Packages
                            fi
                        fi

                        # Setup local APT repository
                        echo 'deb [trusted=yes] file://$remote_pkg_dir ./' | sudo tee '$repo_list' > /dev/null

                        # Update APT cache with local repo
                        sudo apt-get update -o Dir::Etc::sourcelist='$repo_list' \
                                            -o Dir::Etc::sourceparts='-' \
                                            -o APT::Get::List-Cleanup='0' 2>/dev/null || true

                        # Install munge via APT (handles dependencies automatically)
                        sudo apt-get install -y --no-install-recommends munge libmunge2 2>/dev/null || {
                            sudo apt-get install -f -y 2>/dev/null || true
                        }

                        # Keep repo for future use
                    " 2>/dev/null || true

                    log SUCCESS "      Munge packages installed on $ctrl_hostname via APT"
                else
                    log WARNING "      Offline package directory not found: $offline_pkg_dir"
                fi
            fi

            local scp_error
            local scp_exit
            # Use timeout to prevent hanging
            # Note: Use || true to prevent set -e from killing the script on SCP failure
            scp_error=$(timeout 30 scp $SCP_OPTS /etc/munge/munge.key "$ctrl_user@$ctrl_ip:/tmp/munge.key.sync" 2>&1) || true
            scp_exit=${PIPESTATUS[0]}
            # If PIPESTATUS is empty, check the command substitution exit code
            if [[ -z "$scp_exit" ]] || [[ "$scp_exit" -eq 0 && -z "$scp_error" ]]; then
                # Command succeeded
                scp_exit=0
            elif [[ -n "$scp_error" ]]; then
                # There was an error, check if it's a real failure
                # SCP returns non-zero on failure
                scp_exit=1
            fi

            # Alternative: Try to check if the file was transferred
            if timeout 5 ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "test -f /tmp/munge.key.sync" 2>/dev/null; then
                scp_exit=0
            fi

            # Check for timeout (exit code 124 from timeout command)
            if echo "$scp_error" | grep -qi "timed out\|timeout"; then
                log ERROR "      SCP timed out after 30 seconds"
                fail_count=$((fail_count + 1))
                failed_controllers+=("$ctrl_hostname")
                continue
            fi

            if [[ $scp_exit -eq 0 ]]; then
                log SUCCESS "      File transferred"
                log INFO "      Cleaning up and installing munge key..."

                # Clean up existing munge state, install new key, and restart service
                # Note: Capture exit code BEFORE || true to preserve failure status
                local ssh_error
                local ssh_exit
                set +e  # Temporarily disable errexit
                ssh_error=$(ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "
                    # Verify munge package is installed (should have been installed via offline packages above)
                    if ! dpkg -l | grep -q '^ii.*munge ' && ! rpm -q munge &> /dev/null 2>&1; then
                        echo 'ERROR: munge package is not installed. Offline package installation may have failed.'
                        exit 1
                    fi

                    # Create munge user if not exists
                    if ! id munge &> /dev/null; then
                        sudo useradd -r -s /sbin/nologin munge 2>/dev/null || true
                    fi

                    sudo systemctl stop munge 2>/dev/null || true
                    sudo rm -f /etc/munge/munge.key 2>/dev/null || true
                    sudo rm -rf /var/run/munge/* /run/munge/* 2>/dev/null || true
                    sudo mkdir -p /etc/munge /var/lib/munge /var/log/munge /var/run/munge /run/munge
                    sudo mv /tmp/munge.key.sync /etc/munge/munge.key
                    sudo chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /var/run/munge /run/munge 2>/dev/null || true
                    sudo chmod 700 /etc/munge /var/lib/munge
                    sudo chmod 400 /etc/munge/munge.key
                    sudo chmod 755 /var/log/munge /var/run/munge /run/munge
                    sudo systemctl enable munge 2>/dev/null || true
                    sudo systemctl start munge
                " 2>&1)
                ssh_exit=$?
                set -e  # Re-enable errexit

                if [[ $ssh_exit -eq 0 ]]; then
                    # Verify munge is actually running on the remote node
                    local verify_error
                    verify_error=$(ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "systemctl is-active munge 2>/dev/null || echo 'inactive'" 2>&1)
                    if [[ "$verify_error" == "active" ]]; then
                        log SUCCESS "      ✅ Munge key synced to $ctrl_hostname (service running)"
                        sync_count=$((sync_count + 1))
                    else
                        log WARNING "      ⚠️  Munge key copied but service not running on $ctrl_hostname"
                        log WARNING "      Status: $verify_error"
                        sync_count=$((sync_count + 1))  # Key was copied, count as partial success
                    fi
                else
                    log ERROR "      ❌ Failed to install munge key on $ctrl_hostname"
                    log ERROR "      Error: $ssh_error"
                    fail_count=$((fail_count + 1))
                    failed_controllers+=("$ctrl_hostname")
                fi
            else
                log ERROR "      ❌ Failed to copy munge key to $ctrl_hostname"
                log ERROR "      SCP error: $scp_error"
                fail_count=$((fail_count + 1))
                failed_controllers+=("$ctrl_hostname")
            fi
            log INFO ""
        done < <(echo "$SLURM_CONTROLLERS" | jq -c '.[]')

        # Summary
        log INFO "=== Munge Key Distribution Summary ==="
        if [[ $sync_count -gt 0 ]]; then
            log SUCCESS "  ✅ Successfully synced: $sync_count controller(s)"
        fi
        if [[ $fail_count -gt 0 ]]; then
            log WARNING "  ⚠️  Failed (도달 불가): $fail_count controller(s)"
            log WARNING "  Failed controllers: ${failed_controllers[*]}"
            log WARNING ""
            log WARNING "  💡 도달 가능한 노드들은 정상 동기화됨"
            log WARNING "  도달 불가 노드 살아나면 phase3만 재실행:"
            log WARNING "    sudo bash cluster/setup/phase3_slurm.sh --config <YAML>"
            log WARNING "  또는 수동: scp /etc/munge/munge.key user@host:/etc/munge/"
            log WARNING ""
        fi
        if [[ $total_other_controllers -eq 0 ]]; then
            log INFO "  (No other controllers to sync - single controller setup)"
        fi
    fi
}

check_glusterfs_mounted() {
    log INFO "Checking if GlusterFS is mounted..."

    if mount | grep -q "$GLUSTER_MOUNT"; then
        log SUCCESS "GlusterFS is mounted at $GLUSTER_MOUNT"
        USE_GLUSTERFS=true
    else
        log WARNING "GlusterFS is not mounted at $GLUSTER_MOUNT"

        # Check if GlusterFS is expected to be enabled
        if [[ "$GLUSTERFS_ENABLED" == "true" ]]; then
            log WARNING "GlusterFS is enabled in config but not mounted"
            log WARNING "You may want to run Phase 0 (GlusterFS setup) first"
            log INFO "Proceeding with local directories instead..."
        else
            log INFO "GlusterFS is not enabled for this controller"
        fi

        # Fallback: Use local directories for Slurm state
        USE_GLUSTERFS=false
        log INFO "Will use local directories for Slurm state management"
    fi
}

create_shared_directories() {
    if [[ "$USE_GLUSTERFS" == "true" ]]; then
        log INFO "Creating shared Slurm directories on GlusterFS..."

        local state_dir="$GLUSTER_MOUNT/slurm/state"
        local log_dir="$GLUSTER_MOUNT/slurm/logs"
        local spool_dir="$GLUSTER_MOUNT/slurm/spool"

        run_command "mkdir -p $state_dir $log_dir $spool_dir"
        run_command "chown -R slurm:slurm $GLUSTER_MOUNT/slurm"
        run_command "chmod 755 $state_dir $log_dir $spool_dir"
        # GlusterFS 마운트 타이밍으로 권한이 root로 돌아올 수 있어 재보정
        chown -R slurm:slurm "$GLUSTER_MOUNT/slurm" 2>/dev/null || true
        chmod 755 "$state_dir" "$log_dir" "$spool_dir" 2>/dev/null || true

        # Set paths for slurm.conf
        SLURM_STATE_DIR="$state_dir"
        SLURM_LOG_DIR="$log_dir"

        log SUCCESS "Shared directories created on GlusterFS"
    else
        log INFO "Creating local Slurm directories..."

        # Fallback to local directories
        local state_dir="/var/spool/slurmctld"
        local log_dir="/var/log/slurm"
        local spool_dir="/var/spool/slurmd"

        run_command "mkdir -p $state_dir $log_dir $spool_dir"
        run_command "chown -R slurm:slurm $state_dir $log_dir $spool_dir"
        run_command "chmod 755 $state_dir $log_dir $spool_dir"

        # Set paths for slurm.conf
        SLURM_STATE_DIR="$state_dir"
        SLURM_LOG_DIR="$log_dir"

        log SUCCESS "Local directories created"
        log WARNING "Note: Without shared storage, Slurm state is local to each controller"
        log WARNING "This may affect failover capabilities in multi-controller setup"
    fi
}

generate_slurmctld_hosts() {
    log INFO "Generating SlurmctldHost entries..."

    # VIP owner is primary (listed first)
    local slurmctld_hosts=""

    # Add VIP owner first
    if [[ -n "$VIP_OWNER_IP" ]]; then
        local vip_owner_hostname=$(echo "$SLURM_CONTROLLERS" | jq -r ".[] | select(.ip_address == \"$VIP_OWNER_IP\") | .hostname")
        slurmctld_hosts="SlurmctldHost=${vip_owner_hostname}(${VIP_OWNER_IP})"
        log INFO "Primary controller: $vip_owner_hostname ($VIP_OWNER_IP)"
    fi

    # Add other controllers as backups
    while IFS= read -r controller; do
        local hostname=$(echo "$controller" | jq -r '.hostname')
        local ip=$(echo "$controller" | jq -r '.ip_address')

        # Skip VIP owner (already added)
        if [[ "$ip" == "$VIP_OWNER_IP" ]]; then
            continue
        fi

        if [[ -n "$slurmctld_hosts" ]]; then
            slurmctld_hosts="${slurmctld_hosts}\n"
        fi
        slurmctld_hosts="${slurmctld_hosts}SlurmctldHost=${hostname}(${ip})"
        log INFO "Backup controller: $hostname ($ip)"
    done < <(echo "$SLURM_CONTROLLERS" | jq -c '.[]')

    SLURMCTLD_HOSTS="$slurmctld_hosts"
}

generate_node_definitions() {
    log INFO "Generating node definitions from YAML..."

    local node_defs=""

    # Get compute + viz nodes from YAML (both run slurmd)
    local compute_nodes=$(python3 -c "
import yaml, json
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
nodes = cfg.get('nodes', {})
all_nodes = nodes.get('compute_nodes', []) + nodes.get('viz_nodes', [])
print(json.dumps(all_nodes))
" 2>/dev/null || echo "[]")

    # Generate NodeName entries
    while IFS= read -r node; do
        local hostname=$(echo "$node" | jq -r '.hostname')
        local node_addr=$(echo "$node" | jq -r '.ip_address // ""')
        local cpus=$(echo "$node" | jq -r '.hardware.cpus // 1')
        local sockets=$(echo "$node" | jq -r '.hardware.sockets // 1')
        local cores_per_socket=$(echo "$node" | jq -r '.hardware.cores_per_socket // 1')
        local threads_per_core=$(echo "$node" | jq -r '.hardware.threads_per_core // 1')
        local real_memory=$(echo "$node" | jq -r '.hardware.memory_mb // 1024')
        local tmp_disk=$(echo "$node" | jq -r '.hardware.tmp_disk_mb // 10240')
        local gres=$(echo "$node" | jq -r '.hardware.gres // ""')

        if [[ -n "$node_defs" ]]; then
            node_defs="${node_defs}\n"
        fi

        # Build node definition with optional fields
        local node_line="NodeName=${hostname}"
        [[ -n "$node_addr" ]] && node_line="${node_line} NodeAddr=${node_addr}"
        node_line="${node_line} CPUs=${cpus} Sockets=${sockets} CoresPerSocket=${cores_per_socket} ThreadsPerCore=${threads_per_core} RealMemory=${real_memory}"
        [[ -n "$gres" ]] && node_line="${node_line} Gres=${gres}"
        node_line="${node_line} State=UNKNOWN"

        node_defs="${node_defs}${node_line}"
    done < <(echo "$compute_nodes" | jq -c '.[]')

    if [[ -z "$node_defs" ]]; then
        # No compute nodes defined, create example
        node_defs="# NodeName=node[001-010] CPUs=8 RealMemory=16384 TmpDisk=102400 State=UNKNOWN"
        log WARNING "No compute nodes defined in YAML, added example entry"
    fi

    NODE_DEFINITIONS="$node_defs"
}

generate_partition_definitions() {
    log INFO "Generating partition definitions..."

    local partition_defs=""
    local default_partition=""

    # Get partitions from YAML (try slurm_config.partitions first, then slurm.partitions)
    local partitions=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get slurm_config.partitions 2>/dev/null || echo "[]")
    if [[ "$partitions" == "[]" ]] || [[ -z "$partitions" ]]; then
        partitions=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get slurm.partitions 2>/dev/null || echo "[]")
    fi

    # Generate PartitionName entries
    local part_count=0
    while IFS= read -r partition; do
        local name=$(echo "$partition" | jq -r '.name')
        local nodes=$(echo "$partition" | jq -r '.nodes // "ALL"')
        local default=$(echo "$partition" | jq -r '.default // false')
        local max_time=$(echo "$partition" | jq -r '.max_time // "INFINITE"')
        local state=$(echo "$partition" | jq -r '.state // "UP"')

        if [[ -n "$partition_defs" ]]; then
            partition_defs="${partition_defs}\n"
        fi
        partition_defs="${partition_defs}PartitionName=${name} Nodes=${nodes} Default=${default} MaxTime=${max_time} State=${state}"

        if [[ "$default" == "true" ]] || [[ "$default" == "YES" ]]; then
            default_partition="# Default partition: ${name}"
        fi

        part_count=$((part_count + 1))
    done < <(echo "$partitions" | jq -c '.[]')

    if [[ $part_count -eq 0 ]]; then
        # No partitions defined, create default
        partition_defs="PartitionName=debug Nodes=ALL Default=YES MaxTime=INFINITE State=UP"
        default_partition="# Default partition: debug"
        log WARNING "No partitions defined in YAML, added default 'debug' partition"
    fi

    PARTITION_DEFINITIONS="$partition_defs"
    DEFAULT_PARTITION="$default_partition"
}

generate_slurm_config() {
    log INFO "Generating Slurm configuration from template..."

    # Generate dynamic sections
    generate_slurmctld_hosts
    generate_node_definitions
    generate_partition_definitions

    # Auto-detect Slurm plugin directory (소스 빌드 23.x 우선)
    # apt 패키지 21.x (/usr/lib/x86_64-linux-gnu/slurm-wlm)는 지원하지 않음
    local PLUGIN_DIR
    if [[ -d "/usr/local/slurm/lib/slurm" ]]; then
        # Source install (23.x) - 우선 사용
        PLUGIN_DIR="/usr/local/slurm/lib/slurm"
    elif [[ -d "/opt/slurm/lib/slurm" ]]; then
        # Alternative source install path
        PLUGIN_DIR="/opt/slurm/lib/slurm"
    elif [[ -d "/usr/lib64/slurm" ]]; then
        # CentOS/RedHat package install
        PLUGIN_DIR="/usr/lib64/slurm"
    else
        # Default fallback to source install path
        PLUGIN_DIR="/usr/local/slurm/lib/slurm"
        log WARNING "Could not auto-detect Slurm plugin directory, using default: $PLUGIN_DIR"
    fi
    log INFO "Using Slurm plugin directory: $PLUGIN_DIR"

    # Read template and substitute variables
    local config_content
    config_content=$(cat "$SLURM_TEMPLATE")

    # Substitute template variables
    # Use SLURM_STATE_DIR and SLURM_LOG_DIR which are set based on GlusterFS availability
    config_content="${config_content//\{\{CLUSTER_NAME\}\}/$CLUSTER_NAME}"
    config_content="${config_content//\{\{SLURMCTLD_HOSTS\}\}/$SLURMCTLD_HOSTS}"
    config_content="${config_content//\{\{STATE_SAVE_LOCATION\}\}/$SLURM_STATE_DIR}"
    config_content="${config_content//\{\{SLURMCTLD_LOG_FILE\}\}/$SLURM_LOG_DIR/slurmctld.log}"
    config_content="${config_content//\{\{SLURMD_LOG_FILE\}\}/\/var\/log\/slurm\/slurmd.log}"
    config_content="${config_content//\{\{ACCOUNTING_STORAGE_HOST:-localhost\}\}/localhost}"
    config_content="${config_content//\{\{PLUGIN_DIR:-\/usr\/local\/slurm\/lib\/slurm\}\}/$PLUGIN_DIR}"
    config_content="${config_content//\{\{NODE_DEFINITIONS\}\}/$NODE_DEFINITIONS}"
    config_content="${config_content//\{\{PARTITION_DEFINITIONS\}\}/$PARTITION_DEFINITIONS}"
    config_content="${config_content//\{\{DEFAULT_PARTITION\}\}/$DEFAULT_PARTITION}"

    # GPU 노드가 있으면 GresTypes=gpu 자동 활성화
    if echo "$NODE_DEFINITIONS" | grep -q "Gres="; then
        config_content="${config_content/# GresTypes=gpu/GresTypes=gpu}"
        log INFO "GPU nodes detected: enabling GresTypes=gpu"
    fi

    # Substitute cgroup-related placeholders
    local PROCTRACK_TYPE
    local TASK_PLUGIN
    if [[ "$CGROUP_ENABLED" == "true" || "$CGROUP_ENABLED" == "True" ]]; then
        PROCTRACK_TYPE="proctrack/cgroup"
        TASK_PLUGIN="task/cgroup,task/affinity"
        log INFO "Cgroup enabled: using proctrack/cgroup and task/cgroup"
    else
        PROCTRACK_TYPE="proctrack/linuxproc"
        TASK_PLUGIN="task/affinity"
        log INFO "Cgroup disabled: using proctrack/linuxproc and task/affinity only"
    fi
    config_content="${config_content//\{\{PROCTRACK_TYPE\}\}/$PROCTRACK_TYPE}"
    config_content="${config_content//\{\{TASK_PLUGIN\}\}/$TASK_PLUGIN}"

    log INFO "Using state directory: $SLURM_STATE_DIR"
    log INFO "Using log directory: $SLURM_LOG_DIR"

    # Backup existing config
    if [[ -f "$SLURM_CONFIG" ]] && [[ "$DRY_RUN" == "false" ]]; then
        cp "$SLURM_CONFIG" "${SLURM_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        log INFO "Backed up existing config"
    fi

    # Write configuration file
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would write Slurm config to: $SLURM_CONFIG"
        log INFO "[DRY-RUN] Config preview (first 50 lines):"
        echo "$config_content" | head -50
    else
        # Write to /etc/slurm/slurm.conf (primary location)
        mkdir -p "$(dirname "$SLURM_CONFIG")"
        echo -e "$config_content" > "$SLURM_CONFIG"
        chmod 644 "$SLURM_CONFIG"
        chown slurm:slurm "$SLURM_CONFIG"
        log SUCCESS "Slurm configuration written to $SLURM_CONFIG"

        # Also copy to /usr/local/slurm/etc/ for source-built Slurm compatibility
        local LOCAL_SLURM_ETC="/usr/local/slurm/etc"
        if [[ -d "$LOCAL_SLURM_ETC" ]] || [[ -d "/usr/local/slurm" ]]; then
            mkdir -p "$LOCAL_SLURM_ETC"
            cp "$SLURM_CONFIG" "$LOCAL_SLURM_ETC/slurm.conf"
            chmod 644 "$LOCAL_SLURM_ETC/slurm.conf"
            chown slurm:slurm "$LOCAL_SLURM_ETC/slurm.conf"
            log SUCCESS "Slurm configuration also copied to $LOCAL_SLURM_ETC/slurm.conf"
        fi
    fi
}

generate_cgroup_config() {
    # Generate cgroup.conf if cgroup is enabled
    if [[ "$CGROUP_ENABLED" != "true" && "$CGROUP_ENABLED" != "True" ]]; then
        log INFO "Cgroup disabled in YAML, skipping cgroup.conf generation"
        return 0
    fi

    log INFO "Generating cgroup.conf for cgroup v2 resource control..."

    local CGROUP_CONFIG_DIR
    local CGROUP_CONFIG_FILE

    # Determine config directory based on OS
    if [[ -d "/etc/slurm" ]]; then
        CGROUP_CONFIG_DIR="/etc/slurm"
    elif [[ -d "/etc/slurm-llnl" ]]; then
        CGROUP_CONFIG_DIR="/etc/slurm-llnl"
    else
        CGROUP_CONFIG_DIR="/etc/slurm"
        mkdir -p "$CGROUP_CONFIG_DIR"
    fi
    CGROUP_CONFIG_FILE="${CGROUP_CONFIG_DIR}/cgroup.conf"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would write cgroup.conf to: $CGROUP_CONFIG_FILE"
        log INFO "[DRY-RUN] Settings:"
        log INFO "  ConstrainRAMSpace=$CGROUP_CONSTRAIN_RAM"
        log INFO "  ConstrainSwapSpace=$CGROUP_CONSTRAIN_SWAP"
        log INFO "  ConstrainDevices=$CGROUP_CONSTRAIN_DEVICES"
        log INFO "  ConstrainCores=$CGROUP_CONSTRAIN_CORES"
        log INFO "  AllowedRAMSpace=$CGROUP_ALLOWED_RAM"
        log INFO "  AllowedSwapSpace=$CGROUP_ALLOWED_SWAP"
        return 0
    fi

    # Backup existing config
    if [[ -f "$CGROUP_CONFIG_FILE" ]]; then
        cp "$CGROUP_CONFIG_FILE" "${CGROUP_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log INFO "Backed up existing cgroup.conf"
    fi

    # Generate cgroup.conf
    {
        echo "################################################################################"
        echo "# Slurm cgroup.conf - cgroup v2 Configuration"
        echo "# Auto-generated by phase3_slurm.sh at $(date)"
        echo "# Source: YAML configuration (cgroup section)"
        echo "################################################################################"
        echo ""
        echo "# ============================================================================"
        echo "# Resource Constraining (from YAML cgroup settings)"
        echo "# ============================================================================"
        echo ""
        echo "# Enable memory constraining (limit job memory usage)"
        echo "ConstrainRAMSpace=${CGROUP_CONSTRAIN_RAM}"
        echo ""
        echo "# Enable swap constraining (prevent swap usage)"
        echo "ConstrainSwapSpace=${CGROUP_CONSTRAIN_SWAP}"
        echo ""
        echo "# Enable device constraining (GPU access control)"
        echo "ConstrainDevices=${CGROUP_CONSTRAIN_DEVICES}"
        echo ""
        echo "# Enable core constraining (CPU affinity)"
        echo "ConstrainCores=${CGROUP_CONSTRAIN_CORES}"
        echo ""
        echo "# ============================================================================"
        echo "# Memory Settings"
        echo "# ============================================================================"
        echo ""
        echo "# Allowed RAM usage as percentage of allocated memory"
        echo "AllowedRAMSpace=${CGROUP_ALLOWED_RAM}"
        echo ""
        echo "# Allowed swap usage as percentage (0 = no swap)"
        echo "AllowedSwapSpace=${CGROUP_ALLOWED_SWAP}"
        echo ""
        echo "################################################################################"
        echo "# Notes:"
        echo "# - cgroup v2 is auto-detected by Slurm 23.x+"
        echo "# - slurm.conf uses: ProctrackType=proctrack/cgroup"
        echo "# - slurm.conf uses: TaskPlugin=task/cgroup,task/affinity"
        echo "################################################################################"
    } > "$CGROUP_CONFIG_FILE"

    chmod 644 "$CGROUP_CONFIG_FILE"
    chown slurm:slurm "$CGROUP_CONFIG_FILE"

    log SUCCESS "cgroup.conf written to $CGROUP_CONFIG_FILE"
}

generate_gres_config() {
    # Generate gres.conf for GPU nodes
    log INFO "Generating gres.conf for GPU resource management..."

    local GRES_CONFIG_DIR="/etc/slurm"
    local GRES_CONFIG_FILE="${GRES_CONFIG_DIR}/gres.conf"

    # YAML에서 GPU 노드 정보 추출
    local gpu_nodes=$(python3 <<EOPY
import yaml
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
except Exception as e:
    sys.exit(0)  # YAML 읽기 실패 시 조용히 종료

nodes = config.get('nodes', {})
gpu_entries = []

# compute_nodes 확인
for node in nodes.get('compute_nodes', []):
    hostname = node.get('hostname', '')
    hardware = node.get('hardware', {})
    gpus = hardware.get('gpus', 0)
    gpu_type = hardware.get('gpu_type', 'nvidia')
    if gpus > 0:
        gpu_entries.append(f"{hostname}|{gpus}|{gpu_type}")

# viz_nodes 확인
for node in nodes.get('viz_nodes', []):
    hostname = node.get('hostname', '')
    hardware = node.get('hardware', {})
    gpus = hardware.get('gpus', 0)
    gpu_type = hardware.get('gpu_type', 'nvidia')
    if gpus > 0:
        gpu_entries.append(f"{hostname}|{gpus}|{gpu_type}")

for entry in gpu_entries:
    print(entry)
EOPY
)

    # GPU 노드가 없으면 건너뜀
    if [[ -z "$gpu_nodes" ]]; then
        log INFO "No GPU nodes found in YAML, skipping gres.conf generation"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would write gres.conf to: $GRES_CONFIG_FILE"
        log INFO "[DRY-RUN] GPU nodes:"
        while IFS='|' read -r hostname gpu_count gpu_type; do
            log INFO "  $hostname: $gpu_count x $gpu_type"
        done <<< "$gpu_nodes"
        return 0
    fi

    # gres.conf 생성
    mkdir -p "$GRES_CONFIG_DIR"
    {
        echo "################################################################################"
        echo "# gres.conf - Generic Resource (GRES) Configuration for Slurm"
        echo "#"
        echo "# Auto-generated from: $CONFIG_FILE"
        echo "# Generated on: $(date)"
        echo "################################################################################"
        echo ""

        while IFS='|' read -r hostname gpu_count gpu_type; do
            [[ -z "$hostname" ]] && continue

            echo "# Node: $hostname ($gpu_count x $gpu_type GPU)"
            for ((i=0; i<gpu_count; i++)); do
                case "$gpu_type" in
                    nvidia)
                        device_file="/dev/nvidia$i"
                        ;;
                    amd)
                        device_file="/dev/dri/renderD$((128+i))"
                        ;;
                    *)
                        device_file="/dev/gpu$i"
                        ;;
                esac
                echo "NodeName=$hostname Name=gpu Type=$gpu_type File=$device_file"
            done
            echo ""
        done <<< "$gpu_nodes"

        echo "################################################################################"
        echo "# GPU Detection Commands:"
        echo "#   NVIDIA: nvidia-smi"
        echo "#   AMD:    rocm-smi"
        echo "################################################################################"
    } > "$GRES_CONFIG_FILE"

    chmod 644 "$GRES_CONFIG_FILE"
    chown slurm:slurm "$GRES_CONFIG_FILE"

    log SUCCESS "gres.conf written to $GRES_CONFIG_FILE"

    # GPU 노드 목록 출력
    log INFO "GPU nodes configured:"
    while IFS='|' read -r hostname gpu_count gpu_type; do
        log INFO "  $hostname: $gpu_count x $gpu_type"
    done <<< "$gpu_nodes"
}

setup_slurmdbd() {
    log INFO "Setting up SlurmDBD..."

    # Determine SLURM_PREFIX for plugin directory
    local SLURM_PREFIX="/usr/local/slurm"
    if [[ -x "/opt/slurm/sbin/slurmdbd" ]]; then
        SLURM_PREFIX="/opt/slurm"
    fi

    # Validate and set DB_HOST with fallback
    local SLURMDBD_STORAGE_HOST="${DB_HOST:-localhost}"
    if [[ -z "$SLURMDBD_STORAGE_HOST" ]] || [[ "$SLURMDBD_STORAGE_HOST" == "null" ]]; then
        SLURMDBD_STORAGE_HOST="localhost"
    fi

    # Use DB_SLURM_PASSWORD from YAML (loaded in load_config)
    # This is the password for the 'slurm' database user
    local SLURMDBD_STORAGE_PASS="${DB_SLURM_PASSWORD:-changeme}"
    if [[ -z "$SLURMDBD_STORAGE_PASS" ]] || [[ "$SLURMDBD_STORAGE_PASS" == "null" ]]; then
        SLURMDBD_STORAGE_PASS="changeme"
        log WARNING "DB_SLURM_PASSWORD not set, using insecure default 'changeme'"
    fi

    log INFO "SlurmDBD StorageHost: $SLURMDBD_STORAGE_HOST"
    log INFO "SlurmDBD StoragePass: [configured from YAML - database.mariadb.databases[0].password]"

    # Create slurmdbd.conf using printf to avoid variable expansion issues
    # Note: slurmdbd.conf does NOT support quoted values - use plain text
    {
        echo "# SlurmDBD Configuration"
        echo "# Auto-generated by cluster/setup/phase3_slurm.sh"
        echo "# Password loaded from YAML: database.mariadb.databases[0].password"
        echo ""
        echo "# Archive info"
        echo "#ArchiveJobs=yes"
        echo "#ArchiveDir=/tmp"
        echo "#ArchiveSteps=yes"
        echo "#ArchiveScript="
        echo "#JobPurge=12"
        echo "#StepPurge=1"
        echo ""
        echo "# Authentication"
        echo "AuthType=auth/munge"
        echo "PluginDir=${SLURM_PREFIX}/lib/slurm"
        echo ""
        echo "# Database settings"
        echo "DbdHost=localhost"
        echo "DbdPort=6819"
        echo "SlurmUser=slurm"
        echo "LogFile=/var/log/slurm/slurmdbd.log"
        echo "PidFile=/var/run/slurm/slurmdbd.pid"
        echo ""
        echo "# Database connection"
        echo "StorageType=accounting_storage/mysql"
        echo "StorageHost=${SLURMDBD_STORAGE_HOST}"
        echo "StoragePort=3306"
        echo "StorageUser=slurm"
        echo "StoragePass=${SLURMDBD_STORAGE_PASS}"
        echo "StorageLoc=slurm_acct_db"
        echo ""
        echo "# Purge settings"
        echo "#PurgeEventAfter=1month"
        echo "#PurgeJobAfter=12month"
        echo "#PurgeResvAfter=1month"
        echo "#PurgeStepAfter=1month"
        echo "#PurgeSuspendAfter=1month"
        echo "#PurgeTXNAfter=12month"
        echo "#PurgeUsageAfter=24month"
    } > "$SLURMDBD_CONFIG"

    chmod 600 "$SLURMDBD_CONFIG"
    chown slurm:slurm "$SLURMDBD_CONFIG"

    log SUCCESS "SlurmDBD configuration created"

    # Create database and user with password from YAML
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO "Creating SlurmDBD database and user..."

        # Use DB_ROOT_PASSWORD for root login, DB_SLURM_PASSWORD for slurm user
        local mysql_host="${SLURMDBD_STORAGE_HOST}"
        if [[ "$mysql_host" == "localhost" ]]; then
            # For localhost, don't use -h option
            log WARNING "Dropping existing slurm_acct_db to avoid schema version conflicts..."
            mysql -u root -p"${DB_ROOT_PASSWORD}" <<EOSQL
DROP DATABASE IF EXISTS slurm_acct_db;
CREATE DATABASE slurm_acct_db;
DROP USER IF EXISTS 'slurm'@'localhost';
DROP USER IF EXISTS 'slurm'@'%';
CREATE USER 'slurm'@'localhost' IDENTIFIED BY '${SLURMDBD_STORAGE_PASS}';
CREATE USER 'slurm'@'%' IDENTIFIED BY '${SLURMDBD_STORAGE_PASS}';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'%';
FLUSH PRIVILEGES;
EOSQL
        else
            log WARNING "Dropping existing slurm_acct_db to avoid schema version conflicts..."
            mysql -h "$mysql_host" -u root -p"${DB_ROOT_PASSWORD}" <<EOSQL
DROP DATABASE IF EXISTS slurm_acct_db;
CREATE DATABASE slurm_acct_db;
DROP USER IF EXISTS 'slurm'@'localhost';
DROP USER IF EXISTS 'slurm'@'%';
CREATE USER 'slurm'@'localhost' IDENTIFIED BY '${SLURMDBD_STORAGE_PASS}';
CREATE USER 'slurm'@'%' IDENTIFIED BY '${SLURMDBD_STORAGE_PASS}';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'%';
FLUSH PRIVILEGES;
EOSQL
        fi

        if [[ $? -eq 0 ]]; then
            log SUCCESS "SlurmDBD database and user created with password from YAML"
        else
            log ERROR "Failed to create SlurmDBD database/user"
            log ERROR "Check MariaDB root password in YAML: database.mariadb.root_password"
        fi
    fi

    # Check if slurmdbd service exists before enabling
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! systemctl list-unit-files slurmdbd.service &>/dev/null; then
            log WARNING "slurmdbd.service not found!"

            # 소스 빌드 Slurm 확인 (apt 패키지 대신 systemd 서비스 직접 생성)
            if [[ -x /usr/local/slurm/sbin/slurmdbd ]] || [[ -x /opt/slurm/sbin/slurmdbd ]]; then
                local SLURM_PREFIX="/usr/local/slurm"
                [[ -x /opt/slurm/sbin/slurmdbd ]] && SLURM_PREFIX="/opt/slurm"

                log INFO "Found source-built slurmdbd at $SLURM_PREFIX/sbin/slurmdbd"
                log INFO "Creating systemd service file for source-built slurmdbd..."

                cat > /etc/systemd/system/slurmdbd.service << EOFSLURMDBD
[Unit]
Description=Slurm DBD accounting daemon
After=network-online.target munge.service mysql.service mariadb.service
Wants=network-online.target
ConditionPathExists=${SLURM_PREFIX}/etc/slurmdbd.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmdbd
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStartPre=/bin/sh -c 'pkill -9 slurmdbd || true'
ExecStartPre=/bin/sleep 1
ExecStart=${SLURM_PREFIX}/sbin/slurmdbd -D \$SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
LimitNOFILE=65536
LimitMEMLOCK=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSLURMDBD
                chmod 644 /etc/systemd/system/slurmdbd.service
                systemctl daemon-reload
                log SUCCESS "Created slurmdbd.service for source-built Slurm"
            else
                # 소스 빌드 Slurm 23.x 필수
                log ERROR "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                log ERROR "slurmdbd가 설치되지 않았습니다!"
                log ERROR "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                log ERROR ""
                log ERROR "  소스 빌드 Slurm 23.x를 먼저 설치해야 합니다."
                log ERROR "  apt/yum 패키지의 slurmdbd는 지원하지 않습니다."
                log ERROR ""
                log ERROR "  설치 방법:"
                log ERROR "     cd ${OFFLINE_PKG_DIR}/slurm"
                log ERROR "     tar -xzf slurm-23.11.10-prebuilt.tar.gz"
                log ERROR "     sudo bash deploy_slurm.sh"
                log ERROR ""
                log WARNING "Skipping SlurmDBD setup - accounting will not be available"
                return 1
            fi
        fi
    fi

    # Pre-flight checks before starting slurmdbd
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO "Running pre-flight checks before starting SlurmDBD..."

        # Check 1: Munge service
        if ! systemctl is-active --quiet munge; then
            log WARNING "Munge service not active, attempting to start..."
            systemctl start munge 2>/dev/null || true
            sleep 2
            if ! systemctl is-active --quiet munge; then
                log ERROR "Munge service failed to start - SlurmDBD requires munge!"
                log ERROR "Check munge key and permissions: ls -la /etc/munge/munge.key"
                log WARNING "Continuing anyway, but SlurmDBD will likely fail..."
            else
                log SUCCESS "Munge service started successfully"
            fi
        else
            log SUCCESS "Munge service is active"
        fi

        # Check 2: MariaDB connectivity
        local mysql_host="${SLURMDBD_STORAGE_HOST}"
        local mysql_check_cmd=""
        if [[ "$mysql_host" == "localhost" ]]; then
            mysql_check_cmd="mysql -u root -p'${DB_ROOT_PASSWORD}' -e 'SELECT 1' 2>/dev/null"
        else
            mysql_check_cmd="mysql -h '$mysql_host' -u root -p'${DB_ROOT_PASSWORD}' -e 'SELECT 1' 2>/dev/null"
        fi

        if eval "$mysql_check_cmd"; then
            log SUCCESS "MariaDB connection successful"
        else
            log WARNING "MariaDB connection failed - checking if service is running..."
            if systemctl is-active --quiet mariadb; then
                log INFO "MariaDB is running but connection failed - check credentials"
            elif systemctl is-active --quiet mysql; then
                log INFO "MySQL is running but connection failed - check credentials"
            else
                log ERROR "MariaDB/MySQL service is not running!"
                log INFO "Attempting to start mariadb..."
                systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
                sleep 3
            fi
        fi
    fi

    # Cleanup before starting slurmdbd
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create PID directory with correct permissions
        log INFO "Preparing slurmdbd runtime directories..."
        mkdir -p /run/slurm /var/run/slurm
        chown slurm:slurm /run/slurm /var/run/slurm 2>/dev/null || true
        chmod 755 /run/slurm /var/run/slurm

        # Kill any leftover slurmdbd processes
        if pgrep -x slurmdbd > /dev/null 2>&1; then
            log WARNING "Found leftover slurmdbd processes, killing them..."
            pkill -9 -x slurmdbd 2>/dev/null || true
            sleep 2
        fi

        # Remove stale PID files
        rm -f /run/slurm/slurmdbd.pid /var/run/slurm/slurmdbd.pid /var/run/slurmdbd.pid 2>/dev/null || true
    fi

    # Enable and start slurmdbd
    run_command "systemctl enable slurmdbd"

    log INFO "Starting slurmdbd service..."
    run_command "systemctl restart slurmdbd"

    # Verify service started
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 3
        if systemctl is-active --quiet slurmdbd; then
            log SUCCESS "SlurmDBD started successfully"
        else
            log ERROR "❌ SlurmDBD failed to start!"
            log ERROR ""
            log ERROR "=== SlurmDBD Diagnostic Information ==="
            log ERROR "1. Service status:"
            systemctl status slurmdbd --no-pager 2>&1 | head -15 || true
            log ERROR ""
            log ERROR "2. Recent logs:"
            journalctl -u slurmdbd -n 20 --no-pager 2>&1 || true
            log ERROR ""
            log ERROR "3. Common causes:"
            log ERROR "   - MariaDB not running or not reachable"
            log ERROR "   - Wrong database credentials in slurmdbd.conf"
            log ERROR "   - Munge service not running"
            log ERROR "   - Permission issues on /var/log/slurm/"
            log ERROR ""
            log ERROR "4. Manual debug:"
            log ERROR "   slurmdbd -Dvvv"
            log ERROR ""
            log ERROR "5. Check MariaDB connection:"
            log ERROR "   mysql -h $SLURMDBD_STORAGE_HOST -u slurm_user -p slurm_acct_db"
            log ERROR ""
            # Don't exit - slurmctld can still work without accounting
            log WARNING "Continuing without accounting database (SlurmDBD)..."
        fi
    else
        log SUCCESS "SlurmDBD setup completed (dry-run)"
    fi
}

start_slurmctld() {
    log INFO "Starting slurmctld service..."

    # Pre-flight checks
    log INFO "Pre-flight checks for slurmctld..."

    # Check munge is running
    if ! systemctl is-active --quiet munge; then
        log WARNING "Munge service is not running - starting it first"
        systemctl start munge
        sleep 2
        if ! systemctl is-active --quiet munge; then
            log ERROR "Failed to start munge service"
            log ERROR "Check: journalctl -u munge -n 30"
            exit 1
        fi
    fi
    log SUCCESS "  Munge service is running"

    # Check slurm.conf exists
    if [[ ! -f /etc/slurm/slurm.conf ]]; then
        log ERROR "slurm.conf not found at /etc/slurm/slurm.conf"
        exit 1
    fi
    log SUCCESS "  slurm.conf exists"

    # Check slurm.conf syntax
    if command -v slurmctld &>/dev/null; then
        log INFO "  Checking slurm.conf syntax..."
        local config_test
        config_test=$(slurmctld -t 2>&1) || true
        if [[ -n "$config_test" ]] && echo "$config_test" | grep -qi "error"; then
            log WARNING "  Config issues found: $config_test"
        fi
    fi

    # Check state directory permissions
    local state_dir=$(grep "^StateSaveLocation" /etc/slurm/slurm.conf | awk -F= '{print $2}' | tr -d ' ')
    if [[ -n "$state_dir" ]]; then
        if [[ ! -d "$state_dir" ]]; then
            log WARNING "State directory $state_dir does not exist - creating"
            mkdir -p "$state_dir"
            chown slurm:slurm "$state_dir"
            chmod 755 "$state_dir"
        fi
        log SUCCESS "  State directory exists: $state_dir"
    fi

    # Enable service
    run_command "systemctl enable slurmctld"

    # Start service
    log INFO "Starting slurmctld..."
    run_command "systemctl restart slurmctld"

    # Wait for service to start
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 5

        if systemctl is-active --quiet slurmctld; then
            log SUCCESS "slurmctld started successfully"
        else
            log ERROR "Failed to start slurmctld"
            log ERROR ""
            log ERROR "=== Diagnostic Information ==="
            log ERROR "1. Service status:"
            systemctl status slurmctld --no-pager 2>&1 | head -20 || true
            log ERROR ""
            log ERROR "2. Recent logs:"
            journalctl -u slurmctld -n 30 --no-pager 2>&1 || true
            log ERROR ""
            log ERROR "3. Check these common issues:"
            log ERROR "   - Munge key mismatch between controllers"
            log ERROR "   - SlurmDBD not running (if accounting enabled)"
            log ERROR "   - Incorrect hostname/IP in slurm.conf"
            log ERROR "   - State directory permissions"
            log ERROR ""
            log ERROR "Run manually to see detailed errors:"
            log ERROR "   slurmctld -Dvvv"
            exit 1
        fi
    fi
}

start_slurmd() {
    log INFO "Starting slurmd service..."

    # Enable service
    run_command "systemctl enable slurmd"

    # Start service
    run_command "systemctl restart slurmd"

    # Wait for service to start
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 3

        if systemctl is-active --quiet slurmd; then
            log SUCCESS "slurmd started successfully"
        else
            log ERROR "Failed to start slurmd"
            log ERROR "Check logs: journalctl -u slurmd -n 50"
            exit 1
        fi
    fi
}

show_cluster_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    # Auto-detect Slurm binary paths
    # Source install (23.x): /usr/local/slurm/bin/ - 우선 사용
    # apt package (21.x): /usr/bin/ - 지원하지 않음
    local SINFO SCONTROL
    if [[ -x "/usr/local/slurm/bin/sinfo" ]]; then
        SINFO="/usr/local/slurm/bin/sinfo"
        SCONTROL="/usr/local/slurm/bin/scontrol"
    elif [[ -x "/opt/slurm/bin/sinfo" ]]; then
        SINFO="/opt/slurm/bin/sinfo"
        SCONTROL="/opt/slurm/bin/scontrol"
    else
        # Fallback to PATH (환경변수 설정된 경우)
        SINFO="sinfo"
        SCONTROL="scontrol"
    fi
    log INFO "Using Slurm binaries: SINFO=$SINFO, SCONTROL=$SCONTROL"

    log INFO "Waiting for slurmctld to be ready..."

    # Wait for slurmctld to initialize (it needs a few seconds after systemd start)
    local max_attempts=10
    local attempt=1
    local wait_time=2

    while [ $attempt -le $max_attempts ]; do
        log INFO "Attempt $attempt/$max_attempts: Checking slurmctld connectivity..."

        # Test if slurmctld is responding
        if $SCONTROL ping &>/dev/null; then
            log SUCCESS "slurmctld is responsive"
            break
        elif $SINFO &>/dev/null; then
            log SUCCESS "slurmctld is responsive (via sinfo)"
            break
        else
            if [ $attempt -lt $max_attempts ]; then
                log WARNING "slurmctld not ready yet, waiting ${wait_time}s..."
                sleep $wait_time
                attempt=$((attempt + 1))
            else
                log ERROR "slurmctld failed to become ready after $max_attempts attempts"
                log WARNING "Continuing anyway - this may be a transient issue"
                # MUST break to avoid infinite loop!
                break
            fi
        fi
    done

    echo ""
    log INFO "Slurm cluster status:"

    # Show cluster info
    $SCONTROL show config | head -20 || true
    echo ""

    # Show partitions
    $SINFO || true
    echo ""

    # Show nodes
    $SCONTROL show nodes || true
    echo ""

    # Check for DOWN nodes and attempt to resume them
    log INFO "Checking for nodes that need to be resumed..."

    # Check for down nodes (try multiple state filters)
    local down_nodes=$($SINFO -h -o "%N" -t down 2>/dev/null || true)
    local drain_nodes=$($SINFO -h -o "%N" -t drain,drained,draining 2>/dev/null || true)

    # Combine results
    local problem_nodes="${down_nodes} ${drain_nodes}"
    problem_nodes=$(echo "$problem_nodes" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

    if [[ -n "$problem_nodes" ]]; then
        log WARNING "Found nodes in DOWN/DRAIN state: $problem_nodes"
        log INFO "Attempting to resume nodes..."

        # Get list of all configured nodes
        local all_nodes=$($SCONTROL show nodes | grep "NodeName=" | awk -F= '{print $2}' | awk '{print $1}')

        for node in $all_nodes; do
            # Get node state
            local node_state=$($SCONTROL show node "$node" | grep "State=" | awk -F= '{print $2}' | awk '{print $1}')

            # Resume if DOWN, DRAIN, or similar
            if [[ "$node_state" =~ ^(DOWN|DRAIN) ]]; then
                log INFO "  Resuming node: $node (state: $node_state)"
                $SCONTROL update nodename="$node" state=resume 2>/dev/null || \
                    log WARNING "  Failed to resume $node"
            fi
        done

        # Wait a moment for state changes to propagate
        sleep 2

        # Show updated status
        log SUCCESS "Node resume complete. Updated status:"
        $SINFO || true
    else
        log SUCCESS "All nodes are in operational state"
    fi
}

setup_slurm_accounts() {
    log INFO "=== Setting up Slurm Accounts ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would setup Slurm accounts"
        return 0
    fi

    # Check if SlurmDBD is configured and running
    local accounting_type=$(grep "^AccountingStorageType" /etc/slurm/slurm.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')

    if [[ "$accounting_type" == "accounting_storage/none" ]] || [[ -z "$accounting_type" ]]; then
        log INFO "Slurm accounting is disabled (accounting_storage/none)"
        log INFO "All users can submit jobs without account registration"
        return 0
    fi

    # SlurmDBD accounting is enabled - need to register accounts
    log INFO "SlurmDBD accounting is enabled - registering accounts..."

    # Wait for slurmdbd to be ready
    local max_wait=30
    local waited=0
    while ! sacctmgr show cluster -P &>/dev/null; do
        if [[ $waited -ge $max_wait ]]; then
            log WARNING "SlurmDBD not responding after ${max_wait}s - skipping account setup"
            log WARNING "You may need to manually run: sacctmgr add account default && sacctmgr add user <username> account=default"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    # Get cluster name
    local cluster_name=$(grep "^ClusterName" /etc/slurm/slurm.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
    cluster_name=${cluster_name:-linux}

    # Check if cluster is registered
    if ! sacctmgr show cluster "$cluster_name" -P 2>/dev/null | grep -q "$cluster_name"; then
        log INFO "Registering cluster: $cluster_name"
        sacctmgr -i add cluster "$cluster_name" 2>/dev/null || log WARNING "Cluster may already exist"
    fi

    # Create default account if not exists
    if ! sacctmgr show account default -P 2>/dev/null | grep -q "default"; then
        log INFO "Creating default account..."
        sacctmgr -i add account default Description="Default Account" Organization="HPC" 2>/dev/null || \
            log WARNING "Default account may already exist"
    fi

    # Get setup user from YAML or use SUDO_USER
    local setup_user=""

    # Try to get from YAML
    if [[ -f "$CONFIG_FILE" ]]; then
        setup_user=$(python3 << EOPY
import yaml
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
        # Try cluster_info.admin_user first, then ssh_user
        user = config.get('cluster_info', {}).get('admin_user', '')
        if not user:
            user = config.get('cluster_info', {}).get('ssh_user', '')
        print(user)
except:
    pass
EOPY
)
    fi

    # Fallback to SUDO_USER or current user
    if [[ -z "$setup_user" ]]; then
        setup_user="${SUDO_USER:-$(whoami)}"
    fi

    # Register user if not exists
    if [[ -n "$setup_user" ]] && [[ "$setup_user" != "root" ]]; then
        if ! sacctmgr show user "$setup_user" -P 2>/dev/null | grep -q "$setup_user"; then
            log INFO "Adding user to Slurm account: $setup_user"
            sacctmgr -i add user "$setup_user" account=default 2>/dev/null || \
                log WARNING "User $setup_user may already exist in Slurm"
        else
            log INFO "User $setup_user already registered in Slurm"
        fi
    fi

    # Also add root for system jobs
    if ! sacctmgr show user root -P 2>/dev/null | grep -q "root"; then
        log INFO "Adding root user to Slurm account..."
        sacctmgr -i add user root account=default 2>/dev/null || true
    fi

    log SUCCESS "Slurm account setup completed"
    log INFO "Registered accounts:"
    sacctmgr show association -P 2>/dev/null | head -10 || true
}

setup_remote_compute_nodes() {
    log INFO "=== Setting up Slurm on remote compute nodes ==="

    # Get compute + viz nodes from YAML (both need slurmd)
    local compute_nodes=$(python3 << EOPY
import yaml, json
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
    nodes = config.get('nodes', {})
    all_nodes = nodes.get('compute_nodes', []) + nodes.get('viz_nodes', [])
    print(json.dumps(all_nodes))
EOPY
)

    if [[ "$compute_nodes" == "[]" ]] || [[ -z "$compute_nodes" ]]; then
        log WARNING "No compute nodes defined in YAML, skipping remote setup"
        return 0
    fi

    # Step: Sync offline packages to GlusterFS for compute nodes
    # This is the most maintainable solution for offline environments
    if [[ "$USE_GLUSTERFS" == "true" ]]; then
        log INFO "Syncing offline packages to GlusterFS for compute nodes..."
        sync_offline_packages_to_glusterfs || log WARNING "Could not sync offline packages (compute nodes may need online access)"
    else
        log WARNING "GlusterFS not available - compute nodes will need online access for package installation"
    fi

    # Get cluster password from YAML for SSH access (if needed for sshpass)
    local ssh_password=$(python3 << EOPY
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
    print(config.get('cluster_info', {}).get('ssh_password', ''))
EOPY
)

    local setup_count=0
    local failed_count=0

    while IFS= read -r node; do
        local hostname=$(echo "$node" | jq -r '.hostname')
        local ip_address=$(echo "$node" | jq -r '.ip_address')
        local ssh_user=$(echo "$node" | jq -r '.ssh_user // "root"')

        log INFO "Setting up Slurm on $hostname ($ip_address)..."

        # Check if node is reachable
        if ! ping -c 1 -W 2 "$ip_address" &>/dev/null; then
            log WARNING "Node $hostname ($ip_address) is not reachable, skipping"
            failed_count=$((failed_count + 1))
            continue
        fi

        # per-node SSH 인증 설정 (키 우선, sshpass fallback)
        if ! setup_node_ssh_opts "$ssh_user" "$ip_address"; then
            log WARNING "Node $hostname ($ip_address) SSH auth failed, skipping"
            failed_count=$((failed_count + 1))
            continue
        fi

        # Check if Slurm is already installed (check both package and source install paths)
        if ssh $SSH_OPTS "$ssh_user@$ip_address" "test -x /usr/bin/slurmd || test -x /usr/local/slurm/bin/slurmd" 2>/dev/null; then
            log INFO "Slurm already installed on $hostname, syncing config..."

            # Detect remote slurm.conf path
            local remote_slurm_conf
            remote_slurm_conf=$(ssh $SSH_OPTS "$ssh_user@$ip_address" \
                "if [ -d /etc/slurm ]; then echo /etc/slurm/slurm.conf; elif [ -d /usr/local/slurm/etc ]; then echo /usr/local/slurm/etc/slurm.conf; else echo /etc/slurm/slurm.conf; fi" 2>/dev/null)

            # Sync slurm.conf (use local SLURM_CONFIG which is /etc/slurm/slurm.conf)
            scp $SCP_OPTS \
                "$SLURM_CONFIG" \
                "$ssh_user@$ip_address:/tmp/slurm.conf" &>/dev/null

            ssh $SSH_OPTS "$ssh_user@$ip_address" \
                "sudo mkdir -p \$(dirname $remote_slurm_conf) && \
                 sudo mv /tmp/slurm.conf $remote_slurm_conf && \
                 sudo chown slurm:slurm $remote_slurm_conf && \
                 sudo chmod 644 $remote_slurm_conf" &>/dev/null

            # Sync cgroup.conf if cgroup is enabled
            if [[ "$CGROUP_ENABLED" == "true" || "$CGROUP_ENABLED" == "True" ]]; then
                local local_cgroup_conf
                if [[ -f "/etc/slurm/cgroup.conf" ]]; then
                    local_cgroup_conf="/etc/slurm/cgroup.conf"
                elif [[ -f "/etc/slurm-llnl/cgroup.conf" ]]; then
                    local_cgroup_conf="/etc/slurm-llnl/cgroup.conf"
                fi

                if [[ -n "$local_cgroup_conf" && -f "$local_cgroup_conf" ]]; then
                    local remote_config_dir=$(dirname "$remote_slurm_conf")
                    scp $SCP_OPTS \
                        "$local_cgroup_conf" \
                        "$ssh_user@$ip_address:/tmp/cgroup.conf" &>/dev/null

                    ssh $SSH_OPTS "$ssh_user@$ip_address" \
                        "sudo mv /tmp/cgroup.conf ${remote_config_dir}/cgroup.conf && \
                         sudo chown slurm:slurm ${remote_config_dir}/cgroup.conf && \
                         sudo chmod 644 ${remote_config_dir}/cgroup.conf" &>/dev/null

                    log INFO "  cgroup.conf synced to $hostname"
                fi
            fi

            # Sync gres.conf if exists
            local local_gres_conf
            if [[ -f "/etc/slurm/gres.conf" ]]; then
                local_gres_conf="/etc/slurm/gres.conf"
            elif [[ -f "/etc/slurm-llnl/gres.conf" ]]; then
                local_gres_conf="/etc/slurm-llnl/gres.conf"
            fi

            if [[ -n "$local_gres_conf" && -f "$local_gres_conf" ]]; then
                local remote_config_dir=$(dirname "$remote_slurm_conf")
                scp $SCP_OPTS \
                    "$local_gres_conf" \
                    "$ssh_user@$ip_address:/tmp/gres.conf" &>/dev/null

                ssh $SSH_OPTS "$ssh_user@$ip_address" \
                    "sudo mv /tmp/gres.conf ${remote_config_dir}/gres.conf && \
                     sudo chown slurm:slurm ${remote_config_dir}/gres.conf && \
                     sudo chmod 644 ${remote_config_dir}/gres.conf" &>/dev/null

                log INFO "  gres.conf synced to $hostname"
            fi

            # Restart slurmd
            ssh $SSH_OPTS "$ssh_user@$ip_address" \
                "sudo systemctl restart slurmd" &>/dev/null

            log SUCCESS "Config synced and slurmd restarted on $hostname"
            setup_count=$((setup_count + 1))
            continue
        fi

        log INFO "Installing Slurm on $hostname..."

        # Setup GlusterFS-based offline APT repository on compute node (for offline environments)
        if [[ "$USE_GLUSTERFS" == "true" ]]; then
            log INFO "  Setting up offline APT repository on $hostname..."
            setup_glusterfs_offline_repo_remote "$ssh_user" "$ip_address" || \
                log WARNING "  Could not setup offline repo on $hostname (may need online access)"
        fi

        # Save output to temp file to avoid subshell issues
        local install_log="/tmp/slurm_install_${hostname}.log"

        # Check for prebuilt Slurm package (preferred for offline environments)
        local PREBUILT_TARBALL="$(ls ${OFFLINE_PKG_DIR}/slurm/slurm-*-prebuilt.tar.gz 2>/dev/null | head -1)"
        local use_prebuilt=false

        if [[ -f "$PREBUILT_TARBALL" ]]; then
            log INFO "  Found prebuilt Slurm package, using offline deployment..."
            use_prebuilt=true
        else
            log WARNING "  Prebuilt package not found: $PREBUILT_TARBALL"
            log INFO "  Falling back to source compilation (requires internet)"
        fi

        if [[ "$use_prebuilt" == "true" ]]; then
            # === PREBUILT PACKAGE DEPLOYMENT (OFFLINE) ===

            # Get UID/GID from YAML config (default to 64001 to avoid conflicts with system accounts like opsadmin)
            local target_slurm_uid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('slurm_user',{}).get('uid', 64001))" 2>/dev/null || echo 64001)
            local target_slurm_gid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('slurm_user',{}).get('gid', 64001))" 2>/dev/null || echo 64001)

            # Create slurm user on remote node BEFORE deploying (to avoid UID 1001 conflict in deploy_slurm.sh)
            log INFO "  Creating slurm user on $hostname (UID=$target_slurm_uid, GID=$target_slurm_gid)..."
            ssh -n -o BatchMode=yes -o ConnectTimeout=60 -o StrictHostKeyChecking=no "$ssh_user@$ip_address" \
                "if ! id slurm &>/dev/null; then \
                    sudo groupadd -g $target_slurm_gid slurm 2>/dev/null || sudo groupadd slurm 2>/dev/null || true; \
                    sudo useradd -u $target_slurm_uid -g slurm -m -s /bin/bash slurm 2>/dev/null || sudo useradd -g slurm -m -s /bin/bash slurm 2>/dev/null || true; \
                fi" >> "$install_log" 2>&1 || log WARNING "  Could not create slurm user (may already exist)"

            # Also create munge user with proper UID
            local target_munge_uid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('slurm_user',{}).get('munge_uid', 64002))" 2>/dev/null || echo 64002)
            local target_munge_gid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('slurm_user',{}).get('munge_gid', 64002))" 2>/dev/null || echo 64002)

            log INFO "  Creating munge user on $hostname (UID=$target_munge_uid, GID=$target_munge_gid)..."
            ssh -n -o BatchMode=yes -o ConnectTimeout=60 -o StrictHostKeyChecking=no "$ssh_user@$ip_address" \
                "if ! id munge &>/dev/null; then \
                    sudo groupadd -g $target_munge_gid munge 2>/dev/null || sudo groupadd munge 2>/dev/null || true; \
                    sudo useradd -u $target_munge_uid -g munge -m -s /sbin/nologin munge 2>/dev/null || sudo useradd -g munge -m -s /sbin/nologin munge 2>/dev/null || true; \
                fi" >> "$install_log" 2>&1 || log WARNING "  Could not create munge user (may already exist)"

            log INFO "  Copying prebuilt Slurm package to $hostname..."

            # Copy prebuilt tarball
            if ! scp $SCP_OPTS "$PREBUILT_TARBALL" "$ssh_user@$ip_address:/tmp/" 2>&1 | tee -a "$install_log"; then
                log ERROR "Failed to copy prebuilt tarball to $hostname"
                failed_count=$((failed_count + 1))
                continue
            fi

            # Extract and deploy prebuilt package
            log INFO "  Deploying prebuilt Slurm on $hostname..."

            # 최신 deploy_slurm.sh를 별도로 전송 (tar 안의 버전보다 우선)
            local DEPLOY_SCRIPT="${OFFLINE_PKG_DIR}/slurm/deploy_slurm.sh"
            if [[ -f "$DEPLOY_SCRIPT" ]]; then
                scp $SCP_OPTS "$DEPLOY_SCRIPT" "$ssh_user@$ip_address:/tmp/deploy_slurm_latest.sh" 2>/dev/null || true
            fi

            # Create dedicated extraction directory to avoid /tmp permission issues
            # slurmstepd kill + sbin pre-delete: Text file busy 에러 방지
            if ! ssh -n -o BatchMode=yes -o ConnectTimeout=300 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no "$ssh_user@$ip_address" \
                "sudo rm -rf /tmp/slurm_prebuilt && \
                 mkdir -p /tmp/slurm_prebuilt && \
                 cd /tmp/slurm_prebuilt && \
                 tar --no-same-owner --no-same-permissions -xzf /tmp/slurm-23.11.10-prebuilt.tar.gz && \
                 sudo pkill -9 slurmstepd 2>/dev/null; \
                 sudo pkill -9 slurmd 2>/dev/null; \
                 sudo pkill -9 -f slurmstepd 2>/dev/null; \
                 sleep 2; \
                 sudo rm -f /opt/slurm/sbin/* 2>/dev/null; \
                 if [ -f /tmp/deploy_slurm_latest.sh ]; then cp /tmp/deploy_slurm_latest.sh deploy_slurm.sh; fi; \
                 sudo bash deploy_slurm.sh" >> "$install_log" 2>&1; then
                local install_exit_code=$?
                log ERROR "Failed to deploy prebuilt Slurm on $hostname (exit code: $install_exit_code)"
                log ERROR "  Install log file: $install_log"
                if [[ -f "$install_log" ]] && [[ -s "$install_log" ]]; then
                    log ERROR "  === Last 50 lines of output ==="
                    while IFS= read -r line; do
                        echo "    [LOG] $line"
                    done < <(tail -50 "$install_log")
                    log ERROR "  === End of output ==="
                fi
                failed_count=$((failed_count + 1))
                continue
            fi

            # Setup slurmd systemd service for prebuilt package
            log INFO "  Creating slurmd systemd service on $hostname..."
            ssh -n -o BatchMode=yes -o ConnectTimeout=60 -o StrictHostKeyChecking=no "$ssh_user@$ip_address" \
                "sudo tee /etc/systemd/system/slurmd.service > /dev/null << 'EOFSVC'
[Unit]
Description=Slurm node daemon
After=munge.service network-online.target remote-fs.target
Wants=network-online.target
ConditionPathExists=/opt/slurm/etc/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStart=/opt/slurm/sbin/slurmd -D \$SLURMD_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC
sudo systemctl daemon-reload" >> "$install_log" 2>&1 || log WARNING "  Could not create slurmd service file"

            # Also need to install Munge package via offline APT repo (if available)
            log INFO "  Installing Munge on $hostname..."
            ssh -n -o BatchMode=yes -o ConnectTimeout=120 -o StrictHostKeyChecking=no "$ssh_user@$ip_address" \
                "if ! command -v munge &>/dev/null; then \
                    if [[ -f $GLUSTER_MOUNT/offline_packages/apt_packages/Packages.gz ]]; then \
                        echo 'deb [trusted=yes] file://$GLUSTER_MOUNT/offline_packages/apt_packages ./' | sudo tee /etc/apt/sources.list.d/offline-gluster.list > /dev/null && \
                        sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/offline-gluster.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>/dev/null || true && \
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends munge libmunge2 2>/dev/null || \
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y munge 2>/dev/null || true; \
                    else \
                        sudo DEBIAN_FRONTEND=noninteractive apt-get update && \
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y munge 2>/dev/null || true; \
                    fi; \
                fi" >> "$install_log" 2>&1 || log WARNING "  Munge installation may need manual attention"

            # Setup Munge on compute node (copy key from controller)
            log INFO "  Setting up Munge key on $hostname..."
            if [[ -f /etc/munge/munge.key ]]; then
                scp $SCP_OPTS /etc/munge/munge.key "$ssh_user@$ip_address:/tmp/munge.key" 2>/dev/null || true
                ssh -n -o BatchMode=yes -o ConnectTimeout=60 -o StrictHostKeyChecking=no "$ssh_user@$ip_address" \
                    "sudo mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge && \
                     sudo mv /tmp/munge.key /etc/munge/munge.key && \
                     sudo chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge 2>/dev/null || true && \
                     sudo chmod 700 /etc/munge /var/lib/munge && \
                     sudo chmod 400 /etc/munge/munge.key && \
                     sudo systemctl enable munge && \
                     sudo systemctl restart munge" >> "$install_log" 2>&1 || log WARNING "  Munge key setup may need manual attention"
            fi

            # Cleanup temporary files
            ssh -n -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=no "$ssh_user@$ip_address" \
                "rm -rf /tmp/slurm_prebuilt /tmp/slurm-23.11.10-prebuilt.tar.gz" 2>/dev/null || true

            log SUCCESS "Prebuilt Slurm deployed on $hostname"
        else
            # === SOURCE COMPILATION FALLBACK (ONLINE) ===
            # Copy installation script
            if ! scp $SCP_OPTS \
                "${PROJECT_ROOT}/install_slurm_cgroup_v2.sh" \
                "$ssh_user@$ip_address:/tmp/" &>/dev/null; then
                log ERROR "Failed to copy install script to $hostname"
                failed_count=$((failed_count + 1))
                continue
            fi

            # Execute installation (use longer timeout for install)
            log INFO "  Running install_slurm_cgroup_v2.sh on $hostname (source compilation)..."
            log INFO "  SSH command: ssh -n ... $ssh_user@$ip_address 'cd /tmp && sudo bash install_slurm_cgroup_v2.sh'"

            # Execute with explicit error capture
            if ! ssh -n -o BatchMode=yes -o ConnectTimeout=300 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no "$ssh_user@$ip_address" \
                "cd /tmp && sudo GLUSTER_MOUNT='$GLUSTER_MOUNT' bash install_slurm_cgroup_v2.sh" > "$install_log" 2>&1; then
                local install_exit_code=$?
                log ERROR "Failed to install Slurm on $hostname (exit code: $install_exit_code)"
                log ERROR "  Install log file: $install_log"
                if [[ -f "$install_log" ]] && [[ -s "$install_log" ]]; then
                    log ERROR "  === Last 50 lines of output ==="
                    while IFS= read -r line; do
                        echo "    [LOG] $line"
                    done < <(tail -50 "$install_log")
                    log ERROR "  === End of output ==="
                else
                    log ERROR "  (Log file empty or not created)"
                    log ERROR "  Checking if script exists on remote..."
                    ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ssh_user@$ip_address" \
                        "ls -la /tmp/install_slurm_cgroup_v2.sh 2>&1" || log ERROR "    Script not found on remote!"
                fi
                failed_count=$((failed_count + 1))
                continue
            fi

            log SUCCESS "Slurm installed on $hostname (from source)"
        fi

        rm -f "$install_log" 2>/dev/null || true

        # Copy slurm.conf - detect remote path (check prebuilt path /opt/slurm/etc first)
        local remote_slurm_conf
        remote_slurm_conf=$(ssh $SSH_OPTS "$ssh_user@$ip_address" \
            "if [ -d /opt/slurm/etc ]; then echo /opt/slurm/etc/slurm.conf; \
             elif [ -d /usr/local/slurm/etc ]; then echo /usr/local/slurm/etc/slurm.conf; \
             elif [ -d /etc/slurm ]; then echo /etc/slurm/slurm.conf; \
             else echo /opt/slurm/etc/slurm.conf; fi" 2>/dev/null)

        if scp $SCP_OPTS \
            "$SLURM_CONFIG" \
            "$ssh_user@$ip_address:/tmp/slurm.conf" &>/dev/null; then
            ssh $SSH_OPTS "$ssh_user@$ip_address" \
                "sudo mkdir -p \$(dirname $remote_slurm_conf) && \
                 sudo mv /tmp/slurm.conf $remote_slurm_conf && \
                 sudo chown slurm:slurm $remote_slurm_conf && \
                 sudo chmod 644 $remote_slurm_conf" &>/dev/null
            log SUCCESS "Config copied to $hostname ($remote_slurm_conf)"
        else
            log WARNING "Failed to copy config to $hostname"
        fi

        # Copy cgroup.conf if cgroup is enabled
        if [[ "$CGROUP_ENABLED" == "true" || "$CGROUP_ENABLED" == "True" ]]; then
            local local_cgroup_conf
            if [[ -f "/etc/slurm/cgroup.conf" ]]; then
                local_cgroup_conf="/etc/slurm/cgroup.conf"
            elif [[ -f "/etc/slurm-llnl/cgroup.conf" ]]; then
                local_cgroup_conf="/etc/slurm-llnl/cgroup.conf"
            fi

            if [[ -n "$local_cgroup_conf" && -f "$local_cgroup_conf" ]]; then
                local remote_config_dir=$(dirname "$remote_slurm_conf")
                if scp $SCP_OPTS \
                    "$local_cgroup_conf" \
                    "$ssh_user@$ip_address:/tmp/cgroup.conf" &>/dev/null; then
                    ssh $SSH_OPTS "$ssh_user@$ip_address" \
                        "sudo mv /tmp/cgroup.conf ${remote_config_dir}/cgroup.conf && \
                         sudo chown slurm:slurm ${remote_config_dir}/cgroup.conf && \
                         sudo chmod 644 ${remote_config_dir}/cgroup.conf" &>/dev/null
                    log SUCCESS "cgroup.conf copied to $hostname (${remote_config_dir}/cgroup.conf)"
                else
                    log WARNING "Failed to copy cgroup.conf to $hostname"
                fi
            fi
        fi

        # Copy gres.conf if exists
        local local_gres_conf
        if [[ -f "/etc/slurm/gres.conf" ]]; then
            local_gres_conf="/etc/slurm/gres.conf"
        elif [[ -f "/etc/slurm-llnl/gres.conf" ]]; then
            local_gres_conf="/etc/slurm-llnl/gres.conf"
        fi

        if [[ -n "$local_gres_conf" && -f "$local_gres_conf" ]]; then
            local remote_config_dir=$(dirname "$remote_slurm_conf")
            if scp $SCP_OPTS \
                "$local_gres_conf" \
                "$ssh_user@$ip_address:/tmp/gres.conf" &>/dev/null; then
                ssh $SSH_OPTS "$ssh_user@$ip_address" \
                    "sudo mv /tmp/gres.conf ${remote_config_dir}/gres.conf && \
                     sudo chown slurm:slurm ${remote_config_dir}/gres.conf && \
                     sudo chmod 644 ${remote_config_dir}/gres.conf" &>/dev/null
                log SUCCESS "gres.conf copied to $hostname (${remote_config_dir}/gres.conf)"
            else
                log WARNING "Failed to copy gres.conf to $hostname"
            fi
        fi

        # Start slurmd
        if ssh $SSH_OPTS "$ssh_user@$ip_address" \
            "sudo systemctl enable slurmd && sudo systemctl start slurmd" &>/dev/null; then
            log SUCCESS "slurmd started on $hostname"
            setup_count=$((setup_count + 1))
        else
            log WARNING "Failed to start slurmd on $hostname (may need manual start)"
            failed_count=$((failed_count + 1))
        fi

    done < <(echo "$compute_nodes" | jq -c '.[]')

    log INFO ""
    log INFO "Remote setup summary:"
    log INFO "  - Successfully set up: $setup_count nodes"
    log INFO "  - Failed or skipped: $failed_count nodes"
    log INFO ""
}

#############################################################################
# Main
#############################################################################

main() {
    log INFO "=== Phase 3: Slurm Multi-Master Setup ==="
    log INFO "Starting at $(date)"

    # Step 0: Check root privileges
    check_root

    # Step 1: Check dependencies
    check_dependencies

    # Step 2: Load configuration
    load_config

    # Step 3: Detect OS
    detect_os

    # Step 4: Check if Slurm is installed
    check_slurm_installed

    # Step 5: Install Slurm packages (checks each package individually)
    # This ensures slurmdbd is installed even if slurmctld was already present
    install_slurm

    # Step 6: Create slurm user
    create_slurm_user

    # Step 7: Setup Munge authentication
    setup_munge

    # Controller-specific setup
    if [[ "$SETUP_CONTROLLER" == "true" ]]; then
        # Step 8: Check GlusterFS
        check_glusterfs_mounted

        # Step 9: Create shared directories
        create_shared_directories

        # Step 10: Generate slurm.conf
        generate_slurm_config

        # Step 10.5: Generate cgroup.conf (if cgroup enabled)
        generate_cgroup_config

        # Step 10.6: Generate gres.conf (if GPU nodes exist)
        generate_gres_config

        # Step 11: Setup SlurmDBD if requested
        if [[ "$SETUP_DBD" == "true" ]]; then
            setup_slurmdbd
        fi

        # Step 12: Start slurmctld
        start_slurmctld

        # Step 13: Show cluster status
        show_cluster_status

        # Step 14: Setup Slurm accounts (if accounting enabled)
        setup_slurm_accounts

        # Step 15: Auto-deploy to compute nodes if requested
        if [[ "$AUTO_DEPLOY_COMPUTE" == "true" ]]; then
            setup_remote_compute_nodes

            # Step 16: Deploy Apptainer images to compute nodes
            log INFO ""
            log INFO "=== Deploying Apptainer images to compute nodes ==="

            DEPLOY_SCRIPT="${PROJECT_ROOT}/apptainer/deploy_compute_images.sh"
            if [[ -f "$DEPLOY_SCRIPT" ]]; then
                if bash "$DEPLOY_SCRIPT" "$CONFIG_FILE"; then
                    log SUCCESS "Apptainer images deployed to compute nodes"
                else
                    log WARNING "Apptainer image deployment failed or skipped (non-critical)"
                fi
            else
                log WARNING "Deployment script not found: $DEPLOY_SCRIPT (skipping)"
            fi
        fi
    fi

    # Compute node setup
    if [[ "$SETUP_COMPUTE" == "true" ]]; then
        # Try to copy slurm.conf from shared storage or system config
        local config_found=false

        # Check GlusterFS shared storage first
        if [[ -f "$GLUSTER_MOUNT/slurm/slurm.conf" ]]; then
            log INFO "Copying slurm.conf from shared storage (GlusterFS)..."
            cp "$GLUSTER_MOUNT/slurm/slurm.conf" "$SLURM_CONFIG"
            config_found=true
        # Fallback: Check /etc/slurm
        elif [[ -f "/etc/slurm/slurm.conf" ]]; then
            log INFO "Using existing slurm.conf from /etc/slurm"
            config_found=true
        # Fallback: Check /usr/local/slurm/etc
        elif [[ -f "/usr/local/slurm/etc/slurm.conf" ]]; then
            log INFO "Using existing slurm.conf from /usr/local/slurm/etc"
            cp "/usr/local/slurm/etc/slurm.conf" "$SLURM_CONFIG"
            config_found=true
        fi

        if [[ "$config_found" == "true" ]]; then
            chown slurm:slurm "$SLURM_CONFIG"
            chmod 644 "$SLURM_CONFIG"
        else
            log ERROR "slurm.conf not found in any known location"
            log ERROR "Please run --controller setup first or manually copy slurm.conf"
            exit 1
        fi

        # Start slurmd
        start_slurmd
    fi

    log SUCCESS "=== Slurm setup completed ==="
    log INFO "Finished at $(date)"

    if [[ "$SETUP_CONTROLLER" == "true" ]]; then
        log INFO ""
        log INFO "Next steps:"
        log INFO "  1. Run this script on other Slurm-enabled controllers"
        log INFO "  2. Setup compute nodes: $0 --compute"
        log INFO "  3. Check cluster status: sinfo"
        log INFO "  4. Submit test job: sbatch --wrap='sleep 60'"
    fi
}

#############################################################################
# Parse arguments
#############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --controller)
            SETUP_CONTROLLER=true
            shift
            ;;
        --compute)
            SETUP_COMPUTE=true
            shift
            ;;
        --dbd)
            SETUP_DBD=true
            shift
            ;;
        --auto-deploy-compute)
            AUTO_DEPLOY_COMPUTE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Auto-detect roles from YAML if not explicitly specified
if [[ "$SETUP_CONTROLLER" == "false" ]] && [[ "$SETUP_COMPUTE" == "false" ]] && [[ "$SETUP_DBD" == "false" ]]; then
    log INFO "No roles specified, auto-detecting from YAML configuration..."

    # Check if slurm service is enabled for this controller
    if [[ -f "$CONFIG_FILE" ]]; then
        # Get current node's IP
        CURRENT_IP=$(hostname -I | awk '{print $1}')

        # Check if this node has slurm service enabled in YAML
        SLURM_ENABLED=$(python3 -c "
import yaml
import sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
    controllers = config.get('nodes', {}).get('controllers', [])
    for ctrl in controllers:
        # Match by IP or hostname
        if ctrl.get('ip_address') == '$CURRENT_IP' or ctrl.get('hostname') == '$(hostname)':
            print('true' if ctrl.get('services', {}).get('slurm', False) else 'false')
            sys.exit(0)
    print('false')
except Exception as e:
    print('false', file=sys.stderr)
" 2>/dev/null || echo "false")

        if [[ "$SLURM_ENABLED" == "true" ]]; then
            log INFO "Slurm service enabled in YAML, setting up controller and DBD"
            SETUP_CONTROLLER=true
            SETUP_DBD=true
        else
            log ERROR "Slurm service not enabled in YAML and no explicit roles specified"
            log ERROR "Either enable slurm in YAML or specify --controller/--compute/--dbd"
            exit 1
        fi
    else
        log ERROR "Must specify at least one of: --controller, --compute, --dbd"
        show_help
        exit 1
    fi
fi

# Run main function
main
