# 🚀 LS-DYNA Job Templates - 빠른 시작 가이드

## ✅ 설치 및 설정

### 1단계: 실행 권한 부여

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation/job_templates

# 모든 스크립트에 실행 권한 부여
chmod +x *.sh
```

### 2단계: 라이선스 서버 설정

각 스크립트 파일에서 라이선스 서버 IP를 수정하세요:

```bash
# 모든 submit_lsdyna_*.sh 파일에서
export LSTC_LICENSE_SERVER=10.0.0.1  # ← 실제 라이선스 서버 IP로 변경

# 일괄 변경
sed -i 's/10.0.0.1/실제IP주소/g' submit_lsdyna_*.sh
```

### 3단계: PATH 설정 (선택사항)

```bash
# ~/.bashrc 또는 ~/.bash_profile에 추가
export PATH=$PATH:/home/koopark/claude/KooSlurmInstallAutomation/job_templates

# 적용
source ~/.bashrc
```

---

## 🎯 사용법

### 기본 명령어

```bash
./lsdyna_submit.sh <작업타입> <K파일> [옵션]
```

### 작업 타입

| 타입 | 설명 | 리소스 |
|------|------|--------|
| `basic` | 기본 단일 노드 | 1노드, 16코어, 32GB |
| `mpi` | MPI 병렬 | 4노드, 64코어, 128GB |
| `gpu` | GPU 가속 | 1노드, 2GPU, 64GB |
| `restart` | 재시작 | 1노드, 32코어, 64GB |
| `custom` | 사용자 정의 | 사용자 지정 |

---

## 📋 실전 예시

### 예시 1: 간단한 충돌 해석 (16 cores)

```bash
# K 파일 준비
cd ~/my_analysis
ls input.k  # K 파일 확인

# 작업 제출
/home/koopark/claude/KooSlurmInstallAutomation/job_templates/lsdyna_submit.sh \
    basic input.k

# 결과
# Submitted batch job 12345
```

**작업 흐름:**
1. `/scratch/username/12345/` 에서 계산 실행
2. 계산 완료 후 자동으로 `/Data/home/username/12345/`로 결과 이동
3. Scratch 디렉토리 자동 삭제

---

### 예시 2: 대규모 MPI 병렬 해석 (64 cores)

```bash
# 대규모 모델 준비
cd ~/large_model
ls main.k include*.k  # 메인 K 파일과 Include 파일들

# MPI 병렬 제출
lsdyna_submit.sh mpi main.k

# 작업 상태 확인
squeue -u $(whoami)

# 실시간 로그 확인
tail -f lsdyna_mpi_12346.out
```

**MPI 최적화:**
- 4개 노드에 분산 실행
- 노드당 16코어 자동 바인딩
- NUMA 인터리브 메모리 정책 적용
- 소켓별 프로세스 매핑

---

### 예시 3: GPU 가속 암시적 해석

```bash
# 암시적 해석 K 파일 준비
cd ~/implicit_analysis
ls forming_implicit.k

# GPU 작업 제출
lsdyna_submit.sh gpu forming_implicit.k

# GPU 사용률 확인 (작업 실행 중)
ssh node-with-gpu
nvidia-smi
```

**GPU 설정:**
- 2개 GPU 자동 할당
- CUDA 메모리 최적화
- CPU 8개와 협업

---

### 예시 4: 장시간 해석 재시작

```bash
# 1. 초기 작업 제출
lsdyna_submit.sh basic longrun.k
# Job ID: 10001

# 2. 작업이 24시간 제한으로 종료됨
# 결과는 /Data/home/username/10001/ 에 저장됨

# 3. d3dump 파일 확인
ls /Data/home/$(whoami)/10001/d3dump*

# 4. 재시작 작업 제출
lsdyna_submit.sh restart longrun.k --restart-from 10001
# Job ID: 10002 (새 작업)

# 5. 재시작 작업은 10001의 d3dump에서 계속 진행
```

**자동 처리:**
- 이전 Job 결과에서 d3dump 파일 자동 복사
- 재시작 옵션(`r=d3dump`) 자동 설정
- 새로운 Job ID로 계속 실행

---

### 예시 5: 사용자 정의 (고메모리, 장시간)

```bash
# 메모리 집약적 해석
lsdyna_submit.sh custom high_memory.k \
    -n 2 \
    -c 64 \
    -p normal \
    -q normal_qos \
    -t 96:00:00 \
    -m 512 \
    -j "HighMemory_Analysis_v2"

