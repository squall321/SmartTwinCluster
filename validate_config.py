#!/usr/bin/env python3
"""
Slurm 설정 파일 검증 도구
설정 파일의 유효성을 검증하고 요약 정보를 출력
"""

import sys
import argparse
from pathlib import Path

# src 디렉토리를 Python 경로에 추가
sys.path.insert(0, str(Path(__file__).parent / 'src'))

from config_parser import ConfigParser
from utils import print_banner


def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(
        description='Slurm 설정 파일 검증 도구',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        'config_file',
        help='검증할 설정 파일 경로 (YAML)'
    )
    
    parser.add_argument(
        '--detailed',
        action='store_true',
        help='상세한 검증 결과 출력'
    )
    
    parser.add_argument(
        '--quiet',
        action='store_true',
        help='요약 정보만 출력 (배너 생략)'
    )
    
    args = parser.parse_args()
    
    # 배너 출력
    if not args.quiet:
        print_banner()
        print("🔍 설정 파일 검증 모드\n")
    
    # 설정 파일 존재 확인
    config_path = Path(args.config_file)
    if not config_path.exists():
        print(f"❌ 설정 파일을 찾을 수 없습니다: {args.config_file}")
        return 1
    
    try:
        # 설정 파일 로드 및 검증
        config_parser = ConfigParser(args.config_file)
        config = config_parser.load_config()
        
        if config_parser.validate_config():
            print("✅ 설정 파일 검증 성공!")
            
            if not args.quiet:
                config_parser.print_config_summary()
            
            # 상세 정보 출력
            if args.detailed:
                print("\n📋 상세 검증 결과:")
                print("-" * 50)
                
                # 노드별 상세 정보
                print("\n🖥️  노드 상세 정보:")
                all_nodes = config_parser.get_node_list()
                
                for node in all_nodes:
                    print(f"\n  {node['hostname']} ({node['node_type']}):")
                    print(f"    IP: {node['ip_address']}")
                    print(f"    OS: {node.get('os_type', 'N/A')}")
                    print(f"    SSH User: {node.get('ssh_user', 'N/A')}")
                    
                    hardware = node.get('hardware', {})
                    print(f"    CPU: {hardware.get('cpus', 'N/A')}")
                    print(f"    Memory: {hardware.get('memory_mb', 'N/A')} MB")
                    
                    gpu = hardware.get('gpu', {})
                    if gpu.get('type') != 'none' and gpu.get('count', 0) > 0:
                        print(f"    GPU: {gpu.get('type')} x{gpu.get('count')}")
                
                # 파티션 상세 정보
                print("\n📊 파티션 상세 정보:")
                partitions = config.get('slurm_config', {}).get('partitions', [])
                
                for partition in partitions:
                    print(f"\n  {partition['name']}:")
                    print(f"    노드: {partition['nodes']}")
                    print(f"    최대 시간: {partition.get('max_time', 'UNLIMITED')}")
                    print(f"    기본 파티션: {'예' if partition.get('default') else '아니오'}")
                
                # 활성화된 기능들
                print("\n🔧 활성화된 고급 기능:")
                features = [
                    ('database.enabled', '데이터베이스'),
                    ('monitoring.prometheus.enabled', 'Prometheus'),
                    ('monitoring.grafana.enabled', 'Grafana'),
                    ('monitoring.ganglia.enabled', 'Ganglia'),
                    ('environment_modules.enabled', 'Environment Modules'),
                    ('container_support.singularity.enabled', 'Singularity'),
                    ('power_management.enabled', '전력 관리'),
                ]
                
                enabled_features = []
                for feature_path, display_name in features:
                    if config_parser.is_feature_enabled(feature_path):
                        enabled_features.append(display_name)
                
                if enabled_features:
                    for feature in enabled_features:
                        print(f"  ✅ {feature}")
                else:
                    print("  없음 (기본 설치만)")
            
            return 0
            
        else:
            print("❌ 설정 파일 검증 실패!")
            print("위의 오류들을 수정한 후 다시 시도해주세요.")
            return 1
    
    except Exception as e:
        print(f"❌ 설정 파일 처리 중 오류 발생: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
