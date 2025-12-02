#!/usr/bin/env python3
"""
Slurm 명령어 경로 테스트 스크립트
"""

import sys
import os

# 현재 디렉토리를 Python path에 추가
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from slurm_commands import (
    check_slurm_installation,
    get_sinfo,
    get_squeue,
    get_scontrol,
    SLURM_BIN_DIR
)

def main():
    print("="*60)
    print("Slurm 명령어 경로 테스트")
    print("="*60)
    print(f"SLURM_BIN_DIR: {SLURM_BIN_DIR}\n")
    
    # 1. 설치 확인
    print("1. Slurm 설치 확인...")
    if check_slurm_installation():
        print("   ✅ Slurm이 올바르게 설치되어 있습니다.\n")
    else:
        print("   ❌ Slurm을 찾을 수 없습니다!")
        print(f"   위치를 확인하세요: {SLURM_BIN_DIR}\n")
        return 1
    
    # 2. sinfo 테스트
    print("2. sinfo 테스트...")
    try:
        result = get_sinfo('--version', check=False)
        if result.returncode == 0:
            print(f"   ✅ {result.stdout.strip()}")
        else:
            print(f"   ⚠️  실행 실패: {result.stderr}")
    except Exception as e:
        print(f"   ❌ 에러: {e}")
    print()
    
    # 3. squeue 테스트
    print("3. squeue 테스트...")
    try:
        result = get_squeue('--version', check=False)
        if result.returncode == 0:
            print(f"   ✅ {result.stdout.strip()}")
        else:
            print(f"   ⚠️  실행 실패: {result.stderr}")
    except Exception as e:
        print(f"   ❌ 에러: {e}")
    print()
    
    # 4. scontrol 테스트
    print("4. scontrol 테스트...")
    try:
        result = get_scontrol('--version', check=False)
        if result.returncode == 0:
            print(f"   ✅ {result.stdout.strip()}")
        else:
            print(f"   ⚠️  실행 실패: {result.stderr}")
    except Exception as e:
        print(f"   ❌ 에러: {e}")
    print()
    
    # 5. 실제 클러스터 상태 조회 (간단한 테스트)
    print("5. 실제 클러스터 상태 조회...")
    try:
        result = get_sinfo('-h', '-o', '%T', timeout=5, check=False)
        if result.returncode == 0:
            node_states = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
            print(f"   ✅ 총 {len(node_states)}개 노드 발견")
            if node_states:
                print(f"   샘플 상태: {node_states[:3]}")
        else:
            print(f"   ⚠️  조회 실패: {result.stderr}")
    except Exception as e:
        print(f"   ❌ 에러: {e}")
    print()
    
    # 6. 작업 조회
    print("6. 작업 큐 조회...")
    try:
        result = get_squeue('-h', '-o', '%i|%T', timeout=5, check=False)
        if result.returncode == 0:
            jobs = [line for line in result.stdout.strip().split('\n') if line.strip()]
            print(f"   ✅ 총 {len(jobs)}개 작업 발견")
            if jobs:
                print(f"   샘플: {jobs[:3]}")
        else:
            print(f"   ⚠️  조회 실패: {result.stderr}")
    except Exception as e:
        print(f"   ❌ 에러: {e}")
    print()
    
    print("="*60)
    print("테스트 완료!")
    print("="*60)
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
