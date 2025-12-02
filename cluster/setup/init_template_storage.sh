#!/bin/bash

################################################################################
# Template Storage Initialization Script
#
# /shared/templates/ 디렉토리 구조를 생성하고 초기화합니다.
# 외부 템플릿 저장소를 구성하여 프론트엔드 빌드와 독립적으로 관리합니다.
#
# Usage:
#   sudo ./init_template_storage.sh
#
# Created: 2025-11-05
# Version: 1.0.0
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Template storage path
TEMPLATE_DIR="/shared/templates"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Create directory structure
create_directories() {
    log_info "Creating template storage directory structure..."

    # Main directories
    mkdir -p "$TEMPLATE_DIR"/{official,community,private,archived}

    # Official template categories
    mkdir -p "$TEMPLATE_DIR"/official/{ml,cfd,structural,molecular,data,rendering,custom}

    log_success "Directory structure created"
}

# Set permissions
set_permissions() {
    log_info "Setting permissions..."

    # Base directory: readable by all
    chown -R koopark:koopark "$TEMPLATE_DIR"
    chmod 755 "$TEMPLATE_DIR"

    # Official: read-only for users, writable by admin
    chmod 755 "$TEMPLATE_DIR"/official
    find "$TEMPLATE_DIR"/official -type d -exec chmod 755 {} \;
    find "$TEMPLATE_DIR"/official -type f -exec chmod 644 {} \;

    # Community: writable by all authenticated users
    chmod 777 "$TEMPLATE_DIR"/community

    # Private: user-specific, writable by owner
    chmod 777 "$TEMPLATE_DIR"/private

    # Archived: read-only
    chmod 755 "$TEMPLATE_DIR"/archived

    log_success "Permissions set"
}

