# 성능 모니터링 기능 업데이트

## 📊 새로 추가된 기능

KooSlurmInstallAutomation v1.2.0에 **자동 성능 모니터링** 기능이 추가되었습니다!

### 주요 변경사항

1. **자동 성능 추적**
   - CPU 사용량 자동 기록
   - 메모리 사용량 추적
   - 프로세스별 실행 시간 측정
   - 자식 프로세스(SSH 연결) 모니터링

2. **새로운 파일**
   - `src/performance_monitor.py` - 성능 모니터링 핵심 모듈
   - `view_performance_report.py` - 리포트 뷰어 도구
   - `docs/PERFORMANCE_MONITORING.md` - 상세 가이드

3. **수정된 파일**
   - `src/main.py` - 성능 모니터링 통합
   - `requirements.txt` - psutil 의존성 추가
   - `make_executable.sh` - 리포트 뷰어 실행 권한 추가

---

## 🚀 빠른 시작

### 1. 의존성 설치

```bash
# 가상환경 활성화
source venv/bin/activate

# 새로운 의존성 설치
pip install -r requirements.txt

# 또는 직접 설치
pip install psutil>=5.9.0
```

### 2. 실행 권한 설정

```bash
# 새로운 스크립트에 실행 권한 부여
chmod +x view_performance_report.py

# 또는 전체 재설정
./make_executable.sh
```

### 3. Slurm 설치 (자동 모니터링)

```bash
# 일반 설치 - 자동으로 성능 모니터링됨
./install_slurm.py -c config.yaml --stage all

# 샘플링 간격 조정 (기본 60초)
./install_slurm.py -c config.yaml --monitoring-interval 30

# 모니터링 비활성화
./install_slurm.py -c config.yaml --disable-monitoring
```

### 4. 성능 리포트 확인

```bash
# 최신 리포트 자동 선택
./view_performance_report.py

# 리포트 목록 보기
./view_performance_report.py --list

# CSV로 내보내기
./view_performance_report.py --export analysis.csv
```

---

## 📈 성능 리포트 예시

설치 완료 후 자동으로 다음과 같은 요약이 출력됩니다:

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
  - install_slurm_on_all_nodes:
      호출 1회, 총 567.89초, 평균 567.890초
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

### JSON 파일 구조

```json
{
  "metadata": {
    "start_time": "2025-01-05T14:30:22",
    "end_time": "2025-01-05T15:15:45",
    "total_duration": 2723.53,
    "sampling_interval": 60,
    "total_samples": 45,
    "pid": 12345
  },
  "summary": {
    "cpu": {
      "avg_percent": 35.2,
      "max_percent": 78.9,
      "total_cpu_time": 1234.5
    },
    "memory": {
      "avg_rss_mb": 256.3,
      "max_rss_mb": 512.7
    }
  },
  "function_stats": {
    "install_stage1_basic": {
      "count": 1,
      "total_time": 1234.56,
      "cpu_time": 567.89
    }
  },
  "samples": [...]
}
```

---

## 🔧 CLI 옵션

### 성능 모니터링 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--enable-monitoring` | 성능 모니터링 활성화 | True |
| `--disable-monitoring` | 성능 모니터링 비활성화 | - |
| `--monitoring-interval N` | 샘플링 간격 (초) | 60 |

### 리포트 뷰어 옵션

| 옵션 | 설명 |
|------|------|
| `-f, --file FILE` | 특정 리포트 파일 지정 |
| `--list` | 사용 가능한 리포트 목록 |
| `--top-functions N` | 상위 N개 함수 표시 |
| `--export FILE` | CSV로 내보내기 |
| `--timeline-samples N` | 타임라인 샘플 수 |
| `--detailed-samples START END` | 상세 샘플 범위 |

---

## 💡 성능 최적화 팁

### 1. 병목 지점 찾기

```bash
# 상위 20개 함수 확인
./view_performance_report.py --top-functions 20
```

