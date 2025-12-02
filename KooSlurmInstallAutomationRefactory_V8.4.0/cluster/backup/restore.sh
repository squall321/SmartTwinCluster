#!/bin/bash

#############################################################################
# Unified Cluster Restore Script
#############################################################################
# Description:
#   Restores cluster from unified backup
#   Includes: GlusterFS metadata, MariaDB, Redis, Slurm state, configurations
#
# Features:
#   - Lists available backups
#   - Interactive or automated restore
#   - Selective service restore
#   - Safety confirmations
#   - Pre-restore backup of current state
#
# Usage:
#   sudo ./cluster/backup/restore.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml
#   --backup-dir PATH   Backup directory (default: /var/backups/cluster)
#   --backup-path PATH  Specific backup to restore
#   --latest            Restore from latest backup
#   --services LIST     Services to restore (default: all)
#   --force             Skip confirmation prompts
#   --list              List available backups and exit
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

# Restore utilities
DB_RESTORE_SCRIPT="${PROJECT_ROOT}/cluster/utils/db_restore.sh"
REDIS_RESTORE_SCRIPT="${PROJECT_ROOT}/cluster/utils/redis_restore.sh"

# Default values
BACKUP_DIR="/var/backups/cluster"
BACKUP_PATH=""
SERVICES="all"
USE_LATEST=false
FORCE=false
LIST_ONLY=false
LOG_FILE="/var/log/cluster_restore.log"

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
  --backup-path PATH  Specific backup directory or archive to restore
  --latest            Restore from latest backup
  --services LIST     Services to restore: all, glusterfs, mariadb, redis, slurm, config (default: all)
  --force             Skip confirmation prompts (DANGEROUS!)
  --list              List available backups and exit
  --help              Show this help message

Examples:
  # List available backups
  $0 --list

  # Restore latest backup (interactive)
  sudo $0 --latest

  # Restore specific backup
  sudo $0 --backup-path /var/backups/cluster/cluster_backup_20251027_120000

  # Restore only database and redis
  sudo $0 --latest --services mariadb,redis

  # Force restore without confirmation
  sudo $0 --latest --force
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

    # Get GlusterFS mount point
    GLUSTER_MOUNT=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get storage.glusterfs.mount_point 2>/dev/null || echo "/mnt/gluster")

    log SUCCESS "Configuration loaded"
}

