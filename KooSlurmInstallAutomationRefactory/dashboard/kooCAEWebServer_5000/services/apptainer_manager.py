"""
Apptainer Manager
Apptainer 컨테이너 실행 및 관리
"""

import subprocess
import os
import signal
from typing import Optional, Dict
import time


class ApptainerManager:
    """Apptainer 컨테이너 관리"""

    def __init__(self):
        # Apptainer 이미지 디렉토리
        self.image_dir = "/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/apptainer/app"

        # 실행 중인 컨테이너 추적
        self.running_containers: Dict[str, dict] = {}

    def get_image_path(self, app_id: str) -> str:
        """앱 ID로 SIF 이미지 경로 반환"""
        return os.path.join(self.image_dir, app_id, f"{app_id}.sif")

    def start_container(
        self,
        session_id: str,
        app_id: str,
        vnc_port: int,
        websocket_port: int
    ) -> Optional[dict]:
        """
        Apptainer 컨테이너 시작

        Args:
            session_id: 세션 ID
            app_id: 앱 ID (예: 'gedit')
            vnc_port: VNC 포트 (예: 5901)
            websocket_port: WebSocket 포트 (예: 6080)

        Returns:
            컨테이너 정보
        """
        image_path = self.get_image_path(app_id)

        # 이미지 파일 존재 확인
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Apptainer image not found: {image_path}")

        # 환경 변수 설정
        env = os.environ.copy()
        env['VNC_PORT'] = str(vnc_port)
        env['WEBSOCKIFY_PORT'] = str(websocket_port)
        env['VNC_RESOLUTION'] = '1280x720'
        env['DISPLAY'] = ':1'

        # Apptainer 실행 명령
        cmd = [
            'apptainer', 'run',
            '--cleanenv',  # 깨끗한 환경
            '--env', f'VNC_PORT={vnc_port}',
            '--env', f'WEBSOCKIFY_PORT={websocket_port}',
            '--env', 'VNC_RESOLUTION=1280x720',
            '--env', 'DISPLAY=:1',
            image_path
        ]

        print(f"[ApptainerManager] Starting container for {app_id}")
        print(f"[ApptainerManager] Command: {' '.join(cmd)}")

        # 백그라운드에서 실행
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            preexec_fn=os.setsid  # 새 프로세스 그룹 생성
        )

        # 컨테이너 정보 저장
        container_info = {
            'session_id': session_id,
            'app_id': app_id,
            'pid': process.pid,
            'vnc_port': vnc_port,
            'websocket_port': websocket_port,
            'image_path': image_path,
            'process': process,
            'started_at': time.time()
        }

        self.running_containers[session_id] = container_info

        print(f"[ApptainerManager] Container started with PID: {process.pid}")
        print(f"[ApptainerManager] VNC Port: {vnc_port}")
        print(f"[ApptainerManager] WebSocket Port: {websocket_port}")

        return container_info

    def stop_container(self, session_id: str) -> bool:
        """
        컨테이너 중지

        Args:
            session_id: 세션 ID

        Returns:
            성공 여부
        """
        container = self.running_containers.get(session_id)
        if not container:
            return False

        try:
            process = container['process']
            pid = container['pid']

            print(f"[ApptainerManager] Stopping container (Session: {session_id}, PID: {pid})")

            # 프로세스 그룹 전체 종료 (자식 프로세스 포함)
            try:
                os.killpg(os.getpgid(pid), signal.SIGTERM)
                time.sleep(2)  # 정상 종료 대기

                # 아직 살아있으면 강제 종료
                if process.poll() is None:
                    os.killpg(os.getpgid(pid), signal.SIGKILL)

            except ProcessLookupError:
                print(f"[ApptainerManager] Process {pid} already terminated")

            # 컨테이너 목록에서 제거
            del self.running_containers[session_id]

            print(f"[ApptainerManager] Container stopped successfully")
            return True

        except Exception as e:
            print(f"[ApptainerManager] Error stopping container: {e}")
            return False

    def get_container_status(self, session_id: str) -> Optional[dict]:
        """컨테이너 상태 조회"""
        container = self.running_containers.get(session_id)
        if not container:
            return None

        process = container['process']

        # 프로세스 상태 확인
        poll_result = process.poll()

        return {
            'session_id': session_id,
            'app_id': container['app_id'],
            'pid': container['pid'],
            'running': poll_result is None,
            'vnc_port': container['vnc_port'],
            'websocket_port': container['websocket_port'],
            'uptime': time.time() - container['started_at']
        }

    def list_running_containers(self) -> list:
        """실행 중인 모든 컨테이너 목록"""
        return [
            self.get_container_status(session_id)
            for session_id in self.running_containers.keys()
        ]
