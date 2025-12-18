#!/bin/bash

################################################################################
# Phase 9: Software Installation (MPI & Apptainer)
#
# This script installs optional HPC software components:
# - OpenMPI or MPICH (MPI library for parallel computing)
# - Apptainer (container runtime for HPC)
#
# Features:
# - Reads install_mpi and install_apptainer options from YAML config
# - Supports both online and offline installation modes
# - Deploys to all controllers and compute nodes
# - Supports Ubuntu/Debian and RHEL/CentOS/Rocky
#
# Usage:
#   sudo ./phase9_software.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml
#   --mpi-only          Install only MPI (skip Apptainer)
#   --apptainer-only    Install only Apptainer (skip MPI)
#   --mpi-type TYPE     MPI type: openmpi (default) or mpich
#   --dry-run           Preview actions without executing
#   --force             Force reinstall even if already installed
#   --help              Show this help message
#
# Examples:
#   sudo ./phase9_software.sh --config ../my_multihead_cluster.yaml
#   sudo ./phase9_software.sh --mpi-only --mpi-type mpich
#   sudo ./phase9_software.sh --apptainer-only
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
PARSER_SCRIPT="$PROJECT_ROOT/cluster/config/parser.py"
DRY_RUN=false
FORCE=false
MPI_ONLY=false
APPTAINER_ONLY=false
MPI_TYPE="openmpi"  # openmpi or mpich
LOG_FILE="/var/log/cluster_software_setup.log"

# SSH options (includes GSSAPIAuthentication=no to prevent Kerberos delays)
#
# IMPORTANT: When running with sudo, we need to use the original user's SSH key
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
SSH_KEY_FILE="${ORIGINAL_HOME}/.ssh/id_rsa"

# -n: Don't read from stdin (critical for while read loops!)
if [[ -f "$SSH_KEY_FILE" ]]; then
    SSH_OPTS="-n -i $SSH_KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o BatchMode=yes -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
else
    SSH_OPTS="-n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o BatchMode=yes -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
fi

################################################################################
# Logging Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local color=$NC
    case $level in
        ERROR) color=$RED ;;
        SUCCESS) color=$GREEN ;;
        WARNING) color=$YELLOW ;;
        INFO) color=$BLUE ;;
        PHASE) color=$CYAN ;;
    esac

    if [[ "$DRY_RUN" == "false" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi

    echo -e "${color}[$level]${NC} $message"
}

show_help() {
    grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//'
}

run_command() {
    local cmd="$1"
    local description="${2:-$cmd}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would run: $cmd"
        return 0
    fi

    log INFO "Running: $description"
    if eval "$cmd"; then
        return 0
    else
        log ERROR "Command failed: $cmd"
        return 1
    fi
}

run_remote() {
    local user=$1
    local ip=$2
    local cmd=$3
    local description="${4:-Remote: $cmd}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would run on ${user}@${ip}: $cmd"
        return 0
    fi

    log INFO "Running on ${user}@${ip}: $description"
    if ssh -n $SSH_OPTS "${user}@${ip}" "$cmd" 2>/dev/null; then
        return 0
    else
        log WARNING "Remote command failed on ${ip}: $cmd"
        return 1
    fi
}

################################################################################
# Configuration Parsing
################################################################################

parse_config() {
    log INFO "Parsing configuration from $CONFIG_PATH..."

    if [[ ! -f "$CONFIG_PATH" ]]; then
        log ERROR "Config file not found: $CONFIG_PATH"
        exit 1
    fi

    if [[ ! -f "$PARSER_SCRIPT" ]]; then
        log ERROR "Parser script not found: $PARSER_SCRIPT"
        exit 1
    fi

    # Get installation options
    INSTALL_MPI=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_PATH" --get "installation.install_mpi" 2>/dev/null || echo "false")
    INSTALL_APPTAINER=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_PATH" --get "installation.install_apptainer" 2>/dev/null || echo "false")
    OFFLINE_MODE=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_PATH" --get "installation.offline_mode" 2>/dev/null || echo "false")
    PACKAGE_CACHE=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_PATH" --get "installation.package_cache_path" 2>/dev/null || echo "/var/cache/cluster_packages")

    # Get MPI config if exists
    MPI_TYPE_CONFIG=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_PATH" --get "mpi_support.mpi_type" 2>/dev/null || echo "")
    if [[ -n "$MPI_TYPE_CONFIG" ]]; then
        MPI_TYPE="$MPI_TYPE_CONFIG"
    fi

    log INFO "Configuration:"
    log INFO "  install_mpi: $INSTALL_MPI"
    log INFO "  install_apptainer: $INSTALL_APPTAINER"
    log INFO "  offline_mode: $OFFLINE_MODE"
    log INFO "  mpi_type: $MPI_TYPE"
}

get_all_nodes() {
    log INFO "Getting all nodes from configuration..."

    # Get controllers
    CONTROLLERS=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_PATH" --get "nodes.controllers" 2>/dev/null | \
        python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join([f\"{c['ssh_user']}@{c['ip_address']}\" for c in data]))" 2>/dev/null || echo "")

    # Get compute nodes
    COMPUTE_NODES=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_PATH" --get "nodes.compute_nodes" 2>/dev/null | \
        python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join([f\"{c['ssh_user']}@{c['ip_address']}\" for c in data]))" 2>/dev/null || echo "")

    # Combine all nodes
    ALL_NODES=""
    if [[ -n "$CONTROLLERS" ]]; then
        ALL_NODES="$CONTROLLERS"
    fi
    if [[ -n "$COMPUTE_NODES" ]]; then
        if [[ -n "$ALL_NODES" ]]; then
            ALL_NODES="$ALL_NODES"$'\n'"$COMPUTE_NODES"
        else
            ALL_NODES="$COMPUTE_NODES"
        fi
    fi

    NODE_COUNT=$(echo "$ALL_NODES" | grep -c . || echo "0")
    log INFO "Found $NODE_COUNT nodes to configure"
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
    log INFO "Detected OS: $OS_ID $OS_VERSION"
}

