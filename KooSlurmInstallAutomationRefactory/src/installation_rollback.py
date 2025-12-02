#!/usr/bin/env python3
"""
Slurm 설치 롤백 모듈
설치 실패 시 이전 상태로 복구하는 기능
"""

import os
import time
import json
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime
from ssh_manager import SSHManager


class InstallationRollback:
    """설치 롤백 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        
        # 롤백 정보 저장 경로
        self.rollback_dir = Path('./rollback_snapshots')
        self.rollback_dir.mkdir(parents=True, exist_ok=True)
        
        # 현재 스냅샷 정보
        self.snapshot_id = None
        self.snapshot_data = {
            'timestamp': None,
            'stage': None,
            'backups': [],
            'installed_packages': [],
            'created_users': [],
            'created_directories': [],
            'modified_files': [],
            'services': []
        }
    
    def create_snapshot(self, stage: int) -> str:
        """설치 전 스냅샷 생성
        
        Args:
            stage: 설치 단계 (1, 2, 3)
            
        Returns:
            스냅샷 ID
        """
        print(f"\n📸 설치 전 스냅샷 생성 중 (Stage {stage})...")
        
        self.snapshot_id = f"snapshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}_stage{stage}"
        self.snapshot_data['timestamp'] = datetime.now().isoformat()
        self.snapshot_data['stage'] = stage
        
        # 각 노드에서 백업 생성
        all_nodes = self._get_all_nodes()
        
        for node in all_nodes:
            hostname = node['hostname']
            print(f"  📦 {hostname}: 스냅샷 생성 중...")
            
            # 기존 Slurm 설정 백업
            self._backup_slurm_configs(hostname)
            
            # 설치된 패키지 목록 저장
            self._save_installed_packages(hostname)
            
            # 실행 중인 서비스 목록 저장
            self._save_running_services(hostname)
        
        # 스냅샷 정보 저장
        self._save_snapshot()
        
        print(f"✅ 스냅샷 생성 완료: {self.snapshot_id}")
        return self.snapshot_id
    
    def rollback(self, snapshot_id: Optional[str] = None) -> bool:
        """스냅샷으로 롤백
        
        Args:
            snapshot_id: 롤백할 스냅샷 ID (None이면 최신 스냅샷)
            
        Returns:
            롤백 성공 여부
        """
        if snapshot_id is None:
            snapshot_id = self._get_latest_snapshot()
        
        if snapshot_id is None:
            print("❌ 사용 가능한 스냅샷이 없습니다.")
            return False
        
        print(f"\n🔄 롤백 시작: {snapshot_id}")
        
        # 스냅샷 정보 로드
        if not self._load_snapshot(snapshot_id):
            print("❌ 스냅샷 로드 실패")
            return False
        
        # 롤백 실행
        all_nodes = self._get_all_nodes()
        
        for node in all_nodes:
            hostname = node['hostname']
            print(f"  🔙 {hostname}: 롤백 중...")
            
            # Slurm 서비스 중지
            self._stop_slurm_services(hostname)
            
            # 설정 파일 복원
            self._restore_slurm_configs(hostname)
            
            # 생성된 디렉토리 제거
            self._remove_created_directories(hostname)
            
            # 생성된 사용자 제거
            self._remove_created_users(hostname)
        
        print("✅ 롤백 완료")
        return True
    
    def _backup_slurm_configs(self, hostname: str):
        """Slurm 설정 파일 백업"""
        config_paths = [
            '/usr/local/slurm/etc/slurm.conf',
            '/etc/slurm/slurm.conf',
            '/usr/local/slurm/etc/slurmdbd.conf',
            '/etc/munge/munge.key'
        ]
        
        backup_dir = f"/tmp/slurm_backup_{self.snapshot_id}"
        self.ssh_manager.execute_command(hostname, f"mkdir -p {backup_dir}", show_output=False)
        
        for config_path in config_paths:
            # 파일이 존재하는지 확인
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, f"test -f {config_path}", show_output=False
            )
            
            if exit_code == 0:
                # 백업
                backup_path = f"{backup_dir}/{Path(config_path).name}"
                self.ssh_manager.execute_command(
                    hostname, f"cp -p {config_path} {backup_path}", show_output=False
                )
                
                self.snapshot_data['backups'].append({
                    'hostname': hostname,
                    'original_path': config_path,
                    'backup_path': backup_path
                })
    
    def _save_installed_packages(self, hostname: str):
        """현재 설치된 패키지 목록 저장"""
        # CentOS/RHEL
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            hostname, "rpm -qa --qf '%{NAME}\\n' 2>/dev/null || dpkg-query -W -f='${Package}\\n'",
            show_output=False
        )
        
        if exit_code == 0:
            packages = stdout.strip().split('\n')
            self.snapshot_data['installed_packages'].append({
                'hostname': hostname,
                'packages': packages
            })
    
    def _save_running_services(self, hostname: str):
        """실행 중인 서비스 목록 저장"""
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            hostname, "systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}'",
            show_output=False
        )
        
        if exit_code == 0:
            services = stdout.strip().split('\n')
            self.snapshot_data['services'].append({
                'hostname': hostname,
                'running_services': services
            })
    
    def _stop_slurm_services(self, hostname: str):
        """Slurm 관련 서비스 중지"""
        services = ['slurmctld', 'slurmd', 'slurmdbd', 'munge']
        
        for service in services:
            self.ssh_manager.execute_command(
                hostname, f"systemctl stop {service}", show_output=False
            )
    
    def _restore_slurm_configs(self, hostname: str):
        """Slurm 설정 파일 복원"""
        for backup in self.snapshot_data['backups']:
            if backup['hostname'] == hostname:
                self.ssh_manager.execute_command(
                    hostname,
                    f"cp -p {backup['backup_path']} {backup['original_path']}",
                    show_output=False
                )
    
    def _remove_created_directories(self, hostname: str):
        """설치 중 생성된 디렉토리 제거"""
        directories = [
            '/usr/local/slurm',
            '/var/log/slurm',
            '/var/spool/slurm'
        ]
        
        for directory in directories:
            self.ssh_manager.execute_command(
                hostname, f"rm -rf {directory}", show_output=False
            )
    
    def _remove_created_users(self, hostname: str):
        """설치 중 생성된 사용자 제거"""
        users = ['slurm']
        
        for user in users:
            self.ssh_manager.execute_command(
                hostname, f"userdel -r {user}", show_output=False
            )
    
    def _save_snapshot(self):
        """스냅샷 정보를 파일로 저장"""
        snapshot_file = self.rollback_dir / f"{self.snapshot_id}.json"
        
        with open(snapshot_file, 'w', encoding='utf-8') as f:
            json.dump(self.snapshot_data, f, indent=2, ensure_ascii=False)
        
        print(f"  💾 스냅샷 저장: {snapshot_file}")
    
    def _load_snapshot(self, snapshot_id: str) -> bool:
        """스냅샷 정보 로드"""
        snapshot_file = self.rollback_dir / f"{snapshot_id}.json"
        
        if not snapshot_file.exists():
            return False
        
        with open(snapshot_file, 'r', encoding='utf-8') as f:
            self.snapshot_data = json.load(f)
        
        self.snapshot_id = snapshot_id
        return True
    
    def _get_latest_snapshot(self) -> Optional[str]:
        """최신 스냅샷 ID 반환"""
        snapshots = list(self.rollback_dir.glob("snapshot_*.json"))
        
        if not snapshots:
            return None
        
        # 파일명 정렬 (최신이 마지막)
        snapshots.sort()
        latest = snapshots[-1]
        
        return latest.stem
    
    def list_snapshots(self):
        """사용 가능한 스냅샷 목록 출력"""
        snapshots = list(self.rollback_dir.glob("snapshot_*.json"))
        
        if not snapshots:
            print("사용 가능한 스냅샷이 없습니다.")
            return
        
        print("\n📸 사용 가능한 스냅샷:")
        print("-" * 60)
        
        for snapshot_file in sorted(snapshots):
            with open(snapshot_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            print(f"  ID: {snapshot_file.stem}")
            print(f"  시간: {data['timestamp']}")
            print(f"  단계: Stage {data['stage']}")
            print(f"  백업 파일: {len(data['backups'])}개")
            print("-" * 60)
    
    def _get_all_nodes(self) -> List[Dict[str, Any]]:
        """모든 노드 정보 반환"""
        nodes = []
        
        # config가 비어있으면 빈 리스트 반환
        if not self.config or 'nodes' not in self.config:
            return nodes
        
        if 'controller' in self.config['nodes']:
            controller = self.config['nodes']['controller'].copy()
            controller['node_type'] = 'controller'
            nodes.append(controller)
        
        for compute_node in self.config['nodes'].get('compute_nodes', []):
            node = compute_node.copy()
            node['node_type'] = 'compute'
            nodes.append(node)
        
        return nodes


def main():
    """테스트 메인 함수"""
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python installation_rollback.py <config_file> [--list|--rollback <snapshot_id>]")
        return
    
    try:
        # 설정 파일 로드
        parser = ConfigParser(sys.argv[1])
        config = parser.load_config()
        
        # SSH 관리자 설정
        ssh_manager = SSHManager()
        all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
        for node in all_nodes:
            ssh_manager.add_node(node)
        
        # 롤백 관리자 생성
        rollback = InstallationRollback(config, ssh_manager)
        
        # 명령 처리
        if len(sys.argv) > 2:
            command = sys.argv[2]
            
            if command == '--list':
                rollback.list_snapshots()
            elif command == '--rollback':
                snapshot_id = sys.argv[3] if len(sys.argv) > 3 else None
                rollback.rollback(snapshot_id)
            elif command == '--create':
                stage = int(sys.argv[3]) if len(sys.argv) > 3 else 1
                rollback.create_snapshot(stage)
        else:
            rollback.list_snapshots()
        
        ssh_manager.disconnect_all()
        
    except Exception as e:
        print(f"롤백 처리 중 오류 발생: {e}")


if __name__ == "__main__":
    main()
