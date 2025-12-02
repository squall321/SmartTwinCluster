# Phase 3: Redis Cluster

Phase 3 implements Redis for distributed caching and session storage with support for both Cluster mode (3+ nodes) and Sentinel mode (2 nodes).

## Overview

**Components:**
- `setup/phase2_redis.sh` - Redis setup script with automatic mode detection
- `config/redis_template.conf` - Dynamic Redis configuration template
- `utils/redis_backup.sh` - Redis backup utility (RDB + AOF)
- `utils/redis_restore.sh` - Redis restore utility

**Features:**
- Cluster mode (3+ nodes): Hash slot-based partitioning
- Sentinel mode (2 nodes): Master-replica with auto-failover
- Automatic mode selection based on node count
- Hot backup without downtime
- RDB (snapshot) and AOF (append-only) persistence

## Prerequisites

1. **Configuration File**: `my_multihead_cluster.yaml` with Redis-enabled controllers
2. **Network**: Ports 6379 (Redis) and 26379 (Sentinel) open
3. **Permissions**: Root/sudo access
4. **Dependencies**: Python 3 with PyYAML, jq, redis-cli

## Redis Cluster vs Sentinel Mode

### Cluster Mode (3+ nodes)

**When to use:** 3 or more Redis-enabled nodes

**Features:**
- Hash slot-based data partitioning (16384 slots)
- Automatic sharding across nodes
- Built-in high availability
- No single point of failure
- Horizontal scalability

**Architecture:**
```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Node 1     │  │  Node 2     │  │  Node 3     │
│ Slots:      │  │ Slots:      │  │ Slots:      │
│ 0-5460      │  │ 5461-10922  │  │ 10923-16383 │
└─────────────┘  └─────────────┘  └─────────────┘
```

### Sentinel Mode (2 nodes)

**When to use:** Exactly 2 Redis-enabled nodes

**Features:**
- Master-replica replication
- Automatic failover via Sentinel
- Simpler setup
- Lower resource usage
- Good for small deployments

**Architecture:**
```
┌─────────────┐       Replication      ┌─────────────┐
│  Master     │──────────────────────→│  Replica    │
│  Node 1     │                        │  Node 2     │
│  Port 6379  │                        │  Port 6379  │
└─────────────┘                        └─────────────┘
      ↓                                       ↓
┌─────────────┐                        ┌─────────────┐
│  Sentinel   │←──────────────────────→│  Sentinel   │
│  Port 26379 │      Monitor           │  Port 26379 │
└─────────────┘                        └─────────────┘
```

## Redis Setup

### Usage

```bash
# Auto mode (3+ nodes → cluster, 2 nodes → sentinel)
sudo ./cluster/setup/phase2_redis.sh --config ../my_multihead_cluster.yaml

# Force cluster mode
sudo ./cluster/setup/phase2_redis.sh --mode cluster

# Force sentinel mode
sudo ./cluster/setup/phase2_redis.sh --mode sentinel

# Dry-run to preview changes
./cluster/setup/phase2_redis.sh --dry-run
```

### Options

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to my_multihead_cluster.yaml |
| `--mode MODE` | Force mode: cluster, sentinel (auto-detect by default) |
| `--dry-run` | Show what would be done without executing |
| `--help` | Show help message |

### How It Works

**13-Step Process:**

1. **Check Root Privileges**
2. **Check Dependencies** (python3, jq, redis template)
3. **Load Configuration** (YAML parsing, extract Redis settings)
4. **Detect Operating System** (Ubuntu/Debian or CentOS/RHEL)
5. **Check Redis Installation**
6. **Install Redis** (if needed)
7. **Discover Active Nodes** (find running Redis instances)
8. **Determine Redis Mode**:
   - 3+ nodes → Cluster mode
   - 2 nodes → Sentinel mode
   - <2 nodes → Error
9. **Calculate Memory Settings**:
   - Max memory: 25% of RAM
   - Max clients: 10000
