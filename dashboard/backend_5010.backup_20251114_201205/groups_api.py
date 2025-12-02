"""
Cluster Groups API
클러스터 그룹 정보 조회 (Job Templates용)
"""

from flask import Blueprint, jsonify
import os
import json
from database import get_db_connection

groups_bp = Blueprint('groups', __name__, url_prefix='/api/groups')

# 노드당 CPU 코어 수 (고정값)
CPUS_PER_NODE = 128

# Mock 모드 체크 함수 (매번 환경변수 확인)
def is_mock_mode():
    """현재 MOCK_MODE 환경변수 확인"""
    return os.getenv('MOCK_MODE', 'true').lower() == 'true'

# Mock 그룹 데이터 - 실제 initialData.ts와 일치하도록 수정
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


def calculate_node_config(total_cores):
    """
    총 코어 수를 노드 수와 노드당 CPU로 변환
    
    Args:
        total_cores: 총 코어 수 (예: 8192)
    
    Returns:
        dict: {
            'nodes': 노드 수,
            'cpus_per_node': 노드당 CPU 수 (최대 128),
            'total_cores': 총 코어 수
        }
    """
    if total_cores <= CPUS_PER_NODE:
        # 1개 노드로 처리 가능
        return {
            'nodes': 1,
            'cpus_per_node': total_cores,
            'total_cores': total_cores
        }
    else:
        # 여러 노드 필요
        nodes = (total_cores + CPUS_PER_NODE - 1) // CPUS_PER_NODE  # 올림 계산
        cpus_per_node = CPUS_PER_NODE
        return {
            'nodes': nodes,
            'cpus_per_node': cpus_per_node,
            'total_cores': nodes * cpus_per_node
        }


def get_groups_from_db():
    """데이터베이스에서 그룹 정보 가져오기"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT config FROM cluster_config WHERE id = 1")
            row = cursor.fetchone()
            
            if row:
                config = json.loads(row[0])
                return config.get('groups', MOCK_GROUPS)
            else:
                # DB에 없으면 Mock 데이터 사용
                return MOCK_GROUPS
    except Exception as e:
        print(f"⚠️  Error reading groups from DB, using mock data: {e}")
        return MOCK_GROUPS


@groups_bp.route('', methods=['GET'])
def get_groups():
    """
    모든 그룹 정보 조회
    Returns:
        {
            "success": true,
            "groups": [
                {
                    "id": 1,
                    "name": "Group 1",
                    "partitionName": "group1",
                    "qosName": "group1_qos",
                    "allowedCoreSizes": [8192],
                    "color": "#3b82f6",
                    "description": "Large scale jobs"
                },
                ...
            ]
        }
    """
    try:
        if is_mock_mode():
            groups = MOCK_GROUPS
            mode = 'mock'
        else:
            # Production: DB에서 실제 클러스터 구성 가져오기
            groups = get_groups_from_db()
            mode = 'production'
        
        return jsonify({
            'success': True,
            'mode': mode,
            'groups': groups
        })
        
    except Exception as e:
        print(f"❌ Error getting groups: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@groups_bp.route('/partitions', methods=['GET'])
def get_partitions():
    """
    파티션 목록만 간단히 조회
    각 allowedCoreSize에 대해 nodes와 cpus_per_node 계산 포함
    
    Returns:
        {
            "success": true,
            "partitions": [
                {
                    "name": "group1", 
                    "label": "Group 1", 
                    "allowedCoreSizes": [8192],
                    "allowedConfigs": [
                        {
                            "total_cores": 8192,
                            "nodes": 64,
                            "cpus_per_node": 128
                        }
                    ],
                    "description": "Large scale jobs"
                },
                ...
            ]
        }
    """
    try:
        if is_mock_mode():
            groups = MOCK_GROUPS
            mode = 'mock'
        else:
            # Production: DB에서 실제 클러스터 구성 가져오기
            groups = get_groups_from_db()
            mode = 'production'
        
        partitions = []
        for g in groups:
            # 각 allowedCoreSize에 대해 노드 구성 계산
            allowed_configs = [
                calculate_node_config(cores) 
                for cores in g['allowedCoreSizes']
            ]
            
            partitions.append({
                'name': g['partitionName'],
                'label': g['name'],
                'allowedCoreSizes': g['allowedCoreSizes'],
                'allowedConfigs': allowed_configs,
                'description': g.get('description', '')
            })
        
        return jsonify({
            'success': True,
            'mode': mode,
            'partitions': partitions,
            'cpus_per_node': CPUS_PER_NODE
        })
        
    except Exception as e:
        print(f"❌ Error getting partitions: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


print("✅ Groups API initialized")
