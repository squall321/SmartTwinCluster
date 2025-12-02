#!/bin/bash

################################################################################
# Web Services Health Check Script
#
# This script checks the health of all web services deployed on controllers
# with web: true enabled.
#
# Usage:
#   ./web_health_check.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml (default: ../../my_multihead_cluster.yaml)
#   --format FORMAT     Output format: table, json, compact (default: table)
#   --service NAME      Check specific service only
#   --all-nodes         Check all web-enabled nodes (default: local only)
#   --timeout SECONDS   HTTP timeout in seconds (default: 5)
#   --verbose           Show detailed output
#   --help              Show this help message
#
# Examples:
#   ./web_health_check.sh
#   ./web_health_check.sh --all-nodes --format json
#   ./web_health_check.sh --service dashboard --verbose
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
CONFIG_PATH="$PROJECT_ROOT/my_multihead_cluster.yaml"
OUTPUT_FORMAT="table"
CHECK_SERVICE=""
ALL_NODES=false
TIMEOUT=5
VERBOSE=false

# Service definitions
declare -A SERVICES=(
    ["dashboard"]="5173:/:frontend"
    ["auth_service"]="5000:/health:backend"
    ["job_api"]="5001:/health:backend"
    ["websocket_service"]="5010:/health:backend"
    ["file_service"]="5002:/health:backend"
    ["monitoring_dashboard"]="5174:/:frontend"
    ["metrics_api"]="5003:/health:backend"
    ["admin_portal"]="5175:/:frontend"
)

# Function to print colored output
log_info() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

log_success() {
    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
    fi
}

log_warning() {
    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    fi
}

log_error() {
    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
        echo -e "${RED}[ERROR]${NC} $1" >&2
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
                CHECK_SERVICE="$2"
                shift 2
                ;;
            --all-nodes)
                ALL_NODES=true
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
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

# Function to check single service
check_service() {
    local node_ip=$1
    local service_name=$2
    local service_info=$3

    local port=$(echo "$service_info" | cut -d: -f1)
    local path=$(echo "$service_info" | cut -d: -f2)
    local type=$(echo "$service_info" | cut -d: -f3)

    local url="http://${node_ip}:${port}${path}"

    log_info "Checking $service_name at $url"

    # Attempt HTTP request with timeout
    local response_code
    local response_time
    local status="unknown"
    local message=""

    if response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" 2>/dev/null); then
        response_time=$(curl -s -o /dev/null -w "%{time_total}" --max-time "$TIMEOUT" "$url" 2>/dev/null)

        if [[ "$response_code" -ge 200 && "$response_code" -lt 300 ]]; then
            status="healthy"
            message="OK"
        elif [[ "$response_code" -ge 300 && "$response_code" -lt 400 ]]; then
            status="redirect"
            message="Redirect ($response_code)"
        elif [[ "$response_code" -ge 400 && "$response_code" -lt 500 ]]; then
            status="client_error"
            message="Client Error ($response_code)"
        elif [[ "$response_code" -ge 500 ]]; then
            status="server_error"
            message="Server Error ($response_code)"
        fi
    else
        status="unreachable"
        message="Connection failed"
        response_code="000"
        response_time="0"
    fi

    # Check if systemd service is running (local only)
    local service_status="unknown"
    if [[ "$node_ip" == "localhost" || "$node_ip" == "127.0.0.1" ]]; then
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            service_status="running"
        else
            service_status="stopped"
        fi
    fi

    # Output result
    echo "$node_ip|$service_name|$type|$port|$status|$response_code|$response_time|$service_status|$message"
}

# Function to check all services on a node
check_node() {
    local node_ip=$1

    log_info "Checking services on node $node_ip..."

    local results=()

    if [[ -n "$CHECK_SERVICE" ]]; then
        # Check specific service only
        if [[ -v "SERVICES[$CHECK_SERVICE]" ]]; then
            results+=($(check_service "$node_ip" "$CHECK_SERVICE" "${SERVICES[$CHECK_SERVICE]}"))
        else
            log_error "Unknown service: $CHECK_SERVICE"
            log_info "Available services: ${!SERVICES[*]}"
            exit 1
        fi
    else
        # Check all services
        for service_name in "${!SERVICES[@]}"; do
            results+=($(check_service "$node_ip" "$service_name" "${SERVICES[$service_name]}"))
        done
    fi

    printf '%s\n' "${results[@]}"
}

