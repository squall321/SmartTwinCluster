# 346-Node Multihead Cluster 오프라인 설치 가이드

> 대상: `my_multihead_cluster_346.yaml` 기반 Ubuntu 24.04 오프라인 환경

## 클러스터 구성

| 역할 | 대수 | 노드 |
|------|------|------|
| 컨트롤러 (삼중화) | 3 | icn401-0412-h08, 0413-h08, 0414-h08 |
| 컴퓨트 | 346 | icn401-0101 ~ 0402 |
| GPU/viz (RTX PRO 6000 x2) | 10 | icn401-0401-h[06-10], 0402-h[06-10] |
| **합계** | **359** | |

## 사전 조건

- 모든 노드에 Ubuntu 24.04 설치 완료
- 모든 노드 간 SSH 키 접속 가능 (koopark 계정)
- Compute IP 네트워크(10.228.128.0/16) 통신 확인
- 헤드노드(icn401-0412-h08)에서 모든 노드 SSH 접속 가능

---

## Phase 0: 사전 준비 (온라인 환경에서)

이 단계는 **인터넷 연결된 Ubuntu 24.04 머신**에서 수행합니다.

### 0-1. 프로젝트 전체 복사

```bash
# 이 프로젝트를 USB/NAS 등으로 오프라인 서버에 복사할 준비
# 필요한 디렉토리:
#   - cluster/           (설치 스크립트)
#   - dashboard/         (웹 서비스)
#   - offline_packages_2404/  (24.04 오프라인 패키지)
#   - *.yaml             (클러스터 설정)
#   - *.sh               (메인 스크립트)
```

### 0-2. 24.04 오프라인 패키지 수집

```bash
# Ubuntu 24.04 머신에서 실행 (인터넷 연결 필요)
sudo ./collect_offline_packages.sh --clone-system --yes

# 또는 기본 패키지만:
sudo ./collect_offline_packages.sh --yes
```

### 0-3. 패키지 완성도 확인

현재 `offline_packages_2404/` 상태:

| 항목 | 상태 | 비고 |
|------|------|------|
| APT .deb | 499개 | `--clone-system`으로 추가 수집 권장 |
| Slurm prebuilt | slurm-23.11.10-prebuilt.tar.gz | 완료 |
| Python wheels | **0개 (부족!)** | 아래 명령으로 수집 필요 |
| Munge key | munge.key | 완료 |
| NVIDIA GPU | CUDA 12.4 + 드라이버 550 | RTX PRO 6000용 확인 필요 |

```bash
# Python wheels 수집 (24.04 머신에서)
cd offline_packages_2404/python_wheels
pip download -r ../../dashboard/backend_5010/requirements.txt -d .
pip download -r ../../dashboard/auth_portal_4430/requirements.txt -d .
```

### 0-4. NVIDIA GPU 드라이버 확인

RTX PRO 6000은 최신 드라이버가 필요할 수 있습니다.
현재 포함된 드라이버: `NVIDIA-Linux-x86_64-550.127.05.run` (550 계열)

```bash
# 필요시 최신 드라이버 다운로드 (온라인 환경에서)
# https://www.nvidia.com/download/index.aspx
# RTX PRO 6000 → Linux 64-bit → 최신 Production Branch
```

---

## Phase 1: 오프라인 서버에 프로젝트 전송

### 1-1. 프로젝트 복사

```bash
# USB/NAS/SCP 등으로 프로젝트 전체를 Primary 컨트롤러에 복사
# 대상: icn401-0412-h08 (Primary Controller)

rsync -avz --progress \
  /path/to/KooSlurmInstallAutomationRefactory/ \
  koopark@10.228.133.69:/home/koopark/KooSlurmInstallAutomationRefactory/

# 또는 USB:
# cp -r /media/usb/KooSlurmInstallAutomationRefactory/ /home/koopark/
```

### 1-2. 파일 권한 설정

```bash
cd /home/koopark/KooSlurmInstallAutomationRefactory
chmod 600 my_multihead_cluster_346.yaml   # 비밀번호 포함
chmod +x setup_cluster_full_multihead_offline.sh
chmod +x cluster/setup/phase*.sh
chmod +x collect_offline_packages.sh
chmod +x deploy_apptainers.sh
```

---

## Phase 2: APT 패키지 설치 (헤드노드)

```bash
# Primary 컨트롤러(icn401-0412-h08)에서 실행
cd /home/koopark/KooSlurmInstallAutomationRefactory

# 오프라인 APT 패키지 설치 (로컬 repo 생성 + dpkg 설치)
sudo bash offline_packages_2404/apt_packages/install_offline_packages.sh
```

