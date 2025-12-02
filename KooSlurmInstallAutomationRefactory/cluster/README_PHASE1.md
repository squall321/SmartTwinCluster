# Phase 1: GlusterFS Dynamic Clustering

Phase 1 implements GlusterFS distributed storage with dynamic cluster expansion/contraction capabilities.

## Overview

**Components:**
- `setup/phase0_storage.sh` - Main GlusterFS setup script with auto bootstrap/join detection
- `utils/node_add.sh` - Add nodes to service clusters (GlusterFS, MariaDB, Redis, Slurm)
- `utils/node_remove.sh` - Remove nodes from service clusters

**Features:**
- Automatic bootstrap vs join mode detection
- Dynamic replica count calculation
- Peer discovery and connection
- Volume creation and brick management
- Auto-mount configuration
- Dry-run support for testing

## Prerequisites

1. **Configuration File**: `my_multihead_cluster.yaml` with GlusterFS-enabled controllers
2. **Network**: SSH connectivity between all controllers
3. **Permissions**: Root/sudo access
4. **Dependencies**: Python 3 with PyYAML, jq

## GlusterFS Setup Script

### Usage

```bash
# Auto mode (recommended) - detects bootstrap vs join automatically
sudo ./cluster/setup/phase0_storage.sh --config ../my_multihead_cluster.yaml

# Force bootstrap mode (first node)
sudo ./cluster/setup/phase0_storage.sh --bootstrap

# Force join mode (additional nodes)
sudo ./cluster/setup/phase0_storage.sh --join

# Dry-run to preview changes
./cluster/setup/phase0_storage.sh --dry-run
```

### Options

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml) |
| `--bootstrap` | Force bootstrap mode (create new cluster) |
| `--join` | Force join mode (join existing cluster) |
| `--dry-run` | Show what would be done without executing |
| `--help` | Show help message |

### How It Works

**8-Step Process:**

1. **Load Configuration**
   - Parse YAML config
   - Detect current controller by IP
   - Extract GlusterFS settings (volume name, brick path, mount point, replica count)

2. **Check and Install GlusterFS**
   - Detect if GlusterFS is installed
   - Auto-install based on OS (Ubuntu/Debian or CentOS/RHEL)
   - Enable and start glusterd service

3. **Prepare Brick Directory**
   - Create brick directory (default: `/data/glusterfs/shared`)
   - Set proper permissions

4. **Discover Active GlusterFS Nodes**
   - Run auto_discovery.sh to find active controllers
   - Filter controllers with `services.glusterfs: true`
   - Check GlusterFS service status on each

5. **Determine Operation Mode**
   - **Auto mode**:
     - If no active nodes found → Bootstrap mode
     - If active nodes found → Join mode
   - **Manual mode**: Use `--bootstrap` or `--join` flag

6. **Peer Connection**
   - **Bootstrap mode**: No peers to connect yet
   - **Join mode**: Probe all active GlusterFS nodes

7. **Volume Creation/Join**
   - **Bootstrap mode**:
     - Create new volume with replica count
     - Set performance options
     - Start volume
   - **Join mode**:
     - Add brick to existing volume
     - Automatically rebalance data

8. **Mount Volume**
   - Create mount point (default: `/mnt/gluster`)
   - Mount volume via localhost
   - Add to /etc/fstab for auto-mount on boot
   - Create directory structure (bootstrap only)

### Directory Structure Created

Bootstrap mode creates this structure on mounted volume:

```
/mnt/gluster/
├── frontend_builds/     # Built React/Vue frontends
├── slurm/
│   ├── state/          # Slurm state files
│   ├── logs/           # Slurm logs
│   └── spool/          # Slurm spool
├── uploads/            # User uploads
└── config/             # Shared configuration files
```

### Example Scenarios

#### Scenario 1: First Node (Bootstrap)

```bash
# On server1 (192.168.1.101)
sudo ./cluster/setup/phase0_storage.sh

# Output:
# [INFO] No active nodes found → Bootstrap mode
# [SUCCESS] Volume created and started
# [SUCCESS] Volume mounted at /mnt/gluster
```

**Result:**
- GlusterFS cluster initialized
- Volume "shared_data" created with 1 brick
- Mounted at /mnt/gluster

#### Scenario 2: Second Node (Auto Join)

```bash
# On server2 (192.168.1.102)
sudo ./cluster/setup/phase0_storage.sh

# Output:
# [INFO] Active nodes found → Join mode
# [INFO] Connected to server1
# [SUCCESS] Brick added to volume
# [SUCCESS] Volume mounted at /mnt/gluster
```

