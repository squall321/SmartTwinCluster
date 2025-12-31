"""
YAML Node Group Loader
YAML 설정 파일에서 노드 정보를 읽어 그룹으로 초기화
+ Slurm 파티션 자동 동기화
"""

import os
import subprocess
import yaml
from typing import List, Dict, Any, Optional, Tuple
from flask import Blueprint, jsonify, request
from middleware.jwt_middleware import jwt_required, permission_required

# Slurm 명령어 경로
SLURM_BIN_DIR = os.getenv('SLURM_BIN_DIR', '/usr/bin')
SCONTROL = os.path.join(SLURM_BIN_DIR, 'scontrol')

# sudo 사용 여부 (scontrol 명령에 필요한 권한)
USE_SUDO_FOR_SLURM = os.getenv('USE_SUDO_FOR_SLURM', 'true').lower() == 'true'

# Blueprint 생성
yaml_loader_bp = Blueprint('yaml_loader', __name__, url_prefix='/api/yaml')

# YAML 경로 설정
YAML_PATHS = [
    os.path.join(os.path.dirname(__file__), '..', '..', 'my_multihead_cluster.yaml'),
    '/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_multihead_cluster.yaml',
    os.getenv('CLUSTER_YAML_PATH', ''),
]


def find_yaml_path() -> Optional[str]:
    """YAML 파일 경로 찾기"""
    for path in YAML_PATHS:
        if path and os.path.exists(path):
            return path
    return None


def load_yaml_config() -> Optional[Dict[str, Any]]:
    """YAML 설정 파일 로드"""
    yaml_path = find_yaml_path()
    if not yaml_path:
        print("⚠️  YAML config file not found")
        return None

    try:
        with open(yaml_path) as f:
            config = yaml.safe_load(f)
            print(f"✅ Loaded YAML config from {yaml_path}")
            return config
    except Exception as e:
        print(f"❌ Failed to load YAML config: {e}")
        return None


def get_nodes_from_yaml() -> Dict[str, List[Dict[str, Any]]]:
    """
    YAML에서 노드 정보 추출
    Returns:
        {
            'compute': [...],
            'viz': [...],
            'controller': [...]
        }
    """
    config = load_yaml_config()
    if not config:
        return {'compute': [], 'viz': [], 'controller': []}

    nodes_config = config.get('nodes', {})

    result = {
        'compute': [],
        'viz': [],
        'controller': []
    }

    # Controllers
    for ctrl in nodes_config.get('controllers', []):
        node_info = {
            'hostname': ctrl.get('hostname'),
            'ip_address': ctrl.get('ip_address'),
            'node_type': ctrl.get('node_type', 'controller'),
            'cores': ctrl.get('hardware', {}).get('cpus', 0),
            'memory_mb': ctrl.get('hardware', {}).get('memory_mb', 0),
            'state': 'idle',
        }
        result['controller'].append(node_info)

    # Compute nodes
    for node in nodes_config.get('compute_nodes', []):
        node_type = node.get('node_type', 'compute')
        node_info = {
            'hostname': node.get('hostname'),
            'ip_address': node.get('ip_address'),
            'node_type': node_type,
            'cores': node.get('hardware', {}).get('cpus', 0),
            'memory_mb': node.get('hardware', {}).get('memory_mb', 0),
            'gpus': node.get('hardware', {}).get('gpus', 0),
            'gpu_type': node.get('hardware', {}).get('gpu_type', ''),
            'state': 'idle',
        }

        if node_type == 'viz':
            result['viz'].append(node_info)
        else:
            result['compute'].append(node_info)

    return result


