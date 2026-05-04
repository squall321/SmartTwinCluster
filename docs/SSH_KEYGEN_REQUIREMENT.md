# SSH 키 인증이 필요한 이유 — SmartTwinCluster 전체 분석

## 개요

SmartTwinCluster는 헤드노드(컨트롤러)에서 수백 대의 컴퓨트 노드를 **비대화형(non-interactive)** 방식으로 관리합니다. 모든 노드 간 통신은 SSH를 기반으로 하며, 비밀번호 입력 없이 자동으로 인증이 이루어져야 합니다.

SSH 키 인증(`ssh-keygen` + `ssh-copy-id`)이 없으면 **클러스터 설치, 운영, 모니터링, 잡 실행**의 거의 모든 기능이 동작하지 않습니다.

---

## 본 HPC 시스템의 특수성 — 왜 일반 HPC보다 SSH가 더 중요한가

### 일반 HPC와의 근본적 차이

일반적인 HPC 클러스터는 **솔버 실행(Job Submission)** 만을 목적으로 합니다. 사용자가 입력 파일을 준비하고, `sbatch`로 잡을 제출하면, 결과 파일을 받아서 끝입니다. 클러스터가 한번 구축되면 노드 구성이 거의 변하지 않으며, Apptainer 이미지도 1~2개로 고정됩니다.

**SmartTwinCluster는 근본적으로 다릅니다.**

본 시스템은 CAE 시뮬레이션의 **전처리(Pre-processing) → 솔버 실행(Solving) → 후처리(Post-processing)** 전 과정을 자동화하는 통합 플랫폼입니다. 솔버만 돌리는 것이 아니라, 모델 수정, 경계조건 부여, 결과 분석, 보고서 생성까지 모두 클러스터 위에서 이루어집니다. 이 자동화 로직은 Apptainer 컨테이너 내부에 패키징되어 각 노드에 배포됩니다.

### 지속적 개발 — 2~3일 주기 배포

| 항목 | 일반 HPC | SmartTwinCluster |
|------|---------|-----------------|
| Apptainer 이미지 변경 주기 | 수개월~수년 | **2~3일에 1회** |
| 자동화 범위 | 솔버 실행만 | 전처리 + 솔버 + 후처리 + 보고서 |
| 노드 배포 빈도 | 초기 설치 후 거의 없음 | **지속적 반복 배포** |
| SSH 사용 빈도 | 설치 시 1회 | **운영 중 상시** |

본 시스템에서 Apptainer 컨테이너는 단순한 솔버 래퍼가 아닙니다. 아래 자동화 기능이 모두 컨테이너 안에 포함되어 있으며, 기능이 추가/수정될 때마다 SIF 이미지를 새로 빌드하고 전 노드(346대 + GPU 10대)에 재배포해야 합니다:

### 전처리 자동화 (KooMeshModifier)

사업부 내외에서 진행되는 모든 CAE 시뮬레이션의 전처리가 자동화됩니다:

- **낙하 시험 자동화**: LS-DYNA 모델에 대해 전각도(Full Angle) 낙하 자세 자동 생성, 바닥판/강체벽 자동 구성, 초기 속도 부여, 접촉 조건 자동 분해
- **충격 시험 자동화**: 낙하 중량(Drop Weight) 충격 시험 설정, 충격자 메시 자동 생성, 부분 강체화
- **경계조건 부여 자동화**: 온갖 시뮬레이션 시나리오(3점 굽힘, 접촉 강성, 약결합 등)의 경계조건을 JSON 설정으로 자동 적용
- **메시 변환**: CNRB→Solid, Solid→TShell, FEM→IGA 등 요소 변환
- **DOE 자동 생성**: 재료 물성 치환, 치수 공차, 위치 변형 등 수백~수천 개 케이스 일괄 생성
- **휨/변형 적용**: Warpage 데이터 기반 노드 좌표 변형, 초기 응력 변환
- **접촉 관리**: AUTOMATIC_GENERAL 접촉 자동 분해, 중복 Tied Contact 감지/제거

**새로운 표준 시뮬레이션이 정의될 때마다** 해당 전처리 로직이 KooMeshModifier에 추가되고, Apptainer 이미지에 포함되어 전 노드에 배포됩니다.

### 후처리 자동화 및 LLM 기반 인사이트 도출

시뮬레이션 결과에 대한 후처리도 지속적으로 발전합니다:

- **d3plot 결과 자동 분석**: 변위/응력/에너지 이력 추출, 임계값 판정
- **LLM 기반 후처리**: AI(Claude API)를 활용한 시뮬레이션 결과 해석, 파라미터 최적화 제안, 자동 인사이트 도출
- **자동 보고서 생성**: 시뮬레이션 결과를 기반으로 표준 보고서 자동 작성
- **비교 분석**: DOE 결과 간 비교, 트렌드 분석, 최적 조건 탐색

**신규 시뮬레이션 유형이 추가되거나 LLM 후처리 로직이 개선될 때마다** 컨테이너 이미지가 업데이트되어야 합니다.

### 배포 주기가 만드는 SSH 의존성

```
[개발 사이클 — 2~3일 주기]

1. 새로운 시뮬레이션 표준 정의 또는 기존 자동화 로직 개선
2. KooMeshModifier / KooChainRun / 후처리 코드 수정
3. Apptainer SIF 이미지 리빌드 (apptainer build)
4. deploy_apptainers.sh로 346 + 10 노드에 배포     ← SSH 필수
   - scp로 SIF 이미지 전송 (수백 MB ~ 수 GB)
   - ssh로 배포 확인 + 서비스 재시작
5. 대시보드에서 새 기능 동작 확인
6. VNC 세션으로 시각적 검증                          ← SSH 터널 필수

이 사이클이 2~3일마다 반복됩니다.
```

일반 HPC에서 SSH 키 인증은 "초기 설치 시 편의를 위한 것"이지만, 본 시스템에서는 **운영 내내 2~3일마다 356대 노드에 반복 배포가 이루어지는 핵심 인프라**입니다. SSH 키 인증이 없으면 매번 356번의 비밀번호 입력이 필요하며, 이는 사실상 운영 불가능을 의미합니다.

### 실제 배포 규모

하나의 SIF 이미지 업데이트 시:
- **전송량**: 500MB x 356대 = **약 174GB** 네트워크 전송
- **SSH 접속 횟수**: 최소 356회 (이미지 확인) + 356회 (SCP 전송) + 356회 (배포 확인) = **약 1,068회**
- **소요 시간**: 병렬 배포 시에도 수십 분~수 시간
- **빈도**: 2~3일에 1회

이 모든 SSH 접속이 비밀번호 프롬프트 없이, 자동으로, 안정적으로 이루어져야 합니다.

---

## 1. 클러스터 초기 설치 (Phase 0~10)

### Phase 0: GlusterFS 스토리지 구성
| 용도 | 명령 |
|------|------|
| 피어 프로브 | `ssh controller2 gluster peer probe controller1` |
| 볼륨 생성 확인 | `ssh controller3 gluster volume info` |
| 서비스 상태 확인 | `ssh NODE_IP systemctl status glusterd` |

컨트롤러 3대 간 GlusterFS 피어 연결 시 SSH로 원격 명령을 실행합니다.

### Phase 1: MariaDB Galera 클러스터
| 용도 | 명령 |
|------|------|
| DB 초기화 | `ssh controller2 sudo galera_new_cluster` |
| 노드 합류 | `ssh controller3 systemctl start mariadb` |
| 상태 확인 | `ssh CONTROLLER wsrep_cluster_size` |

Galera 클러스터 부트스트랩 시 첫 번째 컨트롤러에서 나머지 컨트롤러에 SSH로 명령을 전달합니다.

### Phase 2: Redis 클러스터
| 용도 | 명령 |
|------|------|
| Redis 시작 | `ssh controller2 systemctl start redis` |
| 클러스터 생성 | `redis-cli --cluster create` (로컬이지만 사전 SSH 확인) |

### Phase 3: Slurm 설치 — **가장 SSH 의존도 높음**

```bash
# slurm.conf를 모든 컴퓨트 노드에 동기화
scp $SCP_OPTS slurm.conf ${ssh_user}@${ip_address}:/tmp/slurm.conf
ssh $SSH_OPTS ${ssh_user}@${ip_address} "sudo mv /tmp/slurm.conf /etc/slurm/"

# gres.conf GPU 설정 동기화
scp $SCP_OPTS gres.conf ${ssh_user}@${ip_address}:/tmp/gres.conf
ssh $SSH_OPTS ${ssh_user}@${ip_address} "sudo mv /tmp/gres.conf /etc/slurm/"

# slurmd 재시작
ssh $SSH_OPTS ${ssh_user}@${ip_address} "sudo systemctl restart slurmd"
```

