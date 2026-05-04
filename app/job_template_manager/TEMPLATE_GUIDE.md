# Job Template 작성 가이드

## 개요

Job Template은 Slurm 작업을 표준화하여 사용자가 쉽게 재사용할 수 있도록 하는 YAML 형식의 설정 파일입니다.

## 템플릿 위치

```
app/job_template_manager/src/resources/templates/
├── simulation/      # 시뮬레이션 작업 (LS-DYNA, ANSYS, ABAQUS 등)
├── ml/              # 머신러닝 작업 (PyTorch, TensorFlow 등)
├── data/            # 데이터 처리 작업 (전처리, 변환 등)
└── visualization/   # 가시화 작업 (Paraview, VNC 등)
```

## 템플릿 구조

### 1. Template Metadata (필수)

작업 템플릿의 기본 정보를 정의합니다.

```yaml
template:
  id: "unique-template-id"           # 고유 식별자 (영문, 숫자, 하이픈만 사용)
  name: "Display Name"               # 사용자에게 보이는 이름 (한글 가능)
  description: |                     # 템플릿 설명 (여러 줄 가능)
    이 템플릿은 LS-DYNA R16을 사용하여
    충돌 시뮬레이션을 수행합니다.
  category: simulation               # 카테고리 (simulation/ml/data/visualization)
  version: "1.0.0"                   # 버전 (Semantic Versioning)
  author: "Your Name"                # 작성자 (선택)
  tags:                              # 태그 (선택, 검색용)
    - lsdyna
    - crash
    - automotive
```

**필드 설명:**
- `id`: API에서 템플릿을 조회할 때 사용하는 고유 키 (변경 불가)
- `name`: 웹 UI에서 표시되는 이름
- `description`: 템플릿의 목적과 사용법 설명
- `category`: 템플릿 분류 (필터링에 사용)
- `version`: 템플릿 버전 관리
- `tags`: 검색 및 필터링용 키워드

---

### 2. Slurm Resource (필수)

Slurm 작업에 필요한 리소스를 정의합니다.

```yaml
slurm:
  partition: compute                 # 파티션 이름 (compute/viz/gpu)
  nodes: 1                           # 노드 수 (1~N)
  ntasks: 8                          # 총 태스크 수 (MPI 프로세스 수)
  cpus_per_task: 1                   # 태스크당 CPU 코어 수
  mem: 32G                           # 메모리 크기 (GB 단위)
  time: "04:00:00"                   # 최대 실행 시간 (HH:MM:SS)
  gres: "gpu:2"                      # GPU 리소스 (선택)
  constraint: "intel"                # 노드 제약 조건 (선택)
  exclusive: true                    # 노드 독점 사용 여부 (선택)
```

**필드 설명:**
- `partition`: 작업을 실행할 파티션
  - `compute`: 일반 계산 노드
  - `viz`: 가시화 노드 (GPU 포함)
  - `gpu`: GPU 전용 노드
- `nodes`: 사용할 노드 개수
- `ntasks`: MPI 병렬 작업의 프로세스 수
- `cpus_per_task`: OpenMP 스레드 수 (ntasks × cpus_per_task = 총 CPU 코어)
- `mem`: 메모리 요청량 (예: 32G, 64G, 128G)
- `time`: 작업 시간 제한 (초과 시 자동 종료)
- `gres`: GPU 리소스 요청 (예: `gpu:1`, `gpu:tesla:2`)

**리소스 계산 예시:**
```yaml
# 8코어 단일 노드 작업
nodes: 1
ntasks: 8
cpus_per_task: 1

# 4코어 × 4스레드 하이브리드 병렬
nodes: 1
ntasks: 4
cpus_per_task: 4

# 2노드 × 16코어 MPI 작업
nodes: 2
ntasks: 32
cpus_per_task: 1
```

---

### 3. Apptainer Container (선택)

컨테이너 이미지를 사용하는 경우 정의합니다.

```yaml
apptainer:
  image_name: "lsdyna_r16.sif"       # 컨테이너 이미지 파일명
  image_path: "/opt/apptainers"      # 이미지 경로 (선택, 기본값 사용 시 생략)
  mode: fixed                        # fixed: 이미지 고정, selectable: 사용자 선택
  bind:                              # 마운트 경로 리스트
    - /shared:/shared
    - /scratch:/scratch
    - /mnt/gluster:/mnt/gluster
  environment:                       # 환경변수 (선택)
    - OMP_NUM_THREADS=8
    - CUDA_VISIBLE_DEVICES=0,1
  options:                           # 추가 apptainer 옵션 (선택)
    - --nv                           # NVIDIA GPU 지원
    - --rocm                         # AMD GPU 지원
```

**필드 설명:**
- `image_name`: `/opt/apptainers/` 디렉토리에 있는 .sif 파일명
- `mode`:
  - `fixed`: 이미지가 템플릿에 고정 (일반적)
  - `selectable`: 사용자가 실행 시 이미지 선택 가능
- `bind`: 호스트 경로를 컨테이너 내부에 마운트
  - 형식: `호스트경로:컨테이너경로[:옵션]`
  - 예: `/shared:/shared:ro` (읽기 전용)
