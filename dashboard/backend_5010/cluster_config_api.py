"""
Cluster Configuration API
클러스터 구성 정보 저장 및 조회
+ Slurm 파티션 자동 동기화
"""

from flask import Blueprint, request, jsonify
import os
import json
import subprocess
from datetime import datetime
from typing import List, Dict, Tuple
from database import get_db_connection
from middleware.jwt_middleware import jwt_required, permission_required

# Slurm 명령어 경로
SLURM_BIN_DIR = os.getenv('SLURM_BIN_DIR', '/usr/local/slurm/bin')
SCONTROL = os.path.join(SLURM_BIN_DIR, 'scontrol')
USE_SUDO_FOR_SLURM = os.getenv('USE_SUDO_FOR_SLURM', 'true').lower() == 'true'

cluster_config_bp = Blueprint('cluster_config', __name__, url_prefix='/api/cluster')

# Mock 모드 체크 함수 (매번 환경변수 확인)
def is_mock_mode():
    """현재 MOCK_MODE 환경변수 확인"""
    return os.getenv('MOCK_MODE', 'true').lower() == 'true'

# Mock 그룹 데이터 - 실제 initialData.ts와 일치
MOCK_GROUPS = [
    {
        'id': 1,
        'name': 'Group 1',
        'partitionName': 'group1',
        'qosName': 'group1_qos',
        'allowedCoreSizes': [8192],
        'color': '#3b82f6',
        'description': 'Large scale jobs'
    },
    {
        'id': 2,
        'name': 'Group 2',
        'partitionName': 'group2',
        'qosName': 'group2_qos',
        'allowedCoreSizes': [1024],
        'color': '#10b981',
        'description': 'Medium jobs'
    },
    {
        'id': 3,
        'name': 'Group 3',
        'partitionName': 'group3',
        'qosName': 'group3_qos',
        'allowedCoreSizes': [1024],
        'color': '#f59e0b',
        'description': 'Medium jobs'
    },
    {
        'id': 4,
        'name': 'Group 4',
        'partitionName': 'group4',
        'qosName': 'group4_qos',
        'allowedCoreSizes': [128],
        'color': '#ef4444',
        'description': 'Small jobs'
    },
    {
        'id': 5,
        'name': 'Group 5',
        'partitionName': 'group5',
        'qosName': 'group5_qos',
        'allowedCoreSizes': [128],
        'color': '#8b5cf6',
        'description': 'Small jobs'
    },
    {
        'id': 6,
        'name': 'Group 6',
        'partitionName': 'group6',
        'qosName': 'group6_qos',
        'allowedCoreSizes': [8, 16, 32, 64],
        'color': '#ec4899',
        'description': 'Flexible jobs'
    }
]


# ==================== Slurm 파티션 동기화 ====================

def _build_slurm_cmd(base_cmd: List[str]) -> List[str]:
    """Slurm 명령어에 sudo prefix 추가 (필요한 경로)"""
    if USE_SUDO_FOR_SLURM:
        return ['/usr/bin/sudo', '-n'] + base_cmd
    return base_cmd


