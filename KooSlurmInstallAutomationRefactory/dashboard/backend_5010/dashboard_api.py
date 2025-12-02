"""
Dashboard API
실시간 대시보드용 데이터 제공
v3.4.0 - 리소스 차트, Top 사용자, 작업 상태, 비용 추이
"""

from flask import Blueprint, request, jsonify
from datetime import datetime, timedelta
import random
import os

# Slurm data collector import
try:
    from slurm_data_collector import (
        get_slurm_jobs_data,
        get_slurm_usage_by_user,
        get_current_cluster_state,
        get_daily_usage_data
    )
    SLURM_COLLECTOR_AVAILABLE = True
except ImportError:
    SLURM_COLLECTOR_AVAILABLE = False
    print("⚠️  slurm_data_collector not available - will use mock data")

# Create Blueprint
dashboard_bp = Blueprint('dashboard', __name__, url_prefix='/api/reports/dashboard')

MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# ============================================
# Mock Data Generators
# ============================================

def generate_mock_resource_data():
    """시간대별 리소스 사용률 Mock 데이터 생성 (24시간)"""
    now = datetime.now()
    timestamps = []
    cpu_usage = []
    gpu_usage = []
    memory_usage = []
    
    for i in range(24):
        time_point = now - timedelta(hours=23-i)
        timestamps.append(time_point.strftime('%Y-%m-%d %H:00'))
        
        # 시간대별로 다른 패턴 생성 (낮/밤)
        hour = time_point.hour
        if 9 <= hour <= 18:  # 업무 시간
            cpu_usage.append(round(random.uniform(60, 90), 1))
            gpu_usage.append(round(random.uniform(70, 95), 1))
            memory_usage.append(round(random.uniform(65, 85), 1))
        else:  # 업무 외 시간
            cpu_usage.append(round(random.uniform(20, 50), 1))
            gpu_usage.append(round(random.uniform(30, 60), 1))
            memory_usage.append(round(random.uniform(25, 55), 1))
    
    return {
        'timestamps': timestamps,
        'cpu_usage': cpu_usage,
        'gpu_usage': gpu_usage,
        'memory_usage': memory_usage
    }

def generate_mock_top_users(limit=10):
    """Top 사용자 Mock 데이터 생성"""
    users = []
    user_names = [f'user{i}' for i in range(1, limit + 1)]
    
    for idx, name in enumerate(user_names):
        cpu_hours = round(random.uniform(50, 300), 1)
        gpu_hours = round(random.uniform(20, 150), 1)
        jobs_count = random.randint(10, 100)
        cost = round((cpu_hours * 0.5 + gpu_hours * 2.0), 2)
        
        users.append({
            'rank': idx + 1,
            'username': name,
            'cpu_hours': cpu_hours,
            'gpu_hours': gpu_hours,
            'memory_gb_hours': round(random.uniform(200, 1000), 1),
            'jobs_count': jobs_count,
            'jobs_success': jobs_count - random.randint(0, 5),
            'jobs_failed': random.randint(0, 5),
            'cost': cost,
            'cpu_utilization': round(random.uniform(50, 95), 1),
            'gpu_utilization': round(random.uniform(60, 98), 1)
        })
    
    # 비용 기준으로 정렬
    users.sort(key=lambda x: x['cost'], reverse=True)
    
    # 순위 재조정
    for idx, user in enumerate(users):
        user['rank'] = idx + 1
    
    return users

def generate_mock_job_status():
    """작업 상태 분포 Mock 데이터 생성"""
    total_jobs = random.randint(150, 300)
    
    running = random.randint(10, 20)
    pending = random.randint(5, 15)
    failed = random.randint(2, 8)
    cancelled = random.randint(1, 5)
    completed = total_jobs - running - pending - failed - cancelled
    
    return {
        'running': running,
        'pending': pending,
        'completed': completed,
        'failed': failed,
        'cancelled': cancelled,
        'total': total_jobs
    }

