# SmartTwinCluster 백업/전송 분류 가이드

오프라인 서버에 프로젝트를 백업/전송할 때, **Git으로 보낼 것**과 **오프라인 매체(USB/외장하드)로 직접 전송할 것**을 구분합니다.

---

## 요약

| 분류 | 크기 | 전송 방법 |
|------|------|-----------|
| **Git 추적** (소스/문서/스크립트) | ~수백 MB | `git clone` |
| **오프라인 전송** (바이너리 패키지) | ~32GB | rsync/USB/외장하드 |
| **선택 전송** (Apptainer SIF) | 수~수십 GB | rsync (필요 시) |
| **재생성 가능** (node_modules, dist, venv) | ~3GB | 오프라인에서 build |

---

## 1. Git에 포함되는 것 (`git clone`으로 전송)

### 추적 대상 (16,136 파일, 약 수백 MB)

| 종류 | 경로 | 설명 |
|------|------|------|
| 클러스터 설치 스크립트 | `cluster/setup/phase*.sh` | Phase 0~10 자동화 |
| YAML 설정 | `*.yaml` | 26/346 클러스터 설정 |
| 대시보드 소스 | `dashboard/*/src/`, `*.py`, `*.tsx` | React/Flask 코드 |
| 오프라인 수집 스크립트 | `offline_packages_2404/*.sh` | VM 자동 수집 |
| Apptainer 빌드 정의 | `dashboard/MoonlightSunshine_8004/*.def`, `dashboard/vnc_sandbox/*.def` | SIF 빌드 레시피 |
| 메인 스크립트 | `setup_cluster_full_multihead*.sh` | 전체 설치 진입점 |
| 문서 | `docs/*.md`, `docs/*.txt` | 가이드/설명 |
| Nginx 설정 | `dashboard/nginx/*.conf` | 리버스 프록시 |
| Slurm 빌드 스크립트 | `offline_packages_2404/slurm/build_slurm_package.sh` | VM 내 Slurm 소스 빌드 |

### Git 사용법

```bash
# 오프라인 서버에서 (인터넷 가능 시):
git clone https://github.com/squall321/SmartTwinCluster.git
cd SmartTwinCluster
git checkout v9.3.0

# 또는 오프라인 환경 (인터넷 없음):
# 작업 머신 → bundle 생성
git bundle create smarttwin.bundle --all

# USB로 옮긴 후 오프라인 서버에서:
git clone smarttwin.bundle SmartTwinCluster
cd SmartTwinCluster
git remote remove origin  # bundle 참조 제거
```

---

## 2. 오프라인 매체로 직접 전송해야 하는 것

### 2-1. `offline_packages_2404/` (Ubuntu 24.04용 — **약 12GB**)

대용량 바이너리들로 git에서 제외됨:

| 디렉토리 | 크기 | 내용 |
|---------|------|------|
| `apt_packages/*.deb` | 1.3GB | 1,622개 .deb (Desktop/VNC/NFS/Monitoring 등 27 카테고리) |
| `apt_packages/Packages*` | 2MB | 로컬 APT repo 인덱스 |
| `python_wheels/*.whl` | 359MB | 298개 Python wheel (Python 3.12/3.13) |
| `slurm/slurm-23.11.10-prebuilt.tar.gz` | 108MB | 24.04에서 빌드된 Slurm 바이너리 |
| `slurm/opt/` | 374MB | Slurm prebuilt 풀린 디렉토리 |
| `gpu/` (심볼릭 링크) | 9.9GB | NVIDIA 550/580 + CUDA 12.4/12.8 (실제는 22.04 디렉토리에 있음) |
| `nodejs/*.tar.xz` | 56MB | Node.js 20.x LTS |
| `munge/munge.key` | <1KB | Slurm 인증 키 |

### 2-2. `offline_packages/` (Ubuntu 22.04용 — **약 30GB**)

선택사항 (22.04 노드 운영 시에만 필요):
- 4,208개 .deb (--clone-system으로 호스트 전체 복사)
- 22.04 prebuilt Slurm
- GPU 드라이버/CUDA (24.04와 공유됨)

**24.04 클러스터만 운영하면 22.04 디렉토리는 전송 안 해도 됩니다.**

### 2-3. Apptainer SIF 이미지 (선택 — 수~수십 GB)

CAE 솔루션/VNC 컨테이너 이미지. 노드에서 `apptainer build`로 만들 수도 있지만, 오프라인 환경에서는 미리 빌드해서 전송하는 게 안전:

| SIF 파일 | 추정 크기 |
|---------|----------|
| `vnc_gnome.sif` (GNOME 데스크톱 + TigerVNC) | 3~5GB |
| `vnc_desktop.sif` (XFCE4 데스크톱 + TigerVNC) | 2~3GB |
| `vnc_gnome_lsprepost.sif` (GNOME + LS-PrePost CAE) | 5~8GB |
| `sunshine_gnome.sif` (GPU 스트리밍) | 4~6GB |
| `LSDynaBasic_*.sif` (LS-DYNA 솔버) | 3~5GB |
| `SmartTwinPreprocessor.sif` (전처리 자동화) | 2~4GB |

위치: `/scratch/apptainers/`, `/opt/apptainers/`, `apptainer/compute-node-images/`

### 2-4. 전송 명령

```bash
# rsync로 외장하드/NAS에 전송
rsync -avh --progress \
  /home/koopark/claude/KooSlurmInstallAutomationRefactory/offline_packages_2404/ \
  /media/external/backup/offline_packages_2404/

# Apptainer SIF
rsync -avh --progress \
  /scratch/apptainers/ \
  /media/external/backup/apptainers/

# 또는 USB로 압축 전송 (체크섬 포함)
tar -czvf - offline_packages_2404/ | tee >(sha256sum > backup.sha256) > /media/usb/offline_2404.tar.gz
```

---

## 3. 재생성 가능 (전송 불필요)

오프라인 서버에서 다시 만들면 되는 것들:

| 디렉토리 | 크기 | 재생성 명령 |
|---------|------|------------|
| `dashboard/*/node_modules/` | ~2.6GB | `npm install` (오프라인 npm cache 필요) |
| `dashboard/*/dist/` | ~30MB | `npm run build` |
| `venv/` (Python 가상환경) | 다양 | `pip install -r requirements.txt --no-index --find-links=./python_wheels` |
| `__pycache__/`, `.pyc` | 작음 | 자동 생성 |
| `.bkit/`, `.claude/` | 작음 | IDE/도구 상태, 무관 |

---

## 4. 권장 백업 워크플로우

### A. 작업 머신 (인터넷 연결됨)

```bash
# 1. Git 푸시 (소스/문서)
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
git push origin main
git push origin --tags

# 2. 오프라인 패키지 압축
tar -czvf /media/external/offline_2404_v9.3.0.tar.gz offline_packages_2404/

# 3. SIF 이미지 압축 (있는 것만)
tar -czvf /media/external/sif_v9.3.0.tar.gz \
  /scratch/apptainers/*.sif \
  /opt/apptainers/*.sif

# 4. 체크섬
sha256sum /media/external/offline_2404_v9.3.0.tar.gz > /media/external/CHECKSUMS.txt
sha256sum /media/external/sif_v9.3.0.tar.gz >> /media/external/CHECKSUMS.txt
```

### B. 오프라인 서버 (인터넷 차단)

```bash
# 1. Git bundle 또는 git clone (사내망 git이 있다면)
git clone <bundle 또는 사내망 URL> SmartTwinCluster
cd SmartTwinCluster
git checkout v9.3.0

# 2. 외장 매체에서 오프라인 패키지 복원
sha256sum -c /media/external/CHECKSUMS.txt
tar -xzvf /media/external/offline_2404_v9.3.0.tar.gz
mv offline_packages_2404 /home/koopark/claude/KooSlurmInstallAutomationRefactory/

# 3. SIF 이미지 복원
sudo mkdir -p /opt/apptainers
sudo tar -xzvf /media/external/sif_v9.3.0.tar.gz -C /opt/apptainers/

# 4. 클러스터 설치
cd SmartTwinCluster
sudo ./setup_cluster_full_multihead_offline.sh --config my_multihead_cluster_346.yaml
```

---

## 5. 예상 총 백업 크기

| 항목 | 크기 |
|------|------|
| Git 저장소 (`git clone --depth=1`) | ~500MB (스크린샷 포함) |
| Git 저장소 (`git clone --bare`) | ~700MB |
| `offline_packages_2404/` | **12GB** |
| Apptainer SIF (전체) | 20~30GB |
| **총합** (24.04 운영 기준) | **약 35~45GB** |

USB 64GB 또는 외장하드면 충분합니다.

---

## 6. 주의사항

- **오프라인 패키지는 OS 버전별로 분리**: 24.04 노드에 22.04 .deb 설치하면 동작 안 함
- **GPU 드라이버 호환성**: NVIDIA 580 .run은 RTX PRO 6000 / RTX 50 시리즈용. 구형 GPU는 550 사용
- **SIF 빌드 시점 의존성**: 컨테이너 .def 파일에 wget URL이 하드코딩 — 오프라인 빌드 시 수정 필요
- **Munge 키**: `offline_packages_2404/munge/munge.key`는 클러스터 보안의 핵심. 분실/유출 주의
- **체크섬 필수**: 대용량 백업은 전송 후 sha256 검증 권장
