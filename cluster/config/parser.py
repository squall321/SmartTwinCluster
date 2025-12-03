#!/usr/bin/env python3
"""
Multi-Head Cluster Configuration Parser
Parses my_multihead_cluster.yaml and provides helper functions
"""

import yaml
import os
import sys
import argparse
import json
import re
from pathlib import Path
from typing import Dict, List, Any, Optional


class ClusterConfigParser:
    """Parser for my_multihead_cluster.yaml"""

    def __init__(self, config_path: str):
        """
        Initialize parser with config file path

        Args:
            config_path: Path to my_multihead_cluster.yaml
        """
        self.config_path = Path(config_path)

        if not self.config_path.exists():
            raise FileNotFoundError(f"Config file not found: {config_path}")

        # Load YAML
        with open(self.config_path, 'r', encoding='utf-8') as f:
            self.config = yaml.safe_load(f)

        # Substitute environment variables
        self._substitute_env_vars()

    def _substitute_env_vars(self):
        """Substitute ${VAR_NAME} with environment variable values"""
        def substitute(obj):
            if isinstance(obj, dict):
                return {k: substitute(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [substitute(item) for item in obj]
            elif isinstance(obj, str):
                # Find ${VAR_NAME} pattern
                pattern = r'\$\{([^}]+)\}'
                matches = re.findall(pattern, obj)

                for var_name in matches:
                    # Get environment variable value
                    env_value = os.getenv(var_name, f'${{{var_name}}}')
                    obj = obj.replace(f'${{{var_name}}}', env_value)

                return obj
            else:
                return obj

        self.config = substitute(self.config)

    def get_controllers(self) -> List[Dict[str, Any]]:
        """
        Get all controllers list

        Returns:
            List of controller dictionaries
        """
        # Try both locations for backward compatibility
        controllers = self.config.get('controllers', [])
        if not controllers:
            controllers = self.config.get('nodes', {}).get('controllers', [])
        return controllers

    def get_active_controllers(self, service: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Get active controllers, optionally filtered by service

        Args:
            service: Service name to filter ('glusterfs', 'mariadb', 'redis', 'slurm', 'web', 'keepalived')
                    If None, return all controllers

        Returns:
            List of controller dictionaries with specified service enabled
        """
        controllers = self.get_controllers()

        if service is None:
            return controllers

        # Filter by service
        active = []
        for ctrl in controllers:
            services = ctrl.get('services', {})
            if services.get(service, False):
                active.append(ctrl)

        return active

    def get_current_controller(self) -> Optional[Dict[str, Any]]:
        """
        Get current controller info based on local IP address

        Returns:
            Controller dictionary if found, None otherwise
        """
        # Get local IP addresses
        import socket
        import subprocess

        local_ips = set()

        # Method 1: Get hostname IP
        try:
            hostname = socket.gethostname()
            local_ips.add(socket.gethostbyname(hostname))
        except:
            pass

        # Method 2: Parse ip addr output
        try:
            result = subprocess.run(['ip', 'addr'], capture_output=True, text=True)
            for line in result.stdout.split('\n'):
                if 'inet ' in line:
                    ip = line.strip().split()[1].split('/')[0]
                    local_ips.add(ip)
        except:
            pass

        # Find matching controller
        for ctrl in self.get_controllers():
            if ctrl.get('ip_address') in local_ips:
                return ctrl

        return None

    def get_vip_config(self) -> Dict[str, Any]:
        """
        Get VIP configuration

        Returns:
            VIP configuration dictionary
        """
        vip = self.config.get('network', {}).get('vip', {})
        # Handle both string and dict formats
        if isinstance(vip, str):
            return {'address': vip}
        return vip

    def get_storage_config(self) -> Dict[str, Any]:
        """
        Get shared storage configuration

        Returns:
            Storage configuration dictionary
        """
        return self.config.get('shared_storage', {})

    def get_database_config(self) -> Dict[str, Any]:
        """
        Get database configuration

        Returns:
            Database configuration dictionary
        """
        return self.config.get('database', {})

    def get_redis_config(self) -> Dict[str, Any]:
        """
        Get Redis configuration

        Returns:
            Redis configuration dictionary
        """
        return self.config.get('redis', {})

    def get_slurm_config(self) -> Dict[str, Any]:
        """
        Get Slurm configuration

        Returns:
            Slurm configuration dictionary
        """
        return self.config.get('slurm_config', {})

    def get_web_services_config(self) -> Dict[str, Any]:
        """
        Get web services configuration

        Returns:
            Web services configuration dictionary
        """
        return self.config.get('web_services', {})

    def get_cluster_info(self) -> Dict[str, Any]:
        """
        Get cluster information

        Returns:
            Cluster info dictionary
        """
        # Try both locations for backward compatibility
        cluster_info = self.config.get('cluster', {})
        if not cluster_info:
            cluster_info = self.config.get('cluster_info', {})
        return cluster_info

    def get_value(self, key_path: str) -> Any:
        """
        Get value by dot-notation key path (e.g., 'database.mariadb.root_password')

        Args:
            key_path: Dot-separated path to the value

        Returns:
            Value at the specified path, or None if not found
        """
        keys = key_path.split('.')
        value = self.config
        for key in keys:
            if isinstance(value, dict):
                value = value.get(key)
                if value is None:
                    return None
            else:
                return None
        return value

    def validate(self) -> tuple[bool, List[str]]:
        """
        Validate configuration

        Returns:
            (is_valid, error_messages)
        """
        errors = []

        # Check required sections (flexible for backward compatibility)
        # Accept either 'cluster' or 'cluster_info'
        if 'cluster' not in self.config and 'cluster_info' not in self.config:
            errors.append("Missing required section: cluster or cluster_info")

        # Accept either 'controllers' or 'nodes'
        if 'controllers' not in self.config and 'nodes' not in self.config:
            errors.append("Missing required section: controllers or nodes")

        # Network is required
        if 'network' not in self.config:
            errors.append("Missing required section: network")

        # Check controllers
        controllers = self.get_controllers()
        if not controllers:
            errors.append("No controllers defined")

        # Check for duplicate IPs
        ips = [ctrl.get('ip_address') for ctrl in controllers]
        if len(ips) != len(set(ips)):
            errors.append("Duplicate IP addresses found in controllers")

        # Check for duplicate priorities
        priorities = [ctrl.get('priority') for ctrl in controllers]
        if len(priorities) != len(set(priorities)):
            errors.append("Duplicate priorities found in controllers")

        # Check VIP configuration
        vip = self.get_vip_config()
        if not vip.get('address'):
            errors.append("VIP address not configured")

        # Check at least one vip_owner
        vip_owners = [ctrl for ctrl in controllers if ctrl.get('vip_owner', False)]
        if not vip_owners:
            errors.append("No controller with vip_owner=true")

        return (len(errors) == 0, errors)

    def to_json(self) -> str:
        """
        Convert entire config to JSON

        Returns:
            JSON string
        """
        return json.dumps(self.config, indent=2)


def main():
    """Main CLI entry point"""
    # Support both old and new CLI interfaces
    # Old: parser.py CONFIG_PATH command [args]
    # New: parser.py --config CONFIG_PATH --command

    # Check if using old positional interface
    if len(sys.argv) >= 3 and not sys.argv[1].startswith('--'):
        # Old interface: parser.py CONFIG_PATH command [args]
        config_path = sys.argv[1]
        command = sys.argv[2]
        extra_args = sys.argv[3:] if len(sys.argv) > 3 else []

        try:
            config_parser = ClusterConfigParser(config_path)
        except Exception as e:
            print(f"Error loading config: {e}", file=sys.stderr)
            sys.exit(1)

        # Handle old-style commands
        if command == 'validate':
            is_valid, errors = config_parser.validate()
            if is_valid:
                print("✅ Configuration is valid")
                sys.exit(0)
            else:
                print("❌ Configuration validation failed:")
                for error in errors:
                    print(f"  - {error}")
                sys.exit(1)

        elif command == 'get-controllers':
            service = None
            if '--service' in extra_args:
                idx = extra_args.index('--service')
                if idx + 1 < len(extra_args):
                    service = extra_args[idx + 1]

            if service:
                output = config_parser.get_active_controllers(service)
            else:
                output = config_parser.get_controllers()
            print(json.dumps(output, indent=2))

        elif command == 'get-value':
            if not extra_args:
                print("Error: get-value requires a key path", file=sys.stderr)
                sys.exit(1)

            key_path = extra_args[0]
            keys = key_path.split('.')
            value = config_parser.config

            try:
                for key in keys:
                    value = value[key]
                print(value)
            except (KeyError, TypeError):
                # Key not found
                sys.exit(1)

        else:
            print(f"Unknown command: {command}", file=sys.stderr)
            sys.exit(1)

        return

    # New interface with argparse
    parser = argparse.ArgumentParser(
        description='Multi-Head Cluster Configuration Parser',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List all controllers
  %(prog)s --config my_multihead_cluster.yaml --list-controllers

  # Get controllers with MariaDB enabled
  %(prog)s --config my_multihead_cluster.yaml --service mariadb

  # Get VIP configuration
  %(prog)s --config my_multihead_cluster.yaml --get-vip

  # Validate configuration
  %(prog)s --config my_multihead_cluster.yaml --validate

  # Get current controller info
  %(prog)s --config my_multihead_cluster.yaml --current

  # Old interface (also supported):
  %(prog)s CONFIG_PATH validate
  %(prog)s CONFIG_PATH get-controllers --service web
  %(prog)s CONFIG_PATH get-value cluster.name
        """
    )

    parser.add_argument(
        '--config',
        type=str,
        default='../my_multihead_cluster.yaml',
        help='Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)'
    )

    parser.add_argument(
        '--list-controllers',
        action='store_true',
        help='List all controllers'
    )

    parser.add_argument(
        '--service',
        type=str,
        choices=['glusterfs', 'mariadb', 'redis', 'slurm', 'web', 'keepalived'],
        help='Filter controllers by service'
    )

    parser.add_argument(
        '--get',
        type=str,
        metavar='KEY_PATH',
        help='Get value by dot-notation path (e.g., database.mariadb.root_password)'
    )

    parser.add_argument(
        '--get-vip',
        action='store_true',
        help='Get VIP configuration'
    )

    parser.add_argument(
        '--get-storage',
        action='store_true',
        help='Get storage configuration'
    )

    parser.add_argument(
        '--get-database',
        action='store_true',
        help='Get database configuration'
    )

    parser.add_argument(
        '--get-redis',
        action='store_true',
        help='Get Redis configuration'
    )

    parser.add_argument(
        '--get-slurm',
        action='store_true',
        help='Get Slurm configuration'
    )

    parser.add_argument(
        '--validate',
        action='store_true',
        help='Validate configuration'
    )

    parser.add_argument(
        '--current',
        action='store_true',
        help='Get current controller info (based on local IP)'
    )

    parser.add_argument(
        '--json',
        action='store_true',
        help='Output in JSON format'
    )

    args = parser.parse_args()

    # Parse config
    try:
        config_parser = ClusterConfigParser(args.config)
    except Exception as e:
        print(f"Error loading config: {e}", file=sys.stderr)
        sys.exit(1)

    # Execute command
    output = None

    if args.validate:
        is_valid, errors = config_parser.validate()
        if is_valid:
            print("✅ Configuration is valid")
            sys.exit(0)
        else:
            print("❌ Configuration validation failed:")
            for error in errors:
                print(f"  - {error}")
            sys.exit(1)

    elif args.list_controllers:
        output = config_parser.get_controllers()

    elif args.service:
        output = config_parser.get_active_controllers(args.service)

    elif args.get:
        output = config_parser.get_value(args.get)
        # Print raw value for simple types (string, number, bool)
        if output is not None and not isinstance(output, (dict, list)):
            print(output)
            sys.exit(0)

    elif args.get_vip:
        output = config_parser.get_vip_config()

    elif args.get_storage:
        output = config_parser.get_storage_config()

    elif args.get_database:
        output = config_parser.get_database_config()

    elif args.get_redis:
        output = config_parser.get_redis_config()

    elif args.get_slurm:
        output = config_parser.get_slurm_config()

    elif args.current:
        output = config_parser.get_current_controller()
        if output is None:
            print("❌ Current controller not found (IP not in config)", file=sys.stderr)
            sys.exit(1)

    else:
        # No command specified, show help
        parser.print_help()
        sys.exit(0)

    # Output result
    if output is not None:
        if args.json or isinstance(output, (dict, list)):
            print(json.dumps(output, indent=2))
        else:
            print(output)


if __name__ == '__main__':
    main()
