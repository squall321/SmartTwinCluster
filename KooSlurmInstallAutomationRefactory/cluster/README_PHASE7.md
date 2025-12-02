# Phase 7: Unified Backup and Restore System

Phase 7 implements comprehensive backup and restore functionality for the entire cluster, integrating all services into a unified backup system.

## Overview

**Components:**
- `backup/backup.sh` - Unified cluster backup script
- `backup/restore.sh` - Unified cluster restore script
- Integration with Phase 2 (MariaDB backup/restore)
- Integration with Phase 3 (Redis backup/restore)

**Features:**
- All-in-one cluster backup
- Selective service backup/restore
- Timestamped backup archives
- Compression support
- Retention policy management
- Backup verification
- Interactive and automated modes

## What Gets Backed Up

The unified backup system backs up all critical cluster components:

### 1. GlusterFS Metadata
- GlusterFS configuration (`/var/lib/glusterd/`)
- Volume information
- Peer status
- Slurm shared state from GlusterFS

### 2. MariaDB Database
- Full database dump using mariabackup
- All databases and tables
- User accounts and privileges
- SlurmDBD accounting database

### 3. Redis Data
- RDB snapshots
- AOF files
- Both RDB and AOF for complete coverage

### 4. Slurm Configuration
- slurm.conf
- slurmdbd.conf
- Configuration files

### 5. Cluster Configurations
- YAML configuration files
- Keepalived configuration
- Munge authentication key
- Service templates

### 6. Logs
- Recent cluster logs (last 7 days)
- Keepalived logs
- Service logs

## Unified Backup

### Usage

```bash
# Full cluster backup with compression
sudo ./cluster/backup/backup.sh --compress

# Backup specific services only
sudo ./cluster/backup/backup.sh --services mariadb,redis

# Custom backup directory and retention
sudo ./cluster/backup/backup.sh --backup-dir /mnt/gluster/backups --retention 60

# Backup with verification
sudo ./cluster/backup/backup.sh --compress --verify
```

### Options

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to my_multihead_cluster.yaml |
| `--backup-dir PATH` | Backup directory (default: /var/backups/cluster) |
| `--compress` | Compress backup with gzip |
| `--retention DAYS` | Keep backups for N days (default: 30) |
| `--services LIST` | Services to backup: all, glusterfs, mariadb, redis, slurm, config |
| `--verify` | Verify backup after creation |
| `--help` | Show help message |

### Backup Process

The backup script performs these steps:

1. **Check Prerequisites**
   - Root privileges
   - Dependencies installed
   - Configuration loaded

2. **Create Backup Structure**
   - Timestamped directory: `cluster_backup_YYYYMMDD_HHMMSS`
   - Subdirectories for each service

3. **Backup Services** (in order)
   - GlusterFS metadata
   - MariaDB (using db_backup.sh)
   - Redis (using redis_backup.sh)
   - Slurm configuration
   - Cluster configurations
   - Recent logs

4. **Create Metadata**
   - backup_metadata.json with backup details

5. **Compress** (if requested)
   - Create .tar.gz archive
   - Remove uncompressed directory

6. **Verify** (if requested)
   - Check archive integrity
   - Validate content

7. **Apply Retention Policy**
   - Delete backups older than retention period

### Backup Directory Structure

**Uncompressed backup:**
```
/var/backups/cluster/
└── cluster_backup_20251027_120000/
    ├── glusterfs/
    │   ├── glusterd.tar.gz
    │   ├── volume_info.txt
    │   ├── peer_status.txt
    │   └── slurm_state.tar.gz
    ├── mariadb/
    │   └── backup_20251027_120000/
    │       ├── backup_metadata.json
    │       └── (mariabackup files)
    ├── redis/
    │   ├── rdb/
    │   │   └── rdb_backup_20251027_120000/
    │   └── aof/
    │       └── aof_backup_20251027_120000/
    ├── slurm/
    │   ├── slurm.conf
    │   └── slurmdbd.conf
    ├── config/
    │   ├── my_multihead_cluster.yaml
    │   ├── keepalived.conf
    │   └── munge.key
    ├── logs/
    │   └── (recent log files)
    └── backup_metadata.json
```

**Compressed backup:**
```
/var/backups/cluster/
└── cluster_backup_20251027_120000.tar.gz
```

### Metadata File

Each backup includes a metadata file:

