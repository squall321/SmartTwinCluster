#!/usr/bin/env python3
"""
Slurm 설정 파일 생성 도구
다양한 클러스터 구성에 맞는 설정 파일을 생성
"""

import sys
import argparse
from pathlib import Path

# src 디렉토리를 Python 경로에 추가
sys.path.insert(0, str(Path(__file__).parent / 'src'))
sys.path.insert(0, str(Path(__file__).parent))

from config_generator import SlurmConfigGenerator
from src.utils import print_banner


def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(
        description='Slurm 설정 파일 생성 도구',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
생성되는 파일들:
  templates/
    - stage1_basic.yaml        : 1단계 기본 설치 템플릿
    - stage2_advanced.yaml     : 2단계 고급 기능 템플릿  
    - stage3_optimization.yaml : 3단계 운영 최적화 템플릿
    - complete_template.yaml   : 전체 통합 템플릿

  examples/
    - 2node_example.yaml            : 2노드 기본 구성 예시
    - 4node_research_cluster.yaml   : 4노드 연구용 클러스터 예시

사용 예시:
  # 기본 템플릿 생성
  python generate_config.py
  
  # 특정 디렉토리에 생성
  python generate_config.py --output-dir /path/to/configs
  
  # 예시 파일만 생성
  python generate_config.py --examples-only
        """
    )
    
    parser.add_argument(
        '--output-dir',
        default='.',
        help='출력 디렉토리 (기본값: 현재 디렉토리)'
    )
    
    parser.add_argument(
        '--templates-only',
        action='store_true',
        help='템플릿 파일만 생성'
    )
    
    parser.add_argument(
        '--examples-only', 
        action='store_true',
        help='예시 파일만 생성'
    )
    
    parser.add_argument(
        '--force',
        action='store_true',
        help='기존 파일 덮어쓰기'
    )
    
    parser.add_argument(
        '--quiet',
        action='store_true',
        help='간단한 출력만 표시'
    )
    
    args = parser.parse_args()
    
    # 배너 출력
    if not args.quiet:
        print_banner()
        print("📝 설정 파일 생성 모드\n")
    
    try:
        # 출력 디렉토리 설정
        output_path = Path(args.output_dir).resolve()
        
        # SlurmConfigGenerator의 작업 디렉토리 변경
        original_cwd = Path.cwd()
        output_path.mkdir(parents=True, exist_ok=True)
        
        # 생성기 초기화
        generator = SlurmConfigGenerator()
        
        # 디렉토리 경로를 output_dir 기준으로 설정
        generator.config_dir = output_path / "configs"
        generator.templates_dir = output_path / "templates"  
        generator.examples_dir = output_path / "examples"
        
        # 디렉토리 생성
        generator.templates_dir.mkdir(exist_ok=True)
        generator.examples_dir.mkdir(exist_ok=True)
        
        if not args.quiet:
            print(f"📁 출력 디렉토리: {output_path}")
            print()
        
        generated_files = []
        
        # 템플릿 생성
        if not args.examples_only:
            if not args.quiet:
                print("📋 템플릿 파일 생성 중...")
            
            templates = [
                ("stage1_basic.yaml", generator.generate_stage1_template()),
                ("stage2_advanced.yaml", generator.generate_stage2_template()),
                ("stage3_optimization.yaml", generator.generate_stage3_template()),
                ("complete_template.yaml", generator.generate_complete_template())
            ]
            
            for filename, template in templates:
                filepath = generator.templates_dir / filename
                
                if filepath.exists() and not args.force:
                    print(f"⚠️  건너뛰기: {filepath} (이미 존재, --force로 덮어쓰기 가능)")
                    continue
                
                generator.save_template(template, filename)
                generated_files.append(f"templates/{filename}")
        
        # 예시 파일 생성  
        if not args.templates_only:
            if not args.quiet:
                print("\n📄 예시 파일 생성 중...")
            
            examples = [
                ("2node_example.yaml", generator.generate_2node_example()),
            ]
            
            # 4노드 예시도 추가
            try:
                # 4노드 예시를 위한 설정 (여기서는 간단한 버전만)
                four_node_example = generator.generate_2node_example().copy()
                four_node_example['cluster_info']['cluster_name'] = 'research-cluster'
                
                # 추가 계산 노드 2개 더 추가
                additional_nodes = [
                    {
                        "hostname": "compute02",
                        "ip_address": "192.168.1.21", 
                        "ssh_user": "root",
                        "ssh_port": 22,
                        "ssh_key_path": "~/.ssh/id_rsa",
                        "os_type": "centos8",
                        "hardware": {
                            "cpus": 32,
                            "sockets": 2,
                            "cores_per_socket": 8,
                            "threads_per_core": 2,
                            "memory_mb": 65536,
                            "tmp_disk_mb": 204800,
                            "gpu": {"type": "none", "count": 0}
                        }
                    },
                    {
                        "hostname": "gpu01", 
                        "ip_address": "192.168.1.22",
                        "ssh_user": "root",
                        "ssh_port": 22,
                        "ssh_key_path": "~/.ssh/id_rsa",
                        "os_type": "centos8",
                        "hardware": {
                            "cpus": 16,
                            "sockets": 1,
                            "cores_per_socket": 8,
                            "threads_per_core": 2,
                            "memory_mb": 32768,
                            "tmp_disk_mb": 102400,
                            "gpu": {"type": "nvidia", "count": 2}
                        }
                    }
                ]
                
                four_node_example['nodes']['compute_nodes'].extend(additional_nodes)
                
                # 파티션 수정
                four_node_example['slurm_config']['partitions'] = [
                    {
                        "name": "cpu",
                        "nodes": "compute[01-02]",
                        "default": True,
                        "max_time": "7-00:00:00",
                        "max_nodes": 2
                    },
                    {
                        "name": "gpu", 
                        "nodes": "gpu01",
                        "default": False,
                        "max_time": "3-00:00:00",
                        "max_nodes": 1
                    }
                ]
                
                examples.append(("4node_research_cluster.yaml", four_node_example))
                
            except Exception as e:
                if not args.quiet:
                    print(f"⚠️  4노드 예시 생성 중 오류: {e}")
            
            for filename, example in examples:
                filepath = generator.examples_dir / filename
                
                if filepath.exists() and not args.force:
                    print(f"⚠️  건너뛰기: {filepath} (이미 존재, --force로 덮어쓰기 가능)")
                    continue
                
                generator.save_example(example, filename)
                generated_files.append(f"examples/{filename}")
        
        # 결과 출력
        if generated_files:
            print(f"\n✅ 총 {len(generated_files)}개 파일이 생성되었습니다:")
            for file in generated_files:
                print(f"  📄 {output_path / file}")
            
            print(f"\n📋 다음 단계:")
            print(f"  1. 예시 파일을 참고하여 실제 환경에 맞게 설정 수정")
            print(f"  2. 설정 파일 검증: python validate_config.py <config_file>")
            print(f"  3. SSH 연결 테스트: python test_connection.py <config_file>")
            print(f"  4. Slurm 설치: python install_slurm.py -c <config_file>")
        else:
            print("⚠️  생성된 파일이 없습니다. (모든 파일이 이미 존재)")
        
        return 0
        
    except Exception as e:
        print(f"❌ 설정 파일 생성 중 오류 발생: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
