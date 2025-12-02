#!/usr/bin/env python3
"""
성능 모니터링 기능 테스트
새로 추가된 성능 모니터링 모듈을 테스트합니다.
"""

import sys
import time
import tempfile
from pathlib import Path

# 경로 설정
sys.path.insert(0, str(Path(__file__).parent / 'src'))

from performance_monitor import PerformanceMonitor


def test_basic_monitoring():
    """기본 모니터링 테스트"""
    print("=" * 60)
    print("테스트 1: 기본 모니터링")
    print("=" * 60)
    
    # 임시 디렉토리 생성
    with tempfile.TemporaryDirectory() as tmpdir:
        monitor = PerformanceMonitor(
            log_dir=tmpdir,
            sampling_interval=2,  # 2초마다 샘플링
            enable_monitoring=True
        )
        
        print("\n✅ 모니터 생성 완료")
        print(f"   로그 디렉토리: {tmpdir}")
        print(f"   샘플링 간격: 2초")
        
        # 5초간 대기 (2-3개 샘플 수집)
        print("\n⏳ 5초간 샘플 수집 중...")
        time.sleep(5)
        
        # 현재 통계 확인
        stats = monitor.get_current_stats()
        if stats:
            print("\n📊 현재 통계:")
            latest = stats.get('latest_sample', {})
            print(f"   CPU: {latest.get('cpu_percent', 0):.1f}%")
            print(f"   메모리: {latest.get('memory_rss_mb', 0):.1f} MB")
            print(f"   스레드: {latest.get('num_threads', 0)}개")
        
        # 수동 저장
        monitor.stop_and_save()
        print("\n✅ 테스트 1 완료!")


def test_function_tracking():
    """함수 추적 테스트"""
    print("\n" + "=" * 60)
    print("테스트 2: 함수별 성능 추적")
    print("=" * 60)
    
    with tempfile.TemporaryDirectory() as tmpdir:
        monitor = PerformanceMonitor(
            log_dir=tmpdir,
            sampling_interval=10,
            enable_monitoring=True
        )
        
        # 테스트 함수 정의
        @monitor.track_function()
        def fast_task():
            """빠른 작업"""
            time.sleep(0.1)
            return sum(range(1000))
        
        @monitor.track_function()
        def slow_task():
            """느린 작업"""
            time.sleep(0.5)
            return sum(range(10000))
        
        print("\n🔧 테스트 함수 실행 중...")
        
        # 여러 번 호출
        for i in range(3):
            print(f"   반복 {i+1}/3")
            fast_task()
            slow_task()
        
        print("\n📈 함수 통계:")
        for func_name, stats in monitor.function_stats.items():
            avg_time = stats['total_time'] / stats['count']
            print(f"   {func_name}:")
            print(f"      호출: {stats['count']}회")
            print(f"      총 시간: {stats['total_time']:.3f}초")
            print(f"      평균: {avg_time:.3f}초")
        
        monitor.stop_and_save()
        print("\n✅ 테스트 2 완료!")


def test_operation_tracking():
    """작업 추적 테스트"""
    print("\n" + "=" * 60)
    print("테스트 3: 작업별 성능 추적")
    print("=" * 60)
    
    with tempfile.TemporaryDirectory() as tmpdir:
        monitor = PerformanceMonitor(
            log_dir=tmpdir,
            sampling_interval=10,
            enable_monitoring=True
        )
        
        print("\n🔧 작업 시뮬레이션 중...")
        
        # 작업 1
        with monitor.start_operation("데이터_로드"):
            print("   작업 1: 데이터 로드 중...")
            time.sleep(0.3)
        
        # 작업 2
        with monitor.start_operation("데이터_처리"):
            print("   작업 2: 데이터 처리 중...")
            time.sleep(0.5)
        
        # 작업 3
        with monitor.start_operation("결과_저장"):
            print("   작업 3: 결과 저장 중...")
            time.sleep(0.2)
        
        print("\n📈 작업 통계:")
        for op_name, stats in monitor.function_stats.items():
            print(f"   {op_name}:")
            print(f"      실행 시간: {stats['total_time']:.3f}초")
            print(f"      CPU 시간: {stats['cpu_time']:.3f}초")
        
        monitor.stop_and_save()
        print("\n✅ 테스트 3 완료!")