---

## Phase 3: 메인 설치 스크립트 실행

```bash
# Primary 컨트롤러에서 실행
# --config 옵션으로 346 YAML 지정

sudo -E ./setup_cluster_full_multihead_offline.sh \
  --config my_multihead_cluster_346.yaml
```

이 스크립트가 자동으로 수행하는 것:

| Phase | 내용 | 대상 |
|-------|------|------|
| pre_cleanup | 기존 설정 정리 | 헤드노드 |
| phase0 | GlusterFS 스토리지 구성 | 컨트롤러 3대 |
| phase1 | MariaDB Galera 클러스터 | 컨트롤러 3대 |
| phase2 | Redis 클러스터 | 컨트롤러 3대 |
| phase3 | Slurm 설치 (slurmctld + slurmdbd + slurm.conf + gres.conf) | 컨트롤러 + 컴퓨트 |
| phase4 | Keepalived VIP 구성 | 컨트롤러 3대 |
| phase5 | 웹 서비스 (대시보드, 인증 포탈) | 컨트롤러 |
| phase6 | GPU 드라이버 설치 | GPU 노드 10대 |
| phase8 | Apptainer 컨테이너 배포 | 전체 |
| phase9 | 소프트웨어 설정 | 전체 |
| phase10 | 컴퓨트 노드 배포 (APT + Slurm + Munge) | 컴퓨트 346대 |

---

## Phase 4: 컴퓨트 노드 배포 확인

```bash
# 모든 노드 상태 확인
sinfo -N -l

# 비정상 노드 복구
sudo bash cluster/utils/fix_all_nodes.sh

# 노드별 SSH 접속 테스트
for i in $(scontrol show nodes | grep NodeName | awk -F= '{print $2}' | awk '{print $1}'); do
  echo -n "$i: "
  ssh -o ConnectTimeout=3 $i hostname 2>/dev/null || echo "FAIL"
done
```

---

## Phase 5: GPU 노드 확인

```bash
# GPU 노드에서 nvidia-smi 확인
for node in icn401-0401-h{06..10} icn401-0402-h{06..10}; do
  echo "=== $node ==="
  ssh $node nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "FAIL"
done

# Slurm GRES 확인
scontrol show nodes | grep -A2 "Gres=gpu"
```

---

## Phase 6: Apptainer 이미지 배포

```bash
# SIF 이미지를 전체 노드에 배포
sudo ./deploy_apptainers.sh --config my_multihead_cluster_346.yaml
```

---

## Phase 7: 서비스 최종 확인

```bash
# Slurm 서비스 확인
sinfo
squeue

# 웹 서비스 확인 (브라우저에서)
# https://10.228.128.100/  (VIP 주소)

# 테스트 잡 제출
srun --partition=alpha -N 1 hostname
srun --partition=viz --gres=gpu:1 nvidia-smi

# 노드 헬스체크
sudo bash cluster/utils/health_check.sh
```

---

## 주의사항

### 네트워크
- Compute IP(10.228.128.x)를 Slurm 통신에 사용
- Service IP(10.228.x.x)는 관리/서비스용
- 방화벽에서 Slurm 포트(6817~6819) + SSH(22) 개방 필요

### 패키지 부족 시
- 24.04 오프라인 패키지가 부족하면 인터넷 연결된 24.04 머신에서:
  ```bash
  sudo ./collect_offline_packages.sh --clone-system --yes
  ```
- Python wheels가 비어있으면 대시보드 백엔드가 시작 안 됨

### 삼중화 컨트롤러
- phase3에서 `SlurmctldHost`를 3대 모두 등록
- VIP(10.228.128.100)로 접속하면 자동으로 Active 컨트롤러로 연결
- 컨트롤러 1대가 죽어도 서비스 유지

### GPU 노드
- RTX PRO 6000용 NVIDIA 드라이버 호환성 확인 필요
- `gres.conf`에 `gpu:nvidia:2`로 GPU 2개 등록
- VNC 세션 생성 시 `viz` 파티션 선택

### 트러블슈팅
```bash
# 노드 상태 확인
scontrol show node <NODE_NAME>

# 비정상 노드 강제 복구
sudo bash cluster/utils/fix_all_nodes.sh

# Slurm 로그
tail -f /mnt/gluster/slurm/logs/slurmctld.log

# 서비스 상태
systemctl status slurmctld slurmdbd slurmd munge
```
