#!/usr/bin/env python3
"""
KooSlurmInstallAutomation 테스트 스위트
"""

import unittest
import sys
from pathlib import Path

# src 디렉토리를 Python 경로에 추가
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from test_config_parser import TestConfigParser
from test_utils import TestUtils
from test_ssh_manager import TestSSHManager


def run_all_tests():
    """모든 테스트 실행"""
    
    print("🧪 KooSlurmInstallAutomation 테스트 시작")
    print("=" * 60)
    
    # 테스트 로더
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # 테스트 클래스들 추가
    test_classes = [
        TestConfigParser,
        TestUtils,
        TestSSHManager
    ]
    
    for test_class in test_classes:
        tests = loader.loadTestsFromTestCase(test_class)
        suite.addTests(tests)
    
    # 테스트 실행
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # 결과 요약
    print("\n" + "=" * 60)
    print("테스트 결과 요약")
    print("=" * 60)
    
    total_tests = result.testsRun
    failures = len(result.failures)
    errors = len(result.errors)
    successes = total_tests - failures - errors
    
    print(f"총 테스트: {total_tests}")
    print(f"성공: {successes}")
    print(f"실패: {failures}")
    print(f"오류: {errors}")
    
    if result.wasSuccessful():
        print("\n✅ 모든 테스트가 통과했습니다!")
        return True
    else:
        print("\n❌ 일부 테스트가 실패했습니다.")
        
        if result.failures:
            print("\n실패한 테스트:")
            for test, traceback in result.failures:
                print(f"  - {test}: {traceback.split('AssertionError:')[-1].strip() if 'AssertionError:' in traceback else 'Assertion 실패'}")
        
        if result.errors:
            print("\n오류가 발생한 테스트:")
            for test, traceback in result.errors:
                error_msg = traceback.split('\n')[-2] if traceback.split('\n') else '알 수 없는 오류'
                print(f"  - {test}: {error_msg}")
        
        return False


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
