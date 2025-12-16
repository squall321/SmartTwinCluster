#!/bin/bash
###############################################################################
# Phase 0: GlusterFS Storage Setup
#
# Purpose: Setup GlusterFS cluster for shared storage
# - Automatic installation
# - Peer connection
# - Volume creation/join
# - Mount configuration
#
# Usage:
#   ./phase0_storage.sh [--config CONFIG_PATH] [--bootstrap|--join] [--dry-run]
###############################################################################

set -euo pipefail

# Default values
CONFIG_PATH="../my_multihead_cluster.yaml"
MODE="auto"  # auto, bootstrap, join
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER_PY="${SCRIPT_DIR}/../config/parser.py"
DISCOVERY_SH="${SCRIPT_DIR}/../discovery/auto_discovery.sh"
LOG_FILE="/var/log/cluster_storage_setup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"

    case $level in
        ERROR)
            echo -e "${RED}✗ $message${NC}" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}✓ $message${NC}"
            ;;
        INFO)
            echo -e "${CYAN}ℹ $message${NC}"
            ;;
        WARNING)
            echo -e "${YELLOW}⚠ $message${NC}"
            ;;
    esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --bootstrap)
            MODE="bootstrap"
            shift
            ;;
        --join)
            MODE="join"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
  --config PATH     Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)
  --bootstrap       Force bootstrap mode (create new cluster)
  --join            Force join mode (join existing cluster)
  --dry-run         Show what would be done without executing
  --help            Show this help message

Examples:
  # Auto mode (detect and decide)
  $0 --config ../my_multihead_cluster.yaml

  # Bootstrap new cluster
  $0 --bootstrap

  # Join existing cluster
  $0 --join
EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check root privileges
if [[ $EUID -ne 0 && $DRY_RUN == false ]]; then
   log "ERROR" "This script must be run as root (use sudo)"
   exit 1
fi

# Check if parser.py exists
if [[ ! -f "$PARSER_PY" ]]; then
    log "ERROR" "parser.py not found at $PARSER_PY"
    exit 1
fi

# Check if config exists
if [[ ! -f "$CONFIG_PATH" ]]; then
    log "ERROR" "Config file not found: $CONFIG_PATH"
    exit 1
fi

log "INFO" "=== Phase 0: GlusterFS Storage Setup ==="
log "INFO" "Config: $CONFIG_PATH"
log "INFO" "Mode: $MODE"
log "INFO" "Dry Run: $DRY_RUN"
echo ""

###############################################################################
# Step 1: Load configuration
###############################################################################

log "INFO" "[Step 1/8] Loading configuration..."

# Get current controller info
CURRENT_CTRL=$(python3 "$PARSER_PY" --config "$CONFIG_PATH" --current 2>/dev/null || echo "")

if [[ -z "$CURRENT_CTRL" ]]; then
    log "ERROR" "Current controller not found in config (IP not matched)"
    log "INFO" "Please ensure this server's IP is listed in my_multihead_cluster.yaml"
    exit 1
fi

CURRENT_HOSTNAME=$(echo "$CURRENT_CTRL" | jq -r '.hostname')
CURRENT_IP=$(echo "$CURRENT_CTRL" | jq -r '.ip_address')
GLUSTERFS_ENABLED=$(echo "$CURRENT_CTRL" | jq -r '.services.glusterfs // false')

log "SUCCESS" "Current controller: $CURRENT_HOSTNAME ($CURRENT_IP)"

# Check if GlusterFS is enabled
if [[ "$GLUSTERFS_ENABLED" != "true" ]]; then
    log "WARNING" "GlusterFS is not enabled for this controller"
    log "INFO" "Skipping GlusterFS setup"
    exit 0
fi

# Get storage configuration
STORAGE_CONFIG=$(python3 "$PARSER_PY" --config "$CONFIG_PATH" --get-storage 2>/dev/null)
VOLUME_NAME=$(echo "$STORAGE_CONFIG" | jq -r '.glusterfs.volume_name // "shared_data"')
REPLICA_COUNT=$(echo "$STORAGE_CONFIG" | jq -r '.glusterfs.replica_count // "auto"')
BRICK_PATH=$(echo "$STORAGE_CONFIG" | jq -r '.glusterfs.brick_path // "/srv/glusterfs/brick"')
MOUNT_POINT=$(echo "$STORAGE_CONFIG" | jq -r '.glusterfs.mount_point // "/mnt/gluster"')

log "INFO" "Volume name: $VOLUME_NAME"
log "INFO" "Brick path: $BRICK_PATH"
log "INFO" "Mount point: $MOUNT_POINT"

