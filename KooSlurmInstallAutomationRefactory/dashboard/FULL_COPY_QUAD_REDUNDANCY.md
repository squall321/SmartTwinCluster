# 풀 카피 사중화(Full-Copy Quad-Redundancy) HA 아키텍처

## 📋 전략 개요

### ✅ 풀 카피 사중화란?

```
┌─────────────────────────────────────────────────────────────┐
│  모든 서버가 동일한 기능을 수행 (Full Copy)                   │
│                                                               │
│  • 각 서버: All-in-One (Slurm + Web + DB + Redis)           │
│  • 4대 중 1대 죽어도 → 나머지 3대가 100% 기능 수행            │
│  • 부하 분산: 4대가 동시에 모든 요청 처리                     │
│  • 데이터 동기화: 실시간 Multi-Master Replication            │
└─────────────────────────────────────────────────────────────┘
```

**핵심 차이점**:
- ❌ 기존 계획: 역할 분리 (Web/App/Data Tier 분리)
- ✅ 새 계획: **모든 서버가 동일** (완벽한 동질성)

**장점**:
- ✅ **완벽한 장애 대응**: 3대까지 죽어도 서비스 가능
- ✅ **간단한 관리**: 모든 서버 설정 동일
- ✅ **최대 성능**: 고사양 서버 4대 모두 활용
- ✅ **쉬운 확장**: 동일한 서버 1대 추가하면 5중화

**단점**:
- ⚠️ **리소스 중복**: 각 서버가 모든 기능 실행 (CPU/메모리 낭비 가능)
- ⚠️ **복잡한 동기화**: Multi-Master DB 동기화 필요
- ⚠️ **초기 구축 비용**: 4대 모두 고사양 필요

---

## 🏗️ 아키텍처 설계

### 전체 구성도

```
                          인터넷 / 사용자
                                 │
                    ┌────────────▼────────────┐
                    │   VIP (192.168.1.100)   │ ← Keepalived (Floating IP)
                    │   Load Balancer         │
                    └────────────┬────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
         │                       │                       │
    ┌────▼─────┐           ┌────▼─────┐           ┌────▼─────┐           ┌──────────┐
    │ Server1  │           │ Server2  │           │ Server3  │           │ Server4  │
    │ (MASTER) │◄─────────►│ (MASTER) │◄─────────►│ (MASTER) │◄─────────►│ (MASTER) │
    │          │   Sync    │          │   Sync    │          │   Sync    │          │
    └────┬─────┘           └────┬─────┘           └────┬─────┘           └────┬─────┘
         │                      │                      │                       │
    ┌────▼──────────────────────▼──────────────────────▼───────────────────────▼────┐
    │                      모든 서버가 동일한 구성                                    │
    │                                                                                │
    │  ┌─────────────────────────────────────────────────────────────────────────┐  │
    │  │ Slurm Layer                                                              │  │
    │  │  - slurmctld (Multi-Master with VIP failover)                           │  │
    │  │  - slurmdbd (MariaDB 연결)                                              │  │
    │  │  - Compute Node Manager                                                 │  │
    │  └─────────────────────────────────────────────────────────────────────────┘  │
    │                                                                                │
    │  ┌─────────────────────────────────────────────────────────────────────────┐  │
    │  │ Web Services Layer                                                       │  │
    │  │  - auth_portal (4430/4431)                                              │  │
    │  │  - backend (5010/5011)                                                  │  │
    │  │  - kooCAEWebServer (5000/5001)                                          │  │
    │  │  - dashboard (5173)                                                     │  │
    │  │  - app_framework (5174)                                                 │  │
    │  │  - Nginx (로컬 reverse proxy)                                           │  │
    │  └─────────────────────────────────────────────────────────────────────────┘  │
    │                                                                                │
    │  ┌─────────────────────────────────────────────────────────────────────────┐  │
    │  │ Data Layer                                                               │  │
    │  │  - Redis Cluster (Multi-Master) ← 4-node cluster                        │  │
    │  │  - MariaDB Galera Cluster (Multi-Master) ← 4-node cluster               │  │
    │  │  - Shared Storage (GlusterFS 4-node) ← 프론트엔드 빌드 파일 공유         │  │
    │  └─────────────────────────────────────────────────────────────────────────┘  │
    │                                                                                │
    │  ┌─────────────────────────────────────────────────────────────────────────┐  │
    │  │ Monitoring Layer                                                         │  │
    │  │  - Prometheus (각 서버에서 메트릭 수집)                                   │  │
    │  │  - Node Exporter (9100)                                                 │  │
    │  │  - Health Check Script (/health)                                        │  │
    │  └─────────────────────────────────────────────────────────────────────────┘  │
    └────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔧 각 레이어별 구성

### 1️⃣ Load Balancer (VIP + Keepalived)

**목적**: 단일 진입점, 자동 장애 전환

```
VIP: 192.168.1.100 (Floating IP)
│
├─ Server1 (Priority 100) ← MASTER
├─ Server2 (Priority 99)
├─ Server3 (Priority 98)
└─ Server4 (Priority 97)
```

**Keepalived 설정** (`/etc/keepalived/keepalived.conf`):

Server1 (Priority 100):
```bash
vrrp_script check_services {
    script "/usr/local/bin/check_all_services.sh"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface ens18
    virtual_router_id 51
    priority 100  # Server1: 100, Server2: 99, Server3: 98, Server4: 97
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass hpc_cluster_secret
    }

    virtual_ipaddress {
        192.168.1.100/24
    }

    track_script {
        check_services
    }

    # 장애 전환 시 알림
    notify_master "/usr/local/bin/notify_master.sh"
    notify_backup "/usr/local/bin/notify_backup.sh"
    notify_fault "/usr/local/bin/notify_fault.sh"
}
```

**헬스체크 스크립트** (`/usr/local/bin/check_all_services.sh`):
```bash
#!/bin/bash
# 모든 핵심 서비스 체크