def get_existing_partitions() -> List[str]:
    """현재 Slurm에 정의된 파티션 목록 조회"""
    try:
        result = subprocess.run(
            [SCONTROL, 'show', 'partition', '-o'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            return []

        partitions = []
        for line in result.stdout.strip().split('\n'):
            if 'PartitionName=' in line:
                for part in line.split():
                    if part.startswith('PartitionName='):
                        partitions.append(part.split('=')[1])
                        break
        return partitions
    except Exception as e:
        print(f"⚠️  Failed to get partitions: {e}")
        return []


def sync_partition(
    partition_name: str,
    nodes: List[str],
    max_time: str = "INFINITE",
    default: bool = False
) -> Tuple[bool, str]:
    """
    Slurm 파티션 생성/업데이트
    """
    if not nodes:
        return False, f"No nodes specified for partition {partition_name}"

    node_list = ','.join(nodes)
    existing_partitions = get_existing_partitions()

    try:
        if partition_name in existing_partitions:
            # 기존 파티션 업데이트
            base_cmd = [
                SCONTROL, 'update',
                f'PartitionName={partition_name}',
                f'Nodes={node_list}',
                f'MaxTime={max_time}',
                'State=UP'
            ]
            if default:
                base_cmd.append('Default=YES')
        else:
            # 새 파티션 생성
            base_cmd = [
                SCONTROL, 'create',
                f'PartitionName={partition_name}',
                f'Nodes={node_list}',
                f'MaxTime={max_time}',
                'State=UP'
            ]
            if default:
                base_cmd.append('Default=YES')

        cmd = _build_slurm_cmd(base_cmd)
        print(f"🔧 Running: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        if result.returncode == 0:
            action = "Updated" if partition_name in existing_partitions else "Created"
            return True, f"{action} partition {partition_name} with {len(nodes)} nodes"
        else:
            return False, f"Failed: {result.stderr.strip()}"

    except subprocess.TimeoutExpired:
        return False, f"Timeout configuring partition {partition_name}"
    except Exception as e:
        return False, f"Error: {str(e)}"


def sync_partitions_from_groups(groups: List[Dict]) -> Dict:
    """
    그룹 설정에서 Slurm 파티션 동기화
    각 그룹의 partitionName과 nodes를 기반으로 파티션 생성/업데이트
    """
    results = {
        'success': True,
        'partitions': {},
        'errors': []
    }

    # Slurm 사용 가능 여부 확인
    try:
        check = subprocess.run([SCONTROL, '--version'], capture_output=True, timeout=5)
        if check.returncode != 0:
            results['success'] = False
            results['errors'].append('Slurm not available')
            return results
    except Exception:
        results['success'] = False
        results['errors'].append('Slurm not available')
        return results

    for idx, group in enumerate(groups):
        partition_name = group.get('partitionName')
        if not partition_name:
            continue

        # 그룹 내 노드 호스트명 추출
        nodes = group.get('nodes', [])
        hostnames = [n.get('hostname') for n in nodes if n.get('hostname')]

        if not hostnames:
            results['partitions'][partition_name] = {
                'success': False,
                'message': 'No nodes in group',
                'nodes': 0
            }
            continue

        # 첫 번째 그룹을 기본 파티션으로 설정
        is_default = (idx == 0)

        success, message = sync_partition(
            partition_name=partition_name,
            nodes=hostnames,
            max_time="INFINITE",
            default=is_default
        )

        results['partitions'][partition_name] = {
            'success': success,
            'message': message,
            'nodes': len(hostnames)
        }

        if success:
            print(f"✅ {message}")
        else:
            print(f"❌ {message}")
            results['errors'].append(message)

    # 하나라도 실패하면 전체 success는 False
    if results['errors']:
        results['success'] = False

    return results


@cluster_config_bp.route('/config', methods=['GET'])
def get_cluster_config():
    """
    전체 클러스터 구성 조회
    Returns:
        {
            "success": true,
            "config": {
                "groups": [...],
                "clusterName": "HPC-Cluster-370",
                "controllerIp": "192.168.1.10"
            }
        }
    """
    try:
        if is_mock_mode():
            return jsonify({
                'success': True,
                'mode': 'mock',
                'config': {
                    'groups': MOCK_GROUPS,
                    'clusterName': 'HPC-Cluster-370',
                    'controllerIp': '192.168.1.10',
                    'totalNodes': 370
                }
            })
        
        # Production: DB에서 조회
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT config FROM cluster_config WHERE id = 1")
            row = cursor.fetchone()
            
            if row:
                config = json.loads(row[0])
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'config': config
                })
            else:
                # DB에 없으면 빈 config 반환 (목업 데이터 사용 안함)
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'config': {
                        'groups': [],
                        'clusterName': 'HPC-Cluster',
                        'controllerIp': '127.0.0.1',
                        'totalNodes': 0,
                        'totalCores': 0
                    },
                    'note': 'No configuration found. Run update_partitions.sh to initialize.'
                })
        
    except Exception as e:
        print(f"❌ Error getting cluster config: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@cluster_config_bp.route('/config', methods=['POST'])
@jwt_required
@permission_required('admin')
def save_cluster_config():
    """
    클러스터 구성 저장 (admin 권한 필요)
    - DB에 설정 저장
    - Slurm 파티션 자동 동기화

    Body:
        {
            "groups": [...],
            "clusterName": "...",
            "controllerIp": "...",
            "totalNodes": 370
        }

    Query params:
        sync_slurm: true/false (기본: true) - Slurm 파티션 동기화 여부
    """
    try:
        config = request.json
        sync_slurm = request.args.get('sync_slurm', 'true').lower() == 'true'

        if is_mock_mode():
            print(f"📝 [Mock] Cluster config would be saved")
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': 'Configuration saved (Mock)'
            })

        # Production: DB에 저장
        with get_db_connection() as conn:
            cursor = conn.cursor()

            # 기존 설정이 있는지 확인
            cursor.execute("SELECT id FROM cluster_config WHERE id = 1")
            exists = cursor.fetchone()

            if exists:
                # UPDATE
                cursor.execute("""
                    UPDATE cluster_config
                    SET config = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE id = 1
                """, (json.dumps(config),))
            else:
                # INSERT
                cursor.execute("""
                    INSERT INTO cluster_config (id, config)
                    VALUES (1, ?)
                """, (json.dumps(config),))

        print(f"✅ Cluster config saved to database")

        # Slurm 파티션 동기화
        slurm_result = None
        if sync_slurm:
            groups = config.get('groups', [])
            if groups:
                print(f"🔄 Syncing Slurm partitions for {len(groups)} groups...")
                slurm_result = sync_partitions_from_groups(groups)

        response = {
            'success': True,
            'mode': 'production',
            'message': 'Configuration saved successfully'
        }

        if slurm_result:
            response['slurm_sync'] = slurm_result
            if not slurm_result['success']:
                response['warning'] = 'Configuration saved but Slurm sync had errors'

        return jsonify(response)

    except Exception as e:
        print(f"❌ Error saving cluster config: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


print("✅ Cluster Config API initialized")
