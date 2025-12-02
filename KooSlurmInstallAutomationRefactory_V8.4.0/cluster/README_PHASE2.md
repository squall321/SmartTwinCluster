# Phase 2: MariaDB Galera Cluster

Phase 2 implements MariaDB Galera cluster for multi-master database replication with automatic failover and dynamic node management.

## Overview

**Components:**
- `setup/phase1_database.sh` - MariaDB Galera setup script with auto bootstrap/join detection
- `config/galera_template.cnf` - Dynamic Galera configuration template
- `utils/db_backup.sh` - Database backup utility with mariabackup
- `utils/db_restore.sh` - Database restore utility

**Features:**
- Multi-master synchronous replication
- Automatic bootstrap vs join mode detection
- Dynamic configuration generation from YAML
- SST (State Snapshot Transfer) for new nodes
- Quorum-based split-brain protection
- Hot backup without downtime
- Point-in-time recovery

## Prerequisites

1. **Configuration File**: `my_multihead_cluster.yaml` with MariaDB-enabled controllers
2. **Network**: SSH connectivity and ports 3306, 4444, 4567, 4568 open
3. **Permissions**: Root/sudo access
4. **Dependencies**: Python 3 with PyYAML, jq, mariabackup

## MariaDB Galera Setup

### Usage

```bash
# Auto mode (recommended) - detects bootstrap vs join automatically
sudo ./cluster/setup/phase1_database.sh --config ../my_multihead_cluster.yaml

# Force bootstrap mode (first node)
sudo ./cluster/setup/phase1_database.sh --bootstrap

# Force join mode (additional nodes)
sudo ./cluster/setup/phase1_database.sh --join

# Dry-run to preview changes
./cluster/setup/phase1_database.sh --dry-run
```

### Options

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to my_multihead_cluster.yaml |
| `--bootstrap` | Force bootstrap mode (create new cluster) |
| `--join` | Force join mode (join existing cluster) |
| `--dry-run` | Show what would be done without executing |
| `--help` | Show help message |

### How It Works

**13-Step Process:**

1. **Check Root Privileges**
   - Verify script is run with sudo

2. **Check Dependencies**
   - Verify python3, jq are installed
   - Check parser and template files exist

3. **Load Configuration**
   - Parse YAML config
   - Detect current controller by IP
   - Extract MariaDB settings (root password, SST credentials)
   - Verify MariaDB service is enabled for this controller

4. **Detect Operating System**
   - Identify OS (Ubuntu/Debian or CentOS/RHEL)
   - Set Galera provider library path

5. **Check MariaDB Installation**
   - Detect if MariaDB is already installed
   - Get version information

6. **Install MariaDB (if needed)**
   - Ubuntu/Debian: `apt-get install mariadb-server galera-4`
   - CentOS/RHEL: `yum install mariadb-server galera`

7. **Discover Active Nodes**
   - Run auto_discovery.sh to find active MariaDB nodes
   - Filter controllers with `services.mariadb: true`
   - Check MariaDB service status on each

8. **Determine Operation Mode**
   - **Auto mode**:
     - If no active nodes found → Bootstrap mode
     - If active nodes found → Join mode
   - **Manual mode**: Use `--bootstrap` or `--join` flag

9. **Generate Cluster Address**
   - **Bootstrap mode**: `gcomm://` (empty)
   - **Join mode**: `gcomm://ip1:4567,ip2:4567,...`

10. **Generate Galera Configuration**
    - Read template from `galera_template.cnf`
    - Substitute template variables:
      - `{{NODE_IP}}` → Current node IP
      - `{{NODE_HOSTNAME}}` → Current hostname
      - `{{CLUSTER_NAME}}` → Cluster name from YAML
      - `{{CLUSTER_ADDRESS}}` → Generated cluster address
      - `{{SST_USER}}`, `{{SST_PASSWORD}}` → From YAML
      - `{{INNODB_BUFFER_POOL_SIZE}}` → 70% of RAM
      - `{{WSREP_SLAVE_THREADS}}` → CPU cores × 2
    - Write to `/etc/mysql/mariadb.conf.d/60-galera.cnf`

11. **Stop MariaDB**
    - Stop service before reconfiguration

12. **Bootstrap or Join Cluster**
    - **Bootstrap mode**:
      - Run `galera_new_cluster`
      - Create SST user
      - Set root password
    - **Join mode**:
      - Start MariaDB normally
      - Automatically join via SST

13. **Enable Service & Show Status**
    - Enable MariaDB for auto-start
    - Display cluster status