10. **Generate Redis Configuration** from template
11. **Stop Redis** (for reconfiguration)
12. **Start Redis** with new configuration
13. **Create Cluster or Setup Sentinel**
    - Cluster: Create with `redis-cli --cluster create`
    - Sentinel: Configure master-replica + sentinel monitoring

### Network Ports

| Port | Service | Purpose |
|------|---------|---------|
| 6379 | Redis | Client connections and cluster bus |
| 16379 | Redis Cluster Bus | Inter-node communication |
| 26379 | Redis Sentinel | Failover monitoring |

## Example Scenarios

### Scenario 1: 3-Node Cluster Setup

**Node 1:**
```bash
sudo ./cluster/setup/phase2_redis.sh

# Output:
# [INFO] Total Redis-enabled controllers: 3
# [INFO] 3+ Redis nodes detected → Cluster mode
# [INFO] Cluster mode provides:
#   - Hash slot-based data partitioning (16384 slots)
#   - Automatic sharding across nodes
# [SUCCESS] Redis started successfully
# [INFO] This is the first node, creating cluster...
# [SUCCESS] Redis Cluster created successfully
```

**Node 2 & 3:**
```bash
sudo ./cluster/setup/phase2_redis.sh

# Output:
# [INFO] This is not the first node, waiting for cluster creation...
# [SUCCESS] Redis started successfully
```

**Verify Cluster:**
```bash
redis-cli -a <password> CLUSTER INFO

# Output:
# cluster_state:ok
# cluster_slots_assigned:16384
# cluster_slots_ok:16384
# cluster_known_nodes:3
# cluster_size:3
```

**Test Data Distribution:**
```bash
# On node 1
redis-cli -c -a <password> SET user:1 "Alice"
redis-cli -c -a <password> SET user:2 "Bob"
redis-cli -c -a <password> SET user:3 "Charlie"

# Data automatically distributed across nodes based on hash slots
redis-cli -a <password> CLUSTER NODES
# Shows which node stores each key
```

### Scenario 2: 2-Node Sentinel Setup

**Node 1 (Master):**
```bash
sudo ./cluster/setup/phase2_redis.sh

# Output:
# [INFO] Total Redis-enabled controllers: 2
# [INFO] 2 Redis nodes detected → Sentinel mode
# [INFO] This node will be the master
# [SUCCESS] Redis started successfully
# [SUCCESS] Sentinel started
```

**Node 2 (Replica):**
```bash
sudo ./cluster/setup/phase2_redis.sh

# Output:
# [INFO] This node will be the replica
# [INFO] Configuring replication to master 192.168.1.101...
# [SUCCESS] Replication configured
# [SUCCESS] Sentinel started
```

**Verify Replication:**
```bash
# On master
redis-cli -a <password> INFO replication

# Output:
# role:master
# connected_slaves:1
# slave0:ip=192.168.1.102,port=6379,state=online

# On replica
redis-cli -a <password> INFO replication

# Output:
# role:slave
# master_host:192.168.1.101
# master_link_status:up
```

**Test Sentinel:**
```bash
redis-cli -p 26379 -a <password> SENTINEL masters

# Output shows master status and sentinel monitoring
```

### Scenario 3: Cluster Failover Test

**Initial state:**
```bash
redis-cli -a <password> CLUSTER NODES
# node1: master (slots 0-5460)
# node2: master (slots 5461-10922)
# node3: master (slots 10923-16383)
```

**Simulate node2 failure:**
```bash
# On node2
sudo systemctl stop redis-server
```

**Cluster behavior:**
- Cluster detects node2 is down
- Marks slots 5461-10922 as failed
- cluster_state becomes "fail" temporarily
- If replicas exist, promotes replica to master
- Cluster recovers automatically

**Verify:**
```bash
redis-cli -a <password> CLUSTER INFO
# cluster_state:ok (or fail if no replicas)

redis-cli -a <password> CLUSTER NODES
# node2: fail
```

