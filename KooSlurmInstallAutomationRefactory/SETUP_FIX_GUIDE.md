# 🔧 Slurm Setup Fix Guide - Complete Solution

## 📋 Problem Summary

When running `setup_cluster_full.sh`, you encountered these errors:
- ❌ **slurmctld.service timeout** - Service times out after 5 minutes
- ❌ **PID file permission errors** - "Can't open PID file /run/slurmctld.pid: Operation not permitted"
- ❌ **Incompatible plugins** - Old 23.02.7 plugins conflicting with new 23.11.10
- ❌ **Invalid cgroup.conf** - Unrecognized keys: `TaskAffinity`, `MemoryLimitEnforce`
- ❌ **Config mismatch** - Compute nodes have outdated configuration files

## ✅ Solution Applied

We created and applied a comprehensive fix that addresses all issues:

### 1️⃣ **fix_slurmctld_complete.sh**
This script fixes the controller node:
- Stops all zombie/orphaned slurmctld processes
- Removes incompatible old plugins (23.02.7)
- Fixes cgroup.conf with correct Slurm 23.11.x syntax
- Creates proper state directories with correct permissions
- Creates systemd tmpfiles.d configuration for `/run/slurm`
- Updates systemd service files with `RuntimeDirectory`
- Updates PID file paths in slurm.conf

### 2️⃣ **sync_config_to_nodes.sh**
This script syncs configurations to compute nodes:
- Copies updated slurm.conf to all nodes
- Copies updated cgroup.conf to all nodes
- Creates proper slurmd.service on each node
- Creates tmpfiles.d configuration on each node
- Restarts slurmd services

### 3️⃣ **Updated configure_slurm_cgroup_v2.sh**
The main configuration script now includes:
- Correct PID file paths: `/run/slurm/slurmctld.pid`
- RuntimeDirectory configuration for systemd
- tmpfiles.d setup for automatic `/run/slurm` creation
- Proper User/Group settings

## 🚀 Quick Fix (If You're Experiencing Issues Right Now)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# Step 1: Fix the controller
sudo bash fix_slurmctld_complete.sh

# Step 2: Start slurmctld
sudo systemctl start slurmctld
sudo systemctl status slurmctld

# Step 3: Sync configs to compute nodes
chmod +x sync_config_to_nodes.sh
./sync_config_to_nodes.sh

# Step 4: Check cluster status
export PATH=/usr/local/slurm/bin:$PATH
sinfo
sinfo -N

# Step 5: Resume nodes if needed
scontrol update NodeName=node001 State=RESUME
scontrol update NodeName=node002 State=RESUME
```

## 🔄 Clean Install (Recommended for Best Results)

For a completely clean installation with all fixes included:

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# Step 1: Clean up old installation
sudo systemctl stop slurmctld slurmd 2>/dev/null || true
sudo pkill -9 slurmctld slurmd 2>/dev/null || true

# Step 2: Remove old plugins
sudo rm -rf /usr/local/slurm/lib/slurm/*.so
sudo rm -rf /usr/local/slurm/lib/slurm.backup

# Step 3: Reinstall Slurm 23.11.x
sudo bash install_slurm_cgroup_v2.sh

# Step 4: Configure with updated script
sudo bash configure_slurm_cgroup_v2.sh

# Step 5: Start services
sudo systemctl start slurmctld
sleep 3
sudo systemctl status slurmctld

# Step 6: Sync to compute nodes
./sync_config_to_nodes.sh
```

## 📊 Verification

After applying the fix, verify everything is working:

### Check Services
```bash
# Controller
sudo systemctl status slurmctld

# Check PID file
ls -la /run/slurm/slurmctld.pid

# Check logs
sudo tail -f /var/log/slurm/slurmctld.log
```

### Check Cluster Status
```bash
export PATH=/usr/local/slurm/bin:$PATH

# Node status
sinfo
sinfo -N

# Node details
scontrol show node

# Submit test job
cat > test_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=test
#SBATCH --output=test_%j.out
#SBATCH --cpus-per-task=2
#SBATCH --mem=1G

echo "Testing Slurm..."
echo "CPUs: $SLURM_CPUS_PER_TASK"
echo "Memory: $SLURM_MEM_PER_NODE MB"
cat /proc/self/cgroup
sleep 10
echo "Test complete!"
EOF

sbatch test_job.sh
squeue
```

## 🔍 Key Changes Made

### 1. **PID File Paths**
```diff
- PIDFile=/run/slurmctld.pid
+ PIDFile=/run/slurm/slurmctld.pid

- SlurmctldPidFile=/run/slurmctld.pid
+ SlurmctldPidFile=/run/slurm/slurmctld.pid
```