```json
{
  "backup_name": "cluster_backup_20251027_120000",
  "backup_path": "/var/backups/cluster/cluster_backup_20251027_120000",
  "cluster_name": "my_cluster",
  "hostname": "server1",
  "timestamp": "2025-10-27T12:00:00+00:00",
  "services": "all",
  "compressed": true,
  "verified": true,
  "size": "2.5G",
  "retention_days": 30
}
```

## Unified Restore

### Usage

```bash
# List available backups
./cluster/backup/restore.sh --list

# Restore from latest backup (interactive)
sudo ./cluster/backup/restore.sh --latest

# Restore specific backup
sudo ./cluster/backup/restore.sh --backup-path /var/backups/cluster/cluster_backup_20251027_120000

# Restore specific services only
sudo ./cluster/backup/restore.sh --latest --services mariadb,redis

# Force restore without confirmation
sudo ./cluster/backup/restore.sh --latest --force
```

### Options

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to my_multihead_cluster.yaml |
| `--backup-dir PATH` | Backup directory (default: /var/backups/cluster) |
| `--backup-path PATH` | Specific backup to restore |
| `--latest` | Restore from latest backup |
| `--services LIST` | Services to restore: all, glusterfs, mariadb, redis, slurm, config |
| `--force` | Skip confirmation prompts (DANGEROUS!) |
| `--list` | List available backups and exit |
| `--help` | Show help message |

### Restore Process

1. **List/Select Backup**
   - Interactive selection or use `--latest`
   - Display backup metadata

2. **Extract** (if compressed)
   - Extract .tar.gz to temporary directory

3. **Validate Backup**
   - Check backup structure
   - Verify metadata

4. **Confirm Restore**
   - Display warning about data replacement
   - Require explicit confirmation

5. **Restore Services** (in order)
   - GlusterFS metadata
   - MariaDB (using db_restore.sh)
   - Redis (using redis_restore.sh)
   - Slurm configuration
   - Cluster configurations

6. **Restart Services**
   - Restart affected services
   - Verify services are running

7. **Cleanup**
   - Remove extracted files
   - Display completion message

## Example Scenarios

### Scenario 1: Full Cluster Backup

```bash
# Create full backup with compression
sudo ./cluster/backup/backup.sh --compress

# Output:
# [INFO] === Unified Cluster Backup ===
# [INFO] Cluster: my_cluster
# [INFO] Node: server1
# [INFO] Backup directory: /var/backups/cluster/cluster_backup_20251027_120000
# [INFO] Backing up GlusterFS metadata...
# [SUCCESS] GlusterFS config backed up
# [SUCCESS] GlusterFS volume info saved
# [SUCCESS] Slurm state backed up
# [INFO] Backing up MariaDB...
# [SUCCESS] MariaDB backed up
# [INFO] Backing up Redis...
# [SUCCESS] Redis backed up
# [INFO] Backing up Slurm configuration...
# [SUCCESS] Slurm config backed up
# [INFO] Backing up cluster configurations...
# [SUCCESS] Configurations backed up
# [INFO] Backing up recent logs...
# [SUCCESS] Logs backed up
# [SUCCESS] Metadata created
# [INFO] Compressing backup archive...
# [SUCCESS] Backup compressed: 2.5G
# [SUCCESS] Retention policy applied (deleted 2 old backups)
# [SUCCESS] === Backup completed successfully ===
# [INFO] Duration: 180s
# [INFO] Backup location: /var/backups/cluster/cluster_backup_20251027_120000.tar.gz
```

### Scenario 2: Selective Service Backup

```bash
# Backup only database and Redis
sudo ./cluster/backup/backup.sh --services mariadb,redis --compress

# Output:
# [INFO] Backing up MariaDB...
# [SUCCESS] MariaDB backed up
# [INFO] Backing up Redis...
# [SUCCESS] Redis backed up
# [INFO] Skipping GlusterFS backup
# [INFO] Skipping Slurm backup
# [INFO] Skipping configuration backup
```

### Scenario 3: List Available Backups

```bash
./cluster/backup/restore.sh --list

# Output:
# [INFO] === Available Backups ===
#
# No.   Backup Name                              Date                 Size
# ------------------------------------------------------------------------------------
# 1     cluster_backup_20251027_120000           2025-10-27           2.5G
# 2     cluster_backup_20251026_120000           2025-10-26           2.4G
# 3     cluster_backup_20251025_120000           2025-10-25           2.3G
# ------------------------------------------------------------------------------------
```