**Result:**
- Joined existing cluster
- Brick added to volume
- Replica count increased to 2

#### Scenario 3: Third Node (Dry-Run First)

```bash
# Preview changes without executing
./cluster/setup/phase0_storage.sh --dry-run

# Output:
# [DRY-RUN] Would install GlusterFS packages
# [DRY-RUN] Would create directory: /data/glusterfs/shared
# [DRY-RUN] Would run: gluster peer probe 192.168.1.101
# [DRY-RUN] Would create/join volume: shared_data

# Then execute for real
sudo ./cluster/setup/phase0_storage.sh
```

## Node Management Utilities

### Add Node to Cluster

```bash
# Add GlusterFS node
sudo ./cluster/utils/node_add.sh --service glusterfs --ip 192.168.1.105

# Add MariaDB Galera node
sudo ./cluster/utils/node_add.sh --service mariadb --ip 192.168.1.105

# Add Redis Cluster node
sudo ./cluster/utils/node_add.sh --service redis --ip 192.168.1.105

# Add Slurm controller
sudo ./cluster/utils/node_add.sh --service slurm --ip 192.168.1.105
```

#### GlusterFS Node Addition

**Process:**
1. Probe peer: `gluster peer probe <IP>`
2. Verify peer status
3. Add brick to volume
4. Rebalance volume data

**Example:**
```bash
sudo ./cluster/utils/node_add.sh --service glusterfs --ip 192.168.1.105

# Output:
# ✓ Peer 192.168.1.105 added successfully
# ℹ Current peer status:
#   Number of Peers: 4
# ℹ Add brick to volume:
#   gluster volume add-brick shared_data replica 5 192.168.1.105:/data/glusterfs/shared force
```

#### MariaDB Node Addition

**Process:**
1. Display instructions for Galera join
2. Show current cluster size
3. Verify quorum requirements

**Example:**
```bash
sudo ./cluster/utils/node_add.sh --service mariadb --ip 192.168.1.105

# Output:
# ℹ MariaDB Galera cluster join requires:
#   1. On the new node (192.168.1.105):
#      - Install MariaDB
#      - Configure galera.cnf with wsrep_cluster_address
#      - Start MariaDB (will auto-join via SST)
```

#### Redis Node Addition

**Process:**
1. Check cluster mode
2. Add node to cluster
3. Rebalance hash slots
4. Verify cluster info

**Example:**
```bash
sudo ./cluster/utils/node_add.sh --service redis --ip 192.168.1.105

# Output:
# ✓ Node 192.168.1.105:6379 added to cluster
# ℹ Rebalancing hash slots...
# ✓ Cluster rebalanced
```

### Remove Node from Cluster

```bash
# Remove GlusterFS node
sudo ./cluster/utils/node_remove.sh --service glusterfs --ip 192.168.1.105

# Remove MariaDB node
sudo ./cluster/utils/node_remove.sh --service mariadb --ip 192.168.1.105

# Remove Redis node
sudo ./cluster/utils/node_remove.sh --service redis --ip 192.168.1.105

# Remove Slurm controller
sudo ./cluster/utils/node_remove.sh --service slurm --ip 192.168.1.105
```

#### GlusterFS Node Removal

**Process:**
1. Confirm removal
2. Check if bricks are removed from volumes
3. Detach peer
4. Display remaining peers

**Example:**
```bash
sudo ./cluster/utils/node_remove.sh --service glusterfs --ip 192.168.1.105

# Output:
# ⚠ Before removing peer, ensure all bricks from this node are removed from volumes!
# ℹ To remove bricks:
#   gluster volume remove-brick shared_data 192.168.1.105:/data/glusterfs/shared start
#   gluster volume remove-brick shared_data 192.168.1.105:/data/glusterfs/shared commit
#
# Have you removed all bricks from this node? (yes/no): yes
# ✓ Peer 192.168.1.105 removed successfully
```

**IMPORTANT**: Always remove bricks from volumes before detaching peer!

#### MariaDB Node Removal

**Process:**
1. Display removal instructions
2. Show current cluster size
3. Warn about minimum quorum (2 nodes)

