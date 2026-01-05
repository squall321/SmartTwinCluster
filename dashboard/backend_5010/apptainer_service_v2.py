"""
Apptainer Image Registry Service (v2)
중앙 레지스트리 기반 이미지 관리

설계 철학:
- 같은 이름 = 같은 이미지
- 하나의 이미지에 대해 하나의 대표 경로만 유지
- Flat 구조: {gluster_mount}/apptainer/metadata/*.json (partition은 JSON 내부 필드로 구분)

메타데이터 기반 스캔:
- 우선순위 1: {gluster_mount}/apptainer/metadata/*.json (중앙 메타데이터, flat 구조)
- 우선순위 2: /opt/apptainers/*.json (로컬 메타데이터, fallback)

경로 구조:
- 메타데이터: {gluster_mount}/apptainer/metadata/*.json (headnode, flat 구조)
  기본 GlusterFS 마운트: /mnt/gluster (YAML shared_storage.glusterfs.mount_point)
- 실제 이미지: /opt/apptainers/*.sif (compute/viz 노드에 배포됨)
- 샌드박스: /scratch/apptainer_sandboxes/ (별도 관리)

메타데이터 JSON 구조:
{
  "id": "image_hash",
  "name": "image.sif",
  "path": "/opt/apptainers/image.sif",  // 실제 실행 경로
  "partition": "compute|viz|shared",    // 파티션 정보 (JSON 필드로 구분)
  "type": "compute|viz|custom",
  ...
}

특징:
- 메타데이터만 스캔 (SSH 불필요, .sif 파일 불필요)
- 파티션별 필터링 (partition 필드 기반)
- 메타데이터에 실제 경로가 포함되어 있음
"""

import os
import json
import subprocess
import hashlib
from typing import List, Dict, Optional
from datetime import datetime
from pathlib import Path
import logging

logger = logging.getLogger(__name__)

# 시스템 명령어 절대 경로 (systemd 환경에서 PATH 제한)
APPTAINER = '/usr/bin/apptainer'


class ApptainerImage:
    """Apptainer 이미지 메타데이터 클래스"""

    def __init__(self, **kwargs):
        self.id = kwargs.get('id', '')
        self.name = kwargs.get('name', '')
        self.path = kwargs.get('path', '')
        self.node = kwargs.get('node', 'headnode')  # 기본값: headnode
        self.partition = kwargs.get('partition', '')
        self.type = kwargs.get('type', 'custom')
        self.size = kwargs.get('size', 0)
        self.version = kwargs.get('version', '')
        self.description = kwargs.get('description', '')
        self.labels = kwargs.get('labels', {})
        self.apps = kwargs.get('apps', [])
        self.runscript = kwargs.get('runscript', '')
        self.env_vars = kwargs.get('env_vars', {})
        self.command_templates = kwargs.get('command_templates', [])  # 명령어 템플릿
        self.created_at = kwargs.get('created_at', datetime.now().isoformat())
        self.updated_at = kwargs.get('updated_at', datetime.now().isoformat())
        self.last_scanned = kwargs.get('last_scanned', datetime.now().isoformat())
        self.is_active = kwargs.get('is_active', True)
        self.available_on_nodes = kwargs.get('available_on_nodes', [])

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


