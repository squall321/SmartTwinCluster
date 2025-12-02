#!/usr/bin/env python3
"""
Slurm 설치 자동화 - OS 관리
운영체제별 패키지 설치 및 시스템 설정을 담당하는 모듈
"""

from typing import Dict, List, Optional, Tuple, Any, TYPE_CHECKING
from abc import ABC, abstractmethod
import re

if TYPE_CHECKING:
    from ssh_manager import SSHManager


class OSManager(ABC):
    """OS 관리 추상 클래스"""
    
    def __init__(self, ssh_manager: SSHManager, hostname: str):
        self.ssh_manager = ssh_manager
        self.hostname = hostname
        self.os_info = None
    
    @abstractmethod
    def detect_os(self) -> Dict[str, str]:
        """OS 정보 감지"""
        pass
    
    @abstractmethod
    def update_system(self) -> bool:
        """시스템 업데이트"""
        pass
    
    @abstractmethod
    def install_packages(self, packages: List[str]) -> bool:
        """패키지 설치"""
        pass
    
    @abstractmethod
    def install_development_tools(self) -> bool:
        """개발 도구 설치"""
        pass
    
    @abstractmethod
    def configure_firewall(self, ports: Dict[str, int]) -> bool:
        """방화벽 설정"""
        pass
    
    @abstractmethod
    def create_user(self, username: str, uid: int, gid: int, groups: List[str] = None) -> bool:
        """사용자 생성"""
        pass
    
    @abstractmethod
    def configure_nfs_client(self, mount_points: List[Dict[str, str]]) -> bool:
        """NFS 클라이언트 설정"""
        pass
    
    def execute_command(self, command: str, timeout: int = 300) -> Tuple[int, str, str]:
        """명령 실행"""
        return self.ssh_manager.execute_command(self.hostname, command, timeout)
    
    def check_command_exists(self, command: str) -> bool:
        """명령어 존재 여부 확인"""
        exit_code, _, _ = self.execute_command(f"which {command}", show_output=False)
        return exit_code == 0
    
    def is_service_running(self, service_name: str) -> bool:
        """서비스 실행 상태 확인"""
        exit_code, _, _ = self.execute_command(
            f"systemctl is-active {service_name}", show_output=False
        )
        return exit_code == 0
    
    def enable_service(self, service_name: str) -> bool:
        """서비스 활성화 및 시작"""
        exit_code1, _, _ = self.execute_command(f"systemctl enable {service_name}")
        exit_code2, _, _ = self.execute_command(f"systemctl start {service_name}")
        return exit_code1 == 0 and exit_code2 == 0
    
    def configure_time_sync(self, ntp_servers: List[str] = None) -> bool:
        """시간 동기화 설정"""
        if not ntp_servers:
            ntp_servers = ["pool.ntp.org", "time.google.com"]
        
        # Chrony 설정
        chrony_conf = "# Slurm cluster NTP configuration\n"
        for server in ntp_servers:
            chrony_conf += f"server {server} iburst\n"
        
        chrony_conf += """
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
"""
        
        # Chrony 설정 파일 업로드
        exit_code, _, _ = self.execute_command(
            f"echo '{chrony_conf}' > /etc/chrony.conf"
        )
        
        if exit_code == 0:
            return self.enable_service("chronyd")
        
        return False


