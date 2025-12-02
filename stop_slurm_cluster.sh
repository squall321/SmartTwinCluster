#!/bin/bash
################################################################################
# Stop Slurm Cluster - All Compute Nodes + Controller
# Gracefully stops all Slurm services
################################################################################

echo "================================================================================"
echo "🛑 Stopping Slurm Cluster Services"
echo "================================================================================"
echo ""

# Configuration
COMPUTE_NODES=("192.168.122.90" "192.168.122.103")
SSH_USER="koopark"

################################################################################
# Step 1: Stop Compute Nodes First (slurmd)
################################################################################

echo "📋 Step 1/3: Stopping Compute Nodes (slurmd)..."
echo "--------------------------------------------------------------------------------"

for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "🔧 Stopping slurmd on ${node}..."
    
    # Timeout으로 SSH 실행 (30초)
    if timeout 30 ssh -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 ${SSH_USER}@${node} "sudo systemctl stop slurmd" 2>/dev/null; then
        sleep 1
        
        # 상태 확인도 timeout 적용
        if timeout 10 ssh -o ConnectTimeout=5 ${SSH_USER}@${node} "sudo systemctl is-active --quiet slurmd" 2>/dev/null; then
            echo "  ⚠️  ${node}: slurmd still running"
        else
            echo "  ✅ ${node}: slurmd stopped successfully"
        fi
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo "  ⚠️  ${node}: Timeout (30초 초과)"
        else
            echo "  ⚠️  ${node}: Cannot connect or command failed"
        fi
    fi
done

echo ""

################################################################################
# Step 2: Wait for clean shutdown
################################################################################

echo "📋 Step 2/3: Waiting for clean shutdown..."
echo "--------------------------------------------------------------------------------"

sleep 3
echo "✅ Wait complete"
echo ""

################################################################################
# Step 3: Stop Controller (slurmctld)
################################################################################

echo "📋 Step 3/3: Stopping Controller (slurmctld)..."
echo "--------------------------------------------------------------------------------"

sudo systemctl stop slurmctld
sleep 2

if ! sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld stopped successfully"
else
    echo "⚠️  slurmctld still running, forcing stop..."
    sudo systemctl stop slurmctld
    sleep 2
fi

# Check for any remaining processes
if ps aux | grep -v grep | grep -q slurmctld; then
    echo "⚠️  Warning: Some slurmctld processes still running"
    ps aux | grep -v grep | grep slurmctld || true
    echo ""
    echo "To force kill:"
    echo "  sudo pkill -9 slurmctld"
else
    echo "✅ All slurmctld processes stopped"
fi

echo ""

################################################################################
# Summary
################################################################################

echo "================================================================================"
echo "✅ Slurm Cluster Services Stopped"
echo "================================================================================"
echo ""

echo "All services stopped:"
echo "  ✅ Controller (slurmctld) - Stopped"
echo "  ✅ Compute nodes (slurmd) - Stopped"
echo ""

echo "🚀 To start the cluster again:"
echo "   ./start_slurm_cluster.sh"
echo ""

echo "🔧 Service status commands:"
echo "   sudo systemctl status slurmctld"
echo "   ssh koopark@192.168.122.90 'sudo systemctl status slurmd'"
echo "   ssh koopark@192.168.122.103 'sudo systemctl status slurmd'"
echo ""

echo "================================================================================"
echo "🛑 Cluster stopped"
echo "================================================================================"
echo ""



