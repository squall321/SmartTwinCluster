"""
Monitoring and Metrics Module for Dashboard
Prometheus 메트릭, 로깅, 헬스체크를 위한 모니터링 모듈
"""

from prometheus_client import Counter, Histogram, Gauge, Info, generate_latest, CONTENT_TYPE_LATEST
from flask import Response
import time
import psutil
import os
from functools import wraps
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

# ============================================================================
# Prometheus 메트릭 정의
# ============================================================================

# API 요청 메트릭
api_requests_total = Counter(
    'api_requests_total',
    'Total API requests',
    ['method', 'endpoint', 'status']
)

api_request_duration_seconds = Histogram(
    'api_request_duration_seconds',
    'API request duration in seconds',
    ['method', 'endpoint'],
    buckets=(0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0)
)

# 캐시 메트릭
cache_hits_total = Counter(
    'cache_hits_total',
    'Total cache hits',
    ['cache_type']
)

cache_misses_total = Counter(
    'cache_misses_total',
    'Total cache misses',
    ['cache_type']
)

cache_size = Gauge(
    'cache_size_entries',
    'Current number of entries in cache',
    ['cache_type']
)

cache_evictions_total = Counter(
    'cache_evictions_total',
    'Total number of cache evictions',
    ['cache_type']
)

# SSH 연결 메트릭
ssh_connections_total = Counter(
    'ssh_connections_total',
    'Total SSH connection attempts',
    ['node', 'status']
)

ssh_connection_duration_seconds = Histogram(
    'ssh_connection_duration_seconds',
    'SSH connection duration in seconds',
    ['node'],
    buckets=(0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0)
)

ssh_command_errors_total = Counter(
    'ssh_command_errors_total',
    'Total SSH command errors',
    ['node', 'error_type']
)

# WebSocket 메트릭
websocket_connections = Gauge(
    'websocket_connections_active',
    'Number of active WebSocket connections'
)

websocket_messages_sent_total = Counter(
    'websocket_messages_sent_total',
    'Total WebSocket messages sent',
    ['message_type']
)

websocket_messages_received_total = Counter(
    'websocket_messages_received_total',
    'Total WebSocket messages received',
    ['message_type']
)

websocket_broadcast_duration_seconds = Histogram(
    'websocket_broadcast_duration_seconds',
    'WebSocket broadcast duration in seconds',
    buckets=(0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0)
)

# 스토리지 메트릭
storage_scan_duration_seconds = Histogram(
    'storage_scan_duration_seconds',
    'Storage scan duration in seconds',
    ['storage_type'],
    buckets=(0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0)
)

storage_usage_percent = Gauge(
    'storage_usage_percent',
    'Storage usage percentage',
    ['storage_type', 'path']
)

storage_capacity_bytes = Gauge(
    'storage_capacity_bytes',
    'Total storage capacity in bytes',
    ['storage_type', 'path']
)

storage_used_bytes = Gauge(
    'storage_used_bytes',
    'Used storage in bytes',
    ['storage_type', 'path']
)

# 노드 메트릭
node_scratch_usage_percent = Gauge(
    'node_scratch_usage_percent',
    'Scratch storage usage percentage per node',
    ['node']
)

node_status = Gauge(
    'node_status',
    'Node status (1=active, 0=inactive)',
    ['node']
)

# 시스템 메트릭
system_cpu_percent = Gauge(
    'system_cpu_percent',
    'System CPU usage percentage'
)

system_memory_percent = Gauge(
    'system_memory_percent',
    'System memory usage percentage'
)

system_memory_bytes = Gauge(
    'system_memory_bytes',
    'System memory in bytes',
    ['type']  # total, available, used
)

# 애플리케이션 정보
app_info = Info(
    'app_info',
    'Application information'
)

app_uptime_seconds = Gauge(
    'app_uptime_seconds',
    'Application uptime in seconds'
)

# ============================================================================
# 데코레이터: API 메트릭 자동 수집
# ============================================================================