check_service() {
    local service=$1
    systemctl is-active --quiet $service
    return $?
}

# 핵심 서비스 리스트
CRITICAL_SERVICES=(
    "slurmctld"
    "redis-server"
    "mariadb"
    "auth_portal_4430"
    "backend_5010"
    "kooCAEWebServer_5000"
)

for service in "${CRITICAL_SERVICES[@]}"; do
    if ! check_service "$service"; then
        echo "CRITICAL: $service is down"
        exit 1
    fi
done

# HTTP 헬스체크
curl -sf http://localhost:4430/health > /dev/null || exit 1
curl -sf http://localhost:5010/health > /dev/null || exit 1
curl -sf http://localhost:5000/health > /dev/null || exit 1

exit 0
```

**작동 방식**:
1. Server1이 MASTER로 VIP 소유
2. 2초마다 헬스체크 실행
3. Server1 장애 시 → VIP가 Server2로 즉시 이동 (2-3초)
4. Server1 복구 시 → VIP는 Server2에 유지 (preempt 비활성화)

---

### 2️⃣ Slurm Multi-Master Configuration

**목적**: 4대 중 어느 서버든 Slurm Controller 역할 수행 가능

#### Slurm 설정 (`/etc/slurm/slurm.conf`)

```bash
# Multi-Master 설정 (4대 모두 백업 컨트롤러)
SlurmctldHost=server1(192.168.1.101)
SlurmctldHost=server2(192.168.1.102)
SlurmctldHost=server3(192.168.1.103)
SlurmctldHost=server4(192.168.1.104)

# 공유 상태 디렉토리 (GlusterFS)
StateSaveLocation=/mnt/gluster/slurm/state
SlurmdSpoolDir=/var/spool/slurmd

# 빠른 장애 전환
SlurmctldTimeout=120
SlurmdTimeout=300
MessageTimeout=30

# 작업 큐 공유 (MariaDB via slurmdbd)
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=127.0.0.1  # 로컬 slurmdbd → 로컬 MariaDB (Galera)
AccountingStoragePort=6819

# 로그 중앙화 (GlusterFS)
SlurmctldLogFile=/mnt/gluster/slurm/logs/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
```

#### Slurmdbd 설정 (`/etc/slurm/slurmdbd.conf`)

```bash
# MariaDB Galera 연결 (로컬 노드)
StorageType=accounting_storage/mysql
StorageHost=127.0.0.1
StoragePort=3306
StorageUser=slurm
StoragePass=slurm_password

