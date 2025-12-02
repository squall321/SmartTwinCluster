# Phase 0: YAML 파싱 및 기본 프레임워크 ✅

## 완료 상태

- ✅ YAML 파서 구현 (parser.py)
- ✅ 자동 탐지 시스템 (auto_discovery.sh)
- ✅ 클러스터 정보 표시 (cluster_info.sh)

## 구현된 파일

```
cluster/
├── config/
│   └── parser.py           # YAML 파서 및 CLI 도구
├── discovery/
│   └── auto_discovery.sh   # 활성 노드 자동 탐지
└── utils/
    └── cluster_info.sh     # 클러스터 상태 표시
```

## 사용법

### 1. YAML 파서 (parser.py)

```bash
# 설정 검증
python3 cluster/config/parser.py --config my_multihead_cluster.yaml --validate

# 모든 controller 리스트
python3 cluster/config/parser.py --config my_multihead_cluster.yaml --list-controllers

# MariaDB 활성화된 controller만 필터
python3 cluster/config/parser.py --config my_multihead_cluster.yaml --service mariadb

# VIP 설정 확인
python3 cluster/config/parser.py --config my_multihead_cluster.yaml --get-vip

# 현재 controller 정보 (로컬 IP 기반)
python3 cluster/config/parser.py --config my_multihead_cluster.yaml --current
```

**출력 예시**:
```json
[
  {
    "hostname": "server1",
    "ip_address": "192.168.1.101",
    "priority": 100,
    "services": {
      "glusterfs": true,
      "mariadb": true,
      "redis": true,
      "slurm": true,
      "web": true,
      "keepalived": true
    },
    "vip_owner": true
  }
]
```

### 2. 자동 탐지 (auto_discovery.sh)

```bash
# 활성 controller 탐지
./cluster/discovery/auto_discovery.sh --config my_multihead_cluster.yaml --timeout 2
```

**출력 예시**:
```json
{
  "timestamp": "2025-10-27T00:06:54+00:00",
  "total_controllers": 4,
  "active_controllers": 0,
  "inactive_controllers": 4,
  "vip": "192.168.1.100",
  "vip_owner": null,
  "cluster_state": "down",
  "controllers": [
    {
      "hostname": "server1",
      "ip": "192.168.1.101",
      "status": "inactive",
      "error": "Connection timeout or SSH error"
    }
  ]
}
```

**활성 controller가 있을 때 출력**:
```json
{
  "controllers": [
    {
      "hostname": "server1",
      "ip": "192.168.1.101",
      "status": "active",
      "priority": 100,
      "load": "0.35",
      "uptime": "5 days",
      "services": {
        "glusterfs": {"status": "ok", "peers": 3},
        "mariadb": {"status": "ok", "cluster_size": 4, "state": "Synced"},
        "redis": {"status": "ok", "cluster_state": "ok", "nodes": 4},
        "slurm": {"status": "ok", "role": "primary"},
        "web": {"status": "ok", "http_code": 200},
        "keepalived": {"status": "ok", "state": "MASTER", "vip": true}
      }
    }
  ]
}
```

### 3. 클러스터 정보 표시 (cluster_info.sh)

```bash
# Table 형식 (기본)
./cluster/utils/cluster_info.sh --config my_multihead_cluster.yaml

# JSON 형식
./cluster/utils/cluster_info.sh --config my_multihead_cluster.yaml --format json

# Compact 형식
./cluster/utils/cluster_info.sh --config my_multihead_cluster.yaml --format compact
```

**출력 예시 (Table)**:
```
========================================
HPC Portal Multi-Head Cluster Status
========================================
Cluster Name: my_multihead_cluster
Cluster Size: 4-node
Cluster State: down
VIP: 192.168.1.100 (owned by none)
Active/Total: 0/4 controllers
Timestamp: 2025-10-27T00:06:54+00:00

Controller Status:
+------------+---------------+----------+--------+-----+-----+-----+-----+-----+
| Hostname   | IP            | Status   | Load   | GFS | MDB | RDS | SLM | WEB |
+------------+---------------+----------+--------+-----+-----+-----+-----+-----+
| server1    | 192.168.1.101 | Inactive | N/A    |  ✗  |  ✗  |  ✗  |  ✗  |  ✗  |
| server2    | 192.168.1.102 | Inactive | N/A    |  ✗  |  ✗  |  ✗  |  ✗  |  ✗  |
| server3    | 192.168.1.103 | Inactive | N/A    |  ✗  |  ✗  |  ✗  |  ✗  |  ✗  |
| server4    | 192.168.1.104 | Inactive | N/A    |  ✗  |  ✗  |  ✗  |  ✗  |  ✗  |
+------------+---------------+----------+--------+-----+-----+-----+-----+-----+
GFS=GlusterFS, MDB=MariaDB, RDS=Redis, SLM=Slurm, WEB=Web Services

========================================
```