def monitor_api(endpoint_name=None):
    """
    API 엔드포인트 모니터링 데코레이터
    
    사용법:
    @app.route('/api/data')
    @monitor_api('get_data')
    def get_data():
        ...
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            from flask import request
            
            # 엔드포인트 이름
            endpoint = endpoint_name or f.__name__
            method = request.method
            
            # 시작 시간
            start_time = time.time()
            
            # 함수 실행
            try:
                response = f(*args, **kwargs)
                
                # 상태 코드 추출
                if isinstance(response, tuple):
                    status = response[1] if len(response) > 1 else 200
                else:
                    status = 200
                
                # 메트릭 기록
                api_requests_total.labels(
                    method=method,
                    endpoint=endpoint,
                    status=status
                ).inc()
                
                return response
                
            except Exception as e:
                # 에러 메트릭
                api_requests_total.labels(
                    method=method,
                    endpoint=endpoint,
                    status=500
                ).inc()
                raise
                
            finally:
                # 소요 시간 기록
                duration = time.time() - start_time
                api_request_duration_seconds.labels(
                    method=method,
                    endpoint=endpoint
                ).observe(duration)
        
        return decorated_function
    return decorator


# ============================================================================
# 캐시 모니터링 함수
# ============================================================================

def record_cache_hit(cache_type: str):
    """캐시 히트 기록"""
    cache_hits_total.labels(cache_type=cache_type).inc()


def record_cache_miss(cache_type: str):
    """캐시 미스 기록"""
    cache_misses_total.labels(cache_type=cache_type).inc()


def update_cache_size(cache_type: str, size: int):
    """캐시 크기 업데이트"""
    cache_size.labels(cache_type=cache_type).set(size)


def record_cache_eviction(cache_type: str):
    """캐시 eviction 기록"""
    cache_evictions_total.labels(cache_type=cache_type).inc()


# ============================================================================
# SSH 모니터링 함수
# ============================================================================

def record_ssh_connection(node: str, success: bool, duration: float):
    """SSH 연결 기록"""
    status = 'success' if success else 'failure'
    ssh_connections_total.labels(node=node, status=status).inc()
    
    if success:
        ssh_connection_duration_seconds.labels(node=node).observe(duration)


def record_ssh_error(node: str, error_type: str):
    """SSH 에러 기록"""
    ssh_command_errors_total.labels(node=node, error_type=error_type).inc()


# ============================================================================
# WebSocket 모니터링 함수
# ============================================================================

def set_websocket_connections(count: int):
    """활성 WebSocket 연결 수 설정"""
    websocket_connections.set(count)


def record_websocket_message_sent(message_type: str):
    """WebSocket 메시지 전송 기록"""
    websocket_messages_sent_total.labels(message_type=message_type).inc()


def record_websocket_message_received(message_type: str):
    """WebSocket 메시지 수신 기록"""
    websocket_messages_received_total.labels(message_type=message_type).inc()


def record_websocket_broadcast(duration: float):
    """WebSocket 브로드캐스트 시간 기록"""
    websocket_broadcast_duration_seconds.observe(duration)


# ============================================================================
# 스토리지 모니터링 함수
# ============================================================================

def record_storage_scan(storage_type: str, duration: float):
    """스토리지 스캔 시간 기록"""
    storage_scan_duration_seconds.labels(storage_type=storage_type).observe(duration)


def update_storage_metrics(storage_type: str, path: str, total_bytes: int, used_bytes: int):
    """스토리지 메트릭 업데이트"""
    usage_percent = (used_bytes / total_bytes * 100) if total_bytes > 0 else 0
    
    storage_usage_percent.labels(storage_type=storage_type, path=path).set(usage_percent)
    storage_capacity_bytes.labels(storage_type=storage_type, path=path).set(total_bytes)
    storage_used_bytes.labels(storage_type=storage_type, path=path).set(used_bytes)


def update_node_metrics(node: str, usage_percent: float, is_active: bool):
    """노드 메트릭 업데이트"""
    node_scratch_usage_percent.labels(node=node).set(usage_percent)
    node_status.labels(node=node).set(1 if is_active else 0)


# ============================================================================
# 시스템 메트릭 수집
# ============================================================================

def collect_system_metrics():
    """시스템 메트릭 수집 (주기적으로 호출)"""
    try:
        # CPU 사용률
        cpu_percent = psutil.cpu_percent(interval=1)
        system_cpu_percent.set(cpu_percent)
        
        # 메모리 사용률
        memory = psutil.virtual_memory()
        system_memory_percent.set(memory.percent)
        system_memory_bytes.labels(type='total').set(memory.total)
        system_memory_bytes.labels(type='available').set(memory.available)
        system_memory_bytes.labels(type='used').set(memory.used)
        
    except Exception as e:
        logger.error(f"Error collecting system metrics: {e}")


# ============================================================================
# 애플리케이션 정보 설정
# ============================================================================

_app_start_time = time.time()

def set_app_info(version: str, mode: str):
    """애플리케이션 정보 설정"""
    app_info.info({
        'version': version,
        'mode': mode,
        'python_version': os.sys.version.split()[0],
        'start_time': datetime.fromtimestamp(_app_start_time).isoformat()
    })


def update_app_uptime():
    """애플리케이션 업타임 업데이트"""
    uptime = time.time() - _app_start_time
    app_uptime_seconds.set(uptime)


# ============================================================================
# Prometheus 메트릭 엔드포인트
# ============================================================================

def metrics_endpoint():
    """
    Prometheus 메트릭 엔드포인트
    Flask 앱에 등록:
    
    from monitoring import metrics_endpoint
    @app.route('/metrics')
    def metrics():
        return metrics_endpoint()
    """
    # 시스템 메트릭 업데이트
    collect_system_metrics()
    update_app_uptime()
    
    # Prometheus 형식으로 메트릭 반환
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


# ============================================================================
# 헬스 체크
# ============================================================================

def health_check():
    """
    상세한 헬스 체크
    Returns: dict with health status
    """
    try:
        # 시스템 상태
        cpu_percent = psutil.cpu_percent(interval=0.1)
        memory = psutil.virtual_memory()
        
        # 디스크 상태
        disk = psutil.disk_usage('/')
        
        # 상태 판단
        status = 'healthy'
        issues = []
        
        if cpu_percent > 90:
            issues.append('High CPU usage')
            status = 'degraded'
        
        if memory.percent > 90:
            issues.append('High memory usage')
            status = 'degraded'
        
        if disk.percent > 90:
            issues.append('High disk usage')
            status = 'degraded'
        
        return {
            'status': status,
            'timestamp': datetime.now().isoformat(),
            'uptime_seconds': time.time() - _app_start_time,
            'system': {
                'cpu_percent': cpu_percent,
                'memory_percent': memory.percent,
                'disk_percent': disk.percent
            },
            'issues': issues if issues else None
        }
    except Exception as e:
        logger.error(f"Health check error: {e}")
        return {
            'status': 'unhealthy',
            'timestamp': datetime.now().isoformat(),
            'error': str(e)
        }
