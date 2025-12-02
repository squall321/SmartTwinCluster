# 🎉 Apptainer 관리 기능 추가 완료!

KooSlurmInstallAutomationRefactory 프로젝트에 Apptainer 컨테이너 이미지 관리 기능이 성공적으로 추가되었습니다!

## 📦 추가된 내용

### 1. 새로운 디렉토리
```
apptainers/
├── README.md              # Apptainer 사용 가이드
└── ubuntu_python.def      # 예제 definition 파일
```

### 2. 새로운 스크립트
- `sync_apptainers_to_nodes.sh` - 메인 동기화 스크립트
- `setup_apptainer_features.sh` - 기능 설정 및 검증 스크립트
- `test_apptainer_sync.sh` - 동기화 테스트 스크립트 (dry-run)
- `chmod_apptainer_scripts.sh` - 권한 설정 스크립트

### 3. 새로운 문서
- `APPTAINER_MANAGEMENT_GUIDE.md` - 전체 사용 가이드
- `APPTAINER_SETUP_COMPLETE.md` - 설치 완료 가이드
- `APPTAINER_INTEGRATION_SUMMARY.md` - 이 파일

### 4. 업데이트된 파일
- `setup_cluster_full.sh` - Step 13 추가 (Apptainer 동기화)
- `.gitignore` - `.sif` 파일 제외 추가

## 🚀 빠른 시작 (3단계)

### Step 1: 권한 설정
```bash
chmod +x chmod_apptainer_scripts.sh
./chmod_apptainer_scripts.sh
```

### Step 2: 기능 확인
```bash
./setup_apptainer_features.sh
```

### Step 3: 테스트
```bash
./test_apptainer_sync.sh
```

## 📖 주요 기능

### 1️⃣ 중앙 집중식 이미지 관리
- `apptainers/` 디렉토리에 `.def` 및 `.sif` 파일 저장
- Git으로 definition 파일 버전 관리
- 이미지 파일은 자동으로 `.gitignore` 처리

### 2️⃣ 자동 배포
- 한 번의 명령으로 모든 계산 노드에 배포
- rsync를 통한 효율적인 전송
- 증분 업데이트 지원 (변경된 파일만 전송)

### 3️⃣ YAML 기반 설정
- `my_cluster.yaml`에서 노드 정보 자동 추출
- SSH 연결 정보 통합 관리
- 확장 가능한 설정 구조

### 4️⃣ setup_cluster_full.sh 통합
- Step 13으로 자연스럽게 통합
- 선택적 실행 가능
- 파일이 없을 경우 건너뛰기

## 💻 사용 예제

### 기본 동기화
```bash
# 1. 이미지 준비
cd apptainers/
sudo apptainer build myapp.sif myapp.def

# 2. 동기화
cd ..
./sync_apptainers_to_nodes.sh
```

### 옵션 사용
```bash
# DRY-RUN (시뮬레이션)
./sync_apptainers_to_nodes.sh --dry-run

# 강제 덮어쓰기
./sync_apptainers_to_nodes.sh --force

# 다른 설정 파일
./sync_apptainers_to_nodes.sh --config dev_cluster.yaml

# 도움말
./sync_apptainers_to_nodes.sh --help
```

### Slurm 작업에서 사용
```bash
#!/bin/bash
#SBATCH --job-name=my_job
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4

apptainer exec /scratch/apptainers/myapp.sif ./my_program
```

## 🔧 설정 확인

### YAML 설정
`my_cluster.yaml`에 이미 Apptainer 설정이 포함되어 있습니다:

```yaml
container_support:
  apptainer:
    enabled: true
    scratch_image_path: /scratch/apptainer/images  # 복사 대상
    auto_sync_images: true
```

### 노드 설정
계산 노드 정보가 정의되어 있어야 합니다:

```yaml
nodes:
  compute_nodes:
  - hostname: node001
    ip_address: 192.168.122.90
    ssh_user: koopark
    ssh_key_path: ~/.ssh/id_rsa
  - hostname: node002
    ip_address: 192.168.122.103
    ssh_user: koopark
    ssh_key_path: ~/.ssh/id_rsa
```

## 📊 작동 방식

```
┌─────────────────────────────────────────────────────────────┐
│                    로컬 환경                                 │
│  ┌──────────────────────────────────────────────────┐       │
│  │  apptainers/                                     │       │
│  │  ├── myapp.def                                   │       │
│  │  ├── myapp.sif  ◄─── apptainer build            │       │
│  │  └── other.sif                                   │       │
│  └──────────────────────────────────────────────────┘       │
│                          │                                   │
│                          │ ./sync_apptainers_to_nodes.sh    │
│                          ▼                                   │
└─────────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
        ▼                                     ▼
┌────────────────────┐              ┌────────────────────┐
│     node001        │              │     node002        │
│  /scratch/         │              │  /scratch/         │
│    apptainers/     │              │    apptainers/     │
│    ├── myapp.sif   │              │    ├── myapp.sif   │
│    └── other.sif   │              │    └── other.sif   │
└────────────────────┘              └────────────────────┘
```

