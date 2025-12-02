#!/usr/bin/env python3
"""
Slurm 설치 자동화 - 유틸리티 함수들
공통으로 사용되는 유틸리티 함수들을 모아놓은 모듈
"""

import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import sys
import os


def setup_logging(log_level: str = 'info', log_dir: str = './logs') -> logging.Logger:
    """로깅 설정 (개선된 버전)
    
    Args:
        log_level: 로그 레벨 (debug, info, warning, error)
        log_dir: 로그 파일을 저장할 디렉토리
        
    Returns:
        설정된 로거 객체
    """
    
    # 로그 디렉토리 생성
    os.makedirs(log_dir, exist_ok=True)
    
    # 로그 레벨 설정
    level_map = {
        'debug': logging.DEBUG,
        'info': logging.INFO,
        'warning': logging.WARNING,
        'error': logging.ERROR
    }
    
    level = level_map.get(log_level.lower(), logging.INFO)
    
    # 로거 설정
    logger = logging.getLogger('slurm_installer')
    logger.setLevel(level)
    
    # 이미 핸들러가 설정되어 있으면 제거
    if logger.handlers:
        logger.handlers.clear()
    
    # 콘솔 핸들러 (색상 지원)
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(level)
    
    # 파일 핸들러 (일반 로그)
    log_filename = os.path.join(log_dir, f"slurm_install_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")
    file_handler = logging.FileHandler(log_filename, encoding='utf-8')
    file_handler.setLevel(logging.DEBUG)  # 파일에는 모든 로그 저장
    
    # 에러 로그 파일 핸들러 (에러만 별도 저장)
    error_log_filename = os.path.join(log_dir, f"slurm_install_error_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")
    error_file_handler = logging.FileHandler(error_log_filename, encoding='utf-8')
    error_file_handler.setLevel(logging.ERROR)
    
    # 로그 포맷 설정
    console_format = logging.Formatter(
        '%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    file_format = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(funcName)s() - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    console_handler.setFormatter(console_format)
    file_handler.setFormatter(file_format)
    error_file_handler.setFormatter(file_format)
    
    # 핸들러 추가
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    logger.addHandler(error_file_handler)
    
    # 타사 라이브러리 로그 레벨 조정 (노이즈 감소)
    logging.getLogger('paramiko').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)
    
    logger.info(f"로깅 설정 완료")
    logger.info(f"  - 레벨: {log_level.upper()}")
    logger.info(f"  - 일반 로그: {log_filename}")
    logger.info(f"  - 에러 로그: {error_log_filename}")
    
    return logger


def print_banner():
    """프로그램 시작 배너 출력"""
    banner = """
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║        KooSlurmInstallAutomation                             ║
║        Slurm Cluster Automated Installation Tool            ║
║                                                              ║
║        Version: 1.0.0                                        ║
║        Author: Koo Automation Team                           ║
║        Date: """ + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + """                              ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
    """
    
    print(banner)
    print()