### Scenario 4: Restore from Latest Backup

```bash
sudo ./cluster/backup/restore.sh --latest

# Output:
# [INFO] === Unified Cluster Restore ===
# [INFO] Using latest backup: cluster_backup_20251027_120000.tar.gz
# [INFO] Extracting compressed backup...
# [SUCCESS] Backup extracted
# [INFO] Backup cluster: my_cluster
# [INFO] Backup date: 2025-10-27T12:00:00+00:00
# [SUCCESS] Backup validation passed
# [WARNING] === WARNING ===
# [WARNING] This will restore from backup:
# [WARNING]   Backup: cluster_backup_20251027_120000
# [WARNING]   Services: all
# Are you sure you want to continue? Type 'YES' to proceed: YES
# [INFO] Restoring GlusterFS metadata...
# [SUCCESS] GlusterFS config restored
# [INFO] Restoring MariaDB...
# [SUCCESS] MariaDB restored
# [INFO] Restoring Redis...
# [SUCCESS] Redis restored
# [INFO] Restoring Slurm configuration...
# [SUCCESS] Slurm config restored
# [INFO] Restoring cluster configurations...
# [SUCCESS] Configurations restored
# [SUCCESS] === Restore completed successfully ===
```

### Scenario 5: Disaster Recovery

**Situation**: Server1 (primary controller) hardware failure, need to rebuild from scratch

**Steps:**

1. **Install OS and basic software on new server**

2. **Restore cluster scripts**
   ```bash
   git clone <repository>
   cd KooSlurmInstallAutomationRefactory
   ```

3. **Copy backup from shared storage or remote location**
   ```bash
   # If backups are on shared storage
   mount /mnt/gluster
   cp /mnt/gluster/backups/cluster_backup_20251027_120000.tar.gz /var/backups/cluster/
   ```

4. **Restore from backup**
   ```bash
   sudo ./cluster/backup/restore.sh --backup-path /var/backups/cluster/cluster_backup_20251027_120000.tar.gz --force
   ```

5. **Reconfigure services**
   ```bash
   # Phase 1-5 setup scripts if needed
   sudo ./cluster/setup/phase0_storage.sh --join
   sudo ./cluster/setup/phase1_database.sh --controller
   sudo ./cluster/setup/phase2_redis.sh
   sudo ./cluster/setup/phase3_slurm.sh --controller
   sudo ./cluster/setup/phase4_keepalived.sh
   ```

6. **Verify services**
   ```bash
   ./cluster/utils/cluster_info.sh
   ```

## Automated Backups

### Daily Backup with Cron

```bash
# Edit crontab
sudo crontab -e

# Add daily backup at 2 AM
0 2 * * * /home/koopark/claude/KooSlurmInstallAutomationRefactory/cluster/backup/backup.sh --compress --retention 30 >> /var/log/cluster_backup_cron.log 2>&1
```

### Weekly Full Backup + Daily Incrementals

```bash
# Full backup on Sundays at 2 AM
0 2 * * 0 /path/to/cluster/backup/backup.sh --compress --retention 90

# MariaDB incremental backups daily at 3 AM
0 3 * * 1-6 /path/to/cluster/utils/db_backup.sh --type incremental --compress
```

### Backup to Remote Storage

```bash
# Backup and copy to remote server
sudo ./cluster/backup/backup.sh --compress && \
rsync -avz /var/backups/cluster/ backup-server:/backups/cluster/
```

## Best Practices

### 1. Regular Backups

**Recommendation**: Daily full backups, keep 30 days

```bash
0 2 * * * /path/to/backup.sh --compress --retention 30
```

### 2. Test Restores Monthly

```bash
# Test restore in non-production environment
sudo ./cluster/backup/restore.sh --latest --services config
```

### 3. Store Backups Off-Site

```bash
# Copy backups to remote location
rsync -avz /var/backups/cluster/ remote-server:/backups/
```

### 4. Use Compression

```bash
# Saves disk space (typically 50-70% reduction)
sudo ./cluster/backup/backup.sh --compress
```

### 5. Verify Backups

```bash
# Periodically verify backup integrity
sudo ./cluster/backup/backup.sh --compress --verify
```

### 6. Monitor Backup Success

