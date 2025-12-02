# Apptainer 이미지 관리 가이드

이 프로젝트는 Apptainer 컨테이너 이미지를 중앙에서 관리하고 모든 계산 노드에 자동으로 배포하는 기능을 제공합니다.

## 📁 디렉토리 구조

```
KooSlurmInstallAutomationRefactory/
├── apptainers/                      # Apptainer 이미지 저장소
│   ├── README.md                    # 사용 가이드
│   ├── ubuntu_python.def            # 예제 definition 파일
│   ├── *.def                        # Definition 파일들
│   └── *.sif                        # 빌드된 이미지 파일들
├── sync_apptainers_to_nodes.sh      # 동기화 스크립트
└── my_cluster.yaml                  # 클러스터 설정 (노드 정보 포함)
```

## 🚀 빠른 시작

### 1. Apptainer 이미지 준비

#### 방법 A: Definition 파일로 빌드

```bash
cd apptainers/

# Definition 파일 작성 (ubuntu_python.def 참고)
vim my_container.def

# 이미지 빌드 (sudo 필요)
sudo apptainer build my_container.sif my_container.def
```

#### 방법 B: 기존 이미지 다운로드

```bash
cd apptainers/

# Docker Hub에서 변환
apptainer pull docker://ubuntu:22.04

# Singularity Library에서 다운로드
apptainer pull library://sylabs/examples/lolcow
```

### 2. 계산 노드로 동기화

#### 자동 동기화 (setup_cluster_full.sh 실행 시)

```bash
./setup_cluster_full.sh
# Step 13에서 자동으로 물어봄
```

#### 수동 동기화

```bash
# 기본 동기화 (기존 파일 건너뜀)
./sync_apptainers_to_nodes.sh

# 강제 덮어쓰기
./sync_apptainers_to_nodes.sh --force

# 시뮬레이션 (실제 복사 안 함)
./sync_apptainers_to_nodes.sh --dry-run

# 다른 설정 파일 사용
./sync_apptainers_to_nodes.sh --config dev_cluster.yaml
```

### 3. 노드에서 확인

```bash
# 노드에 접속
ssh node001

# 이미지 확인
ls -lh /scratch/apptainers/

# 이미지 정보 보기
apptainer inspect /scratch/apptainers/ubuntu_python.sif
```

## 📝 Definition 파일 작성 예제

### 기본 구조

```def
Bootstrap: docker
From: ubuntu:22.04

%post
    # 여기에 설치 명령 작성
    apt-get update
    apt-get install -y python3 python3-pip
    pip3 install numpy pandas

%environment
    # 환경 변수 설정
    export LC_ALL=C
    export PATH=/usr/local/bin:$PATH

%labels
    Author your-name
    Version 1.0

%help
    사용 방법 설명

%runscript
    # 기본 실행 명령
    exec /bin/bash "$@"
```

### Python 과학 계산 환경

```def
Bootstrap: docker
From: ubuntu:22.04

%post
    apt-get update
    apt-get install -y \
        python3 python3-pip \
        build-essential \
        git wget curl
    
    pip3 install \
        numpy scipy pandas \
        matplotlib seaborn \
        scikit-learn \
        jupyter

%environment
    export PYTHONPATH=/usr/local/lib/python3.10/dist-packages:$PYTHONPATH

%runscript
    exec /bin/bash "$@"
```

### MPI 병렬 처리 환경

```def
Bootstrap: docker
From: ubuntu:22.04

%post
    apt-get update
    apt-get install -y \
        build-essential \
        libopenmpi-dev \
        openmpi-bin
    
    # MPI 프로그램 컴파일
    # mpicc -o mpi_program mpi_program.c

%environment
    export PATH=/usr/lib/x86_64-linux-gnu/openmpi/bin:$PATH

%runscript
    exec /bin/bash "$@"
```

## 🔧 Slurm에서 사용하기

### 인터랙티브 작업

