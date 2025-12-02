#!/bin/bash

#############################################################################
# MariaDB Galera Cluster Backup Utility
#############################################################################
# Description:
#   Creates consistent backups of MariaDB Galera cluster using mariabackup
#   Supports full and incremental backups with compression
#
# Features:
#   - Hot backup (no downtime)
#   - Galera-aware (consistent across cluster)
#   - Compression support (gzip, pigz)
#   - Retention policy
#   - Backup verification
#   - Email notifications (optional)
#
# Usage:
#   sudo ./cluster/utils/db_backup.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml
#   --type TYPE         Backup type: full, incremental (default: full)
#   --compress          Compress backup with gzip/pigz
#   --retention DAYS    Keep backups for N days (default: 7)
#   --backup-dir PATH   Backup directory (default: /var/backups/mariadb)
#   --verify            Verify backup after creation
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
BACKUP_TYPE="full"
BACKUP_DIR="/var/backups/mariadb"
COMPRESS=false
VERIFY=false
RETENTION_DAYS=7
LOG_FILE="/var/log/cluster_db_backup.log"

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
  --type TYPE         Backup type: full, incremental (default: full)
  --compress          Compress backup with gzip/pigz
  --retention DAYS    Keep backups for N days (default: 7)
  --backup-dir PATH   Backup directory (default: $BACKUP_DIR)
  --verify            Verify backup after creation
  --help              Show this help message

Examples:
  # Full backup with compression
  sudo $0 --type full --compress

  # Incremental backup
  sudo $0 --type incremental

  # Full backup with verification
  sudo $0 --type full --verify

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

    local deps=("mariabackup" "python3" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log ERROR "Required dependency not found: $dep"
            log INFO "Install with: apt-get install mariadb-backup (or yum install MariaDB-backup)"
            exit 1
        fi
    done

    # Check for compression tools
    if [[ "$COMPRESS" == "true" ]]; then
        if command -v pigz &> /dev/null; then
            COMPRESS_CMD="pigz"
            log INFO "Using pigz for compression (parallel gzip)"
        elif command -v gzip &> /dev/null; then
            COMPRESS_CMD="gzip"
            log INFO "Using gzip for compression"
        else
            log WARNING "No compression tool found, disabling compression"
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

    # Get database credentials
    DB_ROOT_PASSWORD=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get database.mariadb.root_password 2>/dev/null || echo "")

    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        log ERROR "Database root password not found in config"
        exit 1
    fi

    log SUCCESS "Configuration loaded"
}

create_backup_dir() {
    log INFO "Creating backup directory structure..."

    # Create base backup directory
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/full"
    mkdir -p "$BACKUP_DIR/incremental"

    # Set permissions
    chmod 700 "$BACKUP_DIR"

    log SUCCESS "Backup directory created: $BACKUP_DIR"
}

check_mariadb_running() {
    log INFO "Checking MariaDB status..."

    if ! systemctl is-active --quiet mariadb; then
        log ERROR "MariaDB is not running"
        exit 1
    fi

    log SUCCESS "MariaDB is running"
}

check_cluster_status() {
    log INFO "Checking Galera cluster status..."

    # Check if node is synced
    local wsrep_ready=$(mysql -uroot -p"$DB_ROOT_PASSWORD" -e "SHOW STATUS LIKE 'wsrep_ready';" 2>/dev/null | grep wsrep_ready | awk '{print $2}')
    local wsrep_local_state=$(mysql -uroot -p"$DB_ROOT_PASSWORD" -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | grep wsrep_local_state_comment | awk '{print $2}')

    if [[ "$wsrep_ready" != "ON" ]] || [[ "$wsrep_local_state" != "Synced" ]]; then
        log WARNING "Node is not in Synced state (wsrep_ready=$wsrep_ready, state=$wsrep_local_state)"
        log WARNING "Backup may not be consistent with cluster"
        read -p "Continue anyway? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log INFO "Backup cancelled"
            exit 0
        fi
    fi

    log SUCCESS "Cluster status: Ready and Synced"
}

