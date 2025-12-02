# Phase 8: Main Integration Script

Phase 8 provides unified orchestration scripts for managing the entire multi-head HPC cluster lifecycle.

## Overview

**Purpose:**
- Orchestrate complete cluster setup from Phase 0 through Phase 7
- Manage cluster lifecycle (start, stop, status)
- Handle dependencies between services
- Provide consistent management interface

**Scripts:**
1. **start_multihead.sh** - Setup and start all cluster services
2. **stop_multihead.sh** - Gracefully stop all cluster services
3. **status_multihead.sh** - Display comprehensive cluster status

## Scripts

### 1. start_multihead.sh

Main orchestration script that executes all setup phases in the correct order.

**Features:**
- Automatic dependency resolution
- Phase-by-phase execution with verification
- Dry-run mode for testing
- Single-phase execution
- Phase skipping
- Error handling with continue/abort options
- Comprehensive logging

**Usage:**
```bash
# Full cluster setup
sudo ./cluster/start_multihead.sh --config my_multihead_cluster.yaml

# Dry-run (preview without executing)
sudo ./cluster/start_multihead.sh --dry-run

# Run specific phase only
sudo ./cluster/start_multihead.sh --phase 1        # Phase number
sudo ./cluster/start_multihead.sh --phase storage  # Phase name

# Skip specific phases
sudo ./cluster/start_multihead.sh --skip-phase 6 --skip-phase 7

# Force re-setup even if already configured
sudo ./cluster/start_multihead.sh --force

# Skip SSL certificate generation (for testing)
sudo ./cluster/start_multihead.sh --skip-ssl

# Auto-confirm (no prompts)
sudo ./cluster/start_multihead.sh --auto-confirm
```

**Options:**
- `--config PATH` - Path to my_multihead_cluster.yaml
- `--phase PHASE` - Run specific phase (0-7 or name)
- `--skip-phase PHASE` - Skip specific phase
- `--dry-run` - Preview actions without executing
- `--force` - Force setup even if already configured
- `--skip-ssl` - Skip SSL certificate generation
- `--auto-confirm` - Skip confirmation prompts
- `--help` - Show help message

**Phase Names:**
- `0` or `infrastructure` - Basic infrastructure
- `1` or `storage` - GlusterFS
- `2` or `database` - MariaDB Galera
- `3` or `redis` - Redis Cluster
- `4` or `slurm` - Slurm Multi-Master
- `5` or `keepalived` - Keepalived VIP
- `6` or `web` - Web Services
- `7` or `backup` - Backup System

**Execution Flow:**

```
┌─────────────────────────────────────────────┐
│  1. Check Prerequisites                     │
│     - Root privileges                       │
│     - Config file exists                    │
│     - Parser available                      │
│     - Python 3 installed                    │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  2. Load Configuration                      │
│     - Parse YAML                            │
│     - Get cluster info                      │
│     - Identify current node                 │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  3. Display Execution Plan                  │
│     - List phases to execute                │
│     - Show service distribution             │
│     - Confirm with user                     │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  4. Execute Phases Sequentially             │
│                                             │
│  Phase 0: Infrastructure                    │
│  ├─ Verify parser                          │
│  ├─ Verify auto-discovery                  │
│  └─ Verify cluster_info                    │
│                                             │
│  Phase 1: GlusterFS                        │
│  ├─ Install packages                       │
│  ├─ Configure peers                        │
│  ├─ Create volumes                         │
│  └─ Mount volumes                          │
│                                             │
│  Phase 2: MariaDB Galera                   │
│  ├─ Install MariaDB                        │
│  ├─ Configure Galera                       │
│  ├─ Bootstrap/join cluster                 │
│  └─ Create databases                       │
│                                             │
│  Phase 3: Redis Cluster                    │
│  ├─ Install Redis                          │
│  ├─ Configure cluster/sentinel             │
│  ├─ Create cluster                         │
│  └─ Test connectivity                      │
│                                             │
│  Phase 4: Slurm Multi-Master               │
│  ├─ Install Slurm                          │
│  ├─ Configure multi-master                 │
│  ├─ Start services                         │
│  └─ Configure accounting                   │
│                                             │
│  Phase 5: Keepalived VIP                   │
│  ├─ Install Keepalived                     │
│  ├─ Configure VRRP                         │
│  ├─ Setup health checks                    │
│  └─ Start service                          │
│                                             │
│  Phase 6: Web Services                     │
│  ├─ Install Node.js/Nginx                  │
│  ├─ Deploy services                        │
│  ├─ Configure reverse proxy                │
│  ├─ Setup SSL                              │
│  └─ Start services                         │
│                                             │
│  Phase 7: Backup System                    │
│  └─ Verify backup utilities                │
│                                             │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  5. Verify Each Phase                       │
│     - Check service status                  │
│     - Test functionality                    │
│     - Log results                           │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  6. Display Summary                         │
│     - Show success/failure counts           │
│     - List next steps                       │
│     - Show access URLs                      │
└─────────────────────────────────────────────┘
```