```bash
# 쉘 실행
srun --pty apptainer shell /scratch/apptainers/ubuntu_python.sif

# 명령 실행
srun apptainer exec /scratch/apptainers/ubuntu_python.sif python3 script.py
```

### 배치 작업 스크립트

```bash
#!/bin/bash
#SBATCH --job-name=apptainer_test
#SBATCH --output=output_%j.txt
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=4G

# Apptainer 이미지로 Python 스크립트 실행
apptainer exec /scratch/apptainers/ubuntu_python.sif \
    python3 /home/koopark/my_analysis.py

# 또는 bind mount를 사용하여 데이터 접근
apptainer exec \
    --bind /scratch/data:/data \
    --bind /home/koopark:/work \
    /scratch/apptainers/ubuntu_python.sif \
    python3 /work/process_data.py --input /data/dataset.csv
```

### MPI 병렬 실행

```bash
#!/bin/bash
#SBATCH --job-name=mpi_apptainer
#SBATCH --nodes=2
#SBATCH --ntasks=8
#SBATCH --cpus-per-task=1

# MPI + Apptainer
mpirun -np 8 apptainer exec /scratch/apptainers/mpi_container.sif \
    /opt/myapp/mpi_program
```

## ⚙️ 고급 사용법

### 1. GPU 지원

```bash
# GPU 사용 가능한 이미지로 실행
apptainer exec --nv /scratch/apptainers/cuda_container.sif \
    python3 gpu_training.py
```

### 2. 환경 변수 전달

```bash
# 호스트 환경 변수 전달
apptainer exec --cleanenv \
    --env MYVAR=value \
    /scratch/apptainers/myapp.sif \
    ./run.sh
```

### 3. 여러 경로 바인드

```bash
apptainer exec \
    --bind /scratch:/scratch \
    --bind /home:/home \
    --bind /data:/mnt/data:ro \
    /scratch/apptainers/myapp.sif \
    ./process.sh
```

### 4. Overlay 파일시스템 사용

```bash
# 쓰기 가능한 오버레이 생성
apptainer overlay create --size 500 overlay.img

# 오버레이와 함께 실행
apptainer exec --overlay overlay.img \
    /scratch/apptainers/ubuntu_python.sif \
    python3 -m pip install additional-package
```

## 🛠️ sync_apptainers_to_nodes.sh 옵션

### 기본 사용법

```bash
./sync_apptainers_to_nodes.sh [옵션]
```

### 옵션

| 옵션 | 설명 |
|------|------|
| `--config FILE` | YAML 설정 파일 지정 (기본: my_cluster.yaml) |
| `--force` | 기존 파일 강제 덮어쓰기 |
| `--dry-run` | 실제 복사 없이 시뮬레이션 |
| `--help` | 도움말 출력 |

### 예제

```bash
# 시뮬레이션으로 무엇이 복사될지 확인
./sync_apptainers_to_nodes.sh --dry-run

# 모든 파일 강제 업데이트
./sync_apptainers_to_nodes.sh --force

# 개발 클러스터에 동기화
./sync_apptainers_to_nodes.sh --config dev_cluster.yaml
```

## 📊 동기화 작동 방식

1. **파일 스캔**: `apptainers/` 디렉토리에서 `.def`와 `.sif` 파일 검색
2. **노드 정보 추출**: `my_cluster.yaml`에서 계산 노드 정보 읽기
3. **SSH 연결 테스트**: 각 노드에 SSH 접속 확인
4. **디렉토리 생성**: `/scratch/apptainers/` 디렉토리 생성
5. **파일 동기화**: rsync를 통한 효율적인 파일 전송
6. **권한 설정**: 모든 사용자가 읽을 수 있도록 755 권한 설정

## 🔒 보안 고려사항

### 1. SSH 키 관리

```bash
# SSH 키 생성 (아직 없다면)
ssh-keygen -t rsa -b 4096

# 각 노드에 공개키 복사
ssh-copy-id koopark@node001
ssh-copy-id koopark@node002
```

