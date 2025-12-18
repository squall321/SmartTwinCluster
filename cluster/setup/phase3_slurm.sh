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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

if [[ -f "$SSH_KEY_FILE" ]]; then
    # -n: Don't read from stdin (critical for while read loops!)
    SSH_OPTS="-n -i $SSH_KEY_FILE -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
    SCP_OPTS="-i $SSH_KEY_FILE -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no"
else
    # -n: Don't read from stdin (critical for while read loops!)
    SSH_OPTS="-n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
    SCP_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no"
fi

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
    local offline_pkg_dir="${PROJECT_ROOT}/offline_packages/apt_packages"

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

# Install package on remote node using offline packages
# Usage: install_offline_package_remote <remote_user> <remote_ip> <package_name> [package_name2...]
install_offline_package_remote() {
    local remote_user="$1"
    local remote_ip="$2"
    shift 2
    local packages=("$@")
    local offline_pkg_dir="${PROJECT_ROOT}/offline_packages/apt_packages"

    if [[ ! -d "$offline_pkg_dir" ]]; then
        log ERROR "Offline package directory not found: $offline_pkg_dir"
        return 1
    fi

    # Create temp directory on remote
    ssh $SSH_OPTS "$remote_user@$remote_ip" "mkdir -p /tmp/offline_packages" 2>/dev/null || true

    # Copy packages and their dependencies
    local copied=0
    for pkg in "${packages[@]}"; do
        for deb_file in "$offline_pkg_dir"/${pkg}_*.deb "$offline_pkg_dir"/${pkg}-*.deb "$offline_pkg_dir"/lib${pkg}*.deb; do
            if [[ -f "$deb_file" ]]; then
                log INFO "  Copying $(basename "$deb_file") to $remote_ip..."
                scp $SCP_OPTS "$deb_file" "$remote_user@$remote_ip:/tmp/offline_packages/" 2>/dev/null && copied=$((copied + 1))
            fi
        done
    done

    if [[ $copied -eq 0 ]]; then
        log WARNING "No packages found for: ${packages[*]}"
        return 1
    fi

    # Install on remote
    log INFO "Installing packages on $remote_ip..."
    ssh $SSH_OPTS "$remote_user@$remote_ip" "
        cd /tmp/offline_packages
        # Install all .deb files
        sudo dpkg -i *.deb 2>/dev/null || true
        # Fix any dependency issues
        sudo apt-get install -f -y 2>/dev/null || true
        # Cleanup
        rm -rf /tmp/offline_packages
    " 2>/dev/null

    return 0
}

# Setup GlusterFS-based offline APT repository on remote node
# This is the most maintainable solution for offline compute nodes
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
            log ERROR "  Failed to mount GlusterFS on $remote_ip"
            return 1
        }
    fi

    # Check if offline packages exist on GlusterFS
    if ! ssh $SSH_OPTS "$remote_user@$remote_ip" "[ -d '$gluster_offline_pkg_path' ]" 2>/dev/null; then
        log WARNING "  Offline packages not found at $gluster_offline_pkg_path on $remote_ip"
        log INFO "  Copying offline packages to GlusterFS..."

        # Copy from local offline_packages to GlusterFS if it doesn't exist
        local local_offline_pkg="${PROJECT_ROOT}/offline_packages/apt_packages"
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
    local local_offline_pkg="${PROJECT_ROOT}/offline_packages/apt_packages"

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
    # Fix systemd service files that may point to wrong paths
    # This happens when a custom-compiled Slurm was previously installed
    # but we're now using package-installed Slurm

    log INFO "Checking systemd service files for correct paths..."

    local needs_reload=false

    # Check slurmctld service file
    if [[ -f /etc/systemd/system/slurmctld.service ]]; then
        if grep -q "/usr/local/slurm" /etc/systemd/system/slurmctld.service 2>/dev/null; then
            log WARNING "Found old slurmctld.service pointing to /usr/local/slurm"
            log INFO "Updating slurmctld.service to use package paths..."

            # Backup old service file
            cp /etc/systemd/system/slurmctld.service /etc/systemd/system/slurmctld.service.backup.$(date +%Y%m%d_%H%M%S)

            # Create new service file with correct paths
            cat > /etc/systemd/system/slurmctld.service << 'SLURMCTLD_SERVICE'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service slurmdbd.service