**Example Output:**
```
╔════════════════════════════════════════════════════════════╗
║      Multi-Head HPC Cluster Setup Orchestration           ║
╚════════════════════════════════════════════════════════════╝

[INFO] Starting at: 2025-10-27 10:00:00
[INFO] Log file: /var/log/cluster_multihead_setup.log

[INFO] Checking prerequisites...
[SUCCESS] Prerequisites check passed

=== Cluster Configuration ===
[INFO] Cluster Name: my-hpc-cluster
[INFO] Current Node: 192.168.1.101
[INFO] Controllers:
  - server1 (192.168.1.101) - VIP Owner: true
  - server2 (192.168.1.102) - VIP Owner: false
  - server3 (192.168.1.103) - VIP Owner: false

=== Execution Plan ===
[INFO] Mode: Full Cluster Setup
[INFO] Phases to execute:
  Phase 0 (infrastructure)
  Phase 1 (storage)
  Phase 2 (database)
  Phase 3 (redis)
  Phase 4 (slurm)
  Phase 5 (keepalived)
  Phase 6 (web)
  Phase 7 (backup)

Do you want to proceed? (yes/no): yes

=== Beginning Cluster Setup ===

[PHASE 0] Basic Infrastructure Setup
[INFO] Verifying parser and utilities...
[SUCCESS] Configuration parser verified
[SUCCESS] Auto-discovery script found
[SUCCESS] Cluster info utility found
[SUCCESS] Phase 0 completed: Basic infrastructure ready
[SUCCESS] Phase 0 verification passed
[INFO] Waiting 5s before next phase...

[PHASE 1] storage Setup
[INFO] Executing: ./cluster/setup/phase0_storage.sh --config my_multihead_cluster.yaml
...
[SUCCESS] Phase 1 completed successfully
[SUCCESS] Phase 1 verification passed
[INFO] Waiting 5s before next phase...

[PHASE 2] database Setup
...

=== Execution Summary ===
[INFO] Total phases: 8
[SUCCESS] Successful: 8
[SUCCESS] All phases completed successfully!

[INFO] Cluster setup complete. Next steps:
  1. Verify cluster status: ./utils/cluster_info.sh --config my_multihead_cluster.yaml
  2. Check web services: ./utils/web_health_check.sh
  3. Test job submission: srun hostname
  4. Access web interface: https://cluster.example.com

[INFO] Finished at: 2025-10-27 10:45:00
```

**Error Handling:**

If a phase fails:
```
[ERROR] Phase 2 failed with exit code 1
Continue with next phase anyway? (yes/no):
```

Options:
- Type `yes` to continue with remaining phases
- Type `no` to abort (or Ctrl+C)
- Use `--auto-confirm` flag to automatically abort on errors

### 2. stop_multihead.sh

Gracefully stops all cluster services in reverse order to ensure clean shutdown.

**Features:**
- Reverse-order shutdown (dependencies first)
- Graceful stop with timeout
- Force stop option (SIGKILL)
- Selective service stopping
- Data preservation option
- Cleanup on stop

**Usage:**
```bash
# Stop all services
sudo ./cluster/stop_multihead.sh

# Stop specific service only
sudo ./cluster/stop_multihead.sh --service web
sudo ./cluster/stop_multihead.sh --service slurm
sudo ./cluster/stop_multihead.sh --service mariadb

# Force stop (SIGKILL if graceful fails)
sudo ./cluster/stop_multihead.sh --force

# Keep data mounted (don't umount GlusterFS)
sudo ./cluster/stop_multihead.sh --keep-data

# Auto-confirm (no prompts)
sudo ./cluster/stop_multihead.sh --auto-confirm
```