# Galera가 multi-master이므로 어느 노드든 읽기/쓰기 가능
# 장애 시 자동으로 다른 노드의 slurmdbd가 계속 쓰기

LogFile=/mnt/gluster/slurm/logs/slurmdbd.log
```

#### systemd 서비스 (모든 서버에 동일하게 설치)

`/etc/systemd/system/slurmctld.service`:
```ini
[Unit]
Description=Slurm Controller Daemon
After=network.target mariadb.service
Requires=mariadb.service

[Service]
Type=forking
ExecStart=/usr/local/slurm/sbin/slurmctld -D
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

**모든 서버에서 slurmctld 실행**:
- Primary: VIP를 가진 서버의 slurmctld가 Active
- Others: Standby 모드로 대기
- 장애 시: VIP가 이동하면 해당 서버의 slurmctld가 Active

---

### 3️⃣ MariaDB Galera Cluster (4-node Multi-Master)

**목적**: 모든 노드에서 읽기/쓰기 가능, 자동 동기화

#### MariaDB 설치 (모든 서버)

```bash
apt install -y mariadb-server galera-4 rsync
```

#### Galera 설정 (`/etc/mysql/mariadb.conf.d/galera.cnf`)

Server1:
```ini
[galera]
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so

# 클러스터 설정
wsrep_cluster_name="hpc_portal_cluster"
wsrep_cluster_address="gcomm://192.168.1.101,192.168.1.102,192.168.1.103,192.168.1.104"

# 노드 설정
wsrep_node_address="192.168.1.101"
wsrep_node_name="server1"

# Replication 설정
binlog_format=row
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2

# SST (State Snapshot Transfer) 방식
wsrep_sst_method=rsync

# 동시 쓰기 허용
wsrep_slave_threads=4
```

Server2/3/4는 `wsrep_node_address`와 `wsrep_node_name`만 변경

#### 클러스터 초기화

**첫 번째 노드 (Server1):**
```bash
# Bootstrap (최초 1회만)
galera_new_cluster

# 또는
systemctl start mariadb@bootstrap
```

**나머지 노드 (Server2/3/4):**
```bash
# 일반 시작 (자동으로 클러스터 조인)
systemctl start mariadb
```

#### 클러스터 상태 확인

```bash
mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
# 결과: 4 (4개 노드 모두 연결됨)

mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_ready';"
# 결과: ON

mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_local_state_comment';"
# 결과: Synced
```

#### 데이터베이스 생성 (한 노드에서만)

```sql
-- Server1에서 실행 (자동으로 모든 노드에 복제됨)

-- Slurm accounting DB
CREATE DATABASE slurm_acct_db;
CREATE USER 'slurm'@'localhost' IDENTIFIED BY 'slurm_password';
GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';

-- Auth Portal 사용자 DB
CREATE DATABASE auth_portal;
CREATE USER 'auth_user'@'localhost' IDENTIFIED BY 'auth_password';
GRANT ALL ON auth_portal.* TO 'auth_user'@'localhost';

FLUSH PRIVILEGES;
```

**장애 대응**:
- 1-2대 다운: 나머지 노드가 자동으로 쿼럼 유지, 서비스 계속
- 3대 다운 (1대만 남음): Read-Only 모드 전환 (안전 장치)
- 복구: 다운된 노드 재시작 시 자동으로 데이터 동기화 (IST/SST)

---

### 4️⃣ Redis Cluster (4-node Multi-Master)

**목적**: 세션 데이터 공유, 4대 모두 읽기/쓰기 가능

#### Redis 설치 및 설정

```bash
apt install -y redis-server redis-tools
```

#### Redis Cluster 설정 (`/etc/redis/redis.conf`)

Server1:
```bash
# 네트워크
bind 0.0.0.0
port 6379
protected-mode yes
requirepass redis_cluster_secret

# 클러스터 모드
cluster-enabled yes
cluster-config-file nodes-6379.conf
cluster-node-timeout 5000

# 데이터 동기화
appendonly yes
appendfsync everysec

# 메모리 정책
maxmemory 4gb
maxmemory-policy allkeys-lru
```

