#!/bin/bash
###############################################################################
# Multi-Head Cluster Auto-Discovery Script
#
# Purpose: Automatically discover active controllers and their service status
# Output: JSON format with detailed controller information
#
# Usage:
#   ./auto_discovery.sh [--config CONFIG_PATH] [--timeout SECONDS]
###############################################################################

set -euo pipefail

# Default values
CONFIG_PATH="../my_multihead_cluster.yaml"
SSH_TIMEOUT=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER_PY="${SCRIPT_DIR}/../config/parser.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --timeout)
            SSH_TIMEOUT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --config PATH     Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)"
            echo "  --timeout SECONDS SSH timeout in seconds (default: 5)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if parser.py exists
if [[ ! -f "$PARSER_PY" ]]; then
    echo -e "${RED}Error: parser.py not found at $PARSER_PY${NC}" >&2
    exit 1
fi

# Check if config file exists
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo -e "${RED}Error: Config file not found: $CONFIG_PATH${NC}" >&2
    exit 1
fi

###############################################################################
# Helper Functions
###############################################################################

# Check if SSH is accessible
check_ssh() {
    local ip=$1
    local user=$2
    local port=${3:-22}

    timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                              -o StrictHostKeyChecking=no \
                              -o BatchMode=yes \
                              -p $port \
                              "${user}@${ip}" \
                              "echo ok" 2>/dev/null
}

# Check GlusterFS status
check_glusterfs() {
    local ip=$1
    local user=$2
    local port=${3:-22}

    local result=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                             -o StrictHostKeyChecking=no \
                                             -o BatchMode=yes \
                                             -p $port \
                                             "${user}@${ip}" \
                                             "gluster peer status 2>/dev/null | grep -c 'Peer in Cluster' || echo 0" 2>/dev/null)

    if [[ -n "$result" && "$result" =~ ^[0-9]+$ ]]; then
        echo "{\"status\": \"ok\", \"peers\": $result}"
    else
        echo "{\"status\": \"error\", \"message\": \"glusterd not running or not installed\"}"
    fi
}

# Check MariaDB Galera status
check_mariadb() {
    local ip=$1
    local user=$2
    local port=${3:-22}

    local result=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                             -o StrictHostKeyChecking=no \
                                             -o BatchMode=yes \
                                             -p $port \
                                             "${user}@${ip}" \
                                             "mysql -e \"SHOW STATUS LIKE 'wsrep_cluster_size'\" 2>/dev/null | tail -1 | awk '{print \$2}' || echo 0" 2>/dev/null)

    if [[ -n "$result" && "$result" =~ ^[0-9]+$ && "$result" -gt 0 ]]; then
        local state=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                                -o StrictHostKeyChecking=no \
                                                -o BatchMode=yes \
                                                -p $port \
                                                "${user}@${ip}" \
                                                "mysql -e \"SHOW STATUS LIKE 'wsrep_local_state_comment'\" 2>/dev/null | tail -1 | awk '{print \$2}'" 2>/dev/null)

        echo "{\"status\": \"ok\", \"cluster_size\": $result, \"state\": \"$state\"}"
    else
        echo "{\"status\": \"error\", \"message\": \"MariaDB not running or Galera not configured\"}"
    fi
}

# Check Redis Cluster status
check_redis() {
    local ip=$1
    local user=$2
    local port=${3:-22}

    local result=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                             -o StrictHostKeyChecking=no \
                                             -o BatchMode=yes \
                                             -p $port \
                                             "${user}@${ip}" \
                                             "redis-cli cluster info 2>/dev/null | grep cluster_state | cut -d: -f2 | tr -d '\r\n' || echo 'fail'" 2>/dev/null)

    if [[ "$result" == "ok" ]]; then
        local nodes=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                                -o StrictHostKeyChecking=no \
                                                -o BatchMode=yes \
                                                -p $port \
                                                "${user}@${ip}" \
                                                "redis-cli cluster info 2>/dev/null | grep cluster_known_nodes | cut -d: -f2 | tr -d '\r\n' || echo 0" 2>/dev/null)

        echo "{\"status\": \"ok\", \"cluster_state\": \"$result\", \"nodes\": $nodes}"
    else
        echo "{\"status\": \"error\", \"message\": \"Redis not running or cluster not configured\"}"
    fi
}

# Check Slurm status
check_slurm() {
    local ip=$1
    local user=$2
    local port=${3:-22}

    local result=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                             -o StrictHostKeyChecking=no \
                                             -o BatchMode=yes \
                                             -p $port \
                                             "${user}@${ip}" \
                                             "scontrol ping 2>/dev/null | grep -q 'is UP' && echo 'primary' || scontrol ping 2>/dev/null | grep -q 'Backup controller' && echo 'backup' || echo 'down'" 2>/dev/null)

    if [[ "$result" == "primary" || "$result" == "backup" ]]; then
        echo "{\"status\": \"ok\", \"role\": \"$result\"}"
    else
        echo "{\"status\": \"error\", \"message\": \"slurmctld not running\"}"
    fi
}