### Network Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 3306 | TCP | MySQL client connections |
| 4444 | TCP | SST (State Snapshot Transfer) |
| 4567 | TCP | Galera cluster replication |
| 4568 | TCP | IST (Incremental State Transfer) |

### Configuration Template

The `galera_template.cnf` includes:

**Mandatory Galera Settings:**
```ini
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
```

**Node Configuration:**
```ini
wsrep_node_address={{NODE_IP}}
wsrep_node_name={{NODE_HOSTNAME}}
```

**Cluster Configuration:**
```ini
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name={{CLUSTER_NAME}}
wsrep_cluster_address={{CLUSTER_ADDRESS}}
```

**SST Configuration:**
```ini
wsrep_sst_method=mariabackup
wsrep_sst_auth={{SST_USER}}:{{SST_PASSWORD}}
```

**Performance Tuning:**
```ini
innodb_buffer_pool_size={{INNODB_BUFFER_POOL_SIZE}}  # 70% of RAM
wsrep_slave_threads={{WSREP_SLAVE_THREADS}}          # CPU cores × 2
```

## Example Scenarios

### Scenario 1: Bootstrap First Node

```bash
# On server1 (192.168.1.101)
sudo ./cluster/setup/phase1_database.sh

# Output:
# [INFO] No active MariaDB nodes found → Bootstrap mode
# [INFO] CLUSTER_ADDRESS=gcomm://
# [SUCCESS] Galera cluster bootstrapped successfully
# [SUCCESS] SST user configured
```

**Result:**
- MariaDB Galera cluster initialized
- Cluster size: 1 node
- Ready to accept connections

**Verify:**
```bash
mysql -uroot -p -e "SHOW STATUS LIKE 'wsrep%';"
```

### Scenario 2: Join Second Node

```bash
# On server2 (192.168.1.102)
sudo ./cluster/setup/phase1_database.sh

# Output:
# [INFO] Active MariaDB nodes found: 1
# [INFO] Active nodes:
#   - 192.168.1.101
# [INFO] Join mode → CLUSTER_ADDRESS=gcomm://192.168.1.101:4567
# [INFO] Waiting for node to join cluster (SST may take time)...
# [SUCCESS] Node joined cluster successfully
# [INFO] Cluster size: 2 nodes
```

**Result:**
- Joined existing cluster via SST
- Data synchronized from server1
- Cluster size: 2 nodes

**What is SST?**
State Snapshot Transfer (SST) is a full data copy from an existing cluster node to the new node. MariaBackup method:
- Creates consistent snapshot on donor
- Transfers data to joiner
- Applies transaction logs
- Joins cluster when ready

### Scenario 3: Third Node (Multi-Master)

```bash
# On server3 (192.168.1.103)
sudo ./cluster/setup/phase1_database.sh

# Output:
# [INFO] Active nodes: server1, server2
# [INFO] CLUSTER_ADDRESS=gcomm://192.168.1.101:4567,192.168.1.102:4567
# [SUCCESS] Node joined cluster successfully
# [INFO] Cluster size: 3 nodes
```

**Result:**
- 3-node Galera cluster
- Quorum: 2 nodes required
- Can tolerate 1 node failure

### Scenario 4: Test Multi-Master Replication

```bash
# On server1
mysql -uroot -p -e "CREATE DATABASE test_replication;"
mysql -uroot -p -e "USE test_replication; CREATE TABLE data (id INT PRIMARY KEY, value VARCHAR(100));"
mysql -uroot -p -e "INSERT INTO test_replication.data VALUES (1, 'Written on server1');"

# On server2 (verify replication)
mysql -uroot -p -e "SELECT * FROM test_replication.data;"
# Output: 1 | Written on server1

# On server3 (write to different node)
mysql -uroot -p -e "INSERT INTO test_replication.data VALUES (2, 'Written on server3');"

# On server1 (verify bidirectional replication)
mysql -uroot -p -e "SELECT * FROM test_replication.data;"
# Output:
# 1 | Written on server1
# 2 | Written on server3
```

**Result:** All nodes can read and write, changes replicate instantly

## Database Backup

### Create Backup

```bash
# Full backup with compression
sudo ./cluster/utils/db_backup.sh --type full --compress

# Incremental backup
sudo ./cluster/utils/db_backup.sh --type incremental

# Full backup with verification
sudo ./cluster/utils/db_backup.sh --type full --verify

# Custom retention (keep 30 days)
sudo ./cluster/utils/db_backup.sh --retention 30
```

### Backup Options

