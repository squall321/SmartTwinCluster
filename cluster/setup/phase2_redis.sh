#!/bin/bash

#############################################################################
# Phase 2: Redis Cluster Setup
#############################################################################
# Description:
#   Sets up Redis Cluster for distributed caching and session storage
#   Supports both Cluster mode (3+ nodes) and Sentinel mode (2 nodes)
#
# Features:
#   - Auto-detect cluster size and choose mode
#   - Cluster mode: Hash slot-based partitioning (3+ nodes)
#   - Sentinel mode: Master-replica with automatic failover (2 nodes)
#   - Dynamic redis.conf generation from template
#   - Integration with my_multihead_cluster.yaml
#
# Usage:
#   sudo ./cluster/setup/phase2_redis.sh [OPTIONS]
#
# Options:
#   --config PATH     Path to my_multihead_cluster.yaml
#   --mode MODE       Force mode: cluster, sentinel (auto-detect by default)
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
REDIS_TEMPLATE="${PROJECT_ROOT}/cluster/config/redis_template.conf"
REDIS_CONFIG="/etc/redis/redis.conf"
LOG_FILE="/var/log/cluster_redis_setup.log"

# Default values
MODE="auto"
DRY_RUN=false
REDIS_PORT=6379
SKIP_CLUSTER=false

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
  --mode MODE       Force mode: cluster, sentinel (auto-detect by default)
  --dry-run         Show what would be done without executing
  --help            Show this help message

Examples:
  # Auto mode (3+ nodes → cluster, 2 nodes → sentinel)
  sudo $0 --config ../my_multihead_cluster.yaml

  # Force cluster mode
  sudo $0 --mode cluster

  # Force sentinel mode
  sudo $0 --mode sentinel

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

    # Check if redis template exists
    if [[ ! -f "$REDIS_TEMPLATE" ]]; then
        log ERROR "Redis template not found: $REDIS_TEMPLATE"
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

    # Check if Redis service is enabled for this controller
    REDIS_ENABLED=$(echo "$CURRENT_CONTROLLER" | jq -r '.services.redis // false')
    if [[ "$REDIS_ENABLED" != "true" ]]; then
        log ERROR "Redis service is not enabled for this controller in the config"
        exit 1
    fi

    log INFO "Current controller: $CURRENT_HOSTNAME ($CURRENT_IP)"

    # Get all Redis-enabled controllers
    REDIS_CONTROLLERS=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --service redis 2>/dev/null)
    TOTAL_REDIS_NODES=$(echo "$REDIS_CONTROLLERS" | jq '. | length')

    log INFO "Total Redis-enabled controllers: $TOTAL_REDIS_NODES"

    # Get cluster name
    CLUSTER_NAME=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cluster.name 2>/dev/null || echo "multihead_cluster")

    # Get Redis-specific config
    REDIS_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cache.redis.password 2>/dev/null || echo "changeme")

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

check_redis_installed() {
    log INFO "Checking if Redis is installed..."

    if command -v redis-server &> /dev/null; then
        log SUCCESS "Redis is already installed"
        REDIS_INSTALLED=true

        # Check version
        REDIS_VERSION=$(redis-server --version | grep -oP '(?<=v=)[\d.]+' || echo "unknown")
        log INFO "Redis version: $REDIS_VERSION"
    else
        log WARNING "Redis is not installed"
        REDIS_INSTALLED=false
    fi
}

install_redis() {
    if [[ "$REDIS_INSTALLED" == "true" ]]; then
        log INFO "Skipping Redis installation (already installed)"
        return 0
    fi

    log INFO "Installing Redis..."

    case $OS in
        ubuntu|debian)
            run_command "apt-get update"
            run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server redis-tools"
            ;;
        centos|rhel|rocky|almalinux)
            run_command "yum install -y redis"
            ;;
    esac

    log SUCCESS "Redis installed successfully"
}

discover_active_nodes() {
    log INFO "Discovering active Redis nodes..."

    # Run auto-discovery script
    if [[ ! -f "$DISCOVERY_SCRIPT" ]]; then
        log ERROR "Discovery script not found: $DISCOVERY_SCRIPT"
        exit 1
    fi

    DISCOVERY_OUTPUT=$("$DISCOVERY_SCRIPT" --config "$CONFIG_FILE" 2>/dev/null || echo "{}")

    # Extract active Redis nodes (check for status == "ok")
    ACTIVE_CONTROLLERS=$(echo "$DISCOVERY_OUTPUT" | jq -r '.controllers[] | select(.services.redis.status == "ok") | .ip' 2>/dev/null || echo "")

    # Count active nodes (handle empty result from grep)
    if [[ -z "$ACTIVE_CONTROLLERS" ]]; then
        ACTIVE_COUNT=0
    else
        ACTIVE_COUNT=$(echo "$ACTIVE_CONTROLLERS" | grep -v '^$' | wc -l)
    fi

    log INFO "Active Redis nodes found: $ACTIVE_COUNT"

    if [[ $ACTIVE_COUNT -gt 0 ]]; then
        log INFO "Active nodes:"
        echo "$ACTIVE_CONTROLLERS" | while read -r ip; do
            log INFO "  - $ip"
        done
    fi
}

