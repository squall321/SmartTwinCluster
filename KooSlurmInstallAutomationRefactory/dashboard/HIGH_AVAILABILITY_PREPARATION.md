# 사중화(4중화) 구성 준비 가이드

**작성일**: 2025-10-26
**대상**: HPC Portal 시스템 고가용성 구성
**목표**: 4대 서버로 무중단 서비스 구성

---

## 📋 현재 시스템 분석

### 현재 구성 (단일 서버)

**서버 정보:**
- IP: `110.15.177.120` (외부), `192.168.122.1` (내부)
- OS: Ubuntu (Linux 5.15.0)
- 역할: All-in-One (웹, 백엔드, DB, Slurm Controller)

**실행 중인 핵심 서비스:**
```
- Nginx (80)
- Redis (6379)
- MariaDB (3306)
- Slurm Controller (slurmctld)
- Slurm Database (slurmdbd)
- 10+ Python 백엔드 서비스
- 5+ Vite 프론트엔드 (dev 모드)
```

**현재 문제점:**
- ❌ 단일 장애점(SPOF): 서버 다운 시 전체 서비스 중단
- ❌ 수평 확장 불가: 트래픽 증가 시 대응 어려움
- ❌ 무중단 배포 불가: 업데이트 시 서비스 중단 필수
- ❌ 데이터 유실 위험: 백업 없으면 복구 불가

---

## 🎯 사중화 목표 아키텍처

### 계층별 분리 전략

```
                     ┌─────────────────────┐
                     │   Load Balancer     │ ← 단일 진입점
                     │  (HAProxy/Nginx)    │
                     │   + Keepalived      │ ← VIP 관리
                     └──────────┬──────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────▼────────┐ ┌─────▼──────┐ ┌───────▼──────┐
    │  Web Tier #1     │ │ Web #2     │ │  Web #3      │ ← 웹 서버 3~4대
    │  - Nginx         │ │ - Nginx    │ │  - Nginx     │
    │  - Static Files  │ │ - Static   │ │  - Static    │
    └─────────┬────────┘ └─────┬──────┘ └───────┬──────┘
              │                 │                 │
              └─────────────────┼─────────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────▼────────┐ ┌─────▼──────┐ ┌───────▼──────┐
    │  App Tier #1     │ │ App #2     │ │  App #3      │ ← 앱 서버 3~4대
    │  - Flask 5010    │ │ - Flask    │ │  - Flask     │
    │  - Flask 5000    │ │ - Flask    │ │  - Flask     │
    │  - WebSocket     │ │ - WS       │ │  - WS        │
    └─────────┬────────┘ └─────┬──────┘ └───────┬──────┘
              │                 │                 │
              └─────────────────┼─────────────────┘
                                │
              ┌─────────────────┴─────────────────┐
              │                                   │
    ┌─────────▼────────┐              ┌──────────▼──────┐
    │  Data Tier       │              │  Slurm Tier     │
    │  - Redis Cluster │              │  - slurmctld HA │
    │  - MariaDB Galera│              │  - slurmdbd HA  │
    │  (3-node)        │              │  (Active-Standby)│
    └──────────────────┘              └─────────────────┘
```

---

## 🛠️ 필요한 인프라 준비사항

### 1. **하드웨어 / VM 요구사항**

#### 최소 구성 (4대)
```
[서버 1] Load Balancer + Web Tier
- CPU: 4 Core
- RAM: 8GB
- Disk: 100GB
- 역할: HAProxy/Keepalived + Nginx

[서버 2] App Tier + Slurm Controller
- CPU: 8 Core
- RAM: 16GB
- Disk: 200GB
- 역할: Python 백엔드 + Slurm Controller

[서버 3] App Tier (Replica)
- CPU: 8 Core
- RAM: 16GB
- Disk: 200GB
- 역할: Python 백엔드 (Active-Active)

[서버 4] Data Tier
- CPU: 4 Core
- RAM: 16GB
- Disk: 500GB (SSD 권장)
- 역할: Redis + MariaDB Master
```

