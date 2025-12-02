"""
Apptainer Discovery Service
Compute Node와 Viz Node의 .sif 이미지를 스캔하고 메타데이터를 관리

SSH를 통해 원격 노드의 /opt/apptainers/ 디렉토리를 스캔하고
apptainer inspect 명령으로 메타데이터를 추출합니다.

이미지 정보는 DB에 저장되며, Redis를 통해 캐싱됩니다 (TTL 1시간).
"""

import asyncio
import asyncssh
import json
import hashlib
import os
from typing import List, Dict, Optional
from datetime import datetime
from pathlib import Path
import logging

# 로깅 설정
logger = logging.getLogger(__name__)


class ApptainerImage:
    """Apptainer 이미지 메타데이터 클래스"""

    def __init__(self, **kwargs):
        self.id = kwargs.get('id', '')
        self.name = kwargs.get('name', '')
        self.path = kwargs.get('path', '')
        self.node = kwargs.get('node', '')
        self.partition = kwargs.get('partition', '')
        self.type = kwargs.get('type', 'custom')
        self.size = kwargs.get('size', 0)
        self.version = kwargs.get('version', '')
        self.description = kwargs.get('description', '')
        self.labels = kwargs.get('labels', {})
        self.apps = kwargs.get('apps', [])
        self.runscript = kwargs.get('runscript', '')
        self.env_vars = kwargs.get('env_vars', {})
        self.command_templates = kwargs.get('command_templates', [])
        self.created_at = kwargs.get('created_at', datetime.now().isoformat())
        self.updated_at = kwargs.get('updated_at', datetime.now().isoformat())
        self.last_scanned = kwargs.get('last_scanned', datetime.now().isoformat())
        self.is_active = kwargs.get('is_active', True)

    def to_dict(self) -> Dict:
        """딕셔너리로 변환"""
        return {
            'id': self.id,
            'name': self.name,
            'path': self.path,
            'node': self.node,
            'partition': self.partition,
            'type': self.type,
            'size': self.size,
            'version': self.version,
            'description': self.description,
            'labels': json.dumps(self.labels) if isinstance(self.labels, dict) else self.labels,
            'apps': json.dumps(self.apps) if isinstance(self.apps, list) else self.apps,
            'runscript': self.runscript,
            'env_vars': json.dumps(self.env_vars) if isinstance(self.env_vars, dict) else self.env_vars,
            'command_templates': json.dumps(self.command_templates) if isinstance(self.command_templates, list) else self.command_templates,
            'created_at': self.created_at,
            'updated_at': self.updated_at,
            'last_scanned': self.last_scanned,
            'is_active': self.is_active
        }


