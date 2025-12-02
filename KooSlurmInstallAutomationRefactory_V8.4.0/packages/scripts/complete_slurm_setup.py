#!/usr/bin/env python3
"""
Slurm 완전 자동 설치 보완 모듈
누락된 필수 설정들을 자동으로 처리
"""

import sys
from pathlib import Path
from typing import Dict, Any

# src 디렉토리 경로 추가
src_path = Path(__file__).parent / 'src'
sys.path.insert(0, str(src_path))

# 개별 import로 순환 참조 방지
import ssh_manager


class SlurmAutoSetup:
    """Slurm 자동 설치 보완 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_mgr):
        self.config = config
        self.ssh_manager = ssh_mgr
        self.all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
    
    def complete_setup(self) -> bool:
        """완전 자동 설치 - 누락된 모든 단계 처리"""
        print("\n🔧 Slurm 완전 자동 설치 시작...")
        
        steps = [
            ("SSH 키 자동 설정", self.setup_ssh_keys),
            ("방화벽 설정", self.configure_firewall),
            ("SELinux 설정", self.configure_selinux),
            ("NTP 시간 동기화", self.setup_ntp),
            ("필수 패키지 설치", self.install_dependencies),
            ("Munge 인증 설정", self.setup_munge),
            ("NFS 공유 스토리지", self.setup_nfs),
            ("slurm.conf 생성", self.generate_slurm_conf),
            ("cgroup 설정", self.setup_cgroup),
            ("환경변수 설정", self.setup_environment),
        ]
        
        for step_name, step_func in steps:
            print(f"\n📌 {step_name}...")
            try:
                if not step_func():
                    print(f"  ⚠️  {step_name} 실패 (계속 진행)")
            except Exception as e:
                print(f"  ❌ {step_name} 오류: {e}")
        
        print("\n✅ Slurm 완전 자동 설치 완료!")
        return True
    
    def setup_ssh_keys(self) -> bool:
        """모든 노드에 호스트명 및 SSH 키 자동 설정 (패스워드 없는 로그인)"""
        print("  🔑 SSH 키 설정 중...")
        
        # 1. /etc/hosts에 모든 노드 추가
        print("    📝 /etc/hosts 파일 업데이트 중...")

        # 모든 호스트 엔트리를 준비
        host_entries = []
        for node in self.all_nodes:
            hostname = node['hostname']
            ip_address = node.get('ip_address', hostname)
            host_entries.append(f"{ip_address} {hostname}")

        # 각 노드의 /etc/hosts 업데이트
        for target_node in self.all_nodes:
            target_hostname = target_node['hostname']
            target_ip = target_node.get('ip_address', target_hostname)

            print(f"      → {target_hostname} /etc/hosts 업데이트 중...")

            # 모든 호스트 엔트리를 한 번에 추가
            for entry in host_entries:
                hostname_in_entry = entry.split()[1]
                ip_in_entry = entry.split()[0]

                # 해당 호스트명이 이미 있는지 확인 후 추가
                check_cmd = f"grep -q '{hostname_in_entry}' /etc/hosts"
                exit_code, _, _ = self.ssh_manager.execute_command(
                    target_hostname,
                    check_cmd,
                    show_output=False
                )

                if exit_code != 0:  # 없으면 추가
                    add_cmd = f"sudo bash -c 'echo \"{ip_in_entry} {hostname_in_entry}\" >> /etc/hosts'"
                    self.ssh_manager.execute_command(
                        target_hostname,
                        add_cmd,
                        show_output=False
                    )

        print("    ✅ /etc/hosts 업데이트 완료")
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        ssh_user = controller['ssh_user']
        
        # 2. 컨트롤러에 SSH 키가 없으면 생성
        exit_code, _, _ = self.ssh_manager.execute_command(
            controller_hostname,
            f"test -f ~/.ssh/id_rsa",
            show_output=False
        )
        
        if exit_code != 0:
            print(f"    📝 SSH 키 생성 중...")
            self.ssh_manager.execute_command(
                controller_hostname,
                f"ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''",
                show_output=False
            )
        
        # 3. 공개키 내용 가져오기
        exit_code, pubkey, _ = self.ssh_manager.execute_command(
            controller_hostname,
            f"cat ~/.ssh/id_rsa.pub",
            show_output=False
        )
        
        if exit_code != 0 or not pubkey.strip():
            print(f"    ⚠️  공개키를 읽을 수 없습니다")
            return False
        
        # 4. 모든 노드에 공개키 추가
        for node in self.all_nodes:
            hostname = node['hostname']
            print(f"    🔐 {hostname}: SSH 키 배포 중...")
            
            # authorized_keys에 추가
            self.ssh_manager.execute_command(
                hostname,
                f"""
                mkdir -p ~/.ssh
                chmod 700 ~/.ssh
                echo '{pubkey.strip()}' >> ~/.ssh/authorized_keys
                chmod 600 ~/.ssh/authorized_keys
                """,
                show_output=False
            )
            
            # StrictHostKeyChecking 비활성화
            self.ssh_manager.execute_command(
                hostname,
                f"""
                mkdir -p ~/.ssh
                echo 'Host *' > ~/.ssh/config
                echo '    StrictHostKeyChecking no' >> ~/.ssh/config
                echo '    UserKnownHostsFile=/dev/null' >> ~/.ssh/config
                chmod 600 ~/.ssh/config
                """,
                show_output=False
            )
        
        print(f"    ✅ SSH 키 설정 완료")
        return True
    
    def configure_firewall(self) -> bool:
        """방화벽 설정 (Slurm 포트 개방)"""
        print("  🔥 방화벽 설정 중...")
        
        firewall_config = self.config.get('network', {}).get('firewall', {})
        if not firewall_config.get('enabled', True):
            print("    ⏭️  방화벽 설정 건너뜀 (비활성화됨)")
            return True
        
        ports = firewall_config.get('ports', {})
        
        for node in self.all_nodes:
            hostname = node['hostname']
            node_type = node.get('node_type', 'compute')
            
            print(f"    🔐 {hostname}: 방화벽 규칙 추가 중...")
            
            # 필요한 포트 결정
            required_ports = [ports.get('ssh', 22)]
            
            if node_type == 'controller':
                required_ports.extend([
                    ports.get('slurmctld', 6817),
                    ports.get('slurmdbd', 6819)
                ])
            else:
                required_ports.append(ports.get('slurmd', 6818))
            
            # firewalld 사용 (CentOS/RHEL)
            for port in required_ports:
                self.ssh_manager.execute_command(
                    hostname,
                    f"firewall-cmd --permanent --add-port={port}/tcp 2>/dev/null || true",
                    show_output=False
                )
            
            self.ssh_manager.execute_command(
                hostname,
                "firewall-cmd --reload 2>/dev/null || true",
                show_output=False
            )
            
            # ufw 사용 (Ubuntu)
            for port in required_ports:
                self.ssh_manager.execute_command(
                    hostname,
                    f"ufw allow {port}/tcp 2>/dev/null || true",
                    show_output=False
                )
        
        print(f"    ✅ 방화벽 설정 완료")
        return True
    
    def configure_selinux(self) -> bool:
        """SELinux 설정"""
        print("  🛡️  SELinux 설정 중...")
        
        selinux_config = self.config.get('security', {}).get('selinux', {})
        if not selinux_config.get('enabled', True):
            # SELinux 비활성화
            for node in self.all_nodes:
                hostname = node['hostname']
                self.ssh_manager.execute_command(
                    hostname,
                    "setenforce 0 2>/dev/null || true",
                    show_output=False
                )
                self.ssh_manager.execute_command(
                    hostname,
                    "sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true",
                    show_output=False
                )
            print(f"    ✅ SELinux 비활성화 완료")
        else:
            mode = selinux_config.get('mode', 'permissive')
            for node in self.all_nodes:
                hostname = node['hostname']
                self.ssh_manager.execute_command(
                    hostname,
                    f"setenforce {1 if mode == 'enforcing' else 0} 2>/dev/null || true",
                    show_output=False
                )
            print(f"    ✅ SELinux {mode} 모드 설정 완료")
        
        return True
    
    def setup_ntp(self) -> bool:
        """NTP 시간 동기화 설정"""
        print("  ⏰ NTP 시간 동기화 설정 중...")
        
        time_config = self.config.get('time_synchronization', {})
        if not time_config.get('enabled', True):
            print("    ⏭️  NTP 설정 건너뜀")
            return True
        
        ntp_servers = time_config.get('ntp_servers', ['time.google.com'])
        timezone = time_config.get('timezone', 'Asia/Seoul')
        
        for node in self.all_nodes:
            hostname = node['hostname']
            os_type = node.get('os_type', 'ubuntu22')
            
            print(f"    ⏰ {hostname}: NTP 설정 중...")
            
            # 타임존 설정
            self.ssh_manager.execute_command(
                hostname,
                f"timedatectl set-timezone {timezone} 2>/dev/null || true",
                show_output=False
            )
            
            # systemd-timesyncd 또는 chrony 사용
            if 'ubuntu' in os_type or 'debian' in os_type:
                # systemd-timesyncd
                self.ssh_manager.execute_command(
                    hostname,
                    "apt install -y systemd-timesyncd 2>/dev/null || true",
                    show_output=False
                )
                
                self.ssh_manager.execute_command(
                    hostname,
                    "systemctl restart systemd-timesyncd && systemctl enable systemd-timesyncd",
                    show_output=False
                )
            else:
                # chrony (CentOS/RHEL)
                self.ssh_manager.execute_command(
                    hostname,
                    "yum install -y chrony 2>/dev/null || true",
                    show_output=False
                )
                
                self.ssh_manager.execute_command(
                    hostname,
                    "systemctl restart chronyd && systemctl enable chronyd",
                    show_output=False
                )
        
        print(f"    ✅ NTP 설정 완료")
        return True
    
    def install_dependencies(self) -> bool:
        """필수 패키지 설치"""
        print("  📦 필수 패키지 설치 중...")
        
        for node in self.all_nodes:
            hostname = node['hostname']
            os_type = node.get('os_type', 'ubuntu22')
            
            print(f"    📦 {hostname}: 패키지 설치 중...")
            
            if 'ubuntu' in os_type or 'debian' in os_type:
                packages = [
                    "build-essential", "gcc", "g++", "make",
                    "libmunge-dev", "libmunge2",
                    "libpam0g-dev", "libreadline-dev",
                    "libssl-dev", "libnuma-dev",
                    "libhwloc-dev",
                    "python3", "python3-pip",
                    "rsync", "wget", "curl", "vim",
                    "munge", "nfs-common"
                ]
                
                self.ssh_manager.execute_command(
                    hostname,
                    f"apt update && apt install -y {' '.join(packages)}",
                    show_output=False,
                    timeout=600
                )
            else:
                # CentOS/RHEL
                packages = [
                    "gcc", "gcc-c++", "make",
                    "munge", "munge-devel", "munge-libs",
                    "pam-devel", "readline-devel",
                    "openssl-devel", "numactl-devel",
                    "hwloc-devel",
                    "python3", "python3-pip",
                    "rsync", "wget", "curl", "vim",
                    "nfs-utils", "rpcbind"
                ]
                
                self.ssh_manager.execute_command(
                    hostname,
                    f"yum install -y {' '.join(packages)}",
                    show_output=False,
                    timeout=600
                )
        
        print(f"    ✅ 필수 패키지 설치 완료")
        return True
    
    def setup_munge(self) -> bool:
        """Munge 인증 시스템 설정"""
        print("  🔐 Munge 설정 중...")
        
        # munge_validator import를 여기서 함
        import munge_validator
        
        validator = munge_validator.MungeValidator(self.config, self.ssh_manager)
        return validator.setup_and_validate_munge()
    
    def setup_nfs(self) -> bool:
        """NFS 공유 스토리지 설정"""
        print("  💾 NFS 공유 스토리지 설정 중...")
        
        nfs_config = self.config.get('shared_storage', {})
        if not nfs_config:
            print("    ⏭️  NFS 설정 건너뜀")
            return True
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        nfs_server = nfs_config.get('nfs_server', controller['ip_address'])
        mount_points = nfs_config.get('mount_points', [])
        
        # 1. 컨트롤러를 NFS 서버로 설정
        print(f"    📤 {controller_hostname}: NFS 서버 설정 중...")
        
        os_type = controller.get('os_type', 'ubuntu22')
        
        if 'ubuntu' in os_type:
            self.ssh_manager.execute_command(
                controller_hostname,
                "apt install -y nfs-kernel-server",
                show_output=False
            )
        else:
            self.ssh_manager.execute_command(
                controller_hostname,
                "yum install -y nfs-utils rpcbind",
                show_output=False
            )
        
        # 2. Export 디렉토리 생성 및 /etc/exports 설정
        exports_lines = []
        
        for mount in mount_points:
            source = mount['source']
            options = mount.get('options', 'rw,sync,no_root_squash')
            
            # 디렉토리 생성
            self.ssh_manager.execute_command(
                controller_hostname,
                f"mkdir -p {source} && chmod 755 {source}",
                show_output=False
            )
            
            # exports 라인 추가
            network = self.config.get('network', {}).get('management_network', '192.168.0.0/24')
            exports_lines.append(f"{source} {network}({options})")
        
        # /etc/exports 파일 생성
        exports_content = '\\n'.join(exports_lines)
        self.ssh_manager.execute_command(
            controller_hostname,
            f"echo '{exports_content}' >> /etc/exports",
            show_output=False
        )
        
        # NFS 서비스 재시작
        self.ssh_manager.execute_command(
            controller_hostname,
            "exportfs -ra && systemctl restart nfs-server && systemctl enable nfs-server 2>/dev/null || systemctl restart nfs-kernel-server && systemctl enable nfs-kernel-server 2>/dev/null",
            show_output=False
        )
        
        # 3. 계산 노드에서 마운트
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            print(f"    📥 {hostname}: NFS 마운트 중...")
            
            for mount in mount_points:
                source = mount['source']
                target = mount['target']
                options = mount.get('options', 'rw,sync,hard,intr')
                
                # 마운트 포인트 생성
                self.ssh_manager.execute_command(
                    hostname,
                    f"mkdir -p {target}",
                    show_output=False
                )
                
                # 마운트
                self.ssh_manager.execute_command(
                    hostname,
                    f"mount -t nfs -o {options} {nfs_server}:{source} {target} 2>/dev/null || true",
                    show_output=False
                )
                
                # /etc/fstab에 추가 (재부팅 후에도 자동 마운트)
                fstab_line = f"{nfs_server}:{source} {target} nfs {options} 0 0"
                self.ssh_manager.execute_command(
                    hostname,
                    f"grep -q '{nfs_server}:{source}' /etc/fstab || echo '{fstab_line}' >> /etc/fstab",
                    show_output=False
                )
        
        print(f"    ✅ NFS 설정 완료")
        return True
    
    def generate_slurm_conf(self) -> bool:
        """slurm.conf 파일 생성"""
        print("  📝 slurm.conf 생성 중...")
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        cluster_name = self.config['cluster_info']['cluster_name']
        
        # slurm.conf 내용 생성
        slurm_conf = f"""# slurm.conf - Auto-generated by KooSlurmInstallAutomation