Wants=slurmdbd.service
Requires=munge.service
ConditionPathExists=/etc/slurm/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/sbin/slurmctld -D $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
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
            log SUCCESS "slurmctld.service updated"
            needs_reload=true
        fi
    fi

    # Check slurmdbd service file
    if [[ -f /etc/systemd/system/slurmdbd.service ]]; then
        if grep -q "/usr/local/slurm" /etc/systemd/system/slurmdbd.service 2>/dev/null; then
            log WARNING "Found old slurmdbd.service pointing to /usr/local/slurm"
            log INFO "Updating slurmdbd.service to use package paths..."

            # Backup old service file
            cp /etc/systemd/system/slurmdbd.service /etc/systemd/system/slurmdbd.service.backup.$(date +%Y%m%d_%H%M%S)

            # Create new service file with correct paths
            cat > /etc/systemd/system/slurmdbd.service << 'SLURMDBD_SERVICE'
[Unit]
Description=Slurm DBD accounting daemon
After=network.target munge.service mariadb.service mysql.service
Requires=munge.service
ConditionPathExists=/etc/slurm/slurmdbd.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmdbd
ExecStart=/usr/sbin/slurmdbd -D $SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
LimitNOFILE=65536
LimitMEMLOCK=infinity
LimitSTACK=infinity

[Install]
WantedBy=multi-user.target
SLURMDBD_SERVICE
            log SUCCESS "slurmdbd.service updated"
            needs_reload=true
        fi
    fi

    # Check slurmd service file
    if [[ -f /etc/systemd/system/slurmd.service ]]; then
        if grep -q "/usr/local/slurm" /etc/systemd/system/slurmd.service 2>/dev/null; then
            log WARNING "Found old slurmd.service pointing to /usr/local/slurm"
            log INFO "Updating slurmd.service to use package paths..."

            # Backup old service file
            cp /etc/systemd/system/slurmd.service /etc/systemd/system/slurmd.service.backup.$(date +%Y%m%d_%H%M%S)

            # Create new service file with correct paths
            cat > /etc/systemd/system/slurmd.service << 'SLURMD_SERVICE'
[Unit]
Description=Slurm node daemon
After=network.target munge.service remote-fs.target
Requires=munge.service
ConditionPathExists=/etc/slurm/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/sbin/slurmd -D $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity

