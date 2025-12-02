# Multi-Head 클러스터 구현 계획 (my_multihead_cluster.yaml 기반)

## 📋 프로젝트 개요

### 핵심 변경사항

**기존 계획** (cluster_config.yaml):
- 수동으로 작성한 YAML 설정 파일
- 클러스터 관리 전용

**새 계획** (my_multihead_cluster.yaml):
- ✅ 기존 `my_cluster.yaml` 포맷 확장
- ✅ `controllers` 리스트로 다중 헤드 지원
- ✅ 각 controller마다 서비스 활성화 옵션
  - `glusterfs`: true/false
  - `mariadb`: true/false
  - `redis`: true/false
  - `slurm`: true/false
  - `web`: true/false
  - `keepalived`: true/false
- ✅ `vip_owner` 여부 설정 (MASTER/BACKUP)
- ✅ 기존 Slurm 자동화 스크립트와 통합 가능

### 장점

1. **일관성**: 기존 `my_cluster.yaml` 사용자에게 친숙
2. **유연성**: 각 controller마다 서비스 선택 가능
3. **확장성**: controller 추가는 리스트에 항목 추가만
4. **통합성**: 기존 Slurm 설치 자동화와 호환

---

## 🏗️ 파일 구조 (업데이트)

```
/home/koopark/claude/KooSlurmInstallAutomationRefactory/
├── my_cluster.yaml                    # 기존: 단일 controller
├── my_multihead_cluster.yaml          # ✨ 새로 추가: 다중 controller
│
├── dashboard/                         # 웹 서비스
│   ├── auth_portal_4430/
│   ├── backend_5010/
│   ├── ...
│   └── start_complete.sh              # 기존 단일 서버 시작
│
└── cluster/                           # ✨ 새로 추가: 멀티헤드 클러스터 관리
    ├── start_multihead.sh             # 메인 실행 스크립트
    ├── config/
    │   └── parser.py                  # my_multihead_cluster.yaml 파싱
    ├── discovery/
    │   ├── auto_discovery.sh          # 활성 노드 탐지
    │   └── join_cluster.sh            # 클러스터 조인
    ├── setup/
    │   ├── phase0_storage.sh          # GlusterFS
    │   ├── phase1_database.sh         # MariaDB Galera
    │   ├── phase2_redis.sh            # Redis Cluster
    │   ├── phase3_slurm.sh            # Slurm Multi-Master
    │   ├── phase4_keepalived.sh       # VIP 관리
    │   └── phase5_web.sh              # 웹 서비스
    ├── backup/
    │   ├── backup.sh                  # 원클릭 백업
    │   └── restore.sh                 # 원클릭 복원
    └── utils/
        ├── cluster_info.sh            # 클러스터 정보
        ├── node_add.sh                # 노드 추가
        └── node_remove.sh             # 노드 제거
```

---

## 📅 Phase별 구현 계획 (재설계)

---

### Phase 0: YAML 파싱 및 기본 프레임워크 (3일)

**목표**: my_multihead_cluster.yaml을 파싱하고 활성 노드 정보 추출

#### 0.1 YAML 파서 작성 (1일)

**파일**: `cluster/config/parser.py`

**기능**:
1. my_multihead_cluster.yaml 읽기
2. 환경변수 치환 (`${DB_PASSWORD}` → 실제 값)
3. 데이터 추출 함수
   - `get_controllers()` → controllers 리스트 반환
   - `get_active_controllers(service='all')` → 특정 서비스가 true인 controller만 반환
   - `get_vip_config()` → VIP 설정 반환
   - `get_storage_config()` → GlusterFS 설정 반환
   - `get_database_config()` → MariaDB 설정 반환
   - `get_redis_config()` → Redis 설정 반환
   - `get_slurm_config()` → Slurm 설정 반환

**출력 예시**:
```python
# get_active_controllers('mariadb')
[
    {
        'hostname': 'server1',
        'ip': '192.168.1.101',
        'priority': 100,
        'vip_owner': True,
        'services': {
            'glusterfs': True,
            'mariadb': True,
            'redis': True,
            'slurm': True,
            'web': True,
            'keepalived': True
        }
    },
    {
        'hostname': 'server2',
        'ip': '192.168.1.102',
        ...
    }
]
```

**명령줄 도구**:
```bash
# 모든 controller 출력
./cluster/config/parser.py --list-controllers

# MariaDB 활성 controller만 출력
./cluster/config/parser.py --service mariadb

# VIP 설정 출력
./cluster/config/parser.py --get-vip

# 설정 검증
./cluster/config/parser.py --validate
```

