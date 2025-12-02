# Phase 4: Production Mode - Slurm Cluster Integration

Dashboard Backend를 Production 모드로 전환하여 실제 Slurm 클러스터와 연동 완료

---

## 📋 Phase 4 개요

Phase 0-3에서 전체 인증 시스템을 Mock 모드로 구축한 후, Phase 4에서는 **Production 모드로 전환**하여 실제 Slurm 클러스터와 연동합니다.

**목표:**
- ✅ Mock Mode → Production Mode 전환
- ✅ 실제 Slurm 클러스터 데이터 조회
- ✅ 실제 작업 제출 및 모니터링
- ✅ Dashboard에서 실시간 클러스터 상태 확인

---

## 🔧 Phase 4 완료 사항

### 1. Slurm 환경 확인

**Slurm 버전**: 23.11.10
**노드**: node001, node002 (2개 노드)
**파티션**: normal (default, idle 상태)

```bash
$ sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up   infinite      2   idle node[001-002]
```

### 2. Production 모드 전환

**파일**: [backend_5010/.env](backend_5010/.env)

```bash
# Before
MOCK_MODE=true

# After
MOCK_MODE=false
```

**Backend 재시작**:
```bash
# 기존 Backend 중지
kill <backend_pid>

# Production 모드로 시작
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010
source venv/bin/activate
nohup python3 app.py > /tmp/backend_production.log 2>&1 &
```

### 3. Slurm 명령어 인프라

**파일**: [backend_5010/slurm_commands.py](backend_5010/slurm_commands.py)

이미 구현된 Slurm 명령어 래퍼:
- `get_sinfo()` - 클러스터 정보 조회
- `get_squeue()` - 작업 큐 조회
- `get_sacct()` - 작업 이력 조회
- `get_scontrol()` - Slurm 제어
- `get_sacctmgr()` - 계정 관리 (sudo)
- `get_sreport()` - 리포트 생성

```python
# Slurm 설치 경로
SLURM_BIN_DIR = os.getenv('SLURM_BIN_DIR', '/usr/local/slurm/bin')

# 명령어 실행 헬퍼
def run_slurm_command(command: List[str], timeout: int = 10,
                      use_sudo: bool = False, check: bool = True):
    """Slurm 명령어 실행"""
    if use_sudo:
        command = ['sudo'] + command

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=check
    )
    return result
```

### 4. 실제 Slurm 작업 제출

**Test Script**: [/tmp/test_phase4_production.sh](/tmp/test_phase4_production.sh)

```bash
# JWT 토큰 획득
TOKEN=$(curl -s -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","email":"admin@hpc.local","groups":["HPC-Admins"]}' | jq -r '.token')

# 실제 작업 제출
curl -s -X POST http://localhost:5010/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jobName": "phase4_test",
    "partition": "normal",
    "nodes": 1,
    "cpus": 1,
    "memory": "1GB",
    "time": "00:01:00",
    "script": "#!/bin/bash\necho \"Phase 4 Production Test\"\nsleep 5\necho \"Completed\""
  }'
```

**결과**:
```json
{
  "jobId": "2",
  "message": "Job 2 submitted successfully",
  "mode": "production",
  "success": true
}
```

### 5. 실제 클러스터 데이터 조회

#### Nodes API
```bash
curl -s http://localhost:5010/api/slurm/nodes/real | jq
```

**응답**:
```json
{
  "data": {
    "nodes": [
      {
        "cores": 2,
        "cpus_allocated": 0,
        "cpus_idle": 2,
        "hostname": "node001",
        "ipAddress": "192.168.122.90",
        "memory": 4096,
        "partition": "normal",
        "state": "idle"
      },
      {
        "cores": 2,
        "cpus_allocated": 0,
        "cpus_idle": 2,
        "hostname": "node002",
        "ipAddress": "192.168.122.103",
        "memory": 4096,
        "partition": "normal",
        "state": "idle"
      }
    ],
    "total_nodes": 2
  },
  "mode": "production",
  "success": true
}
```

#### Slurm Status API
```bash
curl -s http://localhost:5010/api/slurm/status | jq
```

**응답**:
```json
{
  "mode": "production",
  "partitions": [
    {
      "availability": "up",
      "name": "normal",
      "nodes": 2,
      "state": "idle",
      "timelimit": "infinite"
    }
  ],
  "success": true
}
```

---

## 🧪 테스트 결과

### 자동 테스트 실행

```bash
chmod +x /tmp/test_phase4_production.sh
/tmp/test_phase4_production.sh
```

### 테스트 결과 요약

```
==========================================
Phase 4: Production Mode Test
==========================================

✅ Step 1: JWT Token obtained
✅ Step 2: Backend is in PRODUCTION mode
✅ Step 3: Real Cluster Status (Slurm 23.11.10, 2 nodes)
✅ Step 4: Nodes via API (2 nodes found)
✅ Step 5: Real Slurm Job submitted (Job ID = 2)
✅ Step 6: Job Status via squeue (PENDING → RUNNING)
✅ Step 7: Job Completion (5 seconds)
✅ Step 8: Job Output verified

🎉 Phase 4: PRODUCTION MODE WORKING!
```

