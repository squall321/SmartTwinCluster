#!/bin/bash

################################################################################
# Cluster Nodes Status Checker
#
# 클러스터의 모든 노드 상태를 확인하고 표시합니다.
#
# Usage:
#   ./check_nodes.sh [--config PATH]
#
# Example:
#   ./check_nodes.sh
#   ./check_nodes.sh --config ../my_multihead_cluster.yaml
################################################################################

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default config path
CONFIG_PATH="${1:-$PROJECT_ROOT/my_multihead_cluster.yaml}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--config PATH]"
            echo ""
            echo "Check and display cluster nodes status"
            echo ""
            echo "Options:"
            echo "  --config PATH    Path to my_multihead_cluster.yaml"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

echo ""
echo "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║                        Cluster Nodes Status                                    ║${NC}"
echo "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${BLUE}Config: ${NC}$CONFIG_PATH"
echo ""
printf "%-20s %-18s %-12s %-25s %-30s\n" "HOSTNAME" "IP ADDRESS" "ROLE" "STATUS" "SERVICES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get all nodes from config (controllers + compute nodes)
all_nodes_json=$(python3 -c "
import yaml, json, sys
try:
    with open('$CONFIG_PATH') as f:
        config = yaml.safe_load(f)

    # Get controllers
    controllers = config.get('nodes', {}).get('controllers', [])
    for c in controllers:
        c['node_role'] = 'controller'

    # Get compute nodes
    compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
    for c in compute_nodes:
        c['node_role'] = 'compute'

    # Merge all nodes
    all_nodes = controllers + compute_nodes
    print(json.dumps(all_nodes))
except Exception as e:
    print('[]', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "[]")

if [[ -z "$all_nodes_json" ]] || [[ "$all_nodes_json" == "[]" ]]; then
    echo "${RED}[ERROR]${NC} Could not load node list from configuration"
    exit 1
fi

# Temporarily disable errexit to avoid breaking on ping/ssh failures
set +e

# Process each node and save to temp file for counting
temp_output=$(mktemp)
temp_stats=$(mktemp)
alive_count=0

echo "$all_nodes_json" | jq -c '.[]' 2>/dev/null | while IFS= read -r node; do
    if [[ -z "$node" ]]; then
        continue
    fi

    hostname=$(echo "$node" | jq -r '.hostname' 2>/dev/null || echo "unknown")
    ip=$(echo "$node" | jq -r '.ip_address' 2>/dev/null || echo "0.0.0.0")
    role=$(echo "$node" | jq -r '.node_role' 2>/dev/null || echo "unknown")

    # Get services - different for controllers vs compute nodes
    if [[ "$role" == "controller" ]]; then
        services=$(echo "$node" | jq -r '.services | to_entries | map(select(.value == true) | .key) | join(",")' 2>/dev/null || echo "none")
    else
        services="slurmd"
    fi

    # Check if node is reachable
    status="❌ DOWN"
    status_color="${RED}"
    is_alive=0

    # Try to ping the node (1 second timeout)
    if ping -c 1 -W 1 "$ip" &>/dev/null; then
        # Try SSH connection (3 second timeout)
        if timeout 3 ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes "$ip" "echo 2>&1" &>/dev/null 2>&1; then
            status="✅ UP (SSH OK)"
            status_color="${GREEN}"
            is_alive=1
        else
            status="⚠️  PING OK, SSH FAILED"
            status_color="${YELLOW}"
        fi
    fi

    echo "$is_alive" >> "$temp_stats"
    printf "${status_color}%-20s %-18s %-12s %-25s${NC} %-30s\n" "$hostname" "$ip" "$role" "$status" "$services" >> "$temp_output"
done

# Display all nodes
cat "$temp_output"

# Count alive nodes
alive_count=$(grep -c "1" "$temp_stats" 2>/dev/null || echo 0)

# Clean up temp files
rm -f "$temp_output" "$temp_stats"

# Count nodes properly
node_count=$(echo "$all_nodes_json" | jq '. | length' 2>/dev/null || echo 0)
controller_count=$(echo "$all_nodes_json" | jq '[.[] | select(.node_role == "controller")] | length' 2>/dev/null || echo 0)
compute_count=$(echo "$all_nodes_json" | jq '[.[] | select(.node_role == "compute")] | length' 2>/dev/null || echo 0)

# Re-enable errexit
set -e

echo ""
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ $node_count -gt 0 ]]; then
    echo "${BLUE}Node Summary:${NC}"
    echo "  • Controllers: $controller_count"
    echo "  • Compute Nodes: $compute_count"
    echo "  • Total: $node_count"
    echo ""
    if [[ $alive_count -eq $node_count ]]; then
        echo "${GREEN}✅ Status: All $node_count nodes are fully accessible${NC}"
    elif [[ $alive_count -gt 0 ]]; then
        echo "${YELLOW}⚠️  Status: $alive_count/$node_count nodes are fully accessible${NC}"
    else
        echo "${RED}❌ Status: No nodes are fully accessible (0/$node_count)${NC}"
    fi
else
    echo "${YELLOW}[INFO] No nodes found to check${NC}"
fi
echo ""

# Show additional info
echo "${BLUE}Additional Commands:${NC}"
echo "  • Full status:     ./cluster/status_multihead.sh --all"
echo "  • Slurm status:    sinfo"
echo "  • Service status:  systemctl status glusterd mariadb redis slurmctld keepalived nginx"
echo ""