### 2. **Systemd Service Files**
Added these critical lines:
```ini
RuntimeDirectory=slurm
RuntimeDirectoryMode=0755
```
This ensures systemd automatically creates `/run/slurm` with correct permissions.

### 3. **tmpfiles.d Configuration**
Created `/etc/tmpfiles.d/slurm.conf`:
```
d /run/slurm 0755 slurm slurm -
```
This ensures `/run/slurm` is created on boot.

### 4. **cgroup.conf**
Removed deprecated/invalid keys:
```diff
- CgroupAutomount=yes
- TaskAffinity=yes
- MemoryLimitEnforce=yes
```

Kept only valid Slurm 23.11.x keys:
```ini
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=no
AllowedRAMSpace=100
AllowedSwapSpace=0
```

### 5. **Plugin Cleanup**
Backed up old incompatible plugins:
```bash
/usr/local/slurm/lib/slurm/select_cons_res.so  # Old 23.02.7
/usr/local/slurm/lib/slurm/mpi_none.so          # Old 23.02.7
```

## 🎯 Root Cause Analysis

### Why Did This Happen?

1. **Multiple Slurm Versions Mixed**
   - Old 23.02.7 installation not completely removed
   - New 23.11.10 installed on top
   - Incompatible shared libraries (.so files) remained

2. **PID File Path Issues**
   - Slurm daemon tried to write to `/run/slurm/slurmctld.pid`
   - Directory `/run/slurm` didn't exist or had wrong permissions
   - systemd couldn't read PID file → timeout

3. **cgroup.conf Syntax Changes**
   - Old config had keys valid in Slurm 23.02.x
   - Those keys were removed/renamed in 23.11.x
   - Parser failed → daemon wouldn't start

4. **Permission Issues**
   - `/run/slurm` needed to be owned by `slurm:slurm`
   - Without `RuntimeDirectory`, systemd wouldn't create it
   - Daemon couldn't write PID file

## 🛡️ Prevention

To avoid these issues in the future:

1. **Clean Uninstall Before Upgrade**
   ```bash
   sudo systemctl stop slurmctld slurmd
   sudo rm -rf /usr/local/slurm
   sudo rm /etc/systemd/system/slurm*.service
   ```

2. **Use Updated Scripts**
   - Always use the latest `configure_slurm_cgroup_v2.sh`
   - It now includes all necessary fixes

3. **Verify After Installation**
   ```bash
   # Check version consistency
   /usr/local/slurm/sbin/slurmctld -V
   
   # Check plugins
   ls -la /usr/local/slurm/lib/slurm/*.so
   
   # Verify config syntax
   /usr/local/slurm/sbin/slurmctld -t
   ```

4. **Sync Configs Regularly**
   ```bash
   # After any config changes
   ./sync_config_to_nodes.sh
   ```

## 📚 Related Files

- `fix_slurmctld_complete.sh` - Main fix script
- `sync_config_to_nodes.sh` - Node synchronization script
- `configure_slurm_cgroup_v2.sh` - Updated configuration script (with fixes)
- `setup_cluster_full.sh` - Full setup script (can now run successfully)

## 💡 Tips

### If Nodes Show as DOWN
```bash
scontrol update NodeName=node001 State=RESUME
scontrol update NodeName=node002 State=RESUME
```

### If Config Changes Don't Take Effect
```bash
# Reconfigure running daemons
sudo scontrol reconfigure

# Or restart
sudo systemctl restart slurmctld
ssh node001 "sudo systemctl restart slurmd"
ssh node002 "sudo systemctl restart slurmd"
```

### Check cgroup v2
```bash
# Verify cgroup v2 is mounted
mount | grep cgroup2

# Check Slurm cgroup plugin
/usr/local/slurm/sbin/slurmd -C
```

## 🎉 Current Status

✅ **slurmctld is running successfully**
✅ **PID file created properly** at `/run/slurm/slurmctld.pid`
✅ **Cluster is operational** - 2 nodes in idle state
✅ **All fixes applied and tested**

You can now run `setup_cluster_full.sh` successfully!

## ❓ Still Having Issues?

If you encounter any problems:

1. **Check logs:**
   ```bash
   sudo journalctl -u slurmctld -n 100 --no-pager
   sudo tail -50 /var/log/slurm/slurmctld.log
   ```

2. **Verify permissions:**
   ```bash
   ls -la /run/slurm/
   ls -la /var/spool/slurm/
   ```

3. **Test configuration:**
   ```bash
   /usr/local/slurm/sbin/slurmctld -t
   ```

4. **Try the clean install approach** (see above)

---

**Created:** 2025-10-07  
**Status:** ✅ Fixed and Tested  
**Slurm Version:** 23.11.10 with cgroup v2 support



