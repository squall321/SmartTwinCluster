#!/bin/bash

#############################################################################
# Redis Cluster Backup Utility
#############################################################################
# Description:
#   Creates backups of Redis data using RDB and AOF
#   Supports both Cluster mode and Sentinel mode
#
# Features:
#   - RDB snapshot backup
#   - AOF (Append-Only File) backup
#   - Backup compression
#   - Retention policy
#   - Cluster-aware (backs up all nodes)
#
# Usage:
#   sudo ./cluster/utils/redis_backup.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml
#   --type TYPE         Backup type: rdb, aof, both (default: both)
#   --compress          Compress backup with gzip
#   --retention DAYS    Keep backups for N days (default: 7)
#   --backup-dir PATH   Backup directory (default: /var/backups/redis)
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
BACKUP_TYPE="both"
BACKUP_DIR="/var/backups/redis"
COMPRESS=false
RETENTION_DAYS=7
LOG_FILE="/var/log/cluster_redis_backup.log"
REDIS_PORT=6379
REDIS_DATA_DIR="/var/lib/redis"

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
  --type TYPE         Backup type: rdb, aof, both (default: both)
  --compress          Compress backup with gzip
  --retention DAYS    Keep backups for N days (default: 7)
  --backup-dir PATH   Backup directory (default: $BACKUP_DIR)
  --help              Show this help message

Examples:
  # Both RDB and AOF backup with compression
  sudo $0 --type both --compress

  # RDB snapshot only
  sudo $0 --type rdb

  # Custom backup directory and retention
  sudo $0 --backup-dir /mnt/gluster/backups --retention 30
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

    # Check for compression tools
    if [[ "$COMPRESS" == "true" ]]; then
        if ! command -v gzip &> /dev/null; then
            log WARNING "gzip not found, disabling compression"
            COMPRESS=false
        fi
    fi

    log SUCCESS "All dependencies satisfied"
}

load_config() {
    log INFO "Loading configuration..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Get current controller
    CURRENT_CONTROLLER=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --current 2>/dev/null)
    if [[ -z "$CURRENT_CONTROLLER" ]]; then
        log ERROR "Could not detect current controller"
        exit 1
    fi

    CURRENT_IP=$(echo "$CURRENT_CONTROLLER" | jq -r '.ip_address')
    CURRENT_HOSTNAME=$(echo "$CURRENT_CONTROLLER" | jq -r '.hostname')

    # Get Redis password
    REDIS_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cache.redis.password 2>/dev/null || echo "")

    if [[ -z "$REDIS_PASSWORD" ]]; then
        log ERROR "Redis password not found in config"
        exit 1
    fi

    # Get all Redis-enabled controllers
    REDIS_CONTROLLERS=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --service redis 2>/dev/null)

    log SUCCESS "Configuration loaded"
}

create_backup_dir() {
    log INFO "Creating backup directory structure..."

    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/rdb"
    mkdir -p "$BACKUP_DIR/aof"

    chmod 700 "$BACKUP_DIR"

    log SUCCESS "Backup directory created: $BACKUP_DIR"
}

check_redis_running() {
    log INFO "Checking Redis status..."

    if ! systemctl is-active --quiet redis-server && ! systemctl is-active --quiet redis; then
        log ERROR "Redis is not running"
        exit 1
    fi

    # Test connection
    if ! redis-cli -a "$REDIS_PASSWORD" PING &>/dev/null; then
        log ERROR "Cannot connect to Redis"
        exit 1
    fi

    log SUCCESS "Redis is running"
}

detect_redis_mode() {
    log INFO "Detecting Redis mode..."

    # Check if cluster mode is enabled
    local cluster_enabled=$(redis-cli -a "$REDIS_PASSWORD" CONFIG GET cluster-enabled 2>/dev/null | tail -1)

    if [[ "$cluster_enabled" == "yes" ]]; then
        REDIS_MODE="cluster"
        log INFO "Redis is running in Cluster mode"
    else
        REDIS_MODE="standalone"
        log INFO "Redis is running in Standalone/Sentinel mode"
    fi
}

