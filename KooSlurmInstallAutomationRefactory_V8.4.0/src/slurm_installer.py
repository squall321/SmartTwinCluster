#!/usr/bin/env python3
"""
Slurm 설치 자동화 - Slurm 설치 및 설정
실제 Slurm을 설치하고 설정하는 핵심 모듈
"""

import os
import tempfile
from typing import Dict, List, Optional, Tuple, Any
from pathlib import Path
from ssh_manager import SSHManager
from os_manager import OSManager
import time


class SlurmInstaller:
    """Slurm 설치 및 설정 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.slurm_config = config['slurm_config']
        self.cluster_info = config['cluster_info']
        
        # Slurm 설정 경로
        self.install_path = self.slurm_config['install_path']
        self.config_path = self.slurm_config['config_path']
        self.log_path = self.slurm_config['log_path']
        self.spool_path = self.slurm_config.get('spool_path', '/var/spool/slurm')
        
        # 사용자 정보
        self.slurm_user = config['users']['slurm_user']
        self.slurm_uid = config['users']['slurm_uid']
        self.slurm_gid = config['users']['slurm_gid']
    
    def install_slurm_on_all_nodes(self) -> bool:
        """모든 노드에 Slurm 설치"""
        print("\n🚀 Slurm 설치 시작...")
        
        # 1. 컨트롤러 노드 설치
        controller = self.config['nodes']['controller']
        if not self.install_slurm_on_node(controller, 'controller'):
            print("❌ 컨트롤러 노드 설치 실패")
            return False
        
        # 2. 계산 노드들 설치
        compute_nodes = self.config['nodes']['compute_nodes']
        for node in compute_nodes:
            if not self.install_slurm_on_node(node, 'compute'):
                print(f"❌ 계산 노드 {node['hostname']} 설치 실패")
                return False
        
        print("✅ 모든 노드에 Slurm 설치 완료")
        return True
    
    def install_slurm_on_node(self, node_config: Dict[str, Any], node_type: str) -> bool:
        """개별 노드에 Slurm 설치"""
        hostname = node_config['hostname']
        print(f"\n📦 {hostname}: Slurm 설치 시작 ({node_type})")
        
        try:
            # 1. Slurm 사용자 생성
            if not self.create_slurm_user(hostname):
                return False
            
            # 2. 디렉토리 생성
            if not self.create_slurm_directories(hostname):
                return False
            
            # 3. Slurm 소스 다운로드 및 컴파일
            if not self.download_and_compile_slurm(hostname):
                return False
            
            # 4. Slurm 서비스 설정
            if not self.setup_slurm_services(hostname, node_type):
                return False
            
            print(f"✅ {hostname}: Slurm 설치 완료")
            return True
            
        except Exception as e:
            print(f"❌ {hostname}: Slurm 설치 실패 - {e}")
            return False
    
    def create_slurm_user(self, hostname: str) -> bool:
        """Slurm 사용자 생성"""
        print(f"👤 {hostname}: Slurm 사용자 생성...")
        
        commands = [
            f"groupadd -g {self.slurm_gid} {self.slurm_user}",
            f"useradd -u {self.slurm_uid} -g {self.slurm_gid} -m -s /bin/bash {self.slurm_user}",
            f"usermod -aG wheel {self.slurm_user}"  # sudo 권한 추가 (CentOS/RHEL)
        ]
        
        for cmd in commands:
            self.ssh_manager.execute_command(hostname, cmd, show_output=False)
        
        return True
    
    def create_slurm_directories(self, hostname: str) -> bool:
        """Slurm 디렉토리 생성"""
        print(f"📁 {hostname}: Slurm 디렉토리 생성...")
        
        directories = [
            self.install_path,
            self.config_path,
            self.log_path,
            self.spool_path,
            f"{self.spool_path}/ctld",
            f"{self.spool_path}/d",
        ]
        
        for directory in directories:
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, f"mkdir -p {directory}"
            )
            if exit_code != 0:
                return False
            
            # 소유권 설정
            self.ssh_manager.execute_command(
                hostname, f"chown -R {self.slurm_user}:{self.slurm_user} {directory}"
            )
        
        return True
    
    def download_and_compile_slurm(self, hostname: str) -> bool:
        """Slurm 소스 다운로드 및 컴파일"""
        print(f"⚙️  {hostname}: Slurm 컴파일 중...")
        
        slurm_version = self.slurm_config['version']
        build_options = self.slurm_config.get('build_options', '')
        
        # 컴파일 명령어들
        compile_commands = [
            "cd /tmp",
            f"wget https://download.schedmd.com/slurm/slurm-{slurm_version}.tar.bz2",
            f"tar -xjf slurm-{slurm_version}.tar.bz2",
            f"cd slurm-{slurm_version}",
            f"./configure --prefix={self.install_path} --sysconfdir={self.config_path} {build_options}",
            "make -j$(nproc)",
            "make install"
        ]
        
        # 컴파일 실행 (시간이 오래 걸릴 수 있음)
        for cmd in compile_commands:
            exit_code, stdout, stderr = self.ssh_manager.execute_command(
                hostname, cmd, timeout=1800  # 30분 timeout
            )
            
            if exit_code != 0:
                print(f"❌ {hostname}: 컴파일 실패 - {cmd}")
                if stderr:
                    print(f"오류: {stderr[:500]}")
                return False
        
        # PATH 환경변수 설정
        path_cmd = f"echo 'export PATH={self.install_path}/bin:{self.install_path}/sbin:$PATH' >> /etc/profile"
        self.ssh_manager.execute_command(hostname, path_cmd)
        
        # 라이브러리 경로 설정
        lib_cmd = f"echo '{self.install_path}/lib' > /etc/ld.so.conf.d/slurm.conf"
        self.ssh_manager.execute_command(hostname, lib_cmd)
        self.ssh_manager.execute_command(hostname, "ldconfig")
        
        return True
    
    def setup_slurm_services(self, hostname: str, node_type: str) -> bool:
        """Slurm 서비스 설정"""
        print(f"🔧 {hostname}: Slurm 서비스 설정...")
        
        if node_type == 'controller':
            return self.setup_controller_services(hostname)
        else:
            return self.setup_compute_services(hostname)
    
    def setup_controller_services(self, hostname: str) -> bool:
        """컨트롤러 서비스 설정"""
        
        # slurmctld 서비스 파일 생성
        slurmctld_service = f"""[Unit]
