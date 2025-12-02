#!/usr/bin/env python3
"""
Find all /api/slurm routes in app.py to understand the structure
"""
import re

app_py = '/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/app.py'

with open(app_py, 'r') as f:
    lines = f.readlines()

print("="*60)
print("All /api/slurm routes in app.py")
print("="*60)

for i, line in enumerate(lines, 1):
    if '@app.route' in line and 'slurm' in line.lower():
        # Print route and next few lines to see the function
        print(f"\nLine {i}: {line.strip()}")
        for j in range(i, min(i+5, len(lines))):
            print(f"  {j+1}: {lines[j].rstrip()}")

print("\n" + "="*60)