def generate_mock_cost_trends(period='week'):
    """비용 추이 Mock 데이터 생성"""
    if period == 'week':
        days = 7
    elif period == 'month':
        days = 30
    elif period == 'year':
        days = 365
    else:
        days = 7
    
    now = datetime.now()
    dates = []
    daily_costs = []
    cumulative_costs = []
    cumulative = 0
    
    for i in range(days):
        date = now - timedelta(days=days-1-i)
        dates.append(date.strftime('%Y-%m-%d'))
        
        # 평일/주말에 따라 다른 비용
        weekday = date.weekday()
        if weekday < 5:  # 평일
            daily_cost = round(random.uniform(300, 600), 2)
        else:  # 주말
            daily_cost = round(random.uniform(100, 300), 2)
        
        daily_costs.append(daily_cost)
        cumulative += daily_cost
        cumulative_costs.append(round(cumulative, 2))
    
    return {
        'period': period,
        'dates': dates,
        'daily_costs': daily_costs,
        'cumulative_costs': cumulative_costs,
        'total_cost': round(cumulative, 2),
        'average_daily_cost': round(cumulative / days, 2)
    }

# ============================================
# Production Data Collectors
# ============================================

def collect_resource_data():
    """실제 Slurm 데이터로 리소스 사용률 수집"""
    try:
        # 현재 클러스터 상태 가져오기
        cluster_state = get_current_cluster_state()
        
        # 최근 24시간 작업 데이터
        end_date = datetime.now()
        start_date = end_date - timedelta(hours=24)
        jobs_data = get_slurm_jobs_data(start_date, end_date)
        
        # 시간대별로 집계
        timestamps = []
        cpu_usage = []
        gpu_usage = []
        memory_usage = []
        
        for i in range(24):
            time_point = end_date - timedelta(hours=23-i)
            timestamps.append(time_point.strftime('%Y-%m-%d %H:00'))
            
            # 간단한 집계 (실제로는 더 복잡한 로직 필요)
            cpu_usage.append(round(cluster_state.get('cpu_utilization', 0), 1))
            gpu_usage.append(round(cluster_state.get('gpu_utilization', 0), 1))
            memory_usage.append(round(cluster_state.get('memory_utilization', 0), 1))
        
        return {
            'timestamps': timestamps,
            'cpu_usage': cpu_usage,
            'gpu_usage': gpu_usage,
            'memory_usage': memory_usage
        }
    except Exception as e:
        print(f"❌ Error collecting resource data: {e}")
        raise

def collect_top_users(limit=10):
    """실제 Slurm 데이터로 Top 사용자 수집"""
    try:
        end_date = datetime.now()
        start_date = end_date - timedelta(days=7)
        
        # 사용자별 사용량 가져오기
        usage_data = get_slurm_usage_by_user(start_date, end_date)
        
        users = []
        for idx, user_data in enumerate(usage_data[:limit]):
            users.append({
                'rank': idx + 1,
                'username': user_data.get('username', 'unknown'),
                'cpu_hours': user_data.get('cpu_hours', 0),
                'gpu_hours': user_data.get('gpu_hours', 0),
                'memory_gb_hours': user_data.get('memory_gb_hours', 0),
                'jobs_count': user_data.get('jobs_total', 0),
                'jobs_success': user_data.get('jobs_success', 0),
                'jobs_failed': user_data.get('jobs_failed', 0),
                'cost': user_data.get('cost', 0),
                'cpu_utilization': user_data.get('cpu_utilization', 0),
                'gpu_utilization': user_data.get('gpu_utilization', 0)
            })
        
        return users
    except Exception as e:
        print(f"❌ Error collecting top users: {e}")
        raise

def collect_job_status():
    """실제 Slurm 데이터로 작업 상태 수집"""
    try:
        cluster_state = get_current_cluster_state()
        
        return {
            'running': cluster_state.get('running_jobs', 0),
            'pending': cluster_state.get('pending_jobs', 0),
            'completed': cluster_state.get('completed_jobs', 0),
            'failed': cluster_state.get('failed_jobs', 0),
            'cancelled': cluster_state.get('cancelled_jobs', 0),
            'total': cluster_state.get('total_jobs', 0)
        }
    except Exception as e:
        print(f"❌ Error collecting job status: {e}")
        raise

def collect_cost_trends(period='week'):
    """실제 Slurm 데이터로 비용 추이 수집"""
    try:
        if period == 'week':
            days = 7
        elif period == 'month':
            days = 30
        elif period == 'year':
            days = 365
        else:
            days = 7
        
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)
        
        # 일별 사용량 데이터
        daily_data = get_daily_usage_data(start_date, end_date)
        
        dates = []
        daily_costs = []
        cumulative_costs = []
        cumulative = 0
        
        for day_data in daily_data:
            dates.append(day_data.get('date', ''))
            daily_cost = day_data.get('cost', 0)
            daily_costs.append(daily_cost)
            cumulative += daily_cost
            cumulative_costs.append(round(cumulative, 2))
        
        return {
            'period': period,
            'dates': dates,
            'daily_costs': daily_costs,
            'cumulative_costs': cumulative_costs,
            'total_cost': round(cumulative, 2),
            'average_daily_cost': round(cumulative / len(daily_costs) if daily_costs else 0, 2)
        }
    except Exception as e:
        print(f"❌ Error collecting cost trends: {e}")
        raise

