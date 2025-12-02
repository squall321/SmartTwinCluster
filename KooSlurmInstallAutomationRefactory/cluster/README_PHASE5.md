# Phase 5: Keepalived VIP Management

Phase 5 implements Keepalived for Virtual IP (VIP) management with automatic failover, health checks, and notification scripts.

## Overview

**Components:**
- `setup/phase4_keepalived.sh` - Keepalived setup script
- `config/keepalived_template.conf` - Dynamic Keepalived configuration template
- Health check scripts - Monitor service health
- Notification scripts - Alert on state changes

**Features:**
- VRRP (Virtual Router Redundancy Protocol) implementation
- Priority-based master selection
- Automatic failover on failure
- Service health monitoring
- State change notifications
- Integration with all previous phases

## Prerequisites

1. **Phase 0-4 Completed**: All services (GlusterFS, MariaDB, Redis, Slurm) operational
2. **Network Configuration**: Controllers on same subnet
3. **VIP Configuration**: VIP address configured in YAML
4. **Keepalived Service**: Enabled in YAML for controllers

## VIP Architecture

### What is a VIP?

A Virtual IP (VIP) is a floating IP address that can be assigned to any controller in the cluster. Clients always connect to the VIP, and Keepalived ensures the VIP points to a healthy controller.

### Benefits

- **Single Entry Point**: Clients connect to one IP (VIP)
- **Automatic Failover**: VIP moves to backup if primary fails
- **No Client Reconfiguration**: Failover is transparent
- **High Availability**: Eliminates single point of failure

### Architecture Diagram

```
Clients (applications, users, compute nodes)
            │
            ▼
    VIP: 192.168.1.100 ◄── Managed by Keepalived
            │
     ┌──────┴──────┐
     │             │
  MASTER        BACKUP
server1(101)  server2(102)
Priority:100  Priority:90
VIP Owner     Standby
```

**Normal Operation:**
- server1 has priority 100 (highest)
- server1 owns VIP (MASTER state)
- server2 standby (BACKUP state)
- Clients connect to 192.168.1.100 → routes to server1

**After Failure:**
```
server1 FAILS
     │
     ▼
Keepalived detects failure
     │
     ▼
server2 takes VIP (becomes MASTER)
     │
     ▼
Clients connect to 192.168.1.100 → routes to server2
```

## Keepalived Setup

### Usage

```bash
# Setup Keepalived with auto-detection
sudo ./cluster/setup/phase4_keepalived.sh

# Dry-run to preview changes
./cluster/setup/phase4_keepalived.sh --dry-run
```

### Options

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to my_multihead_cluster.yaml |
| `--dry-run` | Show what would be done without executing |
| `--help` | Show help message |

### Setup Process (11 steps)

1. **Check Root Privileges**
2. **Check Dependencies** (python3, jq)
3. **Load Configuration** from YAML
4. **Detect Operating System**
5. **Check Keepalived Installation**
6. **Install Keepalived** if needed
7. **Create Health Check Script** - Monitors services
8. **Create Notification Scripts** - Alert on state changes
9. **Generate keepalived.conf** from template
10. **Enable IP Forwarding** - Allow VIP traffic
11. **Start Keepalived Service**

## Configuration Generation

### Dynamic keepalived.conf

The script generates keepalived.conf with these settings:

**Global Configuration:**
```conf
global_defs {
    router_id {{HOSTNAME}}
    enable_script_security
}
```

**Health Check:**
```conf
vrrp_script chk_services {
    script "/usr/local/bin/keepalived_health_check.sh"
    interval 5        # Check every 5 seconds
    weight -20        # Reduce priority by 20 if unhealthy
    fall 2           # 2 failures = unhealthy
    rise 2           # 2 successes = healthy
}
```

**VRRP Instance:**
```conf
vrrp_instance VI_MAIN {
    state {{STATE}}              # MASTER or BACKUP
    interface {{INTERFACE}}      # Network interface (eth0, ens0, etc.)
    virtual_router_id 51
    priority {{PRIORITY}}        # From YAML (VIP owner has highest)

    authentication {
        auth_type PASS
        auth_pass {{AUTH_PASS}}
    }

    virtual_ipaddress {
        {{VIP_ADDRESS}}/{{NETMASK}} dev {{INTERFACE}}
    }

    track_script {
        chk_services            # Monitor service health
    }

    notify_master "/usr/local/bin/keepalived_notify_master.sh"
    notify_backup "/usr/local/bin/keepalived_notify_backup.sh"
    notify_fault "/usr/local/bin/keepalived_notify_fault.sh"
}
```

### Health Check Script

**Purpose**: Check if critical services are running

**Generated at**: `/usr/local/bin/keepalived_health_check.sh`

