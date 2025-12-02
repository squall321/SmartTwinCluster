# LS-DYNA R16 Job Templates

LS-DYNA R16을 위한 다양한 작업 제출 스크립트 템플릿 모음입니다.

## 📁 파일 구조

```
job_templates/
├── lsdyna_submit.sh              # 통합 작업 제출 관리자
├── submit_lsdyna_basic.sh        # 기본 단일 노드 해석
├── submit_lsdyna_mpi.sh          # MPI 다중 노드 병렬
├── submit_lsdyna_gpu.sh          # GPU 가속 해석
├── submit_lsdyna_restart.sh      # 재시작 해석
└── README.md                     # 이 파일
```

## 🎯 작업 타입

### 1. Basic (기본)
- **용도**: 소규모 모델, 빠른 테스트
- **리소스**: 1 노드, 16 코어, 32GB RAM
- **시간**: 24시간
- **NUMA**: Interleaved 메모리 정책

### 2. MPI (병렬)
- **용도**: 대규모 모델, 명시적 해석
- **리소스**: 4 노드, 64 코어 (16/노드), 128GB RAM
- **시간**: 48시간
- **최적화**: MPI binding + NUMA interleaved

### 3. GPU (가속)
- **용도**: 암시적 해석, 비선형 해석
- **리소스**: 1 노드, 8 CPU, 2 GPU, 64GB RAM
- **시간**: 72시간
- **GPU**: CUDA 가속

### 4. Restart (재시작)
- **용도**: 장시간 해석 재개, 계속 해석
- **리소스**: 1 노드, 32 코어, 64GB RAM
- **시간**: 48시간
- **요구사항**: 이전 Job ID 필요

### 5. Custom (사용자 정의)
- **용도**: 특수한 요구사항
- **리소스**: 사용자 지정
- **유연성**: 모든 파라미터 조정 가능

## 🚀 빠른 시작

### 기본 사용법

```bash
# 실행 권한 부여
chmod +x lsdyna_submit.sh

# 기본 해석 (16 cores)
./lsdyna_submit.sh basic input.k

# MPI 병렬 (64 cores)
./lsdyna_submit.sh mpi large_model.k

# GPU 해석
./lsdyna_submit.sh gpu implicit_analysis.k

# 재시작 해석
./lsdyna_submit.sh restart input.k --restart-from 12345

# 사용자 정의
./lsdyna_submit.sh custom input.k \
    -n 2 -c 32 -p normal -q normal_qos -t 48:00:00
```

### 도움말 및 목록

```bash
# 도움말 표시
./lsdyna_submit.sh --help

# 작업 타입 목록
./lsdyna_submit.sh --list
```

## 📋 상세 사용 예시

### 예시 1: 소규모 충돌 해석

```bash
./lsdyna_submit.sh basic crash_analysis.k
```

**결과:**
- Job ID: 자동 할당
- 작업 디렉토리: `/scratch/username/jobid`
- 결과 디렉토리: `/Data/home/username/jobid`

### 예시 2: 대규모 낙하 시뮬레이션

```bash
./lsdyna_submit.sh mpi drop_test_large.k
```

**특징:**
- 4개 노드에 분산 실행
- MPI 자동 바인딩
- NUMA 최적화 적용

### 예시 3: GPU를 사용한 암시적 해석

```bash
./lsdyna_submit.sh gpu forming_implicit.k
```

**GPU 설정:**
- 2개 GPU 자동 할당
- CUDA 메모리 최적화
- GPU 사용률 자동 모니터링

### 예시 4: 장시간 해석 재시작

```bash
# 이전 Job ID가 12345인 경우
./lsdyna_submit.sh restart longrun.k --restart-from 12345
```

**자동 처리:**
- 이전 작업 결과에서 d3dump 파일 자동 복사
- 재시작 옵션 자동 설정

### 예시 5: 특수 요구사항 (Custom)

```bash
./lsdyna_submit.sh custom special_case.k \
    -n 8 \
    -c 128 \
    -p high_priority \
    -q high_qos \
    -t 96:00:00 \
    -m 256 \
    -j "Special_Analysis"
```

## 🔧 고급 옵션

### 전체 옵션 목록

```
-n, --nodes N          노드 수
-c, --cores N          코어 수
-p, --partition NAME   파티션 (normal/gpu/high_priority)
-q, --qos NAME         QoS (normal_qos/gpu_qos/high_qos)
-t, --time HH:MM:SS    최대 실행 시간
-m, --mem SIZE         메모리 (GB 단위)
-g, --gpus N           GPU 수
-r, --restart-from ID  재시작할 Job ID
-j, --job-name NAME    작업 이름
```

### Custom 예시

#### 메모리 집약적 해석
```bash
./lsdyna_submit.sh custom memory_intensive.k \
    -n 1 -c 32 -m 512 -t 72:00:00
```

