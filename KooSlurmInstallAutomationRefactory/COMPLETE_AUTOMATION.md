# 🚀 Slurm 완전 자동 설치 - 최종 완성판

## 🎯 추가된 완전 자동화 기능

### ✅ 새로 추가된 스크립트

1. **`complete_slurm_setup.py`** - Slurm 완전 자동 설정
   - SSH 키 자동 설정 (패스워드 없는 로그인)
   - 방화벽 자동 설정 (필수 포트 개방)
   - SELinux 자동 설정
   - NTP 시간 동기화
   - 필수 패키지 일괄 설치
   - **Munge 인증 자동 설정** (핵심!)
   - **NFS 공유 스토리지 자동 설정**
   - **slurm.conf 자동 생성**
   - cgroup 자동 설정
   - 환경변수 자동 설정

2. **`check_installation.py`** - 설치 완료 여부 체크
   - 10가지 항목 자동 검증
   - 상세한 오류 메시지
   - 해결 방법 제시

3. **`setup_cluster_full.sh`** - 통합 실행 스크립트 (개선판)
   - 8단계 완전 자동 설치
   - 각 단계별 선택 가능

---

## 🔧 이전에 누락되었던 필수 구성 요소

### 1. SSH 키 자동 설정 ✅
**문제**: 노드 간 패스워드 없는 SSH 로그인 필요  
**해결**: `complete_slurm_setup.py`에서 자동 처리
- SSH 키 자동 생성
- 모든 노드에 공개키 배포
- authorized_keys 자동 설정

### 2. Munge 인증 설정 ✅
**문제**: Slurm 노드 간 인증 필수  
**해결**: 자동 Munge 키 생성 및 배포
- 컨트롤러에서 Munge 키 생성
- 모든 노드에 동일한 키 배포
- Munge 서비스 자동 시작
- 상호 인증 검증

### 3. NFS 공유 스토리지 ✅
**문제**: /home, /share 디렉토리 공유 필요  
**해결**: 자동 NFS 서버/클라이언트 설정
- 컨트롤러를 NFS 서버로 설정
- /etc/exports 자동 생성
- 계산 노드에서 자동 마운트
- /etc/fstab에 자동 추가

### 4. slurm.conf 생성 ✅
**문제**: Slurm 설정 파일 수동 작성 복잡  
**해결**: YAML 설정에서 자동 생성
- 노드 정보 자동 추출
- 파티션 자동 설정
- 모든 노드에 자동 배포

### 5. 방화벽 설정 ✅
**문제**: Slurm 포트 수동 개방 필요  
**해결**: 자동 방화벽 규칙 설정
- slurmctld (6817)
- slurmd (6818)
- slurmdbd (6819)
- SSH (22)

### 6. 시간 동기화 ✅
**문제**: 노드 간 시간 불일치  
**해결**: NTP 자동 설정
- systemd-timesyncd (Ubuntu)
- chrony (CentOS)
- 타임존 자동 설정

### 7. cgroup 설정 ✅
**문제**: 리소스 제한 설정 필요  
**해결**: cgroup.conf 자동 생성
- CPU 제한
- 메모리 제한
- 자동 마운트

### 8. 환경변수 ✅
**문제**: PATH, LD_LIBRARY_PATH 설정 필요  
**해결**: /etc/profile.d 스크립트 자동 생성
- Slurm 바이너리 경로
- 라이브러리 경로
- 맨페이지 경로

---

## 🚀 완전 자동 설치 가이드

