#!/bin/bash

################################################################################
# Multi-Head Cluster Status Script
#
# This script displays comprehensive status information for all services
# in the multi-head HPC cluster.
#
# Status Information:
#   - Service status (running/stopped)
#   - Cluster health (GlusterFS, Galera, Redis, Slurm)
#   - Resource usage (CPU, memory, disk)
#   - Network status (VIP, connectivity)
#   - Recent logs and errors
#
# Usage:
#   ./status_multihead.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)
#   --format FORMAT     Output format: full, compact, json (default: full)
#   --service NAME      Show specific service only
#   --all-nodes         Show status of all nodes (not just local)
#   --watch             Continuous monitoring (refresh every 5s)
#   --no-color          Disable colored output
#   --help              Show this help message
#
# Examples:
#   ./status_multihead.sh
#   ./status_multihead.sh --format compact
#   ./status_multihead.sh --service slurm
#   ./status_multihead.sh --all-nodes --format json
#   ./status_multihead.sh --watch
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
CONFIG_PATH="$PROJECT_ROOT/my_multihead_cluster.yaml"
OUTPUT_FORMAT="full"
SPECIFIC_SERVICE=""
ALL_NODES=false
WATCH_MODE=false
USE_COLOR=true

# Function to print colored output
log_info() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    else
        echo "[INFO] $1"
    fi
}

log_success() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${GREEN}[OK]${NC} $1"
    else
        echo "[OK] $1"
    fi
}

log_warning() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    else
        echo "[WARN] $1"
    fi
}

log_error() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${RED}[ERROR]${NC} $1"
    else
        echo "[ERROR] $1"
    fi
}

# Function to show help
show_help() {
    grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//'
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_PATH="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --service)
                SPECIFIC_SERVICE="$2"
                shift 2
                ;;
            --all-nodes)
                ALL_NODES=true
                shift
                ;;
            --watch)
                WATCH_MODE=true
                shift
                ;;
            --no-color)
                USE_COLOR=false
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to check service status
check_service_status() {
    local service_name=$1

    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Function to get service status with color
get_service_status_colored() {
    local service_name=$1
    local status
    status=$(check_service_status "$service_name")

    if [[ "$USE_COLOR" == true ]]; then
        if [[ "$status" == "running" ]]; then
            echo -e "${GREEN}●${NC} running"
        else
            echo -e "${RED}○${NC} stopped"
        fi
    else
        if [[ "$status" == "running" ]]; then
            echo "● running"
        else
            echo "○ stopped"
        fi
    fi
}

# Function to get system info
get_system_info() {
    local hostname=$(hostname)
    local ip=$(hostname -I | awk '{print $1}')
    local uptime=$(uptime -p)
    local kernel=$(uname -r)
    local os=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)

    echo "Hostname: $hostname"
    echo "IP: $ip"
    echo "OS: $os"
    echo "Kernel: $kernel"
    echo "Uptime: $uptime"
}

# Function to get resource usage
get_resource_usage() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    local mem_percent=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2*100}')
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)

    echo "CPU Usage: ${cpu_usage}%"
    echo "Memory: ${mem_used} / ${mem_total} (${mem_percent}%)"
    echo "Disk Usage: ${disk_usage}"
    echo "Load Average: ${load_avg}"
}

# Function to check GlusterFS status
check_glusterfs_status() {
    if [[ "$(check_service_status glusterd)" != "running" ]]; then
        echo "GlusterFS: stopped"
        return
    fi

    local peer_count=$(gluster peer status 2>/dev/null | grep -c "Peer in Cluster" || echo "0")
    local volume_count=$(gluster volume list 2>/dev/null | wc -l || echo "0")

    echo "GlusterFS: running"
    echo "  Peers: $peer_count"
    echo "  Volumes: $volume_count"

    # Check volume status
    if [[ $volume_count -gt 0 ]]; then
        while IFS= read -r volume; do
            local status=$(gluster volume info "$volume" 2>/dev/null | grep "Status:" | awk '{print $2}')
            echo "  Volume '$volume': $status"
        done < <(gluster volume list 2>/dev/null)
    fi
}

# Function to check MariaDB Galera status
check_mariadb_status() {
    if [[ "$(check_service_status mariadb)" != "running" ]]; then
        echo "MariaDB: stopped"
        return
    fi

    echo "MariaDB: running"

    # Check if Galera is enabled
    if mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | grep -q wsrep_cluster_size; then
        local cluster_size=$(mysql -se "SHOW STATUS LIKE 'wsrep_cluster_size'" | awk '{print $2}')
        local cluster_status=$(mysql -se "SHOW STATUS LIKE 'wsrep_cluster_status'" | awk '{print $2}')
        local local_state=$(mysql -se "SHOW STATUS LIKE 'wsrep_local_state_comment'" | awk '{print $2}')
        local ready=$(mysql -se "SHOW STATUS LIKE 'wsrep_ready'" | awk '{print $2}')

        echo "  Galera Cluster:"
        echo "    Size: $cluster_size nodes"
        echo "    Status: $cluster_status"
        echo "    Local State: $local_state"
        echo "    Ready: $ready"
    else
        echo "  Mode: Standalone (not Galera)"
    fi
}

