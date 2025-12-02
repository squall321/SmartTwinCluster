#!/usr/bin/env python3
"""
Apptainer 지원 확장 모듈
advanced_features.py에 추가할 Apptainer 관련 메서드들
"""

from typing import Dict, Any
from ssh_manager import SSHManager


def setup_apptainer(ssh_manager: SSHManager, config: Dict[str, Any], apptainer_config: Dict[str, Any]) -> bool:
    """Apptainer 설치 (Singularity의 후속 프로젝트)"""
    print("📦 모든 노드에 Apptainer 설치 중...")
    
    version = apptainer_config.get('version', '1.2.5')
    install_path = apptainer_config.get('install_path', '/usr/local')
    
    all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
    
    for node in all_nodes:
        hostname = node['hostname']
        print(f"  📦 {hostname}: Apptainer 설치 중...")
        
        # Go 설치 (Apptainer 빌드에 필요)
        go_commands = [
            "cd /tmp",
            "wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz",
            "rm -rf /usr/local/go",
            "tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz",
            "export PATH=$PATH:/usr/local/go/bin"
        ]
        
        for cmd in go_commands:
            ssh_manager.execute_command(hostname, cmd, show_output=False)
        
        # 의존성 패키지 설치
        dep_commands = [
            "yum groupinstall -y 'Development Tools' || apt install -y build-essential",
            "yum install -y openssl-devel libuuid-devel libseccomp-devel wget squashfs-tools cryptsetup || " +
            "apt install -y libssl-dev uuid-dev libseccomp-dev wget squashfs-tools cryptsetup-bin libglib2.0-dev"
        ]
        
        for cmd in dep_commands:
            ssh_manager.execute_command(hostname, cmd, show_output=False)
        
        # Apptainer 다운로드 및 컴파일
        apptainer_commands = [
            "cd /tmp",
            f"wget -q https://github.com/apptainer/apptainer/releases/download/v{version}/apptainer-{version}.tar.gz",
            f"tar -xzf apptainer-{version}.tar.gz",
            f"cd apptainer-{version}",
            f"./mconfig --prefix={install_path}",
            "make -C builddir -j$(nproc)",
            "make -C builddir install"
        ]
        
        for cmd in apptainer_commands:
            exit_code, stdout, stderr = ssh_manager.execute_command(
                hostname, 
                f"export PATH=$PATH:/usr/local/go/bin && {cmd}",
                timeout=1800,
                show_output=False
            )
            
            if exit_code != 0:
                print(f"  ⚠️  {hostname}: 명령 실패 - {cmd}")
                if stderr:
                    print(f"     오류: {stderr[:200]}")
        
        # Apptainer 설정
        config_commands = [
            f"mkdir -p {apptainer_config.get('cache_path', '/tmp/apptainer')}",
            f"mkdir -p {apptainer_config.get('image_path', '/share/apptainer')}",
            f"chmod 755 {apptainer_config.get('cache_path', '/tmp/apptainer')}",
            f"chmod 755 {apptainer_config.get('image_path', '/share/apptainer')}"
        ]
        
        for cmd in config_commands:
            ssh_manager.execute_command(hostname, cmd, show_output=False)
        
        # 환경변수 설정
        env_setup = f"""
cat >> /etc/profile.d/apptainer.sh << 'EOF'
export PATH={install_path}/bin:$PATH
export APPTAINER_CACHEDIR={apptainer_config.get('cache_path', '/tmp/apptainer')}
EOF
"""
        ssh_manager.execute_command(hostname, env_setup, show_output=False)
        
        # Bind paths 설정
        bind_paths = apptainer_config.get('bind_paths', ['/home', '/share'])
        if bind_paths:
            bind_config = f"""
cat >> {install_path}/etc/apptainer/apptainer.conf << 'EOF'
bind path = {', '.join(bind_paths)}
EOF
"""
            ssh_manager.execute_command(hostname, bind_config, show_output=False)
        
        print(f"  ✅ {hostname}: Apptainer 설치 완료")
    
    # 설치 검증
    print("\n🧪 Apptainer 설치 검증 중...")
    test_node = config['nodes']['controller']['hostname']
    exit_code, stdout, stderr = ssh_manager.execute_command(
        test_node,
        f"source /etc/profile.d/apptainer.sh && {install_path}/bin/apptainer --version",
        show_output=False
    )
    
    if exit_code == 0:
        print(f"✅ Apptainer 버전: {stdout.strip()}")
    else:
        print(f"⚠️  Apptainer 검증 실패")
    
    return True


def setup_docker(ssh_manager: SSHManager, config: Dict[str, Any], docker_config: Dict[str, Any]) -> bool:
    """Docker 설치 및 설정"""
    print("🐋 모든 노드에 Docker 설치 중...")
    
    rootless = docker_config.get('rootless', True)
    data_root = docker_config.get('data_root', '/var/lib/docker')
    
    all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
    
    for node in all_nodes:
        hostname = node['hostname']
        print(f"  🐋 {hostname}: Docker 설치 중...")
        
        # Docker 설치
        docker_install_commands = [
            "yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true",
            "yum install -y docker-ce docker-ce-cli containerd.io || apt install -y docker.io",
            "systemctl enable docker",
            "systemctl start docker"
        ]
        
        for cmd in docker_install_commands:
            ssh_manager.execute_command(hostname, cmd, show_output=False)
        
        # Rootless 모드 설정
        if rootless:
            print(f"  🔐 {hostname}: Rootless Docker 설정 중...")
            rootless_commands = [
                "yum install -y fuse-overlayfs slirp4netns || apt install -y fuse-overlayfs slirp4netns",
                "dockerd-rootless-setuptool.sh install"
            ]
            
            for cmd in rootless_commands:
                ssh_manager.execute_command(hostname, cmd, show_output=False)
        
        print(f"  ✅ {hostname}: Docker 설치 완료")
    
    return True
