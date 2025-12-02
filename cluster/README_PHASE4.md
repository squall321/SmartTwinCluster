# Phase 4: Slurm Multi-Master Configuration

Phase 4 implements Slurm workload manager with multi-master high availability using VIP-based primary controller selection and shared state storage via GlusterFS.

## Overview

**Components:**
- `setup/phase3_slurm.sh` - Slurm setup script with multi-master support
- `config/slurm_template.conf` - Dynamic Slurm configuration template
- Integration with Phase 1 (GlusterFS) for shared state
- Integration with Phase 2 (MariaDB) for accounting database

**Features:**
- Multi-master slurmctld configuration
- VIP-based primary controller selection
- Automatic failover on VIP transfer
- Shared StateSaveLocation via GlusterFS
- SlurmDBD with MariaDB Galera backend
- Dynamic node and partition configuration

## Prerequisites

1. **Phase 0-3 Completed**: GlusterFS, MariaDB, and Redis must be operational
2. **GlusterFS Mounted**: `/mnt/gluster` must be mounted and accessible
3. **Munge Installed**: Authentication via Munge
4. **Configuration File**: `my_multihead_cluster.yaml` with Slurm configuration
5. **Network**: VIP configured and Keepalived managing failover

## Slurm Multi-Master Architecture

### Traditional vs Multi-Master

**Traditional Slurm:**
```
┌─────────────┐
│  Controller │ ← Single point of failure
│  (Primary)  │
└─────────────┘
      │
  ┌───┴───┐
  │       │
Node1   Node2
```

**Multi-Master Slurm:**
```
                    VIP: 192.168.1.100
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
┌───────┴──────┐   ┌───────┴──────┐   ┌───────┴──────┐
│ Controller 1 │   │ Controller 2 │   │ Controller 3 │
│  (Primary)   │   │   (Backup)   │   │   (Backup)   │
│  VIP Owner   │   │              │   │              │
└──────────────┘   └──────────────┘   └──────────────┘
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                   Shared State (GlusterFS)
                   /mnt/gluster/slurm/state/
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
     Node1              Node2              Node3
```

### Key Concepts

**SlurmctldHost:**
- Multiple controllers listed in slurm.conf
- First controller is primary (VIP owner)
- Others are backups
- Automatic failover if primary fails

**VIP (Virtual IP):**
- Managed by Keepalived (Phase 5)
- Points to current primary controller
- Failover moves VIP to backup controller
- Slurm uses VIP for all communications

**Shared State Directory:**
- StateSaveLocation: `/mnt/gluster/slurm/state/`
- Stores job state, node state, partition state
- Accessible by all controllers via GlusterFS
- Enables seamless failover

## Slurm Setup

### Usage

```bash
# Setup controller (with auto-detection)
sudo ./cluster/setup/phase3_slurm.sh --controller

# Setup controller + SlurmDBD (on first controller)
sudo ./cluster/setup/phase3_slurm.sh --controller --dbd

# Setup compute node
sudo ./cluster/setup/phase3_slurm.sh --compute

# Dry-run to preview changes
./cluster/setup/phase3_slurm.sh --controller --dry-run
```

### Options

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to my_multihead_cluster.yaml |
| `--controller` | Setup as controller (slurmctld) |
| `--compute` | Setup as compute node (slurmd) |
| `--dbd` | Setup SlurmDBD (accounting database daemon) |
| `--dry-run` | Show what would be done without executing |
| `--help` | Show help message |

### Setup Process

**Controller Setup (13 steps):**
1. Check root privileges
2. Check dependencies (python3, jq, munge)
3. Load configuration from YAML
4. Detect operating system
5. Check if Slurm is installed
6. Install Slurm if needed
7. Create slurm user and directories
8. Setup Munge authentication
9. Check GlusterFS is mounted
10. Create shared directories on GlusterFS
11. Generate slurm.conf from template
12. Setup SlurmDBD (if --dbd specified)
13. Start slurmctld service

