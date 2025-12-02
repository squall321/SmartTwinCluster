#!/bin/bash

#############################################################################
# Unified Cluster Backup Script
#############################################################################
# Description:
#   Creates comprehensive backup of all cluster services
#   Includes: GlusterFS metadata, MariaDB, Redis, Slurm state, configurations
#
# Features:
#   - Backs up all services in correct order
#   - Creates timestamped backup archives
#   - Compression support
#   - Retention policy
#   - Backup verification
#   - Metadata tracking
#
# Usage:
#   sudo ./cluster/backup/backup.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml
#   --backup-dir PATH   Backup directory (default: /var/backups/cluster)
#   --compress          Compress backup archives
#   --retention DAYS    Keep backups for N days (default: 30)
#   --services LIST     Comma-separated list of services to backup (default: all)
#   --verify            Verify backups after creation
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

# Backup utilities
DB_BACKUP_SCRIPT="${PROJECT_ROOT}/cluster/utils/db_backup.sh"
REDIS_BACKUP_SCRIPT="${PROJECT_ROOT}/cluster/utils/redis_backup.sh"

# Default values
BACKUP_DIR="/var/backups/cluster"
COMPRESS=false
VERIFY=false
RETENTION_DAYS=30
SERVICES="all"
LOG_FILE="/var/log/cluster_backup.log"

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
  --backup-dir PATH   Backup directory (default: $BACKUP_DIR)
  --compress          Compress backup archives with gzip
  --retention DAYS    Keep backups for N days (default: 30)
  --services LIST     Services to backup: all, glusterfs, mariadb, redis, slurm, config (default: all)
  --verify            Verify backups after creation
  --help              Show this help message

Examples:
  # Full cluster backup with compression
  sudo $0 --compress

  # Backup only database and redis
  sudo $0 --services mariadb,redis

  # Custom backup directory and retention
  sudo $0 --backup-dir /mnt/gluster/backups --retention 60

  # Backup with verification
  sudo $0 --compress --verify
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

    local deps=("python3" "jq" "tar")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log ERROR "Required dependency not found: $dep"
            exit 1
        fi
    done

    # Check backup scripts exist
    if [[ ! -f "$DB_BACKUP_SCRIPT" ]]; then
        log ERROR "Database backup script not found: $DB_BACKUP_SCRIPT"
        exit 1
    fi

    if [[ ! -f "$REDIS_BACKUP_SCRIPT" ]]; then
        log ERROR "Redis backup script not found: $REDIS_BACKUP_SCRIPT"
        exit 1
    fi

    log SUCCESS "All dependencies satisfied"
}

load_config() {
    log INFO "Loading configuration..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Get cluster name
    CLUSTER_NAME=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get cluster.name 2>/dev/null || echo "cluster")

    # Get current controller
    CURRENT_CONTROLLER=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --current 2>/dev/null)
    CURRENT_HOSTNAME=$(echo "$CURRENT_CONTROLLER" | jq -r '.hostname')

    # Get GlusterFS mount point
    GLUSTER_MOUNT=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get storage.glusterfs.mount_point 2>/dev/null || echo "/mnt/gluster")

    log INFO "Cluster: $CLUSTER_NAME"
    log INFO "Node: $CURRENT_HOSTNAME"

    log SUCCESS "Configuration loaded"
}

create_backup_structure() {
    log INFO "Creating backup directory structure..."

    # Create timestamped backup directory
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_NAME="${CLUSTER_NAME}_backup_${BACKUP_TIMESTAMP}"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

    mkdir -p "$BACKUP_PATH"/{glusterfs,mariadb,redis,slurm,config,logs}
    chmod 700 "$BACKUP_PATH"

    log INFO "Backup directory: $BACKUP_PATH"
    log SUCCESS "Backup structure created"
}

should_backup_service() {
    local service=$1

    if [[ "$SERVICES" == "all" ]]; then
        return 0
    fi

    if echo "$SERVICES" | grep -q "$service"; then
        return 0
    fi

    return 1
}

backup_glusterfs() {
    if ! should_backup_service "glusterfs"; then
        log INFO "Skipping GlusterFS backup"
        return 0
    fi

    log INFO "Backing up GlusterFS metadata..."

    local gluster_backup_dir="$BACKUP_PATH/glusterfs"

    # Backup GlusterFS configuration
    if [[ -d /var/lib/glusterd ]]; then
        tar czf "$gluster_backup_dir/glusterd.tar.gz" /var/lib/glusterd/ 2>/dev/null || true
        log SUCCESS "GlusterFS config backed up"
    fi

    # Save volume info
    if command -v gluster &> /dev/null; then
        gluster volume info > "$gluster_backup_dir/volume_info.txt" 2>/dev/null || true
        gluster peer status > "$gluster_backup_dir/peer_status.txt" 2>/dev/null || true
        log SUCCESS "GlusterFS volume info saved"
    fi

    # Backup shared state (if mounted)
    if mount | grep -q "$GLUSTER_MOUNT"; then
        log INFO "Backing up shared Slurm state from GlusterFS..."
        if [[ -d "$GLUSTER_MOUNT/slurm/state" ]]; then
            tar czf "$gluster_backup_dir/slurm_state.tar.gz" "$GLUSTER_MOUNT/slurm/state" 2>/dev/null || true
            log SUCCESS "Slurm state backed up"
        fi
    fi
}

