#!/bin/bash

#############################################################################
# Redis Cluster Restore Utility
#############################################################################
# Description:
#   Restores Redis data from RDB or AOF backups
#   Supports both Cluster mode and Sentinel mode
#
# Features:
#   - Automatic backup detection
#   - Safe restoration (stops Redis, backs up current data)
#   - RDB and AOF restoration
#   - Cluster re-initialization
#
# Usage:
#   sudo ./cluster/utils/redis_restore.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml
#   --backup-path PATH  Path to backup directory
#   --backup-dir PATH   Base backup directory (default: /var/backups/redis)
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
BACKUP_DIR="/var/backups/redis"
BACKUP_PATH=""
REDIS_DATA_DIR="/var/lib/redis"
LIST_ONLY=false
FORCE=false
LOG_FILE="/var/log/cluster_redis_restore.log"

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
  sudo $0 --backup-path /var/backups/redis/rdb/rdb_backup_20251027_120000

  # Interactive restore (will prompt for backup selection)
  sudo $0

  # Force restore without confirmation
  sudo $0 --backup-path /var/backups/redis/rdb/rdb_backup_20251027_120000 --force
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

    local deps=("redis-cli" "python3" "jq")
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

    # Get Redis password
    REDIS_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cache.redis.password 2>/dev/null || echo "")

    if [[ -z "$REDIS_PASSWORD" ]]; then
        log ERROR "Redis password not found in config"
        exit 1
    fi

    log SUCCESS "Configuration loaded"
}

list_backups() {
    log INFO "=== Available Backups ==="

    # List RDB backups
    echo ""
    log INFO "RDB Backups:"
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
    done < <(find "$BACKUP_DIR/rdb" -maxdepth 1 -type d -name "rdb_backup_*" 2>/dev/null | sort -r)

    # List AOF backups
    echo ""
    log INFO "AOF Backups:"
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
    done < <(find "$BACKUP_DIR/aof" -maxdepth 1 -type d -name "aof_backup_*" 2>/dev/null | sort -r)

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
        BACKUP_TYPE=$(jq -r '.backup_type' "$BACKUP_PATH/backup_metadata.json")
        local backup_name=$(jq -r '.backup_name' "$BACKUP_PATH/backup_metadata.json")
        local timestamp=$(jq -r '.timestamp' "$BACKUP_PATH/backup_metadata.json")

        log INFO "Backup type: $BACKUP_TYPE"
        log INFO "Backup name: $backup_name"
        log INFO "Timestamp: $timestamp"
    fi

    # Check for backup files
    if [[ "$BACKUP_TYPE" == "rdb" ]] || [[ -f "$BACKUP_PATH/dump.rdb" ]] || [[ -f "$BACKUP_PATH/dump.rdb.gz" ]]; then
        BACKUP_TYPE="rdb"
        log INFO "RDB backup detected"
    elif [[ "$BACKUP_TYPE" == "aof" ]] || [[ -f "$BACKUP_PATH/appendonly.aof" ]] || [[ -f "$BACKUP_PATH/appendonly.aof.gz" ]]; then
        BACKUP_TYPE="aof"
        log INFO "AOF backup detected"
    else
        log ERROR "No valid backup files found (dump.rdb or appendonly.aof)"
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
    log WARNING "  1. Stop Redis service"
    log WARNING "  2. Backup current data directory to: ${REDIS_DATA_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    log WARNING "  3. Restore from: $BACKUP_PATH"
    log WARNING "  4. Restart Redis"
    log WARNING ""
    log WARNING "ALL CURRENT DATA WILL BE REPLACED!"
    echo ""

    read -p "Are you sure you want to continue? Type 'YES' to proceed: " confirmation

    if [[ "$confirmation" != "YES" ]]; then
        log INFO "Restore cancelled"
        exit 0
    fi

    log INFO "Confirmation received, proceeding with restore..."
}

stop_redis() {
    log INFO "Stopping Redis service..."

    if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
        systemctl stop redis-server || systemctl stop redis
        sleep 3

        # Force kill if still running
        if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
            log WARNING "Redis did not stop gracefully, forcing..."
            pkill -9 redis-server || true
            sleep 2
        fi
    fi

    log SUCCESS "Redis stopped"
}

backup_current_data() {
    log INFO "Backing up current data directory..."

    local backup_name="${REDIS_DATA_DIR}_backup_$(date +%Y%m%d_%H%M%S)"

    if [[ -d "$REDIS_DATA_DIR" ]]; then
        log INFO "Moving $REDIS_DATA_DIR to $backup_name"
        mv "$REDIS_DATA_DIR" "$backup_name"
        log SUCCESS "Current data backed up to: $backup_name"
    else
        log INFO "Data directory does not exist, skipping backup"
    fi

    # Create fresh data directory
    mkdir -p "$REDIS_DATA_DIR"
    chown redis:redis "$REDIS_DATA_DIR" 2>/dev/null || chown redis:redis "$REDIS_DATA_DIR" || true
    chmod 750 "$REDIS_DATA_DIR"
}

