"""
Prometheus API
RESTful endpoints for Prometheus integration
"""

from flask import Blueprint, request, jsonify
import requests
import os
import random
import subprocess
from datetime import datetime, timedelta

# Slurm sinfo 절대경로 (systemd PATH 제한 대비)
try:
    from slurm_commands import SINFO
except ImportError:
    SINFO = '/usr/bin/sinfo'

# Create Blueprint
prometheus_bp = Blueprint('prometheus', __name__, url_prefix='/api/prometheus')

# Prometheus configuration
PROMETHEUS_URL = os.getenv('PROMETHEUS_URL', 'http://localhost:9090')
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# ============================================
# Helper Functions
# ============================================

def query_prometheus(endpoint: str, params: dict = None):
    """Query Prometheus API"""
    try:
        url = f"{PROMETHEUS_URL}/api/v1/{endpoint}"
        response = requests.get(url, params=params, timeout=5)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.ConnectionError as e:
        print(f"⚠️ Prometheus not reachable at {PROMETHEUS_URL}: {e}")
        return {'status': 'error', 'errorType': 'connection', 'error': 'Prometheus not available', 'data': {'result': []}}
    except requests.exceptions.Timeout as e:
        print(f"⚠️ Prometheus timeout: {e}")
        return {'status': 'error', 'errorType': 'timeout', 'error': 'Prometheus query timeout', 'data': {'result': []}}
    except Exception as e:
        print(f"❌ Prometheus query error: {e}")
        return None

def get_mock_instant_query(query: str):
    """Generate mock instant query response"""
    
    # GPU 관련 쿼리 처리
    if 'nvidia' in query.lower() or 'gpu' in query.lower():
        return get_mock_gpu_data(query)
    
    # 기본 mock 데이터
    mock_data = {
        'status': 'success',
        'data': {
            'resultType': 'vector',
            'result': [
                {
                    'metric': {
                        '__name__': query.split('{')[0] if '{' in query else query,
                        'instance': 'localhost:9090',
                        'job': 'node_exporter'
                    },
                    'value': [
                        datetime.now().timestamp(),
                        str(round(85.5 + (hash(query) % 10), 2))  # Pseudo-random value
                    ]
                }
            ]
        }
    }
    return mock_data

def get_mock_gpu_data(query: str):
    """Generate mock GPU data"""
    num_gpus = 4
    result = []
    
    # GPU 사용률 쿼리
    if 'utilization' in query.lower():
        for i in range(num_gpus):
            result.append({
                'metric': {
                    '__name__': 'nvidia_smi_utilization_gpu_ratio',
                    'gpu': str(i),
                    'minor_number': str(i),
                    'instance': 'localhost:9100',
                    'job': 'nvidia_exporter'
                },
                'value': [
                    datetime.now().timestamp(),
                    str(round(random.uniform(0.2, 0.95), 3))  # 0.2 ~ 0.95 (ratio)
                ]
            })
    
    # GPU 메모리 쿼리
    elif 'memory' in query.lower():
        for i in range(num_gpus):
            # Memory used / total * 100
            memory_percent = random.uniform(30, 95)
            result.append({
                'metric': {
                    '__name__': 'nvidia_smi_memory_used_bytes',
                    'gpu': str(i),
                    'minor_number': str(i),
                    'instance': 'localhost:9100',
                    'job': 'nvidia_exporter'
                },
                'value': [
                    datetime.now().timestamp(),
                    str(round(memory_percent, 2))
                ]
            })
    
    # GPU 온도 쿼리
    elif 'temperature' in query.lower():
        for i in range(num_gpus):
            result.append({
                'metric': {
                    '__name__': 'nvidia_smi_temperature_gpu',
                    'gpu': str(i),
                    'minor_number': str(i),
                    'instance': 'localhost:9100',
                    'job': 'nvidia_exporter'
                },
                'value': [
                    datetime.now().timestamp(),
                    str(round(random.uniform(45, 80), 1))  # 45°C ~ 80°C
                ]
            })
    
    # 일반 GPU 쿼리 (기본값)
    else:
        for i in range(num_gpus):
            result.append({
                'metric': {
                    '__name__': query.split('{')[0] if '{' in query else query,
                    'gpu': str(i),
                    'minor_number': str(i),
                    'instance': 'localhost:9100',
                    'job': 'nvidia_exporter'
                },
                'value': [
                    datetime.now().timestamp(),
                    str(round(random.uniform(60, 90), 2))
                ]
            })
    
    return {
        'status': 'success',
        'data': {
            'resultType': 'vector',
            'result': result
        }
    }

