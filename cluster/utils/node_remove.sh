#!/bin/bash
###############################################################################
# Node Remove Utility
#
# Purpose: Remove a node from specific service cluster
# Services: glusterfs, mariadb, redis, slurm
#
# Usage:
#   ./node_remove.sh --service SERVICE --ip IP_ADDRESS [--config CONFIG_PATH]
###############################################################################

set -euo pipefail

# Default values
CONFIG_PATH="../my_multihead_cluster.yaml"
SERVICE=""
NODE_IP=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/cluster_node_remove.log"

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
  --ip IP_ADDRESS    IP address of the node to remove

Options:
  --config PATH      Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)
  --help             Show this help message

Examples:
  # Remove node from GlusterFS cluster
  $0 --service glusterfs --ip 192.168.1.105

  # Remove node from MariaDB Galera cluster
  $0 --service mariadb --ip 192.168.1.105

  # Remove node from Redis cluster
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

log "INFO" "=== Removing Node from $SERVICE Cluster ==="
log "INFO" "Node IP: $NODE_IP"
log "WARNING" "This operation cannot be undone!"

# Confirmation prompt
read -p "Are you sure you want to remove this node? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    log "INFO" "Operation cancelled"
    exit 0
fi

echo ""

###############################################################################
# Service-specific implementations
###############################################################################

remove_glusterfs_node() {
    local ip=$1

    log "INFO" "Removing node from GlusterFS cluster..."

    # Check if glusterd is running locally
    if ! systemctl is-active --quiet glusterd; then
        log "ERROR" "glusterd is not running on this node"
        exit 1
    fi

    # Check if peer exists
    if ! sudo gluster peer status | grep -q "$ip"; then
        log "WARNING" "Peer $ip not found in cluster"
        exit 0
    fi

    # Get hostname from peer status
    PEER_HOSTNAME=$(sudo gluster peer status | grep -B1 "$ip" | grep "Hostname" | awk '{print $2}')

    log "WARNING" "Before removing peer, ensure all bricks from this node are removed from volumes!"
    log "INFO" "To remove bricks:"
    log "INFO" "  gluster volume remove-brick VOLUME_NAME $ip:/brick/path start"
    log "INFO" "  gluster volume remove-brick VOLUME_NAME $ip:/brick/path commit"
    echo ""

    read -p "Have you removed all bricks from this node? (yes/no): " CONFIRM_BRICK
    if [[ "$CONFIRM_BRICK" != "yes" ]]; then
        log "INFO" "Please remove bricks first"
        exit 1
    fi

    # Detach peer
    log "INFO" "Detaching peer: $ip ($PEER_HOSTNAME)"
    if sudo gluster peer detach "$ip"; then
        log "SUCCESS" "Peer $ip removed successfully"

        # Display remaining peers
        echo ""
        log "INFO" "Remaining peers:"
        sudo gluster peer status
    else
        log "ERROR" "Failed to remove peer $ip"
        exit 1
    fi
}

remove_mariadb_node() {
    local ip=$1

    log "INFO" "Removing node from MariaDB Galera cluster..."

    log "WARNING" "MariaDB Galera cluster removal requires:"
    log "INFO" "  1. On the node to remove ($ip):"
    log "INFO" "     - Stop MariaDB: systemctl stop mariadb"
    log "INFO" ""
    log "INFO" "  2. On remaining nodes (optional, for cleanup):"
    log "INFO" "     - UPDATE wsrep_cluster_address (remove $ip):"
    log "INFO" "       SET GLOBAL wsrep_cluster_address='gcomm://node1,node2,...';"
    log "INFO" ""
    log "INFO" "  3. Verify cluster size:"
    log "INFO" "     SHOW STATUS LIKE 'wsrep_cluster_size';"
    log "INFO" "     (should be N-1)"

    # If MariaDB is running locally, show current cluster size
    if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb; then
        log "INFO" ""
        log "INFO" "Current cluster status:"
        sudo mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null || true
        sudo mysql -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null || true

        log "WARNING" ""
        log "WARNING" "Minimum cluster size: 2 nodes (for quorum)"
        log "WARNING" "Removing this node will leave $(sudo mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | tail -1 | awk '{print $2-1}') nodes"
    fi
}