| Option | Description |
|--------|-------------|
| `--type TYPE` | full or incremental (default: full) |
| `--compress` | Compress backup with gzip/pigz |
| `--verify` | Verify backup after creation |
| `--retention DAYS` | Keep backups for N days (default: 7) |
| `--backup-dir PATH` | Backup directory (default: /var/backups/mariadb) |

### How Backup Works

**Full Backup:**
1. Check MariaDB and cluster status
2. Create hot backup using `mariabackup --backup`
3. Compress if `--compress` specified
4. Create metadata file (JSON)
5. Verify if `--verify` specified
6. Apply retention policy (delete old backups)

**Incremental Backup:**
1. Find last full backup
2. Create incremental backup using `mariabackup --backup --incremental-basedir`
3. Only backs up changes since last full backup
4. Much faster and smaller than full backup

**Example Output:**
```bash
sudo ./cluster/utils/db_backup.sh --type full --compress

# Output:
# [INFO] Checking dependencies...
# [SUCCESS] All dependencies satisfied
# [INFO] MariaDB is running
# [SUCCESS] Cluster status: Ready and Synced
# [INFO] Starting full backup...
# [INFO] Backup path: /var/backups/mariadb/full/backup_20251027_143000
# [SUCCESS] Full backup completed in 45s
# [INFO] Backup size: 2.3G
# [SUCCESS] Backup verification successful
# [INFO] Retention policy applied (deleted 2 old backups)
```

### Backup Directory Structure

```
/var/backups/mariadb/
├── full/
│   ├── backup_20251027_120000/
│   │   ├── backup_metadata.json
│   │   ├── xtrabackup_checkpoints
│   │   ├── ibdata1.qp (compressed)
│   │   └── ... (database files)
│   └── backup_20251026_120000/
└── incremental/
    ├── incremental_20251027_180000/
    │   ├── backup_metadata.json
    │   ├── xtrabackup_checkpoints
    │   └── ... (changed files only)
    └── incremental_20251027_150000/
```

### Automated Backups with Cron

```bash
# Daily full backup at 2 AM
0 2 * * * /home/koopark/claude/KooSlurmInstallAutomationRefactory/cluster/utils/db_backup.sh --type full --compress --retention 30

# Incremental backup every 6 hours
0 */6 * * * /home/koopark/claude/KooSlurmInstallAutomationRefactory/cluster/utils/db_backup.sh --type incremental --compress
```

## Database Restore

### List Available Backups

```bash
./cluster/utils/db_restore.sh --list
```

**Output:**
```
Full Backups:
------------------------------------------------------------
No.   Backup Name                    Timestamp                 Size
------------------------------------------------------------
1     backup_20251027_120000         2025-10-27T12:00:00+00:00 2.3G
2     backup_20251026_120000         2025-10-26T12:00:00+00:00 2.1G

Incremental Backups:
------------------------------------------------------------
No.   Backup Name                    Timestamp                 Size
------------------------------------------------------------
3     incremental_20251027_180000    2025-10-27T18:00:00+00:00 450M
4     incremental_20251027_150000    2025-10-27T15:00:00+00:00 380M
```

### Restore from Backup

```bash
# Interactive restore (prompts for backup selection)
sudo ./cluster/utils/db_restore.sh

# Restore specific backup
sudo ./cluster/utils/db_restore.sh --backup-path /var/backups/mariadb/full/backup_20251027_120000

# Force restore without confirmation (DANGEROUS!)
sudo ./cluster/utils/db_restore.sh --backup-path /var/backups/mariadb/full/backup_20251027_120000 --force
```

### Restore Options

| Option | Description |
|--------|-------------|
| `--backup-path PATH` | Path to specific backup directory |
| `--backup-dir PATH` | Base backup directory (default: /var/backups/mariadb) |
| `--list` | List available backups and exit |
| `--force` | Skip confirmation prompts (dangerous!) |

### How Restore Works

**Restoration Process:**
1. List available backups (if not specified)
2. Validate backup (check xtrabackup_checkpoints)
3. Confirm restore (WARNS about data loss)
4. Stop MariaDB service
5. Backup current data directory to `/var/lib/mysql_backup_TIMESTAMP`
6. Prepare backup (decompress if needed, apply transaction logs)
7. Copy prepared backup to `/var/lib/mysql`
8. Remove Galera state files (grastate.dat, gvwstate.dat)
9. Bootstrap cluster with restored data
10. Verify restoration (check cluster status)

