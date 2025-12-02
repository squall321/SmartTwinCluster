#!/usr/bin/env python3
"""
Slurm 설치 자동화 - SSH 연결 관리
원격 노드에 SSH로 연결하여 명령을 실행하는 모듈
"""

import paramiko
import socket
import time
from typing import Dict, List, Optional, Tuple, Any
from pathlib import Path
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
import os


class SSHConnection:
    """개별 SSH 연결을 관리하는 클래스"""
    
    def __init__(self, hostname: str, username: str, 
                 key_path: str = None, password: str = None,
                 port: int = 22, timeout: int = 30, ip_address: str = None):
        self.hostname = hostname
        self.ip_address = ip_address  # IP 주소 추가
        self.username = username
        self.key_path = key_path
        self.password = password
        self.port = port
        self.timeout = timeout
        self.client = None
        self.connected = False
        
        # 연결에 사용할 주소 결정 (IP 우선)
        self.connect_address = self.ip_address if self.ip_address else self.hostname
    
    def connect(self) -> bool:
        """SSH 연결 수립 (IP 주소 우선 사용)"""
        try:
            self.client = paramiko.SSHClient()
            self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # 연결 주소 표시 (디버깅용)
            connect_info = f"{self.hostname}"
            if self.ip_address and self.ip_address != self.hostname:
                connect_info = f"{self.hostname} ({self.ip_address})"
            
            # SSH 키 또는 패스워드로 연결 (IP 주소 우선 사용)
            if self.key_path and Path(self.key_path).exists():
                self.client.connect(
                    hostname=self.connect_address,  # IP 우선!
                    username=self.username,
                    key_filename=self.key_path,
                    port=self.port,
                    timeout=self.timeout
                )
            elif self.password:
                self.client.connect(
                    hostname=self.connect_address,  # IP 우선!
                    username=self.username,
                    password=self.password,
                    port=self.port,
                    timeout=self.timeout
                )
            else:
                # 기본 SSH 키들 시도
                self.client.connect(
                    hostname=self.connect_address,  # IP 우선!
                    username=self.username,
                    port=self.port,
                    timeout=self.timeout
                )
            
            self.connected = True
            return True
            
        except paramiko.AuthenticationException:
            print(f"❌ {self.hostname}: SSH 인증 실패")
            return False
        except paramiko.SSHException as e:
            print(f"❌ {self.hostname}: SSH 연결 오류 - {e}")
            return False
        except socket.timeout:
            print(f"❌ {self.hostname}: 연결 시간 초과 (주소: {self.connect_address})")
            return False
        except socket.gaierror as e:
            print(f"❌ {self.hostname}: 호스트명 확인 실패 - {e} (주소: {self.connect_address})")
            print(f"   💡 힌트: /etc/hosts에 '{self.connect_address}'를 등록하거나 YAML의 ip_address를 확인하세요")
            return False
        except Exception as e:
            print(f"❌ {self.hostname}: 연결 실패 - {e} (주소: {self.connect_address})")
            return False
    
    def execute_command(self, command: str, timeout: int = 300, max_retries: int = 3, show_output: bool = True) -> Tuple[int, str, str]:
        """원격 명령 실행 (재시도 로직 포함)
        
        Args:
            command: 실행할 명령
            timeout: 타임아웃 (초)
            max_retries: 최대 재시도 횟수
            show_output: 출력 표시 여부
            
        Returns:
            (exit_code, stdout, stderr)
        """
        if not self.connected or not self.client:
            raise Exception(f"{self.hostname}: SSH 연결이 되어있지 않음")
        
        last_exception = None
        for attempt in range(max_retries):
            try:
                stdin, stdout, stderr = self.client.exec_command(command, timeout=timeout)
                
                # 명령 완료까지 대기
                exit_status = stdout.channel.recv_exit_status()
                
                # 출력 읽기
                stdout_data = stdout.read().decode('utf-8')
                stderr_data = stderr.read().decode('utf-8')
                
                return exit_status, stdout_data, stderr_data
                
            except socket.timeout as e:
                last_exception = Exception(f"{self.hostname}: 명령 실행 시간 초과 - {command}")
                if attempt < max_retries - 1:
                    wait_time = 2 ** attempt  # 지수 백오프
                    print(f"⚠️  {self.hostname}: 재시도 {attempt + 1}/{max_retries} ({wait_time}초 후)...")
                    time.sleep(wait_time)
                continue
            except Exception as e:
                last_exception = Exception(f"{self.hostname}: 명령 실행 실패 - {e}")
                if attempt < max_retries - 1:
                    wait_time = 2 ** attempt
                    print(f"⚠️  {self.hostname}: 재시도 {attempt + 1}/{max_retries} ({wait_time}초 후)...")
                    time.sleep(wait_time)
                continue
        
        # 모든 재시도 실패
        raise last_exception
    
    def upload_file(self, local_path: str, remote_path: str) -> bool:
        """파일 업로드"""
        if not self.connected or not self.client:
            raise Exception(f"{self.hostname}: SSH 연결이 되어있지 않음")
        
        try:
            sftp = self.client.open_sftp()
            sftp.put(local_path, remote_path)
            sftp.close()
            return True
        except Exception as e:
            print(f"❌ {self.hostname}: 파일 업로드 실패 - {e}")
            return False
    
    def download_file(self, remote_path: str, local_path: str) -> bool:
        """파일 다운로드"""
        if not self.connected or not self.client:
            raise Exception(f"{self.hostname}: SSH 연결이 되어있지 않음")
        
        try:
            sftp = self.client.open_sftp()
            sftp.get(remote_path, local_path)
            sftp.close()
            return True
        except Exception as e:
            print(f"❌ {self.hostname}: 파일 다운로드 실패 - {e}")
            return False
    
    def disconnect(self):
        """SSH 연결 종료"""
        if self.client:
            self.client.close()
            self.connected = False