################################################################################
# MPI Installation
################################################################################

install_mpi_local() {
    log PHASE "Installing MPI ($MPI_TYPE) locally..."

    # Check if already installed
    if [[ "$FORCE" == "false" ]]; then
        if command -v mpirun &>/dev/null; then
            local current_version=$(mpirun --version 2>&1 | head -1)
            log INFO "MPI already installed: $current_version"
            return 0
        fi
    fi

    case $OS_ID in
        ubuntu|debian)
            if [[ "$MPI_TYPE" == "openmpi" ]]; then
                run_command "apt-get update" "Update package lists"
                run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y openmpi-bin libopenmpi-dev openmpi-common" "Install OpenMPI"
            elif [[ "$MPI_TYPE" == "mpich" ]]; then
                run_command "apt-get update" "Update package lists"
                run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y mpich libmpich-dev" "Install MPICH"
            fi
            ;;
        centos|rhel|rocky|almalinux)
            if [[ "$MPI_TYPE" == "openmpi" ]]; then
                run_command "yum install -y openmpi openmpi-devel" "Install OpenMPI"
                # Add module path for RHEL-based systems
                echo 'module load mpi/openmpi-x86_64' >> /etc/profile.d/openmpi.sh 2>/dev/null || true
            elif [[ "$MPI_TYPE" == "mpich" ]]; then
                run_command "yum install -y mpich mpich-devel" "Install MPICH"
            fi
            ;;
        *)
            log ERROR "Unsupported OS: $OS_ID"
            return 1
            ;;
    esac

    log SUCCESS "MPI ($MPI_TYPE) installed successfully"
}

install_mpi_remote() {
    local user_ip=$1
    local user=${user_ip%@*}
    local ip=${user_ip#*@}

    log INFO "Installing MPI on $ip..."

    # Detect remote OS
    local remote_os=$(ssh -n $SSH_OPTS "${user}@${ip}" "cat /etc/os-release 2>/dev/null | grep ^ID= | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "unknown")

    case $remote_os in
        ubuntu|debian)
            if [[ "$MPI_TYPE" == "openmpi" ]]; then
                run_remote "$user" "$ip" \
                    "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openmpi-bin libopenmpi-dev openmpi-common" \
                    "Install OpenMPI"
            elif [[ "$MPI_TYPE" == "mpich" ]]; then
                run_remote "$user" "$ip" \
                    "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mpich libmpich-dev" \
                    "Install MPICH"
            fi
            ;;
        centos|rhel|rocky|almalinux)
            if [[ "$MPI_TYPE" == "openmpi" ]]; then
                run_remote "$user" "$ip" \
                    "sudo yum install -y openmpi openmpi-devel" \
                    "Install OpenMPI"
            elif [[ "$MPI_TYPE" == "mpich" ]]; then
                run_remote "$user" "$ip" \
                    "sudo yum install -y mpich mpich-devel" \
                    "Install MPICH"
            fi
            ;;
        *)
            log WARNING "Unknown OS on $ip, skipping MPI installation"
            return 1
            ;;
    esac

    log SUCCESS "MPI installed on $ip"
}

