# 동적 클러스터링 자동화 구현 계획 (Phase별 상세 가이드)

## 📋 프로젝트 목표

### 핵심 요구사항

1. **자동 탐지 및 동적 클러스터링**
   - 설정 파일에 IP 리스트 등록
   - 현재 활성화된 서버 자동 탐지
   - 현재 서버를 기존 클러스터에 자동 조인 (N중화 → N+1중화)
   - 단독 실행도 가능 (1중화)

2. **공유 스토리지 기반 백업/복원**
   - `/data` → 모든 서버의 공유 스토리지
   - `/data/system_backup` → 백업 데이터 저장소
   - 원클릭 백업 (`backup.sh`)
   - 원클릭 복원 (`restore.sh`)
   - 서버 망가져도 언제든 복구 가능

3. **간편한 실행 방식**
   - `start_multi_complete.sh` → 멀티 클러스터 모드 시작
   - `cluster_config.yaml` → 클러스터 설정 파일
   - 자동으로 현재 상태 감지 및 최적 구성 적용

---

## 🏗️ 전체 아키텍처 개요

### 파일 구조

```
/opt/hpc-dashboard/
├── dashboard/                          # 기존 프로젝트
│   ├── auth_portal_4430/
│   ├── backend_5010/
│   ├── ...
│   └── start_complete.sh               # 기존 단일 서버 시작 스크립트
│
├── cluster/                            # ✨ 새로 추가될 클러스터 관리 디렉토리
│   ├── cluster_config.yaml             # 클러스터 설정 파일
│   ├── start_multi_complete.sh         # 멀티 클러스터 시작 스크립트
│   ├── discovery/
│   │   ├── check_cluster_status.sh     # 클러스터 상태 확인
│   │   ├── auto_discovery.sh           # 활성 노드 자동 탐지
│   │   └── join_cluster.sh             # 클러스터 조인
│   ├── setup/
│   │   ├── phase0_storage_setup.sh     # 공유 스토리지 설정
│   │   ├── phase1_database_setup.sh    # MariaDB Galera 설정
│   │   ├── phase2_redis_setup.sh       # Redis Cluster 설정
│   │   ├── phase3_slurm_setup.sh       # Slurm Multi-Master 설정
│   │   └── phase4_keepalived_setup.sh  # VIP/Keepalived 설정
│   ├── backup/
│   │   ├── backup.sh                   # 원클릭 백업
│   │   ├── restore.sh                  # 원클릭 복원
│   │   └── backup_scheduler.sh         # 자동 백업 스케줄러
│   └── utils/
│       ├── health_check.sh             # 헬스체크
│       ├── cluster_info.sh             # 클러스터 정보 출력
│       └── node_add.sh                 # 노드 추가
│       └── node_remove.sh              # 노드 제거
│
└── /data/                              # ✨ 공유 스토리지 (모든 서버 공통)
    ├── glusterfs/                      # GlusterFS brick
    │   └── shared/
    ├── system_backup/                  # 백업 저장소
    │   ├── configs/                    # 설정 파일 백업
    │   ├── databases/                  # DB 백업
    │   └── state/                      # 클러스터 상태 백업
    └── shared/                         # 애플리케이션 공유 데이터
        ├── frontend_builds/            # 프론트엔드 빌드
        ├── slurm/                      # Slurm 상태 파일
        └── uploads/                    # 사용자 업로드
```

### cluster_config.yaml 예시

```yaml
# 클러스터 설정 파일
cluster:
  name: hpc-portal-cluster

  # 클러스터에 참여 가능한 모든 서버 IP 리스트
  nodes:
    - ip: 192.168.1.101
      hostname: server1
      priority: 100      # Keepalived priority
      role: master       # master 또는 worker (현재는 모두 master)

    - ip: 192.168.1.102
      hostname: server2
      priority: 99
      role: master

    - ip: 192.168.1.103
      hostname: server3
      priority: 98
      role: master

    - ip: 192.168.1.104
      hostname: server4
      priority: 97
      role: master

  # VIP 설정
  vip:
    address: 192.168.1.100
    interface: ens18
    vrrp_router_id: 51
    auth_password: hpc_cluster_secret

  # 공유 스토리지 설정
  storage:
    type: glusterfs              # glusterfs 또는 nfs
    mount_point: /mnt/gluster
    backup_path: /data/system_backup
    brick_path: /data/glusterfs/shared
    volume_name: shared_data
    replica_count: auto          # 'auto' = 활성 노드 수만큼

  # 데이터베이스 설정
  database:
    type: mariadb-galera
    port: 3306
    cluster_name: hpc_portal_cluster
    sst_method: rsync
    databases:
      - name: slurm_acct_db
        user: slurm
        password: ${DB_SLURM_PASSWORD}
      - name: auth_portal
        user: auth_user
        password: ${DB_AUTH_PASSWORD}

  # Redis 설정
  redis:
    type: cluster                # cluster 또는 sentinel
    port: 6379
    password: ${REDIS_PASSWORD}
    replicas: 0                  # 0 = 모든 노드가 master

  # Slurm 설정
  slurm:
    mode: multi-master           # multi-master 또는 ha
    state_location: /mnt/gluster/slurm/state
    log_location: /mnt/gluster/slurm/logs
    spool_location: /var/spool/slurmd

  # 백업 설정
  backup:
    enabled: true
    schedule: "0 2 * * *"        # 매일 새벽 2시
    retention_days: 30
    backup_items:
      - configs
      - databases
      - slurm_state
      - redis_rdb

  # 모니터링 설정
  monitoring:
    prometheus_port: 9090
    node_exporter_port: 9100
    alertmanager_port: 9093
```

---

## 📅 Phase별 구현 계획

---

### Phase 0: 준비 및 공유 스토리지 구성 (3-5일)

**목표**: 모든 서버에서 접근 가능한 공유 스토리지 구축

#### 0.1 사전 준비 (1일)

**작업 내용**:
1. 4대 서버 하드웨어 준비 확인
   - 동일 스펙 확인 (CPU, RAM, Disk)
   - 네트워크 연결 확인 (ping 테스트)
   - SSH 접근 확인

2. `/data` 디렉토리 생성 (각 서버)
   - 용량: 최소 500GB 이상 권장
   - 파일시스템: XFS 또는 EXT4
   - 마운트 포인트 고정

3. 기본 패키지 설치 (각 서버)
   - GlusterFS 클라이언트/서버
   - Python 3.8+
   - PyYAML (cluster_config.yaml 파싱용)
   - jq (JSON 파싱용)

**체크리스트**:
- [ ] 4대 서버 IP 고정 할당 완료
- [ ] `/data` 디렉토리 생성 및 권한 설정 (모든 서버)
- [ ] SSH 키 교환 완료 (패스워드 없이 서로 접속 가능)
- [ ] 방화벽 포트 오픈 (GlusterFS: 24007-24008, 49152-49156)

#### 0.2 GlusterFS 설치 및 Peer 연결 (1일)

**작업 내용**:

1. GlusterFS 서버 설치 (모든 서버)
   ```
   패키지: glusterfs-server
   서비스: glusterd 활성화 및 시작
   ```

2. Peer 연결 (Server1에서 실행)
   - Server2, 3, 4를 Peer로 추가
   - Peer 상태 확인 (모두 Connected 확인)

3. `/data/glusterfs/shared` 디렉토리 생성 (모든 서버)
   - GlusterFS brick으로 사용될 디렉토리
   - 권한: root:root, 755

**체크리스트**:
- [ ] glusterd 서비스 실행 중 (모든 서버)
- [ ] Peer 상태 확인: 4개 노드 모두 Connected
- [ ] Brick 디렉토리 준비 완료

#### 0.3 GlusterFS Volume 생성 (1일)

**작업 내용**:

1. Replica 4 Volume 생성
   - Volume 이름: `shared_data`
   - Replica 수: 4 (4대 모두 복제)
   - Brick: 각 서버의 `/data/glusterfs/shared`

2. Volume 설정 최적화
   - 성능 캐시 설정
   - Network timeout 설정
   - Self-heal 활성화

3. Volume 시작 및 확인
   - Volume 상태 확인
   - Brick 상태 확인 (모두 Online)

**체크리스트**:
- [ ] Volume `shared_data` 생성 완료
- [ ] Volume 시작됨 (Status: Started)
- [ ] 모든 Brick Online 확인

