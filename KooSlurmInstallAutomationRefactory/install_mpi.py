#!/usr/bin/env python3
"""
MPI 라이브러리 자동 설치 모듈
모든 노드에 OpenMPI 또는 MPICH를 자동으로 설치합니다.
"""

import sys
from typing import Dict, Any, TYPE_CHECKING
from pathlib import Path

# src 디렉토리 경로 추가
src_path = Path(__file__).parent / 'src'
sys.path.insert(0, str(src_path))

# 개별 import로 순환 참조 방지
import ssh_manager

if TYPE_CHECKING:
    from ssh_manager import SSHManager


class MPIInstaller:
    """MPI 라이브러리 설치 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_mgr):
        self.config = config
        self.ssh_manager = ssh_mgr
        self.mpi_config = config.get('mpi_support', {})
        self.all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
    
    def install_mpi(self) -> bool:
        """모든 노드에 MPI 설치"""
        if not self.mpi_config.get('enabled', False):
            print("ℹ️  MPI 지원이 비활성화되어 있습니다.")
            return True
        
        print("\n🚀 MPI 라이브러리 설치 시작...")
        
        mpi_type = self.mpi_config.get('mpi_type', 'openmpi')
        
        if mpi_type == 'openmpi':
            return self._install_openmpi()
        elif mpi_type == 'mpich':
            return self._install_mpich()
        else:
            print(f"❌ 지원하지 않는 MPI 타입: {mpi_type}")
            return False
    
    def _install_openmpi(self) -> bool:
        """OpenMPI 설치"""
        print("📦 OpenMPI 설치 중...")
        
        for node in self.all_nodes:
            hostname = node['hostname']
            os_type = node.get('os_type', 'ubuntu22')
            
            print(f"  🔧 {hostname}: OpenMPI 설치 중...")
            
            if 'ubuntu' in os_type or 'debian' in os_type:
                install_cmd = """
                sudo apt update
                sudo apt install -y openmpi-bin openmpi-common libopenmpi-dev \
                    libopenmpi3 openmpi-doc
                """
            elif 'centos' in os_type or 'rhel' in os_type or 'rocky' in os_type:
                install_cmd = """
                sudo yum install -y openmpi openmpi-devel environment-modules
                """
            else:
                print(f"  ⚠️  {hostname}: 지원하지 않는 OS 타입 - {os_type}")
                continue
            
            exit_code, stdout, stderr = self.ssh_manager.execute_command(
                hostname, install_cmd, show_output=False, timeout=600
            )
            
            if exit_code != 0:
                print(f"  ⚠️  {hostname}: OpenMPI 설치 중 경고 발생")
                if stderr:
                    print(f"     {stderr[:200]}")
            
            # 환경변수 설정
            env_setup = """
sudo bash -c 'cat > /etc/profile.d/openmpi.sh << "EOF"
# OpenMPI Environment
export PATH=/usr/lib64/openmpi/bin:/usr/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH
export MPI_ROOT=/usr/lib64/openmpi
export MANPATH=/usr/share/man/openmpi:$MANPATH
EOF'
sudo chmod 644 /etc/profile.d/openmpi.sh
"""
            self.ssh_manager.execute_command(hostname, env_setup, show_output=False)
            
            # 설치 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "mpirun --version", show_output=False
            )
            
            if exit_code == 0:
                version = stdout.strip().split('\n')[0] if stdout else "알 수 없음"
                print(f"  ✅ {hostname}: OpenMPI 설치 완료 - {version}")
            else:
                print(f"  ⚠️  {hostname}: OpenMPI 설치 검증 실패")
        
        print("\n✅ 모든 노드에 OpenMPI 설치 완료!")
        return True
    
    def _install_mpich(self) -> bool:
        """MPICH 설치"""
        print("📦 MPICH 설치 중...")
        
        for node in self.all_nodes:
            hostname = node['hostname']
            os_type = node.get('os_type', 'ubuntu22')
            
            print(f"  🔧 {hostname}: MPICH 설치 중...")
            
            if 'ubuntu' in os_type or 'debian' in os_type:
                install_cmd = """
                sudo apt update
                sudo apt install -y mpich libmpich-dev
                """
            elif 'centos' in os_type or 'rhel' in os_type:
                install_cmd = """
                sudo yum install -y mpich mpich-devel
                """
            else:
                print(f"  ⚠️  {hostname}: 지원하지 않는 OS 타입 - {os_type}")
                continue
            
            exit_code, stdout, stderr = self.ssh_manager.execute_command(
                hostname, install_cmd, show_output=False, timeout=600
            )
            
            if exit_code != 0:
                print(f"  ⚠️  {hostname}: MPICH 설치 중 경고 발생")
            
            # 환경변수 설정
            env_setup = """
sudo bash -c 'cat > /etc/profile.d/mpich.sh << "EOF"
# MPICH Environment
export PATH=/usr/lib64/mpich/bin:/usr/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib64/mpich/lib:$LD_LIBRARY_PATH
EOF'
sudo chmod 644 /etc/profile.d/mpich.sh
"""
            self.ssh_manager.execute_command(hostname, env_setup, show_output=False)
            
            print(f"  ✅ {hostname}: MPICH 설치 완료")
        
        print("\n✅ 모든 노드에 MPICH 설치 완료!")
        return True
    
    def verify_mpi_installation(self) -> bool:
        """MPI 설치 검증"""
        print("\n🧪 MPI 설치 검증 중...")
        
        all_success = True
        for node in self.all_nodes:
            hostname = node['hostname']
            
            # mpirun 명령어 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "which mpirun", show_output=False
            )
            
            if exit_code == 0 and stdout:
                print(f"  ✅ {hostname}: mpirun 경로 - {stdout.strip()}")
            else:
                print(f"  ❌ {hostname}: mpirun을 찾을 수 없습니다")
                all_success = False
            
            # MPI 버전 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "mpirun --version", show_output=False
            )
            
            if exit_code == 0 and stdout:
                version = stdout.strip().split('\n')[0]
                print(f"  ℹ️  {hostname}: {version}")
        
        if all_success:
            print("\n✅ MPI 설치 검증 완료!")
        else:
            print("\n⚠️  일부 노드에서 MPI 검증 실패")
        
        return all_success


def main():
    """메인 함수"""
    import yaml
    
    print("=" * 70)
    print("🚀 MPI 라이브러리 자동 설치")
    print("=" * 70)
    
    # 설정 파일 로드
    config_file = Path("my_cluster.yaml")
    if not config_file.exists():
        print("❌ my_cluster.yaml 파일을 찾을 수 없습니다.")
        sys.exit(1)
    
    with open(config_file, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    # SSH 매니저 초기화
    ssh_mgr = ssh_manager.SSHManager()
    
    # 모든 노드 추가
    all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
    for node in all_nodes:
        ssh_mgr.add_node(node)
    
    # 연결
    ssh_mgr.connect_all_nodes()
    
    # MPI 설치
    installer = MPIInstaller(config, ssh_mgr)
    
    if installer.install_mpi():
        installer.verify_mpi_installation()
        print("\n🎉 MPI 설치가 성공적으로 완료되었습니다!")
    else:
        print("\n❌ MPI 설치 실패")
        sys.exit(1)
    
    # 연결 종료
    ssh_mgr.disconnect_all()


if __name__ == '__main__':
    main()