**체크리스트**:
- [ ] parser.py 작성 완료
- [ ] my_multihead_cluster.yaml 파싱 테스트
- [ ] 환경변수 치환 테스트
- [ ] 각 get_* 함수 테스트

#### 0.2 자동 탐지 시스템 (2일)

**파일**: `cluster/discovery/auto_discovery.sh`

**실행 흐름**:
```
[1] my_multihead_cluster.yaml에서 controllers 읽기
     ↓
[2] 각 controller에 대해:
     - SSH 접속 시도 (timeout 5초)
     - services.glusterfs: true면 → gluster peer status 확인
     - services.mariadb: true면 → mysql -e "SHOW STATUS LIKE 'wsrep%'" 확인
     - services.redis: true면 → redis-cli cluster info 확인
     - services.slurm: true면 → scontrol ping 확인
     - services.web: true면 → curl http://IP:4430/health 확인
     ↓
[3] JSON 출력
```

**출력 예시**:
```json
{
  "total_controllers": 4,
  "active_controllers": 3,
  "inactive_controllers": 1,
  "controllers": [
    {
      "hostname": "server1",
      "ip": "192.168.1.101",
      "status": "active",
      "services": {
        "glusterfs": {"status": "ok", "peers": 3},
        "mariadb": {"status": "ok", "cluster_size": 3},
        "redis": {"status": "ok", "cluster_state": "ok"},
        "slurm": {"status": "ok", "controller": "primary"},
        "web": {"status": "ok", "http_code": 200},
        "keepalived": {"status": "ok", "vip": true}
      },
      "uptime": "5 days",
      "load": 0.35
    },
    {
      "hostname": "server4",
      "ip": "192.168.1.104",
      "status": "inactive",
      "error": "Connection timeout"
    }
  ],
  "vip_owner": "server1",
  "cluster_state": "healthy"
}
```

**체크리스트**:
- [ ] auto_discovery.sh 작성
- [ ] SSH 접속 테스트
- [ ] 각 서비스별 상태 확인 테스트
- [ ] JSON 출력 검증

**Phase 0 완료 조건**:
- ✅ my_multihead_cluster.yaml 파싱 가능
- ✅ 활성 controller 자동 탐지 가능
- ✅ 각 서비스별 상태 확인 가능

---

### Phase 1: GlusterFS 동적 클러스터링 (1주)

**목표**: services.glusterfs: true인 controller들로 GlusterFS 클러스터 구성

#### 1.1 GlusterFS 설정 스크립트 (3일)

**파일**: `cluster/setup/phase0_storage.sh`

**실행 흐름**:
```
[1] YAML에서 GlusterFS 설정 읽기
     - glusterfs 활성 controller 리스트
     - volume_name, replica_count, brick_path 등
     ↓
[2] 현재 서버가 glusterfs: true인지 확인
     - false면 → 스킵
     ↓
[3] GlusterFS 설치 확인
     - 미설치 시 자동 설치
     ↓
[4] 활성 GlusterFS 노드 탐지
     - auto_discovery.sh 호출
     - glusterfs 상태가 'ok'인 노드 추출
     ↓
[5] Peer 연결 여부 확인
     - 이미 연결되어 있으면 → 스킵
     - 연결 안 되어 있으면 → gluster peer probe
     ↓
[6] Volume 생성 또는 조인
     - 활성 노드 0개 → 새 volume 생성 (Bootstrap)
     - 활성 노드 1개+ → 기존 volume에 brick 추가
     ↓
[7] Volume 마운트
     - mkdir -p /mnt/gluster
     - mount -t glusterfs localhost:/<volume_name> /mnt/gluster
     - /etc/fstab에 등록
     ↓
[8] 디렉토리 구조 생성 (Bootstrap만)
     - frontend_builds/, slurm/, uploads/, config/
     ↓
[9] 검증
     - gluster volume status
     - df -h | grep gluster
```

**옵션**:
```bash
./cluster/setup/phase0_storage.sh
  --config /path/to/my_multihead_cluster.yaml  # 설정 파일 경로
  --bootstrap                                    # 강제 Bootstrap
  --join                                         # 강제 Join
  --dry-run                                      # 실제 실행 없이 절차만 출력
```

**체크리스트**:
- [ ] phase0_storage.sh 작성
- [ ] GlusterFS 설치 자동화
- [ ] Peer 연결 테스트
- [ ] Volume 생성/조인 테스트
- [ ] 마운트 및 fstab 등록 테스트

#### 1.2 Brick 동적 추가/제거 (2일)

**파일**: `cluster/utils/node_add.sh`, `cluster/utils/node_remove.sh`