# Create sample official templates
create_sample_templates() {
    log_info "Creating sample official templates..."

    # PyTorch Training Template
    cat > "$TEMPLATE_DIR"/official/ml/pytorch_training.yaml << 'EOF'
# PyTorch 모델 학습 템플릿
template:
  id: pytorch-training-v1
  name: pytorch_training
  display_name: "PyTorch 모델 학습"
  description: "PyTorch를 이용한 딥러닝 모델 학습 템플릿"
  category: ml
  tags: [gpu, pytorch, ml, deep-learning]
  version: "1.0.0"
  author: admin
  is_public: true

slurm:
  partition: compute
  nodes: 1
  ntasks: 1
  cpus_per_task: 8
  mem: 32G
  time: "04:00:00"
  gres: gpu:1
  constraint: "gpu_v100|gpu_a100"

apptainer:
  image_name: "KooSimulationPython313.sif"
  app: python
  bind:
    - /shared/datasets:/datasets:ro
    - /shared/models:/models:rw

files:
  input_schema:
    required:
      - name: training_script
        pattern: "*.py"
        description: "학습 스크립트"
        type: code
        max_size: 10MB
      - name: dataset
        pattern: "*.tar.gz"
        description: "데이터셋 아카이브"
        type: data
        max_size: 10GB
    optional:
      - name: pretrained_model
        pattern: "*.pth"
        description: "사전 학습된 모델"
        type: model
        max_size: 2GB

  config_schema:
    required:
      - name: config
        pattern: config.yaml
        format: yaml
        schema:
          type: object
          properties:
            learning_rate: {type: number, minimum: 0.0001, maximum: 1}
            batch_size: {type: integer, minimum: 1, maximum: 1024}
            epochs: {type: integer, minimum: 1}
            optimizer: {type: string, enum: [adam, sgd, rmsprop]}
          required: [learning_rate, batch_size, epochs]

  output_pattern: "checkpoints/*.pth"

script:
  pre_exec: |
    #!/bin/bash
    # 데이터셋 압축 해제
    mkdir -p $SLURM_SUBMIT_DIR/data
    tar -xzf dataset.tar.gz -C $SLURM_SUBMIT_DIR/data

    # 환경 변수 설정
    export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID

  main_exec: |
    #!/bin/bash
    # PyTorch 학습 실행
    apptainer exec --nv $APPTAINER_IMAGE \
      python training_script.py \
        --config config.yaml \
        --data $SLURM_SUBMIT_DIR/data \
        --output $SLURM_SUBMIT_DIR/checkpoints

  post_exec: |
    #!/bin/bash
    # 결과 파일 정리
    mkdir -p /shared/results/$SLURM_JOB_ID
    cp -r checkpoints /shared/results/$SLURM_JOB_ID/

    # 임시 파일 정리
    rm -rf $SLURM_SUBMIT_DIR/data

validation:
  pre_submit:
    - check_gpu_availability
    - validate_dataset_size
  post_submit:
    - notify_user
    - log_submission
EOF

    # OpenFOAM CFD Template
    cat > "$TEMPLATE_DIR"/official/cfd/openfoam_simulation.yaml << 'EOF'
# OpenFOAM CFD 시뮬레이션 템플릿
template:
  id: openfoam-cfd-v1
  name: openfoam_simulation
  display_name: "OpenFOAM CFD 시뮬레이션"
  description: "OpenFOAM을 이용한 유체역학 시뮬레이션"
  category: cfd
  tags: [cfd, openfoam, fluid-dynamics, mpi]
  version: "1.0.0"
  author: admin
  is_public: true

slurm:
  partition: compute
  nodes: 2
  ntasks: 32
  cpus_per_task: 1
  mem: 64G
  time: "12:00:00"

apptainer:
  image_name: "openfoam_v2312.sif"
  app: simpleFoam
  bind:
    - /shared/cfd_cases:/cases:ro
    - /shared/results:/results:rw

files:
  input_schema:
    required:
      - name: case_directory
        pattern: "*/"
        description: "OpenFOAM 케이스 디렉토리"
        type: directory
        max_size: 5GB
      - name: mesh_file
        pattern: "*.msh"
        description: "메쉬 파일"
        type: data
        max_size: 1GB

  output_pattern: "postProcessing/**/*"

script:
  pre_exec: |
    #!/bin/bash
    # 케이스 디렉토리 복사
    cp -r case_directory $SLURM_SUBMIT_DIR/case
    cd $SLURM_SUBMIT_DIR/case

    # 메쉬 생성
    apptainer exec $APPTAINER_IMAGE blockMesh

  main_exec: |
    #!/bin/bash
    cd $SLURM_SUBMIT_DIR/case

    # MPI 병렬 실행
    mpirun -np $SLURM_NTASKS \
      apptainer exec $APPTAINER_IMAGE \
      simpleFoam -parallel

  post_exec: |
    #!/bin/bash
    # 결과 수집
    cd $SLURM_SUBMIT_DIR/case
    apptainer exec $APPTAINER_IMAGE reconstructPar

    # 결과 저장
    mkdir -p /shared/results/$SLURM_JOB_ID
    cp -r postProcessing /shared/results/$SLURM_JOB_ID/
EOF

    # GROMACS Molecular Dynamics Template
    cat > "$TEMPLATE_DIR"/official/molecular/gromacs_simulation.yaml << 'EOF'
# GROMACS 분자동역학 시뮬레이션 템플릿
template:
  id: gromacs-md-v1
  name: gromacs_simulation
  display_name: "GROMACS 분자동역학"
  description: "GROMACS를 이용한 분자동역학 시뮬레이션"
  category: molecular
  tags: [molecular-dynamics, gromacs, protein, gpu]
  version: "1.0.0"
  author: admin
  is_public: true

slurm:
  partition: compute
  nodes: 1
  ntasks: 8
  cpus_per_task: 1
  mem: 32G
  time: "24:00:00"
  gres: gpu:1

apptainer:
  image_name: "gromacs_gpu.sif"
  bind:
    - /shared/proteins:/proteins:ro
    - /shared/forcefields:/ff:ro

files:
  input_schema:
    required:
      - name: structure_file
        pattern: "*.pdb"
        description: "단백질 구조 파일"
        type: data
        max_size: 100MB
      - name: topology_file
        pattern: "*.top"
        description: "토폴로지 파일"
        type: config
        max_size: 10MB
      - name: mdp_file
        pattern: "*.mdp"
        description: "시뮬레이션 파라미터"
        type: config
        max_size: 1MB

  output_pattern: "trajectory/*.xtc"

script:
  pre_exec: |
    #!/bin/bash
    # 작업 디렉토리 설정
    mkdir -p trajectory

    # 시스템 준비
    apptainer exec $APPTAINER_IMAGE \
      gmx pdb2gmx -f structure_file.pdb -o conf.gro -water spce

  main_exec: |
    #!/bin/bash
    # 에너지 최소화
    apptainer exec --nv $APPTAINER_IMAGE \
      gmx grompp -f mdp_file.mdp -c conf.gro -p topology_file.top -o em.tpr

    apptainer exec --nv $APPTAINER_IMAGE \
      gmx mdrun -v -deffnm em -nb gpu

    # MD 실행
    apptainer exec --nv $APPTAINER_IMAGE \
      gmx grompp -f md.mdp -c em.gro -p topology_file.top -o md.tpr

    apptainer exec --nv $APPTAINER_IMAGE \
      gmx mdrun -v -deffnm md -nb gpu

  post_exec: |
    #!/bin/bash
    # 궤적 파일 저장
    mkdir -p /shared/results/$SLURM_JOB_ID
    cp md.xtc md.edr md.log /shared/results/$SLURM_JOB_ID/
EOF

    # Set permissions on template files
    find "$TEMPLATE_DIR"/official -type f -exec chmod 644 {} \;

    log_success "Sample templates created"
}

