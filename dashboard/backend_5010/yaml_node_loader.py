"""
YAML Node Group Loader
YAML 설정 파일에서 노드 정보를 읽어 그룹으로 초기화
"""

import os
import yaml
from typing import List, Dict, Any, Optional
from flask import Blueprint, jsonify, request
from middleware.jwt_middleware import jwt_required, permission_required

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

        # DB에 저장
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

        return jsonify({
            'success': True,
            'message': f'Initialized {len(groups)} groups from YAML',
            'groups_count': len(groups),
            'compute_nodes': cluster_info.get('computeNodes', 0),
            'viz_nodes': cluster_info.get('vizNodes', 0)
        })

    except Exception as e:
        print(f"❌ [Startup] YAML initialization failed: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


print("✅ YAML Node Loader API initialized")