#### 권장 구성 (7대)
```
[서버 1-2] Load Balancer (Active-Standby)
[서버 3-5] Web + App Tier (3대)
[서버 6-7] Data Tier (2대, Master-Slave)
```

---

### 2. **네트워크 요구사항**

#### IP 주소 계획
```
# VIP (Virtual IP)
110.15.177.120  → Load Balancer VIP (Keepalived)

# 실제 서버 IP
110.15.177.121  → LB Server #1
110.15.177.122  → LB Server #2
110.15.177.123  → Web/App Server #1
110.15.177.124  → Web/App Server #2
110.15.177.125  → Web/App Server #3
110.15.177.126  → Data Server #1 (Master)
110.15.177.127  → Data Server #2 (Slave)
```

#### 네트워크 토폴로지
- **외부 네트워크**: `110.15.177.0/26` (공인 IP)
- **내부 네트워크**: `192.168.100.0/24` (사설 IP, 서버 간 통신)
- **관리 네트워크**: `10.0.0.0/24` (SSH, 모니터링 전용)

#### 방화벽 규칙
```
# Load Balancer
- 80 (HTTP)
- 443 (HTTPS)
- VRRP (Keepalived)

# Web/App Servers
- 4430, 4431, 5000, 5001, 5010, 5011
- 9090, 9100 (Prometheus)

# Data Servers
- 6379 (Redis)
- 3306 (MariaDB)
- 4567, 4568, 4444 (Galera Cluster)

# Slurm
- 6817, 6818, 6819 (slurmctld)
- 6820 (slurmdbd)
```

---

### 3. **스토리지 요구사항**

#### 공유 스토리지
```
목적: 정적 파일, 업로드 파일, 로그 동기화

옵션 1: NFS
- NFS Server 1대 추가
- /data → 업로드 파일
- /dist → 빌드된 프론트엔드
- 성능: ⭐⭐⭐
- 복잡도: ⭐⭐

옵션 2: GlusterFS (권장)
- 3개 노드로 복제
- Brick: /data, /dist
- 성능: ⭐⭐⭐⭐
- 복잡도: ⭐⭐⭐

옵션 3: Ceph
- Object Storage 구성
- 성능: ⭐⭐⭐⭐⭐
- 복잡도: ⭐⭐⭐⭐⭐
```

#### 로컬 스토리지
```
각 서버:
- OS: 50GB
- Logs: 50GB
- Temp: 50GB
- 여유: 50GB
```

---

## 💾 데이터베이스 준비사항

### 1. **Redis 클러스터 구성**

#### 현재 상태
```
- 단일 Redis (127.0.0.1:6379)
- 용도: JWT 세션 저장
- 데이터: 휘발성 (TTL 8시간)
```

#### 필요 준비사항

**방법 1: Redis Sentinel (권장)**
```
구성:
- Redis Master 1대
- Redis Slave 2대
- Sentinel 3대 (각 Redis 노드에 co-located)

장점:
- 자동 failover
- 설정 간단
- 기존 코드 수정 최소

준비물:
- Redis 서버 3대
- Sentinel 설정 파일
```

**방법 2: Redis Cluster**
```
구성:
- 최소 6노드 (Master 3 + Slave 3)

장점:
- 데이터 샤딩 (확장성)
- 자동 failover

단점:
- 복잡도 높음
- 일부 명령어 제한
```

#### 필요 작업
```bash
# 각 Redis 노드 설정
1. redis.conf 수정
   - bind 0.0.0.0
   - requirepass <password>
   - masterauth <password>

2. Sentinel 설정
   sentinel monitor mymaster <master-ip> 6379 2
   sentinel auth-pass mymaster <password>
   sentinel down-after-milliseconds mymaster 5000
   sentinel failover-timeout mymaster 10000

3. 백엔드 코드에서 Sentinel 주소 사용
   - redis-py-sentinel 라이브러리 설치
   - 연결 문자열 변경
```

---

### 2. **MariaDB Galera Cluster**