**Example:**
```bash
sudo ./cluster/utils/node_remove.sh --service mariadb --ip 192.168.1.105

# Output:
# ⚠ MariaDB Galera cluster removal requires:
#   1. On the node to remove (192.168.1.105):
#      - Stop MariaDB: systemctl stop mariadb
#   2. On remaining nodes (optional, for cleanup):
#      - UPDATE wsrep_cluster_address (remove 192.168.1.105)
# ⚠ Minimum cluster size: 2 nodes (for quorum)
```

#### Redis Node Removal

**Process:**
1. Get node ID
2. Check hash slot assignment
3. Reshard slots to other nodes
4. Remove node from cluster

**Example:**
```bash
sudo ./cluster/utils/node_remove.sh --service redis --ip 192.168.1.105

# Output:
# ℹ Node ID: 1a2b3c4d5e6f...
# ⚠ Node has 3 hash slot ranges
# ℹ Resharding hash slots to other nodes...
# ✓ Slots resharded
# ✓ Node 192.168.1.105 removed from cluster
```

## Configuration Reference

### YAML Configuration

```yaml
storage:
  glusterfs:
    volume_name: shared_data          # Volume name
    replica_count: auto               # 'auto' or specific number (2, 3, 4...)
    brick_path: /data/glusterfs/shared  # Brick directory
    mount_point: /mnt/gluster         # Mount point

nodes:
  controllers:
    - hostname: server1
      ip_address: 192.168.1.101
      priority: 100
      services:
        glusterfs: true               # Enable GlusterFS on this controller
        mariadb: true
        redis: true
        slurm: true
        web: true
        keepalived: true
      vip_owner: true
```

### Replica Count Strategies

| Replica Count | Use Case | Fault Tolerance |
|---------------|----------|-----------------|
| 1 (no replica) | Testing/dev | None - data loss if node fails |
| 2 | Minimum production | 1 node can fail |
| 3 (recommended) | Production | 1 node can fail + maintenance |
| 4+ | High availability | Multiple node failures |

**Auto mode**: Sets replica count = number of GlusterFS-enabled controllers

### Volume Performance Options

Default settings applied by phase0_storage.sh:

```bash
gluster volume set shared_data performance.cache-size 256MB
gluster volume set shared_data network.ping-timeout 10
gluster volume set shared_data cluster.self-heal-daemon on
```

## Troubleshooting

### Issue: glusterd not running

```bash
# Check service status
sudo systemctl status glusterd

# Start service
sudo systemctl start glusterd

# Enable auto-start
sudo systemctl enable glusterd
```

### Issue: Peer probe failed

```bash
# Check network connectivity
ping 192.168.1.105

# Check glusterd on remote
ssh 192.168.1.105 "sudo systemctl status glusterd"

# Check firewall
sudo firewall-cmd --list-all  # CentOS/RHEL
sudo ufw status               # Ubuntu
```

**Required ports:**
- 24007: glusterd
- 24008: Management
- 49152+: Brick ports

### Issue: Volume not mounting

```bash
# Check if volume is started
sudo gluster volume info shared_data

# Start volume if stopped
sudo gluster volume start shared_data

# Check mount point
mount | grep gluster

# Manual mount
sudo mount -t glusterfs localhost:/shared_data /mnt/gluster
```

### Issue: Current controller not found in config

```bash
# Check current IPs
hostname -I

# Verify config has matching IP
python3 cluster/config/parser.py --config my_multihead_cluster.yaml --current

# Update YAML if needed
vi my_multihead_cluster.yaml
```

### Issue: Split-brain (conflicting data)

```bash
# Check split-brain status
sudo gluster volume heal shared_data info split-brain

# Heal volume
sudo gluster volume heal shared_data

# Full heal
sudo gluster volume heal shared_data full
```

## Testing

### Test 1: Dry-Run Mode

```bash
# Test without making changes
./cluster/setup/phase0_storage.sh --dry-run

# Expected output:
# [DRY-RUN] Would install GlusterFS packages
# [DRY-RUN] Would create directory: /data/glusterfs/shared
# [DRY-RUN] Would enable and start glusterd service
```

### Test 2: Bootstrap First Node

```bash
# On first controller
sudo ./cluster/setup/phase0_storage.sh --bootstrap

# Verify volume created
sudo gluster volume info shared_data

# Verify mount
df -h | grep gluster

# Test write
echo "test" | sudo tee /mnt/gluster/test.txt
```

### Test 3: Join Additional Node

```bash
# On second controller
sudo ./cluster/setup/phase0_storage.sh --join

# Verify peer connected
sudo gluster peer status

# Verify brick added
sudo gluster volume info shared_data

# Verify data replication
cat /mnt/gluster/test.txt  # Should show "test"
```