# 제출된 작업 확인
squeue -u $(whoami)

# 작업 상세 정보
scontrol show job <job_id>
```

**Custom 옵션:**
- `-n 2`: 2개 노드
- `-c 64`: 64개 코어
- `-m 512`: 512GB 메모리
- `-t 96:00:00`: 96시간 실행

---

## 🔍 작업 모니터링

### 작업 상태 확인

```bash
# 내 작업 목록
squeue -u $(whoami)

# 출력 예시:
#  JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
#  12345    normal lsdyna_b username  R       1:23      1 node001
#  12346    normal lsdyna_m username PD       0:00      4 (Resources)

# ST (Status):
#   R  = Running (실행 중)
#   PD = Pending (대기 중)
#   CG = Completing (완료 중)
```

### 실시간 로그 확인

```bash
# 표준 출력 (계산 진행 상황)
tail -f lsdyna_basic_12345.out

# 에러 로그
tail -f lsdyna_basic_12345.err

# 로그 파일 검색
grep -i "error\|warning" lsdyna_basic_12345.out
```

### 작업 상세 정보

```bash
# 작업 상세
scontrol show job 12345

# 노드 정보
sinfo -N

# 파티션 정보
sinfo -p normal
```

---

## 🎮 작업 제어

### 작업 취소

```bash
# 특정 작업 취소
scancel 12345

# 내 모든 작업 취소
scancel -u $(whoami)

# 특정 이름의 작업 취소
scancel --name=lsdyna_basic
```

### 작업 일시 중지/재개

```bash
# 작업 일시 중지
scontrol hold 12345

# 작업 재개
scontrol release 12345

# 우선순위 변경 (관리자 권한 필요)
scontrol update job=12345 priority=1000
```

---

## 📂 결과 관리

### 결과 확인

```bash
# Job ID가 12345인 경우
cd /Data/home/$(whoami)/12345

# 결과 파일 목록
ls -lh

# 주요 결과 파일:
#   d3plot, d3plot01, d3plot02, ...  (시각화 데이터)
#   d3thdt                           (시간 이력 데이터)
#   messag                           (메시지 파일)
#   d3dump                           (재시작 파일)
#   input.k                          (입력 파일 사본)
```

### 결과 다운로드

```bash
# 1. 압축
cd /Data/home/$(whoami)/12345
tar -czf results_12345.tar.gz *

# 2. 로컬로 다운로드 (별도 터미널)
scp user@hpc-server:/Data/home/user/12345/results_12345.tar.gz ~/Downloads/

# 3. 또는 rsync 사용
rsync -avz --progress \
    user@hpc-server:/Data/home/user/12345/ \
    ~/Downloads/job_12345/
```

### 디스크 사용량 확인

```bash
# 특정 Job 결과 크기
du -sh /Data/home/$(whoami)/12345

