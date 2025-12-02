#!/usr/bin/env python3
# check_mock_status.py - MOCK 모드 상태 간단 확인

import requests
import os

BASE_URL = "http://localhost:5000"

def check_mock_status():
    print("🎭 MOCK 모드 상태 확인...")
    
    # 환경변수 확인
    env_mock = os.environ.get('MOCK_SLURM', '1')
    print(f"🔧 환경변수 MOCK_SLURM: {env_mock}")
    
    try:
        # 서버 응답 확인
        response = requests.get(f"{BASE_URL}/api/slurm/cluster-status", timeout=3)
        if response.status_code == 200:
            data = response.json()
            server_mock = data.get('mock_mode', 'unknown')
            print(f"🌐 서버 MOCK 모드: {server_mock}")
            
            if server_mock:
                print("✅ MOCK 모드로 실행 중입니다!")
                print("   - 실제 SLURM 없이 동작")
                print("   - 가상 데이터로 테스트 가능")
            else:
                print("⚠️  실제 SLURM 모드로 실행 중입니다!")
                print("   - 실제 SLURM 클러스터 필요")
                print("   - MOCK 모드로 변경하려면:")
                print("     export MOCK_SLURM=1  # Linux/macOS")
                print("     set MOCK_SLURM=1     # Windows")
        else:
            print(f"❌ 서버 응답 오류: {response.status_code}")
            
    except requests.ConnectionError:
        print("❌ 서버에 연결할 수 없습니다.")
        print("   서버를 먼저 시작하세요:")
        print("   ./server_manager.sh start")
    except Exception as e:
        print(f"❌ 오류: {e}")

if __name__ == "__main__":
    check_mock_status()
