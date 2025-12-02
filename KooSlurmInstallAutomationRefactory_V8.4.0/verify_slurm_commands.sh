#!/bin/bash
################################################################################
# Verify Slurm Commands are Available
# Quick check to ensure all Slurm commands are in your PATH
################################################################################

echo "================================================================================"
echo "🔍 Verifying Slurm Command Availability"
echo "================================================================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if PATH includes Slurm
echo "📋 Step 1: Checking PATH..."
echo "--------------------------------------------------------------------------------"
if echo "$PATH" | grep -q "/usr/local/slurm/bin"; then
    echo -e "${GREEN}✅ Slurm bin directory is in PATH${NC}"
else
    echo -e "${RED}❌ Slurm bin directory NOT in PATH${NC}"
    echo ""
    echo "To fix this, run:"
    echo "  source /etc/profile.d/slurm.sh"
    echo ""
    echo "Or add to your ~/.bashrc:"
    echo "  export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:\$PATH"
    exit 1
fi
echo ""

# Check individual commands
echo "🔧 Step 2: Checking individual commands..."
echo "--------------------------------------------------------------------------------"

COMMANDS=(
    "sinfo:Cluster information"
    "squeue:Job queue"
    "sbatch:Submit batch job"
    "srun:Run interactive job"
    "scancel:Cancel job"
    "scontrol:Control Slurm"
    "sacct:Job accounting"
    "sacctmgr:Accounting manager"
    "salloc:Allocate resources"
    "sprio:Job priority"
    "sdiag:Diagnostics"
)

ALL_OK=true

for item in "${COMMANDS[@]}"; do
    cmd="${item%%:*}"
    desc="${item##*:}"
    
    if command -v "$cmd" &> /dev/null; then
        echo -e "  ${GREEN}✅${NC} $cmd - $desc"
    else
        echo -e "  ${RED}❌${NC} $cmd - NOT FOUND"
        ALL_OK=false
    fi
done

echo ""

# Check Slurm version
echo "📊 Step 3: Checking Slurm version..."
echo "--------------------------------------------------------------------------------"
if command -v scontrol &> /dev/null; then
    VERSION=$(scontrol version | head -1)
    echo -e "${GREEN}✅ $VERSION${NC}"
else
    echo -e "${RED}❌ Cannot determine version${NC}"
    ALL_OK=false
fi

echo ""

# Test cluster connectivity
echo "🔗 Step 4: Testing cluster connectivity..."
echo "--------------------------------------------------------------------------------"
if command -v sinfo &> /dev/null; then
    if sinfo &> /dev/null; then
        echo -e "${GREEN}✅ Cluster is reachable${NC}"
        echo ""
        sinfo
    else
        echo -e "${YELLOW}⚠️  Cluster not responding (slurmctld may be down)${NC}"
        ALL_OK=false
    fi
else
    echo -e "${RED}❌ sinfo not available${NC}"
    ALL_OK=false
fi

echo ""
echo "================================================================================"

if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}✅ All checks passed! Slurm commands are ready to use.${NC}"
    echo ""
    echo "Try these commands:"
    echo "  sinfo              # View cluster status"
    echo "  squeue             # View job queue"
    echo "  sinfo -Nel         # Detailed node information"
    echo "  scontrol show node # Full node details"
else
    echo -e "${YELLOW}⚠️  Some issues detected. See above for details.${NC}"
fi

echo "================================================================================"
echo ""



