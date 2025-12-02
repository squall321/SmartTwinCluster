#!/bin/bash
################################################################################
# Start Slurm Cluster - Controller + All Compute Nodes
# Run this after setup_cluster_full.sh completes
################################################################################

set -e

echo "================================================================================"
echo "🚀 Starting Slurm Cluster Services"
echo "================================================================================"
echo ""

# Configuration
COMPUTE_NODES=("192.168.122.90" "192.168.122.103")
SSH_USER="koopark"

################################################################################
# Step 1: Start Controller (slurmctld)
################################################################################

echo "📋 Step 1/4: Starting Controller (slurmctld)..."
echo "--------------------------------------------------------------------------------"

sudo systemctl start slurmctld
sleep 3

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld started successfully"
    sudo systemctl status slurmctld --no-pager -l | head -10
else
    echo "❌ Failed to start slurmctld"
    sudo systemctl status slurmctld --no-pager -l
    exit 1
fi

echo ""

################################################################################
# Step 2: Start Compute Nodes (slurmd)
################################################################################

echo "📋 Step 2/4: Starting Compute Nodes (slurmd)..."
echo "--------------------------------------------------------------------------------"

for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "🔧 Starting slurmd on ${node}..."
    
    # Timeout으로 SSH 실행 (60초)
    if timeout 60 ssh -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 ${SSH_USER}@${node} "sudo systemctl start slurmd" 2>/dev/null; then
        sleep 2
        
        # 상태 확인도 timeout 적용
        if timeout 10 ssh -o ConnectTimeout=5 ${SSH_USER}@${node} "sudo systemctl is-active --quiet slurmd" 2>/dev/null; then
            echo "  ✅ ${node}: slurmd started successfully"
        else
            echo "  ⚠️  ${node}: slurmd may have issues"
            timeout 10 ssh -o ConnectTimeout=5 ${SSH_USER}@${node} "sudo systemctl status slurmd --no-pager -l" 2>/dev/null || true
        fi
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo "  ⚠️  ${node}: Timeout (60초 초과)"
        else
            echo "  ❌ ${node}: Cannot connect or command failed"
        fi
    fi
done

echo ""

################################################################################
# Step 3: Wait for nodes to register
################################################################################

echo "📋 Step 3/4: Waiting for nodes to register..."
echo "--------------------------------------------------------------------------------"

sleep 5
echo "✅ Wait complete"
echo ""

################################################################################
# Step 4: Check Cluster Status
################################################################################

echo "📋 Step 4/4: Checking Cluster Status..."
echo "--------------------------------------------------------------------------------"

# Load PATH if needed
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH

echo ""
echo "📊 Cluster Information:"
sinfo || echo "⚠️  sinfo command failed"

echo ""
echo "📊 Node Details:"
sinfo -N || echo "⚠️  sinfo -N command failed"

echo ""
echo "📊 Node States:"
scontrol show nodes | grep -E "NodeName|State=" || true

echo ""

################################################################################
# Summary
################################################################################

echo "================================================================================"
echo "✅ Slurm Cluster Services Started"
echo "================================================================================"
echo ""

# Count active nodes
IDLE_NODES=$(sinfo -h -o "%t" | grep -c "idle" 2>/dev/null || echo "0")
DOWN_NODES=$(sinfo -h -o "%t" | grep -c "down" 2>/dev/null || echo "0")

echo "Status Summary:"
echo "  Controller:    ✅ Running"
echo "  Idle Nodes:    ${IDLE_NODES}"
echo "  Down Nodes:    ${DOWN_NODES}"
echo ""

if [ "$DOWN_NODES" -gt 0 ]; then
    echo "⚠️  Some nodes are DOWN. To resume them:"
    echo "   scontrol update NodeName=node001 State=RESUME"
    echo "   scontrol update NodeName=node002 State=RESUME"
    echo ""
fi

echo "💡 Quick Commands:"
echo "   sinfo              # Cluster status"
echo "   squeue             # Job queue"
echo "   sbatch script.sh   # Submit job"
echo "   scontrol show node # Node details"
echo ""

echo "🛑 To stop the cluster:"
echo "   ./stop_slurm_cluster.sh"
echo ""

echo "================================================================================"
echo "🎉 Ready to submit jobs!"
echo "================================================================================"
echo ""



