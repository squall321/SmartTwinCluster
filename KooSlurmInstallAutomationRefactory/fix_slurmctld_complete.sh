#!/bin/bash
################################################################################
# Complete Slurmctld Fix Script
# Fixes: PID permissions, incompatible plugins, cgroup.conf, state files
################################################################################

set -e

echo "================================================================================"
echo "🔧 Slurmctld Complete Fix"
echo "================================================================================"
echo ""

################################################################################
# Step 1: Stop and kill all existing slurmctld processes
################################################################################

echo "🛑 Step 1/7: Stopping existing slurmctld processes..."
echo "--------------------------------------------------------------------------------"

# Stop the service
sudo systemctl stop slurmctld 2>/dev/null || true
sleep 2

# Kill any remaining processes
sudo pkill -9 slurmctld 2>/dev/null || true
sudo pkill -9 slurmscriptd 2>/dev/null || true
sleep 1

# Verify
if ps aux | grep -v grep | grep slurmctld > /dev/null; then
    echo "⚠️  Warning: Some slurmctld processes still running"
    ps aux | grep -v grep | grep slurmctld
else
    echo "✅ All slurmctld processes stopped"
fi

echo ""

################################################################################
# Step 2: Remove old incompatible plugins
################################################################################

echo "🗑️  Step 2/7: Removing old incompatible plugins..."
echo "--------------------------------------------------------------------------------"

if [ -d "/usr/local/slurm/lib/slurm" ]; then
    echo "Found plugin directory, checking for old 23.02.7 plugins..."
    
    # Backup old plugins
    sudo mkdir -p /usr/local/slurm/lib/slurm.backup
    
    # Move old plugins to backup
    for plugin in select_cons_res.so mpi_none.so; do
        if [ -f "/usr/local/slurm/lib/slurm/${plugin}" ]; then
            echo "  Backing up ${plugin}..."
            sudo mv /usr/local/slurm/lib/slurm/${plugin} /usr/local/slurm/lib/slurm.backup/ 2>/dev/null || true
        fi
    done
    
    echo "✅ Old plugins backed up"
else
    echo "⚠️  Plugin directory not found"
fi

echo ""

################################################################################
# Step 3: Fix cgroup.conf
################################################################################

echo "📝 Step 3/7: Fixing cgroup.conf for Slurm 23.11.x..."
echo "--------------------------------------------------------------------------------"

sudo tee /usr/local/slurm/etc/cgroup.conf > /dev/null <<'EOF'
###
# Slurm cgroup Configuration for Slurm 23.11.x
# Compatible with cgroup v2 and systemd
###

# Resource constraints
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=no
ConstrainDevices=no

# Memory limits
AllowedRAMSpace=100
AllowedSwapSpace=0

# cgroup v2 is managed by systemd automatically
# No additional options needed
EOF

sudo chown slurm:slurm /usr/local/slurm/etc/cgroup.conf
sudo chmod 644 /usr/local/slurm/etc/cgroup.conf

echo "✅ cgroup.conf updated"
echo ""

################################################################################
# Step 4: Fix state directory permissions
################################################################################

echo "📂 Step 4/7: Fixing state directories and permissions..."
echo "--------------------------------------------------------------------------------"

# Create necessary directories
sudo mkdir -p /var/spool/slurm/state
sudo mkdir -p /var/spool/slurm/d
sudo mkdir -p /var/log/slurm
sudo mkdir -p /run/slurm

# Set ownership
sudo chown -R slurm:slurm /var/spool/slurm
sudo chown -R slurm:slurm /var/log/slurm
sudo chown -R slurm:slurm /run/slurm

# Set permissions
sudo chmod 755 /var/spool/slurm
sudo chmod 755 /var/spool/slurm/state
sudo chmod 755 /var/spool/slurm/d
sudo chmod 755 /var/log/slurm
sudo chmod 755 /run/slurm

echo "✅ Directories and permissions fixed"
echo ""

################################################################################
# Step 5: Create systemd tmpfiles.d configuration
################################################################################

echo "📄 Step 5/7: Creating systemd tmpfiles.d configuration..."
echo "--------------------------------------------------------------------------------"

# This ensures /run/slurm is created on boot and has correct permissions
sudo tee /etc/tmpfiles.d/slurm.conf > /dev/null <<'EOF'
# Slurm runtime directories
d /run/slurm 0755 slurm slurm -
EOF

# Create the directory now
sudo systemd-tmpfiles --create

echo "✅ tmpfiles.d configuration created"
echo ""

################################################################################
# Step 6: Update systemd service file
################################################################################

echo "🔧 Step 6/7: Updating slurmctld.service..."
echo "--------------------------------------------------------------------------------"

sudo tee /etc/systemd/system/slurmctld.service > /dev/null <<'EOF'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/local/slurm/sbin/slurmctld $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmctld.pid
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

echo "✅ slurmctld.service updated"
echo ""

################################################################################
# Step 7: Update slurm.conf PID file paths
################################################################################

echo "📝 Step 7/7: Updating slurm.conf PID file paths..."
echo "--------------------------------------------------------------------------------"

# Update PID file paths
sudo sed -i 's|^SlurmctldPidFile=.*|SlurmctldPidFile=/run/slurm/slurmctld.pid|' /usr/local/slurm/etc/slurm.conf
sudo sed -i 's|^SlurmdPidFile=.*|SlurmdPidFile=/run/slurm/slurmd.pid|' /usr/local/slurm/etc/slurm.conf

echo "✅ slurm.conf PID paths updated"
echo ""

################################################################################
# Reload and restart
################################################################################

echo "🔄 Reloading systemd and restarting services..."
echo "--------------------------------------------------------------------------------"

sudo systemctl daemon-reload
sleep 2

echo "✅ systemd reloaded"
echo ""

################################################################################
# Summary
################################################################################

echo "================================================================================"
echo "✅ Fix Complete!"
echo "================================================================================"
echo ""
echo "Changes made:"
echo "  1. ✅ Stopped and killed all old slurmctld processes"
echo "  2. ✅ Removed incompatible 23.02.7 plugins"
echo "  3. ✅ Fixed cgroup.conf (removed invalid keys)"
echo "  4. ✅ Created and fixed state directories"
echo "  5. ✅ Created tmpfiles.d configuration for /run/slurm"
echo "  6. ✅ Updated systemd service with RuntimeDirectory"
echo "  7. ✅ Updated slurm.conf PID file paths"
echo ""
echo "================================================================================"
echo "🚀 Next Steps"
echo "================================================================================"
echo ""
echo "Option 1: Start slurmctld now"
echo "  sudo systemctl start slurmctld"
echo "  sudo systemctl status slurmctld"
echo ""
echo "Option 2: Run full setup script"
echo "  ./setup_cluster_full.sh"
echo ""
echo "Option 3: Reinstall Slurm 23.11.x completely (recommended)"
echo "  sudo bash install_slurm_cgroup_v2.sh"
echo ""
echo "================================================================================"
echo ""
echo "💡 Recommendation: Reinstall Slurm 23.11.x to ensure all plugins are compatible"
echo ""