# Validate brick path - must be on local disk, not shared storage
if [[ "$BRICK_PATH" == /data/* ]]; then
    log "ERROR" "Brick path '$BRICK_PATH' is under /data which is typically a shared storage mount"
    log "ERROR" "GlusterFS bricks must be on LOCAL disk, not shared storage"
    log "INFO" "Recommended paths: /srv/glusterfs/brick, /var/lib/glusterfs/brick"
    log "INFO" "Please update 'brick_path' in your YAML config file"
    exit 1
fi

# Check if brick path is on a mounted filesystem (potential conflict)
if mountpoint -q "$(dirname "$BRICK_PATH")" 2>/dev/null; then
    PARENT_MOUNT=$(df "$(dirname "$BRICK_PATH")" 2>/dev/null | tail -1 | awk '{print $1}')
    if [[ "$PARENT_MOUNT" == *"nfs"* ]] || [[ "$PARENT_MOUNT" == *"gluster"* ]] || [[ "$PARENT_MOUNT" == *"ceph"* ]]; then
        log "WARNING" "Brick path parent appears to be network storage: $PARENT_MOUNT"
        log "WARNING" "GlusterFS bricks should be on local disk for proper operation"
    fi
fi
log "INFO" "Replica count: $REPLICA_COUNT"

# Get all GlusterFS-enabled controllers
GLUSTERFS_CONTROLLERS=$(python3 "$PARSER_PY" --config "$CONFIG_PATH" --service glusterfs 2>/dev/null)
TOTAL_GLUSTERFS_NODES=$(echo "$GLUSTERFS_CONTROLLERS" | jq '. | length')

log "INFO" "Total GlusterFS nodes in config: $TOTAL_GLUSTERFS_NODES"

# Auto-calculate replica count
if [[ "$REPLICA_COUNT" == "auto" ]]; then
    REPLICA_COUNT=$TOTAL_GLUSTERFS_NODES
    log "INFO" "Auto replica count: $REPLICA_COUNT"
fi

echo ""

###############################################################################
# Step 2: Check and install GlusterFS
###############################################################################

log "INFO" "[Step 2/8] Checking GlusterFS installation..."

if ! command -v gluster &> /dev/null; then
    log "WARNING" "GlusterFS not installed"

    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY-RUN] Would install GlusterFS packages"
    else
        log "INFO" "Installing GlusterFS..."

        # Detect OS
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            OS=$ID
        else
            log "ERROR" "Cannot detect OS"
            exit 1
        fi

        case $OS in
            ubuntu|debian)
                apt-get update
                apt-get install -y glusterfs-server glusterfs-client attr
                ;;
            centos|rhel|rocky|alma)
                yum install -y centos-release-gluster
                yum install -y glusterfs-server glusterfs-cli attr
                ;;
            *)
                log "ERROR" "Unsupported OS: $OS"
                exit 1
                ;;
        esac

        log "SUCCESS" "GlusterFS installed"
    fi
else
    log "SUCCESS" "GlusterFS already installed"
fi

# Enable and start glusterd
if [[ $DRY_RUN == true ]]; then
    log "INFO" "[DRY-RUN] Would enable and start glusterd service"
else
    systemctl enable glusterd
    systemctl start glusterd

    # Wait for glusterd to be ready
    sleep 3

    if ! systemctl is-active --quiet glusterd; then
        log "ERROR" "glusterd service failed to start"
        exit 1
    fi

    log "SUCCESS" "glusterd service running"
fi

echo ""

###############################################################################
# Step 3: Prepare brick directory
###############################################################################

log "INFO" "[Step 3/8] Preparing brick directory..."

if [[ $DRY_RUN == true ]]; then
    log "INFO" "[DRY-RUN] Would create directory: $BRICK_PATH"
else
    # Check if volume metadata exists in glusterd
    GLUSTERD_VOL_DIR="/var/lib/glusterd/vols/$VOLUME_NAME"
    if [[ -d "$GLUSTERD_VOL_DIR" ]]; then
        log "WARNING" "Found existing volume metadata for $VOLUME_NAME"
        log "INFO" "Performing complete GlusterFS cleanup..."

        # Stop glusterd
        systemctl stop glusterd
        sleep 1

        # Remove ALL volume metadata (not just this volume)
        rm -rf /var/lib/glusterd/vols/*

        # Remove brick metadata
        if [[ -d "$BRICK_PATH/.glusterfs" ]]; then
            rm -rf "$BRICK_PATH/.glusterfs"
        fi

        # Remove entire brick directory and recreate
        rm -rf "$BRICK_PATH"
        mkdir -p "$BRICK_PATH"
        chmod 755 "$BRICK_PATH"

        # Start glusterd and wait for it to be ready
        systemctl start glusterd
        sleep 3

        # Wait for glusterd to be fully ready
        for i in {1..10}; do
            if gluster peer status &>/dev/null; then
                break
            fi
            sleep 1
        done

        log "SUCCESS" "GlusterFS completely cleaned and ready"
    elif [[ -d "$BRICK_PATH/.glusterfs" ]]; then
        # Only brick metadata exists
        log "WARNING" "Found existing brick metadata in $BRICK_PATH"
        log "INFO" "Cleaning up old brick metadata..."
        rm -rf "$BRICK_PATH/.glusterfs"
        log "SUCCESS" "Old brick metadata cleaned"
    fi

    # Create/ensure brick directory exists
    mkdir -p "$BRICK_PATH"
    chmod 755 "$BRICK_PATH"

    log "SUCCESS" "Brick directory prepared: $BRICK_PATH"
fi

echo ""

###############################################################################
# Step 4: Discover active GlusterFS nodes
###############################################################################

log "INFO" "[Step 4/8] Discovering active GlusterFS nodes..."
log "INFO" "  Running auto-discovery script (timeout: 2s per node)..."

# Run discovery with verbose logging to help diagnose issues
# stderr (verbose logs) goes to console, stdout (JSON) is captured
# Don't use 2>&1 - keep streams separate so JSON isn't polluted with logs
DISCOVERY_JSON=$(bash "$DISCOVERY_SH" --config "$CONFIG_PATH" --timeout 2 --verbose || echo '{"controllers":[]}')

# Validate JSON output
if ! echo "$DISCOVERY_JSON" | jq empty 2>/dev/null; then
    log "WARN" "  Discovery returned invalid JSON, using empty result"
    log "WARN" "  Raw output (first 200 chars): ${DISCOVERY_JSON:0:200}"
    DISCOVERY_JSON='{"controllers":[]}'
else
    log "INFO" "  Discovery completed successfully"
fi

# Extract active GlusterFS nodes
ACTIVE_GLUSTERFS_NODES=()
for i in $(seq 0 $(($TOTAL_GLUSTERFS_NODES - 1))); do
    CTRL=$(echo "$GLUSTERFS_CONTROLLERS" | jq ".[$i]")
    CTRL_IP=$(echo "$CTRL" | jq -r '.ip_address')
    CTRL_HOSTNAME=$(echo "$CTRL" | jq -r '.hostname')

    # Skip current node
    if [[ "$CTRL_IP" == "$CURRENT_IP" ]]; then
        continue
    fi

    # Check if active in discovery
    CTRL_DISCOVERY=$(echo "$DISCOVERY_JSON" | jq ".controllers[] | select(.ip == \"$CTRL_IP\")")
    if [[ -n "$CTRL_DISCOVERY" ]]; then
        STATUS=$(echo "$CTRL_DISCOVERY" | jq -r '.status')
        if [[ "$STATUS" == "active" ]]; then
            # Check if GlusterFS is running
            GLUSTERFS_STATUS=$(echo "$CTRL_DISCOVERY" | jq -r '.services.glusterfs.status // "error"')
            if [[ "$GLUSTERFS_STATUS" == "ok" ]]; then
                ACTIVE_GLUSTERFS_NODES+=("$CTRL_HOSTNAME:$CTRL_IP")
                log "INFO" "  Found active node: $CTRL_HOSTNAME ($CTRL_IP)"
            fi
        fi
    fi
done

ACTIVE_COUNT=${#ACTIVE_GLUSTERFS_NODES[@]}
log "INFO" "Active GlusterFS nodes found: $ACTIVE_COUNT"

echo ""

###############################################################################
# Step 5: Determine mode (bootstrap vs join)
###############################################################################

log "INFO" "[Step 5/8] Determining operation mode..."

if [[ "$MODE" == "auto" ]]; then
    if [[ $ACTIVE_COUNT -eq 0 ]]; then
        MODE="bootstrap"
        log "INFO" "No active nodes found → Bootstrap mode"

        # In bootstrap mode, we're the only node, so use replica count 1
        if [[ "$REPLICA_COUNT" == "auto" ]] || [[ "$REPLICA_COUNT" -gt 1 ]]; then
            REPLICA_COUNT=1
            log "INFO" "Bootstrap mode: setting replica count to 1 (single node)"
        fi
    else
        MODE="join"
        log "INFO" "Active nodes found → Join mode"

        # In join mode, replica count should be ACTIVE_COUNT + 1 (including current node)
        if [[ "$REPLICA_COUNT" == "auto" ]]; then
            REPLICA_COUNT=$((ACTIVE_COUNT + 1))
            log "INFO" "Join mode: setting replica count to $REPLICA_COUNT (active nodes + current)"
        fi
    fi
else
    log "INFO" "Mode forced to: $MODE"
fi

echo ""

###############################################################################
# Step 6: Peer connection
###############################################################################

log "INFO" "[Step 6/8] Connecting to peers..."

if [[ "$MODE" == "join" && $ACTIVE_COUNT -gt 0 ]]; then
    for node_info in "${ACTIVE_GLUSTERFS_NODES[@]}"; do
        NODE_HOSTNAME=$(echo "$node_info" | cut -d: -f1)
        NODE_IP=$(echo "$node_info" | cut -d: -f2)

        log "INFO" "  Probing peer: $NODE_HOSTNAME ($NODE_IP)"

        if [[ $DRY_RUN == true ]]; then
            log "INFO" "  [DRY-RUN] Would run: gluster peer probe $NODE_IP"
        else
            # Check if already connected
            if gluster peer status | grep -q "$NODE_IP"; then
                log "INFO" "  Already connected to $NODE_HOSTNAME"
            else
                if gluster peer probe "$NODE_IP" &>> "$LOG_FILE"; then
                    log "SUCCESS" "  Connected to $NODE_HOSTNAME"
                else
                    log "WARNING" "  Failed to connect to $NODE_HOSTNAME"
                fi
            fi
        fi
    done
else
    log "INFO" "Bootstrap mode - no peers to connect yet"
fi

echo ""

###############################################################################
# Step 7: Volume creation or brick addition
###############################################################################

log "INFO" "[Step 7/8] Managing GlusterFS volume..."

if [[ $DRY_RUN == true ]]; then
    log "INFO" "[DRY-RUN] Would create/join volume: $VOLUME_NAME"
else
    # Check if volume exists
    if gluster volume info "$VOLUME_NAME" &>/dev/null; then
        log "INFO" "Volume $VOLUME_NAME already exists"

        # Check volume status
        VOLUME_STATUS=$(gluster volume status "$VOLUME_NAME" 2>/dev/null || echo "error")
        if [[ "$VOLUME_STATUS" == "error" ]]; then
            log "WARNING" "Volume exists but is in error state"
            log "INFO" "Cleaning up failed volume..."
            gluster volume delete "$VOLUME_NAME" --mode=script 2>/dev/null || true
            log "INFO" "Will recreate volume from scratch"
        fi
    fi

    # Re-check after potential cleanup
    if gluster volume info "$VOLUME_NAME" &>/dev/null; then
        log "INFO" "Volume $VOLUME_NAME is active"

        # Check if current brick is already in volume
        if gluster volume info "$VOLUME_NAME" | grep -q "$CURRENT_IP:$BRICK_PATH"; then
            log "INFO" "Current brick already in volume"
        else
            log "INFO" "Adding current brick to volume..."

            # Add brick - handle replica count
            if [[ "$REPLICA_COUNT" -eq 1 ]]; then
                # Adding to non-replicated volume
                gluster volume add-brick "$VOLUME_NAME" "$CURRENT_IP:$BRICK_PATH" force
            else
                # Adding to replicated volume - need to increase replica count
                NEW_REPLICA_COUNT=$((REPLICA_COUNT + 1))
                gluster volume add-brick "$VOLUME_NAME" replica $NEW_REPLICA_COUNT "$CURRENT_IP:$BRICK_PATH" force
            fi

            log "SUCCESS" "Brick added to volume"
        fi
    else
        if [[ "$MODE" == "bootstrap" ]]; then
            log "INFO" "Creating new volume: $VOLUME_NAME"

            # Create volume - don't use replica if count is 1
            if [[ "$REPLICA_COUNT" -eq 1 ]]; then
                log "INFO" "Single node setup - creating without replication"
                gluster volume create "$VOLUME_NAME" "$CURRENT_IP:$BRICK_PATH" force
            else
                log "INFO" "Multi-node setup - creating with replica count $REPLICA_COUNT"
                gluster volume create "$VOLUME_NAME" replica $REPLICA_COUNT "$CURRENT_IP:$BRICK_PATH" force
            fi

            # Set volume options
            gluster volume set "$VOLUME_NAME" performance.cache-size 256MB
            gluster volume set "$VOLUME_NAME" network.ping-timeout 10

            # Only set self-heal for replicated volumes (replica count > 1)
            if [[ "$REPLICA_COUNT" -gt 1 ]]; then
                gluster volume set "$VOLUME_NAME" cluster.self-heal-daemon on
                log "INFO" "Enabled self-heal daemon (replicated volume)"
            else
                log "INFO" "Skipping self-heal daemon (non-replicated volume)"
            fi

            # Start volume
            gluster volume start "$VOLUME_NAME"

            log "SUCCESS" "Volume created and started"
        else
            log "WARNING" "Volume doesn't exist and not in bootstrap mode"
            log "INFO" "Waiting for bootstrap node to create volume..."
        fi
    fi
fi

echo ""

###############################################################################
# Step 8: Mount volume
###############################################################################

log "INFO" "[Step 8/8] Mounting volume..."

if [[ $DRY_RUN == true ]]; then
    log "INFO" "[DRY-RUN] Would create mount point: $MOUNT_POINT"
    log "INFO" "[DRY-RUN] Would mount: localhost:/$VOLUME_NAME → $MOUNT_POINT"
else
    # Clean up any stale mount points
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log "WARNING" "Found existing mount at $MOUNT_POINT, unmounting..."
        umount -f "$MOUNT_POINT" 2>/dev/null || true
    fi

    # If directory exists but is inaccessible, remove and recreate
    if [ -d "$MOUNT_POINT" ] && ! ls "$MOUNT_POINT" >/dev/null 2>&1; then
        log "WARNING" "Mount point $MOUNT_POINT is inaccessible, recreating..."
        umount -f "$MOUNT_POINT" 2>/dev/null || true
        umount -l "$MOUNT_POINT" 2>/dev/null || true  # Lazy unmount
        rm -rf "$MOUNT_POINT" 2>/dev/null || true
    fi

    # Create mount point - ensure clean state
    if ! mkdir -p "$MOUNT_POINT" 2>/dev/null; then
        log "WARNING" "mkdir failed, forcing cleanup..."
        umount -f "$MOUNT_POINT" 2>/dev/null || true
        umount -l "$MOUNT_POINT" 2>/dev/null || true
        rm -rf "$MOUNT_POINT" || true
        mkdir -p "$MOUNT_POINT"
    fi

    # Check if already mounted
    if mountpoint -q "$MOUNT_POINT"; then
        log "INFO" "Already mounted at $MOUNT_POINT"
    else
        # Mount
        if mount -t glusterfs "localhost:/$VOLUME_NAME" "$MOUNT_POINT"; then
            log "SUCCESS" "Volume mounted at $MOUNT_POINT"
        else
            log "WARNING" "Failed to mount volume (volume might not be ready yet)"
        fi
    fi

    # Add to /etc/fstab if not present
    FSTAB_ENTRY="localhost:/$VOLUME_NAME $MOUNT_POINT glusterfs defaults,_netdev 0 0"
    if ! grep -q "$MOUNT_POINT" /etc/fstab; then
        echo "$FSTAB_ENTRY" >> /etc/fstab
        log "SUCCESS" "Added to /etc/fstab for auto-mount on boot"
    else
        log "INFO" "Already in /etc/fstab"
    fi

    # Create directory structure (only if bootstrap)
    if [[ "$MODE" == "bootstrap" && -d "$MOUNT_POINT" ]]; then
        log "INFO" "Creating directory structure..."

        mkdir -p "$MOUNT_POINT"/{frontend_builds,slurm/{state,logs,spool},uploads,config}

        log "SUCCESS" "Directory structure created"
    fi
fi

echo ""

###############################################################################
# Summary
###############################################################################

log "SUCCESS" "=== Phase 0: GlusterFS Setup Complete ==="
log "INFO" "Summary:"
log "INFO" "  - Controller: $CURRENT_HOSTNAME ($CURRENT_IP)"
log "INFO" "  - Mode: $MODE"
log "INFO" "  - Volume: $VOLUME_NAME"
log "INFO" "  - Brick: $BRICK_PATH"
log "INFO" "  - Mount: $MOUNT_POINT"
log "INFO" "  - Active peers: $ACTIVE_COUNT"

if [[ $DRY_RUN == false ]]; then
    # Display volume info
    echo ""
    log "INFO" "Volume status:"
    gluster volume info "$VOLUME_NAME" 2>/dev/null || log "WARNING" "Volume info not available yet"
fi

exit 0