Description=Slurm controller daemon
After=network.target munge.service
Requires=munge.service

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmctld
ExecStart={self.install_path}/sbin/slurmctld -D
ExecReload=/bin/kill -HUP $MAINPID
PIDFile={self.spool_path}/ctld/slurmctld.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
User={self.slurm_user}
Group={self.slurm_user}

[Install]
WantedBy=multi-user.target
"""
        
        # 서비스 파일 업로드
        exit_code, _, _ = self.ssh_manager.execute_command(
            hostname, f"echo '{slurmctld_service}' > /etc/systemd/system/slurmctld.service"
        )
        
        if exit_code != 0:
            return False
        
        # 데이터베이스 사용 시 slurmdbd 서비스도 설정
        if self.config.get('database', {}).get('enabled'):
            if not self.setup_slurmdbd_service(hostname):
                return False
        
        return True
    
    def setup_compute_services(self, hostname: str) -> bool:
        """계산 노드 서비스 설정"""
        
        # slurmd 서비스 파일 생성
        slurmd_service = f"""[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmd
ExecStart={self.install_path}/sbin/slurmd -D
ExecReload=/bin/kill -HUP $MAINPID
PIDFile={self.spool_path}/d/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
User=root
Group=root

[Install]
WantedBy=multi-user.target
"""
        
        # 서비스 파일 업로드
        exit_code, _, _ = self.ssh_manager.execute_command(
            hostname, f"echo '{slurmd_service}' > /etc/systemd/system/slurmd.service"
        )
        
        return exit_code == 0
    
    def setup_slurmdbd_service(self, hostname: str) -> bool:
        """slurmdbd 서비스 설정 (데이터베이스 사용 시)"""
        
        slurmdbd_service = f"""[Unit]
Description=Slurm DBD accounting daemon
After=network.target munge.service mariadb.service
Requires=munge.service

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmdbd
ExecStart={self.install_path}/sbin/slurmdbd -D
ExecReload=/bin/kill -HUP $MAINPID
PIDFile={self.spool_path}/slurmdbd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
User={self.slurm_user}
Group={self.slurm_user}

[Install]
WantedBy=multi-user.target
"""
        
        exit_code, _, _ = self.ssh_manager.execute_command(
            hostname, f"echo '{slurmdbd_service}' > /etc/systemd/system/slurmdbd.service"
        )
        
        return exit_code == 0
    
    def generate_slurm_conf(self) -> str:
        """slurm.conf 설정 파일 생성"""
        
        controller_hostname = self.config['nodes']['controller']['hostname']
        cluster_name = self.cluster_info['cluster_name']
        
        # 기본 Slurm 설정
        config_content = f"""# Slurm configuration file generated by KooSlurmInstallAutomation
# Generated on: {time.strftime('%Y-%m-%d %H:%M:%S')}

# MANAGEMENT POLICIES
ClusterName={cluster_name}
ControlMachine={controller_hostname}
ControlAddr={controller_hostname}

# ACCOUNTING
"""
        
        # 데이터베이스 사용 시 회계 설정 추가
        if self.config.get('database', {}).get('enabled'):
            config_content += f"""JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost={controller_hostname}
"""
        else:
            config_content += """JobAcctGatherType=jobacct_gather/none
AccountingStorageType=accounting_storage/none
"""
        
        # 스케줄링 설정
        scheduler_type = self.slurm_config.get('scheduler_type', 'sched/backfill')
        select_type = self.slurm_config.get('select_type', 'select/cons_tres')
        
        config_content += f"""
# SCHEDULING
SchedulerType={scheduler_type}
SelectType={select_type}
SelectTypeParameters=CR_Core_Memory

# TIMERS
SlurmctldTimeout=120
SlurmdTimeout=300
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0

# LOGGING
SlurmctldDebug=info
SlurmctldLogFile={self.log_path}/slurmctld.log
SlurmdDebug=info
SlurmdLogFile={self.log_path}/slurmd.log

# STATE PRESERVATION
StateSaveLocation={self.spool_path}/ctld
SlurmdSpoolDir={self.spool_path}/d

# PATHS
SlurmUser={self.slurm_user}
SlurmdUser=root

# COMPUTE NODES
"""
        
        # 계산 노드 정의
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            hardware = node['hardware']
            
            cpus = hardware['cpus']
            memory = hardware['memory_mb']
            
            # 소켓, 코어, 스레드 정보
            sockets = hardware.get('sockets', 1)
            cores_per_socket = hardware.get('cores_per_socket', cpus // sockets)
            threads_per_core = hardware.get('threads_per_core', 1)
            
            config_content += f"""NodeName={hostname} CPUs={cpus} Sockets={sockets} CoresPerSocket={cores_per_socket} ThreadsPerCore={threads_per_core} RealMemory={memory}"""
            
            # GPU 설정
            gpu = hardware.get('gpu', {})
            if gpu.get('type') != 'none' and gpu.get('count', 0) > 0:
                gpu_type = gpu['type']
                gpu_count = gpu['count']
                config_content += f" Gres=gpu:{gpu_type}:{gpu_count}"
            
            config_content += f" State=UNKNOWN\\n"
        
        # 파티션 정의
        config_content += "\n# PARTITIONS\n"
        for partition in self.slurm_config['partitions']:
            name = partition['name']
            nodes = partition['nodes']
            max_time = partition.get('max_time', 'UNLIMITED')
            max_nodes = partition.get('max_nodes', '')
            default = partition.get('default', False)
            
            config_content += f"PartitionName={name} Nodes={nodes} MaxTime={max_time}"
            
            if max_nodes:
                config_content += f" MaxNodes={max_nodes}"
            
            if default:
                config_content += " Default=YES"
            
            config_content += " State=UP\\n"
        
        return config_content
    
    def generate_slurmdbd_conf(self) -> str:
        """slurmdbd.conf 설정 파일 생성 (데이터베이스 사용 시)"""
        
        if not self.config.get('database', {}).get('enabled'):
            return ""
        
        db_config = self.config['database']
        
        config_content = f"""# Slurmdbd configuration file generated by KooSlurmInstallAutomation
# Generated on: {time.strftime('%Y-%m-%d %H:%M:%S')}

# AUTHENTICATION
AuthType=auth/munge

# DATABASE
DbdHost={db_config['host']}
DbdPort={db_config['port']}
SlurmUser={self.slurm_user}
StorageHost={db_config['host']}
StoragePort={db_config['port']}
StorageUser={db_config['username']}
StoragePass={db_config['password']}
StorageType=accounting_storage/mysql

# LOGGING
LogFile={self.log_path}/slurmdbd.log
DebugLevel=info

# MISC
PidFile={self.spool_path}/slurmdbd.pid
"""
        
        return config_content
    
    def deploy_configuration_files(self) -> bool:
        """설정 파일들을 모든 노드에 배포"""
        print("\n📋 Slurm 설정 파일 배포 중...")
        
        # slurm.conf 생성
        slurm_conf_content = self.generate_slurm_conf()
        
        # 임시 파일로 저장
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.conf') as f:
            f.write(slurm_conf_content)
            temp_slurm_conf = f.name
        
        try:
            # 모든 노드에 slurm.conf 배포
            all_nodes = [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']
            
            for node in all_nodes:
                hostname = node['hostname']
                
                # 설정 파일 업로드
                success = self.ssh_manager.upload_file_to_node(
                    hostname, temp_slurm_conf, f"{self.config_path}/slurm.conf"
                )
                
                if not success:
                    print(f"❌ {hostname}: slurm.conf 배포 실패")
                    return False
                
                # 소유권 및 권한 설정
                self.ssh_manager.execute_command(
                    hostname, f"chown {self.slurm_user}:{self.slurm_user} {self.config_path}/slurm.conf"
                )
                self.ssh_manager.execute_command(
                    hostname, f"chmod 644 {self.config_path}/slurm.conf"
                )
            
            # 데이터베이스 사용 시 slurmdbd.conf도 배포
            if self.config.get('database', {}).get('enabled'):
                slurmdbd_conf_content = self.generate_slurmdbd_conf()
                
                with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.conf') as f:
                    f.write(slurmdbd_conf_content)
                    temp_slurmdbd_conf = f.name
                
                controller_hostname = self.config['nodes']['controller']['hostname']
                success = self.ssh_manager.upload_file_to_node(
                    controller_hostname, temp_slurmdbd_conf, f"{self.config_path}/slurmdbd.conf"
                )
                
                if success:
                    self.ssh_manager.execute_command(
                        controller_hostname, f"chown {self.slurm_user}:{self.slurm_user} {self.config_path}/slurmdbd.conf"
                    )
                    self.ssh_manager.execute_command(
                        controller_hostname, f"chmod 600 {self.config_path}/slurmdbd.conf"
                    )
                
                os.unlink(temp_slurmdbd_conf)
            
            print("✅ 설정 파일 배포 완료")
            return True
            
        finally:
            # 임시 파일 정리
            os.unlink(temp_slurm_conf)
    
    def setup_munge_authentication(self) -> bool:
        """Munge 인증 시스템 설정"""
        print("\n🔐 Munge 인증 시스템 설정 중...")
        
        controller_hostname = self.config['nodes']['controller']['hostname']
        
        # 컨트롤러에서 Munge 키 생성
        print(f"🔑 {controller_hostname}: Munge 키 생성...")
        
        commands = [
            "yum install -y munge munge-libs munge-devel || apt install -y munge",
            "systemctl enable munge",
            "create-munge-key",
            "chown munge:munge /etc/munge/munge.key",
            "chmod 400 /etc/munge/munge.key"
        ]
        
        for cmd in commands:
            exit_code, _, _ = self.ssh_manager.execute_command(controller_hostname, cmd)
            if exit_code != 0 and "create-munge-key" in cmd:
                # Munge 키가 이미 있을 수 있음
                continue
        
        # Munge 키를 다른 노드들에 복사
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            print(f"🔑 {hostname}: Munge 키 복사...")
            
            # Munge 설치
            self.ssh_manager.execute_command(
                hostname, "yum install -y munge munge-libs munge-devel || apt install -y munge"
            )
            
            # 키 파일 복사 (scp 사용)
            self.ssh_manager.execute_command(
                controller_hostname, 
                f"scp /etc/munge/munge.key {hostname}:/etc/munge/munge.key"
            )
            
            # 권한 설정
            key_setup_commands = [
                "chown munge:munge /etc/munge/munge.key",
                "chmod 400 /etc/munge/munge.key",
                "systemctl enable munge",
                "systemctl start munge"
            ]
            
            for cmd in key_setup_commands:
                self.ssh_manager.execute_command(hostname, cmd)
        
        # 컨트롤러에서도 Munge 시작
        self.ssh_manager.execute_command(controller_hostname, "systemctl start munge")
        
        print("✅ Munge 인증 시스템 설정 완료")
        return True
    
    def start_slurm_services(self) -> bool:
        """Slurm 서비스 시작"""
        print("\n▶️  Slurm 서비스 시작 중...")
        
        controller_hostname = self.config['nodes']['controller']['hostname']
        
        # 1. 데이터베이스 사용 시 slurmdbd 먼저 시작
        if self.config.get('database', {}).get('enabled'):
            print(f"🗄️  {controller_hostname}: slurmdbd 시작...")
            self.ssh_manager.execute_command(controller_hostname, "systemctl daemon-reload")
            self.ssh_manager.execute_command(controller_hostname, "systemctl enable slurmdbd")
            self.ssh_manager.execute_command(controller_hostname, "systemctl start slurmdbd")
            time.sleep(5)  # slurmdbd 시작 대기
        
        # 2. 컨트롤러 서비스 시작
        print(f"🎯 {controller_hostname}: slurmctld 시작...")
        self.ssh_manager.execute_command(controller_hostname, "systemctl daemon-reload")
        self.ssh_manager.execute_command(controller_hostname, "systemctl enable slurmctld")
        self.ssh_manager.execute_command(controller_hostname, "systemctl start slurmctld")
        
        time.sleep(10)  # 컨트롤러 시작 대기
        
        # 3. 계산 노드 서비스 시작
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            print(f"⚡ {hostname}: slurmd 시작...")
            
            self.ssh_manager.execute_command(hostname, "systemctl daemon-reload")
            self.ssh_manager.execute_command(hostname, "systemctl enable slurmd")
            self.ssh_manager.execute_command(hostname, "systemctl start slurmd")
        
        time.sleep(5)  # 서비스 시작 대기
        
        print("✅ Slurm 서비스 시작 완료")
        return True
    
    def verify_installation(self) -> bool:
        """설치 검증"""
        print("\n✅ Slurm 설치 검증 중...")
        
        controller_hostname = self.config['nodes']['controller']['hostname']
        
        # 1. 서비스 상태 확인
        services_to_check = ['munge', 'slurmctld']
        if self.config.get('database', {}).get('enabled'):
            services_to_check.append('slurmdbd')
        
        for service in services_to_check:
            exit_code, stdout, stderr = self.ssh_manager.execute_command(
                controller_hostname, f"systemctl is-active {service}", show_output=False
            )
            
            if exit_code == 0:
                print(f"✅ {controller_hostname}: {service} 서비스 실행 중")
            else:
                print(f"❌ {controller_hostname}: {service} 서비스 실행 실패")
                return False
        
        # 2. 계산 노드 서비스 확인
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            
            for service in ['munge', 'slurmd']:
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, f"systemctl is-active {service}", show_output=False
                )
                
                if exit_code == 0:
                    print(f"✅ {hostname}: {service} 서비스 실행 중")
                else:
                    print(f"❌ {hostname}: {service} 서비스 실행 실패")
        
        # 3. 노드 상태 확인
        print(f"📊 노드 상태 확인...")
        exit_code, stdout, stderr = self.ssh_manager.execute_command(
            controller_hostname, f"{self.install_path}/bin/sinfo", show_output=False
        )
        
        if exit_code == 0:
            print("노드 상태:")
            print(stdout)
        else:
            print("❌ 노드 상태 확인 실패")
            if stderr:
                print(f"오류: {stderr}")
        
        # 4. 간단한 테스트 작업 제출
        print("🧪 테스트 작업 제출...")
        test_job_script = """#!/bin/bash
#SBATCH --job-name=test_job
#SBATCH --output=test_job.out
#SBATCH --time=00:01:00
#SBATCH --nodes=1

echo "Test job started at $(date)"
hostname
echo "Test job completed at $(date)"
"""
        
        # 테스트 스크립트 생성
        self.ssh_manager.execute_command(
            controller_hostname, f"echo '{test_job_script}' > /tmp/test_job.sh"
        )
        
        # 작업 제출
        exit_code, stdout, stderr = self.ssh_manager.execute_command(
            controller_hostname, f"{self.install_path}/bin/sbatch /tmp/test_job.sh"
        )
        
        if exit_code == 0:
            print(f"✅ 테스트 작업 제출 성공: {stdout.strip()}")
        else:
            print(f"❌ 테스트 작업 제출 실패: {stderr}")
        
        print("✅ Slurm 설치 검증 완료")
        return True


def main():
    """테스트 메인 함수"""
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python slurm_installer.py <config_file>")
        return
    
    try:
        # 설정 파일 로드
        parser = ConfigParser(sys.argv[1])
        config = parser.load_config()
        
        if not parser.validate_config():
            print("설정 파일 검증 실패")
            return
        
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
        
        # Slurm 설치
        installer = SlurmInstaller(config, ssh_manager)
        
        if installer.install_slurm_on_all_nodes():
            installer.deploy_configuration_files()
            installer.setup_munge_authentication()
            installer.start_slurm_services()
            installer.verify_installation()
        
        ssh_manager.disconnect_all()
        
    except Exception as e:
        print(f"설치 중 오류 발생: {e}")


if __name__ == "__main__":
    main()
