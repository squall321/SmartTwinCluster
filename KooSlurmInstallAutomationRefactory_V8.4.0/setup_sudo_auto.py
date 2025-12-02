#!/usr/bin/env python3
"""
sudo 권한 자동 설정 스크립트
모든 노드의 사용자에게 sudo 권한 부여
"""

import sys
from pathlib import Path
import yaml

sys.path.insert(0, str(Path(__file__).parent))

from src.ssh_manager import SSHManager


def setup_sudo_for_all_nodes(config):
    """모든 노드에 sudo 권한 설정"""
    print("\n" + "=" * 70)
    print("🔐 sudo 권한 자동 설정")
    print("=" * 70)
    
    ssh_manager = SSHManager(config)
    all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
    
    ssh_user = config['nodes']['controller']['ssh_user']
    
    print(f"\n사용자: {ssh_user}")
    print(f"노드 수: {len(all_nodes)}")
    print("")
    
    for node in all_nodes:
        hostname = node['hostname']
        ip_address = node['ip_address']
        
        print(f"📌 {hostname} ({ip_address})")
        print(f"   처리 중...")
        
        # 방법 1: sudoers.d에 파일 추가 (권장)
        sudoers_content = f"{ssh_user} ALL=(ALL) NOPASSWD:ALL"
        
        commands = [
            # 1. wheel/sudo 그룹에 추가
            f"usermod -aG wheel {ssh_user} 2>/dev/null || usermod -aG sudo {ssh_user} 2>/dev/null || true",
            
            # 2. sudoers.d에 규칙 추가
            f"echo '{sudoers_content}' | tee /etc/sudoers.d/{ssh_user} > /dev/null",
            f"chmod 0440 /etc/sudoers.d/{ssh_user}",
            
            # 3. 검증
            f"visudo -c -f /etc/sudoers.d/{ssh_user}"
        ]
        
        all_success = True
        
        for cmd in commands:
            # root로 직접 실행 시도
            exit_code, stdout, stderr = ssh_manager.execute_command(
                hostname, 
                cmd,
                show_output=False
            )
            
            if "visudo" in cmd and exit_code == 0:
                print(f"   ✅ sudoers 파일 검증 성공")
        
        # sudo 테스트
        exit_code, stdout, stderr = ssh_manager.execute_command(
            hostname,
            f"sudo -n true",
            show_output=False
        )
        
        if exit_code == 0:
            print(f"   ✅ {hostname}: sudo 권한 설정 완료")
        else:
            print(f"   ⚠️  {hostname}: sudo 권한 테스트 실패")
            print(f"   💡 수동 설정이 필요할 수 있습니다")
            print(f"      ssh {hostname}")
            print(f"      su -  # root로 전환")
            print(f"      usermod -aG sudo {ssh_user}")
            print(f"      echo '{ssh_user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/{ssh_user}")
        
        print("")
    
    print("=" * 70)
    print("✅ sudo 권한 설정 완료!")
    print("=" * 70)
    print("\n💡 설정이 제대로 안 된 노드가 있다면:")
    print("   1. 해당 노드에 직접 로그인")
    print(f"      ssh {hostname}")
    print("   2. root 계정으로 전환")
    print("      su -")
    print("   3. 사용자를 sudo 그룹에 추가")
    print(f"      usermod -aG sudo {ssh_user}  # Ubuntu")
    print(f"      usermod -aG wheel {ssh_user}  # CentOS")
    print("   4. sudoers 파일 추가")
    print(f"      echo '{ssh_user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/{ssh_user}")
    print(f"      chmod 0440 /etc/sudoers.d/{ssh_user}")
    print("")


def main():
    """메인 함수"""
    print("🔐 sudo 권한 자동 설정 도구")
    
    config_file = Path("my_cluster.yaml")
    if not config_file.exists():
        print("❌ my_cluster.yaml 파일을 찾을 수 없습니다.")
        sys.exit(1)
    
    with open(config_file, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    setup_sudo_for_all_nodes(config)


if __name__ == '__main__':
    main()