**Compute Node Setup:**
1-8. Same as controller
9. Copy slurm.conf from shared storage
10. Start slurmd service

## Configuration Generation

### Dynamic slurm.conf Generation

The script generates slurm.conf from template with these substitutions:

**Cluster Configuration:**
```bash
ClusterName={{CLUSTER_NAME}}  # From YAML: cluster.name
```

**Controller Configuration:**
```bash
# VIP owner is primary (listed first)
SlurmctldHost=server1(192.168.1.101)
SlurmctldHost=server2(192.168.1.102)
SlurmctldHost=server3(192.168.1.103)
```

**Shared State:**
```bash
StateSaveLocation={{GLUSTER_MOUNT}}/slurm/state
# Expands to: /mnt/gluster/slurm/state
```

**Accounting:**
```bash
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost={{VIP_ADDRESS}}
# Expands to VIP address, points to SlurmDBD
```

**Nodes:**
```bash
# From YAML: nodes.compute_nodes
NodeName=node[001-010] CPUs=8 RealMemory=16384 TmpDisk=102400 State=UNKNOWN
```

**Partitions:**
```bash
# From YAML: slurm.partitions
PartitionName=debug Nodes=ALL Default=YES MaxTime=INFINITE State=UP
PartitionName=batch Nodes=node[001-010] Default=NO MaxTime=24:00:00 State=UP
```

### SlurmDBD Configuration

**slurmdbd.conf:**
```conf
AuthType=auth/munge
DbdHost=localhost
DbdPort=6819
SlurmUser=slurm
LogFile=/var/log/slurm/slurmdbd.log

# Database connection (MariaDB Galera via VIP)
StorageType=accounting_storage/mysql
StorageHost={{VIP_ADDRESS}}
StoragePort=3306
StorageUser=slurm
StoragePass=slurm_db_password
StorageLoc=slurm_acct_db
```

**Database Setup:**
```sql
CREATE DATABASE slurm_acct_db;
CREATE USER 'slurm'@'%' IDENTIFIED BY 'slurm_db_password';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'%';
```

## Example Scenarios

### Scenario 1: Setup 3-Node Slurm Cluster

**Configuration (my_multihead_cluster.yaml):**
```yaml
cluster:
  name: my_cluster

network:
  vip:
    address: 192.168.1.100

storage:
  glusterfs:
    mount_point: /mnt/gluster

nodes:
  controllers:
    - hostname: server1
      ip_address: 192.168.1.101
      vip_owner: true
      services:
        slurm: true
    - hostname: server2
      ip_address: 192.168.1.102
      services:
        slurm: true
    - hostname: server3
      ip_address: 192.168.1.103
      services:
        slurm: true

  compute_nodes:
    - hostname: node001
      cpus: 16
      real_memory: 65536
      tmp_disk: 204800
    - hostname: node002
      cpus: 16
      real_memory: 65536
      tmp_disk: 204800

slurm:
  partitions:
    - name: debug
      nodes: ALL
      default: true
      max_time: INFINITE
      state: UP
```

**Setup Process:**

**On server1 (VIP owner, primary controller):**
```bash
# Setup controller + SlurmDBD
sudo ./cluster/setup/phase3_slurm.sh --controller --dbd

# Output:
# [INFO] Current node: server1 (192.168.1.101)
# [INFO] Total Slurm-enabled controllers: 3
# [INFO] VIP address: 192.168.1.100
# [INFO] VIP owner: 192.168.1.101
# [INFO] Primary controller: server1 (192.168.1.101)
# [INFO] Backup controller: server2 (192.168.1.102)
# [INFO] Backup controller: server3 (192.168.1.103)
# [SUCCESS] Slurm configuration written to /etc/slurm/slurm.conf
# [SUCCESS] SlurmDBD database created
# [SUCCESS] SlurmDBD started
# [SUCCESS] slurmctld started successfully
```