def get_mock_range_query(query: str, start: str, end: str, step: str):
    """Generate mock range query response with multiple time series"""
    import math
    
    start_time = datetime.fromisoformat(start.replace('Z', '+00:00'))
    end_time = datetime.fromisoformat(end.replace('Z', '+00:00'))
    step_seconds = int(step.rstrip('s'))
    
    # 여러 시계열을 생성할지 결정
    results = []
    
    # GPU 관련 쿼리
    if 'nvidia' in query.lower() or 'gpu' in query.lower():
        num_gpus = 4
        for gpu_idx in range(num_gpus):
            values = []
            current = start_time
            base_value = 60 + (gpu_idx * 10) + random.uniform(-5, 5)
            
            while current <= end_time:
                timestamp = current.timestamp()
                offset = math.sin(timestamp / 1000 + gpu_idx) * 15
                value = max(0, base_value + offset)
                values.append([timestamp, str(round(value, 2))])
                current += timedelta(seconds=step_seconds)
            
            results.append({
                'metric': {
                    '__name__': query.split('{')[0].split('(')[0].strip() if any(c in query for c in ['{', '(']) else query.split()[0],
                    'gpu': str(gpu_idx),
                    'instance': f'node{gpu_idx//2 + 1}:9100',
                    'job': 'nvidia_exporter'
                },
                'values': values
            })
    
    # 'or' 연산자가 있는 쿼리 (비교 쿼리)
    elif ' or ' in query.lower():
        # 쿼리를 ' or '로 분리
        sub_queries = [q.strip() for q in query.split(' or ')]
        print(f"[Mock] Detected comparison query with {len(sub_queries)} sub-queries")
        
        # 각 sub-query에 대해 2-3개 시계열 생성
        for sub_idx, sub_query in enumerate(sub_queries):
            # 메트릭 이름 추출
            metric_name = sub_query.split('{')[0].split('(')[0].strip()
            if not metric_name or metric_name in ['100', '-', '+', '*', '/']:
                metric_name = f'metric_{sub_idx}'
            
            # 각 sub-query당 2-3개 노드
            num_nodes = 2 + (sub_idx % 2)
            for node_idx in range(num_nodes):
                values = []
                current = start_time
                base_value = 40 + (sub_idx * 20) + (node_idx * 10) + random.uniform(-5, 5)
                
                while current <= end_time:
                    timestamp = current.timestamp()
                    offset = math.sin(timestamp / 800 + sub_idx + node_idx) * 12
                    value = max(0, min(100, base_value + offset))
                    values.append([timestamp, str(round(value, 2))])
                    current += timedelta(seconds=step_seconds)
                
                results.append({
                    'metric': {
                        '__name__': metric_name,
                        'instance': f'node{node_idx + 1}:9100',
                        'job': 'node_exporter'
                    },
                    'values': values
                })
    
    # topk() 함수가 있는 쿼리
    elif 'topk(' in query.lower():
        # topk(5, ...) -> 5개 시계열
        try:
            k = int(query.split('topk(')[1].split(',')[0].strip())
        except:
            k = 5
        
        print(f"[Mock] Detected topk query, generating {k} time series")
        
        for i in range(k):
            values = []
            current = start_time
            # 높은 값부터 낮은 값으로
            base_value = 90 - (i * 10) + random.uniform(-3, 3)
            
            while current <= end_time:
                timestamp = current.timestamp()
                offset = math.sin(timestamp / 1200 + i) * 8
                value = max(0, min(100, base_value + offset))
                values.append([timestamp, str(round(value, 2))])
                current += timedelta(seconds=step_seconds)
            
            results.append({
                'metric': {
                    '__name__': query.split('{')[0].split('(')[-1].strip() if '(' in query else 'metric',
                    'instance': f'node{i + 1}:9100',
                    'job': 'node_exporter'
                },
                'values': values
            })
    
    # by (instance, cpu) 같은 그룹화가 있는 쿼리
    elif 'by (instance, cpu)' in query or 'by(instance,cpu)' in query:
        num_nodes = 2
        num_cpus = 4
        print(f"[Mock] Detected per-core query, generating {num_nodes}x{num_cpus} time series")
        
        for node_idx in range(num_nodes):
            for cpu_idx in range(num_cpus):
                values = []
                current = start_time
                base_value = 30 + random.uniform(0, 50)
                
                while current <= end_time:
                    timestamp = current.timestamp()
                    offset = math.sin(timestamp / 900 + node_idx + cpu_idx) * 20
                    value = max(0, min(100, base_value + offset))
                    values.append([timestamp, str(round(value, 2))])
                    current += timedelta(seconds=step_seconds)
                
                results.append({
                    'metric': {
                        '__name__': query.split('{')[0].split('(')[0].strip() if any(c in query for c in ['{', '(']) else query.split()[0],
                        'instance': f'node{node_idx + 1}:9100',
                        'cpu': str(cpu_idx),
                        'job': 'node_exporter'
                    },
                    'values': values
                })
    
    # by (instance) 그룹화가 있는 쿼리 (다중 노드)
    elif 'by (instance)' in query or 'by(instance)' in query:
        num_nodes = 3
        print(f"[Mock] Detected per-instance query, generating {num_nodes} time series")
        
        for node_idx in range(num_nodes):
            values = []
            current = start_time
            base_value = 50 + (node_idx * 15) + random.uniform(-8, 8)
            
            while current <= end_time:
                timestamp = current.timestamp()
                offset = math.sin(timestamp / 1000 + node_idx) * 12
                value = max(0, min(100, base_value + offset))
                values.append([timestamp, str(round(value, 2))])
                current += timedelta(seconds=step_seconds)
            
            results.append({
                'metric': {
                    '__name__': query.split('{')[0].split('(')[0].strip() if any(c in query for c in ['{', '(']) else query.split()[0],
                    'instance': f'node{node_idx + 1}:9100',
                    'job': 'node_exporter'
                },
                'values': values
            })
    
    # 기본: 단일 시계열
    else:
        values = []
        current = start_time
        base_value = 70 + (hash(query) % 20)
        
        while current <= end_time:
            timestamp = current.timestamp()
            offset = math.sin(timestamp / 1000) * 10
            value = base_value + offset
            values.append([timestamp, str(round(value, 2))])
            current += timedelta(seconds=step_seconds)
        
        results.append({
            'metric': {
                '__name__': query.split('{')[0] if '{' in query else query.split('(')[0].strip() if '(' in query else query.split()[0],
                'instance': 'localhost:9100',
                'job': 'node_exporter'
            },
            'values': values
        })
    
    print(f"[Mock] Generated {len(results)} time series for query: {query[:100]}")
    
    return {
        'status': 'success',
        'data': {
            'resultType': 'matrix',
            'result': results
        }
    }

