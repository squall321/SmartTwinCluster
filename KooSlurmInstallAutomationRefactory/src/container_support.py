#!/usr/bin/env python3
"""
컨테이너 지원 모듈 - Apptainer, Singularity, Docker
advanced_features.py에서 import하여 사용
"""

import time
from typing import Dict, Any
from ssh_manager import SSHManager


class ContainerSupport:
    """컨테이너 지원 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
    
    def setup_container_support(self) -> bool:
        """컨테이너 지원 설정"""
        print("\n🐳 컨테이너 지원 설정 중...")
        
        container_config = self.config.get('container_support', {})
        
        # Apptainer 설정 (우선순위 1)
        apptainer_config = container_config.get('apptainer', {})
        if apptainer_config.get('enabled', False):
            print("📦 Apptainer 설치를 선택하셨습니다 (권장)")
            if not self.setup_apptainer(apptainer_config):
                return False
        
        # Singularity 설정 (레거시 지원)
        singularity_config = container_config.get('singularity', {})
        if singularity_config.get('enabled', False):
            print("⚠️  Singularity는 레거시입니다. Apptainer 사용을 권장합니다.")
            if not self.setup_singularity(singularity_config):
                return False
        
        # Docker 설정
        docker_config = container_config.get('docker', {})
        if docker_config.get('enabled', False):
            if not self.setup_docker(docker_config):
                return False
        
        return True
    
    def setup_apptainer(self, apptainer_config: Dict[str, Any]) -> bool:
        """Apptainer 설치 (Singularity의 후속 프로젝트)"""
        print("📦 모든 노드에 Apptainer 설치 중...")
        
        version = apptainer_config.get('version', '1.2.5')
        install_path = apptainer_config.get('install_path', '/usr/local')
        cache_path = apptainer_config.get('cache_path', '/tmp/apptainer')
        image_path = apptainer_config.get('image_path', '/share/apptainer')
        bind_paths = apptainer_config.get('bind_paths', ['/home', '/share'])
        
        for node in self.all_nodes:
            hostname = node['hostname']
            print(f"  📦 {hostname}: Apptainer 설치 시작...")
            
            # Go 설치 (Apptainer 빌드에 필요)
            print(f"     ⚙️  Go 설치 중...")
            go_commands = [
                "cd /tmp",
                "wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz 2>/dev/null || true",
                "rm -rf /usr/local/go",
                "tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz 2>/dev/null || true"
            ]
            
            for cmd in go_commands:
                self.ssh_manager.execute_command(hostname, cmd, show_output=False)
            
            # 의존성 패키지 설치
            print(f"     📚 의존성 패키지 설치 중...")
            dep_cmd = (
                "yum groupinstall -y 'Development Tools' 2>/dev/null || "
                "apt install -y build-essential 2>/dev/null; "
                "yum install -y openssl-devel libuuid-devel libseccomp-devel wget squashfs-tools cryptsetup 2>/dev/null || "
                "apt install -y libssl-dev uuid-dev libseccomp-dev wget squashfs-tools cryptsetup-bin libglib2.0-dev 2>/dev/null"
            )
            self.ssh_manager.execute_command(hostname, dep_cmd, show_output=False, timeout=600)
            
            # Apptainer 다운로드 및 컴파일
            print(f"     🔨 Apptainer 컴파일 중 (시간이 걸릴 수 있습니다)...")
            apptainer_build_script = f"""
export PATH=/usr/local/go/bin:$PATH
cd /tmp
rm -rf apptainer-{version}*
wget -q https://github.com/apptainer/apptainer/releases/download/v{version}/apptainer-{version}.tar.gz
tar -xzf apptainer-{version}.tar.gz
cd apptainer-{version}
./mconfig --prefix={install_path}
make -C builddir -j$(nproc)
make -C builddir install
"""
            
            exit_code, stdout, stderr = self.ssh_manager.execute_command(
                hostname, 
                apptainer_build_script,
                timeout=1800,
                show_output=False
            )
            
            if exit_code != 0:
                print(f"     ⚠️  {hostname}: Apptainer 컴파일 중 경고 발생")
                if stderr and len(stderr) > 0:
                    print(f"          오류: {stderr[:300]}")
            
            # Apptainer 디렉토리 설정
            print(f"     📁 디렉토리 설정 중...")
            dir_commands = [
                f"mkdir -p {cache_path}",
                f"mkdir -p {image_path}",
                f"chmod 755 {cache_path}",
                f"chmod 755 {image_path}"
            ]
            
            for cmd in dir_commands:
                self.ssh_manager.execute_command(hostname, cmd, show_output=False)
            
            # 환경변수 설정
            env_setup = f"""
cat > /etc/profile.d/apptainer.sh << 'EOF'
export PATH={install_path}/bin:$PATH
export APPTAINER_CACHEDIR={cache_path}
export APPTAINER_TMPDIR={cache_path}/tmp
EOF
chmod 644 /etc/profile.d/apptainer.sh
"""
            self.ssh_manager.execute_command(hostname, env_setup, show_output=False)
            
            # Apptainer 설정 파일 수정 (bind paths)
            if bind_paths:
                bind_config = f"""
if [ -f {install_path}/etc/apptainer/apptainer.conf ]; then
    # 기존 bind path 주석 처리
    sed -i 's/^bind path/#bind path/g' {install_path}/etc/apptainer/apptainer.conf
    # 새로운 bind paths 추가
    echo "" >> {install_path}/etc/apptainer/apptainer.conf
    echo "# Custom bind paths" >> {install_path}/etc/apptainer/apptainer.conf
    echo "bind path = {', '.join(bind_paths)}" >> {install_path}/etc/apptainer/apptainer.conf