## 기능 설명

### parser.py의 주요 기능

1. **YAML 파싱**: my_multihead_cluster.yaml을 읽어 Python 딕셔너리로 변환
2. **환경변수 치환**: `${DB_PASSWORD}` 형식의 변수를 실제 환경변수 값으로 치환
3. **필터링**: 특정 서비스가 활성화된 controller만 추출
4. **검증**: 설정 파일의 유효성 검사 (중복 IP, Priority 등)
5. **현재 controller 감지**: 로컬 IP를 기반으로 현재 controller 정보 반환

### auto_discovery.sh의 주요 기능

1. **SSH 접속 테스트**: 각 controller에 SSH로 접속 시도
2. **서비스별 상태 확인**:
   - GlusterFS: `gluster peer status`
   - MariaDB: `SHOW STATUS LIKE 'wsrep%'`
   - Redis: `redis-cli cluster info`
   - Slurm: `scontrol ping`
   - Web: `curl http://IP:4430/health`
   - Keepalived: VIP 소유 여부 확인
3. **JSON 출력**: 표준화된 JSON 형식으로 결과 출력
4. **타임아웃 설정**: 긴 대기 시간 방지

### cluster_info.sh의 주요 기능

1. **사용자 친화적 표시**: 테이블 형식으로 클러스터 상태 표시
2. **서비스 상태 요약**: 각 서비스별 활성 노드 수 표시
3. **다양한 출력 형식**: table, json, compact 지원
4. **컬러 출력**: 상태에 따라 색상으로 구분 (active=녹색, inactive=빨강)

## 테스트 결과

### ✅ parser.py 테스트

```bash
$ python3 cluster/config/parser.py --config my_multihead_cluster.yaml --validate
✅ Configuration is valid

$ python3 cluster/config/parser.py --config my_multihead_cluster.yaml --service mariadb
[JSON output with 4 MariaDB-enabled controllers]
```

### ✅ auto_discovery.sh 테스트

```bash
$ ./cluster/discovery/auto_discovery.sh --config my_multihead_cluster.yaml --timeout 1
[JSON output showing all controllers as inactive - expected since servers don't exist yet]
```

### ✅ cluster_info.sh 테스트

```bash
$ ./cluster/utils/cluster_info.sh --config my_multihead_cluster.yaml
[Table output showing cluster status]
```

## Python 라이브러리로 사용

parser.py는 독립 실행 가능한 스크립트이지만, Python 모듈로도 사용할 수 있습니다:

```python
#!/usr/bin/env python3
import sys
sys.path.insert(0, '/path/to/cluster/config')

from parser import ClusterConfigParser

# 파서 초기화
config = ClusterConfigParser('my_multihead_cluster.yaml')

# MariaDB 활성화된 controller 가져오기
mariadb_controllers = config.get_active_controllers('mariadb')

for ctrl in mariadb_controllers:
    print(f"Controller: {ctrl['hostname']} ({ctrl['ip_address']})")

# VIP 설정 가져오기
vip = config.get_vip_config()
print(f"VIP: {vip['address']}")

# 현재 controller 확인
current = config.get_current_controller()
if current:
    print(f"Current controller: {current['hostname']}")
```

## 다음 단계

Phase 0 완료! 다음은 **Phase 1: GlusterFS 동적 클러스터링** 구현입니다.

Phase 1에서는:
1. GlusterFS 자동 설치
2. Peer 연결 자동화
3. Volume 생성/조인 자동 결정
4. 동적 Brick 추가/제거

계속 진행하려면:
```bash
# Phase 1 구현 시작
# 구현 계획은 MULTIHEAD_IMPLEMENTATION_PLAN.md의 Phase 1 섹션 참조
```

## 파일 위치

- 설정 파일: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_multihead_cluster.yaml`
- 스크립트: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/cluster/`
- 문서: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MULTIHEAD_IMPLEMENTATION_PLAN.md`