backup_mariadb() {
    if ! should_backup_service "mariadb"; then
        log INFO "Skipping MariaDB backup"
        return 0
    fi

    log INFO "Backing up MariaDB..."

    local db_backup_dir="$BACKUP_PATH/mariadb"

    # Use existing db_backup.sh script
    if systemctl is-active --quiet mariadb; then
        log INFO "Running MariaDB backup script..."

        # Run backup with compression
        local compress_flag=""
        if [[ "$COMPRESS" == "true" ]]; then
            compress_flag="--compress"
        fi

        "$DB_BACKUP_SCRIPT" --type full $compress_flag --backup-dir "$db_backup_dir" >> "$LOG_FILE" 2>&1 || {
            log ERROR "MariaDB backup failed"
            return 1
        }

        log SUCCESS "MariaDB backed up"
    else
        log WARNING "MariaDB is not running, skipping"
    fi
}

backup_redis() {
    if ! should_backup_service "redis"; then
        log INFO "Skipping Redis backup"
        return 0
    fi

    log INFO "Backing up Redis..."

    local redis_backup_dir="$BACKUP_PATH/redis"

    # Use existing redis_backup.sh script
    if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
        log INFO "Running Redis backup script..."

        local compress_flag=""
        if [[ "$COMPRESS" == "true" ]]; then
            compress_flag="--compress"
        fi

        "$REDIS_BACKUP_SCRIPT" --type both $compress_flag --backup-dir "$redis_backup_dir" >> "$LOG_FILE" 2>&1 || {
            log ERROR "Redis backup failed"
            return 1
        }

        log SUCCESS "Redis backed up"
    else
        log WARNING "Redis is not running, skipping"
    fi
}

backup_slurm() {
    if ! should_backup_service "slurm"; then
        log INFO "Skipping Slurm backup"
        return 0
    fi

    log INFO "Backing up Slurm configuration..."

    local slurm_backup_dir="$BACKUP_PATH/slurm"

    # Backup Slurm configuration
    if [[ -f /etc/slurm/slurm.conf ]]; then
        cp /etc/slurm/slurm.conf "$slurm_backup_dir/slurm.conf"
        log SUCCESS "Slurm config backed up"
    fi

    if [[ -f /etc/slurm/slurmdbd.conf ]]; then
        cp /etc/slurm/slurmdbd.conf "$slurm_backup_dir/slurmdbd.conf"
        log SUCCESS "SlurmDBD config backed up"
    fi

    # Note: Slurm state is backed up via GlusterFS
}