---

## 🔄 Mock vs Production 모드 비교

| 항목 | Mock Mode | Production Mode |
|------|-----------|-----------------|
| 노드 데이터 | 가짜 데이터 (20개 노드) | 실제 Slurm 클러스터 (2개 노드) |
| 작업 제출 | 시뮬레이션 (Job ID 10001+) | 실제 sbatch 실행 (Job ID 1+) |
| 작업 실행 | 가상 실행 (즉시 완료) | 실제 노드에서 실행 |
| 작업 큐 | Mock 데이터 (20개 작업) | 실제 squeue 결과 |
| 파티션 | Mock 데이터 (group1, group2, gpu, high) | 실제 파티션 (normal) |
| 작업 이력 | Mock 데이터 (250개) | 실제 sacct 결과 (accounting 필요) |
| 성능 | 빠름 (0.01초) | Slurm 명령어 속도 (0.1-0.5초) |

---

## 📊 API 엔드포인트 변경 사항

### Production 모드에서 작동하는 엔드포인트

| 엔드포인트 | Mock | Production | 비고 |
|-----------|------|------------|------|
| GET /api/health | ✅ | ✅ | mode: production으로 변경 |
| GET /api/slurm/status | ✅ | ✅ | 실제 sinfo 데이터 |
| GET /api/slurm/nodes/real | ✅ | ✅ | 실제 노드 정보 |
| POST /api/slurm/jobs/submit | ✅ | ✅ | 실제 sbatch 실행 |
| GET /api/slurm/jobs | ✅ | ✅ | 실제 squeue 데이터 |
| POST /api/slurm/jobs/:id/cancel | ✅ | ✅ | 실제 scancel 실행 |
| GET /api/metrics/realtime | ✅ | ✅ | 실제 클러스터 메트릭 |

### Production 모드에서 제한되는 엔드포인트

일부 엔드포인트는 Slurm accounting (slurmdbd)이 필요합니다:

| 엔드포인트 | 요구사항 | 현재 상태 |
|-----------|---------|----------|
| GET /api/reports/usage | slurmdbd | ⚠️  Accounting disabled |
| GET /api/reports/costs | slurmdbd | ⚠️  Accounting disabled |
| GET /api/reports/users | slurmdbd | ⚠️  Accounting disabled |

**참고**: Slurm accounting을 활성화하려면 slurmdbd 설정 필요

---

## 🔐 권한 설정

### Backend 사용자 권한

Backend가 Slurm 명령어를 실행하려면 적절한 권한이 필요합니다:

```bash
# 현재 사용자가 Slurm 명령어를 실행할 수 있는지 확인
sinfo --version
squeue
sbatch --version

# 필요한 경우 sudoers 설정 (sacctmgr 등)
# /etc/sudoers.d/slurm
koopark ALL=(ALL) NOPASSWD: /usr/local/slurm/bin/sacctmgr
```

### 작업 제출 디렉토리

작업 스크립트와 출력 파일을 위한 디렉토리 권한:

```bash
# 작업 스크립트 임시 디렉토리
mkdir -p /tmp/slurm_jobs
chmod 755 /tmp/slurm_jobs

# 출력 파일은 /tmp에 저장
# 예: /tmp/phase4_test_2.out
```

---

## 🚀 Production 모드 전환 방법

### 1단계: .env 파일 수정

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010
vi .env
```

```bash
# 변경
MOCK_MODE=false
```

### 2단계: Backend 재시작

```bash
# 기존 프로세스 확인
ps aux | grep "python3.*app.py" | grep 5010

# 종료
kill <pid>

# 재시작
source venv/bin/activate
nohup python3 app.py > /tmp/backend_production.log 2>&1 &

# 로그 확인
tail -f /tmp/backend_production.log
```

### 3단계: 모드 확인

```bash
curl -s http://localhost:5010/api/health | jq
```

**예상 출력**:
```json
{
  "mode": "production",
  "status": "healthy",
  "timestamp": "2025-10-16T20:00:44.251895"
}
```

### 4단계: Mock 모드로 되돌리기 (필요시)

```bash
# .env 수정
MOCK_MODE=true

