#!/bin/bash
###############################################################################
# Node Add Utility
#
# Purpose: Add a node to specific service cluster
# Services: glusterfs, mariadb, redis, slurm
#
# Usage:
#   ./node_add.sh --service SERVICE --ip IP_ADDRESS [--config CONFIG_PATH]
###############################################################################

set -euo pipefail

# Default values
CONFIG_PATH="../my_multihead_cluster.yaml"
SERVICE=""
NODE_IP=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/cluster_node_add.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | sudo tee -a "$LOG_FILE" >/dev/null

    case $level in
        ERROR) echo -e "${RED}✗ $message${NC}" >&2 ;;
        SUCCESS) echo -e "${GREEN}✓ $message${NC}" ;;
        INFO) echo -e "${CYAN}ℹ $message${NC}" ;;
        WARNING) echo -e "${YELLOW}⚠ $message${NC}" ;;
    esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --ip)
            NODE_IP="$2"
            shift 2
            ;;
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --help)
            cat << EOF
Usage: $0 --service SERVICE --ip IP_ADDRESS [OPTIONS]

Required:
  --service SERVICE  Service name: glusterfs, mariadb, redis, slurm
  --ip IP_ADDRESS    IP address of the node to add

Options:
  --config PATH      Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)
  --help             Show this help message

Examples:
  # Add node to GlusterFS cluster
  $0 --service glusterfs --ip 192.168.1.105

  # Add node to MariaDB Galera cluster
  $0 --service mariadb --ip 192.168.1.105

  # Add node to Redis cluster
  $0 --service redis --ip 192.168.1.105
EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "$SERVICE" ]]; then
    log "ERROR" "--service is required"
    exit 1
fi

if [[ -z "$NODE_IP" ]]; then
    log "ERROR" "--ip is required"
    exit 1
fi

if [[ ! "$SERVICE" =~ ^(glusterfs|mariadb|redis|slurm)$ ]]; then
    log "ERROR" "Invalid service: $SERVICE (must be glusterfs, mariadb, redis, or slurm)"
    exit 1
fi

log "INFO" "=== Adding Node to $SERVICE Cluster ==="
log "INFO" "Node IP: $NODE_IP"
echo ""

###############################################################################
# Service-specific implementations
###############################################################################

add_glusterfs_node() {
    local ip=$1

    log "INFO" "Adding node to GlusterFS cluster..."

    # Check if glusterd is running locally
    if ! systemctl is-active --quiet glusterd; then
        log "ERROR" "glusterd is not running on this node"
        exit 1
    fi

    # Probe peer
    log "INFO" "Probing peer: $ip"
    if sudo gluster peer probe "$ip"; then
        log "SUCCESS" "Peer $ip probed successfully"
    else
        log "ERROR" "Failed to probe peer $ip"
        exit 1
    fi

    # Wait for peer to be connected
    sleep 3

    # Check peer status
    if sudo gluster peer status | grep -q "$ip"; then
        log "SUCCESS" "Peer $ip is now connected"

        # Display peer status
        echo ""
        log "INFO" "Current peer status:"
        sudo gluster peer status
    else
        log "ERROR" "Peer $ip not in peer list"
        exit 1
    fi

    log "INFO" "Note: To add brick from this node, run on the new node:"
    log "INFO" "  gluster volume add-brick VOLUME_NAME replica N $ip:/brick/path force"
}

add_mariadb_node() {
    local ip=$1

    log "INFO" "Adding node to MariaDB Galera cluster..."

    log "WARNING" "MariaDB Galera cluster addition requires:"
    log "INFO" "  1. On the new node ($ip):"
    log "INFO" "     - Install MariaDB + Galera"
    log "INFO" "     - Configure galera.cnf with wsrep_cluster_address including all nodes"
    log "INFO" "     - Start MariaDB (will auto-join via SST)"
    log "INFO" ""
    log "INFO" "  2. On existing nodes (optional, for dynamic update):"
    log "INFO" "     - UPDATE wsrep_cluster_address:"
    log "INFO" "       SET GLOBAL wsrep_cluster_address='gcomm://node1,node2,...,new_node';"
    log "INFO" ""
    log "INFO" "  3. Verify cluster size:"
    log "INFO" "     SHOW STATUS LIKE 'wsrep_cluster_size';"

    # If MariaDB is running locally, show current cluster size
    if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb; then
        log "INFO" ""
        log "INFO" "Current cluster status:"
        sudo mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null || true
        sudo mysql -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null || true
    fi
}

add_redis_node() {
    local ip=$1

    log "INFO" "Adding node to Redis cluster..."

    # Check if redis-cli is available
    if ! command -v redis-cli &>/dev/null; then
        log "ERROR" "redis-cli not installed"
        exit 1
    fi

    # Check if local Redis is part of a cluster
    if ! redis-cli cluster info &>/dev/null; then
        log "ERROR" "Local Redis is not in cluster mode"
        exit 1
    fi

    # Get current node IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')

    log "INFO" "Adding node $ip to cluster..."

    # Add node to cluster
    if redis-cli --cluster add-node "$ip:6379" "$LOCAL_IP:6379"; then
        log "SUCCESS" "Node $ip added to cluster"

        # Rebalance cluster
        log "INFO" "Rebalancing cluster..."
        if redis-cli --cluster rebalance "$LOCAL_IP:6379" --cluster-use-empty-masters; then
            log "SUCCESS" "Cluster rebalanced"
        else
            log "WARNING" "Failed to rebalance cluster"
        fi

        # Display cluster status
        echo ""
        log "INFO" "Current cluster status:"
        redis-cli cluster info
    else
        log "ERROR" "Failed to add node to cluster"
        exit 1
    fi
}

add_slurm_node() {
    local ip=$1

    log "INFO" "Adding node to Slurm Multi-Master configuration..."

    log "WARNING" "Slurm Multi-Master addition requires:"
    log "INFO" "  1. On the new node ($ip):"
    log "INFO" "     - Install Slurm"
    log "INFO" "     - Copy /etc/slurm/slurm.conf from existing node"
    log "INFO" "     - Add new SlurmctldHost line to slurm.conf"
    log "INFO" "     - Restart slurmctld"
    log "INFO" ""
    log "INFO" "  2. On all existing nodes:"
    log "INFO" "     - Update slurm.conf with new SlurmctldHost line"
    log "INFO" "     - Run: scontrol reconfigure"
    log "INFO" ""
    log "INFO" "  3. Verify configuration:"
    log "INFO" "     scontrol show config | grep SlurmctldHost"

    # If slurmctld is running, show current config
    if command -v scontrol &>/dev/null; then
        log "INFO" ""
        log "INFO" "Current Slurm controllers:"
        scontrol show config | grep SlurmctldHost || true
    fi
}

###############################################################################
# Main execution
###############################################################################

case $SERVICE in
    glusterfs)
        add_glusterfs_node "$NODE_IP"
        ;;
    mariadb)
        add_mariadb_node "$NODE_IP"
        ;;
    redis)
        add_redis_node "$NODE_IP"
        ;;
    slurm)
        add_slurm_node "$NODE_IP"
        ;;
esac

echo ""
log "SUCCESS" "=== Node Addition Process Complete ==="

exit 0
