# 성능 모니터링 가이드

## 📊 개요

KooSlurmInstallAutomation에 통합된 성능 모니터링 시스템은 Slurm 설치 과정의 성능을 자동으로 추적하고 기록합니다.

### 주요 기능

- ✅ **자동 모니터링**: 설치 프로세스 자동 추적
- ✅ **최소 오버헤드**: 백그라운드 스레드로 주기적 샘플링 (기본 60초)
- ✅ **상세 메트릭**: CPU, 메모리, 스레드, 자식 프로세스
- ✅ **함수별 추적**: 각 함수/작업의 실행 시간 측정
- ✅ **JSON 리포트**: 구조화된 성능 데이터 저장
- ✅ **시각화 도구**: 리포트 뷰어 제공

---

## 🚀 사용법

### 1. 기본 사용 (자동 모니터링)

성능 모니터링은 **기본적으로 활성화**되어 있습니다.

```bash
# 일반적인 설치 실행
./install_slurm.py -c config.yaml --stage all

# 자동으로 성능 데이터 수집됨
# 설치 완료 후 performance_logs/ 디렉토리에 JSON 파일 생성
```

### 2. 모니터링 설정 조정

```bash
# 샘플링 간격 변경 (기본 60초)
./install_slurm.py -c config.yaml --monitoring-interval 30

# 모니터링 비활성화
./install_slurm.py -c config.yaml --disable-monitoring

# 상세 로그와 함께
./install_slurm.py -c config.yaml --log-level debug --monitoring-interval 30
```

### 3. 성능 리포트 확인

설치가 완료되면 자동으로 요약 정보가 출력됩니다:

```
============================================================
성능 모니터링 요약
============================================================

⏱️  실행 시간: 45분 23.5초
📊 샘플 수: 45개

💻 CPU 사용량:
  - 평균: 35.2%
  - 최대: 78.9%
  - 총 CPU 시간: 1234.5초

🧠 메모리 사용량:
  - 평균: 256.3 MB
  - 최대: 512.7 MB

👨‍👩‍👧‍👦 자식 프로세스:
  - 최대 개수: 12개
  - 평균 CPU: 145.6%
  - 평균 메모리: 384.2 MB

📈 함수별 실행 통계:
  - install_stage1_basic:
      호출 1회, 총 1234.56초, 평균 1234.560초
  - setup_ssh_connections:
      호출 1회, 총 45.23초, 평균 45.230초
============================================================
```

---

## 📁 성능 로그 파일

### 저장 위치

```
KooSlurmInstallAutomation/
└── performance_logs/
    ├── performance_20250105_143022.json
    ├── performance_20250105_150145.json
    └── performance_20250105_162530.json
```

### 파일 명명 규칙

- `performance_YYYYMMDD_HHMMSS.json`
- 타임스탬프는 프로그램 시작 시간

---

## 🔍 리포트 뷰어 사용

### 최신 리포트 보기

```bash
# 가장 최근 리포트 자동 선택
./view_performance_report.py

# 또는 Python으로 직접 실행
python view_performance_report.py
```

### 특정 리포트 보기

```bash
# 리포트 목록 확인
./view_performance_report.py --list

# 출력 예시:
# 사용 가능한 성능 리포트:
# ============================================================
# 1. performance_20250105_162530.json
#    생성 시간: 2025-01-05 16:25:30
#    파일 크기: 45.3 KB
# 
# 2. performance_20250105_150145.json
#    생성 시간: 2025-01-05 15:01:45
#    파일 크기: 38.7 KB

# 특정 파일 선택
./view_performance_report.py -f performance_logs/performance_20250105_162530.json
```

### 상위 함수 개수 조정

```bash
# 상위 30개 함수 표시
./view_performance_report.py --top-functions 30

# 상위 50개 함수 표시
./view_performance_report.py --top-functions 50
```

### CSV로 내보내기

```bash
# 성능 데이터를 CSV 파일로 변환
./view_performance_report.py --export performance_data.csv

# 특정 리포트를 CSV로
./view_performance_report.py -f performance_logs/performance_20250105_162530.json \
    --export analysis_data.csv
```

### 상세 샘플 데이터 보기

```bash
# 샘플 0~10번 상세 보기
./view_performance_report.py --detailed-samples 0 10

# 샘플 20~30번 상세 보기
./view_performance_report.py --detailed-samples 20 30
```

---

## 📊 리포트 구조

### JSON 파일 구조