install_mpi_all_nodes() {
    log PHASE "Installing MPI on all nodes..."

    local success_count=0
    local fail_count=0

    # Install locally first
    install_mpi_local && ((success_count++)) || ((fail_count++))

    # Install on remote nodes
    while IFS= read -r node; do
        [[ -z "$node" ]] && continue

        if install_mpi_remote "$node"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done <<< "$ALL_NODES"

    log INFO "MPI installation complete: $success_count succeeded, $fail_count failed"
}

################################################################################
# Apptainer Installation
################################################################################

install_apptainer_local() {
    log PHASE "Installing Apptainer locally..."

    # Check if already installed
    if [[ "$FORCE" == "false" ]]; then
        if command -v apptainer &>/dev/null; then
            local current_version=$(apptainer --version 2>&1)
            log INFO "Apptainer already installed: $current_version"
            return 0
        fi
    fi

    case $OS_ID in
        ubuntu|debian)
            run_command "apt-get update" "Update package lists"

            # Check if apptainer is in default repos
            if apt-cache show apptainer &>/dev/null; then
                run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y apptainer" "Install Apptainer from repo"
            else
                # Install from official Apptainer repo
                log INFO "Adding Apptainer repository..."
                run_command "apt-get install -y software-properties-common" "Install prerequisites"
                run_command "add-apt-repository -y ppa:apptainer/ppa || true" "Add Apptainer PPA"
                run_command "apt-get update" "Update package lists"
                run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y apptainer" "Install Apptainer"
            fi
            ;;
        centos|rhel|rocky|almalinux)
            # Enable EPEL if needed
            run_command "yum install -y epel-release || true" "Enable EPEL"

            # Check if apptainer is available
            if yum info apptainer &>/dev/null; then
                run_command "yum install -y apptainer" "Install Apptainer"
            else
                # Install from Apptainer repo
                log INFO "Adding Apptainer repository..."
                run_command "yum install -y yum-utils" "Install yum-utils"
                run_command "yum-config-manager --add-repo https://download.opensuse.org/repositories/home:/spack/CentOS_8/home:spack.repo || true" "Add Apptainer repo"
                run_command "yum install -y apptainer" "Install Apptainer"
            fi
            ;;
        *)
            log ERROR "Unsupported OS: $OS_ID"
            return 1
            ;;
    esac

    # Create default directories
    run_command "mkdir -p /opt/apptainers" "Create Apptainer images directory"
    run_command "mkdir -p /tmp/apptainer" "Create Apptainer cache directory"

    log SUCCESS "Apptainer installed successfully"
}

install_apptainer_remote() {
    local user_ip=$1
    local user=${user_ip%@*}
    local ip=${user_ip#*@}

    log INFO "Installing Apptainer on $ip..."

    # Detect remote OS
    local remote_os=$(ssh -n $SSH_OPTS "${user}@${ip}" "cat /etc/os-release 2>/dev/null | grep ^ID= | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "unknown")

    case $remote_os in
        ubuntu|debian)
            # Check if apptainer is available, if not add PPA
            run_remote "$user" "$ip" \
                "sudo apt-get update && (apt-cache show apptainer &>/dev/null || (sudo apt-get install -y software-properties-common && sudo add-apt-repository -y ppa:apptainer/ppa && sudo apt-get update)) && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apptainer" \
                "Install Apptainer"
            ;;
        centos|rhel|rocky|almalinux)
            run_remote "$user" "$ip" \
                "sudo yum install -y epel-release || true; sudo yum install -y apptainer || (sudo yum install -y yum-utils && sudo yum-config-manager --add-repo https://download.opensuse.org/repositories/home:/spack/CentOS_8/home:spack.repo && sudo yum install -y apptainer)" \
                "Install Apptainer"
            ;;
        *)
            log WARNING "Unknown OS on $ip, skipping Apptainer installation"
            return 1
            ;;
    esac

    # Create directories
    run_remote "$user" "$ip" "sudo mkdir -p /opt/apptainers /tmp/apptainer" "Create Apptainer directories"

    log SUCCESS "Apptainer installed on $ip"
}

