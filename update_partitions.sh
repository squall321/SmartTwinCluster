#!/bin/bash
################################################################################
# Update Partitions from YAML
#
# YAML의 slurm_config.partitions 설정을 읽어서:
#   1. Slurm 파티션 업데이트 (scontrol)
#   2. DB의 cluster_config 업데이트
#
# Usage:
#   sudo ./update_partitions.sh [--config PATH]
#
# Options:
#   --config PATH   YAML 설정 파일 경로 (기본: my_multihead_cluster.yaml)
#   --db-only       DB만 업데이트 (Slurm 건너뜀)
#   --slurm-only    Slurm만 업데이트 (DB 건너뜀)
#   --dry-run       실제 적용 없이 미리보기만
#   --help          도움말
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/my_multihead_cluster.yaml"
DRY_RUN=false
DB_ONLY=false
SLURM_ONLY=false

# Slurm paths
SLURM_BIN_DIR="${SLURM_BIN_DIR:-/usr/local/slurm/bin}"
SCONTROL="${SLURM_BIN_DIR}/scontrol"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --db-only)
            DB_ONLY=true
            shift
            ;;
        --slurm-only)
            SLURM_ONLY=true
            shift
            ;;
        --help|-h)
            grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | head -20
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "Config file not found: $CONFIG_PATH"
    exit 1
fi

log_info "Config: $CONFIG_PATH"

# Get DB path from backend .env
DB_PATH="/home/koopark/web_services/backend/dashboard.db"
if [[ -f "${SCRIPT_DIR}/dashboard/backend_5010/.env" ]]; then
    _db=$(grep "^DATABASE_PATH=" "${SCRIPT_DIR}/dashboard/backend_5010/.env" 2>/dev/null | cut -d= -f2)
    [[ -n "$_db" ]] && DB_PATH="$_db"
fi

# ============================================================================
# Part 1: Update Slurm Partitions (scontrol)
# ============================================================================
if [[ "$DB_ONLY" == false ]]; then
    echo ""
    log_info "=== Updating Slurm Partitions ==="

    # Check if scontrol exists
    if [[ ! -x "$SCONTROL" ]]; then
        log_warning "scontrol not found at $SCONTROL, trying PATH..."
        SCONTROL=$(which scontrol 2>/dev/null || echo "")
        if [[ -z "$SCONTROL" ]]; then
            log_error "scontrol not found. Skipping Slurm update."
            log_info "Install Slurm or set SLURM_BIN_DIR environment variable."
        fi
    fi

    if [[ -n "$SCONTROL" ]] && [[ -x "$SCONTROL" ]]; then
        # Get existing partitions
        EXISTING_PARTITIONS=$($SCONTROL show partition -o 2>/dev/null | grep -oP 'PartitionName=\K[^ ]+' || echo "")

        # Parse YAML and update Slurm partitions
        python3 << EOPY
import yaml
import subprocess
import sys

config_path = '$CONFIG_PATH'
scontrol = '$SCONTROL'
dry_run = '$DRY_RUN' == 'true'
existing = set('$EXISTING_PARTITIONS'.split())

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

partitions = config.get('slurm_config', {}).get('partitions', [])
if not partitions:
    partitions = config.get('slurm', {}).get('partitions', [])

for partition in partitions:
    name = partition.get('name')
    nodes = partition.get('nodes', '')
    default = 'YES' if partition.get('default', False) else 'NO'
    max_time = partition.get('max_time', 'INFINITE')
    state = partition.get('state', 'UP')

    if not name or not nodes:
        continue

    if name in existing:
        # Update existing partition
        cmd = [scontrol, 'update', f'PartitionName={name}', f'Nodes={nodes}',
               f'Default={default}', f'MaxTime={max_time}', f'State={state}']
        action = "Updating"
    else:
        # Create new partition
        cmd = [scontrol, 'create', f'PartitionName={name}', f'Nodes={nodes}',
               f'Default={default}', f'MaxTime={max_time}', f'State={state}']
        action = "Creating"

    print(f"  {action} partition '{name}' with {len(nodes.split(','))} nodes...")

    if dry_run:
        print(f"    [DRY-RUN] Would run: {' '.join(cmd)}")
    else:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                print(f"    ✅ Success")
            else:
                print(f"    ❌ Failed: {result.stderr.strip()}")
        except Exception as e:
            print(f"    ❌ Error: {e}")

print("")
EOPY

        if [[ "$DRY_RUN" == false ]]; then
            log_success "Slurm partitions updated!"
        else
            log_info "[DRY-RUN] Slurm partition update simulated"
        fi
    fi