**Logic**:
```bash
# Checks enabled services from YAML
CHECK_GLUSTERFS=true
CHECK_MARIADB=true
CHECK_REDIS=true
CHECK_SLURM=true

# If any service is down, return exit code 1
# Keepalived will reduce this node's priority
```

**Effect**:
- Exit 0: All services healthy → Normal priority
- Exit 1: Service down → Priority reduced by 20
- If priority drops below backup → VIP moves to backup

### Notification Scripts

**Purpose**: Log and alert on state changes

**Scripts created**:
1. `keepalived_notify_master.sh` - Called when becoming MASTER
2. `keepalived_notify_backup.sh` - Called when becoming BACKUP
3. `keepalived_notify_fault.sh` - Called when health check fails

**Log file**: `/var/log/keepalived_notify.log`

**Example log entry**:
```
2025-10-27 12:00:00: Transitioned to MASTER state
  Type: INSTANCE
  Name: VI_MAIN
  State: MASTER
```

## Example Scenarios

### Scenario 1: Setup 3-Node Cluster with Keepalived

**Configuration (my_multihead_cluster.yaml)**:
```yaml
network:
  vip:
    address: 192.168.1.100
    netmask: 24
    interface: eth0  # Auto-detected if not specified
    auth_pass: secure_password_here

nodes:
  controllers:
    - hostname: server1
      ip_address: 192.168.1.101
      priority: 100
      vip_owner: true
      services:
        glusterfs: true
        mariadb: true
        redis: true
        slurm: true
        keepalived: true

    - hostname: server2
      ip_address: 192.168.1.102
      priority: 90
      services:
        glusterfs: true
        mariadb: true
        redis: true
        slurm: true
        keepalived: true

    - hostname: server3
      ip_address: 192.168.1.103
      priority: 80
      services:
        glusterfs: true
        mariadb: true
        redis: true
        slurm: true
        keepalived: true
```

**Setup on server1 (VIP owner):**
```bash
sudo ./cluster/setup/phase4_keepalived.sh

# Output:
# [INFO] Current controller: server1 (192.168.1.101)
# [INFO] Priority: 100
# [INFO] VIP owner: true
# [INFO] VIP: 192.168.1.100/24 on eth0
# [SUCCESS] Health check script created
# [SUCCESS] Notification scripts created
# [SUCCESS] Keepalived configuration written
# [SUCCESS] Keepalived started successfully
# [SUCCESS] VIP 192.168.1.100 is assigned to this node (MASTER)
```

**Setup on server2 and server3:**
```bash
sudo ./cluster/setup/phase4_keepalived.sh

# Output:
# [INFO] Priority: 90 (or 80 for server3)
# [INFO] VIP owner: false
# [SUCCESS] Keepalived started successfully
# [INFO] VIP 192.168.1.100 is not assigned to this node (BACKUP)
```

**Verify VIP assignment:**
```bash
# On all nodes
ip addr show eth0 | grep 192.168.1.100

# Only server1 (MASTER) should show:
# inet 192.168.1.100/24 scope global secondary eth0
```

### Scenario 2: Test Manual Failover

**Initial state:**
```bash
# Check VIP owner
ip addr show | grep 192.168.1.100

# On server1:
# inet 192.168.1.100/24 scope global secondary eth0

# server1 is MASTER
```

**Stop Keepalived on server1:**
```bash
# On server1
sudo systemctl stop keepalived
```

**Automatic failover:**
- Keepalived on server1 stops
- VRRP advertisements cease
- server2 detects missing advertisements
- server2 transitions to MASTER (after ~3 seconds)
- server2 assigns VIP to its interface

**Verify failover:**
```bash
# On server2
ip addr show eth0 | grep 192.168.1.100

# Now shows:
# inet 192.168.1.100/24 scope global secondary eth0

# Check notification log
tail /var/log/keepalived_notify.log

# Shows:
# 2025-10-27 12:05:00: Transitioned to MASTER state
```

**Test connectivity:**
```bash
# From any client
ping 192.168.1.100
# Should work without interruption

# Connect to services via VIP
redis-cli -h 192.168.1.100 -a password PING
mysql -h 192.168.1.100 -u root -p
```

**Restart server1:**
```bash
# On server1
sudo systemctl start keepalived

# server1 rejoins as BACKUP (server2 stays MASTER with nopreempt)
# Or, if preemption enabled, server1 reclaims VIP after delay
```

### Scenario 3: Service Failure Detection

**Simulate service failure:**
```bash
# On server1 (MASTER)
sudo systemctl stop slurmctld
```

**Health check detects failure:**
1. Health check script runs every 5 seconds
2. Detects slurmctld is down
3. Returns exit code 1
4. Keepalived reduces priority by 20 (100 → 80)
5. server2 (priority 90) now has higher priority
6. VIP moves to server2

