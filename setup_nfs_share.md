# setup_nfs_share.sh

현재 노드의 디렉토리를 NFS로 export하고, YAML 클러스터 설정 파일에 정의된 모든 노드에 NFS 마운트를 자동 설정하는 스크립트입니다.

## 사용법

```bash
sudo ./setup_nfs_share.sh --config <yaml_config> <source_path> <mount_path>
```

| 인자 | 설명 | 예시 |
|------|------|------|
| `--config PATH` | YAML 클러스터 설정 파일 경로 (필수) | `my_multihead_cluster_2.yaml` |
| `<source_path>` | 현재 노드에서 NFS export할 절대 경로 | `/data` |
| `<mount_path>` | 각 원격 노드에서 마운트할 절대 경로 | `/data` |

## 실행 예시

```bash
# 같은 경로로 공유 (가장 일반적)
sudo ./setup_nfs_share.sh --config my_multihead_cluster_2.yaml /data /data

# 소스와 마운트 경로가 다른 경우
sudo ./setup_nfs_share.sh --config my_multihead_cluster.yaml /scratch /mnt/scratch

# 도움말
./setup_nfs_share.sh --help
```

## 동작 흐름

### Step 0: NFS 오프라인 패키지 준비

1. `offline_packages/nfs/` 디렉토리에 NFS 관련 `.deb` 패키지가 있는지 확인
2. 없으면 현재 노드의 apt 캐시에서 `nfs-kernel-server`, `nfs-common` 및 의존성 패키지를 자동 수집
3. 수집된 패키지는 `offline_packages/nfs/`에 저장되어 이후 재사용 가능

### Step 1: NFS 서버 설정 (현재 노드)

1. `nfs-kernel-server`가 없으면 오프라인 패키지(`dpkg -i`)로 설치
2. YAML의 `network.management_network` 값을 읽어 NFS export 네트워크 범위 결정
3. `/etc/exports`에 export 엔트리 추가 (이미 있으면 비교 후 업데이트)
4. `exportfs -ra`로 적용 후 NFS 서버 재시작

### Step 2: 각 노드에 NFS 마운트

YAML에 정의된 모든 노드(controllers + compute_nodes)에 SSH로 접속하여 마운트를 설정합니다.

각 원격 노드에서 `nfs-common`이 설치되어 있지 않으면:
1. `scp`로 오프라인 패키지를 원격 노드의 `/tmp/_nfs_offline_pkgs/`로 전송
2. `dpkg -i`로 설치 후 임시 파일 정리
3. 설치 검증 후 마운트 진행

## 노드별 처리 로직

### 현재 노드 (스크립트를 실행한 노드)

| 조건 | 동작 |
|------|------|
| `source_path == mount_path` | 건너뜀 (이미 해당 경로가 로컬에 존재) |
| `source_path != mount_path`, 이미 마운트됨 | 건너뜀 |
| `source_path != mount_path`, 미마운트 | `bind mount` 설정 + `/etc/fstab` 등록 |

### 원격 노드

| 상태 | 동작 |
|------|------|
| SSH 연결 실패 | `[FAIL]` 출력 후 건너뜀 |
| 이미 같은 NFS 서버로 마운트됨 | `[SKIP]` 출력 후 건너뜀 |
| 다른 소스로 마운트됨 | `[WARN]` 출력 후 건너뜀 |
| 경로에 기존 데이터 존재 (비어있지 않음) | `[WARN]` 출력 후 건너뜀 |
| nfs-common 미설치 | 오프라인 패키지 scp 전송 + dpkg 설치 |
| 마운트 안 됨 | NFS 마운트 + `/etc/fstab` 등록 |

## 출력 예시

