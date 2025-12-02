#!/bin/bash

################################################################################
# Multi-Head Cluster Stop Script
#
# This script gracefully stops all services in the multi-head HPC cluster
# in the reverse order of startup to ensure proper shutdown.
#
# Stop Order (reverse of startup):
#   1. Web Services (nginx, dashboard, APIs)
#   2. Keepalived (VIP management)
#   3. Slurm (job scheduler)
#   4. Redis (cache)
#   5. MariaDB (database)
#   6. GlusterFS (storage)
#
# Usage:
#   sudo ./stop_multihead.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)
#   --service NAME      Stop specific service only (web, keepalived, slurm, redis, mariadb, glusterfs)
#   --force             Force stop (kill -9) if graceful stop fails
#   --keep-data         Keep data (don't umount GlusterFS)
#   --auto-confirm      Skip confirmation prompts
#   --help              Show this help message
#
# Examples:
#   sudo ./stop_multihead.sh
#   sudo ./stop_multihead.sh --service web
#   sudo ./stop_multihead.sh --force --auto-confirm
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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
CONFIG_PATH="$PROJECT_ROOT/my_multihead_cluster.yaml"
SPECIFIC_SERVICE=""
FORCE=false
KEEP_DATA=false
AUTO_CONFIRM=false
LOG_FILE="/var/log/cluster_multihead_stop.log"

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
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
            --service)
                SPECIFIC_SERVICE="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --keep-data)
                KEEP_DATA=true
                shift
                ;;
            --auto-confirm)
                AUTO_CONFIRM=true
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

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Function to confirm execution
confirm_execution() {
    if [[ "$AUTO_CONFIRM" == true ]]; then
        return 0
    fi

    echo -ne "${YELLOW}This will stop cluster services. Continue? (yes/no): ${NC}"
    read -r response

    if [[ "$response" != "yes" && "$response" != "y" ]]; then
        log_info "Execution cancelled by user"
        exit 0
    fi
}

# Function to stop a systemd service
stop_service() {
    local service_name=$1
    local timeout=${2:-30}

    log_info "Stopping $service_name..."

    if ! systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log_info "$service_name is not running"
        return 0
    fi

    # Try graceful stop
    if systemctl stop "$service_name" --no-block; then
        # Wait for service to stop
        local elapsed=0
        while systemctl is-active --quiet "$service_name" 2>/dev/null; do
            if [[ $elapsed -ge $timeout ]]; then
                log_warning "$service_name did not stop within ${timeout}s"

                if [[ "$FORCE" == true ]]; then
                    log_warning "Force stopping $service_name..."
                    systemctl kill -s SIGKILL "$service_name" 2>/dev/null || true
                    sleep 2
                    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                        log_error "Failed to force stop $service_name"
                        return 1
                    fi
                else
                    log_error "Use --force to forcefully stop $service_name"
                    return 1
                fi
                break
            fi

            sleep 1
            ((elapsed++))
        done

        log_success "$service_name stopped"
        return 0
    else
        log_error "Failed to stop $service_name"
        return 1
    fi
}

# Function to stop web services
stop_web_services() {
    log_info "=== Stopping Web Services ==="

    local web_services=(
        "nginx"
        "admin_portal"
        "metrics_api"
        "monitoring_dashboard"
        "file_service"
        "websocket_service"
        "job_api"
        "auth_service"
        "dashboard"
    )

    for service in "${web_services[@]}"; do
        stop_service "$service" 10 || log_warning "Failed to stop $service (continuing...)"
    done

    log_success "Web services stopped"
}

