#!/usr/bin/env python3
"""
Job Submit API - 신규 Template 시스템 지원

핵심 기능:
- Template 기반 Job 제출
- multipart/form-data 처리 (file_key 기반 파일 매핑)
- Apptainer 이미지 동적 선택
- Slurm 스크립트 자동 생성
"""

import os
import re
import json
import logging
import tempfile
import yaml
import subprocess
import hashlib
import sqlite3
import traceback
import uuid
from datetime import datetime
from flask import Blueprint, request, jsonify, g
from werkzeug.utils import secure_filename
from template_validator import TemplateValidator
from middleware.jwt_middleware import (
    jwt_required, permission_required, ROLE_DEFINITIONS,
    is_partition_allowed, PARTITION_ENFORCE,
)


class PartitionNotAllowed(Exception):
    """web_user 의 role 이 요청 파티션에 접근 불가 — submit/preview 가 403 으로 변환."""
    def __init__(self, role, partition, allowed):
        self.role, self.partition, self.allowed = role, partition, allowed
        super().__init__(f"partition '{partition}' not allowed for role '{role}' (allowed={allowed})")

# 절대 경로 import (systemd 환경에서 PATH 제한으로 필요)
from slurm_commands import SSH, SBATCH

# Structured logging setup
logger = logging.getLogger(__name__)

# Error codes for better tracking
class ErrorCode:
    """에러 코드 체계 - 문제 원인 추적용"""
    # Template errors (1xxx)
    TEMPLATE_NOT_FOUND = 1001
    TEMPLATE_INVALID = 1002
    TEMPLATE_VALIDATION_FAILED = 1003

    # File errors (2xxx)
    FILE_MISSING = 2001
    FILE_TOO_LARGE = 2002
    FILE_INVALID_TYPE = 2003
    FILE_UPLOAD_FAILED = 2004
    FILE_VALIDATION_FAILED = 2005

    # Image errors (3xxx)
    IMAGE_NOT_FOUND = 3001
    IMAGE_REQUIRED = 3002
    IMAGE_UNAVAILABLE = 3003

    # Slurm errors (4xxx)
    SLURM_SUBMISSION_FAILED = 4001
    SLURM_TIMEOUT = 4002
    SLURM_SCRIPT_GENERATION_FAILED = 4003

    # DB errors (5xxx)
    DB_CONNECTION_FAILED = 5001
    DB_RECORD_FAILED = 5002

    # General errors (9xxx)
    INVALID_REQUEST = 9001
    INTERNAL_ERROR = 9999

def log_error(request_id: str, error_code: int, message: str, details: dict = None, exc_info: bool = False):
    """
    구조화된 에러 로깅

    Args:
        request_id: 요청 추적 ID
        error_code: 에러 코드
        message: 에러 메시지
        details: 추가 상세 정보
        exc_info: 스택 트레이스 포함 여부
    """
    log_data = {
        'request_id': request_id,
        'error_code': error_code,
        'message': message,
        'timestamp': datetime.now().isoformat()
    }
    if details:
        log_data['details'] = details

    logger.error(json.dumps(log_data, ensure_ascii=False), exc_info=exc_info)

def log_info(request_id: str, event: str, details: dict = None):
    """
    구조화된 정보 로깅

    Args:
        request_id: 요청 추적 ID
        event: 이벤트 이름
        details: 추가 상세 정보
    """
    log_data = {
        'request_id': request_id,
        'event': event,
        'timestamp': datetime.now().isoformat()
    }
    if details:
        log_data['details'] = details

    logger.info(json.dumps(log_data, ensure_ascii=False))

job_submit_bp = Blueprint('job_submit', __name__)

# Template 디렉토리
TEMPLATE_DIRS = {
    'official': '/shared/templates/official',
    'community': '/shared/templates/community',
    'user': '/shared/templates/user',
}

# Apptainer 이미지 디렉토리 (fallback용, DB 우선 사용)
APPTAINER_DIRS = {
    'compute': os.getenv('APPTAINER_RUNTIME_PATH', '/opt/apptainers'),
    'viz': os.getenv('APPTAINER_RUNTIME_PATH', '/opt/apptainers'),
}

# 메타데이터 디렉토리 (GlusterFS 공유 스토리지)
APPTAINER_METADATA_DIR = os.getenv('APPTAINER_METADATA_DIR', '/mnt/gluster/apptainer/metadata')

# 업로드 임시 디렉토리
UPLOAD_DIR = '/tmp/slurm_uploads'
os.makedirs(UPLOAD_DIR, exist_ok=True)

# 파티션별 대표 노드 (이미지 파일 존재 확인용) - YAML에서 동적 로드
def get_partition_nodes_from_yaml():
    """YAML 설정에서 파티션별 대표 노드 가져오기"""
    partition_nodes = {'compute': None, 'viz': None}
    yaml_paths = [
        os.getenv('CLUSTER_YAML_PATH', ''),
        os.getenv('CLUSTER_CONFIG_PATH', ''),
        os.path.join(os.path.dirname(__file__), '..', '..', 'my_multihead_cluster.yaml'),
        '/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_multihead_cluster.yaml',
    ]
    yaml_paths = [p for p in yaml_paths if p]
    for yaml_path in yaml_paths:
        if os.path.exists(yaml_path):
            try:
                with open(yaml_path, 'r') as f:
                    config = yaml.safe_load(f)
                    nodes_config = config.get('nodes', {})

                    for node in nodes_config.get('compute_nodes', []):
                        node_type = node.get('node_type', 'compute')
                        hostname = node.get('hostname')
                        if hostname:
                            if node_type == 'viz' and not partition_nodes['viz']:
                                partition_nodes['viz'] = hostname
                            elif node_type == 'compute' and not partition_nodes['compute']:
                                partition_nodes['compute'] = hostname

                    if partition_nodes['compute'] or partition_nodes['viz']:
                        logger.info(f"✅ Job Submit API: Loaded partition nodes from YAML: {partition_nodes}")
                        return partition_nodes
            except Exception as e:
                logger.warning(f"Failed to load partition nodes from YAML: {e}")

    # Fallback
    logger.warning("Using fallback partition nodes")
    return {'compute': 'node001', 'viz': 'viz-node001'}

PARTITION_NODES = get_partition_nodes_from_yaml()