**노드 추가** (node_add.sh):
```bash
./cluster/utils/node_add.sh --service glusterfs --ip 192.168.1.105

실행 흐름:
[1] 새 노드의 services.glusterfs: true 확인
[2] Peer probe
[3] Volume에 brick 추가
[4] Volume rebalance (데이터 재분배)
```

**노드 제거** (node_remove.sh):
```bash
./cluster/utils/node_remove.sh --service glusterfs --ip 192.168.1.104

실행 흐름:
[1] Volume에서 brick 제거
[2] Volume rebalance
[3] Peer detach
```

**체크리스트**:
- [ ] node_add.sh 작성
- [ ] node_remove.sh 작성
- [ ] Brick 추가/제거 무중단 테스트

#### 1.3 백업 저장소 준비 (2일)

**디렉토리**: `/data/system_backup` (각 controller 로컬 디스크)

**구조**:
```
/data/system_backup/
├── configs/
├── databases/
├── state/
└── snapshots/
    └── YYYYMMDD_HHMMSS/
        ├── metadata.json
        ├── configs.tar.gz
        ├── mariadb_dump.sql.gz
        └── redis_dump.rdb
```

**체크리스트**:
- [ ] 백업 디렉토리 생성 스크립트 작성
- [ ] 디스크 용량 확인

**Phase 1 완료 조건**:
- ✅ GlusterFS N-node 클러스터 작동
- ✅ 동적 노드 추가/제거 가능
- ✅ 백업 저장소 준비 완료

---

### Phase 2: MariaDB Galera 동적 클러스터링 (1주)

**목표**: services.mariadb: true인 controller들로 Galera 클러스터 구성

#### 2.1 MariaDB Galera 설정 스크립트 (3일)

**파일**: `cluster/setup/phase1_database.sh`

**실행 흐름**:
```
[1] YAML에서 MariaDB 설정 읽기
     - mariadb 활성 controller 리스트
     - database.mariadb.databases 리스트
     ↓
[2] 현재 서버가 mariadb: true인지 확인
     - false면 → 스킵
     ↓
[3] MariaDB + Galera 설치
     ↓
[4] 활성 Galera 노드 탐지
     - auto_discovery.sh 호출
     ↓
[5] galera.cnf 동적 생성
     - wsrep_cluster_address에 모든 활성 노드 IP 입력
     ↓
[6] Bootstrap vs Join 결정
     - 활성 Galera 노드 0개 → Bootstrap
     - 활성 Galera 노드 1개+ → Join
     ↓
[7] 시작
     - Bootstrap: galera_new_cluster
     - Join: systemctl start mariadb (자동 SST)
     ↓
[8] 데이터베이스 초기화 (Bootstrap만)
     - CREATE DATABASE slurm_acct_db
     - CREATE DATABASE auth_portal
     - CREATE USER ...
     ↓
[9] 검증
     - SHOW STATUS LIKE 'wsrep_cluster_size'
     - SHOW STATUS LIKE 'wsrep_local_state_comment'
```

**galera.cnf 템플릿**:
```ini
# /etc/mysql/mariadb.conf.d/galera.cnf.template

[galera]
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name="{{cluster_name}}"
wsrep_cluster_address="gcomm://{{cluster_addresses}}"  # 파싱 결과 입력
wsrep_node_address="{{node_ip}}"
wsrep_node_name="{{node_name}}"
binlog_format=row
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
wsrep_sst_method={{sst_method}}
wsrep_slave_threads={{slave_threads}}
```

**체크리스트**:
- [ ] phase1_database.sh 작성
- [ ] MariaDB + Galera 설치 자동화
- [ ] galera.cnf 동적 생성 테스트
- [ ] Bootstrap 모드 테스트
- [ ] Join 모드 테스트 (SST 확인)
- [ ] 데이터베이스 초기화 테스트

#### 2.2 동적 노드 추가/제거 (2일)

**노드 추가**:
```bash
./cluster/utils/node_add.sh --service mariadb --ip 192.168.1.105

실행:
[1] 새 노드의 galera.cnf 생성 (모든 활성 노드 포함)
[2] systemctl start mariadb (자동 SST로 데이터 동기화)
[3] 기존 노드들의 galera.cnf 업데이트 (새 IP 추가)
[4] SET GLOBAL wsrep_cluster_address='gcomm://...' (재시작 불필요!)
```

**노드 제거**:
```bash
./cluster/utils/node_remove.sh --service mariadb --ip 192.168.1.104

실행:
[1] 제거 노드에서 MariaDB 중지
[2] 나머지 노드들의 galera.cnf 업데이트 (제거 IP 삭제)
[3] SET GLOBAL wsrep_cluster_address='gcomm://...'
```

**체크리스트**:
- [ ] 노드 추가 무중단 테스트
- [ ] 노드 제거 무중단 테스트

