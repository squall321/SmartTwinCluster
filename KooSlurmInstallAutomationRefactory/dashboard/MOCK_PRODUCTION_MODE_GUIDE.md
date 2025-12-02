# Mock/Production Mode 자동 전환 가이드

## 📋 개요

`start_all.sh`와 `start_all_mock.sh`에 따라 모든 서버(Backend, WebSocket)가 자동으로 Mock 또는 Production 모드로 실행됩니다.

---

## 🎯 모드별 차이점

### Production Mode (`start_all.sh`)
```bash
MOCK_MODE=false
```

**특징**:
- 🚀 **실제 Slurm 명령 실행**
- ✅ `sinfo`, `scontrol`, `sbatch` 등 실제 명령 사용
- ✅ Node Management에서 실제 노드 Drain/Resume 가능
- ⚠️ **주의**: 실제 클러스터에 영향을 줍니다!

**사용 시나리오**:
- 실제 운영 환경
- Slurm이 설치된 서버
- 실제 노드 관리가 필요한 경우

---

### Mock Mode (`start_all_mock.sh`)
```bash
MOCK_MODE=true
```

**특징**:
- 🎭 **테스트 데이터 사용**
- ✅ Slurm 명령 실행 안함 (안전)
- ✅ Node Management: 샘플 노드 4개 (cn01~cn04)
- ✅ 개발/테스트 환경에 적합

**샘플 노드**:
- cn01: IDLE
- cn02: ALLOCATED
- cn03: DRAINED
- cn04: IDLE

**사용 시나리오**:
- 개발 환경
- Slurm이 없는 로컬 PC
- 안전한 테스트가 필요한 경우
- UI/UX 테스트

---

## 🚀 사용 방법

### Production Mode로 시작
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

./start_all.sh
```

**실행 메시지**:
```
==========================================
🚀 모든 서버 시작 (Production Mode)
==========================================

🎯 모드: Production (실제 Slurm 명령 실행)
   - Backend: MOCK_MODE=false
   - WebSocket: MOCK_MODE=false
   - 실제 노드 조회, Drain/Resume 기능 사용 가능

...

✅ Backend 시작 (PID: 123456)
🔗 http://localhost:5010
💡 MOCK_MODE=false

✅ WebSocket 시작 (PID: 123457)
🔗 ws://localhost:5011/ws
💡 독립 venv 사용
🎯 MOCK_MODE=false

...

🎯 모드: 🚀 Production (MOCK_MODE=false)
   - 실제 Slurm 명령 실행
   - Node Management: 실제 노드 Drain/Resume 가능
   - sinfo, scontrol 명령 사용
```

---

### Mock Mode로 시작
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

./start_all_mock.sh
```

**실행 메시지**:
```
==========================================
🚀 모든 서버 시작 (Mock Mode)
==========================================

🎯 모드: Mock (테스트 데이터 사용)
   - Backend: MOCK_MODE=true
   - WebSocket: MOCK_MODE=true
   - 샘플 노드 4개 (cn01~cn04) 표시
   - 실제 Slurm 명령 미실행

...

✅ Backend 시작 (PID: 123456)
🔗 http://localhost:5010
💡 MOCK_MODE=true

✅ WebSocket 시작 (PID: 123457)
🔗 ws://localhost:5011/ws
💡 독립 venv 사용
🎯 MOCK_MODE=true

...

🎯 모드: 🎭 Mock (MOCK_MODE=true)
   - 테스트 데이터 사용
   - Node Management: 샘플 노드 4개 (cn01~cn04)
   - Slurm 명령 실행 안함 (안전하게 테스트)
```

---

## 🔄 모드 전환 방법

### 방법 1: start_all 스크립트로 전환 (권장)

```bash
# 현재 서버 종료
./stop_all.sh

# Production Mode로 시작
./start_all.sh

# 또는 Mock Mode로 시작
./start_all_mock.sh
```

### 방법 2: Backend만 전환

```bash
cd backend_5010

# Production Mode
./stop.sh
MOCK_MODE=false ./start.sh

# Mock Mode
./stop.sh
MOCK_MODE=true ./start.sh
```

### 방법 3: 대화형 모드 전환 (Backend만)

```bash
cd backend_5010
./switch_mode.sh

# 선택 화면에서:
# 1) Mock Mode
# 2) Production Mode
```

---

## 🌐 브라우저에서 확인

### Mode Badge 확인
1. http://localhost:3010 접속
2. **Node Management** 탭 클릭
3. 우측 상단의 Mode Badge 확인:
   - 🎭 **MOCK MODE** (노란색)
   - 🚀 **PRODUCTION** (초록색)

### 노드 목록 확인

**Mock Mode**:
- cn01 (IDLE)
- cn02 (ALLOCATED)
- cn03 (DRAINED)
- cn04 (IDLE)

**Production Mode**:
- 실제 Slurm 클러스터의 노드 목록

---

## 🔍 모드 확인 방법

### 1. API로 확인
```bash
# 노드 목록 API
curl http://localhost:5010/api/nodes | jq '.mode'

# 응답:
# "mock" 또는 "production"
```

