#!/usr/bin/env python3
"""
KooSlurmInstallAutomation - 메인 실행 스크립트
Slurm 클러스터 자동 설치를 총괄하는 메인 프로그램
"""

import sys
import os
import argparse
import time
from pathlib import Path
from typing import TYPE_CHECKING

# 현재 디렉토리를 Python 경로에 추가
sys.path.insert(0, str(Path(__file__).parent))

import config_parser
import ssh_manager
import os_manager
import slurm_installer
import pre_install_validator
import advanced_features
import slurm_cleanup
import performance_monitor
import installation_rollback
import utils


def parse_arguments():
    """명령행 인자 파싱"""
    parser = argparse.ArgumentParser(
        description='Slurm 클러스터 자동 설치 도구',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 기본 설치 (Stage 1)
  python main.py -c examples/2node_example.yaml

  # 모든 단계 설치
  python main.py -c examples/4node_research_cluster.yaml --stage all

  # 설치 전 검증만 실행
  python main.py -c config.yaml --validate-only

  # 특정 단계만 실행
  python main.py -c config.yaml --stage 2

  # 로그 레벨 설정
  python main.py -c config.yaml --log-level debug
        """
    )
    
    parser.add_argument(
        '-c', '--config',
        required=False,  # 롤백 기능은 config 없이도 사용 가능
        help='설정 파일 경로 (YAML)'
    )
    
    parser.add_argument(
        '--stage',
        choices=['1', '2', '3', 'all'],
        help='설치 단계 (기본값: 설정파일의 stage 값 사용)'
    )
    
    parser.add_argument(
        '--validate-only',
        action='store_true',
        help='설치 전 검증만 실행하고 종료'
    )
    
    parser.add_argument(
        '--skip-validation',
        action='store_true',
        help='설치 전 검증 건너뛰기'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='실제 설치 없이 시뮬레이션만 실행'
    )
    
    parser.add_argument(
        '--log-level',
        choices=['debug', 'info', 'warning', 'error'],
        default='info',
        help='로그 레벨 (기본값: info)'
    )
    
    parser.add_argument(
        '--max-workers',
        type=int,
        default=10,
        help='병렬 작업 최대 수 (기본값: 10)'
    )
    
    parser.add_argument(
        '--continue-on-error',
        action='store_true',
        help='오류 발생 시에도 계속 진행'
    )
    
    parser.add_argument(
        '--cleanup',
        action='store_true',
        help='기존 Slurm 설치를 제거하고 초기화'
    )
    
    parser.add_argument(
        '--force-cleanup',
        action='store_true',
        help='확인 없이 기존 Slurm 강제 제거'
    )
    
    parser.add_argument(
        '--create-snapshot',
        action='store_true',
        help='설치 전 스냅샷 생성 (롯백용)'
    )
    
    parser.add_argument(
        '--rollback',
        metavar='SNAPSHOT_ID',
        help='지정된 스냅샷으로 롯백'
    )
    
    parser.add_argument(
        '--list-snapshots',
        action='store_true',
        help='사용 가능한 스냅샷 목록 표시'
    )
    
    return parser.parse_args()


class SlurmClusterInstaller:
    """Slurm 클러스터 설치 총괄 클래스"""
    
    def __init__(self, args):
        self.args = args
        self.config = None
        self.config_parser = None
        self.ssh_manager = None
        self.install_stage = None
        
        # 로깅 설정
        self.logger = utils.setup_logging(args.log_level)
        
        # 성능 모니터링 초기화
        self.performance_monitor = performance_monitor.PerformanceMonitor()
        
        # 롤백 관리자 초기화
        self.rollback_manager = None
        
        print_banner()
    
    def load_and_validate_config(self) -> bool:
        """설정 파일 로드 및 검증"""
        try:
            print("📋 설정 파일 로드 중...")
            
            self.config_parser = ConfigParser(self.args.config)
            self.config = self.config_parser.load_config()
            
            if not self.config_parser.validate_config():
                print("❌ 설정 파일 검증 실패!")
                return False
            
            # 설치 단계 결정
            if self.args.stage:
                if self.args.stage == 'all':
                    self.install_stage = 3
                else:
                    self.install_stage = int(self.args.stage)
            else:
                self.install_stage = self.config_parser.get_install_stage()
            
            print(f"✅ 설정 파일 검증 완료 (설치 단계: {self.install_stage})")
            self.config_parser.print_config_summary()
            
            return True
            
        except Exception as e:
            print(f"❌ 설정 파일 처리 실패: {e}")
            return False
    
    def setup_ssh_connections(self) -> bool:
        """SSH 연결 설정"""
        try:
            print("\n🔌 SSH 연결 설정 중...")
            
            self.ssh_manager = SSHManager()
            
            # 모든 노드 추가
            all_nodes = self.config_parser.get_node_list()
            for node in all_nodes:
                self.ssh_manager.add_node(node)
            
            # 연결 테스트
            connection_results = self.ssh_manager.connect_all_nodes(
                max_workers=self.args.max_workers
            )
            
            # 연결 실패 노드 체크
            failed_nodes = [hostname for hostname, success in connection_results.items() if not success]
            
            if failed_nodes and not self.args.continue_on_error:
                print(f"❌ SSH 연결 실패 노드: {failed_nodes}")
                return False
            
            return True
            
        except Exception as e:
            print(f"❌ SSH 연결 설정 실패: {e}")
            return False
    
    def run_pre_install_validation(self) -> bool:
        """설치 전 검증 실행"""
        if self.args.skip_validation:
            print("⏭️  설치 전 검증 건너뛰기")
            return True
        
        try:
            print("\n🔍 설치 전 검증 시작...")
            
            validator = PreInstallValidator(self.config, self.ssh_manager)
            validation_results = validator.run_full_validation()
            
            if not validation_results['overall_success']:
                print("❌ 설치 전 검증 실패!")
                if not self.args.continue_on_error:
                    return False
            else:
                print("✅ 설치 전 검증 완료")
            
            return True
            
        except Exception as e:
            print(f"❌ 설치 전 검증 중 오류: {e}")
            return False if not self.args.continue_on_error else True
    
    def install_stage1_basic(self) -> bool:
        """Stage 1: 기본 Slurm 설치"""
        try:
            print("\n" + "="*60)
            print("🚀 STAGE 1: 기본 Slurm 설치 시작")
            print("="*60)
            
            if self.args.dry_run:
                print("🏃 DRY-RUN: Stage 1 설치 시뮬레이션")
                time.sleep(2)
                return True
            
            # 1. OS별 패키지 설치 및 시스템 설정
            if not self.setup_os_environment():
                return False
            
            # 2. NFS 서버 설정 (컨트롤러에서)
            if not self.setup_nfs_server():
                return False
            
            # 3. Slurm 설치
            installer = SlurmInstaller(self.config, self.ssh_manager)
            
            if not installer.install_slurm_on_all_nodes():
                return False
            
            if not installer.deploy_configuration_files():
                return False
            
            if not installer.setup_munge_authentication():
                return False
            
            if not installer.start_slurm_services():
                return False
            
            if not installer.verify_installation():
                return False
            
            print("✅ Stage 1 설치 완료!")
            return True
            
        except Exception as e:
            print(f"❌ Stage 1 설치 실패: {e}")
            return False
    
    def install_stage2_advanced(self) -> bool:
        """Stage 2: 고급 기능 설치"""
        try:
            print("\n" + "="*60)
            print("🔧 STAGE 2: 고급 기능 설치 시작")
            print("="*60)
            
            if self.args.dry_run:
                print("🏃 DRY-RUN: Stage 2 설치 시뮬레이션")
                time.sleep(2)
                return True
            
            advanced_installer = AdvancedFeaturesInstaller(self.config, self.ssh_manager)
            
            # 데이터베이스 설정
            if self.config_parser.is_feature_enabled('database'):
                if not advanced_installer.setup_database():
                    return False
            
            # 모니터링 시스템 설정
            if self.config_parser.is_feature_enabled('monitoring'):
                if not advanced_installer.setup_monitoring():
                    return False
            
            # 고가용성 설정
            if self.config_parser.is_feature_enabled('high_availability'):
                if not advanced_installer.setup_high_availability():
                    return False
            
            # Environment Modules 설정
            if self.config_parser.is_feature_enabled('environment_modules'):
                if not advanced_installer.setup_environment_modules():
                    return False
            
            print("✅ Stage 2 설치 완료!")
            return True
            
        except Exception as e:
            print(f"❌ Stage 2 설치 실패: {e}")
            return False
    
    def install_stage3_optimization(self) -> bool:
        """Stage 3: 운영 최적화"""
        with self.performance_monitor.start_operation("install_stage3_optimization"):
            try:
                print("\n" + "="*60)
                print("⚡ STAGE 3: 운영 최적화 시작")
                print("="*60)
                
                if self.args.dry_run:
                    print("🏃 DRY-RUN: Stage 3 설치 시뮬레이션")
                    time.sleep(2)
                    return True
                
                advanced_installer = AdvancedFeaturesInstaller(self.config, self.ssh_manager)
                
                # 성능 튜닝
                if not advanced_installer.apply_performance_tuning():
                    return False
                
                # 전력 관리 설정
                if self.config_parser.is_feature_enabled('power_management'):
                    if not advanced_installer.setup_power_management():
                        return False
                
                # 컨테이너 지원 설정
                if self.config_parser.is_feature_enabled('container_support'):
                    if not advanced_installer.setup_container_support():
                        return False
                
                # 병렬 파일시스템 설정
                if self.config_parser.is_feature_enabled('parallel_filesystems'):
                    if not advanced_installer.setup_parallel_filesystems():
                        return False
                
                # 백업 및 복구 설정
                if not advanced_installer.setup_backup_and_recovery():
                    return False
                
                print("✅ Stage 3 설치 완료!")
                return True
                
            except Exception as e:
                print(f"❌ Stage 3 설치 실패: {e}")
                return False
    
    def setup_os_environment(self) -> bool:
        """OS 환경 설정"""
        print("\n🖥️  OS 환경 설정 중...")
        
        try:
            all_nodes = self.config_parser.get_node_list()
            
            for node in all_nodes:
                hostname = node['hostname']
                os_type = node['os_type']
                
                print(f"🔧 {hostname}: OS 환경 설정...")
                
                # OS 관리자 생성
                os_manager = OSManagerFactory.create_manager(
                    self.ssh_manager, hostname, os_type
                )
                
                # OS 정보 감지
                os_info = os_manager.detect_os()
                print(f"   OS: {os_info.get('PRETTY_NAME', 'Unknown')}")
                
                # 시스템 업데이트
                if not os_manager.update_system():
                    print(f"⚠️  {hostname}: 시스템 업데이트 실패")
                
                # 개발 도구 설치
                if not os_manager.install_development_tools():
                    print(f"❌ {hostname}: 개발 도구 설치 실패")
                    if not self.args.continue_on_error:
                        return False
                
                # 방화벽 설정
                firewall_ports = self.config['network']['firewall']['ports']
                if not os_manager.configure_firewall(firewall_ports):
                    print(f"⚠️  {hostname}: 방화벽 설정 실패")
                
                # 사용자 생성
                cluster_users = self.config['users']['cluster_users']
                for user in cluster_users:
                    os_manager.create_user(
                        user['username'], user['uid'], user['gid'], user.get('groups', [])
                    )
                
                # NFS 클라이언트 설정 (컨트롤러 제외)
                if node['node_type'] != 'controller':
                    mount_points = self.config['shared_storage']['mount_points']
                    if not os_manager.configure_nfs_client(mount_points):
                        print(f"⚠️  {hostname}: NFS 클라이언트 설정 실패")
                
                # 시간 동기화 설정
                ntp_servers = self.config.get('time_synchronization', {}).get('ntp_servers')
                if not os_manager.configure_time_sync(ntp_servers):
                    print(f"⚠️  {hostname}: 시간 동기화 설정 실패")
            
            print("✅ OS 환경 설정 완료")
            return True
            
        except Exception as e:
            print(f"❌ OS 환경 설정 실패: {e}")
            return False
    
    def setup_nfs_server(self) -> bool:
        """NFS 서버 설정 (컨트롤러 노드)"""
        print("\n📁 NFS 서버 설정 중...")
        
        try:
            controller = self.config_parser.get_controller_node()
            if not controller:
                print("❌ 컨트롤러 노드 정보 없음")
                return False
            
            hostname = controller['hostname']
            mount_points = self.config['shared_storage']['mount_points']
            
            # NFS 서버 패키지 설치
            self.ssh_manager.execute_command(
                hostname, "yum install -y nfs-utils || apt install -y nfs-kernel-server"
            )
            
            # 공유 디렉토리 생성
            for mount in mount_points:
                source_dir = mount['source']
                self.ssh_manager.execute_command(hostname, f"mkdir -p {source_dir}")
                self.ssh_manager.execute_command(hostname, f"chmod 755 {source_dir}")
            
            # exports 파일 생성
            exports_content = "# NFS exports for Slurm cluster\n"
            network = self.config['network']['management_network']
            
            for mount in mount_points:
                source_dir = mount['source']
                options = mount.get('options', 'rw,sync,no_root_squash,no_subtree_check')
                exports_content += f"{source_dir} {network}({options})\n"
            
            # exports 파일 업로드
            self.ssh_manager.execute_command(
                hostname, f"echo '{exports_content}' > /etc/exports"
            )
            
            # NFS 서비스 시작
            nfs_services = ['rpcbind', 'nfs-server', 'nfs-kernel-server']
            for service in nfs_services:
                self.ssh_manager.execute_command(
                    hostname, f"systemctl enable {service}", show_output=False
                )
                self.ssh_manager.execute_command(
                    hostname, f"systemctl start {service}", show_output=False
                )
            
            # exports 적용
            self.ssh_manager.execute_command(hostname, "exportfs -ra")
            
            print(f"✅ {hostname}: NFS 서버 설정 완료")
            return True
            
        except Exception as e:
            print(f"❌ NFS 서버 설정 실패: {e}")
            return False
    
    def run_installation(self) -> bool:
        """설치 실행"""
        success = True
        
        # Stage 1: 기본 설치
        if self.install_stage >= 1:
            if not self.install_stage1_basic():
                success = False
                if not self.args.continue_on_error:
                    return False
        
        # Stage 2: 고급 기능
        if self.install_stage >= 2:
            if not self.install_stage2_advanced():
                success = False
                if not self.args.continue_on_error:
                    return False
        
        # Stage 3: 운영 최적화
        if self.install_stage >= 3:
            if not self.install_stage3_optimization():
                success = False
                if not self.args.continue_on_error:
                    return False
        
        return success
    
    def cleanup(self):
        """정리 작업"""
        if self.ssh_manager:
            self.ssh_manager.disconnect_all()
        
        # 성능 모니터링 종료 및 저장
        if self.performance_monitor:
            self.performance_monitor.stop_and_save()
    
    def run(self) -> int:
        """메인 실행 함수"""
        try:
            # 1. 설정 파일 로드 및 검증
            if not self.load_and_validate_config():
                return 1
            
            # 2. SSH 연결 설정
            if not self.setup_ssh_connections():
                return 1
            
            # 롤백 관리자 초기화
            self.rollback_manager = InstallationRollback(self.config, self.ssh_manager)
            
            # 스냅샷 목록 표시
            if self.args.list_snapshots:
                self.rollback_manager.list_snapshots()
                return 0
            
            # 롤백 실행
            if self.args.rollback:
                print("\n" + "="*60)
                print("🔄 롤백 작업 시작")
                print("="*60)
                
                if self.rollback_manager.rollback(self.args.rollback):
                    print("✅ 롤백 성공")
                    return 0
                else:
                    print("❌ 롤백 실패")
                    return 1
            
            # 2.5. 기존 Slurm 제거 (cleanup 옵션 사용 시)
            if self.args.cleanup or self.args.force_cleanup:
                print("\n" + "="*60)
                print("🧹 기존 Slurm 제거 작업 시작")
                print("="*60)
                
                cleanup = SlurmCleanup(self.config, self.ssh_manager)
                
                if not cleanup.cleanup_all_nodes(force=self.args.force_cleanup):
                    print("❌ 기존 Slurm 제거 실패")
                    if not self.args.continue_on_error:
                        return 1
                
                cleanup.verify_cleanup()
                print("\n✅ 기존 Slurm 제거 완료. 새로운 설치를 시작합니다...\n")
                time.sleep(3)
            
            # 스냅샷 생성 (옵션이거나 기본 동작)
            if self.args.create_snapshot or not self.args.skip_validation:
                self.rollback_manager.create_snapshot(self.install_stage)
            
            # 3. 설치 전 검증
            if not self.run_pre_install_validation():
                return 1
            
            # 검증만 실행하고 종료
            if self.args.validate_only:
                print("\n✅ 설치 전 검증이 완료되었습니다.")
                return 0
            
            # 4. 설치 실행
            start_time = time.time()
            
            if self.run_installation():
                end_time = time.time()
                elapsed_time = int(end_time - start_time)
                
                print_summary(True, elapsed_time, self.config_parser)
                return 0
            else:
                end_time = time.time()
                elapsed_time = int(end_time - start_time)
                
                print_summary(False, elapsed_time, self.config_parser)
                return 1
                
        except KeyboardInterrupt:
            print("\n\n⚠️  사용자에 의해 설치가 중단되었습니다.")
            return 1
        except Exception as e:
            print(f"\n❌ 예상치 못한 오류 발생: {e}")
            return 1
        finally:
            self.cleanup()


def main():
    """메인 함수"""
    args = parse_arguments()
    
    # 롤백 전용 명령은 config 없이도 실행 가능
    if args.list_snapshots and not args.config:
        from installation_rollback import InstallationRollback
        rollback = InstallationRollback({}, None)
        rollback.list_snapshots()
        return 0
    
    # 그 외 모든 명령은 config 필요
    if not args.config:
        print("❌ 설정 파일이 필요합니다. -c/--config 옵션을 사용하세요.")
        return 1
    
    # 설정 파일 존재 확인
    if not Path(args.config).exists():
        print(f"❌ 설정 파일을 찾을 수 없습니다: {args.config}")
        return 1
    
    # 설치 실행
    installer = SlurmClusterInstaller(args)
    return installer.run()


if __name__ == "__main__":
    sys.exit(main())
