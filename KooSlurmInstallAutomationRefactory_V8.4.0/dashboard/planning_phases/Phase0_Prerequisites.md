# Phase 0: 사전 준비 (Prerequisites)

**기간**: 1주 (5일)
**목표**: 개발 환경 구축 및 Slurm 클러스터 설정 업데이트
**선행 조건**: 없음
**담당자**: 시스템 관리자 + DevOps

---

## 📋 목차

1. [개요](#개요)
2. [Day 1: my_cluster.yaml 업데이트](#day-1-my_clusteryaml-업데이트)
3. [Day 2: Redis 및 Node.js 환경 구축](#day-2-redis-및-nodejs-환경-구축)
4. [Day 3: SAML-IdP 개발 환경 구축](#day-3-saml-idp-개발-환경-구축)
5. [Day 4: SSL/TLS 인증서 및 Nginx 준비](#day-4-ssltls-인증서-및-nginx-준비)
6. [Day 5: Apptainer 환경 검증 및 통합 테스트](#day-5-apptainer-환경-검증-및-통합-테스트)
7. [검증 체크리스트](#검증-체크리스트)
8. [트러블슈팅](#트러블슈팅)

---

## 개요

### 목적
Phase 0는 모든 개발 작업의 기반이 되는 인프라와 설정을 준비하는 단계입니다. 이 단계를 완료해야만 Phase 1 이후의 개발 작업을 시작할 수 있습니다.

### 주요 작업
1. ✅ Slurm 클러스터 설정 업데이트 (GPU, VNC 파티션)
2. ✅ Redis 세션 스토리지 구축
3. ✅ SAML-IdP 개발 환경 구축
4. ✅ SSL 인증서 발급 및 Nginx 설정
5. ✅ Apptainer 샌드박스 환경 검증

### 성공 기준
- [ ] `sinfo -p vnc` 명령어로 vnc 파티션 확인 가능
- [ ] Redis 정상 동작 (`redis-cli ping` → PONG)
- [ ] saml-idp 메타데이터 접근 가능
- [ ] HTTPS 접속 가능 (자체 서명 인증서)
- [ ] Apptainer GPU 접근 테스트 성공

---

## Day 1: my_cluster.yaml 업데이트

### 🎯 목표
Slurm 클러스터 설정에 VNC 시각화를 위한 GPU 활성화 및 전용 파티션 추가

### 📝 작업 순서

#### Step 1.1: 백업 생성
```bash
# 작업 디렉토리로 이동
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 타임스탬프가 포함된 백업 생성
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp my_cluster.yaml my_cluster.yaml.backup_${TIMESTAMP}

# 백업 확인
ls -lh my_cluster.yaml.backup_*

# 백업 내용 검증
diff my_cluster.yaml my_cluster.yaml.backup_${TIMESTAMP}
```

**예상 결과**: 차이 없음 (identical)

#### Step 1.2: GPU Computing 활성화
```bash
# 현재 GPU 설정 확인
grep -A5 "gpu_computing:" my_cluster.yaml

# 출력 예시:
# gpu_computing:
#   nvidia:
#     enabled: false  ← 이 부분을 true로 변경
#     driver_version: "470.82.01"
#     cuda_version: "11.4"
```

**수정 방법 (nano 사용)**:
```bash
nano my_cluster.yaml

# Line 197로 이동 (Ctrl+_ 누르고 197 입력)
# enabled: false → enabled: true 로 변경
# Ctrl+O (저장), Enter, Ctrl+X (종료)
```

**수정 방법 (sed 사용)**:
```bash
sed -i '197s/enabled: false/enabled: true/' my_cluster.yaml

# 변경 확인
grep -A5 "gpu_computing:" my_cluster.yaml
```

**검증**:
```bash
# enabled: true로 변경되었는지 확인
grep "enabled: true" my_cluster.yaml | grep -A2 "nvidia"
```

#### Step 1.3: VNC 파티션 추가
```bash
# 현재 파티션 설정 확인
grep -A20 "partitions:" my_cluster.yaml

# vnc 파티션 설정 준비
cat >> /tmp/vnc_partition.yaml << 'EOF'
  - name: "vnc"
    nodes: "compute01"
    default: false
    max_time: "24:00:00"
    max_nodes: 1
    state: "UP"
    exclusive: false
EOF
```

**my_cluster.yaml에 추가**:
```bash
# Line 105 (debug 파티션 다음) 위치 확인
sed -n '93,110p' my_cluster.yaml

# vnc 파티션 추가 (Line 106 이후에 삽입)
# 방법 1: nano로 수동 추가
nano +106 my_cluster.yaml
# 위에서 준비한 vnc_partition.yaml 내용 붙여넣기

# 방법 2: sed로 자동 추가
sed -i '/name: "debug"/,/state: "UP"/{/state: "UP"/a\  - name: "vnc"\n    nodes: "compute01"\n    default: false\n    max_time: "24:00:00"\n    max_nodes: 1\n    state: "UP"\n    exclusive: false
}' my_cluster.yaml
```

**검증**:
```bash
grep -A6 'name: "vnc"' my_cluster.yaml

# 예상 출력:
#   - name: "vnc"
#     nodes: "compute01"
#     default: false
#     max_time: "24:00:00"
#     max_nodes: 1
#     state: "UP"
#     exclusive: false
```

#### Step 1.4: Sandbox Path 추가
```bash
# 현재 slurm_config 섹션 확인
grep -A10 "slurm_config:" my_cluster.yaml

# sandbox_path 추가 (Line 82 아래)
nano +82 my_cluster.yaml
# state_save_location 다음 줄에 추가:
#   sandbox_path: "/scratch/apptainer_sandboxes"
```

**자동 추가 방법**:
```bash
# state_save_location 다음 줄에 sandbox_path 삽입
sed -i '/state_save_location:/a\  sandbox_path: "/scratch/apptainer_sandboxes"' my_cluster.yaml

# 검증
grep "sandbox_path" my_cluster.yaml
```

#### Step 1.5: 전체 변경사항 검증
```bash
# 3가지 변경사항 모두 확인
echo "=== GPU Computing ==="
grep -A3 "gpu_computing:" my_cluster.yaml | grep "enabled:"

echo "=== VNC Partition ==="
grep -A6 'name: "vnc"' my_cluster.yaml

echo "=== Sandbox Path ==="
grep "sandbox_path:" my_cluster.yaml

# 원본과 비교
diff my_cluster.yaml.backup_${TIMESTAMP} my_cluster.yaml
```

#### Step 1.6: Slurm 설정 재생성
```bash
# 프로젝트에 자동 생성 스크립트가 있는지 확인
ls -la scripts/generate_slurm_config.sh 2>/dev/null

# 스크립트가 있으면 실행
if [ -f scripts/generate_slurm_config.sh ]; then
    ./scripts/generate_slurm_config.sh
else
    echo "수동으로 slurm.conf 업데이트 필요"
fi

# 또는 수동으로 slurm.conf 수정
sudo nano /usr/local/slurm/etc/slurm.conf

# 다음 라인 추가 (PartitionName 섹션에):
# PartitionName=vnc Nodes=compute01 Default=NO MaxTime=24:00:00 State=UP
```

#### Step 1.7: Slurm 재시작
```bash
# slurmctld 설정 테스트
sudo slurmctld -t

# 문제 없으면 재시작
sudo systemctl restart slurmctld

# 상태 확인
sudo systemctl status slurmctld

# slurmd도 재시작 (compute 노드에서)
sudo systemctl restart slurmd
```

#### Step 1.8: 최종 검증
```bash
# VNC 파티션 확인
sinfo -p vnc

# 예상 출력:
# PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
# vnc          up 1-00:00:00      1   idle compute01

# GPU GRES 확인
sinfo -o "%N %G"

# 모든 파티션 확인
sinfo -a
```

### ✅ Day 1 완료 체크리스트
- [ ] my_cluster.yaml 백업 완료
- [ ] GPU computing enabled: true 설정
- [ ] VNC 파티션 추가 완료
- [ ] sandbox_path 설정 완료
- [ ] slurm.conf 업데이트 완료
- [ ] slurmctld 재시작 성공
- [ ] `sinfo -p vnc` 명령어로 vnc 파티션 확인

### 🔧 Day 1 트러블슈팅

**문제 1**: slurmctld 재시작 실패
```bash
# 로그 확인
sudo tail -f /var/log/slurm/slurmctld.log

# 설정 파일 문법 검사
sudo slurmctld -t

# 일반적인 오류: 파티션 이름 중복
# → slurm.conf에서 vnc 파티션 정의 확인
```

**문제 2**: vnc 파티션이 보이지 않음
```bash
# slurm.conf 확인
grep "PartitionName=vnc" /usr/local/slurm/etc/slurm.conf

# 없으면 추가 후 재시작
sudo systemctl restart slurmctld
```

---

## Day 2: Redis 및 Node.js 환경 구축

### 🎯 목표
JWT 세션 스토리지를 위한 Redis 설치 및 SAML-IdP를 위한 Node.js 환경 구축

### 📝 작업 순서

#### Step 2.1: Redis 7+ 설치
```bash
# Rocky Linux 8 / CentOS 8
# EPEL 저장소 활성화
sudo dnf install epel-release -y

# Remi 저장소 추가 (최신 Redis를 위해)
sudo dnf install https://rpms.remirepo.net/enterprise/remi-release-8.rpm -y

# Redis 7 설치
sudo dnf module reset redis -y
sudo dnf module enable redis:remi-7.0 -y
sudo dnf install redis -y

# 버전 확인
redis-server --version
# 예상 출력: Redis server v=7.0.x
```

#### Step 2.2: Redis 설정
```bash
# 설정 파일 백업
sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.backup

# 설정 파일 편집
sudo nano /etc/redis/redis.conf
```

**주요 설정 항목**:
```bash
# 1. 바인드 주소 (localhost만 허용)
bind 127.0.0.1 -::1

# 2. 보호 모드 활성화
protected-mode yes

# 3. 포트
port 6379

# 4. 메모리 제한 (512MB)
maxmemory 512mb

# 5. 메모리 정책 (LRU)
maxmemory-policy allkeys-lru

# 6. 로그 레벨
loglevel notice

# 7. 로그 파일
logfile /var/log/redis/redis.log

# 8. 데이터 디렉토리
dir /var/lib/redis

# 9. RDB 스냅샷 (6시간마다)
save 21600 1

# 10. 패스워드 설정 (선택사항)
# requirepass your_strong_password_here
```

**sed로 자동 설정**:
```bash
sudo sed -i 's/^bind .*/bind 127.0.0.1 -::1/' /etc/redis/redis.conf
sudo sed -i 's/^# maxmemory .*/maxmemory 512mb/' /etc/redis/redis.conf
sudo sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
```

#### Step 2.3: Redis 시작 및 활성화
```bash
# Redis 시작
sudo systemctl start redis

# 부팅 시 자동 시작
sudo systemctl enable redis

# 상태 확인
sudo systemctl status redis

# 예상 출력:
# ● redis.service - Redis persistent key-value database
#    Loaded: loaded (/usr/lib/systemd/system/redis.service; enabled; ...)
#    Active: active (running) since ...
```

#### Step 2.4: Redis 연결 테스트
```bash
# PING 테스트
redis-cli ping
# 예상 출력: PONG

# 기본 동작 테스트
redis-cli << EOF
SET test_key "Hello Redis"
GET test_key
DEL test_key
PING
EOF

# 예상 출력:
# OK
# "Hello Redis"
# (integer) 1
# PONG

# 메모리 정보 확인
redis-cli INFO memory | grep -E "used_memory_human|maxmemory_human"
```

#### Step 2.5: Node.js 18+ 설치
```bash
# NodeSource 저장소 추가
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -

# Node.js 설치
sudo dnf install nodejs -y

# 버전 확인
node --version
# 예상 출력: v18.x.x

npm --version
# 예상 출력: 9.x.x
```

#### Step 2.6: 전역 npm 패키지 디렉토리 설정
```bash
# npm 전역 패키지를 사용자 디렉토리에 설치하도록 설정
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# PATH 추가
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# 확인
npm config get prefix
# 예상 출력: /home/koopark/.npm-global
```

#### Step 2.7: 개발 도구 설치
```bash
# yarn 설치 (선택사항)
npm install -g yarn

# pnpm 설치 (선택사항, 빠른 패키지 관리)
npm install -g pnpm

# 버전 확인
yarn --version
pnpm --version
```

### ✅ Day 2 완료 체크리스트
- [ ] Redis 7+ 설치 완료
- [ ] Redis 설정 완료 (localhost 바인딩, 512MB 메모리)
- [ ] Redis 서비스 시작 및 활성화
- [ ] `redis-cli ping` 테스트 성공
- [ ] Node.js 18+ 설치 완료
- [ ] npm 전역 디렉토리 설정 완료

### 🔧 Day 2 트러블슈팅

**문제 1**: Redis 시작 실패
```bash
# SELinux 문제 확인
sudo ausearch -m avc -ts recent | grep redis

# SELinux 임시 비활성화 (테스트용)
sudo setenforce 0

# Redis 재시작
sudo systemctl restart redis

# 성공하면 SELinux 정책 수정
sudo semanage port -a -t redis_port_t -p tcp 6379
sudo setenforce 1
```

**문제 2**: Redis 메모리 부족
```bash
# 현재 메모리 사용량 확인
redis-cli INFO memory

# maxmemory 증가 (1GB로)
redis-cli CONFIG SET maxmemory 1gb

# 설정 파일에 영구 반영
sudo sed -i 's/maxmemory 512mb/maxmemory 1gb/' /etc/redis/redis.conf
```

---

## Day 3: SAML-IdP 개발 환경 구축

### 🎯 목표
개발/테스트용 SAML Identity Provider 설치 및 테스트 사용자 생성

### 📝 작업 순서

#### Step 3.1: saml-idp npm 패키지 설치
```bash
# 전역 설치
npm install -g saml-idp

# 설치 확인
which saml-idp
# 예상 출력: /home/koopark/.npm-global/bin/saml-idp

saml-idp --help
```

#### Step 3.2: SAML-IdP 설정 디렉토리 생성
```bash
# 프로젝트 내에 설정 디렉토리 생성
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
mkdir -p saml_idp_7000
cd saml_idp_7000

# 디렉토리 구조
mkdir -p config certs logs
```

#### Step 3.3: 테스트 사용자 데이터베이스 생성
```bash
cat > config/users.json << 'EOF'
{
  "user01@hpc.local": {
    "password": "password123",
    "email": "user01@hpc.local",
    "userName": "user01",
    "firstName": "테스트",
    "lastName": "사용자1",
    "displayName": "테스트 사용자1",
    "groups": ["HPC-Users", "GPU-Users"],
    "department": "연구개발팀"
  },
  "user02@hpc.local": {
    "password": "password123",
    "email": "user02@hpc.local",
    "userName": "user02",
    "firstName": "테스트",
    "lastName": "사용자2",
    "displayName": "테스트 사용자2",
    "groups": ["HPC-Users"],
    "department": "연구개발팀"
  },
  "gpu_user@hpc.local": {
    "password": "password123",
    "email": "gpu_user@hpc.local",
    "userName": "gpu_user",
    "firstName": "GPU",
    "lastName": "전용사용자",
    "displayName": "GPU 전용사용자",
    "groups": ["GPU-Users"],
    "department": "시각화팀"
  },
  "cae_user@hpc.local": {
    "password": "password123",
    "email": "cae_user@hpc.local",
    "userName": "cae_user",
    "firstName": "CAE",
    "lastName": "자동화사용자",
    "displayName": "CAE 자동화사용자",
    "groups": ["Automation-Users"],
    "department": "자동화팀"
  },
  "admin@hpc.local": {
    "password": "admin123",
    "email": "admin@hpc.local",
    "userName": "admin",
    "firstName": "시스템",
    "lastName": "관리자",
    "displayName": "시스템 관리자",
    "groups": ["HPC-Admins"],
    "department": "IT관리팀"
  }
}
EOF
```

#### Step 3.4: SAML-IdP 설정 파일 생성
```bash
cat > config/idp-config.json << 'EOF'
{
  "issuer": "http://localhost:7000/metadata",
  "serviceProviderId": "auth-portal",
  "audience": "auth-portal",
  "acsUrl": "http://localhost:4430/auth/saml/acs",
  "sloUrl": "http://localhost:4430/auth/saml/slo",
  "cert": "./certs/idp-cert.pem",
  "key": "./certs/idp-key.pem",
  "authnContextClassRef": "urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport",
  "attributes": {
    "email": "email",
    "userName": "userName",
    "firstName": "firstName",
    "lastName": "lastName",
    "displayName": "displayName",
    "groups": "groups",
    "department": "department"
  },
  "encryptAssertion": false,
  "lifetimeInSeconds": 3600
}
EOF
```

#### Step 3.5: IdP 인증서 생성
```bash
cd certs

# IdP 개인키 및 인증서 생성 (10년 유효)
openssl req -x509 -newkey rsa:2048 -keyout idp-key.pem -out idp-cert.pem \
  -days 3650 -nodes \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/OU=Development/CN=saml-idp-dev"

# 권한 설정
chmod 600 idp-key.pem
chmod 644 idp-cert.pem

# 확인
ls -la
openssl x509 -in idp-cert.pem -noout -text | grep -E "Subject:|Not"
```

#### Step 3.6: SAML-IdP 시작 스크립트 생성
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/saml_idp_7000

cat > start_idp.sh << 'EOF'
#!/bin/bash

# SAML-IdP 시작 스크립트

PORT=7000
HOST="0.0.0.0"
CONFIG_DIR="$(dirname "$0")/config"
CERT_DIR="$(dirname "$0")/certs"
LOG_DIR="$(dirname "$0")/logs"

# 로그 디렉토리 생성
mkdir -p "$LOG_DIR"

# 기존 프로세스 확인
if pgrep -f "saml-idp.*port $PORT" > /dev/null; then
    echo "SAML-IdP가 이미 실행 중입니다."
    exit 1
fi

# SAML-IdP 시작
echo "Starting SAML-IdP on port $PORT..."

saml-idp \
  --port $PORT \
  --host $HOST \
  --issuer "http://localhost:$PORT/metadata" \
  --acsUrl "http://localhost:4430/auth/saml/acs" \
  --audience "auth-portal" \
  --cert "$CERT_DIR/idp-cert.pem" \
  --key "$CERT_DIR/idp-key.pem" \
  --config "$CONFIG_DIR/users.json" \
  > "$LOG_DIR/idp.log" 2>&1 &

PID=$!
echo $PID > "$LOG_DIR/idp.pid"

# 시작 대기
sleep 2

# 상태 확인
if ps -p $PID > /dev/null; then
    echo "✓ SAML-IdP started successfully (PID: $PID)"
    echo "  Metadata URL: http://localhost:$PORT/metadata"
    echo "  SSO URL: http://localhost:$PORT/saml/sso"
    echo "  Log file: $LOG_DIR/idp.log"
else
    echo "✗ Failed to start SAML-IdP"
    cat "$LOG_DIR/idp.log"
    exit 1
fi
EOF

chmod +x start_idp.sh
```

#### Step 3.7: SAML-IdP 중지 스크립트 생성
```bash
cat > stop_idp.sh << 'EOF'
#!/bin/bash

LOG_DIR="$(dirname "$0")/logs"
PID_FILE="$LOG_DIR/idp.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        echo "Stopping SAML-IdP (PID: $PID)..."
        kill $PID
        rm "$PID_FILE"
        echo "✓ SAML-IdP stopped"
    else
        echo "SAML-IdP is not running (stale PID file)"
        rm "$PID_FILE"
    fi
else
    echo "SAML-IdP is not running (no PID file)"
fi
EOF

chmod +x stop_idp.sh
```

#### Step 3.8: SAML-IdP 시작 및 테스트
```bash
# IdP 시작
./start_idp.sh

# 메타데이터 다운로드 테스트
curl -s http://localhost:7000/metadata | head -20

# XML 형식 확인
curl -s http://localhost:7000/metadata | grep -E "<EntityDescriptor|<IDPSSODescriptor"

# 메타데이터 파일로 저장
curl -s http://localhost:7000/metadata > config/idp_metadata.xml

# 저장된 메타데이터 확인
cat config/idp_metadata.xml
```

#### Step 3.9: 테스트 사용자 검증
```bash
# 사용자 목록 확인
cat config/users.json | jq 'keys'

# 특정 사용자 정보 확인
cat config/users.json | jq '."admin@hpc.local"'

# 그룹별 사용자 카운트
cat config/users.json | jq '[.[].groups] | flatten | group_by(.) | map({group: .[0], count: length})'
```

### ✅ Day 3 완료 체크리스트
- [ ] saml-idp npm 패키지 설치
- [ ] 테스트 사용자 5명 생성 (각 그룹별)
- [ ] IdP 인증서 생성
- [ ] SAML-IdP 시작 스크립트 생성
- [ ] IdP 정상 시작 확인
- [ ] 메타데이터 URL 접근 가능 확인
- [ ] idp_metadata.xml 파일 저장

### 🔧 Day 3 트러블슈팅

**문제 1**: saml-idp 시작 실패
```bash
# 로그 확인
cat logs/idp.log

# 포트 충돌 확인
sudo netstat -tunlp | grep 7000

# 다른 포트 사용
PORT=7001 ./start_idp.sh
```

**문제 2**: 메타데이터 접근 불가
```bash
# 프로세스 확인
ps aux | grep saml-idp

# 방화벽 확인
sudo firewall-cmd --list-ports

# 7000 포트 허용 (임시)
sudo firewall-cmd --add-port=7000/tcp

# 영구 적용
sudo firewall-cmd --add-port=7000/tcp --permanent
sudo firewall-cmd --reload
```

---

## Day 4: SSL/TLS 인증서 및 Nginx 준비

### 🎯 목표
HTTPS 통신을 위한 SSL 인증서 발급 및 Nginx 리버스 프록시 설정

### 📝 작업 순서

#### Step 4.1: Nginx 설치
```bash
# Rocky Linux 8
sudo dnf install nginx -y

# 버전 확인
nginx -v
# 예상 출력: nginx version: nginx/1.20.x

# 서비스 활성화
sudo systemctl enable nginx
```

#### Step 4.2: 자체 서명 SSL 인증서 생성 (개발용)
```bash
# 인증서 디렉토리 생성
sudo mkdir -p /etc/ssl/private
sudo chmod 700 /etc/ssl/private

# 개인키 및 인증서 생성 (1년 유효)
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/CN=slurm-dashboard.local"

# 권한 설정
sudo chmod 600 /etc/ssl/private/nginx-selfsigned.key
sudo chmod 644 /etc/ssl/certs/nginx-selfsigned.crt
```

#### Step 4.3: DH 파라미터 생성 (보안 강화)
```bash
# Diffie-Hellman 파라미터 생성 (시간 소요: 1-5분)
sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

# 권한 설정
sudo chmod 644 /etc/ssl/certs/dhparam.pem
```

#### Step 4.4: Nginx SSL 설정 파일 생성
```bash
sudo mkdir -p /etc/nginx/snippets

# SSL 파라미터 스니펫
sudo tee /etc/nginx/snippets/ssl-params.conf > /dev/null << 'EOF'
# SSL Configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;

# DH Parameters
ssl_dhparam /etc/ssl/certs/dhparam.pem;

# Security Headers
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options DENY always;
add_header X-Content-Type-Options nosniff always;
add_header X-XSS-Protection "1; mode=block" always;
EOF

# 인증서 스니펫
sudo tee /etc/nginx/snippets/self-signed.conf > /dev/null << 'EOF'
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOF
```

#### Step 4.5: Nginx 메인 설정 파일 생성
```bash
# 기본 설정 백업
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# 메인 설정 파일 수정
sudo tee /etc/nginx/nginx.conf > /dev/null << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF
```

#### Step 4.6: Auth Portal용 Nginx 설정 생성
```bash
sudo tee /etc/nginx/conf.d/auth-portal.conf > /dev/null << 'EOF'
# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name _;

    return 301 https://$host$request_uri;
}

# HTTPS Server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    # SSL Certificates
    include snippets/self-signed.conf;
    include snippets/ssl-params.conf;

    # Logging
    access_log /var/log/nginx/auth-portal-access.log;
    error_log /var/log/nginx/auth-portal-error.log;

    # Root location (Auth Frontend will be here later)
    location / {
        # Placeholder - will proxy to auth_portal_4431 in Phase 1
        proxy_pass http://localhost:4431;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Auth Backend API
    location /auth/ {
        # Placeholder - will proxy to auth_portal_4430 in Phase 1
        proxy_pass http://localhost:4430/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # CORS headers (will be refined in Phase 1)
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
    }

    # Dashboard (existing service)
    location /dashboard/ {
        proxy_pass http://localhost:3010/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # CAE (existing service)
    location /cae/ {
        proxy_pass http://localhost:5173/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
```

#### Step 4.7: Nginx 설정 검증 및 시작
```bash
# 설정 파일 문법 검사
sudo nginx -t

# 예상 출력:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful

# Nginx 시작
sudo systemctl start nginx

# 상태 확인
sudo systemctl status nginx

# 부팅 시 자동 시작 (이미 설정됨)
sudo systemctl is-enabled nginx
```

#### Step 4.8: 방화벽 설정
```bash
# 현재 방화벽 상태 확인
sudo firewall-cmd --list-all

# HTTP/HTTPS 포트 허용
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# 또는 포트 번호로 직접 허용
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp

# 개발용 포트들 허용 (내부 전용)
sudo firewall-cmd --permanent --add-port=4430/tcp  # Auth Backend
sudo firewall-cmd --permanent --add-port=4431/tcp  # Auth Frontend
sudo firewall-cmd --permanent --add-port=7000/tcp  # SAML-IdP

# 방화벽 재로드
sudo firewall-cmd --reload

# 설정 확인
sudo firewall-cmd --list-ports
```

#### Step 4.9: HTTPS 접속 테스트
```bash
# HTTPS 테스트 (자체 서명 인증서이므로 -k 옵션 사용)
curl -k https://localhost

# 예상 출력: 502 Bad Gateway (아직 4431 서비스가 없으므로 정상)

# 인증서 정보 확인
echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -text | grep -E "Subject:|Issuer:|Not"

# HTTP → HTTPS 리다이렉트 테스트
curl -I http://localhost

# 예상 출력:
# HTTP/1.1 301 Moved Permanently
# Location: https://localhost/
```

### ✅ Day 4 완료 체크리스트
- [ ] Nginx 설치 완료
- [ ] 자체 서명 SSL 인증서 생성
- [ ] DH 파라미터 생성
- [ ] Nginx SSL 설정 완료
- [ ] Auth Portal용 설정 파일 생성
- [ ] 방화벽 포트 허용
- [ ] HTTPS 접속 테스트 성공
- [ ] HTTP → HTTPS 리다이렉트 확인

### 🔧 Day 4 트러블슈팅

**문제 1**: Nginx 시작 실패
```bash
# 로그 확인
sudo tail -f /var/log/nginx/error.log

# SELinux 컨텍스트 확인
sudo ls -Z /etc/ssl/private/nginx-selfsigned.key

# SELinux 컨텍스트 수정
sudo chcon -t cert_t /etc/ssl/private/nginx-selfsigned.key
sudo chcon -t cert_t /etc/ssl/certs/nginx-selfsigned.crt
```

**문제 2**: 502 Bad Gateway (정상)
```bash
# Phase 1에서 4430, 4431 서비스를 시작하기 전까지는 정상적인 에러
# 확인: upstream 서비스가 없음
curl -k https://localhost/auth/

# 임시로 Nginx 설정을 수정하여 테스트 페이지 표시
sudo mkdir -p /usr/share/nginx/html/test
echo "Nginx is working!" | sudo tee /usr/share/nginx/html/test/index.html

# auth-portal.conf에서 location / 수정
# proxy_pass http://localhost:4431;
# → root /usr/share/nginx/html/test;
```

---

## Day 5: Apptainer 환경 검증 및 통합 테스트

### 🎯 목표
Apptainer 샌드박스 디렉토리 준비 및 GPU 접근 테스트, 전체 Phase 0 통합 검증

### 📝 작업 순서

#### Step 5.1: Apptainer 설치 확인
```bash
# Apptainer 버전 확인
apptainer --version
# 예상 출력: apptainer version 1.2.5 이상

# 일반 사용자 실행 가능 여부 확인
apptainer exec library://alpine cat /etc/os-release

# Fakeroot 설정 확인
apptainer config fakeroot --list

# 현재 사용자에게 fakeroot 권한 추가 (필요시)
sudo apptainer config fakeroot --add $USER
```

#### Step 5.2: Sandbox 디렉토리 생성
```bash
# 디렉토리 생성
sudo mkdir -p /scratch/apptainer_sandboxes

# 소유자 설정 (slurm 사용자)
sudo chown slurm:slurm /scratch/apptainer_sandboxes

# 권한 설정 (755: rwxr-xr-x)
sudo chmod 755 /scratch/apptainer_sandboxes

# 확인
ls -ld /scratch/apptainer_sandboxes
# 예상 출력: drwxr-xr-x. 2 slurm slurm 6 Oct 16 10:00 /scratch/apptainer_sandboxes
```

#### Step 5.3: Slurm 사용자로 쓰기 테스트
```bash
# slurm 사용자로 전환하여 테스트
sudo -u slurm bash << 'EOF'
# 테스트 파일 생성
touch /scratch/apptainer_sandboxes/test_file
echo "Write test successful" > /scratch/apptainer_sandboxes/test_file

# 읽기 테스트
cat /scratch/apptainer_sandboxes/test_file

# 디렉토리 생성 테스트
mkdir -p /scratch/apptainer_sandboxes/test_dir

# 정리
rm -rf /scratch/apptainer_sandboxes/test_*

echo "✓ Slurm user write test passed"
EOF
```

#### Step 5.4: 디스크 공간 확인
```bash
# /scratch 파티션 용량 확인
df -h /scratch

# 최소 50GB 이상 여유 공간 권장
# 예상 출력:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sdb1       200G   10G  180G   6% /scratch

# inode 확인
df -i /scratch
```

#### Step 5.5: GPU 접근 테스트용 간단한 이미지 테스트
```bash
# NVIDIA 드라이버 확인
nvidia-smi

# Apptainer로 GPU 접근 테스트 (ubuntu 이미지 사용)
apptainer exec --nv docker://ubuntu:22.04 nvidia-smi

# 예상 출력: nvidia-smi 결과 표시
# GPU 0: NVIDIA ... (정보 표시)

# CUDA 테스트 (간단한 버전 확인)
apptainer exec --nv docker://nvidia/cuda:11.4.0-base-ubuntu20.04 nvcc --version
```

#### Step 5.6: 테스트 샌드박스 생성
```bash
# 간단한 테스트 이미지 다운로드 및 샌드박스 생성
cd /scratch/apptainer_sandboxes

# Ubuntu 이미지로 샌드박스 생성 (일반 사용자)
apptainer build --sandbox ubuntu_test docker://ubuntu:22.04

# 생성 확인
ls -la ubuntu_test/

# 샌드박스 내부 테스트
apptainer exec --writable ubuntu_test touch /tmp/test
apptainer exec ubuntu_test ls -la /tmp/test

# 정리
rm -rf ubuntu_test
```

#### Step 5.7: Phase 0 통합 검증

**통합 검증 스크립트 생성**:
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard

cat > validate_phase0.sh << 'EOF'
#!/bin/bash

echo "=== Phase 0 통합 검증 스크립트 ==="
echo

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 검증 카운터
TOTAL=0
PASSED=0
FAILED=0

# 검증 함수
check() {
    TOTAL=$((TOTAL + 1))
    if eval "$2"; then
        echo -e "${GREEN}✓${NC} $1"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $1"
        FAILED=$((FAILED + 1))
    fi
}

echo "1. Slurm 설정 검증"
check "GPU Computing 활성화" "grep 'enabled: true' ../my_cluster.yaml | grep -q nvidia"
check "VNC 파티션 존재" "grep -q 'name: \"vnc\"' ../my_cluster.yaml"
check "Sandbox Path 설정" "grep -q 'sandbox_path:' ../my_cluster.yaml"
check "VNC 파티션 Slurm 등록" "sinfo -p vnc &>/dev/null"
echo

echo "2. Redis 검증"
check "Redis 서비스 실행 중" "systemctl is-active redis &>/dev/null"
check "Redis PING 응답" "redis-cli ping 2>/dev/null | grep -q PONG"
check "Redis 메모리 설정" "redis-cli CONFIG GET maxmemory 2>/dev/null | grep -q -E '[0-9]+'"
echo

echo "3. SAML-IdP 검증"
check "saml-idp 설치" "which saml-idp &>/dev/null"
check "테스트 사용자 파일 존재" "[ -f saml_idp_7000/config/users.json ]"
check "IdP 인증서 존재" "[ -f saml_idp_7000/certs/idp-cert.pem ]"
check "IdP 메타데이터 접근 가능" "curl -sf http://localhost:7000/metadata &>/dev/null"
echo

echo "4. Nginx 및 SSL 검증"
check "Nginx 서비스 실행 중" "systemctl is-active nginx &>/dev/null"
check "SSL 인증서 존재" "[ -f /etc/ssl/certs/nginx-selfsigned.crt ]"
check "DH 파라미터 존재" "[ -f /etc/ssl/certs/dhparam.pem ]"
check "HTTPS 접속 가능" "curl -k -s -o /dev/null -w '%{http_code}' https://localhost | grep -E '200|502' &>/dev/null"
check "HTTP→HTTPS 리다이렉트" "curl -s -o /dev/null -w '%{http_code}' http://localhost | grep -q 301"
echo

echo "5. Apptainer 환경 검증"
check "Apptainer 설치" "which apptainer &>/dev/null"
check "Sandbox 디렉토리 존재" "[ -d /scratch/apptainer_sandboxes ]"
check "Sandbox 디렉토리 쓰기 가능" "sudo -u slurm touch /scratch/apptainer_sandboxes/test 2>/dev/null && sudo -u slurm rm /scratch/apptainer_sandboxes/test"
check "GPU 접근 가능" "apptainer exec --nv docker://ubuntu:22.04 nvidia-smi &>/dev/null"
echo

echo "6. Node.js 환경 검증"
check "Node.js 설치" "which node &>/dev/null"
check "Node.js 버전 18+" "node -v | grep -E 'v1[8-9]\.|v[2-9][0-9]\.' &>/dev/null"
check "npm 설치" "which npm &>/dev/null"
echo

echo "=== 검증 결과 ==="
echo -e "총 검사 항목: $TOTAL"
echo -e "${GREEN}통과: $PASSED${NC}"
echo -e "${RED}실패: $FAILED${NC}"
echo

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Phase 0 검증 완료! Phase 1을 시작할 수 있습니다.${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ $FAILED개 항목 실패. 위 내용을 확인하고 수정해주세요.${NC}"
    exit 1
fi
EOF

chmod +x validate_phase0.sh
```

#### Step 5.8: 통합 검증 실행
```bash
# SAML-IdP가 실행 중인지 확인 (없으면 시작)
cd saml_idp_7000
./start_idp.sh
cd ..

# 검증 스크립트 실행
./validate_phase0.sh

# 예상 출력:
# === Phase 0 통합 검증 스크립트 ===
#
# 1. Slurm 설정 검증
# ✓ GPU Computing 활성화
# ✓ VNC 파티션 존재
# ✓ Sandbox Path 설정
# ✓ VNC 파티션 Slurm 등록
# ...
# === 검증 결과 ===
# 총 검사 항목: 19
# 통과: 19
# 실패: 0
# ✓ Phase 0 검증 완료! Phase 1을 시작할 수 있습니다.
```

#### Step 5.9: 문서화 및 정리
```bash
# Phase 0 완료 보고서 생성
cat > Phase0_Completion_Report.md << 'EOF'
# Phase 0 완료 보고서

**완료일**: $(date +%Y-%m-%d)
**소요 시간**: 5일

## 완료된 작업

### Day 1: my_cluster.yaml 업데이트
- [x] GPU computing 활성화
- [x] VNC 파티션 추가
- [x] Sandbox path 설정
- [x] Slurm 설정 재생성 및 재시작

### Day 2: Redis 및 Node.js 환경
- [x] Redis 7+ 설치
- [x] Redis 설정 (localhost, 512MB)
- [x] Node.js 18+ 설치
- [x] npm 전역 디렉토리 설정

### Day 3: SAML-IdP 개발 환경
- [x] saml-idp 패키지 설치
- [x] 테스트 사용자 5명 생성
- [x] IdP 인증서 생성
- [x] SAML-IdP 시작 및 메타데이터 확인

### Day 4: SSL/TLS 및 Nginx
- [x] Nginx 설치
- [x] 자체 서명 SSL 인증서 생성
- [x] Nginx SSL 설정
- [x] Auth Portal 설정 파일 생성
- [x] 방화벽 설정

### Day 5: Apptainer 환경 및 통합 검증
- [x] Sandbox 디렉토리 생성
- [x] 권한 설정 및 쓰기 테스트
- [x] GPU 접근 테스트
- [x] 통합 검증 스크립트 실행

## 검증 결과
- 총 19개 검사 항목 모두 통과
- Phase 1 시작 준비 완료

## 다음 단계
- Phase 1: Auth Portal 개발 (2-3주 예정)
  - Auth Backend (auth_portal_4430) 개발
  - Auth Frontend (auth_portal_4431) 개발
  - SAML SSO 통합

## 참고 정보
- Slurm VNC 파티션: `sinfo -p vnc`
- Redis 상태: `systemctl status redis`
- SAML-IdP: http://localhost:7000/metadata
- Nginx HTTPS: https://localhost
EOF

# 날짜 자동 입력
sed -i "s/\$(date +%Y-%m-%d)/$(date +%Y-%m-%d)/" Phase0_Completion_Report.md

cat Phase0_Completion_Report.md
```

### ✅ Day 5 완료 체크리스트
- [ ] Apptainer 설치 확인
- [ ] Sandbox 디렉토리 생성 및 권한 설정
- [ ] Slurm 사용자 쓰기 테스트 통과
- [ ] GPU 접근 테스트 성공
- [ ] 통합 검증 스크립트 작성
- [ ] 19개 검증 항목 모두 통과
- [ ] Phase 0 완료 보고서 작성

### 🔧 Day 5 트러블슈팅

**문제 1**: GPU 접근 실패
```bash
# NVIDIA 드라이버 확인
nvidia-smi

# Apptainer NVIDIA 지원 확인
apptainer exec --nv docker://ubuntu:22.04 ls /usr/local/cuda

# 없으면 Apptainer 재설치 (--with-nvidia 옵션)
# 또는 NVIDIA Container Runtime 설치 확인
```

**문제 2**: 통합 검증 스크립트 실패
```bash
# 실패한 항목 개별 확인
# 예: Redis PING 실패
redis-cli ping

# SAML-IdP 메타데이터 접근 실패
curl http://localhost:7000/metadata

# 각 서비스 개별적으로 디버깅
```

---

## 검증 체크리스트

### 전체 Phase 0 검증

#### Slurm 설정 (4개)
- [ ] `grep 'enabled: true' my_cluster.yaml | grep nvidia` 성공
- [ ] `grep 'name: "vnc"' my_cluster.yaml` 존재
- [ ] `grep 'sandbox_path:' my_cluster.yaml` 존재
- [ ] `sinfo -p vnc` 파티션 표시

#### Redis (3개)
- [ ] `systemctl is-active redis` → active
- [ ] `redis-cli ping` → PONG
- [ ] `redis-cli CONFIG GET maxmemory` → 512MB 설정

#### SAML-IdP (4개)
- [ ] `which saml-idp` → 경로 표시
- [ ] `saml_idp_7000/config/users.json` 파일 존재
- [ ] `saml_idp_7000/certs/idp-cert.pem` 파일 존재
- [ ] `curl http://localhost:7000/metadata` → XML 응답

#### Nginx & SSL (5개)
- [ ] `systemctl is-active nginx` → active
- [ ] `/etc/ssl/certs/nginx-selfsigned.crt` 파일 존재
- [ ] `/etc/ssl/certs/dhparam.pem` 파일 존재
- [ ] `curl -k https://localhost` → 응답 (200 or 502)
- [ ] `curl -I http://localhost` → 301 리다이렉트

#### Apptainer (3개)
- [ ] `which apptainer` → 경로 표시
- [ ] `/scratch/apptainer_sandboxes` 디렉토리 존재
- [ ] `sudo -u slurm touch /scratch/apptainer_sandboxes/test` 성공
- [ ] `apptainer exec --nv docker://ubuntu:22.04 nvidia-smi` 성공

---

## 트러블슈팅

### 일반적인 문제

#### 문제: Slurm 파티션이 DOWN 상태
```bash
# 파티션 상태 확인
sinfo -p vnc

# DOWN이면 노드 상태 확인
scontrol show node compute01

# 노드 재활성화
scontrol update NodeName=compute01 State=RESUME

# 파티션 재활성화
scontrol update PartitionName=vnc State=UP
```

#### 문제: Redis 연결 거부
```bash
# Redis 로그 확인
sudo tail -f /var/log/redis/redis.log

# 포트 바인딩 확인
sudo netstat -tunlp | grep 6379

# SELinux 문제
sudo ausearch -m avc -ts recent | grep redis
sudo setsebool -P redis_enable_homedirs 1
```

#### 문제: SAML-IdP 메타데이터 접근 불가
```bash
# 프로세스 확인
ps aux | grep saml-idp

# 로그 확인
cat saml_idp_7000/logs/idp.log

# 재시작
cd saml_idp_7000
./stop_idp.sh
./start_idp.sh
```

#### 문제: Nginx 502 Bad Gateway
```bash
# upstream 서비스 확인 (Phase 0에서는 정상)
curl http://localhost:4430
curl http://localhost:4431

# Phase 1 전까지는 502 에러가 정상
# 임시 테스트 페이지 표시
echo "Nginx OK" | sudo tee /usr/share/nginx/html/index.html
```

---

## Phase 0 완료 후 Next Steps

### Phase 1 준비 사항
1. ✅ my_cluster.yaml 업데이트 완료
2. ✅ Redis 세션 스토리지 준비 완료
3. ✅ SAML-IdP 개발 환경 구축 완료
4. ✅ Nginx HTTPS 프록시 준비 완료
5. ✅ Apptainer 샌드박스 환경 준비 완료

### Phase 1 시작 전 확인
```bash
# 모든 서비스 상태 확인
systemctl status redis nginx slurmctld slurmd

# SAML-IdP 실행 확인
curl http://localhost:7000/metadata | head

# 통합 검증 재실행
./validate_phase0.sh
```

### Phase 1 개요
- **기간**: 2-3주
- **목표**: Auth Portal (SAML SSO + JWT) 개발
- **주요 작업**:
  - auth_portal_4430 (Backend) 개발
  - auth_portal_4431 (Frontend) 개발
  - SAML 인증 통합
  - JWT 토큰 발급 시스템

---

**Phase 0 완료!** 🎉