#### 클러스터 생성

**모든 노드에서 Redis 시작:**
```bash
systemctl enable redis-server
systemctl start redis-server
```

**클러스터 초기화 (Server1에서):**
```bash
redis-cli --cluster create \
    192.168.1.101:6379 \
    192.168.1.102:6379 \
    192.168.1.103:6379 \
    192.168.1.104:6379 \
    --cluster-replicas 0 \
    -a redis_cluster_secret

# --cluster-replicas 0: 모든 노드가 Master (Replica 없음)
# 4대가 모두 동등한 Master로 동작
```

#### 클러스터 상태 확인

```bash
redis-cli -c -h 192.168.1.101 -a redis_cluster_secret cluster info
# cluster_state:ok
# cluster_slots_assigned:16384
# cluster_known_nodes:4

redis-cli -c -h 192.168.1.101 -a redis_cluster_secret cluster nodes
# 4개 노드 모두 master로 표시됨
```

#### 애플리케이션 연결 (Python)

```python
# auth_portal_4430/config/config.py
import os
from redis.cluster import RedisCluster

# Redis Cluster 연결
REDIS_NODES = [
    {"host": "192.168.1.101", "port": 6379},
    {"host": "192.168.1.102", "port": 6379},
    {"host": "192.168.1.103", "port": 6379},
    {"host": "192.168.1.104", "port": 6379},
]

redis_client = RedisCluster(
    startup_nodes=REDIS_NODES,
    password=os.getenv('REDIS_PASSWORD', 'redis_cluster_secret'),
    decode_responses=True,
    skip_full_coverage_check=True  # 일부 노드 다운되어도 계속 작동
)
```

**장애 대응**:
- 1-2대 다운: 나머지 노드가 해시 슬롯 재분배, 서비스 계속
- 세션 데이터: 특정 키가 다운된 노드에 있었다면 유실 (JWT로 복구 가능)

---

### 5️⃣ GlusterFS (분산 파일 시스템)

**목적**: 프론트엔드 빌드 파일, Slurm 상태 파일 공유

#### GlusterFS 설치

```bash
apt install -y glusterfs-server
systemctl enable glusterd
systemctl start glusterd
```

#### Peer 연결 (Server1에서)

```bash
gluster peer probe 192.168.1.102
gluster peer probe 192.168.1.103
gluster peer probe 192.168.1.104

gluster peer status
# State: Peer in Cluster (Connected)
```

#### Volume 생성 (Replica 4)

```bash
# /mnt/gluster_brick 디렉토리 준비 (모든 서버)
mkdir -p /mnt/gluster_brick/shared

# Replica 4 볼륨 생성 (4개 노드에 모두 복제)
gluster volume create shared_data replica 4 \
    192.168.1.101:/mnt/gluster_brick/shared \
    192.168.1.102:/mnt/gluster_brick/shared \
    192.168.1.103:/mnt/gluster_brick/shared \
    192.168.1.104:/mnt/gluster_brick/shared

gluster volume start shared_data

# 볼륨 옵션 설정
gluster volume set shared_data performance.cache-size 256MB
gluster volume set shared_data network.ping-timeout 10
```

#### 마운트 (모든 서버)

```bash
# /etc/fstab에 추가
echo "localhost:/shared_data /mnt/gluster glusterfs defaults,_netdev 0 0" >> /etc/fstab

mkdir -p /mnt/gluster
mount -a

# 확인
df -h | grep gluster
# localhost:/shared_data  xxxG  xxxG  xxxG  xx% /mnt/gluster
```

#### 디렉토리 구조

```bash
/mnt/gluster/
├── frontend_builds/         # 프론트엔드 빌드 결과 (Nginx가 서빙)
│   ├── auth_frontend/
│   ├── dashboard/
│   └── app_framework/
├── slurm/
│   ├── state/               # Slurm 상태 파일
│   ├── logs/                # Slurm 로그
│   └── spool/               # 작업 큐
└── uploads/                 # 사용자 업로드 파일
```