#### 2.3 백업 및 복원 (2일)

**백업 스크립트**: `cluster/backup/backup_mariadb.sh`

```bash
mysqldump --all-databases --single-transaction | gzip > /data/system_backup/databases/mariadb_$(date +%Y%m%d_%H%M%S).sql.gz
```

**복원 스크립트**: `cluster/backup/restore_mariadb.sh`

**체크리스트**:
- [ ] 백업 스크립트 작성
- [ ] 복원 스크립트 작성
- [ ] 백업/복원 통합 테스트

**Phase 2 완료 조건**:
- ✅ MariaDB Galera N-node 클러스터 작동
- ✅ 동적 노드 추가/제거 가능
- ✅ 백업/복원 시스템 작동

---

### Phase 3: Redis Cluster 동적 클러스터링 (1주)

**목표**: services.redis: true인 controller들로 Redis Cluster 구성

#### 3.1 Redis Cluster 설정 스크립트 (3일)

**파일**: `cluster/setup/phase2_redis.sh`

**실행 흐름**:
```
[1] YAML에서 Redis 설정 읽기
     - redis 활성 controller 리스트
     - redis.cluster.password 등
     ↓
[2] 현재 서버가 redis: true인지 확인
     ↓
[3] Redis 설치
     ↓
[4] redis.conf 동적 생성
     - cluster-enabled yes
     - requirepass {{password}}
     ↓
[5] Redis 시작
     ↓
[6] 활성 Redis 노드 탐지
     ↓
[7] Cluster 생성 vs 조인
     - 활성 노드 0-2개 → 대기 (최소 3개 필요)
     - 활성 노드 3개+ → Cluster 생성 또는 조인
     ↓
[8] Cluster 명령 실행
     - 생성: redis-cli --cluster create ...
     - 조인: redis-cli --cluster add-node ...
     ↓
[9] 해시 슬롯 재분배 (조인 시)
     - redis-cli --cluster rebalance
```

**특수 케이스: 2개 노드**
- Redis Cluster는 최소 3개 필요
- 대안: Redis Sentinel (Master-Replica)

**체크리스트**:
- [ ] phase2_redis.sh 작성
- [ ] Redis Cluster 생성 테스트 (3개+)
- [ ] 노드 조인 테스트
- [ ] 해시 슬롯 재분배 테스트
- [ ] 2개 노드 Sentinel 모드 구현 (선택)

#### 3.2 동적 노드 추가/제거 (2일)

**체크리스트**:
- [ ] 노드 추가 테스트
- [ ] 노드 제거 테스트 (슬롯 이동 확인)

#### 3.3 백업 및 복원 (2일)

**백업**: RDB 스냅샷 복사

**체크리스트**:
- [ ] 백업 스크립트 작성
- [ ] 복원 스크립트 작성

**Phase 3 완료 조건**:
- ✅ Redis Cluster N-node 작동
- ✅ 동적 노드 추가/제거 가능

---

### Phase 4: Slurm Multi-Master 동적 구성 (1주)

**목표**: services.slurm: true인 controller들로 Slurm Multi-Master 구성

#### 4.1 Slurm 설정 동적 생성 (3일)

**파일**: `cluster/setup/phase3_slurm.sh`

**실행 흐름**:
```
[1] YAML에서 Slurm 설정 읽기
     - slurm 활성 controller 리스트
     ↓
[2] 현재 서버가 slurm: true인지 확인
     ↓
[3] Slurm 설치 (기존 자동화 스크립트 활용)
     ↓
[4] slurm.conf 동적 생성
     - 모든 활성 controller를 SlurmctldHost로 등록
     - StateSaveLocation=/mnt/gluster/slurm/state
     ↓
[5] slurm.conf를 GlusterFS에 저장
     - /mnt/gluster/slurm/config/slurm.conf
     ↓
[6] 심볼릭 링크
     - ln -s /mnt/gluster/slurm/config/slurm.conf /etc/slurm/slurm.conf
     ↓
[7] slurmdbd 설정
     - StorageHost=127.0.0.1 (로컬 Galera 노드)
     ↓
[8] 서비스 시작
     - slurmdbd 먼저
     - slurmctld
```

**slurm.conf 템플릿**:
```bash
# 동적 생성 부분
{{#each controllers}}
SlurmctldHost={{hostname}}({{ip}})
{{/each}}

StateSaveLocation=/mnt/gluster/slurm/state
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldLogFile=/mnt/gluster/slurm/logs/slurmctld.log

AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=127.0.0.1
```