class ApptainerService:
    """
    Apptainer 이미지 검색 및 관리 서비스

    SSH를 통해 원격 노드의 Apptainer 이미지를 스캔하고
    메타데이터를 추출하여 DB에 저장합니다.
    """

    def __init__(self, db_connection=None, redis_client=None):
        """
        Args:
            db_connection: SQLite DB 연결 객체
            redis_client: Redis 클라이언트 (선택적)
        """
        self.db = db_connection
        self.redis = redis_client
        self.cache_ttl = 3600  # 1시간

        # Slurm 노드 정보 (환경변수 또는 설정 파일에서 로드)
        self.compute_nodes = os.getenv('COMPUTE_NODES', 'compute-node001').split(',')
        self.viz_nodes = os.getenv('VIZ_NODES', 'viz-node001').split(',')
        self.apptainer_base_path = os.getenv('APPTAINER_PATH', '/opt/apptainers')

    async def scan_node_images(self, node: str) -> List[ApptainerImage]:
        """
        특정 노드의 /opt/apptainers/ 디렉토리를 스캔하여 .sif 이미지 목록 반환

        SSH 연결 실패 시 재시도를 3번 수행하는 이유:
        - 네트워크 일시적 장애 대응
        - Compute Node의 부팅 중일 가능성

        Args:
            node: 스캔할 노드 호스트명 (예: compute-node001)

        Returns:
            List[ApptainerImage]: 발견된 이미지 목록

        Raises:
            SSHConnectionError: 3번 재시도 후에도 연결 실패
        """
        images = []
        max_retries = 3

        for attempt in range(max_retries):
            try:
                async with asyncssh.connect(
                    node,
                    known_hosts=None,  # 프로덕션에서는 known_hosts 파일 사용 권장
                    username=os.getenv('SSH_USER', 'koopark')
                ) as conn:
                    # .sif 파일 목록 조회
                    result = await conn.run(
                        f'ls -lh {self.apptainer_base_path}/*.sif 2>/dev/null || echo "NO_FILES"',
                        check=False
                    )

                    if result.stdout.strip() == "NO_FILES":
                        logger.warning(f"No .sif files found on {node}")
                        return []

                    # 각 .sif 파일에 대해 메타데이터 추출
                    for line in result.stdout.strip().split('\n'):
                        if '.sif' in line:
                            parts = line.split()
                            if len(parts) >= 9:
                                size_str = parts[4]  # 파일 크기 (human-readable)
                                filename = parts[-1]

                                # 메타데이터 추출
                                metadata = await self._get_image_metadata_remote(conn, filename, node)
                                if metadata:
                                    images.append(metadata)

                logger.info(f"Successfully scanned {node}: {len(images)} images found")
                return images

            except asyncssh.Error as e:
                logger.warning(f"SSH connection to {node} failed (attempt {attempt+1}/{max_retries}): {e}")
                if attempt < max_retries - 1:
                    await asyncio.sleep(2 ** attempt)  # Exponential backoff
                else:
                    logger.error(f"Failed to connect to {node} after {max_retries} attempts")
                    raise

        return images

    async def _get_image_metadata_remote(
        self,
        conn: asyncssh.SSHClientConnection,
        image_path: str,
        node: str
    ) -> Optional[ApptainerImage]:
        """
        원격 노드에서 apptainer inspect 명령으로 이미지 메타데이터 추출

        Args:
            conn: SSH 연결 객체
            image_path: 이미지 파일 전체 경로
            node: 노드 호스트명

        Returns:
            ApptainerImage 또는 None (실패 시)
        """
        try:
            # apptainer inspect --json 실행
            result = await conn.run(
                f'apptainer inspect --json {image_path}',
                check=False
            )

            if result.exit_status != 0:
                logger.warning(f"Failed to inspect {image_path} on {node}: {result.stderr}")
                return None

            inspect_data = json.loads(result.stdout)

            # 파일 크기 조회
            size_result = await conn.run(f'stat -c %s {image_path}')
            file_size = int(size_result.stdout.strip())

            # 이미지 이름 추출
            image_name = Path(image_path).name

            # 이미지 ID 생성 (경로 + 노드의 해시)
            image_id = hashlib.sha256(f"{node}:{image_path}".encode()).hexdigest()[:16]

            # 파티션 결정 (노드 타입에 따라)
            partition = 'viz' if node in self.viz_nodes else 'compute'

            # 이미지 타입 결정
            image_type = self._determine_image_type(image_name, inspect_data)

            # ApptainerImage 객체 생성
            image = ApptainerImage(
                id=image_id,
                name=image_name,
                path=image_path,
                node=node,
                partition=partition,
                type=image_type,
                size=file_size,
                version=self._extract_version(inspect_data),
                description=self._extract_description(inspect_data),
                labels=inspect_data.get('attributes', {}).get('labels', {}),
                apps=await self._get_image_apps_remote(conn, image_path),
                runscript=inspect_data.get('attributes', {}).get('runscript', ''),
                env_vars=inspect_data.get('attributes', {}).get('environment', {}),
                last_scanned=datetime.now().isoformat()
            )

            return image

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse inspect output for {image_path}: {e}")
            return None
        except Exception as e:
            logger.error(f"Error getting metadata for {image_path}: {e}")
            return None

    async def _get_image_apps_remote(
        self,
        conn: asyncssh.SSHClientConnection,
        image_path: str
    ) -> List[str]:
        """
        이미지 내부의 앱 목록 조회

        Args:
            conn: SSH 연결 객체
            image_path: 이미지 파일 경로

        Returns:
            앱 이름 리스트
        """
        try:
            result = await conn.run(
                f'apptainer inspect --list-apps {image_path}',
                check=False
            )

            if result.exit_status == 0 and result.stdout.strip():
                apps = [app.strip() for app in result.stdout.strip().split('\n') if app.strip()]
                return apps

            return []

        except Exception as e:
            logger.warning(f"Failed to get apps for {image_path}: {e}")
            return []

    def _determine_image_type(self, image_name: str, inspect_data: Dict) -> str:
        """
        이미지 타입 결정 (viz, compute, custom)

        Args:
            image_name: 이미지 파일명
            inspect_data: inspect 명령 결과

        Returns:
            이미지 타입 문자열
        """
        name_lower = image_name.lower()

        # VNC, GUI 관련 키워드가 있으면 viz
        if any(keyword in name_lower for keyword in ['vnc', 'gui', 'desktop', 'gnome', 'kde']):
            return 'viz'

        # GPU, MPI, HPC 관련 키워드가 있으면 compute
        if any(keyword in name_lower for keyword in ['gpu', 'cuda', 'mpi', 'hpc', 'openmpi']):
            return 'compute'

        # Labels에서 판단
        labels = inspect_data.get('attributes', {}).get('labels', {})
        if labels.get('type') in ['viz', 'compute']:
            return labels['type']

        return 'custom'

    def _extract_version(self, inspect_data: Dict) -> str:
        """이미지 버전 추출"""
        labels = inspect_data.get('attributes', {}).get('labels', {})
        return labels.get('version', labels.get('VERSION', '1.0.0'))

    def _extract_description(self, inspect_data: Dict) -> str:
        """이미지 설명 추출"""
        labels = inspect_data.get('attributes', {}).get('labels', {})
        return labels.get('description', labels.get('DESCRIPTION', ''))

    def scan_node_images_sync(self, node: str) -> List[ApptainerImage]:
        """동기 버전의 scan_node_images (Flask에서 사용)"""
        return asyncio.run(self.scan_node_images(node))

    def list_available_images(self, partition: str = None) -> List[Dict]:
        """
        DB에 저장된 사용 가능한 이미지 목록 조회

        Args:
            partition: 파티션 필터 (compute, viz) - None이면 전체

        Returns:
            이미지 정보 딕셔너리 리스트
        """
        if not self.db:
            logger.error("Database connection not available")
            return []

        try:
            cursor = self.db.cursor()

            if partition:
                query = """
                    SELECT * FROM apptainer_images
                    WHERE partition = ? AND is_active = 1
                    ORDER BY name
                """
                cursor.execute(query, (partition,))
            else:
                query = """
                    SELECT * FROM apptainer_images
                    WHERE is_active = 1
                    ORDER BY partition, name
                """
                cursor.execute(query)

            columns = [desc[0] for desc in cursor.description]
            images = []

            for row in cursor.fetchall():
                image_dict = dict(zip(columns, row))
                # JSON 필드 파싱
                for field in ['labels', 'apps', 'env_vars', 'command_templates']:
                    if image_dict.get(field) and isinstance(image_dict[field], str):
                        try:
                            image_dict[field] = json.loads(image_dict[field])
                        except json.JSONDecodeError:
                            logger.warning(f"Failed to parse {field} for image {image_dict.get('id')}")
                            image_dict[field] = [] if field in ['apps', 'command_templates'] else {}

                images.append(image_dict)

            return images

        except Exception as e:
            logger.error(f"Failed to list images from DB: {e}")
            return []

    def get_image_by_id(self, image_id: str) -> Optional[Dict]:
        """
        이미지 ID로 상세 정보 조회

        Args:
            image_id: 이미지 ID

        Returns:
            이미지 정보 딕셔너리 또는 None
        """
        if not self.db:
            return None

        try:
            cursor = self.db.cursor()
            cursor.execute("SELECT * FROM apptainer_images WHERE id = ?", (image_id,))
            row = cursor.fetchone()

            if not row:
                return None

            columns = [desc[0] for desc in cursor.description]
            image_dict = dict(zip(columns, row))

            # JSON 필드 파싱
            for field in ['labels', 'apps', 'env_vars', 'command_templates']:
                if image_dict.get(field) and isinstance(image_dict[field], str):
                    try:
                        image_dict[field] = json.loads(image_dict[field])
                    except json.JSONDecodeError:
                        logger.warning(f"Failed to parse {field} for image {image_dict.get('id')}")
                        image_dict[field] = [] if field in ['apps', 'command_templates'] else {}

            return image_dict

        except Exception as e:
            logger.error(f"Failed to get image {image_id}: {e}")
            return None

    def save_image_to_db(self, image: ApptainerImage) -> bool:
        """
        이미지 정보를 DB에 저장 (INSERT or UPDATE)

        Args:
            image: ApptainerImage 객체

        Returns:
            성공 여부
        """
        if not self.db:
            logger.error("Database connection not available")
            return False

        try:
            cursor = self.db.cursor()
            image_dict = image.to_dict()

            # 기존 이미지 확인
            cursor.execute("SELECT id FROM apptainer_images WHERE id = ?", (image.id,))
            exists = cursor.fetchone()

            if exists:
                # UPDATE
                query = """
                    UPDATE apptainer_images SET
                        name=?, path=?, node=?, partition=?, type=?,
                        size=?, version=?, description=?, labels=?, apps=?,
                        runscript=?, env_vars=?, command_templates=?, updated_at=?, last_scanned=?, is_active=?
                    WHERE id=?
                """
                cursor.execute(query, (
                    image.name, image.path, image.node, image.partition, image.type,
                    image.size, image.version, image.description,
                    image_dict['labels'], image_dict['apps'],
                    image.runscript, image_dict['env_vars'], image_dict['command_templates'],
                    datetime.now().isoformat(), image.last_scanned, image.is_active,
                    image.id
                ))
            else:
                # INSERT
                query = """
                    INSERT INTO apptainer_images (
                        id, name, path, node, partition, type, size, version,
                        description, labels, apps, runscript, env_vars, command_templates,
                        created_at, updated_at, last_scanned, is_active
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
                cursor.execute(query, (
                    image.id, image.name, image.path, image.node, image.partition,
                    image.type, image.size, image.version, image.description,
                    image_dict['labels'], image_dict['apps'], image.runscript,
                    image_dict['env_vars'], image_dict['command_templates'], image.created_at, image.updated_at,
                    image.last_scanned, image.is_active
                ))

            self.db.commit()
            logger.info(f"Saved image {image.name} ({image.id}) to DB")
            return True

        except Exception as e:
            logger.error(f"Failed to save image to DB: {e}")
            self.db.rollback()
            return False

    def scan_all_nodes(self) -> Dict[str, int]:
        """
        모든 compute/viz 노드를 스캔하여 DB에 저장

        Returns:
            스캔 결과 통계 {'total': int, 'success': int, 'failed': int}
        """
        stats = {'total': 0, 'success': 0, 'failed': 0}
        all_nodes = self.compute_nodes + self.viz_nodes

        for node in all_nodes:
            try:
                logger.info(f"Scanning node: {node}")
                images = self.scan_node_images_sync(node)

                for image in images:
                    if self.save_image_to_db(image):
                        stats['success'] += 1
                    else:
                        stats['failed'] += 1
                    stats['total'] += 1

            except Exception as e:
                logger.error(f"Failed to scan node {node}: {e}")
                stats['failed'] += 1

        logger.info(f"Scan complete: {stats}")
        return stats

    def validate_image(self, image_path: str, node: str) -> bool:
        """
        이미지 유효성 검증 (파일 존재 여부 확인)

        Args:
            image_path: 이미지 파일 경로
            node: 노드 호스트명

        Returns:
            유효성 여부
        """
        try:
            # SSH로 파일 존재 확인
            result = asyncio.run(self._validate_image_remote(image_path, node))
            return result
        except Exception as e:
            logger.error(f"Failed to validate image {image_path} on {node}: {e}")
            return False

    async def _validate_image_remote(self, image_path: str, node: str) -> bool:
        """원격 노드에서 이미지 파일 존재 확인"""
        try:
            async with asyncssh.connect(
                node,
                known_hosts=None,
                username=os.getenv('SSH_USER', 'koopark')
            ) as conn:
                result = await conn.run(f'test -f {image_path} && echo "EXISTS"')
                return result.stdout.strip() == "EXISTS"
        except Exception:
            return False
