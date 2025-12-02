#!/bin/bash

#############################################################################
# Phase -1: Pre-Setup Cleanup & Validation
#############################################################################
# Description:
#   Ensures idempotent setup by cleaning up existing services and resources
#   This phase runs BEFORE all other setup phases
#
# Features:
#   - Detects existing cluster services
#   - Safely stops services in reverse dependency order
#   - Backs up critical configurations
#   - Cleans up conflicting resources (ports, mounts, processes)
#   - Validates prerequisites
#
# Usage:
#   sudo ./cluster/setup/phase_pre_cleanup.sh [OPTIONS]
#
# Options:
#   --config PATH     Path to my_multihead_cluster.yaml
#   --force           Skip safety confirmations (DANGEROUS)
#   --backup-only     Only backup, don't cleanup
#   --dry-run         Show what would be done without executing
#   --help            Show this help message
#
# Author: Claude Code
# Date: 2025-10-30
#############################################################################

set -euo pipefail

#############################################################################
# Configuration
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/my_multihead_cluster.yaml"
BACKUP_DIR="/var/backups/cluster_setup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/cluster_cleanup.log"

# Default values
FORCE=false
BACKUP_ONLY=false
DRY_RUN=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Service lists (in reverse dependency order for cleanup)
SERVICES_TO_STOP=(
    # Web services first
    "nginx"
    "kooCAEWebServer_5000.service"
    "kooCAEWebServer_5001.service"
    "frontend_3010.service"
    "vnc_service_8002.service"
    "simulation_automation_8000.service"
    "simulation_automation_8001.service"
    "auth_service_5010.service"
    "auth_service_5011.service"

    # High-level services
    "keepalived"

    # Slurm services
    "slurmctld"
    "slurmdbd"
    "slurmd"

    # Data services
    "redis-server"
    "redis-sentinel"
    "mariadb"
    "mysql"

    # Storage services (last)
    "glusterd"
)

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
        CLEANUP) color=$CYAN ;;
    esac

    # Log to file
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi

    # Log to console with color
    echo -e "${color}[$level]${NC} $message"
}

show_help() {
    cat << 'EOF'
Phase -1: Pre-Setup Cleanup & Validation

This script ensures idempotent cluster setup by:
  1. Detecting existing services
  2. Backing up critical configurations
  3. Safely stopping services in dependency order
  4. Cleaning up conflicting resources

Usage:
  sudo ./cluster/setup/phase_pre_cleanup.sh [OPTIONS]

Options:
  --config PATH     Path to configuration file (default: my_multihead_cluster.yaml)
  --force           Skip safety confirmations (DANGEROUS - use only in automation)
  --backup-only     Only create backups, don't cleanup
  --dry-run         Show what would be done without executing
  --help            Show this help message

Examples:
  # Interactive cleanup with confirmations
  sudo ./cluster/setup/phase_pre_cleanup.sh

  # Automated cleanup (CI/CD)
  sudo ./cluster/setup/phase_pre_cleanup.sh --force

  # Dry run to see what would be cleaned
  sudo ./cluster/setup/phase_pre_cleanup.sh --dry-run

  # Backup existing configuration only
  sudo ./cluster/setup/phase_pre_cleanup.sh --backup-only

EOF
    exit 0
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        exit 1
    fi
}

