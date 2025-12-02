# 멀티헤드 HPC 클러스터 완전 자동화

## 🎯 개요

이 프로젝트는 **N중화 고가용성(HA) HPC 클러스터**를 완전 자동으로 구축하는 솔루션입니다.

**핵심 특징**:
- ✅ **완전 자동화**: 단 한 번의 명령으로 전체 클러스터 구성
- ✅ **고가용성 (HA)**: 모든 컨트롤러가 모든 서비스 실행 (N중화)
- ✅ **단일 장애점 없음**: GlusterFS, MariaDB Galera, Redis, Slurm 멀티 마스터
- ✅ **자동 Failover**: Keepalived VIP 기반
- ✅ **웹 관리 인터페이스**: Dashboard, 모니터링, Admin Portal (8개 서비스)
- ✅ **프로덕션 준비**: Nginx, SSL/TLS, systemd 완전 통합

---

## 📋 목차

1. [빠른 시작](#빠른-시작)
2. [아키텍처](#아키텍처)
3. [요구사항](#요구사항)
4. [설치 방법](#설치-방법)
5. [설정 파일](#설정-파일)
6. [명령어 가이드](#명령어-가이드)
7. [테스트](#테스트)
8. [트러블슈팅](#트러블슈팅)
9. [문서](#문서)

---

## 🚀 빠른 시작

### 1. 설정 파일 편집

```bash
# my_multihead_cluster.yaml 편집
vim my_multihead_cluster.yaml
```

주요 설정:
- 컨트롤러 IP 및 호스트명
- VIP 주소
- 서비스별 활성화 여부
- **비밀번호 (environment 섹션)**

```yaml
# environment 섹션 예시
environment:
  DB_SLURM_PASSWORD: "your_secure_password"
  DB_AUTH_PASSWORD: "your_secure_password"
  REDIS_PASSWORD: "your_redis_password"
  JWT_SECRET_KEY: "your_jwt_secret_key"
  GRAFANA_PASSWORD: "your_grafana_password"
```

### 2. 파일 권한 설정 (보안)

```bash
# 민감 정보가 포함되므로 권한 제한
chmod 600 my_multihead_cluster.yaml
```

### 3. 설치 실행

**환경변수 설정 불필요!** YAML에서 자동으로 로드됩니다.

**Controller 1 (Bootstrap)**:
```bash
sudo ./setup_cluster_full_multihead.sh
```

**5분 대기**

**Controller 2**:
```bash
sudo ./setup_cluster_full_multihead.sh
```

**5분 대기**

**Controller 3**:
```bash
sudo ./setup_cluster_full_multihead.sh
```

### 4. 확인

```bash
# 클러스터 상태
./cluster/status_multihead.sh --all

# 자동화 테스트
./cluster/test_cluster.sh --all

# 웹 서비스 헬스체크
./cluster/utils/web_health_check.sh
```

---

## 🏗️ 아키텍처

### N-Way 중복성 (All Active)

```
┌─────────────────────────────────────────────────────────┐
│                   Virtual IP (VIP)                      │
│                    192.168.1.100                        │
│                  (Keepalived VRRP)                      │
└──────────────┬──────────────┬──────────────┬───────────┘
               │              │              │
    ┌──────────▼─────┐ ┌─────▼──────────┐ ┌─▼────────────┐
    │ Controller 1   │ │ Controller 2   │ │ Controller 3 │
    │ (Priority 100) │ │ (Priority 90)  │ │ (Priority 80)│
    │                │ │                │ │              │
    │ ✓ GlusterFS    │ │ ✓ GlusterFS    │ │ ✓ GlusterFS  │
    │ ✓ MariaDB      │ │ ✓ MariaDB      │ │ ✓ MariaDB    │
    │ ✓ Redis        │ │ ✓ Redis        │ │ ✓ Redis      │
    │ ✓ Slurm        │ │ ✓ Slurm        │ │ ✓ Slurm      │
    │ ✓ Web (8개)    │ │ ✓ Web (8개)    │ │ ✓ Web (8개)  │
    │ ✓ Keepalived   │ │ ✓ Keepalived   │ │ ✓ Keepalived │
    └────────────────┘ └────────────────┘ └──────────────┘
```

### 서비스 스택

**인프라 서비스**:
1. **GlusterFS**: 분산 파일 시스템 (3-way 복제)
2. **MariaDB Galera**: 멀티 마스터 데이터베이스
3. **Redis**: 클러스터 또는 센티넬
4. **Slurm**: 멀티 slurmctld (VIP 기반 Primary)
5. **Keepalived**: VRRP VIP 자동 Failover
6. **Nginx**: 리버스 프록시 + SSL/TLS

**웹 서비스** (8개):
- **Frontend** (3개):
  - Dashboard (5173)
  - Monitoring (5174)
  - Admin Portal (5175)
- **Backend** (4개):
  - Auth Service (5000)
  - Job API (5001)
  - File Service (5002)
  - Metrics API (5003)
- **Realtime** (1개):
  - WebSocket (5010)

---

## 📦 요구사항

### 하드웨어

**최소 구성**:
- 컨트롤러: 3대 (4 CPU, 8GB RAM, 100GB 디스크)
- 계산 노드: 1대 이상

**권장 구성**:
- 컨트롤러: 3대 (8 CPU, 16GB RAM, 500GB SSD)
- 계산 노드: 여러 대

### 소프트웨어

- Ubuntu 20.04 / 22.04 (또는 호환 Linux)
- Python 3.8+
- Bash 4.0+
- root 권한

### 네트워크

- 모든 컨트롤러 간 네트워크 연결
- SSH 접근 가능
- VIP를 위한 여유 IP 주소 1개
- 방화벽 포트 오픈 (필요 시)

---

## 🔧 설치 방법

### 방법 1: 완전 자동 설치 (권장)

**특징**: 기본 시스템 설정 + 멀티헤드 서비스를 한번에 설치

```bash
# 1. YAML 파일 편집 (environment 섹션에서 비밀번호 설정)
vim my_multihead_cluster.yaml

# 2. 파일 권한 설정
chmod 600 my_multihead_cluster.yaml

# 3. 실행 (각 컨트롤러에서 순차적으로)
sudo ./setup_cluster_full_multihead.sh
```

### 방법 2: 단계별 설치

**Step 1**: 기본 시스템만 먼저 설치
```bash
sudo ./setup_cluster_full_multihead.sh --skip-multihead
```

**Step 2**: 멀티헤드 서비스만 설치
```bash
sudo ./setup_cluster_full_multihead.sh --skip-base
```

### 방법 3: 멀티헤드 서비스만 수동 설치

기본 시스템이 이미 설정된 경우:
```bash
sudo ./cluster/start_multihead.sh --config my_multihead_cluster.yaml
```

**참고**: 모든 명령에서 `-E` 옵션 불필요! 환경변수는 YAML에서 자동 로드됩니다.

---

## ⚙️ 설정 파일

### my_multihead_cluster.yaml 구조

```yaml
cluster:
  name: my-cluster

nodes:
  controllers:                    # 복수 (N개)
    - hostname: server1
      ip_address: 192.168.1.101
      services:                   # 서비스별 활성화 여부
        glusterfs: true
        mariadb: true
        redis: true
        slurm: true
        web: true
        keepalived: true
      vip_owner: true             # VIP 소유 여부
      priority: 100               # VIP 우선순위 (높을수록 우선)

    - hostname: server2
      ip_address: 192.168.1.102
      services:
        glusterfs: true
        mariadb: true
        redis: true
        slurm: true
        web: true
        keepalived: true
      vip_owner: false
      priority: 90

  compute_nodes:
    - hostname: node001
      ip_address: 192.168.1.201
      cpus: 16
      memory: 64000

network:
  vip: 192.168.1.100              # Virtual IP

database:
  user: admin
  password: ${DB_ROOT_PASSWORD}   # 환경변수 치환

redis:
  password: ${REDIS_PASSWORD}

web:
  domain: cluster.local
  session_secret: ${SESSION_SECRET}
  jwt_secret: ${JWT_SECRET}

storage:
  gluster:
    volume_name: data_volume
    replica_count: 3
    brick_path: /data/gluster/data_volume/brick
```

**환경변수 자동 로드**:
- `environment` 섹션의 값들이 자동으로 환경변수로 설정됩니다
- 스크립트 실행 전 별도로 환경변수를 설정할 필요 없습니다!
- YAML의 `${VAR_NAME}` 형식도 자동으로 치환됩니다

---

## 📝 명령어 가이드

### 클러스터 관리

```bash
# 전체 클러스터 시작
sudo ./cluster/start_multihead.sh

# 전체 클러스터 중지
sudo ./cluster/stop_multihead.sh

# 클러스터 상태 확인 (전체)
./cluster/status_multihead.sh --all

# 특정 서비스 상태만 확인
./cluster/status_multihead.sh --service glusterfs
./cluster/status_multihead.sh --service mariadb
./cluster/status_multihead.sh --service redis
./cluster/status_multihead.sh --service slurm
./cluster/status_multihead.sh --service keepalived
./cluster/status_multihead.sh --service web
```

### Phase별 실행

```bash
# 특정 Phase만 실행
sudo ./cluster/start_multihead.sh --phase 1  # GlusterFS
sudo ./cluster/start_multihead.sh --phase 2  # MariaDB
sudo ./cluster/start_multihead.sh --phase 3  # Redis
sudo ./cluster/start_multihead.sh --phase 4  # Slurm
sudo ./cluster/start_multihead.sh --phase 5  # Keepalived
sudo ./cluster/start_multihead.sh --phase 6  # 웹 서비스

# Phase 범위 실행
sudo ./cluster/start_multihead.sh --start-phase 1 --end-phase 3
```

### 웹 서비스

```bash
# 헬스체크
./cluster/utils/web_health_check.sh

# JSON 출력
./cluster/utils/web_health_check.sh --output json

# 특정 서비스만 체크
./cluster/utils/web_health_check.sh --service dashboard
```

### Slurm 명령어

```bash
# 클러스터 상태
sinfo

# 작업 큐
squeue

# 작업 제출
sbatch test.sh

# 노드 상태 변경
scontrol update NodeName=node001 State=RESUME
```

---

## 🧪 테스트

### 자동화 테스트 실행

```bash
# 전체 테스트 (7개 시나리오)
sudo ./cluster/test_cluster.sh --all

# 특정 테스트만 실행
sudo ./cluster/test_cluster.sh --test glusterfs
sudo ./cluster/test_cluster.sh --test mariadb
sudo ./cluster/test_cluster.sh --test redis
sudo ./cluster/test_cluster.sh --test slurm
sudo ./cluster/test_cluster.sh --test keepalived
sudo ./cluster/test_cluster.sh --test web
sudo ./cluster/test_cluster.sh --test backup
```

### 수동 테스트

**GlusterFS 복제 테스트**:
```bash
# Controller 1에서 파일 생성
echo "test" > /mnt/glusterfs/test.txt

# Controller 2에서 확인
cat /mnt/glusterfs/test.txt  # "test" 출력되어야 함
```

**MariaDB Galera 테스트**:
```bash
# Controller 1에서 DB 생성
mysql -u root -p$DB_ROOT_PASSWORD -e "CREATE DATABASE test_db;"

# Controller 2에서 확인
mysql -u root -p$DB_ROOT_PASSWORD -e "SHOW DATABASES;" | grep test_db
```

**VIP Failover 테스트**:
```bash
# 현재 VIP 소유자 확인
ip addr show | grep 192.168.1.100

# Controller 1 Keepalived 중지
sudo systemctl stop keepalived

# VIP가 Controller 2로 이동했는지 확인 (Controller 2에서)
ip addr show | grep 192.168.1.100
```

---

## 🔍 트러블슈팅

### 일반적인 문제

**Q: 환경변수 로드 실패**
```bash
# 원인: YAML 파일에 environment 섹션이 없거나 잘못됨
# 해결: my_multihead_cluster.yaml 확인

# environment 섹션이 있는지 확인
grep -A 10 "^environment:" my_multihead_cluster.yaml

# Python YAML 모듈 확인
python3 -c "import yaml; print('OK')"
# 없으면 설치: pip3 install pyyaml
```

**Q: GlusterFS 볼륨 생성 실패**
```bash
# 상태 확인
sudo gluster peer status
sudo gluster volume status

# 수동 볼륨 생성
sudo gluster volume create data_volume replica 3 \
  server1:/data/gluster/data_volume/brick \
  server2:/data/gluster/data_volume/brick \
  server3:/data/gluster/data_volume/brick force

sudo gluster volume start data_volume
```

**Q: MariaDB Galera 클러스터 형성 실패**
```bash
# 클러스터 크기 확인
mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';"

# Bootstrap 필요 시 (Controller 1에서만)
sudo systemctl stop mariadb
sudo galera_new_cluster

# 다른 노드들 재시작
sudo systemctl restart mariadb
```

**Q: VIP가 할당되지 않음**
```bash
# Keepalived 상태
sudo systemctl status keepalived

# 로그 확인
sudo journalctl -u keepalived -n 50

# 설정 확인
sudo vim /etc/keepalived/keepalived.conf

# 재시작
sudo systemctl restart keepalived
```

**Q: 웹 서비스 접근 불가**
```bash
# Nginx 상태
sudo systemctl status nginx

# 포트 확인
sudo netstat -tlnp | grep -E ':(80|443|5000|5001|5173)'

# 방화벽 확인 (Ubuntu)
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### 로그 확인

```bash
# 전체 로그
ls -lh /var/log/multihead_cluster/

# 특정 Phase 로그
cat /var/log/multihead_cluster/phase1_glusterfs.log
cat /var/log/multihead_cluster/phase2_mariadb.log

# systemd 서비스 로그
sudo journalctl -u glusterd -n 50
sudo journalctl -u mariadb -n 50
sudo journalctl -u redis-server -n 50
sudo journalctl -u slurmctld -n 50
sudo journalctl -u keepalived -n 50
sudo journalctl -u nginx -n 50
```

---

## 📚 문서

### 주요 문서

1. **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** (25K)
   - 완전한 배포 프로세스
   - 하드웨어/소프트웨어 요구사항
   - 8가지 테스트 시나리오
   - 트러블슈팅 가이드

2. **[SETUP_SCRIPTS_COMPARISON.md](SETUP_SCRIPTS_COMPARISON.md)**
   - setup_cluster_full.sh vs setup_cluster_full_multihead.sh
   - 선택 가이드
   - 마이그레이션 경로

3. **[QUICKSTART.md](QUICKSTART.md)**
   - 빠른 시작 가이드
   - 1페이지 요약

4. **[README_PHASE6.md](cluster/README_PHASE6.md)** (29K)
   - 웹 서비스 상세 가이드
   - 8개 서비스 설명
   - Nginx 설정

5. **[README_PHASE8.md](cluster/README_PHASE8.md)** (27K)
   - 통합 오케스트레이션
   - Phase별 실행 가이드

### Phase별 README

각 Phase의 상세 구현은 해당 스크립트의 헤더 주석 참조:
- `cluster/setup/phase0_prepare.sh`
- `cluster/setup/phase1_glusterfs.sh`
- `cluster/setup/phase2_mariadb.sh`
- `cluster/setup/phase3_redis.sh`
- `cluster/setup/phase4_slurm.sh`
- `cluster/setup/phase5_keepalived.sh`
- `cluster/setup/phase5_web.sh`

---

## 🎓 고급 주제

### 커스터마이징

**서비스 선택적 활성화**:
```yaml
# my_multihead_cluster.yaml
nodes:
  controllers:
    - hostname: server1
      services:
        glusterfs: true   # 활성화
        mariadb: false    # 비활성화
        redis: true
        slurm: true
        web: false
        keepalived: true
```

**GlusterFS 복제 수 변경**:
```yaml
storage:
  gluster:
    replica_count: 2    # 2-way 복제
```

**Redis 모드 선택**:
```yaml
redis:
  mode: cluster       # 또는 sentinel
  cluster:
    slots: 16384
  sentinel:
    quorum: 2
```

### 스케일링

**컨트롤러 추가** (4대 이상):
```yaml
nodes:
  controllers:
    - hostname: server4
      ip_address: 192.168.1.104
      priority: 70      # 낮은 우선순위
```

**계산 노드 추가**:
```yaml
nodes:
  compute_nodes:
    - hostname: node005
      ip_address: 192.168.1.205
      cpus: 32
      memory: 128000
```

### 백업 및 복구

**설정 백업**:
```bash
tar czf cluster_config_backup_$(date +%Y%m%d).tar.gz \
  my_multihead_cluster.yaml \
  /usr/local/slurm/etc/ \
  /etc/keepalived/ \
  /etc/nginx/
```

**데이터 백업**:
```bash
# GlusterFS 데이터
rsync -avz /mnt/glusterfs/ backup_server:/backup/glusterfs/

# MariaDB 데이터
mysqldump --all-databases -u root -p > all_databases_$(date +%Y%m%d).sql
```

---

## 🤝 기여

버그 리포트, 기능 제안, Pull Request를 환영합니다!

---

## 📄 라이선스

이 프로젝트는 내부 사용을 위한 것입니다.

---

## 📞 지원

문제가 발생하면 다음을 확인하세요:
1. [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) 트러블슈팅 섹션
2. `/var/log/multihead_cluster/` 로그 파일
3. `sudo journalctl -u <service_name>` systemd 로그

---

**작성일**: 2025-10-27
**버전**: 1.0
**상태**: 프로덕션 준비 완료
