#!/bin/bash
################################################################################
# Sync Slurm Configuration to Compute Nodes
# Copies slurm.conf, cgroup.conf, and systemd service files to all nodes
################################################################################

set -e

echo "================================================================================"
echo "📤 Syncing Slurm Configuration to Compute Nodes"
echo "================================================================================"
echo ""

# Configuration
# my_cluster.yaml에서 모든 compute_nodes 읽기 (viz 노드 포함)
mapfile -t COMPUTE_NODES < <(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    print(node['ip_address'])
EOFPY
)

SSH_USER="koopark"
CONFIG_DIR="/usr/local/slurm/etc"

echo "📋 검색된 계산 노드 (viz 노드 포함):"
for node in "${COMPUTE_NODES[@]}"; do
    echo "  - $node"
done
echo ""

################################################################################
# Check if config files exist
################################################################################

echo "🔍 Checking configuration files..."
echo "--------------------------------------------------------------------------------"

if [ ! -f "${CONFIG_DIR}/slurm.conf" ]; then
    echo "❌ slurm.conf not found at ${CONFIG_DIR}/slurm.conf"
    exit 1
fi

if [ ! -f "${CONFIG_DIR}/cgroup.conf" ]; then
    echo "❌ cgroup.conf not found at ${CONFIG_DIR}/cgroup.conf"
    exit 1
fi

if [ ! -f "/etc/systemd/system/slurmd.service" ]; then
    echo "⚠️  slurmd.service not found, will create on nodes"
fi

echo "✅ Configuration files found"
echo ""

################################################################################
# Sync to each compute node
################################################################################

for node in "${COMPUTE_NODES[@]}"; do
    echo "📤 Syncing to ${node}..."
    echo "--------------------------------------------------------------------------------"
    
    # Test SSH connection
    if ! ssh -o ConnectTimeout=5 ${SSH_USER}@${node} "echo ''" 2>/dev/null; then
        echo "❌ Cannot connect to ${node}, skipping..."
        echo ""
        continue
    fi
    
    # Copy slurm.conf
    echo "  [1/4] Copying slurm.conf..."
    scp ${CONFIG_DIR}/slurm.conf ${SSH_USER}@${node}:/tmp/
    ssh ${SSH_USER}@${node} "sudo mv /tmp/slurm.conf ${CONFIG_DIR}/ && sudo chown slurm:slurm ${CONFIG_DIR}/slurm.conf && sudo chmod 644 ${CONFIG_DIR}/slurm.conf"
    
    # Copy cgroup.conf
    echo "  [2/4] Copying cgroup.conf..."
    scp ${CONFIG_DIR}/cgroup.conf ${SSH_USER}@${node}:/tmp/
    ssh ${SSH_USER}@${node} "sudo mv /tmp/cgroup.conf ${CONFIG_DIR}/ && sudo chown slurm:slurm ${CONFIG_DIR}/cgroup.conf && sudo chmod 644 ${CONFIG_DIR}/cgroup.conf"
    
    # Create slurmd.service on node
    echo "  [3/4] Creating slurmd.service..."
    ssh ${SSH_USER}@${node} "sudo tee /etc/systemd/system/slurmd.service > /dev/null" <<'EOF'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/local/slurm/sbin/slurmd $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
User=slurm
Group=slurm
RuntimeDirectory=slurm
RuntimeDirectoryMode=0755
TimeoutStartSec=300
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF
    
    # Create tmpfiles.d configuration
    echo "  [4/4] Creating tmpfiles.d configuration..."
    ssh ${SSH_USER}@${node} "sudo tee /etc/tmpfiles.d/slurm.conf > /dev/null" <<'EOF'
# Slurm runtime directories
d /run/slurm 0755 slurm slurm -
EOF
    ssh ${SSH_USER}@${node} "sudo systemd-tmpfiles --create"
    
    # Reload systemd
    ssh ${SSH_USER}@${node} "sudo systemctl daemon-reload"
    
    # Restart slurmd
    echo "  [*] Restarting slurmd..."
    ssh ${SSH_USER}@${node} "sudo systemctl restart slurmd" || echo "  ⚠️  Failed to restart slurmd on ${node}"
    
    sleep 2
    
    # Check status
    if ssh ${SSH_USER}@${node} "sudo systemctl is-active --quiet slurmd"; then
        echo "  ✅ ${node}: slurmd running"
    else
        echo "  ⚠️  ${node}: slurmd not running"
        ssh ${SSH_USER}@${node} "sudo systemctl status slurmd --no-pager -l" || true
    fi
    
    echo ""
done

################################################################################
# Summary
################################################################################

echo "================================================================================"
echo "✅ Configuration Sync Complete"
echo "================================================================================"
echo ""

# Restart slurmctld to refresh node info
echo "🔄 Restarting slurmctld to refresh node information..."
sudo systemctl restart slurmctld
sleep 3

# Check cluster status
echo ""
echo "📊 Cluster Status:"
echo "--------------------------------------------------------------------------------"
export PATH=/usr/local/slurm/bin:$PATH
sinfo || echo "⚠️  sinfo command failed"
echo ""
sinfo -N || echo "⚠️  sinfo -N command failed"

echo ""
echo "================================================================================"
echo "✅ Done!"
echo "================================================================================"
echo ""
echo "If nodes are still in DOWN state, you may need to resume them:"
echo "  scontrol update NodeName=node001 State=RESUME"
echo "  scontrol update NodeName=node002 State=RESUME"
echo ""