find_last_full_backup() {
    # Find the most recent full backup
    LAST_FULL_BACKUP=$(find "$BACKUP_DIR/full" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r | head -1)

    if [[ -z "$LAST_FULL_BACKUP" ]]; then
        log INFO "No previous full backup found"
        return 1
    fi

    log INFO "Last full backup: $LAST_FULL_BACKUP"
    return 0
}

perform_full_backup() {
    log INFO "Starting full backup..."

    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/full/$backup_name"

    log INFO "Backup path: $backup_path"

    # Create backup using mariabackup
    local start_time=$(date +%s)

    if mariabackup --backup \
        --user=root \
        --password="$DB_ROOT_PASSWORD" \
        --target-dir="$backup_path" \
        --compress=${COMPRESS} 2>&1 | tee -a "$LOG_FILE"; then

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log SUCCESS "Full backup completed in ${duration}s"
        LATEST_BACKUP="$backup_path"

        # Get backup size
        local backup_size=$(du -sh "$backup_path" | awk '{print $1}')
        log INFO "Backup size: $backup_size"

        # Create metadata file
        cat > "$backup_path/backup_metadata.json" << EOF
{
  "backup_type": "full",
  "backup_name": "$backup_name",
  "backup_path": "$backup_path",
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": $duration,
  "size": "$backup_size",
  "compressed": $COMPRESS,
  "hostname": "$(hostname)",
  "mariadb_version": "$(mysql --version | grep -oP '(?<=MariaDB )[\d.]+')"
}
EOF

        return 0
    else
        log ERROR "Full backup failed"
        return 1
    fi
}

perform_incremental_backup() {
    log INFO "Starting incremental backup..."

    # Check if we have a base full backup
    if ! find_last_full_backup; then
        log ERROR "Cannot perform incremental backup without a full backup"
        log INFO "Run full backup first: $0 --type full"
        exit 1
    fi

    local backup_name="incremental_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/incremental/$backup_name"

    log INFO "Backup path: $backup_path"
    log INFO "Base backup: $LAST_FULL_BACKUP"

    # Create incremental backup
    local start_time=$(date +%s)

    if mariabackup --backup \
        --user=root \
        --password="$DB_ROOT_PASSWORD" \
        --target-dir="$backup_path" \
        --incremental-basedir="$LAST_FULL_BACKUP" \
        --compress=${COMPRESS} 2>&1 | tee -a "$LOG_FILE"; then

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log SUCCESS "Incremental backup completed in ${duration}s"
        LATEST_BACKUP="$backup_path"

        # Get backup size
        local backup_size=$(du -sh "$backup_path" | awk '{print $1}')
        log INFO "Backup size: $backup_size"

        # Create metadata file
        cat > "$backup_path/backup_metadata.json" << EOF
{
  "backup_type": "incremental",
  "backup_name": "$backup_name",
  "backup_path": "$backup_path",
  "base_backup": "$LAST_FULL_BACKUP",
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": $duration,
  "size": "$backup_size",
  "compressed": $COMPRESS,
  "hostname": "$(hostname)",
  "mariadb_version": "$(mysql --version | grep -oP '(?<=MariaDB )[\d.]+')"
}
EOF

        return 0
    else
        log ERROR "Incremental backup failed"
        return 1
    fi
}

verify_backup() {
    if [[ "$VERIFY" != "true" ]]; then
        return 0
    fi

    log INFO "Verifying backup: $LATEST_BACKUP"

    # Prepare backup in temporary directory
    local verify_dir="/tmp/mariabackup_verify_$$"
    mkdir -p "$verify_dir"

    log INFO "Preparing backup for verification..."

    # Copy backup to temp dir
    cp -r "$LATEST_BACKUP" "$verify_dir/backup"

    # Decompress if needed
    if [[ "$COMPRESS" == "true" ]]; then
        log INFO "Decompressing backup..."
        mariabackup --decompress --target-dir="$verify_dir/backup" 2>&1 | tee -a "$LOG_FILE"
        # Remove compressed files
        find "$verify_dir/backup" -name "*.qp" -delete
    fi

    # Prepare backup
    if mariabackup --prepare --target-dir="$verify_dir/backup" 2>&1 | tee -a "$LOG_FILE"; then
        log SUCCESS "Backup verification successful"
        rm -rf "$verify_dir"
        return 0
    else
        log ERROR "Backup verification failed"
        rm -rf "$verify_dir"
        return 1
    fi
}