# Function to check Redis status
check_redis_status() {
    local redis_service="redis-server"
    if ! systemctl list-units --type=service --all | grep -q "redis-server"; then
        redis_service="redis"
    fi

    if [[ "$(check_service_status $redis_service)" != "running" ]]; then
        echo "Redis: stopped"
        return
    fi

    echo "Redis: running"

    # Check Redis mode
    if redis-cli cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
        local cluster_state=$(redis-cli cluster info 2>/dev/null | grep cluster_state | cut -d: -f2)
        local cluster_size=$(redis-cli cluster info 2>/dev/null | grep cluster_size | cut -d: -f2)
        local cluster_slots_ok=$(redis-cli cluster info 2>/dev/null | grep cluster_slots_ok | cut -d: -f2)

        echo "  Mode: Cluster"
        echo "    State: $cluster_state"
        echo "    Size: $cluster_size nodes"
        echo "    Slots OK: $cluster_slots_ok"
    elif systemctl is-active --quiet redis-sentinel 2>/dev/null; then
        echo "  Mode: Sentinel"
        local master_status=$(redis-cli -p 26379 SENTINEL master mymaster 2>/dev/null | grep -A1 "status" | tail -1 || echo "unknown")
        echo "    Master Status: $master_status"
    else
        echo "  Mode: Standalone"
        local used_memory=$(redis-cli info memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r')
        echo "    Memory Used: $used_memory"
    fi
}

# Function to check Slurm status
check_slurm_status() {
    if [[ "$(check_service_status slurmctld)" != "running" ]]; then
        echo "Slurm: stopped"
        return
    fi

    echo "Slurm: running"

    # Check if scontrol is available
    if command -v scontrol &> /dev/null; then
        local total_nodes=$(scontrol show nodes 2>/dev/null | grep -c NodeName || echo "0")
        local idle_nodes=$(sinfo -h -o "%t" 2>/dev/null | grep -c "idle" || echo "0")
        local alloc_nodes=$(sinfo -h -o "%t" 2>/dev/null | grep -c "alloc" || echo "0")
        local down_nodes=$(sinfo -h -o "%t" 2>/dev/null | grep -c "down" || echo "0")

        echo "  Total Nodes: $total_nodes"
        echo "  Idle: $idle_nodes, Allocated: $alloc_nodes, Down: $down_nodes"

        # Check jobs
        if command -v squeue &> /dev/null; then
            local running_jobs=$(squeue -h -t RUNNING 2>/dev/null | wc -l || echo "0")
            local pending_jobs=$(squeue -h -t PENDING 2>/dev/null | wc -l || echo "0")

            echo "  Jobs: Running=$running_jobs, Pending=$pending_jobs"
        fi
    fi

    # Check slurmdbd
    if [[ "$(check_service_status slurmdbd)" == "running" ]]; then
        echo "  Accounting: running"
    else
        echo "  Accounting: stopped"
    fi
}

# Function to check Keepalived status
check_keepalived_status() {
    if [[ "$(check_service_status keepalived)" != "running" ]]; then
        echo "Keepalived: stopped"
        return
    fi

    echo "Keepalived: running"

    # Check VIP
    if [[ -f "$CONFIG_PATH" ]] && command -v python3 &> /dev/null; then
        local vip=$(python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" get-value network.vip 2>/dev/null || echo "")

        if [[ -n "$vip" ]]; then
            if ip addr show | grep -q "$vip"; then
                echo "  VIP $vip: MASTER (this node)"
            else
                echo "  VIP $vip: BACKUP"
            fi
        fi
    fi

    # Check VRRP state from logs
    local vrrp_state=$(journalctl -u keepalived -n 50 --no-pager 2>/dev/null | \
        grep -oE "Entering (MASTER|BACKUP|FAULT) STATE" | tail -1 | awk '{print $2}' || echo "UNKNOWN")
    echo "  VRRP State: $vrrp_state"
}

# Function to check web services status
check_web_services_status() {
    local web_services=(
        "nginx:Nginx"
        "dashboard:Dashboard"
        "auth_service:Auth Service"
        "job_api:Job API"
        "websocket_service:WebSocket"
        "file_service:File Service"
        "monitoring_dashboard:Monitoring"
        "metrics_api:Metrics API"
        "admin_portal:Admin Portal"
    )

    echo "Web Services:"

    local running_count=0
    local total_count=${#web_services[@]}

    for service_info in "${web_services[@]}"; do
        local service_name=$(echo "$service_info" | cut -d: -f1)
        local display_name=$(echo "$service_info" | cut -d: -f2)
        local status=$(check_service_status "$service_name")

        if [[ "$status" == "running" ]]; then
            ((running_count++))
            if [[ "$OUTPUT_FORMAT" == "full" ]]; then
                if [[ "$USE_COLOR" == true ]]; then
                    echo -e "  ${GREEN}●${NC} $display_name"
                else
                    echo "  ● $display_name"
                fi
            fi
        else
            if [[ "$OUTPUT_FORMAT" == "full" ]]; then
                if [[ "$USE_COLOR" == true ]]; then
                    echo -e "  ${RED}○${NC} $display_name"
                else
                    echo "  ○ $display_name"
                fi
            fi
        fi
    done

    if [[ "$OUTPUT_FORMAT" != "full" ]]; then
        echo "  Status: $running_count / $total_count running"
    fi
}

# Function to display full status
display_full_status() {
    echo ""
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║      Multi-Head HPC Cluster Status                        ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    else
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║      Multi-Head HPC Cluster Status                        ║"
        echo "╚════════════════════════════════════════════════════════════╝"
    fi
    echo ""

    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${BLUE}=== System Information ===${NC}"
    else
        echo "=== System Information ==="
    fi
    get_system_info
    echo ""

    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${BLUE}=== Resource Usage ===${NC}"
    else
        echo "=== Resource Usage ==="
    fi
    get_resource_usage
    echo ""

    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${BLUE}=== Cluster Services ===${NC}"
    else
        echo "=== Cluster Services ==="
    fi
    echo ""

    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "glusterfs" ]]; then
        check_glusterfs_status
        echo ""
    fi

    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "mariadb" ]]; then
        check_mariadb_status
        echo ""
    fi

    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "redis" ]]; then
        check_redis_status
        echo ""
    fi

    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "slurm" ]]; then
        check_slurm_status
        echo ""
    fi

    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "keepalived" ]]; then
        check_keepalived_status
        echo ""
    fi

    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "web" ]]; then
        check_web_services_status
        echo ""
    fi

    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${BLUE}=== Recent Errors (last 10) ===${NC}"
    else
        echo "=== Recent Errors (last 10) ==="
    fi
    journalctl -p err -n 10 --no-pager 2>/dev/null || echo "  No recent errors"
    echo ""
}

