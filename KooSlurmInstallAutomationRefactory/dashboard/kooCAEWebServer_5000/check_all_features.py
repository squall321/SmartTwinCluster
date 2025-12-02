#!/usr/bin/env python3
# check_all_features.py - 모든 기능 종합 테스트

import requests
import json
import sys

BASE_URL = "http://localhost:5000"

def test_server_connection():
    """서버 연결 테스트"""
    print("🔗 서버 연결 테스트...")
    try:
        response = requests.get(f"{BASE_URL}/api/job-templates", timeout=5)
        if response.status_code == 200:
            print("✅ 서버 연결 성공")
            return True
        else:
            print(f"❌ 서버 응답 오류: {response.status_code}")
            return False
    except requests.ConnectionError:
        print("❌ 서버에 연결할 수 없습니다. 'python app.py'로 서버를 먼저 실행하세요.")
        return False
    except Exception as e:
        print(f"❌ 연결 오류: {e}")
        return False

def test_existing_apis():
    """기존 API 기능 테스트"""
    print("\n📋 기존 API 기능 테스트...")
    
    apis_to_test = [
        ("/api/slurm/sinfo", "SLURM 노드 정보"),
        ("/api/slurm/squeue", "SLURM 작업 큐"),
        ("/api/slurm/lsdyna-core-usage", "LS-DYNA 코어 사용량"),
        ("/api/slurm/user-core-usage", "사용자별 코어 사용량"),
        ("/api/slurm/cluster-status", "클러스터 상태")
    ]
    
    success_count = 0
    for endpoint, description in apis_to_test:
        try:
            response = requests.get(f"{BASE_URL}{endpoint}")
            if response.status_code == 200:
                print(f"  ✅ {description}")
                success_count += 1
            else:
                print(f"  ❌ {description} - 상태코드: {response.status_code}")
        except Exception as e:
            print(f"  ❌ {description} - 오류: {e}")
    
    print(f"\n📊 기존 API 테스트 결과: {success_count}/{len(apis_to_test)} 성공")
    return success_count == len(apis_to_test)

def test_new_template_system():
    """새로운 템플릿 시스템 테스트"""
    print("\n🎯 새로운 템플릿 시스템 테스트...")
    
    try:
        # 템플릿 목록 조회
        response = requests.get(f"{BASE_URL}/api/job-templates")
        if response.status_code == 200:
            data = response.json()
            templates = data.get('templates', [])
            print(f"  ✅ 템플릿 목록 조회 성공 ({len(templates)}개 템플릿)")
            
            for template in templates:
                print(f"    - {template['name']} ({template['category']})")
            
            # 스키마 조회 테스트
            if templates:
                first_template = templates[0]['filename'].replace('.yaml', '').replace('.yml', '')
                schema_response = requests.get(f"{BASE_URL}/api/job-templates/{first_template}/schema")
                if schema_response.status_code == 200:
                    print(f"  ✅ 템플릿 스키마 조회 성공")
                    return True
                else:
                    print(f"  ❌ 템플릿 스키마 조회 실패")
                    return False
            else:
                print(f"  ❌ 템플릿이 없습니다")
                return False
        else:
            print(f"  ❌ 템플릿 목록 조회 실패: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"  ❌ 템플릿 시스템 오류: {e}")
        return False

def test_job_management():
    """작업 관리 기능 테스트"""
    print("\n📊 작업 관리 기능 테스트...")
    
    try:
        # 작업 히스토리 조회
        response = requests.get(f"{BASE_URL}/api/jobs/history?user=test_user")
        if response.status_code == 200:
            data = response.json()
            job_count = len(data.get('jobs', []))
            print(f"  ✅ 작업 히스토리 조회 성공 ({job_count}개 작업)")
            return True
        else:
            print(f"  ❌ 작업 히스토리 조회 실패: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"  ❌ 작업 관리 기능 오류: {e}")
        return False

def show_cluster_status():
    """클러스터 상태 상세 표시"""
    print("\n🖥️ 클러스터 상태 상세 정보...")
    
    try:
        response = requests.get(f"{BASE_URL}/api/slurm/cluster-status")
        if response.status_code == 200:
            data = response.json()
            print(f"  🔧 MOCK 모드: {data.get('mock_mode', 'unknown')}")
            print(f"  ⚡ LS-DYNA 코어: {data.get('lsdyna_cores', 0)}")
            print(f"  👥 활성 사용자: {len(data.get('user_usage', []))}")
            
            # 사용자별 사용량 표시
            user_usage = data.get('user_usage', [])
            if user_usage:
                print("  📊 사용자별 코어 사용량:")
                for user in user_usage[:5]:  # 상위 5명만 표시
                    print(f"    - {user['user']}: {user['cores']} 코어")
        else:
            print(f"  ❌ 클러스터 상태 조회 실패")
            
    except Exception as e:
        print(f"  ❌ 클러스터 상태 오류: {e}")

def main():
    """메인 테스트 실행"""
    print("🧪 KooCAE 전체 기능 종합 테스트")
    print("=" * 50)
    
    # 1. 서버 연결 테스트
    if not test_server_connection():
        sys.exit(1)
    
    # 2. 기존 API 테스트
    existing_api_ok = test_existing_apis()
    
    # 3. 새로운 템플릿 시스템 테스트
    template_system_ok = test_new_template_system()
    
    # 4. 작업 관리 기능 테스트
    job_management_ok = test_job_management()
    
    # 5. 클러스터 상태 상세 표시
    show_cluster_status()
    
    # 결과 요약
    print("\n" + "=" * 50)
    print("📋 테스트 결과 요약:")
    print(f"  {'✅' if existing_api_ok else '❌'} 기존 SLURM API 기능")
    print(f"  {'✅' if template_system_ok else '❌'} 새로운 템플릿 시스템")
    print(f"  {'✅' if job_management_ok else '❌'} 작업 관리 기능")
    
    all_ok = existing_api_ok and template_system_ok and job_management_ok
    
    if all_ok:
        print("\n🎉 모든 기능이 정상 작동합니다!")
        print("\n📝 다음 단계:")
        print("  1. 웹 브라우저에서 확인: http://localhost:5000")
        print("  2. 실제 파일로 테스트: python test_job_templates.py")
        print("  3. SLURM 실제 모드 테스트: export MOCK_SLURM=0")
    else:
        print("\n⚠️ 일부 기능에 문제가 있습니다.")
        print("  - Flask 서버가 정상 실행되었는지 확인하세요.")
        print("  - requirements.txt의 모든 패키지가 설치되었는지 확인하세요.")

if __name__ == "__main__":
    main()