- `environment`: 컨테이너 내부 환경변수 설정
- `options`: apptainer exec 추가 옵션

---

### 4. Input Files Schema (선택)

사용자로부터 입력 파일을 받을 때 정의합니다.

```yaml
files:
  input_schema:
    required:                        # 필수 입력 파일
      - file_key: input_k            # 파일 키 (스크립트에서 {input_k}로 참조)
        name: "Input K File"         # 사용자에게 보이는 이름
        description: "LS-DYNA input deck file"  # 설명
        validation:
          extensions: [.k, .key, .dyn]  # 허용 확장자
          max_size: "500MB"          # 최대 파일 크기
        default_location: "/shared/inputs"  # 기본 저장 위치 (선택)

      - file_key: mesh_file
        name: "Mesh File"
        validation:
          extensions: [.msh, .mesh, .inp]
          max_size: "1GB"

    optional:                        # 선택 입력 파일
      - file_key: config_file
        name: "Configuration File"
        description: "Optional solver configuration"
        validation:
          extensions: [.cfg, .conf, .txt]
          max_size: "10MB"
```

**필드 설명:**
- `file_key`: 스크립트에서 변수로 사용할 키 이름
  - 예: `{input_k}` → 실제 파일 경로로 치환
- `name`: 웹 UI에서 표시되는 파일 이름
- `description`: 파일 용도 설명
- `validation`: 파일 검증 규칙
  - `extensions`: 허용되는 파일 확장자 리스트
  - `max_size`: 최대 파일 크기 (MB, GB 단위)
- `required` vs `optional`: 필수/선택 파일 구분

---

### 5. Script Execution (필수)

실제 작업을 수행하는 스크립트를 정의합니다.

```yaml
script:
  pre_exec: |                        # 실행 전 준비 작업
    #!/bin/bash
    set -e

    echo "=========================================="
    echo "Job started at: $(date)"
    echo "Node: $SLURM_NODELIST"
    echo "Working directory: $SLURM_SUBMIT_DIR"
    echo "=========================================="

    # 환경 변수 설정
    export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

    # 작업 디렉토리 생성
    mkdir -p /shared/results/$SLURM_JOB_ID
    cd /shared/results/$SLURM_JOB_ID

    # 입력 파일 복사
    cp {input_k} ./input.k

  main_exec: |                       # 메인 실행 명령어
    #!/bin/bash
    set -e

    echo "Starting LS-DYNA simulation..."

    # LS-DYNA 실행
    apptainer exec \
      --bind /shared:/shared \
      /opt/apptainers/lsdyna_r16.sif \
      lsdyna i=input.k \
            ncpu=$SLURM_NTASKS \
            memory=30g \
            jobid=$SLURM_JOB_ID

    echo "Simulation completed successfully"

  post_exec: |                       # 실행 후 정리 작업
    #!/bin/bash

    echo "=========================================="
    echo "Post-processing..."
    echo "=========================================="

    # 결과 파일 정리
    mkdir -p /shared/results/$SLURM_JOB_ID/output
    mv d3plot* /shared/results/$SLURM_JOB_ID/output/ 2>/dev/null || true
    mv messag* /shared/results/$SLURM_JOB_ID/ 2>/dev/null || true

    # 요약 정보 생성
    echo "Job ID: $SLURM_JOB_ID" > job_summary.txt
    echo "End time: $(date)" >> job_summary.txt
    echo "Exit code: $?" >> job_summary.txt

    echo "Job completed at: $(date)"
```

**변수 치환:**

템플릿 스크립트에서 사용 가능한 변수:

1. **사용자 입력 파일**: `{file_key}` 형식
   - 예: `{input_k}` → `/shared/uploads/user123/input_file.k`

2. **Slurm 환경변수**: 자동으로 사용 가능
   - `$SLURM_JOB_ID`: 작업 ID
   - `$SLURM_NODELIST`: 할당된 노드 리스트
   - `$SLURM_NTASKS`: 태스크 수
   - `$SLURM_CPUS_PER_TASK`: 태스크당 CPU
   - `$SLURM_SUBMIT_DIR`: 제출 디렉토리

3. **사용자 파라미터**: `{param_name}` 형식 (고급 기능)

---

## 전체 예시: LS-DYNA R16 Template