#### 0.4 클라이언트 마운트 및 테스트 (1일)

**작업 내용**:

1. 마운트 포인트 생성 (모든 서버)
   - `/mnt/gluster` 디렉토리 생성

2. Volume 마운트 (모든 서버)
   - `localhost:/shared_data` → `/mnt/gluster`로 마운트
   - `/etc/fstab`에 등록 (재부팅 시 자동 마운트)

3. 디렉토리 구조 생성 (Server1에서만 실행, 자동 복제됨)
   ```
   /mnt/gluster/
   ├── frontend_builds/
   ├── slurm/
   │   ├── state/
   │   ├── logs/
   │   └── spool/
   └── uploads/
   ```

4. 읽기/쓰기 테스트
   - Server1에서 파일 생성
   - Server2/3/4에서 파일 보이는지 확인
   - 동시 쓰기 테스트

**체크리스트**:
- [ ] `/mnt/gluster` 마운트 완료 (모든 서버)
- [ ] 디렉토리 구조 생성 완료
- [ ] 읽기/쓰기 테스트 성공
- [ ] 재부팅 후 자동 마운트 확인

#### 0.5 백업 저장소 준비 (1일)

**작업 내용**:

1. `/data/system_backup` 디렉토리 생성 (모든 서버)
   - 로컬 디스크에 생성 (GlusterFS 아님!)
   - 각 서버의 로컬 백업 저장

2. 백업 디렉토리 구조 생성
   ```
   /data/system_backup/
   ├── configs/              # 설정 파일 백업
   │   ├── nginx/
   │   ├── systemd/
   │   └── cluster/
   ├── databases/            # DB 덤프
   │   ├── mariadb/
   │   └── redis/
   ├── state/                # 클러스터 상태
   │   ├── slurm/
   │   └── glusterfs/
   └── snapshots/            # 전체 스냅샷
       └── YYYYMMDD_HHMMSS/
   ```

3. 백업 보존 정책 설정
   - 일일 백업: 최근 7일
   - 주간 백업: 최근 4주
   - 월간 백업: 최근 12개월

**체크리스트**:
- [ ] `/data/system_backup` 디렉토리 생성 (모든 서버)
- [ ] 백업 디렉토리 구조 생성 완료
- [ ] 디스크 용량 확인 (최소 100GB 여유)

**Phase 0 완료 조건**:
- ✅ GlusterFS 4-node 클러스터 정상 작동
- ✅ 모든 서버에서 `/mnt/gluster` 접근 가능
- ✅ 백업 저장소 준비 완료

---

### Phase 1: 클러스터 탐지 및 자동 구성 프레임워크 (1주)

**목표**: 자동으로 활성 노드를 탐지하고 클러스터에 조인하는 시스템 구축

#### 1.1 cluster_config.yaml 파싱 모듈 (1일)

**작업 내용**:

1. `cluster/utils/config_parser.py` 작성
   - YAML 파일 읽기
   - 환경변수 치환 (${DB_PASSWORD} 등)
   - 노드 리스트 반환
   - VIP 정보 반환
   - 스토리지 설정 반환

2. 설정 검증 기능
   - 필수 필드 체크
   - IP 주소 형식 확인
   - 중복 IP 체크
   - Priority 중복 체크

3. 명령줄 도구 작성
   ```bash
   ./cluster/utils/config_parser.py --list-nodes
   ./cluster/utils/config_parser.py --get-vip
   ./cluster/utils/config_parser.py --validate
   ```

**체크리스트**:
- [ ] config_parser.py 작성 완료
- [ ] YAML 파싱 테스트 성공
- [ ] 환경변수 치환 테스트 성공
- [ ] 설정 검증 테스트 성공

#### 1.2 자동 탐지 시스템 (2일)

**작업 내용**:

1. `cluster/discovery/auto_discovery.sh` 작성

   **기능**:
   - `cluster_config.yaml`에서 노드 리스트 읽기
   - 각 노드에 SSH 접속 시도 (타임아웃 5초)
   - 헬스체크 엔드포인트 확인 (`http://IP:4430/health`)
   - GlusterFS peer 상태 확인
   - MariaDB Galera 상태 확인 (있다면)
   - Redis Cluster 상태 확인 (있다면)

   **출력 형식** (JSON):
   ```json
   {
     "total_nodes": 4,
     "active_nodes": 3,
     "inactive_nodes": 1,
     "nodes": [
       {
         "ip": "192.168.1.101",
         "hostname": "server1",
         "status": "active",
         "services": {
           "ssh": true,
           "glusterfs": true,
           "mariadb": true,
           "redis": true,
           "web": true
         },
         "load": 0.35,
         "uptime": "5 days"
       },
       {
         "ip": "192.168.1.104",
         "hostname": "server4",
         "status": "inactive",
         "services": {},
         "error": "Connection timeout"
       }
     ],
     "cluster_state": "healthy",
     "vip_owner": "192.168.1.101"
   }
   ```

2. `cluster/discovery/check_cluster_status.sh` 작성

   **기능**:
   - 현재 서버가 클러스터에 속해있는지 확인
   - 클러스터 모드인지 단독 모드인지 판단
   - 클러스터 크기 반환 (N중화)

   **반환값**:
   - `standalone`: 단독 모드 (클러스터 미구성)
   - `cluster-2`: 이중화
   - `cluster-3`: 삼중화
   - `cluster-4`: 사중화

3. `cluster/utils/health_check.sh` 작성

   **기능**:
   - 현재 서버의 모든 핵심 서비스 상태 확인
   - HTTP 엔드포인트 제공 (`/health`)
   - JSON 형식 반환

   **체크 항목**:
   - Slurm (slurmctld, slurmdbd)
   - MariaDB (Galera 노드 상태)
   - Redis (Cluster 노드 상태)
   - 웹서비스 (auth, dashboard, cae)
   - GlusterFS (Volume 마운트 상태)
   - 디스크 용량 (80% 이상이면 warning)
   - 메모리 사용률

**체크리스트**:
- [ ] auto_discovery.sh 작성 완료
- [ ] 활성 노드 자동 탐지 테스트 성공
- [ ] check_cluster_status.sh 작성 완료
- [ ] health_check.sh 작성 완료
- [ ] HTTP 헬스체크 엔드포인트 작동 확인

#### 1.3 클러스터 조인 로직 (2일)

**작업 내용**:

1. `cluster/discovery/join_cluster.sh` 작성

   **실행 흐름**:
   ```
   [1] cluster_config.yaml 읽기
        ↓
   [2] 활성 노드 자동 탐지 (auto_discovery.sh 호출)
        ↓
   [3] 현재 클러스터 상태 확인
        - 활성 노드 0개 → 새 클러스터 생성 (Bootstrap)
        - 활성 노드 1개 이상 → 기존 클러스터 조인
        ↓
   [4] 조인 전 체크
        - 현재 서버가 이미 클러스터에 속해있는지?
        - GlusterFS Peer 연결되어 있는지?
        - MariaDB Galera 연결되어 있는지?
        ↓
   [5] 조인 실행
        - GlusterFS: peer probe
        - MariaDB: 클러스터 주소 추가 후 재시작
        - Redis: cluster meet
        - Slurm: 설정 파일 동기화 후 재시작
        ↓
   [6] 조인 검증
        - GlusterFS: peer status
        - MariaDB: wsrep_cluster_size 확인
        - Redis: cluster nodes 확인
        - Slurm: scontrol show config
        ↓
   [7] Keepalived 설정 및 시작
        - Priority는 cluster_config.yaml에서 가져옴
        - VIP는 가장 높은 Priority 서버가 소유
        ↓
   [8] 클러스터 정보 출력
        - 현재 N중화 → N+1중화 완료
        - 각 서비스 상태
   ```