fi

# ============================================================================
# Part 2: Update Database cluster_config
# ============================================================================
if [[ "$SLURM_ONLY" == false ]]; then
    echo ""
    log_info "=== Updating Database cluster_config ==="

    # Get DB path from backend .env
    DB_PATH="/home/koopark/web_services/backend/dashboard.db"
    if [[ -f "${SCRIPT_DIR}/dashboard/backend_5010/.env" ]]; then
        _db=$(grep "^DATABASE_PATH=" "${SCRIPT_DIR}/dashboard/backend_5010/.env" 2>/dev/null | cut -d= -f2)
        [[ -n "$_db" ]] && DB_PATH="$_db"
    fi

    log_info "Database: $DB_PATH"

    # Parse YAML and update DB
    python3 << EOPY
import yaml
import json
import sqlite3
import sys

config_path = '$CONFIG_PATH'
db_path = '$DB_PATH'
dry_run = '$DRY_RUN' == 'true'

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

# Get compute nodes for hardware info
compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
all_nodes = compute_nodes + viz_nodes

node_hardware = {}
for node in all_nodes:
    hostname = node.get('hostname')
    if hostname:
        node_hardware[hostname] = {
            'ip_address': node.get('ip_address'),
            'cpus': node.get('hardware', {}).get('cpus', 128),
            'memory_mb': node.get('hardware', {}).get('memory_mb', 0)
        }

# Get partitions
partitions = config.get('slurm_config', {}).get('partitions', [])
if not partitions:
    partitions = config.get('slurm', {}).get('partitions', [])

if not partitions:
    print("  No partitions found in YAML")
    sys.exit(1)

# Create groups
groups = []
colors = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899']

for idx, partition in enumerate(partitions):
    partition_name = partition.get('name', f'partition{idx+1}')
    nodes_str = partition.get('nodes', '')

    node_list = []
    if nodes_str:
        for hostname in nodes_str.split(','):
            hostname = hostname.strip()
            if hostname:
                hw = node_hardware.get(hostname, {})
                node_list.append({
                    'hostname': hostname,
                    'ip_address': hw.get('ip_address', ''),
                    'cpus': hw.get('cpus', 128),
                    'memory_mb': hw.get('memory_mb', 0),
                    'status': 'idle'
                })

    total_cores = sum(n.get('cpus', 128) for n in node_list)

    group = {
        'id': idx + 1,
        'name': partition_name.capitalize(),
        'partitionName': partition_name,
        'qosName': f'{partition_name}_qos',
        'allowedCoreSizes': [32, 64, 128],
        'color': colors[idx % len(colors)],
        'description': partition.get('description', f'{partition_name} partition'),
        'nodeCount': len(node_list),
        'totalCores': total_cores,
        'nodes': node_list,
        'maxTime': partition.get('max_time', 'INFINITE'),
        'default': partition.get('default', False)
    }
    groups.append(group)
    print(f"  {partition_name}: {len(node_list)} nodes, {total_cores} cores")

cluster_info = config.get('cluster_info', {})
controllers = config.get('nodes', {}).get('controllers', [])
controller_ip = controllers[0].get('ip_address', '127.0.0.1') if controllers else '127.0.0.1'

cluster_config = {
    'groups': groups,
    'clusterName': cluster_info.get('cluster_name', 'HPC-Cluster'),
    'controllerIp': controller_ip,
    'totalNodes': sum(g['nodeCount'] for g in groups),
    'totalCores': sum(g['totalCores'] for g in groups)
}

if dry_run:
    print(f"\n  [DRY-RUN] Would update database")
    sys.exit(0)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cluster_config'")
if not cursor.fetchone():
    print(f"\n  Error: cluster_config table not found")
    sys.exit(1)

cursor.execute("SELECT id FROM cluster_config WHERE id = 1")
if cursor.fetchone():
    cursor.execute("UPDATE cluster_config SET config = ?, updated_at = CURRENT_TIMESTAMP WHERE id = 1",
                   (json.dumps(cluster_config),))
else:
    cursor.execute("INSERT INTO cluster_config (id, config) VALUES (1, ?)",
                   (json.dumps(cluster_config),))

conn.commit()
conn.close()
print(f"\n  ✅ Database updated with {len(groups)} partitions")
EOPY

    if [[ "$DRY_RUN" == false ]]; then
        log_success "Database cluster_config updated!"
    fi
fi

echo ""
log_success "Partition update complete!"
echo ""
echo "Note: Web services may need restart to pick up changes:"
echo "  sudo systemctl restart dashboard_backend"