#### 현재 상태
```
- 단일 MariaDB (127.0.0.1:3306)
- 사용처: slurmdbd (Slurm accounting)
- 데이터: 영구 저장 필요
```

#### 필요 준비사항

**Galera Cluster (3-node)**
```
구성:
- MariaDB 10.6+ with Galera
- 3개 노드 (Multi-Master)
- 동기식 복제

장점:
- 모든 노드에서 읽기/쓰기 가능
- 자동 failover
- 데이터 정합성 보장

준비물:
- MariaDB 서버 3대
- Galera 라이브러리 설치
```

#### 필요 작업
```bash
# 각 MariaDB 노드 설정
1. Galera 설정 추가 (/etc/mysql/mariadb.conf.d/galera.cnf)
   wsrep_on=ON
   wsrep_provider=/usr/lib/galera/libgalera_smm.so
   wsrep_cluster_address="gcomm://node1,node2,node3"
   wsrep_cluster_name="hpc_cluster"
   wsrep_node_address="<node-ip>"
   wsrep_node_name="<node-name>"
   wsrep_sst_method=rsync
   binlog_format=row
   default_storage_engine=InnoDB
   innodb_autoinc_lock_mode=2

2. 초기 부트스트랩
   galera_new_cluster (첫 노드에서만)

3. 나머지 노드 시작
   systemctl start mariadb

4. 데이터베이스 마이그레이션
   - 기존 slurmdbd 데이터 덤프
   - 새 클러스터로 임포트
```

---

### 3. **SQLite → 중앙 DB 마이그레이션**

#### 현재 상태 (문제점)
```
SQLite 파일들:
- dashboard/backend_5010/database/dashboard.db
- dashboard/backend_5010/vnc_sessions.db
- dashboard/kooCAEWebServer_5000/db/users.db
- dashboard/websocket_5011/database/dashboard.db

문제:
- 각 앱 서버마다 로컬 DB → 데이터 불일치
- 파일 기반 → 동시성 제한
- 백업/복제 어려움
```

#### 필요 준비사항

**마이그레이션 계획**
```
SQLite → MariaDB (또는 PostgreSQL)

변환할 테이블:
1. notifications (알림)
2. job_templates (Job 템플릿)
3. dashboard_configs (대시보드 설정)
4. reports (리포트)
5. vnc_sessions (VNC 세션)
6. users (사용자)

준비물:
- MariaDB 데이터베이스 생성
- 스키마 변환 (SQLite → MariaDB)
- ORM 설정 변경 (SQLAlchemy)
```

#### 필요 작업
```python
# 1. SQLAlchemy 연결 문자열 변경
# 기존
SQLALCHEMY_DATABASE_URI = 'sqlite:///database/dashboard.db'

# 변경 후
SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://user:pass@db-cluster-vip:3306/dashboard'

# 2. 데이터 마이그레이션 스크립트
import sqlite3
import mysql.connector

# SQLite → MariaDB 데이터 이전

# 3. 트랜잭션 격리 수준 설정
# Galera Cluster는 SERIALIZABLE 지원 안 함
isolation_level = "READ COMMITTED"
```

---

## 🔄 로드 밸런서 준비사항

### 1. **HAProxy 구성 (권장)**

#### 필요 준비사항
```
서버: 2대 (Active-Standby)
용도: L7 로드 밸런싱 + Health Check
```