```bash
# Check backup logs
tail -f /var/log/cluster_backup.log

# Alert on failure
if ! ./cluster/backup/backup.sh --compress; then
    echo "Backup failed!" | mail -s "Backup Alert" admin@example.com
fi
```

### 7. Document Restore Procedures

Keep a documented runbook for disaster recovery scenarios.

## Troubleshooting

### Issue: Backup fails with permission denied

```bash
# Check backup directory permissions
ls -la /var/backups/cluster

# Create with proper permissions
sudo mkdir -p /var/backups/cluster
sudo chmod 700 /var/backups/cluster

# Run with sudo
sudo ./cluster/backup/backup.sh
```

### Issue: Backup too large

```bash
# Use compression
sudo ./cluster/backup/backup.sh --compress

# Backup only essential services
sudo ./cluster/backup/backup.sh --services mariadb,redis,config

# Check what's taking space
du -sh /var/backups/cluster/*
```

### Issue: Restore fails to extract archive

```bash
# Test archive integrity
tar tzf /var/backups/cluster/backup.tar.gz

# If corrupted, use previous backup
./cluster/backup/restore.sh --list
sudo ./cluster/backup/restore.sh --backup-path /var/backups/cluster/older_backup.tar.gz
```

### Issue: Service fails to start after restore

```bash
# Check service status
systemctl status mariadb redis-server slurmctld

# Check logs
journalctl -u mariadb -n 50
journalctl -u redis-server -n 50

# Restart services
sudo systemctl restart mariadb redis-server slurmctld
```

## Integration with Other Phases

Phase 7 integrates with:

- **Phase 1 (GlusterFS)**: Backs up shared state, can store backups on shared storage
- **Phase 2 (MariaDB)**: Uses db_backup.sh and db_restore.sh
- **Phase 3 (Redis)**: Uses redis_backup.sh and redis_restore.sh
- **Phase 4 (Slurm)**: Backs up configuration and shared state
- **Phase 5 (Keepalived)**: Backs up VIP configuration

## Configuration Reference

### YAML Configuration

No specific YAML configuration needed. Uses existing cluster configuration.

### Backup Locations

| Component | Backup Location |
|-----------|----------------|
| Main backup directory | `/var/backups/cluster/` |
| Backup log | `/var/log/cluster_backup.log` |
| Restore log | `/var/log/cluster_restore.log` |
| MariaDB backups | `/var/backups/mariadb/` |
| Redis backups | `/var/backups/redis/` |

## Monitoring

### Check Recent Backups

```bash
# List backups
ls -lht /var/backups/cluster/ | head -10

# Check latest backup
./cluster/backup/restore.sh --list | head -5
```

### Backup Size Tracking

```bash
# Total backup size
du -sh /var/backups/cluster/

# Size over time
du -sh /var/backups/cluster/* | sort -h
```

### Backup Age

```bash
# Find backups older than 30 days
find /var/backups/cluster/ -type f -name "*.tar.gz" -mtime +30
```

## Next Steps

After completing Phase 7:

1. **Test backup**
   ```bash
   sudo ./cluster/backup/backup.sh --compress --verify
   ```

2. **Test restore**
   ```bash
   ./cluster/backup/restore.sh --list
   ```

3. **Setup automated backups**
   ```bash
   sudo crontab -e
   # Add daily backup job
   ```

4. **Document disaster recovery procedures**

5. **Optional: Proceed to remaining phases**
   - Phase 8: Main integration script
   - Phase 9: Testing and validation
   - Phase 10: Documentation and deployment

## Summary

Phase 7 provides:
- ✅ Unified backup of all cluster services
- ✅ Selective service backup/restore
- ✅ Compression and retention management
- ✅ Interactive and automated modes
- ✅ Integration with existing backup utilities
- ✅ Disaster recovery capability

The cluster now has complete backup and restore capabilities for production use!

## References

- [MariaDB Backup](../utils/db_backup.sh)
- [MariaDB Restore](../utils/db_restore.sh)
- [Redis Backup](../utils/redis_backup.sh)
- [Redis Restore](../utils/redis_restore.sh)
- [my_multihead_cluster.yaml Configuration](../../my_multihead_cluster.yaml)
- [MULTIHEAD_IMPLEMENTATION_PLAN.md](../../dashboard/MULTIHEAD_IMPLEMENTATION_PLAN.md)