**Check logs:**
```bash
# On server1
journalctl -u keepalived -f

# Shows:
# VRRP_Script(chk_services) failed
# Priority decreased from 100 to 80
```

**Verify failover:**
```bash
# VIP should move to server2
# On server2
ip addr show eth0 | grep 192.168.1.100
```

**Fix service:**
```bash
# On server1
sudo systemctl start slurmctld

# Health check succeeds
# Priority restored to 100
# If preemption enabled, VIP returns to server1
```

### Scenario 4: Split-Brain Prevention

**What is split-brain?**
Multiple nodes think they are MASTER and assign VIP.

**Keepalived prevention mechanisms:**

1. **VRRP Protocol**: Only one MASTER per virtual_router_id
2. **Advertisement Timeout**: Nodes detect missing advertisements
3. **Priority-Based Election**: Highest priority wins
4. **Authentication**: Prevents rogue nodes

**Test scenario:**
```bash
# Network partition isolates server1
# server1 thinks it's still MASTER
# server2 also becomes MASTER

# When network heals:
# Both nodes exchange VRRP advertisements
# Higher priority node (server1: 100) wins
# Lower priority node (server2: 90) transitions to BACKUP
```

**Monitoring for split-brain:**
```bash
# On all nodes, check state
systemctl status keepalived | grep "State"

# Only one should show MASTER
```

## Troubleshooting

### Issue: VIP not assigned

```bash
# Check Keepalived status
sudo systemctl status keepalived

# Check logs
sudo journalctl -u keepalived -n 50

# Common causes:
# 1. Wrong interface
ip addr show

# 2. Firewall blocking VRRP (protocol 112)
sudo iptables -L | grep vrrp
sudo firewall-cmd --add-protocol=vrrp --permanent
sudo firewall-cmd --reload

# 3. SELinux blocking
sudo setenforce 0  # Temporary
sudo ausearch -m avc -ts recent  # Check denials

# 4. Priority conflict
# Check all nodes have different priorities
```

### Issue: Keepalived not starting

```bash
# Check config syntax
sudo keepalived -t -f /etc/keepalived/keepalived.conf

# Check if scripts are executable
ls -la /usr/local/bin/keepalived_*.sh

# Make executable
sudo chmod +x /usr/local/bin/keepalived_*.sh

# Check script errors
sudo /usr/local/bin/keepalived_health_check.sh
echo $?  # Should be 0 if healthy
```

### Issue: Frequent failover (flapping)

```bash
# Check health check script
sudo /usr/local/bin/keepalived_health_check.sh

# If failing, check which service is down
systemctl status glusterd mariadb redis-server slurmctld

# Increase check interval to reduce sensitivity
# Edit /etc/keepalived/keepalived.conf:
vrrp_script chk_services {
    interval 10     # Increase from 5 to 10
    fall 3          # Increase from 2 to 3
}

# Restart Keepalived
sudo systemctl restart keepalived
```

### Issue: VIP accessible on wrong interface

```bash
# Check interface configuration
ip addr show

# VIP should only be on one interface
# If on multiple, check keepalived.conf:
virtual_ipaddress {
    192.168.1.100/24 dev eth0  # Specify correct interface
}

# Restart Keepalived
sudo systemctl restart keepalived
```

### Issue: Backup not taking over

```bash
# On backup node, check if it sees MASTER advertisements
sudo tcpdump -i eth0 -n proto 112

# Should see periodic advertisements from MASTER
# If not:
# 1. Network issue between nodes
ping <master_ip>

# 2. Firewall blocking VRRP
sudo iptables -A INPUT -p vrrp -j ACCEPT
sudo iptables -A OUTPUT -p vrrp -j ACCEPT

# 3. Different virtual_router_id
# Check both nodes have same virtual_router_id in keepalived.conf
```

## Monitoring

### Check VIP Status

```bash
# Quick check - is VIP assigned to this node?
ip addr show | grep 192.168.1.100

# If assigned:
# inet 192.168.1.100/24 scope global secondary eth0

# Detailed interface info
ip addr show eth0
```

### Check Keepalived State

```bash
# Service status
sudo systemctl status keepalived

# Check MASTER/BACKUP state
sudo systemctl status keepalived | grep "State"

# Or check via logs
sudo journalctl -u keepalived | grep "Entering"
# Shows: Entering MASTER STATE or Entering BACKUP STATE
```

### Monitor Health Checks

```bash
# Run health check manually
sudo /usr/local/bin/keepalived_health_check.sh
echo $?
# 0 = healthy, 1 = unhealthy

# Watch health check results
watch -n 5 'sudo /usr/local/bin/keepalived_health_check.sh; echo Exit code: $?'
```

### Monitor Failover Events

```bash
# Watch notification log
tail -f /var/log/keepalived_notify.log

# Watch Keepalived logs
sudo journalctl -u keepalived -f

# Count failover events
grep "MASTER" /var/log/keepalived_notify.log | wc -l
```