```json
{
  "metadata": {
    "start_time": "2025-01-05T14:30:22.123456",
    "end_time": "2025-01-05T15:15:45.654321",
    "total_duration": 2723.53,
    "sampling_interval": 60,
    "total_samples": 45,
    "pid": 12345
  },
  "summary": {
    "cpu": {
      "avg_percent": 35.2,
      "max_percent": 78.9,
      "min_percent": 5.1,
      "total_cpu_time": 1234.5
    },
    "memory": {
      "avg_rss_mb": 256.3,
      "max_rss_mb": 512.7,
      "min_rss_mb": 128.4,
      "peak_rss_mb": 512.7
    },
    "children": {
      "max_count": 12,
      "avg_cpu_percent": 145.6,
      "max_cpu_percent": 234.5,
      "avg_memory_mb": 384.2,
      "max_memory_mb": 678.9
    },
    "execution": {
      "total_duration": 2723.53,
      "total_samples": 45
    }
  },
  "function_stats": {
    "install_stage1_basic": {
      "count": 1,
      "total_time": 1234.56,
      "min_time": 1234.56,
      "max_time": 1234.56,
      "cpu_time": 567.89
    },
    "setup_ssh_connections": {
      "count": 1,
      "total_time": 45.23,
      "min_time": 45.23,
      "max_time": 45.23,
      "cpu_time": 12.34
    }
  },
  "samples": [
    {
      "timestamp": "2025-01-05T14:30:22.123456",
      "elapsed_time": 0.0,
      "cpu_percent": 15.2,
      "cpu_time_total": 2.5,
      "memory_rss_mb": 128.4,
      "memory_vms_mb": 256.8,
      "num_threads": 4,
      "pid": 12345,
      "children_count": 2,
      "children_cpu_percent": 25.3,
      "children_memory_mb": 64.2
    }
  ]
}
```

---

## 💡 성능 분석 팁

### 1. 병목 지점 찾기

함수별 통계에서 실행 시간이 긴 작업을 확인:

```bash
./view_performance_report.py --top-functions 20
```

**주의할 함수:**
- `install_stage1_basic` - 기본 설치 단계
- `setup_os_environment` - OS 환경 설정
- `install_slurm_on_all_nodes` - Slurm 패키지 설치

### 2. 메모리 사용량 모니터링

리포트에서 메모리 피크 시점 확인:

```python
# 커스텀 분석 스크립트 예시
import json

with open('performance_logs/performance_20250105_162530.json') as f:
    data = json.load(f)

# 메모리 사용량이 가장 높은 샘플 찾기
samples = data['samples']
max_memory_sample = max(samples, key=lambda x: x['memory_rss_mb'])

print(f"최대 메모리 사용 시점: {max_memory_sample['timestamp']}")
print(f"메모리 사용량: {max_memory_sample['memory_rss_mb']:.2f} MB")
print(f"CPU 사용량: {max_memory_sample['cpu_percent']:.2f}%")
```

### 3. 자식 프로세스 분석

SSH 연결 및 원격 명령 실행 시 자식 프로세스 생성:

- `children_count`: SSH 동시 연결 수
- `children_cpu_percent`: 원격 명령 CPU 사용량
- `children_memory_mb`: 원격 명령 메모리 사용량

**최적화 방법:**
- `--max-workers` 값 조정
- 병렬 처리 수 조절

### 4. 설치 시간 예측

과거 설치 로그를 분석하여 소요 시간 예측:

```bash
# 여러 리포트 비교
for file in performance_logs/performance_*.json; do
    echo "=== $file ==="
    python -c "
import json
with open('$file') as f:
    data = json.load(f)
    duration = data['metadata']['total_duration']
    print(f'설치 시간: {duration/60:.1f}분')
"
done
```

---

## 🔧 고급 사용법

### 1. 프로그래밍 방식으로 모니터링 추가

직접 작성한 스크립트에 성능 모니터링 추가:

```python
from src.performance_monitor import PerformanceMonitor

# 모니터 생성
monitor = PerformanceMonitor(
    log_dir="./my_performance_logs",
    sampling_interval=30,  # 30초마다 샘플링
    enable_monitoring=True
)

# 데코레이터로 함수 추적
@monitor.track_function()
def my_installation_task():
    # 작업 수행
    pass

# 컨텍스트 매니저로 작업 추적
with monitor.start_operation("custom_operation"):
    # 작업 수행
    pass

# 프로그램 종료 시 자동 저장
# 또는 수동 저장
monitor.stop_and_save()
```

### 2. 실시간 모니터링

다른 터미널에서 실시간으로 성능 확인:

```bash
# 터미널 1: 설치 실행
./install_slurm.py -c config.yaml --stage all

# 터미널 2: 실시간 모니터링
watch -n 5 'ps aux | grep install_slurm'

# 또는 top으로 확인
top -p $(pgrep -f install_slurm)
```

### 3. 리포트 자동 분석 스크립트

