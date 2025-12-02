#!/usr/bin/env python3
# test_job_templates.py - Job Template 시스템 테스트 스크립트

import requests
import json
import time
import os
import tempfile

BASE_URL = "http://localhost:5000"

def test_list_templates():
    """템플릿 목록 조회 테스트"""
    print("🔍 Testing template listing...")
    
    response = requests.get(f"{BASE_URL}/api/job-templates")
    assert response.status_code == 200
    
    data = response.json()
    print(f"✅ Found {len(data['templates'])} templates")
    
    for template in data['templates']:
        print(f"   - {template['name']} ({template['category']})")
    
    return data['templates']

def test_get_template_schema():
    """템플릿 스키마 조회 테스트"""
    print("\n📋 Testing template schema...")
    
    response = requests.get(f"{BASE_URL}/api/job-templates/lsdyna_basic/schema")
    assert response.status_code == 200
    
    schema = response.json()['schema']
    print(f"✅ Template: {schema['name']}")
    print(f"   Parameters: {list(schema['parameters'].keys())}")
    print(f"   Input files: {list(schema['input_files'].keys())}")
    
    return schema

def test_submit_job():
    """작업 제출 테스트"""
    print("\n🚀 Testing job submission...")
    
    # 임시 테스트 파일 생성
    with tempfile.NamedTemporaryFile(mode='w', suffix='.k', delete=False) as f:
        f.write("*KEYWORD\n*NODE\n1, 0.0, 0.0, 0.0\n*END\n")
        test_input_file = f.name
    
    try:
        # 파일과 파라미터 준비
        files = {
            'main_input': open(test_input_file, 'rb')
        }
        
        parameters = {
            "job_name": "test_job_001",
            "cores": 16,
            "time_limit": "00:30:00",
            "version": "R12",
            "mode": "smp",
            "precision": "double",
            "memory": "4GB"
        }
        
        data = {
            'parameters': json.dumps(parameters),
            'user': 'test_user'
        }
        
        # API 호출
        response = requests.post(
            f"{BASE_URL}/api/job-templates/lsdyna_basic/submit",
            files=files,
            data=data
        )
        
        files['main_input'].close()
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Job submitted successfully!")
            print(f"   Job ID: {result['job_id']}")
            print(f"   Job Name: {result['job_name']}")
            return result
        else:
            print(f"❌ Job submission failed: {response.text}")
            return None
        
    finally:
        # 임시 파일 정리
        if os.path.exists(test_input_file):
            os.unlink(test_input_file)

def main():
    """메인 테스트 실행"""
    print("🧪 Job Template System Test Suite")
    print("=" * 50)
    
    try:
        # Flask 서버가 실행 중인지 확인
        response = requests.get(f"{BASE_URL}/api/job-templates")
        if response.status_code != 200:
            print("❌ Flask server is not running. Please start the server first.")
            return
        
        # 1. 템플릿 목록 조회
        templates = test_list_templates()
        
        # 2. 스키마 조회
        schema = test_get_template_schema()
        
        # 3. 작업 제출
        job_result = test_submit_job()
        
        print("\n🎉 Basic tests completed!")
        
    except requests.ConnectionError:
        print("❌ Cannot connect to Flask server. Please start the server first.")
        print("   Run: python app.py")
    except Exception as e:
        print(f"\n❌ Test failed: {str(e)}")

if __name__ == "__main__":
    main()
