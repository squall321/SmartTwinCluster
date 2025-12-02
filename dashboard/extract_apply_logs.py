#!/usr/bin/env python3
"""
Extract recent apply-config related logs
"""

log_file = '/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/backend.log'

print("="*60)
print("Recent apply-config logs")
print("="*60)

with open(log_file, 'r') as f:
    lines = f.readlines()

# Find last occurrence of "Production Mode: Applying"
start_idx = None
for i in range(len(lines) - 1, -1, -1):
    if 'Production Mode: Applying' in lines[i]:
        start_idx = i
        break

if start_idx is None:
    print("❌ No recent apply-config execution found")
else:
    print(f"\nFound at line {start_idx + 1}:")
    print("="*60)
    
    # Print from start to end (or next 100 lines)
    end_idx = min(start_idx + 100, len(lines))
    for i in range(start_idx, end_idx):
        print(lines[i], end='')
        
        # Stop at next API call
        if i > start_idx + 5 and 'GET /' in lines[i] or 'POST /' in lines[i]:
            if 'apply-config' not in lines[i]:
                break

print("\n" + "="*60)