**장애 대응**:
- 1-3대 다운: Replica 4이므로 최소 1대만 살아있으면 데이터 접근 가능
- 복구: 다운된 노드 재시작 시 자동 동기화 (Self-heal)

---

### 6️⃣ Web Services (모든 서버에 동일하게 배포)

**목적**: 4대 모두 동일한 웹서비스 실행

#### 서비스 리스트 (각 서버에 All-in-One)

```
auth_portal_4430        → JWT 인증 백엔드
auth_frontend_4431      → SSO 로그인 UI (빌드 파일 → GlusterFS)
backend_5010            → Dashboard API
websocket_5011          → 실시간 모니터링
kooCAEWebServer_5000    → CAE 자동화 백엔드
kooCAEWebAutomation_5001 → CAE 자동화 실행기
dashboard_5173          → Dashboard UI (빌드 파일 → GlusterFS)
app_5174                → App Framework UI (빌드 파일 → GlusterFS)
```

#### 배포 전략

**방법 1: Git + Systemd (추천)**

각 서버에서:
```bash
# 1. 저장소 클론
cd /opt
git clone https://github.com/your-org/hpc-dashboard.git
cd hpc-dashboard/dashboard

# 2. 백엔드 서비스 설치 (Python)
for service in auth_portal_4430 backend_5010 kooCAEWebServer_5000 kooCAEWebAutomationServer_5001 websocket_5011; do
    cd $service
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    deactivate
    cd ..
done

# 3. 프론트엔드 빌드 → GlusterFS로 복사
./build_all_frontends.sh

# 빌드 결과를 GlusterFS로 복사 (1개 서버에서만 실행)
if [ "$(hostname)" == "server1" ]; then
    cp -r auth_frontend_4431/dist /mnt/gluster/frontend_builds/auth_frontend
    cp -r dashboard_5173/dist /mnt/gluster/frontend_builds/dashboard
    cp -r app_5174/dist /mnt/gluster/frontend_builds/app_framework
fi

# 4. 환경변수 설정
for service in auth_portal_4430 backend_5010 kooCAEWebServer_5000 kooCAEWebAutomationServer_5001; do
    cat > $service/.env <<EOF
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=redis_cluster_secret
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=auth_user
DB_PASSWORD=auth_password
MOCK_MODE=false
EOF
done

# 5. Systemd 서비스 생성 및 시작
./create_systemd_services.sh
systemctl daemon-reload
./start_complete.sh
```

#### Nginx 설정 (로컬 리버스 프록시)

각 서버의 `/etc/nginx/sites-available/local-proxy.conf`:
```nginx
# GlusterFS에서 정적 파일 서빙
server {
    listen 80;
    server_name localhost;

    # Auth Frontend
    location /auth/ {
        alias /mnt/gluster/frontend_builds/auth_frontend/;
        try_files $uri $uri/ /auth/index.html;
    }

    # Dashboard Frontend
    location /dashboard/ {
        alias /mnt/gluster/frontend_builds/dashboard/;
        try_files $uri $uri/ /dashboard/index.html;
    }

    # App Framework Frontend
    location /app/ {
        alias /mnt/gluster/frontend_builds/app_framework/;
        try_files $uri $uri/ /app/index.html;
    }

    # 백엔드 API 프록시 (로컬 서비스)
    location /api/auth {
        proxy_pass http://127.0.0.1:4430;
    }

    location /api/dashboard {
        proxy_pass http://127.0.0.1:5010;
    }

    location /api/cae {
        proxy_pass http://127.0.0.1:5000;
    }

    # WebSocket
    location /ws/ {
        proxy_pass http://127.0.0.1:5011;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

---

### 7️⃣ External Load Balancer (선택 사항)

**목적**: VIP 앞단에 HAProxy 추가로 더 정교한 라우팅

```
사용자 → HAProxy (외부) → VIP (Keepalived) → 4대 서버
```

**HAProxy 설정** (`/etc/haproxy/haproxy.cfg`):
```bash
frontend https_frontend
    bind *:443 ssl crt /etc/ssl/certs/hpc-portal.pem
    mode http

    # 헬스체크 기반 라우팅
    acl server1_up srv_is_up(hpc_backend/server1)
    acl server2_up srv_is_up(hpc_backend/server2)
    acl server3_up srv_is_up(hpc_backend/server3)
    acl server4_up srv_is_up(hpc_backend/server4)

    use_backend hpc_backend