ClusterName={cluster_name}
SlurmctldHost={controller_hostname}

# Authentication
AuthType=auth/munge
CryptoType=crypto/munge

# Reboot Program
RebootProgram={self.config['slurm_config'].get('reboot_program', '/sbin/reboot')}

# Scheduler
SchedulerType={self.config['slurm_config']['scheduler']['type']}
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

# Logging
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmSchedLogFile=/var/log/slurm/slurmsched.log

# State
StateSaveLocation=/var/spool/slurm/state
SlurmdSpoolDir=/var/spool/slurm/d

# Timeouts
SlurmctldTimeout=300
SlurmdTimeout=300
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0

# Process Tracking
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup

# Accounting
AccountingStorageType={self.config['slurm_config']['accounting']['storage_type']}
JobAcctGatherType=jobacct_gather/cgroup

# Compute Nodes
"""
        
        # 계산 노드 추가
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            ip_address = node.get('ip_address', hostname)
            hardware = node['hardware']
            cpus = hardware.get('cpus', 1)
            sockets = hardware.get('sockets', 1)
            cores_per_socket = hardware.get('cores_per_socket', cpus // sockets)
            threads_per_core = hardware.get('threads_per_core', 1)
            memory_mb = hardware.get('memory_mb', 1024)
            
            slurm_conf += f"NodeName={hostname} NodeAddr={ip_address} CPUs={cpus} Sockets={sockets} CoresPerSocket={cores_per_socket} ThreadsPerCore={threads_per_core} RealMemory={memory_mb} State=UNKNOWN\n"
        
        # 파티션 추가
        slurm_conf += "\n# Partitions\n"
        for partition in self.config['slurm_config']['partitions']:
            name = partition['name']
            nodes = partition['nodes']
            default = "YES" if partition.get('default', False) else "NO"
            max_time = partition.get('max_time', 'INFINITE')
            state = partition.get('state', 'UP')
            
            slurm_conf += f"PartitionName={name} Nodes={nodes} Default={default} MaxTime={max_time} State={state}\n"
        
        # 컨트롤러에 디렉토리 생성 및 slurm.conf 업로드
        config_path = self.config['slurm_config']['config_path']
        
        print(f"    📁 컨트롤러 디렉토리 생성: {config_path}")
        self.ssh_manager.execute_command(
            controller_hostname,
            f"sudo mkdir -p {config_path} /var/log/slurm /var/spool/slurm/state",
            show_output=False
        )
        
        print(f"    📝 컨트롤러에 slurm.conf 생성")
        # 파일 내용을 임시 파일로 저장 후 복사
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.conf') as f:
            f.write(slurm_conf)
            temp_file = f.name
        
        try:
            # 컨트롤러로 파일 업로드
            self.ssh_manager.connections[controller_hostname].upload_file(
                temp_file, f"/tmp/slurm.conf"
            )
            # sudo로 이동 및 권한 설정
            self.ssh_manager.execute_command(
                controller_hostname,
                f"sudo mv /tmp/slurm.conf {config_path}/slurm.conf && sudo chown slurm:slurm {config_path}/slurm.conf && sudo chmod 644 {config_path}/slurm.conf",
                show_output=False
            )
        except:
            # 업로드 실패시 echo 명령어 사용
            self.ssh_manager.execute_command(
                controller_hostname,
                f"sudo bash -c 'cat > {config_path}/slurm.conf << \'EOFSLURM\'\n{slurm_conf}\nEOFSLURM' && sudo chown slurm:slurm {config_path}/slurm.conf && sudo chmod 644 {config_path}/slurm.conf",
                show_output=False
            )
        finally:
            import os
            os.unlink(temp_file)
        
        # 모든 계산 노드에 복사 (IP 주소 사용)
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            ip_address = node.get('ip_address', hostname)
            
            print(f"    📤 {hostname} ({ip_address})에 복사 중...")
            
            # 1. 대상 노드에 디렉토리 생성
            self.ssh_manager.execute_command(
                hostname,
                f"sudo mkdir -p {config_path} /var/log/slurm /var/spool/slurm/d && sudo chown -R slurm:slurm /var/log/slurm /var/spool/slurm",
                show_output=False,
                timeout=10
            )
            
            # 2. 컨트롤러에서 scp로 복사 (IP 주소 사용, SSH 옵션 추가)
            self.ssh_manager.execute_command(
                controller_hostname,
                f"scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 {config_path}/slurm.conf {ip_address}:/tmp/slurm.conf 2>&1",
                show_output=False,
                timeout=30
            )
            
            # 3. sudo로 이동 및 권한 설정
            self.ssh_manager.execute_command(
                hostname,
                f"sudo mv /tmp/slurm.conf {config_path}/slurm.conf && sudo chown slurm:slurm {config_path}/slurm.conf && sudo chmod 644 {config_path}/slurm.conf",
                show_output=False
            )
        
        print(f"    ✅ slurm.conf 생성 완료")
        return True
    
    def setup_cgroup(self) -> bool:
        """cgroup 설정"""
        print("  ⚙️  cgroup 설정 중...")
        
        cgroup_conf = """CgroupAutomount=yes
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
"""
        
        config_path = self.config['slurm_config']['config_path']
        
        for node in self.all_nodes:
            hostname = node['hostname']
            
            self.ssh_manager.execute_command(
                hostname,
                f"sudo bash -c 'cat > {config_path}/cgroup.conf << \'EOF\'\n{cgroup_conf}\nEOF' && sudo chown slurm:slurm {config_path}/cgroup.conf && sudo chmod 644 {config_path}/cgroup.conf",
                show_output=False
            )
        
        print(f"    ✅ cgroup 설정 완료")
        return True
    
    def setup_environment(self) -> bool:
        """환경변수 설정"""
        print("  🌐 환경변수 설정 중...")
        
        install_path = self.config['slurm_config']['install_path']
        
        env_script = f"""# Slurm Environment