**체크리스트**:
- [ ] phase3_slurm.sh 작성
- [ ] slurm.conf 동적 생성 테스트
- [ ] Multi-Master 설정 확인 (scontrol show config)

#### 4.2 VIP 전환 시 자동 Controller 전환 (2일)

**Keepalived 알림 스크립트**:
```bash
# /usr/local/bin/notify_master.sh
systemctl restart slurmctld
# VIP 받으면 Primary Controller

# /usr/local/bin/notify_backup.sh
systemctl restart slurmctld
# VIP 잃으면 Backup Controller
```

**체크리스트**:
- [ ] 알림 스크립트 작성
- [ ] VIP 전환 테스트

#### 4.3 동적 노드 추가/제거 (2일)

**노드 추가**:
```
[1] slurm.conf에 SlurmctldHost 추가
[2] GlusterFS에 저장 (자동 동기화)
[3] scontrol reconfigure (모든 노드)
```

**체크리스트**:
- [ ] 노드 추가 무중단 테스트

**Phase 4 완료 조건**:
- ✅ Slurm Multi-Master 작동
- ✅ VIP 전환 시 자동 Controller 전환

---

### Phase 5: Keepalived VIP 동적 관리 (3일)

**목표**: services.keepalived: true인 controller들로 VIP 관리

#### 5.1 Keepalived 설정 동적 생성 (2일)

**파일**: `cluster/setup/phase4_keepalived.sh`

**실행 흐름**:
```
[1] YAML에서 VIP 설정 읽기
     - network.vip.address
     - network.vip.interface
     - 현재 controller의 priority
     - vip_owner 여부
     ↓
[2] 현재 서버가 keepalived: true인지 확인
     ↓
[3] keepalived.conf 동적 생성
     - state: vip_owner=true → MASTER, false → BACKUP
     - priority: YAML에서 읽어옴
     ↓
[4] Keepalived 시작
     ↓
[5] VIP 확인
     - MASTER인 경우 VIP 소유 확인
```

**keepalived.conf 템플릿**:
```
vrrp_instance VI_1 {
    state {{state}}              # MASTER or BACKUP
    interface {{interface}}
    virtual_router_id {{vrrp_id}}
    priority {{priority}}
    ...
    virtual_ipaddress {
        {{vip_address}}
    }
    track_script {
        check_all_services
    }
}
```

**체크리스트**:
- [ ] phase4_keepalived.sh 작성
- [ ] keepalived.conf 동적 생성 테스트
- [ ] VIP 할당 확인

#### 5.2 헬스체크 스크립트 (1일)

**파일**: `/usr/local/bin/check_all_services.sh`

**체크 항목** (YAML 기반):
```bash
# services.glusterfs: true면 → gluster volume status 확인
# services.mariadb: true면 → mysql -e "SHOW STATUS LIKE 'wsrep_ready'" 확인
# services.redis: true면 → redis-cli ping 확인
# services.slurm: true면 → scontrol ping 확인
# services.web: true면 → curl http://localhost:4430/health 확인
```

**체크리스트**:
- [ ] check_all_services.sh 작성
- [ ] YAML 기반 동적 체크 테스트

**Phase 5 완료 조건**:
- ✅ Keepalived VIP 자동 관리
- ✅ 헬스체크 기반 자동 전환

---

### Phase 6: 웹 서비스 통합 (1주)

**목표**: services.web: true인 controller들에 웹 서비스 배포

#### 6.1 웹 서비스 자동 배포 (3일)

**파일**: `cluster/setup/phase5_web.sh`

**실행 흐름**:
```
[1] YAML에서 웹 서비스 설정 읽기
     - web_services.services 리스트
     ↓
[2] 현재 서버가 web: true인지 확인
     ↓
[3] 백엔드 서비스 배포
     - Python venv 생성
     - pip install -r requirements.txt
     - 환경변수 설정 (GlusterFS 공유)
     - Systemd 서비스 생성
     ↓
[4] 프론트엔드 빌드 (1개 서버에서만)
     - npm install
     - npm run build
     - /mnt/gluster/frontend_builds/로 복사
     ↓
[5] Nginx 설정
     - 정적 파일 경로: /mnt/gluster/frontend_builds/
     - 백엔드 프록시: localhost
     ↓
[6] 서비스 시작
```

**체크리스트**:
- [ ] phase5_web.sh 작성
- [ ] 백엔드 배포 테스트
- [ ] 프론트엔드 빌드 테스트
- [ ] Nginx 설정 테스트

#### 6.2 Redis/DB 연결 수정 (2일)

**Redis Cluster 연결** (Python):
```python
# cluster/config/parser.py를 활용
redis_nodes = get_active_controllers('redis')
redis_client = RedisCluster(
    startup_nodes=[{"host": node['ip'], "port": 6379} for node in redis_nodes],
    password=os.getenv('REDIS_PASSWORD')
)
```

