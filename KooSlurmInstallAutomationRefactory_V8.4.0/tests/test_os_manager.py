#!/usr/bin/env python3
"""
OS Manager 모듈 테스트
"""

import unittest
import sys
from pathlib import Path
from unittest.mock import Mock, MagicMock, patch

# 상위 디렉토리의 src 모듈 import
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from os_manager import OSManagerFactory, CentOSManager, UbuntuManager


class TestOSManagerFactory(unittest.TestCase):
    """OSManagerFactory 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_ssh_manager = Mock()
        self.hostname = 'testnode01'
    
    def test_create_centos_manager(self):
        """CentOS 매니저 생성 테스트"""
        manager = OSManagerFactory.create_manager(
            self.mock_ssh_manager, self.hostname, 'centos8'
        )
        
        self.assertIsInstance(manager, CentOSManager)
        self.assertEqual(manager.hostname, self.hostname)
    
    def test_create_ubuntu_manager(self):
        """Ubuntu 매니저 생성 테스트"""
        manager = OSManagerFactory.create_manager(
            self.mock_ssh_manager, self.hostname, 'ubuntu20'
        )
        
        self.assertIsInstance(manager, UbuntuManager)
        self.assertEqual(manager.hostname, self.hostname)
    
    def test_create_manager_rhel(self):
        """RHEL 매니저 생성 테스트"""
        for os_type in ['rhel7', 'rhel8', 'rhel9']:
            manager = OSManagerFactory.create_manager(
                self.mock_ssh_manager, self.hostname, os_type
            )
            self.assertIsInstance(manager, CentOSManager)
    
    def test_create_manager_invalid_os(self):
        """잘못된 OS 타입 테스트"""
        with self.assertRaises(ValueError):
            OSManagerFactory.create_manager(
                self.mock_ssh_manager, self.hostname, 'windows10'
            )


class TestCentOSManager(unittest.TestCase):
    """CentOSManager 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_ssh_manager = Mock()
        self.hostname = 'centos-node'
        self.manager = CentOSManager(self.mock_ssh_manager, self.hostname)
        
        # Mock execute_command 기본 응답
        self.mock_ssh_manager.execute_command.return_value = (0, '', '')
    
    def test_detect_os_centos7(self):
        """CentOS 7 감지 테스트"""
        os_release = '''
NAME="CentOS Linux"
VERSION="7 (Core)"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="7"
PRETTY_NAME="CentOS Linux 7 (Core)"
'''
        self.mock_ssh_manager.execute_command.return_value = (0, os_release, '')
        
        os_info = self.manager.detect_os()
        
        self.assertEqual(os_info['VERSION_ID'], '7')
        self.assertEqual(os_info['ID'], 'centos')
        self.assertEqual(self.manager.package_manager, 'yum')
    
    def test_detect_os_centos8(self):
        """CentOS 8 감지 테스트"""
        os_release = '''
NAME="CentOS Linux"
VERSION="8"
ID="centos"
VERSION_ID="8"
PRETTY_NAME="CentOS Linux 8"
'''
        self.mock_ssh_manager.execute_command.return_value = (0, os_release, '')
        
        os_info = self.manager.detect_os()
        
        self.assertEqual(os_info['VERSION_ID'], '8')
        self.assertEqual(self.manager.package_manager, 'dnf')
        self.assertEqual(self.manager.major_version, 8)
    
    def test_install_packages(self):
        """패키지 설치 테스트"""
        packages = ['gcc', 'make', 'git']
        
        result = self.manager.install_packages(packages)
        
        self.assertTrue(result)
        # yum install이 호출되었는지 확인
        call_args = str(self.mock_ssh_manager.execute_command.call_args)
        self.assertIn('gcc', call_args)
        self.assertIn('make', call_args)
    
    def test_install_development_tools(self):
        """개발 도구 설치 테스트"""
        result = self.manager.install_development_tools()
        
        self.assertTrue(result)
        # Development Tools 그룹이 설치되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('Development' in call for call in calls))
    
    def test_configure_firewall(self):
        """방화벽 설정 테스트"""
        ports = {'slurmctld': 6817, 'slurmd': 6818}
        
        result = self.manager.configure_firewall(ports)
        
        self.assertTrue(result)
        # 포트가 추가되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('6817' in call for call in calls))
        self.assertTrue(any('6818' in call for call in calls))
    
    def test_create_user(self):
        """사용자 생성 테스트"""
        result = self.manager.create_user('testuser', 2000, 2000, ['wheel', 'users'])
        
        self.assertTrue(result)
        # groupadd, useradd, usermod 명령 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('groupadd' in call for call in calls))
        self.assertTrue(any('useradd' in call for call in calls))
        self.assertTrue(any('usermod' in call for call in calls))