2. `cluster/utils/cluster_info.sh` 작성

   **기능**:
   - 현재 클러스터 전체 상태 요약 출력
   - 사용자 친화적인 표 형식

   **출력 예시**:
   ```
   ========================================
   HPC Portal Cluster Status
   ========================================
   Cluster Name: hpc-portal-cluster
   Cluster Size: 4-node (Quad Redundancy)
   VIP: 192.168.1.100 (owned by server1)
   Uptime: 15 days

   Node Status:
   +------------+---------------+----------+--------+
   | Hostname   | IP            | Status   | Load   |
   +------------+---------------+----------+--------+
   | server1    | 192.168.1.101 | Active   | 0.35   |
   | server2    | 192.168.1.102 | Active   | 0.42   |
   | server3    | 192.168.1.103 | Active   | 0.38   |
   | server4    | 192.168.1.104 | Active   | 0.29   |
   +------------+---------------+----------+--------+

   Service Status:
   - GlusterFS: 4/4 nodes (Healthy)
   - MariaDB Galera: 4/4 nodes (Synced)
   - Redis Cluster: 4/4 nodes (OK)
   - Slurm: Primary on server1 (3 backups ready)
   - Web Services: All running

   Storage:
   - Shared: 850GB / 2TB (42%)
   - Backup: 120GB / 500GB (24%)

   Last Backup: 2025-10-26 02:00:00
   ========================================
   ```

**체크리스트**:
- [ ] join_cluster.sh 작성 완료
- [ ] 신규 클러스터 생성 테스트 (Bootstrap)
- [ ] 기존 클러스터 조인 테스트 (2중화 → 3중화)
- [ ] cluster_info.sh 작성 완료

#### 1.4 start_multi_complete.sh 메인 스크립트 (2일)

**작업 내용**:

1. `cluster/start_multi_complete.sh` 작성

   **옵션**:
   - `--bootstrap`: 새 클러스터 생성 (첫 노드)
   - `--join`: 기존 클러스터 조인
   - `--standalone`: 단독 모드로 실행
   - `--status`: 현재 상태만 확인
   - `--force`: 강제 실행 (체크 무시)

   **실행 흐름**:
   ```
   [1] 환경 체크
        - root 권한 확인
        - cluster_config.yaml 존재 확인
        - /data, /mnt/gluster 확인
        ↓
   [2] 모드 결정
        - --bootstrap 옵션 → Bootstrap 모드
        - --standalone 옵션 → 단독 모드
        - 기본값 → 자동 탐지 후 결정
        ↓
   [3] 자동 탐지 (--standalone 아닌 경우)
        - auto_discovery.sh 실행
        - 활성 노드 수 확인
        ↓
   [4] 클러스터 구성
        - 활성 노드 0개 → Bootstrap
        - 활성 노드 1개+ → Join
        - 단독 모드 → Skip
        ↓
   [5] 서비스 시작
        - MariaDB
        - Redis
        - Slurm
        - 웹서비스 (기존 start_complete.sh 호출)
        - Keepalived (클러스터 모드만)
        ↓
   [6] 헬스체크
        - 5초 대기 후 모든 서비스 확인
        - 실패 시 롤백
        ↓
   [7] 클러스터 정보 출력
        - cluster_info.sh 호출
        ↓
   [8] 백업 스케줄러 시작
        - backup_scheduler.sh 백그라운드 실행
   ```

2. 에러 처리 및 롤백
   - 각 단계에서 실패 시 이전 상태로 복원
   - 로그 파일 저장 (`/var/log/cluster_setup.log`)
   - 실패 원인 명확히 출력

3. 사용자 확인 프롬프트
   - 위험한 작업 전 확인 (Y/N)
   - `--force` 옵션으로 스킵 가능

**체크리스트**:
- [ ] start_multi_complete.sh 작성 완료
- [ ] Bootstrap 모드 테스트
- [ ] Join 모드 테스트
- [ ] Standalone 모드 테스트
- [ ] 에러 처리 및 롤백 테스트

**Phase 1 완료 조건**:
- ✅ cluster_config.yaml 자동 파싱
- ✅ 활성 노드 자동 탐지
- ✅ 동적 클러스터 조인 (N→N+1)
- ✅ start_multi_complete.sh 정상 작동
- ✅ 단독 모드도 정상 작동

---

### Phase 2: MariaDB Galera 동적 클러스터링 (1주)

**목표**: 노드 수에 관계없이 자동으로 Galera Cluster 구성

#### 2.1 Galera 설정 템플릿 (1일)

**작업 내용**:

1. `/etc/mysql/mariadb.conf.d/galera.cnf.template` 작성

   **템플릿 변수**:
   - `{{NODE_IP}}`: 현재 노드 IP
   - `{{NODE_NAME}}`: 현재 노드 호스트명
   - `{{CLUSTER_NAME}}`: 클러스터 이름
   - `{{CLUSTER_ADDRESSES}}`: 모든 활성 노드 IP (쉼표 구분)

   **예시**:
   ```ini
   [galera]
   wsrep_on=ON
   wsrep_provider=/usr/lib/galera/libgalera_smm.so
   wsrep_cluster_name="{{CLUSTER_NAME}}"
   wsrep_cluster_address="gcomm://{{CLUSTER_ADDRESSES}}"
   wsrep_node_address="{{NODE_IP}}"
   wsrep_node_name="{{NODE_NAME}}"
   binlog_format=row
   default_storage_engine=InnoDB
   innodb_autoinc_lock_mode=2
   wsrep_sst_method=rsync
   ```

2. `cluster/setup/phase1_database_setup.sh` 작성

   **기능**:
   - MariaDB 설치 (미설치 시)
   - 템플릿 → 실제 설정 파일 생성
   - 활성 노드 리스트를 `wsrep_cluster_address`에 자동 입력
   - Bootstrap vs Join 자동 결정

   **실행 흐름**:
   ```
   [1] MariaDB 설치 확인
        ↓
   [2] 활성 Galera 노드 탐지
        - 각 노드의 3306 포트 체크
        - wsrep_cluster_size 쿼리
        ↓
   [3] 모드 결정
        - 활성 Galera 노드 0개 → Bootstrap (첫 노드)
        - 활성 Galera 노드 1개+ → Join
        ↓
   [4] 설정 파일 생성
        - 템플릿에 변수 치환
        - /etc/mysql/mariadb.conf.d/galera.cnf 저장
        ↓
   [5] 시작
        - Bootstrap: galera_new_cluster
        - Join: systemctl start mariadb
        ↓
   [6] 검증
        - wsrep_cluster_size 확인
        - wsrep_ready = ON 확인
        - wsrep_local_state_comment = Synced 확인
        ↓
   [7] 데이터베이스 초기화 (Bootstrap만)
        - slurm_acct_db 생성
        - auth_portal 생성
        - 사용자 생성
   ```

**체크리스트**:
- [ ] Galera 설정 템플릿 작성 완료
- [ ] phase1_database_setup.sh 작성 완료
- [ ] Bootstrap 모드 테스트 (첫 노드)
- [ ] Join 모드 테스트 (2번째 노드)

#### 2.2 동적 노드 추가/제거 (2일)

**작업 내용**:

1. `cluster/utils/node_add.sh --service mariadb` 작성

   **기능**:
   - 새 노드를 Galera 클러스터에 추가
   - 기존 노드들의 `wsrep_cluster_address` 업데이트
   - 롤링 리로드 (무중단)

   **실행 흐름**:
   ```
   [1] 새 노드에서 MariaDB 설정
        - galera.cnf 생성 (모든 활성 노드 포함)
        ↓
   [2] 새 노드에서 MariaDB 시작
        - systemctl start mariadb
        ↓
   [3] 기존 노드들에 새 노드 추가
        - wsrep_cluster_address에 새 IP 추가
        - SET GLOBAL wsrep_cluster_address='gcomm://...'
        - (재시작 불필요!)
        ↓
   [4] 검증
        - wsrep_cluster_size = N+1 확인
   ```

2. `cluster/utils/node_remove.sh --service mariadb` 작성

   **기능**:
   - 노드를 Galera 클러스터에서 제거
   - 제거된 노드에서 MariaDB 중지
   - 나머지 노드들의 `wsrep_cluster_address` 업데이트

   **안전 장치**:
   - 마지막 노드는 제거 불가
   - 쿼럼 유지 확인 (최소 2개 노드 필요)

**체크리스트**:
- [ ] node_add.sh MariaDB 추가 테스트
- [ ] node_remove.sh MariaDB 제거 테스트
- [ ] 무중단 추가/제거 확인

#### 2.3 자동 복구 및 재조인 (2일)

**작업 내용**:

1. `cluster/utils/galera_auto_recover.sh` 작성

   **시나리오 1: 전체 클러스터 다운 후 복구**
   - 모든 노드의 `grastate.dat` 확인
   - 가장 최신 `seqno`를 가진 노드 찾기
   - 해당 노드에서 `galera_new_cluster` (Bootstrap)
   - 나머지 노드들 순차 재조인

   **시나리오 2: 일부 노드 재시작**
   - 기존 클러스터 활성 확인
   - 단순히 `systemctl start mariadb`로 자동 조인

   **시나리오 3: Split-brain 감지 및 복구**
   - `wsrep_cluster_size`가 예상과 다른 경우
   - 수동 개입 필요 경고 출력

2. Systemd 서비스 수정
   - `mariadb.service`에 자동 복구 스크립트 추가
   - 재시작 정책: `Restart=on-failure`, `RestartSec=10s`

**체크리스트**:
- [ ] 전체 다운 복구 테스트
- [ ] 일부 노드 재조인 테스트
- [ ] Split-brain 감지 테스트

#### 2.4 백업 및 복원 (2일)

**작업 내용**:

1. `cluster/backup/backup_mariadb.sh` 작성

   **백업 방식**:
   - `mysqldump --all-databases` (논리 백업)
   - 압축: gzip
   - 저장 위치: `/data/system_backup/databases/mariadb/`
   - 파일명: `mariadb_YYYYMMDD_HHMMSS.sql.gz`

   **증분 백업** (선택 사항):
   - Binary log 기반
   - 매 시간 증분 백업

2. `cluster/backup/restore_mariadb.sh` 작성

   **복원 절차**:
   ```
   [1] 모든 노드에서 MariaDB 중지
        ↓
   [2] 첫 노드에서 복원
        - DROP DATABASE (기존 DB 삭제)
        - mysql < backup.sql
        ↓
   [3] Bootstrap
        - galera_new_cluster
        ↓
   [4] 나머지 노드 조인
        - SST로 자동 동기화
   ```

**체크리스트**:
- [ ] 백업 스크립트 작성 및 테스트
- [ ] 복원 스크립트 작성 및 테스트
- [ ] 증분 백업 테스트 (선택)

**Phase 2 완료 조건**:
- ✅ MariaDB Galera 동적 클러스터링 작동
- ✅ 노드 추가/제거 무중단 가능
- ✅ 자동 복구 시스템 작동
- ✅ 백업/복원 시스템 작동

---

### Phase 3: Redis Cluster 동적 클러스터링 (1주)

**목표**: 노드 수에 관계없이 자동으로 Redis Cluster 구성

#### 3.1 Redis 설정 템플릿 (1일)

**작업 내용**:

1. `/etc/redis/redis.conf.template` 작성

   **클러스터 모드 설정**:
   ```
   bind 0.0.0.0
   port 6379
   cluster-enabled yes
   cluster-config-file nodes-6379.conf
   cluster-node-timeout 5000
   appendonly yes
   requirepass {{REDIS_PASSWORD}}
   masterauth {{REDIS_PASSWORD}}
   ```

2. `cluster/setup/phase2_redis_setup.sh` 작성

   **실행 흐름**:
   ```
   [1] Redis 설치 확인
        ↓
   [2] 설정 파일 생성
        - 템플릿에서 비밀번호 치환
        ↓
   [3] Redis 시작
        - systemctl start redis-server
        ↓
   [4] 활성 Redis 노드 탐지
        - 각 노드의 6379 포트 체크
        - CLUSTER INFO 쿼리
        ↓
   [5] 클러스터 생성 vs 조인
        - 활성 Redis 노드 0개 → 새 클러스터 생성
        - 활성 Redis 노드 1개+ → 기존 클러스터 조인
   ```

**체크리스트**:
- [ ] Redis 설정 템플릿 작성 완료
- [ ] phase2_redis_setup.sh 작성 완료

#### 3.2 Redis Cluster 생성 및 조인 (2일)

**작업 내용**:

1. 새 클러스터 생성 (Bootstrap)

   **명령**:
   ```bash
   redis-cli --cluster create \
       192.168.1.101:6379 \
       192.168.1.102:6379 \
       ... \
       --cluster-replicas 0 \
       -a $REDIS_PASSWORD
   ```

   **주의사항**:
   - `--cluster-replicas 0`: 모든 노드가 Master
   - 최소 3개 노드 필요 (Redis Cluster 제약)
   - 2개 노드인 경우: Sentinel 모드 사용

2. 기존 클러스터 조인

   **명령**:
   ```bash
   redis-cli --cluster add-node \
       <새노드IP>:6379 \
       <기존노드IP>:6379 \
       -a $REDIS_PASSWORD
   ```

   **해시 슬롯 재분배**:
   ```bash
   redis-cli --cluster rebalance \
       <클러스터IP>:6379 \
       --cluster-use-empty-masters \
       -a $REDIS_PASSWORD
   ```

3. 2개 노드 특수 처리 (Sentinel 모드)

   **이유**: Redis Cluster는 최소 3개 노드 필요

   **대안**: Redis Sentinel (Master-Replica)
   - Server1: Master
   - Server2: Replica
   - 자동 failover

**체크리스트**:
- [ ] 3개+ 노드 클러스터 생성 테스트
- [ ] 노드 조인 테스트
- [ ] 해시 슬롯 재분배 테스트
- [ ] 2개 노드 Sentinel 모드 테스트

#### 3.3 동적 노드 추가/제거 (2일)

**작업 내용**:

1. `cluster/utils/node_add.sh --service redis` 작성

   **실행 흐름**:
   ```
   [1] 새 노드에서 Redis 시작
        ↓
   [2] 클러스터에 추가
        - redis-cli --cluster add-node
        ↓
   [3] 해시 슬롯 재분배
        - redis-cli --cluster rebalance
        ↓
   [4] 검증
        - CLUSTER INFO (cluster_size 확인)
   ```

2. `cluster/utils/node_remove.sh --service redis` 작성

   **실행 흐름**:
   ```
   [1] 제거할 노드의 해시 슬롯 재분배
        - reshard (슬롯을 다른 노드로 이동)
        ↓
   [2] 노드 제거
        - redis-cli --cluster del-node
        ↓
   [3] Redis 중지 (제거된 노드)
        - systemctl stop redis-server
   ```

**체크리스트**:
- [ ] Redis 노드 추가 테스트
- [ ] Redis 노드 제거 테스트
- [ ] 무중단 재분배 확인

#### 3.4 백업 및 복원 (2일)

**작업 내용**:

1. `cluster/backup/backup_redis.sh` 작성

   **백업 방식**:
   - RDB 스냅샷 (`SAVE` 명령)
   - AOF 파일 복사
   - 저장 위치: `/data/system_backup/databases/redis/`

   **주의사항**:
   - 모든 노드 백업 (각 노드가 다른 키 보유)
   - 또는 마스터 1개만 백업 (세션 데이터는 일시적이므로)

2. `cluster/backup/restore_redis.sh` 작성

   **복원 방식**:
   - RDB 파일을 `/var/lib/redis/`에 복사
   - Redis 재시작
   - 클러스터 재구성

**체크리스트**:
- [ ] Redis 백업 스크립트 작성
- [ ] Redis 복원 스크립트 작성

**Phase 3 완료 조건**:
- ✅ Redis Cluster 동적 클러스터링 작동
- ✅ 노드 추가/제거 무중단 가능
- ✅ 백업/복원 시스템 작동

---

### Phase 4: Slurm Multi-Master 동적 구성 (1주)

**목표**: 활성 노드를 모두 백업 컨트롤러로 등록

#### 4.1 Slurm 설정 동적 생성 (2일)

**작업 내용**:

1. `/etc/slurm/slurm.conf.template` 작성

   **동적 부분**:
   ```bash
   # Multi-Master 설정 (동적 생성)
   {{SLURMCTLD_HOSTS}}
   # 예: SlurmctldHost=server1(192.168.1.101)
   #     SlurmctldHost=server2(192.168.1.102)
   #     ...

   StateSaveLocation=/mnt/gluster/slurm/state
   SlurmdSpoolDir=/var/spool/slurmd
   SlurmctldLogFile=/mnt/gluster/slurm/logs/slurmctld.log

   AccountingStorageType=accounting_storage/slurmdbd
   AccountingStorageHost=127.0.0.1
   ```