```
╔════════════════════════════════════════════════════════════════════════════════╗
║                         NFS Share Setup                                       ║
╚════════════════════════════════════════════════════════════════════════════════╝

Config:      my_multihead_cluster_2.yaml
Source Path: /data (현재 노드에서 export)
Mount Path:  /data (각 노드에서 마운트)

[INFO] 현재 노드: icn102-0407-h19 (IPs: 10.179.100.25)
[INFO] 총 26개 노드를 설정합니다.

━━━ Step 0: NFS 오프라인 패키지 준비 ━━━

[OK] NFS 오프라인 패키지 이미 존재 (15개 .deb)

━━━ Step 1: NFS 서버 설정 (현재 노드) ━━━

[OK] nfs-kernel-server 이미 설치됨
[OK] NFS export 추가 완료: /data 10.179.100.0/24(rw,sync,no_subtree_check,no_root_squash)
[OK] NFS export 적용 완료
[OK] NFS 서버 시작 완료

━━━ Step 2: 각 노드에 NFS 마운트 설정 ━━━

HOSTNAME                  IP ADDRESS         ROLE         STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
icn102-0407-h19           10.179.100.25      controller   [SKIP] 현재 노드 - 소스/마운트 경로 동일
icn102-0407-h18           10.179.100.24      controller   [OK] NFS 마운트 완료 (/data)
icn102-0407-h14           10.179.100.20      compute      [OK] NFS 마운트 완료 (/data)
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[결과 요약]
  성공: 24개 노드
  건너뜀: 1개 노드
  실패: 0개 노드

[OK] NFS 공유 설정이 완료되었습니다.
```

## 오프라인 패키지 구조

```
offline_packages/
└── nfs/
    ├── nfs-common_*.deb
    ├── nfs-kernel-server_*.deb
    ├── rpcbind_*.deb
    ├── keyutils_*.deb
    ├── libnfsidmap1_*.deb
    ├── libtirpc3_*.deb
    └── ... (기타 의존성)
```

최초 실행 시 현재 노드의 apt 캐시에서 자동 수집됩니다. 이후에는 수집된 패키지를 재사용하므로 인터넷 연결이 필요하지 않습니다.

## 사전 요구사항

- **root 권한**: `sudo`로 실행 필수
- **SSH 키 인증**: 현재 노드에서 각 원격 노드로 비밀번호 없이 SSH 접속 가능해야 함
- **Python3 + PyYAML**: YAML 파싱에 사용 (프로젝트 venv에 포함)
- **네트워크**: 모든 노드가 동일 네트워크에서 통신 가능
- **오프라인 패키지**: 최초 실행 시 현재 노드에 apt 캐시가 있어야 함 (이후 `offline_packages/nfs/`에 캐싱)

## NFS 설정 상세

### Export 옵션

```
rw,sync,no_subtree_check,no_root_squash
```

| 옵션 | 설명 |
|------|------|
| `rw` | 읽기/쓰기 허용 |
| `sync` | 동기 쓰기 (데이터 안정성) |
| `no_subtree_check` | 서브트리 검사 비활성화 (성능 향상) |
| `no_root_squash` | 원격 root를 로컬 root로 매핑 (HPC 환경 필수) |

### Mount 옵션

```
rw,hard,intr,nfsvers=4
```

| 옵션 | 설명 |
|------|------|
| `rw` | 읽기/쓰기 |
| `hard` | NFS 서버 무응답 시 무한 재시도 (데이터 무결성 보장) |
| `intr` | 대기 중 인터럽트 허용 |
| `nfsvers=4` | NFSv4 프로토콜 사용 |

## 영구 마운트

스크립트는 각 노드의 `/etc/fstab`에 마운트 정보를 자동 등록합니다. 따라서 노드 재부팅 후에도 자동으로 마운트됩니다.

## 문제 해결

| 증상 | 원인 / 해결 |
|------|------------|
| `[FAIL] SSH 연결 실패` | SSH 키 설정 확인. `ssh-copy-id`로 키 배포 필요 |
| `[FAIL] NFS 마운트 실패` | 방화벽에서 NFS 포트(2049) 허용 확인. `ufw allow from <network> to any port nfs` |
| `[WARN] 경로에 데이터 존재` | 해당 노드에 이미 데이터가 있음. 수동으로 백업 후 제거하거나 다른 마운트 경로 사용 |
| `[WARN] 다른 소스로 마운트됨` | 이미 다른 NFS 서버나 디바이스가 마운트됨. `umount` 후 재실행 |
| `[FAIL] nfs-common 패키지 설치 실패` | 오프라인 패키지 전송/설치 실패. `offline_packages/nfs/`에 `.deb` 파일이 있는지 확인. 노드 OS 버전 불일치 가능 |
| `NFS 패키지를 수집할 수 없습니다` | 현재 노드에 apt 캐시 없음. `apt-get update` 후 재실행하거나, 수동으로 `.deb` 파일을 `offline_packages/nfs/`에 배치 |
