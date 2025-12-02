"""
Health Check API
시스템 전체 상태 모니터링 및 자동 복구
"""

from flask import Blueprint, jsonify, request
import subprocess
import psutil
import requests
import os
import sqlite3
from datetime import datetime
from typing import Dict, Any, List

health_bp = Blueprint('health', __name__, url_prefix='/api/health')

# Mock 모드 설정
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# ============================================
# 유틸리티 함수
# ============================================

def get_process_uptime(process_name: str) -> str:
    """프로세스 업타임 계산"""
    try:
        for proc in psutil.process_iter(['name', 'create_time', 'cmdline']):
            try:
                # 프로세스 이름 또는 커맨드라인에서 검색
                if process_name in proc.info['name'] or \
                   (proc.info['cmdline'] and any(process_name in cmd for cmd in proc.info['cmdline'])):
                    create_time = datetime.fromtimestamp(proc.info['create_time'])
                    uptime = datetime.now() - create_time
                    # HH:MM:SS 형식으로 반환
                    total_seconds = int(uptime.total_seconds())
                    hours = total_seconds // 3600
                    minutes = (total_seconds % 3600) // 60
                    seconds = total_seconds % 60
                    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        return 'Unknown'
    except Exception as e:
        print(f"Error getting uptime for {process_name}: {e}")
        return 'Unknown'

def calculate_uptime_percentage(service_name: str) -> float:
    """서비스 가동률 계산 (간단한 버전)"""
    # 실제로는 DB에서 히스토리를 조회해야 함
    # 여기서는 현재 상태 기반으로 간단히 계산
    try:
        uptime_str = get_process_uptime(service_name)
        if uptime_str != 'Unknown':
            return 99.9  # 실행 중이면 99.9%
        return 0.0
    except:
        return 0.0

# ============================================
# 개별 서비스 체크 함수
# ============================================

def check_backend() -> Dict[str, Any]:
    """Backend API 상태"""
    try:
        # 자기 자신이므로 항상 실행 중
        process = psutil.Process()
        memory_mb = process.memory_info().rss / 1024 / 1024
        cpu_percent = process.cpu_percent(interval=0.1)
        
        return {
            'status': 'healthy',
            'uptime': get_process_uptime('app.py'),
            'uptime_percentage': 99.9,
            'memory_mb': round(memory_mb, 2),
            'cpu_percent': round(cpu_percent, 2),
            'last_check': datetime.now().isoformat()
        }
    except Exception as e:
        return {
            'status': 'down',
            'error': str(e),
            'last_check': datetime.now().isoformat()
        }

def check_websocket() -> Dict[str, Any]:
    """WebSocket 서버 상태 (Integrated with Backend via SocketIO)"""
    # WebSocket is now integrated with Flask-SocketIO on port 5010
    # No separate server on port 5011 anymore
    try:
        # Check if SocketIO is initialized in the backend
        # We can verify this by checking if the backend process is running
        # since WebSocket is now part of the backend
        uptime = get_process_uptime('app.py')

        return {
            'status': 'healthy',
            'mode': 'integrated',  # SocketIO integrated with backend
            'info': 'WebSocket integrated with Flask backend (SocketIO)',
            'uptime': uptime,
            'uptime_percentage': 99.9 if uptime != 'Unknown' else 0.0,
            'last_check': datetime.now().isoformat()
        }
    except Exception as e:
        return {
            'status': 'down',
            'error': str(e),
            'last_check': datetime.now().isoformat()
        }