fi
"""
                self.ssh_manager.execute_command(hostname, bind_config, show_output=False)
            
            print(f"  ✅ {hostname}: Apptainer 설치 완료")
        
        # 설치 검증
        print("\n🧪 Apptainer 설치 검증 중...")
        test_node = self.config['nodes']['controller']['hostname']
        exit_code, stdout, stderr = self.ssh_manager.execute_command(
            test_node,
            f"source /etc/profile.d/apptainer.sh && {install_path}/bin/apptainer --version",
            show_output=False
        )
        
        if exit_code == 0 and stdout:
            print(f"✅ Apptainer 버전: {stdout.strip()}")
            print(f"✅ 설치 경로: {install_path}/bin/apptainer")
            print(f"✅ 캐시 디렉토리: {cache_path}")
            print(f"✅ 이미지 디렉토리: {image_path}")
        else:
            print(f"⚠️  Apptainer 검증 실패")
            if stderr:
                print(f"   오류: {stderr[:200]}")
        
        print("\n💡 사용 예시:")
        print(f"   apptainer pull docker://ubuntu:22.04")
        print(f"   apptainer run ubuntu_22.04.sif")
        
        return True
    
    def setup_singularity(self, singularity_config: Dict[str, Any]) -> bool:
        """Singularity 설치 (레거시 지원)"""
        print("⚠️  경고: Singularity는 레거시 프로젝트입니다.")
        print("   Apptainer 사용을 강력히 권장합니다.")
        print("📦 모든 노드에 Singularity 설치 중...")
        
        version = singularity_config.get('version', '3.10.0')
        install_path = singularity_config.get('install_path', '/usr/local')
        
        for node in self.all_nodes:
            hostname = node['hostname']
            print(f"  📦 {hostname}: Singularity 설치 중...")
            
            # Go 설치
            go_commands = [
                "cd /tmp",
                "wget -q https://go.dev/dl/go1.19.5.linux-amd64.tar.gz 2>/dev/null || true",
                "rm -rf /usr/local/go",
                "tar -C /usr/local -xzf go1.19.5.linux-amd64.tar.gz 2>/dev/null || true"
            ]
            
            for cmd in go_commands:
                self.ssh_manager.execute_command(hostname, cmd, show_output=False)
            
            # 의존성 패키지 설치
            dep_cmd = (
                "yum groupinstall -y 'Development Tools' 2>/dev/null || "
                "apt install -y build-essential 2>/dev/null; "
                "yum install -y openssl-devel libuuid-devel libseccomp-devel wget squashfs-tools cryptsetup 2>/dev/null || "
                "apt install -y libssl-dev uuid-dev libseccomp-dev wget squashfs-tools cryptsetup-bin 2>/dev/null"
            )
            self.ssh_manager.execute_command(hostname, dep_cmd, show_output=False, timeout=600)
            
            # Singularity 다운로드 및 컴파일
            singularity_build_script = f"""
export PATH=/usr/local/go/bin:$PATH
cd /tmp
rm -rf singularity-ce-{version}*
wget -q https://github.com/sylabs/singularity/releases/download/v{version}/singularity-ce-{version}.tar.gz
tar -xzf singularity-ce-{version}.tar.gz
cd singularity-ce-{version}
./mconfig --prefix={install_path}
make -C builddir -j$(nproc)
make -C builddir install
"""
            
            self.ssh_manager.execute_command(
                hostname, 
                singularity_build_script,
                timeout=1800,
                show_output=False
            )
            
            print(f"  ✅ {hostname}: Singularity 설치 완료")
        
        return True
    
    def setup_docker(self, docker_config: Dict[str, Any]) -> bool:
        """Docker 설치 및 설정"""
        print("🐋 모든 노드에 Docker 설치 중...")
        
        rootless = docker_config.get('rootless', True)
        data_root = docker_config.get('data_root', '/var/lib/docker')
        
        for node in self.all_nodes:
            hostname = node['hostname']
            print(f"  🐋 {hostname}: Docker 설치 중...")
            
            # Docker 설치
            docker_install_script = """
# Docker 리포지토리 추가 및 설치
if command -v yum &> /dev/null; then
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null
    yum install -y docker-ce docker-ce-cli containerd.io
elif command -v apt &> /dev/null; then
    apt update
    apt install -y docker.io
fi

systemctl enable docker
systemctl start docker
"""
            
            self.ssh_manager.execute_command(hostname, docker_install_script, show_output=False, timeout=600)
            
            # Rootless 모드 설정
            if rootless:
                print(f"     🔐 {hostname}: Rootless Docker 설정 중...")
                rootless_cmd = (
                    "yum install -y fuse-overlayfs slirp4netns 2>/dev/null || "
                    "apt install -y fuse-overlayfs slirp4netns 2>/dev/null; "
                    "dockerd-rootless-setuptool.sh install 2>/dev/null || true"
                )
                self.ssh_manager.execute_command(hostname, rootless_cmd, show_output=False)
            
            print(f"  ✅ {hostname}: Docker 설치 완료")
        
        # 검증
        test_node = self.config['nodes']['controller']['hostname']
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            test_node,
            "docker --version",
            show_output=False
        )
        
        if exit_code == 0 and stdout:
            print(f"✅ Docker 버전: {stdout.strip()}")
        
        return True
