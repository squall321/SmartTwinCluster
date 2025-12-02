# 🎯 전체 실행 순서 가이드

## 📌 현재 상황
- 이미 Slurm이 설치되어 있음
- Dashboard backend에서 Slurm 명령어 경로 문제 발생
- 해결 완료: slurm_commands.py 모듈 생성

---

## 🔄 실행 순서 옵션

### 옵션 1: Dashboard만 재시작 (가장 빠름) ⭐ 추천

```bash
# 1. Dashboard 디렉토리로 이동
cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard

# 2. Backend 재시작 (Production 모드)
chmod +x restart_backend_production.sh
./restart_backend_production.sh

# 3. 로그 확인
tail -f backend.log

# 4. 브라우저에서 확인
# http://localhost:3010
```

**소요 시간**: 1-2분  
**상황**: Dashboard만 문제가 있을 때

---

### 옵션 2: Slurm 클러스터 재시작 (전체 재시작)

```bash
# 위치: /home/koopark/claude/KooSlurmInstallAutomation

# 1. 클러스터 중지
./stop_slurm_cluster.sh

# 2. 클러스터 시작
./start_slurm_cluster.sh

# 3. 상태 확인
sinfo
sinfo -N

# 4. Dashboard 시작 (Production 모드)
cd dashboard
./restart_backend_production.sh
```

**소요 시간**: 3-5분  
**상황**: Slurm 서비스 자체에 문제가 있을 때

---

### 옵션 3: 처음부터 전체 설정 (완전 재설치)

```bash
# 위치: /home/koopark/claude/KooSlurmInstallAutomation

# 1. 환경 설정 (이미 했다면 스킵)
source venv/bin/activate

# 2. 설정 파일 준비 (이미 있다면 스킵)
# my_cluster.yaml 파일이 있는지 확인
ls -la my_cluster.yaml

# 3. Slurm 설치 (이미 설치되어 있다면 스킵)
./install_slurm.py -c my_cluster.yaml

# 4. 클러스터 시작
./start_slurm_cluster.sh

# 5. Dashboard 시작
cd dashboard
./restart_backend_production.sh
```

**소요 시간**: 10-30분 (설치 상태에 따라)  
**상황**: 처음 설치하거나 완전히 재설치할 때

---

## 🎯 당신의 상황에 맞는 선택

### 상황 1: "Dashboard 에러만 해결하고 싶어요" ✅
→ **옵션 1 사용** (가장 빠름, 1-2분)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard
./restart_backend_production.sh
```

### 상황 2: "Slurm 서비스가 안 돌아가요"
→ **옵션 2 사용** (3-5분)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation
./stop_slurm_cluster.sh
./start_slurm_cluster.sh
```

### 상황 3: "처음부터 다시 하고 싶어요"
→ **옵션 3 사용** (10-30분)

---

## 📋 명령어 단축키 (Alias) 등록

찾으시던 것이 이거였나요?

### 방법 1: 현재 세션만

```bash
# Slurm 명령어 경로 추가
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH

# 테스트
sinfo
squeue
```

### 방법 2: 영구 등록 (자동으로 이미 되어있음)

이미 설치 시 `/etc/profile.d/slurm.sh` 파일이 생성되어 있습니다:

```bash
# 확인
cat /etc/profile.d/slurm.sh

# 새 터미널에서 자동으로 로드됨
# 현재 터미널에서 즉시 적용하려면:
source /etc/profile.d/slurm.sh
```

### 방법 3: 개인 별칭 추가

```bash
# ~/.bashrc 또는 ~/.bash_profile에 추가
nano ~/.bashrc

# 다음 내용 추가:
# Slurm aliases
alias sinfo='/usr/local/slurm/bin/sinfo'
alias squeue='/usr/local/slurm/bin/squeue'
alias sbatch='/usr/local/slurm/bin/sbatch'
alias scancel='/usr/local/slurm/bin/scancel'
alias scontrol='/usr/local/slurm/bin/scontrol'

# Quick cluster commands
alias start-cluster='cd /home/koopark/claude/KooSlurmInstallAutomation && ./start_slurm_cluster.sh'
alias stop-cluster='cd /home/koopark/claude/KooSlurmInstallAutomation && ./stop_slurm_cluster.sh'
alias cluster-status='sinfo && echo && squeue'

# Dashboard commands
alias start-dashboard='cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard && ./start_all.sh'
alias stop-dashboard='cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard && ./stop_all.sh'

# 적용
source ~/.bashrc
```

이제 다음과 같이 사용 가능:
```bash
start-cluster      # 클러스터 시작
stop-cluster       # 클러스터 중지
cluster-status     # 상태 확인
start-dashboard    # Dashboard 시작
stop-dashboard     # Dashboard 중지
```

---

## 🔍 현재 상태 확인

```bash
# Slurm 서비스 상태
sudo systemctl status slurmctld

# 노드 상태
sinfo
sinfo -N

# Dashboard 상태
cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard
lsof -i :5010  # Backend
lsof -i :3010  # Frontend

# 로그 확인
tail -f backend.log
```

---

## 💡 당신이 찾던 명령어

기억하시는 명령어가 이것이었나요?

```bash
# 클러스터 설정 파일로 시작
./start_slurm_cluster.sh my_cluster.yaml
```

**하지만 실제로는:**
```bash
# 설치 시에만 yaml 사용
./install_slurm.py -c my_cluster.yaml

# 시작은 그냥
./start_slurm_cluster.sh  # yaml 파일 필요 없음
```

---

## ✅ 체크리스트

현재 상황 점검:

- [ ] Slurm이 이미 설치되어 있음
- [ ] sinfo, squeue 등 명령어가 작동함
- [ ] Dashboard backend에서 에러 발생
- [ ] slurm_commands.py로 수정 완료
- [ ] 이제 backend 재시작만 하면 됨

**다음 할 일:**
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard
./restart_backend_production.sh
```

---

## 📚 관련 문서

| 문서 | 내용 |
|------|------|
| `START_HERE.md` | 처음 시작 가이드 |
| `QUICKSTART.md` | 5분 빠른 시작 |
| `QUICK_REFERENCE.md` | 빠른 참조 가이드 ⭐ |
| `SLURM_PATH_GUIDE.md` | 명령어 경로 설정 |
| `dashboard/QUICK_START_PRODUCTION.md` | Dashboard 시작 가이드 ⭐ NEW |
| `dashboard/SLURM_PATH_FIX.md` | 방금 수정한 문제 상세 ⭐ NEW |

---

**선택하세요:**

1. **Dashboard만 고치기** (1분) → 옵션 1
2. **Slurm 재시작** (5분) → 옵션 2  
3. **처음부터** (30분) → 옵션 3

**당신의 상황은 옵션 1입니다!** ✅

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard
./restart_backend_production.sh
```
