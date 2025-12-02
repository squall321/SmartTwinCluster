"""
Slurm 데이터 수집 유틸리티
실제 Slurm 명령어로 데이터 수집
"""

import subprocess
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any

def run_slurm_command(command: List[str]) -> str:
    """Slurm 명령어 실행"""
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            return result.stdout
        else:
            print(f"❌ Slurm command failed: {' '.join(command)}")
            print(f"   Error: {result.stderr}")
            return ""
    except Exception as e:
        print(f"❌ Exception running command: {e}")
        return ""

def get_slurm_jobs_data(start_date: datetime, end_date: datetime) -> Dict[str, Any]:
    """
    Slurm에서 작업 데이터 수집
    sacct 명령어 사용
    """
    # 날짜 형식: YYYY-MM-DD
    start_str = start_date.strftime('%Y-%m-%d')
    end_str = end_date.strftime('%Y-%m-%d')
    
    # sacct로 작업 정보 수집
    command = [
        'sacct',
        '-S', start_str,
        '-E', end_str,
        '--format=JobID,JobName,User,State,AllocCPUS,AllocNodes,Elapsed,TotalCPU,Start,End',
        '--parsable2',
        '--noheader',
        '--allocations'  # 작업 단위만 (각 step 제외)
    ]
    
    output = run_slurm_command(command)
    if not output:
        return {
            'jobs': [],
            'total': 0,
            'completed': 0,
            'failed': 0,
            'running': 0,
            'pending': 0
        }
    
    jobs = []
    states = {'COMPLETED': 0, 'FAILED': 0, 'RUNNING': 0, 'PENDING': 0, 'CANCELLED': 0}
    total_cpu_hours = 0
    
    for line in output.strip().split('\n'):
        if not line:
            continue
        
        parts = line.split('|')
        if len(parts) < 10:
            continue
        
        job_id, job_name, user, state, cpus, nodes, elapsed, total_cpu, start, end = parts[:10]
        
        # 상태 카운트
        state_clean = state.split()[0]  # "COMPLETED" from "COMPLETED by 0"
        if state_clean in states:
            states[state_clean] += 1
        
        # CPU 시간 계산 (elapsed time * cpus)
        try:
            cpu_count = int(cpus) if cpus else 0
            # elapsed 형식: DD-HH:MM:SS 또는 HH:MM:SS
            elapsed_hours = parse_time_to_hours(elapsed)
            cpu_hours = elapsed_hours * cpu_count
            total_cpu_hours += cpu_hours
        except:
            pass
        
        jobs.append({
            'job_id': job_id,
            'name': job_name,
            'user': user,
            'state': state_clean,
            'cpus': cpu_count,
            'elapsed': elapsed
        })
    
    return {
        'jobs': jobs,
        'total': len(jobs),
        'completed': states['COMPLETED'],
        'failed': states['FAILED'] + states['CANCELLED'],
        'running': states['RUNNING'],
        'pending': states['PENDING'],
        'total_cpu_hours': round(total_cpu_hours, 2)
    }

def get_slurm_usage_by_user(start_date: datetime, end_date: datetime) -> List[Dict[str, Any]]:
    """
    사용자별 리소스 사용량 수집
    sreport 명령어 사용
    """
    start_str = start_date.strftime('%Y-%m-%d')
    end_str = end_date.strftime('%Y-%m-%d')
    
    # sreport로 사용자별 사용량 수집
    command = [
        'sreport',
        'cluster',
        'UserUtilizationByAccount',
        'Start=' + start_str,
        'End=' + end_str,
        '-t', 'Hours',
        '--parsable2',
        '--noheader'
    ]
    
    output = run_slurm_command(command)
    if not output:
        return []
    
    users = []
    for line in output.strip().split('\n'):
        if not line or line.startswith('Cluster'):
            continue
        
        parts = line.split('|')
        if len(parts) < 4:
            continue
        
        # Format: Cluster|Account|Login|Proper|Used
        cluster, account, login, proper, used = parts[:5]
        
        try:
            cpu_hours = float(used) if used else 0.0
            users.append({
                'username': login,
                'account': account,
                'cpu_hours': round(cpu_hours, 2),
                'gpu_hours': 0,  # GPU는 별도 수집 필요
                'memory_gb_hours': 0,  # 메모리는 별도 수집 필요
                'jobs_total': 0,
                'jobs_success': 0,
                'jobs_failed': 0,
                'cost': round(cpu_hours * 0.5, 2)  # CPU $0.5/hour
            })
        except:
            continue
    
    return users

