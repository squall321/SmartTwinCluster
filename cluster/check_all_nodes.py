#!/usr/bin/env python3
"""
Cluster Nodes Status Checker

Checks and displays the status of all nodes in the cluster (controllers + compute nodes).
"""

import yaml
import json
import subprocess
import sys
import argparse
from pathlib import Path

# ANSI colors
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

def check_node_status(ip, ssh_user=None):
    """Check if node is reachable via ping and SSH"""
    # Try ping
    ping_result = subprocess.run(
        ['ping', '-c', '1', '-W', '1', ip],
        capture_output=True,
        timeout=3
    )

    if ping_result.returncode != 0:
        return "DOWN", RED

    # Try SSH
    ssh_target = f"{ssh_user}@{ip}" if ssh_user else ip
    ssh_result = subprocess.run(
        ['timeout', '3', 'ssh', '-o', 'ConnectTimeout=2',
         '-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes',
         ssh_target, 'echo'],
        capture_output=True,
        timeout=5
    )

    if ssh_result.returncode == 0:
        return "UP (SSH OK)", GREEN
    else:
        return "PING OK, SSH FAILED", YELLOW

def main():
    parser = argparse.ArgumentParser(description='Check cluster nodes status')
    parser.add_argument('--config', default='my_multihead_cluster.yaml',
                      help='Path to cluster configuration YAML')
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.exists():
        print(f"{RED}[ERROR]{NC} Configuration file not found: {config_path}")
        sys.exit(1)

    # Load configuration
    with open(config_path) as f:
        config = yaml.safe_load(f)

    # Get all nodes
    controllers = config.get('nodes', {}).get('controllers', [])
    for c in controllers:
        c['node_role'] = 'controller'

    compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
    for c in compute_nodes:
        c['node_role'] = 'compute'

    all_nodes = controllers + compute_nodes

    # Print header
    print()
    print(f"{BLUE}╔════════════════════════════════════════════════════════════════════════════════╗{NC}")
    print(f"{BLUE}║                        Cluster Nodes Status                                    ║{NC}")
    print(f"{BLUE}╚════════════════════════════════════════════════════════════════════════════════╝{NC}")
    print()
    print(f"{BLUE}Config:{NC} {config_path}")
    print()
    print(f"{'HOSTNAME':<20} {'IP ADDRESS':<18} {'ROLE':<12} {'STATUS':<25} {'SERVICES':<30}")
    print("━" * 105)

    # Check each node
    alive_count = 0

    for node in all_nodes:
        hostname = node['hostname']
        ip = node['ip_address']
        role = node['node_role']
        ssh_user = node.get('ssh_user', None)  # Get SSH user from config

        # Get services
        if role == 'controller':
            services_dict = node.get('services', {})
            services = ','.join([k for k, v in services_dict.items() if v])
        else:
            services = 'slurmd'

        # Check status
        try:
            status, color = check_node_status(ip, ssh_user)
            if "SSH OK" in status:
                alive_count += 1
        except Exception as e:
            status = f"ERROR: {str(e)}"
            color = RED

        # Print node info
        print(f"{color}{hostname:<20} {ip:<18} {role:<12} {status:<25}{NC} {services:<30}")

    # Print summary
    print()
    print(f"{BLUE}{'━' * 105}{NC}")
    print(f"{BLUE}Node Summary:{NC}")
    print(f"  • Controllers: {len(controllers)}")
    print(f"  • Compute Nodes: {len(compute_nodes)}")
    print(f"  • Total: {len(all_nodes)}")
    print()

    if alive_count == len(all_nodes):
        print(f"{GREEN}✅ Status: All {len(all_nodes)} nodes are fully accessible{NC}")
    elif alive_count > 0:
        print(f"{YELLOW}⚠️  Status: {alive_count}/{len(all_nodes)} nodes are fully accessible{NC}")
    else:
        print(f"{RED}❌ Status: No nodes are fully accessible (0/{len(all_nodes)}){NC}")

    print()
    print(f"{BLUE}Additional Commands:{NC}")
    print("  • Full status:     ./cluster/status_multihead.sh --all")
    print("  • Slurm status:    sinfo")
    print("  • Service status:  systemctl status glusterd mariadb redis slurmctld keepalived nginx")
    print()

if __name__ == '__main__':
    main()