# Function to display compact status
display_compact_status() {
    local hostname=$(hostname)
    local ip=$(hostname -I | awk '{print $1}')

    echo "[$hostname ($ip)]"

    # Service status summary
    local services=(
        "glusterd:GlusterFS"
        "mariadb:MariaDB"
        "redis-server:Redis"
        "redis:Redis"
        "slurmctld:Slurm"
        "keepalived:Keepalived"
        "nginx:Web"
    )

    for service_info in "${services[@]}"; do
        local service_name=$(echo "$service_info" | cut -d: -f1)
        local display_name=$(echo "$service_info" | cut -d: -f2)
        local status=$(check_service_status "$service_name")

        if [[ "$status" == "running" ]]; then
            if [[ "$USE_COLOR" == true ]]; then
                echo -e "  ${GREEN}●${NC} $display_name"
            else
                echo "  ● $display_name"
            fi
        fi
    done
}

# Function to display JSON status
display_json_status() {
    local hostname=$(hostname)
    local ip=$(hostname -I | awk '{print $1}')
    local uptime=$(uptime -p)

    echo "{"
    echo "  \"hostname\": \"$hostname\","
    echo "  \"ip\": \"$ip\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"uptime\": \"$uptime\","
    echo "  \"services\": {"

    local services=(
        "glusterd"
        "mariadb"
        "redis-server"
        "slurmctld"
        "slurmdbd"
        "keepalived"
        "nginx"
        "dashboard"
        "auth_service"
        "job_api"
    )

    local first=true
    for service in "${services[@]}"; do
        local status=$(check_service_status "$service")

        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi

        echo -n "    \"$service\": \"$status\""
    done

    echo ""
    echo "  }"
    echo "}"
}

# Main function
main() {
    parse_args "$@"

    if [[ "$WATCH_MODE" == true ]]; then
        # Watch mode - refresh every 5 seconds
        while true; do
            clear
            case "$OUTPUT_FORMAT" in
                full)
                    display_full_status
                    ;;
                compact)
                    display_compact_status
                    ;;
                json)
                    display_json_status
                    ;;
                *)
                    log_error "Unknown format: $OUTPUT_FORMAT"
                    exit 1
                    ;;
            esac

            echo ""
            echo "Press Ctrl+C to exit. Refreshing in 5 seconds..."
            sleep 5
        done
    else
        # Single run
        case "$OUTPUT_FORMAT" in
            full)
                display_full_status
                ;;
            compact)
                display_compact_status
                ;;
            json)
                display_json_status
                ;;
            *)
                log_error "Unknown format: $OUTPUT_FORMAT"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"
