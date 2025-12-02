#!/usr/bin/env python3
"""
Check Backend status and configuration
"""
import requests
import subprocess
import os

print("="*60)
print("🔍 Backend Status Check")
print("="*60)

# 1. Check if backend is running
print("\n1️⃣  Backend Process:")
try:
    pid_file = '/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/.backend.pid'
    if os.path.exists(pid_file):
        with open(pid_file, 'r') as f:
            pid = f.read().strip()
        print(f"   PID: {pid}")
        
        # Check environment variables
        try:
            env_file = f'/proc/{pid}/environ'
            with open(env_file, 'rb') as f:
                env_data = f.read().decode('utf-8', errors='ignore')
                for line in env_data.split('\0'):
                    if 'MOCK_MODE' in line:
                        print(f"   {line}")
        except:
            print("   ⚠️  Cannot read environment variables")
    else:
        print("   ❌ Backend not running (no PID file)")
except Exception as e:
    print(f"   ❌ Error: {e}")

# 2. Test API endpoint
print("\n2️⃣  API Test:")
try:
    # Test a simple endpoint first
    response = requests.get('http://localhost:5010/api/health', timeout=5)
    print(f"   Health Check: {response.status_code}")
    
    # Test apply-config with empty data (should fail but show mode)
    response = requests.post(
        'http://localhost:5010/api/slurm/apply-config',
        json={'groups': []},
        timeout=5
    )
    data = response.json()
    print(f"   Status: {response.status_code}")
    print(f"   Response: {data}")
    
except requests.exceptions.ConnectionError:
    print("   ❌ Cannot connect to backend (not running?)")
except Exception as e:
    print(f"   ❌ Error: {e}")

# 3. Check recent errors in log
print("\n3️⃣  Recent Errors in Log:")
try:
    log_file = '/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/backend.log'
    with open(log_file, 'r') as f:
        lines = f.readlines()
    
    # Find recent errors
    errors = []
    for i, line in enumerate(lines[-100:], start=len(lines)-100):
        if 'ERROR' in line.upper() or '❌' in line or 'Traceback' in line:
            errors.append((i+1, line))
    
    if errors:
        print(f"   Found {len(errors)} error lines:")
        for line_num, line in errors[-10:]:  # Last 10 errors
            print(f"   Line {line_num}: {line.strip()}")
    else:
        print("   ✅ No recent errors found")
        
except Exception as e:
    print(f"   ❌ Error reading log: {e}")

print("\n" + "="*60)
