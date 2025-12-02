#!/usr/bin/env python3
"""
ConfigParser 테스트
"""

import unittest
import tempfile
import yaml
from pathlib import Path
import sys

# src 디렉토리를 Python 경로에 추가
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from config_parser import ConfigParser


class TestConfigParser(unittest.TestCase):
    """ConfigParser 클래스 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        # 유효한 테스트 설정
        self.valid_config = {
            'cluster_info': {
                'cluster_name': 'test-cluster',
                'domain': 'test.local',
                'admin_email': 'admin@test.local',
                'timezone': 'Asia/Seoul'
            },
            'nodes': {
                'controller': {
                    'hostname': 'controller01',
                    'ip_address': '192.168.1.10',
                    'ssh_user': 'root',
                    'ssh_port': 22,
                    'ssh_key_path': '~/.ssh/id_rsa',
                    'os_type': 'centos8',
                    'hardware': {
                        'cpus': 8,
                        'memory_mb': 16384,
                        'disk_gb': 500
                    }
                },
                'compute_nodes': [
                    {
                        'hostname': 'node01',
                        'ip_address': '192.168.1.20',
                        'ssh_user': 'root',
                        'ssh_port': 22,
                        'ssh_key_path': '~/.ssh/id_rsa',
                        'os_type': 'centos8',
                        'hardware': {
                            'cpus': 16,
                            'sockets': 1,
                            'cores_per_socket': 8,
                            'threads_per_core': 2,
                            'memory_mb': 32768,
                            'tmp_disk_mb': 102400,
                            'gpu': {
                                'type': 'none',
                                'count': 0
                            }
                        }
                    }
                ]
            },
            'network': {
                'management_network': '192.168.1.0/24',
                'compute_network': '192.168.1.0/24',
                'firewall': {
                    'enabled': True,
                    'ports': {
                        'slurmd': 6818,
                        'slurmctld': 6817,
                        'ssh': 22
                    }
                }
            },
            'slurm_config': {
                'version': '22.05.8',
                'install_path': '/usr/local/slurm',
                'config_path': '/usr/local/slurm/etc',
                'log_path': '/var/log/slurm',
                'partitions': [
                    {
                        'name': 'cpu',
                        'nodes': 'node01',
                        'default': True,
                        'max_time': '7-00:00:00',
                        'max_nodes': 1
                    }
                ]
            },
            'users': {
                'slurm_user': 'slurm',
                'slurm_uid': 1001,
                'slurm_gid': 1001,
                'cluster_users': [
                    {
                        'username': 'user01',
                        'uid': 2001,
                        'gid': 2001,
                        'groups': ['users']
                    }
                ]
            },
            'shared_storage': {
                'nfs_server': '192.168.1.10',
                'mount_points': [
                    {
                        'source': '/export/home',
                        'target': '/home',
                        'options': 'rw,sync,hard,intr'
                    }
                ]
            }
        }
    
    def test_load_valid_config(self):
        """유효한 설정 파일 로드 테스트"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(self.valid_config, f)
            temp_path = f.name
        
        try:
            parser = ConfigParser(temp_path)
            config = parser.load_config()
            
            self.assertIsInstance(config, dict)
            self.assertEqual(config['cluster_info']['cluster_name'], 'test-cluster')
            self.assertIn('nodes', config)
            
        finally:
            Path(temp_path).unlink()
    
    def test_load_nonexistent_file(self):
        """존재하지 않는 파일 로드 테스트"""
        parser = ConfigParser('nonexistent.yaml')
        
        with self.assertRaises(FileNotFoundError):
            parser.load_config()
    
    def test_validate_valid_config(self):
        """유효한 설정 검증 테스트"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(self.valid_config, f)
            temp_path = f.name
        
        try:
            parser = ConfigParser(temp_path)
            parser.load_config()
            result = parser.validate_config()
            
            self.assertTrue(result)
            self.assertEqual(len(parser.errors), 0)
            
        finally:
            Path(temp_path).unlink()
    
    def test_validate_missing_sections(self):
        """필수 섹션 누락 테스트"""
        invalid_config = {'cluster_info': {'cluster_name': 'test'}}
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(invalid_config, f)
            temp_path = f.name
        
        try:
            parser = ConfigParser(temp_path)
            parser.load_config()
            result = parser.validate_config()
            
            self.assertFalse(result)
            self.assertGreater(len(parser.errors), 0)
            
        finally:
            Path(temp_path).unlink()
    
    def test_validate_invalid_ip_address(self):
        """잘못된 IP 주소 검증 테스트"""
        invalid_config = self.valid_config.copy()
        invalid_config['nodes']['controller']['ip_address'] = 'invalid-ip'
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(invalid_config, f)
            temp_path = f.name
        
        try:
            parser = ConfigParser(temp_path)
            parser.load_config()
            result = parser.validate_config()
            
            self.assertFalse(result)
            # IP 주소 형식 오류가 있어야 함
            ip_errors = [error for error in parser.errors if 'ip_address' in error and '형식이 올바르지 않음' in error]
            self.assertGreater(len(ip_errors), 0)
            
        finally:
            Path(temp_path).unlink()
    
    def test_get_node_list(self):
        """노드 리스트 가져오기 테스트"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(self.valid_config, f)
            temp_path = f.name
        
        try:
            parser = ConfigParser(temp_path)
            parser.load_config()
            parser.validate_config()
            
            node_list = parser.get_node_list()
            
            self.assertEqual(len(node_list), 2)  # 컨트롤러 1개 + 계산노드 1개
            
            controller_node = next((node for node in node_list if node['node_type'] == 'controller'), None)
            compute_node = next((node for node in node_list if node['node_type'] == 'compute'), None)
            
            self.assertIsNotNone(controller_node)
            self.assertIsNotNone(compute_node)
            self.assertEqual(controller_node['hostname'], 'controller01')
            self.assertEqual(compute_node['hostname'], 'node01')
            
        finally:
            Path(temp_path).unlink()
    
    def test_get_install_stage(self):
        """설치 단계 가져오기 테스트"""
        # Stage 설정이 없는 경우
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(self.valid_config, f)
            temp_path = f.name
        
        try:
            parser = ConfigParser(temp_path)
            parser.load_config()
            
            stage = parser.get_install_stage()
            self.assertEqual(stage, 1)  # 기본값
            
        finally:
            Path(temp_path).unlink()
        
        # Stage 설정이 있는 경우
        config_with_stage = self.valid_config.copy()
        config_with_stage['stage'] = 2
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(config_with_stage, f)
            temp_path = f.name
        
        try:
            parser = ConfigParser(temp_path)
            parser.load_config()
            
            stage = parser.get_install_stage()
            self.assertEqual(stage, 2)
            
        finally:
            Path(temp_path).unlink()
    
    def test_is_feature_enabled(self):
        """기능 활성화 상태 확인 테스트"""
        config_with_features = self.valid_config.copy()
        config_with_features['database'] = {'enabled': True}
        config_with_features['monitoring'] = {
            'prometheus': {'enabled': True},
            'grafana': {'enabled': False}
        }
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(config_with_features, f)
            temp_path = f.name
        
        try:
            parser = ConfigParser(temp_path)
            parser.load_config()
            
            self.assertTrue(parser.is_feature_enabled('database'))
            self.assertTrue(parser.is_feature_enabled('monitoring.prometheus'))
            self.assertFalse(parser.is_feature_enabled('monitoring.grafana'))
            self.assertFalse(parser.is_feature_enabled('nonexistent'))
            
        finally:
            Path(temp_path).unlink()


if __name__ == '__main__':
    unittest.main()
