# Hybrid HA 아키텍처: Slurm 이중화 + 웹서비스 N중화 자동 스케일링

## 📋 전략 개요

### ✅ 왜 이 구성이 합리적인가?

```
┌─────────────────────────────────────────────────────────────┐
│  HPC 클러스터에서 일반적으로 사용되는 HA 전략                 │
│                                                               │
│  • Slurm: Active-Standby (이중화)                            │
│    → 상태 저장(Stateful), 단일 제어점 필요                    │
│                                                               │
│  • 웹서비스: Active-Active N중화 (자동 스케일링)              │
│    → 상태 비저장(Stateless), 수평 확장 가능                   │
└─────────────────────────────────────────────────────────────┘
```

**핵심 이유**:
1. **Slurm은 분산 스케줄러가 아님** → 단일 컨트롤러가 클러스터 전체를 관리
2. **웹서비스는 이미 Stateless** → Redis/DB만 공유하면 무한 확장 가능
3. **부하 패턴이 다름** → Slurm은 안정적, 웹서비스는 사용자 수에 따라 변동

---

## 🏗️ 아키텍처 설계

### 1️⃣ Slurm 이중화 (Active-Standby)

```
                  VIP (192.168.1.100)
                         │
         ┌───────────────┴───────────────┐
         │                               │
    ┌────▼────┐                    ┌─────────┐
    │ Slurm   │ ACTIVE             │ Slurm   │ STANDBY
    │ Master1 │◄──────heartbeat────►│ Master2 │
    │ Node    │                    │ Node    │
    └────┬────┘                    └─────────┘
         │
         ├─── slurmctld (스케줄러)
         ├─── slurmdbd (DB 데몬)
         └─── 공유 스토리지 (/etc/slurm, /var/spool/slurmd)
```

**구성 요소**:
- **VIP (Virtual IP)**: Keepalived로 관리
- **Heartbeat**: Pacemaker/Corosync 또는 Keepalived
- **공유 스토리지**: NFS 또는 DRBD (설정 파일, 작업 큐 동기화)
- **자동 전환**: Master1 실패 시 Master2가 VIP 인수 및 slurmctld 시작

**왜 이중화만?**
- Slurm은 **단일 제어점** 아키텍처 (Split-brain 방지 필요)
- 3중화 이상은 **복잡도만 증가**, 실질적 이점 없음
- 계산 노드(compute node)는 N개 → 실제 작업은 분산됨

---

### 2️⃣ 웹서비스 N중화 (Auto-Scaling)

```
                    인터넷 / 사용자
                         │
                    ┌────▼────┐
                    │ HAProxy │ (VIP: 192.168.1.101)
                    │  LB     │
                    └────┬────┘
                         │
         ┌───────────────┼───────────────┬───────────────┐
         │               │               │               │
    ┌────▼────┐     ┌────▼────┐     ┌────▼────┐     ┌────▼────┐
    │  Web1   │     │  Web2   │     │  Web3   │ ... │  WebN   │
    │ 4430/31 │     │ 4430/31 │     │ 4430/31 │     │ 4430/31 │
    │ 5010/11 │     │ 5010/11 │     │ 5010/11 │     │ 5010/11 │
    │ 5000/01 │     │ 5000/01 │     │ 5000/01 │     │ 5000/01 │
    │ 5173/74 │     │ 5173/74 │     │ 5173/74 │     │ 5173/74 │
    └────┬────┘     └────┬────┘     └────┬────┘     └────┬────┘
         │               │               │               │
         └───────────────┴───────────────┴───────────────┘
                         │
                    ┌────▼────────────┐
                    │ Redis Sentinel  │ (세션, JWT 토큰)
                    │ 3 Master Nodes  │
                    └────┬────────────┘
                         │
                    ┌────▼────────────┐
                    │ MariaDB Galera  │ (설정, 사용자 데이터)
                    │ 3 Master Nodes  │
                    └─────────────────┘
```

**자동 스케일링 메커니즘**:

#### 방법 1: 간단한 스크립트 기반 (추천)
```bash
#!/bin/bash
# auto_scale_web.sh

HAPROXY_STATS="http://192.168.1.101:8404/stats"
CPU_THRESHOLD=70
CONNECTIONS_THRESHOLD=1000

# 현재 부하 체크
CURRENT_CPU=$(get_avg_cpu_from_haproxy)
CURRENT_CONN=$(get_active_connections)

if [ $CURRENT_CPU -gt $CPU_THRESHOLD ] || [ $CURRENT_CONN -gt $CONNECTIONS_THRESHOLD ]; then
    # 새 웹서버 추가
    NEW_SERVER_ID=$((LAST_SERVER_ID + 1))

    # 1. VM 또는 컨테이너 시작
    virsh start web-node-$NEW_SERVER_ID

    # 2. 웹서비스 자동 배포 (Ansible)
    ansible-playbook -i inventory deploy_web_services.yml --limit web-node-$NEW_SERVER_ID

    # 3. HAProxy에 등록
    echo "server web$NEW_SERVER_ID 192.168.1.$NEW_SERVER_ID:4430 check" | \
        socat stdio /var/run/haproxy.sock

    echo "✅ 웹서버 $NEW_SERVER_ID 추가됨"
fi
```

#### 방법 2: Kubernetes + HPA (고급)
```yaml
# web-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-portal
spec:
  replicas: 2  # 최소 2개
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: auth-portal-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: auth-portal
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

---

## 🔧 구현 방법

### Phase 1: Slurm 이중화 (1-2주)

#### 필요한 하드웨어
```
┌────────────────┬──────────┬──────────┬─────────────┐
│ 역할            │ 호스트명  │ IP       │ 사양         │
├────────────────┼──────────┼──────────┼─────────────┤
│ Slurm Master 1 │ slurm-m1 │ .1.10    │ 8C/32GB     │
│ Slurm Master 2 │ slurm-m2 │ .1.11    │ 8C/32GB     │
│ NFS Storage    │ nfs-srv  │ .1.12    │ 4C/16GB+RAID│
│ VIP            │ (가상)   │ .1.100   │ -           │
└────────────────┴──────────┴──────────┴─────────────┘
```

#### 단계별 작업

**1. Keepalived 설정 (VIP 관리)**

`/etc/keepalived/keepalived.conf` (Master1):
```bash
vrrp_script check_slurmctld {
    script "/usr/local/bin/check_slurm_health.sh"
    interval 2
    weight -20
}

vrrp_instance SLURM_HA {
    state MASTER
    interface ens18
    virtual_router_id 51
    priority 100
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass slurm_vip_secret
    }

    virtual_ipaddress {
        192.168.1.100/24
    }

    track_script {
        check_slurmctld
    }
}
```

**2. NFS 공유 스토리지 설정**

NFS 서버:
```bash
# /etc/exports
/slurm_shared  192.168.1.0/24(rw,sync,no_root_squash)

# 디렉토리 생성
mkdir -p /slurm_shared/{config,spool,logs}
exportfs -arv
```

Master 노드들:
```bash
# /etc/fstab
nfs-srv:/slurm_shared  /mnt/slurm  nfs  defaults,_netdev  0 0

# Slurm 심볼릭 링크
ln -s /mnt/slurm/config /etc/slurm
ln -s /mnt/slurm/spool /var/spool/slurmd
ln -s /mnt/slurm/logs /var/log/slurm
```

**3. Slurm 설정 파일 수정**

`/etc/slurm/slurm.conf`:
```bash
# HA 설정
SlurmctldHost=slurm-m1(192.168.1.10)   # Primary
SlurmctldHost=slurm-m2(192.168.1.11)   # Backup

# 공유 상태 디렉토리
StateSaveLocation=/mnt/slurm/spool
SlurmdSpoolDir=/mnt/slurm/spool/slurmd

