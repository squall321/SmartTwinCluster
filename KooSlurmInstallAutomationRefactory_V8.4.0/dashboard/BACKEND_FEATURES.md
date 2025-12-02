# Backend Server (Port 5010) - 기능 상세 문서

## 📋 개요
Flask 기반의 RESTful API 서버로, Slurm 클러스터 관리와 모니터링을 위한 모든 백엔드 로직을 담당합니다.

**포트**: 5010  
**프레임워크**: Flask + Flask-CORS  
**데이터베이스**: SQLite3  
**모드**: Mock Mode / Production Mode 지원

---

## 🏗️ 핵심 아키텍처

### 1. 모드 분리 시스템
```python
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'
```

- **Mock Mode**: 개발 및 테스트 환경, 실제 Slurm 명령 없이 시뮬레이션 데이터 제공
- **Production Mode**: 실제 Slurm 명령 실행 및 클러스터 관리

### 2. 모듈화된 API Blueprint 구조
```
app.py (Main)
├── alerts_api.py          # 디스크 알림 관리
├── dashboard_api.py       # 커스텀 대시보드 설정
├── directory_api.py       # 디렉토리 탐색
├── notifications_api.py   # 알림 센터
├── preview_api.py         # 파일 미리보기
├── prometheus_api.py      # Prometheus 메트릭 조회
├── reports_api.py         # 리포트 생성 및 다운로드
├── search_api.py          # 전역 검색
├── templates_api.py       # Job 템플릿 관리
└── upload_api.py          # 파일 업로드/다운로드
```

---

## 🔧 주요 기능 모듈

### 1. Slurm 통합 (`slurm_commands.py`, `slurm_utils.py`)

#### 기능
- Slurm 명령어 래퍼 함수 제공
- 노드, 파티션, 작업, 계정 정보 조회
- QoS(Quality of Service) 관리
- 작업 제출 및 취소

#### 주요 함수
```python
get_sinfo()         # 노드 정보 조회
get_squeue()        # 작업 큐 조회
get_sacct()         # 작업 계정 정보 조회
get_scontrol()      # 상세 제어 정보
get_sreport()       # 리포트 생성
check_slurm_installation()  # Slurm 설치 확인
```

#### Mock Mode 동작
- 노드 4개 (node[001-004]) 시뮬레이션
- 랜덤 작업 데이터 생성
- CPU, 메모리, GPU 사용률 시뮬레이션

---

### 2. Alerts API (`alerts_api.py`)

#### 엔드포인트
| Method | Endpoint | 설명 |
|--------|----------|------|
| POST | `/api/alerts/disk/check` | 디스크 사용량 체크 및 알림 생성 |
| GET | `/api/alerts/disk` | 모든 디스크 알림 조회 |
| POST | `/api/alerts/disk/clear` | 알림 초기화 |
| PUT | `/api/alerts/disk/thresholds` | 임계값 업데이트 |

#### 기능
- **Data Storage 알림**: `/data` 디렉토리 사용량 모니터링
- **Scratch Storage 알림**: 각 노드의 `/scratch` 디렉토리 모니터링
- **임계값 설정**: Warning(75%), Critical(90%) 기본값
- **알림 레벨**: INFO, WARNING, CRITICAL

#### 사용 예시
```bash
# 디스크 사용량 체크
curl -X POST http://localhost:5010/api/alerts/disk/check \
  -H "Content-Type: application/json" \
  -d '{
    "storage_type": "scratch",
    "nodes_data": [
      {"node": "node001", "usage_percent": 85.5}
    ]
  }'

# 임계값 업데이트
curl -X PUT http://localhost:5010/api/alerts/disk/thresholds \
  -H "Content-Type: application/json" \
  -d '{"warning": 80, "critical": 95}'
```

---

### 3. Notifications API (`notifications_api.py`)

