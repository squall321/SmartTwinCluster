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
import json
import tempfile
import sqlite3
from datetime import datetime
from pathlib import Path

# Blueprint setup
lsdyna_submit_bp = Blueprint('lsdyna_submit', __name__, url_prefix='/api/slurm')

# Database path
DB_PATH = Path(__file__).parent / 'database' / 'dashboard.db'

def get_db_connection():
    """Get SQLite database connection"""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def get_apptainer_image_by_id(image_id: str):
    """Get Apptainer image from database"""
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM apptainer_images WHERE id = ?", (image_id,))
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
        # Check if running in mock mode
        mock_mode = os.getenv('MOCK_MODE', 'true').lower() == 'true'

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

            # Save uploaded file temporarily
            temp_dir = '/tmp/lsdyna_uploads'
            os.makedirs(temp_dir, exist_ok=True)

            temp_path = os.path.join(temp_dir, f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{file.filename}")
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
                cursor.execute("SELECT * FROM apptainer_images WHERE name LIKE ?", (f"%{image_id}%",))
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
                            'partition': 'group6',  # Default partition
                            'nodes': 1,
                            'cores': meta.get('cores', 32),
                            'memory': f"{meta.get('cores', 32) * 2}G",  # 2GB per core
                            'time': '24:00:00',
                            'qos': 'group6_qos',
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

    lines.append('#!/bin/bash')
    lines.append('')
    lines.append('# Traditional LS-DYNA submission (no template)')
    lines.append(f"#SBATCH --job-name={meta.get('filename', 'lsdyna_job')}")
    lines.append(f"#SBATCH --partition=group6")
    lines.append(f"#SBATCH --nodes=1")
    lines.append(f"#SBATCH --ntasks={meta.get('cores', 16)}")
    lines.append(f"#SBATCH --mem={meta.get('cores', 16) * 2}G")
    lines.append(f"#SBATCH --time=24:00:00")
    lines.append('#SBATCH --output=/shared/logs/%j.out')
    lines.append('#SBATCH --error=/shared/logs/%j.err')
    lines.append('')

    lines.append('# Environment')
    lines.append(f"export K_FILE=\"{k_file_path}\"")
    lines.append(f"export CORES={meta.get('cores', 16)}")
    lines.append(f"export MODE={meta.get('mode', 'MPP')}")
    lines.append(f"export VERSION={meta.get('version', 'R15')}")
    lines.append(f"export PRECISION={meta.get('precision', 'single')}")
    lines.append('')

    lines.append('# Execute LS-DYNA')
    lines.append('echo "Starting LS-DYNA job..."')
    lines.append('echo "K-file: $K_FILE"')
    lines.append('echo "Cores: $CORES"')
    lines.append('echo "Mode: $MODE"')
    lines.append('')

    # Add actual LS-DYNA execution command here
    lines.append('# TODO: Add actual LS-DYNA command')
    lines.append('# mpirun -np $CORES lsdyna i=$K_FILE ...')
    lines.append('')

    lines.append('echo "Job completed"')

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
