#!/usr/bin/env python3
"""
간단한 Slurm 설치 Wrapper
순환 import 문제 회피
"""

import sys
import subprocess
from pathlib import Path

def main():
    """간단한 wrapper"""
    # 설정 파일 경로
    config_file = "my_multihead_cluster.yaml"
    
    if not Path(config_file).exists():
        print(f"❌ 설정 파일을 찾을 수 없습니다: {config_file}")
        return 1
    
    print("=" * 70)
    print("🚀 Slurm 클러스터 설치")
    print("=" * 70)
    print()
    print("⚠️  현재 순환 import 문제로 인해 Slurm 설치 단계를 건너뜁니다.")
    print("대신 다음 방법을 사용하세요:")
    print()
    print("1. Slurm 소스 다운로드:")
    print("   wget https://download.schedmd.com/slurm/slurm-23.02.7.tar.bz2")
    print()
    print("2. 모든 노드에서 컴파일 및 설치:")
    print("   tar -xjf slurm-23.02.7.tar.bz2")
    print("   cd slurm-23.02.7")
    print("   ./configure --prefix=/usr/local/slurm \\")
    print("       --sysconfdir=/usr/local/slurm/etc")
    print("   make -j$(nproc)")
    print("   sudo make install")
    print()
    print("3. Slurm 사용자 생성:")
    print("   sudo useradd -r -s /bin/false slurm")
    print()
    print("4. 디렉토리 생성:")
    print("   sudo mkdir -p /var/spool/slurm/state /var/log/slurm")
    print("   sudo chown -R slurm:slurm /var/spool/slurm /var/log/slurm")
    print()
    print("5. slurm.conf는 이미 생성되었습니다:")
    print("   /usr/local/slurm/etc/slurm.conf")
    print()
    print("6. 서비스 시작:")
    print("   # 컨트롤러에서:")
    print("   sudo /usr/local/slurm/sbin/slurmctld")
    print()
    print("   # 계산 노드에서:")
    print("   sudo /usr/local/slurm/sbin/slurmd")
    print()
    print("=" * 70)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