determine_redis_mode() {
    log INFO "Determining Redis mode..."

    if [[ "$MODE" != "auto" ]]; then
        log INFO "Mode forced to: $MODE"
        return 0
    fi

    # Auto-detect based on total Redis-enabled nodes
    if [[ $TOTAL_REDIS_NODES -ge 3 ]]; then
        MODE="cluster"
        log INFO "3+ Redis nodes detected → Cluster mode"
        log INFO "Cluster mode provides:"
        log INFO "  - Hash slot-based data partitioning (16384 slots)"
        log INFO "  - Automatic sharding across nodes"
        log INFO "  - Built-in high availability"
    elif [[ $TOTAL_REDIS_NODES -eq 2 ]]; then
        MODE="sentinel"
        log INFO "2 Redis nodes detected → Sentinel mode"
        log INFO "Sentinel mode provides:"
        log INFO "  - Master-replica replication"
        log INFO "  - Automatic failover via Sentinel"
        log INFO "  - Simpler setup for small deployments"
    else
        log ERROR "Need at least 2 Redis-enabled nodes"
        log ERROR "Current Redis-enabled nodes: $TOTAL_REDIS_NODES"
        exit 1
    fi
}

calculate_memory_settings() {
    log INFO "Calculating memory settings..."

    # Get total RAM
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))

    # Redis max memory: 25% of RAM (leaving room for OS, MariaDB, etc.)
    MAX_MEMORY_MB=$((TOTAL_RAM_MB * 25 / 100))
    MAX_MEMORY="${MAX_MEMORY_MB}mb"

    # Max clients
    MAX_CLIENTS=10000

    log INFO "Memory settings:"
    log INFO "  - Total RAM: ${TOTAL_RAM_MB}MB"
    log INFO "  - Redis max memory: $MAX_MEMORY"
    log INFO "  - Max clients: $MAX_CLIENTS"
}

generate_redis_config() {
    log INFO "Generating Redis configuration from template..."

    calculate_memory_settings

    # Read template and substitute variables
    local config_content
    config_content=$(cat "$REDIS_TEMPLATE")

    # Common substitutions
    config_content="${config_content//\{\{BIND_ADDRESS\}\}/0.0.0.0}"
    config_content="${config_content//\{\{REDIS_PORT\}\}/$REDIS_PORT}"
    config_content="${config_content//\{\{REDIS_PASSWORD\}\}/$REDIS_PASSWORD}"
    config_content="${config_content//\{\{MAX_CLIENTS\}\}/$MAX_CLIENTS}"
    config_content="${config_content//\{\{MAX_MEMORY\}\}/$MAX_MEMORY}"

    # Mode-specific substitutions
    if [[ "$MODE" == "cluster" ]]; then
        config_content="${config_content//\{\{CLUSTER_ENABLED\}\}/yes}"
    else
        config_content="${config_content//\{\{CLUSTER_ENABLED\}\}/no}"
    fi

    # Backup existing config
    if [[ -f "$REDIS_CONFIG" ]] && [[ "$DRY_RUN" == "false" ]]; then
        cp "$REDIS_CONFIG" "${REDIS_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        log INFO "Backed up existing config to ${REDIS_CONFIG}.backup.*"
    fi

    # Write configuration file
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would write Redis config to: $REDIS_CONFIG"
        log INFO "[DRY-RUN] Config preview (first 30 lines):"
        echo "$config_content" | head -30
    else
        echo "$config_content" > "$REDIS_CONFIG"
        chmod 644 "$REDIS_CONFIG"
        log SUCCESS "Redis configuration written to $REDIS_CONFIG"
    fi
}

stop_redis() {
    log INFO "Stopping Redis service..."

    run_command "systemctl stop redis-server || systemctl stop redis || true"

    log SUCCESS "Redis stopped"
}

start_redis() {
    log INFO "Starting Redis service..."

    run_command "systemctl start redis-server || systemctl start redis"

    # Wait for Redis to start
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 3

        # Check if Redis is running
        if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
            log SUCCESS "Redis started successfully"
        else
            log ERROR "Failed to start Redis"
            exit 1
        fi
    fi
}

