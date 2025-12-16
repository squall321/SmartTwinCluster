# Slurm QoS 설정 가이드 - Moonlight/Sunshine

**목적**: Moonlight 서비스를 위한 전용 QoS (Quality of Service) 생성 및 리소스 격리

---

## 🎯 QoS 목적

### 왜 QoS가 필요한가?

1. **리소스 경쟁 방지**
   - VNC, CAE, Moonlight이 모두 `viz` 파티션을 공유
   - QoS로 각 서비스별 리소스 제한 가능

2. **공정한 리소스 분배**
   - Moonlight 사용자가 GPU를 독점하지 않도록 제한
   - 다른 사용자들에게도 공정한 기회 보장

3. **서비스 추적 및 모니터링**
   - QoS별 사용 통계 수집 가능
   - Prometheus + Grafana로 모니터링

---

## 📋 QoS 설정 사항

### QoS 이름
```
moonlight
```

### QoS 파라미터

| 파라미터 | 값 | 설명 |
|----------|-----|------|
| **GraceTime** | 60 | Job 종료 유예 시간 (60초) |
| **MaxWall** | 8:00:00 | 최대 실행 시간 (8시간) |
| **MaxTRESPerUser** | gpu=2 | 사용자당 최대 GPU 2개 |
| **Priority** | 100 | 우선순위 (기본값, 조정 가능) |

---

## 🔧 QoS 생성 절차

### Step 1: 현재 QoS 확인

```bash
# 현재 QoS 목록 조회
sacctmgr show qos format=Name,Priority,MaxWall,MaxTRESPerUser

# 예상 출력:
#       Name   Priority     MaxWall MaxTRESPU
# ---------- ---------- ----------- ---------
#     normal          0
```

### Step 2: moonlight QoS 생성

```bash
# QoS 추가 (sudo 또는 slurm 권한 필요)
sudo sacctmgr add qos moonlight

# 예상 출력:
#  Adding QOS(s)
#   moonlight
# Settings
# Would you like to commit changes? (You have 30 seconds to decide)
# (N/y): y

# 'y' 입력하여 확정
```

### Step 3: QoS 파라미터 설정

```bash
# GraceTime, MaxWall, MaxTRESPerUser 설정
sudo sacctmgr modify qos moonlight set \
    GraceTime=60 \
    MaxWall=8:00:00 \
    MaxTRESPerUser=gpu=2 \
    Priority=100

# 예상 출력:
#  Modified qos...
#   moonlight
# Would you like to commit changes? (You have 30 seconds to decide)
# (N/y): y
```

### Step 4: QoS 확인

```bash
# moonlight QoS 상세 정보 확인
sacctmgr show qos moonlight format=Name,Priority,MaxWall,MaxTRESPerUser,GraceTime -p

# 예상 출력:
# Name|Priority|MaxWall|MaxTRESPU|GraceTime|
# moonlight|100|08:00:00|gpu=2|00:01:00|
```

### Step 5: 사용자/계정에 QoS 할당 (선택사항)

```bash
# 특정 사용자에게 moonlight QoS 사용 권한 부여
# (기본적으로 모든 사용자가 사용 가능, 제한하려면 설정)

# 예: hpc-users 그룹에 moonlight QoS 할당
sudo sacctmgr modify user where account=hpc-users set qos+=moonlight

# 확인
sacctmgr show user format=User,Account,QOS
```

---

## 🧪 QoS 테스트

### Test Job 작성

```bash
# /tmp/test_moonlight_qos.sh 생성
cat > /tmp/test_moonlight_qos.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=test-moonlight-qos
#SBATCH --partition=viz
#SBATCH --qos=moonlight
#SBATCH --gres=gpu:1
#SBATCH --time=00:05:00
#SBATCH --output=/tmp/test-moonlight-qos-%j.out

echo "========================================"
echo "Testing Moonlight QoS"
echo "Job ID: $SLURM_JOB_ID"
echo "QoS: $SLURM_JOB_QOS"
echo "Partition: $SLURM_JOB_PARTITION"
echo "GPU: $CUDA_VISIBLE_DEVICES"
echo "Node: $(hostname)"
echo "========================================"

# GPU 확인
nvidia-smi

echo "========================================"
echo "Test completed successfully!"
echo "========================================"
EOF

chmod +x /tmp/test_moonlight_qos.sh
```

### Test Job 제출

```bash
# Job 제출
sbatch /tmp/test_moonlight_qos.sh

# 예상 출력:
# Submitted batch job 12345

# Job 상태 확인
squeue -u $USER

# 예상 출력:
#  JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
#  12345       viz test-moo  koopark  R       0:01      1 viz-node001

# QoS 확인
scontrol show job 12345 | grep QOS

# 예상 출력:
# QOS=moonlight
```

### 결과 확인

