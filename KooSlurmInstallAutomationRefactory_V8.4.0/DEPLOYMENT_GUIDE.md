# Multi-Head HPC Cluster 배포 및 테스트 가이드

본 문서는 실제 노드에 클러스터를 배포하고 테스트하는 전체 프로세스를 단계별로 안내합니다.

## 목차

1. [사전 요구사항](#사전-요구사항)
2. [테스트 환경 준비](#테스트-환경-준비)
3. [배포 프로세스](#배포-프로세스)
4. [단계별 테스트](#단계별-테스트)
5. [트러블슈팅](#트러블슈팅)
6. [롤백 절차](#롤백-절차)

---

## 사전 요구사항

### 1. 하드웨어 요구사항

**최소 구성 (테스트용):**
- 컨트롤러 노드: 2대
  - CPU: 4 cores
  - RAM: 8GB
  - Disk: 50GB
  - Network: 1Gbps

**권장 구성 (프로덕션):**
- 컨트롤러 노드: 3대 이상
  - CPU: 8+ cores
  - RAM: 32GB+
  - Disk: 100GB+ (SSD 권장)
  - Network: 10Gbps

### 2. 네트워크 요구사항

- **모든 노드가 같은 네트워크에 있어야 함**
- **고정 IP 주소 할당 필수**
- **방화벽 포트 개방:**
  ```
  22    - SSH
  80    - HTTP (웹 서비스)
  443   - HTTPS (웹 서비스)
  3306  - MariaDB
  4567  - Galera Cluster
  4444  - Galera SST
  4568  - Galera IST
  6379  - Redis
  24007 - GlusterFS Daemon
  49152-49156 - GlusterFS Brick
  6817-6819   - Slurm
  5000-5175   - Web Services
  ```

- **VIP (Virtual IP) 1개 필요**
  - 예: 192.168.1.100

### 3. OS 요구사항

**지원 OS:**
- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Debian 11/12

**필수 패키지 (자동 설치됨):**
- Python 3.8+
- Bash 4.0+
- SSH (passwordless 설정 필요)

### 4. 계정 요구사항

- **모든 노드에 root 접근 권한 필요**
- **SSH key 기반 인증 설정 필요**
- **동일한 사용자명 권장** (예: admin, ubuntu 등)

---

## 테스트 환경 준비

### Phase 1: 노드 준비

#### 1.1 노드 정보 정리

테스트할 노드 정보를 표로 정리:

| 역할 | Hostname | IP 주소 | VIP Owner | 비고 |
|------|----------|---------|-----------|------|
| Controller 1 | server1 | 192.168.1.101 | Yes | 우선순위 100 |
| Controller 2 | server2 | 192.168.1.102 | No | 우선순위 90 |
| Controller 3 | server3 | 192.168.1.103 | No | 우선순위 80 |
| VIP | - | 192.168.1.100 | - | Keepalived |

#### 1.2 각 노드에서 기본 설정

**모든 노드에서 실행:**

```bash
# 1. 시스템 업데이트
sudo apt-get update
sudo apt-get upgrade -y

# 2. 필수 패키지 설치
sudo apt-get install -y \
    python3 python3-pip \
    git curl wget \
    net-tools iputils-ping \
    vim htop

# 3. 호스트명 설정 (각 노드마다 다르게)
sudo hostnamectl set-hostname server1  # server1에서
sudo hostnamectl set-hostname server2  # server2에서
sudo hostnamectl set-hostname server3  # server3에서

# 4. /etc/hosts 파일 수정 (모든 노드 동일)
sudo tee -a /etc/hosts << EOF
192.168.1.101 server1
192.168.1.102 server2
192.168.1.103 server3
192.168.1.100 vip-cluster
EOF

# 5. 방화벽 설정 (테스트 시 비활성화 가능)
sudo ufw disable  # 또는 필요한 포트만 개방

# 6. SELinux 비활성화 (RedHat 계열만)
# sudo setenforce 0
```

#### 1.3 SSH Key 설정 (Passwordless SSH)

**Controller 1 (주 노드)에서 실행:**

```bash
# 1. SSH key 생성 (이미 있으면 건너뛰기)
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

# 2. 모든 노드에 SSH key 복사
ssh-copy-id root@192.168.1.101  # 본인 포함
ssh-copy-id root@192.168.1.102
ssh-copy-id root@192.168.1.103

# 3. SSH 연결 테스트
ssh root@192.168.1.101 "hostname"
ssh root@192.168.1.102 "hostname"
ssh root@192.168.1.103 "hostname"

# 모두 hostname이 출력되면 성공
```

**Controller 2, 3에서도 동일하게 실행** (상호 접속 가능하게)

#### 1.4 시간 동기화

**모든 노드에서 실행:**

```bash
# NTP 설치 및 활성화
sudo apt-get install -y chrony
sudo systemctl enable --now chrony

# 시간 동기화 확인
chronyc tracking
```

---

### Phase 2: 프로젝트 파일 배포

#### 2.1 프로젝트 복사

**방법 1: Git 사용 (권장)**

```bash
# 모든 노드에서 실행
cd /home/koopark
git clone <repository_url> KooSlurmInstallAutomationRefactory

# 또는 현재 개발 폴더에서 git init 후 push
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
git init
git add .
git commit -m "Initial commit"
git remote add origin <repository_url>
git push -u origin main
```

**방법 2: SCP 사용**

```bash
# Controller 1에서 다른 노드로 복사
cd /home/koopark/claude
tar czf cluster.tar.gz KooSlurmInstallAutomationRefactory/

# Controller 2, 3으로 복사
scp cluster.tar.gz root@192.168.1.102:/home/koopark/
scp cluster.tar.gz root@192.168.1.103:/home/koopark/

# 각 노드에서 압축 해제
ssh root@192.168.1.102 "cd /home/koopark && tar xzf cluster.tar.gz"
ssh root@192.168.1.103 "cd /home/koopark && tar xzf cluster.tar.gz"
```

**방법 3: rsync 사용 (가장 빠름)**

```bash
# Controller 1에서 실행
rsync -avz --progress \
    /home/koopark/claude/KooSlurmInstallAutomationRefactory/ \
    root@192.168.1.102:/home/koopark/KooSlurmInstallAutomationRefactory/

rsync -avz --progress \
    /home/koopark/claude/KooSlurmInstallAutomationRefactory/ \
    root@192.168.1.103:/home/koopark/KooSlurmInstallAutomationRefactory/
```

#### 2.2 파일 확인

**모든 노드에서 확인:**

```bash
cd /home/koopark/KooSlurmInstallAutomationRefactory

# 디렉토리 구조 확인
tree -L 2 cluster/

# 또는
ls -la cluster/

# 필수 파일 확인
ls -lh cluster/start_multihead.sh
ls -lh cluster/stop_multihead.sh
ls -lh cluster/status_multihead.sh
ls -lh cluster/setup/phase*.sh
ls -lh cluster/config/parser.py

# 실행 권한 확인 및 부여
chmod +x cluster/*.sh
chmod +x cluster/setup/*.sh
chmod +x cluster/utils/*.sh
chmod +x cluster/backup/*.sh
chmod +x cluster/discovery/*.sh
```

---

### Phase 3: 설정 파일 작성

#### 3.1 my_multihead_cluster.yaml 생성

**Controller 1에서 작성:**

```bash
cd /home/koopark/KooSlurmInstallAutomationRefactory

# 샘플 설정 파일 생성
cat > my_multihead_cluster.yaml << 'EOF'
# Multi-Head HPC Cluster Configuration
cluster:
  name: test-hpc-cluster
  domain: cluster.example.com  # 실제 도메인으로 변경

# Network configuration
network:
  vip: 192.168.1.100
  netmask: 255.255.255.0
  interface: eth0  # 또는 ens160 등 실제 인터페이스명

# Database configuration
database:
  user: clusteradmin
  password: ${DB_ROOT_PASSWORD}  # 환경변수로 설정
  vip: 192.168.1.100

# Redis configuration
redis:
  password: ${REDIS_PASSWORD}  # 환경변수로 설정

# Web services configuration
web:
  domain: cluster.example.com  # 실제 도메인으로 변경
  session_secret: ${SESSION_SECRET}
  jwt_secret: ${JWT_SECRET}

# Controllers configuration
controllers:
  - hostname: server1
    ip: 192.168.1.101
    services:
      glusterfs: true
      mariadb: true
      redis: true
      slurm: true
      web: true
      keepalived: true
    vip_owner: true
    priority: 100

  - hostname: server2
    ip: 192.168.1.102
    services:
      glusterfs: true
      mariadb: true
      redis: true
      slurm: true
      web: true
      keepalived: true
    vip_owner: false
    priority: 90

  - hostname: server3
    ip: 192.168.1.103
    services:
      glusterfs: true
      mariadb: true
      redis: true
      slurm: true
      web: true
      keepalived: true
    vip_owner: false
    priority: 80

# Compute nodes (optional for testing)
compute_nodes: []
#  - hostname: compute1
#    ip: 192.168.1.201
#    cpus: 16
#    memory: 64GB
#    gpus: 0

# Storage configuration
storage:
  gluster:
    volume_name: gluster_volume
    replica_count: 3
    brick_path: /data/gluster/brick

# Slurm configuration
slurm:
  cluster_name: test-cluster
  accounting_storage_type: accounting_storage/mysql
  accounting_storage_host: 192.168.1.100

# Backup configuration
backup:
  retention_days: 30
  backup_dir: /var/backups/cluster
EOF

# 설정 파일 검증
python3 cluster/config/parser.py my_multihead_cluster.yaml validate
```

#### 3.2 환경변수 설정

**모든 노드에서 설정:**

```bash
# 환경변수 파일 생성
cat > ~/.cluster_env << 'EOF'
export DB_ROOT_PASSWORD='ChangeMe123!@#'
export REDIS_PASSWORD='Redis123!@#'
export SESSION_SECRET='SessionSecret123!@#RandomString'
export JWT_SECRET='JWTSecret123!@#RandomString'
EOF

# 권한 설정 (중요!)
chmod 600 ~/.cluster_env

# bashrc에 추가
echo "source ~/.cluster_env" >> ~/.bashrc

# 현재 셸에 적용
source ~/.cluster_env

# 환경변수 확인
env | grep -E "(DB_ROOT_PASSWORD|REDIS_PASSWORD|SESSION_SECRET|JWT_SECRET)"
```

**보안 강화 버전 (프로덕션):**

```bash
# 랜덤 패스워드 생성
cat > ~/.cluster_env << EOF
export DB_ROOT_PASSWORD='$(openssl rand -base64 32)'
export REDIS_PASSWORD='$(openssl rand -base64 32)'
export SESSION_SECRET='$(openssl rand -base64 64)'
export JWT_SECRET='$(openssl rand -base64 64)'
EOF

chmod 600 ~/.cluster_env
source ~/.cluster_env
```

#### 3.3 설정 파일 배포

**Controller 1에서 다른 노드로 복사:**

```bash
# YAML 설정 파일 복사
scp my_multihead_cluster.yaml root@192.168.1.102:/home/koopark/KooSlurmInstallAutomationRefactory/
scp my_multihead_cluster.yaml root@192.168.1.103:/home/koopark/KooSlurmInstallAutomationRefactory/

# 환경변수 파일 복사
scp ~/.cluster_env root@192.168.1.102:~/
scp ~/.cluster_env root@192.168.1.103:~/

# 각 노드에서 적용
ssh root@192.168.1.102 "chmod 600 ~/.cluster_env && echo 'source ~/.cluster_env' >> ~/.bashrc"
ssh root@192.168.1.103 "chmod 600 ~/.cluster_env && echo 'source ~/.cluster_env' >> ~/.bashrc"
```

---

## 배포 프로세스

### 배포 순서

**중요:** 반드시 순서대로 진행!

1. **Controller 1 (VIP Owner) 먼저 설치**
2. **Controller 2 설치**
3. **Controller 3 설치**

이유: 첫 노드가 클러스터를 bootstrap하고, 나머지는 join 모드로 동작

### 실제 배포 단계

#### Step 1: Controller 1 설치 (Primary)

**Terminal 1 - Controller 1 SSH 접속:**

```bash
ssh root@192.168.1.101

# 프로젝트 디렉토리 이동
cd /home/koopark/KooSlurmInstallAutomationRefactory

# 환경변수 로드
source ~/.cluster_env

# 설정 검증
python3 cluster/config/parser.py my_multihead_cluster.yaml validate

# DRY-RUN으로 먼저 테스트 (중요!)
sudo -E ./cluster/start_multihead.sh \
    --config my_multihead_cluster.yaml \
    --dry-run

# 문제없으면 실제 실행
sudo -E ./cluster/start_multihead.sh \
    --config my_multihead_cluster.yaml \
    --auto-confirm
```

**Terminal 2 - 로그 모니터링:**

```bash
ssh root@192.168.1.101
tail -f /var/log/cluster_multihead_setup.log
```

**예상 소요 시간:**
- Phase 0: 1분
- Phase 1 (GlusterFS): 5-10분
- Phase 2 (MariaDB): 10-15분
- Phase 3 (Redis): 5분
- Phase 4 (Slurm): 10-15분
- Phase 5 (Keepalived): 3분
- Phase 6 (Web): 15-20분
- Phase 7 (Backup): 1분
- **총 소요 시간: 약 50-70분**

#### Step 2: Controller 1 검증

```bash
# 서비스 상태 확인
./cluster/status_multihead.sh

# 클러스터 정보 확인
./cluster/utils/cluster_info.sh --config my_multihead_cluster.yaml

# 개별 서비스 확인
systemctl status glusterd
systemctl status mariadb
systemctl status redis-server
systemctl status slurmctld
systemctl status keepalived
systemctl status nginx

# VIP 확인
ip addr show | grep 192.168.1.100

# 웹 서비스 헬스체크
./cluster/utils/web_health_check.sh
```

**성공 조건:**
- ✅ 모든 systemd 서비스가 active (running) 상태
- ✅ VIP가 Controller 1에 할당되어 있음
- ✅ 웹 서비스 모두 healthy 상태
- ✅ GlusterFS 볼륨 생성 및 마운트됨
- ✅ MariaDB Galera 클러스터 크기 1
- ✅ Redis 정상 작동

#### Step 3: Controller 2 설치

**Controller 1 완료 후 5분 대기**

```bash
ssh root@192.168.1.102

cd /home/koopark/KooSlurmInstallAutomationRefactory
source ~/.cluster_env

# DRY-RUN
sudo -E ./cluster/start_multihead.sh \
    --config my_multihead_cluster.yaml \
    --dry-run

# 실제 실행
sudo -E ./cluster/start_multihead.sh \
    --config my_multihead_cluster.yaml \
    --auto-confirm
```

**예상 동작:**
- GlusterFS: 기존 클러스터에 peer 추가 및 join
- MariaDB: SST를 통해 데이터 동기화 후 join
- Redis: 기존 클러스터에 join
- Slurm: 기존 설정 동기화
- Keepalived: BACKUP 모드로 시작

**예상 소요 시간:** 약 40-60분

#### Step 4: Controller 2 검증

```bash
# 서비스 상태 확인
./cluster/status_multihead.sh

# 클러스터 정보 (모든 노드 확인)
./cluster/utils/cluster_info.sh --config my_multihead_cluster.yaml --all-nodes

# VIP 확인 (Controller 2에는 없어야 함)
ip addr show | grep 192.168.1.100  # 출력 없어야 정상

# Galera 클러스터 크기 확인
mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size'"  # 결과: 2

# GlusterFS peer 확인
gluster peer status  # Peer in Cluster: 1

# Redis 클러스터 확인
redis-cli cluster info  # cluster_size:2 (또는 sentinel info)
```

#### Step 5: Controller 3 설치

**Controller 2 완료 후 5분 대기**

```bash
ssh root@192.168.1.103

cd /home/koopark/KooSlurmInstallAutomationRefactory
source ~/.cluster_env

# 실행
sudo -E ./cluster/start_multihead.sh \
    --config my_multihead_cluster.yaml \
    --auto-confirm
```

**예상 소요 시간:** 약 40-60분

#### Step 6: 전체 클러스터 검증

**Controller 1에서 실행:**

```bash
# 전체 클러스터 상태
./cluster/utils/cluster_info.sh --all-nodes --format table

# 웹 서비스 헬스체크 (모든 노드)
./cluster/utils/web_health_check.sh --all-nodes --format table

# Galera 클러스터 크기 확인
mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size'"  # 결과: 3

# GlusterFS peer 확인
gluster peer status  # Peer in Cluster: 2

# Redis 클러스터 확인
redis-cli cluster info  # cluster_size:3

# Slurm 노드 확인
sinfo
scontrol show nodes

# Keepalived 상태
ssh 192.168.1.101 "ip addr | grep 192.168.1.100"  # VIP 있어야 함
ssh 192.168.1.102 "ip addr | grep 192.168.1.100"  # VIP 없어야 함
ssh 192.168.1.103 "ip addr | grep 192.168.1.100"  # VIP 없어야 함
```

---

## 단계별 테스트

### Test 1: GlusterFS 테스트

```bash
# Controller 1에서
cd /mnt/gluster

# 파일 생성
echo "Test from server1" > test1.txt

# Controller 2에서 확인
ssh root@192.168.1.102 "cat /mnt/gluster/test1.txt"
# 출력: Test from server1

# Controller 3에서도 확인
ssh root@192.168.1.103 "cat /mnt/gluster/test1.txt"
# 출력: Test from server1

# 볼륨 상태 확인
gluster volume info gluster_volume
gluster volume status gluster_volume

# 성공 조건:
# ✅ 모든 노드에서 파일이 동일하게 보임
# ✅ 볼륨 상태가 Started
# ✅ 모든 brick이 online
```

### Test 2: MariaDB Galera 테스트

```bash
# Controller 1에서 데이터베이스 생성
mysql << EOF
CREATE DATABASE test_db;
USE test_db;
CREATE TABLE test_table (
    id INT PRIMARY KEY AUTO_INCREMENT,
    data VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test_table (data) VALUES ('Test from server1');
EOF

# Controller 2에서 확인
ssh root@192.168.1.102 \
    "mysql -e 'SELECT * FROM test_db.test_table'"
# 데이터가 보여야 함

# Controller 3에서도 확인
ssh root@192.168.1.103 \
    "mysql -e 'SELECT * FROM test_db.test_table'"

# Galera 상태 확인
mysql -e "SHOW STATUS LIKE 'wsrep%'" | grep -E "(cluster_size|cluster_status|local_state_comment|ready)"

# 성공 조건:
# ✅ wsrep_cluster_size = 3
# ✅ wsrep_cluster_status = Primary
# ✅ wsrep_local_state_comment = Synced
# ✅ wsrep_ready = ON
# ✅ 모든 노드에서 데이터 동일
```

### Test 3: Redis 테스트

```bash
# Redis 모드 확인
redis-cli cluster info 2>/dev/null || redis-cli -p 26379 sentinel masters 2>/dev/null || echo "Standalone"

# Cluster 모드인 경우
redis-cli set test_key "Test from server1"
redis-cli get test_key

# 다른 노드에서 확인
ssh root@192.168.1.102 "redis-cli get test_key"

# Cluster 정보
redis-cli cluster nodes

# 성공 조건:
# ✅ 클러스터 상태 ok
# ✅ 모든 노드에서 데이터 접근 가능
# ✅ 슬롯이 모두 할당됨 (16384/16384)
```

### Test 4: Slurm 테스트

```bash
# Slurm 정보 확인
sinfo
scontrol show nodes

# 간단한 작업 제출
sbatch << EOF
#!/bin/bash
#SBATCH --job-name=test_job
#SBATCH --output=test_job_%j.out
#SBATCH --ntasks=1
#SBATCH --time=00:01:00

hostname
date
echo "Test job completed"
EOF

# 작업 상태 확인
squeue
sacct

# 작업 완료 후 결과 확인
cat test_job_*.out

# slurmctld 상태 확인 (모든 컨트롤러에서)
ssh root@192.168.1.101 "systemctl status slurmctld"
ssh root@192.168.1.102 "systemctl status slurmctld"
ssh root@192.168.1.103 "systemctl status slurmctld"

# 성공 조건:
# ✅ 모든 컨트롤러에서 slurmctld 실행 중
# ✅ 작업이 정상적으로 완료됨
# ✅ 작업 출력 파일 생성됨
```

### Test 5: Keepalived VIP Failover 테스트

```bash
# 현재 VIP 위치 확인
for i in 101 102 103; do
    echo "=== 192.168.1.$i ==="
    ssh root@192.168.1.$i "ip addr | grep 192.168.1.100"
done

# VIP가 192.168.1.101에 있어야 함

# VIP로 접속 테스트
ping -c 3 192.168.1.100
curl -k https://192.168.1.100/health

# Failover 테스트: Controller 1의 keepalived 중지
ssh root@192.168.1.101 "systemctl stop keepalived"

# 5초 대기
sleep 5

# VIP 재확인 (Controller 2로 이동했어야 함)
for i in 101 102 103; do
    echo "=== 192.168.1.$i ==="
    ssh root@192.168.1.$i "ip addr | grep 192.168.1.100 || echo 'No VIP'"
done

# VIP로 접속 여전히 가능한지 확인
ping -c 3 192.168.1.100
curl -k https://192.168.1.100/health

# Controller 1 복구
ssh root@192.168.1.101 "systemctl start keepalived"

# 성공 조건:
# ✅ VIP가 자동으로 Controller 2로 이동
# ✅ 서비스 중단 없이 VIP 접속 가능
# ✅ Controller 1 복구 후 VIP가 다시 돌아옴 (우선순위에 따라)
```

### Test 6: 웹 서비스 테스트

```bash
# 웹 헬스체크
./cluster/utils/web_health_check.sh --all-nodes

# 개별 서비스 테스트
curl -k https://192.168.1.100/  # Dashboard
curl -k https://192.168.1.100/health  # Nginx health
curl -k https://192.168.1.100/api/auth/health  # Auth service
curl -k https://192.168.1.100/api/jobs/health  # Job API

# 브라우저에서 테스트
# https://192.168.1.100 접속

# SSL 인증서 확인
openssl s_client -connect 192.168.1.100:443 -servername cluster.example.com

# 성공 조건:
# ✅ 모든 서비스가 200 OK 응답
# ✅ 브라우저에서 접속 가능
# ✅ SSL 인증서 유효 (자체 서명 또는 Let's Encrypt)
```

### Test 7: 백업 및 복구 테스트

```bash
# 백업 생성
sudo ./cluster/backup/backup.sh --config my_multihead_cluster.yaml

# 백업 확인
ls -lh /var/backups/cluster/

# 백업 목록 조회
sudo ./cluster/backup/restore.sh --config my_multihead_cluster.yaml --list

# 테스트 데이터 생성
mysql -e "INSERT INTO test_db.test_table (data) VALUES ('Before restore')"

# 복구 테스트 (DRY-RUN)
sudo ./cluster/backup/restore.sh \
    --config my_multihead_cluster.yaml \
    --latest \
    --dry-run

# 실제 복구 (주의!)
# sudo ./cluster/backup/restore.sh \
#     --config my_multihead_cluster.yaml \
#     --latest

# 성공 조건:
# ✅ 백업 파일 생성됨
# ✅ 백업 메타데이터 확인 가능
# ✅ 복구 프로세스 정상 작동 (dry-run)
```

### Test 8: 노드 추가/제거 테스트

```bash
# 노드 정보 추가 (YAML 파일 수정)
vim my_multihead_cluster.yaml
# controllers에 server4 추가

# 새 노드에서 설치
# ssh root@192.168.1.104
# ./cluster/start_multihead.sh --config my_multihead_cluster.yaml

# 노드 추가 확인
./cluster/utils/cluster_info.sh --all-nodes

# 노드 제거 테스트
# ./cluster/utils/node_remove.sh --service glusterfs --node server4

# 성공 조건:
# ✅ 새 노드가 모든 클러스터에 자동 join
# ✅ 데이터 동기화 완료
# ✅ 노드 제거 시 안전하게 제거됨
```

---

## 트러블슈팅

### 문제 1: Phase 실행 중 실패

**증상:**
```
[ERROR] Phase 2 failed with exit code 1
```

**해결:**
```bash
# 로그 확인
tail -100 /var/log/cluster_multihead_setup.log

# 특정 Phase 로그 확인
journalctl -xe | grep -A 20 "mariadb"

# 해당 Phase만 재실행
sudo -E ./cluster/start_multihead.sh --phase 2

# 강제 재설치
sudo -E ./cluster/start_multihead.sh --phase 2 --force
```

### 문제 2: SSH 연결 실패

**증상:**
```
Permission denied (publickey)
```

**해결:**
```bash
# SSH key 재설정
ssh-copy-id root@192.168.1.102

# SSH 에이전트 사용
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa

# 패스워드 인증 임시 활성화
sudo vi /etc/ssh/sshd_config
# PasswordAuthentication yes
sudo systemctl restart sshd
```

### 문제 3: Galera 클러스터 형성 실패

**증상:**
```
wsrep_cluster_size = 0
```

**해결:**
```bash
# 모든 노드에서 MariaDB 중지
systemctl stop mariadb

# Controller 1에서 bootstrap
galera_new_cluster

# 또는
mysqld_bootstrap

# 상태 확인
mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size'"

# Controller 2, 3에서 시작
systemctl start mariadb
```

### 문제 4: VIP 할당 안됨

**증상:**
```
VIP가 어느 노드에도 없음
```

**해결:**
```bash
# Keepalived 로그 확인
journalctl -u keepalived -n 50

# 설정 확인
cat /etc/keepalived/keepalived.conf

# 수동 VIP 할당 테스트
sudo ip addr add 192.168.1.100/24 dev eth0

# Keepalived 재시작
sudo systemctl restart keepalived
```

### 문제 5: GlusterFS 볼륨 마운트 실패

**증상:**
```
mount: /mnt/gluster: cannot mount
```

**해결:**
```bash
# Gluster 상태 확인
gluster peer status
gluster volume status

# 볼륨 재시작
gluster volume stop gluster_volume
gluster volume start gluster_volume

# 수동 마운트
mount -t glusterfs server1:/gluster_volume /mnt/gluster

# /etc/fstab 확인
cat /etc/fstab | grep gluster
```

---

## 롤백 절차

### 완전 롤백 (모든 노드 초기화)

**모든 노드에서 순서대로 실행:**

```bash
# 1. 클러스터 중지
sudo ./cluster/stop_multihead.sh --force

# 2. 서비스 비활성화
sudo systemctl disable glusterd mariadb redis-server slurmctld keepalived nginx

# 3. 패키지 제거
sudo apt-get purge -y \
    glusterfs-server glusterfs-client \
    mariadb-server mariadb-client \
    redis-server \
    slurm-wlm \
    keepalived \
    nginx

# 4. 데이터 디렉토리 삭제
sudo rm -rf /var/lib/glusterd
sudo rm -rf /var/lib/mysql
sudo rm -rf /var/lib/redis
sudo rm -rf /var/spool/slurm
sudo rm -rf /etc/keepalived
sudo rm -rf /mnt/gluster
sudo rm -rf /opt/web_services

# 5. 로그 정리
sudo rm -rf /var/log/cluster_*.log

# 6. 재부팅
sudo reboot
```

### 부분 롤백 (특정 Phase만)

```bash
# 웹 서비스만 제거
sudo ./cluster/stop_multihead.sh --service web
sudo systemctl disable nginx dashboard auth_service
sudo rm -rf /opt/web_services

# MariaDB만 제거
sudo ./cluster/stop_multihead.sh --service mariadb
sudo apt-get purge -y mariadb-server
sudo rm -rf /var/lib/mysql
```

---

## 체크리스트

### 배포 전 체크리스트

- [ ] 모든 노드에 고정 IP 할당됨
- [ ] SSH passwordless 설정 완료
- [ ] /etc/hosts 파일 모든 노드 동일
- [ ] 방화벽 포트 개방 또는 비활성화
- [ ] 시간 동기화 설정됨
- [ ] 프로젝트 파일 모든 노드에 복사됨
- [ ] my_multihead_cluster.yaml 작성 및 검증됨
- [ ] 환경변수 파일 생성 및 로드됨
- [ ] 네트워크 인터페이스명 확인됨 (eth0, ens160 등)
- [ ] 도메인명 준비됨 (웹 서비스용)

### 배포 중 체크리스트

- [ ] Controller 1 설치 완료 및 검증
- [ ] Controller 1 VIP 할당 확인
- [ ] Controller 2 설치 완료 및 join 확인
- [ ] Controller 3 설치 완료 및 join 확인
- [ ] Galera 클러스터 크기 = 노드 수
- [ ] GlusterFS peer 수 = 노드 수 - 1
- [ ] Redis 클러스터 정상
- [ ] Slurm 모든 노드에서 실행 중

### 배포 후 체크리스트

- [ ] 모든 테스트 통과
- [ ] VIP failover 테스트 성공
- [ ] 웹 인터페이스 접속 가능
- [ ] Slurm 작업 제출 가능
- [ ] 백업 시스템 동작 확인
- [ ] 모니터링 설정 완료
- [ ] 문서화 완료
- [ ] 운영팀 교육 완료

---

## 다음 단계

배포 및 테스트 완료 후:

1. **Phase 9: Testing and Validation** 진행
   - 부하 테스트
   - 장애 복구 시나리오 테스트
   - 성능 벤치마크

2. **모니터링 설정**
   - Prometheus + Grafana
   - 알림 설정

3. **프로덕션 준비**
   - 보안 강화
   - 자동 백업 설정
   - 운영 문서 작성

4. **사용자 교육**
   - 웹 인터페이스 사용법
   - Slurm 작업 제출
   - 트러블슈팅

---

## 참고사항

- **예상 총 배포 시간:** 3-4시간 (3개 노드 기준)
- **디스크 사용량:** 노드당 약 20-30GB
- **네트워크 대역폭:** 설치 중 노드당 5-10GB 다운로드
- **권장 작업 시간:** 업무 시간 외 (서비스 중단 최소화)

---

이 가이드를 따라 진행하면 완전한 Multi-Head HPC 클러스터를 구축할 수 있습니다!