**Options:**
- `--config PATH` - Path to my_multihead_cluster.yaml
- `--service NAME` - Stop specific service only
- `--force` - Force stop (SIGKILL) if graceful fails
- `--keep-data` - Keep data volumes mounted
- `--auto-confirm` - Skip confirmation prompts
- `--help` - Show help message

**Service Names:**
- `web` - All web services
- `keepalived` - Keepalived VIP
- `slurm` - Slurm services
- `redis` - Redis cluster
- `mariadb` or `database` - MariaDB Galera
- `glusterfs` or `storage` - GlusterFS

**Stop Order (Reverse of Startup):**

```
1. Web Services
   ├─ nginx
   ├─ admin_portal
   ├─ metrics_api
   ├─ monitoring_dashboard
   ├─ file_service
   ├─ websocket_service
   ├─ job_api
   ├─ auth_service
   └─ dashboard

2. Keepalived
   ├─ Stop keepalived service
   └─ Remove VIP if present

3. Slurm
   ├─ slurmd (compute nodes)
   ├─ slurmctld (controller)
   └─ slurmdbd (accounting)

4. Redis
   ├─ Save data (SAVE command)
   └─ Stop redis instances

5. MariaDB
   ├─ Flush tables (Galera)
   └─ Stop mariadb service

6. GlusterFS
   ├─ Unmount volumes (unless --keep-data)
   └─ Stop glusterd service

7. Cleanup
   ├─ Remove PID files
   └─ Clean temp files (if --force)
```

**Example Output:**
```
╔════════════════════════════════════════════════════════════╗
║      Multi-Head HPC Cluster Stop                          ║
╚════════════════════════════════════════════════════════════╝

[INFO] Starting at: 2025-10-27 16:00:00
[INFO] Current node: 192.168.1.101

=== Current Service Status ===
  ● Web Server
  ● Dashboard
  ● Auth Service
  ● Job API
  ● Keepalived
  ● Slurm Controller
  ● Redis
  ● MariaDB
  ● GlusterFS

This will stop cluster services. Continue? (yes/no): yes

=== Stopping Cluster Services ===

=== Stopping Web Services ===
[INFO] Stopping nginx...
[SUCCESS] nginx stopped
[INFO] Stopping admin_portal...
[SUCCESS] admin_portal stopped
...
[SUCCESS] Web services stopped

=== Stopping Keepalived ===
[INFO] Stopping keepalived...
[SUCCESS] keepalived stopped
[WARNING] VIP 192.168.1.100 is still present, removing...
[SUCCESS] Keepalived stopped

=== Stopping Slurm ===
[INFO] Stopping slurmd...
[SUCCESS] slurmd stopped
[INFO] Stopping slurmctld...
[SUCCESS] slurmctld stopped
[INFO] Stopping slurmdbd...
[SUCCESS] slurmdbd stopped
[SUCCESS] Slurm stopped

=== Stopping Redis ===
[INFO] Redis mode: cluster
[INFO] Saving Redis cluster data...
[INFO] Stopping redis@6379...
[SUCCESS] redis@6379 stopped
...
[SUCCESS] Redis stopped

=== Stopping MariaDB ===
[INFO] Detected Galera cluster node
[INFO] Flushing MariaDB data...
[INFO] Stopping mariadb...
[SUCCESS] mariadb stopped
[SUCCESS] MariaDB stopped

=== Stopping GlusterFS ===
[INFO] Unmounting GlusterFS volumes...
[INFO] Unmounting /mnt/gluster...
[SUCCESS] /mnt/gluster unmounted
[INFO] Stopping glusterd...
[SUCCESS] glusterd stopped
[SUCCESS] GlusterFS stopped

=== Cleanup ===
[INFO] Removing /var/run/slurmctld.pid
[SUCCESS] Cleanup complete

=== Current Service Status ===
  ○ Web Server
  ○ Dashboard
  ○ Auth Service
  ○ Job API
  ○ Keepalived
  ○ Slurm Controller
  ○ Redis
  ○ MariaDB
  ○ GlusterFS

[SUCCESS] === Cluster services stopped ===
[INFO] Finished at: 2025-10-27 16:05:00
[INFO] Data volumes unmounted. To restart: sudo ./start_multihead.sh
```

### 3. status_multihead.sh

Displays comprehensive status information for all cluster services and resources.

**Features:**
- Real-time service status
- Cluster health checks
- Resource usage monitoring
- Network status (VIP, connectivity)
- Multiple output formats
- Watch mode (continuous refresh)
- Per-service status