# 빠른 전환을 위한 타임아웃
SlurmctldTimeout=300
SlurmdTimeout=300
```

**4. 자동 전환 테스트**

```bash
# Master1에서 slurmctld 중지
systemctl stop slurmctld

# VIP가 Master2로 이동하는지 확인 (2초 이내)
watch -n 1 'ip addr show | grep 192.168.1.100'

# Master2에서 slurmctld가 자동 시작되는지 확인
systemctl status slurmctld

# 클라이언트에서 작업 제출이 계속 가능한지 확인
sbatch test_job.sh
```

---

### Phase 2: 웹서비스 자동 스케일링 (2-3주)

#### 방법 A: 스크립트 기반 (간단, 추천)

**1. HAProxy 설정 (동적 서버 추가 지원)**

`/etc/haproxy/haproxy.cfg`:
```bash
# Runtime API 활성화
stats socket /var/run/haproxy.sock mode 600 level admin
stats timeout 2m

# Frontend
frontend web_https
    bind *:443 ssl crt /etc/ssl/certs/hpc-portal.pem
    mode http

    # 서비스별 라우팅
    acl is_auth path_beg /auth
    acl is_dashboard path_beg /dashboard
    acl is_cae path_beg /cae
    acl is_vnc path_beg /vnc
    acl is_app path_beg /app

    use_backend auth_backend if is_auth
    use_backend dashboard_backend if is_dashboard
    use_backend cae_backend if is_cae
    use_backend vnc_backend if is_vnc
    use_backend app_backend if is_app

# Backend - 동적 서버 추가 가능
backend auth_backend
    mode http
    balance roundrobin
    option httpchk GET /health

    # 초기 서버 (최소 2대)
    server web1 192.168.1.21:4430 check
    server web2 192.168.1.22:4430 check
    # 이후 Runtime API로 동적 추가

backend dashboard_backend
    mode http
    balance leastconn
    option httpchk GET /health

    server web1 192.168.1.21:5010 check
    server web2 192.168.1.22:5010 check
```

**2. 자동 스케일링 스크립트**

`/usr/local/bin/auto_scale_web.sh`:
```bash
#!/bin/bash
# 웹서비스 자동 스케일링 스크립트

CONFIG_FILE="/etc/auto-scale/web-scale.conf"
HAPROXY_SOCK="/var/run/haproxy.sock"
LOG_FILE="/var/log/auto-scale.log"

# 설정 로드
source $CONFIG_FILE

# 현재 상태 체크
get_current_metrics() {
    # HAProxy 통계에서 현재 연결 수, 큐 길이 가져오기
    echo "show stat" | socat stdio $HAPROXY_SOCK | \
        awk -F',' '/auth_backend/{print $5,$8,$34}'
}

# 스케일 아웃 판단
should_scale_out() {
    local current_conn=$1
    local queue_len=$2

    if [ $current_conn -gt $MAX_CONNECTIONS_PER_SERVER ] || \
       [ $queue_len -gt $MAX_QUEUE_LENGTH ]; then
        return 0
    fi
    return 1
}

# 스케일 인 판단
should_scale_in() {
    local avg_conn=$1
    local server_count=$2

    if [ $avg_conn -lt $MIN_CONNECTIONS_PER_SERVER ] && \
       [ $server_count -gt $MIN_SERVERS ]; then
        return 0
    fi
    return 1
}

# 새 웹서버 추가
add_web_server() {
    local new_id=$(get_next_server_id)
    local new_ip="192.168.1.$((20 + new_id))"

    log "INFO" "새 웹서버 추가 시작: web$new_id ($new_ip)"

    # 1. VM 시작
    virsh start web-node-$new_id || {
        log "ERROR" "VM 시작 실패: web-node-$new_id"
        return 1
    }

    # 2. VM이 부팅될 때까지 대기 (SSH 접속 가능할 때까지)
    wait_for_ssh $new_ip 60 || {
        log "ERROR" "VM 부팅 타임아웃: $new_ip"
        return 1
    }

    # 3. Ansible로 웹서비스 배포
    ansible-playbook -i inventory.yml deploy_web_services.yml \
        --limit web-node-$new_id || {
        log "ERROR" "웹서비스 배포 실패: web-node-$new_id"
        return 1
    }

    # 4. HAProxy에 등록
    for port in 4430 5010 5000 5173; do
        backend=$(get_backend_name_for_port $port)
        echo "add server $backend/web$new_id $new_ip:$port check" | \
            socat stdio $HAPROXY_SOCK
    done

    log "INFO" "웹서버 추가 완료: web$new_id ($new_ip)"
    return 0
}

