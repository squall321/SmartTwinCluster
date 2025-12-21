"""
Slurm Script Generator

템플릿과 설정을 기반으로 Slurm 배치 스크립트 생성
"""

import logging
from pathlib import Path
from typing import Dict, Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class ScriptGenerator:
    """Slurm 배치 스크립트 생성기"""

    def __init__(self):
        """초기화"""
        logger.info("ScriptGenerator initialized")

    def generate(
        self,
        template_obj,
        slurm_config: Dict,
        uploaded_files: Dict[str, Path],
        job_name: Optional[str] = None,
        apptainer_image_path: Optional[str] = None
    ) -> str:
        """
        Slurm 배치 스크립트 생성

        Args:
            template_obj: Template 객체
            slurm_config: Slurm 설정 딕셔너리 (TemplateEditorWidget.get_current_slurm_config())
            uploaded_files: {file_key: file_path} (FileUploadWidget.get_uploaded_files())
            job_name: Job 이름 (선택적)
            apptainer_image_path: Apptainer 이미지 경로 (선택적)

        Returns:
            Slurm 배치 스크립트 문자열
        """
        logger.info(f"Generating script for template: {template_obj.template.name}")

        # 1. Shebang
        script = "#!/bin/bash\n"

        # 2. SBATCH 헤더
        script += self._generate_sbatch_header(template_obj, slurm_config, job_name)

        # 3. 환경 변수 설정
        script += self._generate_environment_variables(
            template_obj, slurm_config, uploaded_files, apptainer_image_path
        )

        # 4. 작업 디렉토리 설정
        script += self._generate_directory_setup()

        # 5. 파일 복사
        script += self._generate_file_copy(uploaded_files)

        # 6. Template 스크립트 블록
        script += self._generate_script_blocks(template_obj)

        logger.debug(f"Generated script ({len(script)} bytes)")
        return script

    def _generate_sbatch_header(
        self,
        template_obj,
        slurm_config: Dict,
        job_name: Optional[str]
    ) -> str:
        """
        SBATCH 헤더 생성

        Args:
            template_obj: Template 객체
            slurm_config: Slurm 설정
            job_name: Job 이름

        Returns:
            SBATCH 헤더 문자열
        """
        header = "\n"
        header += "# =============================================================================\n"
        header += "# SBATCH Configuration\n"
        header += "# =============================================================================\n\n"

        # Job name
        if not job_name:
            job_name = template_obj.template.name.replace(' ', '_')
        header += f"#SBATCH --job-name={job_name}\n"

        # Partition
        header += f"#SBATCH --partition={slurm_config['partition']}\n"

        # Nodes
        header += f"#SBATCH --nodes={slurm_config['nodes']}\n"

        # Tasks
        header += f"#SBATCH --ntasks={slurm_config['ntasks']}\n"

        # CPUs per task (optional)
        if 'cpus_per_task' in slurm_config and slurm_config['cpus_per_task']:
            header += f"#SBATCH --cpus-per-task={slurm_config['cpus_per_task']}\n"

        # Memory
        header += f"#SBATCH --mem={slurm_config['mem']}\n"

        # Time limit
        header += f"#SBATCH --time={slurm_config['time']}\n"

        # GPUs (optional)
        if slurm_config.get('gpus'):
            header += f"#SBATCH --gpus={slurm_config['gpus']}\n"

        # Output/Error logs
        header += "#SBATCH --output=/shared/logs/%j.out\n"
        header += "#SBATCH --error=/shared/logs/%j.err\n\n"

        return header

    def _generate_environment_variables(
        self,
        template_obj,
        slurm_config: Dict,
        uploaded_files: Dict[str, Path],
        apptainer_image_path: Optional[str]
    ) -> str:
        """
        환경 변수 설정 생성

        Args:
            template_obj: Template 객체
            slurm_config: Slurm 설정
            uploaded_files: 업로드된 파일 딕셔너리
            apptainer_image_path: Apptainer 이미지 경로

        Returns:
            환경 변수 설정 문자열
        """
        env = ""
        env += "# =============================================================================\n"
        env += "# Environment Variables\n"
        env += "# =============================================================================\n\n"

        # Slurm 설정 변수
        env += "# --- Slurm Configuration Variables ---\n"
        env += f"export JOB_PARTITION=\"{slurm_config['partition']}\"\n"
        env += f"export JOB_NODES={slurm_config['nodes']}\n"
        env += f"export JOB_NTASKS={slurm_config['ntasks']}\n"
        env += f"export JOB_CPUS_PER_TASK={slurm_config.get('cpus_per_task', 1)}\n"
        env += f"export JOB_MEMORY=\"{slurm_config['mem']}\"\n"
        env += f"export JOB_TIME=\"{slurm_config['time']}\"\n"

        if slurm_config.get('gpus'):
            env += f"export JOB_GPUS={slurm_config['gpus']}\n"

        env += "\n"

        # Apptainer 이미지
        if apptainer_image_path:
            env += "# --- Apptainer Image ---\n"
            env += f"export APPTAINER_IMAGE=\"{apptainer_image_path}\"\n\n"
        elif template_obj.apptainer:
            # Template에 이미지 이름이 있으면 사용
            env += "# --- Apptainer Image ---\n"
            env += f"export APPTAINER_IMAGE=\"/opt/apptainers/{template_obj.apptainer.image_name}\"\n\n"

        # 작업 디렉토리
        env += "# --- Work Directories ---\n"
        env += "export SLURM_SUBMIT_DIR=/shared/jobs/$SLURM_JOB_ID\n"
        env += "export WORK_DIR=\"$SLURM_SUBMIT_DIR\"\n"
        env += "export RESULT_DIR=\"$WORK_DIR/results\"\n\n"

        # Template의 Apptainer 환경 변수
        if template_obj.apptainer and template_obj.apptainer.env:
            env += "# --- Apptainer Environment Variables ---\n"
            for key, value in template_obj.apptainer.env.items():
                env += f"export {key}=\"{value}\"\n"
            env += "\n"

        # 업로드된 파일 환경 변수
        if uploaded_files:
            env += "# --- Uploaded File Paths ---\n"
            for file_key, file_path in uploaded_files.items():
                var_name = f"FILE_{file_key.upper()}"
                filename = Path(file_path).name
                env += f"export {var_name}=\"$SLURM_SUBMIT_DIR/input/{filename}\"\n"
            env += "\n"

        env += "# =============================================================================\n\n"

        return env

    def _generate_directory_setup(self) -> str:
        """
        작업 디렉토리 설정 생성

        Returns:
            디렉토리 설정 문자열
        """
        setup = "# =============================================================================\n"
        setup += "# Directory Setup\n"
        setup += "# =============================================================================\n\n"

        setup += "# Create directories\n"
        setup += "mkdir -p $SLURM_SUBMIT_DIR/input\n"
        setup += "mkdir -p $SLURM_SUBMIT_DIR/work\n"
        setup += "mkdir -p $SLURM_SUBMIT_DIR/output\n"
        setup += "mkdir -p $RESULT_DIR\n\n"

        setup += "# Change to work directory\n"
        setup += "cd $SLURM_SUBMIT_DIR\n\n"

        return setup

    def _generate_file_copy(self, uploaded_files: Dict[str, Path]) -> str:
        """
        파일 복사 명령 생성

        Args:
            uploaded_files: 업로드된 파일 딕셔너리

        Returns:
            파일 복사 명령 문자열
        """
        if not uploaded_files:
            return ""

        copy = "# =============================================================================\n"
        copy += "# Copy Input Files\n"
        copy += "# =============================================================================\n\n"

        for file_key, file_path in uploaded_files.items():
            filename = Path(file_path).name
            src = str(file_path)
            dst = f"$SLURM_SUBMIT_DIR/input/{filename}"
            copy += f"echo \"Copying {filename}...\"\n"
            copy += f"cp \"{src}\" \"{dst}\"\n"

        copy += "\n"

        return copy

    def _generate_script_blocks(self, template_obj) -> str:
        """
        Template 스크립트 블록 삽입

        Args:
            template_obj: Template 객체

        Returns:
            스크립트 블록 문자열
        """
        blocks = "# =============================================================================\n"
        blocks += "# Execution Scripts\n"
        blocks += "# =============================================================================\n\n"

        # Pre-execution
        if template_obj.script.pre_exec:
            blocks += "# --- Pre-Execution ---\n"
            blocks += template_obj.script.pre_exec
            if not template_obj.script.pre_exec.endswith('\n'):
                blocks += "\n"
            blocks += "\n"

        # Main execution
        if template_obj.script.main_exec:
            blocks += "# --- Main Execution ---\n"
            blocks += template_obj.script.main_exec
            if not template_obj.script.main_exec.endswith('\n'):
                blocks += "\n"
            blocks += "\n"

        # Post-execution
        if template_obj.script.post_exec:
            blocks += "# --- Post-Execution ---\n"
            blocks += template_obj.script.post_exec
            if not template_obj.script.post_exec.endswith('\n'):
                blocks += "\n"
            blocks += "\n"

        blocks += "# =============================================================================\n"
        blocks += "# End of Script\n"
        blocks += "# =============================================================================\n"

        return blocks

    def save_script(self, script: str, output_path: Path) -> Path:
        """
        스크립트를 파일로 저장

        Args:
            script: 스크립트 내용
            output_path: 저장할 파일 경로

        Returns:
            저장된 파일 경로
        """
        try:
            output_path.parent.mkdir(parents=True, exist_ok=True)

            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(script)

            # 실행 권한 부여
            output_path.chmod(0o755)

            logger.info(f"Script saved: {output_path}")
            return output_path

        except Exception as e:
            logger.error(f"Failed to save script to {output_path}: {e}")
            raise

    def generate_job_metadata(
        self,
        template_obj,
        slurm_config: Dict,
        uploaded_files: Dict[str, Path],
        job_name: Optional[str] = None
    ) -> Dict:
        """
        Job 메타데이터 생성 (DB 저장용)

        Args:
            template_obj: Template 객체
            slurm_config: Slurm 설정
            uploaded_files: 업로드된 파일
            job_name: Job 이름

        Returns:
            메타데이터 딕셔너리
        """
        return {
            'template_id': template_obj.template.id,
            'template_name': template_obj.template.name,
            'template_version': template_obj.template.version,
            'job_name': job_name or template_obj.template.name,
            'slurm_config': slurm_config,
            'uploaded_files': {
                k: str(v) for k, v in uploaded_files.items()
            },
            'created_at': datetime.now().isoformat(),
        }
