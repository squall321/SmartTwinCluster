"""
Notifications API
RESTful endpoints for notification management
"""

from flask import Blueprint, request, jsonify
from datetime import datetime
import os
import requests

# Import database functions
from database import (
    create_notification,
    get_notifications,
    mark_notification_read,
    mark_all_notifications_read,
    delete_notification,
    get_unread_count
)

# WebSocket 브로드캐스트 헬퍼
def broadcast_notification_to_websocket(notification: dict):
    """WebSocket을 통해 알림 브로드캐스트"""
    try:
        response = requests.post(
            'http://localhost:5011/broadcast',
            json={
                'channel': 'notifications',
                'message': {
                    'type': 'notification',
                    'data': notification
                }
            },
            timeout=1
        )
        if response.status_code == 200:
            print(f"📤 Notification broadcasted to WebSocket clients")
    except Exception as e:
        print(f"⚠️ Failed to broadcast notification: {e}")

# Create Blueprint
notifications_bp = Blueprint('notifications', __name__, url_prefix='/api/notifications')

# Mock mode flag
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# ============================================
# GET /api/notifications
# ============================================
@notifications_bp.route('', methods=['GET'])
def get_all_notifications():
    """Get all notifications"""
    try:
        limit = int(request.args.get('limit', 50))
        unread_only = request.args.get('unread', 'false').lower() == 'true'
        
        if MOCK_MODE:
            # Mock notifications
            notifications = [
                {
                    'id': 'notif-001',
                    'type': 'job_completed',
                    'title': 'Job Completed',
                    'message': 'Job #12345 has finished successfully',
                    'timestamp': '2025-10-07T14:30:00Z',
                    'read': False,
                    'data': {'jobId': '12345', 'duration': '2h 30m'}
                },
                {
                    'id': 'notif-002',
                    'type': 'job_failed',
                    'title': 'Job Failed',
                    'message': 'Job #12346 failed with exit code 1',
                    'timestamp': '2025-10-07T13:45:00Z',
                    'read': False,
                    'data': {'jobId': '12346', 'exitCode': 1}
                },
                {
                    'id': 'notif-003',
                    'type': 'alert',
                    'title': 'High CPU Usage',
                    'message': 'Node compute-001 CPU usage is at 95%',
                    'timestamp': '2025-10-07T12:00:00Z',
                    'read': False,
                    'data': {'node': 'compute-001', 'metric': 'cpu', 'value': 95}
                },
                {
                    'id': 'notif-004',
                    'type': 'system',
                    'title': 'Maintenance Scheduled',
                    'message': 'System maintenance on 2025-10-15 from 2-4 AM',
                    'timestamp': '2025-10-07T10:00:00Z',
                    'read': True,
                    'data': {'date': '2025-10-15', 'duration': '2 hours'}
                },
                {
                    'id': 'notif-005',
                    'type': 'info',
                    'title': 'New Feature',
                    'message': 'Job templates are now available!',
                    'timestamp': '2025-10-06T16:00:00Z',
                    'read': True,
                    'data': {'feature': 'templates'}
                }
            ]
            
            if unread_only:
                notifications = [n for n in notifications if not n['read']]
            
            return jsonify({
                'success': True,
                'notifications': notifications[:limit],
                'unreadCount': sum(1 for n in notifications if not n['read'])
            })
        else:
            # Production mode - use database
            notifications = get_notifications(limit=limit, unread_only=unread_only)
            unread_count = get_unread_count()
            
            return jsonify({
                'success': True,
                'notifications': notifications,
                'unreadCount': unread_count
            })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ============================================
# POST /api/notifications
# ============================================
@notifications_bp.route('', methods=['POST'])
def create_new_notification():
    """Create a new notification"""
    try:
        data = request.json
        
        notif_type = data.get('type', 'info')
        title = data.get('title')
        message = data.get('message')
        notif_data = data.get('data')
        
        if not title or not message:
            return jsonify({
                'success': False,
                'error': 'Title and message are required'
            }), 400
        
        if MOCK_MODE:
            notif_id = f"notif-{int(datetime.now().timestamp() * 1000)}"
            notification = {
                'id': notif_id,
                'type': notif_type,
                'title': title,
                'message': message,
                'data': notif_data,
                'read': False,
                'timestamp': datetime.now().isoformat()
            }
            # WebSocket 브로드캐스트
            broadcast_notification_to_websocket(notification)
            return jsonify({
                'success': True,
                'id': notif_id,
                'message': 'Notification created (Mock Mode)'
            })
        else:
            notif_id = create_notification(notif_type, title, message, notif_data)
            # 생성된 알림 조회
            notifications = get_notifications(limit=1)
            if notifications:
                broadcast_notification_to_websocket(notifications[0])
            return jsonify({
                'success': True,
                'id': notif_id,
                'message': 'Notification created'
            })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ============================================
# POST /api/notifications/mark-read
# ============================================
@notifications_bp.route('/mark-read', methods=['POST'])
def mark_all_read():
    """Mark all notifications as read"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'message': 'All notifications marked as read (Mock Mode)',
                'count': 3
            })
        else:
            count = mark_all_notifications_read()
            return jsonify({
                'success': True,
                'message': 'All notifications marked as read',
                'count': count
            })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ============================================
# POST /api/notifications/:id/read
# ============================================
@notifications_bp.route('/<notif_id>/read', methods=['POST'])
def mark_read(notif_id):
    """Mark a specific notification as read"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'message': f'Notification {notif_id} marked as read (Mock Mode)'
            })
        else:
            success = mark_notification_read(notif_id)
            if success:
                return jsonify({
                    'success': True,
                    'message': 'Notification marked as read'
                })
            else:
                return jsonify({
                    'success': False,
                    'error': 'Notification not found'
                }), 404
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ============================================
# DELETE /api/notifications/:id
# ============================================
@notifications_bp.route('/<notif_id>', methods=['DELETE'])
def delete_notif(notif_id):
    """Delete a notification"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'message': f'Notification {notif_id} deleted (Mock Mode)'
            })
        else:
            success = delete_notification(notif_id)
            if success:
                return jsonify({
                    'success': True,
                    'message': 'Notification deleted'
                })
            else:
                return jsonify({
                    'success': False,
                    'error': 'Notification not found'
                }), 404
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ============================================
# GET /api/notifications/unread-count
# ============================================
@notifications_bp.route('/unread-count', methods=['GET'])
def get_unread_count_api():
    """Get unread notification count"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'count': 3
            })
        else:
            count = get_unread_count()
            return jsonify({
                'success': True,
                'count': count
            })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
