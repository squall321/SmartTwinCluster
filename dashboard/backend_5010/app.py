"""
Slurm Cluster Dashboard Backend API (Mock Mode 지원)
실시간 모니터링, 작업 관리, 3D 시각화 지원
🆕 Slurm 통합 기능 추가
"""

from flask import Flask, request, jsonify, g
from flask_cors import CORS
from flask_socketio import SocketIO
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import subprocess
import json
import os
from datetime import datetime
import random
import time
import tempfile
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# JWT middleware import
from middleware.jwt_middleware import jwt_required, permission_required, optional_jwt

# Slurm 설정 관리 모듈 임포트
from slurm_config_manager import (
    slurm_config,
    create_qos,
    update_partitions,
    reconfigure_slurm,
    apply_full_configuration
)

# Slurm 명령어 경로 모듈 임포트
try:
    from slurm_commands import (
        get_sinfo, get_squeue, get_sacct, get_scontrol, 
        get_sreport, SBATCH, SCANCEL, check_slurm_installation
    )
    # Slurm 설치 확인
    SLURM_AVAILABLE = check_slurm_installation()
    if not SLURM_AVAILABLE:
        print("⚠️  Warning: Slurm commands not available at expected location")
except Exception as e:
    print(f"⚠️  Could not import slurm_commands: {e}")
    SLURM_AVAILABLE = False

# Mock 모드 설정 (환경변수로 제어)
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

if MOCK_MODE:
    print("⚠️  Running in MOCK MODE - No actual Slurm commands will be executed")
else:
    print("✅ Running in PRODUCTION MODE - Real Slurm commands will be executed")

# Storage 관리 유틸리티 임포트 (Mock 모드에서는 선택적)
try:
    from storage_utils import (
        get_disk_usage,
        format_size,
        get_file_info,
        list_directory,
        count_files_recursive,
        get_directory_size,
        safe_path_join,
        is_path_accessible,
        search_files,
        get_slurm_nodes as get_storage_nodes,
        run_remote_command
    )
except ImportError as e:
    if not MOCK_MODE:
        print(f"⚠️  storage_utils import error: {e}")
    # Mock 모드에서는 무시
    pass

# 비동기 Storage 관리 유틸리티 임포트 (Mock 모드에서는 선택적)
try:
    from storage_utils_async import (
        get_all_nodes_scratch_info_sync,
        get_scratch_storage_stats_sync,
        get_data_storage_stats_cached,
        clear_cache
    )
except ImportError as e:
    if not MOCK_MODE:
        print(f"⚠️  storage_utils_async import error: {e}")
    # Mock 모드에서는 무시
    pass

# v1.3.0 신규 기능 Blueprint 임포트
from alerts_api import alerts_bp
from preview_api import preview_bp
from search_api import search_bp
from directory_api import directory_bp

# v3.0 신규 기능 Blueprint 임포트
from notifications_api import notifications_bp
from prometheus_api import prometheus_bp
from templates_api import templates_bp

# v3.2 신규 기능 Blueprint 임포트
from reports_api import reports_bp

# v3.4 신규 기능 Blueprint 임포트
from dashboard_api import dashboard_bp

# v3.5 신규 기능 Blueprint 임포트
from health_check_api import health_bp
from cache_api import cache_bp

# 파일 업로드 API
from upload_api import upload_bp

# v4.0 신규 기능 Blueprint 임포트 (Phase 1-2)
from node_management_api import node_bp
from groups_api import groups_bp
from cluster_config_api import cluster_config_bp

# v5.0 신규 기능 Blueprint 임포트 (Phase 5 - VNC, SSH)
from vnc_api import vnc_bp
from ssh_api import ssh_bp

# v4.1.0 신규 기능 Blueprint 임포트 (Phase 1 - Apptainer Discovery)
from apptainer_api import apptainer_bp

# v4.2.0 신규 기능 Blueprint 임포트 (Phase 2 - Template Management)
from templates_api_v2 import templates_v2_bp

# v4.3.0 신규 기능 Blueprint 임포트 (Phase 3 - Unified File Upload)
from file_upload_api import file_upload_bp

# v4.4.0 신규 기능 Blueprint 임포트 (Phase 4 - Job Submit with Template System)
from job_submit_api import job_submit_bp

# v4.5.0 신규 기능 Blueprint 임포트 (Phase 3 Production - Template Persistence)
from template_service import template_bp as template_persistence_bp

# v4.6.0 신규 기능 Blueprint 임포트 (Phase 3 Production - LS-DYNA Template Integration)
from lsdyna_submit_api import lsdyna_submit_bp

# v4.7.0 신규 기능 Blueprint 임포트 (Phase 3 Production - File Listing API)
from file_listing_api import file_listing_bp

# v5.1.0 신규 기능 Blueprint 임포트 (YAML Node Group Loader)
from yaml_node_loader import yaml_loader_bp

app = Flask(__name__)
CORS(app)

# Initialize Flask-SocketIO
socketio = SocketIO(
    app,
    cors_allowed_origins="*",
    async_mode='threading',
    logger=False,
    engineio_logger=False
)

# ==================== Prometheus Metrics ====================
# HTTP 요청 카운터
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

# HTTP 요청 지연 시간
http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint']
)

# 활성 작업 수
active_jobs_gauge = Gauge('slurm_active_jobs', 'Number of active Slurm jobs')
pending_jobs_gauge = Gauge('slurm_pending_jobs', 'Number of pending Slurm jobs')

# 노드 상태
idle_nodes_gauge = Gauge('slurm_idle_nodes', 'Number of idle nodes')
allocated_nodes_gauge = Gauge('slurm_allocated_nodes', 'Number of allocated nodes')
down_nodes_gauge = Gauge('slurm_down_nodes', 'Number of down nodes')

# API 호출 전후 처리
@app.before_request
def before_request():
    request.start_time = time.time()

@app.after_request
def after_request(response):
    if hasattr(request, 'start_time'):
        duration = time.time() - request.start_time
        http_request_duration_seconds.labels(
            method=request.method,
            endpoint=request.endpoint or 'unknown'
        ).observe(duration)
    
    http_requests_total.labels(
        method=request.method,
        endpoint=request.endpoint or 'unknown',
        status=response.status_code
    ).inc()
    
    return response

# ==================== Prometheus Metrics Endpoint ====================
@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

# v1.3.0 신규 기능 Blueprint 등록 (선택적)
try:
    app.register_blueprint(alerts_bp)
    app.register_blueprint(preview_bp)
    app.register_blueprint(search_bp)
    app.register_blueprint(directory_bp)
except NameError:
    if not MOCK_MODE:
        print("⚠️  Some blueprints not available")
    pass