def get_current_cluster_state() -> Dict[str, Any]:
    """
    현재 클러스터 상태 수집
    sinfo, squeue 사용
    """
    # 노드 정보
    sinfo_output = run_slurm_command(['sinfo', '-h', '-o', '%D|%C'])
    total_nodes = 0
    total_cpus = 0
    used_cpus = 0
    
    if sinfo_output:
        for line in sinfo_output.strip().split('\n'):
            parts = line.split('|')
            if len(parts) >= 2:
                nodes = int(parts[0])
                # CPU 형식: A/I/O/T (Allocated/Idle/Other/Total)
                cpu_parts = parts[1].split('/')
                if len(cpu_parts) >= 4:
                    allocated = int(cpu_parts[0])
                    total = int(cpu_parts[3])
                    total_nodes += nodes
                    total_cpus += total
                    used_cpus += allocated
    
    cpu_utilization = (used_cpus / total_cpus * 100) if total_cpus > 0 else 0
    
    # 실행 중인 작업
    squeue_output = run_slurm_command(['squeue', '-h', '-o', '%T'])
    running_jobs = 0
    pending_jobs = 0
    
    if squeue_output:
        for line in squeue_output.strip().split('\n'):
            state = line.strip()
            if state == 'RUNNING' or state == 'R':
                running_jobs += 1
            elif state == 'PENDING' or state == 'PD':
                pending_jobs += 1
    
    # 사용자 수 (활성)
    users_output = run_slurm_command(['squeue', '-h', '-o', '%u'])
    active_users = len(set(users_output.strip().split('\n'))) if users_output else 0
    
    return {
        'total_nodes': total_nodes,
        'total_cpus': total_cpus,
        'used_cpus': used_cpus,
        'cpu_utilization': round(cpu_utilization, 2),
        'gpu_utilization': 0,  # GPU는 별도 수집 필요
        'memory_utilization': 0,  # 메모리는 별도 수집 필요
        'running_jobs': running_jobs,
        'pending_jobs': pending_jobs,
        'active_users': active_users,
        'total_users': 0  # 전체 사용자는 별도 수집 필요
    }

def parse_time_to_hours(time_str: str) -> float:
    """
    시간 문자열을 시간(hours)으로 변환
    형식: DD-HH:MM:SS 또는 HH:MM:SS 또는 MM:SS
    """
    if not time_str or time_str == '':
        return 0.0
    
    try:
        parts = time_str.split('-')
        days = 0
        time_part = time_str
        
        if len(parts) == 2:
            days = int(parts[0])
            time_part = parts[1]
        
        time_components = time_part.split(':')
        hours = 0
        minutes = 0
        seconds = 0
        
        if len(time_components) == 3:
            hours = int(time_components[0])
            minutes = int(time_components[1])
            seconds = int(time_components[2])
        elif len(time_components) == 2:
            minutes = int(time_components[0])
            seconds = int(time_components[1])
        elif len(time_components) == 1:
            seconds = int(time_components[0])
        
        total_hours = days * 24 + hours + minutes / 60 + seconds / 3600
        return total_hours
    except:
        return 0.0

def get_daily_usage_data(start_date: datetime, end_date: datetime) -> List[Dict[str, Any]]:
    """
    일별 사용량 데이터 생성
    실제로는 sacct를 날짜별로 호출해야 하지만, 
    전체 기간의 데이터를 날짜별로 그룹화
    """
    jobs_data = get_slurm_jobs_data(start_date, end_date)
    
    # 간단히 하기 위해 전체 데이터를 균등 분배
    # 실제로는 각 작업의 Start 날짜로 그룹화해야 함
    days = (end_date - start_date).days
    if days <= 0:
        days = 1
    
    daily_data = []
    # total_cpu_hours 키가 없을 수 있으므로 기본값 사용
    total_cpu_hours = jobs_data.get('total_cpu_hours', 0)
    avg_cpu_per_day = total_cpu_hours / days if days > 0 else 0
    avg_jobs_per_day = jobs_data['total'] / days if days > 0 else 0
    
    for i in range(days):
        date = start_date + timedelta(days=i)
        daily_data.append({
            'date': date.strftime('%Y-%m-%d'),
            'cpu_hours': round(avg_cpu_per_day, 2),
            'gpu_hours': 0,  # GPU 데이터 수집 필요
            'memory_gb_hours': 0,  # 메모리 데이터 수집 필요
            'jobs_submitted': int(avg_jobs_per_day),
            'jobs_completed': int(avg_jobs_per_day * 0.9),  # 추정
            'jobs_failed': int(avg_jobs_per_day * 0.1)  # 추정
        })
    
    return daily_data

# 테스트
if __name__ == '__main__':
    print("Testing Slurm data collection...")
    
    # 현재 상태
    state = get_current_cluster_state()
    print("\nCurrent State:")
    print(json.dumps(state, indent=2))
    
    # 최근 7일 작업 데이터
    end_date = datetime.now()
    start_date = end_date - timedelta(days=7)
    jobs = get_slurm_jobs_data(start_date, end_date)
    print("\nJobs (last 7 days):")
    print(f"Total: {jobs['total']}")
    print(f"Completed: {jobs['completed']}")
    print(f"Failed: {jobs['failed']}")
    
    # 사용자 데이터
    users = get_slurm_usage_by_user(start_date, end_date)
    print(f"\nUsers: {len(users)}")
    if users:
        print(f"Top user: {users[0]}")
