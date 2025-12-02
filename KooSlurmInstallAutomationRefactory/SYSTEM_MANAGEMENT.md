# HPC 클러스터 전체 시스템 관리 가이드

## 📋 개요

이 문서는 Slurm 클러스터와 웹 대시보드를 포함한 전체 HPC 시스템을 통합 관리하는 방법을 설명합니다.

## 🎯 시스템 구성

### 1. Slurm 클러스터 서비스
- **Controller 노드 (smarttwincluster)**
  - Munge (인증)
  - MariaDB (데이터베이스)
  - slurmdbd (데이터베이스 데몬)
  - slurmctld (컨트롤러 데몬)

- **Compute 노드 (node001, node002, viz-node001)**
  - Munge (인증)
  - slurmd (컴퓨트 데몬)

### 2. 웹 대시보드 서비스
- **Frontend**: React 기반 웹 UI (포트 3010/80)
- **Backend API**: Python FastAPI (포트 5010)
- **Prometheus**: 메트릭 수집 (포트 9090)
- **Node Exporter**: 시스템 메트릭 (포트 9100)

## 🚀 전체 시스템 관리

### 통합 시작/정지 스크립트

#### 1. start_all_services.sh
전체 시스템을 한 번에 시작합니다.

#### 2. stop_all_services.sh
전체 시스템을 한 번에 정지합니다.

## 📖 사용법

### 🟢 전체 시스템 시작

#### 기본 사용 (Production Mode)
```bash
./start_all_services.sh
```

**실행 순서:**
1. ✅ Slurm 클러스터 서비스 시작
   - Munge (모든 노드)
   - MariaDB (Controller)
   - slurmdbd (Controller)
   - slurmctld (Controller)
   - slurmd (모든 Compute 노드)

2. ✅ 웹 대시보드 서비스 시작
   - Frontend 빌드 및 Nginx 배포
   - Backend API 시작
   - Prometheus 시작
   - Node Exporter 시작

#### Mock Mode (테스트용)
```bash
./start_all_services.sh --mock
```
- Slurm 없이 웹 대시보드만 테스트 데이터로 실행
- 개발/테스트/데모 환경에 적합

#### 부분 시작

**Slurm만 시작 (웹 건너뛰기):**
```bash
./start_all_services.sh --skip-web
```

**웹만 시작 (Slurm 건너뛰기):**
```bash
./start_all_services.sh --skip-slurm
```

### 🔴 전체 시스템 정지

#### 기본 사용
```bash
./stop_all_services.sh
```

**실행 순서:**
1. ✅ 웹 대시보드 서비스 정지 (먼저)
2. ✅ Slurm 클러스터 서비스 정지
   - slurmd (모든 Compute 노드)
   - slurmctld (Controller)
   - slurmdbd (Controller)
   - MariaDB (선택 사항)
   - Munge (선택 사항)

#### 강제 정지 (확인 없이)
```bash
./stop_all_services.sh --force
```

#### 부분 정지

**Slurm만 정지:**
```bash
./stop_all_services.sh --skip-web
```

**웹만 정지:**
```bash
./stop_all_services.sh --skip-slurm
```

## 🔧 개별 서비스 관리

### Slurm 서비스만 관리

**시작:**
```bash
./start_slurm_services.sh
```

**정지:**
```bash
./stop_slurm_services.sh
```

### 웹 대시보드만 관리

**시작 (Production):**
```bash
./start.sh
```

**시작 (Mock):**
```bash
./start.sh --mock
```

**정지:**
```bash
./stop.sh
```

## 📊 시스템 상태 확인

### 전체 상태 한눈에 보기

```bash
# Slurm 클러스터
sinfo                    # 노드 상태
squeue                   # 작업 큐
scontrol show node       # 노드 상세 정보

# 웹 서비스
lsof -i -P -n | grep LISTEN   # 열린 포트 확인

# 프로세스
ps aux | grep slurm      # Slurm 프로세스
ps aux | grep python     # Python 백엔드
```

### Slurm 서비스 상태