# 웹서버 제거
remove_web_server() {
    local server_id=$1

    log "INFO" "웹서버 제거 시작: web$server_id"

    # 1. HAProxy에서 drain 모드 설정 (새 연결 차단)
    for backend in auth_backend dashboard_backend cae_backend vnc_backend app_backend; do
        echo "set server $backend/web$server_id state drain" | \
            socat stdio $HAPROXY_SOCK
    done

    # 2. 기존 연결 종료 대기 (최대 5분)
    wait_for_connections_drain web$server_id 300

    # 3. HAProxy에서 제거
    for backend in auth_backend dashboard_backend cae_backend vnc_backend app_backend; do
        echo "del server $backend/web$server_id" | \
            socat stdio $HAPROXY_SOCK
    done

    # 4. VM 종료
    virsh shutdown web-node-$server_id

    log "INFO" "웹서버 제거 완료: web$server_id"
}

# 메인 루프
main() {
    while true; do
        metrics=$(get_current_metrics)
        current_conn=$(echo $metrics | awk '{print $1}')
        queue_len=$(echo $metrics | awk '{print $2}')
        server_count=$(get_active_server_count)

        if should_scale_out $current_conn $queue_len; then
            if [ $server_count -lt $MAX_SERVERS ]; then
                add_web_server
            else
                log "WARN" "최대 서버 수($MAX_SERVERS) 도달, 스케일 아웃 불가"
            fi
        elif should_scale_in $((current_conn / server_count)) $server_count; then
            oldest_server=$(get_oldest_server_id)
            remove_web_server $oldest_server
        fi

        # 체크 주기 (기본 30초)
        sleep ${CHECK_INTERVAL:-30}
    done
}

main "$@"
```

**3. 설정 파일**

`/etc/auto-scale/web-scale.conf`:
```bash
# 스케일링 임계값
MAX_CONNECTIONS_PER_SERVER=500
MIN_CONNECTIONS_PER_SERVER=50
MAX_QUEUE_LENGTH=20

# 서버 개수 제한
MIN_SERVERS=2
MAX_SERVERS=10

# 체크 간격 (초)
CHECK_INTERVAL=30

# VM 템플릿
VM_TEMPLATE="web-node-template"
NETWORK_BRIDGE="br0"
```

**4. Ansible 플레이북 (웹서비스 자동 배포)**

`deploy_web_services.yml`:
```yaml
---
- name: Deploy HPC Web Services
  hosts: web_nodes
  become: yes
  vars:
    dashboard_path: /opt/hpc-dashboard
    services:
      - { name: "auth_portal_4430", port: 4430 }
      - { name: "auth_frontend_4431", port: 4431 }
      - { name: "backend_5010", port: 5010 }
      - { name: "websocket_5011", port: 5011 }
      - { name: "kooCAEWebServer_5000", port: 5000 }
      - { name: "kooCAEWebAutomationServer_5001", port: 5001 }
      - { name: "dashboard_5173", port: 5173 }
      - { name: "app_5174", port: 5174 }

  tasks:
    - name: Git clone dashboard repository
      git:
        repo: https://github.com/your-org/hpc-dashboard.git
        dest: "{{ dashboard_path }}"
        version: main

    - name: Install Python dependencies
      pip:
        requirements: "{{ dashboard_path }}/{{ item.name }}/requirements.txt"
        virtualenv: "{{ dashboard_path }}/{{ item.name }}/venv"
      loop: "{{ services }}"
      when: "'backend' in item.name or 'Server' in item.name or 'portal' in item.name"

    - name: Install Node.js dependencies and build
      shell: |
        cd {{ dashboard_path }}/{{ item.name }}
        npm install
        npm run build
      loop: "{{ services }}"
      when: "'frontend' in item.name or 'dashboard' in item.name or 'app' in item.name"

    - name: Create systemd services
      template:
        src: templates/service.j2
        dest: /etc/systemd/system/{{ item.name }}.service
      loop: "{{ services }}"

    - name: Enable and start services
      systemd:
        name: "{{ item.name }}"
        enabled: yes
        state: started
        daemon_reload: yes
      loop: "{{ services }}"

    - name: Configure environment variables
      template:
        src: templates/env.j2
        dest: "{{ dashboard_path }}/{{ item.name }}/.env"
      loop: "{{ services }}"
      vars:
        redis_host: "{{ redis_sentinel_vip }}"
        redis_port: 6379
        db_host: "{{ mariadb_galera_vip }}"
        db_port: 3306