### 2. 컨테이너 이미지 검증

```bash
# 이미지 서명 생성
apptainer sign myimage.sif

# 서명 검증
apptainer verify myimage.sif
```

### 3. 읽기 전용 바인드

```bash
# 민감한 데이터는 읽기 전용으로 마운트
apptainer exec --bind /sensitive/data:/data:ro \
    myimage.sif ./process.sh
```

## 🐛 문제 해결

### SSH 연결 실패

```bash
# SSH 연결 테스트
ssh -v node001

# 키 권한 확인
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

### rsync 에러

```bash
# rsync 설치 확인
sudo apt-get install rsync

# 수동 rsync 테스트
rsync -avz apptainers/ node001:/scratch/apptainers/
```

### 이미지 빌드 실패

```bash
# 자세한 로그 확인
sudo apptainer build --debug myimage.sif myimage.def

# 샌드박스 모드로 빌드
sudo apptainer build --sandbox /tmp/sandbox myimage.def
```

### 권한 문제

```bash
# 노드에서 디렉토리 권한 확인
ssh node001 'ls -ld /scratch/apptainers'

# 필요시 권한 수정
ssh node001 'sudo chmod 755 /scratch/apptainers'
```

## 📚 추가 리소스

### 공식 문서
- [Apptainer 공식 문서](https://apptainer.org/docs/)
- [Definition 파일 가이드](https://apptainer.org/docs/user/main/definition_files.html)
- [Slurm + Apptainer](https://slurm.schedmd.com/containers.html)

### 프로젝트 문서
- `apptainers/README.md` - Apptainer 디렉토리 가이드
- `MPI_APPTAINER_GUIDE.md` - MPI + Apptainer 통합 가이드
- `my_cluster.yaml` - 클러스터 설정

### 커뮤니티
- [Apptainer Slack](https://apptainer.org/help)
- [Slurm User Mailing List](https://slurm.schedmd.com/mail.html)

## 🔄 워크플로우 예제

### 전체 프로세스

```bash
# 1. Definition 파일 작성
vim apptainers/myapp.def

# 2. 이미지 빌드
cd apptainers/
sudo apptainer build myapp.sif myapp.def

# 3. 로컬에서 테스트
apptainer exec myapp.sif ./test.sh

# 4. 노드로 동기화
cd ..
./sync_apptainers_to_nodes.sh

# 5. Slurm 작업 제출
sbatch my_job.sh

# 6. 결과 확인
squeue
cat output_*.txt
```

## 💡 팁과 권장사항

1. **이미지 버전 관리**: 파일명에 버전 포함 (예: `myapp_v1.2.sif`)
2. **용량 최적화**: 필요한 패키지만 설치하여 이미지 크기 최소화
3. **캐시 활용**: Apptainer 빌드 캐시를 활용하여 빌드 시간 단축
4. **정기 동기화**: 이미지 업데이트 시 `--force` 옵션으로 동기화
5. **문서화**: 각 이미지의 용도와 사용법을 README에 기록

## ❓ FAQ

**Q: 이미지가 너무 크면 어떻게 하나요?**
A: 네트워크 대역폭을 고려하여 필요한 이미지만 동기화하거나, 압축된 상태로 전송 후 노드에서 해제할 수 있습니다.

**Q: 기존 파일을 덮어쓰려면?**
A: `./sync_apptainers_to_nodes.sh --force` 옵션을 사용하세요.

**Q: 특정 노드에만 동기화하려면?**
A: `my_cluster.yaml`에서 해당 노드만 남기거나, 수동으로 `scp` 또는 `rsync`를 사용하세요.

**Q: 이미지를 삭제하려면?**
A: 로컬에서 삭제 후, 각 노드에서 수동으로 삭제하거나 동기화 스크립트에 `--delete` 기능을 추가해야 합니다.