**Example Output:**
```bash
sudo ./cluster/utils/db_restore.sh

# Output:
# [INFO] === Available Backups ===
# ...
# Enter backup number to restore: 1
# [WARNING] === WARNING ===
# [WARNING] ALL CURRENT DATA WILL BE REPLACED!
# Are you sure you want to continue? Type 'YES' to proceed: YES
# [INFO] Stopping MariaDB service...
# [INFO] Backing up current data directory...
# [SUCCESS] Current data backed up to: /var/lib/mysql_backup_20251027_150000
# [INFO] Preparing backup for restoration...
# [SUCCESS] Backup prepared successfully
# [INFO] Copying prepared backup to data directory...
# [INFO] Bootstrapping Galera cluster...
# [SUCCESS] Galera cluster bootstrapped successfully
# [SUCCESS] Cluster is ready
# [SUCCESS] === Restore completed successfully ===
```

### Post-Restore Steps

After restoring on one node:

1. **Verify data integrity**
   ```bash
   mysql -uroot -p -e "SHOW DATABASES;"
   mysql -uroot -p -e "SELECT COUNT(*) FROM your_database.your_table;"
   ```

2. **Start other cluster nodes**
   ```bash
   # On server2, server3, etc.
   sudo systemctl stop mariadb
   sudo rm -f /var/lib/mysql/grastate.dat
   sudo systemctl start mariadb  # Will join via SST
   ```

3. **Monitor cluster sync**
   ```bash
   # On all nodes
   mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
   mysql -e "SHOW STATUS LIKE 'wsrep_local_state_comment';"
   ```

## Troubleshooting

### Issue: Node fails to join cluster

```bash
# Check Galera logs
sudo tail -f /var/log/mysql/error.log | grep wsrep

# Common causes:
# 1. Firewall blocking ports
sudo firewall-cmd --add-port=4567/tcp --permanent  # CentOS/RHEL
sudo ufw allow 4567/tcp                             # Ubuntu

# 2. Wrong cluster address in galera.cnf
cat /etc/mysql/mariadb.conf.d/60-galera.cnf | grep wsrep_cluster_address

# 3. SELinux blocking
sudo setenforce 0  # CentOS/RHEL (temporary)
```

### Issue: Split-brain (multiple primaries)

```bash
# Check cluster status on all nodes
mysql -e "SHOW STATUS LIKE 'wsrep_cluster_status';"

# If multiple nodes show 'Primary', cluster split occurred
# Solution: Stop all nodes, bootstrap from most up-to-date

# On most recent node:
sudo galera_new_cluster

# On other nodes:
sudo systemctl start mariadb
```

### Issue: SST fails during join

```bash
# Check error log
sudo tail -f /var/log/mysql/error.log

# Common causes:
# 1. Donor node too busy - try another
# Edit galera.cnf, change wsrep_cluster_address order

# 2. Insufficient disk space
df -h /var/lib/mysql

# 3. SST user missing
# On donor node:
mysql -e "SELECT User, Host FROM mysql.user WHERE User='sstuser';"
```

### Issue: Cluster quorum lost

```bash
# Check cluster size
mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';"

# If cluster_size < (total_nodes / 2 + 1), quorum lost
# Example: 3 nodes, need 2 minimum

# Solution: Bootstrap from a node with latest data
sudo galera_new_cluster
```

### Issue: High replication lag

```bash
# Check flow control
mysql -e "SHOW STATUS LIKE 'wsrep_flow_control%';"

# If paused often, increase slave threads
# Edit /etc/mysql/mariadb.conf.d/60-galera.cnf
wsrep_slave_threads=16  # Increase based on CPU cores

# Restart MariaDB
sudo systemctl restart mariadb
```

### Issue: Backup verification fails

```bash
# Check backup integrity
sudo mariabackup --prepare --target-dir=/var/backups/mariadb/full/backup_XXXX

# If fails, backup may be corrupted
# Solution: Use previous backup or create new full backup
```

## Monitoring

### Cluster Health Check

```bash
# Quick status
mysql -e "SHOW STATUS LIKE 'wsrep_%';" | grep -E "(cluster_size|cluster_status|ready|local_state_comment)"

# Expected output:
# wsrep_cluster_size            3
# wsrep_cluster_status          Primary
# wsrep_ready                   ON
# wsrep_local_state_comment     Synced
```

### Important Galera Status Variables

| Variable | Healthy Value | Description |
|----------|---------------|-------------|
| wsrep_ready | ON | Node is ready for queries |
| wsrep_cluster_status | Primary | Cluster is primary (not split) |
| wsrep_local_state_comment | Synced | Node is synchronized |
| wsrep_cluster_size | N | Number of nodes in cluster |
| wsrep_incoming_addresses | IP list | All cluster members |
| wsrep_flow_control_paused | <0.1 | Low = good, High = congestion |
| wsrep_cert_deps_distance | <10 | Average transaction distance |