#### 설정 예시
```haproxy
# /etc/haproxy/haproxy.cfg

global
    maxconn 4096
    log /dev/log local0

defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    option httplog

# Frontend
frontend http_front
    bind *:80
    acl is_auth path_beg /auth
    acl is_dashboard path_beg /dashboard
    acl is_api path_beg /api
    acl is_ws hdr(Upgrade) -i WebSocket

    use_backend auth_backend if is_auth
    use_backend app_backend if is_api
    use_backend websocket_backend if is_ws
    default_backend web_backend

# Backend - Web Tier (Static Files)
backend web_backend
    balance roundrobin
    option httpchk GET /
    server web1 110.15.177.123:80 check
    server web2 110.15.177.124:80 check
    server web3 110.15.177.125:80 check

# Backend - App Tier (API)
backend app_backend
    balance leastconn
    option httpchk GET /api/health
    server app1 110.15.177.123:5010 check
    server app2 110.15.177.124:5010 check
    server app3 110.15.177.125:5010 check

# Backend - WebSocket
backend websocket_backend
    balance source  # Sticky session
    option httpchk GET /ws/health
    server ws1 110.15.177.123:5011 check
    server ws2 110.15.177.124:5011 check
    server ws3 110.15.177.125:5011 check

# Backend - Auth
backend auth_backend
    balance roundrobin
    option httpchk GET /auth/health
    server auth1 110.15.177.123:4430 check
    server auth2 110.15.177.124:4430 check
```

---

### 2. **Keepalived (VIP 관리)**

#### 필요 준비사항
```
설치: 2대 HAProxy 서버
용도: VIP failover
```

#### 설정 예시
```bash
# /etc/keepalived/keepalived.conf (Master)

vrrp_instance VI_1 {
    state MASTER
    interface enp13s0
    virtual_router_id 51
    priority 100
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass secretpass
    }

    virtual_ipaddress {
        110.15.177.120/26
    }

    track_script {
        chk_haproxy
    }
}

vrrp_script chk_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
}
```

```bash
# /etc/keepalived/keepalived.conf (Backup)
# state BACKUP, priority 90으로 변경
```

---

## 📦 애플리케이션 수정 없이 필요한 작업

### 1. **환경 변수 외부화**

#### 현재 문제
- 하드코딩된 localhost, 127.0.0.1
- 각 서버마다 다른 설정 필요

#### 해결 방법
```bash
# .env 파일 또는 환경 변수

# Redis
REDIS_HOST=redis-cluster-vip
REDIS_PORT=6379
REDIS_PASSWORD=secret

# MariaDB
DB_HOST=mariadb-cluster-vip
DB_PORT=3306
DB_USER=slurm
DB_PASSWORD=secret
DB_NAME=slurm_acct_db

# 서비스 엔드포인트
BACKEND_5010_HOST=0.0.0.0  # 외부 접근 허용
BACKEND_5010_PORT=5010

# Slurm Controller
SLURM_CONTROLLER_HOST=slurm-vip
```

#### 각 서버에 배포
```bash
# Web/App Server #1
REDIS_HOST=110.15.177.126
DB_HOST=110.15.177.126
SERVER_ID=1

# Web/App Server #2
REDIS_HOST=110.15.177.126
DB_HOST=110.15.177.126
SERVER_ID=2
```

---

### 2. **헬스 체크 엔드포인트 추가**

#### 필요한 엔드포인트
```python
# backend_5010/app.py

@app.route('/api/health', methods=['GET'])
def health_check():
    """Load Balancer용 헬스 체크"""
    checks = {
        'redis': check_redis_connection(),
        'database': check_db_connection(),
        'slurm': check_slurm_connection(),
    }

    if all(checks.values()):
        return jsonify({'status': 'healthy', 'checks': checks}), 200
    else:
        return jsonify({'status': 'unhealthy', 'checks': checks}), 503
```

#### 모든 서비스에 추가 필요
- `/api/health` (backend_5010)
- `/auth/health` (auth_portal_4430)
- `/ws/health` (websocket_5011)
- `/health` (kooCAEWebServer_5000)

---

### 3. **세션 저장소 중앙화**

#### 현재 문제
```
Flask Session → 로컬 파일 또는 메모리
→ 다른 서버로 요청 가면 로그인 풀림
```

#### 해결 방법
```python
# Flask Session을 Redis로 변경

from flask_session import Session
from redis import Redis

app.config['SESSION_TYPE'] = 'redis'
app.config['SESSION_REDIS'] = Redis(
    host=os.getenv('REDIS_HOST'),
    port=6379,
    password=os.getenv('REDIS_PASSWORD')
)
Session(app)
```