remove_redis_node() {
    local ip=$1

    log "INFO" "Removing node from Redis cluster..."

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

    # Get node ID of the node to remove
    NODE_ID=$(redis-cli cluster nodes | grep "$ip:6379" | awk '{print $1}')

    if [[ -z "$NODE_ID" ]]; then
        log "ERROR" "Node $ip not found in cluster"
        exit 1
    fi

    log "INFO" "Node ID: $NODE_ID"

    # Check if node has hash slots
    SLOT_COUNT=$(redis-cli cluster nodes | grep "$ip:6379" | grep -oP '\d+-\d+' | wc -l)

    if [[ $SLOT_COUNT -gt 0 ]]; then
        log "WARNING" "Node has $SLOT_COUNT hash slot ranges"
        log "INFO" "Resharding hash slots to other nodes..."

        # Get any other master node
        OTHER_NODE=$(redis-cli cluster nodes | grep master | grep -v "$ip" | head -1 | awk '{print $2}' | cut -d@ -f1)

        if [[ -z "$OTHER_NODE" ]]; then
            log "ERROR" "No other master nodes found"
            exit 1
        fi

        log "INFO" "Moving slots to $OTHER_NODE"

        # Reshard all slots from this node
        redis-cli --cluster reshard "$ip:6379" \
            --cluster-from "$NODE_ID" \
            --cluster-to "$(redis-cli cluster nodes | grep "$OTHER_NODE" | awk '{print $1}')" \
            --cluster-slots 16384 \
            --cluster-yes

        log "SUCCESS" "Slots resharded"
    fi

    # Remove node from cluster
    log "INFO" "Removing node from cluster..."
    LOCAL_IP=$(hostname -I | awk '{print $1}')

    if redis-cli --cluster del-node "$LOCAL_IP:6379" "$NODE_ID"; then
        log "SUCCESS" "Node $ip removed from cluster"

        # Display cluster status
        echo ""
        log "INFO" "Current cluster status:"
        redis-cli cluster info
    else
        log "ERROR" "Failed to remove node from cluster"
        exit 1
    fi
}

remove_slurm_node() {
    local ip=$1

    log "INFO" "Removing node from Slurm Multi-Master configuration..."

    log "WARNING" "Slurm Multi-Master removal requires:"
    log "INFO" "  1. On all nodes:"
    log "INFO" "     - Edit /etc/slurm/slurm.conf"
    log "INFO" "     - Remove SlurmctldHost line for $ip"
    log "INFO" "     - Run: scontrol reconfigure"
    log "INFO" ""
    log "INFO" "  2. On the node to remove ($ip):"
    log "INFO" "     - Stop slurmctld: systemctl stop slurmctld"
    log "INFO" ""
    log "INFO" "  3. Verify configuration:"
    log "INFO" "     scontrol show config | grep SlurmctldHost"

    # If slurmctld is running, show current config
    if command -v scontrol &>/dev/null; then
        log "INFO" ""
        log "INFO" "Current Slurm controllers:"
        scontrol show config | grep SlurmctldHost || true

        CONTROLLER_COUNT=$(scontrol show config | grep -c SlurmctldHost || echo 0)
        log "WARNING" ""
        log "WARNING" "Current controller count: $CONTROLLER_COUNT"
        log "WARNING" "Minimum controllers: 1"
        log "WARNING" "After removal: $((CONTROLLER_COUNT - 1)) controllers"
    fi
}

###############################################################################
# Main execution
###############################################################################

case $SERVICE in
    glusterfs)
        remove_glusterfs_node "$NODE_IP"
        ;;
    mariadb)
        remove_mariadb_node "$NODE_IP"
        ;;
    redis)
        remove_redis_node "$NODE_IP"
        ;;
    slurm)
        remove_slurm_node "$NODE_IP"
        ;;
esac

echo ""
log "SUCCESS" "=== Node Removal Process Complete ==="

exit 0
