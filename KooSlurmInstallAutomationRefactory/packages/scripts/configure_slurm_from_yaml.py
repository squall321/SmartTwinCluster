#!/usr/bin/env python3
"""
YAML 기반 Slurm 설정 파일 생성 스크립트
모든 설정을 my_cluster.yaml에서 읽어와서 동적으로 생성합니다.
"""

import yaml
import sys
import subprocess
from pathlib import Path
from datetime import datetime


class SlurmConfigFromYAML:
    """YAML 기반 Slurm 설정 생성기"""
    
    def __init__(self, yaml_file='my_cluster.yaml'):
        self.yaml_file = yaml_file
        self.config = self.load_yaml()
        
    def load_yaml(self):
        """YAML 파일 로드"""
        yaml_path = Path(self.yaml_file)
        if not yaml_path.exists():
            print(f"❌ {self.yaml_file} 파일을 찾을 수 없습니다!")
            sys.exit(1)
        
        with open(yaml_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    
    def generate_slurm_conf(self):
        """slurm.conf 생성"""
        cluster_info = self.config['cluster_info']
        controller = self.config['nodes']['controller']
        slurm_cfg = self.config['slurm_config']
        users = self.config['users']
        
        # Header
        slurm_conf = f"""# slurm.conf
# Auto-generated from {self.yaml_file}
# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
# DO NOT EDIT MANUALLY - Modify {self.yaml_file} and regenerate

#######################################################################
# CLUSTER INFO
#######################################################################
ClusterName={cluster_info['cluster_name']}
SlurmctldHost={controller['hostname']}({controller['ip_address']})

#######################################################################
# USER CONFIGURATION
#######################################################################
SlurmUser={users['slurm_user']}
SlurmdUser=root

#######################################################################
# PID FILES
#######################################################################
SlurmctldPidFile=/run/slurm/slurmctld.pid
SlurmdPidFile=/run/slurm/slurmd.pid

#######################################################################
# AUTHENTICATION
#######################################################################
AuthType=auth/munge
CredType=cred/munge

"""
        
        # Reboot Program (YAML에서 읽기)
        reboot_program = slurm_cfg.get('reboot_program', '/sbin/reboot')
        slurm_conf += f"""#######################################################################
# REBOOT PROGRAM
#######################################################################
RebootProgram={reboot_program}

"""
        
        # Scheduler
        scheduler = slurm_cfg['scheduler']
        slurm_conf += f"""#######################################################################
# SCHEDULER
#######################################################################
SchedulerType={scheduler['type']}
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

"""
        
        # Logging
        log_path = slurm_cfg.get('log_path', '/var/log/slurm')
        slurm_conf += f"""#######################################################################
# LOGGING
#######################################################################
SlurmctldDebug=info
SlurmctldLogFile={log_path}/slurmctld.log
SlurmdDebug=info
SlurmdLogFile={log_path}/slurmd.log

"""
        
        # State Preservation
        state_save = slurm_cfg.get('state_save_location', '/var/spool/slurm/state')
        spool_path = slurm_cfg.get('spool_path', '/var/spool/slurm')
        slurm_conf += f"""#######################################################################
# STATE PRESERVATION
#######################################################################
StateSaveLocation={state_save}
SlurmdSpoolDir={spool_path}/d

"""
        
        # Timeouts
        slurm_conf += """#######################################################################
# TIMEOUTS
#######################################################################
SlurmctldTimeout=300
SlurmdTimeout=300
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0

"""
        
        # Process Tracking - cgroup v2
        slurm_conf += """#######################################################################
# PROCESS TRACKING - cgroup v2
#######################################################################
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup,task/affinity

"""
        
        # Accounting
        accounting = slurm_cfg['accounting']
        slurm_conf += f"""#######################################################################
# ACCOUNTING
#######################################################################
AccountingStorageType={accounting['storage_type']}
JobAcctGatherType=jobacct_gather/cgroup
JobAcctGatherFrequency=30

"""
        
        # Compute Nodes (YAML에서 동적으로 생성)
        slurm_conf += """#######################################################################
# COMPUTE NODES
# Generated from my_cluster.yaml nodes.compute_nodes
#######################################################################
"""
        
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            ip_address = node.get('ip_address', hostname)
            hw = node['hardware']
            
            cpus = hw['cpus']
            sockets = hw.get('sockets', 1)
            cores_per_socket = hw.get('cores_per_socket', cpus // sockets)
            threads_per_core = hw.get('threads_per_core', 1)
            memory_mb = hw['memory_mb']
            
            slurm_conf += f"NodeName={hostname} NodeAddr={ip_address} CPUs={cpus} Sockets={sockets} CoresPerSocket={cores_per_socket} ThreadsPerCore={threads_per_core} RealMemory={memory_mb} State=UNKNOWN\n"
        
        # Partitions (YAML에서 동적으로 생성)
        slurm_conf += """
#######################################################################
# PARTITIONS
# Generated from my_cluster.yaml slurm_config.partitions
#######################################################################
"""
        
        for partition in slurm_cfg['partitions']:
            name = partition['name']
            nodes = partition['nodes']
            default = "YES" if partition.get('default', False) else "NO"
            max_time = partition.get('max_time', 'INFINITE')
            max_nodes = partition.get('max_nodes', '')
            state = partition.get('state', 'UP')
            
            max_nodes_str = f" MaxNodes={max_nodes}" if max_nodes else ""
            slurm_conf += f"PartitionName={name} Nodes={nodes} Default={default} MaxTime={max_time}{max_nodes_str} State={state}\n"
        
        return slurm_conf
    
    def generate_cgroup_conf(self):
        """cgroup.conf 생성"""
        cgroup_conf = f"""###
# Slurm cgroup v2 Configuration
# Auto-generated from {self.yaml_file}
# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
###

# 리소스 제한 활성화
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=no
ConstrainDevices=no

# 메모리 제한 설정
AllowedRAMSpace=100
AllowedSwapSpace=0

# Slurm 23.11.x는 systemd와 통합되어
# cgroup v2를 자동으로 사용합니다.
"""
        return cgroup_conf
    
    def generate_systemd_slurmctld(self):
        """slurmctld.service 생성"""
        slurm_cfg = self.config['slurm_config']
        config_path = slurm_cfg['config_path']
        install_path = slurm_cfg['install_path']
        
        service = f"""[Unit]
Description=Slurm controller daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists={config_path}/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmctld
ExecStart={install_path}/sbin/slurmctld $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmctld.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
User=slurm
Group=slurm
RuntimeDirectory=slurm
RuntimeDirectoryMode=0755
TimeoutStartSec=300
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
"""
        return service
    
    def generate_systemd_slurmd(self):
        """slurmd.service 생성"""
        slurm_cfg = self.config['slurm_config']
        config_path = slurm_cfg['config_path']
        install_path = slurm_cfg['install_path']
        
        service = f"""[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists={config_path}/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmd
ExecStart={install_path}/sbin/slurmd $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
User=root
Group=root
RuntimeDirectory=slurm
RuntimeDirectoryMode=0755
TimeoutStartSec=300
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
"""
        return service
    
    def save_files(self):
        """생성된 설정 파일들을 저장"""
        slurm_cfg = self.config['slurm_config']
        config_path = Path(slurm_cfg['config_path'])
        
        print("="*80)
        print("🔧 Slurm 설정 파일 생성 (YAML 기반)")
        print("="*80)
        print()
        print(f"📝 YAML 파일: {self.yaml_file}")
        print(f"📁 설정 경로: {config_path}")
        print()
        
        # 디렉토리 생성
        print("📁 Step 1/5: 디렉토리 생성...")
        print("-"*80)
        
        dirs_to_create = [
            config_path,
            Path(slurm_cfg['log_path']),
            Path(slurm_cfg['state_save_location']),
            Path(slurm_cfg['spool_path']) / 'd',
            Path('/run/slurm')
        ]
        
        for directory in dirs_to_create:
            try:
                subprocess.run(['sudo', 'mkdir', '-p', str(directory)], check=True)
                print(f"  ✅ {directory}")
            except subprocess.CalledProcessError as e:
                print(f"  ⚠️  {directory} 생성 실패: {e}")
        
        print()
        
        # slurm.conf 생성
        print("📝 Step 2/5: slurm.conf 생성...")
        print("-"*80)
        
        slurm_conf = self.generate_slurm_conf()
        slurm_conf_path = config_path / 'slurm.conf'
        
        # 임시 파일로 저장 후 sudo로 이동
        temp_slurm = Path('/tmp/slurm.conf')
        with open(temp_slurm, 'w') as f:
            f.write(slurm_conf)
        
        try:
            subprocess.run(['sudo', 'mv', str(temp_slurm), str(slurm_conf_path)], check=True)
            subprocess.run(['sudo', 'chown', 'slurm:slurm', str(slurm_conf_path)], check=True)
            subprocess.run(['sudo', 'chmod', '644', str(slurm_conf_path)], check=True)
            print(f"  ✅ {slurm_conf_path}")
        except subprocess.CalledProcessError as e:
            print(f"  ❌ 생성 실패: {e}")
            return False
        
        print()
        
        # cgroup.conf 생성
        print("📝 Step 3/5: cgroup.conf 생성...")
        print("-"*80)
        
        cgroup_conf = self.generate_cgroup_conf()
        cgroup_conf_path = config_path / 'cgroup.conf'
        
        temp_cgroup = Path('/tmp/cgroup.conf')
        with open(temp_cgroup, 'w') as f:
            f.write(cgroup_conf)
        
        try:
            subprocess.run(['sudo', 'mv', str(temp_cgroup), str(cgroup_conf_path)], check=True)
            subprocess.run(['sudo', 'chown', 'slurm:slurm', str(cgroup_conf_path)], check=True)
            subprocess.run(['sudo', 'chmod', '644', str(cgroup_conf_path)], check=True)
            print(f"  ✅ {cgroup_conf_path}")
        except subprocess.CalledProcessError as e:
            print(f"  ❌ 생성 실패: {e}")
            return False
        
        print()
        
        # systemd 서비스 파일 생성
        print("📝 Step 4/5: systemd 서비스 파일 생성...")
        print("-"*80)
        
        # slurmctld.service
        slurmctld_service = self.generate_systemd_slurmctld()
        temp_slurmctld = Path('/tmp/slurmctld.service')
        with open(temp_slurmctld, 'w') as f:
            f.write(slurmctld_service)
        
        try:
            subprocess.run(['sudo', 'mv', str(temp_slurmctld), '/etc/systemd/system/slurmctld.service'], check=True)
            print(f"  ✅ /etc/systemd/system/slurmctld.service")
        except subprocess.CalledProcessError as e:
            print(f"  ⚠️  slurmctld.service 생성 실패: {e}")
        
        # slurmd.service
        slurmd_service = self.generate_systemd_slurmd()
        temp_slurmd = Path('/tmp/slurmd.service')
        with open(temp_slurmd, 'w') as f:
            f.write(slurmd_service)
        
        try:
            subprocess.run(['sudo', 'mv', str(temp_slurmd), '/etc/systemd/system/slurmd.service'], check=True)
            print(f"  ✅ /etc/systemd/system/slurmd.service")
        except subprocess.CalledProcessError as e:
            print(f"  ⚠️  slurmd.service 생성 실패: {e}")
        
        # tmpfiles.d 설정
        tmpfiles_conf = "d /run/slurm 0755 slurm slurm -\n"
        temp_tmpfiles = Path('/tmp/slurm_tmpfiles.conf')
        with open(temp_tmpfiles, 'w') as f:
            f.write(tmpfiles_conf)
        
        try:
            subprocess.run(['sudo', 'mv', str(temp_tmpfiles), '/etc/tmpfiles.d/slurm.conf'], check=True)
            subprocess.run(['sudo', 'systemd-tmpfiles', '--create'], check=True)
            print(f"  ✅ /etc/tmpfiles.d/slurm.conf")
        except subprocess.CalledProcessError as e:
            print(f"  ⚠️  tmpfiles.d 생성 실패: {e}")
        
        # systemd reload
        try:
            subprocess.run(['sudo', 'systemctl', 'daemon-reload'], check=True)
            print(f"  ✅ systemd daemon-reload")
        except subprocess.CalledProcessError as e:
            print(f"  ⚠️  daemon-reload 실패: {e}")
        
        print()
        
        # 권한 설정
        print("🔒 Step 5/5: 권한 설정...")
        print("-"*80)
        
        paths_to_chown = [
            (slurm_cfg['log_path'], 'slurm:slurm'),
            (slurm_cfg['spool_path'], 'slurm:slurm'),
            ('/run/slurm', 'slurm:slurm')
        ]
        
        for path, owner in paths_to_chown:
            try:
                subprocess.run(['sudo', 'chown', '-R', owner, path], check=True)
                subprocess.run(['sudo', 'chmod', '755', path], check=True)
                print(f"  ✅ {path} → {owner}")
            except subprocess.CalledProcessError as e:
                print(f"  ⚠️  {path} 권한 설정 실패: {e}")
        
        print()
        
        return True
    
    def print_summary(self):
        """설정 요약 출력"""
        print("="*80)
        print("🎉 Slurm 설정 파일 생성 완료!")
        print("="*80)
        print()
        
        slurm_cfg = self.config['slurm_config']
        config_path = slurm_cfg['config_path']
        
        print("📁 생성된 파일:")
        print(f"  ✅ {config_path}/slurm.conf")
        print(f"  ✅ {config_path}/cgroup.conf")
        print(f"  ✅ /etc/systemd/system/slurmctld.service")
        print(f"  ✅ /etc/systemd/system/slurmd.service")
        print(f"  ✅ /etc/tmpfiles.d/slurm.conf")
        print()
        
        print("🔧 YAML에서 읽어온 주요 설정:")
        cluster_name = self.config['cluster_info']['cluster_name']
        controller = self.config['nodes']['controller']
        reboot_program = slurm_cfg.get('reboot_program', '/sbin/reboot')
        
        print(f"  ✅ ClusterName: {cluster_name}")
        print(f"  ✅ Controller: {controller['hostname']} ({controller['ip_address']})")
        print(f"  ✅ RebootProgram: {reboot_program}")
        print(f"  ✅ 계산 노드: {len(self.config['nodes']['compute_nodes'])}개")
        print(f"  ✅ 파티션: {len(slurm_cfg['partitions'])}개")
        print()
        
        # 계산 노드 목록
        print("📊 계산 노드 목록:")
        for node in self.config['nodes']['compute_nodes']:
            hw = node['hardware']
            print(f"  - {node['hostname']} ({node['ip_address']}): {hw['cpus']} CPUs, {hw['memory_mb']} MB")
        print()
        
        # 파티션 목록
        print("📊 파티션 목록:")
        for partition in slurm_cfg['partitions']:
            default_mark = " (기본)" if partition.get('default', False) else ""
            print(f"  - {partition['name']}{default_mark}: {partition['nodes']}, MaxTime={partition.get('max_time', 'INFINITE')}")
        print()
        
        print("🔍 설정 확인:")
        print(f"  grep -E '^ClusterName|^RebootProgram|^NodeName|^PartitionName' {config_path}/slurm.conf")
        print()
        
        print("📋 다음 단계:")
        print("  1. 모든 계산 노드에 설정 파일 복사:")
        
        for node in self.config['nodes']['compute_nodes']:
            ip = node['ip_address']
            user = node['ssh_user']
            print(f"     scp {config_path}/slurm.conf {config_path}/cgroup.conf {user}@{ip}:/tmp/")
            print(f"     ssh {user}@{ip} 'sudo mv /tmp/{{slurm,cgroup}}.conf {config_path}/ && sudo chown slurm:slurm {config_path}/{{slurm,cgroup}}.conf'")
        
        print()
        print("  2. Slurm 재시작:")
        print("     sudo systemctl restart slurmctld")
        
        for node in self.config['nodes']['compute_nodes']:
            print(f"     ssh {node['ssh_user']}@{node['ip_address']} 'sudo systemctl restart slurmd'")
        
        print()
        print("  3. 상태 확인:")
        print("     sinfo")
        print("     scontrol show config | grep RebootProgram")
        print()
        print("="*80)


def main():
    """메인 함수"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='YAML 기반 Slurm 설정 파일 생성',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
예시:
  # 기본 (my_cluster.yaml 사용)
  python3 configure_slurm_from_yaml.py
  
  # 다른 YAML 파일 사용
  python3 configure_slurm_from_yaml.py -c custom_cluster.yaml
  
  # 생성만 하고 저장은 안함 (미리보기)
  python3 configure_slurm_from_yaml.py --dry-run
        """
    )
    
    parser.add_argument(
        '-c', '--config',
        default='my_cluster.yaml',
        help='YAML 설정 파일 경로 (기본: my_cluster.yaml)'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='실제 저장하지 않고 미리보기만'
    )
    
    args = parser.parse_args()
    
    # YAML 로드 및 생성
    generator = SlurmConfigFromYAML(args.config)
    
    if args.dry_run:
        print("="*80)
        print("🔍 DRY RUN MODE - 미리보기")
        print("="*80)
        print()
        print("📝 slurm.conf:")
        print("-"*80)
        print(generator.generate_slurm_conf())
        print()
        print("📝 cgroup.conf:")
        print("-"*80)
        print(generator.generate_cgroup_conf())
        print()
    else:
        # 실제 파일 생성 및 저장
        if generator.save_files():
            generator.print_summary()
        else:
            print("❌ 설정 파일 생성 실패!")
            sys.exit(1)


if __name__ == '__main__':
    main()