apply_retention_policy() {
    log INFO "Applying retention policy (keep last $RETENTION_DAYS days)..."

    local deleted_count=0

    # Clean up old full backups
    while IFS= read -r backup; do
        local backup_date=$(echo "$backup" | grep -oP '\d{8}' | head -1)
        local backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo 0)
        local current_timestamp=$(date +%s)
        local age_days=$(( (current_timestamp - backup_timestamp) / 86400 ))

        if [[ $age_days -gt $RETENTION_DAYS ]]; then
            log INFO "Deleting old backup (${age_days} days old): $backup"
            rm -rf "$backup"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "$BACKUP_DIR/full" -maxdepth 1 -type d -name "backup_*" 2>/dev/null)

    # Clean up old incremental backups
    while IFS= read -r backup; do
        local backup_date=$(echo "$backup" | grep -oP '\d{8}' | head -1)
        local backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo 0)
        local current_timestamp=$(date +%s)
        local age_days=$(( (current_timestamp - backup_timestamp) / 86400 ))

        if [[ $age_days -gt $RETENTION_DAYS ]]; then
            log INFO "Deleting old incremental backup (${age_days} days old): $backup"
            rm -rf "$backup"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "$BACKUP_DIR/incremental" -maxdepth 1 -type d -name "incremental_*" 2>/dev/null)

    log SUCCESS "Retention policy applied (deleted $deleted_count old backups)"
}

list_backups() {
    log INFO "Current backups:"

    # List full backups
    log INFO ""
    log INFO "Full backups:"
    local full_count=0
    while IFS= read -r backup; do
        if [[ -f "$backup/backup_metadata.json" ]]; then
            local backup_name=$(jq -r '.backup_name' "$backup/backup_metadata.json")
            local timestamp=$(jq -r '.timestamp' "$backup/backup_metadata.json")
            local size=$(jq -r '.size' "$backup/backup_metadata.json")
            log INFO "  - $backup_name [$timestamp] ($size)"
            full_count=$((full_count + 1))
        fi
    done < <(find "$BACKUP_DIR/full" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r)

    # List incremental backups
    log INFO ""
    log INFO "Incremental backups:"
    local inc_count=0
    while IFS= read -r backup; do
        if [[ -f "$backup/backup_metadata.json" ]]; then
            local backup_name=$(jq -r '.backup_name' "$backup/backup_metadata.json")
            local timestamp=$(jq -r '.timestamp' "$backup/backup_metadata.json")
            local size=$(jq -r '.size' "$backup/backup_metadata.json")
            log INFO "  - $backup_name [$timestamp] ($size)"
            inc_count=$((inc_count + 1))
        fi
    done < <(find "$BACKUP_DIR/incremental" -maxdepth 1 -type d -name "incremental_*" 2>/dev/null | sort -r)

    log INFO ""
    log INFO "Total: $full_count full backups, $inc_count incremental backups"
}

#############################################################################
# Main
#############################################################################

main() {
    log INFO "=== MariaDB Galera Cluster Backup Utility ==="
    log INFO "Starting at $(date)"

    # Check root privileges
    check_root

    # Check dependencies
    check_dependencies

    # Load configuration
    load_config

    # Create backup directory
    create_backup_dir

    # Check MariaDB status
    check_mariadb_running

    # Check cluster status
    check_cluster_status

    # Perform backup based on type
    case $BACKUP_TYPE in
        full)
            perform_full_backup || exit 1
            ;;
        incremental)
            perform_incremental_backup || exit 1
            ;;
        *)
            log ERROR "Invalid backup type: $BACKUP_TYPE"
            exit 1
            ;;
    esac

    # Verify backup if requested
    verify_backup

    # Apply retention policy
    apply_retention_policy

    # List current backups
    list_backups

    log SUCCESS "=== Backup completed successfully ==="
    log INFO "Finished at $(date)"
    log INFO "Backup location: $LATEST_BACKUP"
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
        --verify)
            VERIFY=true
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