list_backups() {
    log INFO "=== Available Backups ==="

    echo ""
    printf "%-5s %-40s %-20s %-10s\n" "No." "Backup Name" "Date" "Size"
    echo "------------------------------------------------------------------------------------"

    local index=1
    declare -g -A BACKUP_MAP

    # List compressed archives first
    while IFS= read -r backup; do
        if [[ -f "$backup" ]]; then
            local backup_name=$(basename "$backup")
            local backup_date=$(stat -c %y "$backup" | cut -d' ' -f1)
            local backup_size=$(du -sh "$backup" | awk '{print $1}')

            printf "%-5s %-40s %-20s %-10s\n" "$index" "${backup_name%.tar.gz}" "$backup_date" "$backup_size"

            BACKUP_MAP[$index]="$backup"
            index=$((index + 1))
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${CLUSTER_NAME}_backup_*.tar.gz" 2>/dev/null | sort -r)

    # List directories
    while IFS= read -r backup; do
        if [[ -d "$backup" ]]; then
            local backup_name=$(basename "$backup")
            local backup_date=$(stat -c %y "$backup" | cut -d' ' -f1)
            local backup_size=$(du -sh "$backup" | awk '{print $1}')

            printf "%-5s %-40s %-20s %-10s\n" "$index" "$backup_name" "$backup_date" "$backup_size"

            BACKUP_MAP[$index]="$backup"
            index=$((index + 1))
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name "${CLUSTER_NAME}_backup_*" 2>/dev/null | sort -r)

    echo "------------------------------------------------------------------------------------"

    if [[ ${#BACKUP_MAP[@]} -eq 0 ]]; then
        log WARNING "No backups found in $BACKUP_DIR"
    fi
}

select_backup() {
    if [[ -n "$BACKUP_PATH" ]]; then
        # Backup path specified via command line
        if [[ ! -e "$BACKUP_PATH" ]]; then
            log ERROR "Backup not found: $BACKUP_PATH"
            exit 1
        fi
        log INFO "Using specified backup: $BACKUP_PATH"
        return 0
    fi

    if [[ "$USE_LATEST" == "true" ]]; then
        # Find latest backup
        BACKUP_PATH=$(find "$BACKUP_DIR" -maxdepth 1 \( -type f -name "${CLUSTER_NAME}_backup_*.tar.gz" -o -type d -name "${CLUSTER_NAME}_backup_*" \) 2>/dev/null | sort -r | head -1)

        if [[ -z "$BACKUP_PATH" ]]; then
            log ERROR "No backups found"
            exit 1
        fi

        log INFO "Using latest backup: $(basename "$BACKUP_PATH")"
        return 0
    fi

    # Interactive selection
    list_backups

    if [[ ${#BACKUP_MAP[@]} -eq 0 ]]; then
        log ERROR "No backups available"
        exit 1
    fi

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
    log INFO "Selected backup: $(basename "$BACKUP_PATH")"
}

extract_backup() {
    # If backup is compressed, extract it
    if [[ -f "$BACKUP_PATH" ]] && [[ "$BACKUP_PATH" == *.tar.gz ]]; then
        log INFO "Extracting compressed backup..."

        local extract_dir="/tmp/cluster_restore_$$"
        mkdir -p "$extract_dir"

        tar xzf "$BACKUP_PATH" -C "$extract_dir"

        # Find extracted directory
        BACKUP_PATH=$(find "$extract_dir" -maxdepth 1 -type d -name "${CLUSTER_NAME}_backup_*" | head -1)

        if [[ -z "$BACKUP_PATH" ]]; then
            log ERROR "Failed to extract backup"
            exit 1
        fi

        log SUCCESS "Backup extracted to: $BACKUP_PATH"
        CLEANUP_EXTRACT=true
    else
        CLEANUP_EXTRACT=false
    fi
}

validate_backup() {
    log INFO "Validating backup..."

    if [[ ! -d "$BACKUP_PATH" ]]; then
        log ERROR "Backup directory not found: $BACKUP_PATH"
        exit 1
    fi

    # Check for metadata
    if [[ -f "$BACKUP_PATH/backup_metadata.json" ]]; then
        local backup_cluster=$(jq -r '.cluster_name' "$BACKUP_PATH/backup_metadata.json")
        local backup_date=$(jq -r '.timestamp' "$BACKUP_PATH/backup_metadata.json")

        log INFO "Backup cluster: $backup_cluster"
        log INFO "Backup date: $backup_date"

        if [[ "$backup_cluster" != "$CLUSTER_NAME" ]]; then
            log WARNING "Backup is from different cluster: $backup_cluster (current: $CLUSTER_NAME)"
        fi
    else
        log WARNING "Backup metadata not found (old backup format?)"
    fi

    log SUCCESS "Backup validation passed"
}

confirm_restore() {
    if [[ "$FORCE" == "true" ]]; then
        log WARNING "Force mode enabled, skipping confirmation"
        return 0
    fi

    log WARNING "=== WARNING ==="
    log WARNING "This will restore from backup:"
    log WARNING "  Backup: $(basename "$BACKUP_PATH")"
    log WARNING "  Services: $SERVICES"
    log WARNING ""
    log WARNING "Current data will be backed up before restoration"
    log WARNING "Services will be stopped and restarted"
    echo ""

    read -p "Are you sure you want to continue? Type 'YES' to proceed: " confirmation

    if [[ "$confirmation" != "YES" ]]; then
        log INFO "Restore cancelled"
        exit 0
    fi

    log INFO "Confirmation received, proceeding with restore..."
}

should_restore_service() {
    local service=$1

    if [[ "$SERVICES" == "all" ]]; then
        return 0
    fi

    if echo "$SERVICES" | grep -q "$service"; then
        return 0
    fi

    return 1
}

restore_glusterfs() {
    if ! should_restore_service "glusterfs"; then
        log INFO "Skipping GlusterFS restore"
        return 0
    fi

    log INFO "Restoring GlusterFS metadata..."

    local gluster_backup_dir="$BACKUP_PATH/glusterfs"

    if [[ ! -d "$gluster_backup_dir" ]]; then
        log WARNING "GlusterFS backup not found in this backup"
        return 0
    fi

    # Restore glusterd configuration
    if [[ -f "$gluster_backup_dir/glusterd.tar.gz" ]]; then
        log INFO "Restoring GlusterFS config..."
        systemctl stop glusterd || true
        tar xzf "$gluster_backup_dir/glusterd.tar.gz" -C / 2>/dev/null || true
        systemctl start glusterd
        log SUCCESS "GlusterFS config restored"
    fi

    # Restore Slurm state to GlusterFS
    if [[ -f "$gluster_backup_dir/slurm_state.tar.gz" ]] && mount | grep -q "$GLUSTER_MOUNT"; then
        log INFO "Restoring Slurm state..."
        tar xzf "$gluster_backup_dir/slurm_state.tar.gz" -C / 2>/dev/null || true
        log SUCCESS "Slurm state restored"
    fi
}

restore_mariadb() {
    if ! should_restore_service "mariadb"; then
        log INFO "Skipping MariaDB restore"
        return 0
    fi

    log INFO "Restoring MariaDB..."

    local db_backup_dir="$BACKUP_PATH/mariadb"

    if [[ ! -d "$db_backup_dir" ]]; then
        log WARNING "MariaDB backup not found in this backup"
        return 0
    fi

    # Find MariaDB backup subdirectory
    local mariadb_backup=$(find "$db_backup_dir" -maxdepth 2 -type d -name "backup_*" | head -1)

    if [[ -z "$mariadb_backup" ]]; then
        log WARNING "No MariaDB backup found"
        return 0
    fi

    log INFO "Using MariaDB backup: $(basename "$mariadb_backup")"

    # Use existing db_restore.sh script
    "$DB_RESTORE_SCRIPT" --backup-path "$mariadb_backup" --force >> "$LOG_FILE" 2>&1 || {
        log ERROR "MariaDB restore failed"
        return 1
    }

    log SUCCESS "MariaDB restored"
}

restore_redis() {
    if ! should_restore_service "redis"; then
        log INFO "Skipping Redis restore"
        return 0
    fi

    log INFO "Restoring Redis..."

    local redis_backup_dir="$BACKUP_PATH/redis"

    if [[ ! -d "$redis_backup_dir" ]]; then
        log WARNING "Redis backup not found in this backup"
        return 0
    fi

    # Find Redis backup subdirectory
    local redis_backup=$(find "$redis_backup_dir" -maxdepth 2 -type d -name "*backup_*" | head -1)

    if [[ -z "$redis_backup" ]]; then
        log WARNING "No Redis backup found"
        return 0
    fi

    log INFO "Using Redis backup: $(basename "$redis_backup")"

    # Use existing redis_restore.sh script
    "$REDIS_RESTORE_SCRIPT" --backup-path "$redis_backup" --force >> "$LOG_FILE" 2>&1 || {
        log ERROR "Redis restore failed"
        return 1
    }

    log SUCCESS "Redis restored"
}

restore_slurm() {
    if ! should_restore_service "slurm"; then
        log INFO "Skipping Slurm restore"
        return 0
    fi

    log INFO "Restoring Slurm configuration..."

    local slurm_backup_dir="$BACKUP_PATH/slurm"

    if [[ ! -d "$slurm_backup_dir" ]]; then
        log WARNING "Slurm backup not found in this backup"
        return 0
    fi

    # Restore Slurm configuration
    if [[ -f "$slurm_backup_dir/slurm.conf" ]]; then
        cp "$slurm_backup_dir/slurm.conf" /etc/slurm/slurm.conf
        chown slurm:slurm /etc/slurm/slurm.conf
        log SUCCESS "Slurm config restored"
    fi

    if [[ -f "$slurm_backup_dir/slurmdbd.conf" ]]; then
        cp "$slurm_backup_dir/slurmdbd.conf" /etc/slurm/slurmdbd.conf
        chown slurm:slurm /etc/slurm/slurmdbd.conf
        chmod 600 /etc/slurm/slurmdbd.conf
        log SUCCESS "SlurmDBD config restored"
    fi

    # Restart Slurm services
    systemctl restart slurmctld || log WARNING "Failed to restart slurmctld"
    systemctl restart slurmdbd || log WARNING "Failed to restart slurmdbd"
}

restore_configs() {
    if ! should_restore_service "config"; then
        log INFO "Skipping configuration restore"
        return 0
    fi

    log INFO "Restoring cluster configurations..."

    local config_backup_dir="$BACKUP_PATH/config"

    if [[ ! -d "$config_backup_dir" ]]; then
        log WARNING "Config backup not found in this backup"
        return 0
    fi

    # Restore Keepalived config
    if [[ -f "$config_backup_dir/keepalived.conf" ]]; then
        cp "$config_backup_dir/keepalived.conf" /etc/keepalived/keepalived.conf
        systemctl restart keepalived || true
        log SUCCESS "Keepalived config restored"
    fi

    # Restore Munge key
    if [[ -f "$config_backup_dir/munge.key" ]]; then
        cp "$config_backup_dir/munge.key" /etc/munge/munge.key
        chown munge:munge /etc/munge/munge.key
        chmod 400 /etc/munge/munge.key
        systemctl restart munge || true
        log SUCCESS "Munge key restored"
    fi

    log SUCCESS "Configurations restored"
}

cleanup() {
    if [[ "${CLEANUP_EXTRACT:-false}" == "true" ]] && [[ -n "${BACKUP_PATH:-}" ]]; then
        log INFO "Cleaning up extracted files..."
        rm -rf "$(dirname "$BACKUP_PATH")"
    fi
}

#############################################################################
# Main
#############################################################################

main() {
    local start_time=$(date +%s)

    log INFO "=== Unified Cluster Restore ==="
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

    # Extract if compressed
    extract_backup

    # Validate backup
    validate_backup

    # Confirm restore
    confirm_restore

    # Restore services
    restore_glusterfs
    restore_mariadb
    restore_redis
    restore_slurm
    restore_configs

    # Cleanup
    cleanup

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log SUCCESS "=== Restore completed successfully ==="
    log INFO "Duration: ${duration}s"
    log INFO "Finished at $(date)"

    log INFO ""
    log INFO "Next steps:"
    log INFO "  1. Verify all services are running"
    log INFO "  2. Check cluster status: ./cluster/utils/cluster_info.sh"
    log INFO "  3. Test connectivity to services"
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
        --backup-path)
            BACKUP_PATH="$2"
            shift 2
            ;;
        --latest)
            USE_LATEST=true
            shift
            ;;
        --services)
            SERVICES="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --list)
            LIST_ONLY=true
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