2. `cluster/setup/phase3_slurm_setup.sh` 작성

   **실행 흐름**:
   ```
   [1] Slurm 설치 확인
        ↓
   [2] 활성 노드 탐지
        - auto_discovery.sh 호출
        ↓
   [3] slurm.conf 동적 생성
        - 모든 활성 노드를 SlurmctldHost로 등록
        - /mnt/gluster/slurm/config/slurm.conf 저장 (공유)
        ↓
   [4] 심볼릭 링크 생성
        - ln -s /mnt/gluster/slurm/config/slurm.conf /etc/slurm/slurm.conf
        ↓
   [5] slurmdbd 설정
        - MariaDB 로컬 연결 (Galera)
        ↓
   [6] 서비스 시작
        - slurmdbd 먼저 시작
        - slurmctld 시작
        ↓
   [7] 검증
        - scontrol show config
        - sacctmgr show cluster
   ```

**체크리스트**:
- [ ] slurm.conf 템플릿 작성
- [ ] phase3_slurm_setup.sh 작성
- [ ] 동적 설정 생성 테스트

#### 4.2 VIP 전환 시 Slurm Controller 자동 전환 (2일)

**작업 내용**:

1. Keepalived 알림 스크립트 수정

   **`/usr/local/bin/notify_master.sh`**:
   ```bash
   #!/bin/bash
   # VIP를 받으면 slurmctld를 Primary로 승격

   systemctl restart slurmctld
   logger "This node is now Slurm PRIMARY controller (VIP acquired)"
   ```

   **`/usr/local/bin/notify_backup.sh`**:
   ```bash
   #!/bin/bash
   # VIP를 잃으면 slurmctld를 Backup으로 유지

   systemctl restart slurmctld
   logger "This node is now Slurm BACKUP controller (VIP lost)"
   ```

2. Slurm Controller HA 동작 확인

   **테스트 시나리오**:
   - Server1 (VIP 소유) 중지
   - VIP가 Server2로 이동
   - Server2의 slurmctld가 자동으로 Active
   - 진행 중인 작업 영향 없음

**체크리스트**:
- [ ] Keepalived 알림 스크립트 작성
- [ ] VIP 전환 시 slurmctld 자동 전환 테스트

#### 4.3 동적 노드 추가/제거 (2일)

**작업 내용**:

1. `cluster/utils/node_add.sh --service slurm` 작성

   **실행 흐름**:
   ```
   [1] 새 노드 추가
        - slurm.conf에 SlurmctldHost 추가
        ↓
   [2] 모든 노드에 설정 동기화
        - GlusterFS를 통해 자동 동기화
        ↓
   [3] 모든 노드에서 slurmctld 재설정
        - scontrol reconfigure
        ↓
   [4] 검증
        - scontrol show config
   ```

2. Slurm 재설정 자동화
   - 새 노드 추가 시 무중단 재설정
   - `scontrol reconfigure` 사용 (재시작 불필요)

**체크리스트**:
- [ ] Slurm 노드 추가 테스트
- [ ] Slurm 노드 제거 테스트
- [ ] 무중단 재설정 확인

#### 4.4 백업 및 복원 (1일)

**작업 내용**:

1. `cluster/backup/backup_slurm.sh` 작성

   **백업 항목**:
   - `/mnt/gluster/slurm/state/` (작업 큐, 노드 상태)
   - `/etc/slurm/slurm.conf` (설정 파일)
   - MariaDB의 `slurm_acct_db` (별도 백업과 통합)

2. `cluster/backup/restore_slurm.sh` 작성

   **복원 절차**:
   - 상태 파일 복원
   - 설정 파일 복원
   - slurmctld 재시작

**체크리스트**:
- [ ] Slurm 백업 스크립트 작성
- [ ] Slurm 복원 스크립트 작성

**Phase 4 완료 조건**:
- ✅ Slurm Multi-Master 동적 구성
- ✅ VIP 전환 시 자동 Controller 전환
- ✅ 무중단 노드 추가/제거
- ✅ 백업/복원 시스템 작동

---

### Phase 5: Keepalived 동적 VIP 관리 (3일)

**목표**: 활성 노드에 자동으로 Priority 할당 및 VIP 관리

#### 5.1 Keepalived 설정 동적 생성 (1일)

**작업 내용**:

1. `/etc/keepalived/keepalived.conf.template` 작성

   **동적 부분**:
   ```
   vrrp_instance VI_1 {
       state {{STATE}}              # MASTER or BACKUP
       interface {{INTERFACE}}      # ens18
       virtual_router_id {{VRRP_ID}}
       priority {{PRIORITY}}        # cluster_config.yaml에서 가져옴
       ...
       virtual_ipaddress {
           {{VIP}}
       }
   }
   ```

2. `cluster/setup/phase4_keepalived_setup.sh` 작성

   **실행 흐름**:
   ```
   [1] 현재 노드 IP 확인
        ↓
   [2] cluster_config.yaml에서 Priority 찾기
        ↓
   [3] 가장 높은 Priority인지 확인
        - Yes → STATE=MASTER
        - No → STATE=BACKUP
        ↓
   [4] keepalived.conf 생성
        ↓
   [5] Keepalived 시작
        ↓
   [6] VIP 확인
        - MASTER인 경우 VIP 소유 확인
   ```

**체크리스트**:
- [ ] Keepalived 설정 템플릿 작성
- [ ] phase4_keepalived_setup.sh 작성
- [ ] Priority 동적 할당 테스트

#### 5.2 헬스체크 스크립트 개선 (1일)

**작업 내용**:

1. `check_all_services.sh` 작성 (Phase 1에서 작성한 것 개선)

   **체크 항목 확대**:
   - GlusterFS 마운트 상태
   - MariaDB Galera 동기화 상태
   - Redis Cluster 노드 상태
   - Slurm slurmctld 실행 상태
   - 웹서비스 HTTP 응답
   - 디스크 여유 공간 (80% 이상이면 실패)

   **가중치 시스템**:
   - 치명적 서비스 실패 → weight -100 (즉시 VIP 이동)
   - 비치명적 서비스 실패 → weight -20 (누적되면 이동)

**체크리스트**:
- [ ] 헬스체크 스크립트 개선
- [ ] 가중치 시스템 테스트

#### 5.3 VIP 전환 테스트 (1일)

**작업 내용**:

1. 자동 전환 시나리오 테스트

   **시나리오 1**: MASTER 노드 완전 다운
   - Server1 (MASTER) 전원 차단
   - VIP가 Server2로 이동 (2-3초)
   - Slurm, 웹서비스 자동 전환

   **시나리오 2**: MASTER 노드 서비스 장애
   - Server1의 MariaDB 중지
   - 헬스체크 실패
   - VIP가 Server2로 이동

   **시나리오 3**: MASTER 노드 복구
   - Server1 재시작
   - BACKUP 모드로 조인 (VIP는 Server2 유지)
   - Preempt 비활성화 확인

2. 수동 전환 명령

   **VIP 강제 이동**:
   ```bash
   # Server1에서 실행 (VIP를 Server2로 이동)
   systemctl stop keepalived
   ```

**체크리스트**:
- [ ] 자동 전환 테스트 (완전 다운)
- [ ] 자동 전환 테스트 (서비스 장애)
- [ ] 복구 후 BACKUP 유지 확인
- [ ] 수동 전환 테스트

**Phase 5 완료 조건**:
- ✅ Keepalived 동적 설정 생성
- ✅ 헬스체크 시스템 완성
- ✅ VIP 자동 전환 정상 작동

---

### Phase 6: 백업 및 복원 시스템 (1주)

**목표**: 원클릭 백업/복원으로 서버 망가져도 즉시 복구

#### 6.1 통합 백업 스크립트 (2일)

**작업 내용**:

1. `cluster/backup/backup.sh` 작성 (메인 스크립트)

   **백업 항목**:
   - 설정 파일
     - `/etc/nginx/`
     - `/etc/redis/`
     - `/etc/mysql/`
     - `/etc/slurm/`
     - `/etc/keepalived/`
     - `cluster/cluster_config.yaml`
   - 데이터베이스
     - MariaDB 전체 덤프
     - Redis RDB 스냅샷
   - Slurm 상태
     - `/mnt/gluster/slurm/state/`
   - Systemd 서비스 파일
     - `/etc/systemd/system/`
   - 애플리케이션 코드
     - `/opt/hpc-dashboard/` (선택 사항, Git으로 관리)

   **백업 형식**:
   ```
   /data/system_backup/snapshots/20251026_140530/
   ├── configs/
   │   ├── nginx.tar.gz
   │   ├── redis.conf
   │   ├── mariadb.tar.gz
   │   ├── slurm.tar.gz
   │   └── keepalived.conf
   ├── databases/
   │   ├── mariadb_all.sql.gz
   │   └── redis_dump.rdb
   ├── state/
   │   └── slurm_state.tar.gz
   ├── systemd/
   │   └── services.tar.gz
   └── metadata.json  # 백업 정보 (날짜, 호스트, 버전 등)
   ```