---

### 4. **로그 중앙화**

#### 현재 문제
```
각 서버의 로그 파일 → 분산되어 디버깅 어려움
```

#### 해결 방법 (선택 사항)
```
옵션 1: ELK Stack
- Elasticsearch: 로그 저장
- Logstash: 로그 수집
- Kibana: 시각화

옵션 2: Loki + Grafana
- 경량화
- Prometheus 연동 쉬움

옵션 3: 파일 동기화
- rsyslog로 중앙 서버로 전송
```

---

## 🔧 배포 자동화 준비사항

### 1. **컨테이너화 (선택 사항)**

#### Docker Compose
```yaml
# docker-compose.yml

version: '3.8'

services:
  backend_5010:
    image: hpc-backend:latest
    environment:
      - REDIS_HOST=${REDIS_HOST}
      - DB_HOST=${DB_HOST}
    ports:
      - "5010:5010"
    volumes:
      - /data:/data
    deploy:
      replicas: 3

  websocket_5011:
    image: hpc-websocket:latest
    ports:
      - "5011:5011"
    deploy:
      replicas: 3
```

#### Kubernetes (고급)
```yaml
# deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-5010
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: hpc-backend:latest
        ports:
        - containerPort: 5010
        env:
        - name: REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: redis_host
```

---

### 2. **설정 관리**

#### Ansible Playbook
```yaml
# deploy.yml

- hosts: web_tier
  roles:
    - nginx
    - static_files
  vars:
    backend_servers:
      - 110.15.177.123:5010
      - 110.15.177.124:5010
      - 110.15.177.125:5010

- hosts: app_tier
  roles:
    - python_backend
    - websocket
  vars:
    redis_host: 110.15.177.126
    db_host: 110.15.177.126
```

---

## 📊 모니터링 준비사항

### 1. **Prometheus 클러스터**

#### 필요 구성
```
Prometheus Federation:
- 각 서버에 Node Exporter
- 중앙 Prometheus가 수집
- Grafana로 시각화

또는

Thanos (권장):
- 여러 Prometheus 통합
- 장기 저장
- 고가용성
```

---

### 2. **알림 설정**

#### Alertmanager
```yaml
# alertmanager.yml

route:
  group_by: ['alertname']
  receiver: 'slack'

receivers:
  - name: 'slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/...'
        channel: '#alerts'

# 알림 규칙
groups:
  - name: HA
    rules:
      - alert: ServerDown
        expr: up == 0
        for: 1m

      - alert: RedisDown
        expr: redis_up == 0
        for: 1m

      - alert: DatabaseDown
        expr: mysql_up == 0
        for: 1m
```

---

## ✅ 사중화 준비 체크리스트

### 인프라
- [ ] 서버 4~7대 준비 (VM 또는 물리 서버)
- [ ] IP 주소 할당 (VIP 포함)
- [ ] 네트워크 대역 분리 (외부/내부/관리)
- [ ] 방화벽 규칙 설정
- [ ] DNS 또는 /etc/hosts 설정

### 스토리지
- [ ] 공유 스토리지 구성 (NFS/GlusterFS/Ceph)
- [ ] 각 서버 로컬 디스크 파티셔닝
- [ ] 백업 스토리지 준비

### 데이터베이스
- [ ] Redis Sentinel 또는 Cluster 구성
- [ ] MariaDB Galera Cluster 구성 (3-node)
- [ ] SQLite → 중앙 DB 마이그레이션 계획
- [ ] 데이터베이스 백업 자동화

### 로드 밸런서
- [ ] HAProxy 2대 설치 및 설정
- [ ] Keepalived VIP 설정
- [ ] Health Check 엔드포인트 구현
- [ ] SSL/TLS 인증서 준비

### 애플리케이션
- [ ] 환경 변수 외부화 (.env 파일)
- [ ] 하드코딩된 localhost 제거
- [ ] 세션 저장소 Redis로 변경
- [ ] Health Check API 추가