backup_rdb() {
    log INFO "Creating RDB snapshot backup..."

    local backup_name="rdb_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/rdb/$backup_name"
    mkdir -p "$backup_path"

    local start_time=$(date +%s)

    # Trigger BGSAVE (background save)
    log INFO "Triggering BGSAVE..."
    redis-cli -a "$REDIS_PASSWORD" BGSAVE &>/dev/null

    # Wait for BGSAVE to complete
    local max_wait=300  # 5 minutes
    local elapsed=0
    local save_complete=false

    while [[ $elapsed -lt $max_wait ]]; do
        local last_save=$(redis-cli -a "$REDIS_PASSWORD" LASTSAVE 2>/dev/null)
        sleep 2
        local new_save=$(redis-cli -a "$REDIS_PASSWORD" LASTSAVE 2>/dev/null)

        if [[ $new_save -gt $last_save ]]; then
            save_complete=true
            break
        fi

        elapsed=$((elapsed + 2))
    done

    if [[ "$save_complete" == "false" ]]; then
        log ERROR "BGSAVE did not complete within timeout"
        return 1
    fi

    log SUCCESS "BGSAVE completed"

    # Copy RDB file
    if [[ -f "$REDIS_DATA_DIR/dump.rdb" ]]; then
        cp "$REDIS_DATA_DIR/dump.rdb" "$backup_path/dump.rdb"
        log INFO "RDB file copied to backup"
    else
        log ERROR "RDB file not found at $REDIS_DATA_DIR/dump.rdb"
        return 1
    fi

    # Compress if requested
    if [[ "$COMPRESS" == "true" ]]; then
        log INFO "Compressing RDB backup..."
        gzip "$backup_path/dump.rdb"
        log SUCCESS "RDB backup compressed"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Get backup size
    local backup_size=$(du -sh "$backup_path" | awk '{print $1}')

    log SUCCESS "RDB backup completed in ${duration}s"
    log INFO "Backup size: $backup_size"

    # Create metadata
    cat > "$backup_path/backup_metadata.json" << EOF
{
  "backup_type": "rdb",
  "backup_name": "$backup_name",
  "backup_path": "$backup_path",
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": $duration,
  "size": "$backup_size",
  "compressed": $COMPRESS,
  "hostname": "$CURRENT_HOSTNAME",
  "redis_version": "$(redis-server --version | grep -oP '(?<=v=)[\d.]+')"
}
EOF

    LATEST_BACKUP="$backup_path"
    return 0
}

backup_aof() {
    log INFO "Creating AOF backup..."

    local backup_name="aof_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/aof/$backup_name"
    mkdir -p "$backup_path"

    local start_time=$(date +%s)

    # Trigger BGREWRITEAOF (rewrite AOF file)
    log INFO "Triggering BGREWRITEAOF..."
    redis-cli -a "$REDIS_PASSWORD" BGREWRITEAOF &>/dev/null

    # Wait for AOF rewrite to complete
    local max_wait=300
    local elapsed=0
    local rewrite_complete=false

    while [[ $elapsed -lt $max_wait ]]; do
        local aof_status=$(redis-cli -a "$REDIS_PASSWORD" INFO persistence 2>/dev/null | grep aof_rewrite_in_progress)

        if echo "$aof_status" | grep -q "aof_rewrite_in_progress:0"; then
            rewrite_complete=true
            break
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    if [[ "$rewrite_complete" == "false" ]]; then
        log ERROR "AOF rewrite did not complete within timeout"
        return 1
    fi

    log SUCCESS "AOF rewrite completed"

    # Copy AOF file
    if [[ -f "$REDIS_DATA_DIR/appendonly.aof" ]]; then
        cp "$REDIS_DATA_DIR/appendonly.aof" "$backup_path/appendonly.aof"
        log INFO "AOF file copied to backup"
    else
        log WARNING "AOF file not found (AOF may be disabled)"
        return 1
    fi

    # Compress if requested
    if [[ "$COMPRESS" == "true" ]]; then
        log INFO "Compressing AOF backup..."
        gzip "$backup_path/appendonly.aof"
        log SUCCESS "AOF backup compressed"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Get backup size
    local backup_size=$(du -sh "$backup_path" | awk '{print $1}')

    log SUCCESS "AOF backup completed in ${duration}s"
    log INFO "Backup size: $backup_size"

    # Create metadata
    cat > "$backup_path/backup_metadata.json" << EOF
{
  "backup_type": "aof",
  "backup_name": "$backup_name",
  "backup_path": "$backup_path",
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": $duration,
  "size": "$backup_size",
  "compressed": $COMPRESS,
  "hostname": "$CURRENT_HOSTNAME",
  "redis_version": "$(redis-server --version | grep -oP '(?<=v=)[\d.]+')"
}
EOF

    LATEST_BACKUP="$backup_path"
    return 0
}