**On server2 and server3 (backup controllers):**
```bash
sudo ./cluster/setup/phase3_slurm.sh --controller

# Output:
# [INFO] Backup controller: server2 (192.168.1.102)
# [SUCCESS] slurmctld started successfully
```

**On compute nodes:**
```bash
sudo ./cluster/setup/phase3_slurm.sh --compute

# Output:
# [INFO] Copying slurm.conf from shared storage...
# [SUCCESS] slurmd started successfully
```

**Verify cluster:**
```bash
sinfo

# Output:
# PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
# debug*       up   infinite      2   idle node[001-002]

scontrol show config | head -20

# Shows:
# ClusterName = my_cluster
# SlurmctldHost = server1(192.168.1.101)
# SlurmctldHost = server2(192.168.1.102)
# SlurmctldHost = server3(192.168.1.103)
```

### Scenario 2: Test Failover

**Initial state:**
```bash
# Check which controller is primary
scontrol show config | grep SlurmctldHost

# SlurmctldHost = server1(192.168.1.101) (Primary, VIP owner)
# SlurmctldHost = server2(192.168.1.102) (Backup)
# SlurmctldHost = server3(192.168.1.103) (Backup)

# Submit test job
sbatch --wrap="sleep 300"

# Submitted batch job 1
```

**Simulate failure (stop server1):**
```bash
# On server1
sudo systemctl stop slurmctld
sudo systemctl stop keepalived  # VIP moves to server2
```

**Keepalived failover:**
- VIP (192.168.1.100) moves from server1 to server2
- server2 becomes new VIP owner
- Slurm detects primary controller is down
- server2's slurmctld takes over as primary

**Verify failover:**
```bash
# On any node
squeue

# Shows running job (state preserved via shared GlusterFS)
# JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST
#     1     debug     wrap     root  R       0:45      1 node001

# Job continues running without interruption!
```

**Recover server1:**
```bash
# On server1
sudo systemctl start slurmctld
sudo systemctl start keepalived

# server1 rejoins as backup controller
# VIP may return to server1 (depends on Keepalived priority)
```

### Scenario 3: Add New Compute Node

**Update YAML:**
```yaml
nodes:
  compute_nodes:
    - hostname: node003
      cpus: 16
      real_memory: 65536
      tmp_disk: 204800
```

**Regenerate slurm.conf:**
```bash
# On primary controller (server1)
sudo ./cluster/setup/phase3_slurm.sh --controller

# This regenerates slurm.conf with node003
```

**Setup new node:**
```bash
# On node003
sudo ./cluster/setup/phase3_slurm.sh --compute
```

**Add to cluster:**
```bash
# On controller
scontrol update nodename=node003 state=idle

# Verify
sinfo
# Should show node003 in idle state
```

### Scenario 4: Job Accounting

**Create account and user:**
```bash
# Add cluster to accounting
sacctmgr add cluster my_cluster

# Add account
sacctmgr add account research

# Add user to account
sacctmgr add user alice account=research

# Show accounts
sacctmgr show account
sacctmgr show user
```

**Submit job as user:**
```bash
# Submit job
sbatch -A research --wrap="sleep 60"

# Check accounting
sacct -j <jobid>

# Shows:
# JobID    JobName  Partition Account  AllocCPUS   State ExitCode
# 1        wrap     debug     research         1  COMPLETED  0:0
```

**Usage reports:**
```bash
# Usage by account
sreport cluster AccountUtilizationByUser start=2025-10-01

# Usage by user
sreport user top start=2025-10-01
```

## Troubleshooting

### Issue: slurmctld fails to start

```bash
# Check logs
sudo journalctl -u slurmctld -n 100

# Common causes:
# 1. GlusterFS not mounted
mount | grep gluster

# 2. Permissions on state directory
ls -la /mnt/gluster/slurm/state
sudo chown -R slurm:slurm /mnt/gluster/slurm

# 3. Munge not working
munge -n | unmunge
sudo systemctl restart munge

# 4. Syntax error in slurm.conf
slurmctld -C  # Check config syntax
```

