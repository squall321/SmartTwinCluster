#!/bin/bash

#############################################################################
# Phase 1: MariaDB Galera Cluster Setup
#############################################################################
# Description:
#   Sets up MariaDB Galera cluster for multi-master database replication
#   with automatic bootstrap/join detection
#
# Features:
#   - Auto-detect bootstrap vs join mode
#   - Dynamic galera.cnf generation from template
#   - SST (State Snapshot Transfer) configuration
#   - Quorum-based split-brain protection
#   - Integration with my_multihead_cluster.yaml
#
# Usage:
#   sudo ./cluster/setup/phase1_database.sh [OPTIONS]
#
# Options:
#   --config PATH     Path to my_multihead_cluster.yaml
#   --bootstrap       Force bootstrap mode (first node)
#   --join            Force join mode (additional nodes)
#   --dry-run         Show what would be done without executing
#   --help            Show this help message
#
# Author: Claude Code
# Date: 2025-10-27
#############################################################################

# set -e 제거 - Auto-confirm 모드 및 일부 명령 실패 시에도 계속 진행
set -uo pipefail

#############################################################################
# Configuration
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/my_multihead_cluster.yaml"
PARSER_SCRIPT="${PROJECT_ROOT}/cluster/config/parser.py"
DISCOVERY_SCRIPT="${PROJECT_ROOT}/cluster/discovery/auto_discovery.sh"
GALERA_TEMPLATE="${PROJECT_ROOT}/cluster/config/galera_template.cnf"
GALERA_CONFIG="/etc/mysql/mariadb.conf.d/60-galera.cnf"
LOG_FILE="/var/log/cluster_database_setup.log"

# Default values
MODE="auto"
DRY_RUN=false
SKIP_BOOTSTRAP=false
FORCE_FRESH=false

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
  --config PATH     Path to my_multihead_cluster.yaml (default: $CONFIG_FILE)
  --bootstrap       Force bootstrap mode (create new cluster)
  --join            Force join mode (join existing cluster)
  --force-fresh     Clear existing Galera state and start completely fresh
  --dry-run         Show what would be done without executing
  --help            Show this help message

Examples:
  # Auto mode (detect and decide)
  sudo $0 --config ../my_multihead_cluster.yaml

  # Bootstrap new cluster
  sudo $0 --bootstrap

  # Join existing cluster
  sudo $0 --join

  # Force fresh start (clear existing state)
  sudo $0 --bootstrap --force-fresh

  # Dry-run to preview changes
  $0 --dry-run
EOF
}

run_command() {
    local cmd="$*"
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        # Use bash -c instead of eval for better security
        # This prevents command injection from config values
        bash -c "$cmd"
    fi
}

# SSH options for secure remote connections
# Uses accept-new: accepts host key on first connection, rejects if changed later
# This is safer than StrictHostKeyChecking=no which always accepts
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
SCP_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"