# Check Web services
check_web() {
    local ip=$1
    local port=4430  # Auth backend port

    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $SSH_TIMEOUT "http://${ip}:${port}/health" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        echo "{\"status\": \"ok\", \"http_code\": $http_code}"
    else
        echo "{\"status\": \"error\", \"http_code\": $http_code}"
    fi
}

# Check Keepalived (VIP ownership)
check_keepalived() {
    local ip=$1
    local user=$2
    local port=${3:-22}
    local vip=$4

    local has_vip=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                              -o StrictHostKeyChecking=no \
                                              -o BatchMode=yes \
                                              -p $port \
                                              "${user}@${ip}" \
                                              "ip addr show | grep -q '$vip' && echo 'true' || echo 'false'" 2>/dev/null)

    local state="unknown"
    if [[ "$has_vip" == "true" ]]; then
        state="MASTER"
    else
        local keepalived_state=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                                          -o StrictHostKeyChecking=no \
                                                          -o BatchMode=yes \
                                                          -p $port \
                                                          "${user}@${ip}" \
                                                          "systemctl is-active keepalived 2>/dev/null || echo 'inactive'" 2>/dev/null)

        if [[ "$keepalived_state" == "active" ]]; then
            state="BACKUP"
        else
            state="inactive"
        fi
    fi

    echo "{\"status\": \"ok\", \"state\": \"$state\", \"vip\": $has_vip}"
}

# Get system load
get_system_load() {
    local ip=$1
    local user=$2
    local port=${3:-22}

    local load=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                          -o StrictHostKeyChecking=no \
                                          -o BatchMode=yes \
                                          -p $port \
                                          "${user}@${ip}" \
                                          "uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | tr -d ','" 2>/dev/null || echo "0.00")

    echo "$load"
}

# Get uptime
get_uptime() {
    local ip=$1
    local user=$2
    local port=${3:-22}

    local uptime_str=$(timeout $SSH_TIMEOUT ssh -o ConnectTimeout=$SSH_TIMEOUT \
                                                 -o StrictHostKeyChecking=no \
                                                 -o BatchMode=yes \
                                                 -p $port \
                                                 "${user}@${ip}" \
                                                 "uptime -p 2>/dev/null || uptime | awk '{print \$3\" \"\$4}'" 2>/dev/null || echo "unknown")

    echo "$uptime_str"
}

###############################################################################
# Main Discovery Logic
###############################################################################

# Get VIP from config
VIP=$(python3 "$PARSER_PY" --config "$CONFIG_PATH" --get-vip | jq -r '.address')

# Get controllers from config
CONTROLLERS_JSON=$(python3 "$PARSER_PY" --config "$CONFIG_PATH" --list-controllers)

# Parse controllers
TOTAL_CONTROLLERS=$(echo "$CONTROLLERS_JSON" | jq '. | length')

# Initialize counters
ACTIVE_COUNT=0
INACTIVE_COUNT=0

# Initialize result JSON
RESULT_JSON='{
  "timestamp": "'$(date -Iseconds)'",
  "config_path": "'$CONFIG_PATH'",
  "total_controllers": '$TOTAL_CONTROLLERS',
  "active_controllers": 0,
  "inactive_controllers": 0,
  "vip": "'$VIP'",
  "vip_owner": null,
  "cluster_state": "unknown",
  "controllers": []
}'