### Scenario 4: Sentinel Automatic Failover

**Initial state:**
```bash
# Master: node1
# Replica: node2
```

**Simulate master failure:**
```bash
# On node1 (master)
sudo systemctl stop redis-server
```

**Sentinel behavior:**
1. Sentinels detect master is down (after 5 seconds)
2. Sentinels reach quorum (both agree master is down)
3. Sentinels elect leader to perform failover
4. Leader promotes replica (node2) to master
5. Updates configuration

**Verify:**
```bash
# On node2 (now master)
redis-cli -a <password> INFO replication
# role:master

# Check sentinel
redis-cli -p 26379 -a <password> SENTINEL masters
# Shows node2 as new master
```

**Recover old master:**
```bash
# On node1
sudo systemctl start redis-server

# Automatically becomes replica of new master (node2)
redis-cli -a <password> INFO replication
# role:slave
# master_host:192.168.1.102
```

## Redis Backup

### Create Backup

```bash
# Both RDB and AOF backup
sudo ./cluster/utils/redis_backup.sh --type both --compress

# RDB snapshot only (fast, point-in-time)
sudo ./cluster/utils/redis_backup.sh --type rdb

# AOF only (complete command history)
sudo ./cluster/utils/redis_backup.sh --type aof

# Custom retention (keep 30 days)
sudo ./cluster/utils/redis_backup.sh --retention 30
```

### Backup Options

| Option | Description |
|--------|-------------|
| `--type TYPE` | rdb, aof, both (default: both) |
| `--compress` | Compress backup with gzip |
| `--retention DAYS` | Keep backups for N days (default: 7) |
| `--backup-dir PATH` | Backup directory (default: /var/backups/redis) |

### Backup Types

**RDB (Redis Database):**
- Point-in-time snapshot
- Compact binary format
- Fast to create and restore
- Uses `BGSAVE` command (background save)
- Good for disaster recovery

**AOF (Append-Only File):**
- Log of all write operations
- Can replay to any point
- More durable (fsync every second)
- Uses `BGREWRITEAOF` command
- Good for data integrity

### How Backup Works

**RDB Backup Process:**
1. Trigger `BGSAVE` (background save)
2. Wait for save to complete (check `LASTSAVE`)
3. Copy `dump.rdb` from data directory
4. Compress if requested
5. Create metadata JSON
6. Apply retention policy

**AOF Backup Process:**
1. Trigger `BGREWRITEAOF` (rewrite AOF)
2. Wait for rewrite to complete
3. Copy `appendonly.aof` from data directory
4. Compress if requested
5. Create metadata JSON
6. Apply retention policy

**Example Output:**
```bash
sudo ./cluster/utils/redis_backup.sh --type both --compress

# Output:
# [INFO] Checking Redis status...
# [SUCCESS] Redis is running
# [INFO] Redis is running in Cluster mode
# [INFO] Creating RDB snapshot backup...
# [INFO] Triggering BGSAVE...
# [SUCCESS] BGSAVE completed
# [SUCCESS] RDB backup completed in 12s
# [INFO] Backup size: 156M
# [INFO] Creating AOF backup...
# [SUCCESS] AOF backup completed in 8s
# [INFO] Backup size: 234M
# [SUCCESS] Retention policy applied (deleted 2 old backups)
```

### Backup Directory Structure

```
/var/backups/redis/
├── rdb/
│   ├── rdb_backup_20251027_120000/
│   │   ├── backup_metadata.json
│   │   └── dump.rdb.gz (compressed)
│   └── rdb_backup_20251026_120000/
└── aof/
    ├── aof_backup_20251027_180000/
    │   ├── backup_metadata.json
    │   └── appendonly.aof.gz (compressed)
    └── aof_backup_20251027_150000/
```

### Automated Backups with Cron