### 원클릭 설치 (권장!)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# 1. 권한 설정
chmod +x *.py *.sh job_templates/*.sh

# 2. 가상환경 활성화
source venv/bin/activate

# 3. 완전 자동 설치 실행
./setup_cluster_full.sh
```

**이 명령어 하나로 모든 것이 자동으로 설치됩니다!**

### 단계별 설명

#### Step 1: 설정 파일 자동 수정
```bash
python3 fix_config.py
```
- compute_nodes 중복 제거
- Apptainer, MPI 활성화
- 이미지 경로 설정

#### Step 2-4: 기본 검증
```bash
python3 validate_config.py my_cluster.yaml
python3 test_connection.py my_cluster.yaml
```

#### Step 5: Slurm 완전 자동 설정 (핵심!)
```bash
python3 complete_slurm_setup.py
```
**10가지 필수 구성 요소 자동 설정**

#### Step 6: Slurm + Apptainer 설치
```bash
python3 install_slurm.py -c my_cluster.yaml --stage 3
```

#### Step 7: MPI 설치
```bash
python3 install_mpi.py
```

#### Step 8: 이미지 동기화
```bash
python3 sync_apptainer_images.py
```

---

## 🔍 설치 완료 검증

```bash
python3 check_installation.py
```

**출력 예시:**
```
================================================================================
🔍 Slurm 설치 완료 여부 체크
================================================================================

📌 SSH 연결 체크 중...
  ✅ smarttwincluster: SSH 연결 정상
  ✅ node1: SSH 연결 정상
  ✅ node2: SSH 연결 정상
✅ SSH 연결: 통과

📌 Munge 인증 체크 중...
  ✅ smarttwincluster: Munge 인증 정상
  ✅ node1: Munge 인증 정상
  ✅ node2: Munge 인증 정상
✅ Munge 인증: 통과

... (중략) ...

================================================================================
📊 체크 결과 요약
================================================================================

통과: 10/10
실패: 0/10

🎉 모든 체크 통과! Slurm 클러스터가 완전히 설치되었습니다!
```

---

## 📋 설치 후 작업

### 1. Slurm 서비스 시작

```bash
# 컨트롤러
ssh smarttwincluster 'sudo systemctl start slurmctld'
ssh smarttwincluster 'sudo systemctl enable slurmctld'

# 계산 노드
ssh node1 'sudo systemctl start slurmd'
ssh node1 'sudo systemctl enable slurmd'

ssh node2 'sudo systemctl start slurmd'
ssh node2 'sudo systemctl enable slurmd'
```

### 2. 클러스터 상태 확인

```bash
sinfo
sinfo -N
scontrol show nodes
```

**정상 출력:**
```
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up 7-00:00:00      2   idle node[1-2]
debug        up   00:30:00      1   idle node1
```

### 3. Apptainer 이미지 업로드

```bash
# 방법 1: 관리 도구 사용
python3 manage_images.py upload myapp.sif

# 방법 2: 수동 업로드
scp myapp.sif koopark@smarttwincluster:/share/apptainer/images/
python3 sync_apptainer_images.py
```

### 4. 테스트 Job 제출

```bash
# 간단한 테스트
sbatch job_templates/submit_mpi_apptainer.sh ubuntu.sif /bin/bash -c "hostname && date"

# 작업 확인
squeue
tail -f mpi_apptainer_*.out
```

---

## 🐛 문제 해결

### 설치 실패시

```bash
# 1. 로그 확인
cat logs/slurm_install_*.log | grep -i error

# 2. 설치 체크
python3 check_installation.py

# 3. 특정 단계 재실행
python3 complete_slurm_setup.py

# 4. 전체 재설치
./setup_cluster_full.sh
```

### Munge 인증 실패

```bash
# Munge 재설정
python3 complete_slurm_setup.py

# 또는 수동으로
ssh smarttwincluster 'sudo systemctl restart munge'
ssh node1 'sudo systemctl restart munge'
ssh node2 'sudo systemctl restart munge'
```

### NFS 마운트 실패

```bash
# NFS 상태 확인
ssh smarttwincluster 'showmount -e'
ssh node1 'mount | grep nfs'

# 수동 마운트
ssh node1 'sudo mount -t nfs smarttwincluster:/export/home /home'
```

### Slurm 서비스 시작 실패

```bash
# 로그 확인
ssh smarttwincluster 'sudo journalctl -u slurmctld -n 50'
ssh node1 'sudo journalctl -u slurmd -n 50'

# 설정 파일 검증
ssh smarttwincluster 'slurmctld -C'
ssh node1 'slurmd -C'
```

---

## 📊 완성도 체크리스트

### 자동화된 항목 (10/10)

- [x] SSH 키 설정
- [x] 방화벽 설정
- [x] SELinux 설정
- [x] NTP 시간 동기화
- [x] 필수 패키지 설치
- [x] Munge 인증 설정
- [x] NFS 공유 스토리지
- [x] slurm.conf 생성
- [x] cgroup 설정
- [x] 환경변수 설정

### MPI + Apptainer 통합 (완료)

- [x] MPI 자동 설치
- [x] Apptainer 자동 설치
- [x] 이미지 중앙 저장소 설정
- [x] 이미지 로컬 캐시 자동 동기화
- [x] Job 템플릿 제공
- [x] 이미지 관리 도구

### 검증 및 문서화 (완료)

- [x] 설치 완료 체크 스크립트
- [x] 완전 가이드 문서
- [x] 문제 해결 가이드
- [x] 사용 예시

---

## 🎉 결론

### 이전 버전
- ❌ 수동 설정 필요 (20+ 단계)
- ❌ 누락된 구성 요소
- ❌ 복잡한 Munge 설정
- ❌ NFS 수동 설정
- ❌ slurm.conf 수동 작성

### 현재 버전 (완전판)
- ✅ **완전 자동 설치** (1 명령어)
- ✅ **모든 필수 구성 요소** 자동 설정
- ✅ **Munge 인증** 자동화
- ✅ **NFS 공유** 자동화
- ✅ **slurm.conf** 자동 생성
- ✅ **MPI + Apptainer** 통합
- ✅ **검증 도구** 포함

---

## 🚀 지금 바로 시작하세요!

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation
chmod +x *.py *.sh job_templates/*.sh
source venv/bin/activate
./setup_cluster_full.sh
```

**단 하나의 명령어로 완전한 Slurm 클러스터 구축!**

---

## 📞 추가 도구 및 명령어

```bash
# 설정 관리
python3 fix_config.py                          # 설정 수정
python3 validate_config.py my_cluster.yaml     # 검증

# 설치 및 검증
python3 complete_slurm_setup.py                # 완전 자동 설정
python3 check_installation.py                  # 설치 체크

# 이미지 관리
python3 manage_images.py list                  # 목록
python3 manage_images.py upload FILE           # 업로드
python3 manage_images.py sync                  # 동기화

# MPI 관리
python3 install_mpi.py                         # MPI 설치

# 클러스터 관리
sinfo                                          # 상태 확인
squeue                                         # 작업 확인
sbatch job_templates/submit_mpi_apptainer.sh   # Job 제출
```

---

**완료! 이제 모든 것이 자동화되었습니다!** 🎉