주의할 함수들:
- `install_stage1_basic` - 기본 설치 (가장 오래 걸림)
- `setup_os_environment` - OS 환경 설정
- `install_slurm_on_all_nodes` - 패키지 설치

### 2. 샘플링 간격 조정

| 간격 | 용도 | 오버헤드 |
|------|------|----------|
| 10초 | 상세 분석 | 높음 |
| 30초 | 일반 모니터링 | 중간 |
| 60초 | 기본 (권장) | 낮음 |
| 120초 | 경량 모니터링 | 매우 낮음 |

### 3. 병렬 처리 조정

```bash
# SSH 연결 수 조정으로 성능 개선
./install_slurm.py -c config.yaml --max-workers 20

# 모니터링 간격 줄여서 상세 분석
./install_slurm.py -c config.yaml --monitoring-interval 10 --log-level debug
```

---

## 📚 상세 문서

더 자세한 내용은 다음 문서를 참조하세요:

- **[PERFORMANCE_MONITORING.md](docs/PERFORMANCE_MONITORING.md)** - 전체 가이드
  - 프로그래밍 방식 사용법
  - 커스텀 분석 스크립트
  - 문제 해결
  - FAQ

- **[README.md](README.md)** - 프로젝트 전체 개요

---

## 🐛 문제 해결

### psutil 설치 오류

```bash
# psutil 재설치
pip uninstall psutil
pip install psutil>=5.9.0
```

### 로그 파일이 생성되지 않음

```bash
# 로그 디렉토리 생성 및 권한 확인
mkdir -p performance_logs
chmod 755 performance_logs

# 모니터링 활성화 확인
./install_slurm.py -c config.yaml --enable-monitoring
```

### 리포트 뷰어 실행 오류

```bash
# 실행 권한 부여
chmod +x view_performance_report.py

# Python으로 직접 실행
python3 view_performance_report.py
```

---

## ⚙️ 기술 세부사항

### 구현 방식

- **백그라운드 스레드**: 메인 프로세스에 영향 없이 샘플링
- **psutil 라이브러리**: 크로스 플랫폼 프로세스 모니터링
- **JSON 저장**: 구조화된 데이터로 분석 용이
- **최소 오버헤드**: CPU 사용률 < 1%

### 측정 메트릭

- **CPU**: 퍼센트, 총 CPU 시간 (user + system)
- **메모리**: RSS, VMS (단위: MB)
- **프로세스**: 스레드 수, 자식 프로세스
- **시간**: wall time, CPU time

---

## 📊 사용 사례

### 케이스 1: 성능 비교

```bash
# 서로 다른 설정으로 설치
./install_slurm.py -c config1.yaml --max-workers 10
./install_slurm.py -c config2.yaml --max-workers 20

# 리포트 비교
./view_performance_report.py -f performance_logs/performance_*.json
```

### 케이스 2: 시스템 리소스 계획

과거 설치 로그를 분석하여 필요한 시스템 리소스 추정:

```python
import json
from pathlib import Path

# 모든 리포트 분석
for report_file in Path('performance_logs').glob('*.json'):
    with open(report_file) as f:
        data = json.load(f)
    
    summary = data['summary']
    print(f"\n{report_file.name}:")
    print(f"  실행 시간: {summary['execution']['total_duration']/60:.1f}분")
    print(f"  최대 메모리: {summary['memory']['max_rss_mb']:.1f} MB")
    print(f"  평균 CPU: {summary['cpu']['avg_percent']:.1f}%")
```

---

## 🎯 다음 단계

1. ✅ 기본 성능 모니터링 구현 완료
2. 🚧 웹 기반 대시보드 개발 중
3. 📋 실시간 모니터링 기능 계획
4. 📋 알림 시스템 추가 예정

---

**버전**: 1.2.0  
**업데이트 날짜**: 2025-01-05  
**문의**: support@kooautomation.com

Happy Monitoring! 📊🚀
