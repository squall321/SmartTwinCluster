#!/usr/bin/env python3
"""
Extract the apply-config endpoint from app.py
"""

with open('/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/app.py', 'r') as f:
    lines = f.readlines()

# Find the apply-config endpoint (line 683)
start = 683 - 1  # 0-indexed
end = start + 120  # Get 120 lines to see the full function

print("="*60)
print("/api/slurm/apply-config endpoint (Lines 683-800)")
print("="*60)

for i in range(start, min(end, len(lines))):
    print(f"{i+1}: {lines[i]}", end='')
    
    # Stop at next @app.route
    if i > start + 5 and lines[i].strip().startswith('@app.route'):
        break

print("\n" + "="*60)