class CentOSManager(OSManager):
    """CentOS/RHEL 계열 OS 관리"""
    
    def __init__(self, ssh_manager: SSHManager, hostname: str):
        super().__init__(ssh_manager, hostname)
        self.package_manager = "yum"
        self.major_version = None
    
    def detect_os(self) -> Dict[str, str]:
        """CentOS/RHEL OS 정보 감지"""
        exit_code, stdout, _ = self.execute_command("cat /etc/os-release")
        
        if exit_code != 0:
            raise Exception(f"{self.hostname}: OS 정보를 가져올 수 없음")
        
        os_info = {}
        for line in stdout.split('\n'):
            if '=' in line:
                key, value = line.split('=', 1)
                os_info[key] = value.strip('"')
        
        # CentOS 8+ 또는 RHEL 8+에서는 dnf 사용
        if 'VERSION_ID' in os_info:
            version = os_info['VERSION_ID'].split('.')[0]
            self.major_version = int(version)
            if self.major_version >= 8:
                self.package_manager = "dnf"
        
        self.os_info = os_info
        return os_info
    
    def update_system(self) -> bool:
        """시스템 업데이트"""
        print(f"🔄 {self.hostname}: 시스템 업데이트 중...")
        exit_code, _, _ = self.execute_command(f"{self.package_manager} update -y")
        return exit_code == 0
    
    def install_packages(self, packages: List[str]) -> bool:
        """패키지 설치"""
        if not packages:
            return True
        
        package_list = " ".join(packages)
        print(f"📦 {self.hostname}: 패키지 설치 - {package_list}")
        
        exit_code, _, _ = self.execute_command(
            f"{self.package_manager} install -y {package_list}"
        )
        return exit_code == 0
    
    def install_development_tools(self) -> bool:
        """개발 도구 설치"""
        print(f"🛠️  {self.hostname}: 개발 도구 설치 중...")
        
        # 기본 개발 도구 그룹
        if self.major_version and self.major_version >= 8:
            group_install_cmd = f"{self.package_manager} groupinstall -y 'Development Tools'"
        else:
            group_install_cmd = f"{self.package_manager} groupinstall -y 'Development tools'"
        
        exit_code1, _, _ = self.execute_command(group_install_cmd)
        
        # 추가 필수 패키지
        additional_packages = [
            "gcc", "gcc-c++", "make", "cmake", "autoconf", "automake", "libtool",
            "git", "wget", "curl", "vim", "htop", "rsync", "nfs-utils",
            "epel-release", "python3", "python3-devel"
        ]
        
        exit_code2 = 0
        if additional_packages:
            exit_code2, _, _ = self.execute_command(
                f"{self.package_manager} install -y {' '.join(additional_packages)}"
            )
        
        return exit_code1 == 0 and exit_code2 == 0
    
    def configure_firewall(self, ports: Dict[str, int]) -> bool:
        """방화벽 설정"""
        print(f"🔥 {self.hostname}: 방화벽 설정 중...")
        
        # firewalld 설치 및 활성화
        self.install_packages(["firewalld"])
        self.enable_service("firewalld")
        
        # 포트 열기
        success = True
        for service, port in ports.items():
            exit_code, _, _ = self.execute_command(
                f"firewall-cmd --permanent --add-port={port}/tcp"
            )
            if exit_code != 0:
                success = False
                print(f"⚠️  {self.hostname}: {service} 포트 {port} 설정 실패")
        
        # 방화벽 설정 재로드
        exit_code, _, _ = self.execute_command("firewall-cmd --reload")
        
        return success and exit_code == 0
    
    def create_user(self, username: str, uid: int, gid: int, groups: List[str] = None) -> bool:
        """사용자 생성"""
        print(f"👤 {self.hostname}: 사용자 생성 - {username}")
        
        # 그룹 생성
        self.execute_command(f"groupadd -g {gid} {username}", show_output=False)
        
        # 사용자 생성
        user_cmd = f"useradd -u {uid} -g {gid} -m -s /bin/bash {username}"
        exit_code, _, _ = self.execute_command(user_cmd)
        
        if exit_code != 0:
            return False
        
        # 추가 그룹에 사용자 추가
        if groups:
            for group in groups:
                # 그룹이 없으면 생성
                self.execute_command(f"groupadd {group}", show_output=False)
                # 사용자를 그룹에 추가
                self.execute_command(f"usermod -aG {group} {username}")
        
        return True
    
    def configure_nfs_client(self, mount_points: List[Dict[str, str]]) -> bool:
        """NFS 클라이언트 설정"""
        print(f"📁 {self.hostname}: NFS 클라이언트 설정 중...")
        
        # NFS 유틸리티 설치
        if not self.install_packages(["nfs-utils"]):
            return False
        
        # NFS 클라이언트 서비스 활성화
        self.enable_service("rpcbind")
        self.enable_service("nfs-client.target")
        
        # 마운트 포인트 생성 및 fstab 설정
        fstab_entries = []
        
        for mount in mount_points:
            source = mount['source']
            target = mount['target']
            options = mount.get('options', 'rw,sync,hard,intr')
            
            # 마운트 포인트 디렉토리 생성
            self.execute_command(f"mkdir -p {target}")
            
            # fstab 엔트리 생성
            fstab_entry = f"{source} {target} nfs {options} 0 0"
            fstab_entries.append(fstab_entry)
        
        if fstab_entries:
            # fstab 백업
            self.execute_command("cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)")
            
            # fstab에 추가
            for entry in fstab_entries:
                self.execute_command(f"echo '{entry}' >> /etc/fstab")
        
        return True