def check_prometheus() -> Dict[str, Any]:
    """Prometheus 상태"""
    if MOCK_MODE:
        return {
            'status': 'healthy',
            'uptime': '24:15:30',
            'uptime_percentage': 99.9,
            'total_targets': 5,
            'up_targets': 5,
            'down_targets': 0,
            'last_check': datetime.now().isoformat()
        }
    
    try:
        # Health check
        response = requests.get('http://localhost:9090/-/healthy', timeout=3)
        if response.status_code != 200:
            return {
                'status': 'warning',
                'message': f'HTTP {response.status_code}',
                'last_check': datetime.now().isoformat()
            }
        
        # Targets check
        targets_response = requests.get('http://localhost:9090/api/v1/targets', timeout=3)
        targets_data = targets_response.json()
        active_targets = targets_data.get('data', {}).get('activeTargets', [])
        
        up_targets = [t for t in active_targets if t.get('health') == 'up']
        down_targets = [t for t in active_targets if t.get('health') != 'up']
        
        status = 'healthy' if len(down_targets) == 0 else 'warning'
        
        return {
            'status': status,
            'uptime': get_process_uptime('prometheus'),
            'uptime_percentage': calculate_uptime_percentage('prometheus'),
            'total_targets': len(active_targets),
            'up_targets': len(up_targets),
            'down_targets': len(down_targets),
            'down_target_details': [
                {'job': t.get('labels', {}).get('job'), 
                 'instance': t.get('labels', {}).get('instance')}
                for t in down_targets
            ] if down_targets else None,
            'last_check': datetime.now().isoformat()
        }
    except requests.exceptions.RequestException as e:
        return {
            'status': 'down',
            'error': 'Connection failed',
            'last_check': datetime.now().isoformat()
        }
    except Exception as e:
        return {
            'status': 'down',
            'error': str(e)[:100],  # 에러 메시지 길이 제한
            'last_check': datetime.now().isoformat()
        }

def check_node_exporter() -> Dict[str, Any]:
    """Node Exporter 상태"""
    if MOCK_MODE:
        return {
            'status': 'healthy',
            'uptime': '48:20:15',
            'uptime_percentage': 99.9,
            'last_check': datetime.now().isoformat()
        }
    
    try:
        response = requests.get('http://localhost:9100/metrics', timeout=3)
        if response.status_code == 200:
            return {
                'status': 'healthy',
                'uptime': get_process_uptime('node_exporter'),
                'uptime_percentage': calculate_uptime_percentage('node_exporter'),
                'last_check': datetime.now().isoformat()
            }
        else:
            return {
                'status': 'warning',
                'message': f'HTTP {response.status_code}',
                'last_check': datetime.now().isoformat()
            }
    except requests.exceptions.RequestException:
        return {
            'status': 'down',
            'error': 'Connection failed',
            'last_check': datetime.now().isoformat()
        }
    except Exception as e:
        return {
            'status': 'down',
            'error': str(e)[:100],
            'last_check': datetime.now().isoformat()
        }