```

**5. Systemd 서비스로 자동 스케일링 실행**

`/etc/systemd/system/web-autoscale.service`:
```ini
[Unit]
Description=Web Services Auto-Scaling
After=network.target haproxy.service

[Service]
Type=simple
ExecStart=/usr/local/bin/auto_scale_web.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable web-autoscale
systemctl start web-autoscale
```

---

#### 방법 B: Kubernetes 기반 (고급, 권장하지 않음)

**왜 추천하지 않는가?**
- Slurm과 Kubernetes 모두 리소스 스케줄러 → **충돌 가능**
- HPC 클러스터는 보통 베어메탈 → K8s 오버헤드 불필요
- 복잡도만 증가, 실질적 이점 적음

**만약 도입한다면**:
```yaml
# 웹서비스만 K8s로 관리 (Slurm은 별도)
# StatefulSet이 아닌 Deployment 사용 (Stateless)

apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-portal
spec:
  replicas: 2
  selector:
    matchLabels:
      app: auth-portal
  template:
    metadata:
      labels:
        app: auth-portal
    spec:
      containers:
      - name: backend
        image: hpc-dashboard/auth-portal-backend:latest
        ports:
        - containerPort: 4430
        env:
        - name: REDIS_HOST
          value: "redis-sentinel-service"
        - name: DB_HOST
          value: "mariadb-galera-service"
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: auth-portal-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: auth-portal
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

## 📊 자동화 난이도 평가

| 구성 요소 | 난이도 | 시간 | 이유 |
|----------|-------|------|------|
| **Slurm 이중화** | ⭐⭐⭐ 중간 | 1-2주 | Keepalived, NFS 설정은 표준 절차 |
| **Redis Sentinel** | ⭐⭐ 쉬움 | 3-5일 | 이미 구현 가이드 있음 ([HA_MINIMAL_CHANGES.md](HA_MINIMAL_CHANGES.md)) |
| **MariaDB Galera** | ⭐⭐⭐ 중간 | 1주 | 초기 설정 후 자동 동기화 |
| **HAProxy + Keepalived** | ⭐⭐ 쉬움 | 3-5일 | 설정 파일 기반, 복잡도 낮음 |
| **스크립트 기반 Auto-Scale** | ⭐⭐⭐ 중간 | 1-2주 | Bash + Ansible, 테스트 필요 |
| **K8s 기반 Auto-Scale** | ⭐⭐⭐⭐⭐ 매우 어려움 | 1-2개월 | 전체 재설계 필요, 권장 안 함 |

**총 예상 시간 (스크립트 기반)**: **4-6주**

---

## ✅ 장점

### 1. Slurm 이중화
✅ **안정성**: Master 노드 장애 시 2초 이내 자동 전환
✅ **단순성**: Active-Standby는 검증된 HA 방식
✅ **비용 효율**: 서버 2대로 충분 (3중화는 불필요)