### Slurm
- [ ] slurmctld HA 구성 (Active-Standby)
- [ ] slurmdbd HA 구성
- [ ] Slurm DB를 Galera Cluster로 연결
- [ ] 노드 정보 공유 설정

### 배포
- [ ] CI/CD 파이프라인 구축 (옵션)
- [ ] Ansible 또는 배포 스크립트 준비
- [ ] Blue-Green 배포 전략 수립
- [ ] 롤백 계획 수립

### 모니터링
- [ ] Prometheus Federation 또는 Thanos 구성
- [ ] Grafana 대시보드 구성
- [ ] Alertmanager 알림 설정
- [ ] 로그 중앙화 (ELK/Loki)

### 테스트
- [ ] 부하 테스트 (Apache Bench, JMeter)
- [ ] Failover 테스트 (서버 다운 시나리오)
- [ ] 데이터 정합성 테스트
- [ ] 복구 시간 측정 (RTO/RPO)

---

## 📅 단계별 마이그레이션 계획

### Phase 1: 준비 (1-2주)
1. 하드웨어/VM 프로비저닝
2. 네트워크 설정
3. OS 설치 및 기본 설정
4. 공유 스토리지 구성

### Phase 2: 데이터베이스 HA (1주)
1. Redis Sentinel 구성
2. MariaDB Galera Cluster 구성
3. 데이터 마이그레이션 (SQLite → MariaDB)
4. 복제 테스트

### Phase 3: 애플리케이션 배포 (1-2주)
1. 환경 변수 설정
2. 각 서버에 애플리케이션 배포
3. Health Check 구현
4. 세션 저장소 변경

### Phase 4: 로드 밸런서 (1주)
1. HAProxy 설치 및 설정
2. Keepalived VIP 설정
3. SSL/TLS 인증서 적용
4. 트래픽 라우팅 테스트

### Phase 5: 모니터링 및 테스트 (1주)
1. Prometheus/Grafana 구성
2. Alertmanager 설정
3. 부하 테스트
4. Failover 테스트

### Phase 6: 전환 (Cutover)
1. DNS 변경 (기존 IP → VIP)
2. 트래픽 모니터링
3. 문제 발생 시 롤백 준비
4. 구 시스템 백업 후 종료

**총 소요 기간: 약 6-8주**

---

## 🚨 주의사항

### 1. Stateful 서비스
```
WebSocket (5011):
- Sticky Session 필요
- 연결이 끊기면 재연결 로직 필요

VNC Session:
- 특정 노드에서만 실행
- 세션 정보 중앙 DB에 저장
```

### 2. Slurm HA 제약
```
slurmctld:
- Active-Standby만 지원 (Active-Active 불가)
- 공유 스토리지 필요 (StateSaveLocation)
- Failover 시간: 1-2분

slurmdbd:
- 단일 인스턴스 권장
- DB만 HA 구성
```

### 3. 비용
```
최소 구성 (4대):
- 서버: $1,000 x 4 = $4,000 (초기)
- 네트워크: 스위치, 케이블
- 스토리지: NAS 또는 SAN (옵션)
- 유지보수: 전기, 냉각, 관리

클라우드 (AWS/Azure):
- 월 $500-1,000 (트래픽에 따라)
```

---

## 📚 참고 자료

### 공식 문서
- [Nginx Load Balancing](https://nginx.org/en/docs/http/load_balancing.html)
- [HAProxy Configuration](https://www.haproxy.org/documentation.html)
- [Redis Sentinel](https://redis.io/docs/manual/sentinel/)
- [MariaDB Galera Cluster](https://mariadb.com/kb/en/galera-cluster/)
- [Slurm High Availability](https://slurm.schedmd.com/high_availability.html)

### 추천 도구
- Ansible (배포 자동화)
- Terraform (인프라 프로비저닝)
- Prometheus + Grafana (모니터링)
- Consul (서비스 디스커버리)

---

**작성자**: Claude AI Assistant
**최종 수정**: 2025-10-26
**문의**: HPC 시스템 관리자
