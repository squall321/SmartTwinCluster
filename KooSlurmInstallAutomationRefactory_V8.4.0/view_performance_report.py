#!/usr/bin/env python3
"""
성능 모니터링 리포트 뷰어
저장된 성능 로그를 분석하고 시각화하는 도구
"""

import json
import sys
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any
import os


class PerformanceReportViewer:
    """성능 리포트를 분석하고 표시하는 클래스"""
    
    def __init__(self, report_file: str):
        self.report_file = Path(report_file)
        self.data = None
        
        if not self.report_file.exists():
            raise FileNotFoundError(f"리포트 파일을 찾을 수 없습니다: {report_file}")
        
        self.load_report()
    
    def load_report(self):
        """리포트 파일 로드"""
        with open(self.report_file, 'r', encoding='utf-8') as f:
            self.data = json.load(f)
    
    def print_header(self, title: str):
        """헤더 출력"""
        print("\n" + "=" * 80)
        print(f"  {title}")
        print("=" * 80)
    
    def print_metadata(self):
        """메타데이터 출력"""
        self.print_header("📊 성능 모니터링 리포트")
        
        metadata = self.data.get('metadata', {})
        
        print(f"\n⏱️  실행 정보:")
        print(f"  시작 시간: {metadata.get('start_time', 'N/A')}")
        print(f"  종료 시간: {metadata.get('end_time', 'N/A')}")
        print(f"  총 실행 시간: {self._format_duration(metadata.get('total_duration', 0))}")
        print(f"  프로세스 ID: {metadata.get('pid', 'N/A')}")
        print(f"  샘플링 간격: {metadata.get('sampling_interval', 0)}초")
        print(f"  총 샘플 수: {metadata.get('total_samples', 0)}개")
    
    def print_summary(self):
        """요약 통계 출력"""
        self.print_header("📈 성능 요약")
        
        summary = self.data.get('summary', {})
        
        # CPU 사용량
        cpu = summary.get('cpu', {})
        print(f"\n💻 CPU 사용량:")
        print(f"  평균: {cpu.get('avg_percent', 0):.2f}%")
        print(f"  최대: {cpu.get('max_percent', 0):.2f}%")
        print(f"  최소: {cpu.get('min_percent', 0):.2f}%")
        print(f"  총 CPU 시간: {cpu.get('total_cpu_time', 0):.2f}초")
        
        # 메모리 사용량
        memory = summary.get('memory', {})
        print(f"\n🧠 메모리 사용량:")
        print(f"  평균 RSS: {memory.get('avg_rss_mb', 0):.2f} MB")
        print(f"  최대 RSS: {memory.get('max_rss_mb', 0):.2f} MB")
        print(f"  최소 RSS: {memory.get('min_rss_mb', 0):.2f} MB")
        print(f"  피크 RSS: {memory.get('peak_rss_mb', 0):.2f} MB")
        
        # 자식 프로세스
        if 'children' in summary:
            children = summary['children']
            print(f"\n👨‍👩‍👧‍👦 자식 프로세스:")
            print(f"  최대 개수: {children.get('max_count', 0)}개")
            print(f"  평균 CPU: {children.get('avg_cpu_percent', 0):.2f}%")
            print(f"  최대 CPU: {children.get('max_cpu_percent', 0):.2f}%")
            print(f"  평균 메모리: {children.get('avg_memory_mb', 0):.2f} MB")
            print(f"  최대 메모리: {children.get('max_memory_mb', 0):.2f} MB")
    
    def print_function_stats(self, top_n: int = 10):
        """함수별 통계 출력"""
        self.print_header("🔧 함수별 실행 통계")
        
        function_stats = self.data.get('function_stats', {})
        
        if not function_stats:
            print("\n함수별 통계 데이터가 없습니다.")
            return
        
        # 총 실행 시간 기준으로 정렬
        sorted_functions = sorted(
            function_stats.items(),
            key=lambda x: x[1].get('total_time', 0),
            reverse=True
        )
        
        print(f"\n상위 {min(top_n, len(sorted_functions))}개 함수 (실행 시간 기준):\n")
        print(f"{'함수명':<40} {'호출':<8} {'총 시간':<12} {'평균':<12} {'최소':<12} {'최대':<12}")
        print("-" * 100)
        
        for func_name, stats in sorted_functions[:top_n]:
            count = stats.get('count', 0)
            total_time = stats.get('total_time', 0)
            avg_time = total_time / count if count > 0 else 0
            min_time = stats.get('min_time', 0)
            max_time = stats.get('max_time', 0)
            
            # min_time이 inf인 경우 처리
            if min_time == float('inf'):
                min_time = 0
            
            print(f"{func_name:<40} {count:<8} "
                  f"{total_time:<12.3f} {avg_time:<12.3f} "
                  f"{min_time:<12.3f} {max_time:<12.3f}")
        
        # CPU 시간이 많은 함수
        sorted_by_cpu = sorted(
            function_stats.items(),
            key=lambda x: x[1].get('cpu_time', 0),
            reverse=True
        )
        
        if sorted_by_cpu:
            print(f"\n\n상위 {min(top_n, len(sorted_by_cpu))}개 함수 (CPU 시간 기준):\n")
            print(f"{'함수명':<40} {'호출':<8} {'CPU 시간':<12} {'평균 CPU':<12}")
            print("-" * 80)
            
            for func_name, stats in sorted_by_cpu[:top_n]:
                count = stats.get('count', 0)
                cpu_time = stats.get('cpu_time', 0)
                avg_cpu = cpu_time / count if count > 0 else 0
                
                print(f"{func_name:<40} {count:<8} "
                      f"{cpu_time:<12.3f} {avg_cpu:<12.3f}")
    
    def print_timeline(self, interval: int = 10):
        """타임라인 그래프 출력"""
        self.print_header("📊 성능 타임라인")
        
        samples = self.data.get('samples', [])
        
        if not samples:
            print("\n샘플 데이터가 없습니다.")
            return
        
        # 지정된 간격으로 샘플 선택
        selected_samples = samples[::max(1, len(samples) // interval)]
        
        print(f"\n시간대별 CPU 및 메모리 사용량 (샘플 {len(selected_samples)}개):\n")
        print(f"{'시간':<20} {'CPU %':<10} {'메모리 MB':<12} {'스레드':<8}")
        print("-" * 50)
        
        for sample in selected_samples:
            timestamp = sample.get('timestamp', '')
            # ISO 포맷에서 시간만 추출
            try:
                dt = datetime.fromisoformat(timestamp)
                time_str = dt.strftime('%H:%M:%S')
            except:
                time_str = timestamp[:19] if len(timestamp) >= 19 else timestamp
            
            cpu = sample.get('cpu_percent', 0)
            memory = sample.get('memory_rss_mb', 0)
            threads = sample.get('num_threads', 0)
            
            # 간단한 막대 그래프
            cpu_bar = '█' * int(cpu / 5)
            
            print(f"{time_str:<20} {cpu:<10.1f} {memory:<12.1f} {threads:<8} {cpu_bar}")
    
    def print_detailed_samples(self, start: int = 0, end: int = 10):
        """상세 샘플 데이터 출력"""
        self.print_header("🔬 상세 샘플 데이터")
        
        samples = self.data.get('samples', [])
        
        if not samples:
            print("\n샘플 데이터가 없습니다.")
            return
        
        end = min(end, len(samples))
        
        print(f"\n샘플 {start} ~ {end} (총 {len(samples)}개):\n")
        
        for i, sample in enumerate(samples[start:end], start=start):
            print(f"\n샘플 #{i}:")
            print(f"  시간: {sample.get('timestamp', 'N/A')}")
            print(f"  경과 시간: {sample.get('elapsed_time', 0):.2f}초")
            print(f"  CPU: {sample.get('cpu_percent', 0):.2f}%")
            print(f"  CPU 시간: {sample.get('cpu_time_total', 0):.2f}초")
            print(f"  메모리 RSS: {sample.get('memory_rss_mb', 0):.2f} MB")
            print(f"  메모리 VMS: {sample.get('memory_vms_mb', 0):.2f} MB")
            print(f"  스레드 수: {sample.get('num_threads', 0)}")
            
            if 'children_count' in sample:
                print(f"  자식 프로세스: {sample.get('children_count', 0)}개")
                print(f"  자식 CPU: {sample.get('children_cpu_percent', 0):.2f}%")
                print(f"  자식 메모리: {sample.get('children_memory_mb', 0):.2f} MB")
    
    def export_csv(self, output_file: str):
        """CSV 파일로 내보내기"""
        samples = self.data.get('samples', [])
        
        if not samples:
            print("샘플 데이터가 없습니다.")
            return
        
        import csv
        
        with open(output_file, 'w', newline='', encoding='utf-8') as f:
            # 헤더 작성
            fieldnames = list(samples[0].keys())
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            
            writer.writeheader()
            writer.writerows(samples)
        
        print(f"\n✅ CSV 파일 생성 완료: {output_file}")
    
    def generate_full_report(self, top_functions: int = 20):
        """전체 리포트 출력"""
        self.print_metadata()
        self.print_summary()
        self.print_function_stats(top_n=top_functions)
        self.print_timeline(interval=20)
        
        print("\n" + "=" * 80)
        print("  리포트 끝")
        print("=" * 80 + "\n")
    
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


def find_latest_report(log_dir: str = "./performance_logs") -> str:
    """가장 최근 리포트 파일 찾기"""
    log_path = Path(log_dir)
    
    if not log_path.exists():
        raise FileNotFoundError(f"로그 디렉토리를 찾을 수 없습니다: {log_dir}")
    
    json_files = list(log_path.glob("performance_*.json"))
    
    if not json_files:
        raise FileNotFoundError(f"리포트 파일을 찾을 수 없습니다: {log_dir}")
    
    # 가장 최근 파일 반환
    latest = max(json_files, key=lambda p: p.stat().st_mtime)
    return str(latest)


def list_reports(log_dir: str = "./performance_logs"):
    """사용 가능한 리포트 목록 출력"""
    log_path = Path(log_dir)
    
    if not log_path.exists():
        print(f"로그 디렉토리를 찾을 수 없습니다: {log_dir}")
        return
    
    json_files = sorted(
        log_path.glob("performance_*.json"),
        key=lambda p: p.stat().st_mtime,
        reverse=True
    )
    
    if not json_files:
        print(f"리포트 파일이 없습니다: {log_dir}")
        return
    
    print("\n사용 가능한 성능 리포트:")
    print("=" * 80)
    
    for i, file in enumerate(json_files, 1):
        mtime = datetime.fromtimestamp(file.stat().st_mtime)
        size = file.stat().st_size / 1024  # KB
        
        print(f"{i}. {file.name}")
        print(f"   생성 시간: {mtime.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"   파일 크기: {size:.1f} KB")
        print()


def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(
        description='성능 모니터링 리포트 뷰어',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 최신 리포트 보기
  python view_performance_report.py

  # 특정 리포트 보기
  python view_performance_report.py -f performance_logs/performance_20250105_123456.json

  # 리포트 목록 보기
  python view_performance_report.py --list

  # 상위 30개 함수 표시
  python view_performance_report.py --top-functions 30

  # CSV로 내보내기
  python view_performance_report.py --export performance_data.csv
        """
    )
    
    parser.add_argument(
        '-f', '--file',
        help='리포트 파일 경로'
    )
    
    parser.add_argument(
        '-d', '--log-dir',
        default='./performance_logs',
        help='로그 디렉토리 경로 (기본값: ./performance_logs)'
    )
    
    parser.add_argument(
        '--list',
        action='store_true',
        help='사용 가능한 리포트 목록 표시'
    )
    
    parser.add_argument(
        '--top-functions',
        type=int,
        default=10,
        help='표시할 상위 함수 개수 (기본값: 10)'
    )
    
    parser.add_argument(
        '--export',
        help='CSV 파일로 내보내기'
    )
    
    parser.add_argument(
        '--timeline-samples',
        type=int,
        default=20,
        help='타임라인에 표시할 샘플 수 (기본값: 20)'
    )
    
    parser.add_argument(
        '--detailed-samples',
        type=int,
        nargs=2,
        metavar=('START', 'END'),
        help='상세 샘플 데이터 표시 범위'
    )
    
    args = parser.parse_args()
    
    try:
        # 리포트 목록 표시
        if args.list:
            list_reports(args.log_dir)
            return 0
        
        # 리포트 파일 결정
        if args.file:
            report_file = args.file
        else:
            report_file = find_latest_report(args.log_dir)
            print(f"최신 리포트 사용: {report_file}\n")
        
        # 뷰어 생성
        viewer = PerformanceReportViewer(report_file)
        
        # CSV 내보내기
        if args.export:
            viewer.export_csv(args.export)
        
        # 상세 샘플 데이터
        if args.detailed_samples:
            start, end = args.detailed_samples
            viewer.print_detailed_samples(start, end)
        else:
            # 전체 리포트 출력
            viewer.generate_full_report(top_functions=args.top_functions)
        
        return 0
        
    except FileNotFoundError as e:
        print(f"❌ {e}")
        return 1
    except Exception as e:
        print(f"❌ 오류 발생: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