class ApptainerRegistryService:
    """
    중앙 레지스트리 기반 Apptainer 이미지 관리 서비스

    설계 철학: 같은 이름 = 같은 이미지, 하나의 대표 경로만 유지

    {gluster_mount}/apptainer/ 구조 (flat):
      └── metadata/   # 모든 파티션의 메타데이터 (*.json)
                      # partition은 JSON 내부 필드로 구분

    /opt/apptainers/ 구조:
      └── *.sif       # 실제 이미지 파일 (compute/viz 노드에 배포됨)
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

        # 중앙 레지스트리 경로 (headnode에서 메타데이터 스캔용)
        # 기본값: /mnt/gluster/apptainer (YAML shared_storage.glusterfs.mount_point 기본값)
        # 환경 변수로 재정의 가능: APPTAINER_REGISTRY=/mnt/gluster/apptainer
        self.registry_base = os.getenv('APPTAINER_REGISTRY', '/mnt/gluster/apptainer')
        self.metadata_base = os.path.join(self.registry_base, 'metadata')

        # 이전 버전 호환: images 경로도 유지
        self.images_base = os.path.join(self.registry_base, 'images')
        self.metadata_dir = self.metadata_base  # alias

        # 실행 시 사용되는 경로 (compute/viz 노드에 배포되는 경로)
        # Phase8에서 /opt/apptainers/로 배포하므로 이 경로를 DB에 저장
        self.runtime_base = os.getenv('APPTAINER_RUNTIME_PATH', '/opt/apptainers')

        # 지원하는 파티션 타입
        self.partition_types = ['compute', 'viz', 'shared']

        # 메타데이터 스캔 경로 (우선순위 순서대로)
        # 철학: 같은 이름 = 같은 이미지, partition은 JSON 내부 필드로 구분
        # 구조: {gluster_mount}/apptainer/metadata/*.json (flat)
        self.metadata_scan_paths = [
            self.metadata_base,      # {gluster_mount}/apptainer/metadata/ (중앙 메타데이터)
            self.runtime_base,       # /opt/apptainers/ (로컬 배포, fallback)
        ]

    def scan_partition_images(self, partition: str = None) -> List[ApptainerImage]:
        """
        메타데이터를 스캔하고 파티션별로 필터링

        설계 철학: 같은 이름 = 같은 이미지, 하나의 대표 경로만 유지
        Flat 구조: partition은 JSON 내부 필드로 구분

        스캔 우선순위 (flat 디렉토리들):
        1. {gluster_mount}/apptainer/metadata/*.json (중앙 메타데이터)
        2. /opt/apptainers/*.json (로컬 메타데이터, fallback)

        Args:
            partition: 'compute', 'viz', 'shared', 또는 None (전체)

        Returns:
            ApptainerImage 객체 리스트
        """
        if partition and partition not in self.partition_types:
            logger.error(f"Unknown partition: {partition}")
            return []

        images = []
        scanned_names = set()  # 중복 방지 (같은 이름 = 같은 이미지)

        # Flat 구조: 모든 메타데이터 스캔 경로 순회
        for scan_dir in self.metadata_scan_paths:
            if not os.path.exists(scan_dir):
                logger.debug(f"Directory not found, skipping: {scan_dir}")
                continue

            logger.info(f"Scanning metadata in: {scan_dir}")

            try:
                for filename in os.listdir(scan_dir):
                    # .json 메타데이터 파일 검색 (.commands.json 제외)
                    if not filename.endswith('.json'):
                        continue
                    if filename.endswith('.commands.json'):
                        continue

                    # 이미지 이름 추출 (두 가지 패턴 지원)
                    # 패턴 1: image.json → image.sif
                    # 패턴 2: image.sif.json → image.sif
                    if filename.endswith('.sif.json'):
                        image_name = filename.replace('.sif.json', '.sif')
                    else:
                        image_name = filename.replace('.json', '.sif')

                    # 이미 스캔된 이미지는 건너뜀 (우선순위 높은 경로 우선)
                    if image_name in scanned_names:
                        continue

                    json_path = os.path.join(scan_dir, filename)

                    try:
                        # partition=None이면 기본값 'compute' 사용
                        default_partition = partition if partition else 'compute'
                        image = self._load_image_from_metadata(json_path, default_partition)

                        if image:
                            # 파티션 필터링 (None이면 전체)
                            if partition is None or image.partition == partition:
                                images.append(image)
                                scanned_names.add(image_name)
                                logger.info(f"Loaded metadata: {filename} (partition: {image.partition})")
                            else:
                                logger.debug(f"Skipping {filename}: partition mismatch ({image.partition} != {partition})")

                    except Exception as e:
                        logger.error(f"Failed to load metadata {filename}: {e}")
                        continue

            except Exception as e:
                logger.error(f"Failed to scan directory {scan_dir}: {e}")

        partition_str = partition if partition else 'all'
        logger.info(f"Partition {partition_str}: found {len(images)} images")
        return images

    def _load_image_from_metadata(self, json_path: str, default_partition: str) -> Optional[ApptainerImage]:
        """
        JSON 메타데이터 파일에서 이미지 정보 로드

        두 가지 메타데이터 형식 지원:
        1. 새 형식: generate_metadata.py 생성 (name, path, partition 등)
        2. 기존 형식: /opt/apptainers/*.sif.json (filename, display_name, node_types 등)

        Args:
            json_path: .json 파일 경로
            default_partition: 기본 파티션 (메타데이터에 없을 경우)

        Returns:
            ApptainerImage 객체 또는 None
        """
        try:
            with open(json_path, 'r') as f:
                raw_metadata = json.load(f)

            # 정규화된 메타데이터 딕셔너리
            metadata = {}

            # === name 필드 처리 ===
            if 'name' in raw_metadata:
                metadata['name'] = raw_metadata['name']
            elif 'filename' in raw_metadata:
                # 기존 형식: filename → name
                metadata['name'] = raw_metadata['filename']
            else:
                # 파일명에서 추출
                json_filename = os.path.basename(json_path)
                if json_filename.endswith('.sif.json'):
                    metadata['name'] = json_filename.replace('.sif.json', '.sif')
                else:
                    metadata['name'] = json_filename.replace('.json', '.sif')

            # === path 필드 처리 ===
            if 'path' in raw_metadata and raw_metadata['path']:
                metadata['path'] = raw_metadata['path']
            else:
                # runtime_base에서 생성
                metadata['path'] = os.path.join(self.runtime_base, metadata['name'])

            # === partition 필드 처리 ===
            if 'partition' in raw_metadata:
                metadata['partition'] = raw_metadata['partition']
            elif 'node_types' in raw_metadata:
                # 기존 형식: node_types에서 partition 추론
                node_types = raw_metadata['node_types']
                if 'viz' in node_types:
                    metadata['partition'] = 'viz'
                elif 'compute' in node_types:
                    metadata['partition'] = 'compute'
                else:
                    metadata['partition'] = default_partition
            elif 'category' in raw_metadata:
                # category에서 추론
                category = raw_metadata['category'].lower()
                if category in ['visualization', 'viz', 'desktop']:
                    metadata['partition'] = 'viz'
                else:
                    metadata['partition'] = 'compute'
            else:
                metadata['partition'] = default_partition

            # === id 필드 처리 ===
            if 'id' in raw_metadata:
                metadata['id'] = raw_metadata['id']
            else:
                metadata['id'] = metadata['name'].replace('.sif', '').replace(' ', '_').lower()

            # === type 필드 처리 ===
            if 'type' in raw_metadata:
                metadata['type'] = raw_metadata['type']
            else:
                # partition과 동일하게 설정
                metadata['type'] = metadata['partition']

            # === description 필드 처리 ===
            if 'description' in raw_metadata:
                metadata['description'] = raw_metadata['description']
            elif 'display_name' in raw_metadata:
                metadata['description'] = raw_metadata.get('display_name', '')
            else:
                metadata['description'] = f"{metadata['name']} image"

            # === version 필드 처리 ===
            metadata['version'] = raw_metadata.get('version', '1.0.0')

            # === size 필드 처리 ===
            metadata['size'] = raw_metadata.get('size', 0)

            # === 기타 필드 복사 ===
            for field in ['labels', 'apps', 'runscript', 'env_vars', 'command_templates']:
                if field in raw_metadata:
                    metadata[field] = raw_metadata[field]

            # === 타임스탬프 ===
            metadata['created_at'] = raw_metadata.get('created_at', datetime.now().isoformat())
            metadata['updated_at'] = raw_metadata.get('updated_at', datetime.now().isoformat())
            metadata['last_scanned'] = datetime.now().isoformat()
            metadata['is_active'] = raw_metadata.get('is_active', True)

            return ApptainerImage(**metadata)

        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in {json_path}: {e}")
            return None
        except Exception as e:
            logger.error(f"Failed to load metadata from {json_path}: {e}")
            return None

    def _scan_single_image(self, image_path: str, partition: str) -> Optional[ApptainerImage]:
        """
        단일 이미지 파일 스캔 및 메타데이터 추출

        우선순위:
        1. 배포된 JSON 메타데이터 파일 ({gluster_mount}/apptainer/metadata/*.json)
        2. 이미지 옆 JSON 파일 (*.sif -> *.json)
        3. apptainer inspect 실행 (느림)

        Args:
            image_path: .sif 파일 절대 경로
            partition: 파티션 이름

        Returns:
            ApptainerImage 객체 또는 None
        """
        try:
            filename = os.path.basename(image_path)

            # 파일 크기 확인
            if not os.path.exists(image_path):
                return None

            # 1. 먼저 중앙 메타데이터 저장소 확인 (가장 빠름)
            json_filename = filename.replace('.sif', '.json')
            central_json_path = os.path.join(self.metadata_dir, json_filename)

            cached_metadata = None
            if os.path.exists(central_json_path):
                try:
                    with open(central_json_path, 'r') as f:
                        cached_metadata = json.load(f)
                        logger.info(f"Loaded metadata from central cache: {central_json_path}")
                except Exception as e:
                    logger.warning(f"Failed to load central metadata {central_json_path}: {e}")

            # 2. 중앙 저장소에 없으면 이미지 옆 JSON 파일 확인
            if not cached_metadata:
                local_json_path = image_path.replace('.sif', '.json')
                if os.path.exists(local_json_path):
                    try:
                        with open(local_json_path, 'r') as f:
                            cached_metadata = json.load(f)
                            logger.info(f"Loaded metadata from local cache: {local_json_path}")
                    except Exception as e:
                        logger.warning(f"Failed to load local metadata {local_json_path}: {e}")

            # 3. 캐시된 메타데이터가 있으면 그것을 사용
            if cached_metadata:
                # 캐시된 메타데이터로 ApptainerImage 생성
                # path는 runtime 경로로 변환 ({gluster_mount}/... → /opt/apptainers/...)
                # 실제 실행은 compute/viz 노드에서 /opt/apptainers/ 경로로 수행됨
                runtime_path = os.path.join(self.runtime_base, filename)
                cached_metadata['path'] = runtime_path
                cached_metadata['last_scanned'] = datetime.now().isoformat()

                # command_templates가 없으면 .commands.json 파일에서 로드
                if 'command_templates' not in cached_metadata:
                    cached_metadata['command_templates'] = self._load_command_templates(image_path)

                return ApptainerImage(**cached_metadata)

            # 4. 캐시가 없으면 apptainer inspect 실행 (느림)
            logger.info(f"No cached metadata found, running apptainer inspect for {filename}")

            file_size = os.path.getsize(image_path)

            # ID 생성 (파일명 기반)
            image_id = filename.replace('.sif', '').replace(' ', '_').lower()

            # 이미지 타입 결정
            image_type = self._determine_image_type(filename, partition)

            # Apptainer inspect로 메타데이터 추출
            metadata = self._get_image_metadata(image_path)

            # 버전 추출
            version = self._extract_version(filename, metadata)

            # 설명 생성
            description = metadata.get('DESCRIPTION', '') or f"{filename} from {partition} partition"

            # 명령어 템플릿 로드
            command_templates = self._load_command_templates(image_path)

            # Runtime 경로 생성 (실제 실행 시 사용되는 경로)
            runtime_path = os.path.join(self.runtime_base, filename)

            # ApptainerImage 객체 생성
            image = ApptainerImage(
                id=image_id,
                name=filename,
                path=runtime_path,  # /opt/apptainers/{filename} 경로 사용
                node='headnode',  # 중앙 레지스트리는 headnode에 위치
                partition=partition,
                type=image_type,
                size=file_size,
                version=version,
                description=description,
                labels=metadata.get('labels', {}),
                apps=self._get_image_apps(image_path),
                runscript=metadata.get('RUNSCRIPT', ''),
                env_vars=metadata.get('environment', {}),
                command_templates=command_templates,
                created_at=datetime.now().isoformat(),
                updated_at=datetime.now().isoformat(),
                last_scanned=datetime.now().isoformat(),
                is_active=True,
                available_on_nodes=['headnode']  # 초기값: headnode만
            )

            return image

        except Exception as e:
            logger.error(f"Error scanning image {image_path}: {e}")
            return None

    def _load_command_templates(self, image_path: str) -> List[Dict]:
        """
        .commands.json 파일에서 명령어 템플릿 로드

        Args:
            image_path: SIF 파일 경로

        Returns:
            명령어 템플릿 리스트 (없으면 빈 리스트)
        """
        sif_dir = os.path.dirname(image_path)
        sif_basename = os.path.basename(image_path)
        sif_name_without_ext = os.path.splitext(sif_basename)[0]

        # .commands.json 파일 경로
        commands_file = os.path.join(sif_dir, f"{sif_name_without_ext}.commands.json")

        if not os.path.exists(commands_file):
            logger.debug(f"No command templates file found: {commands_file}")
            return []

        try:
            with open(commands_file, 'r', encoding='utf-8') as f:
                commands_data = json.load(f)

            templates = commands_data.get('command_templates', [])
            logger.info(f"Loaded {len(templates)} command templates from {commands_file}")
            return templates

        except Exception as e:
            logger.error(f"Error loading command templates from {commands_file}: {e}")
            return []

    def _get_image_metadata(self, image_path: str) -> Dict:
        """
        apptainer inspect 명령으로 이미지 메타데이터 추출

        Args:
            image_path: .sif 파일 경로

        Returns:
            메타데이터 딕셔너리
        """
        try:
            # apptainer inspect --json
            result = subprocess.run(
                [APPTAINER, 'inspect', '--json', image_path],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0 and result.stdout:
                metadata = json.loads(result.stdout)
                return metadata.get('attributes', {})
            else:
                logger.warning(f"apptainer inspect failed for {image_path}")
                return {}

        except subprocess.TimeoutExpired:
            logger.error(f"Timeout while inspecting {image_path}")
            return {}
        except json.JSONDecodeError:
            logger.error(f"Invalid JSON from apptainer inspect: {image_path}")
            return {}
        except Exception as e:
            logger.error(f"Error getting metadata for {image_path}: {e}")
            return {}

    def _get_image_apps(self, image_path: str) -> List[str]:
        """
        이미지에 포함된 앱 목록 추출

        Args:
            image_path: .sif 파일 경로

        Returns:
            앱 이름 리스트
        """
        try:
            result = subprocess.run(
                [APPTAINER, 'inspect', '--list-apps', image_path],
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode == 0 and result.stdout:
                # 출력에서 앱 이름 추출
                apps = [line.strip() for line in result.stdout.split('\n') if line.strip()]
                return apps
            return []

        except Exception as e:
            logger.error(f"Error getting apps for {image_path}: {e}")
            return []

    def _determine_image_type(self, filename: str, partition: str) -> str:
        """
        파일명과 파티션 정보로 이미지 타입 결정

        Args:
            filename: 이미지 파일명
            partition: 파티션 이름

        Returns:
            'viz', 'compute', 'shared', 또는 'custom'
        """
        filename_lower = filename.lower()

        # Viz 관련 키워드
        viz_keywords = ['paraview', 'blender', 'vtk', 'visit', 'visualization', 'viz']
        if partition == 'viz' or any(keyword in filename_lower for keyword in viz_keywords):
            return 'viz'

        # Compute 관련 키워드
        compute_keywords = ['python', 'pytorch', 'tensorflow', 'openfoam', 'gromacs', 'lammps', 'ansys', 'compute']
        if partition == 'compute' or any(keyword in filename_lower for keyword in compute_keywords):
            return 'compute'

        # Shared
        if partition == 'shared':
            return 'shared'

        return 'custom'

    def _extract_version(self, filename: str, metadata: Dict) -> str:
        """
        파일명 또는 메타데이터에서 버전 정보 추출

        Args:
            filename: 이미지 파일명
            metadata: 메타데이터 딕셔너리

        Returns:
            버전 문자열
        """
        # 메타데이터에서 버전 확인
        if 'VERSION' in metadata:
            return metadata['VERSION']

        if 'labels' in metadata and 'version' in metadata['labels']:
            return metadata['labels']['version']

        # 파일명에서 버전 패턴 추출 (예: python_3.11.sif → 3.11)
        import re
        version_pattern = r'[\d]+\.[\d]+(?:\.[\d]+)?'
        match = re.search(version_pattern, filename)
        if match:
            return match.group(0)

        return 'unknown'

    def scan_all_partitions(self) -> Dict[str, int]:
        """
        모든 파티션의 이미지를 스캔하고 DB에 저장

        Flat 구조에서는 전체 스캔 후 partition 필드로 집계

        Returns:
            파티션별 스캔된 이미지 개수
        """
        stats = {partition: 0 for partition in self.partition_types}
        stats['unknown'] = 0  # partition 필드가 없는 경우

        try:
            # 전체 스캔 (partition=None)
            images = self.scan_partition_images(partition=None)

            # DB에 저장 및 파티션별 집계
            for image in images:
                if self._save_image_to_db(image):
                    partition_key = image.partition if image.partition in self.partition_types else 'unknown'
                    stats[partition_key] = stats.get(partition_key, 0) + 1

            total = sum(stats.values())
            logger.info(f"Scanned all partitions: {total} total images")
            for partition_name, count in stats.items():
                if count > 0:
                    logger.info(f"  - {partition_name}: {count} images")

        except Exception as e:
            logger.error(f"Error scanning all partitions: {e}")

        return stats

    def _save_image_to_db(self, image: ApptainerImage) -> bool:
        """
        이미지 정보를 DB에 저장 (UPSERT)

        Args:
            image: ApptainerImage 객체

        Returns:
            성공 여부
        """
        if not self.db:
            logger.warning("No DB connection available")
            return False

        try:
            cursor = self.db.cursor()

            # UPSERT (id 기준으로 업데이트 또는 삽입)
            cursor.execute('''
                INSERT OR REPLACE INTO apptainer_images (
                    id, name, path, node, partition, type, size, version,
                    description, labels, apps, runscript, env_vars, command_templates,
                    created_at, updated_at, last_scanned, is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                image.id,
                image.name,
                image.path,
                image.node,
                image.partition,
                image.type,
                image.size,
                image.version,
                image.description,
                json.dumps(image.labels) if isinstance(image.labels, dict) else image.labels,
                json.dumps(image.apps) if isinstance(image.apps, list) else image.apps,
                image.runscript,
                json.dumps(image.env_vars) if isinstance(image.env_vars, dict) else image.env_vars,
                json.dumps(image.command_templates) if isinstance(image.command_templates, list) else image.command_templates,
                image.created_at,
                image.updated_at,
                image.last_scanned,
                image.is_active
            ))

            self.db.commit()
            return True

        except Exception as e:
            logger.error(f"Failed to save image {image.id} to DB: {e}")
            if self.db:
                self.db.rollback()
            return False

    def get_images_by_partition(self, partition: str) -> List[Dict]:
        """
        특정 파티션의 이미지 목록 조회

        Args:
            partition: 파티션 이름

        Returns:
            이미지 딕셔너리 리스트
        """
        if not self.db:
            return []

        try:
            cursor = self.db.cursor()
            cursor.execute('''
                SELECT * FROM apptainer_images
                WHERE partition = ? AND is_active = 1
                ORDER BY name
            ''', (partition,))

            columns = [description[0] for description in cursor.description]
            results = []

            for row in cursor.fetchall():
                image_dict = dict(zip(columns, row))

                # JSON 필드 파싱
                for field in ['labels', 'apps', 'env_vars', 'command_templates']:
                    if field in image_dict and isinstance(image_dict[field], str):
                        try:
                            image_dict[field] = json.loads(image_dict[field])
                        except:
                            image_dict[field] = {} if field not in ['apps', 'command_templates'] else []

                results.append(image_dict)

            return results

        except Exception as e:
            logger.error(f"Error getting images for partition {partition}: {e}")
            return []

    def get_all_images(self) -> List[Dict]:
        """
        모든 이미지 목록 조회

        Returns:
            이미지 딕셔너리 리스트
        """
        if not self.db:
            return []

        try:
            cursor = self.db.cursor()
            cursor.execute('''
                SELECT * FROM apptainer_images
                WHERE is_active = 1
                ORDER BY partition, name
            ''')

            columns = [description[0] for description in cursor.description]
            results = []

            for row in cursor.fetchall():
                image_dict = dict(zip(columns, row))

                # JSON 필드 파싱
                for field in ['labels', 'apps', 'env_vars', 'command_templates']:
                    if field in image_dict and isinstance(image_dict[field], str):
                        try:
                            image_dict[field] = json.loads(image_dict[field])
                        except:
                            image_dict[field] = {} if field not in ['apps', 'command_templates'] else []

                results.append(image_dict)

            return results

        except Exception as e:
            logger.error(f"Error getting all images: {e}")
            return []


# 하위 호환성을 위한 alias
ApptainerService = ApptainerRegistryService