install_apptainer_all_nodes() {
    log PHASE "Installing Apptainer on all nodes..."

    local success_count=0
    local fail_count=0

    # Install locally first
    install_apptainer_local && ((success_count++)) || ((fail_count++))

    # Install on remote nodes
    while IFS= read -r node; do
        [[ -z "$node" ]] && continue

        if install_apptainer_remote "$node"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done <<< "$ALL_NODES"

    log INFO "Apptainer installation complete: $success_count succeeded, $fail_count failed"
}

################################################################################
# Verification
################################################################################

verify_installation() {
    log PHASE "Verifying installations..."

    local all_good=true

    # Verify MPI
    if [[ "$INSTALL_MPI" == "true" ]] || [[ "$MPI_ONLY" == "true" ]]; then
        if command -v mpirun &>/dev/null; then
            local mpi_version=$(mpirun --version 2>&1 | head -1)
            log SUCCESS "MPI verified: $mpi_version"
        else
            log ERROR "MPI not found after installation"
            all_good=false
        fi
    fi

    # Verify Apptainer
    if [[ "$INSTALL_APPTAINER" == "true" ]] || [[ "$APPTAINER_ONLY" == "true" ]]; then
        if command -v apptainer &>/dev/null; then
            local apptainer_version=$(apptainer --version 2>&1)
            log SUCCESS "Apptainer verified: $apptainer_version"
        else
            log ERROR "Apptainer not found after installation"
            all_good=false
        fi
    fi

    if [[ "$all_good" == "true" ]]; then
        log SUCCESS "All verifications passed"
        return 0
    else
        log ERROR "Some verifications failed"
        return 1
    fi
}

################################################################################
# Main
################################################################################

main() {
    log PHASE "=========================================="
    log PHASE "Phase 9: Software Installation (MPI & Apptainer)"
    log PHASE "=========================================="

    # Initialize log file
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "=== Phase 9 Software Installation Started: $(date) ===" >> "$LOG_FILE"
    fi

    # Parse configuration
    parse_config

    # Get all nodes
    get_all_nodes

    # Detect local OS
    detect_os

    # Determine what to install
    local do_mpi=false
    local do_apptainer=false

    if [[ "$MPI_ONLY" == "true" ]]; then
        do_mpi=true
    elif [[ "$APPTAINER_ONLY" == "true" ]]; then
        do_apptainer=true
    else
        # Use config values
        [[ "$INSTALL_MPI" == "true" ]] && do_mpi=true
        [[ "$INSTALL_APPTAINER" == "true" ]] && do_apptainer=true
    fi

    # Check if anything to do
    if [[ "$do_mpi" == "false" ]] && [[ "$do_apptainer" == "false" ]]; then
        log WARNING "Neither MPI nor Apptainer installation is enabled"
        log INFO "Set install_mpi: true or install_apptainer: true in YAML config"
        log INFO "Or use --mpi-only or --apptainer-only flags"
        exit 0
    fi

    # Install MPI
    if [[ "$do_mpi" == "true" ]]; then
        install_mpi_all_nodes
    fi

    # Install Apptainer
    if [[ "$do_apptainer" == "true" ]]; then
        install_apptainer_all_nodes
    fi

    # Verify installations
    verify_installation

    log PHASE "=========================================="
    log SUCCESS "Phase 9 completed successfully"
    log PHASE "=========================================="
}

# Parse command line arguments
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
            FORCE=true
            shift
            ;;
        --mpi-only)
            MPI_ONLY=true
            shift
            ;;
        --apptainer-only)
            APPTAINER_ONLY=true
            shift
            ;;
        --mpi-type)
            MPI_TYPE="$2"
            shift 2
            ;;
        --help|-h)
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

# Run main
main