# Function to stop Keepalived
stop_keepalived() {
    log_info "=== Stopping Keepalived ==="

    stop_service "keepalived" 10

    # Check if VIP is still present
    local vip
    if [[ -f "$CONFIG_PATH" ]]; then
        vip=$(python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" get-value network.vip 2>/dev/null || echo "")

        if [[ -n "$vip" ]]; then
            if ip addr show | grep -q "$vip"; then
                log_warning "VIP $vip is still present, removing..."
                ip addr del "$vip/24" dev eth0 2>/dev/null || true
            fi
        fi
    fi

    log_success "Keepalived stopped"
}

# Function to stop Slurm
stop_slurm() {
    log_info "=== Stopping Slurm ==="

    # Stop in order: compute nodes, controller
    local slurm_services=(
        "slurmd"        # Compute node daemon
        "slurmctld"     # Controller daemon
        "slurmdbd"      # Database daemon
    )

    for service in "${slurm_services[@]}"; do
        stop_service "$service" 30 || log_warning "Failed to stop $service (continuing...)"
    done

    # Cancel all running jobs if force mode
    if [[ "$FORCE" == true ]]; then
        log_warning "Cancelling all running jobs..."
        scancel --state=RUNNING --user=ALL 2>/dev/null || true
    fi

    log_success "Slurm stopped"
}

# Function to stop Redis
stop_redis() {
    log_info "=== Stopping Redis ==="

    # Check if Redis is in cluster mode
    local redis_mode="standalone"
    if systemctl is-active --quiet redis-sentinel 2>/dev/null; then
        redis_mode="sentinel"
    elif redis-cli cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
        redis_mode="cluster"
    fi

    log_info "Redis mode: $redis_mode"

    case "$redis_mode" in
        cluster)
            # Save data before shutdown
            log_info "Saving Redis cluster data..."
            redis-cli --cluster call 127.0.0.1:6379 SAVE 2>/dev/null || true

            # Stop Redis cluster nodes
            for port in 6379 6380 6381; do
                stop_service "redis@${port}" 15 || log_warning "Failed to stop redis@${port}"
            done
            ;;
        sentinel)
            # Stop sentinel first, then Redis
            stop_service "redis-sentinel" 10 || true
            stop_service "redis-server" 15 || stop_service "redis" 15 || true
            ;;
        *)
            # Stop standalone Redis
            stop_service "redis-server" 15 || stop_service "redis" 15 || true
            ;;
    esac

    log_success "Redis stopped"
}

# Function to stop MariaDB
stop_mariadb() {
    log_info "=== Stopping MariaDB ==="

    # Check if this is a Galera cluster node
    local is_galera=false
    if systemctl is-active --quiet mariadb 2>/dev/null; then
        if mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | grep -q wsrep_cluster_size; then
            is_galera=true
        fi
    fi

    if [[ "$is_galera" == true ]]; then
        log_info "Detected Galera cluster node"

        # Flush data before shutdown
        log_info "Flushing MariaDB data..."
        mysql -e "FLUSH TABLES WITH READ LOCK; FLUSH LOGS;" 2>/dev/null || true
        sleep 2
        mysql -e "UNLOCK TABLES;" 2>/dev/null || true

        # Graceful shutdown with longer timeout for Galera
        stop_service "mariadb" 60
    else
        # Regular MariaDB stop
        stop_service "mariadb" 30
    fi

    log_success "MariaDB stopped"
}

# Function to stop GlusterFS
stop_glusterfs() {
    log_info "=== Stopping GlusterFS ==="

    # Unmount GlusterFS volumes (if not keeping data)
    if [[ "$KEEP_DATA" == false ]]; then
        log_info "Unmounting GlusterFS volumes..."

        # Common mount points
        local mount_points=(
            "/mnt/gluster"
            "/mnt/gluster/slurm_state"
            "/mnt/gluster/uploads"
        )

        for mount_point in "${mount_points[@]}"; do
            if mountpoint -q "$mount_point" 2>/dev/null; then
                log_info "Unmounting $mount_point..."
                if umount "$mount_point" 2>/dev/null; then
                    log_success "$mount_point unmounted"
                else
                    log_warning "Failed to unmount $mount_point"
                    if [[ "$FORCE" == true ]]; then
                        log_warning "Force unmounting $mount_point..."
                        umount -f "$mount_point" 2>/dev/null || \
                        umount -l "$mount_point" 2>/dev/null || true
                    fi
                fi
            fi
        done
    else
        log_info "Keeping GlusterFS volumes mounted (--keep-data)"
    fi

    # Stop GlusterFS daemon
    stop_service "glusterd" 30

    log_success "GlusterFS stopped"
}