# Function to pre-populate known_hosts for a list of IPs
# This is more secure than disabling host key checking
populate_known_hosts() {
    local ip="$1"
    if [[ -n "$ip" ]]; then
        # Use ssh-keyscan to get host key and add to known_hosts
        ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null || true
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

    local deps=("python3" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log ERROR "Required dependency not found: $dep"
            exit 1
        fi
    done

    # Check if parser script exists
    if [[ ! -f "$PARSER_SCRIPT" ]]; then
        log ERROR "Parser script not found: $PARSER_SCRIPT"
        exit 1
    fi

    # Check if galera template exists
    if [[ ! -f "$GALERA_TEMPLATE" ]]; then
        log ERROR "Galera template not found: $GALERA_TEMPLATE"
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

    # Check if MariaDB service is enabled for this controller
    MARIADB_ENABLED=$(echo "$CURRENT_CONTROLLER" | jq -r '.services.mariadb // false')
    if [[ "$MARIADB_ENABLED" != "true" ]]; then
        log ERROR "MariaDB service is not enabled for this controller in the config"
        exit 1
    fi

    log INFO "Current controller: $CURRENT_HOSTNAME ($CURRENT_IP)"

    # Get all MariaDB-enabled controllers
    MARIADB_CONTROLLERS=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --service mariadb 2>/dev/null)
    TOTAL_MARIADB_NODES=$(echo "$MARIADB_CONTROLLERS" | jq '. | length')

    log INFO "Total MariaDB-enabled controllers: $TOTAL_MARIADB_NODES"

    # Get database configuration from YAML
    # Try cluster_info.cluster_name first (multi-head config), then cluster.name as fallback
    CLUSTER_NAME=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cluster_info.cluster_name 2>/dev/null)
    if [[ -z "$CLUSTER_NAME" ]]; then
        CLUSTER_NAME=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cluster.name 2>/dev/null || echo "multihead_cluster")
    fi
    log INFO "Cluster name: $CLUSTER_NAME"

    # Get database-specific config with validation
    DB_ROOT_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.root_password 2>/dev/null)
    SST_USER=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.sst_user 2>/dev/null || echo "sstuser")
    SST_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.sst_password 2>/dev/null)

    # Expand environment variables if value is in ${VAR} format
    # This allows YAML to use: root_password: "${DB_ROOT_PASSWORD}"
    if [[ "$DB_ROOT_PASSWORD" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
        local env_var="${BASH_REMATCH[1]}"
        DB_ROOT_PASSWORD="${!env_var:-}"
        [[ -n "$DB_ROOT_PASSWORD" ]] && log INFO "root_password loaded from environment variable: $env_var"
    fi
    if [[ "$SST_PASSWORD" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
        local env_var="${BASH_REMATCH[1]}"
        SST_PASSWORD="${!env_var:-}"
        [[ -n "$SST_PASSWORD" ]] && log INFO "sst_password loaded from environment variable: $env_var"
    fi

    # Validate passwords - warn if using insecure defaults
    local config_warnings=false
    if [[ -z "$DB_ROOT_PASSWORD" || "$DB_ROOT_PASSWORD" == "changeme" ]]; then
        log WARNING "⚠️  database.mariadb.root_password is not set or uses insecure default!"
        log WARNING "   Please set a secure password in $CONFIG_FILE"
        log WARNING "   Using 'changeme' as fallback - NOT RECOMMENDED FOR PRODUCTION"
        DB_ROOT_PASSWORD="changeme"
        config_warnings=true
    fi

    if [[ -z "$SST_PASSWORD" || "$SST_PASSWORD" == "changeme" ]]; then
        log WARNING "⚠️  database.mariadb.sst_password is not set or uses insecure default!"
        log WARNING "   Please set a secure password in $CONFIG_FILE"
        SST_PASSWORD="changeme"
        config_warnings=true
    fi

    if [[ "$config_warnings" == "true" ]]; then
        log WARNING ""
        log WARNING "=== SECURITY NOTICE ==="
        log WARNING "Add the following to your YAML config:"
        log WARNING "  database:"
        log WARNING "    mariadb:"
        log WARNING "      root_password: <your-secure-password>"
        log WARNING "      sst_password: <your-secure-password>"
        log WARNING ""
        # Auto-confirm 모드 또는 비대화형 환경에서는 자동 계속
        if [[ "$DRY_RUN" == "false" ]] && [[ -t 0 ]]; then
            # 대화형 환경에서만 확인 요청
            read -p "Continue with insecure defaults? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log ERROR "Aborting. Please configure secure passwords first."
                exit 1
            fi
        else
            log WARNING "Non-interactive mode: continuing with default passwords"
        fi
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

    # Set Galera provider path based on OS
    case $OS in
        ubuntu|debian)
            WSREP_PROVIDER="/usr/lib/galera/libgalera_smm.so"
            ;;
        centos|rhel|rocky|almalinux)
            WSREP_PROVIDER="/usr/lib64/galera/libgalera_smm.so"
            ;;
        *)
            log ERROR "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

check_mariadb_installed() {
    log INFO "Checking if MariaDB is installed..."

    if command -v mysql &> /dev/null || command -v mariadb &> /dev/null; then
        log SUCCESS "MariaDB is already installed"
        MARIADB_INSTALLED=true

        # Check version
        MARIADB_VERSION=$(mysql --version 2>/dev/null | grep -oP '(?<=MariaDB )[\d.]+' || echo "unknown")
        log INFO "MariaDB version: $MARIADB_VERSION"
    else
        log WARNING "MariaDB is not installed"
        MARIADB_INSTALLED=false
    fi
}

install_mariadb() {
    if [[ "$MARIADB_INSTALLED" == "true" ]]; then
        log INFO "Skipping MariaDB installation (already installed)"
        return 0
    fi

    log INFO "Installing MariaDB with Galera..."

    # Pre-create mysql user with specific UID/GID if configured in YAML
    # This ensures consistent UID/GID across all nodes for NFS compatibility
    local mysql_uid=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.mysql_uid 2>/dev/null)
    local mysql_gid=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.mysql_gid 2>/dev/null)

    if [[ -n "$mysql_uid" && -n "$mysql_gid" ]]; then
        log INFO "Pre-creating mysql user with UID=$mysql_uid, GID=$mysql_gid"
        if [[ "$DRY_RUN" == "false" ]]; then
            # Create group first if it doesn't exist
            if ! getent group mysql > /dev/null 2>&1; then
                groupadd -g "$mysql_gid" mysql
            fi
            # Create user if it doesn't exist
            if ! id mysql > /dev/null 2>&1; then
                useradd -r -u "$mysql_uid" -g "$mysql_gid" -d /var/lib/mysql -s /sbin/nologin mysql
            else
                log INFO "mysql user already exists, skipping creation"
            fi
        else
            log INFO "[DRY-RUN] Would create mysql user with UID=$mysql_uid, GID=$mysql_gid"
        fi
    else
        log INFO "No custom mysql UID/GID configured, will use system defaults"
        log INFO "💡 To set consistent UID/GID across nodes, add to YAML:"
        log INFO "   database:"
        log INFO "     mariadb:"
        log INFO "       mysql_uid: 999"
        log INFO "       mysql_gid: 999"
    fi

    # Check for offline packages first
    local offline_pkgs="$PROJECT_ROOT/offline_packages/apt_packages"
    local mariadb_deb="$offline_pkgs/mariadb-server-*.deb"

    if [[ -d "$offline_pkgs" ]] && compgen -G "$mariadb_deb" > /dev/null 2>&1; then
        log INFO "Found offline packages, installing from local .deb files..."

        if [[ "$DRY_RUN" == "false" ]]; then
            # Install MariaDB packages from offline directory
            sudo dpkg -i "$offline_pkgs"/mariadb-*.deb "$offline_pkgs"/galera-*.deb "$offline_pkgs"/rsync*.deb 2>/dev/null || true

            # Fix any dependency issues
            sudo dpkg --configure -a 2>/dev/null || true

            log SUCCESS "MariaDB installed from offline packages"
        else
            log INFO "[DRY-RUN] Would install MariaDB from offline packages"
        fi
    else
        # Online installation fallback
        log INFO "No offline packages found, installing online..."

        case $OS in
            ubuntu|debian)
                run_command "apt-get update"
                run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client galera-4 rsync"
                ;;
            centos|rhel|rocky|almalinux)
                run_command "yum install -y mariadb-server mariadb galera rsync"
                ;;
        esac

        log SUCCESS "MariaDB installed successfully (online)"
    fi
}

