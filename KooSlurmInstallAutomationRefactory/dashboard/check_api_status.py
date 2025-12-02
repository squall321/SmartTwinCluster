#!/usr/bin/env python3
"""
Check current API responses
"""
import requests
import json

print("="*60)
print("🔍 현재 API 상태 확인")
print("="*60)

# 1. Groups API
try:
    response = requests.get('http://localhost:5010/api/groups/partitions', timeout=5)
    data = response.json()
    print("\n1. GET /api/groups/partitions")
    print(f"   Status: {response.status_code}")
    print(f"   Mode: {data.get('mode', 'unknown')}")
    print(f"   Partitions: {len(data.get('partitions', []))}")
    for p in data.get('partitions', [])[:3]:
        print(f"      - {p.get('name')}: {p.get('label')}, CPUs: {p.get('allowedCoreSizes')}")
except Exception as e:
    print(f"\n❌ Error: {e}")

# 2. Cluster Config API
try:
    response = requests.get('http://localhost:5010/api/cluster/config', timeout=5)
    data = response.json()
    print("\n2. GET /api/cluster/config")
    print(f"   Status: {response.status_code}")
    print(f"   Mode: {data.get('mode', 'unknown')}")
    groups = data.get('config', {}).get('groups', [])
    print(f"   Groups: {len(groups)}")
    for g in groups[:3]:
        print(f"      - {g.get('partitionName')}: {g.get('name')}, CPUs: {g.get('allowedCoreSizes')}")
except Exception as e:
    print(f"\n❌ Error: {e}")

# 3. Backend 환경변수 확인
print("\n3. Backend 환경변수")
try:
    with open('backend_5010/.backend.pid', 'r') as f:
        pid = f.read().strip()
        with open(f'/proc/{pid}/environ', 'rb') as env_file:
            env_data = env_file.read().decode('utf-8', errors='ignore')
            for line in env_data.split('\0'):
                if 'MOCK_MODE' in line:
                    print(f"   {line}")
except Exception as e:
    print(f"   ⚠️  Cannot read: {e}")

# 4. Database 확인
print("\n4. Database cluster_config")
try:
    import sys
    import sqlite3
    sys.path.insert(0, 'backend_5010')
    
    conn = sqlite3.connect('backend_5010/database/dashboard.db')
    cursor = conn.cursor()
    cursor.execute("SELECT config FROM cluster_config WHERE id = 1")
    row = cursor.fetchone()
    
    if row:
        config = json.loads(row[0])
        groups = config.get('groups', [])
        print(f"   Groups in DB: {len(groups)}")
        for g in groups[:3]:
            print(f"      - {g.get('partitionName')}: {g.get('name')}, CPUs: {g.get('allowedCoreSizes')}")
    else:
        print("   ❌ No data in cluster_config table")
    
    conn.close()
except Exception as e:
    print(f"   ❌ Error: {e}")

print("\n" + "="*60)
