# 🚀 MPI + Apptainer 자동화 가이드

여러 노드에서 Apptainer로 감싼 MPI 프로그램을 실행하기 위한 완전 자동화 가이드

## 📋 목차

1. [빠른 시작](#빠른-시작)
2. [자동화 구조](#자동화-구조)
3. [설치 과정](#설치-과정)
4. [이미지 관리](#이미지-관리)
5. [Job 제출](#job-제출)
6. [문제 해결](#문제-해결)

---

## 🎯 빠른 시작

### 전체 자동 설치 (원클릭!)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation
source venv/bin/activate
chmod +x setup_cluster_full.sh
./setup_cluster_full.sh
```

---

## 🏗️ 자동화 구조

```
Controller (smarttwincluster)
├── /share/apptainer/images/          # 중앙 저장소 (느림)
│   └── *.sif

Compute Nodes (node1, node2)
├── /scratch/apptainer/images/        # 로컬 캐시 (빠름!)
│   └── *.sif (자동 동기화)
```

**장점:**
- 🚀 로컬 scratch에서 직접 읽음 (네트워크 I/O 제로)
- 🔄 자동 동기화 (매일 03:00 cron)
- 💾 각 노드가 독립적으로 이미지 보유

---

## 🔧 설치 과정

### 1. 설정 파일 자동 수정
```bash
python3 fix_config.py
```
- ✅ compute_nodes 중복 제거
- ✅ Apptainer 활성화
- ✅ MPI 지원 추가
- ✅ 이미지 경로 설정

### 2. MPI 라이브러리 설치
```bash
python3 install_mpi.py
```
- ✅ 모든 노드에 OpenMPI 설치
- ✅ 환경변수 자동 설정

### 3. Apptainer 이미지 동기화
```bash
python3 sync_apptainer_images.py
```
- ✅ 디렉토리 생성
- ✅ 이미지 rsync 복사
- ✅ 자동 동기화 cron 설정

---

## 📦 이미지 관리

### 명령어 모음

```bash
# 이미지 목록 조회
python3 manage_images.py list

# 이미지 업로드
python3 manage_images.py upload myapp.sif

# 이미지 동기화
python3 manage_images.py sync

# 이미지 삭제
python3 manage_images.py delete myapp.sif

# Scratch 정리
python3 manage_images.py clean
```

### 수동 업로드

```bash
# 중앙 저장소에 업로드
scp myapp.sif koopark@smarttwincluster:/share/apptainer/images/

# 계산 노드로 동기화
python3 sync_apptainer_images.py
```

---

## 🚀 Job 제출

### 기본 사용법

```bash
sbatch job_templates/submit_mpi_apptainer.sh <image.sif> <program> [args...]
```

### 예시

```bash
# 1. 간단한 테스트
sbatch job_templates/submit_mpi_apptainer.sh ubuntu.sif /bin/bash -c "hostname"

# 2. MPI 프로그램
sbatch job_templates/submit_mpi_apptainer.sh mpi-app.sif /usr/bin/myprogram --input data.txt

# 3. Python 스크립트
sbatch job_templates/submit_mpi_apptainer.sh python3.sif python3 /home/user/script.py
```

### Job 모니터링

```bash
# 작업 상태
squeue

# 로그 확인
tail -f mpi_apptainer_*.out

# 작업 취소
scancel <job_id>
```

---

## 🐛 문제 해결

### 이미지를 찾을 수 없음
```bash
python3 manage_images.py list
python3 manage_images.py upload myapp.sif
```

### MPI 실행 오류
```bash
python3 install_mpi.py
ssh node1 'mpirun --version'
```

### 동기화 실패
```bash
ssh node1 'which rsync'
python3 sync_apptainer_images.py
```

---

## 🎓 Best Practices

1. **항상 로컬 이미지 사용**: scratch의 이미지가 훨씬 빠름
2. **정기적 동기화**: 매일 자동 동기화되지만 수동으로도 가능
3. **이미지 크기 최소화**: 필요한 패키지만 포함
4. **테스트 먼저**: 작은 Job으로 먼저 테스트

---

## 📞 도움말

- **전체 문서**: README.md
- **Job 템플릿**: job_templates/
- **로그 확인**: logs/

---

**Happy Computing!** 🎉