**MariaDB 연결**:
```python
# 로컬 Galera 노드 연결
db = MySQLdb.connect(host='127.0.0.1', user='...', password='...')
```

**체크리스트**:
- [ ] Redis Cluster 연결 수정
- [ ] MariaDB 연결 확인

#### 6.3 Health Check 엔드포인트 추가 (2일)

**모든 백엔드에 `/health` 추가**

**체크리스트**:
- [ ] /health 엔드포인트 추가 (모든 백엔드)
- [ ] Keepalived 연동 테스트

**Phase 6 완료 조건**:
- ✅ 웹 서비스 모든 controller에 배포
- ✅ Redis/DB 클러스터 연결
- ✅ Health Check 작동

---

### Phase 7: 통합 백업/복원 시스템 (1주)

**목표**: 원클릭 백업/복원 시스템 구축

#### 7.1 통합 백업 스크립트 (3일)

**파일**: `cluster/backup/backup.sh`

**실행 흐름**:
```
[1] YAML에서 백업 설정 읽기
     - shared_storage.backup.items
     - shared_storage.backup.retention
     ↓
[2] 백업 디렉토리 생성
     - /data/system_backup/snapshots/YYYYMMDD_HHMMSS/
     ↓
[3] 백업 실행
     - configs: /etc/nginx, /etc/redis, /etc/mysql, /etc/slurm
     - databases: mysqldump, redis SAVE
     - slurm_state: /mnt/gluster/slurm/state
     - glusterfs_meta: gluster volume info
     ↓
[4] metadata.json 생성
     - 백업 ID, 시간, 호스트, 클러스터 크기, 소프트웨어 버전
     ↓
[5] 압축
     - tar + gzip
```

**체크리스트**:
- [ ] backup.sh 작성
- [ ] Full Backup 테스트
- [ ] metadata.json 생성 확인

#### 7.2 통합 복원 스크립트 (2일)

**파일**: `cluster/backup/restore.sh`

**옵션**:
```bash
./cluster/backup/restore.sh --latest
./cluster/backup/restore.sh --id 20251026_140530
./cluster/backup/restore.sh --only-configs
./cluster/backup/restore.sh --dry-run
```

**체크리스트**:
- [ ] restore.sh 작성
- [ ] 전체 복원 테스트
- [ ] Selective Restore 테스트

#### 7.3 자동 백업 스케줄러 (2일)

**파일**: `cluster/backup/backup_scheduler.sh`

**기능**:
- YAML에서 백업 스케줄 읽기
- Cron 작업 자동 등록
- 백업 보존 정책 적용

**체크리스트**:
- [ ] backup_scheduler.sh 작성
- [ ] Cron 등록 테스트
- [ ] 보존 정책 테스트

**Phase 7 완료 조건**:
- ✅ 원클릭 백업 시스템
- ✅ 원클릭 복원 시스템
- ✅ 자동 백업 스케줄러

---

### Phase 8: 메인 스크립트 작성 (1주)

**목표**: start_multihead.sh 통합 스크립트 작성

#### 8.1 start_multihead.sh 메인 스크립트 (5일)

**파일**: `cluster/start_multihead.sh`

**옵션**:
```bash
./cluster/start_multihead.sh
  --config my_multihead_cluster.yaml  # 설정 파일 (기본값: ../my_multihead_cluster.yaml)
  --bootstrap                          # 강제 Bootstrap (새 클러스터)
  --join                               # 강제 Join (기존 클러스터)
  --standalone                         # 단독 모드
  --status                             # 현재 상태만 확인
  --force                              # 확인 프롬프트 스킵
  --dry-run                            # 실제 실행 없이 절차만 출력
  --phase <phase_number>               # 특정 Phase만 실행
```

**실행 흐름**:
```
[1] 환경 체크
     - root 권한 확인
     - my_multihead_cluster.yaml 존재 확인
     - /data, /mnt/gluster 확인
     ↓
[2] YAML 파싱
     - 현재 서버 정보 확인 (IP 기반)
     - 활성화된 서비스 확인
     ↓
[3] 모드 결정
     - --bootstrap → Bootstrap
     - --standalone → Standalone
     - --join → Join
     - 기본값 → 자동 탐지
     ↓
[4] 자동 탐지 (기본값)
     - auto_discovery.sh 실행
     - 활성 controller 수 확인
     - 0개 → Bootstrap
     - 1개+ → Join
     ↓
[5] Phase별 실행
     - Phase 0: GlusterFS (services.glusterfs: true인 경우)
     - Phase 1: MariaDB (services.mariadb: true)
     - Phase 2: Redis (services.redis: true)
     - Phase 3: Slurm (services.slurm: true)
     - Phase 4: Keepalived (services.keepalived: true)
     - Phase 5: Web (services.web: true)
     ↓
[6] 헬스체크
     - 5초 대기 후 모든 서비스 확인
     ↓
[7] 클러스터 정보 출력
     - cluster_info.sh 호출
     ↓
[8] 백업 스케줄러 시작 (선택)
```