2. 백업 옵션

   **Full Backup** (기본):
   - 모든 항목 백업

   **Incremental Backup**:
   - 변경된 항목만 백업 (rsync 기반)

   **Selective Backup**:
   - `--only-configs`: 설정 파일만
   - `--only-databases`: DB만
   - `--only-state`: Slurm 상태만

3. 백업 메타데이터

   **metadata.json 예시**:
   ```json
   {
     "backup_id": "20251026_140530",
     "timestamp": "2025-10-26 14:05:30",
     "hostname": "server1",
     "cluster_size": 4,
     "active_nodes": ["server1", "server2", "server3", "server4"],
     "software_versions": {
       "mariadb": "10.6.16",
       "redis": "7.0.15",
       "slurm": "23.02.7"
     },
     "backup_size": "1.2GB",
     "backup_type": "full"
   }
   ```

**체크리스트**:
- [ ] backup.sh 메인 스크립트 작성
- [ ] Full Backup 테스트
- [ ] Incremental Backup 테스트
- [ ] metadata.json 생성 확인

#### 6.2 통합 복원 스크립트 (2일)

**작업 내용**:

1. `cluster/backup/restore.sh` 작성

   **실행 흐름**:
   ```
   [1] 사용 가능한 백업 리스트 출력
        - /data/system_backup/snapshots/ 스캔
        - metadata.json 파싱
        ↓
   [2] 사용자 선택
        - 복원할 백업 ID 입력
        - 또는 --latest (최신 백업)
        ↓
   [3] 복원 전 확인
        - "현재 데이터가 모두 삭제됩니다. 계속하시겠습니까? (Y/N)"
        - --force 옵션으로 스킵 가능
        ↓
   [4] 서비스 중지
        - 모든 웹서비스 중지
        - Slurm 중지
        - Redis 중지
        - MariaDB 중지
        - Keepalived 중지
        ↓
   [5] 복원 실행
        - 설정 파일 복원
        - 데이터베이스 복원
        - Slurm 상태 복원
        - Systemd 서비스 복원
        ↓
   [6] 서비스 시작
        - start_multi_complete.sh --force 호출
        ↓
   [7] 검증
        - cluster_info.sh 호출
        - 모든 서비스 상태 확인
        ↓
   [8] 복원 완료 로그
        - /var/log/restore_YYYYMMDD_HHMMSS.log
   ```

2. 복원 옵션

   **Selective Restore**:
   - `--only-configs`: 설정 파일만 복원
   - `--only-databases`: DB만 복원
   - `--only-state`: Slurm 상태만 복원

   **Dry-run 모드**:
   - `--dry-run`: 실제 복원 없이 절차만 출력

3. 롤백 기능
   - 복원 전 현재 상태 자동 백업
   - 복원 실패 시 이전 상태로 롤백

**체크리스트**:
- [ ] restore.sh 작성 완료
- [ ] 전체 복원 테스트
- [ ] Selective Restore 테스트
- [ ] Dry-run 모드 테스트
- [ ] 롤백 기능 테스트

#### 6.3 자동 백업 스케줄러 (1일)

**작업 내용**:

1. `cluster/backup/backup_scheduler.sh` 작성

   **기능**:
   - cluster_config.yaml의 백업 스케줄 읽기
   - Cron 작업 자동 등록
   - 백업 보존 정책 적용 (오래된 백업 삭제)

   **Cron 예시**:
   ```bash
   # 매일 새벽 2시 Full Backup
   0 2 * * * /opt/hpc-dashboard/cluster/backup/backup.sh --full

   # 매 시간 Incremental Backup
   0 * * * * /opt/hpc-dashboard/cluster/backup/backup.sh --incremental
   ```

2. 백업 보존 정책

   **예시** (cluster_config.yaml 설정):
   ```yaml
   backup:
     retention_days: 30
     retention_policy:
       daily: 7    # 최근 7일
       weekly: 4   # 최근 4주
       monthly: 12 # 최근 12개월
   ```

   **로직**:
   - 7일 이내: 모든 백업 보존
   - 7-30일: 주간 백업만 보존 (일요일)
   - 30일-1년: 월간 백업만 보존 (매월 1일)
   - 1년 이상: 삭제

3. 백업 상태 알림
   - 백업 성공/실패 로그
   - 실패 시 알림 (Slack, Email)

**체크리스트**:
- [ ] backup_scheduler.sh 작성
- [ ] Cron 자동 등록 테스트
- [ ] 백업 보존 정책 테스트
- [ ] 알림 시스템 연동 (선택)

#### 6.4 재해 복구 문서화 (2일)

**작업 내용**:

1. `DISASTER_RECOVERY.md` 작성

   **시나리오별 복구 절차**:

   **시나리오 1: 단일 서버 장애**
   - 장애 서버 제외하고 클러스터 계속 운영
   - 새 서버 준비 후 `start_multi_complete.sh --join`

   **시나리오 2: 전체 클러스터 다운**
   - 모든 서버 재부팅
   - 마지막으로 살아있던 서버에서 `start_multi_complete.sh --bootstrap`
   - 나머지 서버에서 `start_multi_complete.sh --join`

   **시나리오 3: 데이터 손상**
   - `/data/system_backup/snapshots/` 에서 최신 백업 확인
   - `restore.sh --latest`
   - 클러스터 재시작

   **시나리오 4: 전체 스토리지 손실**
   - `/data/system_backup/` 이 다른 위치에 백업되어 있어야 함
   - 백업에서 복원
   - 클러스터 처음부터 재구성

2. 복구 시간 목표 (RTO) 및 복구 시점 목표 (RPO)

   **RTO (Recovery Time Objective)**:
   - 단일 서버 장애: 5분 (자동 전환)
   - 전체 클러스터 다운: 30분 (수동 복구)
   - 데이터 손상 복원: 1시간

   **RPO (Recovery Point Objective)**:
   - 시간별 증분 백업: 최대 1시간 데이터 손실
   - 일일 전체 백업: 최대 24시간 데이터 손실

**체크리스트**:
- [ ] DISASTER_RECOVERY.md 작성 완료
- [ ] 각 시나리오별 복구 절차 테스트
- [ ] RTO/RPO 달성 확인

**Phase 6 완료 조건**:
- ✅ 원클릭 백업 시스템 작동
- ✅ 원클릭 복원 시스템 작동
- ✅ 자동 백업 스케줄러 작동
- ✅ 재해 복구 문서 완성

---

### Phase 7: 웹 서비스 통합 및 최적화 (1주)

**목표**: 기존 웹 서비스를 클러스터 환경에 통합

#### 7.1 환경변수 및 설정 통합 (2일)

**작업 내용**:

1. 모든 웹서비스 `.env` 파일 통합

   **문제점**:
   - 현재: 각 서비스마다 개별 `.env` 파일
   - 클러스터: 모든 서버에서 동일한 설정 사용해야 함

   **해결책**:
   - `/mnt/gluster/config/` 에 통합 `.env` 파일 생성
   - 각 서비스에서 심볼릭 링크

   **예시**:
   ```bash
   # /mnt/gluster/config/global.env 생성
   REDIS_HOST=127.0.0.1
   REDIS_PORT=6379
   REDIS_PASSWORD=redis_cluster_secret
   DB_HOST=127.0.0.1
   DB_PORT=3306
   DB_USER=auth_user
   DB_PASSWORD=auth_password
   MOCK_MODE=false

   # 각 서비스에서 링크
   ln -s /mnt/gluster/config/global.env /opt/hpc-dashboard/dashboard/auth_portal_4430/.env
   ```

