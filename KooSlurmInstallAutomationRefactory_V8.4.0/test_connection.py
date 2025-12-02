#!/usr/bin/env python3
"""
SSH 연결 테스트 도구
설정 파일의 모든 노드에 대한 SSH 연결을 테스트
"""

import sys
import argparse
from pathlib import Path

# src 디렉토리를 Python 경로에 추가
sys.path.insert(0, str(Path(__file__).parent / 'src'))

from config_parser import ConfigParser
from ssh_manager import SSHManager
from utils import print_banner


def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(
        description='SSH 연결 테스트 도구',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        'config_file',
        help='설정 파일 경로 (YAML)'
    )
    
    parser.add_argument(
        '--max-workers',
        type=int,
        default=10,
        help='병렬 연결 테스트 최대 수 (기본값: 10)'
    )
    
    parser.add_argument(
        '--timeout',
        type=int,
        default=30,
        help='연결 타임아웃 (초, 기본값: 30)'
    )
    
    parser.add_argument(
        '--quiet',
        action='store_true',
        help='간단한 결과만 출력'
    )
    
    args = parser.parse_args()
    
    # 배너 출력
    if not args.quiet:
        print_banner()
        print("🔌 SSH 연결 테스트 모드\n")
    
    # 설정 파일 존재 확인
    config_path = Path(args.config_file)
    if not config_path.exists():
        print(f"❌ 설정 파일을 찾을 수 없습니다: {args.config_file}")
        return 1
    
    try:
        # 설정 파일 로드
        config_parser = ConfigParser(args.config_file)
        config = config_parser.load_config()
        
        if not config_parser.validate_config():
            print("❌ 설정 파일이 유효하지 않습니다.")
            return 1
        
        # SSH 관리자 설정
        ssh_manager = SSHManager()
        
        # 노드들 추가
        all_nodes = config_parser.get_node_list()
        
        if not args.quiet:
            print(f"📋 총 {len(all_nodes)}개 노드에 대한 연결 테스트를 시작합니다...\n")
        
        for node in all_nodes:
            ssh_manager.add_node(node)
        
        # 연결 테스트 실행
        connection_results = ssh_manager.connect_all_nodes(max_workers=args.max_workers)
        
        # 상세 연결성 테스트
        connectivity_results = ssh_manager.test_all_nodes_connectivity(max_workers=args.max_workers)
        
        # 결과 분석
        total_nodes = len(all_nodes)
        successful_connections = sum(1 for success in connection_results.values() if success)
        
        ping_success = sum(1 for result in connectivity_results.values() if result['ping'])
        ssh_success = sum(1 for result in connectivity_results.values() if result['ssh'])
        sudo_success = sum(1 for result in connectivity_results.values() if result['sudo'])
        
        # 간단한 요약 (quiet 모드)
        if args.quiet:
            print(f"연결 테스트 결과: {ssh_success}/{total_nodes}")
            if ssh_success == total_nodes:
                return 0
            else:
                failed_nodes = [hostname for hostname, success in connection_results.items() if not success]
                print(f"실패 노드: {', '.join(failed_nodes)}")
                return 1
        
        # 개별 노드 테스트 명령 실행
        print("\n🧪 기본 명령어 테스트 중...")
        
        test_commands = [
            ("whoami", "사용자 확인"),
            ("uname -n", "호스트네임 확인"),
            ("date", "시간 확인"),
            ("df -h /", "디스크 공간 확인")
        ]
        
        for cmd, description in test_commands:
            print(f"\n📊 {description} ({cmd}):")
            results = ssh_manager.execute_on_all_nodes(cmd, timeout=10, max_workers=args.max_workers)
            
            for hostname, (exit_code, stdout, stderr) in results.items():
                if exit_code == 0:
                    output = stdout.strip()[:50] + ("..." if len(stdout.strip()) > 50 else "")
                    print(f"  ✅ {hostname}: {output}")
                else:
                    error = stderr.strip()[:50] + ("..." if len(stderr.strip()) > 50 else "")
                    print(f"  ❌ {hostname}: {error}")
        
        # 최종 결과
        print(f"\n📊 최종 테스트 결과:")
        print(f"  총 노드 수: {total_nodes}")
        print(f"  Ping 성공: {ping_success}/{total_nodes}")
        print(f"  SSH 연결 성공: {ssh_success}/{total_nodes}")
        print(f"  sudo 권한 확인: {sudo_success}/{total_nodes}")
        
        # 권장사항
        if ssh_success == total_nodes and sudo_success == total_nodes:
            print("\n🎉 모든 노드가 설치 준비 완료!")
            print("install_slurm.py를 실행하여 Slurm 설치를 진행할 수 있습니다.")
        else:
            print("\n⚠️  일부 노드에서 문제 발견:")
            
            if ssh_success < total_nodes:
                failed_ssh = [h for h, r in connectivity_results.items() if not r['ssh']]
                print(f"  SSH 연결 실패: {', '.join(failed_ssh)}")
                print("  해결방법: SSH 키 설정, 방화벽 확인")
            
            if sudo_success < total_nodes:
                failed_sudo = [h for h, r in connectivity_results.items() if not r['sudo']]
                print(f"  sudo 권한 없음: {', '.join(failed_sudo)}")
                print("  해결방법: 사용자를 sudo/wheel 그룹에 추가")
            
            print("\n문제를 해결한 후 다시 테스트해주세요.")
        
        # 연결 종료
        ssh_manager.disconnect_all()
        
        return 0 if ssh_success == total_nodes and sudo_success == total_nodes else 1
        
    except Exception as e:
        print(f"❌ 테스트 중 오류 발생: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
