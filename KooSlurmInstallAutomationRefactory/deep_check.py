#!/usr/bin/env python3
"""
심층 문제점 검사 스크립트
숨겨진 문제가 없는지 확인
"""

import sys
from pathlib import Path

project_root = Path(__file__).parent
sys.path.insert(0, str(project_root / 'src'))

def check_import_chain():
    """모든 import 체인 확인"""
    print("="*60)
    print("1. Import 체인 확인")
    print("="*60)
    
    issues = []
    
    try:
        # config_parser import
        from config_parser import ConfigParser
        print("✅ config_parser.ConfigParser")
        
        # ConfigParser 인스턴스 생성 테스트
        parser = ConfigParser("dummy.yaml")
        
        # 모든 메서드 존재 확인
        required_methods = [
            '_validate_installation',
            '_validate_time_sync',
            '_validate_config_version',
            '_validate_cluster_info',
            '_validate_nodes',
            '_validate_network',
            '_validate_slurm_config',
            '_validate_partition_config',
            'get_node_list',
            'get_controller_node',
            'is_feature_enabled'
        ]
        
        for method in required_methods:
            if hasattr(parser, method):
                print(f"  ✅ {method}")
            else:
                print(f"  ❌ {method} - 누락!")
                issues.append(f"메서드 누락: {method}")
                
    except Exception as e:
        print(f"❌ Import 실패: {e}")
        issues.append(f"Import 오류: {e}")
    
    return issues

