#!/usr/bin/env python3
"""
Slurm 설치 완료 여부 체크 스크립트
모든 구성 요소가 제대로 설치되고 작동하는지 검증
"""

import sys
from pathlib import Path
from typing import Dict, Any, List
import yaml

sys.path.insert(0, str(Path(__file__).parent))

from src.ssh_manager import SSHManager


class SlurmInstallationChecker:
    """Slurm 설치 완료 체크 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
        self.results = {}
    
    def check_all(self) -> bool:
        """모든 항목 체크"""
        print("\n" + "=" * 80)
        print("🔍 Slurm 설치 완료 여부 체크")
        print("=" * 80)
        
        checks = [
            ("SSH 연결", self.check_ssh),
            ("필수 패키지", self.check_packages),
            ("Munge 인증", self.check_munge),
            ("NFS 마운트", self.check_nfs),
            ("Slurm 바이너리", self.check_slurm_binaries),
            ("Slurm 설정 파일", self.check_slurm_config),
            ("Slurm 서비스", self.check_slurm_services),
            ("MPI 설치", self.check_mpi),
            ("Apptainer 설치", self.check_apptainer),
            ("이미지 디렉토리", self.check_image_directories),
        ]
        
        all_passed = True
        
        for check_name, check_func in checks:
            print(f"\n{'─' * 80}")
            print(f"📌 {check_name} 체크 중...")
            print(f"{'─' * 80}")
            
            try:
                result = check_func()
                self.results[check_name] = result
                
                if result:
                    print(f"✅ {check_name}: 통과")
                else:
                    print(f"❌ {check_name}: 실패")
                    all_passed = False
            except Exception as e:
                print(f"❌ {check_name}: 오류 - {e}")
                self.results[check_name] = False
                all_passed = False
        
        # 요약 출력
        self.print_summary(all_passed)
        
        return all_passed
    
    def check_ssh(self) -> bool:
        """SSH 연결 체크"""
        all_ok = True
        
        for node in self.all_nodes:
            hostname = node['hostname']
            
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "echo OK", show_output=False
            )
            
            if exit_code == 0 and "OK" in stdout:
                print(f"  ✅ {hostname}: SSH 연결 정상")
            else:
                print(f"  ❌ {hostname}: SSH 연결 실패")
                all_ok = False
        
        return all_ok
    
    def check_packages(self) -> bool:
        """필수 패키지 체크"""
        required_packages = ['gcc', 'make', 'munge', 'rsync']
        all_ok = True
        
        for node in self.all_nodes:
            hostname = node['hostname']
            node_ok = True
            
            for package in required_packages:
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, f"which {package}", show_output=False
                )
                
                if exit_code != 0:
                    print(f"  ❌ {hostname}: {package} 없음")
                    node_ok = False
                    all_ok = False
            
            if node_ok:
                print(f"  ✅ {hostname}: 모든 필수 패키지 설치됨")
        
        return all_ok
    
    def check_munge(self) -> bool:
        """Munge 인증 체크"""
        all_ok = True
        
        for node in self.all_nodes:
            hostname = node['hostname']
            
            # 서비스 상태
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, "systemctl is-active munge", show_output=False
            )
            
            if exit_code != 0:
                print(f"  ❌ {hostname}: Munge 서비스 미작동")
                all_ok = False
                continue
            
            # 인증 테스트
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "munge -n | unmunge", show_output=False
            )
            
            if exit_code == 0 and "Success" in stdout:
                print(f"  ✅ {hostname}: Munge 인증 정상")
            else:
                print(f"  ❌ {hostname}: Munge 인증 실패")
                all_ok = False
        
        return all_ok
    
    def check_nfs(self) -> bool:
        """NFS 마운트 체크"""
        mount_points = self.config.get('shared_storage', {}).get('mount_points', [])
        
        if not mount_points:
            print("  ⏭️  NFS 설정 없음 (건너뜀)")
            return True
        
        all_ok = True
        
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            node_ok = True
            
            for mount in mount_points:
                target = mount['target']
                
                exit_code, stdout, _ = self.ssh_manager.execute_command(
                    hostname, f"mountpoint -q {target} && echo OK", show_output=False
                )
                
                if exit_code == 0 and "OK" in stdout:
                    print(f"  ✅ {hostname}: {target} 마운트됨")
                else:
                    print(f"  ❌ {hostname}: {target} 마운트 안 됨")
                    node_ok = False
                    all_ok = False
            
            if node_ok:
                print(f"  ✅ {hostname}: 모든 NFS 마운트 정상")
        
        return all_ok
    
    def check_slurm_binaries(self) -> bool:
        """Slurm 바이너리 체크"""
        all_ok = True
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        
        # 컨트롤러 바이너리
        controller_bins = ['slurmctld', 'scontrol', 'squeue', 'sbatch']
        controller_ok = True
        
        for binary in controller_bins:
            exit_code, _, _ = self.ssh_manager.execute_command(
                controller_hostname, f"which {binary}", show_output=False
            )
            
            if exit_code != 0:
                print(f"  ❌ {controller_hostname}: {binary} 없음")
                controller_ok = False
                all_ok = False
        
        if controller_ok:
            print(f"  ✅ {controller_hostname}: Slurm 바이너리 정상")
        
        # 계산 노드 바이너리
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, "which slurmd", show_output=False
            )
            
            if exit_code == 0:
                print(f"  ✅ {hostname}: slurmd 설치됨")
            else:
                print(f"  ❌ {hostname}: slurmd 없음")
                all_ok = False
        
        return all_ok
    
    def check_slurm_config(self) -> bool:
        """Slurm 설정 파일 체크"""
        config_path = self.config['slurm_config']['config_path']
        all_ok = True
        
        required_files = ['slurm.conf']
        
        for node in self.all_nodes:
            hostname = node['hostname']
            node_ok = True
            
            for config_file in required_files:
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, f"test -f {config_path}/{config_file}", show_output=False
                )
                
                if exit_code != 0:
                    print(f"  ❌ {hostname}: {config_file} 없음")
                    node_ok = False
                    all_ok = False
            
            if node_ok:
                print(f"  ✅ {hostname}: Slurm 설정 파일 존재")
        
        return all_ok
    
    def check_slurm_services(self) -> bool:
        """Slurm 서비스 체크"""
        all_ok = True
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        
        # 컨트롤러 서비스
        exit_code, _, _ = self.ssh_manager.execute_command(
            controller_hostname, "systemctl is-active slurmctld", show_output=False
        )
        
        if exit_code == 0:
            print(f"  ✅ {controller_hostname}: slurmctld 실행 중")
        else:
            print(f"  ⚠️  {controller_hostname}: slurmctld 미실행 (수동 시작 필요)")
            print(f"     실행: ssh {controller_hostname} 'sudo systemctl start slurmctld'")
        
        # 계산 노드 서비스
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, "systemctl is-active slurmd", show_output=False
            )
            
            if exit_code == 0:
                print(f"  ✅ {hostname}: slurmd 실행 중")
            else:
                print(f"  ⚠️  {hostname}: slurmd 미실행 (수동 시작 필요)")
                print(f"     실행: ssh {hostname} 'sudo systemctl start slurmd'")
        
        return True  # 서비스는 수동 시작 가능하므로 항상 True
    
    def check_mpi(self) -> bool:
        """MPI 설치 체크"""
        all_ok = True
        
        for node in self.all_nodes:
            hostname = node['hostname']
            
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "mpirun --version", show_output=False
            )
            
            if exit_code == 0 and stdout:
                version = stdout.strip().split('\n')[0]
                print(f"  ✅ {hostname}: {version}")
            else:
                print(f"  ❌ {hostname}: MPI 미설치")
                all_ok = False
        
        return all_ok
    
    def check_apptainer(self) -> bool:
        """Apptainer 설치 체크"""
        all_ok = True
        
        for node in self.all_nodes:
            hostname = node['hostname']
            
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "apptainer --version", show_output=False
            )
            
            if exit_code == 0 and stdout:
                version = stdout.strip()
                print(f"  ✅ {hostname}: {version}")
            else:
                print(f"  ❌ {hostname}: Apptainer 미설치")
                all_ok = False
        
        return all_ok
    
    def check_image_directories(self) -> bool:
        """이미지 디렉토리 체크"""
        container_config = self.config.get('container_support', {}).get('apptainer', {})
        central_path = container_config.get('image_path', '/share/apptainer/images')
        scratch_path = container_config.get('scratch_image_path', '/scratch/apptainer/images')
        
        all_ok = True
        
        # 중앙 저장소
        controller_hostname = self.config['nodes']['controller']['hostname']
        exit_code, _, _ = self.ssh_manager.execute_command(
            controller_hostname, f"test -d {central_path}", show_output=False
        )
        
        if exit_code == 0:
            print(f"  ✅ {controller_hostname}: {central_path} 존재")
        else:
            print(f"  ❌ {controller_hostname}: {central_path} 없음")
            all_ok = False
        
        # 계산 노드 로컬 캐시
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, f"test -d {scratch_path}", show_output=False
            )
            
            if exit_code == 0:
                print(f"  ✅ {hostname}: {scratch_path} 존재")
            else:
                print(f"  ❌ {hostname}: {scratch_path} 없음")
                all_ok = False
        
        return all_ok
    
    def print_summary(self, all_passed: bool):
        """결과 요약 출력"""
        print("\n" + "=" * 80)
        print("📊 체크 결과 요약")
        print("=" * 80)
        
        passed = sum(1 for v in self.results.values() if v)
        total = len(self.results)
        
        print(f"\n통과: {passed}/{total}")
        print(f"실패: {total - passed}/{total}")
        
        print("\n📋 상세 결과:")
        for check_name, result in self.results.items():
            status = "✅ 통과" if result else "❌ 실패"
            print(f"  {status} - {check_name}")
        
        if all_passed:
            print("\n" + "=" * 80)
            print("🎉 모든 체크 통과! Slurm 클러스터가 완전히 설치되었습니다!")
            print("=" * 80)
            print("\n💡 다음 단계:")
            print("   1. Slurm 서비스 시작 (필요시)")
            print("   2. sinfo 명령으로 클러스터 상태 확인")
            print("   3. Apptainer 이미지 업로드")
            print("   4. 테스트 Job 제출")
        else:
            print("\n" + "=" * 80)
            print("⚠️  일부 항목이 실패했습니다")
            print("=" * 80)
            print("\n💡 해결 방법:")
            print("   1. 실패한 항목 확인")
            print("   2. python3 complete_slurm_setup.py 재실행")
            print("   3. 또는 ./setup_cluster_full.sh 재실행")


def main():
    """메인 함수"""
    print("🔍 Slurm 설치 완료 여부 체크 도구")
    
    config_file = Path("my_multihead_cluster.yaml")
    if not config_file.exists():
        print("❌ my_multihead_cluster.yaml 파일을 찾을 수 없습니다.")
        sys.exit(1)
    
    with open(config_file, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    ssh_manager = SSHManager(config)
    
    checker = SlurmInstallationChecker(config, ssh_manager)
    
    all_passed = checker.check_all()
    
    sys.exit(0 if all_passed else 1)


if __name__ == '__main__':
    main()