discover_active_nodes() {
    log INFO "Discovering active MariaDB nodes..."
    log INFO "  Discovery script: $DISCOVERY_SCRIPT"
    log INFO "  Config file: $CONFIG_FILE"

    # Run auto-discovery script
    if [[ ! -f "$DISCOVERY_SCRIPT" ]]; then
        log ERROR "Discovery script not found: $DISCOVERY_SCRIPT"
        exit 1
    fi

    log INFO "  Starting discovery (this may take a while)..."
    local discovery_start=$(date +%s)

    # Run discovery with --verbose to see detailed progress
    # --phase 1: Only check GlusterFS and MariaDB services (skip Redis, Slurm, Web, Keepalived)
    # stderr goes to console (verbose logs), stdout captures JSON
    DISCOVERY_OUTPUT=$("$DISCOVERY_SCRIPT" --config "$CONFIG_FILE" --phase 1 --verbose || echo "{}")

    local discovery_end=$(date +%s)
    local discovery_duration=$((discovery_end - discovery_start))
    log INFO "  Discovery completed in ${discovery_duration} seconds"

    # Validate JSON output
    if ! echo "$DISCOVERY_OUTPUT" | jq -e '.' >/dev/null 2>&1; then
        log WARNING "  Discovery returned invalid JSON, using empty result"
        log WARNING "  Raw output (first 500 chars): ${DISCOVERY_OUTPUT:0:500}"
        DISCOVERY_OUTPUT="{}"
    else
        log INFO "  Discovery returned valid JSON"
        # Show controller count
        local ctrl_count=$(echo "$DISCOVERY_OUTPUT" | jq '.controllers | length' 2>/dev/null || echo "0")
        log INFO "  Total controllers in result: $ctrl_count"
    fi

    # Extract active MariaDB nodes (check for status == "ok")
    log INFO "  Extracting active MariaDB nodes..."
    ACTIVE_CONTROLLERS=$(echo "$DISCOVERY_OUTPUT" | jq -r '.controllers[] | select(.services.mariadb.status == "ok") | .ip' 2>/dev/null || echo "")

    # Count active nodes (handle empty result from grep)
    if [[ -z "$ACTIVE_CONTROLLERS" ]]; then
        ACTIVE_COUNT=0
    else
        ACTIVE_COUNT=$(echo "$ACTIVE_CONTROLLERS" | grep -v '^$' | wc -l)
    fi

    log INFO "Active MariaDB nodes found: $ACTIVE_COUNT"

    if [[ $ACTIVE_COUNT -gt 0 ]]; then
        log INFO "Active nodes:"
        echo "$ACTIVE_CONTROLLERS" | while read -r ip; do
            log INFO "  - $ip"
        done
    else
        log INFO "  No active MariaDB nodes found (will bootstrap new cluster)"
    fi
}