```python
#!/usr/bin/env python3
"""성능 리포트 자동 분석"""

import json
import sys
from pathlib import Path

def analyze_performance(report_file):
    with open(report_file) as f:
        data = json.load(f)
    
    summary = data['summary']
    
    # 성능 기준
    warnings = []
    
    # CPU 사용량 체크
    avg_cpu = summary['cpu']['avg_percent']
    if avg_cpu < 20:
        warnings.append(f"⚠️ 낮은 CPU 사용률 ({avg_cpu:.1f}%) - 병렬화 개선 가능")
    elif avg_cpu > 80:
        warnings.append(f"⚠️ 높은 CPU 사용률 ({avg_cpu:.1f}%) - 시스템 과부하 주의")
    
    # 메모리 사용량 체크
    max_memory = summary['memory']['max_rss_mb']
    if max_memory > 1024:  # 1GB
        warnings.append(f"⚠️ 높은 메모리 사용 ({max_memory:.1f} MB)")
    
    # 실행 시간 체크
    duration = summary['execution']['total_duration']
    if duration > 3600:  # 1시간
        warnings.append(f"⚠️ 긴 실행 시간 ({duration/60:.1f}분)")
    
    # 결과 출력
    if warnings:
        print("\n성능 분석 결과:")
        for warning in warnings:
            print(warning)
    else:
        print("\n✅ 성능 이상 없음")
    
    return len(warnings) == 0

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python analyze_report.py <report_file>")
        sys.exit(1)
    
    success = analyze_performance(sys.argv[1])
    sys.exit(0 if success else 1)
```

---

## 📈 성능 최적화 가이드

### 샘플링 간격 조정

| 간격 | 용도 | 오버헤드 | 데이터 양 |
|------|------|----------|-----------|
| 10초 | 상세 분석 | 높음 | 많음 |
| 30초 | 일반 모니터링 | 중간 | 중간 |
| 60초 | 기본 (권장) | 낮음 | 적음 |
| 120초 | 경량 모니터링 | 매우 낮음 | 매우 적음 |

### 권장 설정

```bash
# 개발/테스트 환경
./install_slurm.py -c config.yaml --monitoring-interval 30

# 프로덕션 환경
./install_slurm.py -c config.yaml --monitoring-interval 60

# 성능 테스트
./install_slurm.py -c config.yaml --monitoring-interval 10 --log-level debug
```

---

## 🐛 문제 해결

### 1. 성능 로그가 생성되지 않음

```bash
# 모니터링이 비활성화되었는지 확인
./install_slurm.py -c config.yaml --enable-monitoring

# 로그 디렉토리 권한 확인
ls -la performance_logs/
chmod 755 performance_logs/
```

### 2. psutil 설치 오류

```bash
# psutil 재설치
pip uninstall psutil
pip install psutil>=5.9.0

# 가상환경 확인
which python
pip list | grep psutil
```

### 3. 리포트 뷰어 실행 오류

```bash
# Python 경로 확인
which python3

# 실행 권한 부여
chmod +x view_performance_report.py

# 직접 Python으로 실행
python3 view_performance_report.py
```

### 4. 메모리 부족

샘플링 간격을 늘려서 메모리 사용량 감소:

```bash
./install_slurm.py -c config.yaml --monitoring-interval 120
```

---

## 📚 추가 리소스

### 관련 파일

- `src/performance_monitor.py` - 모니터링 핵심 모듈
- `src/main.py` - 메인 실행 스크립트 (모니터링 통합)
- `view_performance_report.py` - 리포트 뷰어
- `performance_logs/` - 성능 로그 디렉토리

### 참고 문서

- [psutil 공식 문서](https://psutil.readthedocs.io/)
- [Python threading](https://docs.python.org/3/library/threading.html)
- [Python atexit](https://docs.python.org/3/library/atexit.html)

---

## 💡 자주 묻는 질문 (FAQ)

### Q1: 성능 모니터링이 설치 속도에 영향을 주나요?

A: 매우 미미합니다. 백그라운드 스레드로 주기적(기본 60초)으로만 샘플링하므로 오버헤드는 1% 미만입니다.

### Q2: 여러 설치를 동시에 실행하면?

A: 각 프로세스마다 독립적인 로그 파일이 생성됩니다. 타임스탬프가 다르므로 충돌하지 않습니다.

### Q3: 로그 파일 크기가 너무 큽니다

A: 샘플링 간격을 늘리거나(`--monitoring-interval 120`), 오래된 로그를 삭제하세요:

```bash
# 30일 이상 된 로그 삭제
find performance_logs/ -name "performance_*.json" -mtime +30 -delete
```

### Q4: 특정 함수만 추적하고 싶습니다

A: 코드에서 `@monitor.track_function()` 데코레이터를 해당 함수에만 적용하세요.

### Q5: CSV 데이터를 Excel에서 분석하고 싶습니다

A:
```bash
# CSV로 내보내기
./view_performance_report.py --export performance.csv

# Excel에서 열기
# 또는 LibreOffice Calc 등 사용
```

---

## 🎯 베스트 프랙티스

1. **프로덕션 환경**
   - 기본 설정(60초 간격) 사용
   - 로그는 정기적으로 백업 및 정리

2. **성능 튜닝**
   - 10-30초 간격으로 상세 분석
   - 함수별 통계로 병목 지점 파악

3. **로그 관리**
   - 성공적인 설치 로그는 보관
   - 실패한 설치 로그는 분석 후 삭제
   - 월별로 디렉토리 정리

4. **보안**
   - 로그 파일에 민감한 정보 없음
   - 필요시 로그 디렉토리 권한 제한: `chmod 700 performance_logs/`

---

**Happy Monitoring! 📊🚀**

버전: 1.1.0
최종 업데이트: 2025-01-05