**Usage:**
```bash
# Full status (default)
./cluster/status_multihead.sh

# Compact status
./cluster/status_multihead.sh --format compact

# JSON output
./cluster/status_multihead.sh --format json

# Specific service only
./cluster/status_multihead.sh --service slurm
./cluster/status_multihead.sh --service web

# Watch mode (refresh every 5s)
./cluster/status_multihead.sh --watch

# No colors (for scripts)
./cluster/status_multihead.sh --no-color

# All nodes (if multi-node)
./cluster/status_multihead.sh --all-nodes
```

**Options:**
- `--config PATH` - Path to my_multihead_cluster.yaml
- `--format FORMAT` - Output format: full, compact, json
- `--service NAME` - Show specific service only
- `--all-nodes` - Show status of all nodes
- `--watch` - Continuous monitoring (refresh every 5s)
- `--no-color` - Disable colored output
- `--help` - Show help message

**Example Output (Full):**
```
╔════════════════════════════════════════════════════════════╗
║      Multi-Head HPC Cluster Status                        ║
╚════════════════════════════════════════════════════════════╝

=== System Information ===
Hostname: server1
IP: 192.168.1.101
OS: Ubuntu 22.04.3 LTS
Kernel: 5.15.0-160-generic
Uptime: up 2 days, 5 hours, 23 minutes

=== Resource Usage ===
CPU Usage: 23.5%
Memory: 8.2G / 32G (25.6%)
Disk Usage: 45%
Load Average: 2.31, 1.95, 1.67

=== Cluster Services ===

GlusterFS: running
  Peers: 2
  Volumes: 1
  Volume 'gluster_volume': Started

MariaDB: running
  Galera Cluster:
    Size: 3 nodes
    Status: Primary
    Local State: Synced
    Ready: ON

Redis: running
  Mode: Cluster
    State: ok
    Size: 3 nodes
    Slots OK: 16384

Slurm: running
  Total Nodes: 24
  Idle: 18, Allocated: 6, Down: 0
  Jobs: Running=12, Pending=3
  Accounting: running

Keepalived: running
  VIP 192.168.1.100: MASTER (this node)
  VRRP State: MASTER

Web Services:
  ● Nginx
  ● Dashboard
  ● Auth Service
  ● Job API
  ● WebSocket
  ● File Service
  ● Monitoring
  ● Metrics API
  ● Admin Portal

=== Recent Errors (last 10) ===
  No recent errors
```

**Example Output (Compact):**
```
[server1 (192.168.1.101)]
  ● GlusterFS
  ● MariaDB
  ● Redis
  ● Slurm
  ● Keepalived
  ● Web
```

**Example Output (JSON):**
```json
{
  "hostname": "server1",
  "ip": "192.168.1.101",
  "timestamp": "2025-10-27T14:30:00Z",
  "uptime": "up 2 days, 5 hours",
  "services": {
    "glusterd": "running",
    "mariadb": "running",
    "redis-server": "running",
    "slurmctld": "running",
    "slurmdbd": "running",
    "keepalived": "running",
    "nginx": "running",
    "dashboard": "running",
    "auth_service": "running",
    "job_api": "running"
  }
}
```

**Watch Mode:**
```bash
./cluster/status_multihead.sh --watch
```

Screen refreshes every 5 seconds with updated status. Press Ctrl+C to exit.

## Integration with Other Phases

### Dependencies

The integration scripts depend on all previous phases:

- **Phase 0**: Config parser for YAML loading
- **Phase 1-7**: Individual setup scripts for each service

### Configuration

All scripts use the same `my_multihead_cluster.yaml` configuration:

```yaml
cluster:
  name: my-hpc-cluster

network:
  vip: 192.168.1.100

controllers:
  - hostname: server1
    ip: 192.168.1.101
    services:
      glusterfs: true
      mariadb: true
      redis: true
      slurm: true
      web: true
      keepalived: true
    vip_owner: true
    priority: 100

  - hostname: server2
    ip: 192.168.1.102
    services:
      glusterfs: true
      mariadb: true
      redis: true
      slurm: true
      web: true
      keepalived: true
    vip_owner: false
    priority: 90
```

## Common Workflows

### 1. Initial Cluster Setup