# ============================================
# API Routes
# ============================================

@dashboard_bp.route('/resources', methods=['GET'])
def get_resource_usage():
    """
    리소스 사용률 시계열 데이터
    GET /api/reports/dashboard/resources
    """
    try:
        # Production 모드에서 실제 데이터 수집 시도
        if not MOCK_MODE and SLURM_COLLECTOR_AVAILABLE:
            try:
                data = collect_resource_data()
                data['mode'] = 'production'
                data['status'] = 'success'
                return jsonify(data)
            except Exception as e:
                print(f"⚠️  Production mode failed: {e}")
                print("⚠️  Falling back to mock data")
        
        # Mock 데이터 반환
        data = generate_mock_resource_data()
        data['mode'] = 'demo' if not MOCK_MODE else 'mock'
        data['status'] = 'success'
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@dashboard_bp.route('/top-users', methods=['GET'])
def get_top_users():
    """
    Top 사용자 순위
    GET /api/reports/dashboard/top-users?limit=10
    """
    try:
        limit = int(request.args.get('limit', 10))
        limit = min(max(limit, 1), 50)  # 1~50 사이로 제한
        
        # Production 모드에서 실제 데이터 수집 시도
        if not MOCK_MODE and SLURM_COLLECTOR_AVAILABLE:
            try:
                users = collect_top_users(limit)
                return jsonify({
                    'status': 'success',
                    'mode': 'production',
                    'users': users,
                    'count': len(users)
                })
            except Exception as e:
                print(f"⚠️  Production mode failed: {e}")
                print("⚠️  Falling back to mock data")
        
        # Mock 데이터 반환
        users = generate_mock_top_users(limit)
        return jsonify({
            'status': 'success',
            'mode': 'demo' if not MOCK_MODE else 'mock',
            'users': users,
            'count': len(users)
        })
    
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@dashboard_bp.route('/job-status', methods=['GET'])
def get_job_status():
    """
    작업 상태 분포
    GET /api/reports/dashboard/job-status
    """
    try:
        # Production 모드에서 실제 데이터 수집 시도
        if not MOCK_MODE and SLURM_COLLECTOR_AVAILABLE:
            try:
                data = collect_job_status()
                data['mode'] = 'production'
                data['status'] = 'success'
                return jsonify(data)
            except Exception as e:
                print(f"⚠️  Production mode failed: {e}")
                print("⚠️  Falling back to mock data")
        
        # Mock 데이터 반환
        data = generate_mock_job_status()
        data['mode'] = 'demo' if not MOCK_MODE else 'mock'
        data['status'] = 'success'
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@dashboard_bp.route('/cost-trends', methods=['GET'])
def get_cost_trends():
    """
    비용 추이 (일별)
    GET /api/reports/dashboard/cost-trends?period=week
    period: week, month, year
    """
    try:
        period = request.args.get('period', 'week')
        if period not in ['week', 'month', 'year']:
            period = 'week'
        
        # Production 모드에서 실제 데이터 수집 시도
        if not MOCK_MODE and SLURM_COLLECTOR_AVAILABLE:
            try:
                data = collect_cost_trends(period)
                data['mode'] = 'production'
                data['status'] = 'success'
                return jsonify(data)
            except Exception as e:
                print(f"⚠️  Production mode failed: {e}")
                print("⚠️  Falling back to mock data")
        
        # Mock 데이터 반환
        data = generate_mock_cost_trends(period)
        data['mode'] = 'demo' if not MOCK_MODE else 'mock'
        data['status'] = 'success'
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

# Health check
@dashboard_bp.route('/health', methods=['GET'])
def health_check():
    """Dashboard API 상태 확인"""
    return jsonify({
        'status': 'healthy',
        'service': 'dashboard_api',
        'version': '3.4.0',
        'mock_mode': MOCK_MODE,
        'slurm_available': SLURM_COLLECTOR_AVAILABLE,
        'timestamp': datetime.now().isoformat()
    })