def create_initial_groups_from_yaml() -> List[Dict[str, Any]]:
    """
    YAML 노드 정보로 초기 그룹 생성
    - compute 노드 → "Compute" 그룹
    - viz 노드 → "Visualization" 그룹
    """
    nodes = get_nodes_from_yaml()
    groups = []
    group_id = 1

    # Compute Group
    compute_nodes = nodes.get('compute', [])
    if compute_nodes:
        compute_group = {
            'id': group_id,
            'name': 'Compute',
            'description': 'Compute nodes for batch jobs',
            'color': '#3b82f6',  # Blue
            'partitionName': 'compute',
            'qosName': 'compute_qos',
            'allowedCoreSizes': [128, 256, 512, 1024],
            'nodeCount': len(compute_nodes),
            'totalCores': sum(n.get('cores', 0) for n in compute_nodes),
            'nodes': [
                {
                    'id': n['hostname'],
                    'hostname': n['hostname'],
                    'ipAddress': n['ip_address'],
                    'cores': n['cores'],
                    'memory': n['memory_mb'],
                    'state': 'idle',
                    'groupId': group_id
                }
                for n in compute_nodes
            ]
        }
        groups.append(compute_group)
        group_id += 1

    # Visualization Group
    viz_nodes = nodes.get('viz', [])
    if viz_nodes:
        viz_group = {
            'id': group_id,
            'name': 'Visualization',
            'description': 'Visualization nodes for VNC/GPU desktop',
            'color': '#10b981',  # Green
            'partitionName': 'viz',
            'qosName': 'viz_qos',
            'allowedCoreSizes': [8, 16, 32, 64],
            'nodeCount': len(viz_nodes),
            'totalCores': sum(n.get('cores', 0) for n in viz_nodes),
            'nodes': [
                {
                    'id': n['hostname'],
                    'hostname': n['hostname'],
                    'ipAddress': n['ip_address'],
                    'cores': n['cores'],
                    'memory': n['memory_mb'],
                    'gpus': n.get('gpus', 0),
                    'state': 'idle',
                    'groupId': group_id
                }
                for n in viz_nodes
            ]
        }
        groups.append(viz_group)
        group_id += 1

    return groups


def get_cluster_info_from_yaml() -> Dict[str, Any]:
    """YAML에서 클러스터 정보 추출"""
    config = load_yaml_config()
    if not config:
        return {}

    nodes = get_nodes_from_yaml()
    total_nodes = len(nodes['compute']) + len(nodes['viz'])
    total_cores = sum(n['cores'] for n in nodes['compute']) + sum(n['cores'] for n in nodes['viz'])

    return {
        'clusterName': config.get('cluster_name', 'HPC Cluster'),
        'controllerIp': nodes['controller'][0]['ip_address'] if nodes['controller'] else '',
        'totalNodes': total_nodes,
        'totalCores': total_cores,
        'computeNodes': len(nodes['compute']),
        'vizNodes': len(nodes['viz']),
        'controllerNodes': len(nodes['controller']),
    }


# ==================== Slurm 파티션 동기화 ====================

def _build_slurm_cmd(base_cmd: List[str]) -> List[str]:
    """
    Slurm 명령어에 sudo prefix 추가 (필요한 경우)
    """
    if USE_SUDO_FOR_SLURM:
        return ['/usr/bin/sudo', '-n'] + base_cmd  # -n: non-interactive (password 없이)
    return base_cmd


