# 📊 install_slurm_cgroup_v2.sh 참조 구조

## 🎯 요약

`install_slurm_cgroup_v2.sh`는 **여러 곳에서 참조**됩니다!

---

## 📁 참조하는 스크립트들

### 1. **setup_cluster_full.sh** ⭐ 메인 통합 스크립트
```bash
# Step 6: Slurm 23.11.x + cgroup v2 설치 (컨트롤러)
chmod +x install_slurm_cgroup_v2.sh
sudo bash install_slurm_cgroup_v2.sh
```

**위치**: `/home/koopark/claude/KooSlurmInstallAutomation/setup_cluster_full.sh`  
**역할**: 11단계 통합 설치 스크립트 (Munge + Slurm + MPI + 설정)

---

### 2. **full_install_cgroup_v2.sh** ⭐ 완전 자동화
```bash
# Step 1: 컨트롤러에 Slurm 설치
chmod +x install_slurm_cgroup_v2.sh
sudo bash install_slurm_cgroup_v2.sh

# Step 2: 계산 노드에 Slurm 설치
for node in "${COMPUTE_NODES[@]}"; do
    scp install_slurm_cgroup_v2.sh ${SSH_USER}@${node}:/tmp/
    ssh ${SSH_USER}@${node} "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"
done
```

**위치**: `/home/koopark/claude/KooSlurmInstallAutomation/full_install_cgroup_v2.sh`  
**역할**: 컨트롤러 + 모든 계산 노드 자동 설치

---

### 3. **기타 유사 스크립트들**

#### install_slurm_binary.sh
- 이전 버전 (Slurm 23.02.7)
- **cgroup v2 지원 없음**
- install_slurm.py에서 호출됨

#### install_full_cgroup_v2.sh
- `full_install_cgroup_v2.sh`와 동일한 역할
- 아마도 이름이 비슷해서 중복된 것으로 보임

---

## 🔍 중요한 차이점

### install_slurm_cgroup_v2.sh ✅ (최신, 추천)
- **Slurm 23.11.10** (최신)
- **cgroup v2 완전 지원**
- `--with-systemd` 옵션으로 컴파일
- `/etc/profile.d/slurm.sh` 자동 생성 ⭐

### install_slurm_binary.sh ❌ (구버전)
- **Slurm 23.02.7** (오래됨)
- cgroup v2 지원 없음
- 기본 설치만

---

## 📋 설치 순서 (권장)

### 옵션 A: 통합 설치 (가장 간단) ⭐
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# 1단계: 통합 스크립트 실행 (모든 것 포함)
./setup_cluster_full.sh
```

**포함 내용:**
1. 설정 파일 확인
2. 가상환경 활성화
3. 설정 검증
4. SSH 연결 테스트
5. ✅ **Munge 설치**
6. ✅ **Slurm 23.11.x 설치** (`install_slurm_cgroup_v2.sh` 호출)
7. ✅ **계산 노드 설치**
8. ✅ **설정 파일 생성**
9. ✅ **설정 파일 배포**
10. ✅ **서비스 시작**
11. MPI 설치 (선택)

---

### 옵션 B: 완전 자동화 (빠른 설치)
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# Slurm만 빠르게 설치
./full_install_cgroup_v2.sh
```

**포함 내용:**
- 컨트롤러 Slurm 설치
- 모든 계산 노드 Slurm 설치
- 설정 파일 생성 및 배포
- 서비스 시작

---

### 옵션 C: 수동 단계별 설치
```bash
# 1. 컨트롤러만 설치
sudo bash install_slurm_cgroup_v2.sh

# 2. 계산 노드에 복사 및 설치
scp install_slurm_cgroup_v2.sh koopark@192.168.122.90:/tmp/
ssh koopark@192.168.122.90 "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"

# 3. 설정 파일 생성
sudo bash configure_slurm_cgroup_v2.sh

# 4. 설정 배포
./sync_config_to_nodes.sh

# 5. 서비스 시작
./start_slurm_cluster.sh
```

---

## 🚨 중요: 수정하면 안 되는 이유

`install_slurm_cgroup_v2.sh`는 **핵심 설치 스크립트**이며:

### 1. 여러 곳에서 참조됨
- `setup_cluster_full.sh`
- `full_install_cgroup_v2.sh`
- 수동 설치 가이드

### 2. 중요한 작업 수행
- Slurm 23.11.10 다운로드 및 컴파일
- cgroup v2 지원 활성화 (`--with-systemd`)
- **`/etc/profile.d/slurm.sh` 자동 생성** ⭐
- 환경 변수 설정

### 3. 수정 대신 사용할 것
- PATH 문제 → `/etc/profile.d/slurm.sh` 이미 생성됨
- Dashboard 문제 → `slurm_commands.py` 모듈 사용

---

## ✅ 결론

### 당신의 상황:
1. ✅ Slurm은 이미 설치되어 있음
2. ✅ `/etc/profile.d/slurm.sh`도 이미 생성되어 있음
3. ❌ Dashboard backend에서만 경로 문제

### 해결 방법:
```bash
# install_slurm_cgroup_v2.sh는 그대로 두고
# Dashboard만 수정된 코드로 재시작
cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard
./restart_backend_production.sh
```

---

## 🔗 관련 파일 구조

```
KooSlurmInstallAutomation/
├── install_slurm_cgroup_v2.sh      # 핵심 설치 스크립트 ⭐
│   └── /etc/profile.d/slurm.sh 생성
│
├── setup_cluster_full.sh           # 통합 설치 (11단계)
│   └── install_slurm_cgroup_v2.sh 호출
│
├── full_install_cgroup_v2.sh       # 완전 자동화
│   └── install_slurm_cgroup_v2.sh 호출
│
├── configure_slurm_cgroup_v2.sh    # 설정 파일 생성
├── sync_config_to_nodes.sh         # 설정 배포
├── start_slurm_cluster.sh          # 서비스 시작
├── stop_slurm_cluster.sh           # 서비스 중지
│
└── dashboard/
    ├── backend/
    │   ├── slurm_commands.py       # 새로 생성 ⭐
    │   └── app.py                  # 수정됨 ⭐
    └── restart_backend_production.sh  # 재시작 스크립트 ⭐
```

---

## 📝 요약

**Q: install_slurm_cgroup_v2.sh가 다른 곳에서 참조되는가?**  
**A: 네, 최소 2개의 메인 스크립트에서 참조됩니다:**
1. `setup_cluster_full.sh` (통합 설치)
2. `full_install_cgroup_v2.sh` (완전 자동화)

**Q: 수정해야 하나?**  
**A: 아니요! 그대로 두세요.**
- Slurm 설치는 이미 완료
- `/etc/profile.d/slurm.sh`도 이미 생성됨
- Dashboard 문제는 `slurm_commands.py`로 해결

**Q: 지금 뭘 해야 하나?**  
**A: Dashboard backend만 재시작!**
```bash
cd dashboard
./restart_backend_production.sh
```

---

작성일: 2025-10-08 18:30 KST