```bash
# Step 1: Prepare configuration
vim my_multihead_cluster.yaml

# Step 2: Validate configuration
python3 cluster/config/parser.py my_multihead_cluster.yaml validate

# Step 3: Dry-run to preview
sudo ./cluster/start_multihead.sh --dry-run

# Step 4: Execute full setup
sudo ./cluster/start_multihead.sh

# Step 5: Verify status
./cluster/status_multihead.sh

# Step 6: Check cluster info
./cluster/utils/cluster_info.sh

# Step 7: Check web services
./cluster/utils/web_health_check.sh
```

### 2. Add New Controller Node

```bash
# Step 1: Update YAML to add new controller
vim my_multihead_cluster.yaml

# Step 2: Run setup on new node
sudo ./cluster/start_multihead.sh

# Step 3: Verify cluster expanded
./cluster/status_multihead.sh --all-nodes
```

### 3. Maintenance Window

```bash
# Step 1: Check current status
./cluster/status_multihead.sh

# Step 2: Backup cluster
sudo ./cluster/backup/backup.sh --config my_multihead_cluster.yaml

# Step 3: Stop services
sudo ./cluster/stop_multihead.sh --keep-data

# Step 4: Perform maintenance
# ... maintenance tasks ...

# Step 5: Restart services
sudo ./cluster/start_multihead.sh --skip-phase 0 --skip-phase 1

# Step 6: Verify services
./cluster/status_multihead.sh
```

### 4. Disaster Recovery

```bash
# Step 1: Check what's running
./cluster/status_multihead.sh

# Step 2: Stop everything
sudo ./cluster/stop_multihead.sh --force

# Step 3: Restore from backup
sudo ./cluster/backup/restore.sh --latest

# Step 4: Full restart
sudo ./cluster/start_multihead.sh

# Step 5: Verify recovery
./cluster/status_multihead.sh
./cluster/utils/cluster_info.sh
```

### 5. Selective Service Restart

```bash
# Restart only web services
sudo ./cluster/stop_multihead.sh --service web
sudo ./cluster/start_multihead.sh --phase 6

# Restart only Slurm
sudo ./cluster/stop_multihead.sh --service slurm
sudo ./cluster/start_multihead.sh --phase 4

# Restart only database
sudo ./cluster/stop_multihead.sh --service mariadb
sudo ./cluster/start_multihead.sh --phase 2
```

## Logging

All scripts log to `/var/log/cluster_multihead_*.log`:

```bash
# View setup log
tail -f /var/log/cluster_multihead_setup.log

# View stop log
tail -f /var/log/cluster_multihead_stop.log

# View all cluster logs
tail -f /var/log/cluster_*.log
```

## Monitoring

### Systemd Service

Create a systemd service for status monitoring:

```ini
# /etc/systemd/system/cluster-monitor.service
[Unit]
Description=Cluster Status Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=/path/to/cluster/status_multihead.sh --format json > /var/log/cluster_status.json

[Install]
WantedBy=multi-user.target
```

```bash
# Enable timer for periodic checks
cat > /etc/systemd/system/cluster-monitor.timer << EOF
[Unit]
Description=Cluster Status Monitor Timer

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl enable --now cluster-monitor.timer
```

### Cron Job

```bash
# Add to crontab
sudo crontab -e

# Check status every 5 minutes
*/5 * * * * /path/to/cluster/status_multihead.sh --format json > /var/log/cluster_status.json
```

## Troubleshooting

### Issue: Phase fails during setup

**Check logs:**
```bash
tail -f /var/log/cluster_multihead_setup.log
```

**Retry specific phase:**
```bash
sudo ./cluster/start_multihead.sh --phase 2  # Retry phase 2
```

**Force re-setup:**
```bash
sudo ./cluster/start_multihead.sh --phase 2 --force
```

### Issue: Services won't stop

**Force stop:**
```bash
sudo ./cluster/stop_multihead.sh --force
```

**Check what's still running:**
```bash
./cluster/status_multihead.sh --format compact
```

**Kill specific service:**
```bash
sudo systemctl kill -s SIGKILL mariadb
```

### Issue: Status shows service down but it's running

**Check systemd status:**
```bash
systemctl status mariadb
journalctl -u mariadb -n 50
```

**Restart systemd:**
```bash
sudo systemctl daemon-reload
```

### Issue: Script hangs during execution

**Check for prompts:**
- Some phases may have interactive prompts
- Use `--auto-confirm` to skip prompts