# 모든 작업 결과 크기
du -sh /Data/home/$(whoami)/*

# 큰 파일 찾기
find /Data/home/$(whoami)/12345 -type f -size +1G -exec ls -lh {} \;
```

---

## ⚙️ 고급 활용

### Include 파일이 많은 경우

```bash
# 모든 .k 파일이 자동으로 복사됨
cd ~/my_model
ls *.k
# main.k
# include_material.k
# include_contact.k
# include_boundary.k

# 제출 (모든 .k 파일 자동 복사)
lsdyna_submit.sh basic main.k
```

### 배치 작업 제출

```bash
# 여러 케이스 자동 제출
for case in case1.k case2.k case3.k; do
    lsdyna_submit.sh basic $case
    sleep 1  # 1초 대기
done

# 또는 스크립트 작성
cat > submit_all.sh << 'EOF'
#!/bin/bash
for i in {1..10}; do
    lsdyna_submit.sh basic case_${i}.k -j "Case_${i}"
done
EOF

chmod +x submit_all.sh
./submit_all.sh
```

### 의존성 작업 (Sequential Jobs)

```bash
# 1. 첫 번째 작업 제출
JOB1=$(sbatch submit_lsdyna_basic.sh input1.k | awk '{print $4}')
echo "Job 1 ID: $JOB1"

# 2. 첫 번째 작업 완료 후 실행되는 두 번째 작업
sbatch --dependency=afterok:$JOB1 submit_lsdyna_basic.sh input2.k

# 3. 재시작 작업도 의존성으로
sbatch --dependency=afterok:$JOB1 \
    submit_lsdyna_restart.sh input1.k $JOB1
```

---

## 🐛 문제 해결

### 문제 1: "K 파일을 찾을 수 없습니다"

```bash
# 해결 방법:
# 1. 현재 디렉토리 확인
pwd
ls -la *.k

# 2. 절대 경로 사용
lsdyna_submit.sh basic /full/path/to/input.k

# 3. 파일 이름 확인 (대소문자 구분)
ls -la Input.k input.k INPUT.K
```

### 문제 2: "작업이 Pending 상태"

```bash
# 원인 확인
squeue -u $(whoami)
# NODELIST(REASON) 열 확인

# 주요 원인:
# - Resources: 리소스 대기 중 (정상)
# - Priority: 우선순위 낮음
# - QOSMaxCpuPerUserLimit: QoS 코어 제한 초과
# - PartitionNodeLimit: 파티션 노드 제한

# 해결: 리소스 줄여서 재제출
lsdyna_submit.sh custom input.k -n 1 -c 8
```

### 문제 3: "Out of Memory 에러"

```bash
# 에러 로그 확인
grep -i "memory\|oom" lsdyna_*.err

# 해결: 더 많은 메모리로 재제출
lsdyna_submit.sh custom input.k \
    -n 1 -c 16 -m 128  # 128GB 메모리
```

### 문제 4: "라이선스 에러"

```bash
# 라이선스 서버 연결 확인
ping 라이선스서버IP

# 환경변수 확인
echo $LSTC_LICENSE_SERVER

# 라이선스 서버 IP 수정
vi submit_lsdyna_basic.sh
# export LSTC_LICENSE_SERVER=올바른IP
```

### 문제 5: "d3dump 파일이 없습니다"

```bash
# 이전 작업 결과 확인
ls /Data/home/$(whoami)/<previous_job_id>/

# d3dump 파일 확인
ls /Data/home/$(whoami)/<previous_job_id>/d3dump*

# 파일이 없으면: 이전 작업에서 생성 안 됨
# 해결: 이전 작업의 K 파일에 d3dump 출력 설정 추가
```

---

## 📊 리소스 선택 가이드

### 모델 크기별 권장 사항

| 모델 크기 | 요소 수 | 권장 타입 | 코어 수 | 예상 시간 |
|-----------|---------|-----------|---------|-----------|
| 소규모 | < 100K | basic | 16 | < 2시간 |
| 중규모 | 100K - 1M | basic 또는 custom(32) | 16-32 | 2-12시간 |
| 대규모 | 1M - 10M | mpi | 64-128 | 12-48시간 |
| 초대규모 | > 10M | custom(고사양) | 128+ | 48시간+ |

### 해석 타입별 권장

| 해석 타입 | 권장 작업 | 특징 |
|-----------|-----------|------|
| 충돌/낙하 (명시적) | basic 또는 mpi | CPU 병렬화 효과 좋음 |
| 성형 (암시적) | gpu | GPU 가속 효과 큼 |
| 피로/준정적 | basic 또는 gpu | 장시간 실행, GPU 효율적 |
| 유체-구조 연성 | mpi | 메모리 많이 필요 |

---

## 📞 지원 및 문의

### 로그 정보 수집

문제 발생 시 다음 정보를 수집하세요:

```bash
# 1. Job ID
echo "Job ID: 12345"

# 2. 출력 로그
cat lsdyna_12345.out

# 3. 에러 로그
cat lsdyna_12345.err

# 4. 작업 정보
scontrol show job 12345

# 5. 시스템 정보
sinfo -N
```

---

## 🎓 추가 자료

### LS-DYNA 참고 자료
- [LS-DYNA 공식 매뉴얼](https://www.lstc.com/download/manuals)
- [LS-DYNA 키워드 매뉴얼](https://www.lstc.com/products/ls-dyna)

### Slurm 참고 자료
- [Slurm 공식 문서](https://slurm.schedmd.com/)
- [sbatch 매뉴얼](https://slurm.schedmd.com/sbatch.html)

---

**버전**: 1.0.0  
**최종 업데이트**: 2025-01-10  
**작성**: KooSlurmInstallAutomation Team

**Happy Computing! 🚀**
