#!/usr/bin/env python3
"""
Check if cluster configuration is synchronized
실제 클러스터 구성과 DB가 동기화되었는지 확인
"""
import requests
import json
import sys

print("="*60)
print("🔍 클러스터 설정 동기화 상태 확인")
print("="*60)

# 1. Check database
print("\n1️⃣  데이터베이스 상태")
try:
    import sqlite3
    conn = sqlite3.connect('backend_5010/database/dashboard.db')
    cursor = conn.cursor()
    
    cursor.execute("SELECT config, created_at, updated_at FROM cluster_config WHERE id = 1")
    row = cursor.fetchone()
    
    if row:
        config = json.loads(row[0])
        created_at = row[1]
        updated_at = row[2]
        
        groups = config.get('groups', [])
        print(f"   ✅ cluster_config 테이블에 데이터 있음")
        print(f"   생성일: {created_at}")
        print(f"   수정일: {updated_at}")
        print(f"   그룹 개수: {len(groups)}")
        print(f"\n   그룹 상세:")
        for g in groups:
            node_count = g.get('nodeCount', 0)
            nodes = g.get('nodes', [])
            actual_nodes = len(nodes)
            print(f"      - {g['name']} ({g['partitionName']})")
            print(f"        CPUs: {g['allowedCoreSizes']}")
            print(f"        노드: {actual_nodes}/{node_count} 할당됨")
        
        # Check if it's default or modified
        if created_at == updated_at:
            print(f"\n   ⚠️  주의: 아직 수정되지 않음 (초기 설정 상태)")
            print(f"   → Cluster Management에서 'Apply Configuration' 필요")
        else:
            print(f"\n   ✅ 설정이 수정됨")
    else:
        print("   ❌ cluster_config 테이블이 비어있음")
    
    conn.close()
except Exception as e:
    print(f"   ❌ 에러: {e}")

# 2. Check API
print("\n2️⃣  API 응답 확인")
try:
    response = requests.get('http://localhost:5010/api/groups/partitions', timeout=5)
    data = response.json()
    
    print(f"   Mode: {data.get('mode')}")
    partitions = data.get('partitions', [])
    print(f"   Partitions: {len(partitions)}")
    for p in partitions:
        print(f"      - {p['name']}: {p['label']}, CPUs: {p['allowedCoreSizes']}")
except Exception as e:
    print(f"   ❌ 에러: {e}")

# 3. Frontend가 보는 데이터
print("\n3️⃣  Frontend Job Templates가 보는 데이터")
print("   → 위의 'API 응답 확인'과 동일한 데이터를 봅니다")

# 4. 해결 방법
print("\n" + "="*60)
print("📋 현재 상태 요약")
print("="*60)

try:
    conn = sqlite3.connect('backend_5010/database/dashboard.db')
    cursor = conn.cursor()
    cursor.execute("SELECT created_at, updated_at FROM cluster_config WHERE id = 1")
    row = cursor.fetchone()
    conn.close()
    
    if row and row[0] == row[1]:
        print("\n⚠️  현재 상태: 초기 설정 (6개 Mock 그룹)")
        print("\n🔧 실제 클러스터 설정을 반영하려면:")
        print("   1. Cluster Management 페이지 접속")
        print("   2. 노드를 그룹에 할당")
        print("   3. 'Apply Configuration' 버튼 클릭")
        print("   4. Job Templates에서 변경사항 확인")
    else:
        print("\n✅ 설정이 적용되었습니다")
        print("   Job Templates에서 실제 클러스터 그룹을 봐야 합니다")
except:
    pass

print("\n" + "="*60)