class UbuntuManager(OSManager):
    """Ubuntu 계열 OS 관리"""
    
    def __init__(self, ssh_manager: SSHManager, hostname: str):
        super().__init__(ssh_manager, hostname)
        self.package_manager = "apt"
    
    def detect_os(self) -> Dict[str, str]:
        """Ubuntu OS 정보 감지"""
        exit_code, stdout, _ = self.execute_command("cat /etc/os-release")
        
        if exit_code != 0:
            raise Exception(f"{self.hostname}: OS 정보를 가져올 수 없음")
        
        os_info = {}
        for line in stdout.split('\n'):
            if '=' in line:
                key, value = line.split('=', 1)
                os_info[key] = value.strip('"')
        
        self.os_info = os_info
        return os_info
    
    def update_system(self) -> bool:
        """시스템 업데이트"""
        print(f"🔄 {self.hostname}: 시스템 업데이트 중...")
        
        # 패키지 목록 업데이트
        exit_code1, _, _ = self.execute_command("apt update")
        
        # 시스템 업그레이드
        exit_code2, _, _ = self.execute_command("DEBIAN_FRONTEND=noninteractive apt upgrade -y")
        
        return exit_code1 == 0 and exit_code2 == 0
    
    def install_packages(self, packages: List[str]) -> bool:
        """패키지 설치"""
        if not packages:
            return True
        
        package_list = " ".join(packages)
        print(f"📦 {self.hostname}: 패키지 설치 - {package_list}")
        
        exit_code, _, _ = self.execute_command(
            f"DEBIAN_FRONTEND=noninteractive apt install -y {package_list}"
        )
        return exit_code == 0
    
    def install_development_tools(self) -> bool:
        """개발 도구 설치"""
        print(f"🛠️  {self.hostname}: 개발 도구 설치 중...")
        
        # 필수 개발 도구 패키지
        dev_packages = [
            "build-essential", "gcc", "g++", "make", "cmake", "autoconf", "automake", "libtool",
            "git", "wget", "curl", "vim", "htop", "rsync", "nfs-common",
            "python3", "python3-dev", "python3-pip", "pkg-config",
            "libssl-dev", "libpam0g-dev", "libmysqlclient-dev", "libmariadb-dev-compat"
        ]
        
        return self.install_packages(dev_packages)
    
    def configure_firewall(self, ports: Dict[str, int]) -> bool:
        """방화벽 설정 (UFW 사용)"""
        print(f"🔥 {self.hostname}: 방화벽 설정 중...")
        
        # UFW 설치
        self.install_packages(["ufw"])
        
        # 기본 정책 설정
        self.execute_command("ufw --force reset")
        self.execute_command("ufw default deny incoming")
        self.execute_command("ufw default allow outgoing")
        
        # SSH 포트 허용 (방화벽 활성화 전에 반드시 필요)
        self.execute_command("ufw allow ssh")
        
        # 지정된 포트들 열기
        success = True
        for service, port in ports.items():
            exit_code, _, _ = self.execute_command(f"ufw allow {port}/tcp")
            if exit_code != 0:
                success = False
                print(f"⚠️  {self.hostname}: {service} 포트 {port} 설정 실패")
        
        # 방화벽 활성화
        exit_code, _, _ = self.execute_command("ufw --force enable")
        
        return success and exit_code == 0
    
    def create_user(self, username: str, uid: int, gid: int, groups: List[str] = None) -> bool:
        """사용자 생성"""
        print(f"👤 {self.hostname}: 사용자 생성 - {username}")
        
        # 그룹 생성
        self.execute_command(f"groupadd -g {gid} {username}", show_output=False)
        
        # 사용자 생성
        user_cmd = f"useradd -u {uid} -g {gid} -m -s /bin/bash {username}"
        exit_code, _, _ = self.execute_command(user_cmd)
        
        if exit_code != 0:
            return False
        
        # 추가 그룹에 사용자 추가
        if groups:
            for group in groups:
                # 그룹이 없으면 생성
                self.execute_command(f"groupadd {group}", show_output=False)
                # 사용자를 그룹에 추가
                self.execute_command(f"usermod -aG {group} {username}")
        
        return True
    
    def configure_nfs_client(self, mount_points: List[Dict[str, str]]) -> bool:
        """NFS 클라이언트 설정"""
        print(f"📁 {self.hostname}: NFS 클라이언트 설정 중...")
        
        # NFS 유틸리티 설치
        if not self.install_packages(["nfs-common"]):
            return False
        
        # NFS 클라이언트 서비스 활성화
        self.enable_service("rpcbind")
        
        # 마운트 포인트 생성 및 fstab 설정
        fstab_entries = []
        
        for mount in mount_points:
            source = mount['source']
            target = mount['target']
            options = mount.get('options', 'rw,sync,hard,intr')
            
            # 마운트 포인트 디렉토리 생성
            self.execute_command(f"mkdir -p {target}")
            
            # fstab 엔트리 생성
            fstab_entry = f"{source} {target} nfs {options} 0 0"
            fstab_entries.append(fstab_entry)
        
        if fstab_entries:
            # fstab 백업
            self.execute_command("cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)")
            
            # fstab에 추가
            for entry in fstab_entries:
                self.execute_command(f"echo '{entry}' >> /etc/fstab")
        
        return True