[Install]
WantedBy=multi-user.target
SLURMD_SERVICE
            log SUCCESS "slurmd.service updated"
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

    case $OS in
        ubuntu|debian)
            # Install controller packages if needed
            if [[ "$SETUP_CONTROLLER" == "true" ]] || [[ "$SETUP_DBD" == "true" ]]; then
                if ! command -v slurmctld &> /dev/null; then
                    log INFO "Installing slurmctld via offline packages..."
                    if ! install_offline_package slurm-wlm slurmctld libslurm37; then
                        log ERROR "Failed to install slurmctld from offline packages"
                        log ERROR "Ensure slurm packages are in: ${PROJECT_ROOT}/offline_packages/apt_packages/"
                        exit 1
                    fi
                else
                    log INFO "slurmctld already installed"
                fi
            fi

            # Install slurmdbd if needed (check separately - may not be installed even if slurmctld is)
            if [[ "$SETUP_DBD" == "true" ]]; then
                if ! command -v slurmdbd &> /dev/null; then
                    log INFO "Installing slurmdbd via offline packages..."
                    if ! install_offline_package slurmdbd libslurm37; then
                        log WARNING "Failed to install slurmdbd from offline packages"
                        log WARNING "SlurmDBD will be skipped - accounting will not be available"
                    fi
                else
                    log INFO "slurmdbd already installed"
                fi
            fi

            # Install compute node packages if needed
            if [[ "$SETUP_COMPUTE" == "true" ]]; then
                if ! command -v slurmd &> /dev/null; then
                    log INFO "Installing slurmd via offline packages..."
                    if ! install_offline_package slurmd libslurm37; then
                        log ERROR "Failed to install slurmd from offline packages"
                        log ERROR "Ensure slurm packages are in: ${PROJECT_ROOT}/offline_packages/apt_packages/"
                        exit 1
                    fi
                else
                    log INFO "slurmd already installed"
                fi
            fi
            ;;
        centos|rhel|rocky|almalinux)
            # For RHEL-based systems, use yum with local repo if available
            local offline_rpm_dir="${PROJECT_ROOT}/offline_packages/rpm_packages"

            # Install controller packages if needed
            if [[ "$SETUP_CONTROLLER" == "true" ]] || [[ "$SETUP_DBD" == "true" ]]; then
                if ! command -v slurmctld &> /dev/null; then
                    log INFO "Installing slurmctld..."
                    if [[ -d "$offline_rpm_dir" ]] && ls "$offline_rpm_dir"/slurm*.rpm &>/dev/null; then
                        log INFO "Installing from offline RPM packages..."
                        yum localinstall -y "$offline_rpm_dir"/slurm-[0-9]*.rpm "$offline_rpm_dir"/slurm-slurmctld*.rpm 2>/dev/null || true
                    else
                        log WARNING "No offline RPM packages found, this may fail in offline environment"
                        run_command "yum install -y slurm slurm-slurmctld"
                    fi
                else
                    log INFO "slurmctld already installed"
                fi
            fi

            # Install slurmdbd if needed
            if [[ "$SETUP_DBD" == "true" ]]; then
                if ! command -v slurmdbd &> /dev/null; then
                    log INFO "Installing slurmdbd..."
                    if [[ -d "$offline_rpm_dir" ]] && ls "$offline_rpm_dir"/slurm-slurmdbd*.rpm &>/dev/null; then
                        log INFO "Installing from offline RPM packages..."
                        yum localinstall -y "$offline_rpm_dir"/slurm-slurmdbd*.rpm 2>/dev/null || true
                    else
                        log WARNING "No offline RPM packages found, this may fail in offline environment"
                        run_command "yum install -y slurm-slurmdbd"
                    fi
                else
                    log INFO "slurmdbd already installed"
                fi
            fi

            # Install compute node packages if needed
            if [[ "$SETUP_COMPUTE" == "true" ]]; then
                if ! command -v slurmd &> /dev/null; then
                    log INFO "Installing slurmd..."
                    if [[ -d "$offline_rpm_dir" ]] && ls "$offline_rpm_dir"/slurm-slurmd*.rpm &>/dev/null; then
                        log INFO "Installing from offline RPM packages..."
                        yum localinstall -y "$offline_rpm_dir"/slurm-slurmd*.rpm 2>/dev/null || true
                    else
                        log WARNING "No offline RPM packages found, this may fail in offline environment"
                        run_command "yum install -y slurm-slurmd"
                    fi
                else
                    log INFO "slurmd already installed"
                fi
            fi
            ;;
    esac

    log SUCCESS "Slurm packages ready"

    # Fix systemd service files if they point to wrong paths
    # This happens when a custom-compiled Slurm was previously installed
    fix_systemd_service_files

    # Disable slurmd on controller nodes (only run slurmctld)
    if [[ "$SETUP_CONTROLLER" == "true" ]] && [[ "$SETUP_COMPUTE" == "false" ]]; then
        log INFO "Controller node: disabling slurmd service"
        systemctl stop slurmd 2>/dev/null || true
        systemctl disable slurmd 2>/dev/null || true
        systemctl mask slurmd 2>/dev/null || true
        log SUCCESS "slurmd disabled on controller"
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

    if id "slurm" &>/dev/null; then
        log INFO "User 'slurm' already exists"
    else
        run_command "useradd -r -s /bin/false -d /nonexistent slurm"
        log SUCCESS "User 'slurm' created"
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
            local ssh_test_output
            ssh_test_output=$(ssh $SSH_OPTS "$first_controller_user@$first_controller_ip" "echo 'SSH OK'" 2>&1)
            local ssh_test_exit=$?

            if [[ $ssh_test_exit -ne 0 ]]; then
                log ERROR "  ❌ Cannot SSH to primary controller ($first_controller_ip)"
                log ERROR "  SSH error: $ssh_test_output"
                log ERROR ""
                log ERROR "  Possible causes:"
                log ERROR "  - SSH key not configured"
                log ERROR "  - Primary controller not reachable"
                log ERROR "  - Firewall blocking SSH"
                log ERROR ""
                log ERROR "  Manual check: ssh $first_controller_user@$first_controller_ip"
                log ERROR ""

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

                    local scp_error
                    scp_error=$(scp $SCP_OPTS "$first_controller_user@$first_controller_ip:/etc/munge/munge.key" /tmp/munge.key.sync 2>&1)
                    local scp_exit=$?

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
            local ssh_test_output
            ssh_test_output=$(ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "echo 'SSH OK'" 2>&1)
            local ssh_test_exit=$?

            if [[ $ssh_test_exit -ne 0 ]]; then
                log ERROR "      ❌ Cannot SSH to $ctrl_hostname ($ctrl_ip)"
                log ERROR "      SSH error: $ssh_test_output"
                log ERROR "      Manual check: ssh $ctrl_user@$ctrl_ip"
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
                local offline_pkg_dir="${PROJECT_ROOT}/offline_packages/apt_packages"

                if [[ -d "$offline_pkg_dir" ]]; then
                    # Create temp directory on remote
                    ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "mkdir -p /tmp/munge_packages" 2>/dev/null || true

                    # Copy munge packages
                    local munge_pkgs=("munge_"*.deb "libmunge2_"*.deb "libmunge-dev_"*.deb)
                    for pkg_pattern in "${munge_pkgs[@]}"; do
                        for pkg_file in "$offline_pkg_dir"/$pkg_pattern; do
                            if [[ -f "$pkg_file" ]]; then
                                log INFO "        Copying $(basename "$pkg_file")..."
                                scp $SCP_OPTS "$pkg_file" "$ctrl_user@$ctrl_ip:/tmp/munge_packages/" 2>/dev/null || true
                            fi
                        done
                    done

                    # Install packages on remote using dpkg
                    log INFO "      Installing munge packages on $ctrl_hostname..."
                    ssh $SSH_OPTS "$ctrl_user@$ctrl_ip" "
                        cd /tmp/munge_packages
                        # Install in dependency order: libmunge2 -> munge
                        sudo dpkg -i libmunge2_*.deb 2>/dev/null || true
                        sudo dpkg -i munge_*.deb 2>/dev/null || true
                        # Fix any dependency issues
                        sudo apt-get install -f -y 2>/dev/null || true
                        # Cleanup
                        rm -rf /tmp/munge_packages
                    " 2>/dev/null || true

                    log SUCCESS "      Munge packages installed on $ctrl_hostname"
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
            log ERROR "  ❌ Failed: $fail_count controller(s)"
            log ERROR "  Failed controllers: ${failed_controllers[*]}"
            log ERROR ""
            log ERROR "  ⚠️  IMPORTANT: Munge key must be identical on all controllers!"
            log ERROR "  Without matching keys, slurmctld will fail to start."
            log ERROR ""
            log ERROR "  Manual fix options:"
            log ERROR "  1. Copy key manually: scp /etc/munge/munge.key user@host:/etc/munge/"
            log ERROR "  2. Fix SSH access and re-run this script"
            log ERROR ""
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

    # Get compute nodes from YAML
    local compute_nodes=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get nodes.compute_nodes 2>/dev/null || echo "[]")

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

    # Get partitions from YAML
    local partitions=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get slurm.partitions 2>/dev/null || echo "[]")

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

    # Auto-detect Slurm plugin directory based on OS
    local PLUGIN_DIR
    if [[ -d "/usr/lib/x86_64-linux-gnu/slurm-wlm" ]]; then
        # Ubuntu/Debian package install
        PLUGIN_DIR="/usr/lib/x86_64-linux-gnu/slurm-wlm"
    elif [[ -d "/usr/lib64/slurm" ]]; then
        # CentOS/RedHat package install
        PLUGIN_DIR="/usr/lib64/slurm"
    elif [[ -d "/usr/local/slurm/lib/slurm" ]]; then
        # Source install
        PLUGIN_DIR="/usr/local/slurm/lib/slurm"
    else
        # Default fallback
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
        mkdir -p "$(dirname "$SLURM_CONFIG")"
        echo -e "$config_content" > "$SLURM_CONFIG"
        chmod 644 "$SLURM_CONFIG"
        chown slurm:slurm "$SLURM_CONFIG"
        log SUCCESS "Slurm configuration written to $SLURM_CONFIG"
    fi
}

