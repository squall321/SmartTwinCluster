#!/usr/bin/env python3
"""
Find the apply_configuration method in slurm_config_manager.py
"""

with open('/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/slurm_config_manager.py', 'r') as f:
    lines = f.readlines()

# Find apply_configuration method
for i, line in enumerate(lines, 1):
    if 'def apply_configuration' in line:
        print(f"Found at line {i}")
        print("="*60)
        
        # Print the method (next 100 lines)
        for j in range(i-1, min(i+99, len(lines))):
            print(f"{j+1}: {lines[j]}", end='')
        
        print("="*60)
        break
