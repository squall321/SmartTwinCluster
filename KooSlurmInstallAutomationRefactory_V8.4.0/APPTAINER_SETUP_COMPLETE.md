# Apptainer 관리 기능 추가 완료

## 📦 새로 추가된 기능

프로젝트에 Apptainer 컨테이너 이미지 관리 기능이 추가되었습니다!

### 추가된 파일들

```
KooSlurmInstallAutomationRefactory/
├── apptainers/                          # 신규 디렉토리
│   ├── README.md                        # Apptainer 사용 가이드
│   └── ubuntu_python.def                # 예제 definition 파일
├── sync_apptainers_to_nodes.sh          # 신규 스크립트
├── APPTAINER_MANAGEMENT_GUIDE.md        # 신규 문서
├── set_apptainer_permissions.sh         # 권한 설정 스크립트
└── setup_cluster_full.sh                # Step 13 추가됨
```

## 🚀 빠른 시작

### 1. 실행 권한 부여

```bash
chmod +x set_apptainer_permissions.sh
./set_apptainer_permissions.sh
```

또는 수동으로:

```bash
chmod +x sync_apptainers_to_nodes.sh
```

### 2. Apptainer 이미지 준비

```bash
cd apptainers/

# 예제 이미지 빌드 (선택사항)
sudo apptainer build ubuntu_python.sif ubuntu_python.def

# 또는 Docker 이미지를 변환
apptainer pull docker://ubuntu:22.04
```

### 3-A. 자동 설치 시 동기화 (추천)

```bash
./setup_cluster_full.sh
```

Step 13에서 자동으로 Apptainer 이미지 동기화 여부를 물어봅니다.

### 3-B. 수동 동기화

```bash
# 기본 동기화
./sync_apptainers_to_nodes.sh

# 시뮬레이션 (실제 복사 안 함)
./sync_apptainers_to_nodes.sh --dry-run

# 강제 덮어쓰기
./sync_apptainers_to_nodes.sh --force
```

## 📝 주요 기능

### 1. 중앙 집중식 이미지 관리

- 로컬의 `apptainers/` 디렉토리에 `.def`와 `.sif` 파일 저장
- 버전 관리 시스템(Git)과 함께 사용 가능

### 2. 자동 배포

- 모든 계산 노드의 `/scratch/apptainers/`로 자동 복사
- rsync를 사용한 효율적인 전송
- 기존 파일 건너뛰기 (--force로 덮어쓰기 가능)

### 3. YAML 기반 설정

- `my_cluster.yaml`에서 노드 정보 자동 추출
- SSH 연결 정보 통합 관리

### 4. setup_cluster_full.sh 통합

- Step 13으로 자동 통합
- 선택적으로 활성화/비활성화 가능

## 📖 상세 가이드

전체 사용법은 다음 문서를 참고하세요:

```bash
# Apptainer 관리 전체 가이드
cat APPTAINER_MANAGEMENT_GUIDE.md

# Apptainer 디렉토리 사용법
cat apptainers/README.md

# MPI + Apptainer 통합 가이드
cat MPI_APPTAINER_GUIDE.md
```

## 🔧 설정

### my_cluster.yaml 설정 확인

Apptainer 관련 설정이 이미 포함되어 있습니다:

```yaml
container_support:
  apptainer:
    enabled: true
    version: 1.2.5
    install_path: /usr/local
    image_path: /share/apptainer/images
    cache_path: /tmp/apptainer
    scratch_image_path: /scratch/apptainer/images  # 복사 대상 경로
    bind_paths:
    - /home
    - /share
    - /scratch
    - /tmp
    auto_sync_images: true
```

## 💻 사용 예제

### Slurm 작업에서 Apptainer 사용

```bash
#!/bin/bash
#SBATCH --job-name=apptainer_job
#SBATCH --output=result_%j.txt
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=4G

# Apptainer 이미지로 Python 스크립트 실행
apptainer exec /scratch/apptainers/ubuntu_python.sif \
    python3 my_analysis.py
```

### 인터랙티브 사용

```bash
# 쉘 실행
srun --pty apptainer shell /scratch/apptainers/ubuntu_python.sif

# 명령 실행
srun apptainer exec /scratch/apptainers/ubuntu_python.sif python3 --version
```