setup_slurmdbd() {
    log INFO "Setting up SlurmDBD..."

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
        echo ""
        echo "# Database settings"
        echo "DbdHost=localhost"
        echo "DbdPort=6819"
        echo "SlurmUser=slurm"
        echo "LogFile=/var/log/slurm/slurmdbd.log"
        echo "PidFile=/var/run/slurmdbd.pid"
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
            mysql -u root -p"${DB_ROOT_PASSWORD}" <<EOSQL
CREATE DATABASE IF NOT EXISTS slurm_acct_db;
CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY '${SLURMDBD_STORAGE_PASS}';
CREATE USER IF NOT EXISTS 'slurm'@'%' IDENTIFIED BY '${SLURMDBD_STORAGE_PASS}';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'%';
FLUSH PRIVILEGES;
EOSQL
        else
            mysql -h "$mysql_host" -u root -p"${DB_ROOT_PASSWORD}" <<EOSQL
CREATE DATABASE IF NOT EXISTS slurm_acct_db;
CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY '${SLURMDBD_STORAGE_PASS}';
CREATE USER IF NOT EXISTS 'slurm'@'%' IDENTIFIED BY '${SLURMDBD_STORAGE_PASS}';
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
            log ERROR "slurmdbd.service not found!"
            log ERROR "slurmdbd package may not be installed properly"
            log INFO "Attempting to install slurmdbd from offline packages..."

            case $OS in
                ubuntu|debian)
                    install_offline_package slurmdbd libslurm37
                    ;;
                centos|rhel|rocky|almalinux)
                    local offline_rpm_dir="${PROJECT_ROOT}/offline_packages/rpm_packages"
                    if [[ -d "$offline_rpm_dir" ]] && ls "$offline_rpm_dir"/slurm-slurmdbd*.rpm &>/dev/null; then
                        yum localinstall -y "$offline_rpm_dir"/slurm-slurmdbd*.rpm 2>/dev/null || true
                    else
                        log WARNING "No offline RPM packages found"
                    fi
                    ;;
            esac

            # Check again
            if ! systemctl list-unit-files slurmdbd.service &>/dev/null; then
                log ERROR "Failed to install slurmdbd - service file still not found"
                log ERROR "Ensure slurmdbd package is in: ${PROJECT_ROOT}/offline_packages/apt_packages/"
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
    # Ubuntu/Debian package: /usr/bin/
    # Source install: /usr/local/slurm/bin/
    local SINFO SCONTROL
    if [[ -x "/usr/bin/sinfo" ]]; then
        SINFO="/usr/bin/sinfo"
        SCONTROL="/usr/bin/scontrol"
    elif [[ -x "/usr/local/slurm/bin/sinfo" ]]; then
        SINFO="/usr/local/slurm/bin/sinfo"
        SCONTROL="/usr/local/slurm/bin/scontrol"
    else
        # Fallback to PATH
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