backend hpc_backend
    mode http
    balance roundrobin
    option httpchk GET /health

    # 4대 서버 모두 등록
    server server1 192.168.1.101:80 check inter 2s fall 3 rise 2
    server server2 192.168.1.102:80 check inter 2s fall 3 rise 2
    server server3 192.168.1.103:80 check inter 2s fall 3 rise 2
    server server4 192.168.1.104:80 check inter 2s fall 3 rise 2

    # Sticky Session (WebSocket용)
    cookie SERVERID insert indirect nocache
    server server1 192.168.1.101:80 check cookie s1
    server server2 192.168.1.102:80 check cookie s2
    server server3 192.168.1.103:80 check cookie s3
    server server4 192.168.1.104:80 check cookie s4
```

---

## 📊 장애 시나리오별 대응

### 시나리오 1: Server1 완전 다운

**발생 순서**:
1. Keepalived 헬스체크 실패 (2초)
2. VIP가 Server2로 이동 (3초)
3. Slurm: Server2의 slurmctld가 Active
4. MariaDB Galera: 3노드로 쿼럼 유지
5. Redis Cluster: 해시 슬롯 재분배
6. GlusterFS: Replica 3으로 서비스 계속

**사용자 영향**:
- ✅ 5초 이내 자동 복구
- ✅ 진행 중인 HTTP 요청: 일부 실패 (클라이언트 재시도 필요)
- ✅ WebSocket: 재접속 (프론트엔드 자동 재연결)
- ✅ Slurm 작업: 영향 없음 (계속 실행)

---

### 시나리오 2: Server1, Server2 동시 다운 (2대 다운)

**발생 순서**:
1. VIP가 Server3로 이동
2. MariaDB Galera: 2노드로 쿼럼 유지 (정상)
3. Redis Cluster: 2노드로 해시 슬롯 재분배
4. GlusterFS: Replica 2로 서비스 계속

**사용자 영향**:
- ✅ 서비스 정상 작동
- ⚠️ 성능 50% 감소 (2대가 4대 분량 처리)
- ⚠️ 추가 장애 시 위험 (1대 더 다운되면 문제)

---

### 시나리오 3: Server1, Server2, Server3 다운 (3대 다운 - 최악)

**발생 순서**:
1. VIP가 Server4로 이동
2. MariaDB Galera: 1노드만 남음 → **Read-Only 모드**
3. Redis Cluster: 1노드만 남음 → 일부 키 유실 가능
4. GlusterFS: Replica 1 → 데이터 접근 가능하지만 복제 없음

**사용자 영향**:
- ⚠️ **읽기 전용 모드**: 로그인, 조회는 가능, 작업 제출/수정 불가
- ⚠️ 일부 세션 유실 (Redis 키 유실)
- ⚠️ 성능 75% 감소
- 🚨 **긴급 복구 필요**: 최소 1대 이상 복구해야 쓰기 재개

**복구 방법**:
```bash
# Server2 또는 Server3 재시작
# MariaDB가 자동으로 클러스터 재조인

