#!/usr/bin/env python3
"""
Slurm 설치 자동화 - 고급 기능 설치
Stage 2, 3의 고급 기능들을 설치하고 설정하는 모듈
"""

import tempfile
import time
from typing import Dict, List, Optional, Tuple, Any
from ssh_manager import SSHManager
from container_support import ContainerSupport
from pathlib import Path
import os


class AdvancedFeaturesInstaller:
    """고급 기능 설치 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.controller_hostname = config['nodes']['controller']['hostname']
        
    def setup_database(self) -> bool:
        """데이터베이스 설정 (MySQL/MariaDB)"""
        print("\n🗄️  데이터베이스 설정 중...")
        
        try:
            db_config = self.config.get('database', {})
            if not db_config.get('enabled', False):
                return True
            
            hostname = db_config.get('host', self.controller_hostname)
            db_name = db_config.get('database_name', 'slurm_acct_db')
            db_user = db_config.get('username', 'slurm')
            db_password = db_config.get('password', 'changeme')
            
            print(f"📊 {hostname}: MariaDB 설치 중...")
            
            # MariaDB 설치
            install_commands = [
                "yum install -y mariadb-server mariadb-devel || apt install -y mariadb-server libmariadb-dev",
                "systemctl enable mariadb",
                "systemctl start mariadb"
            ]
            
            for cmd in install_commands:
                exit_code, _, _ = self.ssh_manager.execute_command(hostname, cmd)
                if exit_code != 0 and "systemctl start" in cmd:
                    # 이미 시작되어 있을 수 있음
                    continue
            
            # 데이터베이스 보안 설정
            secure_installation = f"""
mysql -u root << EOF
UPDATE mysql.user SET Password=PASSWORD('root_password') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
"""
            
            self.ssh_manager.execute_command(hostname, secure_installation, show_output=False)
            
            # Slurm 데이터베이스 생성
            db_setup_sql = f"""
mysql -u root -proot_password << EOF
CREATE DATABASE IF NOT EXISTS {db_name};
GRANT ALL PRIVILEGES ON {db_name}.* TO '{db_user}'@'localhost' IDENTIFIED BY '{db_password}';
GRANT ALL PRIVILEGES ON {db_name}.* TO '{db_user}'@'%' IDENTIFIED BY '{db_password}';
FLUSH PRIVILEGES;
EOF
"""
            
            exit_code, stdout, stderr = self.ssh_manager.execute_command(hostname, db_setup_sql)
            
            if exit_code == 0:
                print(f"✅ {hostname}: 데이터베이스 설정 완료")
                
                # 데이터베이스 백업 설정
                self._setup_database_backup(hostname, db_config)
                
                return True
            else:
                print(f"❌ {hostname}: 데이터베이스 설정 실패")
                if stderr:
                    print(f"오류: {stderr}")
                return False
                
        except Exception as e:
            print(f"❌ 데이터베이스 설정 실패: {e}")
            return False
    
    def _setup_database_backup(self, hostname: str, db_config: Dict[str, Any]):
        """데이터베이스 백업 설정"""
        backup_schedule = db_config.get('backup_schedule', '0 2 * * *')  # 매일 2시
        db_name = db_config.get('database_name', 'slurm_acct_db')
        db_user = db_config.get('username', 'slurm')
        db_password = db_config.get('password', 'changeme')
        
        backup_script = f"""#!/bin/bash
# Slurm Database Backup Script
BACKUP_DIR="/backup/slurm-db"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/slurm_db_backup_$DATE.sql"

mkdir -p $BACKUP_DIR

mysqldump -u {db_user} -p{db_password} {db_name} > $BACKUP_FILE

# 7일 이상 된 백업 파일 삭제
find $BACKUP_DIR -name "slurm_db_backup_*.sql" -mtime +7 -delete