### Network Monitoring

```bash
# Capture VRRP advertisements
sudo tcpdump -i eth0 -n proto 112

# Sample output:
# 12:00:01.123456 IP 192.168.1.101 > 224.0.0.18: VRRPv2, Advertisement, vrid 51, prio 100

# Monitor ARP announcements for VIP
sudo tcpdump -i eth0 -n 'arp and host 192.168.1.100'
```

### Important Metrics

| Metric | Command | Healthy Value |
|--------|---------|---------------|
| VIP Assigned | `ip addr show \| grep VIP` | One node has VIP |
| Keepalived State | `systemctl status keepalived` | active (running) |
| Health Check | Run health script | Exit code 0 |
| VRRP Packets | `tcpdump proto 112` | Periodic advertisements |
| Failover Count | Check notify log | Low frequency |

## Best Practices

### 1. Use Different Priorities

**Correct:**
```yaml
- hostname: server1
  priority: 100  # Primary
- hostname: server2
  priority: 90   # Backup 1
- hostname: server3
  priority: 80   # Backup 2
```

**Wrong:**
```yaml
- hostname: server1
  priority: 100
- hostname: server2
  priority: 100  # Same priority = unpredictable
```

### 2. VIP Owner Should Have Highest Priority

```yaml
- hostname: server1
  vip_owner: true
  priority: 100  # Highest
```

### 3. Use nopreempt on Backups

This prevents unnecessary failbacks:
```conf
# On backup nodes
nopreempt
```

**Effect**: Higher priority node won't take VIP back automatically

### 4. Monitor Health Checks

```bash
# Test health check regularly
sudo /usr/local/bin/keepalived_health_check.sh

# If fails, investigate immediately
```

### 5. Set Appropriate Check Intervals

**Too frequent**: False positives, unnecessary failovers
**Too slow**: Delayed failure detection

**Recommended**:
```conf
vrrp_script chk_services {
    interval 5     # 5 seconds
    fall 2         # 2 failures (10 seconds to declare unhealthy)
    rise 2         # 2 successes (10 seconds to declare healthy)
}
```

### 6. Secure VRRP Authentication

```yaml
network:
  vip:
    auth_pass: "Use_Strong_Password_Here_Not_Default"
```

### 7. Test Failover Regularly

```bash
# Monthly failover test
# 1. Stop Keepalived on MASTER
sudo systemctl stop keepalived

# 2. Verify VIP moves to BACKUP
# 3. Verify services accessible via VIP
# 4. Restart MASTER Keepalived
sudo systemctl start keepalived
```

## Integration with Other Phases

Phase 5 Keepalived integrates with:

- **Phase 1 (GlusterFS)**: Health check monitors glusterd
- **Phase 2 (MariaDB)**: Health check monitors mariadb, clients use VIP
- **Phase 3 (Redis)**: Health check monitors redis, clients use VIP
- **Phase 4 (Slurm)**: Health check monitors slurmctld, VIP determines primary
- **Phase 6 (Web)**: Web services bind to VIP, accessible via single endpoint

## Configuration Reference

### YAML Configuration

```yaml
network:
  vip:
    address: 192.168.1.100
    netmask: 24
    interface: eth0        # Optional, auto-detected
    auth_pass: secure_pass

nodes:
  controllers:
    - hostname: server1
      ip_address: 192.168.1.101
      priority: 100
      vip_owner: true
      services:
        glusterfs: true
        mariadb: true
        redis: true
        slurm: true
        keepalived: true     # Enable Keepalived
```

## Next Steps

After completing Phase 5:

1. **Verify Keepalived is operational**
   ```bash
   sudo systemctl status keepalived
   ip addr show | grep 192.168.1.100
   ```

2. **Test failover**
   ```bash
   sudo systemctl stop keepalived  # On MASTER
   # Verify VIP moves to BACKUP
   ```

3. **Monitor notification log**
   ```bash
   tail -f /var/log/keepalived_notify.log
   ```

4. **Proceed to Phase 6: Web Services Integration**
   - Deploy 8 web services
   - Configure to use VIP
   - Integrate with Redis (sessions)
   - Integrate with GlusterFS (static files)

## References

- [Keepalived Documentation](https://www.keepalived.org/documentation.html)
- [VRRP Protocol (RFC 5798)](https://datatracker.ietf.org/doc/html/rfc5798)
- [Keepalived Configuration Guide](https://www.keepalived.org/doc/configuration_synopsis.html)
- [my_multihead_cluster.yaml Configuration](../my_multihead_cluster.yaml)
- [MULTIHEAD_IMPLEMENTATION_PLAN.md](../dashboard/MULTIHEAD_IMPLEMENTATION_PLAN.md)