### Issue: Nodes in DOWN state

```bash
# Check node status
scontrol show node node001

# Common causes:
# 1. slurmd not running on node
ssh node001 "sudo systemctl status slurmd"

# 2. Munge key mismatch
# Copy munge key from controller to all nodes
sudo scp /etc/munge/munge.key node001:/etc/munge/
ssh node001 "sudo systemctl restart munge"

# 3. Node cannot reach controller
ssh node001 "ping -c 3 192.168.1.100"  # VIP

# Manually set node to IDLE
scontrol update nodename=node001 state=idle
```

### Issue: Jobs not starting

```bash
# Check job reason
squeue --start

# Shows:
# JOBID  PARTITION  START_TIME  NODELIST(REASON)
# 123    debug      N/A         (Resources)

# Common reasons:
# - Resources: Not enough free nodes
# - Priority: Other jobs have higher priority
# - QOSMaxCpuPerUserLimit: User hit QOS limit
# - ReqNodeNotAvail: Requested node is down

# Check partition state
scontrol show partition debug

# Check available resources
sinfo -Nel
```

### Issue: SlurmDBD connection failed

```bash
# Check SlurmDBD status
sudo systemctl status slurmdbd

# Check database connection
mysql -h 192.168.1.100 -u slurm -p slurm_acct_db

# Check slurmdbd.conf
sudo cat /etc/slurm/slurmdbd.conf

# Restart slurmdbd
sudo systemctl restart slurmdbd

# Test connection from slurmctld
sacctmgr show cluster
```

### Issue: State file corruption

```bash
# Backup current state
sudo cp -r /mnt/gluster/slurm/state /mnt/gluster/slurm/state.backup

# Stop all controllers
sudo systemctl stop slurmctld  # On all controllers

# Clear state (DANGER: loses job history)
sudo rm -rf /mnt/gluster/slurm/state/*

# Start primary controller
sudo systemctl start slurmctld  # On primary only

# Start backup controllers
sudo systemctl start slurmctld  # On backups
```

## Monitoring

### Cluster Health

```bash
# Quick status
sinfo

# Expected output:
# PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
# debug*       up   infinite      2   idle node[001-002]

# Detailed partition info
scontrol show partition

# Node details
scontrol show nodes

# Show down nodes
sinfo -R
```

### Job Monitoring

```bash
# Running jobs
squeue

# Job details
scontrol show job <jobid>

# Job accounting
sacct -j <jobid>

# All jobs for user
squeue -u alice

# All jobs in partition
squeue -p debug
```

### Controller Monitoring

```bash
# Check which controller is primary
scontrol show config | grep SlurmctldHost

# Check slurmctld status
sudo systemctl status slurmctld

# Check logs
sudo journalctl -u slurmctld -f

# Check daemon ping
scontrol ping

# Shows:
# Slurmctld(primary) at server1 is UP
```

### Accounting Database

```bash
# Cluster usage
sreport cluster utilization

# User usage
sreport user top

# Job summary
sacct --starttime=2025-10-01 --format=jobid,user,account,partition,state,elapsed
```

### Important Metrics

| Metric | Command | Healthy Value |
|--------|---------|---------------|
| Nodes Up | `sinfo -t idle,alloc` | All nodes in idle/alloc |
| Jobs Running | `squeue` | Jobs running smoothly |
| Controller Ping | `scontrol ping` | Primary UP |
| DBD Connection | `sacctmgr show cluster` | Shows cluster |
| Shared State | `ls /mnt/gluster/slurm/state` | Files present |

## Best Practices

### 1. Always Use Shared State Directory

**Why:** Enables seamless failover without job loss

```conf
StateSaveLocation=/mnt/gluster/slurm/state  # Shared via GlusterFS
```

**Not:**
```conf
StateSaveLocation=/var/spool/slurmctld  # Local, not shared
```

### 2. List VIP Owner First in SlurmctldHost