# ============================================
# GET /api/prometheus/query
# Instant query
# ============================================
@prometheus_bp.route('/query', methods=['GET'])
def instant_query():
    """
    Execute instant Prometheus query
    Query params:
        - query: PromQL expression (required)
        - time: Evaluation timestamp (optional)
    """
    query = request.args.get('query')
    time = request.args.get('time')
    
    if not query:
        return jsonify({'error': 'Query parameter is required'}), 400
    
    if MOCK_MODE:
        print(f"📊 [MOCK] Prometheus instant query: {query}")
        data = get_mock_instant_query(query)
        return jsonify(data)
    
    # Production mode
    params = {'query': query}
    if time:
        params['time'] = time
    
    data = query_prometheus('query', params)

    if data is None:
        return jsonify({'status': 'error', 'error': 'Failed to query Prometheus', 'data': {'result': []}}), 503

    return jsonify(data)

# ============================================
# GET /api/prometheus/cluster_cpu
# 클러스터 전체 평균 CPU 사용률 (Slurm 기반)
# ============================================
@prometheus_bp.route('/cluster_cpu', methods=['GET'])
def cluster_cpu():
    """클러스터 전체 노드 평균 CPU 사용률(%).

    node_exporter 가 헤드노드에만 떠있어 Prometheus(node_cpu_*) 로는 헤드 CPU 만
    보였다(Custom Dashboard 가 헤드만 표시한 원인). node_exporter 를 전노드 배포하는
    대신, Slurm sinfo 의 CPULoad(%O)/CPUs(%c) 로 노드별 사용률을 구해 평균낸다(전노드).
      노드 CPU% = min(100, CPULoad / CPUs * 100),  클러스터값 = 응답노드 평균.
    Returns {cpu_percent, node_count, source}.
    """
    if MOCK_MODE:
        return jsonify({'cpu_percent': round(45 + random.random() * 30, 1),
                        'node_count': 0, 'source': 'mock'})
    try:
        # -N: 노드별, -h: 헤더없음. %n=hostname %O=CPULoad %c=CPUs/node
        r = subprocess.run([SINFO, '-h', '-N', '-o', '%n|%O|%c'],
                           capture_output=True, text=True, timeout=8)
        nodes = {}  # hostname -> cpu% (파티션 중복 노드 dedupe)
        for line in r.stdout.splitlines():
            parts = line.split('|')
            if len(parts) < 3:
                continue
            host, load, cpus = parts[0].strip(), parts[1].strip(), parts[2].strip()
            if not host or host in nodes:
                continue
            try:
                lf = float(load); ci = int(cpus)   # CPULoad=N/A(다운/미응답) → except 로 제외
            except ValueError:
                continue
            if ci > 0:
                nodes[host] = min(100.0, max(0.0, lf / ci * 100.0))
        if nodes:
            avg = sum(nodes.values()) / len(nodes)
            return jsonify({'cpu_percent': round(avg, 1), 'node_count': len(nodes),
                            'source': 'slurm-cpuload'})
        return jsonify({'cpu_percent': 0, 'node_count': 0, 'source': 'slurm-cpuload'})
    except Exception as e:
        return jsonify({'error': str(e), 'cpu_percent': 0, 'node_count': 0, 'source': 'slurm-cpuload'}), 200

