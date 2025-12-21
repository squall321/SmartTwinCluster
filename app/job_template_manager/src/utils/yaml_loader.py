"""
YAML Template Loader

템플릿 YAML 파일을 로드하고 저장하는 유틸리티
"""

import logging
from pathlib import Path
from typing import List, Optional, Dict
import yaml

from models.template import Template

logger = logging.getLogger(__name__)


class YAMLLoader:
    """YAML 템플릿 로더"""

    def __init__(self, base_path: Optional[str] = None):
        """
        Args:
            base_path: 템플릿 디렉토리 경로 (기본: src/resources/templates)
        """
        if base_path:
            self.base_path = Path(base_path)
        else:
            # 현재 파일 기준으로 resources/templates 경로 찾기
            current_file = Path(__file__)
            src_dir = current_file.parent.parent  # src/
            self.base_path = src_dir / 'resources' / 'templates'

        logger.info(f"YAMLLoader initialized with base_path: {self.base_path}")

    def load_template(self, template_id: str) -> Optional[Template]:
        """
        템플릿 ID로 템플릿 로드

        Args:
            template_id: 템플릿 ID

        Returns:
            Template 객체 또는 None
        """
        # 전체 템플릿 스캔
        templates = self.scan_templates()

        for template in templates:
            if template.template.id == template_id:
                return template

        logger.warning(f"Template not found: {template_id}")
        return None

    def load_template_from_file(self, file_path: Path) -> Optional[Template]:
        """
        파일 경로에서 템플릿 로드

        Args:
            file_path: YAML 파일 경로

        Returns:
            Template 객체 또는 None
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)

            template = Template.from_dict(data, file_path=file_path)
            logger.debug(f"Loaded template: {template.template.name} from {file_path}")
            return template

        except Exception as e:
            logger.error(f"Failed to load template from {file_path}: {e}")
            return None

    def scan_templates(self, category: Optional[str] = None) -> List[Template]:
        """
        템플릿 디렉토리 스캔

        Args:
            category: 카테고리 필터 (ml, simulation, data 등)

        Returns:
            Template 리스트
        """
        templates = []

        if not self.base_path.exists():
            logger.warning(f"Template directory not found: {self.base_path}")
            return templates

        # 카테고리 필터링
        if category:
            search_paths = [self.base_path / category]
        else:
            search_paths = [self.base_path]

        # YAML 파일 검색
        for search_path in search_paths:
            if not search_path.exists():
                continue

            for yaml_file in search_path.rglob('*.yaml'):
                template = self.load_template_from_file(yaml_file)
                if template:
                    templates.append(template)

            for yml_file in search_path.rglob('*.yml'):
                template = self.load_template_from_file(yml_file)
                if template:
                    templates.append(template)

        logger.info(f"Scanned {len(templates)} templates from {self.base_path}")
        return templates

    def save_template(self, template: Template, file_path: Optional[Path] = None) -> Path:
        """
        템플릿을 YAML 파일로 저장

        Args:
            template: Template 객체
            file_path: 저장할 파일 경로 (None이면 자동 생성)

        Returns:
            저장된 파일 경로
        """
        if file_path is None:
            # 자동 경로 생성: base_path/category/template_id.yaml
            category = template.template.category
            template_id = template.template.id
            file_path = self.base_path / category / f"{template_id}.yaml"

        # 디렉토리 생성
        file_path.parent.mkdir(parents=True, exist_ok=True)

        # YAML 저장
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                yaml.dump(
                    template.to_dict(),
                    f,
                    default_flow_style=False,
                    allow_unicode=True,
                    sort_keys=False
                )

            logger.info(f"Template saved: {file_path}")
            return file_path

        except Exception as e:
            logger.error(f"Failed to save template to {file_path}: {e}")
            raise

    def delete_template(self, template_id: str) -> bool:
        """
        템플릿 삭제 (파일 삭제)

        Args:
            template_id: 템플릿 ID

        Returns:
            삭제 성공 여부
        """
        template = self.load_template(template_id)
        if not template or not template.file_path:
            logger.warning(f"Template not found or has no file path: {template_id}")
            return False

        try:
            template.file_path.unlink()
            logger.info(f"Template deleted: {template.file_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete template {template_id}: {e}")
            return False

    def get_categories(self) -> Dict[str, int]:
        """
        카테고리별 템플릿 개수 반환

        Returns:
            {category: count}
        """
        templates = self.scan_templates()

        categories = {}
        for template in templates:
            category = template.template.category
            categories[category] = categories.get(category, 0) + 1

        return categories
