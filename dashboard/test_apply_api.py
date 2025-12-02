#!/usr/bin/env python3
"""
Test the API directly to see what's happening
"""
import requests
import json

print("="*60)
print("🧪 Direct API Test")
print("="*60)

# Test data - minimal group
test_groups = [
    {
        'id': 1,
        'name': 'Group 1',
        'partitionName': 'group1',
        'qosName': 'group1_qos',
        'allowedCoreSizes': [8192],
        'nodes': [
            {'hostname': 'node001', 'cores': 128},
            {'hostname': 'node002', 'cores': 128},
        ],
        'nodeCount': 2,
        'totalCores': 256,
    }
]

print("\n1️⃣  Sending test request...")
print(f"   Groups: {len(test_groups)}")
print(f"   Nodes in Group 1: {len(test_groups[0]['nodes'])}")

try:
    response = requests.post(
        'http://localhost:5010/api/slurm/apply-config',
        json={'groups': test_groups},
        timeout=30
    )
    
    print(f"\n2️⃣  Response:")
    print(f"   Status Code: {response.status_code}")
    print(f"   Response:")
    print(json.dumps(response.json(), indent=2))
    
    if response.status_code == 200:
        print("\n✅ API call successful!")
    else:
        print("\n❌ API call failed!")
        
except requests.exceptions.Timeout:
    print("\n⏱️  Request timed out (>30s)")
    print("   This might indicate a hanging Slurm command")
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()

print("\n" + "="*60)