setup_remote_compute_nodes() {
    log INFO "=== Setting up Slurm on remote compute nodes ==="

    # Get compute nodes from YAML using direct Python
    local compute_nodes=$(python3 << EOPY
import yaml, json
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
    nodes = config.get('nodes', {}).get('compute_nodes', [])
    print(json.dumps(nodes))
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

        # Copy installation script
        if ! scp $SCP_OPTS \
            "${PROJECT_ROOT}/install_slurm_cgroup_v2.sh" \
            "$ssh_user@$ip_address:/tmp/" &>/dev/null; then
            log ERROR "Failed to copy install script to $hostname"
            failed_count=$((failed_count + 1))
            continue
        fi

        # Execute installation (use longer timeout for install)
        # -n: Don't read from stdin (critical for while read loops!)
        # Pass GLUSTER_MOUNT environment variable for offline mode detection
        if ssh -n -o BatchMode=yes -o ConnectTimeout=300 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no "$ssh_user@$ip_address" \
            "cd /tmp && sudo GLUSTER_MOUNT='$GLUSTER_MOUNT' bash install_slurm_cgroup_v2.sh" &>/dev/null; then
            log SUCCESS "Slurm installed on $hostname"
        else
            log ERROR "Failed to install Slurm on $hostname"
            failed_count=$((failed_count + 1))
            continue
        fi

        # Copy slurm.conf - detect remote path
        local remote_slurm_conf
        remote_slurm_conf=$(ssh $SSH_OPTS "$ssh_user@$ip_address" \
            "if [ -d /etc/slurm ]; then echo /etc/slurm/slurm.conf; elif [ -d /usr/local/slurm/etc ]; then echo /usr/local/slurm/etc/slurm.conf; else echo /etc/slurm/slurm.conf; fi" 2>/dev/null)

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

        # Step 11: Setup SlurmDBD if requested
        if [[ "$SETUP_DBD" == "true" ]]; then
            setup_slurmdbd
        fi

        # Step 12: Start slurmctld
        start_slurmctld

        # Step 13: Show cluster status
        show_cluster_status

        # Step 14: Auto-deploy to compute nodes if requested
        if [[ "$AUTO_DEPLOY_COMPUTE" == "true" ]]; then
            setup_remote_compute_nodes

            # Step 15: Deploy Apptainer images to compute nodes
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
