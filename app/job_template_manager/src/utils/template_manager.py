"""
Template Manager - 템플릿 생성/수정/삭제 관리

YAML 파일 기반 템플릿 관리 시스템
"""

import logging
import shutil
from pathlib import Path
from typing import Optional, List
from datetime import datetime

import yaml

from models.template import Template

logger = logging.getLogger(__name__)


class TemplateManager:
    """템플릿 관리자"""

    def __init__(self, base_path: Optional[Path] = None):
        """
        초기화

        Args:
            base_path: 템플릿 기본 경로 (기본값: src/resources/templates)
        """
        if base_path is None:
            # 기본 경로: src/resources/templates
            current_file = Path(__file__)
            self.base_path = current_file.parent.parent / 'resources' / 'templates'
        else:
            self.base_path = Path(base_path)

        # 템플릿 디렉토리 생성
        self.base_path.mkdir(parents=True, exist_ok=True)

        logger.info(f"TemplateManager initialized with base_path: {self.base_path}")

    def save_template(
        self,
        template: Template,
        overwrite: bool = False
    ) -> tuple[bool, Optional[str], Optional[Path]]:
        """
        템플릿 저장

        Args:
            template: 저장할 템플릿
            overwrite: 기존 파일 덮어쓰기 허용 여부

        Returns:
            (성공여부, 에러 메시지 또는 None, 저장된 파일 경로 또는 None)
        """
        try:
            # 카테고리별 디렉토리
            category_dir = self.base_path / template.template.category
            category_dir.mkdir(parents=True, exist_ok=True)

            # 파일 경로
            file_name = f"{template.template.id}.yaml"
            file_path = category_dir / file_name

            # 파일 존재 확인
            if file_path.exists() and not overwrite:
                logger.warning(f"Template already exists: {file_path}")
                return False, f"Template '{template.template.id}' already exists. Use overwrite=True to replace.", None

            # Template -> dict 변환
            template_dict = template.to_dict()

            # YAML 파일 저장
            with open(file_path, 'w', encoding='utf-8') as f:
                yaml.dump(template_dict, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

            logger.info(f"Template saved: {file_path}")
            return True, None, file_path

        except Exception as e:
            logger.error(f"Failed to save template: {e}", exc_info=True)
            return False, f"Save error: {str(e)}", None

    def update_template(
        self,
        template: Template
    ) -> tuple[bool, Optional[str]]:
        """
        기존 템플릿 업데이트

        Args:
            template: 업데이트할 템플릿

        Returns:
            (성공여부, 에러 메시지 또는 None)
        """
        try:
            # 기존 템플릿 파일 찾기
            existing_path = self.find_template_file(template.template.id)

            if not existing_path:
                logger.warning(f"Template not found: {template.template.id}")
                return False, f"Template '{template.template.id}' not found"

            # updated_at 갱신
            if template.template.updated_at is None:
                template.template.updated_at = datetime.now().isoformat()

            # 덮어쓰기
            success, error, _ = self.save_template(template, overwrite=True)

            if success:
                logger.info(f"Template updated: {existing_path}")
                return True, None
            else:
                return False, error

        except Exception as e:
            logger.error(f"Failed to update template: {e}", exc_info=True)
            return False, f"Update error: {str(e)}"

    def delete_template(
        self,
        template_id: str,
        permanent: bool = False
    ) -> tuple[bool, Optional[str]]:
        """
        템플릿 삭제

        Args:
            template_id: 삭제할 템플릿 ID
            permanent: 영구 삭제 여부 (False면 archived/ 폴더로 이동)

        Returns:
            (성공여부, 에러 메시지 또는 None)
        """
        try:
            # 템플릿 파일 찾기
            template_path = self.find_template_file(template_id)

            if not template_path:
                logger.warning(f"Template not found: {template_id}")
                return False, f"Template '{template_id}' not found"

            if permanent:
                # 영구 삭제
                template_path.unlink()
                logger.info(f"Template permanently deleted: {template_path}")
            else:
                # 아카이브로 이동
                archive_dir = self.base_path / 'archived'
                archive_dir.mkdir(parents=True, exist_ok=True)

                archive_path = archive_dir / template_path.name
                shutil.move(str(template_path), str(archive_path))
                logger.info(f"Template archived: {template_path} -> {archive_path}")

            return True, None

        except Exception as e:
            logger.error(f"Failed to delete template: {e}", exc_info=True)
            return False, f"Delete error: {str(e)}"

    def duplicate_template(
        self,
        template_id: str,
        new_id: str,
        new_name: Optional[str] = None
    ) -> tuple[bool, Optional[str], Optional[Template]]:
        """
        템플릿 복제

        Args:
            template_id: 복제할 템플릿 ID
            new_id: 새 템플릿 ID
            new_name: 새 템플릿 이름 (None이면 "Copy of {원본 이름}")

        Returns:
            (성공여부, 에러 메시지 또는 None, 복제된 템플릿 또는 None)
        """
        try:
            # 원본 템플릿 로드
            from utils.yaml_loader import YAMLLoader

            loader = YAMLLoader(base_path=self.base_path)
            templates = loader.scan_templates()

            original = None
            for t in templates:
                if t.template.id == template_id:
                    original = t
                    break

            if not original:
                return False, f"Template '{template_id}' not found", None

            # 복제본 생성
            duplicate = Template(
                template=original.template,
                slurm=original.slurm,
                script=original.script,
                apptainer=original.apptainer,
                files=original.files
            )

            # ID와 이름 변경
            duplicate.template.id = new_id
            duplicate.template.name = new_name or f"Copy of {original.template.name}"
            duplicate.template.created_at = datetime.now().isoformat()
            duplicate.template.updated_at = datetime.now().isoformat()

            # 저장
            success, error, _ = self.save_template(duplicate, overwrite=False)

            if success:
                logger.info(f"Template duplicated: {template_id} -> {new_id}")
                return True, None, duplicate
            else:
                return False, error, None

        except Exception as e:
            logger.error(f"Failed to duplicate template: {e}", exc_info=True)
            return False, f"Duplicate error: {str(e)}", None

    def export_template(
        self,
        template_id: str,
        export_path: Path
    ) -> tuple[bool, Optional[str]]:
        """
        템플릿 내보내기

        Args:
            template_id: 내보낼 템플릿 ID
            export_path: 내보낼 파일 경로

        Returns:
            (성공여부, 에러 메시지 또는 None)
        """
        try:
            # 템플릿 파일 찾기
            template_path = self.find_template_file(template_id)

            if not template_path:
                return False, f"Template '{template_id}' not found"

            # 파일 복사
            shutil.copy2(str(template_path), str(export_path))

            logger.info(f"Template exported: {template_path} -> {export_path}")
            return True, None

        except Exception as e:
            logger.error(f"Failed to export template: {e}", exc_info=True)
            return False, f"Export error: {str(e)}"

    def import_template(
        self,
        import_path: Path,
        overwrite: bool = False
    ) -> tuple[bool, Optional[str], Optional[Template]]:
        """
        템플릿 가져오기

        Args:
            import_path: 가져올 YAML 파일 경로
            overwrite: 기존 템플릿 덮어쓰기 허용 여부

        Returns:
            (성공여부, 에러 메시지 또는 None, 가져온 템플릿 또는 None)
        """
        try:
            # YAML 파일 로드
            from utils.yaml_loader import YAMLLoader

            loader = YAMLLoader()
            template = loader.load_template_from_file(import_path)

            if not template:
                return False, "Failed to load template from file", None

            # 검증
            validation_ok, validation_error = self.validate_template(template)
            if not validation_ok:
                return False, f"Template validation failed: {validation_error}", None

            # 저장
            success, error, _ = self.save_template(template, overwrite=overwrite)

            if success:
                logger.info(f"Template imported: {import_path}")
                return True, None, template
            else:
                return False, error, None

        except Exception as e:
            logger.error(f"Failed to import template: {e}", exc_info=True)
            return False, f"Import error: {str(e)}", None

    def validate_template(self, template: Template) -> tuple[bool, Optional[str]]:
        """
        템플릿 검증

        Args:
            template: 검증할 템플릿

        Returns:
            (유효 여부, 에러 메시지 또는 None)
        """
        errors = []

        # 필수 필드 검증
        if not template.template.id:
            errors.append("Template ID is required")

        if not template.template.name:
            errors.append("Template name is required")

        if not template.template.category:
            errors.append("Template category is required")

        # Slurm 설정 검증
        if not template.slurm.partition:
            errors.append("Slurm partition is required")

        if template.slurm.nodes < 1:
            errors.append("Slurm nodes must be >= 1")

        if template.slurm.ntasks < 1:
            errors.append("Slurm ntasks must be >= 1")

        if not template.slurm.mem:
            errors.append("Slurm memory is required")

        if not template.slurm.time:
            errors.append("Slurm time is required")

        # Script 검증
        if not template.script.main_exec:
            errors.append("Main execution script is required")

        # Apptainer 검증
        if template.apptainer:
            if not template.apptainer.image_name:
                errors.append("Apptainer image name is required when Apptainer is enabled")

        if errors:
            error_msg = "; ".join(errors)
            logger.warning(f"Template validation failed: {error_msg}")
            return False, error_msg
        else:
            return True, None

    def find_template_file(self, template_id: str) -> Optional[Path]:
        """
        템플릿 ID로 YAML 파일 찾기

        Args:
            template_id: 템플릿 ID

        Returns:
            파일 경로 또는 None
        """
        # 모든 하위 디렉토리에서 검색
        for yaml_file in self.base_path.rglob(f"{template_id}.yaml"):
            return yaml_file

        return None

    def list_templates(self, category: Optional[str] = None) -> List[Template]:
        """
        템플릿 목록 조회

        Args:
            category: 카테고리 필터 (None이면 전체)

        Returns:
            템플릿 목록
        """
        from utils.yaml_loader import YAMLLoader

        loader = YAMLLoader(base_path=self.base_path)
        templates = loader.scan_templates(category=category)

        return templates

    def get_template_count(self) -> dict:
        """
        카테고리별 템플릿 개수 조회

        Returns:
            카테고리별 개수 딕셔너리
        """
        templates = self.list_templates()

        counts = {}
        for template in templates:
            category = template.template.category
            counts[category] = counts.get(category, 0) + 1

        return counts
