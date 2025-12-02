#!/usr/bin/env python3
"""
Slurm 설치 자동화 - 설정 파일 파서
YAML 설정 파일을 읽고 검증하는 모듈
"""

import yaml
import os
from pathlib import Path
from typing import Dict, Any, List, Optional
import ipaddress
import re


class ConfigParser:
    """YAML 설정 파일을 파싱하고 검증하는 클래스"""
    
    def __init__(self, config_path: str):
        self.config_path = Path(config_path)
        self.config = {}
        self.errors = []
        self.warnings = []
        self.supported_versions = ['1.0']  # 지원되는 설정 버전
        
    def load_config(self) -> Dict[str, Any]:
        """YAML 설정 파일을 로드"""
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                self.config = yaml.safe_load(f)
            
            print(f"✅ 설정 파일 로드 완료: {self.config_path}")
            return self.config
            
        except FileNotFoundError:
            raise FileNotFoundError(f"설정 파일을 찾을 수 없습니다: {self.config_path}")
        except yaml.YAMLError as e:
            raise ValueError(f"YAML 파싱 오류: {e}")
        except Exception as e:
            raise Exception(f"설정 파일 로드 오류: {e}")
    
    def validate_config(self) -> bool:
        """설정 파일의 유효성을 검증"""
        self.errors = []
        self.warnings = []
        
        # 설정 버전 검증
        self._validate_config_version()
        
        # 필수 섹션 검증
        required_sections = [
            'cluster_info', 'nodes', 'network', 
            'slurm_config', 'users', 'shared_storage'
        ]
        
        # 권장 섹션 (없어도 되지만 경고)
        recommended_sections = ['installation', 'time_synchronization']
        
        for section in required_sections:
            if section not in self.config:
                self.errors.append(f"필수 섹션 누락: {section}")
        
        for section in recommended_sections:
            if section not in self.config:
                self.warnings.append(f"권장 섹션 누락: {section} (기본값 사용)")
        
        # 각 섹션별 상세 검증
        if 'cluster_info' in self.config:
            self._validate_cluster_info()
        
        if 'nodes' in self.config:
            self._validate_nodes()
            
        if 'network' in self.config:
            self._validate_network()
            
        if 'slurm_config' in self.config:
            self._validate_slurm_config()
        
        if 'installation' in self.config:
            self._validate_installation()
        
        if 'time_synchronization' in self.config:
            self._validate_time_sync()
        
        # 검증 결과 출력
        if self.errors:
            print("\n❌ 설정 파일 검증 오류:")
            for error in self.errors:
                print(f"  - {error}")
        
        if self.warnings:
            print("\n⚠️  설정 파일 경고:")
            for warning in self.warnings:
                print(f"  - {warning}")
        
        return len(self.errors) == 0
    
    def _validate_config_version(self):
        """설정 파일 버전 검증"""
        if 'config_version' not in self.config:
            self.warnings.append("설정 파일 버전이 명시되지 않음. 기본 버전 1.0 사용")
            return
        
        version = str(self.config['config_version'])
        if version not in self.supported_versions:
            self.errors.append(
                f"지원하지 않는 설정 버전: {version}. "
                f"지원 버전: {', '.join(self.supported_versions)}"
            )
    
    def _validate_cluster_info(self):
        """클러스터 기본 정보 검증"""
        cluster_info = self.config['cluster_info']
        
        required_fields = ['cluster_name', 'domain', 'admin_email']
        for field in required_fields:
            if field not in cluster_info:
                self.errors.append(f"cluster_info.{field} 누락")
        
        # 클러스터 이름 검증 (Slurm 규칙)
        if 'cluster_name' in cluster_info:
            name = cluster_info['cluster_name']
            if not re.match(r'^[a-zA-Z0-9_-]+$', name):
                self.errors.append("cluster_name에는 영문, 숫자, _, - 만 사용 가능")
        
        # 이메일 형식 검증
        if 'admin_email' in cluster_info:
            email = cluster_info['admin_email']
            if not re.match(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', email):
                self.errors.append("admin_email 형식이 올바르지 않음")
    
    def _validate_nodes(self):
        """노드 설정 검증"""
        nodes = self.config['nodes']
        
        # 컨트롤러 노드 검증
        if 'controller' not in nodes:
            self.errors.append("controller 노드 설정 누락")
        else:
            self._validate_node_config(nodes['controller'], 'controller')
        
        # 계산 노드 검증
        if 'compute_nodes' not in nodes:
            self.errors.append("compute_nodes 설정 누락")
        elif not isinstance(nodes['compute_nodes'], list) or len(nodes['compute_nodes']) == 0:
            self.errors.append("최소 1개 이상의 compute_nodes 필요")
        else:
            for i, node in enumerate(nodes['compute_nodes']):
                self._validate_node_config(node, f'compute_nodes[{i}]')
        
        # 호스트네임 중복 검사
        hostnames = []
        if 'controller' in nodes:
            hostnames.append(nodes['controller'].get('hostname'))
        
        for node in nodes.get('compute_nodes', []):
            hostname = node.get('hostname')
            if hostname in hostnames:
                self.errors.append(f"호스트네임 중복: {hostname}")
            hostnames.append(hostname)
    
    def _validate_node_config(self, node: Dict[str, Any], node_path: str):
        """개별 노드 설정 검증"""
        required_fields = ['hostname', 'ip_address', 'ssh_user', 'os_type', 'hardware']
        
        for field in required_fields:
            if field not in node:
                self.errors.append(f"{node_path}.{field} 누락")
        
        # IP 주소 검증
        if 'ip_address' in node:
            try:
                ipaddress.ip_address(node['ip_address'])
            except ValueError:
                self.errors.append(f"{node_path}.ip_address 형식이 올바르지 않음: {node['ip_address']}")
        
        # OS 타입 검증
        if 'os_type' in node:
            valid_os = ['centos7', 'centos8', 'centos9', 'ubuntu18', 'ubuntu20', 'ubuntu22', 'rhel8', 'rhel9']
            if node['os_type'] not in valid_os:
                self.errors.append(f"{node_path}.os_type이 지원되지 않음: {node['os_type']}. 지원 OS: {valid_os}")
        
        # 하드웨어 설정 검증
        if 'hardware' in node:
            self._validate_hardware_config(node['hardware'], f"{node_path}.hardware")
    
    def _validate_hardware_config(self, hardware: Dict[str, Any], hw_path: str):
        """하드웨어 설정 검증"""
        required_fields = ['cpus', 'memory_mb']
        
        for field in required_fields:
            if field not in hardware:
                self.errors.append(f"{hw_path}.{field} 누락")
        
        # CPU 수 검증
        if 'cpus' in hardware:
            try:
                cpus = int(hardware['cpus'])
                if cpus <= 0 or cpus > 1024:
                    self.warnings.append(f"{hw_path}.cpus 값이 비정상적: {cpus}")
            except (ValueError, TypeError):
                self.errors.append(f"{hw_path}.cpus는 정수여야 함")
        
        # 메모리 검증
        if 'memory_mb' in hardware:
            try:
                memory = int(hardware['memory_mb'])
                if memory <= 0 or memory > 10000000:  # 10TB
                    self.warnings.append(f"{hw_path}.memory_mb 값이 비정상적: {memory}")
            except (ValueError, TypeError):
                self.errors.append(f"{hw_path}.memory_mb는 정수여야 함")
        
        # GPU 설정 검증
        if 'gpu' in hardware:
            gpu = hardware['gpu']
            if 'type' in gpu and gpu['type'] not in ['none', 'nvidia', 'amd']:
                self.errors.append(f"{hw_path}.gpu.type이 지원되지 않음: {gpu['type']}")
            
            if 'count' in gpu:
                try:
                    count = int(gpu['count'])
                    if count < 0 or count > 16:
                        self.warnings.append(f"{hw_path}.gpu.count 값이 비정상적: {count}")
                except (ValueError, TypeError):
                    self.errors.append(f"{hw_path}.gpu.count는 정수여야 함")
    
    def _validate_network(self):
        """네트워크 설정 검증"""
        network = self.config['network']
        
        required_fields = ['management_network']
        for field in required_fields:
            if field not in network:
                self.errors.append(f"network.{field} 누락")
        
        # 네트워크 주소 검증
        for net_field in ['management_network', 'compute_network', 'storage_network']:
            if net_field in network:
                try:
                    ipaddress.ip_network(network[net_field])
                except ValueError:
                    self.errors.append(f"network.{net_field} 형식이 올바르지 않음: {network[net_field]}")
    
    def _validate_slurm_config(self):
        """Slurm 설정 검증"""
        slurm = self.config['slurm_config']
        
        required_fields = ['version', 'install_path', 'config_path', 'partitions']
        for field in required_fields:
            if field not in slurm:
                self.errors.append(f"slurm_config.{field} 누락")
        
        # 파티션 검증
        if 'partitions' in slurm:
            if not isinstance(slurm['partitions'], list) or len(slurm['partitions']) == 0:
                self.errors.append("최소 1개 이상의 partition 필요")
            else:
                default_partitions = 0
                for i, partition in enumerate(slurm['partitions']):
                    self._validate_partition_config(partition, f"slurm_config.partitions[{i}]")
                    if partition.get('default'):
                        default_partitions += 1
                
                if default_partitions == 0:
                    self.warnings.append("기본 파티션이 설정되지 않음")
                elif default_partitions > 1:
                    self.errors.append("기본 파티션은 1개만 설정 가능")
    
    def _validate_installation(self):
        """설치 방법 설정 검증"""
        installation = self.config['installation']
        
        # 설치 방법 검증
        if 'install_method' in installation:
            method = installation['install_method']
            if method not in ['package', 'source']:
                self.errors.append(
                    f"installation.install_method는 'package' 또는 'source'여야 함: {method}"
                )
        else:
            self.warnings.append("installation.install_method 미지정, 기본값 'package' 사용")
        
        # 오프라인 모드 검증
        if 'offline_mode' in installation:
            if not isinstance(installation['offline_mode'], bool):
                self.errors.append("installation.offline_mode는 boolean이어야 함")
    
    def _validate_time_sync(self):
        """시간 동기화 설정 검증"""
        time_sync = self.config['time_synchronization']
        
        if 'enabled' in time_sync and time_sync['enabled']:
            if 'ntp_servers' not in time_sync or not time_sync['ntp_servers']:
                self.warnings.append(
                    "time_synchronization이 활성화되었으나 ntp_servers가 없음"
                )
    
    def _validate_partition_config(self, partition: Dict[str, Any], part_path: str):
        """파티션 설정 검증"""
        required_fields = ['name', 'nodes']
        
        for field in required_fields:
            if field not in partition:
                self.errors.append(f"{part_path}.{field} 누락")
        
        # 파티션 이름 검증
        if 'name' in partition:
            name = partition['name']
            if not re.match(r'^[a-zA-Z0-9_-]+$', name):
                self.errors.append(f"{part_path}.name에는 영문, 숫자, _, - 만 사용 가능")
        
        # 시간 제한 검증 (Slurm 형식: days-hours:minutes:seconds)
        if 'max_time' in partition:
            max_time = partition['max_time']
            # max_time을 문자열로 변환 (YAML에서 숫자로 파싱될 수 있음)
            max_time_str = str(max_time) if max_time is not None else ''
            if max_time_str and not re.match(r'^(\d+-)?(\d{1,2}:)?\d{1,2}:\d{2}$', max_time_str):
                self.warnings.append(f"{part_path}.max_time 형식 확인 필요: {max_time}")
    
    def get_install_stage(self) -> int:
        """설치 단계 반환"""
        stage = self.config.get('stage', 1)
        if stage == 'all':
            return 3
        try:
            return int(stage)
        except (ValueError, TypeError):
            self.warnings.append(f"stage 값이 올바르지 않음: {stage}, 기본값 1 사용")
            return 1
    
    def get_node_list(self) -> List[Dict[str, Any]]:
        """모든 노드 정보를 리스트로 반환"""
        nodes = []
        
        # 컨트롤러 노드
        if 'controller' in self.config['nodes']:
            controller = self.config['nodes']['controller'].copy()
            controller['node_type'] = 'controller'
            nodes.append(controller)
        
        # 계산 노드들
        for compute_node in self.config['nodes'].get('compute_nodes', []):
            node = compute_node.copy()
            node['node_type'] = 'compute'
            nodes.append(node)
        
        return nodes
    
    def get_controller_node(self) -> Optional[Dict[str, Any]]:
        """컨트롤러 노드 정보 반환"""
        return self.config.get('nodes', {}).get('controller')
    
    def get_compute_nodes(self) -> List[Dict[str, Any]]:
        """계산 노드들 정보 반환"""
        return self.config.get('nodes', {}).get('compute_nodes', [])
    
    def is_feature_enabled(self, feature_path: str) -> bool:
        """특정 기능이 활성화되었는지 확인"""
        keys = feature_path.split('.')
        current = self.config
        
        for key in keys:
            if isinstance(current, dict) and key in current:
                current = current[key]
            else:
                return False
        
        if isinstance(current, dict) and 'enabled' in current:
            return bool(current['enabled'])
        
        return bool(current)
    
    def get_config_value(self, path: str, default=None):
        """설정 값을 경로로 가져오기"""
        keys = path.split('.')
        current = self.config
        
        for key in keys:
            if isinstance(current, dict) and key in current:
                current = current[key]
            else:
                return default
        
        return current
    
    def print_config_summary(self):
        """설정 파일 요약 정보 출력"""
        print("\n" + "="*60)
        print("설정 파일 요약")
        print("="*60)
        
        # 클러스터 정보
        cluster_info = self.config.get('cluster_info', {})
        print(f"클러스터 이름: {cluster_info.get('cluster_name', 'N/A')}")
        print(f"도메인: {cluster_info.get('domain', 'N/A')}")
        print(f"관리자: {cluster_info.get('admin_email', 'N/A')}")
        print(f"설치 단계: {self.get_install_stage()}")
        
        # 노드 정보
        nodes = self.get_node_list()
        print(f"\n노드 구성: 총 {len(nodes)}개")
        
        controller = self.get_controller_node()
        if controller:
            print(f"  - 컨트롤러: {controller.get('hostname')} ({controller.get('ip_address')})")
        
        compute_nodes = self.get_compute_nodes()
        print(f"  - 계산노드: {len(compute_nodes)}개")
        for node in compute_nodes:
            gpu_info = ""
            if 'hardware' in node and 'gpu' in node['hardware']:
                gpu = node['hardware']['gpu']
                if gpu.get('type') != 'none' and gpu.get('count', 0) > 0:
                    gpu_info = f" [{gpu.get('type')} x{gpu.get('count')}]"
            
            print(f"    * {node.get('hostname')} ({node.get('ip_address')}){gpu_info}")
        
        # Slurm 파티션
        partitions = self.config.get('slurm_config', {}).get('partitions', [])
        print(f"\n파티션: {len(partitions)}개")
        for partition in partitions:
            default_str = " [기본]" if partition.get('default') else ""
            print(f"  - {partition.get('name')}: {partition.get('nodes')}{default_str}")
        
        # 활성화된 고급 기능들
        advanced_features = []
        
        if self.is_feature_enabled('database'):
            advanced_features.append('Database')
        if self.is_feature_enabled('monitoring.prometheus'):
            advanced_features.append('Prometheus')
        if self.is_feature_enabled('monitoring.grafana'):
            advanced_features.append('Grafana')
        if self.is_feature_enabled('high_availability.controller_ha'):
            advanced_features.append('HA Controller')
        if self.is_feature_enabled('container_support.singularity'):
            advanced_features.append('Singularity')
        
        if advanced_features:
            print(f"\n활성화된 고급 기능: {', '.join(advanced_features)}")
        
        print("="*60)


def main():
    """테스트 메인 함수"""
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python config_parser.py <config_file>")
        return
    
    config_file = sys.argv[1]
    
    try:
        parser = ConfigParser(config_file)
        config = parser.load_config()
        
        if parser.validate_config():
            print("\n✅ 설정 파일 검증 성공!")
            parser.print_config_summary()
        else:
            print("\n❌ 설정 파일 검증 실패!")
            return 1
            
    except Exception as e:
        print(f"❌ 오류: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
