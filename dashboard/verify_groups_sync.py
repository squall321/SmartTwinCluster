#!/usr/bin/env python3
"""
Verify cluster groups synchronization
클러스터 그룹 동기화 검증
"""
import sys
import requests
import json

def check_api(url, name):
    """API 호출 및 검증"""
    try:
        response = requests.get(url, timeout=5)
        response.raise_for_status()
        data = response.json()
        
        print(f"\n{'='*60}")
        print(f"📡 {name}")
        print(f"{'='*60}")
        print(f"Mode: {data.get('mode', 'unknown')}")
        
        return data
    except Exception as e:
        print(f"❌ Error calling {name}: {e}")
        return None

def main():
    print("\n" + "="*60)
    print("🔍 클러스터 그룹 동기화 검증")
    print("="*60)
    
    # 1. Cluster Config API 호출
    cluster_data = check_api('http://localhost:5010/api/cluster/config', 'Cluster Config API')
    if not cluster_data:
        print("\n❌ Cluster Config API 호출 실패")
        sys.exit(1)
    
    cluster_groups = cluster_data.get('config', {}).get('groups', [])
    print(f"\n📊 Cluster Groups: {len(cluster_groups)}개")
    for g in cluster_groups:
        print(f"  - {g['name']} ({g['partitionName']}): CPUs {g['allowedCoreSizes']}")
    
    # 2. Groups API 호출
    groups_data = check_api('http://localhost:5010/api/groups', 'Groups API')
    if not groups_data:
        print("\n❌ Groups API 호출 실패")
        sys.exit(1)
    
    api_groups = groups_data.get('groups', [])
    print(f"\n📊 API Groups: {len(api_groups)}개")
    for g in api_groups:
        print(f"  - {g['name']} ({g['partitionName']}): CPUs {g['allowedCoreSizes']}")
    
    # 3. Partitions API 호출
    partitions_data = check_api('http://localhost:5010/api/groups/partitions', 'Partitions API')
    if not partitions_data:
        print("\n❌ Partitions API 호출 실패")
        sys.exit(1)
    
    partitions = partitions_data.get('partitions', [])
    print(f"\n📊 Partitions: {len(partitions)}개")
    for p in partitions:
        print(f"  - {p['label']} ({p['name']}): CPUs {p['allowedCoreSizes']}")
    
    # 4. 동기화 검증
    print(f"\n{'='*60}")
    print("✅ 동기화 검증")
    print(f"{'='*60}")
    
    issues = []
    
    # 그룹 개수 확인
    if len(cluster_groups) != len(api_groups):
        issues.append(f"그룹 개수 불일치: Cluster({len(cluster_groups)}) vs API({len(api_groups)})")
    
    if len(api_groups) != len(partitions):
        issues.append(f"파티션 개수 불일치: API({len(api_groups)}) vs Partitions({len(partitions)})")
    
    # 각 그룹의 파티션 이름과 CPU 정책 확인
    cluster_map = {g['partitionName']: g for g in cluster_groups}
    api_map = {g['partitionName']: g for g in api_groups}
    partition_map = {p['name']: p for p in partitions}
    
    for partition_name in cluster_map.keys():
        cluster_g = cluster_map[partition_name]
        api_g = api_map.get(partition_name)
        partition_p = partition_map.get(partition_name)
        
        if not api_g:
            issues.append(f"{partition_name}: Groups API에 없음")
            continue
        
        if not partition_p:
            issues.append(f"{partition_name}: Partitions API에 없음")
            continue
        
        # CPU 정책 확인
        cluster_cpus = sorted(cluster_g['allowedCoreSizes'])
        api_cpus = sorted(api_g['allowedCoreSizes'])
        partition_cpus = sorted(partition_p['allowedCoreSizes'])
        
        if cluster_cpus != api_cpus:
            issues.append(f"{partition_name}: CPU 정책 불일치 - Cluster{cluster_cpus} vs API{api_cpus}")
        
        if api_cpus != partition_cpus:
            issues.append(f"{partition_name}: CPU 정책 불일치 - API{api_cpus} vs Partition{partition_cpus}")
    
    # 결과 출력
    if issues:
        print("\n❌ 동기화 문제 발견:")
        for issue in issues:
            print(f"  - {issue}")
        sys.exit(1)
    else:
        print("\n✅ 모든 API가 동기화되어 있습니다!")
        print("\n📋 요약:")
        print(f"  - 총 그룹 수: {len(cluster_groups)}")
        print(f"  - Cluster Config API: ✅")
        print(f"  - Groups API: ✅")
        print(f"  - Partitions API: ✅")
        print(f"  - 모든 파티션 이름 일치: ✅")
        print(f"  - 모든 CPU 정책 일치: ✅")

if __name__ == '__main__':
    main()
