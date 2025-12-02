#!/usr/bin/env python3
"""
Slurm 설치 자동화 - 설치 전 검증
시스템 요구사항과 네트워크 환경을 검증하는 모듈
"""

import ipaddress
import re
from typing import Dict, List, Optional, Tuple, Any
from ssh_manager import SSHManager
from concurrent.futures import ThreadPoolExecutor, as_completed
import time


class PreInstallValidator:
    """설치 전 검증 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.validation_results = {}
        
    def run_full_validation(self) -> Dict[str, Any]:
        """전체 검증 실행"""
        print("🔍 설치 전 검증 시작...")
        
        results = {
            'network_connectivity': self.validate_network_connectivity(),
            'system_requirements': self.validate_system_requirements(),
            'storage_requirements': self.validate_storage_requirements(),
            'user_permissions': self.validate_user_permissions(),
            'port_availability': self.validate_port_availability(),
            'disk_space': self.validate_disk_space(),
            'package_repositories': self.validate_package_repositories(),
            'overall_success': True
        }
        
        # 전체 성공 여부 결정
        for key, value in results.items():
            if key != 'overall_success' and isinstance(value, dict):
                if not value.get('success', False):
                    results['overall_success'] = False
                    break
        
        self.print_validation_summary(results)
        return results
    
    def validate_network_connectivity(self) -> Dict[str, Any]:
        """네트워크 연결성 검증"""
        print("\n🌐 네트워크 연결성 검증 중...")
        
        results = {
            'success': True,
            'details': {},
            'warnings': [],
            'errors': []
        }
        
        all_nodes = self._get_all_nodes()
        
        # 1. 기본 연결성 테스트
        connectivity_results = self.ssh_manager.test_all_nodes_connectivity()
        
        for hostname, node_result in connectivity_results.items():
            results['details'][hostname] = {
                'ping': node_result['ping'],
                'ssh': node_result['ssh'],
                'sudo': node_result['sudo']
            }
            
            if not node_result['ssh']:
                results['errors'].append(f"{hostname}: SSH 연결 실패")
                results['success'] = False
            
            if not node_result['sudo']:
                results['errors'].append(f"{hostname}: sudo 권한 없음")
                results['success'] = False
        
        # 2. 노드 간 통신 테스트
        controller_hostname = self.config['nodes']['controller']['hostname']
        compute_nodes = [node['hostname'] for node in self.config['nodes']['compute_nodes']]
        
        for compute_hostname in compute_nodes:
            # 컨트롤러 -> 계산노드 연결 테스트
            try:
                exit_code, _, _ = self.ssh_manager.execute_command(
                    controller_hostname, f"ping -c 1 -W 3 {compute_hostname}", show_output=False
                )
                
                if exit_code != 0:
                    results['warnings'].append(f"컨트롤러에서 {compute_hostname}로 ping 실패")
                
            except Exception as e:
                results['errors'].append(f"노드 간 통신 테스트 실패: {e}")
        
        # 3. DNS 해상도 테스트
        for hostname in [controller_hostname] + compute_nodes:
            try:
                exit_code, stdout, _ = self.ssh_manager.execute_command(
                    hostname, "nslookup google.com", show_output=False
                )
                
                if exit_code != 0:
                    results['warnings'].append(f"{hostname}: DNS 해상도 문제")
                    
            except Exception:
                results['warnings'].append(f"{hostname}: DNS 테스트 실패")
        
        return results
    
    def validate_system_requirements(self) -> Dict[str, Any]:
        """시스템 요구사항 검증"""
        print("\n💻 시스템 요구사항 검증 중...")
        
        results = {
            'success': True,
            'details': {},
            'warnings': [],
            'errors': []
        }
        
        all_nodes = self._get_all_nodes()
        
        for node in all_nodes:
            hostname = node['hostname']
            node_results = self._validate_single_node_requirements(node)
            results['details'][hostname] = node_results
            
            if not node_results['success']:
                results['success'] = False
                results['errors'].extend(node_results.get('errors', []))
            
            results['warnings'].extend(node_results.get('warnings', []))
        
        return results
    
    def _validate_single_node_requirements(self, node: Dict[str, Any]) -> Dict[str, Any]:
        """개별 노드 시스템 요구사항 검증"""
        hostname = node['hostname']
        hardware = node['hardware']
        
        node_results = {
            'success': True,
            'os_info': {},
            'cpu_info': {},
            'memory_info': {},
            'errors': [],
            'warnings': []
        }
        
        try:
            # OS 정보 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "cat /etc/os-release", show_output=False
            )
            
            if exit_code == 0:
                os_info = {}
                for line in stdout.split('\n'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        os_info[key] = value.strip('"')
                
                node_results['os_info'] = os_info
                
                # 지원되는 OS 확인
                os_name = os_info.get('ID', '').lower()
                if os_name not in ['centos', 'rhel', 'ubuntu']:
                    node_results['warnings'].append(f"{hostname}: 공식 지원되지 않는 OS - {os_name}")
            
            # CPU 정보 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "nproc", show_output=False
            )
            
            if exit_code == 0:
                actual_cpus = int(stdout.strip())
                expected_cpus = hardware['cpus']
                
                node_results['cpu_info'] = {
                    'actual': actual_cpus,
                    'expected': expected_cpus
                }
                
                if actual_cpus != expected_cpus:
                    node_results['warnings'].append(
                        f"{hostname}: CPU 수 불일치 (실제: {actual_cpus}, 설정: {expected_cpus})"
                    )
            
            # 메모리 정보 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "free -m | grep '^Mem:' | awk '{print $2}'", show_output=False
            )
            
            if exit_code == 0:
                actual_memory = int(stdout.strip())
                expected_memory = hardware['memory_mb']
                
                node_results['memory_info'] = {
                    'actual_mb': actual_memory,
                    'expected_mb': expected_memory
                }
                
                # 메모리 차이 허용 범위: 5%
                memory_diff_percent = abs(actual_memory - expected_memory) / expected_memory * 100
                
                if memory_diff_percent > 5:
                    node_results['warnings'].append(
                        f"{hostname}: 메모리 용량 차이 (실제: {actual_memory}MB, 설정: {expected_memory}MB)"
                    )
            
            # GPU 정보 확인 (GPU가 설정된 경우)
            gpu_config = hardware.get('gpu', {})
            if gpu_config.get('type') == 'nvidia' and gpu_config.get('count', 0) > 0:
                exit_code, stdout, _ = self.ssh_manager.execute_command(
                    hostname, "nvidia-smi --query-gpu=count --format=csv,noheader,nounits", show_output=False
                )
                
                if exit_code != 0:
                    node_results['warnings'].append(f"{hostname}: NVIDIA GPU 드라이버가 설치되지 않음")
                else:
                    try:
                        actual_gpu_count = len(stdout.strip().split('\n'))
                        expected_gpu_count = gpu_config['count']
                        
                        if actual_gpu_count != expected_gpu_count:
                            node_results['warnings'].append(
                                f"{hostname}: GPU 수 불일치 (실제: {actual_gpu_count}, 설정: {expected_gpu_count})"
                            )
                    except:
                        node_results['warnings'].append(f"{hostname}: GPU 정보 파싱 실패")
        
        except Exception as e:
            node_results['errors'].append(f"{hostname}: 시스템 정보 수집 실패 - {e}")
            node_results['success'] = False
        
        return node_results
    
    def validate_storage_requirements(self) -> Dict[str, Any]:
        """스토리지 요구사항 검증"""
        print("\n💽 스토리지 요구사항 검증 중...")
        
        results = {
            'success': True,
            'details': {},
            'warnings': [],
            'errors': []
        }
        
        # NFS 서버 (컨트롤러) 검증
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        
        mount_points = self.config['shared_storage']['mount_points']
        
        for mount in mount_points:
            source_dir = mount['source']
            
            # 디렉토리 존재 여부 확인
            exit_code, _, _ = self.ssh_manager.execute_command(
                controller_hostname, f"test -d {source_dir}", show_output=False
            )
            
            if exit_code != 0:
                # 디렉토리가 없으면 생성 가능한지 확인
                parent_dir = '/'.join(source_dir.split('/')[:-1])
                
                exit_code, _, _ = self.ssh_manager.execute_command(
                    controller_hostname, f"test -w {parent_dir}", show_output=False
                )
                
                if exit_code != 0:
                    results['errors'].append(f"NFS 공유 디렉토리 생성 불가: {source_dir}")
                    results['success'] = False
        
        # 계산 노드의 마운트 포인트 검증
        for node in self.config['nodes']['compute_nodes']:
            hostname = node['hostname']
            
            for mount in mount_points:
                target_dir = mount['target']
                
                # 마운트 포인트 디렉토리 생성 가능한지 확인
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, f"mkdir -p {target_dir}", show_output=False
                )
                
                if exit_code != 0:
                    results['errors'].append(f"{hostname}: 마운트 포인트 생성 실패 - {target_dir}")
        
        return results
    
    def validate_user_permissions(self) -> Dict[str, Any]:
        """사용자 권한 검증"""
        print("\n👤 사용자 권한 검증 중...")
        
        results = {
            'success': True,
            'details': {},
            'warnings': [],
            'errors': []
        }
        
        all_nodes = self._get_all_nodes()
        
        for node in all_nodes:
            hostname = node['hostname']
            
            # sudo 권한 확인 (이미 SSH 연결 테스트에서 확인했지만 재확인)
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, "sudo -n echo 'sudo test'", show_output=False
            )
            
            if exit_code != 0:
                results['errors'].append(f"{hostname}: sudo 권한 없음")
                results['success'] = False
            
            # systemctl 사용 가능 여부 확인
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, "which systemctl", show_output=False
            )
            
            if exit_code != 0:
                results['errors'].append(f"{hostname}: systemctl 명령어 없음 (systemd 필요)")
                results['success'] = False
        
        # Slurm 사용자 생성 가능 여부 확인
        slurm_uid = self.config['users']['slurm_uid']
        slurm_gid = self.config['users']['slurm_gid']
        
        for node in all_nodes:
            hostname = node['hostname']
            
            # UID/GID 중복 확인
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, f"id {slurm_uid}", show_output=False
            )
            
            if exit_code == 0:
                results['warnings'].append(f"{hostname}: UID {slurm_uid} 이미 사용 중")
            
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, f"getent group {slurm_gid}", show_output=False
            )
            
            if exit_code == 0:
                results['warnings'].append(f"{hostname}: GID {slurm_gid} 이미 사용 중")
        
        return results
    
    def validate_port_availability(self) -> Dict[str, Any]:
        """포트 사용 가능성 검증"""
        print("\n🔌 포트 사용 가능성 검증 중...")
        
        results = {
            'success': True,
            'details': {},
            'warnings': [],
            'errors': []
        }
        
        ports_to_check = self.config['network']['firewall']['ports']
        all_nodes = self._get_all_nodes()
        
        for node in all_nodes:
            hostname = node['hostname']
            node_results = {}
            
            for service_name, port in ports_to_check.items():
                # 포트가 사용 중인지 확인
                exit_code, stdout, _ = self.ssh_manager.execute_command(
                    hostname, f"netstat -tlnp | grep :{port}", show_output=False
                )
                
                if exit_code == 0 and stdout.strip():
                    results['warnings'].append(f"{hostname}: 포트 {port} ({service_name}) 이미 사용 중")
                    node_results[service_name] = {'port': port, 'available': False}
                else:
                    node_results[service_name] = {'port': port, 'available': True}
            
            results['details'][hostname] = node_results
        
        return results
    
    def validate_disk_space(self) -> Dict[str, Any]:
        """디스크 공간 검증"""
        print("\n💿 디스크 공간 검증 중...")
        
        results = {
            'success': True,
            'details': {},
            'warnings': [],
            'errors': []
        }
        
        all_nodes = self._get_all_nodes()
        
        # 필요한 디스크 공간 (GB)
        required_space = {
            'slurm_install': 2,      # Slurm 설치
            'temp_compile': 5,       # 컴파일용 임시 공간
            'logs': 1,               # 로그 파일
            'spool': 2               # spool 디렉토리
        }
        
        for node in all_nodes:
            hostname = node['hostname']
            node_results = {}
            
            # 루트 파티션 공간 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "df -BG / | tail -1 | awk '{print $4}'", show_output=False
            )
            
            if exit_code == 0:
                available_space_str = stdout.strip().rstrip('G')
                try:
                    available_space = int(available_space_str)
                    total_required = sum(required_space.values())
                    
                    node_results['available_gb'] = available_space
                    node_results['required_gb'] = total_required
                    
                    if available_space < total_required:
                        results['errors'].append(
                            f"{hostname}: 디스크 공간 부족 (사용가능: {available_space}GB, 필요: {total_required}GB)"
                        )
                        results['success'] = False
                    elif available_space < total_required * 2:
                        results['warnings'].append(
                            f"{hostname}: 디스크 공간 여유 부족 (사용가능: {available_space}GB)"
                        )
                
                except ValueError:
                    results['warnings'].append(f"{hostname}: 디스크 공간 정보 파싱 실패")
            
            # 임시 디렉토리 공간 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "df -BG /tmp | tail -1 | awk '{print $4}'", show_output=False
            )
            
            if exit_code == 0:
                try:
                    tmp_space = int(stdout.strip().rstrip('G'))
                    if tmp_space < required_space['temp_compile']:
                        results['warnings'].append(
                            f"{hostname}: /tmp 공간 부족 (사용가능: {tmp_space}GB, 필요: {required_space['temp_compile']}GB)"
                        )
                except ValueError:
                    pass
            
            results['details'][hostname] = node_results
        
        return results
    
    def validate_package_repositories(self) -> Dict[str, Any]:
        """패키지 저장소 접근성 검증"""
        print("\n📦 패키지 저장소 접근성 검증 중...")
        
        results = {
            'success': True,
            'details': {},
            'warnings': [],
            'errors': []
        }
        
        all_nodes = self._get_all_nodes()
        
        for node in all_nodes:
            hostname = node['hostname']
            os_type = node.get('os_type', '').lower()
            
            # OS별 패키지 매니저 확인
            if 'centos' in os_type or 'rhel' in os_type:
                # yum/dnf 저장소 확인
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, "yum repolist || dnf repolist", show_output=False
                )
                
                if exit_code != 0:
                    results['errors'].append(f"{hostname}: yum/dnf 저장소 접근 실패")
                    results['success'] = False
                
                # EPEL 저장소 필요성 확인
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, "yum repolist | grep epel || dnf repolist | grep epel", show_output=False
                )
                
                if exit_code != 0:
                    results['warnings'].append(f"{hostname}: EPEL 저장소 미설정 (권장)")
                
            elif 'ubuntu' in os_type:
                # apt 저장소 확인
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname, "apt update", show_output=False
                )
                
                if exit_code != 0:
                    results['errors'].append(f"{hostname}: apt 저장소 업데이트 실패")
                    results['success'] = False
        
        return results
    
    def _get_all_nodes(self) -> List[Dict[str, Any]]:
        """모든 노드 정보 반환"""
        nodes = []
        
        # 컨트롤러 노드
        controller = self.config['nodes']['controller'].copy()
        controller['node_type'] = 'controller'
        nodes.append(controller)
        
        # 계산 노드들
        for node in self.config['nodes']['compute_nodes']:
            compute_node = node.copy()
            compute_node['node_type'] = 'compute'
            nodes.append(compute_node)
        
        return nodes
    
    def print_validation_summary(self, results: Dict[str, Any]):
        """검증 결과 요약 출력"""
        print("\n" + "="*60)
        print("설치 전 검증 결과 요약")
        print("="*60)
        
        validation_categories = [
            ('network_connectivity', '🌐 네트워크 연결성'),
            ('system_requirements', '💻 시스템 요구사항'),
            ('storage_requirements', '💽 스토리지 요구사항'),
            ('user_permissions', '👤 사용자 권한'),
            ('port_availability', '🔌 포트 사용 가능성'),
            ('disk_space', '💿 디스크 공간'),
            ('package_repositories', '📦 패키지 저장소')
        ]
        
        for category, display_name in validation_categories:
            if category in results:
                category_result = results[category]
                success = category_result.get('success', False)
                
                status = "✅ 통과" if success else "❌ 실패"
                print(f"{display_name}: {status}")
                
                # 경고사항 출력
                warnings = category_result.get('warnings', [])
                if warnings:
                    for warning in warnings[:3]:  # 최대 3개만 표시
                        print(f"  ⚠️  {warning}")
                    if len(warnings) > 3:
                        print(f"  ⚠️  ... 외 {len(warnings) - 3}개 경고")
                
                # 오류사항 출력
                errors = category_result.get('errors', [])
                if errors:
                    for error in errors[:3]:  # 최대 3개만 표시
                        print(f"  ❌ {error}")
                    if len(errors) > 3:
                        print(f"  ❌ ... 외 {len(errors) - 3}개 오류")
        
        print("\n" + "="*60)
        
        if results['overall_success']:
            print("🎉 전체 검증 결과: 성공!")
            print("설치를 진행할 수 있습니다.")
        else:
            print("⚠️  전체 검증 결과: 실패!")
            print("오류를 해결한 후 다시 실행해주세요.")
        
        print("="*60)


def main():
    """테스트 메인 함수"""
    import sys
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    
    if len(sys.argv) < 2:
        print("사용법: python pre_install_validator.py <config_file>")
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
        all_nodes = parser.get_node_list()
        for node in all_nodes:
            ssh_manager.add_node(node)
        
        # 검증 실행
        validator = PreInstallValidator(config, ssh_manager)
        results = validator.run_full_validation()
        
        ssh_manager.disconnect_all()
        
    except Exception as e:
        print(f"검증 중 오류 발생: {e}")


if __name__ == "__main__":
    main()