# ============================================
# GET /api/prometheus/query_range
# Range query
# ============================================
@prometheus_bp.route('/query_range', methods=['GET'])
def range_query():
    """
    Execute range Prometheus query
    Query params:
        - query: PromQL expression (required)
        - start: Start timestamp (required)
        - end: End timestamp (required)
        - step: Query resolution step (required)
    """
    query = request.args.get('query')
    start = request.args.get('start')
    end = request.args.get('end')
    step = request.args.get('step', '15s')
    
    if not all([query, start, end]):
        return jsonify({'error': 'query, start, and end parameters are required'}), 400
    
    if MOCK_MODE:
        print(f"📊 [MOCK] Prometheus range query: {query} ({start} to {end})")
        data = get_mock_range_query(query, start, end, step)
        return jsonify(data)
    
    # Production mode
    params = {
        'query': query,
        'start': start,
        'end': end,
        'step': step
    }
    
    data = query_prometheus('query_range', params)
    
    if data is None:
        return jsonify({'status': 'error', 'error': 'Failed to query Prometheus', 'data': {'result': []}}), 503
    
    return jsonify(data)

# ============================================
# GET /api/prometheus/labels
# Get label names
# ============================================
@prometheus_bp.route('/labels', methods=['GET'])
def get_labels():
    """Get all label names"""
    if MOCK_MODE:
        return jsonify({
            'status': 'success',
            'data': ['__name__', 'instance', 'job', 'device', 'cpu', 'mode', 'gpu']
        })
    
    data = query_prometheus('labels')
    
    if data is None:
        return jsonify({'status': 'error', 'error': 'Failed to get labels', 'data': []}), 503
    
    return jsonify(data)

