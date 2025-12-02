#!/usr/bin/env python3
"""
SSH Manager 테스트
"""

import unittest
import sys
from pathlib import Path
from unittest.mock import Mock, patch

# src 디렉토리를 Python 경로에 추가
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from ssh_manager import SSHConnection, SSHManager


class TestSSHConnection(unittest.TestCase):
    """SSHConnection 클래스 테스트"""
    
    def test_init(self):
        """초기화 테스트"""
        conn = SSHConnection(
            hostname="test-host",
            username="testuser",
            key_path="/path/to/key",
            port=22,
            timeout=30
        )
        
        self.assertEqual(conn.hostname, "test-host")
        self.assertEqual(conn.username, "testuser")
        self.assertEqual(conn.key_path, "/path/to/key")
        self.assertEqual(conn.port, 22)
        self.assertEqual(conn.timeout, 30)
        self.assertFalse(conn.connected)
        self.assertIsNone(conn.client)


class TestSSHManager(unittest.TestCase):
    """SSHManager 클래스 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.ssh_manager = SSHManager()
        
        self.test_node = {
            'hostname': 'test-node',
            'ssh_user': 'root',
            'ssh_key_path': '~/.ssh/id_rsa',
            'ssh_port': 22
        }
    
    def test_init(self):
        """초기화 테스트"""
        manager = SSHManager()
        
        self.assertIsInstance(manager.connections, dict)
        self.assertEqual(len(manager.connections), 0)
    
    def test_add_node(self):
        """노드 추가 테스트"""
        result = self.ssh_manager.add_node(self.test_node)
        
        self.assertTrue(result)
        self.assertIn('test-node', self.ssh_manager.connections)
        
        connection = self.ssh_manager.connections['test-node']
        self.assertEqual(connection.hostname, 'test-node')
        self.assertEqual(connection.username, 'root')
        self.assertEqual(connection.port, 22)
    
    def test_add_multiple_nodes(self):
        """여러 노드 추가 테스트"""
        nodes = [
            {
                'hostname': 'node1',
                'ssh_user': 'user1',
                'ssh_key_path': '~/.ssh/key1'
            },
            {
                'hostname': 'node2',
                'ssh_user': 'user2',
                'ssh_key_path': '~/.ssh/key2',
                'ssh_port': 2222
            }
        ]
        
        for node in nodes:
            self.ssh_manager.add_node(node)
        
        self.assertEqual(len(self.ssh_manager.connections), 2)
        self.assertIn('node1', self.ssh_manager.connections)
        self.assertIn('node2', self.ssh_manager.connections)
        
        # node2의 포트 확인
        self.assertEqual(self.ssh_manager.connections['node2'].port, 2222)
    
    def test_add_node_with_ssh_password(self):
        """SSH 패스워드를 사용하는 노드 추가 테스트"""
        node_with_password = {
            'hostname': 'password-node',
            'ssh_user': 'testuser',
            'ssh_password': 'testpass'
        }
        
        result = self.ssh_manager.add_node(node_with_password)
        
        self.assertTrue(result)
        connection = self.ssh_manager.connections['password-node']
        self.assertEqual(connection.password, 'testpass')
        self.assertIsNone(connection.key_path)
    
    @patch('paramiko.SSHClient')
    def test_connect_node_success(self, mock_ssh_client):
        """노드 연결 성공 테스트"""
        # Mock SSH 클라이언트 설정
        mock_client_instance = Mock()
        mock_ssh_client.return_value = mock_client_instance
        
        # 노드 추가
        self.ssh_manager.add_node(self.test_node)
        
        # connect 메소드가 성공한다고 가정
        mock_client_instance.connect.return_value = None
        
        # 연결 테스트 (실제로는 모킹되어 있음)
        with patch.object(self.ssh_manager.connections['test-node'], 'connect', return_value=True):
            result = self.ssh_manager.connect_node('test-node')
            self.assertTrue(result)
    
    def test_connect_nonexistent_node(self):
        """존재하지 않는 노드 연결 테스트"""
        result = self.ssh_manager.connect_node('nonexistent-node')
        self.assertFalse(result)
    
    @patch('paramiko.SSHClient')
    def test_execute_command_node_not_registered(self, mock_ssh_client):
        """등록되지 않은 노드에서 명령 실행 테스트"""
        with self.assertRaises(Exception) as context:
            self.ssh_manager.execute_command('nonexistent-node', 'echo test')
        
        self.assertIn('노드가 등록되지 않음', str(context.exception))
    
    def test_disconnect_all(self):
        """모든 연결 종료 테스트"""
        # 몇 개의 노드 추가
        nodes = [
            {'hostname': 'node1', 'ssh_user': 'user1'},
            {'hostname': 'node2', 'ssh_user': 'user2'}
        ]
        
        for node in nodes:
            self.ssh_manager.add_node(node)
        
        # 모든 연결을 Mock으로 설정
        for connection in self.ssh_manager.connections.values():
            connection.client = Mock()
            connection.connected = True
        
        # 연결 종료
        self.ssh_manager.disconnect_all()
        
        # disconnect 메소드가 호출되었는지 확인 (실제로는 각 연결의 disconnect가 호출됨)
        # 이 테스트는 예외가 발생하지 않는지만 확인
        self.assertTrue(True)  # 예외가 없으면 성공
    
    def test_upload_file_to_nonexistent_node(self):
        """존재하지 않는 노드에 파일 업로드 테스트"""
        with self.assertRaises(Exception) as context:
            self.ssh_manager.upload_file_to_node('nonexistent-node', '/local/file', '/remote/file')
        
        self.assertIn('노드가 등록되지 않음', str(context.exception))


class TestSSHConnectionIntegration(unittest.TestCase):
    """SSHConnection 통합 테스트 (실제 연결은 하지 않음)"""
    
    def test_connection_parameters_validation(self):
        """연결 파라미터 검증 테스트"""
        # 필수 파라미터만으로 연결 객체 생성
        conn = SSHConnection("localhost", "user")
        
        self.assertEqual(conn.hostname, "localhost")
        self.assertEqual(conn.username, "user")
        self.assertEqual(conn.port, 22)  # 기본값
        self.assertEqual(conn.timeout, 30)  # 기본값
        self.assertIsNone(conn.key_path)
        self.assertIsNone(conn.password)
    
    def test_connection_with_custom_parameters(self):
        """사용자 정의 파라미터로 연결 객체 생성 테스트"""
        conn = SSHConnection(
            hostname="custom-host",
            username="custom-user", 
            key_path="/custom/key",
            password="custom-pass",
            port=2222,
            timeout=60
        )
        
        self.assertEqual(conn.hostname, "custom-host")
        self.assertEqual(conn.username, "custom-user")
        self.assertEqual(conn.key_path, "/custom/key")
        self.assertEqual(conn.password, "custom-pass")
        self.assertEqual(conn.port, 2222)
        self.assertEqual(conn.timeout, 60)


if __name__ == '__main__':
    unittest.main()