detect_existing_services() {
    log INFO "Detecting existing cluster services..."

    local found_services=()

    for service in "${SERVICES_TO_STOP[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            found_services+=("$service")
            log WARNING "  ⚠ Found running service: $service"
        elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log INFO "  ℹ Found installed (not running): $service"
        fi
    done

    if [[ ${#found_services[@]} -eq 0 ]]; then
        log SUCCESS "No running cluster services detected"
        return 0
    else
        log WARNING "Found ${#found_services[@]} running cluster services"
        return 1
    fi
}

backup_configurations() {
    log INFO "Backing up existing configurations..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create backup directory: $BACKUP_DIR"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"

    local backed_up=0

    # Slurm configurations
    if [[ -f "/usr/local/slurm/etc/slurm.conf" ]]; then
        cp -p "/usr/local/slurm/etc/slurm.conf" "$BACKUP_DIR/"
        log SUCCESS "  ✓ Backed up slurm.conf"
        backed_up=$((backed_up + 1))
    fi

    if [[ -f "/etc/slurm/slurm.conf" ]]; then
        cp -p "/etc/slurm/slurm.conf" "$BACKUP_DIR/"
        log SUCCESS "  ✓ Backed up /etc/slurm/slurm.conf"
        backed_up=$((backed_up + 1))
    fi

    # MariaDB configurations
    if [[ -f "/etc/mysql/mariadb.conf.d/99-cluster.cnf" ]]; then
        cp -p "/etc/mysql/mariadb.conf.d/99-cluster.cnf" "$BACKUP_DIR/"
        log SUCCESS "  ✓ Backed up MariaDB cluster config"
        backed_up=$((backed_up + 1))
    fi

    # Redis configurations
    if [[ -f "/etc/redis/redis.conf" ]]; then
        cp -p "/etc/redis/redis.conf" "$BACKUP_DIR/"
        log SUCCESS "  ✓ Backed up Redis config"
        backed_up=$((backed_up + 1))
    fi

    # Keepalived configurations
    if [[ -f "/etc/keepalived/keepalived.conf" ]]; then
        cp -p "/etc/keepalived/keepalived.conf" "$BACKUP_DIR/"
        log SUCCESS "  ✓ Backed up Keepalived config"
        backed_up=$((backed_up + 1))
    fi

    # Web service configurations
    for web_dir in /opt/web_services/*/; do
        if [[ -d "$web_dir" ]]; then
            service_name=$(basename "$web_dir")
            cp -rp "$web_dir" "$BACKUP_DIR/$service_name" 2>/dev/null || true
            log SUCCESS "  ✓ Backed up $service_name config"
            backed_up=$((backed_up + 1))
        fi
    done

    if [[ $backed_up -gt 0 ]]; then
        log SUCCESS "Backed up $backed_up configurations to $BACKUP_DIR"
    else
        log INFO "No existing configurations found to backup"
    fi
}

stop_services() {
    log INFO "Stopping cluster services (reverse dependency order)..."

    local stopped=0

    for service in "${SERVICES_TO_STOP[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log INFO "[DRY-RUN] Would stop service: $service"
            else
                log INFO "  Stopping $service..."
                systemctl stop "$service" || log WARNING "  Failed to stop $service (may not exist)"
                stopped=$((stopped + 1))
            fi
        fi
    done

    if [[ $stopped -gt 0 ]]; then
        log SUCCESS "Stopped $stopped services"
    else
        log INFO "No running services to stop"
    fi
}

cleanup_ports() {
    log INFO "Checking for port conflicts..."

    local ports=(
        5000 5001  # Backend servers
        3010       # Frontend
        8000 8001 8002  # Services
        5010 5011  # Auth
        6379       # Redis
        3306       # MariaDB
        6709       # Slurm
        24007      # GlusterFS
    )

    local conflicts=0

    for port in "${ports[@]}"; do
        if lsof -ti:$port > /dev/null 2>&1; then
            # Get PIDs and convert to single line (space-separated)
            local pids=$(lsof -ti:$port | tr '\n' ' ' | sed 's/ $//')
            log WARNING "  ⚠ Port $port is in use by PIDs: $pids"

            if [[ "$DRY_RUN" == "false" && "$FORCE" == "true" ]]; then
                log CLEANUP "  Killing processes on port $port..."
                # Kill each PID
                echo "$pids" | xargs -n1 kill 2>/dev/null || true
            fi
            conflicts=$((conflicts + 1))
        fi
    done

    if [[ $conflicts -eq 0 ]]; then
        log SUCCESS "No port conflicts detected"
    else
        log WARNING "Found $conflicts port conflicts"
        if [[ "$FORCE" == "false" ]]; then
            log WARNING "Use --force to automatically kill conflicting processes"
        fi
    fi
}

cleanup_mounts() {
    log INFO "Checking GlusterFS mounts..."

    # Check for GlusterFS mounts
    if mount | grep -q glusterfs; then
        log WARNING "  ⚠ Found active GlusterFS mounts:"

        # Use mapfile instead of while read to avoid subshell issues
        local gluster_mounts
        mapfile -t gluster_mounts < <(mount | grep glusterfs)

        for line in "${gluster_mounts[@]}"; do
            log WARNING "    $line"
        done

        if [[ "$DRY_RUN" == "false" && "$FORCE" == "true" ]]; then
            log CLEANUP "  Unmounting GlusterFS volumes..."
            local mountpoints
            mapfile -t mountpoints < <(mount | grep glusterfs | awk '{print $3}')

            for mountpoint in "${mountpoints[@]}"; do
                umount "$mountpoint" 2>/dev/null || log WARNING "    Failed to unmount $mountpoint"
            done
        fi
    else
        log SUCCESS "No GlusterFS mounts found"
    fi
}

cleanup_slurm_state() {
    log INFO "Checking Slurm state directories..."

    local state_dirs=(
        "/var/spool/slurm/state"
        "/var/spool/slurm/d"
    )

    for dir in "${state_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
            log INFO "  Found Slurm state: $dir ($size)"

            if [[ "$DRY_RUN" == "false" && "$FORCE" == "true" ]]; then
                log WARNING "  Not removing state (manual cleanup required if needed)"
                # Intentionally not removing - let user decide
            fi
        fi
    done
}

validate_prerequisites() {
    log INFO "Validating prerequisites..."

    local missing=0

    # Check for required commands
    local required_commands=(
        "systemctl"
        "lsof"
        "python3"
    )

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log ERROR "  ✗ Missing required command: $cmd"
            missing=$((missing + 1))
        else
            log SUCCESS "  ✓ Found: $cmd"
        fi
    done

    if [[ $missing -gt 0 ]]; then
        log ERROR "Missing $missing required prerequisites"
        return 1
    else
        log SUCCESS "All prerequisites satisfied"
        return 0
    fi
}

confirm_cleanup() {
    if [[ "$FORCE" == "true" ]]; then
        log WARNING "Running in FORCE mode - skipping confirmations"
        return 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log WARNING "This will:"
    echo "  1. Stop all running cluster services"
    echo "  2. Backup existing configurations to $BACKUP_DIR"
    echo "  3. Clean up conflicting resources (ports, mounts)"
    echo "  4. Prepare system for fresh cluster setup"
    echo ""
    log WARNING "This is SAFE - your data will be backed up first"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    read -p "Continue with cleanup? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
}

#############################################################################
# Main
#############################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --backup-only)
                BACKUP_ONLY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                ;;
        esac
    done

    # Banner
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║  Phase -1: Pre-Setup Cleanup & Validation                     ║"
    echo "║                                                                ║"
    echo "║  Ensuring idempotent cluster setup                            ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Check root
    check_root

    # Validate prerequisites
    if ! validate_prerequisites; then
        exit 1
    fi

    echo ""
    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log INFO "Step 1: Detect Existing Services"
    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Capture return code without triggering set -e
    detect_existing_services && has_existing_services=0 || has_existing_services=$?

    echo ""
    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log INFO "Step 2: Backup Existing Configurations"
    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    backup_configurations

    if [[ "$BACKUP_ONLY" == "true" ]]; then
        log SUCCESS "Backup completed. Exiting (--backup-only mode)"
        exit 0
    fi

    # Only proceed with cleanup if there are existing services
    if [[ $has_existing_services -eq 1 ]] || [[ "$FORCE" == "true" ]]; then
        confirm_cleanup

        echo ""
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log INFO "Step 3: Stop Services (Reverse Dependency Order)"
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        stop_services

        echo ""
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log INFO "Step 4: Check Port Conflicts"
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        cleanup_ports

        echo ""
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log INFO "Step 5: Check Filesystem Mounts"
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        cleanup_mounts

        echo ""
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log INFO "Step 6: Check Slurm State"
        log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        cleanup_slurm_state
    else
        log INFO "No cleanup needed - system is clean"
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║  ✅ Pre-Setup Cleanup Complete                                 ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "This was a DRY-RUN. No changes were made."
    else
        log SUCCESS "System is ready for cluster setup!"
    fi

    if [[ -d "$BACKUP_DIR" ]]; then
        log INFO "Backups saved to: $BACKUP_DIR"
    fi

    echo ""
}

# Run main function
main "$@"