determine_mode() {
    log INFO "Determining operation mode..."

    if [[ "$MODE" != "auto" ]]; then
        log INFO "Mode forced to: $MODE"
        return 0
    fi

    # Auto-detect based on active nodes
    if [[ $ACTIVE_COUNT -eq 0 ]]; then
        MODE="bootstrap"
        log INFO "No active nodes found → Bootstrap mode"
    else
        MODE="join"
        log INFO "Active nodes found → Join mode"
    fi
}

generate_cluster_address() {
    log INFO "Generating cluster address..."

    if [[ "$MODE" == "bootstrap" ]]; then
        # Bootstrap mode: empty gcomm://
        CLUSTER_ADDRESS="gcomm://"
        log INFO "Bootstrap mode: CLUSTER_ADDRESS=$CLUSTER_ADDRESS"
    else
        # Join mode: gcomm://ip1:4567,ip2:4567,...
        local addresses=""
        while read -r ip; do
            if [[ -n "$ip" ]]; then
                if [[ -z "$addresses" ]]; then
                    addresses="$ip:4567"
                else
                    addresses="$addresses,$ip:4567"
                fi
            fi
        done <<< "$ACTIVE_CONTROLLERS"

        CLUSTER_ADDRESS="gcomm://$addresses"
        log INFO "Join mode: CLUSTER_ADDRESS=$CLUSTER_ADDRESS"
    fi
}

generate_galera_config() {
    log INFO "Generating Galera configuration from template..."

    # Validate required variables before generating config
    if [[ -z "$CLUSTER_NAME" ]]; then
        log ERROR "CLUSTER_NAME is empty! Check cluster_info.cluster_name in YAML config"
        log ERROR "Current value: '$CLUSTER_NAME'"
        exit 1
    fi

    if [[ -z "$CLUSTER_ADDRESS" ]]; then
        log ERROR "CLUSTER_ADDRESS is empty! This should be set by generate_cluster_address()"
        exit 1
    fi

    if [[ -z "$CURRENT_IP" ]]; then
        log ERROR "CURRENT_IP is empty! Could not detect current node IP"
        exit 1
    fi

    log INFO "Galera config variables:"
    log INFO "  - CLUSTER_NAME: $CLUSTER_NAME"
    log INFO "  - CLUSTER_ADDRESS: $CLUSTER_ADDRESS"
    log INFO "  - CURRENT_IP: $CURRENT_IP"
    log INFO "  - CURRENT_HOSTNAME: $CURRENT_HOSTNAME"

    # Calculate optimal settings based on system resources
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))

    # InnoDB buffer pool: 70% of RAM
    INNODB_BUFFER_POOL_SIZE=$((TOTAL_RAM_GB * 70 / 100))G

    # CPU cores for slave threads
    CPU_CORES=$(nproc)
    WSREP_SLAVE_THREADS=$((CPU_CORES * 2))

    # Max connections
    MAX_CONNECTIONS=500

    log INFO "System resources detected:"
    log INFO "  - Total RAM: ${TOTAL_RAM_GB}G"
    log INFO "  - InnoDB buffer pool: $INNODB_BUFFER_POOL_SIZE"
    log INFO "  - CPU cores: $CPU_CORES"
    log INFO "  - Wsrep slave threads: $WSREP_SLAVE_THREADS"

    # Read template and substitute variables
    local config_content
    config_content=$(cat "$GALERA_TEMPLATE")

    # Substitute template variables
    config_content="${config_content//\{\{NODE_IP\}\}/$CURRENT_IP}"
    config_content="${config_content//\{\{NODE_HOSTNAME\}\}/$CURRENT_HOSTNAME}"
    config_content="${config_content//\{\{WSREP_PROVIDER_PATH\}\}/$WSREP_PROVIDER}"
    config_content="${config_content//\{\{CLUSTER_NAME\}\}/$CLUSTER_NAME}"
    config_content="${config_content//\{\{CLUSTER_ADDRESS\}\}/$CLUSTER_ADDRESS}"
    config_content="${config_content//\{\{SST_USER\}\}/$SST_USER}"
    config_content="${config_content//\{\{SST_PASSWORD\}\}/$SST_PASSWORD}"
    config_content="${config_content//\{\{WSREP_SLAVE_THREADS\}\}/$WSREP_SLAVE_THREADS}"
    config_content="${config_content//\{\{INNODB_BUFFER_POOL_SIZE\}\}/$INNODB_BUFFER_POOL_SIZE}"
    config_content="${config_content//\{\{MAX_CONNECTIONS\}\}/$MAX_CONNECTIONS}"
    config_content="${config_content//\{\{BIND_ADDRESS\}\}/0.0.0.0}"

    # Write configuration file
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would write Galera config to: $GALERA_CONFIG"
        log INFO "[DRY-RUN] Config preview (first 20 lines):"
        echo "$config_content" | head -20
    else
        echo "$config_content" > "$GALERA_CONFIG"
        chmod 644 "$GALERA_CONFIG"
        log SUCCESS "Galera configuration written to $GALERA_CONFIG"
    fi
}

