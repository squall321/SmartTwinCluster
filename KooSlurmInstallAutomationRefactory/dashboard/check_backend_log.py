#!/usr/bin/env python3
"""
Check the last 200 lines of backend.log for apply-config errors
"""

log_file = '/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/backend.log'

print("="*60)
print("Backend Log - Last 200 lines")
print("="*60)

try:
    with open(log_file, 'r') as f:
        lines = f.readlines()
        
    # Get last 200 lines
    recent_lines = lines[-200:]
    
    # Print all lines
    for line in recent_lines:
        print(line, end='')
    
except FileNotFoundError:
    print(f"❌ Log file not found: {log_file}")
except Exception as e:
    print(f"❌ Error reading log: {e}")

print("\n" + "="*60)
