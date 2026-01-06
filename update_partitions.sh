#!/bin/bash
################################################################################
# Update Partitions from YAML
#
# YAML의 slurm_config.partitions 설정을 읽어서 DB의 cluster_config를 업데이트
#
# Usage:
#   ./update_partitions.sh [--config PATH]
#
# Options:
#   --config PATH   YAML 설정 파일 경로 (기본: my_multihead_cluster.yaml)
#   --dry-run       실제 적용 없이 미리보기만
#   --help          도움말
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/my_multihead_cluster.yaml"
DRY_RUN=false

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

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

# Read YAML
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
    partitions = config.get('partitions', [])

if not partitions:
    print("No partitions found in YAML")
    sys.exit(1)

# Create groups
groups = []
colors = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16']

print(f"\n=== Partitions from YAML ===")
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

# Get cluster info
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

print(f"\n  Total: {cluster_config['totalNodes']} nodes, {cluster_config['totalCores']} cores")

if dry_run:
    print(f"\n[DRY-RUN] Would update database with above configuration")
    sys.exit(0)

# Update DB
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Check if table exists
cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cluster_config'")
if not cursor.fetchone():
    print(f"\nError: cluster_config table not found in {db_path}")
    print("Run database migrations first: cd dashboard/backend_5010 && python3 run_migrations.py")
    sys.exit(1)

# Update or insert
cursor.execute("SELECT id FROM cluster_config WHERE id = 1")
if cursor.fetchone():
    cursor.execute("UPDATE cluster_config SET config = ?, updated_at = CURRENT_TIMESTAMP WHERE id = 1",
                   (json.dumps(cluster_config),))
    print(f"\n[SUCCESS] Updated cluster_config with {len(groups)} partitions")
else:
    cursor.execute("INSERT INTO cluster_config (id, config) VALUES (1, ?)",
                   (json.dumps(cluster_config),))
    print(f"\n[SUCCESS] Inserted cluster_config with {len(groups)} partitions")

conn.commit()
conn.close()
EOPY

log_success "Partition update complete!"
echo ""
echo "Note: Web services may need restart to pick up changes:"
echo "  sudo systemctl restart backend-5010"