```bash
# Daily RDB backup at 3 AM
0 3 * * * /path/to/redis_backup.sh --type rdb --compress --retention 30

# AOF backup every 6 hours
0 */6 * * * /path/to/redis_backup.sh --type aof --compress

# Weekly full backup (both) on Sundays at 2 AM
0 2 * * 0 /path/to/redis_backup.sh --type both --compress --retention 60
```

### Cluster Mode Backups

**Important:** In cluster mode, each node stores different data (hash slots).

**Complete backup requires:**
- Backup all nodes individually
- Coordinate backup timing
- Track which backup corresponds to which slots

**Recommended approach:**
```bash
# On each cluster node
sudo ./cluster/utils/redis_backup.sh --type rdb --compress

# Backups are stored locally on each node
# For centralized storage, copy to shared location:
sudo cp -r /var/backups/redis /mnt/gluster/backups/redis_$(hostname)
```

## Redis Restore

### List Available Backups

```bash
./cluster/utils/redis_restore.sh --list
```

**Output:**
```
RDB Backups:
------------------------------------------------------------
No.   Backup Name                    Timestamp                 Size
------------------------------------------------------------
1     rdb_backup_20251027_120000     2025-10-27T12:00:00+00:00 156M
2     rdb_backup_20251026_120000     2025-10-26T12:00:00+00:00 152M

AOF Backups:
------------------------------------------------------------
No.   Backup Name                    Timestamp                 Size
------------------------------------------------------------
3     aof_backup_20251027_180000     2025-10-27T18:00:00+00:00 234M
4     aof_backup_20251027_150000     2025-10-27T15:00:00+00:00 228M
```

### Restore from Backup

```bash
# Interactive restore (prompts for backup selection)
sudo ./cluster/utils/redis_restore.sh

# Restore specific backup
sudo ./cluster/utils/redis_restore.sh --backup-path /var/backups/redis/rdb/rdb_backup_20251027_120000

# Force restore without confirmation
sudo ./cluster/utils/redis_restore.sh --backup-path /var/backups/redis/rdb/rdb_backup_20251027_120000 --force
```

### Restore Options

| Option | Description |
|--------|-------------|
| `--backup-path PATH` | Path to specific backup directory |
| `--backup-dir PATH` | Base backup directory |
| `--list` | List available backups and exit |
| `--force` | Skip confirmation prompts |

### How Restore Works

**Restoration Process:**
1. List available backups (if not specified)
2. Validate backup (check files exist)
3. Confirm restore (WARNING about data loss)
4. Stop Redis service
5. Backup current data directory
6. Restore backup file (decompress if needed)
7. Set proper ownership (redis:redis)
8. Start Redis service
9. Verify restoration (PING, DBSIZE)

**Example Output:**
```bash
sudo ./cluster/utils/redis_restore.sh

# Output:
# === Available Backups ===
# ...
# Enter backup number to restore: 1
# [WARNING] === WARNING ===
# [WARNING] ALL CURRENT DATA WILL BE REPLACED!
# Are you sure? Type 'YES': YES
# [INFO] Stopping Redis service...
# [INFO] Backing up current data directory...
# [SUCCESS] Current data backed up to: /var/lib/redis_backup_20251027_150000
# [INFO] Restoring from RDB backup...
# [SUCCESS] RDB backup restored to data directory
# [INFO] Starting Redis service...
# [SUCCESS] Redis started successfully
# [INFO] Database size: 15432 keys
# [SUCCESS] === Restore completed successfully ===
```

## Troubleshooting

### Issue: Cluster creation fails

```bash
# Check if all nodes are reachable
for ip in 192.168.1.101 192.168.1.102 192.168.1.103; do
    redis-cli -h $ip -a <password> PING
done

# Check firewall
sudo firewall-cmd --add-port=6379/tcp --permanent
sudo firewall-cmd --add-port=16379/tcp --permanent  # Cluster bus
sudo firewall-cmd --reload

# Check cluster bus port
netstat -tlnp | grep 16379
```

### Issue: Node cannot join cluster

