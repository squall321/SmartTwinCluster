#!/usr/bin/env python3
"""
성능 모니터링 모듈
프로그램 별 실행 시간, CPU 사용량, 메모리 사용량을 추적하고 기록합니다.
"""

import os
import time
import psutil
import threading
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from collections import defaultdict
import atexit


class PerformanceMonitor:
    """
    성능 모니터링 클래스
    - 프로세스별 CPU, 메모리 사용량 추적
    - 주기적인 샘플링 (기본 60초)
    - JSON 형식으로 로그 저장
    """
    
    def __init__(
        self,
        log_dir: str = "./performance_logs",
        sampling_interval: int = 60,
        enable_monitoring: bool = True
    ):
        """
        Args:
            log_dir: 성능 로그를 저장할 디렉토리
            sampling_interval: 샘플링 간격 (초)
            enable_monitoring: 모니터링 활성화 여부
        """
        self.log_dir = Path(log_dir)
        self.sampling_interval = sampling_interval
        self.enable_monitoring = enable_monitoring
        
        # 모니터링 데이터
        self.samples: List[Dict[str, Any]] = []
        self.start_time = time.time()
        self.process = psutil.Process()
        
        # 스레드 제어
        self._stop_event = threading.Event()
        self._monitor_thread: Optional[threading.Thread] = None
        
        # 로거 설정
        self.logger = logging.getLogger(__name__)
        
        # 함수별 성능 추적
        self.function_stats = defaultdict(lambda: {
            'count': 0,
            'total_time': 0.0,
            'min_time': float('inf'),
            'max_time': 0.0,
            'cpu_time': 0.0
        })
        
        if self.enable_monitoring:
            self._setup_logging()
            self._start_monitoring()
            # 프로그램 종료 시 자동 저장
            atexit.register(self.stop_and_save)
    
    def _setup_logging(self):
        """로그 디렉토리 생성"""
        self.log_dir.mkdir(parents=True, exist_ok=True)
    
    def _start_monitoring(self):
        """백그라운드 모니터링 시작"""
        self._monitor_thread = threading.Thread(
            target=self._monitoring_loop,
            daemon=True,
            name="PerformanceMonitor"
        )
        self._monitor_thread.start()
        self.logger.info(f"성능 모니터링 시작 (간격: {self.sampling_interval}초)")
    
    def _monitoring_loop(self):
        """주기적으로 성능 데이터 수집"""
        while not self._stop_event.is_set():
            try:
                self._collect_sample()
            except Exception as e:
                self.logger.error(f"성능 데이터 수집 중 오류: {e}")
            
            # 다음 샘플링까지 대기
            self._stop_event.wait(self.sampling_interval)
    
    def _collect_sample(self):
        """현재 시점의 성능 데이터 수집"""
        try:
            # 프로세스 정보
            with self.process.oneshot():
                cpu_percent = self.process.cpu_percent(interval=0.1)
                memory_info = self.process.memory_info()
                num_threads = self.process.num_threads()
                
                # CPU 시간 (user + system)
                cpu_times = self.process.cpu_times()
                cpu_time_total = cpu_times.user + cpu_times.system
            
            # 샘플 데이터
            sample = {
                'timestamp': datetime.now().isoformat(),
                'elapsed_time': time.time() - self.start_time,
                'cpu_percent': cpu_percent,
                'cpu_time_total': cpu_time_total,
                'memory_rss_mb': memory_info.rss / (1024 * 1024),
                'memory_vms_mb': memory_info.vms / (1024 * 1024),
                'num_threads': num_threads,
                'pid': self.process.pid
            }
            
            # 자식 프로세스 포함 (SSH 등)
            try:
                children = self.process.children(recursive=True)
                if children:
                    total_child_cpu = sum(
                        p.cpu_percent(interval=0.1) 
                        for p in children 
                        if p.is_running()
                    )
                    total_child_mem = sum(
                        p.memory_info().rss 
                        for p in children 
                        if p.is_running()
                    )
                    sample['children_count'] = len(children)
                    sample['children_cpu_percent'] = total_child_cpu
                    sample['children_memory_mb'] = total_child_mem / (1024 * 1024)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
            
            self.samples.append(sample)
            
        except psutil.NoSuchProcess:
            self.logger.warning("프로세스가 종료되었습니다.")
            self._stop_event.set()
    
    def track_function(self, func_name: str = None):
        """
        함수 실행 시간과 CPU 사용량을 추적하는 데코레이터
        
        Usage:
            @monitor.track_function()
            def my_function():
                pass
        """
        def decorator(func):
            nonlocal func_name
            if func_name is None:
                func_name = func.__name__
            
            def wrapper(*args, **kwargs):
                if not self.enable_monitoring:
                    return func(*args, **kwargs)
                
                # CPU 시간 측정 시작
                cpu_start = time.process_time()
                wall_start = time.time()
                
                try:
                    result = func(*args, **kwargs)
                    return result
                finally:
                    # 실행 시간 계산
                    wall_time = time.time() - wall_start
                    cpu_time = time.process_time() - cpu_start
                    
                    # 통계 업데이트
                    stats = self.function_stats[func_name]
                    stats['count'] += 1
                    stats['total_time'] += wall_time
                    stats['cpu_time'] += cpu_time
                    stats['min_time'] = min(stats['min_time'], wall_time)
                    stats['max_time'] = max(stats['max_time'], wall_time)
            
            return wrapper
        return decorator
    
    def start_operation(self, operation_name: str) -> 'OperationTracker':
        """
        특정 작업의 성능 추적 시작
        
        Usage:
            with monitor.start_operation("install_slurm"):
                # 설치 작업
                pass
        """
        return OperationTracker(self, operation_name)
    
    def stop_and_save(self):
        """모니터링 중지 및 데이터 저장"""
        if not self.enable_monitoring:
            return
        
        self.logger.info("성능 모니터링 중지 중...")
        self._stop_event.set()
        
        if self._monitor_thread and self._monitor_thread.is_alive():
            self._monitor_thread.join(timeout=5)
        
        # 최종 샘플 수집
        if not self._stop_event.is_set():
            self._collect_sample()
        
        # 데이터 저장
        self._save_results()
    
    def _save_results(self):
        """성능 데이터를 JSON 파일로 저장"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # 통계 계산
        summary = self._calculate_summary()
        
        # 전체 데이터
        report = {
            'metadata': {
                'start_time': datetime.fromtimestamp(self.start_time).isoformat(),
                'end_time': datetime.now().isoformat(),
                'total_duration': time.time() - self.start_time,
                'sampling_interval': self.sampling_interval,
                'total_samples': len(self.samples),
                'pid': os.getpid()
            },
            'summary': summary,
            'function_stats': dict(self.function_stats),
            'samples': self.samples
        }
        
        # JSON 저장
        output_file = self.log_dir / f"performance_{timestamp}.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        
        self.logger.info(f"성능 리포트 저장: {output_file}")
        
        # 요약 정보 출력
        self._print_summary(summary)
    
    def _calculate_summary(self) -> Dict[str, Any]:
        """성능 데이터 요약 통계 계산"""
        if not self.samples:
            return {}
        
        cpu_values = [s['cpu_percent'] for s in self.samples]
        memory_values = [s['memory_rss_mb'] for s in self.samples]
        
        summary = {
            'cpu': {
                'avg_percent': sum(cpu_values) / len(cpu_values),
                'max_percent': max(cpu_values),
                'min_percent': min(cpu_values),
                'total_cpu_time': self.samples[-1]['cpu_time_total'] if self.samples else 0
            },
            'memory': {
                'avg_rss_mb': sum(memory_values) / len(memory_values),
                'max_rss_mb': max(memory_values),
                'min_rss_mb': min(memory_values),
                'peak_rss_mb': max(memory_values)
            },
            'execution': {
                'total_duration': time.time() - self.start_time,
                'total_samples': len(self.samples)
            }
        }
        
        # 자식 프로세스 통계
        children_samples = [s for s in self.samples if 'children_count' in s]
        if children_samples:
            child_cpu = [s['children_cpu_percent'] for s in children_samples]
            child_mem = [s['children_memory_mb'] for s in children_samples]
            summary['children'] = {
                'max_count': max(s['children_count'] for s in children_samples),
                'avg_cpu_percent': sum(child_cpu) / len(child_cpu),
                'max_cpu_percent': max(child_cpu),
                'avg_memory_mb': sum(child_mem) / len(child_mem),
                'max_memory_mb': max(child_mem)
            }
        
        return summary
    
    def _print_summary(self, summary: Dict[str, Any]):
        """요약 정보를 콘솔에 출력"""
        print("\n" + "=" * 60)
        print("성능 모니터링 요약")
        print("=" * 60)
        
        # 실행 시간
        duration = summary['execution']['total_duration']
        print(f"\n⏱️  실행 시간: {self._format_duration(duration)}")
        print(f"📊 샘플 수: {summary['execution']['total_samples']}개")
        
        # CPU 사용량
        cpu = summary['cpu']
        print(f"\n💻 CPU 사용량:")
        print(f"  - 평균: {cpu['avg_percent']:.1f}%")
        print(f"  - 최대: {cpu['max_percent']:.1f}%")
        print(f"  - 총 CPU 시간: {cpu['total_cpu_time']:.1f}초")
        
        # 메모리 사용량
        mem = summary['memory']
        print(f"\n🧠 메모리 사용량:")
        print(f"  - 평균: {mem['avg_rss_mb']:.1f} MB")
        print(f"  - 최대: {mem['max_rss_mb']:.1f} MB")
        
        # 자식 프로세스
        if 'children' in summary:
            child = summary['children']
            print(f"\n👨‍👩‍👧‍👦 자식 프로세스:")
            print(f"  - 최대 개수: {child['max_count']}개")
            print(f"  - 평균 CPU: {child['avg_cpu_percent']:.1f}%")
            print(f"  - 평균 메모리: {child['avg_memory_mb']:.1f} MB")
        
        # 함수별 통계
        if self.function_stats:
            print(f"\n📈 함수별 실행 통계:")
            for func_name, stats in sorted(
                self.function_stats.items(),
                key=lambda x: x[1]['total_time'],
                reverse=True
            )[:10]:  # 상위 10개만
                avg_time = stats['total_time'] / stats['count']
                print(f"  - {func_name}:")
                print(f"      호출 {stats['count']}회, "
                      f"총 {stats['total_time']:.2f}초, "
                      f"평균 {avg_time:.3f}초")
        
        print("=" * 60 + "\n")
    
    @staticmethod
    def _format_duration(seconds: float) -> str:
        """초를 읽기 쉬운 형식으로 변환"""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = seconds % 60
        
        if hours > 0:
            return f"{hours}시간 {minutes}분 {secs:.1f}초"
        elif minutes > 0:
            return f"{minutes}분 {secs:.1f}초"
        else:
            return f"{secs:.1f}초"
    
    def get_current_stats(self) -> Dict[str, Any]:
        """현재 시점의 성능 통계 반환"""
        if not self.samples:
            return {}
        
        return {
            'latest_sample': self.samples[-1],
            'summary': self._calculate_summary()
        }


class OperationTracker:
    """
    특정 작업의 성능을 추적하는 컨텍스트 매니저
    
    Usage:
        with monitor.start_operation("install_packages"):
            # 작업 수행
            pass
    """
    
    def __init__(self, monitor: PerformanceMonitor, operation_name: str):
        self.monitor = monitor
        self.operation_name = operation_name
        self.start_time = None
        self.start_cpu_time = None
        self.logger = logging.getLogger(__name__)
    
    def __enter__(self):
        self.start_time = time.time()
        self.start_cpu_time = time.process_time()
        self.logger.info(f"작업 시작: {self.operation_name}")
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        wall_time = time.time() - self.start_time
        cpu_time = time.process_time() - self.start_cpu_time
        
        # 함수 통계에 기록
        stats = self.monitor.function_stats[self.operation_name]
        stats['count'] += 1
        stats['total_time'] += wall_time
        stats['cpu_time'] += cpu_time
        stats['min_time'] = min(stats.get('min_time', float('inf')), wall_time)
        stats['max_time'] = max(stats.get('max_time', 0), wall_time)
        
        self.logger.info(
            f"작업 완료: {self.operation_name} "
            f"(실행시간: {wall_time:.2f}초, CPU시간: {cpu_time:.2f}초)"
        )


# 전역 모니터 인스턴스 (옵션)
_global_monitor: Optional[PerformanceMonitor] = None


def get_global_monitor() -> Optional[PerformanceMonitor]:
    """전역 모니터 인스턴스 반환"""
    return _global_monitor


def init_global_monitor(**kwargs) -> PerformanceMonitor:
    """전역 모니터 초기화"""
    global _global_monitor
    _global_monitor = PerformanceMonitor(**kwargs)
    return _global_monitor


def track_function(func_name: str = None):
    """전역 모니터를 사용하는 데코레이터"""
    monitor = get_global_monitor()
    if monitor:
        return monitor.track_function(func_name)
    
    # 모니터가 없으면 원본 함수 반환
    def decorator(func):
        return func
    return decorator