# 쿼럼 복구 확인
mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
# 결과: 2 이상이면 Read-Write 모드 복구
```

---

## 🛠️ 구현 체크리스트

### Phase 1: 하드웨어 준비 (1-3일)

- [ ] 서버 4대 준비 (동일 스펙)
  - CPU: 16+ Core
  - RAM: 64+ GB
  - Disk: 1TB+ SSD
  - Network: 10Gbps 이상 권장
- [ ] 네트워크 구성
  - 고정 IP 할당 (192.168.1.101-104)
  - VIP 예약 (192.168.1.100)
  - 스위치 설정 (VRRP/Multicast 허용)

### Phase 2: 기본 인프라 (1주)

- [ ] OS 설치 및 업데이트 (Ubuntu 22.04 LTS)
- [ ] 호스트명 설정 (server1-4)
- [ ] SSH 키 교환 (패스워드 없이 접속)
- [ ] NTP 동기화 설정
- [ ] 방화벽 설정 (iptables/ufw)

### Phase 3: 데이터 레이어 (2주)

- [ ] MariaDB Galera Cluster 구성
  - [ ] Server1-4 모두 설치
  - [ ] 클러스터 초기화
  - [ ] 데이터베이스 생성
  - [ ] 장애 테스트 (1대 중지 → 자동 복구 확인)
- [ ] Redis Cluster 구성
  - [ ] Server1-4 모두 설치
  - [ ] 클러스터 생성
  - [ ] 연결 테스트
- [ ] GlusterFS 구성
  - [ ] Peer 연결
  - [ ] Replica 4 볼륨 생성
  - [ ] 마운트 및 테스트

### Phase 4: Slurm 설정 (1주)

- [ ] Slurm 설치 (Server1-4)
- [ ] `slurm.conf` Multi-Master 설정
- [ ] `slurmdbd.conf` Galera 연결 설정
- [ ] Systemd 서비스 등록
- [ ] VIP 전환 테스트

### Phase 5: 웹 서비스 배포 (2주)

- [ ] Git 저장소 클론 (Server1-4)
- [ ] Python 가상환경 설정
- [ ] Node.js 의존성 설치
- [ ] 프론트엔드 빌드 → GlusterFS 복사
- [ ] 환경변수 설정 (Redis/DB 연결)
- [ ] Systemd 서비스 생성
- [ ] Nginx 로컬 프록시 설정

### Phase 6: Keepalived 설정 (3일)

- [ ] Keepalived 설치 (Server1-4)
- [ ] VIP 설정 (Priority: 100/99/98/97)
- [ ] 헬스체크 스크립트 작성
- [ ] 알림 스크립트 작성 (Slack/Email)
- [ ] VIP 전환 테스트

### Phase 7: 모니터링 (1주)

- [ ] Prometheus 설치 (중앙 서버 또는 Server1)
- [ ] Node Exporter (Server1-4)
- [ ] Grafana 대시보드
- [ ] 알림 규칙 설정

### Phase 8: 테스트 및 검증 (1-2주)

- [ ] 부하 테스트 (4대 → 3대 → 2대 → 1대)
- [ ] 장애 전환 테스트 (각 서버 순차적 중지)
- [ ] 데이터 일관성 테스트 (Galera, Redis, GlusterFS)
- [ ] 백업/복구 테스트
- [ ] 사용자 시나리오 테스트

---

## 🚀 배포 자동화 스크립트

### 전체 배포 스크립트 (`deploy_all.sh`)

```bash
#!/bin/bash
# 4대 서버에 동일하게 배포하는 스크립트

SERVERS=("192.168.1.101" "192.168.1.102" "192.168.1.103" "192.168.1.104")
SSH_USER="hpcadmin"

# 병렬 실행
for server in "${SERVERS[@]}"; do
    echo "🚀 Deploying to $server..."

    ssh $SSH_USER@$server << 'EOF' &
        set -e

        # Git pull
        cd /opt/hpc-dashboard
        git pull origin main

        # 백엔드 재시작
        for service in auth_portal_4430 backend_5010 kooCAEWebServer_5000; do
            sudo systemctl restart $service
        done

        # 프론트엔드 재빌드 (Server1에서만)
        if [ "$(hostname)" == "server1" ]; then
            cd dashboard
            ./build_all_frontends.sh
            cp -r */dist /mnt/gluster/frontend_builds/
        fi

        echo "✅ Deployment on $(hostname) completed"
EOF
done

# 모든 백그라운드 작업 완료 대기
wait