346대 컴퓨트 노드 전체에 설정 파일을 배포하고 서비스를 시작합니다. 비밀번호 인증이면 346번 비밀번호를 입력해야 합니다.

### Phase 4: Keepalived (VIP)
| 용도 | 명령 |
|------|------|
| 설정 배포 | `scp keepalived.conf controller2:/etc/keepalived/` |
| 서비스 시작 | `ssh controller2 systemctl start keepalived` |

### Phase 5: 웹 서비스 배포
| 용도 | 명령 |
|------|------|
| 프론트엔드 빌드 배포 | `scp -r dist/ controller2:/mnt/gluster/frontend_builds/` |
| 서비스 시작 | `ssh controller2 systemctl start dashboard_backend` |
| Nginx 설정 동기화 | `scp hpc-portal.conf controller2:/etc/nginx/conf.d/` |

### Phase 6: GPU 드라이버 설치
```bash
# GPU 노드에 NVIDIA 드라이버 전송 + 설치
scp $SCP_OPTS NVIDIA-Linux-x86_64-550.run ${user}@${gpu_node}:/tmp/
ssh $SSH_OPTS ${user}@${gpu_node} "sudo bash /tmp/NVIDIA-Linux-x86_64-550.run --silent"
```

### Phase 8: Apptainer 컨테이너 배포 (`deploy_apptainers.sh`)
```bash
# SIF 이미지를 각 노드에 전송 (수백 MB~수 GB)
scp -C $SCP_OPTS image.sif ${user}@${ip}:/tmp/
ssh $SSH_OPTS ${user}@${ip} "sudo mv /tmp/image.sif /opt/apptainers/"

# 배포 확인
ssh $SSH_OPTS ${user}@${ip} "sudo ls -lh /opt/apptainers/*.sif"
```

346대 + 10대 GPU 노드에 컨테이너 이미지를 SCP로 전송합니다.

### Phase 9: 소프트웨어 설정
```bash
# 오프라인 APT 패키지 전송 + 설치
scp $SCP_OPTS offline_packages.tar ${user}@${ip}:/tmp/
ssh $SSH_OPTS ${user}@${ip} "cd /tmp && tar xf offline_packages.tar && sudo dpkg -i *.deb"
```

### Phase 10: 컴퓨트 노드 배포
```bash
# Munge 키 동기화 (인증 필수)
scp $SCP_OPTS munge.key ${user}@${ip}:/tmp/
ssh $SSH_OPTS ${user}@${ip} "sudo mv /tmp/munge.key /etc/munge/ && sudo systemctl restart munge"

# Slurm 프리빌드 바이너리 배포
scp $SCP_OPTS slurm-prebuilt.tar.gz ${user}@${ip}:/tmp/
ssh $SSH_OPTS ${user}@${ip} "cd / && sudo tar xzf /tmp/slurm-prebuilt.tar.gz"
```

---

## 2. 클러스터 운영 — 대시보드 서비스

### VNC 원격 데스크톱 (vnc_api.py)

VNC 세션이 viz 노드에서 실행되면, 브라우저는 헤드노드를 통해 접속해야 합니다. 이를 위해 **SSH 포트포워딩 터널**이 필요합니다:

```python
# vnc_api.py — SSH 터널 생성
def create_ssh_tunnel(node, remote_port, local_port, session_id):
    cmd = [SSH, '-f', '-N', '-T', '-g',
           '-o', 'StrictHostKeyChecking=no',
           '-L', f'0.0.0.0:{local_port}:localhost:{remote_port}',
           node]
    subprocess.run(cmd)
```

**흐름:**
```
브라우저 → Nginx(443) → localhost:6988 → [SSH 터널] → viz-node001:6988 → noVNC → VNC 서버
```

SSH 키 인증이 없으면 터널 생성이 불가능하고, VNC 세션 접속이 안 됩니다.

### SIF 이미지 존재 확인 (vnc_api.py)

VNC 세션 생성 전에 viz 노드에 SIF 이미지가 있는지 SSH로 확인합니다:

```python
# vnc_api.py — 원격 노드 이미지 확인
def check_image_exists(sif_path, node, partition):
    ssh_cmd = [SSH] + get_ssh_opts() + [node, f'test -f {sif_path} && echo "exists"']
    result = subprocess.run(ssh_cmd, capture_output=True)
```

