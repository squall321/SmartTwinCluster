"""
App Session Service - Redis 기반

앱 세션의 생명주기를 관리하는 서비스
Redis를 사용하여 Backend 재시작 후에도 세션 유지
"""

import sys
import os
import uuid
import time
from datetime import datetime
from typing import Dict, List, Optional

# Add common module to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from common import RedisSessionManager, get_redis_client
from services.slurm_app_manager import SlurmAppManager
from services.ssh_tunnel_manager import SSHTunnelManager


class AppSessionService:
    """앱 세션 관리 서비스 - Redis 기반"""

    def __init__(self):
        # Redis 세션 관리자 초기화
        try:
            redis_client = get_redis_client()
            self.session_manager = RedisSessionManager('app', ttl=7200, redis_client=redis_client, legacy_key_pattern=True)
            print("[AppSessionService] Redis session manager initialized")
        except Exception as e:
            print(f"[AppSessionService] WARNING: Failed to initialize Redis: {e}")
            print("[AppSessionService] Sessions will not persist across restarts!")
            # Fallback to memory-based (for development/debugging)
            self.session_manager = None
            self._sessions_memory = {}

        # Slurm 앱 매니저
        self.slurm_manager = SlurmAppManager()

        # SSH 터널 매니저
        self.tunnel_manager = SSHTunnelManager()

        # 사용 가능한 앱 목록
        self.available_apps = {
            'gedit': {
                'id': 'gedit',
                'name': 'GEdit',
                'version': '1.0.0',
                'description': 'Simple GNOME text editor for Linux',
                'category': 'editor',
                'tags': ['text', 'editor', 'document', 'gnome'],
                'container_image': 'gedit.sif',
                'default_config': {
                    'resources': {
                        'cpus': 2,
                        'memory': '4Gi',
                        'gpu': False
                    },
                    'display': {
                        'type': 'novnc',
                        'width': 1280,
                        'height': 720
                    }
                }
            }
        }

        # VNC 포트 범위 (6080-6099) - 이미 사용 중인 포트는 Redis에서 체크
        self.vnc_port_range = range(6080, 6100)

    def list_available_apps(self) -> List[dict]:
        """사용 가능한 앱 목록 반환"""
        return list(self.available_apps.values())

    def get_app_info(self, app_id: str) -> Optional[dict]:
        """특정 앱 정보 조회"""
        return self.available_apps.get(app_id)

    def _get_used_ports(self) -> set:
        """현재 사용 중인 VNC 포트 목록 조회"""
        used_ports = set()

        # Redis에서 모든 세션 조회
        if self.session_manager:
            sessions = self.session_manager.list_sessions()
            for session in sessions:
                if 'vnc_port' in session:
                    used_ports.add(session['vnc_port'])
        else:
            # Fallback to memory
            for session in self._sessions_memory.values():
                if 'vnc_port' in session:
                    used_ports.add(session['vnc_port'])

        return used_ports

    def _allocate_port(self) -> int:
        """사용 가능한 VNC 포트 할당"""
        used_ports = self._get_used_ports()

        for port in self.vnc_port_range:
            if port not in used_ports:
                return port

        raise Exception("No available VNC ports")

    def create_session(self, app_id: str, config: dict, username: str = None) -> dict:
        """
        새 세션 생성

        Args:
            app_id: 앱 ID (예: 'gedit')
            config: 앱 설정
            username: SSO 로그인 사용자명 (JWT에서 추출)

        Returns:
            생성된 세션 정보
        """
        # 앱 존재 확인
        app_info = self.available_apps.get(app_id)
        if not app_info:
            raise ValueError(f"App {app_id} not found")

        # 세션 ID 생성
        session_id = str(uuid.uuid4())

        # VNC 포트 할당
        vnc_port = self._allocate_port()

        # 세션 정보 생성 (사용자 정보 포함)
        session = {
            'id': session_id,
            'appId': app_id,
            'appName': app_info['name'],
            'username': username,  # SSO 사용자명 저장
            'status': 'creating',  # creating -> running -> stopped
            'config': config,
            'vnc_port': vnc_port,
            'displayUrl': f'/vncproxy/{vnc_port}/vnc.html?autoconnect=true&resize=scale',
            'websocketUrl': f'/vncproxy/{vnc_port}/websockify',
            'createdAt': datetime.now().isoformat(),
            'updatedAt': datetime.now().isoformat(),
            'container_id': None,
        }

        # Redis에 세션 저장
        if self.session_manager:
            self.session_manager.create_session(session_id, session)
        else:
            self._sessions_memory[session_id] = session

        # 실제 Apptainer 컨테이너 시작
        self._start_real_session(session_id, app_id, vnc_port)

        return session

    def _start_real_session(self, session_id: str, app_id: str, vnc_port: int):
        """Slurm Job 제출하여 세션 시작"""
        import threading

        def submit_job():
            try:
                # Slurm Job 제출
                job_info = self.slurm_manager.submit_app_job(
                    session_id=session_id,
                    app_id=app_id,
                    vnc_port=vnc_port
                )

                # 세션 업데이트
                session = self.get_session(session_id)
                if session:
                    session['job_id'] = job_info['job_id']
                    session['status'] = 'pending'
                    session['updatedAt'] = datetime.now().isoformat()
                    self._update_session(session_id, session)
                    print(f"[SessionService] Slurm job submitted for session {session_id}: {job_info['job_id']}")

                # Job 상태 모니터링
                self._monitor_job_for_session(session_id)

            except Exception as e:
                print(f"[SessionService] Error submitting job: {e}")
                session = self.get_session(session_id)
                if session:
                    session['status'] = 'error'
                    session['error'] = str(e)
                    session['updatedAt'] = datetime.now().isoformat()
                    self._update_session(session_id, session)

        # 백그라운드에서 Job 제출
        thread = threading.Thread(target=submit_job, daemon=True)
        thread.start()

    def _update_session(self, session_id: str, session: dict):
        """세션 업데이트 (내부 헬퍼)"""
        if self.session_manager:
            self.session_manager.update_session(session_id, session)
        else:
            self._sessions_memory[session_id] = session

    def _monitor_job_for_session(self, session_id: str):
        """Job 상태를 모니터링하여 세션 정보 업데이트"""
        import threading

        def monitor():
            # 최대 60초 동안 RUNNING 상태 대기
            for i in range(60):
                time.sleep(1)

                job_info = self.slurm_manager.get_job_status_info(session_id)
                if not job_info:
                    break

                session = self.get_session(session_id)
                if not session:
                    break

                if job_info['status'] == 'RUNNING':
                    node = job_info.get('node')
                    node_ip = job_info.get('node_ip', 'localhost')
                    vnc_port = job_info['vnc_port']

                    print(f"[SessionService] Session {session_id} is RUNNING on {node}({node_ip}):{vnc_port}")

                    # SSH 터널 생성
                    local_port = self.tunnel_manager.create_tunnel(
                        session_id=session_id,
                        remote_host=node,
                        remote_port=vnc_port
                    )

                    if local_port:
                        print(f"[SessionService] SSH tunnel created: localhost:{local_port} -> {node}:{vnc_port}")

                        # VNC 서버 준비 확인
                        import socket
                        vnc_ready = False
                        max_attempts = 30
                        for attempt in range(max_attempts):
                            try:
                                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                                sock.settimeout(1)
                                result = sock.connect_ex(('localhost', local_port))
                                sock.close()
                                if result == 0:
                                    print(f"[SessionService] VNC server ready at localhost:{local_port}")
                                    vnc_ready = True
                                    time.sleep(3)  # 완전 초기화 대기
                                    break
                            except Exception:
                                pass
                            time.sleep(1)

                        if vnc_ready:
                            # 세션 업데이트
                            session['status'] = 'running'
                            session['node'] = node
                            session['node_ip'] = node_ip
                            session['local_port'] = local_port
                            session['displayUrl'] = f'/vncproxy/{local_port}/vnc.html?autoconnect=true&resize=scale'
                            session['websocketUrl'] = f'/vncproxy/{local_port}/websockify'
                            session['updatedAt'] = datetime.now().isoformat()
                            self._update_session(session_id, session)
                        else:
                            print(f"[SessionService] VNC server not ready after {max_attempts} seconds")
                            session['status'] = 'error'
                            session['error'] = 'VNC server not responding'
                            session['updatedAt'] = datetime.now().isoformat()
                            self._update_session(session_id, session)
                    else:
                        print(f"[SessionService] Failed to create SSH tunnel")
                        session['status'] = 'error'
                        session['error'] = 'Failed to create SSH tunnel'
                        session['updatedAt'] = datetime.now().isoformat()
                        self._update_session(session_id, session)
                    break

                elif job_info['status'] in ['COMPLETED', 'FAILED', 'CANCELLED']:
                    session['status'] = 'stopped'
                    session['updatedAt'] = datetime.now().isoformat()
                    self._update_session(session_id, session)
                    break

        thread = threading.Thread(target=monitor, daemon=True)
        thread.start()

    def list_sessions(self) -> List[dict]:
        """모든 세션 목록 반환"""
        if self.session_manager:
            return self.session_manager.list_sessions()
        else:
            return list(self._sessions_memory.values())

    def get_session(self, session_id: str) -> Optional[dict]:
        """특정 세션 조회"""
        if self.session_manager:
            return self.session_manager.get_session(session_id)
        else:
            return self._sessions_memory.get(session_id)

    def delete_session(self, session_id: str) -> bool:
        """
        세션 삭제

        Returns:
            성공 여부
        """
        session = self.get_session(session_id)
        if not session:
            return False

        # SSH 터널 종료
        self.tunnel_manager.close_tunnel(session_id)

        # Slurm Job 취소
        self.slurm_manager.cancel_job(session_id)

        # Redis에서 세션 삭제
        if self.session_manager:
            self.session_manager.delete_session(session_id)
        else:
            if session_id in self._sessions_memory:
                del self._sessions_memory[session_id]

        return True

    def restart_session(self, session_id: str) -> Optional[dict]:
        """
        세션 재시작

        Returns:
            재시작된 세션 정보
        """
        session = self.get_session(session_id)
        if not session:
            return None

        # 기존 Job 취소
        self.slurm_manager.cancel_job(session_id)

        # 상태 업데이트
        session['status'] = 'creating'
        session['updatedAt'] = datetime.now().isoformat()
        self._update_session(session_id, session)

        # 새 Job 제출
        app_id = session['appId']
        vnc_port = session['vnc_port']
        self._start_real_session(session_id, app_id, vnc_port)

        return session

    def get_stats(self) -> dict:
        """세션 통계"""
        if self.session_manager:
            stats = self.session_manager.get_stats()
            stats['used_ports'] = len(self._get_used_ports())
            stats['available_ports'] = len(self.vnc_port_range) - stats['used_ports']
            return stats
        else:
            return {
                'service': 'app',
                'total_sessions': len(self._sessions_memory),
                'used_ports': len(self._get_used_ports()),
                'available_ports': len(self.vnc_port_range) - len(self._get_used_ports()),
                'redis_connected': False,
            }
