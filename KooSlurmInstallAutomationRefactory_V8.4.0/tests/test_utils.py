#!/usr/bin/env python3
"""
Utils 모듈 테스트
"""

import unittest
import sys
from pathlib import Path

# src 디렉토리를 Python 경로에 추가
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from utils import (
    format_time_duration, format_file_size, validate_hostname, 
    validate_ip_address, validate_port, generate_slurm_node_list,
    check_system_requirements
)


class TestUtils(unittest.TestCase):
    """Utils 함수들 테스트"""
    
    def test_format_time_duration(self):
        """시간 형식 변환 테스트"""
        # 초만 있는 경우
        self.assertEqual(format_time_duration(45), "00:45")
        
        # 분과 초
        self.assertEqual(format_time_duration(125), "02:05")
        
        # 시, 분, 초
        self.assertEqual(format_time_duration(3661), "01:01:01")
        
        # 0초
        self.assertEqual(format_time_duration(0), "00:00")
        
        # 큰 값
        self.assertEqual(format_time_duration(7323), "02:02:03")
    
    def test_format_file_size(self):
        """파일 크기 형식 변환 테스트"""
        # 바이트
        self.assertEqual(format_file_size(512), "512.0B")
        
        # 킬로바이트
        self.assertEqual(format_file_size(1536), "1.5KB")
        
        # 메가바이트  
        self.assertEqual(format_file_size(1048576), "1.0MB")
        
        # 기가바이트
        self.assertEqual(format_file_size(2147483648), "2.0GB")
        
        # 0 바이트
        self.assertEqual(format_file_size(0), "0.0B")
    
    def test_validate_hostname(self):
        """호스트네임 검증 테스트"""
        # 유효한 호스트네임
        self.assertTrue(validate_hostname("node01"))
        self.assertTrue(validate_hostname("test-server"))
        self.assertTrue(validate_hostname("server.example.com"))
        self.assertTrue(validate_hostname("a"))
        self.assertTrue(validate_hostname("123"))
        
        # 잘못된 호스트네임
        self.assertFalse(validate_hostname(""))
        self.assertFalse(validate_hostname("-node"))
        self.assertFalse(validate_hostname("node-"))
        self.assertFalse(validate_hostname("node..server"))
        self.assertFalse(validate_hostname("a" * 64))  # 너무 긴 레이블
    
    def test_validate_ip_address(self):
        """IP 주소 검증 테스트"""
        # 유효한 IPv4 주소
        self.assertTrue(validate_ip_address("192.168.1.1"))
        self.assertTrue(validate_ip_address("10.0.0.1"))
        self.assertTrue(validate_ip_address("127.0.0.1"))
        self.assertTrue(validate_ip_address("255.255.255.255"))
        
        # 유효한 IPv6 주소
        self.assertTrue(validate_ip_address("::1"))
        self.assertTrue(validate_ip_address("2001:db8::1"))
        
        # 잘못된 IP 주소
        self.assertFalse(validate_ip_address(""))
        self.assertFalse(validate_ip_address("256.1.1.1"))
        self.assertFalse(validate_ip_address("192.168.1"))
        self.assertFalse(validate_ip_address("invalid-ip"))
        self.assertFalse(validate_ip_address("192.168.1.1.1"))
    
    def test_validate_port(self):
        """포트 번호 검증 테스트"""
        # 유효한 포트
        self.assertTrue(validate_port(22))
        self.assertTrue(validate_port(80))
        self.assertTrue(validate_port(443))
        self.assertTrue(validate_port(65535))
        self.assertTrue(validate_port(1))
        
        # 잘못된 포트
        self.assertFalse(validate_port(0))
        self.assertFalse(validate_port(65536))
        self.assertFalse(validate_port(-1))
        self.assertFalse(validate_port(100000))
    
    def test_generate_slurm_node_list(self):
        """Slurm 노드 리스트 생성 테스트"""
        # 빈 리스트
        self.assertEqual(generate_slurm_node_list([]), "")
        
        # 단일 노드
        self.assertEqual(generate_slurm_node_list(["node01"]), "node01")
        
        # 연속된 숫자 패턴
        nodes = ["node01", "node02", "node03"]
        result = generate_slurm_node_list(nodes)
        self.assertIn("node[01-03]", result)
        
        # 비연속 숫자
        nodes = ["node01", "node03", "node05"]
        result = generate_slurm_node_list(nodes)
        self.assertIn("node[01,03,05]", result)
        
        # 혼합 패턴
        nodes = ["node01", "node02", "gpu01", "gpu02"]
        result = generate_slurm_node_list(nodes)
        # 두 개의 그룹이 포함되어야 함
        self.assertTrue("node[01-02]" in result or "gpu[01-02]" in result)
        
        # 숫자가 없는 호스트네임
        nodes = ["controller", "master"]
        result = generate_slurm_node_list(nodes)
        self.assertIn("controller", result)
        self.assertIn("master", result)
    
    def test_check_system_requirements(self):
        """시스템 요구사항 확인 테스트"""
        requirements = check_system_requirements()
        
        # 반환값이 딕셔너리여야 함
        self.assertIsInstance(requirements, dict)
        
        # 필수 키들이 있어야 함
        required_keys = ['python_version', 'ssh_client', 'required_modules']
        for key in required_keys:
            self.assertIn(key, requirements)
            self.assertIsInstance(requirements[key], bool)
        
        # Python 버전은 테스트 환경에서 True여야 함 (Python 3.7+)
        self.assertTrue(requirements['python_version'])


if __name__ == '__main__':
    unittest.main()
