"""
SSH Tunnel Manager
VNC 세션을 위한 SSH 터널을 관리
"""

import subprocess
import time
import signal
import os
from typing import Dict, Optional


class SSHTunnelManager:
    """SSH 터널 관리 클래스"""

    def __init__(self):
        # 터널 정보 저장: {session_id: {'pid': pid, 'local_port': port, 'remote_host': host, 'remote_port': port}}
        self.tunnels: Dict[str, dict] = {}
        self.base_port = 8000  # 로컬 포트 시작 번호
        self.used_ports = set()

    def _get_next_available_port(self) -> int:
        """사용 가능한 다음 포트 번호 반환"""
        port = self.base_port
        while port in self.used_ports:
            port += 1
        self.used_ports.add(port)
        return port

    def create_tunnel(self, session_id: str, remote_host: str, remote_port: int) -> Optional[int]:
        """
        SSH 터널 생성

        Args:
            session_id: 세션 ID
            remote_host: 원격 호스트 (예: viz-node001 또는 192.168.122.252)
            remote_port: 원격 포트 (예: 6080)

        Returns:
            로컬 포트 번호 또는 None (실패 시)
        """
        # 이미 터널이 존재하면 반환
        if session_id in self.tunnels:
            print(f"[SSHTunnelManager] Tunnel already exists for session {session_id}")
            return self.tunnels[session_id]['local_port']

        local_port = self._get_next_available_port()

        try:
            # SSH 터널 명령어
            # -N: 원격 명령 실행하지 않음 (터널만)
            # -f: 백그라운드로 실행
            # -g: 외부 연결 허용 (0.0.0.0 바인딩)
            # -L: 로컬 포트 포워딩
            # -o ServerAliveInterval=30: 30초마다 keep-alive 패킷 전송
            # -o ServerAliveCountMax=3: keep-alive 실패 3번까지 허용
            # remote_port는 viz-node에서 websockify가 실행되는 동적 포트 (gedit_vnc_job.sh에서 설정)

            cmd = [
                'ssh',
                '-N',  # 원격 명령 실행 안함
                '-f',  # 백그라운드 실행
                '-g',  # 외부 연결 허용 (0.0.0.0 바인딩)
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'ServerAliveInterval=30',
                '-o', 'ServerAliveCountMax=3',
                '-L', f'0.0.0.0:{local_port}:localhost:{remote_port}',  # 동적 websockify 포트 사용
                remote_host
            ]

            print(f"[SSHTunnelManager] Creating tunnel: localhost:{local_port} -> {remote_host}:{remote_port}")

            # SSH 터널 시작
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                print(f"[SSHTunnelManager] Failed to create tunnel: {result.stderr}")
                self.used_ports.remove(local_port)
                return None

            # SSH 프로세스 PID 찾기
            time.sleep(1)  # SSH 프로세스가 완전히 시작될 때까지 대기

            # 생성된 SSH 터널의 PID 찾기
            pid_cmd = f"ps aux | grep 'ssh.*{local_port}:localhost:{remote_port}' | grep -v grep | awk '{{print $2}}' | head -1"
            pid_result = subprocess.run(pid_cmd, shell=True, capture_output=True, text=True)
            pid = pid_result.stdout.strip()

            if not pid:
                print(f"[SSHTunnelManager] Warning: Could not find SSH tunnel PID")
                pid = None
            else:
                pid = int(pid)
                print(f"[SSHTunnelManager] SSH tunnel created with PID: {pid}")

            # 터널 정보 저장
            self.tunnels[session_id] = {
                'pid': pid,
                'local_port': local_port,
                'remote_host': remote_host,
                'remote_port': remote_port,
                'created_at': time.time()
            }

            return local_port

        except Exception as e:
            print(f"[SSHTunnelManager] Error creating tunnel: {e}")
            if local_port in self.used_ports:
                self.used_ports.remove(local_port)
            return None

    def close_tunnel(self, session_id: str) -> bool:
        """
        SSH 터널 종료

        Args:
            session_id: 세션 ID

        Returns:
            성공 여부
        """
        if session_id not in self.tunnels:
            print(f"[SSHTunnelManager] No tunnel found for session {session_id}")
            return False

        tunnel_info = self.tunnels[session_id]
        pid = tunnel_info.get('pid')
        local_port = tunnel_info['local_port']

        try:
            # PID로 프로세스 종료 시도
            if pid:
                try:
                    os.kill(pid, signal.SIGTERM)
                    print(f"[SSHTunnelManager] Killed SSH tunnel process {pid}")
                except ProcessLookupError:
                    print(f"[SSHTunnelManager] Process {pid} not found (already terminated)")
                except Exception as e:
                    print(f"[SSHTunnelManager] Error killing process {pid}: {e}")

            # 포트를 사용하는 SSH 프로세스 강제 종료 (백업)
            kill_cmd = f"lsof -ti:{local_port} | xargs kill -9 2>/dev/null"
            subprocess.run(kill_cmd, shell=True)

            # 터널 정보 삭제
            del self.tunnels[session_id]
            self.used_ports.remove(local_port)

            print(f"[SSHTunnelManager] Tunnel closed for session {session_id}")
            return True

        except Exception as e:
            print(f"[SSHTunnelManager] Error closing tunnel: {e}")
            return False

    def get_tunnel_info(self, session_id: str) -> Optional[dict]:
        """터널 정보 조회"""
        return self.tunnels.get(session_id)

    def cleanup_all(self):
        """모든 터널 정리"""
        print("[SSHTunnelManager] Cleaning up all tunnels...")
        session_ids = list(self.tunnels.keys())
        for session_id in session_ids:
            self.close_tunnel(session_id)
        print("[SSHTunnelManager] All tunnels cleaned up")