#### 고우선순위 긴급 해석
```bash
./lsdyna_submit.sh custom urgent.k \
    -n 2 -c 64 -p high_priority -q high_qos -t 12:00:00
```

## 📂 작업 디렉토리 구조

### 자동 생성되는 경로

```
작업 제출
  ↓
/scratch/username/jobid/          # 계산 중 (고속 스토리지)
  ├── input.k                      # 입력 K 파일
  ├── 기타 .k 파일들               # Include 파일
  └── LS-DYNA 실행
  ↓
계산 완료
  ↓
/Data/home/username/jobid/        # 결과 저장 (영구 스토리지)
  ├── input.k
  ├── d3plot, d3plot01, ...
  ├── d3thdt
  ├── messag
  └── 모든 결과 파일
  ↓
/scratch/username/jobid/          # 자동 삭제
```

### 디렉토리 특징

- **Scratch**: 고속 I/O, 임시 저장소
- **Data/home**: 영구 보관, 백업 대상
- **자동 정리**: Scratch는 작업 종료 후 자동 삭제

## 🔍 작업 모니터링

### 작업 상태 확인

```bash
# 내 작업 목록
squeue -u $(whoami)

# 특정 작업 상세 정보
scontrol show job <job_id>

# 작업 출력 확인
tail -f lsdyna_<job_id>.out

# 작업 에러 확인
tail -f lsdyna_<job_id>.err
```

### 작업 제어

```bash
# 작업 취소
scancel <job_id>

# 작업 일시 중지
scontrol hold <job_id>

# 작업 재개
scontrol release <job_id>
```

## 📊 결과 확인

### 결과 디렉토리 접근

```bash
# Job ID가 12345인 경우
cd /Data/home/$(whoami)/12345

# 결과 파일 목록
ls -lh

# d3plot 파일 확인
ls -lh d3plot*

# messag 파일 확인
tail messag
```

### 결과 다운로드

```bash
# 전체 결과 압축
cd /Data/home/$(whoami)/12345
tar -czf results_12345.tar.gz *

# 로컬로 다운로드 (scp)
scp user@server:/Data/home/user/12345/results_12345.tar.gz .
```

## ⚙️ 환경 설정

### LS-DYNA 라이선스 서버

각 스크립트의 라이선스 서버 IP를 수정하세요:

```bash
export LSTC_LICENSE_SERVER=10.0.0.1  # 실제 라이선스 서버 IP로 변경
```

### NUMA 설정

모든 스크립트는 NUMA 최적화를 적용합니다:

```bash
export OMP_NUM_THREADS=1
export OMP_PROC_BIND=true
export OMP_PLACES=cores
numactl --interleave=all LSDynaR16 ...
```

## 🐛 문제 해결

### Q1: "K 파일을 찾을 수 없습니다"
```bash
# 현재 디렉토리 확인
pwd
ls -la *.k

# 절대 경로 사용
./lsdyna_submit.sh basic /full/path/to/input.k
```

### Q2: "라이선스 에러"
```bash
# 라이선스 서버 확인
ping 10.0.0.1

# 환경변수 확인
echo $LSTC_LICENSE_SERVER
```

### Q3: "메모리 부족"
```bash
# 더 많은 메모리로 재제출
./lsdyna_submit.sh custom input.k -c 32 -m 128
```

### Q4: "재시작 파일이 없습니다"
```bash
# 이전 작업 결과 확인
ls -la /Data/home/$(whoami)/<previous_job_id>/d3dump*
```

## 📌 모범 사례

### 1. 작업 제출 전 체크리스트

- [ ] K 파일 경로 확인
- [ ] Include 파일 모두 같은 디렉토리에 있는지 확인
- [ ] 필요한 리소스 예상 (노드, 코어, 메모리)
- [ ] 예상 실행 시간 계산

### 2. 효율적인 리소스 사용

- 소규모 모델: `basic` (과도한 리소스 낭비 방지)
- 대규모 모델: `mpi` (병렬화 효율 극대화)
- 암시적 해석: `gpu` (GPU 가속 활용)
- 장시간 해석: 주기적으로 체크포인트 저장

### 3. 작업 이름 규칙

```bash
# 의미 있는 작업 이름 사용
./lsdyna_submit.sh custom input.k \
    -j "ProjectA_CrashTest_v1.2_20250110"
```

## 📞 지원

문제가 발생하면:
1. 로그 파일 확인 (`lsdyna_*.out`, `lsdyna_*.err`)
2. Job ID와 에러 메시지 기록
3. 시스템 관리자에게 문의

---

**버전**: 1.0.0  
**날짜**: 2025-01-10  
**작성자**: KooSlurmInstallAutomation Team