# ============================================
# GET /api/prometheus/label/<label_name>/values
# Get label values
# ============================================
@prometheus_bp.route('/label/<label_name>/values', methods=['GET'])
def get_label_values(label_name):
    """Get values for a specific label"""
    if MOCK_MODE:
        mock_values = {
            'job': ['node_exporter', 'slurm_exporter', 'prometheus', 'nvidia_exporter'],
            'instance': ['localhost:9090', 'node01:9100', 'node02:9100'],
            '__name__': ['node_cpu_seconds_total', 'node_memory_MemTotal_bytes', 'up', 'nvidia_smi_utilization_gpu_ratio'],
            'gpu': ['0', '1', '2', '3']
        }
        return jsonify({
            'status': 'success',
            'data': mock_values.get(label_name, [])
        })
    
    data = query_prometheus(f'label/{label_name}/values')
    
    if data is None:
        return jsonify({'status': 'error', 'error': f'Failed to get values for label {label_name}', 'data': []}), 503
    
    return jsonify(data)

# ============================================
# GET /api/prometheus/series
# Get time series
# ============================================
@prometheus_bp.route('/series', methods=['GET'])
def get_series():
    """
    Get time series matching a label set
    Query params:
        - match[]: Series selector (required, can be repeated)
        - start: Start timestamp (optional)
        - end: End timestamp (optional)
    """
    matches = request.args.getlist('match[]')
    start = request.args.get('start')
    end = request.args.get('end')
    
    if not matches:
        return jsonify({'error': 'At least one match[] parameter is required'}), 400
    
    if MOCK_MODE:
        return jsonify({
            'status': 'success',
            'data': [
                {
                    '__name__': 'node_cpu_seconds_total',
                    'instance': 'localhost:9090',
                    'job': 'node_exporter',
                    'mode': 'idle',
                    'cpu': '0'
                },
                {
                    '__name__': 'nvidia_smi_utilization_gpu_ratio',
                    'instance': 'localhost:9100',
                    'job': 'nvidia_exporter',
                    'gpu': '0'
                }
            ]
        })
    
    params = {'match[]': matches}
    if start:
        params['start'] = start
    if end:
        params['end'] = end
    
    data = query_prometheus('series', params)
    
    if data is None:
        return jsonify({'status': 'error', 'error': 'Failed to get series', 'data': []}), 503
    
    return jsonify(data)

# ============================================
# GET /api/prometheus/targets
# Get targets
# ============================================
@prometheus_bp.route('/targets', methods=['GET'])
def get_targets():
    """Get all targets"""
    if MOCK_MODE:
        return jsonify({
            'status': 'success',
            'data': {
                'activeTargets': [
                    {
                        'discoveredLabels': {
                            '__address__': 'localhost:9090',
                            '__metrics_path__': '/metrics',
                            '__scheme__': 'http',
                            'job': 'prometheus'
                        },
                        'labels': {
                            'instance': 'localhost:9090',
                            'job': 'prometheus'
                        },
                        'scrapePool': 'prometheus',
                        'scrapeUrl': 'http://localhost:9090/metrics',
                        'lastError': '',
                        'lastScrape': datetime.now().isoformat(),
                        'lastScrapeDuration': 0.023,
                        'health': 'up'
                    },
                    {
                        'discoveredLabels': {
                            '__address__': 'localhost:9100',
                            '__metrics_path__': '/metrics',
                            '__scheme__': 'http',
                            'job': 'node_exporter'
                        },
                        'labels': {
                            'instance': 'localhost:9100',
                            'job': 'node_exporter'
                        },
                        'scrapePool': 'node_exporter',
                        'scrapeUrl': 'http://localhost:9100/metrics',
                        'lastError': '',
                        'lastScrape': datetime.now().isoformat(),
                        'lastScrapeDuration': 0.045,
                        'health': 'up'
                    }
                ],
                'droppedTargets': []
            }
        })
    
    data = query_prometheus('targets')
    
    if data is None:
        return jsonify({'status': 'error', 'error': 'Failed to get targets', 'data': {'activeTargets': [], 'droppedTargets': []}}), 503
    
    return jsonify(data)