deploy_to_other_controllers() {
    log INFO "Deploying Redis to other controllers..."

    # Get SSH user from config
    local ssh_user=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get nodes.controllers[0].ssh_user 2>/dev/null || echo "root")

    # Get first controller IP
    local first_node_ip=$(echo "$REDIS_CONTROLLERS" | jq -r '.[0].ip_address')

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

        # Test SSH connection
        if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$ssh_user@$ip" "echo OK" > /dev/null 2>&1; then
            log WARNING "Cannot connect to $hostname ($ip) via SSH"
            continue
        fi

        # Copy phase2_redis.sh to remote node
        if ! scp -o StrictHostKeyChecking=no "$0" "$ssh_user@$ip:/tmp/phase2_redis.sh" > /dev/null 2>&1; then
            log WARNING "Failed to copy script to $hostname"
            continue
        fi

        # Execute on remote node (without cluster creation)
        log INFO "Installing Redis on $hostname..."
        if ssh -o StrictHostKeyChecking=no "$ssh_user@$ip" \
            "cd '$SCRIPT_DIR' && sudo bash /tmp/phase2_redis.sh --config '$CONFIG_FILE' --skip-cluster" > /dev/null 2>&1; then
            log SUCCESS "$hostname: Redis installed"
        else
            log WARNING "$hostname: Redis installation failed"
        fi

    done < <(echo "$REDIS_CONTROLLERS" | jq -c '.[]')

    if [[ $node_count -gt 0 ]]; then
        log SUCCESS "Deployed to $node_count other controller(s)"
        # Wait for all nodes to be ready
        log INFO "Waiting 10 seconds for all Redis nodes to start..."
        sleep 10
    fi
}

create_cluster() {
    log INFO "Creating Redis Cluster..."

    # Wait for all nodes to be ready
    log INFO "Waiting for all Redis nodes to be ready..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would wait for all nodes to start Redis"
        log INFO "[DRY-RUN] Would create cluster with nodes:"
        echo "$REDIS_CONTROLLERS" | jq -r '.[].ip_address' | while read -r ip; do
            log INFO "[DRY-RUN]   - $ip:$REDIS_PORT"
        done
        return 0
    fi

    # Build node list for cluster creation
    local node_list=""
    while IFS= read -r ip; do
        if [[ -z "$node_list" ]]; then
            node_list="$ip:$REDIS_PORT"
        else
            node_list="$node_list $ip:$REDIS_PORT"
        fi
    done < <(echo "$REDIS_CONTROLLERS" | jq -r '.[].ip_address')

    log INFO "Creating cluster with nodes: $node_list"

    # Create cluster (only run on first node)
    local first_node_ip=$(echo "$REDIS_CONTROLLERS" | jq -r '.[0].ip_address')

    if [[ "$CURRENT_IP" == "$first_node_ip" ]]; then
        log INFO "This is the first node, creating cluster..."

        # Use redis-cli to create cluster
        # --cluster-replicas 0 means no replicas (we'll add them later if needed)
        run_command "redis-cli --cluster create $node_list --cluster-replicas 0 --cluster-yes -a '$REDIS_PASSWORD'"

        log SUCCESS "Redis Cluster created successfully"
    else
        log INFO "This is not the first node, waiting for cluster creation..."
        log INFO "Run this script on $first_node_ip to create the cluster"
    fi
}

setup_sentinel() {
    log INFO "Setting up Redis Sentinel mode..."

    # Get the two Redis nodes
    local node1_ip=$(echo "$REDIS_CONTROLLERS" | jq -r '.[0].ip_address')
    local node2_ip=$(echo "$REDIS_CONTROLLERS" | jq -r '.[1].ip_address')

    log INFO "Node 1 (master): $node1_ip"
    log INFO "Node 2 (replica): $node2_ip"

    # Determine if current node is master or replica
    if [[ "$CURRENT_IP" == "$node1_ip" ]]; then
        log INFO "This node will be the master"
        ROLE="master"
    else
        log INFO "This node will be the replica"
        ROLE="replica"

        # Configure replication
        if [[ "$DRY_RUN" == "false" ]]; then
            log INFO "Configuring replication to master $node1_ip..."
            redis-cli -a "$REDIS_PASSWORD" REPLICAOF "$node1_ip" "$REDIS_PORT"
            redis-cli -a "$REDIS_PASSWORD" CONFIG SET masterauth "$REDIS_PASSWORD"
            log SUCCESS "Replication configured"
        fi
    fi

    # Install and configure Sentinel
    log INFO "Installing Redis Sentinel..."

    case $OS in
        ubuntu|debian)
            run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y redis-sentinel"
            ;;
        centos|rhel|rocky|almalinux)
            # Sentinel included in redis package
            ;;
    esac

    # Configure Sentinel
    local sentinel_config="/etc/redis/sentinel.conf"

    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$sentinel_config" << EOF