```bash
# Check cluster configuration
redis-cli -a <password> CONFIG GET cluster-*

# Reset cluster (DANGER: loses all data)
redis-cli -a <password> CLUSTER RESET
sudo systemctl restart redis-server

# Re-create cluster from first node
redis-cli --cluster create IP1:6379 IP2:6379 IP3:6379 --cluster-yes -a <password>
```

### Issue: Sentinel failover not working

```bash
# Check sentinel status
redis-cli -p 26379 -a <password> SENTINEL masters
redis-cli -p 26379 -a <password> SENTINEL slaves mymaster

# Check sentinel quorum (need majority)
# With 2 sentinels, both must be working

# Check sentinel logs
sudo tail -f /var/log/redis/sentinel.log

# Test manual failover
redis-cli -p 26379 -a <password> SENTINEL failover mymaster
```

### Issue: Memory limit reached

```bash
# Check memory usage
redis-cli -a <password> INFO memory

# Increase maxmemory
redis-cli -a <password> CONFIG SET maxmemory 2gb
redis-cli -a <password> CONFIG REWRITE

# Or edit /etc/redis/redis.conf
maxmemory 2gb
sudo systemctl restart redis-server
```

### Issue: Slow queries

```bash
# Check slow log
redis-cli -a <password> SLOWLOG GET 10

# Monitor in real-time
redis-cli -a <password> MONITOR

# Check latency
redis-cli -a <password> --latency

# Check client connections
redis-cli -a <password> CLIENT LIST
```

### Issue: Backup/restore fails

```bash
# Check disk space
df -h /var/lib/redis
df -h /var/backups/redis

# Check Redis permissions
ls -la /var/lib/redis
sudo chown -R redis:redis /var/lib/redis

# Manual RDB save
redis-cli -a <password> SAVE  # Synchronous (blocks)
redis-cli -a <password> BGSAVE  # Background

# Check last save time
redis-cli -a <password> LASTSAVE
```

## Monitoring

### Health Check

```bash
# Quick status
redis-cli -a <password> PING
# Expected: PONG

# Database info
redis-cli -a <password> INFO

# Key statistics
redis-cli -a <password> DBSIZE
redis-cli -a <password> INFO keyspace
```

### Cluster Monitoring

```bash
# Cluster health
redis-cli -a <password> CLUSTER INFO

# Important metrics:
# cluster_state:ok
# cluster_slots_assigned:16384
# cluster_slots_ok:16384
# cluster_known_nodes:3

# Node details
redis-cli -a <password> CLUSTER NODES

# Slot distribution
redis-cli -a <password> CLUSTER SLOTS
```

### Sentinel Monitoring

```bash
# Master info
redis-cli -p 26379 -a <password> SENTINEL masters

# Replica info
redis-cli -p 26379 -a <password> SENTINEL slaves mymaster

# Sentinel info
redis-cli -p 26379 -a <password> SENTINEL sentinels mymaster

# Check failover history
redis-cli -p 26379 -a <password> INFO sentinel
```

### Important Metrics

| Metric | Command | Healthy Value |
|--------|---------|---------------|
| Connections | `INFO clients` | connected_clients < maxclients |
| Memory | `INFO memory` | used_memory < maxmemory |
| Hit Rate | `INFO stats` | keyspace_hits / (keyspace_hits + keyspace_misses) > 0.8 |
| Persistence | `INFO persistence` | rdb_last_save_time recent |
| Replication | `INFO replication` | master_link_status:up (replica) |

### Monitoring Script

