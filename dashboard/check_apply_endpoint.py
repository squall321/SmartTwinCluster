#!/usr/bin/env python3
"""
Check if /api/slurm/apply-config endpoint exists in app.py
"""
import os

app_py = '/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/app.py'

with open(app_py, 'r') as f:
    content = f.read()

if 'apply-config' in content:
    print("✅ Found 'apply-config' in app.py")
    
    # Find line numbers
    lines = content.split('\n')
    for i, line in enumerate(lines, 1):
        if 'apply-config' in line:
            print(f"   Line {i}: {line.strip()}")
            # Print context
            start = max(0, i - 5)
            end = min(len(lines), i + 10)
            print("\n   Context:")
            for j in range(start, end):
                marker = ">>> " if j == i - 1 else "    "
                print(f"{marker}{j+1}: {lines[j]}")
else:
    print("❌ 'apply-config' NOT FOUND in app.py")
    print("\n🔍 Searching for /api/slurm routes...")
    
    lines = content.split('\n')
    found_slurm = False
    for i, line in enumerate(lines, 1):
        if '/api/slurm' in line and '@app.route' in line:
            print(f"   Line {i}: {line.strip()}")
            found_slurm = True
    
    if not found_slurm:
        print("   No /api/slurm routes found")
        print("\n💡 The endpoint needs to be created!")
