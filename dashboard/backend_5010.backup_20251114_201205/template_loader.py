"""
Template Loader Service
외부 YAML 템플릿 파일을 로드하고 관리하는 서비스

파일 시스템의 /shared/templates/ 디렉토리를 스캔하여
YAML 템플릿을 로드하고 DB와 동기화합니다.
"""

import os
import yaml
import glob
import hashlib
import logging
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
import json

logger = logging.getLogger(__name__)


class TemplateLoader:
    """
    템플릿 로더 서비스

    파일 시스템의 YAML 템플릿을 스캔하고 DB와 동기화합니다.
    """

    def __init__(self, base_path: str = "/shared/templates", db_connection=None):
        """
        Args:
            base_path: 템플릿 베이스 디렉토리 경로
            db_connection: SQLite DB 연결 객체
        """
        self.base_path = Path(base_path)
        self.db = db_connection
        self.cache = {}  # 메모리 캐시
        self.cache_ttl = 300  # 5분

    def scan_templates(self, category: str = None, source: str = None) -> List[Dict]:
        """
        템플릿 디렉토리 스캔

        Args:
            category: 카테고리 필터 (ml, cfd, structural 등)
            source: 소스 필터 (official, community, private)

        Returns:
            템플릿 정보 딕셔너리 리스트
        """
        templates = []

        # Official templates
        if not source or source == 'official':
            templates.extend(self._scan_directory(
                self.base_path / "official",
                "official",
                category
            ))

        # Community templates
        if not source or source == 'community':
            templates.extend(self._scan_directory(
                self.base_path / "community",
                "community",
                category
            ))

        # Private templates (모든 사용자 디렉토리 스캔)
        if not source or source == 'private':
            private_path = self.base_path / "private"
            if private_path.exists():
                for user_dir in private_path.iterdir():
                    if user_dir.is_dir():
                        templates.extend(self._scan_directory(
                            user_dir,
                            f"private:{user_dir.name}",
                            category
                        ))

        return templates

    def _scan_directory(self, path: Path, source: str, category: str = None) -> List[Dict]:
        """
        디렉토리 내 YAML 템플릿 스캔

        Args:
            path: 스캔할 디렉토리 경로
            source: 소스 타입 (official, community, private:username)
            category: 카테고리 필터

        Returns:
            템플릿 정보 리스트
        """
        templates = []

        if not path.exists():
            logger.warning(f"Directory not found: {path}")
            return templates

        # YAML 파일 검색 (재귀적)
        for yaml_file in path.rglob("*.yaml"):
            try:
                template = self.load_template_file(yaml_file)

                # 카테고리 필터
                if category and template.get('template', {}).get('category') != category:
                    continue

                template['source'] = source
                template['file_path'] = str(yaml_file)

                # 카테고리 자동 추출 (경로에서)
                if 'category' not in template.get('template', {}):
                    # /shared/templates/official/ml/xxx.yaml -> ml
                    parts = yaml_file.parts
                    if 'official' in parts:
                        idx = parts.index('official')
                        if len(parts) > idx + 1:
                            template['template']['category'] = parts[idx + 1]

                templates.append(template)

            except Exception as e:
                logger.error(f"Failed to load template {yaml_file}: {e}")

        return templates

    def load_template_file(self, file_path: Path) -> Dict:
        """
        YAML 템플릿 파일 로드 및 파싱

        Args:
            file_path: YAML 파일 경로

        Returns:
            템플릿 데이터 딕셔너리

        Raises:
            ValueError: 필수 필드가 없거나 형식이 잘못된 경우
        """
        with open(file_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)

        # 필수 필드 검증
        if not isinstance(data, dict):
            raise ValueError("Template must be a YAML dictionary")

        if 'template' not in data:
            raise ValueError("Missing 'template' section")

        template_info = data.get('template', {})

        # 필수 필드 확인
        required_fields = ['id', 'name', 'display_name']
        for field in required_fields:
            if field not in template_info:
                raise ValueError(f"Missing required field: template.{field}")

        # 파일 메타데이터 추가
        data['file_hash'] = self._calculate_hash(file_path)
        data['last_modified'] = datetime.fromtimestamp(file_path.stat().st_mtime).isoformat()
        data['file_size'] = file_path.stat().st_size

        return data

    def _calculate_hash(self, file_path: Path) -> str:
        """
        파일 해시 계산 (SHA256)

        Args:
            file_path: 파일 경로

        Returns:
            16자리 해시 문자열
        """
        with open(file_path, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()[:16]

    def get_template(self, template_id: str) -> Optional[Dict]:
        """
        템플릿 ID로 조회

        Args:
            template_id: 템플릿 ID

        Returns:
            템플릿 데이터 또는 None
        """
        templates = self.scan_templates()
        for template in templates:
            # template.template.id 또는 template_id 필드로 검색
            if (template.get('template', {}).get('id') == template_id or
                template.get('template_id') == template_id):
                return template
        return None

    def get_template_by_path(self, file_path: str) -> Optional[Dict]:
        """
        파일 경로로 템플릿 조회

        Args:
            file_path: 템플릿 파일 경로

        Returns:
            템플릿 데이터 또는 None
        """
        try:
            path = Path(file_path)
            if not path.exists():
                return None
            return self.load_template_file(path)
        except Exception as e:
            logger.error(f"Failed to load template from {file_path}: {e}")
            return None

    def save_template(self, template_data: Dict, user_id: str, is_public: bool = False) -> str:
        """
        새 템플릿 저장

        Args:
            template_data: 템플릿 데이터
            user_id: 사용자 ID
            is_public: 공개 여부 (community에 저장)

        Returns:
            저장된 파일 경로

        Raises:
            ValueError: 잘못된 템플릿 데이터
        """
        # 필수 필드 검증
        if 'template' not in template_data:
            raise ValueError("Missing 'template' section")

        template_info = template_data['template']
        template_id = template_info.get('id')
        category = template_info.get('category', 'custom')

        if not template_id:
            raise ValueError("Missing template.id")

        # 저장 경로 결정
        if is_public:
            # Community 템플릿
            save_dir = self.base_path / "community" / category
            save_dir.mkdir(parents=True, exist_ok=True)
            save_path = save_dir / f"{template_id}.yaml"
        else:
            # Private 템플릿
            user_dir = self.base_path / "private" / user_id
            user_dir.mkdir(parents=True, exist_ok=True)
            save_path = user_dir / f"{template_id}.yaml"

        # YAML로 저장
        with open(save_path, 'w', encoding='utf-8') as f:
            yaml.dump(template_data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

        logger.info(f"Template saved: {save_path}")
        return str(save_path)

    def update_template(self, template_id: str, template_data: Dict, username: str = 'unknown') -> bool:
        """
        기존 템플릿 업데이트

        Args:
            template_id: 템플릿 ID
            template_data: 업데이트할 데이터
            username: 수정하는 사용자명 (로깅용)

        Returns:
            성공 여부

        Raises:
            ValueError: 템플릿을 찾을 수 없거나 권한이 없는 경우
        """
        template = self.get_template(template_id)
        if not template:
            raise ValueError(f"Template {template_id} not found")

        file_path = Path(template['file_path'])

        # 권한 체크는 API 레이어에서 수행됨 (templates_api_v2.py)
        # 여기서는 로깅만 수행
        if 'official' in str(file_path):
            logger.info(f"Official template {template_id} modified by user: {username}")
        else:
            logger.info(f"Template {template_id} modified by user: {username}")

        # YAML로 저장
        with open(file_path, 'w', encoding='utf-8') as f:
            yaml.dump(template_data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

        logger.info(f"Template updated: {file_path}")
        return True

    def delete_template(self, template_id: str, user_id: str) -> bool:
        """
        템플릿 삭제 (아카이브로 이동)

        Args:
            template_id: 템플릿 ID
            user_id: 사용자 ID (권한 확인용)

        Returns:
            성공 여부

        Raises:
            ValueError: 템플릿을 찾을 수 없는 경우
            PermissionError: 권한이 없는 경우
        """
        template = self.get_template(template_id)
        if not template:
            raise ValueError(f"Template {template_id} not found")

        file_path = Path(template['file_path'])

        # Official 템플릿은 삭제 불가
        if 'official' in str(file_path):
            raise PermissionError("Cannot delete official templates")

        # 권한 확인 (private 템플릿인 경우)
        if 'private' in str(file_path):
            if f"private/{user_id}" not in str(file_path):
                raise PermissionError("Cannot delete other user's templates")

        # 아카이브로 이동
        archive_path = self.base_path / "archived" / file_path.name
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.rename(archive_path)

        logger.info(f"Template archived: {file_path} -> {archive_path}")
        return True

    def sync_to_database(self) -> Dict[str, int]:
        """
        파일 시스템의 템플릿을 DB와 동기화

        Returns:
            동기화 통계 {'inserted': int, 'updated': int, 'deleted': int}
        """
        if not self.db:
            logger.warning("Database connection not available")
            return {'inserted': 0, 'updated': 0, 'deleted': 0}

        stats = {'inserted': 0, 'updated': 0, 'deleted': 0}

        try:
            cursor = self.db.cursor()

            # 파일에서 템플릿 스캔
            file_templates = self.scan_templates()
            file_template_ids = {t['template']['id'] for t in file_templates}

            # DB에 있는 템플릿 목록
            cursor.execute("SELECT template_id FROM job_templates_v2")
            db_template_ids = {row[0] for row in cursor.fetchall()}

            # 새로 추가된 템플릿 (INSERT)
            new_templates = file_template_ids - db_template_ids
            for template in file_templates:
                template_id = template['template']['id']
                if template_id in new_templates:
                    self._insert_template_to_db(template)
                    stats['inserted'] += 1

            # 삭제된 템플릿 (MARK AS DELETED)
            deleted_templates = db_template_ids - file_template_ids
            for template_id in deleted_templates:
                cursor.execute(
                    "UPDATE job_templates_v2 SET is_active = 0 WHERE template_id = ?",
                    (template_id,)
                )
                stats['deleted'] += 1

            # 수정된 템플릿 (UPDATE)
            for template in file_templates:
                template_id = template['template']['id']
                if template_id in db_template_ids:
                    # 해시 비교로 변경 감지
                    cursor.execute(
                        "SELECT file_hash FROM job_templates_v2 WHERE template_id = ?",
                        (template_id,)
                    )
                    row = cursor.fetchone()
                    if row and row[0] != template.get('file_hash'):
                        self._update_template_in_db(template)
                        stats['updated'] += 1

            self.db.commit()
            logger.info(f"Template sync completed: {stats}")

        except Exception as e:
            logger.error(f"Failed to sync templates to database: {e}")
            self.db.rollback()

        return stats

    def _insert_template_to_db(self, template: Dict):
        """템플릿을 DB에 INSERT"""
        if not self.db:
            return

        cursor = self.db.cursor()
        t = template['template']

        cursor.execute("""
            INSERT INTO job_templates_v2 (
                template_id, name, display_name, description, category,
                tags, version, author, is_public, source,
                slurm_config, apptainer_config, file_schema, script_template,
                file_path, file_hash, created_at, updated_at, is_active
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            t.get('id'),
            t.get('name'),
            t.get('display_name'),
            t.get('description', ''),
            t.get('category', 'custom'),
            json.dumps(t.get('tags', [])),
            t.get('version', '1.0.0'),
            t.get('author', 'unknown'),
            1 if t.get('is_public', False) else 0,
            template.get('source', 'unknown'),
            json.dumps(template.get('slurm', {})),
            json.dumps(template.get('apptainer', {})),
            json.dumps(template.get('files', {})),
            json.dumps(template.get('script', {})),
            template.get('file_path', ''),
            template.get('file_hash', ''),
            datetime.now().isoformat(),
            datetime.now().isoformat(),
            1
        ))

    def _update_template_in_db(self, template: Dict):
        """템플릿을 DB에 UPDATE"""
        if not self.db:
            return

        cursor = self.db.cursor()
        t = template['template']

        cursor.execute("""
            UPDATE job_templates_v2 SET
                name = ?, display_name = ?, description = ?, category = ?,
                tags = ?, version = ?, author = ?, is_public = ?, source = ?,
                slurm_config = ?, apptainer_config = ?, file_schema = ?, script_template = ?,
                file_path = ?, file_hash = ?, updated_at = ?
            WHERE template_id = ?
        """, (
            t.get('name'),
            t.get('display_name'),
            t.get('description', ''),
            t.get('category', 'custom'),
            json.dumps(t.get('tags', [])),
            t.get('version', '1.0.0'),
            t.get('author', 'unknown'),
            1 if t.get('is_public', False) else 0,
            template.get('source', 'unknown'),
            json.dumps(template.get('slurm', {})),
            json.dumps(template.get('apptainer', {})),
            json.dumps(template.get('files', {})),
            json.dumps(template.get('script', {})),
            template.get('file_path', ''),
            template.get('file_hash', ''),
            datetime.now().isoformat(),
            t.get('id')
        ))

    def get_categories(self) -> List[Dict]:
        """
        사용 가능한 카테고리 목록 조회

        Returns:
            카테고리 정보 리스트
        """
        templates = self.scan_templates()
        categories = {}

        for template in templates:
            category = template.get('template', {}).get('category', 'custom')
            if category not in categories:
                categories[category] = {'name': category, 'count': 0, 'templates': []}

            categories[category]['count'] += 1
            categories[category]['templates'].append(template['template']['id'])

        return list(categories.values())

    def search_templates(self, query: str, tags: List[str] = None) -> List[Dict]:
        """
        템플릿 검색

        Args:
            query: 검색 키워드
            tags: 태그 필터

        Returns:
            검색된 템플릿 리스트
        """
        templates = self.scan_templates()
        results = []

        query_lower = query.lower() if query else ""

        for template in templates:
            t = template.get('template', {})

            # 키워드 검색
            if query:
                name_match = query_lower in t.get('name', '').lower()
                display_name_match = query_lower in t.get('display_name', '').lower()
                desc_match = query_lower in t.get('description', '').lower()

                if not (name_match or display_name_match or desc_match):
                    continue

            # 태그 필터
            if tags:
                template_tags = t.get('tags', [])
                if not any(tag in template_tags for tag in tags):
                    continue

            results.append(template)

        return results