def check_slurm_available() -> bool:
    """Slurm이 사용 가능한지 확인"""
    try:
        result = subprocess.run(
            [SCONTROL, '--version'],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False


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
                # PartitionName=compute State=UP ...
                for part in line.split():
                    if part.startswith('PartitionName='):
                        partitions.append(part.split('=')[1])
                        break
        return partitions
    except Exception as e:
        print(f"⚠️  Failed to get partitions: {e}")
        return []


def create_or_update_partition(
    partition_name: str,
    nodes: List[str],
    max_time: str = "INFINITE",
    default: bool = False,
    state: str = "UP"
) -> Tuple[bool, str]:
    """
    Slurm 파티션 생성 또는 업데이트

    Args:
        partition_name: 파티션 이름
        nodes: 노드 호스트명 리스트
        max_time: 최대 실행 시간
        default: 기본 파티션 여부
        state: 파티션 상태

    Returns:
        (success, message)
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
                f'State={state}'
            ]
            if default:
                base_cmd.append('Default=YES')

            cmd = _build_slurm_cmd(base_cmd)
            print(f"🔧 Running: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

            if result.returncode == 0:
                return True, f"Updated partition {partition_name} with {len(nodes)} nodes"
            else:
                return False, f"Failed to update partition: {result.stderr}"
        else:
            # 새 파티션 생성
            base_cmd = [
                SCONTROL, 'create',
                f'PartitionName={partition_name}',
                f'Nodes={node_list}',
                f'MaxTime={max_time}',
                f'State={state}'
            ]
            if default:
                base_cmd.append('Default=YES')

            cmd = _build_slurm_cmd(base_cmd)
            print(f"🔧 Running: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

            if result.returncode == 0:
                return True, f"Created partition {partition_name} with {len(nodes)} nodes"
            else:
                return False, f"Failed to create partition: {result.stderr}"

    except subprocess.TimeoutExpired:
        return False, f"Timeout while configuring partition {partition_name}"
    except Exception as e:
        return False, f"Error configuring partition {partition_name}: {str(e)}"


def sync_slurm_partitions_from_yaml() -> Dict[str, Any]:
    """
    YAML 설정을 기반으로 Slurm 파티션 동기화

    Returns:
        {
            'success': bool,
            'slurm_available': bool,
            'partitions': {
                'compute': {'success': bool, 'message': str, 'nodes': int},
                'viz': {'success': bool, 'message': str, 'nodes': int}
            }
        }
    """
    result = {
        'success': False,
        'slurm_available': False,
        'partitions': {}
    }

    # Slurm 사용 가능 여부 확인
    if not check_slurm_available():
        result['message'] = 'Slurm is not available on this system'
        print("⚠️  Slurm not available - skipping partition sync")
        return result

    result['slurm_available'] = True
    nodes = get_nodes_from_yaml()

    # Compute 파티션
    compute_nodes = [n['hostname'] for n in nodes.get('compute', [])]
    if compute_nodes:
        success, message = create_or_update_partition(
            partition_name='compute',
            nodes=compute_nodes,
            max_time='INFINITE',
            default=True,  # compute를 기본 파티션으로
            state='UP'
        )
        result['partitions']['compute'] = {
            'success': success,
            'message': message,
            'nodes': len(compute_nodes)
        }
        if success:
            print(f"✅ {message}")
        else:
            print(f"❌ {message}")

    # Visualization 파티션
    viz_nodes = [n['hostname'] for n in nodes.get('viz', [])]
    if viz_nodes:
        success, message = create_or_update_partition(
            partition_name='viz',
            nodes=viz_nodes,
            max_time='8:00:00',  # viz는 8시간 제한
            default=False,
            state='UP'
        )
        result['partitions']['viz'] = {
            'success': success,
            'message': message,
            'nodes': len(viz_nodes)
        }
        if success:
            print(f"✅ {message}")
        else:
            print(f"❌ {message}")

    # 전체 성공 여부
    all_success = all(
        p.get('success', False)
        for p in result['partitions'].values()
    )
    result['success'] = all_success or len(result['partitions']) == 0

    return result


# ==================== API Endpoints ====================

@yaml_loader_bp.route('/nodes', methods=['GET'])
@jwt_required
def get_yaml_nodes():
    """YAML에서 노드 정보 조회"""
    nodes = get_nodes_from_yaml()
    return jsonify({
        'success': True,
        'nodes': nodes,
        'counts': {
            'compute': len(nodes['compute']),
            'viz': len(nodes['viz']),
            'controller': len(nodes['controller'])
        }
    })


@yaml_loader_bp.route('/groups', methods=['GET'])
@jwt_required
def get_yaml_groups():
    """YAML 기반 초기 그룹 조회"""
    groups = create_initial_groups_from_yaml()
    cluster_info = get_cluster_info_from_yaml()

    return jsonify({
        'success': True,
        'groups': groups,
        'clusterInfo': cluster_info
    })


@yaml_loader_bp.route('/init', methods=['POST'])
@jwt_required
@permission_required('admin')
def initialize_from_yaml():
    """
    YAML 기반으로 노드 그룹 초기화
    DB에 저장하고 Slurm 파티션 설정
    """
    try:
        groups = create_initial_groups_from_yaml()
        cluster_info = get_cluster_info_from_yaml()

        if not groups:
            return jsonify({
                'success': False,
                'error': 'No nodes found in YAML configuration'
            }), 400

        # DB에 저장 (cluster_config_api의 로직 사용)
        from database import get_db_connection
        import json

        config = {
            'groups': groups,
            'clusterName': cluster_info.get('clusterName', 'HPC Cluster'),
            'controllerIp': cluster_info.get('controllerIp', ''),
            'totalNodes': cluster_info.get('totalNodes', 0),
            'totalCores': cluster_info.get('totalCores', 0)
        }

        with get_db_connection() as conn:
            cursor = conn.cursor()

            # 기존 설정 확인
            cursor.execute("SELECT id FROM cluster_config WHERE id = 1")
            exists = cursor.fetchone()

            if exists:
                cursor.execute("""
                    UPDATE cluster_config
                    SET config = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE id = 1
                """, (json.dumps(config),))
            else:
                cursor.execute("""
                    INSERT INTO cluster_config (id, config)
                    VALUES (1, ?)
                """, (json.dumps(config),))

        print(f"✅ Initialized {len(groups)} groups from YAML")
        print(f"   Compute nodes: {cluster_info.get('computeNodes', 0)}")
        print(f"   Viz nodes: {cluster_info.get('vizNodes', 0)}")

        return jsonify({
            'success': True,
            'message': f'Initialized {len(groups)} groups from YAML',
            'groups': groups,
            'clusterInfo': cluster_info
        })

    except Exception as e:
        print(f"❌ YAML initialization failed: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@yaml_loader_bp.route('/config', methods=['GET'])
def get_yaml_config_info():
    """YAML 설정 파일 정보 조회 (인증 불필요)"""
    yaml_path = find_yaml_path()
    config = load_yaml_config()

    return jsonify({
        'success': config is not None,
        'yaml_path': yaml_path,
        'cluster_name': config.get('cluster_name', 'Unknown') if config else None,
        'has_compute_nodes': len(get_nodes_from_yaml().get('compute', [])) > 0,
        'has_viz_nodes': len(get_nodes_from_yaml().get('viz', [])) > 0,
    })


@yaml_loader_bp.route('/init-startup', methods=['POST'])
def initialize_from_yaml_startup():
    """
    시스템 시작 시 YAML 기반 노드 그룹 자동 초기화
    localhost에서만 접근 가능 (인증 불필요)
    start.sh에서 서버 시작 후 호출됨

    1. DB에 그룹 정보 저장
    2. Slurm 파티션 동기화 (compute, viz)
    """
    # localhost에서만 접근 허용
    remote_addr = request.remote_addr
    if remote_addr not in ['127.0.0.1', 'localhost', '::1']:
        return jsonify({
            'success': False,
            'error': 'This endpoint is only accessible from localhost'
        }), 403

    try:
        groups = create_initial_groups_from_yaml()
        cluster_info = get_cluster_info_from_yaml()

        if not groups:
            return jsonify({
                'success': False,
                'error': 'No nodes found in YAML configuration',
                'hint': 'Check if my_multihead_cluster.yaml exists and has compute_nodes defined'
            }), 400

        # 1. DB에 저장
        from database import get_db_connection
        import json

        config = {
            'groups': groups,
            'clusterName': cluster_info.get('clusterName', 'HPC Cluster'),
            'controllerIp': cluster_info.get('controllerIp', ''),
            'totalNodes': cluster_info.get('totalNodes', 0),
            'totalCores': cluster_info.get('totalCores', 0)
        }

        with get_db_connection() as conn:
            cursor = conn.cursor()

            # 기존 설정 확인
            cursor.execute("SELECT id FROM cluster_config WHERE id = 1")
            exists = cursor.fetchone()

            if exists:
                cursor.execute("""
                    UPDATE cluster_config
                    SET config = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE id = 1
                """, (json.dumps(config),))
            else:
                cursor.execute("""
                    INSERT INTO cluster_config (id, config)
                    VALUES (1, ?)
                """, (json.dumps(config),))

        print(f"✅ [Startup] Initialized {len(groups)} groups from YAML")
        print(f"   Compute nodes: {cluster_info.get('computeNodes', 0)}")
        print(f"   Viz nodes: {cluster_info.get('vizNodes', 0)}")

        # 2. Slurm 파티션 동기화
        slurm_result = sync_slurm_partitions_from_yaml()

        return jsonify({
            'success': True,
            'message': f'Initialized {len(groups)} groups from YAML',
            'groups_count': len(groups),
            'compute_nodes': cluster_info.get('computeNodes', 0),
            'viz_nodes': cluster_info.get('vizNodes', 0),
            'slurm_sync': slurm_result
        })

    except Exception as e:
        print(f"❌ [Startup] YAML initialization failed: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@yaml_loader_bp.route('/sync-partitions', methods=['POST'])
@jwt_required
@permission_required('admin')
def sync_partitions_endpoint():
    """
    수동으로 Slurm 파티션 동기화 실행
    admin 권한 필요
    """
    result = sync_slurm_partitions_from_yaml()
    return jsonify(result)


@yaml_loader_bp.route('/sync-partitions-local', methods=['POST'])
def sync_partitions_local_endpoint():
    """
    Slurm 파티션 동기화 (localhost 전용)
    start.sh 등에서 서버 시작 시 사용
    """
    remote_addr = request.remote_addr
    if remote_addr not in ['127.0.0.1', 'localhost', '::1']:
        return jsonify({
            'success': False,
            'error': 'This endpoint is only accessible from localhost'
        }), 403

    result = sync_slurm_partitions_from_yaml()
    return jsonify(result)


print("✅ YAML Node Loader API initialized")
