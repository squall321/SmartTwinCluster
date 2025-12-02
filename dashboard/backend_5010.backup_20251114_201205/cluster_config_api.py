"""
Cluster Configuration API
클러스터 구성 정보 저장 및 조회
"""

from flask import Blueprint, request, jsonify
import os
import json
from datetime import datetime
from database import get_db_connection

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
                # DB에 없으면 Mock 데이터 반환
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'config': {
                        'groups': MOCK_GROUPS,
                        'clusterName': 'HPC-Cluster-370',
                        'controllerIp': '192.168.1.10',
                        'totalNodes': 370
                    },
                    'note': 'Using default configuration (not saved yet)'
                })
        
    except Exception as e:
        print(f"❌ Error getting cluster config: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@cluster_config_bp.route('/config', methods=['POST'])
def save_cluster_config():
    """
    클러스터 구성 저장
    Body:
        {
            "groups": [...],
            "clusterName": "...",
            "controllerIp": "...",
            "totalNodes": 370
        }
    """
    try:
        config = request.json
        
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
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': 'Configuration saved successfully'
        })
        
    except Exception as e:
        print(f"❌ Error saving cluster config: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


print("✅ Cluster Config API initialized")
