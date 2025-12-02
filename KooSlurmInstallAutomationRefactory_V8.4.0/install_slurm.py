#!/usr/bin/env python3
"""
Slurm 클러스터 완전 자동 설치
Slurm 바이너리 컴파일 및 설치 포함
"""

import sys
import subprocess
from pathlib import Path
import yaml

def run_command(cmd, description=""):
    """명령어 실행"""
    if description:
        print(f"  {description}")
    
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.returncode == 0

def main():
    print("=" * 80)
    print("🚀 Slurm 완전 자동 설치")
    print("=" * 80)
    print()
    
    # 설정 파일 로드
    config_file = Path("my_cluster.yaml")
    if not config_file.exists():
        print("❌ my_cluster.yaml 파일을 찾을 수 없습니다.")
        return 1
    
    with open(config_file, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    print("📋 설정 정보:")
    print(f"  클러스터: {config['cluster_info']['cluster_name']}")
    print(f"  컨트롤러: {config['nodes']['controller']['hostname']}")
    print(f"  계산 노드: {len(config['nodes']['compute_nodes'])}개")
    print()
    
    # install_slurm_binary.sh 실행
    script_path = Path(__file__).parent / "install_slurm_binary.sh"
    
    if not script_path.exists():
        print("❌ install_slurm_binary.sh를 찾을 수 없습니다.")
        print()
        print("💡 수동 설치 가이드:")
        print("   cat SLURM_INSTALL_GUIDE.md")
        return 1
    
    print("🔧 Slurm 바이너리 설치 스크립트 실행 중...")
    print("   (시간이 걸릴 수 있습니다 - 약 10-15분)")
    print()
    
    # 실행 권한 부여
    subprocess.run(["chmod", "+x", str(script_path)])
    
    # 스크립트 실행
    result = subprocess.run([str(script_path)])
    
    if result.returncode != 0:
        print()
        print("⚠️  자동 설치 실패")
        print()
        print("💡 문제 해결:")
        print("   1. 필수 패키지 확인:")
        print("      sudo apt-get install build-essential libmunge-dev libpam0g-dev")
        print("   2. 수동 설치 가이드:")
        print("      cat SLURM_INSTALL_GUIDE.md")
        print("   3. 직접 스크립트 실행:")
        print("      ./install_slurm_binary.sh")
        return 1
    
    print()
    print("=" * 80)
    print("✅ Slurm 설치 완료!")
    print("=" * 80)
    print()
    print("🚦 다음 단계:")
    print()
    print("1. 서비스 시작:")
    print("   sudo systemctl start slurmctld")
    print("   ssh 192.168.122.90 'sudo systemctl start slurmd'")
    print("   ssh 192.168.122.103 'sudo systemctl start slurmd'")
    print()
    print("2. 상태 확인:")
    print("   /usr/local/slurm/bin/sinfo")
    print("   /usr/local/slurm/bin/sinfo -N")
    print()
    print("3. 노드 활성화 (필요시):")
    print("   /usr/local/slurm/bin/scontrol update NodeName=node001 State=RESUME")
    print("   /usr/local/slurm/bin/scontrol update NodeName=node002 State=RESUME")
    print()
    print("4. 테스트 Job 제출:")
    print("   cat > test_job.sh <<'EOF'")
    print("   #!/bin/bash")
    print("   #SBATCH --job-name=test")
    print("   #SBATCH --output=test_%j.out")
    print("   #SBATCH --nodes=1")
    print("   #SBATCH --ntasks=1")
    print("   echo 'Hello from' $(hostname)")
    print("   EOF")
    print()
    print("   /usr/local/slurm/bin/sbatch test_job.sh")
    print("   /usr/local/slurm/bin/squeue")
    print()
    print("📚 가이드: cat SLURM_INSTALL_GUIDE.md")
    print("=" * 80)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