# Create README
create_readme() {
    log_info "Creating README..."

    cat > "$TEMPLATE_DIR"/README.md << 'EOF'
# Template Storage Directory

외부 템플릿 저장소입니다. 프론트엔드 빌드와 독립적으로 템플릿을 관리합니다.

## 디렉토리 구조

```
/shared/templates/
├── official/          # 공식 템플릿 (관리자만 수정)
│   ├── ml/           # Machine Learning
│   ├── cfd/          # Computational Fluid Dynamics
│   ├── structural/   # Structural Analysis
│   ├── molecular/    # Molecular Dynamics
│   ├── data/         # Data Processing
│   ├── rendering/    # 3D Rendering
│   └── custom/       # Custom Templates
├── community/        # 커뮤니티 템플릿 (공유된 사용자 템플릿)
├── private/          # 개인 템플릿 (사용자별 디렉토리)
│   ├── user1/
│   └── user2/
└── archived/         # 아카이브된 템플릿
```

## 템플릿 형식

YAML 형식으로 작성합니다. 예제:

```yaml
template:
  id: my-template-v1
  name: my_template
  display_name: "나의 템플릿"
  description: "템플릿 설명"
  category: custom
  tags: [tag1, tag2]
  version: "1.0.0"
  author: username
  is_public: false

slurm:
  partition: compute
  nodes: 1
  ntasks: 1
  cpus_per_task: 4
  mem: 16G
  time: "02:00:00"

apptainer:
  image_name: "my_image.sif"
  bind:
    - /shared/data:/data:ro

files:
  input_schema:
    required:
      - name: input_file
        pattern: "*.dat"
        type: data

script:
  main_exec: |
    #!/bin/bash
    apptainer exec $APPTAINER_IMAGE ./run.sh
```

## 사용 방법

1. **템플릿 생성**: YAML 파일을 해당 카테고리 디렉토리에 저장
2. **템플릿 수정**: 파일을 직접 편집 (Hot Reload 지원)
3. **템플릿 공유**: `community/` 디렉토리에 복사
4. **Git 버전 관리**: 이 디렉토리를 Git 저장소로 관리 가능

## 권한

- `official/`: 읽기 전용 (관리자만 수정)
- `community/`: 읽기/쓰기 (모든 사용자)
- `private/`: 읽기/쓰기 (소유자만)
- `archived/`: 읽기 전용

EOF

    chmod 644 "$TEMPLATE_DIR"/README.md
    log_success "README created"
}

# Main function
main() {
    echo "=========================================="
    echo " Template Storage Initialization"
    echo " Phase 2: Template Management System"
    echo "=========================================="
    echo ""

    check_root
    create_directories
    set_permissions
    create_sample_templates
    create_readme

    echo ""
    echo "=========================================="
    log_success "Template storage initialized successfully!"
    echo "=========================================="
    echo ""
    echo "Template directory: $TEMPLATE_DIR"
    echo ""
    echo "Directory structure:"
    tree -L 2 "$TEMPLATE_DIR" 2>/dev/null || ls -la "$TEMPLATE_DIR"
    echo ""
    log_info "Official templates: $(find "$TEMPLATE_DIR"/official -name "*.yaml" | wc -l)"
    log_info "Next steps:"
    echo "  1. Review sample templates in $TEMPLATE_DIR/official/"
    echo "  2. Run database migration: python3 run_migrations.py"
    echo "  3. Restart dashboard backend: sudo systemctl restart dashboard_backend"
    echo "  4. Test API: curl http://localhost:5010/api/v2/templates"
}

# Run main function
main