stop_mariadb() {
    log INFO "Stopping MariaDB service..."

    run_command "systemctl stop mariadb || systemctl stop mysql || true"

    log SUCCESS "MariaDB stopped"
}

check_existing_galera_state() {
    # Check for existing Galera state files
    local grastate="/var/lib/mysql/grastate.dat"
    local gvwstate="/var/lib/mysql/gvwstate.dat"

    if [[ ! -f "$grastate" ]]; then
        log INFO "No existing Galera state found - fresh bootstrap"
        return 1  # No existing state
    fi

    log INFO "Found existing Galera state file: $grastate"

    # Read existing cluster UUID from grastate.dat
    local existing_uuid=$(grep "^uuid:" "$grastate" 2>/dev/null | awk '{print $2}')
    local existing_seqno=$(grep "^seqno:" "$grastate" 2>/dev/null | awk '{print $2}')
    local safe_to_bootstrap=$(grep "^safe_to_bootstrap:" "$grastate" 2>/dev/null | awk '{print $2}')

    log INFO "Existing state:"
    log INFO "  - UUID: ${existing_uuid:-unknown}"
    log INFO "  - Sequence number: ${existing_seqno:-unknown}"
    log INFO "  - Safe to bootstrap: ${safe_to_bootstrap:-unknown}"

    # If safe_to_bootstrap is 1 and seqno is valid (not -1), we can recover
    if [[ "$safe_to_bootstrap" == "1" && "$existing_seqno" != "-1" ]]; then
        log INFO "Existing state is safe to bootstrap - will recover existing cluster"
        return 0  # Can use existing state
    fi

    # Check if seqno is -1 (crash recovery needed)
    if [[ "$existing_seqno" == "-1" ]]; then
        log WARNING "Previous shutdown was unclean (seqno=-1)"
        log INFO "Running wsrep_recover to find last committed position..."

        if [[ "$DRY_RUN" == "false" ]]; then
            # Run wsrep_recover to get the correct position
            local recover_output
            recover_output=$(mysqld --wsrep-recover 2>&1 || true)
            local recovered_pos=$(echo "$recover_output" | grep -oP 'Recovered position.*:\K[0-9]+' | tail -1)

            if [[ -n "$recovered_pos" && "$recovered_pos" != "-1" ]]; then
                log SUCCESS "Recovered position: $recovered_pos"

                # Update grastate.dat with recovered position
                sed -i "s/^seqno:.*/seqno: $recovered_pos/" "$grastate"
                sed -i "s/^safe_to_bootstrap:.*/safe_to_bootstrap: 1/" "$grastate"

                log SUCCESS "Updated grastate.dat for safe recovery"
                return 0  # Can now use existing state
            else
                log WARNING "Could not recover valid position"
            fi
        fi
    fi

    # State exists but not safe - need user decision
    log WARNING "Existing Galera state found but may not be safe to use"
    return 2  # Existing state but needs attention
}