# v3.0 신규 기능 Blueprint 등록
app.register_blueprint(notifications_bp)
app.register_blueprint(prometheus_bp)
# OLD API DISABLED: templates_bp uses deprecated 'templates' table
# app.register_blueprint(templates_bp)

# Templates API alias: /api/templates → /api/jobs/templates (호환성)
# DISABLED: Old API deprecated
# from templates_api import get_templates as templates_get_all
# app.add_url_rule('/api/templates', 'templates_alias', templates_get_all, methods=['GET'])
# print("✅ Templates API alias registered: /api/templates")

# v3.2 신규 기능 Blueprint 등록
app.register_blueprint(reports_bp)

# v3.4 신규 기능 Blueprint 등록
app.register_blueprint(dashboard_bp)

# v3.5 신규 기능 Blueprint 등록
app.register_blueprint(health_bp)
app.register_blueprint(cache_bp)

# 파일 업로드 API 등록
app.register_blueprint(upload_bp)

# v4.0 신규 기능 Blueprint 등록 (Phase 1-2: 노드 관리)
# ⚠️ IMPORTANT: node_bp를 먼저 등록하여 /api/nodes 라우트를 우선 처리
app.register_blueprint(node_bp)
print("✅ Node Management API registered (Priority route for /api/nodes)")

app.register_blueprint(groups_bp)
print("✅ Groups API registered: /api/groups")

# v5.0 신규 기능 Blueprint 등록 (Phase 5 - VNC, SSH)
app.register_blueprint(vnc_bp)
print("✅ VNC API registered: /api/vnc")

app.register_blueprint(ssh_bp)
print("✅ SSH API registered: /api/ssh")

app.register_blueprint(cluster_config_bp)
print("✅ Cluster Config API registered: /api/cluster")

# v4.1.0 신규 기능 Blueprint 등록 (Phase 1 - Apptainer Discovery)
app.register_blueprint(apptainer_bp)
print("✅ Apptainer API registered: /api/apptainer")

# v4.2.0 신규 기능 Blueprint 등록 (Phase 2 - Template Management)
# Templates v2 API now serves as the main Templates API
app.register_blueprint(templates_v2_bp)
print("✅ Templates API v2 registered: /api/jobs/templates (job_templates_v2 table)")

# v4.3.0 신규 기능 Blueprint 등록 (Phase 3 - Unified File Upload)
app.register_blueprint(file_upload_bp)
print("✅ File Upload API v2 registered: /api/v2/files")

# v4.4.0 신규 기능 Blueprint 등록 (Phase 4 - Job Submit with Template System)
app.register_blueprint(job_submit_bp)
print("✅ Job Submit API registered: /api/jobs/submit")

# v4.5.0 신규 기능 Blueprint 등록 (Phase 3 Production - Template Persistence)
app.register_blueprint(template_persistence_bp)
print("✅ Template Persistence API registered: /api/templates")

# v4.6.0 신규 기능 Blueprint 등록 (Phase 3 Production - LS-DYNA Template Integration)
app.register_blueprint(lsdyna_submit_bp)
print("✅ LS-DYNA Submit API registered: /api/slurm/submit-lsdyna-jobs")

# v4.7.0 신규 기능 Blueprint 등록 (Phase 3 Production - File Listing API)
app.register_blueprint(file_listing_bp)
print("✅ File Listing API registered: /api/files")

# v5.1.0 신규 기능 Blueprint 등록 (YAML Node Group Loader)
app.register_blueprint(yaml_loader_bp)
print("✅ YAML Node Loader API registered: /api/yaml")

# Initialize template watcher (Hot Reload)
try:
    from template_loader import TemplateLoader
    from template_watcher import start_template_watcher
    import sqlite3
    import os

    db_path = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')
    db_conn = sqlite3.connect(db_path, check_same_thread=False)
    template_loader = TemplateLoader(base_path="/shared/templates", db_connection=db_conn)

    watcher = start_template_watcher(template_loader, watch_path="/shared/templates")
    print("✅ Template watcher started: /shared/templates")
except Exception as e:
    print(f"⚠️  Template watcher failed to start: {e}")

# Initialize SSH WebSocket handlers
from ssh_websocket import init_ssh_websocket
init_ssh_websocket(socketio)
print("✅ SSH WebSocket handlers registered: /ssh-ws")

# Mock 데이터 저장소
mock_config = {
    'groups': [],
    'partitions': [],
    'qos_list': [],
    'jobs': [],
    'job_counter': 10000
}

@app.route('/api/health', methods=['GET'])
def health_check():
    """헬스 체크"""
    return jsonify({
        'status': 'healthy',
        'mode': 'mock' if MOCK_MODE else 'production',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/auth/config', methods=['GET'])
def get_auth_config():
    """
    인증 설정 조회 (SSO 활성화 여부)
    프론트엔드가 SSO false 모드를 감지하는 데 사용
    """
    from middleware.jwt_middleware import SSO_ENABLED

    return jsonify({
        'sso_enabled': SSO_ENABLED,
        'jwt_required': SSO_ENABLED,
        'timestamp': datetime.now().isoformat()
    })

# ==================== 실시간 모니터링 API ====================

@app.route('/api/metrics/realtime', methods=['GET'])
def get_realtime_metrics():
    """실시간 메트릭 조회"""
    try:
        if MOCK_MODE:
            # Mock 데이터 생성
            metrics = {
                'timestamp': datetime.now().isoformat(),
                'cpuUsage': 45 + random.random() * 30,
                'memoryUsage': 60 + random.random() * 20,
                'gpuUsage': 30 + random.random() * 40,
                'activeJobs': random.randint(50, 80),
                'pendingJobs': random.randint(10, 30),
                'totalNodes': 370,
                'idleNodes': random.randint(100, 150),
                'allocatedNodes': random.randint(200, 250),
                'downNodes': random.randint(0, 5),
            }
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': metrics
            })
        else:
            # Production: 실제 메트릭 수집
            metrics = collect_real_metrics()
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': metrics
            })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/slurm/nodes/<hostname>', methods=['GET'])
