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
    SSH_OPTS="-i $SSH_KEY_FILE -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
    SCP_OPTS="-i $SSH_KEY_FILE -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no"
else
    SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
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

install_slurm() {
    log INFO "Installing/checking Slurm packages..."

    case $OS in
        ubuntu|debian)
            # Install controller packages if needed
            if [[ "$SETUP_CONTROLLER" == "true" ]] || [[ "$SETUP_DBD" == "true" ]]; then
                if ! command -v slurmctld &> /dev/null; then
                    log INFO "Installing slurmctld..."
                    run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y slurm-wlm slurmctld"
                else
                    log INFO "slurmctld already installed"
                fi
            fi

            # Install slurmdbd if needed (check separately - may not be installed even if slurmctld is)
            if [[ "$SETUP_DBD" == "true" ]]; then
                if ! command -v slurmdbd &> /dev/null; then
                    log INFO "Installing slurmdbd..."

                    # Try offline package first (useful when apt has broken dependencies)
                    local offline_pkg="${PROJECT_ROOT}/offline_packages/apt_packages/slurmdbd_21.08.5-2ubuntu1_amd64.deb"
                    if [[ -f "$offline_pkg" ]]; then
                        log INFO "Found offline slurmdbd package, trying dpkg install..."
                        if dpkg -i "$offline_pkg" 2>&1; then
                            log SUCCESS "slurmdbd installed from offline package"
                        else
                            log WARNING "Offline package install failed, trying apt..."
                            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y slurmdbd 2>&1; then
                                log WARNING "Failed to install slurmdbd package"
                                log WARNING "System may have broken package dependencies"
                                log WARNING "Try running: sudo apt --fix-broken install"
                                log WARNING "SlurmDBD will be skipped - accounting will not be available"
                            fi
                        fi
                    else
                        # No offline package, try apt directly
                        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y slurmdbd 2>&1; then
                            log WARNING "Failed to install slurmdbd package"
                            log WARNING "System may have broken package dependencies"
                            log WARNING "Try running: sudo apt --fix-broken install"
                            log WARNING "SlurmDBD will be skipped - accounting will not be available"
                        fi
                    fi
                else
                    log INFO "slurmdbd already installed"
                fi
            fi

            # Install compute node packages if needed
            if [[ "$SETUP_COMPUTE" == "true" ]]; then
                if ! command -v slurmd &> /dev/null; then
                    log INFO "Installing slurmd..."
                    run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y slurmd"
                else
                    log INFO "slurmd already installed"
                fi
            fi
            ;;
        centos|rhel|rocky|almalinux)
            # Install controller packages if needed
            if [[ "$SETUP_CONTROLLER" == "true" ]] || [[ "$SETUP_DBD" == "true" ]]; then
                if ! command -v slurmctld &> /dev/null; then
                    log INFO "Installing slurmctld..."
                    run_command "yum install -y slurm slurm-slurmctld"
                else
                    log INFO "slurmctld already installed"
                fi
            fi

            # Install slurmdbd if needed
            if [[ "$SETUP_DBD" == "true" ]]; then
                if ! command -v slurmdbd &> /dev/null; then
                    log INFO "Installing slurmdbd..."
                    run_command "yum install -y slurm-slurmdbd"
                else
                    log INFO "slurmdbd already installed"
                fi
            fi

            # Install compute node packages if needed
            if [[ "$SETUP_COMPUTE" == "true" ]]; then
                if ! command -v slurmd &> /dev/null; then
                    log INFO "Installing slurmd..."
                    run_command "yum install -y slurm-slurmd"
                else
                    log INFO "slurmd already installed"
                fi
            fi
            ;;
    esac

    log SUCCESS "Slurm packages ready"

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

    # Check if munge key exists
    if [[ ! -f /etc/munge/munge.key ]]; then
        log INFO "Generating munge key..."
        run_command "create-munge-key -f"
    else
        log INFO "Munge key already exists"
    fi

    # Set permissions
    run_command "chown munge:munge /etc/munge/munge.key"
    run_command "chmod 400 /etc/munge/munge.key"

    # Enable and start munge
    run_command "systemctl enable munge"
    run_command "systemctl restart munge"

    # Test munge
    if [[ "$DRY_RUN" == "false" ]]; then
        if munge -n | unmunge &>/dev/null; then
            log SUCCESS "Munge is working"
        else
            log ERROR "Munge test failed"
            exit 1
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
            log INFO "Attempting to install slurmdbd package..."

            case $OS in
                ubuntu|debian)
                    apt-get update && apt-get install -y slurmdbd
                    ;;
                centos|rhel|rocky|almalinux)
                    yum install -y slurm-slurmdbd
                    ;;
            esac

            # Check again
            if ! systemctl list-unit-files slurmdbd.service &>/dev/null; then
                log ERROR "Failed to install slurmdbd - service file still not found"
                log WARNING "Skipping SlurmDBD setup - accounting will not be available"
                return 1
            fi
        fi
    fi

    # Enable and start slurmdbd
    run_command "systemctl enable slurmdbd"
    run_command "systemctl restart slurmdbd"

    # Verify service started
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 3
        if systemctl is-active --quiet slurmdbd; then
            log SUCCESS "SlurmDBD started successfully"
        else
            log WARNING "SlurmDBD may not have started properly"
            log WARNING "Check: journalctl -u slurmdbd -n 30"
        fi
    else
        log SUCCESS "SlurmDBD setup completed (dry-run)"
    fi
}

start_slurmctld() {
    log INFO "Starting slurmctld service..."

    # Enable service
    run_command "systemctl enable slurmctld"

    # Start service
    run_command "systemctl restart slurmctld"

    # Wait for service to start
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 5

        if systemctl is-active --quiet slurmctld; then
            log SUCCESS "slurmctld started successfully"
        else
            log ERROR "Failed to start slurmctld"
            log ERROR "Check logs: journalctl -u slurmctld -n 50"
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

        # Copy installation script
        if ! scp $SCP_OPTS \
            "${PROJECT_ROOT}/install_slurm_cgroup_v2.sh" \
            "$ssh_user@$ip_address:/tmp/" &>/dev/null; then
            log ERROR "Failed to copy install script to $hostname"
            failed_count=$((failed_count + 1))
            continue
        fi

        # Execute installation (use longer timeout for install)
        if ssh -o BatchMode=yes -o ConnectTimeout=300 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no "$ssh_user@$ip_address" \
            "cd /tmp && sudo bash install_slurm_cgroup_v2.sh" &>/dev/null; then
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
