"""
Job Submitter - Slurm Job 제출

sbatch 명령 실행 및 Job ID 추출
"""

import logging
import subprocess
import re
import tempfile
from pathlib import Path
from typing import Optional, Tuple, Dict

logger = logging.getLogger(__name__)


class JobSubmitter:
    """Slurm Job 제출기"""

    def __init__(self):
        """초기화"""
        logger.info("JobSubmitter initialized")

    def submit_job(
        self,
        script_content: str,
        dry_run: bool = False
    ) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        Slurm Job 제출

        Args:
            script_content: 스크립트 내용
            dry_run: 테스트 모드 (실제 제출 안함)

        Returns:
            (성공여부, Job ID 또는 None, 에러 메시지 또는 None)
        """
        logger.info(f"Submitting job (dry_run={dry_run})")

        try:
            # 1. 임시 스크립트 파일 생성
            script_path = self._create_temp_script(script_content)
            logger.debug(f"Temporary script created: {script_path}")

            if dry_run:
                # Dry run 모드: sbatch --test-only
                return self._dry_run_submit(script_path)
            else:
                # 실제 제출
                return self._real_submit(script_path)

        except Exception as e:
            logger.error(f"Job submission failed: {e}", exc_info=True)
            return False, None, f"Submission error: {str(e)}"

    def _create_temp_script(self, script_content: str) -> Path:
        """
        임시 스크립트 파일 생성

        Args:
            script_content: 스크립트 내용

        Returns:
            임시 파일 경로
        """
        # 임시 파일 생성
        temp_fd, temp_path = tempfile.mkstemp(suffix='.sh', prefix='slurm_job_')

        try:
            with open(temp_path, 'w', encoding='utf-8') as f:
                f.write(script_content)

            # 실행 권한 부여
            Path(temp_path).chmod(0o755)

            return Path(temp_path)

        except Exception as e:
            # 에러 발생 시 임시 파일 삭제
            try:
                Path(temp_path).unlink()
            except:
                pass
            raise e

    def _dry_run_submit(self, script_path: Path) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        Dry run 제출 (테스트 모드)

        Args:
            script_path: 스크립트 경로

        Returns:
            (성공여부, None, 에러 메시지 또는 None)
        """
        try:
            # sbatch --test-only 실행
            result = subprocess.run(
                ['sbatch', '--test-only', str(script_path)],
                capture_output=True,
                text=True,
                timeout=10
            )

            # 임시 파일 삭제
            script_path.unlink()

            if result.returncode == 0:
                logger.info("Dry run successful")
                return True, None, None
            else:
                error_msg = result.stderr.strip() or result.stdout.strip()
                logger.warning(f"Dry run validation failed: {error_msg}")
                return False, None, error_msg

        except subprocess.TimeoutExpired:
            logger.error("sbatch --test-only timeout")
            return False, None, "Validation timeout (sbatch not responding)"

        except FileNotFoundError:
            logger.error("sbatch command not found")
            return False, None, "sbatch command not found (Slurm not installed?)"

        except Exception as e:
            logger.error(f"Dry run failed: {e}")
            return False, None, f"Validation error: {str(e)}"

    def _real_submit(self, script_path: Path) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        실제 Job 제출

        Args:
            script_path: 스크립트 경로

        Returns:
            (성공여부, Job ID, 에러 메시지 또는 None)
        """
        try:
            # sbatch 실행
            result = subprocess.run(
                ['sbatch', str(script_path)],
                capture_output=True,
                text=True,
                timeout=30
            )

            # 임시 파일 삭제
            script_path.unlink()

            if result.returncode == 0:
                # Job ID 추출
                job_id = self._extract_job_id(result.stdout)

                if job_id:
                    logger.info(f"Job submitted successfully: {job_id}")
                    return True, job_id, None
                else:
                    logger.warning("Job submitted but failed to extract Job ID")
                    return True, None, "Job ID extraction failed"
            else:
                error_msg = result.stderr.strip() or result.stdout.strip()
                logger.error(f"sbatch failed: {error_msg}")
                return False, None, error_msg

        except subprocess.TimeoutExpired:
            logger.error("sbatch timeout")
            return False, None, "Submission timeout (sbatch not responding)"

        except FileNotFoundError:
            logger.error("sbatch command not found")
            return False, None, "sbatch command not found (Slurm not installed?)"

        except Exception as e:
            logger.error(f"Job submission failed: {e}")
            return False, None, f"Submission error: {str(e)}"

    def _extract_job_id(self, sbatch_output: str) -> Optional[str]:
        """
        sbatch 출력에서 Job ID 추출

        Args:
            sbatch_output: sbatch 명령 출력

        Returns:
            Job ID 또는 None

        Examples:
            "Submitted batch job 12345" -> "12345"
            "Submitted batch job 67890 on cluster main" -> "67890"
        """
        # 패턴: "Submitted batch job <job_id>"
        match = re.search(r'Submitted batch job (\d+)', sbatch_output)

        if match:
            job_id = match.group(1)
            logger.debug(f"Extracted Job ID: {job_id}")
            return job_id
        else:
            logger.warning(f"Failed to extract Job ID from: {sbatch_output}")
            return None

    def check_slurm_available(self) -> Tuple[bool, Optional[str]]:
        """
        Slurm 사용 가능 여부 확인

        Returns:
            (사용 가능 여부, 에러 메시지 또는 None)
        """
        try:
            result = subprocess.run(
                ['sinfo', '--version'],
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode == 0:
                version = result.stdout.strip()
                logger.info(f"Slurm available: {version}")
                return True, None
            else:
                return False, "Slurm commands not responding"

        except FileNotFoundError:
            logger.warning("Slurm not found")
            return False, "Slurm not installed (sinfo command not found)"

        except subprocess.TimeoutExpired:
            return False, "Slurm commands timeout"

        except Exception as e:
            logger.error(f"Slurm check failed: {e}")
            return False, f"Slurm check error: {str(e)}"

    def get_job_info(self, job_id: str) -> Optional[Dict]:
        """
        Job 정보 조회

        Args:
            job_id: Job ID

        Returns:
            Job 정보 딕셔너리 또는 None
        """
        try:
            result = subprocess.run(
                ['scontrol', 'show', 'job', job_id],
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode == 0:
                # 간단한 파싱 (실제로는 더 정교하게)
                output = result.stdout
                info = {
                    'job_id': job_id,
                    'raw_output': output
                }

                # JobState 추출
                state_match = re.search(r'JobState=(\w+)', output)
                if state_match:
                    info['state'] = state_match.group(1)

                logger.debug(f"Job info retrieved: {job_id}")
                return info
            else:
                logger.warning(f"Failed to get job info: {job_id}")
                return None

        except Exception as e:
            logger.error(f"Failed to get job info: {e}")
            return None