# Function to display current status
display_status() {
    log_info "=== Current Service Status ==="

    local services=(
        "nginx:Web Server"
        "dashboard:Dashboard"
        "auth_service:Auth Service"
        "job_api:Job API"
        "keepalived:Keepalived"
        "slurmctld:Slurm Controller"
        "slurmdbd:Slurm DB"
        "slurmd:Slurm Compute"
        "redis-server:Redis"
        "redis:Redis"
        "mariadb:MariaDB"
        "glusterd:GlusterFS"
    )

    for service_info in "${services[@]}"; do
        local service_name=$(echo "$service_info" | cut -d: -f1)
        local display_name=$(echo "$service_info" | cut -d: -f2)

        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} $display_name"
        else
            echo -e "  ${RED}○${NC} $display_name"
        fi
    done

    echo ""
}

# Function to cleanup
cleanup() {
    log_info "=== Cleanup ==="

    # Remove PID files
    local pid_files=(
        "/var/run/slurmctld.pid"
        "/var/run/slurmdbd.pid"
        "/var/run/keepalived.pid"
    )

    for pid_file in "${pid_files[@]}"; do
        if [[ -f "$pid_file" ]]; then
            log_info "Removing $pid_file"
            rm -f "$pid_file"
        fi
    done

    # Clean up temp files
    if [[ "$FORCE" == true ]]; then
        log_info "Cleaning up temporary files..."
        rm -f /tmp/slurm_*.tmp 2>/dev/null || true
        rm -f /tmp/redis_*.rdb 2>/dev/null || true
    fi

    log_success "Cleanup complete"
}

# Main function
main() {
    parse_args "$@"

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      Multi-Head HPC Cluster Stop                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "Starting at: $(date)"
    echo ""

    check_root

    log_info "Current node: $(hostname -I | awk '{print $1}')"
    echo ""

    display_status
    confirm_execution

    echo ""
    log_info "=== Stopping Cluster Services ==="
    echo ""

    if [[ -n "$SPECIFIC_SERVICE" ]]; then
        # Stop specific service only
        log_info "Stopping service: $SPECIFIC_SERVICE"

        case "$SPECIFIC_SERVICE" in
            web)
                stop_web_services
                ;;
            keepalived)
                stop_keepalived
                ;;
            slurm)
                stop_slurm
                ;;
            redis)
                stop_redis
                ;;
            mariadb|database)
                stop_mariadb
                ;;
            glusterfs|storage)
                stop_glusterfs
                ;;
            *)
                log_error "Unknown service: $SPECIFIC_SERVICE"
                log_info "Valid services: web, keepalived, slurm, redis, mariadb, glusterfs"
                exit 1
                ;;
        esac
    else
        # Stop all services in reverse order
        stop_web_services
        echo ""

        stop_keepalived
        echo ""

        stop_slurm
        echo ""

        stop_redis
        echo ""

        stop_mariadb
        echo ""

        stop_glusterfs
        echo ""
    fi

    cleanup
    echo ""

    display_status

    log_success "=== Cluster services stopped ==="
    log_info "Finished at: $(date)"

    if [[ "$KEEP_DATA" == false ]]; then
        log_info "Data volumes unmounted. To restart: sudo ./start_multihead.sh"
    else
        log_info "Data volumes kept mounted. To restart: sudo ./start_multihead.sh"
    fi

    echo ""
}

# Run main function
main "$@"