def check_config_files():
    """설정 파일들의 필수 섹션 확인"""
    print("\n" + "="*60)
    print("2. 설정 파일 필수 섹션 확인")
    print("="*60)
    
    issues = []
    
    files = [
        'examples/2node_example.yaml',
        'examples/2node_example_fixed.yaml',
        'examples/4node_research_cluster.yaml'
    ]
    
    required_sections = [
        'config_version',
        'cluster_info',
        'nodes',
        'network',
        'slurm_config',
        'users',
        'shared_storage'
    ]
    
    recommended_sections = [
        'installation',
        'time_synchronization'
    ]
    
    for filename in files:
        filepath = project_root / filename
        
        if not filepath.exists():
            print(f"\n⚠️  {filename} - 파일 없음")
            continue
            
        print(f"\n📄 {filename}")
        
        try:
            import yaml
            with open(filepath, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
            
            # 필수 섹션 확인
            for section in required_sections:
                if section in config:
                    print(f"  ✅ {section}")
                else:
                    print(f"  ❌ {section} - 누락!")
                    issues.append(f"{filename}: 필수 섹션 {section} 누락")
            
            # 권장 섹션 확인
            for section in recommended_sections:
                if section in config:
                    print(f"  ✅ {section} (권장)")
                else:
                    print(f"  ⚠️  {section} - 권장 섹션 누락")
                    
            # 특수 필드 확인
            if 'nodes' in config:
                # node_type 확인
                if 'controller' in config['nodes']:
                    if 'node_type' in config['nodes']['controller']:
                        print(f"  ✅ controller.node_type")
                    else:
                        print(f"  ⚠️  controller.node_type 미명시")
                        
            if 'users' in config:
                # munge_user 확인
                if 'munge_user' in config['users']:
                    print(f"  ✅ users.munge_user")
                else:
                    print(f"  ⚠️  users.munge_user 미명시")
                    
        except Exception as e:
            print(f"  ❌ 파싱 오류: {e}")
            issues.append(f"{filename}: 파싱 오류 - {e}")
    
    return issues

def check_validation_logic():
    """검증 로직 실제 동작 확인"""
    print("\n" + "="*60)
    print("3. 검증 로직 동작 확인")
    print("="*60)
    
    issues = []
    
    try:
        from config_parser import ConfigParser
        
        # 테스트 케이스 1: 완전한 설정
        print("\n테스트 1: 완전한 설정")
        test_config = {
            'config_version': '1.0',
            'cluster_info': {'cluster_name': 'test', 'domain': 'test.local', 'admin_email': 'test@test.com'},
            'installation': {'install_method': 'package', 'offline_mode': False},
            'time_synchronization': {'enabled': True, 'ntp_servers': ['time.google.com']},
            'nodes': {
                'controller': {'hostname': 'head', 'ip_address': '192.168.1.1', 'ssh_user': 'root', 
                              'os_type': 'centos8', 'node_type': 'controller', 'hardware': {'cpus': 8, 'memory_mb': 16384}},
                'compute_nodes': [{'hostname': 'compute01', 'ip_address': '192.168.1.2', 'ssh_user': 'root',
                                  'os_type': 'centos8', 'node_type': 'compute', 'hardware': {'cpus': 16, 'memory_mb': 32768}}]
            },
            'network': {'management_network': '192.168.1.0/24'},
            'slurm_config': {'version': '22.05', 'install_path': '/usr/local/slurm', 'config_path': '/etc/slurm',
                            'partitions': [{'name': 'main', 'nodes': 'compute01', 'default': True}]},
            'users': {'slurm_user': 'slurm', 'slurm_uid': 1001, 'slurm_gid': 1001, 
                     'munge_user': 'munge', 'munge_uid': 1002, 'munge_gid': 1002},
            'shared_storage': {'nfs_server': '192.168.1.1', 'mount_points': []}
        }
        
        # 임시 파일 생성
        import tempfile
        import yaml
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(test_config, f)
            temp_file = f.name
        
        try:
            parser = ConfigParser(temp_file)
            parser.config = test_config
            
            # 검증 실행
            result = parser.validate_config()
            
            if result:
                print("  ✅ 검증 통과")
                if len(parser.errors) > 0:
                    print(f"  ⚠️  예상치 못한 오류: {parser.errors}")
                    issues.append(f"완전한 설정에 오류: {parser.errors}")
                if len(parser.warnings) > 0:
                    print(f"  ℹ️  경고: {parser.warnings}")
            else:
                print(f"  ❌ 검증 실패")
                print(f"     오류: {parser.errors}")
                issues.append(f"완전한 설정 검증 실패: {parser.errors}")
        finally:
            import os
            os.unlink(temp_file)
        
        # 테스트 케이스 2: 잘못된 install_method
        print("\n테스트 2: 잘못된 install_method")
        test_config['installation']['install_method'] = 'invalid'
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(test_config, f)
            temp_file = f.name
        
        try:
            parser = ConfigParser(temp_file)
            parser.config = test_config
            result = parser.validate_config()
            
            if not result and any('install_method' in str(e) for e in parser.errors):
                print("  ✅ 올바르게 오류 감지")
            else:
                print("  ❌ 오류 감지 실패")
                issues.append("잘못된 install_method를 감지하지 못함")
        finally:
            os.unlink(temp_file)
        
        # 테스트 케이스 3: 누락된 섹션
        print("\n테스트 3: 권장 섹션 누락")
        test_config_minimal = {
            'config_version': '1.0',
            'cluster_info': {'cluster_name': 'test', 'domain': 'test.local', 'admin_email': 'test@test.com'},
            # installation 섹션 없음
            # time_synchronization 섹션 없음
            'nodes': {
                'controller': {'hostname': 'head', 'ip_address': '192.168.1.1', 'ssh_user': 'root',
                              'os_type': 'centos8', 'hardware': {'cpus': 8, 'memory_mb': 16384}},
                'compute_nodes': [{'hostname': 'compute01', 'ip_address': '192.168.1.2', 'ssh_user': 'root',
                                  'os_type': 'centos8', 'hardware': {'cpus': 16, 'memory_mb': 32768}}]
            },
            'network': {'management_network': '192.168.1.0/24'},
            'slurm_config': {'version': '22.05', 'install_path': '/usr/local/slurm', 'config_path': '/etc/slurm',
                            'partitions': [{'name': 'main', 'nodes': 'compute01', 'default': True}]},
            'users': {'slurm_user': 'slurm', 'slurm_uid': 1001, 'slurm_gid': 1001},
            'shared_storage': {'nfs_server': '192.168.1.1', 'mount_points': []}
        }
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(test_config_minimal, f)
            temp_file = f.name
        
        try:
            parser = ConfigParser(temp_file)
            parser.config = test_config_minimal
            result = parser.validate_config()
            
            if len(parser.warnings) >= 2:  # installation과 time_synchronization 경고
                print("  ✅ 경고 메시지 정상 출력")
            else:
                print(f"  ❌ 경고 부족: {len(parser.warnings)}개")
                issues.append(f"권장 섹션 누락 경고 부족: {parser.warnings}")
        finally:
            os.unlink(temp_file)
            
    except Exception as e:
        print(f"❌ 검증 로직 테스트 실패: {e}")
        import traceback
        traceback.print_exc()
        issues.append(f"검증 로직 테스트 오류: {e}")
    
    return issues

def check_scripts():
    """스크립트 파일들 확인"""
    print("\n" + "="*60)
    print("4. 스크립트 파일 확인")
    print("="*60)
    
    issues = []
    
    scripts = [
        ('update_configs.sh', '자동 업데이트 스크립트'),
        ('verify_fixes.sh', '검증 스크립트'),
        ('test_functionality.py', '기능 테스트'),
        ('install_slurm.py', '설치 스크립트'),
        ('validate_config.py', '설정 검증'),
    ]
    
    for script, desc in scripts:
        filepath = project_root / script
        
        if filepath.exists():
            print(f"✅ {script} - {desc}")
            
            # 실행 권한 확인
            import os
            if os.access(filepath, os.X_OK):
                print(f"   ✅ 실행 권한 있음")
            else:
                print(f"   ⚠️  실행 권한 없음 (chmod +x 필요)")
        else:
            print(f"❌ {script} - 파일 없음")
            issues.append(f"스크립트 파일 누락: {script}")
    
    return issues

def main():
    """메인 검사 함수"""
    print("\n")
    print("="*60)
    print("🔍 심층 문제점 검사")
    print("="*60)
    print()
    
    all_issues = []
    
    # 1. Import 체인 확인
    issues = check_import_chain()
    all_issues.extend(issues)
    
    # 2. 설정 파일 확인
    issues = check_config_files()
    all_issues.extend(issues)
    
    # 3. 검증 로직 확인
    issues = check_validation_logic()
    all_issues.extend(issues)
    
    # 4. 스크립트 확인
    issues = check_scripts()
    all_issues.extend(issues)
    
    # 최종 결과
    print("\n")
    print("="*60)
    print("📊 최종 검사 결과")
    print("="*60)
    
    if len(all_issues) == 0:
        print()
        print("🎉 문제 없음! 모든 기능이 정상입니다!")
        print()
        print("✅ 코드: 정상")
        print("✅ 설정 파일: 정상")
        print("✅ 검증 로직: 정상")
        print("✅ 스크립트: 정상")
        print()
        print("프로덕션 배포 가능 상태입니다! 🚀")
        return 0
    else:
        print()
        print(f"⚠️  발견된 문제: {len(all_issues)}개")
        print()
        for i, issue in enumerate(all_issues, 1):
            print(f"{i}. {issue}")
        print()
        print("위 문제들을 해결한 후 다시 검사해주세요.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