def print_summary(success: bool, elapsed_time: int, config_parser = None):
    """설치 완료 후 요약 정보 출력"""
    
    print("\n" + "="*70)
    print("설치 완료 요약")
    print("="*70)
    
    # 설치 결과
    result_icon = "✅" if success else "❌"
    result_text = "성공" if success else "실패"
    print(f"설치 결과: {result_icon} {result_text}")
    
    # 소요 시간
    hours, remainder = divmod(elapsed_time, 3600)
    minutes, seconds = divmod(remainder, 60)
    
    if hours > 0:
        time_str = f"{hours}시간 {minutes}분 {seconds}초"
    elif minutes > 0:
        time_str = f"{minutes}분 {seconds}초"
    else:
        time_str = f"{seconds}초"
    
    print(f"소요 시간: {time_str}")
    print(f"완료 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    if config_parser:
        # 클러스터 정보
        cluster_info = config_parser.config.get('cluster_info', {})
        print(f"클러스터 이름: {cluster_info.get('cluster_name', 'N/A')}")
        
        # 노드 수
        controller = config_parser.get_controller_node()
        compute_nodes = config_parser.get_compute_nodes()
        
        print(f"설치된 노드 수: {len(compute_nodes) + 1}개 (컨트롤러 1개 + 계산노드 {len(compute_nodes)}개)")
        
        # 설치 단계
        stage = config_parser.get_install_stage()
        stage_names = {1: "기본 설치", 2: "고급 기능", 3: "운영 최적화"}
        print(f"설치 단계: Stage {stage} ({stage_names.get(stage, '알 수 없음')})")
    
    print("="*70)
    
    if success:
        print("\n🎉 Slurm 클러스터 설치가 완료되었습니다!")
        print("\n📋 다음 단계:")
        print("  1. 노드 상태 확인: sinfo")
        print("  2. 파티션 확인: sinfo -s")
        print("  3. 테스트 작업 제출: sbatch test_job.sh")
        print("  4. 작업 큐 확인: squeue")
        print("  5. 계정 정보 확인: sacctmgr show accounts")
        
        if config_parser and config_parser.is_feature_enabled('monitoring.grafana'):
            grafana_port = config_parser.get_config_value('monitoring.grafana.port', 3000)
            controller_ip = config_parser.get_controller_node().get('ip_address', 'controller')
            print(f"  6. Grafana 대시보드: http://{controller_ip}:{grafana_port}")
        
        print("\n📚 추가 정보:")
        print("  - Slurm 공식 문서: https://slurm.schedmd.com/documentation.html")
        print("  - 문제 해결 가이드: https://slurm.schedmd.com/troubleshoot.html")
        
    else:
        print("\n❌ 설치 중 오류가 발생했습니다.")
        print("   로그 파일을 확인하시고, 문제를 해결한 후 다시 시도해주세요.")
        
        print("\n🔧 일반적인 문제 해결 방법:")
        print("  1. 네트워크 연결 확인")
        print("  2. SSH 키 권한 확인 (chmod 600 ~/.ssh/id_rsa)")
        print("  3. sudo 권한 확인")
        print("  4. 방화벽 설정 확인")
        print("  5. 디스크 공간 확인")
    
    print("\n" + "="*70)


def format_time_duration(seconds: int) -> str:
    """초를 시:분:초 형식으로 변환"""
    hours, remainder = divmod(seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    
    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    else:
        return f"{minutes:02d}:{seconds:02d}"


def format_file_size(bytes_size: int) -> str:
    """바이트를 사람이 읽기 쉬운 형식으로 변환"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.1f}{unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.1f}PB"


def validate_hostname(hostname: str) -> bool:
    """호스트네임 유효성 검증"""
    import re
    
    if not hostname or len(hostname) > 253:
        return False
    
    # 호스트네임 패턴 (RFC 1123)
    pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
    
    return bool(re.match(pattern, hostname))


def validate_ip_address(ip: str) -> bool:
    """IP 주소 유효성 검증"""
    import ipaddress
    
    try:
        ipaddress.ip_address(ip)
        return True
    except ValueError:
        return False


def validate_port(port: int) -> bool:
    """포트 번호 유효성 검증"""
    return 1 <= port <= 65535


def generate_slurm_node_list(hostnames: List[str]) -> str:
    """호스트네임 리스트를 Slurm 노드 리스트 형식으로 변환"""
    if not hostnames:
        return ""
    
    if len(hostnames) == 1:
        return hostnames[0]
    
    # 연속된 숫자 패턴 찾기 (예: node01, node02, node03 -> node[01-03])
    import re
    
    # 호스트네임을 정렬
    sorted_hostnames = sorted(hostnames)
    
    # 패턴 그룹핑
    groups = {}
    for hostname in sorted_hostnames:
        # 숫자 패턴 찾기
        match = re.match(r'^(.+?)(\d+)$', hostname)
        if match:
            prefix = match.group(1)
            number = int(match.group(2))
            
            if prefix not in groups:
                groups[prefix] = []
            groups[prefix].append((number, hostname))
        else:
            # 숫자가 없는 호스트네임
            if 'no_number' not in groups:
                groups['no_number'] = []
            groups['no_number'].append((0, hostname))
    
    # 노드 리스트 생성
    node_list_parts = []
    
    for prefix, nodes in groups.items():
        if prefix == 'no_number':
            # 숫자가 없는 노드들은 그냥 나열
            node_list_parts.extend([hostname for _, hostname in nodes])
            continue
        
        nodes.sort()  # 숫자 순으로 정렬
        
        if len(nodes) == 1:
            node_list_parts.append(nodes[0][1])
            continue
        
        # 연속된 범위 찾기
        ranges = []
        start = nodes[0][0]
        end = nodes[0][0]
        
        for i in range(1, len(nodes)):
            current_num = nodes[i][0]
            
            if current_num == end + 1:
                end = current_num
            else:
                # 범위 완료
                if start == end:
                    ranges.append(f"{start:02d}")
                else:
                    ranges.append(f"{start:02d}-{end:02d}")
                
                start = current_num
                end = current_num
        
        # 마지막 범위 추가
        if start == end:
            ranges.append(f"{start:02d}")
        else:
            ranges.append(f"{start:02d}-{end:02d}")
        
        # 최종 노드 리스트 형식 생성
        if len(ranges) == 1 and '-' not in ranges[0]:
            node_list_parts.append(f"{prefix}{ranges[0]}")
        else:
            node_list_parts.append(f"{prefix}[{','.join(ranges)}]")
    
    return ','.join(node_list_parts)


def create_test_job_script() -> str:
    """테스트 작업 스크립트 생성"""
    
    script = """#!/bin/bash
#SBATCH --job-name=slurm_test
#SBATCH --output=slurm_test_%j.out
#SBATCH --error=slurm_test_%j.err
#SBATCH --time=00:05:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1

echo "==================================="
echo "Slurm Cluster Test Job"
echo "==================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Job Name: $SLURM_JOB_NAME"
echo "Node List: $SLURM_JOB_NODELIST"
echo "Number of Nodes: $SLURM_JOB_NUM_NODES"
echo "Number of Tasks: $SLURM_NTASKS"
echo "Start Time: $(date)"
echo ""

echo "System Information:"
echo "  Hostname: $(hostname)"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"')"
echo "  Kernel: $(uname -r)"
echo "  Architecture: $(uname -m)"
echo "  CPUs: $(nproc)"
echo "  Memory: $(free -h | grep Mem | awk '{print $2}')"
echo ""

echo "Environment Variables:"
echo "  USER: $USER"
echo "  HOME: $HOME"
echo "  PATH: $PATH"
echo "  SLURM_CLUSTER_NAME: $SLURM_CLUSTER_NAME"
echo "  SLURM_PARTITION: $SLURM_JOB_PARTITION"
echo ""

echo "Running test computation..."
# 간단한 CPU 테스트
python3 -c "
import time
import math
start_time = time.time()
result = sum(math.sqrt(i) for i in range(1000000))
end_time = time.time()
print(f'  Computation result: {result:.2f}')
print(f'  Computation time: {end_time - start_time:.3f} seconds')
"

echo ""
echo "Disk space on compute node:"
df -h | grep -E '(Filesystem|/dev/)'

echo ""
echo "Network connectivity test:"
ping -c 3 8.8.8.8 > /dev/null 2>&1 && echo "  Internet: OK" || echo "  Internet: Failed"

echo ""
echo "End Time: $(date)"
echo "==================================="
echo "Test Job Completed Successfully!"
echo "==================================="
"""
    
    return script


def create_gpu_test_job_script() -> str:
    """GPU 테스트 작업 스크립트 생성"""
    
    script = """#!/bin/bash
#SBATCH --job-name=gpu_test
#SBATCH --output=gpu_test_%j.out
#SBATCH --error=gpu_test_%j.err
#SBATCH --time=00:05:00
#SBATCH --nodes=1
#SBATCH --gres=gpu:1

echo "==================================="
echo "Slurm GPU Test Job"
echo "==================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start Time: $(date)"
echo ""

echo "GPU Information:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=index,name,memory.total,utilization.gpu --format=csv,noheader,nounits
    echo ""
    
    echo "CUDA Version:"
    nvidia-smi | grep "CUDA Version" | sed 's/.*CUDA Version: /  /'
    echo ""
    
    echo "Running GPU test..."
    # 간단한 GPU 메모리 테스트
    python3 -c "
import subprocess
try:
    result = subprocess.run(['nvidia-smi', '--query-gpu=memory.used,memory.total', '--format=csv,noheader,nounits'], 
                          capture_output=True, text=True)
    if result.returncode == 0:
        lines = result.stdout.strip().split('\n')
        for i, line in enumerate(lines):
            used, total = line.split(', ')
            usage_percent = (int(used) / int(total)) * 100
            print(f'  GPU {i}: {used}MB / {total}MB ({usage_percent:.1f}% used)')
    else:
        print('  GPU memory query failed')
except Exception as e:
    print(f'  GPU test error: {e}')
"
else
    echo "  NVIDIA drivers not found"
fi

echo ""
echo "End Time: $(date)"
echo "==================================="
echo "GPU Test Job Completed!"
echo "==================================="
"""
    
    return script


def check_system_requirements() -> Dict[str, bool]:
    """시스템 요구사항 확인"""
    requirements = {
        'python_version': False,
        'ssh_client': False,
        'required_modules': False
    }
    
    # Python 버전 확인 (3.7 이상)
    if sys.version_info >= (3, 7):
        requirements['python_version'] = True
    
    # SSH 클라이언트 확인
    try:
        import subprocess
        result = subprocess.run(['ssh', '-V'], capture_output=True, text=True)
        if result.returncode == 0 or 'OpenSSH' in result.stderr:
            requirements['ssh_client'] = True
    except:
        pass
    
    # 필요한 Python 모듈 확인
    required_modules = ['yaml', 'paramiko', 'ipaddress']
    all_modules_available = True
    
    for module in required_modules:
        try:
            if module == 'ipaddress' and sys.version_info >= (3, 3):
                # ipaddress는 Python 3.3+에서 내장 모듈
                continue
            __import__(module)
        except ImportError:
            all_modules_available = False
            break
    
    requirements['required_modules'] = all_modules_available
    
    return requirements


def print_system_requirements_check():
    """시스템 요구사항 확인 결과 출력"""
    print("\n🔍 시스템 요구사항 확인:")
    print("-" * 40)
    
    requirements = check_system_requirements()
    
    # Python 버전
    python_status = "✅" if requirements['python_version'] else "❌"
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    print(f"Python (≥3.7): {python_status} {python_version}")
    
    # SSH 클라이언트
    ssh_status = "✅" if requirements['ssh_client'] else "❌"
    print(f"SSH 클라이언트: {ssh_status}")
    
    # Python 모듈들
    modules_status = "✅" if requirements['required_modules'] else "❌"
    print(f"필수 Python 모듈: {modules_status}")
    
    if not requirements['required_modules']:
        print("   누락된 모듈 설치: pip install PyYAML paramiko")
    
    print("-" * 40)
    
    all_good = all(requirements.values())
    if all_good:
        print("✅ 모든 시스템 요구사항이 충족되었습니다.")
    else:
        print("❌ 일부 시스템 요구사항이 충족되지 않았습니다.")
        print("   위의 문제들을 해결한 후 다시 실행해주세요.")
    
    return all_good


def main():
    """테스트 메인 함수"""
    print_banner()
    
    # 시스템 요구사항 확인
    if print_system_requirements_check():
        print("\n테스트: 유틸리티 함수들")
        
        # 시간 형식 테스트
        print(f"시간 형식: {format_time_duration(3661)}")  # 1:01:01
        
        # 파일 크기 형식 테스트
        print(f"파일 크기: {format_file_size(1536)}")  # 1.5KB
        
        # 호스트네임 검증 테스트
        print(f"호스트네임 검증: {validate_hostname('node01')}")  # True
        print(f"IP 주소 검증: {validate_ip_address('192.168.1.1')}")  # True
        
        # 노드 리스트 형식 테스트
        hostnames = ['node01', 'node02', 'node03', 'gpu01', 'gpu02']
        node_list = generate_slurm_node_list(hostnames)
        print(f"노드 리스트: {node_list}")
        
        # 가짜 설정 파서로 요약 출력 테스트
        class FakeParser:
            def __init__(self):
                self.config = {
                    'cluster_info': {'cluster_name': 'test-cluster'}
                }
            def get_controller_node(self):
                return {'hostname': 'controller01'}
            def get_compute_nodes(self):
                return [{'hostname': 'node01'}, {'hostname': 'node02'}]
            def get_install_stage(self):
                return 1
            def is_feature_enabled(self, feature):
                return False
        
        fake_parser = FakeParser()
        print_summary(True, 150, fake_parser)


if __name__ == "__main__":
    main()