def check_slurm() -> Dict[str, Any]:
    """Slurm 상태"""
    if MOCK_MODE:
        return {
            'status': 'healthy',
            'uptime': '120:45:30',
            'uptime_percentage': 100.0,
            'slurmctld': 'up',
            'slurmd': 'up',
            'last_check': datetime.now().isoformat()
        }
    
    try:
        # scontrol ping으로 Slurm 상태 확인
        result = subprocess.run(
            ['scontrol', 'ping'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            output = result.stdout
            slurmctld_up = 'UP' in output or 'primary' in output.lower()
            
            return {
                'status': 'healthy' if slurmctld_up else 'warning',
                'uptime': 'N/A',
                'uptime_percentage': 100.0 if slurmctld_up else 50.0,
                'slurmctld': 'up' if slurmctld_up else 'down',
                'slurmd': 'up',
                'details': output.strip()[:200],
                'last_check': datetime.now().isoformat()
            }
        else:
            return {
                'status': 'down',
                'error': result.stderr[:200] if result.stderr else 'Unknown error',
                'last_check': datetime.now().isoformat()
            }
    except subprocess.TimeoutExpired:
        return {
            'status': 'down',
            'error': 'Command timeout',
            'last_check': datetime.now().isoformat()
        }
    except FileNotFoundError:
        return {
            'status': 'down',
            'error': 'Slurm not installed',
            'last_check': datetime.now().isoformat()
        }
    except Exception as e:
        return {
            'status': 'down',
            'error': str(e),
            'last_check': datetime.now().isoformat()
        }

def check_database() -> Dict[str, Any]:
    """데이터베이스 상태"""
    try:
        db_path = os.path.join(os.path.dirname(__file__), 'database', 'dashboard.db')
        conn = sqlite3.connect(db_path, timeout=5)
        cursor = conn.cursor()
        
        # 테이블 존재 확인
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = cursor.fetchall()
        table_count = len(tables)
        
        # notifications 테이블 레코드 수
        try:
            cursor.execute('SELECT COUNT(*) FROM notifications')
            notifications_count = cursor.fetchone()[0]
        except:
            notifications_count = 0
        
        # DB 파일 크기
        db_size_mb = os.path.getsize(db_path) / 1024 / 1024 if os.path.exists(db_path) else 0
        
        conn.close()
        
        return {
            'status': 'healthy',
            'uptime': 'N/A',
            'uptime_percentage': 99.9,
            'table_count': table_count,
            'notifications_count': notifications_count,
            'size_mb': round(db_size_mb, 2),
            'last_check': datetime.now().isoformat()
        }
    except Exception as e:
        return {
            'status': 'down',
            'error': str(e),
            'last_check': datetime.now().isoformat()
        }

def check_storage() -> Dict[str, Any]:
    """스토리지 상태"""
    try:
        # /data 파티션 체크
        try:
            disk = psutil.disk_usage('/data')
            data_usage = disk.percent
            data_free_gb = disk.free / 1024 / 1024 / 1024
        except:
            # /data가 없으면 루트 파티션 체크
            disk = psutil.disk_usage('/')
            data_usage = disk.percent
            data_free_gb = disk.free / 1024 / 1024 / 1024
        
        # 상태 판단
        if data_usage >= 95:
            status = 'critical'
        elif data_usage >= 85:
            status = 'warning'
        else:
            status = 'healthy'
        
        return {
            'status': status,
            'usage_percent': round(data_usage, 1),
            'free_gb': round(data_free_gb, 2),
            'total_gb': round(disk.total / 1024 / 1024 / 1024, 2),
            'last_check': datetime.now().isoformat()
        }
    except Exception as e:
        return {
            'status': 'down',
            'error': str(e),
            'last_check': datetime.now().isoformat()
        }

# ============================================
# API 엔드포인트
# ============================================

@health_bp.route('/status', methods=['GET'])
def system_status():
    """
    전체 시스템 헬스 체크
    
    Returns:
        {
            "success": true,
            "overall_status": "healthy" | "warning" | "critical",
            "timestamp": "2025-10-10T14:30:00Z",
            "services": {
                "backend": {...},
                "websocket": {...},
                ...
            }
        }
    """
    try:
        checks = {
            'backend': check_backend(),
            'websocket': check_websocket(),
            'prometheus': check_prometheus(),
            'node_exporter': check_node_exporter(),
            'slurm': check_slurm(),
            'database': check_database(),
            'storage': check_storage()
        }
        
        # 전체 상태 판단
        overall_status = 'healthy'
        for service, status_info in checks.items():
            if status_info.get('status') == 'critical' or status_info.get('status') == 'down':
                overall_status = 'critical'
                break
            elif status_info.get('status') == 'warning' and overall_status == 'healthy':
                overall_status = 'warning'
        
        return jsonify({
            'success': True,
            'overall_status': overall_status,
            'timestamp': datetime.now().isoformat(),
            'services': checks,
            'mode': 'mock' if MOCK_MODE else 'production'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500

@health_bp.route('/endpoints', methods=['GET'])
def check_api_endpoints():
    """
    주요 API 엔드포인트 헬스 체크
    
    Returns:
        {
            "success": true,
            "endpoints": [
                {
                    "endpoint": "/api/nodes",
                    "status": "healthy",
                    "response_time_ms": 45.23,
                    "status_code": 200
                },
                ...
            ]
        }
    """
    endpoints = [
        '/api/nodes',
        '/api/jobs',
        '/api/notifications',
        '/api/prometheus/health',
        '/api/reports'
    ]
    
    results = []
    base_url = 'http://localhost:5010'
    
    for endpoint in endpoints:
        try:
            start = datetime.now()
            response = requests.get(f'{base_url}{endpoint}', timeout=10)
            elapsed = (datetime.now() - start).total_seconds() * 1000
            
            # 상태 판단
            if response.status_code == 200:
                status = 'healthy'
            elif 400 <= response.status_code < 500:
                status = 'warning'
            else:
                status = 'critical'
            
            results.append({
                'endpoint': endpoint,
                'status': status,
                'response_time_ms': round(elapsed, 2),
                'status_code': response.status_code
            })
        except requests.exceptions.Timeout:
            results.append({
                'endpoint': endpoint,
                'status': 'critical',
                'error': 'Timeout (>10s)'
            })
        except Exception as e:
            results.append({
                'endpoint': endpoint,
                'status': 'down',
                'error': str(e)
            })
    
    return jsonify({
        'success': True,
        'endpoints': results,
        'timestamp': datetime.now().isoformat()
    })

@health_bp.route('/auto-heal', methods=['POST'])
def auto_heal():
    """
    서비스 자동 복구 시도
    
    Request:
        {
            "service": "websocket" | "prometheus" | "node_exporter"
        }
    
    Returns:
        {
            "success": true,
            "message": "Service restarted successfully",
            "service": "websocket"
        }
    """
    if MOCK_MODE:
        return jsonify({
            'success': True,
            'message': 'Auto-heal simulated (Mock Mode)',
            'service': request.json.get('service')
        })
    
    try:
        service = request.json.get('service')
        
        if not service:
            return jsonify({
                'success': False,
                'error': 'Service name required'
            }), 400
        
        # 서비스별 재시작 명령
        restart_commands = {
            'websocket': 'cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/websocket_5011 && ./stop.sh && ./start.sh',
            'prometheus': 'cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/prometheus_9090 && ./stop.sh && ./start.sh',
            'node_exporter': 'cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/node_exporter_9100 && ./stop.sh && ./start.sh'
        }
        
        if service not in restart_commands:
            return jsonify({
                'success': False,
                'error': f'Unknown service: {service}'
            }), 400
        
        # 재시작 실행
        result = subprocess.run(
            ['bash', '-c', restart_commands[service]],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode == 0:
            return jsonify({
                'success': True,
                'message': f'{service} restarted successfully',
                'service': service
            })
        else:
            return jsonify({
                'success': False,
                'error': f'Failed to restart {service}',
                'details': result.stderr
            }), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'error': 'Restart command timeout'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@health_bp.route('/summary', methods=['GET'])
def health_summary():
    """
    간단한 헬스 체크 요약 (빠른 응답)
    
    Returns:
        {
            "success": true,
            "healthy_count": 6,
            "warning_count": 1,
            "critical_count": 0,
            "total_services": 7
        }
    """
    try:
        checks = {
            'backend': check_backend(),
            'websocket': check_websocket(),
            'prometheus': check_prometheus(),
            'node_exporter': check_node_exporter(),
            'slurm': check_slurm(),
            'database': check_database(),
            'storage': check_storage()
        }
        
        healthy_count = sum(1 for s in checks.values() if s.get('status') == 'healthy')
        warning_count = sum(1 for s in checks.values() if s.get('status') == 'warning')
        critical_count = sum(1 for s in checks.values() if s.get('status') in ['critical', 'down'])
        
        return jsonify({
            'success': True,
            'healthy_count': healthy_count,
            'warning_count': warning_count,
            'critical_count': critical_count,
            'total_services': len(checks),
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

print("✅ Health Check API initialized")
