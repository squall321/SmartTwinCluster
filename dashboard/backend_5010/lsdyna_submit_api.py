"""
LS-DYNA Job Submission API with Apptainer Template Integration

통합 기능:
- 기존 LS-DYNA K 파일 업로드 제출
- Apptainer 명령어 템플릿 기반 제출
- 변수 치환 및 스크립트 자동 생성
- Pre/Post 명령어 실행
"""

from flask import Blueprint, request, jsonify
import os
import re
import json
import tempfile
import sqlite3
from datetime import datetime
from pathlib import Path
from middleware.jwt_middleware import jwt_required, permission_required

# Blueprint setup
lsdyna_submit_bp = Blueprint('lsdyna_submit', __name__, url_prefix='/api/slurm')

# Database path — job_submit_api 와 동일한 DATABASE_PATH 환경변수 사용(DB split-brain 해소)
DB_PATH = Path(os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db'))

def get_db_connection():
    """Get SQLite database connection"""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def get_apptainer_image_by_id(image_id: str):
    """Get Apptainer image from database"""
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM apptainer_images WHERE id = ? AND is_active = 1", (image_id,))
    row = cursor.fetchone()
    conn.close()

    if not row:
        return None

    image = dict(row)

    # Parse command_templates if exists
    if image.get('command_templates'):
        try:
            image['command_templates'] = json.loads(image['command_templates'])
        except:
            image['command_templates'] = []

    return image


def find_command_template(image, template_id):
    """Find command template in image"""
    if not image.get('command_templates'):
        return None

    for template in image['command_templates']:
        if template.get('template_id') == template_id:
            return template

    return None


def resolve_dynamic_variable(source: str, value: any, transform: str = None):
    """Resolve dynamic variable with optional transform"""
    # Transform functions
    transforms = {
        'memory_to_kb': lambda x: memory_to_kb(x),
        'time_to_seconds': lambda x: time_to_seconds(x),
        'basename': lambda x: os.path.basename(x),
        'dirname': lambda x: os.path.dirname(x),
    }

    if transform and transform in transforms:
        return transforms[transform](value)

    return value


def memory_to_kb(memory_str: str) -> int:
    """Convert memory string to KB"""
    import re
    match = re.match(r'^(\d+(?:\.\d+)?)\s*([KMGT])?B?$', memory_str, re.IGNORECASE)

    if not match:
        raise ValueError(f"Invalid memory format: {memory_str}")

    value = float(match.group(1))
    unit = (match.group(2) or 'K').upper()

    multipliers = {'K': 1, 'M': 1024, 'G': 1024 * 1024, 'T': 1024 * 1024 * 1024}

    return int(value * multipliers[unit])


def time_to_seconds(time_str: str) -> int:
    """Convert time string to seconds"""
    import re

    # Format: DD-HH:MM:SS
    day_match = re.match(r'^(\d+)-(\d+):(\d+):(\d+)$', time_str)
    if day_match:
        days, hours, minutes, seconds = map(int, day_match.groups())
        return days * 86400 + hours * 3600 + minutes * 60 + seconds

    # Format: HH:MM:SS or MM:SS
    parts = time_str.split(':')
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    elif len(parts) == 2:
        return int(parts[0]) * 60 + int(parts[1])
    elif len(parts) == 1:
        return int(parts[0])

    raise ValueError(f"Invalid time format: {time_str}")


def build_variable_map(template, slurm_config, input_files, custom_values=None):
    """Build variable map from template and context"""
    variables = {}

    # 1. Add dynamic variables (from Slurm config)
    if template.get('variables', {}).get('dynamic'):
        for var_name, var_def in template['variables']['dynamic'].items():
            source = var_def.get('source', '')

            if source.startswith('slurm.'):
                field = source[6:]  # Remove 'slurm.' prefix

                # Map field names
                field_map = {
                    'ntasks': 'cores',  # Frontend uses 'cores'
                    'mem': 'memory',
                }

                field = field_map.get(field, field)

                if field in slurm_config:
                    value = slurm_config[field]
                    transform = var_def.get('transform')
                    variables[var_name] = resolve_dynamic_variable(source, value, transform)

    # 2. Add input file variables
    if template.get('variables', {}).get('input_files'):
        for var_name, var_def in template['variables']['input_files'].items():
            file_key = var_def.get('file_key')
            if file_key and file_key in input_files:
                variables[var_name] = input_files[file_key]

    # 3. Add computed variables
    if template.get('variables', {}).get('computed'):
        for var_name, var_def in template['variables']['computed'].items():
            source_var = var_def.get('source')
            transform = var_def.get('transform')

            if source_var in variables:
                variables[var_name] = resolve_dynamic_variable('', variables[source_var], transform)

    # 4. Add custom values
    if custom_values:
        variables.update(custom_values)

    return variables


def substitute_variables(text: str, variables: dict) -> str:
    """Substitute ${VAR} placeholders with actual values"""
    import re

    def replacer(match):
        var_name = match.group(1)
        if var_name in variables:
            return str(variables[var_name])
        else:
            print(f"Warning: Variable {var_name} not found, keeping placeholder")
            return match.group(0)

    return re.sub(r'\$\{([A-Z_][A-Z0-9_]*)\}', replacer, text)


def generate_script_from_template(template, image, slurm_config, input_files, custom_values=None):
    """Generate Slurm script from command template"""

    # Build variable map
    variables = build_variable_map(template, slurm_config, input_files, custom_values)

    # Add apptainer image path
    variables['APPTAINER_IMAGE'] = image['path']

    lines = []

    # Shebang
    lines.append('#!/bin/bash')
    lines.append('')

    # Slurm directives
    lines.append('# Slurm Job Configuration')
    lines.append(f"#SBATCH --job-name={slurm_config.get('jobName', template.get('display_name', 'lsdyna_job'))}")

    if slurm_config.get('partition'):
        lines.append(f"#SBATCH --partition={slurm_config['partition']}")

    if slurm_config.get('nodes'):
        lines.append(f"#SBATCH --nodes={slurm_config['nodes']}")

    if slurm_config.get('cores') or slurm_config.get('ntasks'):
        ntasks = slurm_config.get('cores') or slurm_config.get('ntasks')
        lines.append(f"#SBATCH --ntasks={ntasks}")

    if slurm_config.get('memory'):
        lines.append(f"#SBATCH --mem={slurm_config['memory']}")

    if slurm_config.get('time'):
        lines.append(f"#SBATCH --time={slurm_config['time']}")

    if slurm_config.get('qos'):
        lines.append(f"#SBATCH --qos={slurm_config['qos']}")

    lines.append('#SBATCH --output=/shared/logs/%j.out')
    lines.append('#SBATCH --error=/shared/logs/%j.err')
    lines.append('')

    # Environment variables
    lines.append('# Environment Variables')
    for var_name, var_value in variables.items():
        lines.append(f'export {var_name}="{var_value}"')
    lines.append('')

    # Pre-commands
    if template.get('pre_commands'):
        lines.append('# Pre-execution commands')
        for cmd in template['pre_commands']:
            lines.append(substitute_variables(cmd, variables))
        lines.append('')

    # Main command
    lines.append('# Main command')
    main_command = substitute_variables(template['command']['format'], variables)
    lines.append(main_command)
    lines.append('')

    # Post-commands
    if template.get('post_commands'):
        lines.append('# Post-execution commands')
        for cmd in template['post_commands']:
            lines.append(substitute_variables(cmd, variables))
        lines.append('')

    return '\n'.join(lines)


@lsdyna_submit_bp.route('/submit-lsdyna-jobs', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def submit_lsdyna_jobs():
    """
    LS-DYNA 작업 제출 (템플릿 통합)

    Request (multipart/form-data):
        - files: List of K files
        - meta[i]: JSON string with job config for each file
          {
              "filename": "job.k",
              "cores": 32,
              "precision": "single",
              "version": "R15",
              "mode": "MPP",
              "template_id": "lsdyna_mpp_solver",  # Optional
              "image_path": "/path/to/image.sif"    # Optional
          }

    Response:
        {
            "success": true,
            "submitted": [
                {
                    "filename": "job.k",
                    "job_id": "12345",
                    "script_path": "/tmp/job_12345.sh"
                }
            ]
        }
    """
    try:
        # Check if running in mock mode (기본 false — env 로 명시할 때만 mock,
        # 미설정 시 운영에서 실제 sbatch 제출되게)
        mock_mode = os.getenv('MOCK_MODE', 'false').lower() == 'true'

        submitted_jobs = []

        # Get uploaded files
        files = request.files.getlist('files')

        if not files:
            return jsonify({
                'success': False,
                'error': 'No files uploaded'
            }), 400

        # Process each file
        for i, file in enumerate(files):
            # Get metadata for this file
            meta_key = f'meta[{i}]'
            if meta_key not in request.form:
                continue

            meta = json.loads(request.form[meta_key])

            # 업로드 k파일 저장 — 공유 스토리지에 둬야 compute 노드가 읽는다(/tmp 는 노드로컬).
            temp_dir = '/shared/lsdyna_uploads' if os.path.isdir('/shared') else '/tmp/lsdyna_uploads'
            os.makedirs(temp_dir, exist_ok=True)
            if os.path.isdir('/shared'):
                os.makedirs('/shared/logs', exist_ok=True)  # #SBATCH --output 대상

            # 파일명 위생: basename + 경로구분자 제거(경로탈출 차단), \w 로 한글 보존.
            safe_name = re.sub(r'[^\w.\-]', '_', os.path.basename(str(file.filename or '')))[:128] or f'input_{i}.k'
            temp_path = os.path.join(temp_dir, f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{i}_{safe_name}")
            file.save(temp_path)

            # Check if using template
            template_id = meta.get('template_id')
            image_path = meta.get('image_path')

            if template_id and image_path:
                # Template-based submission
                print(f"📋 Using template: {template_id}")

                # Get image from database
                # Extract image ID from path
                image_id = os.path.basename(image_path).replace('.sif', '')

                conn = get_db_connection()
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM apptainer_images WHERE name LIKE ? AND is_active = 1", (f"%{image_id}%",))
                image_row = cursor.fetchone()
                conn.close()

                if image_row:
                    image = dict(image_row)

                    # Parse command_templates
                    if image.get('command_templates'):
                        try:
                            image['command_templates'] = json.loads(image['command_templates'])
                        except:
                            image['command_templates'] = []

                    # Find template
                    template = find_command_template(image, template_id)

                    if template:
                        # Generate script from template
                        slurm_config = {
                            'jobName': meta.get('filename', 'lsdyna_job'),
                            # partition/qos 는 meta 로만 — 비면 #SBATCH 줄 생략(클러스터 기본).
                            # 특정 이름 하드코딩 시 다른 클러스터에서 invalid partition 으로 실패.
                            'partition': meta.get('partition'),
                            'nodes': 1,
                            'cores': meta.get('cores', 32),
                            'memory': f"{meta.get('cores', 32) * 2}G",  # 2GB per core
                            'time': '24:00:00',
                            'qos': meta.get('qos'),
                        }

                        input_files = {
                            'k_file': temp_path,
                        }

                        script_content = generate_script_from_template(
                            template, image, slurm_config, input_files
                        )

                        print(f"✅ Generated script from template: {template_id}")
                    else:
                        # Template not found, fall back to traditional method
                        print(f"⚠️  Template {template_id} not found, using traditional method")
                        script_content = generate_traditional_script(meta, temp_path)
                else:
                    # Image not found
                    print(f"⚠️  Image not found, using traditional method")
                    script_content = generate_traditional_script(meta, temp_path)
            else:
                # Traditional submission (no template)
                script_content = generate_traditional_script(meta, temp_path)

            # Save script
            script_path = os.path.join(temp_dir, f"job_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{i}.sh")
            with open(script_path, 'w') as f:
                f.write(script_content)

            os.chmod(script_path, 0o755)

            if mock_mode:
                # Mock submission
                job_id = f"mock_{datetime.now().strftime('%Y%m%d%H%M%S')}_{i}"
                print(f"🎭 Mock mode: Would submit {script_path}")
            else:
                # Real submission
                from slurm_commands import SBATCH, run_slurm_command
                result = run_slurm_command([SBATCH, script_path], timeout=10)
                job_id = result.stdout.strip().split()[-1]
                print(f"✅ Job {job_id} submitted: {meta['filename']}")

            submitted_jobs.append({
                'filename': meta['filename'],
                'job_id': job_id,
                'script_path': script_path,
                'used_template': bool(template_id),
            })

        return jsonify({
            'success': True,
            'submitted': submitted_jobs,
            'count': len(submitted_jobs),
        }), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def generate_traditional_script(meta, k_file_path):
    """Generate traditional LS-DYNA script without template"""
    lines = []

    # 잡 이름/코어수 위생 — #SBATCH 라인 주입 차단.
    safe_job = re.sub(r'[^\w.\-]', '_', str(meta.get('filename', 'lsdyna_job')))[:64] or 'lsdyna_job'
    try:
        cores = int(meta.get('cores', 16) or 16)
    except (ValueError, TypeError):
        cores = 16

    lines.append('#!/bin/bash')
    lines.append('')
    lines.append('# Traditional LS-DYNA submission (no template)')
    lines.append(f"#SBATCH --job-name={safe_job}")
    # partition 은 meta 가 줄 때만 — 비면 #SBATCH 줄 생략(클러스터 기본 사용).
    # 하드코딩(예: group6)하면 그 파티션이 없는 클러스터에서 sbatch 가 invalid partition 으로 실패.
    if meta.get('partition'):
        lines.append(f"#SBATCH --partition={meta['partition']}")
    lines.append("#SBATCH --nodes=1")
    lines.append(f"#SBATCH --ntasks={cores}")
    lines.append(f"#SBATCH --mem={cores * 2}G")
    lines.append("#SBATCH --time=24:00:00")
    lines.append('#SBATCH --output=/shared/logs/%j.out')
    lines.append('#SBATCH --error=/shared/logs/%j.err')
    lines.append('')

    lines.append('# Environment')
    lines.append(f'export K_FILE="{k_file_path}"')
    lines.append(f'export NPROCS={cores}')
    lines.append(f"export MODE={meta.get('mode', 'MPP')}")
    lines.append(f"export VERSION={meta.get('version', 'R13.1.0')}")
    lines.append(f"export PRECISION={meta.get('precision', 'single')}")
    lines.append('export MEMORY=64000000  # LS-DYNA solver memory (words)')
    lines.append('')

    lines.append('echo "========================================"')
    lines.append('echo "LS-DYNA Job ($MODE / $VERSION)"')
    lines.append('echo "K-file : $K_FILE"')
    lines.append('echo "Cores  : $NPROCS"')
    lines.append('echo "========================================"')
    lines.append('')
    lines.append('if [ ! -f "$K_FILE" ]; then')
    lines.append('    echo "Error: K file not found: $K_FILE"')
    lines.append('    exit 1')
    lines.append('fi')
    lines.append('')
    lines.append('# 결과는 k파일 옆 output/ 에 — 업로드 공유경로 하위라 노드 간 접근 가능')
    lines.append('OUTPUT_DIR="$(dirname "$K_FILE")/output"')
    lines.append('mkdir -p "$OUTPUT_DIR"')
    lines.append('cd "$OUTPUT_DIR"')
    lines.append('')
    lines.append('# LS-DYNA 모듈 로드(클러스터 환경에 맞게 조정). 없으면 통과.')
    lines.append('module load lsdyna/$VERSION 2>/dev/null || module load lsdyna/R13.1.0 2>/dev/null || true')
    lines.append('')
    lines.append('echo "Running LS-DYNA MPP solver..."')
    lines.append('mpirun -np $NPROCS ls-dyna_mpp I="$K_FILE" MEMORY=$MEMORY NCPU=$NPROCS')
    lines.append('EXIT_CODE=$?')
    lines.append('')
    lines.append('echo "Exit Code: $EXIT_CODE"')
    lines.append('ls -lh "$OUTPUT_DIR" 2>/dev/null || true')
    lines.append('echo "Job completed"')
    lines.append('exit $EXIT_CODE')

    return '\n'.join(lines)


# Health check
@lsdyna_submit_bp.route('/submit-lsdyna-jobs/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'lsdyna_submit_api',
        'timestamp': datetime.now().isoformat()
    })


def register_blueprint(app):
    """Register blueprint with Flask app"""
    app.register_blueprint(lsdyna_submit_bp)