```bash
# Job 로그 확인
cat /tmp/test-moonlight-qos-12345.out

# 예상 출력:
# ========================================
# Testing Moonlight QoS
# Job ID: 12345
# QoS: moonlight
# Partition: viz
# GPU: 0
# Node: viz-node001
# ========================================
# (nvidia-smi 출력)
# ========================================
# Test completed successfully!
# ========================================
```

---

## 📊 QoS 모니터링

### 사용 통계 확인

```bash
# QoS별 Job 통계
sacct --qos=moonlight --format=JobID,User,QOS,Partition,AllocGRES,State,Elapsed

# 예상 출력:
#        JobID      User        QOS  Partition  AllocGRES      State    Elapsed
# ------------ --------- ---------- ---------- ---------- ---------- ----------
#        12345   koopark  moonlight        viz      gpu:1  COMPLETED   00:05:00
```

### 리소스 사용 현황

```bash
# 현재 moonlight QoS로 실행 중인 Job
squeue --qos=moonlight --format="%.10i %.9P %.20j %.8u %.2t %.10M %.6D %R %b"

# 예상 출력:
#      JOBID PARTITION NAME                 USER ST       TIME  NODES NODELIST(REASON) TRES_PER_NODE
#      12346 viz       moonlight-user01     user01  R      1:23      1 viz-node001      gpu:1
```

---

## ⚙️ QoS 튜닝 (필요 시)

### 1. 최대 동시 Job 제한

```bash
# 사용자당 최대 동시 실행 Job 수 제한
sudo sacctmgr modify qos moonlight set MaxJobsPerUser=2

# 확인
sacctmgr show qos moonlight format=Name,MaxJobsPerUser
```

### 2. 우선순위 조정

```bash
# VNC보다 우선순위 낮추기 (옵션)
sudo sacctmgr modify qos moonlight set Priority=50

# 확인
sacctmgr show qos format=Name,Priority
```

### 3. GPU 메모리 제한 (옵션)

```bash
# GPU 메모리 제한 (예: 20GB)
sudo sacctmgr modify qos moonlight set MaxTRESPerJob=gres/gpu:20000

# 확인
sacctmgr show qos moonlight format=Name,MaxTRESPerJob
```

---

## 🔍 문제 해결

### 1. QoS 생성 실패

```bash
# 권한 부족
# Error: You are not running with sufficient privileges

# 해결: sudo 사용
sudo sacctmgr add qos moonlight
```

### 2. Job 제출 시 QoS 인식 안 됨

```bash
# Error: Invalid qos specification

# 원인 1: QoS가 생성되지 않음
sacctmgr show qos moonlight

# 원인 2: 사용자가 QoS 사용 권한 없음
sacctmgr show user format=User,QOS | grep $USER
```

### 3. MaxTRESPerUser 초과

```bash
# Job이 PD (Pending) 상태로 대기
squeue -u $USER

# Reason 확인
scontrol show job <JOBID> | grep Reason

# 예상 출력:
# Reason=QOSMaxGRESPerUser
# (이미 gpu=2 사용 중)

# 해결: 기존 Job 종료 후 재시도
scancel <JOBID>
```

---

## ✅ Phase 2 완료 체크리스트

- [ ] `sacctmgr show qos` 실행하여 현재 QoS 확인
- [ ] `sudo sacctmgr add qos moonlight` 실행
- [ ] QoS 파라미터 설정 (GraceTime, MaxWall, MaxTRESPerUser)
- [ ] `sacctmgr show qos moonlight` 실행하여 설정 확인
- [ ] Test Job 제출 (`sbatch /tmp/test_moonlight_qos.sh`)
- [ ] Job QoS 확인 (`scontrol show job <JOBID> | grep QOS`)
- [ ] Job 로그 확인 (QoS=moonlight 출력 확인)
- [ ] `sacct --qos=moonlight` 실행하여 통계 확인

**완료 시**: Phase 3 (Backend 설치)로 진행

---

## 📝 참고 자료

### Slurm QoS 문서
- [Slurm QoS Documentation](https://slurm.schedmd.com/qos.html)
- [sacctmgr Manual](https://slurm.schedmd.com/sacctmgr.html)

### QoS 파라미터 설명

| 파라미터 | 설명 |
|----------|------|
| **GraceTime** | Job 종료 전 유예 시간 (scancel 시 SIGTERM → SIGKILL 사이 시간) |
| **MaxWall** | Job 최대 실행 시간 (벽시계 시간) |
| **MaxTRESPerUser** | 사용자당 최대 TRES (Trackable RESources, 예: GPU) |
| **MaxTRESPerJob** | Job당 최대 TRES |
| **MaxJobsPerUser** | 사용자당 최대 동시 실행 Job 수 |
| **Priority** | 스케줄링 우선순위 (높을수록 먼저 실행) |

---

**현재 상태**: Phase 2 문서화 완료, 실제 QoS 생성은 sudo 권한 필요
