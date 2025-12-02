#!/usr/bin/env python3
"""
실제 기능 동작 검증 스크립트
모든 핵심 기능이 정상 동작하는지 확인
"""

import sys
import os
from pathlib import Path

# 프로젝트 루트를 Python 경로에 추가
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root / 'src'))

def test_config_parser_import():
    """config_parser 모듈 import 테스트"""
    try:
        from config_parser import ConfigParser
        print("✅ config_parser 모듈 import 성공")
        return True
    except Exception as e:
        print(f"❌ config_parser 모듈 import 실패: {e}")
        return False

def test_validate_methods_exist():
    """검증 메서드 존재 여부 확인"""
    try:
        from config_parser import ConfigParser
        parser = ConfigParser("dummy.yaml")
        
        # 메서드 존재 확인
        assert hasattr(parser, '_validate_installation'), "_validate_installation 메서드 없음"
        assert hasattr(parser, '_validate_time_sync'), "_validate_time_sync 메서드 없음"
        
        print("✅ 모든 검증 메서드 존재 확인")
        return True
    except Exception as e:
        print(f"❌ 검증 메서드 확인 실패: {e}")
        return False

def test_example_file_validation(filename):
    """예제 파일 검증 테스트"""
    try:
        from config_parser import ConfigParser
        
        filepath = project_root / 'examples' / filename
        if not filepath.exists():
            print(f"⚠️  파일 없음: {filename}")
            return None
        
        parser = ConfigParser(str(filepath))
        config = parser.load_config()
        
        # 검증 수행
        is_valid = parser.validate_config()
        
        if is_valid:
            print(f"✅ {filename} 검증 통과")
            
            # 필수 섹션 확인
            if 'installation' in config:
                print(f"   ✓ installation 섹션 존재")
            if 'time_synchronization' in config:
                print(f"   ✓ time_synchronization 섹션 존재")
            
            return True
        else:
            print(f"❌ {filename} 검증 실패")
            print(f"   오류: {len(parser.errors)}개")
            print(f"   경고: {len(parser.warnings)}개")
            return False
            
    except Exception as e:
        print(f"❌ {filename} 테스트 실패: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_all():
    """모든 테스트 실행"""
    print("="*60)
    print("🔍 기능 동작 검증 시작")
    print("="*60)
    print()
    
    results = {}
    
    # 1. 모듈 import 테스트
    print("1. 모듈 Import 테스트")
    print("-" * 60)
    results['import'] = test_config_parser_import()
    print()
    
    # 2. 검증 메서드 존재 확인
    print("2. 검증 메서드 존재 확인")
    print("-" * 60)
    results['methods'] = test_validate_methods_exist()
    print()
    
    # 3. 예제 파일 검증
    print("3. 예제 파일 검증")
    print("-" * 60)
    
    example_files = [
        '2node_example.yaml',
        '2node_example_fixed.yaml',
        '4node_research_cluster.yaml'
    ]
    
    for filename in example_files:
        result = test_example_file_validation(filename)
        if result is not None:
            results[filename] = result
        print()
    
    # 결과 요약
    print("="*60)
    print("📊 테스트 결과 요약")
    print("="*60)
    
    passed = sum(1 for v in results.values() if v == True)
    failed = sum(1 for v in results.values() if v == False)
    skipped = sum(1 for v in results.values() if v is None)
    total = len(results)
    
    print(f"✅ 통과: {passed}/{total}")
    print(f"❌ 실패: {failed}/{total}")
    if skipped > 0:
        print(f"⚠️  건너뜀: {skipped}/{total}")
    print()
    
    if failed == 0:
        print("🎉 모든 테스트 통과!")
        print()
        print("✅ 기능이 모두 정상 동작합니다!")
        return 0
    else:
        print("❌ 일부 테스트 실패")
        print()
        print("실패한 테스트:")
        for name, result in results.items():
            if result == False:
                print(f"  - {name}")
        return 1

if __name__ == "__main__":
    sys.exit(test_all())