class SSHManager:
    """여러 노드의 SSH 연결을 관리하는 클래스"""
    
    def __init__(self):
        self.connections = {}
        self.lock = threading.Lock()
    
    def add_node(self, node_config: Dict[str, Any]) -> bool:
        """노드를 SSH 관리 목록에 추가 (IP 주소 우선 사용)"""
        hostname = node_config['hostname']
        ip_address = node_config.get('ip_address')  # IP 주소 추가
        username = node_config.get('ssh_user', 'root')
        key_path = node_config.get('ssh_key_path')
        password = node_config.get('ssh_password')
        port = node_config.get('ssh_port', 22)
        
        # SSH 키 경로 확장
        if key_path and key_path.startswith('~'):
            key_path = os.path.expanduser(key_path)
        
        self.connections[hostname] = SSHConnection(
            hostname=hostname,
            ip_address=ip_address,  # IP 주소 전달
            username=username,
            key_path=key_path,
            password=password,
            port=port
        )
        
        return True
    
    def connect_node(self, hostname: str) -> bool:
        """특정 노드에 연결"""
        if hostname not in self.connections:
            print(f"❌ {hostname}: 노드가 등록되지 않음")
            return False
        
        conn = self.connections[hostname]
        success = conn.connect()
        
        if success:
            print(f"✅ {hostname}: SSH 연결 성공")
        
        return success
    
    def connect_all_nodes(self, max_workers: int = 10) -> Dict[str, bool]:
        """모든 노드에 병렬 연결"""
        results = {}
        
        def connect_single_node(hostname):
            return hostname, self.connect_node(hostname)
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_hostname = {
                executor.submit(connect_single_node, hostname): hostname 
                for hostname in self.connections
            }
            
            for future in as_completed(future_to_hostname):
                hostname, success = future.result()
                results[hostname] = success
        
        # 연결 결과 요약
        successful = sum(1 for success in results.values() if success)
        total = len(results)
        
        print(f"\n📊 SSH 연결 결과: {successful}/{total} 성공")
        
        if successful < total:
            print("❌ 연결 실패 노드:")
            for hostname, success in results.items():
                if not success:
                    print(f"  - {hostname}")
        
        return results
    
    def execute_command(self, hostname: str, command: str, 
                       timeout: int = 300, show_output: bool = True) -> Tuple[int, str, str]:
        """특정 노드에서 명령 실행"""
        if hostname not in self.connections:
            raise Exception(f"{hostname}: 노드가 등록되지 않음")
        
        conn = self.connections[hostname]
        if not conn.connected:
            if not self.connect_node(hostname):
                raise Exception(f"{hostname}: SSH 연결 실패")
        
        if show_output:
            print(f"🔧 {hostname}: {command}")
        
        exit_code, stdout, stderr = conn.execute_command(command, timeout)
        
        if show_output and stdout:
            print(f"📤 {hostname}: {stdout.strip()}")
        
        if show_output and stderr:
            print(f"⚠️  {hostname}: {stderr.strip()}")
        
        return exit_code, stdout, stderr
    
    def execute_on_all_nodes(self, command: str, timeout: int = 300, 
                           max_workers: int = 10) -> Dict[str, Tuple[int, str, str]]:
        """모든 노드에서 명령 병렬 실행"""
        results = {}
        
        def execute_single_command(hostname):
            try:
                return hostname, self.execute_command(hostname, command, timeout, show_output=False)
            except Exception as e:
                print(f"❌ {hostname}: 명령 실행 실패 - {e}")
                return hostname, (-1, "", str(e))
        
        print(f"🔧 모든 노드에서 실행: {command}")
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_hostname = {
                executor.submit(execute_single_command, hostname): hostname 
                for hostname in self.connections
            }
            
            for future in as_completed(future_to_hostname):
                hostname, result = future.result()
                results[hostname] = result
                
                exit_code, stdout, stderr = result
                if exit_code == 0:
                    print(f"✅ {hostname}: 성공")
                    if stdout.strip():
                        print(f"   출력: {stdout.strip()}")
                else:
                    print(f"❌ {hostname}: 실패 (exit_code: {exit_code})")
                    if stderr.strip():
                        print(f"   오류: {stderr.strip()}")
        
        return results
    
    def upload_file_to_node(self, hostname: str, local_path: str, remote_path: str) -> bool:
        """특정 노드에 파일 업로드"""
        if hostname not in self.connections:
            raise Exception(f"{hostname}: 노드가 등록되지 않음")
        
        conn = self.connections[hostname]
        if not conn.connected:
            if not self.connect_node(hostname):
                raise Exception(f"{hostname}: SSH 연결 실패")
        
        print(f"📤 {hostname}: {local_path} -> {remote_path}")
        return conn.upload_file(local_path, remote_path)
    
    def upload_file_to_all_nodes(self, local_path: str, remote_path: str, 
                                max_workers: int = 10) -> Dict[str, bool]:
        """모든 노드에 파일 업로드"""
        results = {}
        
        def upload_single_file(hostname):
            try:
                success = self.upload_file_to_node(hostname, local_path, remote_path)
                return hostname, success
            except Exception as e:
                print(f"❌ {hostname}: 파일 업로드 실패 - {e}")
                return hostname, False
        
        print(f"📤 모든 노드에 업로드: {local_path} -> {remote_path}")
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_hostname = {
                executor.submit(upload_single_file, hostname): hostname 
                for hostname in self.connections
            }
            
            for future in as_completed(future_to_hostname):
                hostname, success = future.result()
                results[hostname] = success
                
                if success:
                    print(f"✅ {hostname}: 업로드 성공")
                else:
                    print(f"❌ {hostname}: 업로드 실패")
        
        return results
    
    def test_connectivity(self, hostname: str) -> Dict[str, Any]:
        """노드 연결성 테스트"""
        result = {
            'hostname': hostname,
            'ping': False,
            'ssh': False,
            'sudo': False,
            'os_info': None,
            'errors': []
        }
        
        # 1. Ping 테스트
        try:
            import subprocess
            ping_result = subprocess.run(
                ['ping', '-c', '1', '-W', '3', hostname], 
                capture_output=True, timeout=5
            )
            result['ping'] = ping_result.returncode == 0
        except:
            result['errors'].append("Ping 테스트 실패")
        
        # 2. SSH 연결 테스트
        if hostname in self.connections:
            result['ssh'] = self.connect_node(hostname)
        
        if result['ssh']:
            # 3. sudo 권한 테스트
            try:
                exit_code, stdout, stderr = self.execute_command(
                    hostname, "sudo -n echo 'sudo test'", show_output=False
                )
                result['sudo'] = exit_code == 0
            except:
                result['errors'].append("sudo 권한 테스트 실패")
            
            # 4. OS 정보 수집
            try:
                exit_code, stdout, stderr = self.execute_command(
                    hostname, "cat /etc/os-release", show_output=False
                )
                if exit_code == 0:
                    result['os_info'] = stdout.strip()
            except:
                result['errors'].append("OS 정보 수집 실패")
        
        return result
    
    def test_all_nodes_connectivity(self, max_workers: int = 10) -> Dict[str, Dict[str, Any]]:
        """모든 노드 연결성 테스트"""
        results = {}
        
        def test_single_node(hostname):
            return hostname, self.test_connectivity(hostname)
        
        print("🔍 노드 연결성 테스트 시작...")
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_hostname = {
                executor.submit(test_single_node, hostname): hostname 
                for hostname in self.connections
            }
            
            for future in as_completed(future_to_hostname):
                hostname, result = future.result()
                results[hostname] = result
        
        # 테스트 결과 요약
        self._print_connectivity_report(results)
        
        return results
    
    def _print_connectivity_report(self, results: Dict[str, Dict[str, Any]]):
        """연결성 테스트 결과 보고서 출력"""
        print("\n" + "="*60)
        print("노드 연결성 테스트 결과")
        print("="*60)
        
        for hostname, result in results.items():
            print(f"\n🖥️  {hostname}:")
            print(f"  Ping:  {'✅ 성공' if result['ping'] else '❌ 실패'}")
            print(f"  SSH:   {'✅ 성공' if result['ssh'] else '❌ 실패'}")
            print(f"  sudo:  {'✅ 성공' if result['sudo'] else '❌ 실패'}")
            
            if result['os_info']:
                # OS 정보에서 주요 정보 추출
                os_lines = result['os_info'].split('\n')
                for line in os_lines:
                    if line.startswith('PRETTY_NAME='):
                        os_name = line.split('=', 1)[1].strip().strip('"')
                        print(f"  OS:    {os_name}")
                        break
            
            if result['errors']:
                print("  오류:")
                for error in result['errors']:
                    print(f"    - {error}")
        
        # 전체 요약
        total_nodes = len(results)
        ssh_ok = sum(1 for r in results.values() if r['ssh'])
        ping_ok = sum(1 for r in results.values() if r['ping'])
        sudo_ok = sum(1 for r in results.values() if r['sudo'])
        
        print(f"\n📊 전체 요약:")
        print(f"  총 노드: {total_nodes}")
        print(f"  Ping 성공: {ping_ok}/{total_nodes}")
        print(f"  SSH 성공: {ssh_ok}/{total_nodes}")
        print(f"  sudo 성공: {sudo_ok}/{total_nodes}")
        
        if ssh_ok == total_nodes and sudo_ok == total_nodes:
            print("\n✅ 모든 노드가 설치 준비 완료!")
        else:
            print("\n⚠️  일부 노드에서 문제 발견. 설치 전에 해결 필요.")
        
        print("="*60)
    
    def disconnect_all(self):
        """모든 SSH 연결 종료"""
        with self.lock:
            for conn in self.connections.values():
                conn.disconnect()
        
        print("🔌 모든 SSH 연결 종료됨")


def main():
    """테스트 메인 함수"""
    # 테스트용 노드 설정
    test_nodes = [
        {
            'hostname': 'localhost',
            'ssh_user': 'root',
            'ssh_key_path': '~/.ssh/id_rsa'
        }
    ]
    
    ssh_manager = SSHManager()
    
    # 노드 추가
    for node in test_nodes:
        ssh_manager.add_node(node)
    
    # 연결 테스트
    ssh_manager.test_all_nodes_connectivity()
    
    # 간단한 명령 실행 테스트
    try:
        ssh_manager.execute_on_all_nodes("whoami")
        ssh_manager.execute_on_all_nodes("uname -a")
    except Exception as e:
        print(f"명령 실행 테스트 실패: {e}")
    
    # 연결 종료
    ssh_manager.disconnect_all()


if __name__ == "__main__":
    main()