def get_node_detail(hostname):
    """특정 노드의 상세 정보"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': False,
                'mode': 'mock',
                'message': 'Node details only available in Production mode'
            }), 400
        
        from slurm_utils import get_node_details
        
        details = get_node_details(hostname)
        
        if not details:
            return jsonify({
                'success': False,
                'error': f'Node {hostname} not found'
            }), 404
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'data': details
        })
        
    except Exception as e:
        print(f"❌ Error in get_node_detail: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/slurm/sync-nodes', methods=['POST'])
def sync_nodes_to_dashboard():
    """
    실제 Slurm 노드를 대시보드 형식으로 변환
    """
    try:
        if MOCK_MODE:
            return jsonify({
                'success': False,
                'mode': 'mock',
                'message': 'Node sync only available in Production mode'
            }), 400
        
        from slurm_utils import get_slurm_nodes, get_partitions
        
        nodes = get_slurm_nodes()
        partitions = get_partitions()
        
        # 파티션을 그룹으로 변환
        groups = []
        for idx, partition in enumerate(partitions, start=1):
            partition_nodes = [
                n for n in nodes 
                if n.get('partition') == partition['name']
            ]
            
            # 노드 ID 및 그룹 ID 설정
            for node in partition_nodes:
                node['id'] = f"{partition['name']}-{node['hostname']}"
                node['groupId'] = idx
            
            total_cores = sum(n['cores'] for n in partition_nodes)
            
            groups.append({
                'id': idx,
                'name': partition['name'],
                'description': f'Partition: {partition["name"]}',
                'color': ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899'][idx % 6],
                'qosName': f'{partition["name"]}_qos',
                'partitionName': partition['name'],
                'allowedCoreSizes': [128, 256, 512, 1024],
                'nodeCount': len(partition_nodes),
                'totalCores': total_cores,
                'nodes': partition_nodes
            })
        
        total_nodes = len(nodes)
        total_cores = sum(n['cores'] for n in nodes)
        
        dashboard_config = {
            'clusterName': 'Production Cluster',
            'controllerIp': '192.168.1.1',
            'totalNodes': total_nodes,
            'totalCores': total_cores,
            'groups': groups
        }
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': f'Synced {total_nodes} nodes from Slurm',
            'data': dashboard_config
        })
        
    except Exception as e:
        print(f"❌ Error in sync_nodes_to_dashboard: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

def collect_real_metrics():
    """실제 시스템 메트릭 수집 (개선됨 - 노드별 카운트)"""
    try:
        # sinfo로 노드별 상태 파악 (%n = 노드 이름, %T = 상태)
        result = get_sinfo('-h', '-o', '%n|%T', timeout=5)
        
        # 각 라인이 하나의 노드 (node001|idle, node002|idle 등)
        node_lines = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
        total_nodes = len(node_lines)  # 정확한 노드 개수
        
        # 상태별 카운트
        idle_nodes = 0
        allocated_nodes = 0
        down_nodes = 0
        
        for line in node_lines:
            if '|' in line:
                node_name, state = line.split('|', 1)
                state_lower = state.strip().lower()
                
                if 'idle' in state_lower:
                    idle_nodes += 1
                elif 'alloc' in state_lower or 'mix' in state_lower:
                    allocated_nodes += 1
                elif 'down' in state_lower or 'drain' in state_lower:
                    down_nodes += 1
        
        # squeue로 작업 수 파악
        result = get_squeue('-h', '-o', '%T', timeout=5)
        
        job_states = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
        active_jobs = sum(1 for s in job_states if s == 'RUNNING')
        pending_jobs = sum(1 for s in job_states if s == 'PENDING')
        
        # CPU 사용률 계산 (allocated + mixed 노드 비율)
        cpu_usage = (allocated_nodes / total_nodes * 100) if total_nodes > 0 else 0
        
        # 메모리 사용률 계산 (간단한 추정)
        memory_usage = cpu_usage * 0.9  # CPU 사용률과 비례한다고 가정
        
        # GPU 사용률 (sinfo에서 GRES 정보로 확인 가능, 여기서는 간단히 추정)
        gpu_usage = cpu_usage * 0.7 if allocated_nodes > 0 else 0
        
        print(f"📊 Real Metrics: Nodes={total_nodes}, Jobs={active_jobs}/{pending_jobs}, CPU={cpu_usage:.1f}%")
        
        return {
            'timestamp': datetime.now().isoformat(),
            'cpuUsage': round(cpu_usage, 2),
            'memoryUsage': round(memory_usage, 2),
            'gpuUsage': round(gpu_usage, 2),
            'activeJobs': active_jobs,
            'pendingJobs': pending_jobs,
            'totalNodes': total_nodes,
            'idleNodes': idle_nodes,
            'allocatedNodes': allocated_nodes,
            'downNodes': down_nodes,
        }
    except subprocess.TimeoutExpired:
        print("⚠️  Slurm command timeout")
        raise Exception("Slurm command timeout - check if slurmctld is running")
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Slurm command failed: {e}")
        raise Exception(f"Slurm command failed: {e.stderr if e.stderr else str(e)}")
    except Exception as e:
        print(f"⚠️  Error collecting metrics: {e}")
        raise

# ==================== 작업 관리 API ====================

@app.route('/api/slurm/jobs', methods=['GET'])
def get_slurm_jobs():
    """작업 목록 조회 (Mock 모드 지원)"""
    try:
        if MOCK_MODE:
            # Mock 작업 데이터 생성
            states = ['RUNNING', 'PENDING', 'COMPLETED', 'FAILED']
            users = ['user01', 'user02', 'user03', 'admin', 'researcher']
            partitions = ['group1', 'group2', 'group3', 'gpu', 'debug']
            
            mock_jobs = [
                {
                    'jobId': str(10000 + i),
                    'partition': random.choice(partitions),
                    'jobName': f'job_{i}_{random.choice(["simulation", "training", "analysis"])}',
                    'userId': random.choice(users),
                    'state': random.choice(states),
                    'nodes': random.randint(1, 10),
                    'cpus': random.choice([128, 256, 512, 1024]),
                    'memory': f'{random.randint(16, 64)}GB',
                    'startTime': datetime.now().isoformat(),
                    'runTime': f'{random.randint(0, 23):02d}:{random.randint(0, 59):02d}:{random.randint(0, 59):02d}',
                    'priority': random.randint(100, 1000),
                    'account': 'research',
                    'qos': f'qos_{random.randint(1, 3)}'
                }
                for i in range(20)
            ]
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'jobs': mock_jobs,
                'count': len(mock_jobs),
                'timestamp': datetime.now().isoformat()
            })
        else:
            # Production: 실제 squeue 명령 실행 (개선됨)
            result = get_squeue('-h', '-o', '%i|%P|%j|%u|%T|%D|%C|%m|%S|%M|%Q', timeout=5)
            
            jobs = []
            for line in result.stdout.strip().split('\n'):
                if not line:
                    continue
                    
                parts = line.split('|')
                if len(parts) >= 7:
                    try:
                        jobs.append({
                            'jobId': parts[0].strip(),
                            'partition': parts[1].strip(),
                            'jobName': parts[2].strip(),
                            'userId': parts[3].strip(),
                            'state': parts[4].strip(),
                            'nodes': int(parts[5].strip()),
                            'cpus': int(parts[6].strip()),
                            'memory': parts[7].strip() if len(parts) > 7 else 'N/A',
                            'startTime': parts[8].strip() if len(parts) > 8 else None,
                            'runTime': parts[9].strip() if len(parts) > 9 else '00:00:00',
                            'qos': parts[10].strip() if len(parts) > 10 else 'normal',
                            'priority': random.randint(100, 1000),
                            'account': 'research',
                        })
                    except (ValueError, IndexError) as e:
                        print(f"⚠️  Skipping malformed job line: {line}, error: {e}")
                        continue
            
            print(f"📋 Loaded {len(jobs)} jobs from Slurm")
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'jobs': jobs,
                'count': len(jobs),
                'timestamp': datetime.now().isoformat()
            })
        
    except subprocess.TimeoutExpired:
        print("⚠️  squeue command timeout")
        return jsonify({
            'success': False,
            'error': 'Slurm command timeout'
        }), 500
    except subprocess.CalledProcessError as e:
        print(f"❌ squeue command failed: {e}")
        return jsonify({
            'success': False,
            'error': f'squeue failed: {e.stderr if e.stderr else str(e)}'
        }), 500
    except Exception as e:
        print(f"❌ Error in get_slurm_jobs: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/slurm/jobs/submit', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def submit_job():
    """작업 제출 - JWT 인증 필요"""
    try:
        data = request.json
        job_id = data.get('jobId')  # Frontend에서 전달한 임시 job_id

        # 업로드된 파일 정보 조회 (job_id가 있는 경우)
        file_env_vars = {}
        if job_id:
            try:
                conn = get_db()
                cursor = conn.cursor()
                cursor.execute('''
                    SELECT filename, file_path, storage_path, file_type
                    FROM file_uploads
                    WHERE job_id = ? AND status = 'completed'
                    ORDER BY created_at
                ''', (job_id,))

                uploaded_files = cursor.fetchall()
                conn.close()

                # 파일별 환경변수 생성
                for file in uploaded_files:
                    filename = file['filename']
                    file_path = file['file_path'] or file['storage_path']
                    file_type = file['file_type']

                    # 변수명 생성: 파일명에서 확장자 제거 후 대문자 + 언더스코어
                    var_name = filename.rsplit('.', 1)[0]  # 확장자 제거
                    var_name = ''.join(c if c.isalnum() else '_' for c in var_name)  # 특수문자 -> _
                    var_name = var_name.upper()

                    # FILE_<TYPE>_<NAME> 형식
                    env_var_name = f"FILE_{file_type.upper()}_{var_name}"
                    file_env_vars[env_var_name] = file_path

                    # 짧은 별칭도 추가 (중복 방지)
                    if var_name not in file_env_vars:
                        file_env_vars[var_name] = file_path

                print(f"📁 Found {len(uploaded_files)} uploaded files for job {job_id}")
                print(f"🔧 Environment variables: {list(file_env_vars.keys())}")

            except Exception as e:
                print(f"⚠️ Warning: Could not load uploaded files: {e}")
                # 파일 로딩 실패는 치명적이지 않음 - Job은 계속 진행

        if MOCK_MODE:
            # Mock: 작업 ID 생성 및 저장
            mock_config['job_counter'] += 1
            job_id = str(mock_config['job_counter'])
            
            mock_job = {
                'jobId': job_id,
                'jobName': data['jobName'],
                'partition': data['partition'],
                'nodes': data['nodes'],
                'cpus': data.get('cpus', 128),
                'memory': data.get('memory', '16GB'),
                'time': data.get('time', '01:00:00'),
                'state': 'PENDING',
                'userId': 'current_user',
                'submitTime': datetime.now().isoformat()
            }
            
            mock_config['jobs'].append(mock_job)
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'jobId': job_id,
                'message': f'Job {job_id} submitted successfully (Mock)'
            })
        else:
            # Production: 실제 sbatch 실행
            script_content = data['script']
            apptainer_image = data.get('apptainerImage')  # Phase 1: Apptainer 통합

            # 임시 스크립트 파일 생성
            with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
                f.write(f"#!/bin/bash\n")
                f.write(f"#SBATCH --job-name={data['jobName']}\n")
                f.write(f"#SBATCH --partition={data['partition']}\n")
                f.write(f"#SBATCH --nodes={data['nodes']}\n")
                if data.get('cpus'):
                    f.write(f"#SBATCH --cpus-per-task={data['cpus']}\n")
                if data.get('memory'):
                    f.write(f"#SBATCH --mem={data['memory']}\n")
                if data.get('time'):
                    f.write(f"#SBATCH --time={data['time']}\n")
                f.write(f"\n")

                # 업로드된 파일 경로를 환경변수로 추가
                if file_env_vars:
                    f.write(f"# Uploaded File Paths (Phase 3)\n")
                    for var_name, file_path in file_env_vars.items():
                        f.write(f"export {var_name}=\"{file_path}\"\n")
                    f.write(f"\n")

                # Phase 1: Apptainer 이미지 실행
                if apptainer_image:
                    image_path = apptainer_image['path']
                    image_name = apptainer_image['name']
                    f.write(f"# Phase 1: Apptainer Container Execution\n")
                    f.write(f"echo \"========================================\"\n")
                    f.write(f"echo \"Using Apptainer image: {image_name}\"\n")
                    f.write(f"echo \"Image path: {image_path}\"\n")
                    f.write(f"echo \"========================================\"\n")
                    f.write(f"\n")
                    f.write(f"# Execute script inside Apptainer container\n")
                    f.write(f"apptainer exec {image_path} bash <<'APPTAINER_SCRIPT'\n")
                    f.write(f"{script_content}\n")
                    f.write(f"APPTAINER_SCRIPT\n")
                    f.write(f"\n")
                    f.write(f"echo \"Apptainer execution completed\"\n")
                else:
                    # Apptainer 없이 일반 실행
                    f.write(f"# Direct execution (no Apptainer)\n")
                    f.write(f"{script_content}\n")

                script_path = f.name
            
            # sbatch 실행
            from slurm_commands import run_slurm_command
            result = run_slurm_command([SBATCH, script_path], timeout=10)
            
            # 임시 파일 삭제
            os.unlink(script_path)
            
            # Job ID 추출
            job_id = result.stdout.strip().split()[-1]

            # 로깅 개선
            if apptainer_image:
                print(f"✅ Job {job_id} submitted with Apptainer image: {apptainer_image['name']}")
            else:
                print(f"✅ Job {job_id} submitted (no Apptainer)")

            if file_env_vars:
                print(f"   📁 With {len(file_env_vars)} environment variables for uploaded files")

            return jsonify({
                'success': True,
                'mode': 'production',
                'jobId': job_id,
                'message': f'Job {job_id} submitted successfully'
            })
        
    except Exception as e:
        print(f"❌ Error submitting job: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/slurm/jobs/<job_id>/cancel', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def cancel_job(job_id):
    """작업 취소 - JWT 인증 필요"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Job {job_id} cancelled (Mock)'
            })
        else:
            from slurm_commands import run_slurm_command
            run_slurm_command([SCANCEL, job_id], timeout=5)
            print(f"✅ Job {job_id} cancelled")
            return jsonify({
                'success': True,
                'mode': 'production',
                'message': f'Job {job_id} cancelled'
            })
    except Exception as e:
        print(f"❌ Error cancelling job: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/slurm/jobs/<job_id>/hold', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def hold_job(job_id):
    """작업 홀드 - JWT 인증 필요"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Job {job_id} held (Mock)'
            })
        else:
            get_scontrol('hold', job_id, timeout=5)
            print(f"✅ Job {job_id} held")
            return jsonify({
                'success': True,
                'mode': 'production',
                'message': f'Job {job_id} held'
            })
    except Exception as e:
        print(f"❌ Error holding job: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/slurm/jobs/<job_id>/release', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def release_job(job_id):
    """작업 릴리즈 - JWT 인증 필요"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Job {job_id} released (Mock)'
            })
        else:
            get_scontrol('release', job_id, timeout=5)
            print(f"✅ Job {job_id} released")
            return jsonify({
                'success': True,
                'mode': 'production',
                'message': f'Job {job_id} released'
            })
    except Exception as e:
        print(f"❌ Error releasing job: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ==================== 기존 클러스터 관리 API ====================

@app.route('/api/slurm/apply-config', methods=['POST'])
@jwt_required
@permission_required('dashboard', 'admin')
def apply_slurm_config():
    """설정 적용 (Mock 모드 지원) - JWT 인증 및 admin 권한 필요"""
    try:
        data = request.json
        groups = data.get('groups', [])
        dry_run = data.get('dryRun', False)
        
        if not groups:
            return jsonify({
                'success': False,
                'error': 'No groups provided'
            }), 400
        
        # 매번 환경변수 직접 체크 (동적 모드 전환 지원)
        current_mode = os.getenv('MOCK_MODE', 'true').lower() == 'true'
        
        if current_mode:
            # Mock 모드: 실제 명령 실행 안 함
            return apply_mock_config(groups, dry_run)
        else:
            # Production 모드: 실제 Slurm 명령 실행
            return apply_real_config(groups, dry_run)
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

def apply_mock_config(groups, dry_run):
    """Mock 모드: 실제 명령 없이 시뮬레이션"""
    print("🎭 Mock Mode: Simulating configuration apply...")
    
    # Mock 데이터 업데이트
    mock_config['groups'] = groups
    
    # 가상의 QoS 생성
    for group in groups:
        qos_name = group['qosName']
        max_cores = max(group['allowedCoreSizes']) if group['allowedCoreSizes'] else 1024
        
        print(f"  📝 Mock: Creating QoS {qos_name} (MaxCores: {max_cores})")
        
        mock_config['qos_list'].append({
            'name': qos_name,
            'maxCores': max_cores,
            'priority': 1000 + group['id'] * 100
        })
    
    # 가상의 Partition 생성
    for group in groups:
        partition_name = group['partitionName']
        node_count = len(group['nodes'])
        
        print(f"  📝 Mock: Creating Partition {partition_name} ({node_count} nodes)")
        
        mock_config['partitions'].append({
            'name': partition_name,
            'nodes': node_count,
            'state': 'UP'
        })
    
    print("  ✅ Mock: Configuration applied successfully!")
    
    return jsonify({
        'success': True,
        'mode': 'mock',
        'message': 'Configuration applied successfully (Mock Mode)',
        'changes': {
            'qos_created': len(groups),
            'partitions_updated': len(groups),
            'total_nodes': sum(len(g['nodes']) for g in groups)
        },
        'timestamp': datetime.now().isoformat()
    })

def apply_real_config(groups, dry_run):
    """Production 모드: 실제 Slurm 명령 실행"""
    print("🚀 Production Mode: Applying real configuration...")
    print(f"   Groups: {len(groups)}")
    print(f"   Dry Run: {dry_run}")
    
    try:
        # 전체 설정 적용 (QoS + Partitions)
        print("   Calling apply_full_configuration...")
        results = apply_full_configuration(groups, dry_run)
        print(f"   Results: {results}")
        
        if dry_run:
            return jsonify({
                'success': True,
                'mode': 'production',
                'message': 'Dry run completed - no changes made',
                'changes': {
                    'qos': len(groups),
                    'partitions': len(groups),
                    'total_nodes': sum(len(g.get('nodes', [])) for g in groups)
                },
                'timestamp': datetime.now().isoformat()
            })
        
        # 실제 적용 결과
        return jsonify({
            'success': results['success'],
            'mode': 'production',
            'message': 'Configuration applied successfully' if results['success'] else 'Configuration apply failed',
            'details': {
                'qos_created': results['qos_created'],
                'qos_failed': results['qos_failed'],
                'partitions_updated': results['partitions_updated'],
                'errors': results.get('errors', [])
            },
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        print(f"❌ Error in apply_real_config: {e}")
        import traceback
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'mode': 'production',
            'error': f'Configuration apply failed: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500

@app.route('/api/slurm/status', methods=['GET'])
@optional_jwt
def get_slurm_status():
    """Slurm 상태 조회 (Mock 모드 지원) - JWT 선택적"""
    try:
        if MOCK_MODE:
            # Mock 데이터 반환
            return jsonify({
                'success': True,
                'mode': 'mock',
                'partitions': mock_config.get('partitions', [
                    {'name': 'group1', 'nodes': 64, 'state': 'UP', 'availability': 'up'},
                    {'name': 'group2', 'nodes': 64, 'state': 'UP', 'availability': 'up'},
                    {'name': 'group3', 'nodes': 64, 'state': 'UP', 'availability': 'up'},
                    {'name': 'group4', 'nodes': 100, 'state': 'UP', 'availability': 'up'},
                    {'name': 'group5', 'nodes': 14, 'state': 'UP', 'availability': 'up'},
                    {'name': 'group6', 'nodes': 64, 'state': 'UP', 'availability': 'up'},
                ]),
                'timestamp': datetime.now().isoformat()
            })
        else:
            # 실제 sinfo 명령 실행 (절대 경로 사용)
            from slurm_commands import SINFO
            result = subprocess.run(
                [SINFO, '-h', '-o', '%P %a %l %D %T %N'],
                capture_output=True,
                text=True,
                check=True
            )
            
            partitions = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    parts = line.split()
                    if len(parts) >= 5:
                        partitions.append({
                            'name': parts[0].rstrip('*'),
                            'availability': parts[1],
                            'timelimit': parts[2],
                            'nodes': int(parts[3]),
                            'state': parts[4],
                        })
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'partitions': partitions,
                'timestamp': datetime.now().isoformat()
            })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/slurm/qos', methods=['GET'])
def get_qos_list():
    """QoS 목록 조회 (Mock 모드 지원)"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'mode': 'mock',
                'qos': mock_config.get('qos_list', [
                    {'name': 'group1_qos', 'priority': '1100'},
                    {'name': 'group2_qos', 'priority': '1200'},
                    {'name': 'group3_qos', 'priority': '1300'},
                    {'name': 'group4_qos', 'priority': '1400'},
                    {'name': 'group5_qos', 'priority': '1500'},
                    {'name': 'group6_qos', 'priority': '1600'},
                ])
            })
        else:
            result = subprocess.run(
                ['sacctmgr', 'show', 'qos', '-n', '-P'],
                capture_output=True,
                text=True,
                check=True
            )
            
            qos_list = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    parts = line.split('|')
                    if parts:
                        qos_list.append({
                            'name': parts[0],
                            'priority': parts[1] if len(parts) > 1 else None,
                        })
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'qos': qos_list
            })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ==================== 🆕 실제 노드 정보 조회 API ====================

@app.route('/api/slurm/nodes/real', methods=['GET'])
def get_real_slurm_nodes():
    """
    실제 Slurm 클러스터의 노드 정보 가져오기
    Production 모드에서만 실제 데이터 반환
    """
    try:
        if MOCK_MODE:
            return jsonify({
                'success': False,
                'mode': 'mock',
                'message': 'Real node information is only available in Production mode',
                'hint': 'Set MOCK_MODE=false to enable this feature'
            }), 400
        
        # Production 모드: 실제 노드 정보 가져오기
        from slurm_utils import get_slurm_nodes, get_partitions
        
        print("🔄 Syncing nodes from Slurm...")
        nodes = get_slurm_nodes()
        partitions = get_partitions()
        
        print(f"   Found {len(nodes)} nodes and {len(partitions)} partitions")
        
        # 파티션별로 노드 그룹화
        nodes_by_partition = {}
        for node in nodes:
            partition = node.get('partition', 'default')
            if partition not in nodes_by_partition:
                nodes_by_partition[partition] = []
            nodes_by_partition[partition].append(node)
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'data': {
                'nodes': nodes,
                'partitions': partitions,
                'nodes_by_partition': nodes_by_partition,
                'total_nodes': len(nodes),
                'timestamp': datetime.now().isoformat()
            }
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ==================== 💾 Storage Management API ====================

# 허용된 기본 경로
ALLOWED_PATHS = {
    'data': '/data',
    'scratch': '/scratch'
}

@app.route('/api/storage/data/stats', methods=['GET'])
def get_shared_storage_stats():
    """공유 스토리지 통계"""
    try:
        if MOCK_MODE:
            # Mock 데이터
            from data.mockStorageData import mockStorageStats
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': mockStorageStats
            })
        else:
            # Production: 실제 /data 디렉토리 스캔
            data_path = ALLOWED_PATHS['data']
            
            if not os.path.exists(data_path):
                return jsonify({
                    'success': False,
                    'error': f'Path {data_path} does not exist'
                }), 404
            
            usage = get_disk_usage(data_path)
            file_count, dir_count = count_files_recursive(data_path)
            
            # 데이터셋 디렉토리 수 계산 (예: /data/datasets/ 하위)
            datasets_path = os.path.join(data_path, 'datasets')
            dataset_count = 0
            if os.path.exists(datasets_path):
                dataset_count = len([d for d in os.listdir(datasets_path) 
                                   if os.path.isdir(os.path.join(datasets_path, d))])
            
            stats = {
                'totalCapacity': usage['total'],
                'usedSpace': usage['used'],
                'availableSpace': usage['available'],
                'usagePercent': usage['usagePercent'],
                'datasetCount': dataset_count,
                'fileCount': file_count,
                'lastAnalysis': 'Just now'
            }
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': stats
            })
            
    except Exception as e:
        print(f"❌ Error getting storage stats: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/storage/data/datasets', methods=['GET'])
def get_datasets():
    """데이터셋 목록 조회"""
    try:
        search = request.args.get('search', '')
        status = request.args.get('status', 'all')
        
        if MOCK_MODE:
            # Mock 데이터
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': []  # 프론트엔드에서 mock 데이터 사용
            })
        else:
            # Production: 실제 /data/datasets 스캔
            data_path = ALLOWED_PATHS['data']
            datasets_path = os.path.join(data_path, 'datasets')
            
            if not os.path.exists(datasets_path):
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'data': []
                })
            
            datasets = []
            for entry in os.listdir(datasets_path):
                full_path = os.path.join(datasets_path, entry)
                if os.path.isdir(full_path):
                    file_info = get_file_info(full_path)
                    if file_info:
                        file_count, _ = count_files_recursive(full_path)
                        datasets.append({
                            'id': file_info['id'],
                            'name': file_info['name'],
                            'path': file_info['path'],
                            'size': file_info['size'],
                            'sizeBytes': file_info['sizeBytes'],
                            'fileCount': file_count,
                            'createdAt': file_info['modifiedAt'],
                            'lastAccessed': 'Recently',
                            'owner': file_info['owner'],
                            'group': file_info['group'],
                            'status': 'active',
                            'tags': []
                        })
            
            # 검색 필터
            if search:
                search_lower = search.lower()
                datasets = [d for d in datasets 
                          if search_lower in d['name'].lower() or search_lower in d['owner'].lower()]
            
            # 상태 필터
            if status != 'all':
                datasets = [d for d in datasets if d['status'] == status]
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': datasets
            })
            
    except Exception as e:
        print(f"❌ Error getting datasets: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/storage/files', methods=['GET'])
def list_storage_files():
    """파일 목록 조회"""
    try:
        path = request.args.get('path', '')
        storage_type = request.args.get('type', 'data')  # 'data' or 'scratch'
        
        if not path:
            return jsonify({
                'success': False,
                'error': 'Path parameter is required'
            }), 400
        
        if MOCK_MODE:
            # Mock: 프론트엔드에서 generateMockFiles 사용
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': []  # 프론트에서 생성
            })
        else:
            # Production: 실제 파일 목록
            base_path = ALLOWED_PATHS.get(storage_type, ALLOWED_PATHS['data'])
            
            # 안전한 경로 결합
            if path.startswith(base_path):
                full_path = path
            else:
                full_path = safe_path_join(base_path, path)
            
            if not full_path:
                return jsonify({
                    'success': False,
                    'error': 'Invalid path'
                }), 400
            
            if not is_path_accessible(full_path):
                return jsonify({
                    'success': False,
                    'error': 'Path not accessible'
                }), 403
            
            files = list_directory(full_path)
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': files,
                'path': full_path
            })
            
    except Exception as e:
        print(f"❌ Error listing files: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/storage/scratch/nodes', methods=['GET'])
def get_scratch_nodes():
    """모든 노드의 /scratch 정보"""
    try:
        if MOCK_MODE:
            # Mock 데이터
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': []  # 프론트에서 mock 데이터 사용
            })
        else:
            # Production: Slurm 노드 목록 가져오기
            nodes = get_storage_nodes()
            
            if not nodes:
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'data': [],
                    'message': 'No nodes found'
                })
            
            scratch_data = []
            
            for node in nodes:
                # 원격 노드에서 /scratch 정보 가져오기
                df_output = run_remote_command(node, "df -B1 /scratch | tail -1")
                
                if df_output:
                    parts = df_output.split()
                    if len(parts) >= 4:
                        total_bytes = int(parts[1])
                        used_bytes = int(parts[2])
                        avail_bytes = int(parts[3])
                        usage_percent = (used_bytes / total_bytes * 100) if total_bytes > 0 else 0
                        
                        # /scratch 디렉토리 목록
                        ls_output = run_remote_command(node, "ls -la /scratch | tail -n +2")
                        directories = []
                        
                        if ls_output:
                            for line in ls_output.strip().split('\n'):
                                if line and line.startswith('d'):
                                    parts = line.split()
                                    if len(parts) >= 9:
                                        dir_name = parts[8]
                                        if not dir_name.startswith('.'):
                                            directories.append({
                                                'id': f"{node}-{dir_name}",
                                                'name': dir_name,
                                                'path': f"/scratch/{dir_name}",
                                                'owner': parts[2],
                                                'group': parts[3],
                                                'size': 'Calculating...',
                                                'sizeBytes': 0,
                                                'fileCount': 0,
                                                'createdAt': f"{parts[5]} {parts[6]}",
                                                'lastModified': f"{parts[5]} {parts[6]}"
                                            })
                        
                        scratch_data.append({
                            'nodeId': node,
                            'nodeName': node,
                            'totalSpace': format_size(total_bytes),
                            'totalSpaceBytes': total_bytes,
                            'usedSpace': format_size(used_bytes),
                            'usedSpaceBytes': used_bytes,
                            'availableSpace': format_size(avail_bytes),
                            'availableSpaceBytes': avail_bytes,
                            'usagePercent': round(usage_percent, 1),
                            'fileCount': len(directories),
                            'directories': directories,
                            'status': 'online',
                            'lastUpdated': datetime.now().isoformat()
                        })
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': scratch_data
            })
            
    except Exception as e:
        print(f"❌ Error getting scratch nodes: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/storage/scratch/move', methods=['POST'])
def move_scratch_to_data():
    """/scratch → /data 이동"""
    try:
        data = request.json
        directory_ids = data.get('directoryIds', [])
        destination = data.get('destination', '/data/from_scratch/')
        
        if not directory_ids:
            return jsonify({
                'success': False,
                'error': 'No directories specified'
            }), 400
        
        if MOCK_MODE:
            # Mock: 실제 이동 안 함
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Moved {len(directory_ids)} directories (Mock)',
                'taskId': f'task-{int(time.time())}'
            })
        else:
            # Production: 실제 rsync 실행
            # TODO: 비동기 작업으로 구현 필요
            task_id = f'task-{int(time.time())}'
            
            # 여기서는 간단한 구현만
            # 실제로는 Celery 등을 사용해야 함
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'message': f'Move task initiated for {len(directory_ids)} directories',
                'taskId': task_id
            })
            
    except Exception as e:
        print(f"❌ Error moving directories: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/storage/scratch/delete', methods=['POST'])
def delete_scratch_directories():
    """/scratch 디렉토리 삭제"""
    try:
        data = request.json
        directory_ids = data.get('directoryIds', [])
        
        if not directory_ids:
            return jsonify({
                'success': False,
                'error': 'No directories specified'
            }), 400
        
        if MOCK_MODE:
            # Mock: 실제 삭제 안 함
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Deleted {len(directory_ids)} directories (Mock)'
            })
        else:
            # Production: 실제 rm -rf 실행
            # ⚠️ 매우 위험한 작업이므로 신중하게 구현
            # TODO: 권한 확인 및 안전 장치 필요
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'message': f'Delete task initiated for {len(directory_ids)} directories',
                'warning': 'This operation cannot be undone'
            })
            
    except Exception as e:
        print(f"❌ Error deleting directories: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/storage/search', methods=['GET'])
def search_storage():
    """파일 검색"""
    try:
        query = request.args.get('q', '')
        path = request.args.get('path', '')
        storage_type = request.args.get('type', 'data')
        max_results = int(request.args.get('limit', 100))
        
        if not query:
            return jsonify({
                'success': False,
                'error': 'Query parameter is required'
            }), 400
        
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': []
            })
        else:
            base_path = ALLOWED_PATHS.get(storage_type, ALLOWED_PATHS['data'])
            search_path = safe_path_join(base_path, path) if path else base_path
            
            if not search_path or not is_path_accessible(search_path):
                return jsonify({
                    'success': False,
                    'error': 'Invalid or inaccessible path'
                }), 400
            
            results = search_files(search_path, query, max_results)
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': results,
                'count': len(results)
            })
            
    except Exception as e:
        print(f"❌ Error searching files: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# create_qos, update_partitions, reconfigure_slurm 함수는
# slurm_config_manager.py에서 임포트하여 사용


# ==================== CustomDashboard API Endpoints ====================
# CustomDashboard 위젯용 API 엔드포인트
# 철칙 포트: Backend 5010, Frontend 3010, WebSocket 5011

@app.route('/api/jobs', methods=['GET'])
def get_jobs_alias():
    """
    Jobs API - CustomDashboard JobQueueWidget, RecentJobsWidget용
    Query parameters:
      - state: PENDING, RUNNING, COMPLETED, FAILED
      - limit: 결과 개수 제한
    """
    try:
        state = request.args.get('state')
        limit = request.args.get('limit')
        
        # /api/slurm/jobs 호출하여 데이터 가져오기
        jobs_data = get_slurm_jobs()
        jobs_response = jobs_data.get_json() if hasattr(jobs_data, 'get_json') else jobs_data
        
        if jobs_response and jobs_response.get('success'):
            jobs = jobs_response.get('jobs', [])
            
            # state 필터링
            if state:
                jobs = [j for j in jobs if j.get('state', '').upper() == state.upper()]
            
            # limit 적용
            if limit:
                try:
                    jobs = jobs[:int(limit)]
                except ValueError:
                    pass
            
            return jsonify({
                'jobs': jobs,
                'total': len(jobs),
                'mode': jobs_response.get('mode', 'mock')
            })
        else:
            # Fallback to mock data
            return jsonify({
                'jobs': [],
                'total': 0,
                'mode': 'mock'
            })
    except Exception as e:
        print(f"❌ Error in get_jobs_alias: {e}")
        return jsonify({
            'jobs': [],
            'total': 0,
            'mode': 'mock',
            'error': str(e)
        })

# ❌ REMOVED: Replaced by node_management_api Blueprint
# The /api/nodes route is now handled by node_bp from node_management_api.py
# which provides unified response format for both Dashboard and NodeManagement
#
# @app.route('/api/nodes', methods=['GET'])
# def get_nodes_alias():
#     ... (removed to avoid route conflict)

@app.route('/api/storage/usage', methods=['GET'])
def get_storage_usage_alias():
    """
    Storage Usage API - CustomDashboard StorageWidget용
    """
    try:
        if MOCK_MODE:
            # Mock 스토리지 데이터
            return jsonify({
                'storages': [
                    {'path': '/home', 'name': '/home', 'used_gb': 850, 'total_gb': 1000, 'usage_percent': 85.0},
                    {'path': '/scratch', 'name': '/scratch', 'used_gb': 4500, 'total_gb': 10000, 'usage_percent': 45.0},
                    {'path': '/data', 'name': '/data', 'used_gb': 1800, 'total_gb': 5000, 'usage_percent': 36.0}
                ],
                'total': 3,
                'mode': 'mock'
            })
        else:
            # Production: df 실행
            paths = ['/home', '/scratch', '/data']
            storages = []
            
            for path in paths:
                if os.path.exists(path):
                    try:
                        result = subprocess.run(
                            ['df', '-BG', path],
                            capture_output=True,
                            text=True,
                            check=True,
                            timeout=5
                        )
                        
                        lines = result.stdout.strip().split('\n')
                        if len(lines) >= 2:
                            parts = lines[1].split()
                            if len(parts) >= 5:
                                total_gb = int(parts[1].rstrip('G'))
                                used_gb = int(parts[2].rstrip('G'))
                                usage_str = parts[4].rstrip('%')
                                usage_percent = float(usage_str) if usage_str.replace('.', '').isdigit() else 0.0
                                
                                storages.append({
                                    'path': path,
                                    'name': path,
                                    'used_gb': used_gb,
                                    'total_gb': total_gb,
                                    'usage_percent': usage_percent
                                })
                    except Exception as e:
                        print(f"⚠️  Error getting usage for {path}: {e}")
                        continue
            
            if not storages:
                # Fallback to mock if no storage found
                storages = [
                    {'path': '/home', 'name': '/home', 'used_gb': 850, 'total_gb': 1000, 'usage_percent': 85.0}
                ]
            
            return jsonify({
                'storages': storages,
                'total': len(storages),
                'mode': 'production'
            })
    except Exception as e:
        print(f"❌ Error in get_storage_usage_alias: {e}")
        # Fallback to mock
        return jsonify({
            'storages': [
                {'path': '/home', 'name': '/home', 'used_gb': 850, 'total_gb': 1000, 'usage_percent': 85.0},
                {'path': '/scratch', 'name': '/scratch', 'used_gb': 4500, 'total_gb': 10000, 'usage_percent': 45.0}
            ],
            'total': 2,
            'mode': 'mock',
            'error': str(e)
        })

if __name__ == '__main__':
    print("=" * 60)
    print("Slurm Dashboard Backend API v2.0")
    print("=" * 60)
    print(f"Mode: {'🎭 MOCK (Demo)' if MOCK_MODE else '🚀 PRODUCTION (Real Slurm)'}")
    print("")
    print("Available Endpoints:")
    print("  GET  /api/health")
    print("  GET  /api/metrics/realtime")
    print("  GET  /api/slurm/jobs")
    print("  POST /api/slurm/jobs/submit")
    print("  POST /api/slurm/jobs/<id>/cancel")
    print("  POST /api/slurm/jobs/<id>/hold")
    print("  POST /api/slurm/jobs/<id>/release")
    print("  POST /api/slurm/apply-config")
    print("  GET  /api/slurm/status")
    print("  GET  /api/slurm/qos")
    print("  🆕 GET  /api/slurm/nodes/real")
    print("  🆕 GET  /api/slurm/nodes/<hostname>")
    print("  🆕 POST /api/slurm/sync-nodes")
    print("")
    print("💾 Storage Management:")
    print("  GET  /api/storage/data/stats")
    print("  GET  /api/storage/data/datasets")
    print("  GET  /api/storage/files")
    print("  GET  /api/storage/scratch/nodes")
    print("  POST /api/storage/scratch/move")
    print("  POST /api/storage/scratch/delete")
    print("  GET  /api/storage/search")
    print("")
    print("🆕 v1.3.0 New Features:")
    print("  ⚠️  Disk Alerts:")
    print("    POST /api/alerts/disk/check")
    print("    GET  /api/alerts/disk")
    print("    POST /api/alerts/disk/clear")
    print("    PUT  /api/alerts/disk/thresholds")
    print("  👁️  File Preview:")
    print("    POST /api/preview/type")
    print("    POST /api/preview/text")
    print("    GET  /api/preview/image")
    print("    POST /api/preview/tail")
    print("  🔍 File Search:")
    print("    POST /api/search/files")
    print("    POST /api/search/content")
    print("  📊 Directory Analysis:")
    print("    POST /api/directory/size")
    print("    POST /api/directory/breakdown")
    print("")
    print("📊 v3.4.0 Dashboard API:")
    print("  GET  /api/reports/dashboard/resources")
    print("  GET  /api/reports/dashboard/top-users?limit=10")
    print("  GET  /api/reports/dashboard/job-status")
    print("  GET  /api/reports/dashboard/cost-trends?period=week")
    print("  GET  /api/reports/dashboard/health")
    print("")
    print("🏥 v3.5.0 Health Check API:")
    print("  GET  /api/health/status")
    print("  GET  /api/health/summary")
    print("  GET  /api/health/endpoints")
    print("  POST /api/health/auto-heal")
    print("")
    print("🔌 v5.0 SSH WebSocket:")
    print("  WS   /ssh-ws (namespace)")
    print("")
    print("To switch modes:")
    print("  Mock:       export MOCK_MODE=true")
    print("  Production: export MOCK_MODE=false")
    print("")
    print("Starting server on http://0.0.0.0:5010 with WebSocket support")
    print("=" * 60)

    # Use socketio.run instead of app.run for WebSocket support
    socketio.run(app, host='0.0.0.0', port=5010, debug=False, allow_unsafe_werkzeug=True)