#### 엔드포인트
| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/api/notifications` | 알림 목록 조회 |
| POST | `/api/notifications` | 새 알림 생성 |
| POST | `/api/notifications/mark-read` | 모든 알림 읽음 처리 |
| POST | `/api/notifications/:id/read` | 특정 알림 읽음 처리 |
| DELETE | `/api/notifications/:id` | 알림 삭제 |
| GET | `/api/notifications/unread-count` | 읽지 않은 알림 수 |

#### 기능
- **알림 타입**: job_completed, job_failed, alert, system, info
- **WebSocket 브로드캐스트**: 새 알림 생성 시 실시간 푸시
- **필터링**: 읽지 않은 알림만 조회 가능
- **데이터베이스 저장**: SQLite를 통한 영구 저장

#### Mock Mode 데이터
```json
[
  {
    "id": "notif-001",
    "type": "job_completed",
    "title": "Job Completed",
    "message": "Job #12345 has finished successfully",
    "timestamp": "2025-10-07T14:30:00Z",
    "read": false,
    "data": {"jobId": "12345", "duration": "2h 30m"}
  }
]
```

#### WebSocket 연동
```python
def broadcast_notification_to_websocket(notification: dict):
    """WebSocket 서버(5011)로 알림 전송"""
    requests.post('http://localhost:5011/broadcast', json={
        'channel': 'notifications',
        'message': {'type': 'notification', 'data': notification}
    })
```

---

### 4. Prometheus API (`prometheus_api.py`)

#### 엔드포인트
| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/api/prometheus/query` | Instant query 실행 |
| GET | `/api/prometheus/query_range` | Range query 실행 |
| GET | `/api/prometheus/labels` | 레이블 이름 목록 |
| GET | `/api/prometheus/label/:name/values` | 특정 레이블 값 목록 |
| GET | `/api/prometheus/series` | 시계열 데이터 조회 |
| GET | `/api/prometheus/targets` | 타겟 목록 조회 |
| GET | `/api/prometheus/rules` | 규칙 조회 |
| GET | `/api/prometheus/alerts` | 활성 알림 조회 |
| GET | `/api/prometheus/status/config` | 설정 조회 |
| GET | `/api/prometheus/health` | 연결 상태 확인 |

#### 기능
- **Prometheus 연동**: `http://localhost:9090` 기본 연결
- **PromQL 지원**: Instant/Range 쿼리 실행
- **GPU 메트릭**: NVIDIA GPU 사용률, 메모리, 온도 모니터링
- **Mock 데이터**: 개발 환경용 시뮬레이션 데이터

#### Mock Mode 데이터 생성
```python
def get_mock_gpu_data(query: str):
    """4개 GPU의 사용률, 메모리, 온도 시뮬레이션"""
    for i in range(4):
        # GPU 사용률: 0.2 ~ 0.95 (ratio)
        # GPU 메모리: 30 ~ 95 (%)
        # GPU 온도: 45°C ~ 80°C
```

#### Range Query 특징
- **다중 시계열 지원**: `topk()`, `by (instance)` 쿼리 지원
- **GPU 별 데이터**: 각 GPU별 독립적인 메트릭
- **비교 쿼리**: `or` 연산자를 통한 여러 메트릭 비교
- **코어별 데이터**: `by (instance, cpu)`로 CPU 코어별 데이터

#### 사용 예시
```bash
# Instant Query
curl "http://localhost:5010/api/prometheus/query?query=node_cpu_seconds_total"

# Range Query (최근 1시간)
curl "http://localhost:5010/api/prometheus/query_range?query=node_cpu_seconds_total&start=2025-10-10T13:00:00Z&end=2025-10-10T14:00:00Z&step=15s"

# GPU 사용률 조회
curl "http://localhost:5010/api/prometheus/query?query=nvidia_smi_utilization_gpu_ratio"
```

---

### 5. Reports API (`reports_api.py`)

#### 엔드포인트
| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/api/reports` | 리포트 목록 조회 |
| POST | `/api/reports/generate` | 새 리포트 생성 |
| GET | `/api/reports/:id` | 리포트 상세 조회 |
| GET | `/api/reports/:id/download` | 리포트 다운로드 |
| DELETE | `/api/reports/:id` | 리포트 삭제 |

#### 기능
- **리포트 타입**: Job Usage, System Performance, User Activity, Custom
- **포맷**: PDF, Excel, CSV
- **자동 생성**: 스케줄링 가능
- **데이터 소스**: Slurm 작업 기록, Prometheus 메트릭
- **한글 지원**: PDF 한글 폰트 (NanumGothic)

#### 리포트 생성 프로세스
1. 데이터 수집 (Slurm/Prometheus)
2. 데이터 처리 및 분석
3. 문서 생성 (ReportLab/Pandas)
4. 파일 저장 및 메타데이터 DB 저장
5. 다운로드 URL 반환

#### Mock Mode 데이터
```json
{
  "id": "report-001",
  "title": "Weekly Job Usage Report",
  "type": "job_usage",
  "format": "pdf",
  "status": "completed",
  "created_at": "2025-10-07T10:00:00Z",
  "file_size": "2.4 MB"
}
```

---

### 6. Templates API (`templates_api.py`)

#### 엔드포인트
| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/api/templates` | 템플릿 목록 조회 |
| POST | `/api/templates` | 새 템플릿 생성 |
| GET | `/api/templates/:id` | 템플릿 상세 조회 |
| PUT | `/api/templates/:id` | 템플릿 수정 |
| DELETE | `/api/templates/:id` | 템플릿 삭제 |
| POST | `/api/templates/:id/use` | 템플릿 사용 (작업 제출) |

