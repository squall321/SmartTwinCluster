# 🚀 start.sh 통합 가이드

## 개요

`start.sh` 스크립트가 `--mock` 옵션을 지원하여 하나의 명령어로 Production Mode와 Mock Mode를 모두 실행할 수 있습니다.

---

## 📝 사용법

### 기본 사용법

```bash
# Production Mode (기본)
./start.sh

# Mock Mode
./start.sh --mock

# 도움말
./start.sh --help
```

---

## 🎯 모드 비교

| 항목 | Production Mode | Mock Mode |
|------|----------------|-----------|
| **명령어** | `./start.sh` | `./start.sh --mock` |
| **Slurm** | ✅ 실제 실행 | ❌ Mock 데이터 |
| **데이터** | 실시간 클러스터 | 고정 테스트 데이터 |
| **Prometheus** | ✅ 시작 | ❌ Skip |
| **MOCK_MODE** | false | true |
| **클러스터 영향** | ⚠️ 있음 | ✅ 없음 |
| **용도** | 운영 환경 | 개발/테스트 |

---

## 📊 실행 흐름도

```
./start.sh [--mock]
    │
    ├─── 옵션 파싱
    │      │
    │      ├─── --mock 있음?
    │      │      │
    │      │      ├─── YES → dashboard/start_mock.sh 호출
    │      │      │           │
    │      │      │           ├─ MOCK_MODE=true 환경변수 설정
    │      │      │           ├─ Backend 시작 (Mock 데이터)
    │      │      │           └─ Prometheus Skip
    │      │      │
    │      │      └─── NO  → dashboard/start_complete.sh 호출
    │      │                   │
    │      │                   ├─ MOCK_MODE=false 환경변수 설정
    │      │                   ├─ Backend 시작 (실제 Slurm)
    │      │                   └─ Prometheus 시작
    │      │
    │      └─── --help 있음?
    │             │
    │             └─── YES → 도움말 출력 후 종료
    │
    └─── 서비스 시작 완료
```

---

## 🔧 구현 세부사항

### 1. start.sh (프로젝트 루트)

**경로**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/start.sh`

**주요 기능**:
- `--mock` 옵션 파싱
- `--help` 도움말 출력
- 적절한 하위 스크립트 호출

**코드 구조**:
```bash
# 인자 파싱
MOCK_MODE=false

for arg in "$@"; do
    case $arg in
        --mock)
            MOCK_MODE=true
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac
done

# Mock Mode 선택
if [ "$MOCK_MODE" = true ]; then
    ./dashboard/start_mock.sh
else
    ./dashboard/start_complete.sh
fi
```

### 2. dashboard/start_complete.sh (Production)

**환경변수 설정**:
```bash
# Dashboard Backend (MOCK_MODE=false for Production)
cd backend_5010
MOCK_MODE=false nohup python3 app.py > /tmp/dashboard_backend_5010.log 2>&1 &
```

**특징**:
- `MOCK_MODE=false` 명시적 설정
- Prometheus 시작
- 실제 Slurm 명령어 실행

### 3. dashboard/start_mock.sh (Mock Mode)

**환경변수 설정**:
```bash
# Dashboard Backend (MOCK_MODE=true)
cd backend_5010
MOCK_MODE=true nohup python3 app.py > /tmp/dashboard_backend_5010.log 2>&1 &
```

**특징**:
- `MOCK_MODE=true` 명시적 설정
- Prometheus Skip
- Mock 데이터 반환

---

## ✅ 테스트 시나리오

### 시나리오 1: Production Mode 시작

```bash
# 1. Production Mode로 시작
./start.sh

# 2. 모드 확인
curl http://localhost:5010/api/health | jq .mode
# 출력: "production"

# 3. 로그 확인
tail /tmp/dashboard_backend_5010.log | grep "Running in"
# 출력: ✅ Running in PRODUCTION MODE - Real Slurm commands will be executed
```

### 시나리오 2: Mock Mode로 전환

```bash
# 1. 기존 서비스 종료
./dashboard/stop_complete.sh

# 2. Mock Mode로 시작
./start.sh --mock

# 3. 모드 확인
curl http://localhost:5010/api/health | jq .mode
# 출력: "mock"