# Redis Sentinel configuration
port 26379
dir /var/lib/redis
logfile /var/log/redis/sentinel.log

# Monitor master
sentinel monitor mymaster $node1_ip $REDIS_PORT 1
sentinel auth-pass mymaster $REDIS_PASSWORD
sentinel down-after-milliseconds mymaster 5000
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 10000

# Require password for Sentinel commands
requirepass $REDIS_PASSWORD
EOF

        chmod 644 "$sentinel_config"
        log SUCCESS "Sentinel configuration written"

        # Start Sentinel
        systemctl enable redis-sentinel
        systemctl start redis-sentinel

        log SUCCESS "Sentinel started"
    else
        log INFO "[DRY-RUN] Would create Sentinel config at $sentinel_config"
    fi
}

enable_redis_service() {
    log INFO "Enabling Redis service..."

    run_command "systemctl enable redis-server || systemctl enable redis"

    log SUCCESS "Redis service enabled"
}

show_cluster_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log INFO "Redis status:"

    if [[ "$MODE" == "cluster" ]]; then
        # Show cluster info
        redis-cli -a "$REDIS_PASSWORD" -c CLUSTER INFO 2>/dev/null || true
        echo ""
        redis-cli -a "$REDIS_PASSWORD" -c CLUSTER NODES 2>/dev/null || true
    else
        # Show replication info
        redis-cli -a "$REDIS_PASSWORD" INFO replication 2>/dev/null || true
        echo ""
        log INFO "Sentinel status:"
        redis-cli -p 26379 -a "$REDIS_PASSWORD" SENTINEL masters 2>/dev/null || true
    fi
}

#############################################################################
# Main
#############################################################################

main() {
    log INFO "=== Phase 2: Redis Cluster Setup ==="
    log INFO "Starting at $(date)"

    # Step 0: Check root privileges
    check_root

    # Step 1: Check dependencies
    check_dependencies

    # Step 2: Load configuration
    load_config

    # Step 3: Detect OS
    detect_os

    # Step 4: Check if Redis is installed
    check_redis_installed

    # Step 5: Install Redis if needed
    if [[ "$REDIS_INSTALLED" == "false" ]]; then
        install_redis
    fi

    # Step 6: Discover active Redis nodes
    discover_active_nodes

    # Step 7: Determine Redis mode (cluster vs sentinel)
    determine_redis_mode

    # Step 8: Generate Redis configuration
    generate_redis_config

    # Step 9: Stop Redis before reconfiguration
    stop_redis

    # Step 10: Start Redis with new configuration
    start_redis

    # Step 10.5: Deploy to other controllers (only if not skipping cluster)
    if [[ "$SKIP_CLUSTER" == "false" ]] && [[ "$MODE" == "cluster" ]]; then
        deploy_to_other_controllers
    fi

    # Step 11: Create cluster or setup sentinel
    if [[ "$SKIP_CLUSTER" == "false" ]]; then
        if [[ "$MODE" == "cluster" ]]; then
            create_cluster
        else
            setup_sentinel
        fi
    else
        log INFO "Skipping cluster/sentinel creation (--skip-cluster flag)"
    fi

    # Step 12: Enable service for auto-start
    enable_redis_service

    # Step 13: Show cluster status
    show_cluster_status

    log SUCCESS "=== Redis setup completed ==="
    log INFO "Finished at $(date)"

    if [[ "$MODE" == "cluster" ]]; then
        log INFO ""
        log INFO "Next steps:"
        log INFO "  1. Run this script on all other Redis-enabled controllers"
        log INFO "  2. On the first node, create the cluster:"
        log INFO "     redis-cli --cluster create <ip1>:6379 <ip2>:6379 ... --cluster-yes -a '$REDIS_PASSWORD'"
        log INFO "  3. Monitor cluster status: redis-cli -a '$REDIS_PASSWORD' CLUSTER INFO"
        log INFO "  4. Test with: redis-cli -c -a '$REDIS_PASSWORD' SET test 'Hello Redis Cluster'"
    else
        log INFO ""
        log INFO "Next steps:"
        log INFO "  1. Test replication: redis-cli -a '$REDIS_PASSWORD' INFO replication"
        log INFO "  2. Test Sentinel: redis-cli -p 26379 -a '$REDIS_PASSWORD' SENTINEL masters"
        log INFO "  3. Test failover by stopping master node"
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
        --mode)
            MODE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-cluster)
            SKIP_CLUSTER=true
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