### SSH 웹 터미널 (ssh_bp)

대시보드의 SSH Sessions 페이지에서 브라우저 내 터미널을 제공합니다:

```python
# Paramiko를 통한 SSH 연결
import paramiko
client = paramiko.SSHClient()
client.connect(hostname, username=user, key_filename=ssh_key_path)
```

사용자가 브라우저에서 클러스터 노드에 직접 SSH 접속하는 기능이며, 키 인증 기반입니다.

### 노드 관리 (node_bp)

노드 드레인/재개/재부팅 명령을 원격으로 실행합니다:

```python
# 노드 재부팅
ssh $SSH_OPTS ${user}@${node_ip} "sudo reboot"

# 노드 상태 확인
ssh $SSH_OPTS ${user}@${node_ip} "systemctl status slurmd"
```

---

## 3. 클러스터 유지보수

### fix_all_nodes.sh — 비정상 노드 복구

```bash
# 모든 노드 순회하며 상태 점검 + 자동 복구
for node in $(sinfo -h -N -o "%N" | sort -u); do
    ssh $SSH_OPTS $node "systemctl is-active munge slurmd" || {
        # Munge 키 재동기화
        scp munge.key ${node}:/etc/munge/
        ssh $node "systemctl restart munge slurmd"
    }
done
```

### health_check.sh — 헬스 체크

```bash
# 각 노드 SSH 접속 + 서비스 상태 확인
ssh $SSH_OPTS $node "nvidia-smi"          # GPU 상태
ssh $SSH_OPTS $node "df -h"               # 디스크 상태
ssh $SSH_OPTS $node "free -h"             # 메모리 상태
ssh $SSH_OPTS $node "systemctl status slurmd munge"  # 서비스 상태
```

### Munge 키 동기화

Munge는 공유 키 기반 인증입니다. 헤드노드에서 생성한 `munge.key`를 모든 노드에 복사해야 합니다:

```bash
# 모든 노드에 munge.key 배포
for node in $ALL_NODES; do
    scp /etc/munge/munge.key ${user}@${node}:/tmp/
    ssh ${user}@${node} "sudo cp /tmp/munge.key /etc/munge/ && sudo chown munge:munge /etc/munge/munge.key && sudo systemctl restart munge"
done
```

이 작업 자체가 SSH 키 인증을 전제합니다. Munge 인증을 위해 SSH 인증이 먼저 필요한 구조입니다.

---

## 4. 잡 실행 및 데이터 전송

### Slurm sbatch 제출 (간접적 SSH)

Slurm은 자체적으로 `slurmd`를 통해 잡을 실행하지만, 대시보드에서는 SSH를 통해 `sbatch`를 호출합니다:

```python
# vnc_api.py — 잡 스크립트를 로컬에 저장 후 sbatch 실행
script_path = f"/tmp/vnc_job_{session_id}.sh"
result = subprocess.run([SBATCH, script_path], capture_output=True)
```

### 파일 전송 (storage_utils.py)

대시보드의 Data Management에서 노드 간 파일 전송:

```python
# Paramiko SFTP를 통한 파일 전송
sftp = ssh_client.open_sftp()
sftp.put(local_path, remote_path)
sftp.get(remote_path, local_path)
```

### LS-DYNA 잡 제출 (lsdyna_submit_bp)

CAE 시뮬레이션 잡 제출 시 입력 파일을 컴퓨트 노드에 전송:

```bash
# 입력 파일 전송 → Slurm 잡 제출
scp input.k ${user}@${node}:/scratch/jobs/
sbatch --partition=alpha job_script.sh
```

---

## 5. SSH 키 인증의 기술적 요구사항

### 비대화형(Non-Interactive) 실행 필수

클러스터 자동화 스크립트는 `set -uo pipefail` 환경에서 실행됩니다. SSH 접속 시 비밀번호 프롬프트가 뜨면:
- 스크립트가 EOF를 받아 즉시 종료 (`read -p`와 동일한 문제)
- 346대 노드 순회 도중 첫 번째 노드에서 멈춤
- 전체 설치/배포 프로세스 실패

### BatchMode=yes 강제

모든 SSH 명령에 `BatchMode=yes` 옵션이 포함되어 있습니다:

```bash
SSH_OPTS="-o BatchMode=yes -o PreferredAuthentications=publickey"
```

이 설정은 비밀번호 프롬프트를 완전히 차단하고, 키 인증이 실패하면 즉시 에러를 반환합니다. 키 인증이 설정되지 않으면 **모든 SSH 명령이 실패**합니다.

### StrictHostKeyChecking=no

오프라인 환경에서 노드가 처음 설치되면 SSH 호스트 키가 `known_hosts`에 없습니다. 346대 노드의 호스트 키를 수동으로 등록하는 것은 비현실적이므로:

```bash
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

### 타임아웃 설정

대규모 클러스터에서 응답 없는 노드가 전체 프로세스를 블로킹하지 않도록:

```bash
SSH_OPTS="-o ConnectTimeout=10"
```

---

## 6. SSH 키 설정 방법

### 헤드노드에서 키 생성

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

### 모든 노드에 공개키 배포

```bash
# 단일 노드
ssh-copy-id -i ~/.ssh/id_rsa.pub koopark@10.228.128.5

# 전체 노드 일괄 배포 (초기 1회만 비밀번호 필요)
for ip in $(cat cluster_346_nodes.csv | tail -n +2 | cut -d',' -f6); do
    sshpass -p "PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no koopark@${ip}
done
```

### YAML 설정과의 연동

`my_multihead_cluster_346.yaml`에서 SSH 키 경로를 지정합니다:

```yaml
nodes:
  controllers:
    - hostname: icn401-0412-h08
      ssh_user: koopark
      ssh_key_path: ~/.ssh/id_rsa    # 이 키로 모든 SSH 접속
```

Phase 스크립트들은 이 경로에서 키를 읽어 사용합니다:

```bash
SSH_KEY_FILE="${ORIGINAL_HOME}/.ssh/id_rsa"
if [[ -f "$SSH_KEY_FILE" ]]; then
    SSH_OPTS="-i $SSH_KEY_FILE -o BatchMode=yes ..."
fi
```

---

## 7. SSH 키가 없으면 동작하지 않는 기능 목록

| 기능 | 사용 위치 | 영향 |
|------|----------|------|
| 클러스터 설치 (phase0~10) | setup_cluster_full_multihead_offline.sh | 전체 설치 불가 |
| Slurm 설정 동기화 | phase3_slurm.sh | slurm.conf/gres.conf 배포 불가 |
| Munge 키 배포 | phase10, fix_all_nodes.sh | 노드 인증 불가 → Slurm 잡 실행 불가 |
| APT 패키지 배포 | phase9_software.sh | 오프라인 패키지 설치 불가 |
| Apptainer 이미지 배포 | deploy_apptainers.sh, phase8 | SIF 이미지 전송 불가 |
| GPU 드라이버 설치 | phase6_gpu.sh | NVIDIA 드라이버 원격 설치 불가 |
| VNC 원격 데스크톱 | vnc_api.py | SSH 터널 생성 불가 → 접속 불가 |
| SSH 웹 터미널 | ssh_bp (Paramiko) | 브라우저 터미널 불가 |
| 노드 관리 (드레인/재부팅) | node_bp, fix_all_nodes.sh | 원격 제어 불가 |
| 헬스 체크 | health_check.sh | 노드 상태 확인 불가 |
| 파일 전송 | storage_utils.py (SFTP) | 노드 간 파일 이동 불가 |
| GlusterFS 관리 | phase0_storage.sh | 피어 프로브 불가 |
| Galera/Redis 클러스터링 | phase1, phase2 | 삼중화 구성 불가 |
| 잡 로그 조회 | job_logs_bp | 컴퓨트 노드 로그 읽기 불가 |

---

## 요약

SSH 키 인증은 SmartTwinCluster의 **전제 조건**입니다.

- **설치 단계**: 346대 노드에 파일 배포, 패키지 설치, 서비스 시작을 자동화하려면 비밀번호 없는 SSH 접속이 필수
- **운영 단계**: VNC 터널, 웹 SSH, 노드 관리, 헬스 체크 등 대시보드의 핵심 기능이 모두 SSH 키 인증에 의존
- **유지보수**: Munge 키 동기화, 설정 변경 전파, 비정상 노드 복구 등 모든 유지보수 작업이 SSH 기반

키 인증이 설정되지 않으면 클러스터는 **설치도, 운영도, 유지보수도 불가능**합니다.
