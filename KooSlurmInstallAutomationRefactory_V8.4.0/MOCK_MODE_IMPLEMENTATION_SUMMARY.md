# 🎭 Mock Mode 구현 완료 요약

## 📋 작업 개요

`start.sh` 스크립트에 `--mock` 옵션을 추가하여 하나의 명령어로 Production Mode와 Mock Mode를 모두 실행할 수 있도록 개선했습니다.

---

## ✅ 완료된 작업

### 1. start.sh 개선 (프로젝트 루트)

**파일**: [start.sh](./start.sh)

**추가된 기능**:
- `--mock` 옵션 지원
- `--help` 도움말 출력
- 모드별 적절한 하위 스크립트 호출

**사용법**:
```bash
./start.sh          # Production Mode (기본)
./start.sh --mock   # Mock Mode
./start.sh --help   # 도움말
```

### 2. start_complete.sh 수정 (Production)

**파일**: [dashboard/start_complete.sh](./dashboard/start_complete.sh)

**변경 사항**:
- Backend 시작 시 `MOCK_MODE=false` 환경변수 명시적 설정
- 라인 146: `MOCK_MODE=false nohup python3 app.py ...`

**효과**:
- Production Mode가 항상 올바르게 동작
- `.env` 파일에 의존하지 않음

### 3. start_mock.sh 생성 (Mock Mode)

**파일**: [dashboard/start_mock.sh](./dashboard/start_mock.sh)

**주요 기능**:
- Backend 시작 시 `MOCK_MODE=true` 환경변수 설정
- 포트 5010, 5011 강제 해제 (`pkill -9`)
- Prometheus Skip
- `.env` 파일에 `MOCK_MODE=true` 자동 설정

### 4. start_mock.sh Wrapper 생성

**파일**: [start_mock.sh](./start_mock.sh) (프로젝트 루트)

**목적**:
- 레거시 호환성 유지
- `./start_mock.sh` 직접 실행 지원

---

## 📚 생성된 문서

### 1. START_SCRIPT_GUIDE.md
**파일**: [START_SCRIPT_GUIDE.md](./START_SCRIPT_GUIDE.md)

**내용**:
- `start.sh` 사용법
- Production vs Mock Mode 비교
- 실행 흐름도
- 테스트 시나리오
- 문제 해결 가이드

### 2. MOCK_MODE_SETUP.md
**파일**: [MOCK_MODE_SETUP.md](./MOCK_MODE_SETUP.md)

**내용**:
- Mock Mode 상세 가이드
- 설정 방법
- API 테스트 방법
- 사용 시나리오

### 3. README.md 업데이트
**파일**: [README.md](./README.md)

**변경 사항**:
- "빠른 시작 (웹 서비스)" 섹션에 Mock Mode 추가
- `./start.sh --mock` 사용법 추가

---

## 🎯 주요 개선 사항

### 1. 단일 진입점
**Before**:
```bash
./start.sh              # Production
./start_mock.sh         # Mock (별도 스크립트)
```

**After**:
```bash
./start.sh              # Production (기본)
./start.sh --mock       # Mock (옵션)
```

### 2. 명시적 환경변수 설정

**문제**: `.env` 파일만으로는 프로세스가 재시작되지 않으면 반영 안됨

**해결**:
```bash
# Production
MOCK_MODE=false nohup python3 app.py ...

# Mock
MOCK_MODE=true nohup python3 app.py ...
```

### 3. 강력한 프로세스 종료

**문제**: 기존 프로세스가 남아서 포트 충돌

**해결**:
```bash
# pkill -9로 강제 종료
pkill -9 -f "backend_5010.*app.py"

# 포트 강제 해제
for port in 3010 8002 5173 5010 5011; do
    lsof -ti:$port | xargs -r kill -9 2>/dev/null
done
```

---

## ✨ 테스트 결과

### Production Mode 테스트
```bash
$ ./start.sh
🚀 HPC 웹 서비스 시작 중 (Production Mode)...
✅ Dashboard Backend 시작됨 (PID: 1180635, Port: 5010)

$ curl http://localhost:5010/api/health | jq .mode
"production"

$ tail /tmp/dashboard_backend_5010.log | grep "Running in"
✅ Running in PRODUCTION MODE - Real Slurm commands will be executed
```

### Mock Mode 테스트
```bash
$ ./start.sh --mock
🎭 HPC 웹 서비스 시작 중 (Mock Mode)...
✅ Dashboard Backend 시작됨 (PID: 1189136, Port: 5010, MOCK_MODE=true)

$ curl http://localhost:5010/api/health | jq .mode
"mock"

$ tail /tmp/dashboard_backend_5010.log | grep "Running in"
⚠️ Running in MOCK MODE - No actual Slurm commands will be executed
```

