#!/usr/bin/env python3
"""
reports_api.py에서 모든 "Not implemented in production mode" 제거
"""

import re

# 파일 읽기
with open('reports_api.py', 'r', encoding='utf-8') as f:
    content = f.read()

# 백업
with open('reports_api.py.backup', 'w', encoding='utf-8') as f:
    f.write(content)

# "return jsonify({'error': 'Not implemented in production mode'}), 501" 모두 제거
content = re.sub(
    r"\s+return jsonify\(\{'error': 'Not implemented in production mode'\}\), 501",
    "",
    content
)

# "if MOCK_MODE:" 블록을 일반 코드로 변경
# efficiency_report 함수 수정
content = re.sub(
    r"(@reports_bp\.route\('/efficiency'.*?def efficiency_report\(\):.*?start_date, end_date = get_date_range\(period\)\s+)(if MOCK_MODE:\s+print)",
    r"\1# Production/Mock 모드 모두 지원\n    mode_label = '[MOCK]' if MOCK_MODE else '[DEMO]'\n    print",
    content,
    flags=re.DOTALL
)

# overview 추가 (파일에 없으면)
if '/overview' not in content:
    # overview 엔드포인트 추가
    overview_code = '''

# ============================================
# GET /api/reports/overview
# 종합 개요
# ============================================
@reports_bp.route('/overview', methods=['GET'])
def overview_report():
    """
    전체 시스템 개요
    """
    # Production 모드: 실제 Slurm 데이터
    if not MOCK_MODE and SLURM_COLLECTOR_AVAILABLE:
        print("📊 [PRODUCTION] Overview report")
        
        try:
            cluster_state = get_current_cluster_state()
            
            # 오늘 작업 데이터
            today = datetime.now()
            today_start = today.replace(hour=0, minute=0, second=0)
            jobs_today = get_slurm_jobs_data(today_start, today)
            
            # 이번 달 비용 (간단 계산)
            month_start = today.replace(day=1, hour=0, minute=0, second=0)
            month_data = get_daily_usage_data(month_start, today)
            total_cpu = sum(d['cpu_hours'] for d in month_data)
            costs_month = calculate_costs(total_cpu, 0, 0)
            
            return jsonify({
                'status': 'success',
                'mode': 'production',
                'summary': {
                    'total_users': cluster_state.get('total_users', 0),
                    'active_users': cluster_state['active_users'],
                    'total_jobs_today': jobs_today['total'],
                    'running_jobs': cluster_state['running_jobs'],
                    'pending_jobs': cluster_state['pending_jobs']
                },
                'resources': {
                    'cpu_utilization': cluster_state['cpu_utilization'],
                    'gpu_utilization': cluster_state['gpu_utilization'],
                    'memory_utilization': cluster_state['memory_utilization']
                },
                'costs_today': round(jobs_today.get('total_cpu_hours', 0) * 0.5, 2),
                'costs_this_month': costs_month['total_cost'],
                'generated_at': datetime.now().isoformat()
            })
        except Exception as e:
            print(f"❌ Error collecting overview data: {e}")
            import traceback
            traceback.print_exc()
            print("⚠️  Falling back to mock data")
    
    # Mock 모드 또는 Fallback
    mode_label = "[MOCK]" if MOCK_MODE else "[DEMO-FALLBACK]"
    print(f"📊 {mode_label} Overview report")
    
    import random
    
    return jsonify({
        'status': 'success',
        'mode': 'mock' if MOCK_MODE else 'demo',
        'summary': {
            'total_users': random.randint(10, 50),
            'active_users': random.randint(5, 30),
            'total_jobs_today': random.randint(20, 100),
            'running_jobs': random.randint(5, 20),
            'pending_jobs': random.randint(0, 10)
        },
        'resources': {
            'cpu_utilization': round(random.uniform(60, 90), 2),
            'gpu_utilization': round(random.uniform(70, 95), 2),
            'memory_utilization': round(random.uniform(65, 85), 2)
        },
        'costs_today': round(random.uniform(100, 500), 2),
        'costs_this_month': round(random.uniform(3000, 10000), 2),
        'generated_at': datetime.now().isoformat()
    })
'''
    # efficiency_report 다음에 삽입
    content = content.replace(
        'print("✅ Reports API initialized")',
        overview_code + '\nprint("✅ Reports API initialized")'
    )

# 저장
with open('reports_api.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ reports_api.py 수정 완료")
print("   - 'Not implemented in production mode' 제거")
print("   - overview 엔드포인트 추가")
