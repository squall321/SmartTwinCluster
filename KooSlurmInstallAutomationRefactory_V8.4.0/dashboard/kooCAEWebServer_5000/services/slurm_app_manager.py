"""
Slurm App Manager
Slurm을 통해 가시화 노드에서 앱 컨테이너를 실행
"""

import subprocess
import os
import time
import re
from typing import Optional, Dict


class SlurmAppManager:
    """Slurm 기반 앱 관리"""

    def __init__(self):
        # Job 스크립트 디렉토리
        self.job_template_dir = "/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/slurm_jobs"

        # 실행 중인 Job 추적
        self.running_jobs: Dict[str, dict] = {}

    def submit_app_job(
        self,
        session_id: str,
        app_id: str,
        vnc_port: int
    ) -> Optional[dict]:
        """
        Slurm Job 제출

        Args:
            session_id: 세션 ID
            app_id: 앱 ID (예: 'gedit')
            vnc_port: WebSocket 포트

        Returns:
            Job 정보
        """
        # Job 스크립트 경로
        job_script = os.path.join(self.job_template_dir, f"{app_id}_vnc_job.sh")

        if not os.path.exists(job_script):
            raise FileNotFoundError(f"Job script not found: {job_script}")

        print(f"[SlurmAppManager] Submitting job for {app_id}")
        print(f"[SlurmAppManager] Job script: {job_script}")

        # 환경 변수 설정
        env = os.environ.copy()
        env['SESSION_ID'] = session_id
        env['VNC_PORT'] = str(vnc_port)

        # sbatch 명령
        cmd = [
            'sbatch',
            '--export', f'SESSION_ID={session_id},VNC_PORT={vnc_port}',
            job_script
        ]

        try:
            # Job 제출
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True
            )

            # Job ID 추출
            # 출력 예: "Submitted batch job 12345"
            match = re.search(r'Submitted batch job (\d+)', result.stdout)
            if not match:
                raise Exception(f"Could not parse job ID from: {result.stdout}")

            job_id = match.group(1)

            print(f"[SlurmAppManager] Job submitted: {job_id}")

            # Job 정보 저장
            job_info = {
                'session_id': session_id,
                'app_id': app_id,
                'job_id': job_id,
                'vnc_port': vnc_port,
                'status': 'PENDING',
                'submitted_at': time.time(),
                'node': None,  # Job이 실행되면 업데이트
                'node_ip': None
            }

            self.running_jobs[session_id] = job_info

            # Job 상태 모니터링 시작 (백그라운드)
            self._start_job_monitoring(session_id)

            return job_info

        except subprocess.CalledProcessError as e:
            print(f"[SlurmAppManager] Error submitting job: {e}")
            print(f"[SlurmAppManager] stdout: {e.stdout}")
            print(f"[SlurmAppManager] stderr: {e.stderr}")
            raise

    def _start_job_monitoring(self, session_id: str):
        """Job 상태 모니터링 (백그라운드)"""
        import threading

        def monitor():
            job_info = self.running_jobs.get(session_id)
            if not job_info:
                return

            job_id = job_info['job_id']

            # 최대 60초 동안 RUNNING 상태 대기
            for i in range(60):
                time.sleep(1)

                # Job 상태 확인
                status = self._get_job_status(job_id)

                if status == 'RUNNING':
                    # Job 정보 파일에서 노드 정보 읽기
                    node_info = self._read_job_info(session_id)
                    if node_info:
                        job_info.update(node_info)
                        job_info['status'] = 'RUNNING'
                        print(f"[SlurmAppManager] Job {job_id} is RUNNING on {node_info.get('node')}")
                    break
                elif status in ['COMPLETED', 'FAILED', 'CANCELLED']:
                    job_info['status'] = status
                    print(f"[SlurmAppManager] Job {job_id} ended with status: {status}")
                    break

        thread = threading.Thread(target=monitor, daemon=True)
        thread.start()

    def _get_job_status(self, job_id: str) -> str:
        """Job 상태 조회"""
        try:
            result = subprocess.run(
                ['scontrol', 'show', 'job', job_id],
                capture_output=True,
                text=True,
                timeout=5
            )

            # JobState 추출
            match = re.search(r'JobState=(\w+)', result.stdout)
            if match:
                return match.group(1)

        except Exception as e:
            print(f"[SlurmAppManager] Error checking job status: {e}")

        return 'UNKNOWN'

    def _read_job_info(self, session_id: str) -> Optional[dict]:
        """Job 정보 파일 읽기 (/tmp/app_session_{session_id}.info)"""
        info_file = f"/tmp/app_session_{session_id}.info"

        # 가시화 노드에 있으므로 직접 읽을 수 없음
        # scontrol을 통해 노드 정보를 가져옴
        job_info = self.running_jobs.get(session_id)
        if not job_info:
            return None

        job_id = job_info['job_id']

        try:
            result = subprocess.run(
                ['scontrol', 'show', 'job', job_id],
                capture_output=True,
                text=True,
                timeout=5
            )

            # NodeList 추출 (ReqNodeList, ExcNodeList 제외하고 실제 NodeList만)
            match = re.search(r'^\s+NodeList=(\S+)', result.stdout, re.MULTILINE)
            if match:
                node = match.group(1)
                if node != '(null)':  # (null)이 아닌 경우만
                    # 노드 IP는 my_cluster.yaml에서 가져오거나 DNS 조회
                    # 간단하게 노드 이름을 그대로 사용
                    return {
                        'node': node,
                        'node_ip': self._get_node_ip(node)
                    }

        except Exception as e:
            print(f"[SlurmAppManager] Error reading job info: {e}")

        return None

    def _get_node_ip(self, node_name: str) -> str:
        """노드 이름으로 IP 조회"""
        # 하드코딩된 매핑 (추후 my_cluster.yaml에서 읽기)
        node_mapping = {
            'viz-node001': '192.168.122.252',
        }
        return node_mapping.get(node_name, node_name)

    def cancel_job(self, session_id: str) -> bool:
        """Job 취소"""
        job_info = self.running_jobs.get(session_id)
        if not job_info:
            return False

        job_id = job_info['job_id']

        try:
            print(f"[SlurmAppManager] Cancelling job {job_id}")
            subprocess.run(
                ['scancel', job_id],
                check=True,
                timeout=10
            )

            job_info['status'] = 'CANCELLED'
            del self.running_jobs[session_id]

            print(f"[SlurmAppManager] Job {job_id} cancelled successfully")
            return True

        except Exception as e:
            print(f"[SlurmAppManager] Error cancelling job: {e}")
            return False

    def get_job_status_info(self, session_id: str) -> Optional[dict]:
        """Job 상태 정보 조회"""
        return self.running_jobs.get(session_id)

    def list_running_jobs(self) -> list:
        """실행 중인 모든 Job 목록"""
        return list(self.running_jobs.values())