```bash
# Controller
sudo systemctl status slurmctld
sudo systemctl status slurmdbd
sudo systemctl status munge

# 로그 확인
sudo journalctl -u slurmctld -f
sudo journalctl -u slurmdbd -f
```

### 웹 서비스 상태

```bash
# 포트 확인
lsof -i :5010    # Backend
lsof -i :9090    # Prometheus
lsof -i :9100    # Node Exporter
lsof -i :3010    # Frontend (dev mode)
lsof -i :80      # Nginx (production)

# 로그 확인
tail -f dashboard/backend_5010/logs/*.log
```

## 🔄 일반적인 시나리오

### 1. 시스템 재부팅 후

```bash
# 전체 시스템 시작
./start_all_services.sh

# 또는 순차적으로
./start_slurm_services.sh
./start.sh
```

### 2. 설정 변경 후

**Slurm 설정 변경 시:**
```bash
# slurm.conf 수정 후
sudo scontrol reconfigure

# 또는 서비스 재시작
./stop_slurm_services.sh
./start_slurm_services.sh
```

**웹 대시보드 설정 변경 시:**
```bash
./stop.sh
./start.sh
```

### 3. 유지보수 모드

**Slurm만 정지 (웹은 유지):**
```bash
./stop_slurm_services.sh

# 유지보수 작업 수행
# ...

./start_slurm_services.sh
```

**웹만 정지 (Slurm은 유지):**
```bash
./stop.sh

# 업데이트 작업 수행
# ...

./start.sh
```

### 4. 긴급 정지

```bash
# 확인 없이 즉시 정지
./stop_all_services.sh --force

# 또는 개별 강제 종료
sudo pkill -9 slurmctld slurmdbd slurmd
pkill -9 -f "python.*backend"
pkill -9 -f "prometheus"
```

### 5. 테스트/개발 모드

```bash
# Mock 모드로 시작 (Slurm 없이 웹만)
./start_all_services.sh --mock

# 또는
./start.sh --mock
```

## 🎨 출력 예시

### start_all_services.sh 실행 시

```
================================================================================
                    🚀 HPC 클러스터 전체 시스템 시작
================================================================================

시작할 서비스:
  1️⃣  Slurm 클러스터 서비스 (Munge, slurmdbd, slurmctld, slurmd)
  2️⃣  웹 대시보드 서비스 (Frontend, Backend, Prometheus, Node Exporter)


================================================================================
Phase 1: Slurm 클러스터 서비스 시작
================================================================================

🚀 Slurm 서비스 시작
...

✅ Phase 1 완료: Slurm 서비스 시작 성공

⏱️  Slurm 서비스 안정화 대기 중... (5초)

================================================================================
Phase 2: 웹 대시보드 서비스 시작
================================================================================

🚀 Production Mode로 웹 서비스 시작 중...
...

✅ Phase 2 완료: 웹 대시보드 시작 성공

================================================================================
                        🎉 시스템 시작 완료!
================================================================================

📊 Slurm 클러스터 상태:
--------------------------------------------------------------------------------
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up 7-00:00:00      2   idle node[001-002]
viz          up 60-00:00:0      1   idle viz-node001

📋 실행 중인 작업:
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)

🌐 웹 대시보드 서비스 상태:
--------------------------------------------------------------------------------
  ✅ Backend API (포트 5010) - 실행 중
  ✅ Prometheus (포트 9090) - 실행 중
  ✅ Node Exporter (포트 9100) - 실행 중

================================================================================
💡 유용한 정보:
================================================================================

Slurm 명령어:
  • 노드 상태:     sinfo -N -l
  • 작업 제출:     sbatch <script.sh>
  • 작업 확인:     squeue
  • 로그 확인:     sudo journalctl -u slurmctld -f

웹 대시보드 접속:
  • Frontend:      http://localhost (Nginx)
  • Backend API:   http://localhost:5010
  • Prometheus:    http://localhost:9090

시스템 관리:
  • 전체 중지:     ./stop_all_services.sh
  • Slurm만 중지:  ./stop_slurm_services.sh
  • 웹만 중지:     ./stop.sh

================================================================================
```

## 🔍 문제 해결

