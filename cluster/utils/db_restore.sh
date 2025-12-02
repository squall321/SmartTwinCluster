#!/bin/bash

#############################################################################
# MariaDB Galera Cluster Restore Utility
#############################################################################
# Description:
#   Restores MariaDB Galera cluster from mariabackup backups
#   Supports full and incremental backup restoration
#
# Features:
#   - Automatic backup detection
#   - Safe restoration (stops MariaDB, backs up current data)
#   - Incremental chain restoration
#   - Galera cluster re-initialization
#   - Verification and validation
#
# Usage:
#   sudo ./cluster/utils/db_restore.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml
#   --backup-path PATH  Path to backup directory
#   --backup-dir PATH   Base backup directory (default: /var/backups/mariadb)
#   --list              List available backups
#   --force             Skip confirmation prompts
#   --help              Show this help message
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

# Default values
BACKUP_DIR="/var/backups/mariadb"
BACKUP_PATH=""
DATADIR="/var/lib/mysql"
LIST_ONLY=false
FORCE=false
LOG_FILE="/var/log/cluster_db_restore.log"

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
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # Log to console with color
    echo -e "${color}[$level]${NC} $message"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --config PATH       Path to my_multihead_cluster.yaml (default: $CONFIG_FILE)
  --backup-path PATH  Path to specific backup directory
  --backup-dir PATH   Base backup directory (default: $BACKUP_DIR)
  --list              List available backups and exit
  --force             Skip confirmation prompts (dangerous!)
  --help              Show this help message

Examples:
  # List available backups
  $0 --list

  # Restore from specific backup
  sudo $0 --backup-path /var/backups/mariadb/full/backup_20251027_120000

  # Interactive restore (will prompt for backup selection)
  sudo $0

  # Force restore without confirmation
  sudo $0 --backup-path /var/backups/mariadb/full/backup_20251027_120000 --force
EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_dependencies() {
    log INFO "Checking dependencies..."

    local deps=("mariabackup" "python3" "jq" "rsync")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log ERROR "Required dependency not found: $dep"
            exit 1
        fi
    done

    log SUCCESS "All dependencies satisfied"
}

load_config() {
    log INFO "Loading configuration..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Get database credentials
    DB_ROOT_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.root_password 2>/dev/null || echo "")

    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        log ERROR "Database root password not found in config"
        exit 1
    fi

    log SUCCESS "Configuration loaded"
}

list_backups() {
    log INFO "=== Available Backups ==="

    # List full backups
    echo ""
    log INFO "Full Backups:"
    echo "------------------------------------------------------------"
    printf "%-5s %-30s %-25s %-10s\n" "No." "Backup Name" "Timestamp" "Size"
    echo "------------------------------------------------------------"

    local index=1
    declare -g -A BACKUP_MAP

    while IFS= read -r backup; do
        if [[ -f "$backup/backup_metadata.json" ]]; then
            local backup_name=$(jq -r '.backup_name' "$backup/backup_metadata.json")
            local timestamp=$(jq -r '.timestamp' "$backup/backup_metadata.json")
            local size=$(jq -r '.size' "$backup/backup_metadata.json")

            printf "%-5s %-30s %-25s %-10s\n" "$index" "$backup_name" "$timestamp" "$size"

            BACKUP_MAP[$index]="$backup"
            index=$((index + 1))
        fi
    done < <(find "$BACKUP_DIR/full" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r)

    # List incremental backups
    echo ""
    log INFO "Incremental Backups:"
    echo "------------------------------------------------------------"
    printf "%-5s %-30s %-25s %-10s\n" "No." "Backup Name" "Timestamp" "Size"
    echo "------------------------------------------------------------"

    while IFS= read -r backup; do
        if [[ -f "$backup/backup_metadata.json" ]]; then
            local backup_name=$(jq -r '.backup_name' "$backup/backup_metadata.json")
            local timestamp=$(jq -r '.timestamp' "$backup/backup_metadata.json")
            local size=$(jq -r '.size' "$backup/backup_metadata.json")

            printf "%-5s %-30s %-25s %-10s\n" "$index" "$backup_name" "$timestamp" "$size"

            BACKUP_MAP[$index]="$backup"
            index=$((index + 1))
        fi
    done < <(find "$BACKUP_DIR/incremental" -maxdepth 1 -type d -name "incremental_*" 2>/dev/null | sort -r)

    echo "------------------------------------------------------------"
}