#### 기능
- **템플릿 관리**: Slurm 작업 스크립트 템플릿 저장
- **파라미터화**: 동적 변수 지원 (`{job_name}`, `{nodes}` 등)
- **카테고리**: Deep Learning, Bioinformatics, Data Processing 등
- **버전 관리**: 템플릿 수정 이력 저장

#### 템플릿 구조
```json
{
  "id": "tmpl-001",
  "name": "PyTorch Training",
  "category": "deep_learning",
  "script": "#!/bin/bash\n#SBATCH --job-name={job_name}\n#SBATCH --nodes={nodes}\n#SBATCH --gpus={gpus}\n\npython train.py",
  "parameters": [
    {"name": "job_name", "type": "string", "required": true},
    {"name": "nodes", "type": "number", "default": 1},
    {"name": "gpus", "type": "number", "default": 1}
  ]
}
```

---

### 7. Dashboard API (`dashboard_api.py`)

#### 엔드포인트
| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/api/dashboard/config` | 대시보드 설정 조회 |
| POST | `/api/dashboard/config` | 대시보드 설정 저장 |
| GET | `/api/dashboard/layouts` | 저장된 레이아웃 목록 |
| DELETE | `/api/dashboard/layouts/:id` | 레이아웃 삭제 |

#### 기능
- **위젯 배치**: React Grid Layout 설정 저장
- **즐겨찾기**: 자주 사용하는 위젯 저장
- **프리셋**: 사전 정의된 대시보드 레이아웃
- **사용자별 설정**: 개별 사용자 커스터마이징

---

### 8. Storage Management

#### 파일 시스템 API
- **디렉토리 탐색**: `directory_api.py`
- **파일 검색**: `search_api.py`
- **파일 미리보기**: `preview_api.py`
- **업로드/다운로드**: `upload_api.py`

#### Storage Utils (`storage_utils.py`, `storage_utils_async.py`)
```python
# 동기 함수
get_disk_usage(path)           # 디스크 사용량
list_directory(path)           # 디렉토리 목록
search_files(path, pattern)    # 파일 검색
get_directory_size(path)       # 디렉토리 크기

# 비동기 함수
get_all_nodes_scratch_info_sync()        # 모든 노드 Scratch 정보
get_scratch_storage_stats_sync()         # Scratch 통계
get_data_storage_stats_cached()          # Data 스토리지 통계 (캐시)
```

#### Data Storage vs Scratch Storage
| 구분 | Data Storage | Scratch Storage |
|------|--------------|-----------------|
| 경로 | `/data` | `/scratch` (각 노드) |
| 용도 | 영구 데이터 저장 | 임시 작업 파일 |
| 백업 | Yes | No |
| 공유 | 모든 노드 | 노드별 로컬 |
| 알림 | 중앙 관리 | 노드별 관리 |

---

### 9. 데이터베이스 스키마 (`database.py`)

#### Notifications 테이블
```sql
CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    data TEXT,  -- JSON
    read INTEGER DEFAULT 0,
    timestamp TEXT NOT NULL,
    created_at TEXT NOT NULL
)
```

#### Templates 테이블
```sql
CREATE TABLE IF NOT EXISTS job_templates (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT,
    description TEXT,
    script TEXT NOT NULL,
    parameters TEXT,  -- JSON
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    use_count INTEGER DEFAULT 0
)
```

#### Dashboard 테이블
```sql
CREATE TABLE IF NOT EXISTS dashboard_configs (
    id TEXT PRIMARY KEY,
    user_id TEXT,
    name TEXT NOT NULL,
    layout TEXT NOT NULL,  -- JSON
    widgets TEXT NOT NULL,  -- JSON
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
)
```

---

## 🔄 시작/중지 스크립트

### `start.sh`
```bash
#!/bin/bash
cd "$(dirname "$0")"