class OSManagerFactory:
    """OS 관리자 팩토리 클래스"""
    
    @staticmethod
    def create_manager(ssh_manager: SSHManager, hostname: str, os_type: str) -> OSManager:
        """OS 타입에 따른 관리자 인스턴스 생성"""
        
        os_type_lower = os_type.lower()
        
        if os_type_lower in ['centos7', 'centos8', 'centos9', 'rhel7', 'rhel8', 'rhel9']:
            return CentOSManager(ssh_manager, hostname)
        elif os_type_lower in ['ubuntu18', 'ubuntu20', 'ubuntu22']:
            return UbuntuManager(ssh_manager, hostname)
        else:
            raise ValueError(f"지원하지 않는 OS 타입: {os_type}")
    
    @staticmethod
    def auto_detect_os(ssh_manager: SSHManager, hostname: str) -> OSManager:
        """OS 자동 감지 후 관리자 생성"""
        
        # OS 정보 가져오기
        exit_code, stdout, _ = ssh_manager.execute_command(
            hostname, "cat /etc/os-release", show_output=False
        )
        
        if exit_code != 0:
            raise Exception(f"{hostname}: OS 정보를 가져올 수 없음")
        
        # OS 타입 판단
        stdout_lower = stdout.lower()
        
        if 'centos' in stdout_lower or 'red hat' in stdout_lower:
            return CentOSManager(ssh_manager, hostname)
        elif 'ubuntu' in stdout_lower:
            return UbuntuManager(ssh_manager, hostname)
        else:
            raise ValueError(f"{hostname}: 지원하지 않는 OS 타입")


def main():
    """테스트 메인 함수"""
    from ssh_manager import SSHManager
    
    # 테스트용 노드 설정
    test_nodes = [
        {
            'hostname': 'localhost',
            'ssh_user': 'root',
            'ssh_key_path': '~/.ssh/id_rsa',
            'os_type': 'centos8'
        }
    ]
    
    ssh_manager = SSHManager()
    
    # 노드 추가 및 연결
    for node in test_nodes:
        ssh_manager.add_node(node)
    
    if not ssh_manager.connect_all_nodes():
        print("SSH 연결 실패")
        return
    
    # OS 관리자 생성 및 테스트
    for node in test_nodes:
        hostname = node['hostname']
        os_type = node['os_type']
        
        try:
            # OS 관리자 생성
            os_manager = OSManagerFactory.create_manager(ssh_manager, hostname, os_type)
            
            # OS 정보 감지
            os_info = os_manager.detect_os()
            print(f"OS 정보: {os_info.get('PRETTY_NAME', 'Unknown')}")
            
            # 개발 도구 설치 테스트 (주석 처리 - 실제 설치는 시간이 오래 걸림)
            # os_manager.install_development_tools()
            
        except Exception as e:
            print(f"OS 관리자 테스트 실패: {e}")
    
    ssh_manager.disconnect_all()


if __name__ == "__main__":
    main()