### Test 4: Node Addition

```bash
# Add new node
sudo ./cluster/utils/node_add.sh --service glusterfs --ip 192.168.1.105

# Verify peer
sudo gluster peer status | grep 192.168.1.105

# On new node, verify volume
sudo gluster volume info shared_data
```

### Test 5: Node Removal

```bash
# First remove brick
sudo gluster volume remove-brick shared_data replica 3 192.168.1.105:/data/glusterfs/shared start
sudo gluster volume remove-brick shared_data replica 3 192.168.1.105:/data/glusterfs/shared status
sudo gluster volume remove-brick shared_data replica 3 192.168.1.105:/data/glusterfs/shared commit

# Then remove node
sudo ./cluster/utils/node_remove.sh --service glusterfs --ip 192.168.1.105

# Verify removal
sudo gluster peer status | grep 192.168.1.105  # Should not be found
```

## Best Practices

### 1. Always Use Dry-Run First

```bash
# Preview changes
./cluster/setup/phase0_storage.sh --dry-run

# Review output, then execute
sudo ./cluster/setup/phase0_storage.sh
```

### 2. Remove Bricks Before Detaching Peers

```bash
# Wrong order:
# sudo gluster peer detach 192.168.1.105  ❌

# Correct order:
sudo gluster volume remove-brick shared_data replica N IP:/path start
sudo gluster volume remove-brick shared_data replica N IP:/path commit
sudo gluster peer detach 192.168.1.105  ✓
```

### 3. Monitor Rebalance Progress

```bash
# After adding brick
sudo gluster volume add-brick shared_data replica 4 192.168.1.105:/data/glusterfs/shared force

# Start rebalance
sudo gluster volume rebalance shared_data start

# Monitor progress
sudo gluster volume rebalance shared_data status
```

### 4. Regular Health Checks

```bash
# Check volume health
sudo gluster volume status shared_data

# Check self-heal
sudo gluster volume heal shared_data info

# Check peer status
sudo gluster peer status
```

### 5. Backup Configuration

```bash
# Backup GlusterFS config
sudo tar czf glusterfs-config-$(date +%F).tar.gz /var/lib/glusterd/

# Backup volume info
sudo gluster volume info > gluster-volumes-$(date +%F).txt
```

## Logs

### Log Locations

- **Phase 0 setup log**: `/var/log/cluster_storage_setup.log`
- **Node add log**: `/var/log/cluster_node_add.log`
- **Node remove log**: `/var/log/cluster_node_remove.log`
- **GlusterFS logs**: `/var/log/glusterfs/`

### View Logs

```bash
# Setup log
sudo tail -f /var/log/cluster_storage_setup.log

# GlusterFS glusterd log
sudo tail -f /var/log/glusterfs/glusterd.log

# Brick logs
sudo tail -f /var/log/glusterfs/bricks/data-glusterfs-shared.log
```

## Integration with Other Phases

Phase 1 GlusterFS provides shared storage for:

- **Phase 4 (Slurm)**: Shared state directory at `/mnt/gluster/slurm/state/`
- **Phase 6 (Web)**: Static files at `/mnt/gluster/frontend_builds/`
- **Phase 7 (Backup)**: Backup storage location
- **All Phases**: Shared config at `/mnt/gluster/config/`

## Next Steps

After completing Phase 1:

1. **Verify GlusterFS cluster is operational**
   ```bash
   sudo gluster volume status shared_data
   sudo gluster peer status
   ```

2. **Test data replication**
   ```bash
   echo "test" | sudo tee /mnt/gluster/test.txt
   # Check on other nodes
   ssh server2 "cat /mnt/gluster/test.txt"
   ```

3. **Proceed to Phase 2: MariaDB Galera Cluster**
   - Multi-master database replication
   - Dynamic node join/leave
   - Backup and restore

## References

- [GlusterFS Documentation](https://docs.gluster.org/)
- [GlusterFS Quick Start Guide](https://docs.gluster.org/en/latest/Quick-Start-Guide/Quickstart/)
- [GlusterFS Volume Management](https://docs.gluster.org/en/latest/Administrator-Guide/Managing-Volumes/)
- [my_multihead_cluster.yaml Configuration](../my_multihead_cluster.yaml)
- [MULTIHEAD_IMPLEMENTATION_PLAN.md](../dashboard/MULTIHEAD_IMPLEMENTATION_PLAN.md)