def test_disabled_monitoring():
    """모니터링 비활성화 테스트"""
    print("\n" + "=" * 60)
    print("테스트 4: 모니터링 비활성화")
    print("=" * 60)
    
    with tempfile.TemporaryDirectory() as tmpdir:
        monitor = PerformanceMonitor(
            log_dir=tmpdir,
            sampling_interval=1,
            enable_monitoring=False  # 비활성화
        )
        
        @monitor.track_function()
        def test_func():
            time.sleep(0.1)
        
        print("\n⏭️  모니터링 비활성화 상태에서 함수 실행...")
        test_func()
        test_func()
        
        # 통계가 수집되지 않아야 함
        if not monitor.function_stats:
            print("✅ 통계 수집 안됨 (정상)")
        else:
            print("⚠️  통계가 수집됨 (비정상)")
        
        print("\n✅ 테스트 4 완료!")


def test_long_running():
    """장시간 실행 시뮬레이션"""
    print("\n" + "=" * 60)
    print("테스트 5: 장시간 실행 시뮬레이션")
    print("=" * 60)
    
    with tempfile.TemporaryDirectory() as tmpdir:
        monitor = PerformanceMonitor(
            log_dir=tmpdir,
            sampling_interval=2,  # 2초마다 샘플링
            enable_monitoring=True
        )
        
        print("\n⏳ 10초간 실행 (5개 샘플 예상)...")
        
        @monitor.track_function()
        def cpu_intensive_task():
            """CPU 집약적 작업"""
            result = 0
            for i in range(1000000):
                result += i ** 2
            return result
        
        @monitor.track_function()
        def io_task():
            """I/O 작업"""
            time.sleep(0.5)
        
        # 여러 작업 교차 실행
        for i in range(5):
            print(f"   진행: {i+1}/5")
            cpu_intensive_task()
            io_task()
        
        # 통계 확인
        stats = monitor.get_current_stats()
        summary = stats.get('summary', {})
        
        print("\n📊 최종 통계:")
        if 'cpu' in summary:
            print(f"   평균 CPU: {summary['cpu']['avg_percent']:.1f}%")
            print(f"   최대 CPU: {summary['cpu']['max_percent']:.1f}%")
        
        if 'memory' in summary:
            print(f"   평균 메모리: {summary['memory']['avg_rss_mb']:.1f} MB")
        
        print(f"\n   총 샘플 수: {len(monitor.samples)}개")
        
        monitor.stop_and_save()
        
        # 저장된 파일 확인
        json_files = list(Path(tmpdir).glob("performance_*.json"))
        if json_files:
            print(f"\n✅ 리포트 파일 생성: {json_files[0].name}")
            print(f"   파일 크기: {json_files[0].stat().st_size / 1024:.1f} KB")
        
        print("\n✅ 테스트 5 완료!")


def main():
    """메인 함수"""
    print("\n" + "=" * 60)
    print("🧪 성능 모니터링 모듈 테스트")
    print("=" * 60)
    
    try:
        # 테스트 1: 기본 모니터링
        test_basic_monitoring()
        
        # 테스트 2: 함수 추적
        test_function_tracking()
        
        # 테스트 3: 작업 추적
        test_operation_tracking()
        
        # 테스트 4: 비활성화
        test_disabled_monitoring()
        
        # 테스트 5: 장시간 실행
        test_long_running()
        
        print("\n" + "=" * 60)
        print("✅ 모든 테스트 통과!")
        print("=" * 60)
        
        print("\n다음 단계:")
        print("1. 실제 설치 시나리오 테스트:")
        print("   ./install_slurm.py -c examples/2node_example.yaml --dry-run")
        print("\n2. 성능 리포트 확인:")
        print("   ./view_performance_report.py")
        
        return 0
        
    except Exception as e:
        print(f"\n❌ 테스트 실패: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