def get_db_connection():
    """DB 연결 가져오기"""
    db_path = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def record_job_submission(
    job_id: str,
    job_name: str,
    template_id: str,
    template: dict,
    user_id: str,
    slurm_config: dict,
    apptainer_image: str,
    uploaded_files: dict,
    script_path: str,
    result_dir: str = None
) -> int:
    """
    Job 제출 이력 DB에 저장 (Phase 3)

    Returns:
        int: 생성된 레코드 ID
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    # 스크립트 해시 계산
    try:
        with open(script_path, 'rb') as f:
            script_hash = hashlib.sha256(f.read()).hexdigest()[:16]
    except:
        script_hash = 'unknown'

    try:
        cursor.execute("""
            INSERT INTO job_submissions (
                job_id, job_name, template_id, template_name, template_version,
                user_id, partition, nodes, cpus, memory, time_limit,
                apptainer_image, uploaded_files, script_path, script_hash,
                result_dir, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'submitted')
        """, (
            job_id,
            job_name,
            template_id,
            template.get('template', {}).get('name'),
            template.get('template', {}).get('version', '1.0.0'),
            user_id,
            slurm_config.get('partition'),
            slurm_config.get('nodes'),
            slurm_config.get('ntasks'),
            slurm_config.get('mem', slurm_config.get('memory')),
            slurm_config.get('time'),
            apptainer_image,
            json.dumps(uploaded_files),
            script_path,
            script_hash,
            result_dir
        ))

        conn.commit()
        record_id = cursor.lastrowid

        logger.info(f"✅ Job submission recorded: ID={record_id}, Job={job_id}")
        return record_id

    except Exception as e:
        logger.error(f"Failed to record job submission: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()


def find_file_definition(file_schema: dict, file_key: str) -> dict:
    """
    파일 스키마에서 file_key에 해당하는 정의 찾기

    Args:
        file_schema: Template의 files.input_schema
        file_key: 찾을 파일 키

    Returns:
        dict: 파일 정의 또는 None
    """
    for file_def in file_schema.get('required', []) + file_schema.get('optional', []):
        if file_def.get('file_key') == file_key:
            return file_def
    return None


def parse_size_string(size_str: str) -> int:
    """
    크기 문자열을 바이트로 변환

    Args:
        size_str: "500MB", "1GB" 등

    Returns:
        int: 바이트 수
    """
    size_str = size_str.strip().upper()

    if size_str.endswith('GB'):
        return int(float(size_str[:-2]) * 1024 * 1024 * 1024)
    elif size_str.endswith('MB'):
        return int(float(size_str[:-2]) * 1024 * 1024)
    elif size_str.endswith('KB'):
        return int(float(size_str[:-2]) * 1024)
    else:
        # 기본값: MB로 가정
        return int(float(size_str) * 1024 * 1024)


def validate_file_schema_strict(template: dict, uploaded_files: dict) -> list:
    """
    엄격한 파일 스키마 검증 (Phase 8.1)

    검증 항목:
    1. 필수 파일 확인
    2. 파일 확장자 검증
    3. 파일 크기 검증
    4. 예상치 못한 파일 체크

    Args:
        template: 정규화된 Template
        uploaded_files: {file_key: {path, filename, size}}

    Returns:
        list: 에러 목록 (빈 리스트면 검증 통과)
    """
    errors = []
    file_schema = template.get('files', {}).get('input_schema', {})

    # 1. 필수 파일 확인
    for required_file in file_schema.get('required', []):
        file_key = required_file['file_key']
        if file_key not in uploaded_files:
            errors.append(
                f"Required file missing: {file_key} ({required_file.get('name', file_key)})"
            )

    # 2. 업로드된 파일 검증
    for file_key, file_info in uploaded_files.items():
        # 스키마에서 해당 파일 정의 찾기
        file_def = find_file_definition(file_schema, file_key)

        if not file_def:
            # 예상치 못한 파일
            errors.append(f"Unexpected file uploaded: {file_key}")
            continue

        # 2.1. 확장자 검증
        if 'validation' in file_def and 'extensions' in file_def['validation']:
            allowed_exts = file_def['validation']['extensions']
            filename = file_info['filename']
            ext = os.path.splitext(filename)[1].lower()

            if ext not in [e.lower() for e in allowed_exts]:
                errors.append(
                    f"Invalid file extension for '{file_def.get('name', file_key)}': "
                    f"{ext} (allowed: {', '.join(allowed_exts)})"
                )

        # 2.2. 파일 크기 검증
        if 'max_size' in file_def:
            max_size_str = file_def['max_size']
            try:
                max_size_bytes = parse_size_string(max_size_str)
                actual_size = file_info['size']

                if actual_size > max_size_bytes:
                    errors.append(
                        f"File too large: '{file_def.get('name', file_key)}' "
                        f"({actual_size / 1024 / 1024:.2f}MB, max: {max_size_str})"
                    )
            except Exception as e:
                logger.warning(f"Failed to parse max_size '{max_size_str}': {e}")

    return errors


def verify_script_file_mappings(script: str, uploaded_files: dict) -> list:
    """
    생성된 스크립트에 파일 환경 변수가 포함되었는지 검증 (Phase 8.2)

    Args:
        script: 생성된 Slurm 스크립트
        uploaded_files: {file_key: {path, filename, size}}

    Returns:
        list: 경고 목록 (빈 리스트면 모든 파일 매핑됨)
    """
    warnings = []

    for file_key in uploaded_files.keys():
        # 환경 변수 이름 (예: GEOMETRY_FILE, CONFIG_FILE)
        env_var = f"{file_key.upper()}_FILE"

        if env_var not in script:
            warnings.append(
                f"Warning: File '{file_key}' uploaded but environment variable "
                f"'{env_var}' not found in script. This file may not be used."
            )

    return warnings


def check_image_on_node(image_path, partition='compute'):
    """
    원격 노드에서 이미지 파일 존재 확인

    Args:
        image_path: 이미지 파일 경로
        partition: 파티션 (compute 또는 viz)

    Returns:
        bool: 파일 존재 여부
    """
    node = PARTITION_NODES.get(partition, 'node001')

    try:
        result = subprocess.run(
            [SSH, '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=no',
             node, f'test -f {image_path} && echo "exists"'],
            capture_output=True,
            text=True,
            timeout=5
        )
        return 'exists' in result.stdout
    except:
        return False


def load_template(template_id: str) -> dict:
    """Template YAML 로드"""
    for source, base_dir in TEMPLATE_DIRS.items():
        for root, dirs, files in os.walk(base_dir):
            for file in files:
                if file.endswith('.yaml') or file.endswith('.yml'):
                    filepath = os.path.join(root, file)
                    try:
                        with open(filepath, 'r') as f:
                            template = yaml.safe_load(f)
                            if template.get('template', {}).get('id') == template_id:
                                return template
                    except Exception as e:
                        logger.error(f"Failed to load template {filepath}: {e}")
                        continue

    raise FileNotFoundError(f"Template not found: {template_id}")


def get_apptainer_image(image_id: str) -> dict:
    """
    Apptainer 이미지 정보 조회 (DB 우선, 파일시스템 fallback)

    Note: Headnode에는 JSON 메타데이터만 있고, 실제 .sif 파일은 각 노드에 존재
    """
    # 1. DB에서 먼저 조회
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM apptainer_images WHERE (id = ? OR name LIKE ?) AND is_active = 1", (image_id, f"%{image_id}%"))
        row = cursor.fetchone()
        conn.close()

        if row:
            return {
                'id': row['id'],
                'name': row['name'],
                'path': row['path'],
                'partition': row['partition'],
                'metadata': json.loads(row['labels']) if row['labels'] else {}
            }
    except Exception as e:
        logger.warning(f"DB lookup failed for image {image_id}: {e}")

    # 2. 메타데이터 디렉토리에서 검색 (GlusterFS)
    if os.path.exists(APPTAINER_METADATA_DIR):
        try:
            for file in os.listdir(APPTAINER_METADATA_DIR):
                if file.endswith('.json') and not file.endswith('.commands.json'):
                    json_path = os.path.join(APPTAINER_METADATA_DIR, file)
                    try:
                        with open(json_path, 'r') as f:
                            metadata = json.load(f)
                            sif_name = metadata.get('name', file.replace('.sif.json', '.sif').replace('.json', '.sif'))
                            if image_id in sif_name or image_id in file:
                                runtime_path = os.getenv('APPTAINER_RUNTIME_PATH', '/opt/apptainers')
                                return {
                                    'id': image_id,
                                    'name': sif_name,
                                    'path': os.path.join(runtime_path, sif_name),
                                    'partition': metadata.get('partition', 'compute'),
                                    'metadata': metadata
                                }
                    except:
                        continue
        except Exception as e:
            logger.warning(f"Metadata dir scan failed: {e}")

    # 3. Fallback: 기존 방식 (하위 호환)
    for partition, image_dir in APPTAINER_DIRS.items():
        if not os.path.exists(image_dir):
            continue
        try:
            for file in os.listdir(image_dir):
                if file.endswith('.sif.json'):
                    json_path = os.path.join(image_dir, file)
                    try:
                        with open(json_path, 'r') as f:
                            metadata = json.load(f)
                            sif_name = file.replace('.sif.json', '.sif')
                            if image_id in sif_name:
                                return {
                                    'id': image_id,
                                    'name': sif_name,
                                    'path': os.path.join(image_dir, sif_name),
                                    'partition': partition,
                                    'metadata': metadata
                                }
                    except:
                        continue
        except:
            continue

    raise FileNotFoundError(f"Apptainer image not found: {image_id}")


def get_apptainer_image_by_name(image_name: str) -> dict:
    """
    Apptainer 이미지 정보 조회 (이름으로) - DB 우선, 파일시스템 fallback

    Note: Headnode에는 JSON 메타데이터만 있고, 실제 .sif 파일은 각 노드에 존재
          JSON 메타데이터를 확인하고, 실제 파일은 원격 노드에서 검증
    """
    # 1. DB에서 먼저 조회
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM apptainer_images WHERE (name = ? OR name LIKE ?) AND is_active = 1", (image_name, f"%{image_name}%"))
        row = cursor.fetchone()
        conn.close()

        if row:
            return {
                'id': row['id'],
                'name': row['name'],
                'path': row['path'],
                'partition': row['partition'],
                'metadata': json.loads(row['labels']) if row['labels'] else {}
            }
    except Exception as e:
        logger.warning(f"DB lookup failed for image name {image_name}: {e}")

    # 2. 메타데이터 디렉토리에서 검색 (GlusterFS)
    if os.path.exists(APPTAINER_METADATA_DIR):
        json_path = os.path.join(APPTAINER_METADATA_DIR, image_name + '.json')
        if not os.path.exists(json_path):
            json_path = os.path.join(APPTAINER_METADATA_DIR, image_name.replace('.sif', '') + '.sif.json')
        if os.path.exists(json_path):
            try:
                with open(json_path, 'r') as f:
                    metadata = json.load(f)
                    runtime_path = os.getenv('APPTAINER_RUNTIME_PATH', '/opt/apptainers')
                    return {
                        'id': image_name.replace('.sif', ''),
                        'name': image_name if image_name.endswith('.sif') else image_name + '.sif',
                        'path': os.path.join(runtime_path, image_name if image_name.endswith('.sif') else image_name + '.sif'),
                        'partition': metadata.get('partition', 'compute'),
                        'metadata': metadata
                    }
            except Exception as e:
                logger.warning(f"Metadata file read failed: {e}")

    # 3. Fallback: 기존 방식 (하위 호환)
    for partition, image_dir in APPTAINER_DIRS.items():
        image_path = os.path.join(image_dir, image_name)
        json_path = image_path + '.json'

        if os.path.exists(json_path):
            try:
                with open(json_path, 'r') as f:
                    metadata = json.load(f)
                    return {
                        'id': image_name.replace('.sif', ''),
                        'name': image_name,
                        'path': image_path,
                        'partition': partition,
                        'metadata': metadata
                    }
            except:
                pass

    raise FileNotFoundError(f"Apptainer image not found: {image_name}")


def save_uploaded_file(file, max_size_mb=1000) -> str:
    """
    업로드된 파일 저장 (보안 강화)

    Args:
        file: 업로드 파일
        max_size_mb: 최대 파일 크기 (MB)

    Returns:
        str: 저장된 파일 경로

    Raises:
        ValueError: 파일 크기 초과, 잘못된 파일명 등
    """
    # 1. 파일명 보안 검증
    if not file.filename:
        raise ValueError("Filename is empty")

    filename = secure_filename(file.filename)
    if not filename:
        raise ValueError("Invalid filename after sanitization")

    # 2. Path traversal 방지
    if '..' in filename or filename.startswith('/'):
        raise ValueError(f"Suspicious filename: {filename}")

    # 3. 파일 크기 제한 (스트림으로 체크)
    file.seek(0, os.SEEK_END)
    file_size = file.tell()
    file.seek(0)  # 다시 처음으로

    max_size_bytes = max_size_mb * 1024 * 1024
    if file_size > max_size_bytes:
        raise ValueError(f"File too large: {file_size / 1024 / 1024:.2f}MB (max: {max_size_mb}MB)")

    # 4. 안전한 경로 생성
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    temp_filename = f"{timestamp}_{filename}"
    temp_path = os.path.join(UPLOAD_DIR, temp_filename)

    # 5. Path traversal 최종 검증
    if not os.path.abspath(temp_path).startswith(os.path.abspath(UPLOAD_DIR)):
        raise ValueError("Path traversal detected")

    # 6. 파일 저장
    file.save(temp_path)

    # 7. 파일 권한 설정 (읽기 전용)
    os.chmod(temp_path, 0o644)

    return temp_path


def _sanitize_web_user(raw) -> str:
    """JWT 유래 사용자명을 결과 경로(/data/single/<user>)에 박기 전에 정제.
    허용: [A-Za-z0-9._-] 1~32자, 선행점/./.. 거부. 안전치 못하면 'anonymous'."""
    import re as _re
    if not raw or not isinstance(raw, str):
        return 'anonymous'
    if not _re.fullmatch(r'[A-Za-z0-9._-]{1,32}', raw):
        return 'anonymous'
    if raw in ('.', '..') or raw.startswith('.'):
        return 'anonymous'
    return raw


def _sbatch_account_qos_lines(web_role) -> str:
    """role 기반 #SBATCH --account/--qos 줄 생성 (권한모델 2차 방어).

    ★안전 게이트(기존동작 무중단)★:
      - env SBATCH_INJECT_ACCOUNT 가 'true' 일 때만 주입. 기본 'false' = 무주입.
        (association 이 아직 sacctmgr 에 없을 수 있어, 준비 전 sbatch 가
         'Invalid account' 로 실패하는 회귀를 막기 위한 글로벌 킬스위치.)
      - role 이 없거나 토큰이 불명확([A-Za-z0-9_-] 아님)이면 ★생략★(클러스터 기본).

    매핑(단순/명확):
      - account = role-<role>
      - qos     = ROLE_DEFINITIONS[role].allowed_qos[0] (단, '*' = 무제한이면 생략).
                  YAML 정의가 없으면 <role>_qos 폴백.
    role 이 명확할 때만 주입, 불명확하면 무주입 = 기존동작(클러스터 기본).
    """
    if os.getenv('SBATCH_INJECT_ACCOUNT', 'false').lower() != 'true':
        return ''

    role = web_role if isinstance(web_role, str) else ''
    # role 토큰이 명확할 때만(경로/계정명에 안전한 문자) 주입.
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,32}', role):
        return ''

    lines = f"#SBATCH --account=role-{role}\n"

    # qos: YAML roles.definitions[role].allowed_qos[0] 우선. '*'(무제한)는 특정 qos 가
    # 아니므로 생략하고 클러스터 기본 qos 사용. YAML 없으면 <role>_qos 폴백.
    role_def = ROLE_DEFINITIONS.get(role) or {}
    allowed_qos = role_def.get('allowed_qos') or []
    qos = None
    if allowed_qos:
        first = allowed_qos[0]
        if isinstance(first, str) and first and first != '*':
            qos = first
    else:
        qos = f"{role}_qos"

    if qos and re.fullmatch(r'[A-Za-z0-9_-]{1,32}', qos):
        lines += f"#SBATCH --qos={qos}\n"

    return lines


def generate_slurm_script(template: dict, job_config: dict) -> str:
    """
    Slurm 배치 스크립트 생성

    Args:
        template: Template YAML 데이터
        job_config: {
            'apptainer_image_path': '/opt/apptainers/KooSimulationPython313.sif',
            'uploaded_files': {
                'geometry': {'path': '/tmp/xxx.stl', 'filename': 'part.stl', 'size': 12345},
                'config': {'path': '/tmp/yyy.json', 'filename': 'config.json', 'size': 678}
            },
            'slurm_overrides': {'mem': '64G'},
            'job_name': 'my_simulation',
            'web_role': 'poweruser'  # role 기반 --account/--qos 주입(env SBATCH_INJECT_ACCOUNT=true 일 때만)
        }

    Returns:
        str: Slurm 배치 스크립트
    """
    # Slurm 설정
    slurm_config = template['slurm'].copy()
    slurm_config.update(job_config.get('slurm_overrides', {}))

    # ── 파티션 접근권한 검사 (role 기반, 최종 확정된 partition 기준) ──
    # submit_job 이 multipart/form-data 라 @partition_allowed 데코레이터는 body 의
    # partition 을 못 읽는다. partition 은 여기서 template+override 병합으로 확정되므로
    # 이 지점에서 검사한다(데코레이터/잡제출 공유 헬퍼 is_partition_allowed).
    # PARTITION_ENFORCE=false(기본)=shadow 로그만, true=PartitionNotAllowed→호출측 403.
    _web_role = job_config.get('web_role', 'user')
    _part = slurm_config.get('partition')
    _ok, _allowed = is_partition_allowed(_web_role, _part)
    if not _ok:
        logger.warning(
            f"[partition {'enforce' if PARTITION_ENFORCE else 'shadow'}] "
            f"{'DENY' if PARTITION_ENFORCE else 'DENY-WOULD-BE'} "
            f"role={_web_role} partition={_part} allowed={_allowed} job={job_config.get('job_name')}"
        )
        if PARTITION_ENFORCE:
            raise PartitionNotAllowed(_web_role, _part, _allowed)

    # Slurm 헤더 생성
    script = "#!/bin/bash\n"
    script += f"#SBATCH --job-name={job_config.get('job_name', template['template']['name'])}\n"
    # partition 이 비어있으면 클러스터 기본 파티션 사용 (#SBATCH 줄 생략).
    # 클러스터마다 파티션명이 다르므로(dev=normal, 운영=alpha 등) 템플릿이
    # 특정 이름을 박으면 다른 클러스터에서 sbatch 가 invalid partition 으로 실패한다.
    if slurm_config.get('partition'):
        script += f"#SBATCH --partition={slurm_config['partition']}\n"
    # role 기반 --account/--qos 주입 (권한모델 2차 방어; env SBATCH_INJECT_ACCOUNT 로 게이트).
    # role 불명확/플래그 off 면 빈 문자열 = 무주입(기존 동작 = 클러스터 기본).
    script += _sbatch_account_qos_lines(job_config.get('web_role'))
    script += f"#SBATCH --nodes={slurm_config['nodes']}\n"
    script += f"#SBATCH --ntasks={slurm_config['ntasks']}\n"

    if 'cpus_per_task' in slurm_config:
        script += f"#SBATCH --cpus-per-task={slurm_config['cpus_per_task']}\n"

    script += f"#SBATCH --mem={slurm_config.get('mem', slurm_config.get('memory', '16G'))}\n"
    script += f"#SBATCH --time={slurm_config['time']}\n"
    script += f"#SBATCH --output=/shared/logs/%j.out\n"
    script += f"#SBATCH --error=/shared/logs/%j.err\n\n"

    # 환경 변수 설정
    script += "# =============================================================================\n"
    script += "# 자동 생성된 환경 변수\n"
    script += "# =============================================================================\n\n"

    # Slurm 설정 변수
    script += "# --- Slurm 설정 변수 ---\n"
    script += f"export JOB_PARTITION=\"{slurm_config.get('partition', '')}\"\n"
    script += f"export JOB_NODES={slurm_config['nodes']}\n"
    script += f"export JOB_NTASKS={slurm_config['ntasks']}\n"
    script += f"export JOB_CPUS_PER_TASK={slurm_config.get('cpus_per_task', 1)}\n"
    script += f"export JOB_MEMORY=\"{slurm_config.get('mem', slurm_config.get('memory', '16G'))}\"\n"
    script += f"export JOB_TIME=\"{slurm_config['time']}\"\n\n"

    # Apptainer 이미지 (이미지가 있는 경우에만)
    if job_config.get('apptainer_image_path'):
        script += "# --- Apptainer 이미지 ---\n"
        script += f"export APPTAINER_IMAGE=\"{job_config['apptainer_image_path']}\"\n\n"

    # 작업 디렉토리
    # 스크래치(WORK_DIR)는 기존대로 /shared/jobs/<id>, 결과(RESULT_DIR)는
    # /data/single/<웹사용자>/<잡이름>_<id> — 개별 잡 결과를 웹사용자별 홈에 보관.
    web_user = _sanitize_web_user(job_config.get('web_user', 'anonymous'))
    safe_job = re.sub(r'[^A-Za-z0-9._-]', '_', str(job_config.get('job_name', 'job')))[:64]
    script += "# --- 작업 디렉토리 ---\n"
    script += f"export WEB_USER=\"{web_user}\"\n"
    script += "export SLURM_SUBMIT_DIR=/shared/jobs/$SLURM_JOB_ID\n"
    script += "export WORK_DIR=\"$SLURM_SUBMIT_DIR\"\n"
    script += f"export SINGLE_BASE=\"/data/single/{web_user}\"\n"
    script += f"export RESULT_DIR=\"$SINGLE_BASE/{safe_job}_$SLURM_JOB_ID\"\n\n"

    # Template의 추가 환경 변수
    apptainer_env = template.get('apptainer', {}).get('env', {})
    if apptainer_env:
        script += "# --- Apptainer 환경 변수 ---\n"
        for key, value in apptainer_env.items():
            script += f"export {key}=\"{value}\"\n"
        script += "\n"

    # 업로드된 파일 환경 변수 (file_key 기반)
    if job_config['uploaded_files']:
        script += "# --- 업로드된 파일 경로 (file_key 기반) ---\n"

        # file_key별로 파일 그룹핑
        file_groups = {}
        for file_key, file_info in job_config['uploaded_files'].items():
            # file_info가 리스트인 경우 (복수 파일)
            if isinstance(file_info, list):
                file_groups[file_key] = file_info
            else:
                # 단일 파일을 리스트로 변환
                file_groups[file_key] = [file_info]

        for file_key, files in file_groups.items():
            var_name = f"FILE_{file_key.upper()}"

            if len(files) == 1:
                # 단일 파일
                script += f"export {var_name}=\"$SLURM_SUBMIT_DIR/input/{files[0]['filename']}\"\n"
            else:
                # 복수 파일 - 공백으로 구분된 경로 리스트
                file_paths = " ".join([f"\"$SLURM_SUBMIT_DIR/input/{f['filename']}\"" for f in files])
                script += f"export {var_name}=({file_paths})\n"
                script += f"export {var_name}_COUNT={len(files)}\n"

        script += "\n"

    script += "# =============================================================================\n\n"

    # 작업 디렉토리 설정 및 파일 복사
    script += "# Setup work directory\n"
    script += "mkdir -p $SLURM_SUBMIT_DIR/input\n"
    script += "mkdir -p $SLURM_SUBMIT_DIR/work\n"
    script += "mkdir -p $SLURM_SUBMIT_DIR/output\n"
    script += "mkdir -p $RESULT_DIR\n"
    script += "cd $SLURM_SUBMIT_DIR\n\n"

    script += "# Copy input files\n"
    for file_key, file_info in job_config['uploaded_files'].items():
        # 복수 파일 지원
        if isinstance(file_info, list):
            for single_file in file_info:
                src = single_file['path']
                dst = f"$SLURM_SUBMIT_DIR/input/{single_file['filename']}"
                script += f"cp \"{src}\" \"{dst}\"\n"
        else:
            src = file_info['path']
            dst = f"$SLURM_SUBMIT_DIR/input/{file_info['filename']}"
            script += f"cp \"{src}\" \"{dst}\"\n"

    script += "\n"

    # Template 스크립트 삽입
    script += "# Pre-execution\n"
    script += template['script']['pre_exec'] + "\n\n"

    script += "# Main execution\n"
    script += template['script']['main_exec'] + "\n\n"

    script += "# Post-execution\n"
    script += template['script']['post_exec'] + "\n"

    return script


@job_submit_bp.route('/api/jobs/submit', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def submit_job():
    """
    Job 제출 (신규 Template 시스템) - JWT 인증 및 dashboard 권한 필요

    Request (multipart/form-data):
        - template_id: str
        - apptainer_image_id: str (선택적, template 설정에 따라)
        - file_<file_key>: File (예: file_geometry, file_config)
        - slurm_overrides: JSON string (선택적)
        - job_name: str

    Response:
        {
            "success": true,
            "job_id": "12345",
            "message": "Job submitted successfully",
            "request_id": "uuid"
        }
    """
    # Request ID 생성 (추적용)
    request_id = str(uuid.uuid4())
    start_time = datetime.now()

    log_info(request_id, 'job_submit_start', {
        'template_id': request.form.get('template_id'),
        'has_files': len(request.files) > 0
    })

    try:
        # 1. Template 로드
        template_id = request.form.get('template_id')
        if not template_id:
            log_error(request_id, ErrorCode.INVALID_REQUEST, 'template_id missing')
            return jsonify({
                'success': False,
                'error': 'template_id required',
                'error_code': ErrorCode.INVALID_REQUEST,
                'request_id': request_id
            }), 400

        log_info(request_id, 'template_load_start', {'template_id': template_id})

        try:
            template = load_template(template_id)
            log_info(request_id, 'template_loaded', {
                'template_name': template.get('template', {}).get('name'),
                'version': template.get('template', {}).get('version')
            })
        except FileNotFoundError as e:
            log_error(request_id, ErrorCode.TEMPLATE_NOT_FOUND, str(e), {
                'template_id': template_id
            })
            return jsonify({
                'success': False,
                'error': f'Template not found: {template_id}',
                'error_code': ErrorCode.TEMPLATE_NOT_FOUND,
                'request_id': request_id
            }), 404

        # 2. Template 검증
        log_info(request_id, 'template_validation_start')
        validator = TemplateValidator()
        valid, normalized_template, errors = validator.validate_and_normalize(template)

        if not valid:
            log_error(request_id, ErrorCode.TEMPLATE_VALIDATION_FAILED, 'Template validation failed', {
                'errors': errors
            })
            return jsonify({
                'success': False,
                'error': 'Template validation failed',
                'errors': errors,
                'error_code': ErrorCode.TEMPLATE_VALIDATION_FAILED,
                'request_id': request_id
            }), 400

        log_info(request_id, 'template_validated', {
            'apptainer_mode': normalized_template.get('apptainer_normalized', {}).get('mode')
        })

        apptainer_config = normalized_template['apptainer_normalized']

        # 3. Apptainer 이미지 결정
        image_required = apptainer_config.get('required', True)
        log_info(request_id, 'image_selection_start', {
            'user_selectable': apptainer_config['user_selectable'],
            'mode': apptainer_config['mode'],
            'required': image_required
        })

        image = None  # 이미지 없이 실행 가능한 경우를 위한 초기화

        try:
            if apptainer_config['user_selectable']:
                # 사용자가 선택한 이미지 사용
                image_id = request.form.get('apptainer_image_id')
                if not image_id:
                    # 이미지가 필수가 아니면 이미지 없이 진행
                    if not image_required:
                        log_info(request_id, 'image_skipped', {
                            'reason': 'Image not required and not provided'
                        })
                    else:
                        log_error(request_id, ErrorCode.IMAGE_REQUIRED, 'apptainer_image_id required')
                        return jsonify({
                            'success': False,
                            'error': 'apptainer_image_id required',
                            'error_code': ErrorCode.IMAGE_REQUIRED,
                            'request_id': request_id
                        }), 400
                else:
                    image = get_apptainer_image(image_id)
                    log_info(request_id, 'image_selected', {
                        'image_id': image_id,
                        'image_name': image.get('name')
                    })
            else:
                # Template에 고정된 이미지 사용
                image_name = apptainer_config.get('image_name')
                if image_name:
                    image = get_apptainer_image_by_name(image_name)
                    log_info(request_id, 'image_fixed', {
                        'image_name': image_name
                    })
                elif not image_required:
                    log_info(request_id, 'image_skipped', {
                        'reason': 'No image configured and not required'
                    })
                else:
                    raise FileNotFoundError("No apptainer image configured in template")
        except FileNotFoundError as e:
            # 이미지가 필수가 아니면 이미지 없이 진행
            if not image_required:
                log_info(request_id, 'image_skipped_after_error', {
                    'reason': str(e)
                })
                image = None
            else:
                log_error(request_id, ErrorCode.IMAGE_NOT_FOUND, str(e), {
                    'image_id': request.form.get('apptainer_image_id'),
                    'image_name': apptainer_config.get('image_name')
                })
                return jsonify({
                    'success': False,
                    'error': f'Apptainer image not found: {str(e)}',
                    'error_code': ErrorCode.IMAGE_NOT_FOUND,
                    'request_id': request_id
                }), 404

        # 4. 업로드된 파일 처리
        log_info(request_id, 'file_upload_start', {
            'file_count': len(request.files)
        })

        uploaded_files = {}
        for key in request.files:
            if key.startswith('file_'):
                file_key = key[5:]  # 'file_' 제거
                file = request.files[key]

                try:
                    temp_path = save_uploaded_file(file)
                    file_size = os.path.getsize(temp_path)
                    uploaded_files[file_key] = {
                        'path': temp_path,
                        'filename': file.filename,
                        'size': file_size
                    }
                    log_info(request_id, 'file_uploaded', {
                        'file_key': file_key,
                        'filename': file.filename,
                        'size': file_size
                    })
                except Exception as e:
                    log_error(request_id, ErrorCode.FILE_UPLOAD_FAILED, f'File upload failed: {file_key}', {
                        'file_key': file_key,
                        'filename': file.filename,
                        'error': str(e)
                    }, exc_info=True)
                    return jsonify({
                        'success': False,
                        'error': f'File upload failed: {file_key}',
                        'error_code': ErrorCode.FILE_UPLOAD_FAILED,
                        'request_id': request_id
                    }), 500

        # 5. 파일 스키마 검증 (엄격 모드)
        log_info(request_id, 'file_validation_start', {
            'uploaded_files': list(uploaded_files.keys())
        })

        errors = validate_file_schema_strict(normalized_template, uploaded_files)
        if errors:
            log_error(request_id, ErrorCode.FILE_VALIDATION_FAILED, 'File validation failed (strict mode)', {
                'errors': errors
            })
            return jsonify({
                'success': False,
                'error': 'File validation failed',
                'errors': errors,
                'error_code': ErrorCode.FILE_VALIDATION_FAILED,
                'request_id': request_id
            }), 400

        log_info(request_id, 'files_validated')

        # 6. Slurm 스크립트 생성
        # slurm_overrides 는 #SBATCH 라인에 그대로 보간되므로(nodes/mem/time/partition)
        # 객체·스칼라만 허용하고 개행/제어문자를 거부한다(헤더 주입 차단).
        try:
            slurm_overrides = json.loads(request.form.get('slurm_overrides', '{}'))
            if not isinstance(slurm_overrides, dict):
                raise ValueError('slurm_overrides must be a JSON object')
            for _k, _v in slurm_overrides.items():
                if isinstance(_v, (dict, list)) or (
                        isinstance(_v, str) and any(c in _v for c in '\n\r\x00')):
                    raise ValueError(f'invalid slurm_overrides value for {_k}')
        except (ValueError, TypeError) as e:
            return jsonify({
                'success': False,
                'error': f'Invalid slurm_overrides: {e}',
                'request_id': request_id
            }), 400

        # job_name 은 #SBATCH --job-name 과 스크립트 파일명(os.path.join)에 쓰이므로
        # 경로 구분자/셸 메타문자를 제거해 경로탈출·디렉티브 주입을 막는다.
        # \w(유니코드) 허용으로 한글 잡 이름은 보존, '/'·공백·개행 등은 '_' 치환.
        job_name_raw = request.form.get('job_name') or template['template']['name']
        job_name = re.sub(r'[^\w.\-]', '_', str(job_name_raw))[:64] or 'job'

        # 웹 로그인 사용자 — 결과를 /data/single/<web_user>/ 에 저장하기 위해
        # 스크립트 생성 '전에' 추출한다 (기존엔 제출 후에야 추출해 경로에 못 씀).
        # JWT sub(username). 경로에 박히므로 sanitize 필수.
        web_user = _sanitize_web_user(
            g.get('user', {}).get('username') or g.get('user', {}).get('id') or 'anonymous')

        # 웹 로그인 사용자의 role — #SBATCH --account/--qos 주입(권한모델 2차 방어)에 사용.
        # web_user 와 동일 패턴으로 g.user 에서 추출. 주입 게이트/검증은 generate_slurm_script 내부.
        web_role = g.get('user', {}).get('role', 'user')

        log_info(request_id, 'script_generation_start', {
            'job_name': job_name,
            'web_user': web_user,
            'web_role': web_role,
            'slurm_overrides': slurm_overrides
        })

        try:
            script = generate_slurm_script(
                template=normalized_template,
                job_config={
                    'apptainer_image_path': image['path'] if image else None,
                    'uploaded_files': uploaded_files,
                    'slurm_overrides': slurm_overrides,
                    'job_name': job_name,
                    'web_user': web_user,
                    'web_role': web_role
                }
            )
            log_info(request_id, 'script_generated', {
                'script_length': len(script)
            })

            # 6.5. 스크립트 파일 매핑 검증 (Phase 8.2)
            warnings = verify_script_file_mappings(script, uploaded_files)
            if warnings:
                log_info(request_id, 'script_file_mapping_warnings', {
                    'warnings': warnings
                })

        except PartitionNotAllowed as e:
            # 파티션 접근권한 위반 (PARTITION_ENFORCE=true 일 때만 발생) → 403
            return jsonify({
                'success': False,
                'error': 'partition not allowed for your role',
                'role': e.role,
                'partition': e.partition,
                'allowed_partitions': e.allowed,
                'request_id': request_id
            }), 403
        except Exception as e:
            log_error(request_id, ErrorCode.SLURM_SCRIPT_GENERATION_FAILED, 'Script generation failed', {
                'error': str(e)
            }, exc_info=True)
            return jsonify({
                'success': False,
                'error': f'Script generation failed: {str(e)}',
                'error_code': ErrorCode.SLURM_SCRIPT_GENERATION_FAILED,
                'request_id': request_id
            }), 500

        # 7. Slurm 스크립트 저장
        # 스크립트 저장 디렉토리 (영구 보관용) — /shared 우선, 없으면 /tmp 폴백
        SCRIPT_DIR = '/shared/slurm_scripts' if os.path.isdir('/shared') else '/tmp/slurm_scripts'
        try:
            os.makedirs(SCRIPT_DIR, exist_ok=True)
        except PermissionError:
            SCRIPT_DIR = '/tmp/slurm_scripts'
            os.makedirs(SCRIPT_DIR, exist_ok=True)

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        script_filename = f"job_{job_name}_{timestamp}.sh"
        script_path = os.path.join(SCRIPT_DIR, script_filename)

        with open(script_path, 'w') as f:
            f.write(script)
        os.chmod(script_path, 0o755)  # 실행 권한 부여

        log_info(request_id, 'script_saved', {
            'script_path': script_path
        })

        # 8. Slurm에 실제 제출 (Phase 2)
        log_info(request_id, 'sbatch_submit_start', {
            'script_path': script_path
        })

        try:
            result = subprocess.run(
                [SBATCH, script_path],
                capture_output=True,
                text=True,
                check=True,
                timeout=10  # 10초 타임아웃
            )

            # sbatch 출력 파싱 (예: "Submitted batch job 12345")
            output = result.stdout.strip()

            # Job ID 추출
            if 'Submitted batch job' in output:
                job_id = output.split()[-1]
            else:
                raise ValueError(f"Unexpected sbatch output: {output}")

            log_info(request_id, 'job_submitted', {
                'job_id': job_id,
                'sbatch_output': output
            })

        except subprocess.CalledProcessError as e:
            log_error(request_id, ErrorCode.SLURM_SUBMISSION_FAILED, 'sbatch failed', {
                'stderr': e.stderr,
                'returncode': e.returncode
            })
            return jsonify({
                'success': False,
                'error': f'Slurm submission failed: {e.stderr}',
                'error_code': ErrorCode.SLURM_SUBMISSION_FAILED,
                'request_id': request_id
            }), 500

        except subprocess.TimeoutExpired:
            log_error(request_id, ErrorCode.SLURM_TIMEOUT, 'sbatch timeout (10s)')
            return jsonify({
                'success': False,
                'error': 'Slurm submission timeout (10s)',
                'error_code': ErrorCode.SLURM_TIMEOUT,
                'request_id': request_id
            }), 500

        except Exception as e:
            log_error(request_id, ErrorCode.SLURM_SUBMISSION_FAILED, f'sbatch error: {str(e)}', exc_info=True)
            return jsonify({
                'success': False,
                'error': f'Slurm submission error: {str(e)}',
                'error_code': ErrorCode.SLURM_SUBMISSION_FAILED,
                'request_id': request_id
            }), 500

        # 9. DB에 Job 정보 저장 (Phase 3)
        log_info(request_id, 'db_record_start', {'job_id': job_id})

        try:
            # web_user 는 스크립트 생성 전에 이미 추출됨 (g.user 에 'id' 없음 — username 사용)
            user_id = web_user

            # Slurm 설정 재구성 (generate_slurm_script에서 생성된 것과 동일)
            slurm_config = normalized_template['slurm'].copy()
            slurm_config.update(slurm_overrides)

            # 결과 디렉토리 (스크립트의 RESULT_DIR 과 동일 규칙 — job_id 치환)
            safe_job = re.sub(r'[^A-Za-z0-9._-]', '_', str(job_name))[:64]
            result_dir = f"/data/single/{web_user}/{safe_job}_{job_id}"

            record_id = record_job_submission(
                job_id=job_id,
                job_name=job_name,
                template_id=template_id,
                template=normalized_template,
                user_id=user_id,
                slurm_config=slurm_config,
                apptainer_image=image['path'] if image else None,
                uploaded_files=uploaded_files,
                script_path=script_path,
                result_dir=result_dir
            )
            log_info(request_id, 'db_recorded', {
                'record_id': record_id,
                'job_id': job_id
            })
        except Exception as e:
            # DB 기록 실패해도 Job은 이미 제출되었으므로 성공 반환
            log_error(request_id, ErrorCode.DB_RECORD_FAILED, 'DB recording failed (job still submitted)', {
                'job_id': job_id,
                'error': str(e)
            }, exc_info=True)

        # 10. 성공 응답
        elapsed_time = (datetime.now() - start_time).total_seconds()
        log_info(request_id, 'job_submit_success', {
            'job_id': job_id,
            'elapsed_time': elapsed_time,
            'template_id': template_id,
            'job_name': job_name
        })

        return jsonify({
            'success': True,
            'job_id': job_id,
            'script_path': script_path,
            'message': f'Job {job_id} submitted successfully',
            'request_id': request_id,
            'elapsed_time': f'{elapsed_time:.2f}s'
        }), 201

    except FileNotFoundError as e:
        # 이미 로깅된 경우가 많으므로 간단히 처리
        return jsonify({
            'success': False,
            'error': str(e),
            'request_id': request_id
        }), 404

    except Exception as e:
        # 예상치 못한 에러
        log_error(request_id, ErrorCode.INTERNAL_ERROR, 'Unexpected error in job submission', {
            'error': str(e),
            'traceback': traceback.format_exc()
        }, exc_info=True)
        return jsonify({
            'success': False,
            'error': f'Internal server error: {str(e)}',
            'error_code': ErrorCode.INTERNAL_ERROR,
            'request_id': request_id
        }), 500


@job_submit_bp.route('/api/jobs/preview', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def preview_script():
    """
    스크립트 미리보기 (Phase 6.1) - JWT 인증 및 dashboard 권한 필요

    Job을 제출하지 않고 생성될 스크립트만 미리 확인

    Request (multipart/form-data):
        - template_id: str
        - apptainer_image_id: str (선택적)
        - slurm_overrides: JSON string (선택적)
        - job_name: str

    Response:
        {
            "success": true,
            "script": "생성된 스크립트 내용",
            "script_length": 1234,
            "estimated_cost": {...}
        }
    """
    request_id = str(uuid.uuid4())

    try:
        # 1. Template 로드
        template_id = request.form.get('template_id')
        if not template_id:
            return jsonify({
                'success': False,
                'error': 'template_id required',
                'request_id': request_id
            }), 400

        template = load_template(template_id)

        # 2. Template 검증
        validator = TemplateValidator()
        valid, normalized_template, errors = validator.validate_and_normalize(template)

        if not valid:
            return jsonify({
                'success': False,
                'error': 'Template validation failed',
                'errors': errors,
                'request_id': request_id
            }), 400

        apptainer_config = normalized_template['apptainer_normalized']
        image_required = apptainer_config.get('required', True)

        # 3. Apptainer 이미지 결정
        image = None
        try:
            if apptainer_config['user_selectable']:
                image_id = request.form.get('apptainer_image_id')
                if not image_id:
                    if image_required:
                        return jsonify({
                            'success': False,
                            'error': 'apptainer_image_id required',
                            'request_id': request_id
                        }), 400
                else:
                    image = get_apptainer_image(image_id)
            else:
                image_name = apptainer_config.get('image_name')
                if image_name:
                    image = get_apptainer_image_by_name(image_name)
                elif image_required:
                    raise FileNotFoundError("No apptainer image configured in template")
        except FileNotFoundError:
            if image_required:
                raise

        # 4. 스크립트 생성 (파일 업로드 없이)
        slurm_overrides = json.loads(request.form.get('slurm_overrides', '{}'))
        job_name = request.form.get('job_name', template['template']['name'])

        # 미리보기가 실제 제출 스크립트와 동일한 #SBATCH 를 보이도록 role 도 전달
        # (submit_job 과 동일 패턴). 주입 자체는 env SBATCH_INJECT_ACCOUNT 게이트.
        web_role = g.get('user', {}).get('role', 'user')

        script = generate_slurm_script(
            template=normalized_template,
            job_config={
                'apptainer_image_path': image['path'] if image else None,
                'uploaded_files': {},  # 미리보기에서는 파일 없음
                'slurm_overrides': slurm_overrides,
                'job_name': job_name,
                'web_role': web_role
            }
        )

        # 5. 비용 추정
        slurm_config = normalized_template['slurm'].copy()
        slurm_config.update(slurm_overrides)

        estimated_cost = estimate_job_cost(slurm_config)

        log_info(request_id, 'script_preview', {
            'template_id': template_id,
            'script_length': len(script)
        })

        return jsonify({
            'success': True,
            'script': script,
            'script_length': len(script),
            'estimated_cost': estimated_cost,
            'request_id': request_id
        }), 200

    except FileNotFoundError as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'request_id': request_id
        }), 404

    except PartitionNotAllowed as e:
        # 파티션 접근권한 위반 (PARTITION_ENFORCE=true 일 때만) → 403
        return jsonify({
            'success': False,
            'error': 'partition not allowed for your role',
            'role': e.role,
            'partition': e.partition,
            'allowed_partitions': e.allowed,
            'request_id': request_id
        }), 403

    except Exception as e:
        log_error(request_id, ErrorCode.INTERNAL_ERROR, 'Script preview failed', {
            'error': str(e)
        }, exc_info=True)
        return jsonify({
            'success': False,
            'error': f'Script preview failed: {str(e)}',
            'request_id': request_id
        }), 500


def estimate_job_cost(slurm_config: dict) -> dict:
    """
    Job 비용 추정 (Phase 6.2)

    간단한 비용 추정 모델 (실제 환경에 맞게 조정 필요)

    Args:
        slurm_config: Slurm 설정 (nodes, ntasks, time, mem 등)

    Returns:
        dict: 추정 비용 정보
    """
    # 시간 파싱 (HH:MM:SS → 초)
    time_str = slurm_config.get('time', '01:00:00')
    try:
        parts = time_str.split(':')
        if len(parts) == 3:
            hours, minutes, seconds = map(int, parts)
            total_seconds = hours * 3600 + minutes * 60 + seconds
        else:
            total_seconds = 3600  # 기본 1시간
    except:
        total_seconds = 3600

    # 리소스 계산
    nodes = int(slurm_config.get('nodes', 1))
    ntasks = int(slurm_config.get('ntasks', 1))

    # 메모리 파싱 (예: "16G" → 16384 MB)
    mem_str = slurm_config.get('mem', slurm_config.get('memory', '1G'))
    try:
        if 'G' in mem_str.upper():
            mem_gb = float(mem_str.upper().replace('G', ''))
        elif 'M' in mem_str.upper():
            mem_gb = float(mem_str.upper().replace('M', '')) / 1024
        else:
            mem_gb = 1.0
    except:
        mem_gb = 1.0

    # 간단한 비용 모델 (예시, 실제 환경에 맞게 조정)
    # 가정: 노드당 시간당 $0.50, 메모리 GB당 시간당 $0.01
    cost_per_node_hour = 0.50
    cost_per_gb_hour = 0.01

    hours = total_seconds / 3600
    node_cost = nodes * cost_per_node_hour * hours
    memory_cost = mem_gb * cost_per_gb_hour * hours
    total_cost = node_cost + memory_cost

    return {
        'total_cost_usd': round(total_cost, 2),
        'breakdown': {
            'node_cost': round(node_cost, 2),
            'memory_cost': round(memory_cost, 2)
        },
        'resources': {
            'nodes': nodes,
            'ntasks': ntasks,
            'memory_gb': round(mem_gb, 2),
            'time_hours': round(hours, 2)
        },
        'note': 'Estimated cost - actual cost may vary'
    }


# Health check
@job_submit_bp.route('/api/jobs/submit/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'job_submit_api',
        'timestamp': datetime.now().isoformat()
    })