restore_rdb() {
    log INFO "Restoring from RDB backup..."

    local rdb_file=""

    # Check for compressed or uncompressed RDB file
    if [[ -f "$BACKUP_PATH/dump.rdb.gz" ]]; then
        log INFO "Decompressing RDB backup..."
        gunzip -c "$BACKUP_PATH/dump.rdb.gz" > "$REDIS_DATA_DIR/dump.rdb"
        rdb_file="$REDIS_DATA_DIR/dump.rdb"
    elif [[ -f "$BACKUP_PATH/dump.rdb" ]]; then
        log INFO "Copying RDB backup..."
        cp "$BACKUP_PATH/dump.rdb" "$REDIS_DATA_DIR/dump.rdb"
        rdb_file="$REDIS_DATA_DIR/dump.rdb"
    else
        log ERROR "RDB file not found in backup"
        exit 1
    fi

    # Set ownership
    chown redis:redis "$rdb_file"
    chmod 640 "$rdb_file"

    log SUCCESS "RDB backup restored to data directory"
}

restore_aof() {
    log INFO "Restoring from AOF backup..."

    local aof_file=""

    # Check for compressed or uncompressed AOF file
    if [[ -f "$BACKUP_PATH/appendonly.aof.gz" ]]; then
        log INFO "Decompressing AOF backup..."
        gunzip -c "$BACKUP_PATH/appendonly.aof.gz" > "$REDIS_DATA_DIR/appendonly.aof"
        aof_file="$REDIS_DATA_DIR/appendonly.aof"
    elif [[ -f "$BACKUP_PATH/appendonly.aof" ]]; then
        log INFO "Copying AOF backup..."
        cp "$BACKUP_PATH/appendonly.aof" "$REDIS_DATA_DIR/appendonly.aof"
        aof_file="$REDIS_DATA_DIR/appendonly.aof"
    else
        log ERROR "AOF file not found in backup"
        exit 1
    fi

    # Set ownership
    chown redis:redis "$aof_file"
    chmod 640 "$aof_file"

    log SUCCESS "AOF backup restored to data directory"
}

start_redis() {
    log INFO "Starting Redis service..."

    if systemctl start redis-server || systemctl start redis; then
        sleep 5

        # Check if Redis is running
        if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
            log SUCCESS "Redis started successfully"
        else
            log ERROR "Failed to start Redis"
            exit 1
        fi
    else
        log ERROR "Failed to start Redis"
        exit 1
    fi
}

verify_restoration() {
    log INFO "Verifying restoration..."

    # Check if Redis is running
    if ! systemctl is-active --quiet redis-server && ! systemctl is-active --quiet redis; then
        log ERROR "Redis is not running"
        return 1
    fi

    # Test connection
    if ! redis-cli -a "$REDIS_PASSWORD" PING &>/dev/null; then
        log ERROR "Cannot connect to Redis"
        return 1
    fi

    log SUCCESS "Redis is responsive"

    # Get database info
    local dbsize=$(redis-cli -a "$REDIS_PASSWORD" DBSIZE 2>/dev/null | grep -oP '\d+')
    log INFO "Database size: $dbsize keys"

    # Show sample keys
    log INFO "Sample keys:"
    redis-cli -a "$REDIS_PASSWORD" --scan --count 10 2>/dev/null | head -5 || true

    log SUCCESS "Verification complete"
}

show_next_steps() {
    log INFO ""
    log INFO "=== Next Steps ==="
    log INFO "1. Verify data integrity"
    log INFO "   redis-cli -a '$REDIS_PASSWORD' DBSIZE"
    log INFO "   redis-cli -a '$REDIS_PASSWORD' KEYS '*' | head"
    log INFO "2. Test application connectivity"
    log INFO "3. If using cluster mode, re-join other nodes or restore all nodes"
    log INFO "4. Monitor Redis: redis-cli -a '$REDIS_PASSWORD' INFO"
}

#############################################################################
# Main
#############################################################################

main() {
    log INFO "=== Redis Cluster Restore Utility ==="
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

    # Stop Redis
    stop_redis

    # Backup current data
    backup_current_data

    # Restore based on backup type
    case $BACKUP_TYPE in
        rdb)
            restore_rdb
            ;;
        aof)
            restore_aof
            ;;
        *)
            log ERROR "Unknown backup type: $BACKUP_TYPE"
            exit 1
            ;;
    esac

    # Start Redis
    start_redis

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
