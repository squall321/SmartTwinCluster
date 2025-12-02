#!/usr/bin/env python3
# test_mock_mode.py - MOCK 모드 전용 테스트

import requests
import json
import time

BASE_URL = "http://localhost:5000"

def test_mock_mode():
    """MOCK 모드 기능 테스트"""
    print("🎭 MOCK 모드 전용 테스트 시작...")
    
    try:
        # 1. MOCK 모드 확인
        print("\n1️⃣ MOCK 모드 확인...")
        response = requests.get(f"{BASE_URL}/api/slurm/cluster-status")
        if response.status_code == 200:
            data = response.json()
            mock_mode = data.get('mock_mode', False)
            print(f"   MOCK 모드: {mock_mode}")
            
            if not mock_mode:
                print("   ⚠️  실제 SLURM 모드로 실행 중입니다.")
                print("   MOCK 모드로 실행하려면: MOCK_SLURM=1 python app.py")
                return False
        
        # 2. 가상 클러스터 상태 확인
        print("\n2️⃣ 가상 클러스터 상태...")
        print(f"   LS-DYNA 코어 사용량: {data.get('lsdyna_cores', 0)}")
        print(f"   활성 사용자 수: {len(data.get('user_usage', []))}")
        
        # 사용자별 사용량 표시
        user_usage = data.get('user_usage', [])
        if user_usage:
            print("   👥 사용자별 코어 사용량:")
            for user in user_usage[:5]:
                print(f"      - {user['user']}: {user['cores']} 코어")
        
        # 3. 가상 노드 정보 확인
        print("\n3️⃣ 가상 노드 정보...")
        sinfo_response = requests.get(f"{BASE_URL}/api/slurm/sinfo")
        if sinfo_response.status_code == 200:
            sinfo_data = sinfo_response.json()['output']
            node_lines = [line for line in sinfo_data.split('\n') if 'R' in line and 'N' in line]
            print(f"   가상 노드 수: {len(node_lines)}개")
            if node_lines:
                print(f"   첫 번째 노드: {node_lines[0].split()[-1]}")
        
        # 4. 가상 작업 큐 확인
        print("\n4️⃣ 가상 작업 큐...")
        squeue_response = requests.get(f"{BASE_URL}/api/slurm/squeue")
        if squeue_response.status_code == 200:
            squeue_data = squeue_response.json()['output']
            job_lines = [line for line in squeue_data.split('\n') if line.strip() and 'JOBID' not in line]
            print(f"   실행 중인 가상 작업: {len(job_lines)}개")
            
            if job_lines:
                print("   최근 작업들:")
                for job in job_lines[:3]:
                    parts = job.strip().split()
                    if len(parts) >= 4:
                        print(f"      - Job {parts[0]}: {parts[2]} ({parts[3]})")
        
        # 5. 템플릿 기반 가상 작업 제출 테스트
        print("\n5️⃣ 가상 작업 제출 테스트...")
        
        # 임시 테스트 파일 생성
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.k', delete=False) as f:
            f.write("*KEYWORD\n*NODE\n1, 0.0, 0.0, 0.0\n*END\n")
            test_file_path = f.name
        
        try:
            files = {'main_input': open(test_file_path, 'rb')}
            parameters = {
                "job_name": "mock_test_job",
                "cores": 32,
                "time_limit": "00:10:00",
                "version": "R12",
                "mode": "smp",
                "precision": "double"
            }
            data = {
                'parameters': json.dumps(parameters),
                'user': 'mock_test_user'
            }
            
            submit_response = requests.post(
                f"{BASE_URL}/api/job-templates/lsdyna_basic/submit",
                files=files,
                data=data
            )
            
            files['main_input'].close()
            
            if submit_response.status_code == 200:
                result = submit_response.json()
                print(f"   ✅ 가상 작업 제출 성공!")
                print(f"   Job ID: {result['job_id']}")
                print(f"   SLURM 결과: {result['slurm_result']}")
                
                # 작업 상태 확인
                time.sleep(2)
                status_response = requests.get(f"{BASE_URL}/api/jobs/{result['job_id']}/status")
                if status_response.status_code == 200:
                    status = status_response.json()
                    print(f"   작업 상태: {status['status']}")
                    print(f"   실행 노드: {status.get('node', 'N/A')}")
            else:
                print(f"   ❌ 가상 작업 제출 실패: {submit_response.text}")
        
        finally:
            import os
            if os.path.exists(test_file_path):
                os.unlink(test_file_path)
        
        print("\n🎉 MOCK 모드 테스트 완료!")
        print("\n📋 MOCK 모드 특징:")
        print("   - 실제 SLURM 없이 동작")
        print("   - 가상 27개 노드 (R01N01~R03N09)")  
        print("   - 가상 작업 자동 생성 및 완료")
        print("   - 실제 CAE 팀원 이름으로 시뮬레이션")
        print("   - 빠른 작업 완료 시간 (5-30초)")
        
        return True
        
    except requests.ConnectionError:
        print("❌ 서버에 연결할 수 없습니다.")
        print("   다음 명령어로 서버를 먼저 시작하세요:")
        print("   ./server_manager.sh start  (또는 python app.py)")
        return False
    except Exception as e:
        print(f"❌ 테스트 중 오류 발생: {e}")
        return False

if __name__ == "__main__":
    test_mock_mode()