**에러 처리**:
- 각 Phase 실패 시 롤백
- 로그 파일: `/var/log/cluster_multihead.log`

**체크리스트**:
- [ ] start_multihead.sh 작성
- [ ] Bootstrap 모드 테스트
- [ ] Join 모드 테스트
- [ ] Standalone 모드 테스트
- [ ] 자동 탐지 테스트
- [ ] Phase별 실행 테스트
- [ ] 에러 처리 및 롤백 테스트

#### 8.2 cluster_info.sh 정보 출력 스크립트 (2일)

**파일**: `cluster/utils/cluster_info.sh`

**출력 예시**:
```
========================================
HPC Portal Multi-Head Cluster Status
========================================
Cluster Name: hpc-portal-multihead
Cluster Size: 4-node (Quad Redundancy)
VIP: 192.168.1.100 (owned by server1)
Uptime: 15 days

Controller Status:
+------------+---------------+----------+--------+-----+-----+-----+-----+-----+
| Hostname   | IP            | Status   | Load   | GFS | MDB | RDS | SLM | WEB |
+------------+---------------+----------+--------+-----+-----+-----+-----+-----+
| server1    | 192.168.1.101 | Active   | 0.35   | ✓   | ✓   | ✓   | ✓   | ✓   |
| server2    | 192.168.1.102 | Active   | 0.42   | ✓   | ✓   | ✓   | ✓   | ✓   |
| server3    | 192.168.1.103 | Active   | 0.38   | ✓   | ✓   | ✓   | ✓   | ✓   |
| server4    | 192.168.1.104 | Active   | 0.29   | ✓   | ✓   | ✓   | ✓   | ✓   |
+------------+---------------+----------+--------+-----+-----+-----+-----+-----+
GFS=GlusterFS, MDB=MariaDB, RDS=Redis, SLM=Slurm, WEB=Web

Service Details:
- GlusterFS: 4/4 bricks (Replica 4, Healthy)
- MariaDB Galera: 4/4 nodes (Synced)
- Redis Cluster: 4/4 masters (cluster_state: ok)
- Slurm: Primary on server1 (3 backups ready)
- Web Services: 8 services × 4 nodes = 32 instances

Storage:
- Shared (GlusterFS): 850GB / 2TB (42%)
- Backup (Local): 120GB / 500GB (24%)

Last Backup: 2025-10-26 02:00:00
========================================
```

**체크리스트**:
- [ ] cluster_info.sh 작성
- [ ] 표 형식 출력 테스트

**Phase 8 완료 조건**:
- ✅ start_multihead.sh 정상 작동
- ✅ cluster_info.sh 정보 출력

---

### Phase 9: 테스트 및 검증 (2주)

**목표**: 모든 시나리오 테스트

#### 9.1 기능 테스트 (1주)

**테스트 시나리오**:

1. **신규 클러스터 생성**
   ```bash
   # Server1
   ./cluster/start_multihead.sh --config my_multihead_cluster.yaml --bootstrap
   → ✅ 1중화 클러스터 생성
   ```

2. **노드 조인 (2중화)**
   ```bash
   # Server2
   ./cluster/start_multihead.sh --config my_multihead_cluster.yaml
   → 자동으로 Server1 탐지
   → ✅ 1중화 → 2중화 완료
   ```

3. **노드 계속 조인 (3중화, 4중화)**
   ```bash
   # Server3
   ./cluster/start_multihead.sh
   → ✅ 2중화 → 3중화

   # Server4
   ./cluster/start_multihead.sh
   → ✅ 3중화 → 4중화
   ```

4. **서비스별 활성화 테스트**
   ```yaml
   # my_multihead_cluster.yaml에서 server3의 services.redis: false로 변경
   # Server3 재시작
   → Redis는 3-node 클러스터로 작동
   ```

5. **웹 UI 접속**
   ```
   https://192.168.1.100/  (VIP)
   → SSO 로그인
   → Dashboard, CAE, App 모두 작동 확인
   ```

6. **Slurm 작업 제출**
   ```bash
   sbatch test_job.sh
   → 작업 정상 제출 및 실행 확인
   ```

**체크리스트**:
- [ ] 모든 기능 테스트 통과

