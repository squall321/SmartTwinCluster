#!/usr/bin/env python3
"""
KooSlurmInstallAutomation - 테스트 러너
모든 단위 테스트를 실행하는 스크립트
"""

import sys
import os
import unittest
from pathlib import Path

# 프로젝트 루트 디렉토리를 경로에 추가
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root / 'src'))
sys.path.insert(0, str(project_root / 'tests'))


def run_all_tests(verbosity=2):
    """모든 테스트 실행"""
    
    print("=" * 70)
    print("KooSlurmInstallAutomation - 단위 테스트 실행")
    print("=" * 70)
    print()
    
    # 테스트 디렉토리
    test_dir = project_root / 'tests'
    
    # 테스트 로더
    loader = unittest.TestLoader()
    
    # 모든 테스트 발견
    suite = loader.discover(
        start_dir=str(test_dir),
        pattern='test_*.py',
        top_level_dir=str(project_root)
    )
    
    # 테스트 실행
    runner = unittest.TextTestRunner(verbosity=verbosity)
    result = runner.run(suite)
    
    # 결과 요약
    print()
    print("=" * 70)
    print("테스트 결과 요약")
    print("=" * 70)
    print(f"총 테스트: {result.testsRun}개")
    print(f"성공: {result.testsRun - len(result.failures) - len(result.errors)}개")
    print(f"실패: {len(result.failures)}개")
    print(f"에러: {len(result.errors)}개")
    
    if result.skipped:
        print(f"건너뜀: {len(result.skipped)}개")
    
    print("=" * 70)
    
    # 실패한 테스트 상세 정보
    if result.failures:
        print()
        print("❌ 실패한 테스트:")
        for test, traceback in result.failures:
            print(f"  - {test}")
    
    if result.errors:
        print()
        print("💥 에러가 발생한 테스트:")
        for test, traceback in result.errors:
            print(f"  - {test}")
    
    # 성공 여부 반환
    return result.wasSuccessful()


def run_specific_test(test_module, verbosity=2):
    """특정 테스트 모듈만 실행"""
    
    print(f"테스트 모듈 실행: {test_module}")
    print("=" * 70)
    
    # 테스트 로더
    loader = unittest.TestLoader()
    
    # 특정 모듈 로드
    suite = loader.loadTestsFromName(test_module)
    
    # 테스트 실행
    runner = unittest.TextTestRunner(verbosity=verbosity)
    result = runner.run(suite)
    
    return result.wasSuccessful()


def list_available_tests():
    """사용 가능한 테스트 목록 출력"""
    
    test_dir = project_root / 'tests'
    test_files = sorted(test_dir.glob('test_*.py'))
    
    print("사용 가능한 테스트 모듈:")
    print("-" * 70)
    
    for test_file in test_files:
        module_name = test_file.stem
        print(f"  - {module_name}")
        
        # 테스트 클래스 찾기 (간단한 파싱)
        with open(test_file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        import re
        classes = re.findall(r'class (Test\w+)\(', content)
        
        for cls in classes:
            print(f"      └─ {cls}")
    
    print("-" * 70)


def main():
    """메인 함수"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='KooSlurmInstallAutomation 테스트 러너',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 모든 테스트 실행
  python run_tests.py
  
  # 특정 테스트만 실행
  python run_tests.py --module test_config_parser
  
  # 상세 출력
  python run_tests.py --verbose
  
  # 간단한 출력
  python run_tests.py --quiet
  
  # 사용 가능한 테스트 목록
  python run_tests.py --list
        """
    )
    
    parser.add_argument(
        '--module', '-m',
        help='실행할 특정 테스트 모듈 (예: test_config_parser)'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='상세한 출력'
    )
    
    parser.add_argument(
        '--quiet', '-q',
        action='store_true',
        help='간단한 출력'
    )
    
    parser.add_argument(
        '--list', '-l',
        action='store_true',
        help='사용 가능한 테스트 목록 표시'
    )
    
    parser.add_argument(
        '--coverage',
        action='store_true',
        help='커버리지 측정 (pytest-cov 필요)'
    )
    
    args = parser.parse_args()
    
    # 테스트 목록 표시
    if args.list:
        list_available_tests()
        return 0
    
    # 커버리지 측정
    if args.coverage:
        print("커버리지 측정을 위해 pytest를 사용합니다...")
        import subprocess
        
        cmd = [
            'python', '-m', 'pytest',
            '--cov=src',
            '--cov-report=term-missing',
            '--cov-report=html',
            'tests/'
        ]
        
        result = subprocess.run(cmd)
        return result.returncode
    
    # verbosity 설정
    verbosity = 2  # 기본값
    if args.verbose:
        verbosity = 2
    elif args.quiet:
        verbosity = 1
    
    # 테스트 실행
    if args.module:
        success = run_specific_test(args.module, verbosity)
    else:
        success = run_all_tests(verbosity)
    
    # 결과에 따라 종료 코드 반환
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