# Backend 재시작
kill <pid>
source venv/bin/activate
python3 app.py &
```

---

## 🧑‍💻 브라우저에서 확인

### 1단계: Auth Portal 로그인

```
http://localhost:4431
```
- Test Login (admin / HPC-Admins)

### 2단계: HPC Dashboard 접속

- Service Menu에서 "HPC Dashboard" 클릭
- Dashboard 자동 로드 (JWT 인증)

### 3단계: Production 모드 확인

Dashboard 우측 하단 또는 API 응답에서 확인:
- **Mock Mode**: 가짜 데이터 표시
- **Production Mode**: 실제 클러스터 데이터 표시

### 4단계: 실제 데이터 확인

- **Nodes**: node001, node002 (2개)
- **Partitions**: normal
- **Jobs**: 실제 squeue 결과
- **작업 제출**: 실제 노드에서 실행

---

## 📚 관련 파일

| 파일 | 역할 |
|------|------|
| [backend_5010/.env](backend_5010/.env) | MOCK_MODE 설정 |
| [backend_5010/app.py](backend_5010/app.py) | MOCK_MODE 분기 처리 |
| [backend_5010/slurm_commands.py](backend_5010/slurm_commands.py) | Slurm 명령어 래퍼 |
| [backend_5010/slurm_utils.py](backend_5010/slurm_utils.py) | Slurm 유틸리티 |
| [backend_5010/slurm_data_collector.py](backend_5010/slurm_data_collector.py) | 데이터 수집 |
| [/tmp/test_phase4_production.sh](/tmp/test_phase4_production.sh) | Phase 4 테스트 스크립트 |
| [/tmp/backend_production.log](/tmp/backend_production.log) | Backend 로그 |

---

## ⚠️  Production 배포 시 주의사항

### 1. Slurm Accounting

현재 Slurm accounting이 비활성화되어 있습니다:

```bash
$ sacct -j 2
Slurm accounting storage is disabled
```

**활성화 방법**:
- slurmdbd (Slurm Database Daemon) 설치 및 설정
- slurm.conf에서 AccountingStorageType 설정
- MySQL/MariaDB 데이터베이스 연결

**영향받는 기능**:
- 작업 이력 조회
- 사용량 리포트
- 비용 분석
- 사용자 통계

### 2. 성능 최적화

Production 모드에서는 Slurm 명령어 호출이 Mock보다 느립니다:

**최적화 방법**:
- 캐싱 (Redis)
- 비동기 작업 (Celery)
- 배치 처리
- API 요청 제한 (Rate Limiting)

### 3. 보안

Production 배포 시 필수 설정:

- ✅ JWT 시크릿 키 변경 (.env 파일)
- ✅ HTTPS 적용 (Nginx SSL/TLS)
- ✅ 방화벽 설정 (포트 제한)
- ✅ 사용자 권한 최소화
- ✅ 작업 스크립트 검증 (인젝션 방지)

### 4. 모니터링

Production 환경 모니터링:

```bash
# Backend 로그 모니터링
tail -f /tmp/backend_production.log

# Slurm 로그
tail -f /var/log/slurm/slurmctld.log
tail -f /var/log/slurm/slurmd.log

# 시스템 리소스
htop
df -h
```

---

## 🎯 Phase 4 체크리스트

- [x] Slurm 환경 확인 (23.11.10, 2 nodes)
- [x] Production 모드 전환 (MOCK_MODE=false)
- [x] Backend 재시작
- [x] Slurm 명령어 테스트
- [x] 실제 노드 데이터 조회
- [x] 실제 작업 제출 및 실행
- [x] Dashboard에서 실시간 데이터 확인
- [x] End-to-end 테스트 완료

---

## 🚀 다음 단계 (선택사항)

### Phase 5: Advanced Features (제안)

1. **Slurm Accounting 활성화**
   - slurmdbd 설치
   - 작업 이력 및 통계 수집
   - 비용 분석 기능

2. **성능 최적화**
   - Redis 캐싱
   - Celery 비동기 작업
   - WebSocket 실시간 업데이트

3. **고급 기능**
   - 작업 배열 (Job Arrays)
   - 작업 의존성 (Dependencies)
   - 작업 템플릿
   - 자동 스케일링

4. **Production 배포**
   - Docker 컨테이너화
   - Kubernetes 배포
   - CI/CD 파이프라인
   - 모니터링 및 알림

---

## 📖 참고 문서

- [Phase 0: Infrastructure Setup](setup_phase0_all.sh)
- [Phase 1: Auth Portal](PHASE1_README.md)
- [Phase 2: Backend JWT Integration](PHASE2_README.md)
- [Phase 3: Dashboard Frontend JWT Integration](PHASE3_README.md)
- [User Guide](USER_GUIDE.md)
- [Quick Reference](QUICK_REFERENCE.md)

---

## 🎉 Phase 0-4 완료!

전체 시스템이 Production 모드로 작동합니다:

```
✅ Auth Portal (4431) - SSO 인증
✅ Auth Backend (4430) - JWT 발급/검증
✅ Dashboard Backend (5010) - Production Mode
✅ Dashboard Frontend (3010) - JWT 인증
✅ Redis (6379) - 세션 관리
✅ Slurm Cluster (23.11.10) - 실제 작업 실행
```

**전체 플로우가 Production 환경에서 end-to-end로 작동합니다!** 🎊

---

**작성일**: 2025-10-16
**버전**: Phase 4.0 (Production Mode 완료)
**Slurm**: 23.11.10
**Nodes**: 2 (node001, node002)