# ============================================
# GET /api/prometheus/rules
# Get recording and alerting rules
# ============================================
@prometheus_bp.route('/rules', methods=['GET'])
def get_rules():
    """Get all rules"""
    if MOCK_MODE:
        return jsonify({
            'status': 'success',
            'data': {
                'groups': [
                    {
                        'name': 'node_alerts',
                        'file': '/etc/prometheus/rules.yml',
                        'interval': 30,
                        'rules': [
                            {
                                'name': 'HighCPUUsage',
                                'query': 'node_cpu_usage > 90',
                                'duration': 300,
                                'labels': {
                                    'severity': 'warning'
                                },
                                'annotations': {
                                    'summary': 'High CPU usage detected',
                                    'description': 'CPU usage is above 90% for 5 minutes'
                                },
                                'health': 'ok',
                                'type': 'alerting'
                            }
                        ]
                    }
                ]
            }
        })
    
    data = query_prometheus('rules')
    
    if data is None:
        return jsonify({'status': 'error', 'error': 'Failed to get rules', 'data': {'groups': []}}), 503
    
    return jsonify(data)

# ============================================
# GET /api/prometheus/alerts
# Get active alerts
# ============================================
@prometheus_bp.route('/alerts', methods=['GET'])
def get_alerts():
    """Get all active alerts"""
    if MOCK_MODE:
        return jsonify({
            'status': 'success',
            'data': {
                'alerts': [
                    {
                        'labels': {
                            'alertname': 'HighCPUUsage',
                            'instance': 'localhost:9100',
                            'severity': 'warning'
                        },
                        'annotations': {
                            'summary': 'High CPU usage detected',
                            'description': 'CPU usage is above 90% for 5 minutes'
                        },
                        'state': 'firing',
                        'activeAt': datetime.now().isoformat(),
                        'value': '95.2'
                    }
                ]
            }
        })
    
    data = query_prometheus('alerts')
    
    if data is None:
        return jsonify({'status': 'error', 'error': 'Failed to get alerts', 'data': {'alerts': []}}), 503
    
    return jsonify(data)

# ============================================
# GET /api/prometheus/status/config
# Get Prometheus configuration
# ============================================
@prometheus_bp.route('/status/config', methods=['GET'])
def get_config():
    """Get Prometheus configuration"""
    if MOCK_MODE:
        return jsonify({
            'status': 'success',
            'data': {
                'yaml': 'global:\n  scrape_interval: 15s\n  evaluation_interval: 15s\n\nscrape_configs:\n  - job_name: prometheus\n    static_configs:\n      - targets: [localhost:9090]\n  - job_name: node_exporter\n    static_configs:\n      - targets: [localhost:9100]'
            }
        })
    
    data = query_prometheus('status/config')
    
    if data is None:
        return jsonify({'status': 'error', 'error': 'Failed to get config', 'data': {}}), 503
    
    return jsonify(data)

# ============================================
# Health Check
# ============================================
@prometheus_bp.route('/health', methods=['GET'])
def health_check():
    """Check Prometheus connection"""
    if MOCK_MODE:
        return jsonify({
            'status': 'healthy',
            'mode': 'mock',
            'prometheus_url': PROMETHEUS_URL
        })
    
    try:
        response = requests.get(f"{PROMETHEUS_URL}/-/healthy", timeout=2)
        if response.status_code == 200:
            return jsonify({
                'status': 'healthy',
                'mode': 'production',
                'prometheus_url': PROMETHEUS_URL
            })
        else:
            return jsonify({
                'status': 'unhealthy',
                'mode': 'production',
                'prometheus_url': PROMETHEUS_URL,
                'error': f'HTTP {response.status_code}'
            }), 503
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'mode': 'production',
            'prometheus_url': PROMETHEUS_URL,
            'error': str(e)
        }), 503

print("✅ Prometheus API initialized")