# 백업 압축
gzip $BACKUP_FILE
"""
        
        # 백업 스크립트 업로드
        self.ssh_manager.execute_command(
            hostname, f"echo '{backup_script}' > /usr/local/bin/slurm_db_backup.sh"
        )
        self.ssh_manager.execute_command(hostname, "chmod +x /usr/local/bin/slurm_db_backup.sh")
        
        # cron 작업 추가
        cron_entry = f"{backup_schedule} /usr/local/bin/slurm_db_backup.sh"
        self.ssh_manager.execute_command(
            hostname, f"(crontab -l 2>/dev/null; echo '{cron_entry}') | crontab -"
        )
    
    def setup_monitoring(self) -> bool:
        """모니터링 시스템 설정"""
        print("\n📊 모니터링 시스템 설정 중...")
        
        try:
            monitoring_config = self.config.get('monitoring', {})
            
            # Prometheus 설정
            if monitoring_config.get('prometheus', {}).get('enabled', False):
                if not self._setup_prometheus():
                    return False
            
            # Grafana 설정
            if monitoring_config.get('grafana', {}).get('enabled', False):
                if not self._setup_grafana():
                    return False
            
            # Ganglia 설정
            if monitoring_config.get('ganglia', {}).get('enabled', False):
                if not self._setup_ganglia():
                    return False
            
            print("✅ 모니터링 시스템 설정 완료")
            return True
            
        except Exception as e:
            print(f"❌ 모니터링 시스템 설정 실패: {e}")
            return False
    
    def _setup_prometheus(self) -> bool:
        """Prometheus 설정"""
        print(f"📈 {self.controller_hostname}: Prometheus 설정 중...")
        
        prometheus_config = self.config['monitoring']['prometheus']
        port = prometheus_config.get('port', 9090)
        
        # Prometheus 설치
        install_commands = [
            "useradd --no-create-home --shell /bin/false prometheus",
            "mkdir -p /etc/prometheus /var/lib/prometheus",
            "chown prometheus:prometheus /etc/prometheus /var/lib/prometheus",
            "cd /tmp",
            "wget https://github.com/prometheus/prometheus/releases/download/v2.40.0/prometheus-2.40.0.linux-amd64.tar.gz",
            "tar xzf prometheus-2.40.0.linux-amd64.tar.gz",
            "cp prometheus-2.40.0.linux-amd64/prometheus /usr/local/bin/",
            "cp prometheus-2.40.0.linux-amd64/promtool /usr/local/bin/",
            "chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool",
            "cp -r prometheus-2.40.0.linux-amd64/consoles /etc/prometheus",
            "cp -r prometheus-2.40.0.linux-amd64/console_libraries /etc/prometheus",
            "chown -R prometheus:prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries"
        ]
        
        for cmd in install_commands:
            self.ssh_manager.execute_command(self.controller_hostname, cmd, show_output=False)
        
        # Prometheus 설정 파일
        prometheus_yml = f"""
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:{port}']

  - job_name: 'node_exporter'
    static_configs:
      - targets:
"""
        
        # 모든 노드를 타겟에 추가
        all_nodes = [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']
        for node in all_nodes:
            prometheus_yml += f"        - '{node['hostname']}:9100'\n"
        
        # 설정 파일 업로드
        self.ssh_manager.execute_command(
            self.controller_hostname, f"echo '{prometheus_yml}' > /etc/prometheus/prometheus.yml"
        )
        self.ssh_manager.execute_command(
            self.controller_hostname, "chown prometheus:prometheus /etc/prometheus/prometheus.yml"
        )
        
        # Prometheus 서비스 파일
        prometheus_service = f"""[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path /var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:{port}

[Install]
WantedBy=multi-user.target
"""
        
        self.ssh_manager.execute_command(
            self.controller_hostname, f"echo '{prometheus_service}' > /etc/systemd/system/prometheus.service"
        )
        
        # 서비스 시작
        self.ssh_manager.execute_command(self.controller_hostname, "systemctl daemon-reload")
        self.ssh_manager.execute_command(self.controller_hostname, "systemctl enable prometheus")
        self.ssh_manager.execute_command(self.controller_hostname, "systemctl start prometheus")
        
        # Node Exporter 설치 (모든 노드)
        if prometheus_config.get('node_exporter', True):
            self._install_node_exporter()
        
        return True
    
    def _install_node_exporter(self) -> bool:
        """Node Exporter 설치 (모든 노드)"""
        print("📊 모든 노드에 Node Exporter 설치 중...")
        
        install_commands = [
            "useradd --no-create-home --shell /bin/false node_exporter",
            "cd /tmp",
            "wget https://github.com/prometheus/node_exporter/releases/download/v1.5.0/node_exporter-1.5.0.linux-amd64.tar.gz",
            "tar xzf node_exporter-1.5.0.linux-amd64.tar.gz",
            "cp node_exporter-1.5.0.linux-amd64/node_exporter /usr/local/bin/",
            "chown node_exporter:node_exporter /usr/local/bin/node_exporter"
        ]
        
        # Node Exporter 서비스 파일
        node_exporter_service = """[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100

[Install]
WantedBy=multi-user.target
"""
        
        all_nodes = [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']
        
        for node in all_nodes:
            hostname = node['hostname']
            
            for cmd in install_commands:
                self.ssh_manager.execute_command(hostname, cmd, show_output=False)
            
            self.ssh_manager.execute_command(
                hostname, f"echo '{node_exporter_service}' > /etc/systemd/system/node_exporter.service"
            )
            
            self.ssh_manager.execute_command(hostname, "systemctl daemon-reload")
            self.ssh_manager.execute_command(hostname, "systemctl enable node_exporter")
            self.ssh_manager.execute_command(hostname, "systemctl start node_exporter")
        
        return True
    
    def _setup_grafana(self) -> bool:
        """Grafana 설정"""
        print(f"📊 {self.controller_hostname}: Grafana 설정 중...")
        
        grafana_config = self.config['monitoring']['grafana']
        port = grafana_config.get('port', 3000)
        admin_password = grafana_config.get('admin_password', 'admin')
        
        # Grafana 설치 (CentOS/RHEL의 경우)
        install_commands = [
            "wget https://dl.grafana.com/enterprise/release/grafana-enterprise-9.5.0-1.x86_64.rpm",
            "yum localinstall -y grafana-enterprise-9.5.0-1.x86_64.rpm || " +
            "(wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add - && " +
            "echo 'deb https://packages.grafana.com/oss/deb stable main' | sudo tee /etc/apt/sources.list.d/grafana.list && " +
            "apt update && apt install -y grafana)",
            "systemctl enable grafana-server",
            "systemctl start grafana-server"
        ]
        
        for cmd in install_commands:
            self.ssh_manager.execute_command(self.controller_hostname, cmd, show_output=False)
        
        # Grafana 설정 파일 수정
        grafana_ini_updates = f"""
# 기본 관리자 암호 변경을 위한 환경 변수 설정
echo 'GF_SECURITY_ADMIN_PASSWORD={admin_password}' >> /etc/grafana/grafana.ini
systemctl restart grafana-server
"""
        
        self.ssh_manager.execute_command(self.controller_hostname, grafana_ini_updates)
        
        return True
    
    def _setup_ganglia(self) -> bool:
        """Ganglia 설정"""
        print(f"📊 모든 노드에 Ganglia 설정 중...")
        
        ganglia_config = self.config['monitoring']['ganglia']
        gmetad_host = ganglia_config.get('gmetad_host', self.controller_hostname)
        
        # Ganglia 설치 (모든 노드)
        all_nodes = [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']
        
        for node in all_nodes:
            hostname = node['hostname']
            
            # Ganglia 설치
            self.ssh_manager.execute_command(
                hostname, "yum install -y ganglia ganglia-gmond || apt install -y ganglia-monitor"
            )
            
            # gmond 설정
            if hostname == gmetad_host:
                # 메타 데몬도 설치
                self.ssh_manager.execute_command(
                    hostname, "yum install -y ganglia-gmetad ganglia-web || apt install -y ganglia-webfrontend"
                )
                
                # gmetad 서비스 시작
                self.ssh_manager.execute_command(hostname, "systemctl enable gmetad")
                self.ssh_manager.execute_command(hostname, "systemctl start gmetad")
            
            # gmond 서비스 시작
            self.ssh_manager.execute_command(hostname, "systemctl enable gmond")
            self.ssh_manager.execute_command(hostname, "systemctl start gmond")
        
        return True
    
    def setup_high_availability(self) -> bool:
        """고가용성 설정"""
        print("\n🔄 고가용성 설정 중...")
        
        ha_config = self.config.get('high_availability', {}).get('controller_ha', {})
        if not ha_config.get('enabled', False):
            return True
        
        # 현재 구현에서는 기본적인 HA 설정만 제공
        print("⚠️  고가용성 설정은 고급 기능입니다. 수동 설정이 필요할 수 있습니다.")
        
        return True
    
    def setup_environment_modules(self) -> bool:
        """Environment Modules 설정"""
        print("\n📚 Environment Modules 설정 중...")
        
        try:
            modules_config = self.config.get('environment_modules', {})
            if not modules_config.get('enabled', False):
                return True
            
            module_type = modules_config.get('type', 'modules')  # modules 또는 lmod
            modulefiles_path = modules_config.get('modulefiles_path', '/usr/share/Modules/modulefiles')
            
            all_nodes = [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']
            
            for node in all_nodes:
                hostname = node['hostname']
                
                if module_type.lower() == 'lmod':
                    # Lmod 설치
                    lmod_commands = [
                        "yum install -y lua lua-devel lua-filesystem lua-posix || apt install -y lua5.2 liblua5.2-dev lua-filesystem lua-posix",
                        "cd /tmp",
                        "wget https://github.com/TACC/Lmod/archive/8.7.tar.gz",
                        "tar xzf 8.7.tar.gz",
                        "cd Lmod-8.7",
                        "./configure --prefix=/opt/lmod",
                        "make install",
                        "ln -s /opt/lmod/lmod/lmod/init/profile /etc/profile.d/z00_lmod.sh",
                        "ln -s /opt/lmod/lmod/lmod/init/cshrc /etc/profile.d/z00_lmod.csh"
                    ]
                    
                    for cmd in lmod_commands:
                        self.ssh_manager.execute_command(hostname, cmd, show_output=False)
                
                else:
                    # Environment Modules 설치
                    modules_commands = [
                        "yum install -y environment-modules || apt install -y environment-modules",
                        f"mkdir -p {modulefiles_path}"
                    ]
                    
                    for cmd in modules_commands:
                        self.ssh_manager.execute_command(hostname, cmd, show_output=False)
            
            print("✅ Environment Modules 설정 완료")
            return True
            
        except Exception as e:
            print(f"❌ Environment Modules 설정 실패: {e}")
            return False
    
    def apply_performance_tuning(self) -> bool:
        """성능 튜닝 적용"""
        print("\n⚡ 성능 튜닝 적용 중...")
        
        try:
            perf_config = self.config.get('performance_tuning', {})
            
            all_nodes = [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']
            
            for node in all_nodes:
                hostname = node['hostname']
                
                # 커널 파라미터 설정
                kernel_params = perf_config.get('kernel_parameters', {})
                if kernel_params:
                    self._apply_kernel_parameters(hostname, kernel_params)
                
                # ulimit 설정
                ulimits = perf_config.get('ulimits', {})
                if ulimits:
                    self._apply_ulimits(hostname, ulimits)
                
                # CPU governor 설정
                cpu_governor = perf_config.get('cpu_governor', 'performance')
                if cpu_governor:
                    self._set_cpu_governor(hostname, cpu_governor)
            
            print("✅ 성능 튜닝 적용 완료")
            return True
            
        except Exception as e:
            print(f"❌ 성능 튜닝 적용 실패: {e}")
            return False
    
    def _apply_kernel_parameters(self, hostname: str, params: Dict[str, Any]):
        """커널 파라미터 적용"""
        sysctl_content = "# Slurm cluster performance tuning\n"
        
        for param, value in params.items():
            sysctl_content += f"{param} = {value}\n"
        
        self.ssh_manager.execute_command(
            hostname, f"echo '{sysctl_content}' > /etc/sysctl.d/99-slurm-tuning.conf"
        )
        self.ssh_manager.execute_command(hostname, "sysctl -p /etc/sysctl.d/99-slurm-tuning.conf")
    
    def _apply_ulimits(self, hostname: str, ulimits: Dict[str, Any]):
        """ulimit 설정 적용"""
        limits_content = "# Slurm cluster ulimits\n"
        
        for limit_type, value in ulimits.items():
            limits_content += f"* soft {limit_type} {value}\n"
            limits_content += f"* hard {limit_type} {value}\n"
        
        self.ssh_manager.execute_command(
            hostname, f"echo '{limits_content}' >> /etc/security/limits.conf"
        )
    
    def _set_cpu_governor(self, hostname: str, governor: str):
        """CPU governor 설정"""
        governor_commands = [
            f"echo {governor} | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor",
            f"echo 'GOVERNOR=\"{governor}\"' > /etc/default/cpufrequtils"
        ]
        
        for cmd in governor_commands:
            self.ssh_manager.execute_command(hostname, cmd, show_output=False)
    
    def setup_power_management(self) -> bool:
        """전력 관리 설정"""
        print("\n🔋 전력 관리 설정 중...")
        
        power_config = self.config.get('power_management', {})
        if not power_config.get('enabled', False):
            return True
        
        # 기본적인 전력 관리 설정만 제공
        print("⚠️  전력 관리 기능은 고급 설정입니다. 추가 구성이 필요할 수 있습니다.")
        
        return True
    
    def setup_container_support(self) -> bool:
        """컨테이너 지원 설정"""
        container_support = ContainerSupport(self.config, self.ssh_manager)
        return container_support.setup_container_support()
    
    def _setup_singularity(self, singularity_config: Dict[str, Any]) -> bool:
        """Singularity 설치"""
        print("📦 모든 노드에 Singularity 설치 중...")
        
        version = singularity_config.get('version', '3.10.0')
        
        all_nodes = [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']
        
        singularity_commands = [
            "yum groupinstall -y 'Development Tools' || apt install -y build-essential",
            "yum install -y openssl-devel libuuid-devel libseccomp-devel wget squashfs-tools cryptsetup || " +
            "apt install -y libssl-dev uuid-dev libseccomp-dev wget squashfs-tools cryptsetup-bin",
            f"cd /tmp && wget https://github.com/sylabs/singularity/releases/download/v{version}/singularity-ce-{version}.tar.gz",
            f"tar -xzf singularity-ce-{version}.tar.gz",
            f"cd singularity-ce-{version}",
            "./mconfig && make -C builddir && make -C builddir install"
        ]
        
        for node in all_nodes:
            hostname = node['hostname']
            
            for cmd in singularity_commands:
                self.ssh_manager.execute_command(hostname, cmd, timeout=1800, show_output=False)
        
        return True
    
    def setup_parallel_filesystems(self) -> bool:
        """병렬 파일시스템 설정"""
        print("\n🗂️  병렬 파일시스템 설정 중...")
        
        pfs_config = self.config.get('parallel_filesystems', {})
        
        # Lustre 설정
        if pfs_config.get('lustre', {}).get('enabled', False):
            print("⚠️  Lustre 파일시스템 설정은 복잡한 고급 기능입니다.")
            print("   별도의 전문 설치가 필요합니다.")
        
        # BeeGFS 설정
        if pfs_config.get('beegfs', {}).get('enabled', False):
            print("⚠️  BeeGFS 파일시스템 설정은 복잡한 고급 기능입니다.")
            print("   별도의 전문 설치가 필요합니다.")
        
        return True
    
    def setup_backup_and_recovery(self) -> bool:
        """백업 및 복구 설정"""
        print("\n💾 백업 및 복구 설정 중...")
        
        try:
            backup_config = self.config.get('backup_and_recovery', {}).get('config_backup', {})
            if not backup_config.get('enabled', True):
                return True
            
            schedule = backup_config.get('schedule', '0 3 * * 0')  # 매주 일요일 3시
            retention_days = backup_config.get('retention_days', 30)
            backup_path = backup_config.get('backup_path', '/backup/slurm')
            
            # 백업 스크립트 생성
            backup_script = f"""#!/bin/bash
# Slurm Configuration Backup Script
BACKUP_DIR="{backup_path}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/slurm_config_backup_$DATE.tar.gz"

mkdir -p $BACKUP_DIR

# Slurm 설정 파일들 백업
tar -czf $BACKUP_FILE \\
    {self.config['slurm_config']['config_path']} \\
    /etc/munge/ \\
    /etc/systemd/system/slurm*.service \\
    2>/dev/null

# 오래된 백업 파일 삭제
find $BACKUP_DIR -name "slurm_config_backup_*.tar.gz" -mtime +{retention_days} -delete

echo "Backup completed: $BACKUP_FILE"
"""
            
            # 백업 스크립트를 컨트롤러에 설치
            self.ssh_manager.execute_command(
                self.controller_hostname, f"echo '{backup_script}' > /usr/local/bin/slurm_config_backup.sh"
            )
            self.ssh_manager.execute_command(
                self.controller_hostname, "chmod +x /usr/local/bin/slurm_config_backup.sh"
            )
            
            # cron 작업 추가
            cron_entry = f"{schedule} /usr/local/bin/slurm_config_backup.sh"
            self.ssh_manager.execute_command(
                self.controller_hostname, f"(crontab -l 2>/dev/null; echo '{cron_entry}') | crontab -"
            )
            
            print("✅ 백업 및 복구 설정 완료")
            return True
            
        except Exception as e:
            print(f"❌ 백업 및 복구 설정 실패: {e}")
            return False


def main():
    """테스트 메인 함수"""
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python advanced_features.py <config_file>")
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
        
        # 고급 기능 설치
        installer = AdvancedFeaturesInstaller(config, ssh_manager)
        
        # 각 기능별 테스트 (실제로는 설정에 따라 선택적으로 실행)
        if parser.is_feature_enabled('database'):
            installer.setup_database()
        
        if parser.is_feature_enabled('monitoring'):
            installer.setup_monitoring()
        
        ssh_manager.disconnect_all()
        
    except Exception as e:
        print(f"고급 기능 설치 중 오류 발생: {e}")


if __name__ == "__main__":
    main()