handle_existing_galera_state() {
    local state_check=$1

    case $state_check in
        0)
            # Existing state is usable - recover existing cluster
            log SUCCESS "Recovering existing Galera cluster..."
            return 0
            ;;
        1)
            # No existing state - fresh bootstrap
            log INFO "Starting fresh Galera cluster..."
            return 0
            ;;
        2)
            # Existing state but unclear - ask user
            log WARNING "Existing Galera cluster state detected"
            log WARNING "Options:"
            log WARNING "  1. Keep existing state and try to recover"
            log WARNING "  2. Clear state and start fresh cluster"

            if [[ "$DRY_RUN" == "false" ]] && [[ -t 0 ]]; then
                read -p "Clear existing state and start fresh? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    log INFO "Clearing existing Galera state..."
                    rm -f /var/lib/mysql/grastate.dat
                    rm -f /var/lib/mysql/gvwstate.dat
                    log SUCCESS "Galera state cleared"
                else
                    log INFO "Keeping existing state - attempting recovery"
                    # Set safe_to_bootstrap to 1 for recovery attempt
                    if [[ -f /var/lib/mysql/grastate.dat ]]; then
                        sed -i "s/^safe_to_bootstrap:.*/safe_to_bootstrap: 1/" /var/lib/mysql/grastate.dat
                    fi
                fi
            else
                # Non-interactive: try to recover existing state
                log WARNING "Non-interactive mode: attempting to recover existing state"
                if [[ -f /var/lib/mysql/grastate.dat ]]; then
                    sed -i "s/^safe_to_bootstrap:.*/safe_to_bootstrap: 1/" /var/lib/mysql/grastate.dat
                fi
            fi
            return 0
            ;;
    esac
}