#### 9.2 장애 테스트 (1주)

**시나리오**:

1. **단일 노드 다운**
   ```bash
   # Server1 중지
   systemctl poweroff
   → VIP가 Server2로 이동 (2-3초)
   → 웹서비스 계속 작동
   → Slurm 작업 영향 없음
   ```

2. **2개 노드 다운**
   ```bash
   # Server1, Server2 중지
   → Server3이 VIP 소유
   → 2-node 클러스터로 계속 작동
   ```

3. **백업 및 복원**
   ```bash
   # 백업
   ./cluster/backup/backup.sh

   # 데이터 삭제 시뮬레이션
   mysql -e "DROP DATABASE auth_portal;"

   # 복원
   ./cluster/backup/restore.sh --latest
   → 데이터 복구 확인
   ```

**체크리스트**:
- [ ] 모든 장애 시나리오 통과

**Phase 9 완료 조건**:
- ✅ 모든 테스트 케이스 통과

---

### Phase 10: 문서화 및 배포 (1주)

**목표**: 사용자 매뉴얼 작성

#### 10.1 문서 작성 (5일)

**문서 리스트**:

1. **MULTIHEAD_QUICKSTART.md**
   - my_multihead_cluster.yaml 작성 방법
   - 첫 서버 시작 (Bootstrap)
   - 추가 서버 조인
   - 클러스터 상태 확인

2. **MULTIHEAD_CONFIG_REFERENCE.md**
   - my_multihead_cluster.yaml 전체 스펙
   - 각 섹션 설명
   - services 옵션 설명

3. **MULTIHEAD_OPERATIONS.md**
   - 노드 추가/제거
   - 백업/복원
   - 업데이트 절차
   - 트러블슈팅

**체크리스트**:
- [ ] 모든 문서 작성 완료

#### 10.2 프로덕션 배포 (2일)

**체크리스트**:
- [ ] 프로덕션 배포 완료

**Phase 10 완료 조건**:
- ✅ 문서화 완료
- ✅ 프로덕션 배포 완료

---

## 🎯 최종 완료 조건

### ✅ 전체 시스템 요구사항 충족

- [x] **my_multihead_cluster.yaml 기반 설정**
  - controllers 리스트로 다중 헤드 지원
  - 각 controller마다 services 옵션
  - vip_owner 설정

- [x] **자동 탐지 및 동적 클러스터링**
  - YAML 파싱
  - 활성 노드 자동 탐지
  - Bootstrap vs Join 자동 결정
  - N중화 → N+1중화 자동 구성

- [x] **공유 스토리지 및 백업**
  - /data/system_backup → 백업 저장소
  - backup.sh → 원클릭 백업
  - restore.sh → 원클릭 복원

- [x] **완벽한 장애 대응**
  - 3대까지 동시 다운 OK
  - 자동 VIP 전환
  - 무중단 업데이트

### ⏱️ 전체 소요 시간: **8-10주**

| Phase | 기간 | 주요 작업 |
|-------|------|----------|
| Phase 0 | 3일 | YAML 파싱 및 자동 탐지 |
| Phase 1 | 1주 | GlusterFS 동적 클러스터링 |
| Phase 2 | 1주 | MariaDB Galera 동적 클러스터링 |
| Phase 3 | 1주 | Redis Cluster 동적 클러스터링 |
| Phase 4 | 1주 | Slurm Multi-Master |
| Phase 5 | 3일 | Keepalived VIP 관리 |
| Phase 6 | 1주 | 웹 서비스 통합 |
| Phase 7 | 1주 | 백업/복원 시스템 |
| Phase 8 | 1주 | 메인 스크립트 작성 |
| Phase 9 | 2주 | 테스트 및 검증 |
| Phase 10 | 1주 | 문서화 및 배포 |

---

## 🚀 사용 예시

### 첫 서버 시작 (Bootstrap)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/cluster
./start_multihead.sh --config ../my_multihead_cluster.yaml --bootstrap
```

### 추가 서버 조인 (자동)

```bash
./start_multihead.sh --config ../my_multihead_cluster.yaml
→ 자동으로 기존 클러스터 탐지 및 조인
```

### 클러스터 상태 확인

```bash
./utils/cluster_info.sh --config ../my_multihead_cluster.yaml
```

### 백업

```bash
./backup/backup.sh --config ../my_multihead_cluster.yaml
```

### 복원

```bash
./backup/restore.sh --config ../my_multihead_cluster.yaml --latest
```

---

이 계획서대로 구현하면 **my_multihead_cluster.yaml 기반 완전 자동화된 멀티헤드 클러스터 시스템**이 완성됩니다!