```yaml
template:
  id: lsdyna-r16-basic
  name: "LS-DYNA R16 Basic Run"
  description: |
    LS-DYNA R16을 사용한 기본 충돌 시뮬레이션 템플릿입니다.
    단일 노드, 8코어 병렬 실행을 기본으로 합니다.
  category: simulation
  version: 1.0.0
  author: "HPC Admin"
  tags:
    - lsdyna
    - r16
    - crash
    - explicit

slurm:
  partition: compute
  nodes: 1
  ntasks: 8
  cpus_per_task: 1
  mem: 32G
  time: "04:00:00"

apptainer:
  image_name: lsdyna_r16.sif
  mode: fixed
  bind:
    - /shared:/shared
    - /scratch:/scratch
  environment:
    - OMP_NUM_THREADS=1
  options:
    - --cleanenv

files:
  input_schema:
    required:
      - file_key: input_k
        name: "Input K File"
        description: "LS-DYNA input deck (.k, .key, .dyn)"
        validation:
          extensions: [.k, .key, .dyn]
          max_size: "500MB"

script:
  pre_exec: |
    #!/bin/bash
    set -e
    echo "Job started at: $(date)"
    echo "Node: $SLURM_NODELIST"
    mkdir -p /shared/results/$SLURM_JOB_ID
    cd /shared/results/$SLURM_JOB_ID
    cp {input_k} ./input.k

  main_exec: |
    #!/bin/bash
    set -e
    apptainer exec \
      --bind /shared:/shared \
      /opt/apptainers/lsdyna_r16.sif \
      lsdyna i=input.k ncpu=$SLURM_NTASKS memory=30g

  post_exec: |
    #!/bin/bash
    mkdir -p output
    mv d3plot* output/ 2>/dev/null || true
    mv messag* ./ 2>/dev/null || true
    echo "Job completed at: $(date)"
```

---

## 템플릿 작성 체크리스트

### 필수 항목
- [ ] `template.id` - 고유 식별자 설정
- [ ] `template.name` - 사용자용 이름 설정
- [ ] `template.category` - 카테고리 선택
- [ ] `slurm.partition` - 파티션 지정
- [ ] `slurm.nodes` - 노드 수 설정
- [ ] `slurm.ntasks` - 태스크 수 설정
- [ ] `slurm.mem` - 메모리 설정
- [ ] `slurm.time` - 시간 제한 설정
- [ ] `script.main_exec` - 메인 실행 스크립트 작성

### 선택 항목
- [ ] `template.description` - 상세 설명 추가
- [ ] `template.tags` - 검색용 태그 추가
- [ ] `apptainer` - 컨테이너 설정
- [ ] `files.input_schema` - 입력 파일 스키마 정의
- [ ] `script.pre_exec` - 사전 준비 스크립트
- [ ] `script.post_exec` - 후처리 스크립트

---

## 템플릿 배포

### 1. 파일 저장
템플릿을 적절한 카테고리 디렉토리에 저장:
```bash
# 시뮬레이션 템플릿
/shared/templates/simulation/my-template.yaml

# 또는 프로젝트 소스
app/job_template_manager/src/resources/templates/simulation/my-template.yaml
```

### 2. 템플릿 스캔 및 등록
```bash
# API를 통한 스캔 (자동 DB 등록)
curl -X POST http://localhost:5010/api/jobs/templates/scan
```

### 3. 템플릿 확인
```bash
# 전체 템플릿 목록
curl http://localhost:5010/api/v2/templates

# 특정 템플릿 조회
curl http://localhost:5010/api/v2/templates/lsdyna-r16-basic
```

### 4. 배포 스크립트 사용
```bash
# 프로젝트에서 제공하는 배포 스크립트
./deploy_templates.sh
```

---

## 고급 기능

### 1. 파라미터화된 템플릿

사용자가 실행 시 값을 입력할 수 있는 파라미터 정의:

```yaml
parameters:
  - param_key: time_step
    name: "Time Step"
    type: float
    default: 0.001
    validation:
      min: 0.0001
      max: 0.01

  - param_key: output_interval
    name: "Output Interval"
    type: integer
    default: 100
    validation:
      min: 1
      max: 1000

script:
  main_exec: |
    lsdyna i=input.k \
           dt={time_step} \
           outputfreq={output_interval}
```

### 2. 조건부 실행

```yaml
script:
  main_exec: |
    if [ "$SLURM_NNODES" -gt 1 ]; then
      # Multi-node execution
      mpirun -np $SLURM_NTASKS solver
    else
      # Single-node execution
      solver -np $SLURM_NTASKS
    fi
```

### 3. GPU 사용 템플릿

```yaml
slurm:
  partition: gpu
  gres: "gpu:2"

apptainer:
  options:
    - --nv  # NVIDIA GPU 지원

script:
  pre_exec: |
    export CUDA_VISIBLE_DEVICES=0,1
    nvidia-smi
```

---

## 문제 해결

### 템플릿이 목록에 안 나타날 때
1. YAML 문법 오류 확인:
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('template.yaml'))"
   ```

2. 파일 권한 확인:
   ```bash
   chmod 644 /shared/templates/simulation/my-template.yaml
   ```

3. 템플릿 스캔 재실행:
   ```bash
   curl -X POST http://localhost:5010/api/jobs/templates/scan
   ```

### 작업 제출 실패
1. 로그 확인:
   ```bash
   tail -f /var/log/syslog | grep slurm
   ```

2. 템플릿 변수 확인:
   - `{file_key}` 변수가 올바르게 치환되었는지 확인
   - Slurm 환경변수가 스크립트에서 사용 가능한지 확인

---

## 참고 자료

- Slurm 공식 문서: https://slurm.schedmd.com/
- Apptainer 문서: https://apptainer.org/docs/
- YAML 문법: https://yaml.org/spec/1.2/spec.html