### 2. 로그로 확인
```bash
# Backend 로그
tail -20 backend_5010/logs/backend.log | grep "Running in"

# 응답 예시:
# "⚠️  Running in MOCK MODE - No actual Slurm commands will be executed"
# 또는
# "✅ Running in PRODUCTION MODE - Real Slurm commands will be executed"
```

### 3. 프로세스 환경변수로 확인
```bash
# Backend 프로세스 찾기
ps aux | grep "python.*app.py" | grep -v grep

# 환경변수 확인
cat /proc/<PID>/environ | tr '\0' '\n' | grep MOCK_MODE
```

---

## 📊 영향을 받는 API

### Backend API
모든 노드 관리 API가 모드에 따라 동작합니다:

| API | Mock Mode | Production Mode |
|-----|-----------|-----------------|
| GET `/api/nodes` | 샘플 4개 노드 | 실제 `sinfo` 실행 |
| GET `/api/nodes/<name>` | Mock 데이터 | 실제 `scontrol show node` |
| POST `/api/nodes/drain` | 로그만 출력 | 실제 `scontrol update` |
| POST `/api/nodes/resume` | 로그만 출력 | 실제 `scontrol update` |
| POST `/api/nodes/reboot` | 로그만 출력 | 실제 `scontrol reboot` |
| GET `/api/nodes/history` | 인메모리 저장소 | 인메모리 저장소 |

### 기타 API
- `/api/slurm/jobs`: Mock에서는 샘플 작업, Production에서는 실제 `squeue`
- `/api/health/status`: 모드 정보 포함

---

## ⚠️ 주의사항

### Production Mode
1. **권한 확인**: Slurm 명령 실행 권한 필요
2. **영향 범위**: 실제 클러스터에 영향을 줍니다
3. **테스트**: 먼저 Mock Mode로 테스트 후 사용
4. **백업**: 중요한 작업 전 현재 설정 백업

### Mock Mode
1. **제한사항**: 실제 Slurm 기능 사용 불가
2. **데이터**: 하드코딩된 샘플 데이터 사용
3. **이력**: 서버 재시작 시 작업 이력 초기화

---

## 🛠️ 문제 해결

### 문제: 모드가 바뀌지 않음

**원인**: 서버가 재시작되지 않음

**해결**:
```bash
./stop_all.sh
sleep 3
./start_all.sh  # 또는 ./start_all_mock.sh
```

### 문제: Mode Badge와 실제 동작이 다름

**원인**: Frontend 캐시

**해결**:
- 브라우저 Hard Refresh: **Ctrl + F5** (Windows/Linux) 또는 **Cmd + Shift + R** (Mac)
- 또는 Frontend 재시작:
```bash
cd frontend_3010
./stop.sh && ./start.sh
```

### 문제: Production Mode에서 "Command not found" 에러

**원인**: Slurm이 설치되지 않았거나 PATH 설정 안됨

**해결**:
1. Slurm 설치 확인:
```bash
which sinfo
which scontrol
```

2. Slurm이 없으면 Mock Mode 사용:
```bash
./stop_all.sh
./start_all_mock.sh
```

---

## 📚 관련 파일

### 스크립트
- `start_all.sh` - Production Mode 시작
- `start_all_mock.sh` - Mock Mode 시작
- `stop_all.sh` - 모든 서버 종료
- `backend_5010/start.sh` - Backend 개별 시작
- `backend_5010/switch_mode.sh` - 대화형 모드 전환

### 코드
- `backend_5010/app.py` - MOCK_MODE 환경변수 사용
- `backend_5010/node_management_api.py` - 모드별 로직 구현

### 문서
- `PHASE1_2_NODE_MANAGEMENT_COMPLETE.md` - Phase 1-2 완료 문서
- `QUICK_START_PHASE1_2.md` - 빠른 시작 가이드
- `MOCK_PRODUCTION_MODE_GUIDE.md` - 이 문서

---

## 🎯 베스트 프랙티스

### 개발 시
1. **항상 Mock Mode로 시작**
```bash
./start_all_mock.sh
```

2. UI/기능 개발 및 테스트

3. 완료 후 Production Mode로 최종 확인
```bash
./stop_all.sh
./start_all.sh
```

### 운영 시
1. **Production Mode 사용**
```bash
./start_all.sh
```

2. 정기적으로 로그 확인
```bash
tail -f backend_5010/logs/backend.log
```

3. 문제 발생 시 Mock Mode로 전환하여 UI 테스트
```bash
./stop_all.sh
./start_all_mock.sh
```

---

## ✅ 체크리스트

시작 전 확인:
- [ ] 어떤 모드가 필요한지 결정 (Mock/Production)
- [ ] Production Mode: Slurm 설치 확인
- [ ] Mock Mode: 테스트 시나리오 준비
- [ ] 포트 충돌 없음 확인 (3010, 5010, 5011, 9100, 9090)

시작 후 확인:
- [ ] Backend 로그에서 모드 확인
- [ ] 브라우저에서 Mode Badge 확인
- [ ] Node Management 탭에서 노드 목록 확인
- [ ] Mock Mode: 4개 샘플 노드 표시
- [ ] Production Mode: 실제 노드 표시

---

**작성일**: 2025-10-10  
**버전**: 1.0  
**관련 Phase**: Phase 1-2 (노드 관리 기본)