**Correct:**
```conf
SlurmctldHost=server1(192.168.1.101)  # VIP owner, primary
SlurmctldHost=server2(192.168.1.102)  # Backup
```

**Not:**
```conf
SlurmctldHost=server2(192.168.1.102)  # Wrong order
SlurmctldHost=server1(192.168.1.101)
```

### 3. Use VIP for All Communications

**Applications should connect to:**
- VIP address (192.168.1.100)
- Not individual controller IPs

**Benefits:**
- Automatic failover
- No client reconfiguration needed

### 4. Regular State Directory Backups

```bash
# Backup Slurm state
tar czf slurm-state-$(date +%F).tar.gz /mnt/gluster/slurm/state

# Automated daily backup
0 3 * * * tar czf /mnt/gluster/backups/slurm-state-$(date +%F).tar.gz /mnt/gluster/slurm/state
```

### 5. Monitor Controller Failover

```bash
# Monitor slurmctld status
watch -n 5 'scontrol ping'

# Monitor VIP ownership
watch -n 5 'ip addr show | grep 192.168.1.100'
```

### 6. Sync Munge Keys

**All nodes must have identical munge.key:**
```bash
# Copy from controller to all nodes
sudo scp /etc/munge/munge.key node001:/etc/munge/
sudo scp /etc/munge/munge.key node002:/etc/munge/

# Set permissions
ssh node001 "sudo chown munge:munge /etc/munge/munge.key && sudo chmod 400 /etc/munge/munge.key"

# Restart munge
ssh node001 "sudo systemctl restart munge"
```

### 7. Use SlurmDBD for Accounting

**Benefits:**
- Fair-share scheduling
- Usage reports
- Charge-back data
- Historical job data

**Setup:**
```bash
sudo ./cluster/setup/phase3_slurm.sh --controller --dbd
```

## Integration with Other Phases

Phase 4 Slurm integrates with:

- **Phase 1 (GlusterFS)**: Shared state directory, logs, spool
- **Phase 2 (MariaDB Galera)**: SlurmDBD accounting database
- **Phase 5 (Keepalived)**: VIP management, automatic failover
- **Phase 6 (Web Services)**: Job submission portal, monitoring dashboard

## Configuration Reference

### YAML Configuration

```yaml
cluster:
  name: my_cluster

network:
  vip:
    address: 192.168.1.100

storage:
  glusterfs:
    mount_point: /mnt/gluster

database:
  mariadb:
    host: 192.168.1.100  # VIP
    root_password: ${MARIADB_ROOT_PASSWORD}

nodes:
  controllers:
    - hostname: server1
      ip_address: 192.168.1.101
      vip_owner: true
      services:
        slurm: true

  compute_nodes:
    - hostname: node001
      cpus: 16
      real_memory: 65536
      tmp_disk: 204800

slurm:
  partitions:
    - name: debug
      nodes: ALL
      default: true
      max_time: INFINITE
      state: UP
```

## Next Steps

After completing Phase 4:

1. **Verify Slurm is operational**
   ```bash
   sinfo
   scontrol ping
   ```

2. **Test job submission**
   ```bash
   sbatch --wrap="hostname && sleep 10"
   squeue
   ```

3. **Test failover**
   ```bash
   # Stop primary controller
   # Verify jobs continue running
   ```

4. **Proceed to Phase 5: Keepalived VIP Management**
   - Dynamic keepalived.conf generation
   - Health check scripts
   - Notification scripts
   - VIP failover testing

## References

- [Slurm Documentation](https://slurm.schedmd.com/documentation.html)
- [Slurm Multi-Cluster Operation](https://slurm.schedmd.com/multi_cluster.html)
- [SlurmDBD Documentation](https://slurm.schedmd.com/slurmdbd.html)
- [my_multihead_cluster.yaml Configuration](../my_multihead_cluster.yaml)
- [MULTIHEAD_IMPLEMENTATION_PLAN.md](../dashboard/MULTIHEAD_IMPLEMENTATION_PLAN.md)