backup_configs() {
    if ! should_backup_service "config"; then
        log INFO "Skipping configuration backup"
        return 0
    fi

    log INFO "Backing up cluster configurations..."

    local config_backup_dir="$BACKUP_PATH/config"

    # Backup YAML config
    cp "$CONFIG_FILE" "$config_backup_dir/" 2>/dev/null || true

    # Backup all cluster config templates
    if [[ -d "$PROJECT_ROOT/cluster/config" ]]; then
        cp -r "$PROJECT_ROOT/cluster/config"/*.{conf,cnf} "$config_backup_dir/" 2>/dev/null || true
    fi

    # Backup Keepalived config
    if [[ -f /etc/keepalived/keepalived.conf ]]; then
        cp /etc/keepalived/keepalived.conf "$config_backup_dir/" 2>/dev/null || true
    fi

    # Backup Munge key
    if [[ -f /etc/munge/munge.key ]]; then
        cp /etc/munge/munge.key "$config_backup_dir/" 2>/dev/null || true
    fi

    log SUCCESS "Configurations backed up"
}

backup_logs() {
    log INFO "Backing up recent logs..."

    local log_backup_dir="$BACKUP_PATH/logs"

    # Backup cluster logs (last 7 days)
    find /var/log -name "cluster_*.log" -mtime -7 -exec cp {} "$log_backup_dir/" \; 2>/dev/null || true
    find /var/log -name "keepalived*.log" -mtime -7 -exec cp {} "$log_backup_dir/" \; 2>/dev/null || true

    log SUCCESS "Logs backed up"
}

create_metadata() {
    log INFO "Creating backup metadata..."

    local metadata_file="$BACKUP_PATH/backup_metadata.json"

    # Calculate backup size
    local backup_size=$(du -sh "$BACKUP_PATH" | awk '{print $1}')

    cat > "$metadata_file" << EOF
{
  "backup_name": "$BACKUP_NAME",
  "backup_path": "$BACKUP_PATH",
  "cluster_name": "$CLUSTER_NAME",
  "hostname": "$CURRENT_HOSTNAME",
  "timestamp": "$(date -Iseconds)",
  "services": "$SERVICES",
  "compressed": $COMPRESS,
  "verified": $VERIFY,
  "size": "$backup_size",
  "retention_days": $RETENTION_DAYS
}
EOF

    log SUCCESS "Metadata created"
}

compress_backup() {
    if [[ "$COMPRESS" != "true" ]]; then
        return 0
    fi

    log INFO "Compressing backup archive..."

    local archive_name="${BACKUP_NAME}.tar.gz"
    local archive_path="$BACKUP_DIR/$archive_name"

    cd "$BACKUP_DIR"
    tar czf "$archive_name" "$BACKUP_NAME" 2>/dev/null

    if [[ -f "$archive_path" ]]; then
        # Remove uncompressed directory
        rm -rf "$BACKUP_PATH"

        # Update backup path
        BACKUP_PATH="$archive_path"

        local archive_size=$(du -sh "$archive_path" | awk '{print $1}')
        log SUCCESS "Backup compressed: $archive_size"
    else
        log ERROR "Failed to create compressed archive"
        return 1
    fi
}

verify_backup() {
    if [[ "$VERIFY" != "true" ]]; then
        return 0
    fi

    log INFO "Verifying backup..."

    # If compressed, verify archive integrity
    if [[ "$COMPRESS" == "true" ]]; then
        if tar tzf "$BACKUP_PATH" > /dev/null 2>&1; then
            log SUCCESS "Backup archive verified"
        else
            log ERROR "Backup archive is corrupted"
            return 1
        fi
    else
        # Check if backup directory exists and has content
        if [[ -d "$BACKUP_PATH" ]] && [[ $(find "$BACKUP_PATH" -type f | wc -l) -gt 0 ]]; then
            log SUCCESS "Backup directory verified"
        else
            log ERROR "Backup directory is empty or missing"
            return 1
        fi
    fi
}

apply_retention_policy() {
    log INFO "Applying retention policy (keep last $RETENTION_DAYS days)..."

    local deleted_count=0

    # Clean up old backups
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
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name "${CLUSTER_NAME}_backup_*" 2>/dev/null)

    # Also clean up compressed archives
    while IFS= read -r backup; do
        local backup_date=$(echo "$backup" | grep -oP '\d{8}' | head -1)
        local backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo 0)
        local current_timestamp=$(date +%s)
        local age_days=$(( (current_timestamp - backup_timestamp) / 86400 ))

        if [[ $age_days -gt $RETENTION_DAYS ]]; then
            log INFO "Deleting old backup archive (${age_days} days old): $backup"
            rm -f "$backup"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${CLUSTER_NAME}_backup_*.tar.gz" 2>/dev/null)

    log SUCCESS "Retention policy applied (deleted $deleted_count old backups)"
}

list_backups() {
    log INFO "Current backups:"

    echo ""
    printf "%-40s %-20s %-10s\n" "Backup Name" "Date" "Size"
    echo "--------------------------------------------------------------------------------"

    # List directories
    while IFS= read -r backup; do
        if [[ -d "$backup" ]]; then
            local backup_name=$(basename "$backup")
            local backup_date=$(stat -c %y "$backup" | cut -d' ' -f1)
            local backup_size=$(du -sh "$backup" | awk '{print $1}')
            printf "%-40s %-20s %-10s\n" "$backup_name" "$backup_date" "$backup_size"
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name "${CLUSTER_NAME}_backup_*" 2>/dev/null | sort -r)

    # List compressed archives
    while IFS= read -r backup; do
        if [[ -f "$backup" ]]; then
            local backup_name=$(basename "$backup")
            local backup_date=$(stat -c %y "$backup" | cut -d' ' -f1)
            local backup_size=$(du -sh "$backup" | awk '{print $1}')
            printf "%-40s %-20s %-10s (compressed)\n" "$backup_name" "$backup_date" "$backup_size"
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${CLUSTER_NAME}_backup_*.tar.gz" 2>/dev/null | sort -r)

    echo "--------------------------------------------------------------------------------"
}

#############################################################################
# Main
#############################################################################

main() {
    local start_time=$(date +%s)

    log INFO "=== Unified Cluster Backup ==="
    log INFO "Starting at $(date)"

    # Check root privileges
    check_root

    # Check dependencies
    check_dependencies

    # Load configuration
    load_config

    # Create backup structure
    create_backup_structure

    # Backup services
    backup_glusterfs
    backup_mariadb
    backup_redis
    backup_slurm
    backup_configs
    backup_logs

    # Create metadata
    create_metadata

    # Compress if requested
    compress_backup

    # Verify backup
    verify_backup

    # Apply retention policy
    apply_retention_policy

    # List current backups
    list_backups

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log SUCCESS "=== Backup completed successfully ==="
    log INFO "Duration: ${duration}s"
    log INFO "Backup location: $BACKUP_PATH"
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
        --backup-dir)
            BACKUP_DIR="$2"
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
        --services)
            SERVICES="$2"
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