export PATH={install_path}/bin:{install_path}/sbin:$PATH
export LD_LIBRARY_PATH={install_path}/lib:$LD_LIBRARY_PATH
export MANPATH={install_path}/share/man:$MANPATH
"""
        
        for node in self.all_nodes:
            hostname = node['hostname']
            
            self.ssh_manager.execute_command(
                hostname,
                f"sudo bash -c 'cat > /etc/profile.d/slurm.sh << \'EOF\'\n{env_script}\nEOF' && sudo chmod 644 /etc/profile.d/slurm.sh",
                show_output=False
            )
        
        print(f"    ✅ 환경변수 설정 완료")
        return True


def main():
    """테스트 메인"""
    import yaml
    import argparse

    # 커맨드라인 인자 파싱
    parser = argparse.ArgumentParser(description='Slurm 완전 자동 설치 보완 모듈')
    parser.add_argument('--only-hosts', action='store_true',
                        help='/etc/hosts 설정만 수행 (SSH 키 설정 포함)')
    parser.add_argument('--skip-munge', action='store_true',
                        help='Munge 설정 건너뛰기 (이미 설치된 경우)')
    parser.add_argument('--skip-slurm-conf', action='store_true',
                        help='slurm.conf 생성 건너뛰기 (이미 생성된 경우)')
    parser.add_argument('--skip-cgroup', action='store_true',
                        help='cgroup 설정 건너뛰기 (이미 설정된 경우)')
    parser.add_argument('--skip-nfs', action='store_true',
                        help='NFS 설정 건너뛰기')
    args = parser.parse_args()

    config_file = Path("my_cluster.yaml")
    if not config_file.exists():
        print("❌ my_cluster.yaml 파일을 찾을 수 없습니다.")
        return

    with open(config_file, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)

    # SSHManager 생성 및 노드 추가
    ssh_mgr = ssh_manager.SSHManager()

    # 모든 노드 추가
    all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']

    # viz-node이 있으면 추가
    if 'viz_nodes' in config['nodes']:
        all_nodes += config['nodes']['viz_nodes']

    for node in all_nodes:
        ssh_mgr.add_node(node)

    # 연결
    ssh_mgr.connect_all_nodes()

    setup = SlurmAutoSetup(config, ssh_mgr)

    # --only-hosts 옵션: /etc/hosts 설정만 수행
    if args.only_hosts:
        print("\n🔧 /etc/hosts 설정만 수행합니다...")
        setup.setup_ssh_keys()  # SSH 키 설정 (내부에 /etc/hosts 포함)
    else:
        # 전체 설정 수행 (선택적으로 단계 건너뛰기)
        print("\n🔧 Slurm 완전 자동 설치 시작...")

        steps = [
            ("SSH 키 자동 설정", setup.setup_ssh_keys, False),
            ("방화벽 설정", setup.configure_firewall, False),
            ("SELinux 설정", setup.configure_selinux, False),
            ("NTP 시간 동기화", setup.setup_ntp, False),
            ("필수 패키지 설치", setup.install_dependencies, False),
            ("Munge 인증 설정", setup.setup_munge, args.skip_munge),
            ("NFS 공유 스토리지", setup.setup_nfs, args.skip_nfs),
            ("slurm.conf 생성", setup.generate_slurm_conf, args.skip_slurm_conf),
            ("cgroup 설정", setup.setup_cgroup, args.skip_cgroup),
            ("환경변수 설정", setup.setup_environment, False),
        ]

        for step_name, step_func, skip in steps:
            if skip:
                print(f"\n⏭️  {step_name} (건너뜀)")
                continue

            print(f"\n📌 {step_name}...")
            try:
                if not step_func():
                    print(f"  ⚠️  {step_name} 실패 (계속 진행)")
            except Exception as e:
                print(f"  ❌ {step_name} 오류: {e}")

        print("\n✅ Slurm 완전 자동 설치 완료!")

    # 연결 종료
    ssh_mgr.disconnect_all()


if __name__ == '__main__':
    main()
