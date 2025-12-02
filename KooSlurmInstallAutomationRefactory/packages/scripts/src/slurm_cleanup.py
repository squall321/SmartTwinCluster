#!/usr/bin/env python3
"""
Slurm 설치 자동화 - 기존 Slurm 제거 및 초기화
기존에 설치된 Slurm을 완전히 제거하고 초기화하는 모듈
"""

import time
from typing import Dict, List, Any
from ssh_manager import SSHManager


class SlurmCleanup:
    """Slurm 완전 제거 및 초기화 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.slurm_config = config.get('slurm_config', {})
        
        # 기본 경로들
        self.install_path = self.slurm_config.get('install_path', '/usr/local/slurm')
        self.config_path = self.slurm_config.get('config_path', '/usr/local/slurm/etc')
        self.log_path = self.slurm_config.get('log_path', '/var/log/slurm')
        self.spool_path = self.slurm_config.get('spool_path', '/var/spool/slurm')
        
        # 추가로 확인할 일반적인 Slurm 경로들
        self.common_paths = [
            '/usr/local/slurm',
            '/opt/slurm',
            '/etc/slurm',
            '/var/log/slurm',
            '/var/spool/slurm',
            '/var/lib/slurm',
            '/run/slurm'
        ]
    
    def cleanup_all_nodes(self, force: bool = False) -> bool:
        """모든 노드에서 Slurm 제거"""
        print("\n🧹 기존 Slurm 설치 제거 시작...")
        
        if not force:
            response = input("⚠️  기존 Slurm을 완전히 제거합니다. 계속하시겠습니까? (yes/no): ")
            if response.lower() != 'yes':
                print("❌ 제거 작업이 취소되었습니다.")
                return False
        
        # 1. 컨트롤러 노드 정리
        controller = self.config['nodes']['controller']
        if not self.cleanup_node(controller, 'controller'):
            print(f"⚠️  컨트롤러 노드 {controller['hostname']} 정리 실패")
        
        # 2. 계산 노드들 정리
        compute_nodes = self.config['nodes']['compute_nodes']
        for node in compute_nodes:
            if not self.cleanup_node(node, 'compute'):
                print(f"⚠️  계산 노드 {node['hostname']} 정리 실패")
        
        print("✅ 모든 노드에서 Slurm 제거 완료")
        return True
    
    def cleanup_node(self, node_config: Dict[str, Any], node_type: str) -> bool:
        """개별 노드에서 Slurm 제거"""
        hostname = node_config['hostname']
        print(f"\n🗑️  {hostname}: Slurm 제거 시작 ({node_type})")
        
        try:
            # 1. Slurm 서비스 중지 및 비활성화
            self.stop_slurm_services(hostname, node_type)
            
            # 2. Slurm 서비스 파일 제거
            self.remove_service_files(hostname, node_type)
            
            # 3. Slurm 프로세스 강제 종료
            self.kill_slurm_processes(hostname)
            
            # 4. Slurm 패키지 제거
            self.remove_slurm_packages(hostname)
            
            # 5. Slurm 디렉토리 및 파일 제거
            self.remove_slurm_directories(hostname)
            
            # 6. Slurm 사용자 제거 (선택적)
            # self.remove_slurm_user(hostname)
            
            # 7. Munge 재설정 (키 제거)
            self.cleanup_munge(hostname)
            
            # 8. cron 작업 제거
            self.remove_cron_jobs(hostname)
            
            # 9. 시스템 설정 정리
            self.cleanup_system_config(hostname)
            
            print(f"✅ {hostname}: Slurm 제거 완료")
            return True
            
        except Exception as e:
            print(f"❌ {hostname}: Slurm 제거 실패 - {e}")
            return False
    
    def stop_slurm_services(self, hostname: str, node_type: str):
        """Slurm 서비스 중지"""
        print(f"🛑 {hostname}: Slurm 서비스 중지 중...")
        
        services = []
        if node_type == 'controller':
            services = ['slurmctld', 'slurmdbd']
        else:
            services = ['slurmd']
        
        for service in services:
            # 서비스 중지
            self.ssh_manager.execute_command(
                hostname, f"systemctl stop {service}", show_output=False
            )
            # 서비스 비활성화
            self.ssh_manager.execute_command(
                hostname, f"systemctl disable {service}", show_output=False
            )
    
    def remove_service_files(self, hostname: str, node_type: str):
        """Slurm 서비스 파일 제거"""
        print(f"📄 {hostname}: 서비스 파일 제거 중...")
        
        service_files = [
            '/etc/systemd/system/slurmd.service',
            '/etc/systemd/system/slurmctld.service',
            '/etc/systemd/system/slurmdbd.service',
            '/usr/lib/systemd/system/slurmd.service',
            '/usr/lib/systemd/system/slurmctld.service',
            '/usr/lib/systemd/system/slurmdbd.service'
        ]
        
        for service_file in service_files:
            self.ssh_manager.execute_command(
                hostname, f"rm -f {service_file}", show_output=False
            )
        
        # systemd 재로드
        self.ssh_manager.execute_command(
            hostname, "systemctl daemon-reload", show_output=False
        )
        self.ssh_manager.execute_command(
            hostname, "systemctl reset-failed", show_output=False
        )
    
    def kill_slurm_processes(self, hostname: str):
        """실행 중인 Slurm 프로세스 강제 종료"""
        print(f"⚡ {hostname}: Slurm 프로세스 강제 종료 중...")
        
        processes = ['slurmctld', 'slurmd', 'slurmdbd']
        
        for process in processes:
            # SIGTERM으로 정상 종료 시도
            self.ssh_manager.execute_command(
                hostname, f"pkill -TERM {process}", show_output=False
            )
        
        time.sleep(3)
        
        # SIGKILL로 강제 종료
        for process in processes:
            self.ssh_manager.execute_command(
                hostname, f"pkill -KILL {process}", show_output=False
            )
    
    def remove_slurm_packages(self, hostname: str):
        """패키지 매니저로 설치된 Slurm 제거"""
        print(f"📦 {hostname}: Slurm 패키지 제거 중...")
        
        # RPM 기반 시스템 (CentOS, RHEL)
        rpm_packages = [
            'slurm', 'slurm-*', 'slurmd', 'slurmctld', 'slurmdbd',
            'slurm-perlapi', 'slurm-torque', 'slurm-openlava',
            'slurm-devel', 'slurm-example-configs'
        ]
        
        for package in rpm_packages:
            self.ssh_manager.execute_command(
                hostname, f"yum remove -y {package}", show_output=False
            )
            self.ssh_manager.execute_command(
                hostname, f"rpm -e {package} --nodeps", show_output=False
            )
        
        # DEB 기반 시스템 (Ubuntu, Debian)
        deb_packages = [
            'slurm-wlm', 'slurmd', 'slurmctld', 'slurmdbd',
            'slurm-client', 'slurm-wlm-*'
        ]
        
        for package in deb_packages:
            self.ssh_manager.execute_command(
                hostname, f"apt-get purge -y {package}", show_output=False
            )
        
        # 패키지 캐시 정리
        self.ssh_manager.execute_command(
            hostname, "yum clean all", show_output=False
        )
        self.ssh_manager.execute_command(
            hostname, "apt-get autoremove -y", show_output=False
        )
    
    def remove_slurm_directories(self, hostname: str):
        """Slurm 디렉토리 및 파일 제거"""
        print(f"🗂️  {hostname}: Slurm 디렉토리 제거 중...")
        
        # 설정 파일에서 지정된 경로
        paths_to_remove = [
            self.install_path,
            self.config_path,
            self.log_path,
            self.spool_path
        ]
        
        # 일반적인 Slurm 경로 추가
        paths_to_remove.extend(self.common_paths)
        
        # 중복 제거
        paths_to_remove = list(set(paths_to_remove))
        
        for path in paths_to_remove:
            # 디렉토리 백업 (선택적)
            backup_path = f"{path}.backup.$(date +%Y%m%d_%H%M%S)"
            self.ssh_manager.execute_command(
                hostname, f"[ -d {path} ] && mv {path} {backup_path} || true",
                show_output=False
            )
            
            # 완전 삭제 (백업이 실패했을 경우)
            self.ssh_manager.execute_command(
                hostname, f"rm -rf {path}", show_output=False
            )
        
        # 기타 Slurm 관련 파일 제거
        other_files = [
            '/etc/slurm.conf',
            '/etc/slurmdbd.conf',
            '/etc/sysconfig/slurm*',
            '/etc/default/slurm*',
            '/var/run/slurm*',
            '/tmp/slurm*'
        ]
        
        for file_pattern in other_files:
            self.ssh_manager.execute_command(
                hostname, f"rm -rf {file_pattern}", show_output=False
            )
    
    def remove_slurm_user(self, hostname: str):
        """Slurm 사용자 제거 (선택적)"""
        print(f"👤 {hostname}: Slurm 사용자 제거 중...")
        
        slurm_user = self.config.get('users', {}).get('slurm_user', 'slurm')
        
        # 사용자 홈 디렉토리 백업
        self.ssh_manager.execute_command(
            hostname, f"[ -d /home/{slurm_user} ] && tar -czf /root/{slurm_user}_backup.tar.gz /home/{slurm_user} || true",
            show_output=False
        )
        
        # 사용자 제거
        self.ssh_manager.execute_command(
            hostname, f"userdel -r {slurm_user}", show_output=False
        )
        
        # 그룹 제거
        self.ssh_manager.execute_command(
            hostname, f"groupdel {slurm_user}", show_output=False
        )
    
    def cleanup_munge(self, hostname: str):
        """Munge 키 및 설정 초기화"""
        print(f"🔐 {hostname}: Munge 초기화 중...")
        
        # Munge 서비스 중지
        self.ssh_manager.execute_command(
            hostname, "systemctl stop munge", show_output=False
        )
        
        # Munge 키 백업 및 제거
        self.ssh_manager.execute_command(
            hostname, "[ -f /etc/munge/munge.key ] && cp /etc/munge/munge.key /etc/munge/munge.key.old || true",
            show_output=False
        )
        self.ssh_manager.execute_command(
            hostname, "rm -f /etc/munge/munge.key", show_output=False
        )
        
        # Munge 런타임 파일 제거
        self.ssh_manager.execute_command(
            hostname, "rm -rf /var/run/munge/*", show_output=False
        )
        self.ssh_manager.execute_command(
            hostname, "rm -rf /var/log/munge/*", show_output=False
        )
    
    def remove_cron_jobs(self, hostname: str):
        """Slurm 관련 cron 작업 제거"""
        print(f"⏰ {hostname}: cron 작업 제거 중...")
        
        # Slurm 관련 cron 작업 제거
        cron_patterns = [
            'slurm',
            'slurmdbd',
            'slurm_backup',
            'slurm_db_backup'
        ]
        
        for pattern in cron_patterns:
            self.ssh_manager.execute_command(
                hostname, f"crontab -l 2>/dev/null | grep -v '{pattern}' | crontab -",
                show_output=False
            )
    
    def cleanup_system_config(self, hostname: str):
        """시스템 설정 정리"""
        print(f"⚙️  {hostname}: 시스템 설정 정리 중...")
        
        # PATH 환경변수에서 Slurm 경로 제거
        self.ssh_manager.execute_command(
            hostname, f"sed -i '/slurm/d' /etc/profile", show_output=False
        )
        self.ssh_manager.execute_command(
            hostname, f"sed -i '/slurm/d' /etc/bashrc", show_output=False
        )
        self.ssh_manager.execute_command(
            hostname, f"sed -i '/slurm/d' /etc/bash.bashrc", show_output=False
        )
        
        # 라이브러리 경로 제거
        self.ssh_manager.execute_command(
            hostname, "rm -f /etc/ld.so.conf.d/slurm.conf", show_output=False
        )
        self.ssh_manager.execute_command(
            hostname, "ldconfig", show_output=False
        )
        
        # Slurm 관련 커널 파라미터 제거
        self.ssh_manager.execute_command(
            hostname, "rm -f /etc/sysctl.d/99-slurm*.conf", show_output=False
        )
        
        # Slurm 관련 ulimit 설정 제거
        self.ssh_manager.execute_command(
            hostname, f"sed -i '/Slurm cluster/,+10d' /etc/security/limits.conf",
            show_output=False
        )
    
    def verify_cleanup(self) -> bool:
        """정리 작업 검증"""
        print("\n✅ Slurm 제거 검증 중...")
        
        all_nodes = [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']
        
        for node in all_nodes:
            hostname = node['hostname']
            
            # Slurm 프로세스 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "ps aux | grep -E 'slurm[cd]|slurmdbd' | grep -v grep",
                show_output=False
            )
            
            if stdout.strip():
                print(f"⚠️  {hostname}: Slurm 프로세스가 아직 실행 중입니다.")
            else:
                print(f"✅ {hostname}: Slurm 프로세스 없음")
            
            # Slurm 디렉토리 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, f"ls -la {self.install_path} 2>/dev/null || echo 'not found'",
                show_output=False
            )
            
            if 'not found' in stdout:
                print(f"✅ {hostname}: Slurm 디렉토리 제거됨")
            else:
                print(f"⚠️  {hostname}: Slurm 디렉토리가 아직 존재합니다.")
        
        print("\n✅ Slurm 제거 검증 완료")
        print("💡 새로운 Slurm 설치를 진행할 준비가 되었습니다.")
        return True


def main():
    """테스트 메인 함수"""
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python slurm_cleanup.py <config_file>")
        return
    
    try:
        # 설정 파일 로드
        parser = ConfigParser(sys.argv[1])
        config = parser.load_config()
        
        # SSH 관리자 설정
        ssh_manager = SSHManager()
        
        # 노드들 추가
        all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
        for node in all_nodes:
            ssh_manager.add_node(node)
        
        # 연결 테스트
        if not ssh_manager.connect_all_nodes():
            print("일부 노드 연결 실패")
            return
        
        # Slurm 정리
        cleanup = SlurmCleanup(config, ssh_manager)
        
        if cleanup.cleanup_all_nodes(force=False):
            cleanup.verify_cleanup()
        
        ssh_manager.disconnect_all()
        
    except Exception as e:
        print(f"정리 작업 중 오류 발생: {e}")


if __name__ == "__main__":
    main()
