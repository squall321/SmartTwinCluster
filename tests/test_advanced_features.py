#!/usr/bin/env python3
"""
Advanced Features 모듈 테스트
"""

import unittest
import sys
from pathlib import Path
from unittest.mock import Mock, MagicMock, patch

# 상위 디렉토리의 src 모듈 import
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from advanced_features import AdvancedFeaturesInstaller


class TestAdvancedFeaturesInstaller(unittest.TestCase):
    """AdvancedFeaturesInstaller 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_ssh_manager = Mock()
        self.mock_ssh_manager.execute_command.return_value = (0, '', '')
        
        self.test_config = {
            'cluster_info': {
                'cluster_name': 'test-cluster'
            },
            'nodes': {
                'controller': {
                    'hostname': 'controller01',
                    'ip_address': '192.168.1.10'
                },
                'compute_nodes': [
                    {'hostname': 'compute01', 'ip_address': '192.168.1.20'},
                    {'hostname': 'compute02', 'ip_address': '192.168.1.21'}
                ]
            },
            'slurm_config': {
                'config_path': '/etc/slurm'
            },
            'database': {
                'enabled': True,
                'host': 'controller01',
                'port': 3306,
                'database_name': 'slurm_acct_db',
                'username': 'slurm',
                'password': 'testpass'
            },
            'monitoring': {
                'prometheus': {
                    'enabled': True,
                    'port': 9090,
                    'node_exporter': True
                },
                'grafana': {
                    'enabled': True,
                    'port': 3000,
                    'admin_password': 'admin'
                }
            },
            'environment_modules': {
                'enabled': True,
                'type': 'modules',
                'modulefiles_path': '/usr/share/Modules/modulefiles'
            },
            'performance_tuning': {
                'kernel_parameters': {
                    'vm.swappiness': 10,
                    'net.core.rmem_max': 134217728
                },
                'ulimits': {
                    'nofile': 65536,
                    'nproc': 4096
                },
                'cpu_governor': 'performance'
            }
        }
        
        self.installer = AdvancedFeaturesInstaller(self.test_config, self.mock_ssh_manager)
    
    def test_init(self):
        """초기화 테스트"""
        self.assertEqual(self.installer.config, self.test_config)
        self.assertEqual(self.installer.ssh_manager, self.mock_ssh_manager)
        self.assertEqual(self.installer.controller_hostname, 'controller01')
    
    def test_setup_database(self):
        """데이터베이스 설정 테스트"""
        result = self.installer.setup_database()
        
        self.assertTrue(result)
        # MariaDB 설치 명령 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('mariadb' in call.lower() for call in calls))
    
    def test_setup_database_disabled(self):
        """데이터베이스 비활성화 테스트"""
        self.test_config['database']['enabled'] = False
        installer = AdvancedFeaturesInstaller(self.test_config, self.mock_ssh_manager)
        
        result = installer.setup_database()
        
        self.assertTrue(result)
        # 아무 명령도 실행되지 않았는지 확인
        self.assertEqual(self.mock_ssh_manager.execute_command.call_count, 0)
    
    def test_apply_performance_tuning(self):
        """성능 튜닝 적용 테스트"""
        result = self.installer.apply_performance_tuning()
        
        self.assertTrue(result)
        # sysctl, ulimit, cpu governor 설정 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('sysctl' in call for call in calls))
    
    def test_apply_kernel_parameters(self):
        """커널 파라미터 적용 테스트"""
        params = {
            'vm.swappiness': 10,
            'net.core.rmem_max': 134217728
        }
        
        self.installer._apply_kernel_parameters('controller01', params)
        
        # sysctl 명령 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('sysctl' in call for call in calls))
        self.assertTrue(any('vm.swappiness' in call for call in calls))
    
    def test_apply_ulimits(self):
        """ulimit 설정 적용 테스트"""
        ulimits = {
            'nofile': 65536,
            'nproc': 4096
        }
        
        self.installer._apply_ulimits('controller01', ulimits)
        
        # limits.conf 설정 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('limits.conf' in call for call in calls))
    
    def test_set_cpu_governor(self):
        """CPU governor 설정 테스트"""
        self.installer._set_cpu_governor('controller01', 'performance')
        
        # governor 설정 명령 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('performance' in call for call in calls))
    
    def test_setup_backup_and_recovery(self):
        """백업 및 복구 설정 테스트"""
        self.test_config['backup_and_recovery'] = {
            'config_backup': {
                'enabled': True,
                'schedule': '0 3 * * 0',
                'retention_days': 30,
                'backup_path': '/backup/slurm'
            }
        }
        
        installer = AdvancedFeaturesInstaller(self.test_config, self.mock_ssh_manager)
        result = installer.setup_backup_and_recovery()
        
        self.assertTrue(result)
        # 백업 스크립트 생성 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('backup' in call.lower() for call in calls))


class TestAdvancedFeaturesEdgeCases(unittest.TestCase):
    """경계값 및 에러 케이스 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_ssh_manager = Mock()
        self.minimal_config = {
            'cluster_info': {'cluster_name': 'test'},
            'nodes': {
                'controller': {'hostname': 'ctrl'},
                'compute_nodes': []
            },
            'slurm_config': {'config_path': '/etc/slurm'}
        }
    
    def test_setup_database_connection_failure(self):
        """데이터베이스 연결 실패 테스트"""
        self.minimal_config['database'] = {
            'enabled': True,
            'host': 'controller',
            'username': 'slurm',
            'password': 'pass'
        }
        
        # 명령 실행 실패 시뮬레이션
        self.mock_ssh_manager.execute_command.return_value = (1, '', 'Connection failed')
        
        installer = AdvancedFeaturesInstaller(self.minimal_config, self.mock_ssh_manager)
        result = installer.setup_database()
        
        # 실패해야 함
        self.assertFalse(result)
    
    def test_setup_monitoring_disabled(self):
        """모니터링 비활성화 테스트"""
        self.minimal_config['monitoring'] = {
            'prometheus': {'enabled': False},
            'grafana': {'enabled': False}
        }
        
        installer = AdvancedFeaturesInstaller(self.minimal_config, self.mock_ssh_manager)
        result = installer.setup_monitoring()
        
        self.assertTrue(result)
    
    def test_performance_tuning_empty_config(self):
        """빈 성능 튜닝 설정 테스트"""
        self.minimal_config['performance_tuning'] = {}
        
        self.mock_ssh_manager.execute_command.return_value = (0, '', '')
        installer = AdvancedFeaturesInstaller(self.minimal_config, self.mock_ssh_manager)
        
        result = installer.apply_performance_tuning()
        
        self.assertTrue(result)


if __name__ == '__main__':
    unittest.main()