### Monitoring Script

Create `/usr/local/bin/galera_health.sh`:

```bash
#!/bin/bash
mysql -e "SHOW STATUS LIKE 'wsrep_%';" | grep -E \
  "(cluster_size|cluster_status|ready|local_state_comment|flow_control_paused)"
```

### Nagios/Zabbix Integration

```bash
# Check script for monitoring systems
#!/bin/bash
WSREP_READY=$(mysql -e "SHOW STATUS LIKE 'wsrep_ready';" | grep wsrep_ready | awk '{print $2}')

if [ "$WSREP_READY" == "ON" ]; then
    echo "OK: Galera cluster is ready"
    exit 0
else
    echo "CRITICAL: Galera cluster not ready"
    exit 2
fi
```

## Best Practices

### 1. Always Use Odd Number of Nodes

**Why:** Galera requires quorum (majority) to operate

- 2 nodes: Can't tolerate any failures (quorum = 2)
- 3 nodes: Can tolerate 1 failure (quorum = 2) ✓
- 4 nodes: Can tolerate 1 failure (quorum = 3)
- 5 nodes: Can tolerate 2 failures (quorum = 3) ✓

**Recommendation:** 3 or 5 nodes for production

### 2. Monitor Cluster Status

```bash
# Add to cron
*/5 * * * * /usr/local/bin/galera_health.sh >> /var/log/galera_health.log
```

### 3. Regular Backups

```bash
# Daily full backup
0 2 * * * /path/to/db_backup.sh --type full --compress --retention 30

# Test restore monthly
```

### 4. Load Balancing

Use HAProxy or ProxySQL to distribute load:

```haproxy
listen mysql-cluster
    bind *:3306
    mode tcp
    balance roundrobin
    option mysql-check user haproxy
    server server1 192.168.1.101:3306 check
    server server2 192.168.1.102:3306 check
    server server3 192.168.1.103:3306 check
```

### 5. Avoid Large Transactions

Galera replicates entire transaction at commit:
- Break large INSERT/UPDATE into smaller batches
- Use `wsrep_max_ws_size` to prevent huge transactions

### 6. Graceful Shutdown

```bash
# Proper shutdown (prevents SST on rejoin)
sudo systemctl stop mariadb

# Avoid:
sudo kill -9 $(pidof mysqld)  # Forces SST on rejoin
```

## Integration with Other Phases

Phase 2 MariaDB Galera provides database services for:

- **Phase 4 (Slurm)**: Slurm accounting database (slurm_acct_db)
- **Phase 6 (Web)**: Application databases (user auth, session storage)
- **Phase 7 (Backup)**: Metadata storage for backup system
- **All Phases**: Centralized configuration and state

## Configuration Reference

### YAML Configuration

```yaml
cluster:
  name: my_multihead_cluster

database:
  mariadb:
    root_password: ${MARIADB_ROOT_PASSWORD}  # Environment variable
    sst_user: sstuser
    sst_password: ${MARIADB_SST_PASSWORD}    # Environment variable

nodes:
  controllers:
    - hostname: server1
      ip_address: 192.168.1.101
      services:
        mariadb: true    # Enable MariaDB on this controller
```

### Environment Variables

Set before running setup:

```bash
export MARIADB_ROOT_PASSWORD="your_secure_root_password"
export MARIADB_SST_PASSWORD="your_secure_sst_password"
```

## Next Steps

After completing Phase 2:

1. **Verify cluster is operational**
   ```bash
   mysql -uroot -p -e "SHOW STATUS LIKE 'wsrep%';"
   ```

2. **Test replication**
   ```bash
   # On node 1
   mysql -uroot -p -e "CREATE DATABASE test_db;"

   # On node 2
   mysql -uroot -p -e "SHOW DATABASES LIKE 'test%';"
   ```

3. **Create first backup**
   ```bash
   sudo ./cluster/utils/db_backup.sh --type full --compress
   ```

4. **Proceed to Phase 3: Redis Cluster**
   - Multi-master key-value store
   - Hash slot-based partitioning
   - Session storage for web services

## References

- [MariaDB Galera Cluster Documentation](https://mariadb.com/kb/en/galera-cluster/)
- [Galera Cluster Documentation](https://galeracluster.com/library/documentation/)
- [MariaBackup Documentation](https://mariadb.com/kb/en/mariabackup/)
- [my_multihead_cluster.yaml Configuration](../my_multihead_cluster.yaml)
- [MULTIHEAD_IMPLEMENTATION_PLAN.md](../dashboard/MULTIHEAD_IMPLEMENTATION_PLAN.md)