### 2. 웹서비스 N중화
✅ **탄력성**: 사용자 수에 따라 자동 확장/축소
✅ **비용 절감**: 피크 시간대만 서버 증설, 평소는 최소 운영
✅ **무중단 배포**: 한 대씩 업데이트하며 서비스 유지
✅ **부하 분산**: HAProxy가 자동으로 최적 서버 선택

### 3. 통합 이점
✅ **역할 분리**: Slurm(계산)과 웹(UI)의 장애가 서로 영향 안 줌
✅ **확장성**: 웹서버만 추가하면 더 많은 사용자 수용
✅ **모니터링**: Prometheus로 양쪽 모두 통합 모니터링

---

## ⚠️ 주의사항

### 1. Slurm 이중화
⚠️ **Split-brain 방지 필수**: Keepalived VRRP + fencing 설정
⚠️ **공유 스토리지 필수**: NFS 또는 DRBD 없으면 작동 안 함
⚠️ **네트워크 안정성**: Master 간 heartbeat 끊기면 문제 발생

### 2. 웹서비스 자동 스케일링
⚠️ **Redis/DB HA 선행**: 웹서버만 늘려도 DB가 SPOF면 의미 없음
⚠️ **VM 템플릿 관리**: 웹서버 이미지 항상 최신으로 유지
⚠️ **스케일링 속도**: VM 부팅 시간 고려 (30초~2분)
⚠️ **라이선스 확인**: 상용 SW 있으면 서버 수만큼 필요

### 3. 모니터링
⚠️ **알림 설정**: 자동 스케일링 실패 시 즉시 알림 필요
⚠️ **로그 중앙화**: 서버 N대 → 로그 수집 시스템 필수

---

## 🚀 구현 로드맵

### Week 1-2: Slurm 이중화
- [ ] NFS 서버 구축 및 공유 디렉토리 설정
- [ ] Keepalived 설정 및 VIP 테스트
- [ ] Slurm Master 2대 설정 (Primary/Backup)
- [ ] 자동 전환 테스트 (Master1 중지 → Master2 자동 시작)
- [ ] 계산 노드들이 VIP로 접속하도록 설정 변경

### Week 3: Redis + MariaDB HA
- [ ] Redis Sentinel 3노드 구성
- [ ] MariaDB Galera Cluster 3노드 구성
- [ ] 웹서비스들 DB 연결 환경변수로 변경
- [ ] 장애 테스트 (노드 1개 중지해도 서비스 정상)

### Week 4: HAProxy + 기본 웹서버 2대
- [ ] HAProxy 설치 및 설정
- [ ] 웹서버 2대 구성 (최소 구성)
- [ ] Health Check 엔드포인트 추가
- [ ] SSL 인증서 설정

### Week 5-6: 자동 스케일링 구현
- [ ] VM 템플릿 생성 (웹서비스 All-in-One)
- [ ] Ansible 플레이북 작성
- [ ] 자동 스케일링 스크립트 작성
- [ ] 부하 테스트 (Apache Bench, Locust 등)
- [ ] 알림 시스템 연동 (Slack, Email)

---

## 📈 테스트 시나리오

### 1. Slurm 장애 전환 테스트
```bash
# Master1에서 실행
systemctl stop slurmctld

# 예상 결과:
# - 2초 이내 VIP가 Master2로 이동
# - Master2에서 slurmctld 자동 시작
# - squeue, sbatch 명령 계속 작동
# - 실행 중인 작업 영향 없음
```

### 2. 웹서버 자동 스케일 아웃 테스트
```bash
# 부하 생성 (1000명 동시 사용자)
ab -n 10000 -c 1000 https://hpc-portal.example.com/auth/login

# 예상 결과:
# - 30초 이내 자동 스케일링 감지
# - 1-2분 내 새 웹서버 추가
# - HAProxy에 자동 등록
# - 부하 분산 확인
```