# Function to format output as table
format_table() {
    local results=("$@")

    echo ""
    printf "%-20s %-25s %-10s %-6s %-12s %-6s %-10s %-15s %s\n" \
        "Node" "Service" "Type" "Port" "Status" "HTTP" "Time (s)" "Systemd" "Message"
    echo "------------------------------------------------------------------------------------------------------------------------------------"

    for result in "${results[@]}"; do
        IFS='|' read -r node service type port status code time systemd_status message <<< "$result"

        # Color code status
        local status_colored
        case "$status" in
            healthy)
                status_colored="${GREEN}${status}${NC}"
                ;;
            unreachable|server_error)
                status_colored="${RED}${status}${NC}"
                ;;
            redirect|client_error)
                status_colored="${YELLOW}${status}${NC}"
                ;;
            *)
                status_colored="$status"
                ;;
        esac

        # Color code systemd status
        local systemd_colored
        case "$systemd_status" in
            running)
                systemd_colored="${GREEN}${systemd_status}${NC}"
                ;;
            stopped)
                systemd_colored="${RED}${systemd_status}${NC}"
                ;;
            *)
                systemd_colored="$systemd_status"
                ;;
        esac

        printf "%-20s %-25s %-10s %-6s %-20s %-6s %-10s %-23s %s\n" \
            "$node" "$service" "$type" "$port" "$status_colored" "$code" "$time" "$systemd_colored" "$message"
    done

    echo ""
}

# Function to format output as JSON
format_json() {
    local results=("$@")

    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"checks\": ["

    local first=true
    for result in "${results[@]}"; do
        IFS='|' read -r node service type port status code time systemd_status message <<< "$result"

        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi

        echo -n "    {"
        echo -n "\"node\": \"$node\", "
        echo -n "\"service\": \"$service\", "
        echo -n "\"type\": \"$type\", "
        echo -n "\"port\": $port, "
        echo -n "\"status\": \"$status\", "
        echo -n "\"http_code\": $code, "
        echo -n "\"response_time\": $time, "
        echo -n "\"systemd_status\": \"$systemd_status\", "
        echo -n "\"message\": \"$message\""
        echo -n "}"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# Function to format output as compact
format_compact() {
    local results=("$@")

    local healthy_count=0
    local unhealthy_count=0

    for result in "${results[@]}"; do
        IFS='|' read -r node service type port status code time systemd_status message <<< "$result"

        if [[ "$status" == "healthy" ]]; then
            ((healthy_count++))
            echo -e "${GREEN}✓${NC} $service@$node"
        else
            ((unhealthy_count++))
            echo -e "${RED}✗${NC} $service@$node - $status ($message)"
        fi
    done

    echo ""
    echo "Summary: $healthy_count healthy, $unhealthy_count unhealthy"
}

# Function to get all web-enabled nodes
get_web_nodes() {
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error "Configuration file not found: $CONFIG_PATH"
        exit 1
    fi

    if [[ ! -f "$SCRIPT_DIR/../config/parser.py" ]]; then
        log_error "Parser script not found"
        exit 1
    fi

    python3 "$SCRIPT_DIR/../config/parser.py" "$CONFIG_PATH" get-controllers --service web | jq -r '.[].ip'
}

# Main function
main() {
    parse_args "$@"

    log_info "=== Web Services Health Check ==="
    log_info "Timeout: ${TIMEOUT}s"

    local results=()

    if [[ "$ALL_NODES" == true ]]; then
        # Check all web-enabled nodes
        log_info "Checking all web-enabled nodes..."

        local nodes
        nodes=$(get_web_nodes)

        if [[ -z "$nodes" ]]; then
            log_error "No web-enabled nodes found in configuration"
            exit 1
        fi

        for node in $nodes; do
            while IFS= read -r line; do
                results+=("$line")
            done < <(check_node "$node")
        done
    else
        # Check local node only
        while IFS= read -r line; do
            results+=("$line")
        done < <(check_node "localhost")
    fi

    # Format and display results
    case "$OUTPUT_FORMAT" in
        table)
            format_table "${results[@]}"
            ;;
        json)
            format_json "${results[@]}"
            ;;
        compact)
            format_compact "${results[@]}"
            ;;
        *)
            log_error "Unknown output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac

    # Exit with error if any service is unhealthy
    local all_healthy=true
    for result in "${results[@]}"; do
        IFS='|' read -r node service type port status code time systemd_status message <<< "$result"
        if [[ "$status" != "healthy" ]]; then
            all_healthy=false
            break
        fi
    done

    if [[ "$all_healthy" == true ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