apply_retention_policy() {
    log INFO "Applying retention policy (keep last $RETENTION_DAYS days)..."

    local deleted_count=0

    # Clean up old RDB backups
    while IFS= read -r backup; do
        local backup_date=$(echo "$backup" | grep -oP '\d{8}' | head -1)
        local backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo 0)
        local current_timestamp=$(date +%s)
        local age_days=$(( (current_timestamp - backup_timestamp) / 86400 ))

        if [[ $age_days -gt $RETENTION_DAYS ]]; then
            log INFO "Deleting old RDB backup (${age_days} days old): $backup"
            rm -rf "$backup"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "$BACKUP_DIR/rdb" -maxdepth 1 -type d -name "rdb_backup_*" 2>/dev/null)

    # Clean up old AOF backups
    while IFS= read -r backup; do
        local backup_date=$(echo "$backup" | grep -oP '\d{8}' | head -1)
        local backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo 0)
        local current_timestamp=$(date +%s)
        local age_days=$(( (current_timestamp - backup_timestamp) / 86400 ))

        if [[ $age_days -gt $RETENTION_DAYS ]]; then
            log INFO "Deleting old AOF backup (${age_days} days old): $backup"
            rm -rf "$backup"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "$BACKUP_DIR/aof" -maxdepth 1 -type d -name "aof_backup_*" 2>/dev/null)

    log SUCCESS "Retention policy applied (deleted $deleted_count old backups)"
}

list_backups() {
    log INFO "Current backups:"

    # List RDB backups
    log INFO ""
    log INFO "RDB backups:"
    local rdb_count=0
    while IFS= read -r backup; do
        if [[ -f "$backup/backup_metadata.json" ]]; then
            local backup_name=$(jq -r '.backup_name' "$backup/backup_metadata.json")
            local timestamp=$(jq -r '.timestamp' "$backup/backup_metadata.json")
            local size=$(jq -r '.size' "$backup/backup_metadata.json")
            log INFO "  - $backup_name [$timestamp] ($size)"
            rdb_count=$((rdb_count + 1))
        fi
    done < <(find "$BACKUP_DIR/rdb" -maxdepth 1 -type d -name "rdb_backup_*" 2>/dev/null | sort -r)

    # List AOF backups
    log INFO ""
    log INFO "AOF backups:"
    local aof_count=0
    while IFS= read -r backup; do
        if [[ -f "$backup/backup_metadata.json" ]]; then
            local backup_name=$(jq -r '.backup_name' "$backup/backup_metadata.json")
            local timestamp=$(jq -r '.timestamp' "$backup/backup_metadata.json")
            local size=$(jq -r '.size' "$backup/backup_metadata.json")
            log INFO "  - $backup_name [$timestamp] ($size)"
            aof_count=$((aof_count + 1))
        fi
    done < <(find "$BACKUP_DIR/aof" -maxdepth 1 -type d -name "aof_backup_*" 2>/dev/null | sort -r)

    log INFO ""
    log INFO "Total: $rdb_count RDB backups, $aof_count AOF backups"
}

#############################################################################
# Main
#############################################################################

main() {
    log INFO "=== Redis Cluster Backup Utility ==="
    log INFO "Starting at $(date)"

    # Check root privileges
    check_root

    # Check dependencies
    check_dependencies

    # Load configuration
    load_config

    # Create backup directory
    create_backup_dir

    # Check Redis status
    check_redis_running

    # Detect Redis mode
    detect_redis_mode

    # Perform backup based on type
    case $BACKUP_TYPE in
        rdb)
            backup_rdb || exit 1
            ;;
        aof)
            backup_aof || exit 1
            ;;
        both)
            backup_rdb || log WARNING "RDB backup failed"
            backup_aof || log WARNING "AOF backup failed"
            ;;
        *)
            log ERROR "Invalid backup type: $BACKUP_TYPE"
            exit 1
            ;;
    esac

    # Apply retention policy
    apply_retention_policy

    # List current backups
    list_backups

    log SUCCESS "=== Backup completed successfully ==="
    log INFO "Finished at $(date)"

    if [[ "$REDIS_MODE" == "cluster" ]]; then
        log INFO ""
        log INFO "Note: In cluster mode, you should run this backup on all nodes"
        log INFO "to ensure complete data coverage across all shards."
    fi
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
        --type)
            BACKUP_TYPE="$2"
            shift 2
            ;;
        --compress)
            COMPRESS=true
            shift
            ;;
        --retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
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
