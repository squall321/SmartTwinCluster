"""
Slurm 설정 관리 모듈
QoS 생성, Partition 업데이트, slurm.conf 수정 등
"""

import subprocess
import shutil
import os
import re
import tempfile
from datetime import datetime
from typing import List, Dict, Any, Optional

# Slurm 명령어 경로 import
from slurm_commands import (
    get_sacctmgr, get_scontrol,
    SINFO, SQUEUE, SACCT, SCONTROL, SACCTMGR, SUDO
)

# 시스템 명령어 절대 경로 (systemd 환경에서 PATH 제한)
CAT = '/bin/cat'
CP = '/bin/cp'
CHMOD = '/bin/chmod'
CHOWN = '/bin/chown'


class SlurmConfigManager:
    """Slurm 설정 관리 클래스"""

    def __init__(self, slurm_conf_path: str = '/etc/slurm/slurm.conf'):
        self.slurm_conf_path = slurm_conf_path
        # 소스 빌드 Slurm의 설정 파일 경로 (동기화용)
        self.local_slurm_conf_path = '/usr/local/slurm/etc/slurm.conf'
        # Use user-writable backup directory
        self.backup_dir = os.path.expanduser('~/.slurm_backups')

        # 백업 디렉토리 생성
        os.makedirs(self.backup_dir, exist_ok=True)
    
    def backup_config(self) -> str:
        """
        현재 slurm.conf 백업
        Returns: 백업 파일 경로
        """
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_path = os.path.join(
            self.backup_dir, 
            f'slurm.conf.backup.{timestamp}'
        )
        
        try:
            # Use sudo cp to copy the file (절대 경로 사용)
            subprocess.run(
                [SUDO, '-n', CP, '-p', self.slurm_conf_path, backup_path],
                check=True,
                capture_output=True
            )
            # Make the backup readable by current user (절대 경로 사용)
            subprocess.run(
                [SUDO, '-n', CHOWN, os.getenv('USER', 'koopark'), backup_path],
                check=True,
                capture_output=True
            )
            print(f"✅ Backup created: {backup_path}")
            return backup_path
        except Exception as e:
            print(f"❌ Backup failed: {e}")
            raise
    
    def restore_config(self, backup_path: str):
        """백업에서 복원"""
        try:
            subprocess.run(
                ['sudo', 'cp', '-p', backup_path, self.slurm_conf_path],
                check=True,
                capture_output=True
            )
            print(f"✅ Restored from: {backup_path}")
            self.reconfigure_slurm()
        except Exception as e:
            print(f"❌ Restore failed: {e}")
            raise
    
    def create_or_update_qos(self, qos_name: str, max_cores: int, 
                             priority: int = 1000) -> bool:
        """
        QoS 생성 또는 업데이트
        
        Args:
            qos_name: QoS 이름
            max_cores: 최대 코어 수
            priority: 우선순위
        
        Returns:
            성공 여부
        """
        try:
            # QoS 존재 여부 확인
            result = get_sacctmgr('show', 'qos', qos_name, '-n', '-P', use_sudo=True, check=False)
            
            qos_exists = bool(result.stdout.strip())
            
            if not qos_exists:
                # QoS 생성
                print(f"📝 Creating QoS: {qos_name}")
                get_sacctmgr('-i', 'add', 'qos', qos_name, use_sudo=True)
            else:
                print(f"📝 QoS already exists: {qos_name}")
            
            # MaxTRESPerJob 설정 (최대 코어 수)
            print(f"   Setting MaxTRESPerJob=cpu={max_cores}")
            get_sacctmgr('-i', 'modify', 'qos', qos_name, 'set', 
                        f'MaxTRESPerJob=cpu={max_cores}', use_sudo=True)
            
            # Priority 설정
            print(f"   Setting Priority={priority}")
            get_sacctmgr('-i', 'modify', 'qos', qos_name, 'set', 
                        f'Priority={priority}', use_sudo=True)
            
            print(f"✅ QoS {qos_name} configured successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to create/update QoS {qos_name}: {e}")
            return False
        except Exception as e:
            print(f"❌ Error: {e}")
            return False
    
    def delete_qos(self, qos_name: str) -> bool:
        """QoS 삭제"""
        try:
            print(f"🗑️  Deleting QoS: {qos_name}")
            get_sacctmgr('-i', 'delete', 'qos', qos_name, use_sudo=True)
            print(f"✅ QoS {qos_name} deleted")
            return True
        except Exception as e:
            print(f"❌ Failed to delete QoS {qos_name}: {e}")
            return False
    
    def update_partitions(self, groups: List[Dict[str, Any]], skip_qos: bool = False) -> bool:
        """
        slurm.conf의 파티션 섹션 업데이트
        
        Args:
            groups: 그룹 정보 리스트
                [{
                    'partitionName': 'group1',
                    'nodes': [{'hostname': 'node001', ...}, ...],
                    'qosName': 'group1_qos',
                    'allowedCoreSizes': [128, 256, 512]
                }, ...]
        
        Returns:
            성공 여부
        """
        try:
            # 백업 생성
            backup_path = self.backup_config()
            
            # slurm.conf 읽기 (use sudo to read - 절대 경로 사용)
            result = subprocess.run(
                [SUDO, '-n', CAT, self.slurm_conf_path],
                capture_output=True,
                text=True,
                check=True
            )
            lines = result.stdout.splitlines(keepends=True)
            
            # 파티션 섹션 제거 (기존 것 삭제)
            new_lines = []
            skip_partition = False
            
            for line in lines:
                # 파티션 섹션 시작
                if line.strip().startswith('PartitionName='):
                    skip_partition = True
                    continue
                
                # 다른 섹션 시작 (파티션 섹션 종료)
                if skip_partition and (
                    line.strip().startswith('NodeName=') or
                    line.strip().startswith('SlurmctldHost=') or
                    line.strip().startswith('#') and not line.strip().startswith('# Partition') or
                    line.strip() == ''
                ):
                    skip_partition = False
                
                if not skip_partition:
                    new_lines.append(line)
            
            # 새 파티션 추가
            partition_section = []
            partition_section.append("\n# Partitions (Auto-generated by Dashboard)\n")
            partition_section.append(f"# Generated at: {datetime.now().isoformat()}\n\n")
            
            for group in groups:
                partition_name = group['partitionName']
                qos_name = group['qosName']
                nodes = group.get('nodes', [])
                
                if not nodes:
                    continue
                
                # 노드 리스트 생성
                node_list = ','.join([n['hostname'] for n in nodes])
                
                # 파티션 정의
                partition_line = f"PartitionName={partition_name} "
                partition_line += f"Nodes={node_list} "
                partition_line += f"Default=YES "
                partition_line += f"MaxTime=INFINITE "
                partition_line += f"State=UP "
                
                # QoS 지정 (only if not skipping)
                if not skip_qos and qos_name:
                    partition_line += f"QOS={qos_name} "
                    # AllowQos도 설정 (사용자가 이 QoS를 선택할 수 있도록)
                    partition_line += f"AllowQos={qos_name}"
                
                partition_line += "\n"
                partition_section.append(partition_line)
            
            # 파티션 섹션을 파일 끝에 추가
            new_lines.extend(partition_section)
            
            # 파일 쓰기 (use sudo and temporary file)
            temp_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.conf')
            try:
                temp_file.writelines(new_lines)
                temp_file.close()

                # Copy temp file to slurm.conf with sudo (절대 경로 사용)
                subprocess.run(
                    [SUDO, '-n', CP, '-p', temp_file.name, self.slurm_conf_path],
                    check=True,
                    capture_output=True
                )

                # Fix permissions: 644, owned by slurm:slurm (절대 경로 사용)
                subprocess.run(
                    [SUDO, '-n', CHMOD, '644', self.slurm_conf_path],
                    check=True,
                    capture_output=True
                )
                subprocess.run(
                    [SUDO, '-n', CHOWN, 'slurm:slurm', self.slurm_conf_path],
                    check=True,
                    capture_output=True
                )

                # 소스 빌드 Slurm 설정 파일도 동기화 (존재하는 경우)
                if os.path.exists(os.path.dirname(self.local_slurm_conf_path)):
                    subprocess.run(
                        [SUDO, '-n', CP, '-p', temp_file.name, self.local_slurm_conf_path],
                        check=True,
                        capture_output=True
                    )
                    subprocess.run(
                        [SUDO, '-n', CHMOD, '644', self.local_slurm_conf_path],
                        check=True,
                        capture_output=True
                    )
                    subprocess.run(
                        [SUDO, '-n', CHOWN, 'slurm:slurm', self.local_slurm_conf_path],
                        check=True,
                        capture_output=True
                    )
                    print(f"✅ Also synced to {self.local_slurm_conf_path}")
            finally:
                # Clean up temp file
                os.unlink(temp_file.name)
            
            print(f"✅ Updated partitions in {self.slurm_conf_path}")
            print(f"   Total partitions: {len(groups)}")
            
            # 설정 검증
            if self.validate_config():
                # Slurm 재설정
                self.reconfigure_slurm()
                return True
            else:
                # 검증 실패 시 롤백
                print("❌ Configuration validation failed, rolling back...")
                self.restore_config(backup_path)
                return False
                
        except Exception as e:
            print(f"❌ Failed to update partitions: {e}")
            # 오류 발생 시 롤백
            if 'backup_path' in locals():
                self.restore_config(backup_path)
            return False
    
    def validate_config(self) -> bool:
        """
        slurm.conf 검증
        
        Returns:
            유효하면 True
        """
        try:
            # scontrol show config로 검증
            result = get_scontrol('show', 'config', use_sudo=True, timeout=10, check=False)
            
            if result.returncode == 0:
                print("✅ Configuration is valid")
                return True
            else:
                print(f"❌ Configuration is invalid: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"❌ Validation error: {e}")
            return False
    
    def reconfigure_slurm(self) -> bool:
        """
        Slurm 재설정 (scontrol reconfigure)
        
        Returns:
            성공 여부
        """
        try:
            print("🔄 Reconfiguring Slurm...")
            get_scontrol('reconfigure', use_sudo=True, timeout=30)
            print("✅ Slurm reconfigured successfully")
            return True
        except Exception as e:
            print(f"❌ Failed to reconfigure Slurm: {e}")
            return False
    
    def apply_configuration(self, groups: List[Dict[str, Any]], 
                           dry_run: bool = False,
                           skip_qos: bool = False) -> Dict[str, Any]:
        """
        전체 설정 적용 (QoS + Partitions)
        
        Args:
            groups: 그룹 정보
            dry_run: True면 실제 적용하지 않고 시뮬레이션만
            skip_qos: True면 QoS 생성 건너뛰기 (slurmdbd 미설치 시)
        
        Returns:
            결과 딕셔너리
        """
        results = {
            'success': True,
            'qos_created': [],
            'qos_failed': [],
            'partitions_updated': False,
            'errors': []
        }
        
        if dry_run:
            print("🎭 DRY RUN MODE - No actual changes will be made")
            results['dry_run'] = True
            return results
        
        try:
            # 1. QoS 생성/업데이트 (선택적)
            if skip_qos:
                print("\n" + "="*60)
                print("Step 1: QoS Management (SKIPPED)")
                print("="*60)
                print("⚠️  QoS creation skipped (slurmdbd not configured)")
                print("   Partitions will be created without QoS restrictions")
            else:
                print("\n" + "="*60)
                print("Step 1: Creating/Updating QoS")
                print("="*60)
                
                for group in groups:
                    qos_name = group.get('qosName')
                    if not qos_name:
                        continue
                    
                    allowed_cores = group.get('allowedCoreSizes', [])
                    max_cores = max(allowed_cores) if allowed_cores else 1024
                    priority = 1000 + group.get('id', 0) * 100
                    
                    success = self.create_or_update_qos(qos_name, max_cores, priority)
                    
                    if success:
                        results['qos_created'].append(qos_name)
                    else:
                        results['qos_failed'].append(qos_name)
                        # QoS 실패를 경고로만 처리 (파티션 설정은 계속 진행)
                        print(f"⚠️  Warning: QoS {qos_name} failed, but continuing with partition setup...")
                        # results['success'] = False  # 주석 처리
            
            # 2. 파티션 업데이트
            print("\n" + "="*60)
            print("Step 2: Updating Partitions")
            print("="*60)
            
            # QoS를 스킵했거나 실패한 경우 QoS 설정 없이 파티션만 업데이트
            should_skip_qos_in_partition = skip_qos or len(results['qos_failed']) > 0
            if should_skip_qos_in_partition:
                print("⚠️  QoS will not be configured in partitions")
            
            partitions_success = self.update_partitions(groups, skip_qos=should_skip_qos_in_partition)
            results['partitions_updated'] = partitions_success
            
            if not partitions_success:
                results['success'] = False
                results['errors'].append("Failed to update partitions")
            
            # 3. 최종 결과
            print("\n" + "="*60)
            print("Configuration Apply Summary")
            print("="*60)
            print(f"QoS Created/Updated: {len(results['qos_created'])}")
            print(f"QoS Failed: {len(results['qos_failed'])}")
            print(f"Partitions Updated: {partitions_success}")
            print(f"Overall Success: {results['success']}")
            print("="*60 + "\n")
            
            return results
            
        except Exception as e:
            print(f"❌ Configuration apply failed: {e}")
            results['success'] = False
            results['errors'].append(str(e))
            return results
    
    def get_current_qos_list(self) -> List[Dict[str, Any]]:
        """현재 설정된 QoS 목록 조회"""
        try:
            result = get_sacctmgr('show', 'qos', '-n', '-P', 
                                 'format=Name,Priority,MaxTRESPerJob', 
                                 use_sudo=True)
            
            qos_list = []
            for line in result.stdout.strip().split('\n'):
                if not line:
                    continue
                
                parts = line.split('|')
                if len(parts) >= 2:
                    qos_list.append({
                        'name': parts[0],
                        'priority': parts[1] if len(parts) > 1 else None,
                        'maxTRES': parts[2] if len(parts) > 2 else None,
                    })
            
            return qos_list
            
        except Exception as e:
            print(f"Error getting QoS list: {e}")
            return []
    
    def get_current_partitions(self) -> List[Dict[str, Any]]:
        """현재 설정된 파티션 목록 조회"""
        try:
            result = get_scontrol('show', 'partition', '-o', use_sudo=True)
            
            partitions = []
            for line in result.stdout.strip().split('\n'):
                if not line:
                    continue
                
                partition_info = {}
                for part in line.split():
                    if '=' in part:
                        key, value = part.split('=', 1)
                        partition_info[key] = value
                
                partitions.append({
                    'name': partition_info.get('PartitionName'),
                    'nodes': partition_info.get('Nodes'),
                    'state': partition_info.get('State'),
                    'qos': partition_info.get('QOS'),
                    'default': partition_info.get('Default') == 'YES',
                })
            
            return partitions
            
        except Exception as e:
            print(f"Error getting partitions: {e}")
            return []


# Slurm 설정 파일 경로 (환경변수로 override 가능)
# 기본값: /etc/slurm/slurm.conf (apt/yum 패키지 설치 환경)
# 소스 빌드: /usr/local/slurm/etc/slurm.conf
SLURM_CONF_PATH = os.getenv('SLURM_CONF_PATH', '/etc/slurm/slurm.conf')

# 전역 인스턴스
slurm_config = SlurmConfigManager(slurm_conf_path=SLURM_CONF_PATH)


# 편의 함수들
def create_qos(group: Dict[str, Any]) -> bool:
    """QoS 생성 (편의 함수)"""
    qos_name = group.get('qosName')
    allowed_cores = group.get('allowedCoreSizes', [])
    max_cores = max(allowed_cores) if allowed_cores else 1024
    priority = 1000 + group.get('id', 0) * 100
    
    return slurm_config.create_or_update_qos(qos_name, max_cores, priority)


def update_partitions(groups: List[Dict[str, Any]]) -> bool:
    """파티션 업데이트 (편의 함수)"""
    return slurm_config.update_partitions(groups)


def reconfigure_slurm() -> bool:
    """Slurm 재설정 (편의 함수)"""
    return slurm_config.reconfigure_slurm()


def apply_full_configuration(groups: List[Dict[str, Any]], 
                            dry_run: bool = False,
                            skip_qos: bool = False) -> Dict[str, Any]:  # False로 변경
    """전체 설정 적용 (편의 함수)
    
    Args:
        skip_qos: True면 QoS 생성 건너뛰기 (slurmdbd 설치 후 False로 변경)
    """
    return slurm_config.apply_configuration(groups, dry_run, skip_qos)