## 🛠️ 고급 사용

### 1. 이미지 업데이트

```bash
# 1. 로컬에서 이미지 업데이트
cd apptainers/
sudo apptainer build --force myapp.sif myapp.def

# 2. 모든 노드에 강제 동기화
cd ..
./sync_apptainers_to_nodes.sh --force
```

### 2. 특정 설정 파일 사용

```bash
./sync_apptainers_to_nodes.sh --config dev_cluster.yaml
```

### 3. 사전 확인 (Dry Run)

```bash
# 어떤 파일이 복사될지 확인
./sync_apptainers_to_nodes.sh --dry-run
```

## 🔍 동작 확인

### 1. 동기화 확인

```bash
# 각 노드에서 확인
ssh node001 'ls -lh /scratch/apptainers/'
ssh node002 'ls -lh /scratch/apptainers/'
```

### 2. Apptainer 이미지 정보 확인

```bash
ssh node001 'apptainer inspect /scratch/apptainers/ubuntu_python.sif'
```

### 3. 테스트 실행

```bash
# 간단한 명령 실행 테스트
srun -N1 apptainer exec /scratch/apptainers/ubuntu_python.sif python3 --version
```

## 📊 워크플로우

```
1. Definition 파일 작성
   └─→ apptainers/*.def

2. 이미지 빌드
   └─→ apptainers/*.sif

3. 로컬 테스트
   └─→ apptainer exec myapp.sif ./test.sh

4. 노드 동기화
   └─→ ./sync_apptainers_to_nodes.sh
   └─→ 또는 setup_cluster_full.sh Step 13

5. Slurm 작업 제출
   └─→ sbatch job.sh

6. 결과 확인
```

## 🐛 문제 해결

### SSH 연결 실패

```bash
# SSH 키 확인
ls -la ~/.ssh/

# SSH 연결 테스트
ssh node001 'hostname'

# 필요시 키 재설정
./QUICK_SSH_PASSWORDLESS.sh
```

### rsync 에러

```bash
# rsync 설치 확인
which rsync

# 없다면 설치
sudo apt-get install rsync
```

### 권한 문제

```bash
# 노드에서 디렉토리 권한 확인
ssh node001 'ls -ld /scratch/apptainers'

# 필요시 수정
ssh node001 'sudo chmod 755 /scratch/apptainers'
```

## 📚 관련 문서

- `APPTAINER_MANAGEMENT_GUIDE.md` - 전체 가이드
- `apptainers/README.md` - Apptainer 디렉토리 사용법
- `MPI_APPTAINER_GUIDE.md` - MPI + Apptainer 통합
- `my_cluster.yaml` - 클러스터 설정

## ✅ 체크리스트

설치 확인을 위한 체크리스트:

- [ ] `apptainers/` 디렉토리 존재
- [ ] `sync_apptainers_to_nodes.sh` 실행 권한 있음
- [ ] `my_cluster.yaml`에 노드 정보 정의됨
- [ ] SSH passwordless 설정 완료
- [ ] rsync 설치됨
- [ ] 테스트 이미지 빌드 성공
- [ ] 노드로 동기화 성공
- [ ] Slurm 작업에서 실행 성공

## 🎯 다음 단계

1. **이미지 준비**
   ```bash
   cd apptainers/
   sudo apptainer build myapp.sif myapp.def
   ```

2. **동기화 실행**
   ```bash
   cd ..
   ./sync_apptainers_to_nodes.sh
   ```

3. **Slurm 작업 제출**
   ```bash
   sbatch my_apptainer_job.sh
   ```

## 💡 팁

- 이미지 파일명에 버전 포함 권장 (예: `myapp_v1.2.sif`)
- 큰 이미지는 압축 후 전송 고려
- 정기적으로 `--force` 옵션으로 업데이트
- Git으로 `.def` 파일 버전 관리
- `.sif` 파일은 `.gitignore`에 추가 권장

## 🤝 기여

버그 리포트나 기능 제안은 이슈로 등록해주세요!

---

**작성일**: 2025-10-13
**버전**: 1.0
**작성자**: Claude + koopark
