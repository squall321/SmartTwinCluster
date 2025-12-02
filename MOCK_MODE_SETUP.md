# 🎭 Mock Mode 설정 가이드

## 개요

Mock Mode는 실제 Slurm 클러스터 없이 Dashboard를 테스트할 수 있는 모드입니다.

---

## 📁 생성된 파일

### 1. start_mock.sh (프로젝트 루트)
**경로**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/start_mock.sh`

**목적**: Mock Mode로 모든 서비스를 시작하는 진입점

**사용법**:
```bash
./start_mock.sh
```

### 2. dashboard/start_mock.sh
**경로**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/start_mock.sh`

**목적**: 실제 Mock Mode 시작 로직 구현

**주요 기능**:
- 기존 서비스 종료 (포트 5010, 5011 포함)
- `MOCK_MODE=true` 환경변수로 Backend 시작
- `.env` 파일에 `MOCK_MODE=true` 설정
- Prometheus 제외 (Mock Mode에서는 불필요)

---

## 🔄 start.sh vs start_mock.sh 비교

| 항목 | start.sh (Production) | start_mock.sh (Mock) |
|------|----------------------|---------------------|
| **Slurm 명령어** | ✅ 실제 실행 | ❌ Mock 데이터 |
| **MOCK_MODE** | false | true |
| **데이터** | 실시간 클러스터 데이터 | 고정된 테스트 데이터 |
| **Prometheus** | ✅ 시작 | ❌ Skip |
| **클러스터 영향** | ⚠️ 있음 | ✅ 없음 |
| **용도** | 운영 환경 | 개발/테스트 |

---

## 🚀 사용 방법

### Mock Mode 시작
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
./start_mock.sh
```

**출력 예시**:
```
🎭 HPC Cluster Mock Mode 시작
✅ Dashboard Backend 시작됨 (PID: 1099288, Port: 5010, MOCK_MODE=true)
✅ Mock Mode 시작 완료!
```

### Mock Mode 확인
```bash
curl http://localhost:5010/api/health | jq .mode
# 출력: "mock"
```

### Production Mode로 전환
```bash
./stop_complete.sh
./start.sh  # 또는 ./start_complete.sh
```

---

## ✅ Mock Mode 테스트

### 1. Health Check
```bash
curl http://localhost:5010/api/health | jq
```

**Expected**:
```json
{
  "mode": "mock",
  "status": "healthy",
  "timestamp": "2025-10-22T..."
}
```

### 2. Jobs API (Mock Data)
```bash
curl http://localhost:5010/api/slurm/jobs | jq '.count'
# 출력: 20
```

### 3. Partitions API (Mock Data)
```bash
curl http://localhost:5010/api/slurm/partitions | jq '.partitions[].Name'
```

---

## 🔧 구현 세부사항

### start_mock.sh 핵심 차이점

#### 1. 백엔드 서비스 종료 (강화)
```bash
# 백엔드 서비스 종료 (-9 플래그 추가)
pkill -9 -f "backend_5010.*app.py" 2>/dev/null

# 포트 강제 해제 (5010, 5011 추가)
for port in 3010 8002 5173 5010 5011; do
    if lsof -ti:$port >/dev/null 2>&1; then
        lsof -ti:$port | xargs -r kill -9 2>/dev/null
    fi
done
```

#### 2. Backend 시작 (MOCK_MODE=true)
```bash
cd backend_5010
MOCK_MODE=true nohup python3 app.py > /tmp/dashboard_backend_5010.log 2>&1 &
```

#### 3. .env 파일 설정
```bash
if ! grep -q "^MOCK_MODE=true" backend_5010/.env; then
    sed -i 's/^MOCK_MODE=.*/MOCK_MODE=true/' backend_5010/.env
fi
```

#### 4. Prometheus Skip
```bash
# Prometheus (선택사항 - Mock Mode에서는 skip)
echo -e "${YELLOW}⚠  Prometheus는 Mock Mode에서 시작하지 않습니다${NC}"
```

---

## 📊 Mock vs Production 흐름도

```
사용자 요청
    │
    ├─── Mock Mode 개발/테스트
    │      │
    │      └─> ./start_mock.sh
    │            │
    │            ├─ MOCK_MODE=true 설정
    │            ├─ Mock 데이터 반환
    │            └─ Slurm 명령어 실행 안함
    │
    └─── Production Mode 운영
           │
           └─> ./start.sh
                 │
                 ├─ MOCK_MODE=false 설정
                 ├─ 실제 Slurm 데이터
                 └─ Slurm 명령어 실행
```

---

## 🎯 사용 시나리오

### Mock Mode 추천
- ✅ 프론트엔드 UI/UX 개발
- ✅ API 통합 테스트
- ✅ 데모 또는 프레젠테이션
- ✅ Slurm이 설치되지 않은 환경
- ✅ 클러스터에 영향 없이 안전하게 테스트

### Production Mode 필요
- ⚠️ 실제 Job 제출/관리
- ⚠️ 실시간 클러스터 모니터링
- ⚠️ 실제 VNC 세션 생성
- ⚠️ 실시간 메트릭 수집 (Prometheus)

---

## 🔍 문제 해결

### 1. Mock Mode가 활성화되지 않음
```bash
# 프로세스 확인
ps aux | grep "backend_5010.*app.py"

# 포트 확인
lsof -i:5010

# 강제 종료 후 재시작
pkill -9 -f "backend_5010.*app.py"
./start_mock.sh
```

### 2. 여전히 Production 모드로 실행됨
```bash
# .env 파일 확인
cat dashboard/backend_5010/.env | grep MOCK_MODE

# 수동으로 수정
sed -i 's/MOCK_MODE=false/MOCK_MODE=true/' dashboard/backend_5010/.env

# Backend만 재시작
cd dashboard/backend_5010
pkill -9 -f "app.py"
MOCK_MODE=true python3 app.py > /tmp/dashboard_backend_5010.log 2>&1 &
```

---

## 📚 관련 문서

- **전체 가이드**: `/tmp/mock_mode_guide.md`
- **Production 시작**: [start.sh](./start.sh)
- **Production 중지**: [stop_complete.sh](./dashboard/stop_complete.sh)
- **Setup 가이드**: [SETUP_WORKFLOW_GUIDE.md](./SETUP_WORKFLOW_GUIDE.md)

---

**작성일**: 2025-10-22
**버전**: 1.0
**작성자**: KooSlurmInstallAutomation
