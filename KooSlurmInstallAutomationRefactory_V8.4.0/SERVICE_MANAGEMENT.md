# 🚀 Slurm Service Management Scripts

## 📋 Overview

Two new scripts have been created to easily manage your Slurm cluster services:

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `start_slurm_cluster.sh` | Start all services | After setup or reboot |
| `stop_slurm_cluster.sh` | Stop all services | Maintenance or shutdown |

---

## 🚀 Starting the Cluster

### After Setup
Once `setup_cluster_full.sh` completes, start all services:

```bash
./start_slurm_cluster.sh
```

### What It Does
1. ✅ Starts `slurmctld` on the controller
2. ✅ Starts `slurmd` on all compute nodes (node001, node002)
3. ✅ Waits for nodes to register
4. ✅ Shows cluster status

### Output Example
```
🚀 Starting Slurm Cluster Services
================================================================================

📋 Step 1/4: Starting Controller (slurmctld)...
✅ slurmctld started successfully

📋 Step 2/4: Starting Compute Nodes (slurmd)...
  ✅ 192.168.122.90: slurmd started successfully
  ✅ 192.168.122.103: slurmd started successfully

📋 Step 3/4: Waiting for nodes to register...
✅ Wait complete

📋 Step 4/4: Checking Cluster Status...
📊 Cluster Information:
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up 7-00:00:00      2   idle node[001-002]
debug        up      30:00      1   idle node001

✅ Slurm Cluster Services Started
Status Summary:
  Controller:    ✅ Running
  Idle Nodes:    2
  Down Nodes:    0
```

---

## 🛑 Stopping the Cluster

### Before Maintenance
Stop all services cleanly:

```bash
./stop_slurm_cluster.sh
```

### What It Does
1. ✅ Stops `slurmd` on all compute nodes first (graceful)
2. ✅ Waits for clean shutdown
3. ✅ Stops `slurmctld` on the controller
4. ✅ Verifies all processes stopped

### Output Example
```
🛑 Stopping Slurm Cluster Services
================================================================================

📋 Step 1/3: Stopping Compute Nodes (slurmd)...
  ✅ 192.168.122.90: slurmd stopped successfully
  ✅ 192.168.122.103: slurmd stopped successfully

📋 Step 2/3: Waiting for clean shutdown...
✅ Wait complete

📋 Step 3/3: Stopping Controller (slurmctld)...
✅ slurmctld stopped successfully
✅ All slurmctld processes stopped

✅ Slurm Cluster Services Stopped
All services stopped:
  ✅ Controller (slurmctld) - Stopped
  ✅ Compute nodes (slurmd) - Stopped
```

---

## 📊 Checking Service Status

### Quick Status Check
```bash
# Controller
sudo systemctl status slurmctld

# Individual compute nodes
ssh koopark@192.168.122.90 "sudo systemctl status slurmd"
ssh koopark@192.168.122.103 "sudo systemctl status slurmd"

# Cluster view
sinfo
sinfo -N
```

### Detailed Check
```bash
# All services at once
sudo systemctl status slurmctld
ssh koopark@192.168.122.90 "sudo systemctl status slurmd"
ssh koopark@192.168.122.103 "sudo systemctl status slurmd"

# Node states
scontrol show nodes

# Cluster diagnostics
sdiag
scontrol ping
```

---

## 🔄 Common Workflows

### After System Reboot
```bash
# Start everything
./start_slurm_cluster.sh

# Check status
sinfo

# Resume nodes if DOWN
scontrol update NodeName=node001 State=RESUME
scontrol update NodeName=node002 State=RESUME
```

### Before System Maintenance
```bash
# Drain nodes (stop accepting new jobs)
scontrol update NodeName=node001 State=DRAIN Reason="Maintenance"
scontrol update NodeName=node002 State=DRAIN Reason="Maintenance"

# Wait for running jobs to complete
watch squeue

# Stop cluster
./stop_slurm_cluster.sh
```

### After Configuration Changes
```bash
# Stop cluster
./stop_slurm_cluster.sh

# Make configuration changes
sudo vim /usr/local/slurm/etc/slurm.conf

# Sync to nodes
./sync_config_to_nodes.sh

# Start cluster
./start_slurm_cluster.sh
```

### Quick Restart
```bash
./stop_slurm_cluster.sh
sleep 3
./start_slurm_cluster.sh
```

---

## 🐛 Troubleshooting

### Services Won't Start

**Check logs:**
```bash
# Controller
sudo journalctl -u slurmctld -n 50
sudo tail -50 /var/log/slurm/slurmctld.log

# Compute nodes
ssh koopark@192.168.122.90 "sudo journalctl -u slurmd -n 50"
```

**Fix common issues:**
```bash
# Fix permissions
sudo ./fix_slurmctld_complete.sh

# Sync configs
./sync_config_to_nodes.sh

# Try starting again
./start_slurm_cluster.sh
```

### Nodes Show as DOWN

```bash
# Resume nodes
scontrol update NodeName=node001 State=RESUME
scontrol update NodeName=node002 State=RESUME

# Check node details
scontrol show node node001
scontrol show node node002
```

### Services Won't Stop

**Force stop:**
```bash
# Stop services
./stop_slurm_cluster.sh

# If still running, force kill
sudo pkill -9 slurmctld
ssh koopark@192.168.122.90 "sudo pkill -9 slurmd"
ssh koopark@192.168.122.103 "sudo pkill -9 slurmd"
```

### SSH Connection Issues

```bash
# Test connectivity
ssh koopark@192.168.122.90 "echo OK"
ssh koopark@192.168.122.103 "echo OK"

# Start nodes manually
ssh koopark@192.168.122.90 "sudo systemctl start slurmd"
ssh koopark@192.168.122.103 "sudo systemctl start slurmd"
```

---

## 🎯 Configuration

### Modify Node List

Edit both scripts to match your cluster:

```bash
# Edit compute nodes
vim start_slurm_cluster.sh
vim stop_slurm_cluster.sh

# Find this line and modify:
COMPUTE_NODES=("192.168.122.90" "192.168.122.103")
```

### Change SSH User

```bash
# Find this line:
SSH_USER="koopark"

# Change to your username
```

---

## 📚 Related Documentation

- **QUICK_REFERENCE.md** - Quick command reference
- **SETUP_FIX_GUIDE.md** - Troubleshooting guide
- **CURRENT_STATUS.md** - Current cluster status
- **SLURM_PATH_GUIDE.md** - PATH configuration

---

## ✅ Quick Reference

| Command | Description |
|---------|-------------|
| `./start_slurm_cluster.sh` | Start controller + all compute nodes |
| `./stop_slurm_cluster.sh` | Stop all nodes + controller |
| `sinfo` | View cluster status |
| `squeue` | View job queue |
| `scontrol show node` | Show node details |
| `sudo systemctl status slurmctld` | Check controller status |
| `ssh node "sudo systemctl status slurmd"` | Check node status |

---

## 🎉 Summary

**After `setup_cluster_full.sh` completes:**
1. Run `./start_slurm_cluster.sh` to start all services
2. Check status with `sinfo`
3. Submit jobs with `sbatch`
4. When done, stop with `./stop_slurm_cluster.sh`

**Simple and easy!** 🚀