# 4. 로그 확인
tail /tmp/dashboard_backend_5010.log | grep "Running in"
# 출력: ⚠️ Running in MOCK MODE - No actual Slurm commands will be executed
```

### 시나리오 3: Production Mode로 복귀

```bash
# 1. Mock Mode 종료
./dashboard/stop_complete.sh

# 2. Production Mode로 시작 (기본)
./start.sh

# 3. 모드 확인
curl http://localhost:5010/api/health | jq .mode
# 출력: "production"
```

---

## 🎭 Mock Mode 데이터 확인

### Jobs API (Mock Data)
```bash
curl http://localhost:5010/api/slurm/jobs | jq '.count'
# 출력: 20

curl http://localhost:5010/api/slurm/jobs | jq '.jobs[0]'
# 출력:
# {
#   "jobId": "10000",
#   "jobName": "job_0_analysis",
#   "state": "FAILED",
#   "userId": "user02",
#   ...
# }
```

### Health API
```bash
curl http://localhost:5010/api/health | jq
# 출력:
# {
#   "mode": "mock",
#   "status": "healthy",
#   "timestamp": "2025-10-22T..."
# }
```

---

## 🔍 문제 해결

### 1. 모드가 변경되지 않음

**원인**: 기존 프로세스가 계속 실행 중

**해결**:
```bash
# 강제 종료
pkill -9 -f "backend_5010.*app.py"

# 다시 시작
./start.sh --mock  # 또는 ./start.sh
```

### 2. 환경변수가 적용되지 않음

**원인**: `.env` 파일만 수정하고 프로세스를 재시작하지 않음

**해결**:
```bash
# start.sh는 환경변수를 명시적으로 설정하므로
# 항상 올바른 모드로 시작됩니다
./dashboard/stop_complete.sh
./start.sh --mock  # 또는 ./start.sh
```

### 3. Prometheus가 Mock Mode에서 실행됨

**정상 동작**: Mock Mode에서는 Prometheus를 시작하지 않습니다.

**확인**:
```bash
ps aux | grep prometheus
# Mock Mode에서는 출력 없음
```

---

## 📂 관련 파일

### 핵심 스크립트
- **[start.sh](./start.sh)** - 통합 시작 스크립트 (옵션 처리)
- **[dashboard/start_complete.sh](./dashboard/start_complete.sh)** - Production Mode
- **[dashboard/start_mock.sh](./dashboard/start_mock.sh)** - Mock Mode
- **[dashboard/stop_complete.sh](./dashboard/stop_complete.sh)** - 전체 종료

### 문서
- **[MOCK_MODE_SETUP.md](./MOCK_MODE_SETUP.md)** - Mock Mode 상세 가이드
- **[SETUP_WORKFLOW_GUIDE.md](./SETUP_WORKFLOW_GUIDE.md)** - 전체 워크플로우 가이드

---

## 🌟 장점

### 1. 단일 진입점
- `start.sh` 하나로 모든 모드 실행
- 사용자가 여러 스크립트를 기억할 필요 없음

### 2. 명확한 옵션
- `--mock` 플래그로 명확한 의도 표현
- `--help`로 사용법 즉시 확인

### 3. 안전한 전환
- 환경변수를 명시적으로 설정
- `.env` 파일 의존성 최소화
- 모드 혼동 방지

### 4. 일관된 동작
- 항상 올바른 하위 스크립트 호출
- 모드별 최적화된 설정 적용

---

## 📋 체크리스트

### Production Mode 시작 전
- [ ] 클러스터가 정상 동작 중
- [ ] Slurm 서비스 실행 중
- [ ] Redis 실행 중
- [ ] 실제 Job 제출/관리가 필요함

### Mock Mode 시작 전
- [ ] 프론트엔드 개발/테스트 목적
- [ ] 클러스터에 영향 없이 테스트 필요
- [ ] 고정된 데이터로 충분함
- [ ] Prometheus 불필요

---

## 🔄 Quick Reference

```bash
# Production Mode (실제 클러스터)
./start.sh
curl http://localhost:5010/api/health | jq .mode  # "production"

# Mock Mode (테스트 데이터)
./start.sh --mock
curl http://localhost:5010/api/health | jq .mode  # "mock"

# 전체 종료
./dashboard/stop_complete.sh

# 도움말
./start.sh --help
```

---

**작성일**: 2025-10-22
**버전**: 1.0
**작성자**: KooSlurmInstallAutomation