```bash
#!/bin/bash
# /usr/local/bin/redis_health.sh

PASSWORD="your_redis_password"

# Check if Redis is running
if ! redis-cli -a "$PASSWORD" PING &>/dev/null; then
    echo "CRITICAL: Redis is down"
    exit 2
fi

# Check memory
USED_MEMORY=$(redis-cli -a "$PASSWORD" INFO memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
MAX_MEMORY=$(redis-cli -a "$PASSWORD" CONFIG GET maxmemory | tail -1)

echo "OK: Redis is running"
echo "Memory: $USED_MEMORY / ${MAX_MEMORY} bytes"

# Check cluster status (if cluster mode)
CLUSTER_STATE=$(redis-cli -a "$PASSWORD" CLUSTER INFO 2>/dev/null | grep cluster_state | cut -d: -f2 | tr -d '\r')
if [[ "$CLUSTER_STATE" == "ok" ]]; then
    echo "Cluster: OK"
elif [[ -n "$CLUSTER_STATE" ]]; then
    echo "WARNING: Cluster state is $CLUSTER_STATE"
    exit 1
fi

exit 0
```

## Best Practices

### 1. Use Cluster Mode for Production

**Advantages:**
- No single point of failure
- Automatic data sharding
- Horizontal scalability
- Better performance under load

**Recommendation:** 3-5 nodes minimum

### 2. Enable Persistence

```conf
# RDB: Point-in-time snapshots
save 900 1      # After 900s if 1 key changed
save 300 10     # After 300s if 10 keys changed
save 60 10000   # After 60s if 10000 keys changed

# AOF: Append-only file
appendonly yes
appendfsync everysec  # Fsync every second
```

### 3. Set Appropriate Memory Limits

```bash
# Calculate: 25% of RAM for Redis
# Example: 32GB RAM → 8GB for Redis
redis-cli -a <password> CONFIG SET maxmemory 8gb
redis-cli -a <password> CONFIG SET maxmemory-policy allkeys-lru
```

### 4. Monitor and Alert

```bash
# Add to cron
*/5 * * * * /usr/local/bin/redis_health.sh >> /var/log/redis_health.log
```

### 5. Regular Backups

```bash
# Daily RDB backups
0 3 * * * /path/to/redis_backup.sh --type rdb --compress --retention 30

# Test restore monthly
```

### 6. Use Password Authentication

```conf
requirepass strong_password_here
```

### 7. Limit Network Exposure

```conf
# Bind to specific interface
bind 0.0.0.0

# Use firewall to restrict access
# Only allow cluster members and application servers
```

## Integration with Other Phases

Phase 3 Redis provides caching and session storage for:

- **Phase 6 (Web Services)**: Session storage, cache layer
- **Phase 4 (Slurm)**: Job queue, temporary data storage
- **All Phases**: Distributed locking, pub/sub messaging

## Configuration Reference

### YAML Configuration

```yaml
cache:
  redis:
    password: ${REDIS_PASSWORD}  # Environment variable

nodes:
  controllers:
    - hostname: server1
      ip_address: 192.168.1.101
      services:
        redis: true    # Enable Redis on this controller
```

### Environment Variables

```bash
export REDIS_PASSWORD="your_secure_redis_password"
```

## Next Steps

After completing Phase 3:

1. **Verify Redis is operational**
   ```bash
   redis-cli -a <password> PING
   redis-cli -a <password> CLUSTER INFO  # If cluster mode
   ```

2. **Test data operations**
   ```bash
   redis-cli -c -a <password> SET test "Hello Redis"
   redis-cli -c -a <password> GET test
   ```

3. **Create first backup**
   ```bash
   sudo ./cluster/utils/redis_backup.sh --type both --compress
   ```

4. **Proceed to Phase 4: Slurm Multi-Master**
   - Dynamic slurm.conf generation
   - VIP-based primary controller
   - Automatic failover
   - Integration with GlusterFS for shared state

## References

- [Redis Cluster Tutorial](https://redis.io/docs/manual/scaling/)
- [Redis Sentinel Documentation](https://redis.io/docs/manual/sentinel/)
- [Redis Persistence](https://redis.io/docs/manual/persistence/)
- [my_multihead_cluster.yaml Configuration](../my_multihead_cluster.yaml)
- [MULTIHEAD_IMPLEMENTATION_PLAN.md](../dashboard/MULTIHEAD_IMPLEMENTATION_PLAN.md)
