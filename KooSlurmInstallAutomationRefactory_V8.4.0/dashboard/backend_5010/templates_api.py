"""
Job Templates API
작업 템플릿 생성, 조회, 수정, 삭제
"""

from flask import Blueprint, request, jsonify
from datetime import datetime
import os
import json
import uuid

# Database 함수 임포트
from database import get_db_connection

templates_bp = Blueprint('templates', __name__, url_prefix='/api/jobs/templates')

# Mock 모드 체크 함수 (매번 환경변수 확인)
def is_mock_mode():
    """현재 MOCK_MODE 환경변수 확인"""
    return os.getenv('MOCK_MODE', 'true').lower() == 'true'

# ============================================
# GET /api/jobs/templates
# 템플릿 목록 조회
# ============================================
@templates_bp.route('', methods=['GET'])
def get_templates():
    """
    템플릿 목록 조회
    Query params:
        - category: ml | simulation | data | custom | all (default: all)
        - shared: true | false (optional)
        - search: 검색어 (optional)
    """
    try:
        category = request.args.get('category', 'all')
        shared = request.args.get('shared')
        search = request.args.get('search', '').strip()
        
        if is_mock_mode():
            # Mock 데이터 - 다양한 샘플 템플릿
            mock_templates = [
                {
                    'id': 'tpl-001',
                    'name': 'PyTorch Training',
                    'description': 'Standard PyTorch model training job',
                    'category': 'ml',
                    'shared': True,
                    'config': {
                        'partition': 'group1',
                        'nodes': 1,
                        'cpus': 8192,
                        'memory': '32G',
                        'time': '12:00:00',
                        'gpu': 2,
                        'script': '#!/bin/bash\\npython train.py'
                    },
                    'created_by': 'admin',
                    'created_at': '2025-10-01T10:00:00',
                    'updated_at': '2025-10-01T10:00:00',
                    'usage_count': 45
                },
                {
                    'id': 'tpl-002',
                    'name': 'TensorFlow Distributed',
                    'description': 'Multi-node TensorFlow training',
                    'category': 'ml',
                    'shared': True,
                    'config': {
                        'partition': 'group2',
                        'nodes': 4,
                        'cpus': 1024,
                        'memory': '64G',
                        'time': '24:00:00',
                        'gpu': 4,
                        'script': '#!/bin/bash\\npython -m torch.distributed.launch train.py'
                    },
                    'created_by': 'admin',
                    'created_at': '2025-09-15T10:00:00',
                    'updated_at': '2025-09-15T10:00:00',
                    'usage_count': 23
                },
                {
                    'id': 'tpl-003',
                    'name': 'GROMACS Simulation',
                    'description': 'Molecular dynamics simulation',
                    'category': 'simulation',
                    'shared': True,
                    'config': {
                        'partition': 'group3',
                        'nodes': 2,
                        'cpus': 1024,
                        'memory': '128G',
                        'time': '48:00:00',
                        'script': '#!/bin/bash\\ngmx mdrun -v -deffnm md'
                    },
                    'created_by': 'researcher',
                    'created_at': '2025-09-20T10:00:00',
                    'updated_at': '2025-09-20T10:00:00',
                    'usage_count': 67
                },
                {
                    'id': 'tpl-004',
                    'name': 'Data Processing',
                    'description': 'Large-scale data processing with Spark',
                    'category': 'data',
                    'shared': True,
                    'config': {
                        'partition': 'group6',
                        'nodes': 8,
                        'cpus': 64,
                        'memory': '256G',
                        'time': '06:00:00',
                        'script': '#!/bin/bash\\nspark-submit process.py'
                    },
                    'created_by': 'data_team',
                    'created_at': '2025-09-10T10:00:00',
                    'updated_at': '2025-09-10T10:00:00',
                    'usage_count': 34
                },
                {
                    'id': 'tpl-005',
                    'name': 'Quick Test',
                    'description': 'Quick test job for debugging',
                    'category': 'custom',
                    'shared': False,
                    'config': {
                        'partition': 'group6',
                        'nodes': 1,
                        'cpus': 8,
                        'memory': '4G',
                        'time': '00:10:00',
                        'script': '#!/bin/bash\\necho Hello World'
                    },
                    'created_by': 'user01',
                    'created_at': '2025-10-05T10:00:00',
                    'updated_at': '2025-10-05T10:00:00',
                    'usage_count': 12
                },
                {
                    'id': 'tpl-lsdyna-single',
                    'name': 'LS-DYNA Single Job',
                    'description': 'LS-DYNA simulation with single K-file input. Upload one K file and it will be automatically configured for MPP solver.',
                    'category': 'simulation',
                    'shared': True,
                    'config': {
                        'partition': 'group6',
                        'nodes': 1,
                        'cpus': 32,
                        'memory': '64GB',
                        'time': '24:00:00',
                        'script': '''#!/bin/bash
#SBATCH --ntasks=32

# LS-DYNA Single Job Submission
module load lsdyna/R13.1.0

NPROCS=32
MEMORY=64000000

echo "LS-DYNA Single Job"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Cores: $NPROCS"

if [ ! -f "$K_FILE" ]; then
    echo "Error: K file not found: $K_FILE"
    exit 1
fi

OUTPUT_DIR=$(dirname $K_FILE)/output
mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR

mpirun -np $NPROCS ls-dyna_mpp I=$K_FILE MEMORY=$MEMORY NCPU=$NPROCS

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ LS-DYNA simulation completed successfully"
else
    echo "❌ LS-DYNA simulation failed with exit code $EXIT_CODE"
fi
exit $EXIT_CODE'''
                    },
                    'created_by': 'system',
                    'created_at': '2025-01-10T10:00:00',
                    'updated_at': '2025-01-10T10:00:00',
                    'usage_count': 15
                },
                {
                    'id': 'tpl-lsdyna-array',
                    'name': 'LS-DYNA Array Job',
                    'description': 'LS-DYNA array job for multiple K-files. Upload multiple K files and each will be run as a separate job with dedicated resources and output directory.',
                    'category': 'simulation',
                    'shared': True,
                    'config': {
                        'partition': 'group6',
                        'nodes': 1,
                        'cpus': 16,
                        'memory': '32GB',
                        'time': '12:00:00',
                        'script': '''#!/bin/bash
#SBATCH --ntasks=16

# LS-DYNA Array Job Submission
module load lsdyna/R13.1.0

NPROCS=16
MEMORY=32000000

echo "LS-DYNA Array Job Submission"
echo "Parent Job ID: $SLURM_JOB_ID"
echo "Total K files: ${#K_FILES[@]}"

for K_FILE in "${K_FILES[@]}"; do
    if [ ! -f "$K_FILE" ]; then
        echo "Error: K file not found: $K_FILE"
        exit 1
    fi
done

JOB_IDS=()
for i in "${!K_FILES[@]}"; do
    K_FILE="${K_FILES[$i]}"
    BASENAME=$(basename "$K_FILE" .k)
    
    echo "[$((i+1))/${#K_FILES[@]}] Submitting job for: $BASENAME"
    
    JOB_DIR="/data/results/lsdyna_${SLURM_JOB_ID}_${i}_${BASENAME}"
    mkdir -p $JOB_DIR/output
    
    # Create and submit individual job
    SUBMITTED_JOB_ID=$(sbatch --parsable $JOB_DIR/run_lsdyna.sh)
    JOB_IDS+=($SUBMITTED_JOB_ID)
    
    echo "   → Job ID: $SUBMITTED_JOB_ID"
    sleep 1
done

echo "Total jobs submitted: ${#JOB_IDS[@]}"
echo "Job IDs: ${JOB_IDS[@]}"'''
                    },
                    'created_by': 'system',
                    'created_at': '2025-01-10T10:00:00',
                    'updated_at': '2025-01-10T10:00:00',
                    'usage_count': 8
                }
            ]
            
            # 필터링
            templates = mock_templates
            
            if category != 'all':
                templates = [t for t in templates if t['category'] == category]
            
            if shared is not None:
                shared_bool = shared.lower() == 'true'
                templates = [t for t in templates if t['shared'] == shared_bool]
            
            if search:
                search_lower = search.lower()
                templates = [
                    t for t in templates
                    if search_lower in t['name'].lower() or search_lower in t['description'].lower()
                ]
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'templates': templates,
                'count': len(templates)
            })
        
        # Production: SQLite 데이터베이스에서 조회
        with get_db_connection() as conn:
            cursor = conn.cursor()
        
            # 쿼리 구성
            query = "SELECT id, name, description, category, shared, config, created_by, created_at, updated_at, usage_count FROM templates WHERE 1=1"
            params = []
            
            if category != 'all':
                query += " AND category = ?"
                params.append(category)
            
            if shared is not None:
                shared_bool = 1 if shared.lower() == 'true' else 0
                query += " AND shared = ?"
                params.append(shared_bool)
            
            if search:
                query += " AND (LOWER(name) LIKE ? OR LOWER(description) LIKE ?)"
                search_param = f"%{search.lower()}%"
                params.extend([search_param, search_param])
            
            query += " ORDER BY usage_count DESC"
            
            cursor.execute(query, params)
            rows = cursor.fetchall()
            
            templates = []
            for row in rows:
                templates.append({
                    'id': row[0],
                    'name': row[1],
                    'description': row[2],
                    'category': row[3],
                    'shared': bool(row[4]),
                    'config': json.loads(row[5]),
                    'created_by': row[6],
                    'created_at': row[7],
                    'updated_at': row[8],
                    'usage_count': row[9]
                })
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'templates': templates,
            'count': len(templates)
        })
        
    except Exception as e:
        print(f"❌ Error getting templates: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# POST /api/jobs/templates
# 템플릿 생성
# ============================================
@templates_bp.route('', methods=['POST'])
def create_template():
    """
    템플릿 생성
    Body:
        {
            "name": "Template Name",
            "description": "Description",
            "category": "ml",
            "shared": false,
            "config": {
                "partition": "gpu",
                "nodes": 1,
                "cpus": 8,
                "memory": "32G",
                "time": "12:00:00",
                "gpu": 2,
                "script": "#!/bin/bash\\npython train.py"
            }
        }
    """
    try:
        data = request.json
        
        # 필수 필드 검증
        if not data.get('name'):
            return jsonify({'success': False, 'error': 'Name is required'}), 400
        if not data.get('config'):
            return jsonify({'success': False, 'error': 'Config is required'}), 400
        
        template_id = str(uuid.uuid4())[:8]
        name = data['name']
        description = data.get('description', '')
        category = data.get('category', 'custom')
        shared = data.get('shared', False)
        config = data['config']
        created_by = data.get('created_by', 'current_user')
        
        if is_mock_mode():
            # Mock: 메모리에 저장 (실제로는 저장 안 됨)
            template = {
                'id': template_id,
                'name': name,
                'description': description,
                'category': category,
                'shared': shared,
                'config': config,
                'created_by': created_by,
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat(),
                'usage_count': 0
            }
            
            print(f"📝 [Mock] Template created: {template_id}")
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': 'Template created (Mock)',
                'template': template
            })
        
        # Production: SQLite에 저장
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                INSERT INTO templates (id, name, description, category, shared, config, created_by, created_at, updated_at, usage_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                template_id,
                name,
                description,
                category,
                1 if shared else 0,
                json.dumps(config),
                created_by,
                datetime.now().isoformat(),
                datetime.now().isoformat(),
                0
            ))
        
        print(f"✅ Template created: {template_id}")
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': 'Template created successfully',
            'template_id': template_id
        })
        
    except Exception as e:
        print(f"❌ Error creating template: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# GET /api/jobs/templates/:id
# 템플릿 상세 조회
# ============================================
@templates_bp.route('/<template_id>', methods=['GET'])
def get_template(template_id):
    """특정 템플릿 조회"""
    try:
        if is_mock_mode():
            # Mock: 임시 데이터 반환
            template = {
                'id': template_id,
                'name': 'Sample Template',
                'description': 'Sample description',
                'category': 'ml',
                'shared': True,
                'config': {
                    'partition': 'gpu',
                    'nodes': 1,
                    'cpus': 8,
                    'memory': '32G',
                    'time': '12:00:00',
                    'script': '#!/bin/bash\\necho "Sample"'
                },
                'created_by': 'admin',
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat(),
                'usage_count': 0
            }
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'template': template
            })
        
        # Production
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT id, name, description, category, shared, config, created_by, created_at, updated_at, usage_count
                FROM templates
                WHERE id = ?
            """, (template_id,))
            
            row = cursor.fetchone()
            
            if not row:
                return jsonify({
                    'success': False,
                    'error': 'Template not found'
                }), 404
            
            template = {
                'id': row[0],
                'name': row[1],
                'description': row[2],
                'category': row[3],
                'shared': bool(row[4]),
                'config': json.loads(row[5]),
                'created_by': row[6],
                'created_at': row[7],
                'updated_at': row[8],
                'usage_count': row[9]
            }
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'template': template
        })
        
    except Exception as e:
        print(f"❌ Error getting template: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# PATCH /api/jobs/templates/:id
# 템플릿 수정
# ============================================
@templates_bp.route('/<template_id>', methods=['PATCH'])
def update_template(template_id):
    """템플릿 수정"""
    try:
        data = request.json
        
        if is_mock_mode():
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Template {template_id} updated (Mock)'
            })
        
        # Production
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            # 수정할 필드 구성
            updates = []
            params = []
            
            if 'name' in data:
                updates.append('name = ?')
                params.append(data['name'])
            if 'description' in data:
                updates.append('description = ?')
                params.append(data['description'])
            if 'category' in data:
                updates.append('category = ?')
                params.append(data['category'])
            if 'shared' in data:
                updates.append('shared = ?')
                params.append(1 if data['shared'] else 0)
            if 'config' in data:
                updates.append('config = ?')
                params.append(json.dumps(data['config']))
            
            updates.append('updated_at = ?')
            params.append(datetime.now().isoformat())
            
            params.append(template_id)
            
            query = f"UPDATE templates SET {', '.join(updates)} WHERE id = ?"
            cursor.execute(query, params)
        
        print(f"✅ Template updated: {template_id}")
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': 'Template updated successfully'
        })
        
    except Exception as e:
        print(f"❌ Error updating template: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# DELETE /api/jobs/templates/:id
# 템플릿 삭제
# ============================================
@templates_bp.route('/<template_id>', methods=['DELETE'])
def delete_template(template_id):
    """템플릿 삭제"""
    try:
        if is_mock_mode():
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Template {template_id} deleted (Mock)'
            })
        
        # Production
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("DELETE FROM templates WHERE id = ?", (template_id,))
            
            if cursor.rowcount == 0:
                return jsonify({
                    'success': False,
                    'error': 'Template not found'
                }), 404
        
        print(f"✅ Template deleted: {template_id}")
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': 'Template deleted successfully'
        })
        
    except Exception as e:
        print(f"❌ Error deleting template: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# POST /api/jobs/templates/:id/use
# 템플릿 사용 (usage_count 증가)
# ============================================
@templates_bp.route('/<template_id>/use', methods=['POST'])
def use_template(template_id):
    """템플릿 사용 횟수 증가"""
    try:
        if is_mock_mode():
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Template {template_id} usage count increased (Mock)'
            })
        
        # Production
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                UPDATE templates
                SET usage_count = usage_count + 1
                WHERE id = ?
            """, (template_id,))
        
        print(f"✅ Template used: {template_id}")
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': 'Usage count updated'
        })
        
    except Exception as e:
        print(f"❌ Error updating usage count: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# GET /api/jobs/templates/categories
# 카테고리 목록
# ============================================
@templates_bp.route('/categories', methods=['GET'])
def get_categories():
    """카테고리 목록 및 통계"""
    try:
        if is_mock_mode():
            return jsonify({
                'success': True,
                'mode': 'mock',
                'categories': [
                    {'name': 'ml', 'label': 'Machine Learning', 'count': 2, 'icon': '🤖'},
                    {'name': 'simulation', 'label': 'Simulation', 'count': 1, 'icon': '🔬'},
                    {'name': 'data', 'label': 'Data Processing', 'count': 1, 'icon': '📊'},
                    {'name': 'custom', 'label': 'Custom', 'count': 1, 'icon': '⚙️'}
                ]
            })
        
        # Production
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT category, COUNT(*) as count
                FROM templates
                GROUP BY category
                ORDER BY count DESC
            """)
            
            rows = cursor.fetchall()
            
            category_labels = {
                'ml': {'label': 'Machine Learning', 'icon': '🤖'},
                'simulation': {'label': 'Simulation', 'icon': '🔬'},
                'data': {'label': 'Data Processing', 'icon': '📊'},
                'custom': {'label': 'Custom', 'icon': '⚙️'}
            }
            
            categories = []
            for row in rows:
                cat_name = row[0]
                cat_info = category_labels.get(cat_name, {'label': cat_name, 'icon': '📁'})
                categories.append({
                    'name': cat_name,
                    'label': cat_info['label'],
                    'count': row[1],
                    'icon': cat_info['icon']
                })
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'categories': categories
        })
        
    except Exception as e:
        print(f"❌ Error getting categories: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


print("✅ Templates API initialized")
