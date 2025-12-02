# Apptainer 배포 가이드

## 📦 개요

이 가이드는 Apptainer 바이너리 및 컨테이너 이미지를 클러스터의 모든 노드에 배포하는 방법을 설명합니다.

## 🎯 배포 전략

### 로컬 복사 방식 (권장)
- 각 노드의 `/scratch/apptainers/`에 이미지 로컬 복사
- **장점**: 네트워크 병목 방지, 빠른 실행 속도
- **단점**: 각 노드마다 스토리지 사용

### NFS 공유 방식
- 모든 노드가 NFS를 통해 중앙 스토리지 접근
- **장점**: 스토리지 절약, 중앙 관리 용이
- **단점**: 네트워크 병목, 속도 저하

**현재 설정**: 로컬 복사 방식 (`deployment_strategy: local_copy`)

---

## 🚀 사용 방법

### 1. setup_cluster_full.sh 실행 시 자동 배포

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
./setup_cluster_full.sh
```

마지막 단계에서 묻습니다:
```
Apptainer를 모든 노드에 배포하시겠습니까? (y/N):
```

`y` 입력 시 자동으로 `deploy_apptainers.sh` 실행

---

### 2. 수동 배포

#### 전체 배포 (Apptainer + 이미지)

```bash
./deploy_apptainers.sh
```

**수행 작업**:
1. 각 노드에 Apptainer 1.3.3 바이너리 설치
2. 노드 타입별 이미지 복사:
   - compute 노드 → `compute/` 이미지
   - viz 노드 → `visualization/` 이미지

---

#### 이미지만 업데이트 (--update)

```bash
./deploy_apptainers.sh --update
```

**사용 시나리오**:
- Apptainer는 이미 설치됨
- 컨테이너 이미지만 업데이트하고 싶을 때
- VNC 이미지를 새로 빌드한 후

**수행 작업**:
1. Apptainer 설치 스킵
2. 이미지만 rsync로 재복사

---

### 3. 도움말

```bash
./deploy_apptainers.sh --help
```

---

## 📋 배포 대상 노드

현재 `my_cluster.yaml` 설정:

| 노드 | IP | 타입 | 받는 이미지 |
|------|-----|------|------------|
| node001 | 192.168.122.90 | compute | compute/* |
| node002 | 192.168.122.103 | compute | compute/* |
| viz-node001 | 192.168.122.252 | viz | visualization/* |

---

## 🔧 워크플로우 예시

### 시나리오 1: 최초 클러스터 설정

```bash
# 1. 클러스터 설정 (Slurm + MPI 등)
./setup_cluster_full.sh
# → 마지막에 Apptainer 배포 (y)

# 2. 확인
ssh koopark@192.168.122.252 'ls -lh /scratch/apptainers/'
```

---

### 시나리오 2: VNC 이미지 업데이트

```bash
# 1. VNC 샌드박스 재빌드
cd dashboard/vnc_sandbox
./build_vnc_sandbox.sh

# 2. 헤드노드에 이미지 이동
sudo mv /scratch/apptainer_sandboxes/vnc_desktop /scratch/apptainers/visualization/

# 3. 모든 viz 노드에 업데이트 배포
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
./deploy_apptainers.sh --update

# 4. 확인
ssh koopark@192.168.122.252 'du -sh /scratch/apptainers/visualization/vnc_desktop'
```

---

### 시나리오 3: 새 compute 이미지 추가

```bash
# 1. 헤드노드에 이미지 준비
cp my_new_app.sif /scratch/apptainers/compute/

# 2. 모든 compute 노드에 업데이트 배포
./deploy_apptainers.sh --update

# 3. 확인
ssh koopark@192.168.122.90 'ls -lh /scratch/apptainers/compute/'
```

---

## 📊 디렉토리 구조

### 헤드노드 (마스터 이미지)

```
/scratch/apptainers/
├── compute/
│   ├── gromacs.sif
│   ├── tensorflow.sif
│   └── openmpi.sif
└── visualization/
    └── vnc_desktop/        # 8.2GB VNC sandbox
        ├── bin/
        ├── usr/
        └── ...
```

### Compute 노드 (로컬 복사본)

```
/scratch/apptainers/
└── compute/
    ├── gromacs.sif
    ├── tensorflow.sif
    └── openmpi.sif
```

### Viz 노드 (로컬 복사본)

```
/scratch/apptainers/
└── visualization/
    └── vnc_desktop/        # 8.2GB
```

---

## ⚙️ 고급 사용법

### my_cluster.yaml에서 설정 변경

```yaml
container_support:
  apptainer:
    deployment_strategy: local_copy  # 또는 nfs_shared
    master_images_path: /scratch/apptainers
    node_local_path: /scratch/apptainers
    node_type_images:
      compute:
        - compute/gromacs.sif
        - compute/tensorflow.sif
      viz:
        - visualization/vnc_desktop
```

변경 후:
```bash
./deploy_apptainers.sh --update
```

---

### deploy_apptainers.sh 수정

노드 추가/변경 시 스크립트 내부 수정:

```bash
# 배열 수정
NODE_IPS[node003]="192.168.122.104"
NODE_TYPES[node003]="compute"

NODE_IPS[viz-node002]="192.168.122.253"
NODE_TYPES[viz-node002]="viz"
```

---

## 🐛 문제 해결

### SSH 접속 실패
```bash
# SSH 키 복사
ssh-copy-id koopark@192.168.122.252

# 수동 테스트
ssh koopark@192.168.122.252 'hostname'
```

### rsync 실패 (권한 문제)
```bash
# 원격 노드에서
sudo mkdir -p /scratch/apptainers
sudo chown koopark:koopark /scratch
```

### Apptainer 설치 실패
```bash
# 수동 설치
scp apptainer/apptainer-binary-1.3.3.tar.gz koopark@192.168.122.252:/tmp/
ssh koopark@192.168.122.252
cd /tmp && tar -xzf apptainer-binary-1.3.3.tar.gz
sudo install -m 755 apptainer /usr/local/bin/
sudo install -m 644 apptainer.conf /usr/local/etc/
apptainer --version
```

---

## 📈 프로덕션 환경 (370 노드)

대규모 배포 시:

1. **병렬 배포**: `deploy_apptainers.sh`에서 노드를 그룹으로 나눠 병렬 실행
2. **점진적 롤아웃**: 먼저 소수 노드 테스트 후 전체 배포
3. **모니터링**: rsync 진행 상황 로그 파일 저장

```bash
# 예시: 병렬 배포 (GNU Parallel 사용)
parallel -j 10 ./deploy_to_single_node.sh ::: node{001..370} viz-node{001..010}
```

---

## ✅ 체크리스트

- [ ] Apptainer 바이너리 패키지 존재 확인 (`apptainer/apptainer-binary-1.3.3.tar.gz`)
- [ ] 마스터 이미지 존재 확인 (`/scratch/apptainers/`)
- [ ] SSH 키 모든 노드에 복사 완료
- [ ] deploy_apptainers.sh 실행
- [ ] 각 노드에서 검증
  ```bash
  apptainer --version
  ls /scratch/apptainers/
  ```

---

**문서 업데이트**: 2025-10-17
**버전**: 1.0