### 시작 실패 시

1. **Slurm 서비스 시작 실패:**
```bash
# 로그 확인
sudo journalctl -u slurmctld -n 100
sudo journalctl -u slurmdbd -n 100

# 수동 디버그 모드
sudo /usr/local/slurm/sbin/slurmctld -D -vvv
```

2. **웹 서비스 시작 실패:**
```bash
# 포트 사용 확인
lsof -i :5010
lsof -i :9090

# 로그 확인
tail -f dashboard/backend_5010/logs/error.log
```

3. **네트워크 연결 실패:**
```bash
# SSH 연결 확인
ssh koopark@192.168.122.90 "hostname"

# Munge 인증 확인
munge -n | unmunge
```

### 정지 실패 시

**프로세스가 남아있을 때:**
```bash
# Slurm 강제 종료
sudo pkill -9 slurmctld slurmdbd slurmd

# 웹 서비스 강제 종료
pkill -9 -f "python.*backend"
pkill -9 -f "prometheus"
pkill -9 -f "node_exporter"

# 포트 강제 해제
fuser -k 5010/tcp
fuser -k 9090/tcp
```

## 📝 모범 사례

1. **정기 재시작:**
   - 주 1회 정기 재시작 권장
   - 유지보수 시간대 활용

2. **로그 모니터링:**
   - 정기적으로 로그 확인
   - 디스크 공간 관리

3. **백업:**
   - 설정 파일 정기 백업
   - 데이터베이스 백업 (slurmdbd 사용 시)

4. **순서 준수:**
   - 시작: Slurm → 웹
   - 정지: 웹 → Slurm

5. **테스트:**
   - Production 배포 전 Mock 모드 테스트
   - 새 기능 추가 시 개별 서비스 테스트

## 🆘 긴급 상황

### 전체 시스템 즉시 정지
```bash
./stop_all_services.sh --force
```

### 완전 초기화 (주의!)
```bash
# 모든 서비스 정지
./stop_all_services.sh --force

# 프로세스 정리
sudo pkill -9 slurm
pkill -9 python
pkill -9 prometheus

# 로그 초기화 (선택)
sudo rm -f /var/log/slurm/*.log

# 재시작
./start_all_services.sh
```

## 📞 추가 도움말

- **Slurm 관련**: [SLURM_SERVICE_MANAGEMENT.md](SLURM_SERVICE_MANAGEMENT.md)
- **설정 파일**: `my_cluster.yaml`
- **웹 대시보드**: `dashboard/README.md`

## ⚙️ 스크립트 상세 설명

### start_all_services.sh 옵션

| 옵션 | 설명 |
|------|------|
| (없음) | 전체 시스템 Production 모드로 시작 |
| `--mock` | 웹 대시보드만 Mock 모드로 시작 |
| `--skip-slurm` | Slurm 건너뛰고 웹만 시작 |
| `--skip-web` | 웹 건너뛰고 Slurm만 시작 |
| `--help` | 도움말 표시 |

### stop_all_services.sh 옵션

| 옵션 | 설명 |
|------|------|
| (없음) | 전체 시스템 정지 (확인 프롬프트 포함) |
| `--force` | 확인 없이 즉시 정지 |
| `--skip-slurm` | Slurm 건너뛰고 웹만 정지 |
| `--skip-web` | 웹 건너뛰고 Slurm만 정지 |
| `--help` | 도움말 표시 |

## 🎯 Quick Reference

```bash
# 🟢 시작
./start_all_services.sh              # 전체 시작
./start_all_services.sh --mock       # Mock 모드
./start_slurm_services.sh            # Slurm만
./start.sh                           # 웹만

# 🔴 정지
./stop_all_services.sh               # 전체 정지
./stop_all_services.sh --force       # 강제 정지
./stop_slurm_services.sh             # Slurm만
./stop.sh                            # 웹만

# 📊 상태
sinfo                                # Slurm 노드
squeue                               # Slurm 작업
lsof -i -P -n | grep LISTEN          # 웹 포트

# 🔄 재시작
./stop_all_services.sh && sleep 5 && ./start_all_services.sh
```
