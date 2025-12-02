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
import json
import logging
import tempfile
import yaml
import subprocess
from datetime import datetime
from flask import Blueprint, request, jsonify
from werkzeug.utils import secure_filename
from template_validator import TemplateValidator

logger = logging.getLogger(__name__)

job_submit_bp = Blueprint('job_submit', __name__)

# Template 디렉토리
TEMPLATE_DIRS = {
    'official': '/shared/templates/official',
    'user': '/shared/templates/user',
}

# Apptainer 이미지 디렉토리
APPTAINER_DIRS = {
    'compute': '/opt/apptainers',
    'viz': '/opt/apptainers',
}

# 업로드 임시 디렉토리
UPLOAD_DIR = '/tmp/slurm_uploads'
os.makedirs(UPLOAD_DIR, exist_ok=True)

# 파티션별 대표 노드 (이미지 파일 존재 확인용)
PARTITION_NODES = {
    'compute': 'node001',  # Compute 노드 중 첫 번째
    'viz': 'viz-node001',   # Viz 노드
}


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
            ['ssh', '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=no',
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
    Apptainer 이미지 정보 조회

    Note: Headnode에는 JSON 메타데이터만 있고, 실제 .sif 파일은 각 노드에 존재
    """
    # JSON 메타데이터 또는 파일명 패턴으로 찾기
    for partition, image_dir in APPTAINER_DIRS.items():
        # JSON 메타데이터 먼저 확인
        for file in os.listdir(image_dir):
            if file.endswith('.sif.json'):
                json_path = os.path.join(image_dir, file)
                try:
                    with open(json_path, 'r') as f:
                        metadata = json.load(f)
                        # filename에서 .sif.json 제거
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

    raise FileNotFoundError(f"Apptainer image not found: {image_id}")


def get_apptainer_image_by_name(image_name: str) -> dict:
    """
    Apptainer 이미지 정보 조회 (이름으로)

    Note: Headnode에는 JSON 메타데이터만 있고, 실제 .sif 파일은 각 노드에 존재
          JSON 메타데이터를 확인하고, 실제 파일은 원격 노드에서 검증
    """
    for partition, image_dir in APPTAINER_DIRS.items():
        image_path = os.path.join(image_dir, image_name)
        json_path = image_path + '.json'

        # JSON 메타데이터 존재 확인 (headnode)
        if os.path.exists(json_path):
            # 실제 .sif 파일은 원격 노드에서 확인 (선택사항)
            # 여기서는 JSON이 있으면 파일도 있다고 가정
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


def save_uploaded_file(file) -> str:
    """업로드된 파일 저장"""
    filename = secure_filename(file.filename)
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    temp_filename = f"{timestamp}_{filename}"
    temp_path = os.path.join(UPLOAD_DIR, temp_filename)

    file.save(temp_path)
    return temp_path


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
            'job_name': 'my_simulation'
        }

    Returns:
        str: Slurm 배치 스크립트
    """
    # Slurm 설정
    slurm_config = template['slurm'].copy()
    slurm_config.update(job_config.get('slurm_overrides', {}))

    # Slurm 헤더 생성
    script = "#!/bin/bash\n"
    script += f"#SBATCH --job-name={job_config.get('job_name', template['template']['name'])}\n"
    script += f"#SBATCH --partition={slurm_config['partition']}\n"
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
    script += f"export JOB_PARTITION=\"{slurm_config['partition']}\"\n"
    script += f"export JOB_NODES={slurm_config['nodes']}\n"
    script += f"export JOB_NTASKS={slurm_config['ntasks']}\n"
    script += f"export JOB_CPUS_PER_TASK={slurm_config.get('cpus_per_task', 1)}\n"
    script += f"export JOB_MEMORY=\"{slurm_config.get('mem', slurm_config.get('memory', '16G'))}\"\n"
    script += f"export JOB_TIME=\"{slurm_config['time']}\"\n\n"

    # Apptainer 이미지
    script += "# --- Apptainer 이미지 ---\n"
    script += f"export APPTAINER_IMAGE=\"{job_config['apptainer_image_path']}\"\n\n"

    # 작업 디렉토리
    script += "# --- 작업 디렉토리 ---\n"
    script += "export SLURM_SUBMIT_DIR=/shared/jobs/$SLURM_JOB_ID\n"
    script += "export WORK_DIR=\"$SLURM_SUBMIT_DIR\"\n"
    script += "export RESULT_DIR=\"$WORK_DIR/results\"\n\n"

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
def submit_job():
    """
    Job 제출 (신규 Template 시스템)

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
            "message": "Job submitted successfully"
        }
    """
    try:
        # 1. Template 로드
        template_id = request.form.get('template_id')
        if not template_id:
            return jsonify({'success': False, 'error': 'template_id required'}), 400

        template = load_template(template_id)

        # 2. Template 검증
        validator = TemplateValidator()
        valid, normalized_template, errors = validator.validate_and_normalize(template)

        if not valid:
            return jsonify({
                'success': False,
                'error': 'Template validation failed',
                'errors': errors
            }), 400

        apptainer_config = normalized_template['apptainer_normalized']

        # 3. Apptainer 이미지 결정
        if apptainer_config['user_selectable']:
            # 사용자가 선택한 이미지 사용
            image_id = request.form.get('apptainer_image_id')
            if not image_id:
                return jsonify({'success': False, 'error': 'apptainer_image_id required'}), 400

            image = get_apptainer_image(image_id)
        else:
            # Template에 고정된 이미지 사용
            image = get_apptainer_image_by_name(apptainer_config['image_name'])

        # 4. 업로드된 파일 처리
        uploaded_files = {}
        for key in request.files:
            if key.startswith('file_'):
                file_key = key[5:]  # 'file_' 제거
                file = request.files[key]

                temp_path = save_uploaded_file(file)
                uploaded_files[file_key] = {
                    'path': temp_path,
                    'filename': file.filename,
                    'size': os.path.getsize(temp_path)
                }

        # 5. 파일 스키마 검증
        errors = validator.validate_file_schema(normalized_template, uploaded_files)
        if errors:
            return jsonify({
                'success': False,
                'error': 'File validation failed',
                'errors': errors
            }), 400

        # 6. Slurm 스크립트 생성
        slurm_overrides = json.loads(request.form.get('slurm_overrides', '{}'))
        job_name = request.form.get('job_name', template['template']['name'])

        script = generate_slurm_script(
            template=normalized_template,
            job_config={
                'apptainer_image_path': image['path'],
                'uploaded_files': uploaded_files,
                'slurm_overrides': slurm_overrides,
                'job_name': job_name
            }
        )

        # 7. Slurm에 제출
        # TODO: 실제 sbatch 실행
        script_path = os.path.join(UPLOAD_DIR, f"job_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sh")
        with open(script_path, 'w') as f:
            f.write(script)

        logger.info(f"Slurm script generated: {script_path}")

        # Mock Job ID (실제로는 sbatch 결과)
        job_id = f"mock_{datetime.now().strftime('%Y%m%d%H%M%S')}"

        # 8. DB에 Job 정보 저장
        # TODO: DB 저장 로직 추가

        return jsonify({
            'success': True,
            'job_id': job_id,
            'message': 'Job submitted successfully',
            'script_path': script_path  # 디버깅용
        }), 201

    except FileNotFoundError as e:
        logger.error(f"Resource not found: {e}")
        return jsonify({'success': False, 'error': str(e)}), 404

    except Exception as e:
        logger.error(f"Job submit failed: {e}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500


# Health check
@job_submit_bp.route('/api/jobs/submit/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'job_submit_api',
        'timestamp': datetime.now().isoformat()
    })
