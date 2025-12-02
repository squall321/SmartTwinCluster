#!/usr/bin/env python3
"""
DB 포함 완전 롤백 모듈
Phase 2-2: Database Backup and Full Rollback

개선사항:
- 데이터베이스 백업 및 복구
- 전체 시스템 상태 스냅샷
- 안전한 롤백 메커니즘
"""

import os
import time
import json
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime
from ssh_manager import SSHManager


class FullSystemRollback:
    """DB 포함 완전 롤백 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        
        self.rollback_dir = Path('./rollback_snapshots')
        self.rollback_dir.mkdir(parents=True, exist_ok=True)
        
        self.snapshot_id = None
        self.snapshot_data = {
            'timestamp': None,
            'stage': None,
            'database_backup': None,
            'config_backups': {},
            'service_states': {},
            'installed_packages': {},
            'firewall_rules': {}
        }
    
    def create_full_snapshot(self, stage: int) -> str:
        """전체 시스템 스냅샷 생성"""
        print(f"\n📸 전체 시스템 스냅샷 생성 중 (Stage {stage})...")
        
        self.snapshot_id = f"full_snapshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}_stage{stage}"
        self.snapshot_data['timestamp'] = datetime.now().isoformat()
        self.snapshot_data['stage'] = stage
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        
        # 1. 데이터베이스 백업
        if self.config.get('database', {}).get('enabled'):
            print("  🗄️  데이터베이스 백업 중...")
            self._backup_database(controller_hostname)
        
        # 2. 설정 파일 백업
        print("  📄 설정 파일 백업 중...")
        self._backup_configurations()
        
        # 3. 서비스 상태 저장
        print("  ⚙️  서비스 상태 저장 중...")
        self._save_service_states()
        
        # 4. 패키지 목록
        print("  📦 패키지 목록 저장 중...")
        self._save_package_lists()
        
        # 스냅샷 저장
        self._save_snapshot_metadata()
        
        print(f"✅ 전체 스냅샷 생성 완료: {self.snapshot_id}\n")
        return self.snapshot_id
    
    def _backup_database(self, hostname: str) -> bool:
        """데이터베이스 백업"""
        db_config = self.config['database']
        
        backup_filename = f"slurm_db_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"
        remote_backup = f"/tmp/{backup_filename}"
        
        (self.rollback_dir / self.snapshot_id).mkdir(parents=True, exist_ok=True)
        local_backup = self.rollback_dir / self.snapshot_id / backup_filename
        
        dump_cmd = f"mysqldump -u {db_config['username']} -p'{db_config['password']}' " \
                   f"{db_config['database_name']} > {remote_backup} 2>/dev/null"
        
        exit_code, _, _ = self.ssh_manager.execute_command(
            hostname, dump_cmd, show_output=False, timeout=300
        )
        
        if exit_code != 0:
            print(f"    ⚠️  DB 백업 실패")
            return False
        
        success = self.ssh_manager.download_file(hostname, remote_backup, str(local_backup))
        
        if success:
            self.ssh_manager.execute_command(hostname, f"rm -f {remote_backup}", show_output=False)
            self.snapshot_data['database_backup'] = str(local_backup)
            size_kb = os.path.getsize(local_backup) / 1024
            print(f"    ✅ DB 백업: {backup_filename} ({size_kb:.1f}KB)")
            return True
        
        return False
    
    def _backup_configurations(self) -> bool:
        """설정 파일 백업"""
        all_nodes = self._get_all_nodes()
        
        config_paths = [
            '/etc/slurm/slurm.conf',
            '/etc/slurm/slurmdbd.conf',
            '/usr/local/slurm/etc/slurm.conf',
            '/etc/munge/munge.key'
        ]
        
        for node in all_nodes:
            hostname = node['hostname']
            self.snapshot_data['config_backups'][hostname] = []
            
            for config_path in config_paths:
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, f"test -f {config_path}", show_output=False
                )
                
                if exit_code == 0:
                    backup_dir = self.rollback_dir / self.snapshot_id / hostname
                    backup_dir.mkdir(parents=True, exist_ok=True)
                    
                    filename = config_path.replace('/', '_')
                    local_backup = backup_dir / filename
                    
                    success = self.ssh_manager.download_file(
                        hostname, config_path, str(local_backup)
                    )
                    
                    if success:
                        self.snapshot_data['config_backups'][hostname].append({
                            'original_path': config_path,
                            'backup_path': str(local_backup)
                        })
                        print(f"    ✅ {hostname}: {config_path}")
        
        return True
    
    def _save_service_states(self) -> bool:
        """서비스 상태 저장"""
        all_nodes = self._get_all_nodes()
        services = ['slurmctld', 'slurmd', 'slurmdbd', 'munge', 'mariadb']
        
        for node in all_nodes:
            hostname = node['hostname']
            self.snapshot_data['service_states'][hostname] = {}
            
            for service in services:
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, f"systemctl is-active {service}", show_output=False
                )
                self.snapshot_data['service_states'][hostname][service] = {'running': exit_code == 0}
        
        return True
    
    def _save_package_lists(self) -> bool:
        """패키지 목록 저장"""
        all_nodes = self._get_all_nodes()
        
        for node in all_nodes:
            hostname = node['hostname']
            os_type = node.get('os_type', 'centos8')
            
            if 'centos' in os_type or 'rhel' in os_type:
                exit_code, stdout, _ = self.ssh_manager.execute_command(
                    hostname, "rpm -qa | grep -E 'slurm|munge'", show_output=False
                )
            else:
                exit_code, stdout, _ = self.ssh_manager.execute_command(
                    hostname, "dpkg -l | grep -E 'slurm|munge' | awk '{print $2}'", show_output=False
                )
            
            if exit_code == 0:
                self.snapshot_data['installed_packages'][hostname] = stdout.strip().split('\n')
        
        return True
    
    def _save_snapshot_metadata(self):
        """스냅샷 메타데이터 저장"""
        metadata_file = self.rollback_dir / f"{self.snapshot_id}.json"
        
        with open(metadata_file, 'w') as f:
            json.dump(self.snapshot_data, f, indent=2)
    
    def rollback_to_snapshot(self, snapshot_id: Optional[str] = None) -> bool:
        """스냅샷으로 롤백"""
        if snapshot_id is None:
            snapshot_id = self._get_latest_snapshot()
        
        if not snapshot_id:
            print("❌ 사용 가능한 스냅샷이 없습니다.")
            return False
        
        print(f"\n🔄 롤백 시작: {snapshot_id}")
        
        if not self._load_snapshot(snapshot_id):
            print("❌ 스냅샷 로드 실패")
            return False
        
        # 1. 서비스 중지
        print("  ⏹️  서비스 중지 중...")
        self._stop_all_services()
        
        # 2. 설정 파일 복원
        print("  📄 설정 파일 복원 중...")
        self._restore_configurations()
        
        # 3. 데이터베이스 복원
        if self.snapshot_data.get('database_backup'):
            print("  🗄️  데이터베이스 복원 중...")
            self._restore_database()
        
        # 4. 서비스 재시작
        print("  ▶️  서비스 재시작 중...")
        self._restore_services()
        
        print(f"✅ 롤백 완료: {snapshot_id}\n")
        return True
    
    def _load_snapshot(self, snapshot_id: str) -> bool:
        """스냅샷 로드"""
        metadata_file = self.rollback_dir / f"{snapshot_id}.json"
        
        if not metadata_file.exists():
            return False
        
        with open(metadata_file, 'r') as f:
            self.snapshot_data = json.load(f)
        
        self.snapshot_id = snapshot_id
        return True
    
    def _stop_all_services(self):
        """모든 Slurm 서비스 중지"""
        all_nodes = self._get_all_nodes()
        services = ['slurmctld', 'slurmd', 'slurmdbd']
        
        for node in all_nodes:
            hostname = node['hostname']
            for service in services:
                self.ssh_manager.execute_command(
                    hostname, f"systemctl stop {service} 2>/dev/null", show_output=False
                )
    
    def _restore_configurations(self):
        """설정 파일 복원"""
        for hostname, backups in self.snapshot_data.get('config_backups', {}).items():
            for backup in backups:
                local_path = backup['backup_path']
                remote_path = backup['original_path']
                
                if os.path.exists(local_path):
                    self.ssh_manager.upload_file(local_path, f"{hostname}:{remote_path}")
                    print(f"    ✅ {hostname}: {remote_path}")
    
    def _restore_database(self):
        """데이터베이스 복원"""
        db_backup = self.snapshot_data.get('database_backup')
        if not db_backup or not os.path.exists(db_backup):
            return
        
        controller = self.config['nodes']['controller']
        hostname = controller['hostname']
        db_config = self.config['database']
        
        remote_backup = f"/tmp/restore_{os.path.basename(db_backup)}"
        
        # 백업 파일 업로드
        self.ssh_manager.upload_file(db_backup, f"{hostname}:{remote_backup}")
        
        # 데이터베이스 복원
        restore_cmd = f"mysql -u {db_config['username']} -p'{db_config['password']}' " \
                     f"{db_config['database_name']} < {remote_backup}"
        
        self.ssh_manager.execute_command(hostname, restore_cmd, show_output=False, timeout=300)
        self.ssh_manager.execute_command(hostname, f"rm -f {remote_backup}", show_output=False)
        
        print(f"    ✅ DB 복원 완료")
    
    def _restore_services(self):
        """서비스 복원"""
        for hostname, services in self.snapshot_data.get('service_states', {}).items():
            for service, state in services.items():
                if state.get('running'):
                    self.ssh_manager.execute_command(
                        hostname, f"systemctl start {service}", show_output=False
                    )
    
    def list_snapshots(self) -> List[Dict[str, Any]]:
        """스냅샷 목록 조회"""
        snapshots = []
        
        for metadata_file in self.rollback_dir.glob("*.json"):
            try:
                with open(metadata_file, 'r') as f:
                    data = json.load(f)
                    snapshots.append({
                        'id': metadata_file.stem,
                        'timestamp': data.get('timestamp'),
                        'stage': data.get('stage'),
                        'has_db': bool(data.get('database_backup'))
                    })
            except:
                pass
        
        return sorted(snapshots, key=lambda x: x['timestamp'], reverse=True)
    
    def _get_latest_snapshot(self) -> Optional[str]:
        """최신 스냅샷 ID 반환"""
        snapshots = self.list_snapshots()
        return snapshots[0]['id'] if snapshots else None
    
    def _get_all_nodes(self) -> List[Dict[str, Any]]:
        """모든 노드 목록"""
        return [self.config['nodes']['controller']] + self.config['nodes']['compute_nodes']


def main():
    """테스트 메인 함수"""
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python full_system_rollback.py <config_file> [create|rollback|list]")
        return
    
    config_file = sys.argv[1]
    command = sys.argv[2] if len(sys.argv) > 2 else 'create'
    
    try:
        parser = ConfigParser(config_file)
        config = parser.load_config()
        
        ssh_manager = SSHManager()
        all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
        
        for node in all_nodes:
            ssh_manager.add_node(node)
        
        ssh_manager.connect_all_nodes()
        
        rollback_mgr = FullSystemRollback(config, ssh_manager)
        
        if command == 'create':
            stage = int(sys.argv[3]) if len(sys.argv) > 3 else 1
            snapshot_id = rollback_mgr.create_full_snapshot(stage)
            print(f"\n생성된 스냅샷: {snapshot_id}")
            
        elif command == 'rollback':
            snapshot_id = sys.argv[3] if len(sys.argv) > 3 else None
            rollback_mgr.rollback_to_snapshot(snapshot_id)
            
        elif command == 'list':
            snapshots = rollback_mgr.list_snapshots()
            print("\n사용 가능한 스냅샷:")
            for snap in snapshots:
                db_info = "DB 포함" if snap['has_db'] else "DB 없음"
                print(f"  - {snap['id']} (Stage {snap['stage']}, {db_info})")
                print(f"    생성: {snap['timestamp']}")
        
        ssh_manager.disconnect_all()
        
    except Exception as e:
        print(f"오류 발생: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