# Iterate through each controller
for i in $(seq 0 $(($TOTAL_CONTROLLERS - 1))); do
    CTRL=$(echo "$CONTROLLERS_JSON" | jq ".[$i]")

    HOSTNAME=$(echo "$CTRL" | jq -r '.hostname')
    IP=$(echo "$CTRL" | jq -r '.ip_address')
    SSH_USER=$(echo "$CTRL" | jq -r '.ssh_user')
    SSH_PORT=$(echo "$CTRL" | jq -r '.ssh_port // 22')
    PRIORITY=$(echo "$CTRL" | jq -r '.priority')
    SERVICES=$(echo "$CTRL" | jq '.services')

    echo -e "${YELLOW}Checking $HOSTNAME ($IP)...${NC}" >&2

    # Check SSH connectivity
    if check_ssh "$IP" "$SSH_USER" "$SSH_PORT" >/dev/null 2>&1; then
        STATUS="active"
        ACTIVE_COUNT=$((ACTIVE_COUNT + 1))

        # Get system info
        LOAD=$(get_system_load "$IP" "$SSH_USER" "$SSH_PORT")
        UPTIME=$(get_uptime "$IP" "$SSH_USER" "$SSH_PORT")

        # Initialize services status
        SERVICES_STATUS='{}'

        # Check each service if enabled
        if [[ $(echo "$SERVICES" | jq -r '.glusterfs // false') == "true" ]]; then
            GLUSTERFS_STATUS=$(check_glusterfs "$IP" "$SSH_USER" "$SSH_PORT")
            SERVICES_STATUS=$(echo "$SERVICES_STATUS" | jq ". + {\"glusterfs\": $GLUSTERFS_STATUS}")
        fi

        if [[ $(echo "$SERVICES" | jq -r '.mariadb // false') == "true" ]]; then
            MARIADB_STATUS=$(check_mariadb "$IP" "$SSH_USER" "$SSH_PORT")
            SERVICES_STATUS=$(echo "$SERVICES_STATUS" | jq ". + {\"mariadb\": $MARIADB_STATUS}")
        fi

        if [[ $(echo "$SERVICES" | jq -r '.redis // false') == "true" ]]; then
            REDIS_STATUS=$(check_redis "$IP" "$SSH_USER" "$SSH_PORT")
            SERVICES_STATUS=$(echo "$SERVICES_STATUS" | jq ". + {\"redis\": $REDIS_STATUS}")
        fi

        if [[ $(echo "$SERVICES" | jq -r '.slurm // false') == "true" ]]; then
            SLURM_STATUS=$(check_slurm "$IP" "$SSH_USER" "$SSH_PORT")
            SERVICES_STATUS=$(echo "$SERVICES_STATUS" | jq ". + {\"slurm\": $SLURM_STATUS}")
        fi

        if [[ $(echo "$SERVICES" | jq -r '.web // false') == "true" ]]; then
            WEB_STATUS=$(check_web "$IP")
            SERVICES_STATUS=$(echo "$SERVICES_STATUS" | jq ". + {\"web\": $WEB_STATUS}")
        fi

        if [[ $(echo "$SERVICES" | jq -r '.keepalived // false') == "true" ]]; then
            KEEPALIVED_STATUS=$(check_keepalived "$IP" "$SSH_USER" "$SSH_PORT" "$VIP")
            SERVICES_STATUS=$(echo "$SERVICES_STATUS" | jq ". + {\"keepalived\": $KEEPALIVED_STATUS}")

            # Check if this controller owns VIP
            if [[ $(echo "$KEEPALIVED_STATUS" | jq -r '.vip') == "true" ]]; then
                RESULT_JSON=$(echo "$RESULT_JSON" | jq ".vip_owner = \"$HOSTNAME\"")
            fi
        fi

        # Build controller info
        CTRL_INFO=$(jq -n \
            --arg hostname "$HOSTNAME" \
            --arg ip "$IP" \
            --arg status "$STATUS" \
            --argjson priority "$PRIORITY" \
            --arg load "$LOAD" \
            --arg uptime "$UPTIME" \
            --argjson services "$SERVICES_STATUS" \
            '{
                hostname: $hostname,
                ip: $ip,
                status: $status,
                priority: $priority,
                load: $load,
                uptime: $uptime,
                services: $services
            }'
        )

        echo -e "${GREEN}  ✓ $HOSTNAME is active${NC}" >&2

    else
        STATUS="inactive"
        INACTIVE_COUNT=$((INACTIVE_COUNT + 1))

        # Build controller info (inactive)
        CTRL_INFO=$(jq -n \
            --arg hostname "$HOSTNAME" \
            --arg ip "$IP" \
            --arg status "$STATUS" \
            --arg error "Connection timeout or SSH error" \
            '{
                hostname: $hostname,
                ip: $ip,
                status: $status,
                error: $error
            }'
        )

        echo -e "${RED}  ✗ $HOSTNAME is inactive${NC}" >&2
    fi

    # Add to result
    RESULT_JSON=$(echo "$RESULT_JSON" | jq ".controllers += [$CTRL_INFO]")
done

# Update counters
RESULT_JSON=$(echo "$RESULT_JSON" | jq ".active_controllers = $ACTIVE_COUNT")
RESULT_JSON=$(echo "$RESULT_JSON" | jq ".inactive_controllers = $INACTIVE_COUNT")

# Determine cluster state
if [[ $ACTIVE_COUNT -eq $TOTAL_CONTROLLERS ]]; then
    CLUSTER_STATE="healthy"
elif [[ $ACTIVE_COUNT -gt 0 ]]; then
    CLUSTER_STATE="degraded"
else
    CLUSTER_STATE="down"
fi

RESULT_JSON=$(echo "$RESULT_JSON" | jq ".cluster_state = \"$CLUSTER_STATE\"")

# Output result
echo "$RESULT_JSON"

exit 0