echo "🎉 All servers deployed successfully!"
```

---

## 📈 성능 및 비용 분석

### 리소스 사용률 (4대 서버)

| 상태 | CPU | RAM | 네트워크 | 비고 |
|------|-----|-----|----------|------|
| **정상 (4대)** | 25% | 40% | 낮음 | 여유 충분 |
| **1대 다운 (3대)** | 33% | 53% | 중간 | 정상 운영 |
| **2대 다운 (2대)** | 50% | 80% | 높음 | 서비스 가능, 성능 저하 |
| **3대 다운 (1대)** | 100% | 100% | 매우 높음 | 긴급 상황, 읽기만 가능 |

### 장애 확률 (가정: 각 서버 99% 가용성)

```
1대 운영: 99.0% 가용성
2대 운영: 99.99% (한 대만 살아있으면 OK)
4대 운영: 99.999999% (네 대 모두 죽을 확률: 0.01^4)
```

### 비용 비교

| 구성 | 초기 비용 | 월 운영 비용 | 가용성 |
|------|----------|-------------|--------|
| **단일 서버** | 1x | 1x | 99% |
| **이중화** | 2x | 2x | 99.99% |
| **풀 카피 4중화** | 4x | 4x | 99.999999% |

**판단 기준**:
- 미션 크리티컬 시스템 (HPC 클러스터) → ✅ 4중화 권장
- 개발/테스트 환경 → 이중화로 충분

---

## ⚙️ 유지보수 가이드

### 정기 점검 (월 1회)

```bash
#!/bin/bash
# monthly_check.sh

echo "=== Galera Cluster Status ==="
mysql -u root -p -e "SHOW STATUS LIKE 'wsrep%';" | grep -E 'cluster_size|ready|local_state'

echo "=== Redis Cluster Status ==="
redis-cli -c cluster info

echo "=== GlusterFS Status ==="
gluster volume status shared_data

echo "=== Keepalived Status ==="
systemctl status keepalived | grep -E 'Active|VIP'

echo "=== Disk Usage ==="
df -h | grep -E 'gluster|Filesystem'

echo "=== Service Status ==="
for service in slurmctld slurmdbd mariadb redis-server auth_portal_4430 backend_5010; do
    systemctl is-active --quiet $service && echo "✅ $service" || echo "❌ $service"
done
```

### 업데이트 절차 (Rolling Update)

```bash
# 1. Server4 업데이트 (Priority 가장 낮음)
ssh server4
sudo systemctl stop all_services
cd /opt/hpc-dashboard && git pull
sudo systemctl start all_services

# 2. Server3 업데이트
# ... 동일 ...

# 3. Server2 업데이트
# ...

# 4. Server1 업데이트 (마지막, VIP 소유)
# ...
```

---

## 🎯 결론

### ✅ 풀 카피 사중화 가능한가? → **네, 가능합니다!**

**이유**:
1. **MariaDB Galera**: Multi-Master 지원, 4-node 검증됨
2. **Redis Cluster**: Multi-Master 지원, 무제한 노드
3. **GlusterFS**: Replica 4 지원, 자동 복구
4. **Slurm**: Multi-Master 설정 공식 지원

### 🔧 수정해야 할 것

| 파일 | 변경 내용 |
|------|----------|
| `slurm.conf` | `SlurmctldHost` 4개 선언 (4줄) |
| 웹서비스 `.env` | Redis/DB 주소 → `127.0.0.1` (로컬) |
| Nginx 설정 | 정적 파일 경로 → `/mnt/gluster/frontend_builds/` |

**총 수정량**: ~15개 파일, ~40줄

### ⏱️ 예상 소요 시간

- **Phase 1-2 (하드웨어)**: 3-5일
- **Phase 3 (데이터 레이어)**: 2주
- **Phase 4 (Slurm)**: 1주
- **Phase 5 (웹 서비스)**: 2주
- **Phase 6 (Keepalived)**: 3일
- **Phase 7-8 (모니터링/테스트)**: 2주

**총 6-7주**

### 💰 투자 대비 효과

```
초기 투자: 서버 4대 + 6-7주 작업
운영 이점:
  ✅ 99.999999% 가용성 (연간 다운타임 < 3초)
  ✅ 3대까지 동시 장애 대응
  ✅ 무중단 업데이트 (Rolling Update)
  ✅ 고성능 (4대 병렬 처리)
  ✅ 간단한 관리 (모든 서버 동일)
```

**추천**: ✅ HPC 미션 크리티컬 시스템에 최적
