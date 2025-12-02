"""
디스크 사용량 알림 API 엔드포인트
"""

from flask import Blueprint, jsonify, request
from disk_alerts import (
    disk_alert_system,
    check_data_storage,
    check_scratch_nodes,
    get_all_alerts
)

alerts_bp = Blueprint('alerts', __name__)


@alerts_bp.route('/api/alerts/disk/check', methods=['POST'])
def check_disk_alerts():
    """
    디스크 사용량 체크 및 알림 생성
    
    Request:
        {
            "storage_type": "data" | "scratch",
            "nodes_data": [  // scratch인 경우
                {
                    "node": "node001",
                    "usage_percent": 85.5
                }
            ]
        }
    """
    try:
        data = request.json
        storage_type = data.get('storage_type', 'data')
        
        alerts = []
        
        if storage_type == 'data':
            alert = check_data_storage()
            if alert:
                alerts.append(alert)
        
        elif storage_type == 'scratch':
            nodes_data = data.get('nodes_data', [])
            alerts = check_scratch_nodes(nodes_data)
        
        return jsonify({
            'success': True,
            'alerts': alerts,
            'has_alerts': len(alerts) > 0
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@alerts_bp.route('/api/alerts/disk', methods=['GET'])
def get_disk_alerts():
    """모든 디스크 알림 조회"""
    try:
        result = get_all_alerts()
        
        return jsonify({
            'success': True,
            'data': result
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@alerts_bp.route('/api/alerts/disk/clear', methods=['POST'])
def clear_disk_alerts():
    """알림 초기화"""
    try:
        disk_alert_system.clear_alerts()
        
        return jsonify({
            'success': True,
            'message': 'All alerts cleared'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@alerts_bp.route('/api/alerts/disk/thresholds', methods=['PUT'])
def update_thresholds():
    """
    임계값 업데이트
    
    Request:
        {
            "warning": 75,
            "critical": 90
        }
    """
    try:
        data = request.json
        
        if 'warning' in data:
            disk_alert_system.warning_threshold = int(data['warning'])
        
        if 'critical' in data:
            disk_alert_system.critical_threshold = int(data['critical'])
        
        return jsonify({
            'success': True,
            'thresholds': {
                'warning': disk_alert_system.warning_threshold,
                'critical': disk_alert_system.critical_threshold
            }
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
