#!/usr/bin/env python3
"""
Slurm Installer 모듈 테스트
"""

import unittest
import sys
from pathlib import Path
from unittest.mock import Mock, MagicMock, patch

# 상위 디렉토리의 src 모듈 import
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from slurm_installer import SlurmInstaller


class TestSlurmInstaller(unittest.TestCase):
    """SlurmInstaller 클래스 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_ssh_manager = Mock()
        self.test_config = {
            'cluster_info': {
                'cluster_name': 'test-cluster',
                'domain': 'test.local',
                'admin_email': 'admin@test.local'
            },
            'nodes': {
                'controller': {
                    'hostname': 'controller01',
                    'ip_address': '192.168.1.10',
                    'os_type': 'centos8',
                    'hardware': {
                        'cpus': 8,
                        'memory_mb': 16384
                    }
                },
                'compute_nodes': [
                    {
                        'hostname': 'compute01',
                        'ip_address': '192.168.1.20',
                        'os_type': 'centos8',
                        'hardware': {
                            'cpus': 16,
                            'memory_mb': 32768,
                            'gpu': {
                                'type': 'nvidia',
                                'count': 2
                            }
                        }
                    }
                ]
            },
            'slurm_config': {
                'version': '23.02.0',
                'install_path': '/usr/local/slurm',
                'config_path': '/usr/local/slurm/etc',
                'log_path': '/var/log/slurm',
                'spool_path': '/var/spool/slurm',
                'scheduler_type': 'sched/backfill',
                'select_type': 'select/cons_tres',
                'partitions': [
                    {
                        'name': 'normal',
                        'nodes': 'compute01',
                        'max_time': '24:00:00',
                        'default': True
                    }
                ]
            },
            'users': {
                'slurm_user': 'slurm',
                'slurm_uid': 1001,
                'slurm_gid': 1001,
                'cluster_users': []
            },
            'database': {
                'enabled': False
            }
        }
        
        self.installer = SlurmInstaller(self.test_config, self.mock_ssh_manager)
    
    def test_init(self):
        """초기화 테스트"""
        self.assertEqual(self.installer.config, self.test_config)
        self.assertEqual(self.installer.ssh_manager, self.mock_ssh_manager)
        self.assertEqual(self.installer.install_path, '/usr/local/slurm')
        self.assertEqual(self.installer.config_path, '/usr/local/slurm/etc')
    
    def test_create_slurm_user(self):
        """Slurm 사용자 생성 테스트"""
        self.mock_ssh_manager.execute_command.return_value = (0, '', '')
        
        result = self.installer.create_slurm_user('controller01')
        
        self.assertTrue(result)
        # groupadd, useradd, usermod 명령이 실행되었는지 확인
        self.assertEqual(self.mock_ssh_manager.execute_command.call_count, 3)
    
    def test_create_slurm_directories(self):
        """Slurm 디렉토리 생성 테스트"""
        self.mock_ssh_manager.execute_command.return_value = (0, '', '')
        
        result = self.installer.create_slurm_directories('controller01')
        
        self.assertTrue(result)
        # 여러 디렉토리가 생성되었는지 확인
        self.assertGreater(self.mock_ssh_manager.execute_command.call_count, 5)
    
    def test_generate_slurm_conf(self):
        """slurm.conf 생성 테스트"""
        config_content = self.installer.generate_slurm_conf()
        
        # 필수 항목들이 포함되어 있는지 확인
        self.assertIn('ClusterName=test-cluster', config_content)
        self.assertIn('ControlMachine=controller01', config_content)
        self.assertIn('NodeName=compute01', config_content)
        self.assertIn('PartitionName=normal', config_content)
        self.assertIn('Gres=gpu:nvidia:2', config_content)
    
    def test_generate_slurm_conf_with_database(self):
        """데이터베이스 설정이 있는 slurm.conf 생성 테스트"""
        # 데이터베이스 활성화
        self.test_config['database']['enabled'] = True
        installer = SlurmInstaller(self.test_config, self.mock_ssh_manager)
        
        config_content = installer.generate_slurm_conf()
        
        # 데이터베이스 관련 설정 확인
        self.assertIn('AccountingStorageType=accounting_storage/slurmdbd', config_content)
        self.assertIn('JobAcctGatherType=jobacct_gather/linux', config_content)
    
    def test_generate_slurmdbd_conf(self):
        """slurmdbd.conf 생성 테스트"""
        self.test_config['database'] = {
            'enabled': True,
            'host': 'controller01',
            'port': 3306,
            'username': 'slurm',
            'password': 'testpass',
            'database_name': 'slurm_acct_db'
        }
        
        installer = SlurmInstaller(self.test_config, self.mock_ssh_manager)
        config_content = installer.generate_slurmdbd_conf()
        
        # 데이터베이스 설정 확인
        self.assertIn('DbdHost=controller01', config_content)
        self.assertIn('StorageUser=slurm', config_content)
        self.assertIn('StoragePass=testpass', config_content)
    
    def test_setup_controller_services(self):
        """컨트롤러 서비스 설정 테스트"""
        self.mock_ssh_manager.execute_command.return_value = (0, '', '')
        
        result = self.installer.setup_controller_services('controller01')
        
        self.assertTrue(result)
        # slurmctld 서비스 파일이 생성되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('slurmctld.service' in call for call in calls))
    
    def test_setup_compute_services(self):
        """계산 노드 서비스 설정 테스트"""
        self.mock_ssh_manager.execute_command.return_value = (0, '', '')
        
        result = self.installer.setup_compute_services('compute01')
        
        self.assertTrue(result)
        # slurmd 서비스 파일이 생성되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('slurmd.service' in call for call in calls))


class TestSlurmInstallerEdgeCases(unittest.TestCase):
    """경계값 및 에러 케이스 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_ssh_manager = Mock()
        self.minimal_config = {
            'cluster_info': {'cluster_name': 'test'},
            'nodes': {
                'controller': {
                    'hostname': 'ctrl', 
                    'hardware': {'cpus': 1, 'memory_mb': 1024}
                },
                'compute_nodes': [{
                    'hostname': 'node01',
                    'hardware': {'cpus': 1, 'memory_mb': 1024}
                }]
            },
            'slurm_config': {
                'version': '23.02.0',
                'install_path': '/opt/slurm',
                'config_path': '/etc/slurm',
                'log_path': '/var/log/slurm',
                'partitions': [{'name': 'all', 'nodes': 'node01'}]
            },
            'users': {
                'slurm_user': 'slurm',
                'slurm_uid': 1001,
                'slurm_gid': 1001
            }
        }
    
    def test_create_directories_failure(self):
        """디렉토리 생성 실패 테스트"""
        self.mock_ssh_manager.execute_command.return_value = (1, '', 'Permission denied')
        
        installer = SlurmInstaller(self.minimal_config, self.mock_ssh_manager)
        result = installer.create_slurm_directories('node01')
        
        self.assertFalse(result)
    
    def test_multiple_partitions(self):
        """여러 파티션 설정 테스트"""
        self.minimal_config['slurm_config']['partitions'] = [
            {'name': 'debug', 'nodes': 'node01', 'max_time': '01:00:00'},
            {'name': 'normal', 'nodes': 'node01', 'max_time': '24:00:00', 'default': True},
            {'name': 'long', 'nodes': 'node01', 'max_time': '168:00:00'}
        ]
        
        installer = SlurmInstaller(self.minimal_config, self.mock_ssh_manager)
        config_content = installer.generate_slurm_conf()
        
        self.assertIn('PartitionName=debug', config_content)
        self.assertIn('PartitionName=normal', config_content)
        self.assertIn('PartitionName=long', config_content)
        self.assertIn('Default=YES', config_content)


if __name__ == '__main__':
    unittest.main()