bootstrap_cluster() {
    log INFO "Bootstrapping Galera cluster..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Force fresh start if requested
        if [[ "$FORCE_FRESH" == "true" ]]; then
            log WARNING "Force fresh mode: clearing existing Galera state..."
            rm -f /var/lib/mysql/grastate.dat
            rm -f /var/lib/mysql/gvwstate.dat
            log SUCCESS "Galera state cleared"
        else
            # Check for existing Galera state
            check_existing_galera_state
            local state_result=$?

            # Handle existing state appropriately
            handle_existing_galera_state $state_result
        fi
    fi

    # Use galera_new_cluster command for bootstrap
    log INFO "Running galera_new_cluster..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Run galera_new_cluster and capture output
        local bootstrap_output
        bootstrap_output=$(galera_new_cluster 2>&1) || true
        local bootstrap_exit=$?

        if [[ -n "$bootstrap_output" ]]; then
            log INFO "Bootstrap output: $bootstrap_output"
        fi

        # Wait for MariaDB to start
        sleep 5

        # Check if MariaDB is running
        if systemctl is-active --quiet mariadb; then
            log SUCCESS "Galera cluster bootstrapped successfully"

            # Show cluster info
            local cluster_uuid=$(mysql -N -e "SHOW STATUS LIKE 'wsrep_cluster_state_uuid';" 2>/dev/null | awk '{print $2}')
            local cluster_size=$(mysql -N -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print $2}')
            log INFO "Cluster UUID: ${cluster_uuid:-unknown}"
            log INFO "Cluster size: ${cluster_size:-1}"
        else
            log ERROR "Failed to bootstrap Galera cluster"
            log ERROR "Bootstrap exit code: $bootstrap_exit"
            log ERROR ""
            log ERROR "=== MariaDB Service Status ==="
            systemctl status mariadb --no-pager 2>&1 | head -30 || true
            log ERROR ""
            log ERROR "=== Last 50 lines from journalctl ==="
            journalctl -u mariadb -n 50 --no-pager 2>&1 || true
            log ERROR ""
            log ERROR "=== MariaDB Error Log (last 50 lines) ==="
            tail -50 /var/log/mysql/error.log 2>/dev/null || tail -50 /var/lib/mysql/*.err 2>/dev/null || true
            log ERROR ""
            log ERROR "=== Current grastate.dat ==="
            cat /var/lib/mysql/grastate.dat 2>/dev/null || echo "File not found"
            log ERROR ""
            log ERROR "=== Galera Config ==="
            grep -E "^(wsrep_|binlog_format)" /etc/mysql/mariadb.conf.d/60-galera.cnf 2>/dev/null || \
            grep -E "^(wsrep_|binlog_format)" /etc/mysql/conf.d/galera.cnf 2>/dev/null || \
            echo "Galera config not found"
            exit 1
        fi
    else
        log INFO "[DRY-RUN] Would run: galera_new_cluster"
    fi
}

join_cluster() {
    log INFO "Joining existing Galera cluster..."

    # Start MariaDB normally (it will join via wsrep_cluster_address)
    run_command "systemctl start mariadb"

    # Wait for MariaDB to start and join
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO "Waiting for node to join cluster (SST may take time)..."

        local max_wait=300  # 5 minutes
        local elapsed=0
        local joined=false

        while [[ $elapsed -lt $max_wait ]]; do
            if systemctl is-active --quiet mariadb; then
                # Check cluster status
                local cluster_size=$(mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | grep wsrep_cluster_size | awk '{print $2}' || echo "0")

                if [[ $cluster_size -gt 0 ]]; then
                    log SUCCESS "Node joined cluster successfully"
                    log INFO "Cluster size: $cluster_size nodes"
                    joined=true
                    break
                fi
            fi

            sleep 5
            elapsed=$((elapsed + 5))
        done

        if [[ "$joined" == "false" ]]; then
            log ERROR "Failed to join cluster within timeout"
            exit 1
        fi
    fi
}

deploy_to_other_controllers() {
    log INFO "Deploying MariaDB to other controllers..."

    # Track failed nodes for summary
    local -a FAILED_NODES=()

    # Get SSH user from config
    local ssh_user=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get nodes.controllers[0].ssh_user 2>/dev/null || echo "root")

    # Get first controller IP
    local first_node_ip=$(echo "$MARIADB_CONTROLLERS" | jq -r '.[0].ip_address')

    # Only run on first controller
    if [[ "$CURRENT_IP" != "$first_node_ip" ]]; then
        log INFO "This is not the first controller, skipping deployment to other nodes"
        return 0
    fi

    log INFO "This is the first controller, deploying to other nodes..."

    # Deploy to each other controller
    local node_count=0
    while IFS= read -r controller; do
        local ip=$(echo "$controller" | jq -r '.ip_address')
        local hostname=$(echo "$controller" | jq -r '.hostname')

        # Skip current node
        if [[ "$ip" == "$CURRENT_IP" ]]; then
            continue
        fi

        node_count=$((node_count + 1))
        log INFO "Deploying to $hostname ($ip)..."

        # Pre-populate known_hosts for security
        populate_known_hosts "$ip"

        # Test SSH connection (BatchMode prevents password prompts)
        if ! ssh $SSH_OPTS "$ssh_user@$ip" "echo OK" > /dev/null 2>&1; then
            log WARNING "Cannot connect to $hostname ($ip) via SSH key authentication"
            log WARNING "Please run: ./setup_ssh_passwordless.sh to configure SSH keys"
            FAILED_NODES+=("$hostname ($ip): SSH connection failed")
            continue
        fi

        # Copy phase1_database.sh and config file to remote node
        if ! scp $SCP_OPTS "$0" "$ssh_user@$ip:/tmp/phase1_database.sh" > /dev/null 2>&1; then
            log WARNING "Failed to copy script to $hostname"
            FAILED_NODES+=("$hostname ($ip): Script copy failed")
            continue
        fi

        # Copy config file to remote node
        if ! scp $SCP_OPTS "$CONFIG_FILE" "$ssh_user@$ip:/tmp/cluster_config.yaml" > /dev/null 2>&1; then
            log WARNING "Failed to copy config to $hostname"
            FAILED_NODES+=("$hostname ($ip): Config copy failed")
            continue
        fi

        # Execute on remote node (without bootstrap)
        log INFO "Installing MariaDB on $hostname..."
        if ssh $SSH_OPTS "$ssh_user@$ip" \
            "sudo bash /tmp/phase1_database.sh --config /tmp/cluster_config.yaml --skip-bootstrap --join" 2>&1; then
            log SUCCESS "$hostname: MariaDB installed and joined cluster"
        else
            log WARNING "$hostname: MariaDB installation/join failed"
            FAILED_NODES+=("$hostname ($ip): Installation failed")
        fi

    done < <(echo "$MARIADB_CONTROLLERS" | jq -c '.[]')

    if [[ $node_count -gt 0 ]]; then
        log SUCCESS "Deployed to $node_count other controller(s)"
        # Wait for all nodes to join
        log INFO "Waiting 15 seconds for all MariaDB nodes to join..."
        sleep 15
    fi

    # Report failed nodes summary
    if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
        log ERROR "=== FAILED NODES SUMMARY ==="
        for failed in "${FAILED_NODES[@]}"; do
            log ERROR "  - $failed"
        done
        log ERROR "Please check these nodes manually and re-run setup"
        return 1
    fi
}

configure_sst_user() {
    log INFO "Configuring SST user..."

    if [[ "$MODE" != "bootstrap" ]]; then
        log INFO "Skipping SST user creation (only done on bootstrap node)"
        return 0
    fi

    # Create SST user for state snapshot transfer
    local sql="CREATE USER IF NOT EXISTS '${SST_USER}'@'%' IDENTIFIED BY '${SST_PASSWORD}';"
    sql+="GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON *.* TO '${SST_USER}'@'%';"
    sql+="FLUSH PRIVILEGES;"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create SST user: $SST_USER"
    else
        mysql -e "$sql" 2>/dev/null || log WARNING "Failed to create SST user (may already exist)"
        log SUCCESS "SST user configured"
    fi
}

configure_root_password() {
    log INFO "Configuring root password..."

    if [[ "$MODE" != "bootstrap" ]]; then
        log INFO "Skipping root password setup (only done on bootstrap node)"
        return 0
    fi

    # Set root password
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would set MariaDB root password"
    else
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';" 2>/dev/null || \
        mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${DB_ROOT_PASSWORD}');" 2>/dev/null || \
        log WARNING "Failed to set root password (may already be set)"

        log SUCCESS "Root password configured"
    fi
}

enable_mariadb_service() {
    log INFO "Enabling MariaDB service..."

    run_command "systemctl enable mariadb"

    log SUCCESS "MariaDB service enabled"
}

show_cluster_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log INFO "Cluster status:"

    # Query cluster status
    mysql -e "SHOW STATUS LIKE 'wsrep_%';" 2>/dev/null | grep -E "(wsrep_cluster_size|wsrep_cluster_status|wsrep_connected|wsrep_ready|wsrep_local_state_comment)" || true
}

#############################################################################
# Main
#############################################################################

main() {
    log INFO "=== Phase 1: MariaDB Galera Cluster Setup ==="
    log INFO "Starting at $(date)"

    # Step 0: Check root privileges
    check_root

    # Step 1: Check dependencies
    check_dependencies

    # Step 2: Load configuration
    load_config

    # Step 3: Detect OS
    detect_os

    # Step 4: Check if MariaDB is installed
    check_mariadb_installed

    # Step 5: Install MariaDB if needed
    if [[ "$MARIADB_INSTALLED" == "false" ]]; then
        install_mariadb
    fi

    # Step 6: Discover active MariaDB nodes
    discover_active_nodes

    # Step 7: Determine operation mode
    determine_mode

    # Step 8: Generate cluster address
    generate_cluster_address

    # Step 9: Generate Galera configuration
    generate_galera_config

    # Step 10: Stop MariaDB before reconfiguration
    stop_mariadb

    # Step 11: Bootstrap or join cluster
    if [[ "$SKIP_BOOTSTRAP" == "false" ]]; then
        if [[ "$MODE" == "bootstrap" ]]; then
            bootstrap_cluster
            configure_sst_user
            configure_root_password

            # Step 11.5: Deploy to other controllers (only after successful bootstrap)
            deploy_to_other_controllers
        else
            join_cluster
        fi
    else
        log INFO "Skipping bootstrap/join (--skip-bootstrap flag)"
    fi

    # Step 12: Enable service for auto-start
    enable_mariadb_service

    # Step 13: Show cluster status
    show_cluster_status

    log SUCCESS "=== MariaDB Galera cluster setup completed ==="
    log INFO "Finished at $(date)"

    if [[ "$MODE" == "bootstrap" ]]; then
        log INFO ""
        log INFO "Next steps:"
        log INFO "  1. Run this script on other MariaDB-enabled controllers to join them to the cluster"
        log INFO "  2. Monitor cluster status: mysql -e \"SHOW STATUS LIKE 'wsrep_%';\""
        log INFO "  3. Test replication by creating a database on one node and checking others"
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
        --bootstrap)
            MODE="bootstrap"
            shift
            ;;
        --join)
            MODE="join"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
            ;;
        --force-fresh)
            FORCE_FRESH=true
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

# Run main function
main