select_backup() {
    if [[ -n "$BACKUP_PATH" ]]; then
        # Backup path specified via command line
        if [[ ! -d "$BACKUP_PATH" ]]; then
            log ERROR "Backup path not found: $BACKUP_PATH"
            exit 1
        fi
        log INFO "Using specified backup: $BACKUP_PATH"
        return 0
    fi

    # Interactive selection
    list_backups

    echo ""
    read -p "Enter backup number to restore (or 'q' to quit): " selection

    if [[ "$selection" == "q" ]]; then
        log INFO "Restore cancelled"
        exit 0
    fi

    if [[ ! "${BACKUP_MAP[$selection]+isset}" ]]; then
        log ERROR "Invalid selection: $selection"
        exit 1
    fi

    BACKUP_PATH="${BACKUP_MAP[$selection]}"
    log INFO "Selected backup: $BACKUP_PATH"
}

validate_backup() {
    log INFO "Validating backup..."

    # Check if backup directory exists
    if [[ ! -d "$BACKUP_PATH" ]]; then
        log ERROR "Backup directory not found: $BACKUP_PATH"
        exit 1
    fi

    # Check for metadata file
    if [[ ! -f "$BACKUP_PATH/backup_metadata.json" ]]; then
        log WARNING "Backup metadata not found (old backup format?)"
    else
        local backup_type=$(jq -r '.backup_type' "$BACKUP_PATH/backup_metadata.json")
        local backup_name=$(jq -r '.backup_name' "$BACKUP_PATH/backup_metadata.json")
        local timestamp=$(jq -r '.timestamp' "$BACKUP_PATH/backup_metadata.json")

        log INFO "Backup type: $backup_type"
        log INFO "Backup name: $backup_name"
        log INFO "Timestamp: $timestamp"
    fi

    # Check for essential backup files
    if [[ ! -f "$BACKUP_PATH/xtrabackup_checkpoints" ]]; then
        log ERROR "Invalid backup: xtrabackup_checkpoints not found"
        exit 1
    fi

    log SUCCESS "Backup validation passed"
}

confirm_restore() {
    if [[ "$FORCE" == "true" ]]; then
        log WARNING "Force mode enabled, skipping confirmation"
        return 0
    fi

    log WARNING "=== WARNING ==="
    log WARNING "This will:"
    log WARNING "  1. Stop MariaDB service"
    log WARNING "  2. Backup current data directory to: ${DATADIR}_backup_$(date +%Y%m%d_%H%M%S)"
    log WARNING "  3. Restore from: $BACKUP_PATH"
    log WARNING "  4. Reinitialize Galera cluster (this node will bootstrap)"
    log WARNING ""
    log WARNING "ALL CURRENT DATA WILL BE REPLACED!"
    log WARNING "Make sure other cluster nodes are stopped before proceeding."
    echo ""

    read -p "Are you sure you want to continue? Type 'YES' to proceed: " confirmation

    if [[ "$confirmation" != "YES" ]]; then
        log INFO "Restore cancelled"
        exit 0
    fi

    log INFO "Confirmation received, proceeding with restore..."
}

stop_mariadb() {
    log INFO "Stopping MariaDB service..."

    if systemctl is-active --quiet mariadb; then
        systemctl stop mariadb
        sleep 3

        # Force kill if still running
        if systemctl is-active --quiet mariadb; then
            log WARNING "MariaDB did not stop gracefully, forcing..."
            pkill -9 mysqld || true
            sleep 2
        fi
    fi

    log SUCCESS "MariaDB stopped"
}

backup_current_data() {
    log INFO "Backing up current data directory..."

    local backup_name="${DATADIR}_backup_$(date +%Y%m%d_%H%M%S)"

    if [[ -d "$DATADIR" ]]; then
        log INFO "Moving $DATADIR to $backup_name"
        mv "$DATADIR" "$backup_name"
        log SUCCESS "Current data backed up to: $backup_name"
    else
        log INFO "Data directory does not exist, skipping backup"
    fi

    # Create fresh data directory
    mkdir -p "$DATADIR"
    chown mysql:mysql "$DATADIR"
    chmod 750 "$DATADIR"
}