### 3. Redis 장애 테스트
```bash
# Redis 노드 1개 중지
systemctl stop redis-server  # on redis-node-1

# 예상 결과:
# - Redis Sentinel이 자동으로 새 Master 선출
# - 웹서비스 재접속 자동 (5초 이내)
# - 기존 세션 유지 (JWT는 무관)
```

---

## 💡 추가 최적화 아이디어

### 1. 지역별 분산 (Geo-Redundancy)
```
┌─────────────┐         ┌─────────────┐
│ Site A      │         │ Site B      │
│ (서울)      │◄───────►│ (부산)      │
│             │  WAN    │             │
│ - Slurm M1  │         │ - Slurm M2  │
│ - Web 1-5   │         │ - Web 6-10  │
└─────────────┘         └─────────────┘
```
→ 재해 복구(DR) + 지역별 로드 밸런싱

### 2. 스케줄 기반 스케일링
```bash
# crontab
# 오전 9시: 출근 시간 → 웹서버 5대로 증설
0 9 * * * /usr/local/bin/scale_to.sh 5

# 오후 6시: 퇴근 시간 → 웹서버 2대로 축소
0 18 * * * /usr/local/bin/scale_to.sh 2
```
→ 예측 가능한 부하 패턴 대응

### 3. WebSocket 세션 유지
```bash
# HAProxy - Sticky Session 설정
backend websocket_backend
    balance leastconn
    cookie SERVERID insert indirect nocache
    server web1 192.168.1.21:5011 check cookie web1
    server web2 192.168.1.22:5011 check cookie web2
```
→ WebSocket 연결이 서버 재시작 시에도 유지

---

## 📚 참고 자료

### Slurm HA
- [Slurm Workload Manager - High Availability Guide](https://slurm.schedmd.com/high_availability.html)
- [Building a Highly Available Slurm Cluster](https://wiki.fysik.dtu.dk/niflheim/Slurm_configuration#high-availability-ha-using-slurmdbd)

### 자동 스케일링
- [HAProxy Runtime API](https://www.haproxy.com/blog/dynamic-configuration-haproxy-runtime-api/)
- [Ansible Dynamic Inventory](https://docs.ansible.com/ansible/latest/user_guide/intro_dynamic_inventory.html)

### 현재 시스템 문서
- [HIGH_AVAILABILITY_PREPARATION.md](HIGH_AVAILABILITY_PREPARATION.md) - 전체 HA 아키텍처
- [HA_MINIMAL_CHANGES.md](HA_MINIMAL_CHANGES.md) - 코드 최소 변경사항

---

## 🎯 결론

### ✅ 할 만한가? → **네, 충분히 가능합니다!**

**이유**:
1. **Slurm 이중화**는 표준 HA 방식, 문서도 충분
2. **웹서비스 자동 스케일링**은 이미 Stateless 설계되어 있어 쉬움
3. **스크립트 기반** 접근이면 Kubernetes 없이도 구현 가능
4. **현재 시스템**이 이미 좋은 구조 (Nginx upstream, Redis 세션)

### 🚫 어렵지 않은가? → **중간 난이도, 관리 가능**

**수정해야 할 것**:
- ✅ Slurm 설정 파일 (`slurm.conf`) - **2줄 추가**
- ✅ 웹서비스 환경변수 (`.env`) - **10개 파일, 20줄**
- ✅ Nginx → HAProxy 전환 - **설정 파일 변환 (1:1 매핑)**

**새로 만들 것**:
- Keepalived 설정 (복사-붙여넣기 수준)
- 자동 스케일링 스크립트 (이 문서에 샘플 있음)
- Ansible 플레이북 (이 문서에 샘플 있음)

### 💰 비용 대비 효과

```
초기 투자: 4-6주 작업 시간
운영 비용: 최소 서버 2대 → 피크 시 N대 (자동 조절)
효과:
  - 99.9% 가용성 (Slurm 이중화)
  - 무한 확장성 (웹서비스 Auto-Scale)
  - 비용 절감 (사용량만큼만 지불)
```

**추천**: 스크립트 기반 자동 스케일링으로 시작, 추후 필요시 K8s 고려