class TestUbuntuManager(unittest.TestCase):
    """UbuntuManager 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_ssh_manager = Mock()
        self.hostname = 'ubuntu-node'
        self.manager = UbuntuManager(self.mock_ssh_manager, self.hostname)
        
        # Mock execute_command 기본 응답
        self.mock_ssh_manager.execute_command.return_value = (0, '', '')
    
    def test_detect_os_ubuntu20(self):
        """Ubuntu 20.04 감지 테스트"""
        os_release = '''
NAME="Ubuntu"
VERSION="20.04.3 LTS (Focal Fossa)"
ID=ubuntu
ID_LIKE=debian
VERSION_ID="20.04"
PRETTY_NAME="Ubuntu 20.04.3 LTS"
'''
        self.mock_ssh_manager.execute_command.return_value = (0, os_release, '')
        
        os_info = self.manager.detect_os()
        
        self.assertEqual(os_info['VERSION_ID'], '20.04')
        self.assertEqual(os_info['ID'], 'ubuntu')
    
    def test_update_system(self):
        """시스템 업데이트 테스트"""
        result = self.manager.update_system()
        
        self.assertTrue(result)
        # apt update와 apt upgrade가 호출되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('apt update' in call for call in calls))
        self.assertTrue(any('apt upgrade' in call for call in calls))
    
    def test_install_packages(self):
        """패키지 설치 테스트"""
        packages = ['build-essential', 'python3-dev']
        
        result = self.manager.install_packages(packages)
        
        self.assertTrue(result)
        # apt install이 호출되었는지 확인
        call_args = str(self.mock_ssh_manager.execute_command.call_args)
        self.assertIn('build-essential', call_args)
        self.assertIn('python3-dev', call_args)
    
    def test_configure_firewall_ufw(self):
        """UFW 방화벽 설정 테스트"""
        ports = {'ssh': 22, 'slurmctld': 6817}
        
        result = self.manager.configure_firewall(ports)
        
        self.assertTrue(result)
        # ufw 명령이 호출되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('ufw' in call for call in calls))
    
    def test_install_development_tools(self):
        """개발 도구 설치 테스트"""
        result = self.manager.install_development_tools()
        
        self.assertTrue(result)
        # build-essential이 설치되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('build-essential' in call for call in calls))


class TestOSManagerCommon(unittest.TestCase):
    """OS Manager 공통 기능 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_ssh_manager = Mock()
        self.manager = CentOSManager(self.mock_ssh_manager, 'testnode')
    
    def test_check_command_exists_true(self):
        """명령어 존재 확인 (존재함)"""
        self.mock_ssh_manager.execute_command.return_value = (0, '/usr/bin/gcc', '')
        
        result = self.manager.check_command_exists('gcc')
        
        self.assertTrue(result)
    
    def test_check_command_exists_false(self):
        """명령어 존재 확인 (없음)"""
        self.mock_ssh_manager.execute_command.return_value = (1, '', 'not found')
        
        result = self.manager.check_command_exists('nonexistent')
        
        self.assertFalse(result)
    
    def test_is_service_running_true(self):
        """서비스 실행 확인 (실행 중)"""
        self.mock_ssh_manager.execute_command.return_value = (0, 'active', '')
        
        result = self.manager.is_service_running('sshd')
        
        self.assertTrue(result)
    
    def test_is_service_running_false(self):
        """서비스 실행 확인 (중지)"""
        self.mock_ssh_manager.execute_command.return_value = (3, 'inactive', '')
        
        result = self.manager.is_service_running('httpd')
        
        self.assertFalse(result)
    
    def test_enable_service(self):
        """서비스 활성화 테스트"""
        result = self.manager.enable_service('chronyd')
        
        self.assertTrue(result)
        # systemctl enable과 start가 호출되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('enable chronyd' in call for call in calls))
        self.assertTrue(any('start chronyd' in call for call in calls))
    
    def test_configure_nfs_client(self):
        """NFS 클라이언트 설정 테스트"""
        mount_points = [
            {
                'source': 'controller:/export/home',
                'target': '/home',
                'options': 'rw,sync,hard'
            }
        ]
        
        result = self.manager.configure_nfs_client(mount_points)
        
        self.assertTrue(result)
        # fstab에 추가되었는지 확인
        calls = [str(call) for call in self.mock_ssh_manager.execute_command.call_args_list]
        self.assertTrue(any('/etc/fstab' in call for call in calls))


if __name__ == '__main__':
    unittest.main()