# Mock Mode 설정
export MOCK_MODE=true
export PYTHONPATH="${PYTHONPATH}:$(pwd)"

# Virtual Environment 활성화
source venv/bin/activate

# Flask 서버 시작
python app.py > logs/backend.log 2>&1 &
echo $! > .backend.pid
```

### `stop.sh`
```bash
#!/bin/bash
if [ -f .backend.pid ]; then
    kill $(cat .backend.pid)
    rm .backend.pid
fi
```

---

## 📊 성능 최적화

### 1. 캐싱
```python
from functools import lru_cache
from datetime import datetime, timedelta

# Storage 통계 캐싱 (5분)
@lru_cache(maxsize=1)
def get_data_storage_stats_cached():
    cache_time = datetime.now()
    stats = get_data_storage_stats()
    return stats, cache_time
```

### 2. 비동기 처리
```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

async def get_all_nodes_scratch_info_async(nodes):
    """병렬로 모든 노드의 Scratch 정보 조회"""
    with ThreadPoolExecutor(max_workers=10) as executor:
        loop = asyncio.get_event_loop()
        tasks = [
            loop.run_in_executor(executor, get_node_scratch_info, node)
            for node in nodes
        ]
        return await asyncio.gather(*tasks)
```

### 3. 요청 제한
```python
from flask_limiter import Limiter

limiter = Limiter(app, key_func=lambda: request.remote_addr)

@app.route('/api/expensive-operation')
@limiter.limit("10 per minute")
def expensive_operation():
    # ...
```

---

## 🧪 테스트

### Mock Mode 테스트
```bash
# Mock Mode로 서버 시작
MOCK_MODE=true python app.py

# API 테스트
curl http://localhost:5010/api/nodes
curl http://localhost:5010/api/jobs
curl http://localhost:5010/api/prometheus/query?query=up
```

### Production Mode 테스트
```bash
# Production Mode로 서버 시작
MOCK_MODE=false python app.py

# Slurm 연결 테스트
curl http://localhost:5010/api/slurm/check
```

---

## 🚀 추가 기능 로드맵

### Phase 1: 현재 구현 완료
- ✅ Slurm 통합
- ✅ Prometheus 연동
- ✅ 알림 시스템
- ✅ 리포트 생성
- ✅ Job 템플릿
- ✅ 커스텀 대시보드

### Phase 2: 개선 예정
- 🔄 **실시간 알림 고도화**: WebSocket을 통한 job 상태 변화 실시간 푸시
- 🔄 **리포트 스케줄링**: Cron 기반 자동 리포트 생성
- 🔄 **API 인증**: JWT 기반 사용자 인증
- 🔄 **Rate Limiting**: API 요청 제한 강화

### Phase 3: 신규 기능
- 📋 **Job 예측 분석**: ML 기반 작업 완료 시간 예측
- 📋 **리소스 최적화**: 자동 리소스 할당 추천
- 📋 **장애 감지**: Anomaly Detection
- 📋 **Multi-Cluster 지원**: 여러 클러스터 통합 관리

---

## 🔧 문제 해결

### 1. Slurm 명령 실행 실패
```bash
# Slurm 경로 확인
which sinfo
which squeue

# slurm_commands.py 경로 수정
SINFO = "/usr/local/bin/sinfo"
```

### 2. Database 잠금 오류
```python
# database.py에서 타임아웃 증가
conn = sqlite3.connect('dashboard.db', timeout=30.0)
```

### 3. WebSocket 브로드캐스트 실패
```bash
# WebSocket 서버 상태 확인
curl http://localhost:5011/health
```

---

## 📚 참고 자료
- [Flask 공식 문서](https://flask.palletsprojects.com/)
- [Slurm 명령어 레퍼런스](https://slurm.schedmd.com/documentation.html)
- [Prometheus API](https://prometheus.io/docs/prometheus/latest/querying/api/)
- [SQLite3 Python API](https://docs.python.org/3/library/sqlite3.html)