prepare_backup() {
    log INFO "Preparing backup for restoration..."

    local prepare_dir="/tmp/mariabackup_prepare_$$"
    mkdir -p "$prepare_dir"

    log INFO "Copying backup to temporary directory..."
    rsync -a --info=progress2 "$BACKUP_PATH/" "$prepare_dir/"

    # Check if backup is compressed
    if ls "$prepare_dir"/*.qp &> /dev/null; then
        log INFO "Backup is compressed, decompressing..."
        mariabackup --decompress --target-dir="$prepare_dir" 2>&1 | tee -a "$LOG_FILE"

        # Remove compressed files
        find "$prepare_dir" -name "*.qp" -delete
    fi

    # Prepare backup
    log INFO "Preparing backup (applying transaction logs)..."
    if mariabackup --prepare --target-dir="$prepare_dir" 2>&1 | tee -a "$LOG_FILE"; then
        log SUCCESS "Backup prepared successfully"
    else
        log ERROR "Failed to prepare backup"
        rm -rf "$prepare_dir"
        exit 1
    fi

    # Copy prepared backup to data directory
    log INFO "Copying prepared backup to data directory..."
    rsync -a --info=progress2 "$prepare_dir/" "$DATADIR/"

    # Set ownership
    chown -R mysql:mysql "$DATADIR"

    # Clean up
    rm -rf "$prepare_dir"

    log SUCCESS "Backup restored to data directory"
}

remove_galera_state() {
    log INFO "Removing Galera state files to force re-bootstrap..."

    # Remove grastate.dat to allow bootstrap
    if [[ -f "$DATADIR/grastate.dat" ]]; then
        rm -f "$DATADIR/grastate.dat"
        log INFO "Removed grastate.dat"
    fi

    # Remove gvwstate.dat
    if [[ -f "$DATADIR/gvwstate.dat" ]]; then
        rm -f "$DATADIR/gvwstate.dat"
        log INFO "Removed gvwstate.dat"
    fi

    log SUCCESS "Galera state files removed"
}

bootstrap_cluster() {
    log INFO "Bootstrapping Galera cluster..."

    # Use galera_new_cluster to bootstrap
    if galera_new_cluster; then
        sleep 5

        # Check if MariaDB is running
        if systemctl is-active --quiet mariadb; then
            log SUCCESS "Galera cluster bootstrapped successfully"
        else
            log ERROR "Failed to bootstrap cluster"
            exit 1
        fi
    else
        log ERROR "Failed to start galera_new_cluster"
        exit 1
    fi
}

verify_restoration() {
    log INFO "Verifying restoration..."

    # Check if MariaDB is running
    if ! systemctl is-active --quiet mariadb; then
        log ERROR "MariaDB is not running"
        return 1
    fi

    # Check cluster status
    local wsrep_ready=$(mysql -uroot -p"$DB_ROOT_PASSWORD" -e "SHOW STATUS LIKE 'wsrep_ready';" 2>/dev/null | grep wsrep_ready | awk '{print $2}')
    local wsrep_cluster_size=$(mysql -uroot -p"$DB_ROOT_PASSWORD" -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | grep wsrep_cluster_size | awk '{print $2}')

    if [[ "$wsrep_ready" == "ON" ]]; then
        log SUCCESS "Cluster is ready"
        log INFO "Cluster size: $wsrep_cluster_size node(s)"
    else
        log ERROR "Cluster is not ready (wsrep_ready=$wsrep_ready)"
        return 1
    fi

    # List databases
    log INFO "Databases:"
    mysql -uroot -p"$DB_ROOT_PASSWORD" -e "SHOW DATABASES;" 2>/dev/null || true

    log SUCCESS "Verification complete"
}

show_next_steps() {
    log INFO ""
    log INFO "=== Next Steps ==="
    log INFO "1. Verify databases and data integrity"
    log INFO "2. Start other Galera nodes to join this cluster:"
    log INFO "   - Update their galera.cnf with correct wsrep_cluster_address"
    log INFO "   - Start MariaDB: systemctl start mariadb"
    log INFO "3. Monitor cluster status:"
    log INFO "   mysql -e \"SHOW STATUS LIKE 'wsrep_%';\""
    log INFO "4. Test replication by creating a test database"
}

#############################################################################
# Main
#############################################################################

main() {
    log INFO "=== MariaDB Galera Cluster Restore Utility ==="
    log INFO "Starting at $(date)"

    # Check root privileges
    check_root

    # Check dependencies
    check_dependencies

    # Load configuration
    load_config

    # List backups if requested
    if [[ "$LIST_ONLY" == "true" ]]; then
        list_backups
        exit 0
    fi

    # Select backup
    select_backup

    # Validate backup
    validate_backup

    # Confirm restore
    confirm_restore

    # Stop MariaDB
    stop_mariadb

    # Backup current data
    backup_current_data

    # Prepare and restore backup
    prepare_backup

    # Remove Galera state files
    remove_galera_state

    # Bootstrap cluster
    bootstrap_cluster

    # Verify restoration
    verify_restoration

    # Show next steps
    show_next_steps

    log SUCCESS "=== Restore completed successfully ==="
    log INFO "Finished at $(date)"
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
        --backup-path)
            BACKUP_PATH="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --force)
            FORCE=true
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
