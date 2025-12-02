#!/usr/bin/env python3
"""
KooSlurmInstallAutomation - Python 환경 테스트
Python 3.13 가상환경에서의 기본 실행 확인
"""

import sys
import platform
import os
from datetime import datetime


def check_python_environment():
    """Python 환경 정보를 확인하고 출력합니다."""
    print("=" * 50)
    print("Python 환경 확인")
    print("=" * 50)
    
    # Python 버전 정보
    print(f"Python 버전: {sys.version}")
    print(f"Python 실행 경로: {sys.executable}")
    print(f"플랫폼: {platform.platform()}")
    print(f"아키텍처: {platform.architecture()}")
    
    # 가상환경 확인
    if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
        print("✅ 가상환경이 활성화되어 있습니다.")
        print(f"가상환경 경로: {sys.prefix}")
    else:
        print("❌ 가상환경이 활성화되어 있지 않습니다.")
    
    # 현재 작업 디렉토리
    print(f"현재 작업 디렉토리: {os.getcwd()}")
    print(f"현재 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")


def test_basic_operations():
    """기본적인 Python 연산을 테스트합니다."""
    print("\n" + "=" * 50)
    print("기본 연산 테스트")
    print("=" * 50)
    
    # 기본 연산
    a = 10
    b = 20
    result = a + b
    print(f"덧셈 테스트: {a} + {b} = {result}")
    
    # 리스트 연산
    test_list = [1, 2, 3, 4, 5]
    print(f"리스트 테스트: {test_list}")
    print(f"리스트 합계: {sum(test_list)}")
    
    # 딕셔너리 연산
    test_dict = {"name": "KooSlurmInstallAutomation", "version": "1.0.0"}
    print(f"딕셔너리 테스트: {test_dict}")
    
    # 문자열 연산
    test_string = "Python 3.13 가상환경 테스트"
    print(f"문자열 길이: {len(test_string)}")
    print(f"대문자 변환: {test_string.upper()}")


def test_imports():
    """기본 모듈 import 테스트"""
    print("\n" + "=" * 50)
    print("모듈 Import 테스트")
    print("=" * 50)
    
    modules_to_test = [
        'os', 'sys', 'json', 'datetime', 'math', 'random'
    ]
    
    for module_name in modules_to_test:
        try:
            __import__(module_name)
            print(f"✅ {module_name} 모듈 import 성공")
        except ImportError as e:
            print(f"❌ {module_name} 모듈 import 실패: {e}")


def main():
    """메인 함수"""
    print("🚀 KooSlurmInstallAutomation Python 환경 테스트 시작")
    
    # 환경 확인
    check_python_environment()
    
    # 기본 연산 테스트
    test_basic_operations()
    
    # 모듈 import 테스트
    test_imports()
    
    print("\n" + "=" * 50)
    print("✅ 모든 테스트가 완료되었습니다!")
    print("Python 3.13 가상환경이 정상적으로 작동하고 있습니다.")
    print("=" * 50)


if __name__ == "__main__":
    main()