### Mock 데이터 확인
```bash
$ curl -s http://localhost:5010/api/slurm/jobs | jq '.count'
20

$ curl -s http://localhost:5010/api/slurm/jobs | jq '.jobs[0] | {jobId, jobName, state}'
{
  "jobId": "10000",
  "jobName": "job_0_analysis",
  "state": "FAILED"
}
```

---

## 🔄 사용 흐름

### Production Mode (운영 환경)
```
./start.sh
    │
    ├─ dashboard/start_complete.sh 호출
    │
    ├─ MOCK_MODE=false 설정
    │
    ├─ Backend 시작 (실제 Slurm)
    │
    ├─ Prometheus 시작
    │
    └─ "production" mode 확인
```

### Mock Mode (개발/테스트)
```
./start.sh --mock
    │
    ├─ dashboard/start_mock.sh 호출
    │
    ├─ MOCK_MODE=true 설정
    │
    ├─ Backend 시작 (Mock 데이터)
    │
    ├─ Prometheus Skip
    │
    └─ "mock" mode 확인
```

---

## 📂 파일 구조

```
KooSlurmInstallAutomationRefactory/
├── start.sh ✨ (수정)
│   ├─ --mock 옵션 추가
│   ├─ --help 도움말 추가
│   └─ 하위 스크립트 호출
│
├── start_mock.sh (신규)
│   └─ dashboard/start_mock.sh wrapper
│
├── dashboard/
│   ├── start_complete.sh ✨ (수정)
│   │   └─ MOCK_MODE=false 명시적 설정
│   │
│   └── start_mock.sh (신규)
│       ├─ MOCK_MODE=true 설정
│       ├─ 포트 강제 해제
│       └─ Prometheus Skip
│
├── START_SCRIPT_GUIDE.md (신규)
├── MOCK_MODE_SETUP.md (신규)
├── MOCK_MODE_IMPLEMENTATION_SUMMARY.md (신규)
└── README.md ✨ (수정)
```

---

## 🎓 핵심 학습 내용

### 1. 환경변수 우선순위
- 프로세스 시작 시 환경변수 > `.env` 파일
- `.env` 파일만 수정해도 프로세스 재시작 필요

### 2. 프로세스 종료 전략
- `pkill` vs `pkill -9`: 강제 종료가 더 안전
- 포트 해제 확인 필수

### 3. 스크립트 설계
- 단일 진입점 (Single Entry Point)
- 명확한 옵션 (`--mock`, `--help`)
- Wrapper 패턴 활용

---

## 🚀 다음 단계 (선택 사항)

### 1. stop.sh 개선
```bash
./stop.sh          # 전체 종료
./stop.sh --mock   # Mock Mode만 종료 (Production 유지)?
```

### 2. 상태 확인 명령어
```bash
./status.sh        # 현재 모드 및 서비스 상태 확인
```

### 3. 모드 전환 명령어
```bash
./switch-mode.sh mock        # Mock으로 전환
./switch-mode.sh production  # Production으로 전환
```

---

## 📊 비교표

| 항목 | Before | After |
|------|--------|-------|
| **Production 시작** | `./start.sh` | `./start.sh` ✅ (동일) |
| **Mock 시작** | `./start_mock.sh` | `./start.sh --mock` ✅ |
| **도움말** | ❌ 없음 | `./start.sh --help` ✅ |
| **환경변수 설정** | `.env`만 | 명시적 설정 ✅ |
| **프로세스 종료** | `pkill` | `pkill -9` ✅ |
| **포트 해제** | ❌ 없음 | 자동 해제 ✅ |

---

## ✅ 체크리스트

- [x] `start.sh`에 `--mock` 옵션 추가
- [x] `start_complete.sh`에 `MOCK_MODE=false` 명시적 설정
- [x] `start_mock.sh` 생성 (강력한 종료 로직)
- [x] Production Mode 테스트 완료
- [x] Mock Mode 테스트 완료
- [x] 모드 전환 테스트 완료
- [x] Mock 데이터 확인 완료
- [x] 문서 작성 (START_SCRIPT_GUIDE.md)
- [x] 문서 작성 (MOCK_MODE_SETUP.md)
- [x] README.md 업데이트

---

## 🎉 결론

**`start.sh`가 `--mock` 옵션을 지원하여 하나의 명령어로 두 가지 모드를 모두 실행할 수 있습니다!**

### 장점
1. ✅ **간편한 사용**: 옵션 하나로 모드 전환
2. ✅ **안정적인 동작**: 환경변수 명시적 설정
3. ✅ **명확한 의도**: `--mock` 플래그로 목적 표현
4. ✅ **레거시 호환**: `start_mock.sh` 직접 실행도 가능

### 사용 예시
```bash
# Production (실제 클러스터)
./start.sh

# Mock (테스트)
./start.sh --mock

# 도움말
./start.sh --help
```

---

**작성일**: 2025-10-22
**작성자**: KooSlurmInstallAutomation
**버전**: 1.0