2. Nginx 설정 통합

   **정적 파일 경로**:
   - 현재: 각 서버의 로컬 `dist/` 디렉토리
   - 클러스터: GlusterFS 공유 디렉토리

   **변경**:
   ```nginx
   # Before
   location /auth/ {
       alias /opt/hpc-dashboard/dashboard/auth_frontend_4431/dist/;
   }

   # After
   location /auth/ {
       alias /mnt/gluster/frontend_builds/auth_frontend/;
   }
   ```

3. 프론트엔드 빌드 자동화

   **빌드 스크립트 수정** (`build_all_frontends.sh`):
   - 빌드 완료 후 `/mnt/gluster/frontend_builds/`로 자동 복사
   - 1개 서버에서만 빌드하면 모든 서버에 자동 배포

**체크리스트**:
- [ ] 통합 `.env` 파일 생성
- [ ] 심볼릭 링크 설정
- [ ] Nginx 설정 수정
- [ ] 프론트엔드 빌드 자동화

#### 7.2 Redis/DB 연결 수정 (2일)

**작업 내용**:

1. Python 백엔드 Redis 연결 수정

   **Before** (단일 Redis):
   ```python
   redis_client = Redis(host='localhost', port=6379)
   ```

   **After** (Redis Cluster):
   ```python
   from redis.cluster import RedisCluster

   redis_nodes = [
       {"host": "192.168.1.101", "port": 6379},
       {"host": "192.168.1.102", "port": 6379},
       {"host": "192.168.1.103", "port": 6379},
       {"host": "192.168.1.104", "port": 6379},
   ]

   redis_client = RedisCluster(
       startup_nodes=redis_nodes,
       password=os.getenv('REDIS_PASSWORD'),
       decode_responses=True,
       skip_full_coverage_check=True
   )
   ```

   **또는 자동 탐지**:
   ```python
   # cluster_config.yaml에서 자동으로 노드 리스트 읽기
   redis_client = get_redis_cluster_client()
   ```

2. MariaDB 연결 수정

   **Before**:
   ```python
   db = MySQLdb.connect(host='localhost', user='...', password='...')
   ```

   **After** (동일):
   ```python
   # 로컬 Galera 노드에 연결 (모든 노드가 Master)
   db = MySQLdb.connect(host='127.0.0.1', user='...', password='...')
   ```

   **주의사항**:
   - Galera는 Multi-Master이므로 로컬 노드에만 연결
   - 장애 시 자동으로 클러스터가 처리

**체크리스트**:
- [ ] Redis Cluster 연결 수정 (모든 백엔드)
- [ ] MariaDB 연결 확인
- [ ] 연결 테스트 (모든 서비스)

#### 7.3 세션 및 상태 관리 (2일)

**작업 내용**:

1. JWT 토큰 세션 공유

   **현재 상황**:
   - JWT 토큰은 Redis에 저장
   - Redis Cluster로 자동 공유됨

   **확인 사항**:
   - 세션 키 해싱 (Redis Cluster는 키 기반 샤딩)
   - 세션 만료 시간 (TTL) 동기화

2. WebSocket 세션 관리

   **문제**:
   - WebSocket 연결은 특정 서버에 고정됨
   - VIP 전환 시 연결 끊김

   **해결책**:
   - Sticky Session (HAProxy 또는 Nginx)
   - 또는 클라이언트 자동 재연결 (프론트엔드에서 처리)

   **Nginx Sticky Session 설정**:
   ```nginx
   upstream websocket_backend {
       ip_hash;  # 동일 IP는 동일 서버로 라우팅
       server 192.168.1.101:5011;
       server 192.168.1.102:5011;
       server 192.168.1.103:5011;
       server 192.168.1.104:5011;
   }
   ```

3. 파일 업로드 공유

   **업로드 경로**:
   - 현재: 로컬 디스크
   - 클러스터: `/mnt/gluster/uploads/`

   **변경 필요**:
   - 모든 업로드 API에서 경로 수정

**체크리스트**:
- [ ] JWT 세션 공유 확인
- [ ] WebSocket Sticky Session 설정
- [ ] 파일 업로드 경로 수정

#### 7.4 Health Check 엔드포인트 추가 (1일)

**작업 내용**:

1. 모든 백엔드에 `/health` 엔드포인트 추가

   **예시** (Flask):
   ```python
   @app.route('/health')
   def health_check():
       checks = {
           "status": "ok",
           "timestamp": datetime.now().isoformat(),
           "services": {
               "redis": check_redis(),
               "database": check_database(),
               "disk": check_disk_space(),
               "memory": check_memory()
           }
       }

       if all(checks["services"].values()):
           return jsonify(checks), 200
       else:
           return jsonify(checks), 503
   ```

2. Keepalived 헬스체크에서 사용
   - 각 백엔드의 `/health` 확인
   - 응답 없거나 503이면 VIP 이동

**체크리스트**:
- [ ] 모든 백엔드에 `/health` 추가
- [ ] Keepalived 헬스체크 연동
- [ ] 장애 감지 테스트

**Phase 7 완료 조건**:
- ✅ 웹 서비스 설정 통합
- ✅ Redis/DB 클러스터 연결
- ✅ 세션 공유 작동
- ✅ Health Check 시스템 완성

---

### Phase 8: 모니터링 및 알림 시스템 (1주)

**목표**: 클러스터 상태 실시간 모니터링 및 장애 알림

#### 8.1 Prometheus 설정 (2일)

**작업 내용**:

1. Prometheus 설치 (Server1 또는 별도 서버)

   **Scrape 대상**:
   - Node Exporter (4대 서버 각각: 9100)
   - MariaDB Exporter (4대 서버: 9104)
   - Redis Exporter (4대 서버: 9121)
   - Slurm Exporter (커스텀, 선택 사항)
   - 웹서비스 메트릭 (각 백엔드: /metrics)

2. `prometheus.yml` 설정

   **동적 타겟 생성**:
   ```yaml
   scrape_configs:
     - job_name: 'node'
       static_configs:
         - targets:
           - '192.168.1.101:9100'
           - '192.168.1.102:9100'
           - '192.168.1.103:9100'
           - '192.168.1.104:9100'

     - job_name: 'mariadb'
       static_configs:
         - targets:
           - '192.168.1.101:9104'
           - '192.168.1.102:9104'
           - '192.168.1.103:9104'
           - '192.168.1.104:9104'
   ```

**체크리스트**:
- [ ] Prometheus 설치 및 설정
- [ ] Node Exporter 실행 (4대)
- [ ] 메트릭 수집 확인

#### 8.2 Grafana 대시보드 (2일)

**작업 내용**:

1. Grafana 설치 및 Prometheus 연결

2. 대시보드 생성

   **클러스터 Overview**:
   - 활성 노드 수
   - VIP 소유 노드
   - 각 노드 CPU/RAM 사용률
   - 디스크 사용률

   **서비스 상태**:
   - GlusterFS: Volume 상태, Brick 상태
   - MariaDB Galera: wsrep_cluster_size, 동기화 상태
   - Redis Cluster: 노드 상태, 키 개수
   - Slurm: 작업 큐, 노드 상태

   **알림 기록**:
   - 최근 VIP 전환 이력
   - 최근 장애 이력

**체크리스트**:
- [ ] Grafana 설치
- [ ] 대시보드 생성
- [ ] 실시간 모니터링 확인

#### 8.3 알림 시스템 (2일)

**작업 내용**:

1. Alertmanager 설정

   **알림 규칙**:
   - 노드 다운 (30초 이상 응답 없음)
   - CPU 사용률 90% 이상 (5분)
   - 디스크 사용률 80% 이상
   - MariaDB Galera 노드 연결 끊김
   - Redis Cluster 노드 연결 끊김
   - VIP 전환 발생

   **알림 채널**:
   - Slack
   - Email
   - Webhook (선택)

2. `alertmanager.yml` 설정

   **예시**:
   ```yaml
   route:
     receiver: 'slack'
     group_by: ['alertname', 'cluster']
     group_wait: 10s
     group_interval: 5m
     repeat_interval: 3h

   receivers:
     - name: 'slack'
       slack_configs:
         - api_url: 'https://hooks.slack.com/services/...'
           channel: '#hpc-alerts'
   ```

**체크리스트**:
- [ ] Alertmanager 설치 및 설정
- [ ] 알림 규칙 작성
- [ ] Slack/Email 알림 테스트

#### 8.4 로그 중앙화 (1일, 선택 사항)

**작업 내용**:

1. ELK Stack 또는 Loki 설치

   **로그 수집**:
   - 시스템 로그 (syslog)
   - 클러스터 관리 로그 (start_multi_complete.sh)
   - 서비스 로그 (웹서비스, Slurm)

2. 로그 검색 및 분석

**체크리스트**:
- [ ] 로그 중앙화 시스템 설치 (선택)
- [ ] 로그 수집 확인

**Phase 8 완료 조건**:
- ✅ Prometheus 메트릭 수집
- ✅ Grafana 대시보드 작동
- ✅ 알림 시스템 작동
- ✅ 로그 중앙화 (선택)

---

### Phase 9: 테스트 및 검증 (2주)

**목표**: 모든 시나리오 테스트 및 문제 해결

#### 9.1 기능 테스트 (1주)

**테스트 시나리오**:

1. **클러스터 생성 테스트**
   - [ ] 새 서버에서 `start_multi_complete.sh --bootstrap`
   - [ ] 클러스터 단독 모드 작동 확인

2. **노드 조인 테스트**
   - [ ] 2번째 서버에서 `start_multi_complete.sh --join`
   - [ ] 2중화 구성 확인
   - [ ] 3번째, 4번째 서버 조인
   - [ ] 4중화 구성 확인

3. **서비스 정상 작동 테스트**
   - [ ] 웹 UI 접속 (https://VIP/)
   - [ ] SSO 로그인
   - [ ] Dashboard 작동
   - [ ] CAE 자동화 작동
   - [ ] Slurm 작업 제출
   - [ ] WebSocket 실시간 모니터링

4. **데이터 동기화 테스트**
   - [ ] Server1에서 파일 업로드 → Server2/3/4에서 확인
   - [ ] Server1에서 DB 쓰기 → Server2/3/4에서 읽기
   - [ ] Server1에서 Redis 쓰기 → Server2/3/4에서 읽기

#### 9.2 장애 테스트 (1주)

**테스트 시나리오**:

1. **단일 노드 장애**
   - [ ] Server1 중지
   - [ ] VIP 자동 전환 확인 (2-3초)
   - [ ] 웹서비스 계속 작동 확인
   - [ ] Slurm 작업 영향 없음 확인
   - [ ] Server1 재시작 후 자동 조인 확인

2. **2개 노드 동시 장애**
   - [ ] Server1, Server2 중지
   - [ ] 나머지 2대로 서비스 계속 작동 확인
   - [ ] 성능 저하 확인

3. **3개 노드 장애 (최악)**
   - [ ] Server1, Server2, Server3 중지
   - [ ] Server4만으로 읽기 전용 모드 확인
   - [ ] 1대 복구 후 쓰기 재개 확인

4. **서비스별 장애**
   - [ ] MariaDB 중지 → VIP 전환 확인
   - [ ] Redis 중지 → VIP 전환 확인
   - [ ] Slurm 중지 → VIP 전환 확인

5. **백업 및 복원 테스트**
   - [ ] 전체 백업 실행
   - [ ] 데이터 삭제
   - [ ] 복원 실행
   - [ ] 데이터 복구 확인

6. **네트워크 장애**
   - [ ] 노드 간 통신 차단 (iptables)
   - [ ] Split-brain 감지 확인
   - [ ] 복구 절차 확인

#### 9.3 성능 테스트

**테스트 항목**:

1. **부하 테스트**
   - [ ] 동시 사용자 100명 (Apache Bench)
   - [ ] 동시 사용자 1000명
   - [ ] WebSocket 동시 연결 100개

2. **스토리지 성능**
   - [ ] GlusterFS 읽기/쓰기 속도
   - [ ] 대용량 파일 업로드 (1GB+)

3. **DB 쓰기 성능**
   - [ ] Galera 동시 쓰기 (sysbench)

**체크리스트**:
- [ ] 모든 기능 테스트 통과
- [ ] 모든 장애 시나리오 통과
- [ ] 성능 목표 달성

**Phase 9 완료 조건**:
- ✅ 모든 테스트 케이스 통과
- ✅ 발견된 버그 모두 수정
- ✅ 성능 기준 만족

---

### Phase 10: 문서화 및 배포 (1주)

**목표**: 운영 가이드 작성 및 프로덕션 배포

#### 10.1 사용자 매뉴얼 작성 (3일)

**문서 리스트**:

1. **QUICK_START.md**
   - 첫 서버 시작 방법
   - 클러스터 조인 방법
   - 기본 명령어

2. **CLUSTER_MANAGEMENT.md**
   - 노드 추가/제거 방법
   - 백업/복원 방법
   - 업데이트 절차

3. **TROUBLESHOOTING.md**
   - 자주 발생하는 문제
   - 로그 확인 방법
   - 긴급 복구 절차

4. **API_REFERENCE.md**
   - cluster_config.yaml 스펙
   - 명령줄 도구 옵션
   - 환경변수 리스트

**체크리스트**:
- [ ] 모든 문서 작성 완료
- [ ] 예제 및 스크린샷 추가
- [ ] 동료 리뷰

#### 10.2 배포 체크리스트 (2일)

**프로덕션 배포 전 체크**:

- [ ] 모든 서버 하드웨어 점검
- [ ] 네트워크 설정 확인
- [ ] 백업 시스템 작동 확인
- [ ] 모니터링 알림 작동 확인
- [ ] 재해 복구 계획 수립
- [ ] 롤백 계획 수립
- [ ] 사용자 공지

**체크리스트**:
- [ ] 배포 체크리스트 모두 완료
- [ ] 롤백 계획 준비

#### 10.3 프로덕션 배포 (2일)

**배포 절차**:

1. 유지보수 모드 전환
2. 기존 시스템 백업
3. 클러스터 구성 (Phase별 순차 실행)
4. 기능 테스트
5. 유지보수 모드 해제
6. 사용자 공지

**체크리스트**:
- [ ] 프로덕션 배포 완료
- [ ] 사용자 피드백 수집

**Phase 10 완료 조건**:
- ✅ 문서화 완료
- ✅ 프로덕션 배포 완료
- ✅ 시스템 안정화

---

## 🎯 최종 완료 조건

### ✅ 전체 시스템 요구사항 충족

- [x] **자동 탐지 및 동적 클러스터링**
  - cluster_config.yaml에 IP 등록
  - start_multi_complete.sh로 자동 조인
  - N중화 → N+1중화 자동 구성
  - 단독 모드도 작동

- [x] **공유 스토리지 및 백업**
  - /data → 모든 서버 공유 스토리지
  - /data/system_backup → 백업 저장소
  - backup.sh → 원클릭 백업
  - restore.sh → 원클릭 복원

- [x] **완벽한 장애 대응**
  - 3대까지 동시 다운 OK
  - 자동 VIP 전환 (2-3초)
  - 무중단 업데이트

### ⏱️ 전체 소요 시간: **8-10주**

| Phase | 기간 | 주요 작업 |
|-------|------|----------|
| Phase 0 | 3-5일 | 공유 스토리지 (GlusterFS) |
| Phase 1 | 1주 | 클러스터 탐지/조인 프레임워크 |
| Phase 2 | 1주 | MariaDB Galera 동적 클러스터링 |
| Phase 3 | 1주 | Redis Cluster 동적 클러스터링 |
| Phase 4 | 1주 | Slurm Multi-Master |
| Phase 5 | 3일 | Keepalived VIP 관리 |
| Phase 6 | 1주 | 백업/복원 시스템 |
| Phase 7 | 1주 | 웹 서비스 통합 |
| Phase 8 | 1주 | 모니터링/알림 |
| Phase 9 | 2주 | 테스트 및 검증 |
| Phase 10 | 1주 | 문서화 및 배포 |

---

## 🚀 시작하기

### 첫 서버 시작 (Bootstrap)

```bash
cd /opt/hpc-dashboard/cluster
./start_multi_complete.sh --bootstrap
```

### 두 번째 서버 조인 (N+1)

```bash
cd /opt/hpc-dashboard/cluster
./start_multi_complete.sh --join
```

### 현재 클러스터 상태 확인

```bash
./utils/cluster_info.sh
```

### 백업 생성

```bash
./backup/backup.sh
```

### 복원

```bash
./backup/restore.sh --latest
```

---

이 계획서를 따라 구현하면 **완전 자동화된 동적 클러스터링 시스템**이 완성됩니다!