## 🛠️ 문제 해결

### SSH 연결 실패
```bash
# SSH 키 생성 및 복사
ssh-keygen -t rsa -b 4096
ssh-copy-id koopark@node001
ssh-copy-id koopark@node002

# 연결 테스트
ssh node001 'hostname'
```

### rsync 미설치
```bash
sudo apt-get update
sudo apt-get install -y rsync
```

### Python yaml 모듈 없음
```bash
pip3 install pyyaml
# 또는
python3 -m pip install pyyaml
```

### 권한 문제
```bash
# 모든 스크립트 권한 재설정
./chmod_apptainer_scripts.sh

# 개별 설정
chmod +x sync_apptainers_to_nodes.sh
```

## 📚 문서 참고 순서

1. **처음 사용자**
   - `APPTAINER_SETUP_COMPLETE.md` 읽기
   - `./setup_apptainer_features.sh` 실행
   - `apptainers/README.md` 읽기

2. **상세 가이드 필요 시**
   - `APPTAINER_MANAGEMENT_GUIDE.md` 참고
   - `MPI_APPTAINER_GUIDE.md` (MPI 사용 시)

3. **스크립트 도움말**
   - `./sync_apptainers_to_nodes.sh --help`

## ✅ 설치 체크리스트

다음 항목들을 확인하세요:

- [ ] `apptainers/` 디렉토리 생성됨
- [ ] `sync_apptainers_to_nodes.sh` 실행 권한 있음
- [ ] `my_cluster.yaml`에 노드 정보 정의됨
- [ ] SSH passwordless 설정 완료
- [ ] rsync 설치됨
- [ ] Python3 + pyyaml 설치됨
- [ ] 테스트 실행 성공 (`./test_apptainer_sync.sh`)

## 🎯 다음 단계

### 1. 첫 이미지 만들기
```bash
cd apptainers/

# Definition 파일 편집
vim my_first_app.def

# 이미지 빌드
sudo apptainer build my_first_app.sif my_first_app.def

# 로컬 테스트
apptainer exec my_first_app.sif echo "Hello from Apptainer!"
```

### 2. 노드로 배포
```bash
cd ..

# 테스트
./test_apptainer_sync.sh

# 실제 동기화
./sync_apptainers_to_nodes.sh
```

### 3. Slurm 작업 실행
```bash
# 인터랙티브
srun --pty apptainer shell /scratch/apptainers/my_first_app.sif

# 배치 작업
cat > test_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=apptainer_test
#SBATCH --output=result_%j.txt

apptainer exec /scratch/apptainers/my_first_app.sif \
    echo "Running in Apptainer!"
EOF

sbatch test_job.sh
squeue
```

## 🔗 관련 링크

### 프로젝트 문서
- [Apptainer 전체 가이드](./APPTAINER_MANAGEMENT_GUIDE.md)
- [설치 완료 가이드](./APPTAINER_SETUP_COMPLETE.md)
- [Apptainer 디렉토리 README](./apptainers/README.md)
- [MPI + Apptainer](./MPI_APPTAINER_GUIDE.md)

### 외부 리소스
- [Apptainer 공식 문서](https://apptainer.org/docs/)
- [Slurm + Containers](https://slurm.schedmd.com/containers.html)
- [Definition 파일 가이드](https://apptainer.org/docs/user/main/definition_files.html)

## 💡 유용한 팁

1. **이미지 버전 관리**
   ```bash
   # 버전을 파일명에 포함
   myapp_v1.0.sif
   myapp_v1.1.sif
   myapp_v2.0.sif
   ```

2. **Git으로 Definition 관리**
   ```bash
   git add apptainers/*.def
   git commit -m "Add new container definition"
   # .sif 파일은 자동으로 제외됨
   ```

3. **정기 업데이트**
   ```bash
   # cron으로 자동 동기화
   0 2 * * * cd /path/to/project && ./sync_apptainers_to_nodes.sh
   ```

4. **이미지 크기 최적화**
   ```bash
   # 불필요한 파일 제거
   apt-get clean
   rm -rf /var/lib/apt/lists/*
   ```

## 🤝 기여 및 피드백

문제나 개선 사항이 있다면 이슈로 등록해주세요!

---

**작성일**: 2025-10-13  
**버전**: 1.0  
**작성자**: Claude & koopark  
**프로젝트**: KooSlurmInstallAutomationRefactory

## 🎊 완료!

Apptainer 관리 기능이 성공적으로 통합되었습니다.

```bash
./setup_apptainer_features.sh  # 지금 바로 시작하세요!
```