**Check for locks:**
```bash
# Check for apt locks
sudo lsof /var/lib/dpkg/lock-frontend

# Check for systemd locks
sudo systemctl list-jobs
```

**Kill hung process:**
```bash
# Find process
ps aux | grep phase

# Kill it
sudo kill -9 <PID>
```

## Best Practices

### 1. Always Backup Before Changes

```bash
sudo ./cluster/backup/backup.sh --config my_multihead_cluster.yaml
```

### 2. Use Dry-Run First

```bash
sudo ./cluster/start_multihead.sh --dry-run
```

### 3. Monitor Logs During Execution

```bash
# Terminal 1: Run setup
sudo ./cluster/start_multihead.sh

# Terminal 2: Monitor logs
tail -f /var/log/cluster_multihead_setup.log
```

### 4. Verify After Each Phase

```bash
sudo ./cluster/start_multihead.sh --phase 1
./cluster/status_multihead.sh --service glusterfs
```

### 5. Document Custom Changes

```bash
# Keep a changelog
echo "$(date): Added new controller server4" >> CLUSTER_CHANGES.log
```

## Performance Considerations

### Parallel Execution

Currently, phases run sequentially. For faster setup on multiple nodes:

```bash
# Run on all nodes in parallel (using GNU parallel or similar)
parallel-ssh -h nodes.txt "sudo ./cluster/start_multihead.sh" &
```

### Resource Usage

- Setup scripts are CPU and I/O intensive
- Expect high network usage during:
  - GlusterFS volume creation
  - MariaDB SST (State Snapshot Transfer)
  - Redis cluster creation
  - Package downloads

### Timeouts

Default timeouts:
- Service stop: 30s (60s for Galera)
- Health checks: 5s
- Phase completion: No limit

Adjust in scripts if needed for slower systems.

## Security

### Credentials

All credentials are loaded from YAML with environment variable substitution:

```yaml
database:
  password: ${DB_ROOT_PASSWORD}

redis:
  password: ${REDIS_PASSWORD}

web:
  jwt_secret: ${JWT_SECRET}
  session_secret: ${SESSION_SECRET}
```

Set environment variables before running:
```bash
export DB_ROOT_PASSWORD='secure_password'
export REDIS_PASSWORD='secure_password'
export JWT_SECRET='secure_random_string'
export SESSION_SECRET='secure_random_string'

sudo -E ./cluster/start_multihead.sh
```

### Sudo Requirements

Scripts require root for:
- Installing packages
- Configuring system services
- Mounting filesystems
- Configuring network (VIP)

### Log Permissions

Logs may contain sensitive information. Restrict access:

```bash
sudo chmod 600 /var/log/cluster_*.log
```

## Next Steps

After completing Phase 8:

1. **Proceed to Phase 9: Testing and Validation**
   - Functional tests
   - Failure scenario tests
   - Performance benchmarks

2. **Setup Monitoring**
   - Configure Prometheus
   - Setup Grafana dashboards
   - Enable alerts

3. **Production Deployment**
   - Review security settings
   - Configure backups
   - Document procedures

## Summary

Phase 8 provides:
- ✅ Unified cluster orchestration
- ✅ Complete lifecycle management
- ✅ Dependency resolution
- ✅ Error handling and recovery
- ✅ Comprehensive status monitoring
- ✅ Flexible execution (single/multi-phase)
- ✅ Dry-run support
- ✅ Detailed logging

The cluster can now be managed with three simple commands:
- `start_multihead.sh` - Setup/start
- `stop_multihead.sh` - Stop
- `status_multihead.sh` - Check status

## References

- [Phase 0: Basic Infrastructure](README_PHASE0.md)
- [Phase 1: GlusterFS](README_PHASE1.md)
- [Phase 2: MariaDB Galera](README_PHASE2.md)
- [Phase 3: Redis Cluster](README_PHASE3.md)
- [Phase 4: Slurm Multi-Master](README_PHASE4.md)
- [Phase 5: Keepalived VIP](README_PHASE5.md)
- [Phase 6: Web Services](README_PHASE6.md)
- [Phase 7: Backup and Restore](README_PHASE7.md)
- [my_multihead_cluster.yaml Configuration](../../my_multihead_cluster.yaml)
- [MULTIHEAD_IMPLEMENTATION_PLAN.md](../../MULTIHEAD_IMPLEMENTATION_PLAN.md)
