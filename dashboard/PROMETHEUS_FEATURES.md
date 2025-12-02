# Prometheus Server (Port 9090) - 기능 상세 문서

## 📋 개요
시계열 데이터베이스 및 모니터링 시스템으로, 시스템 메트릭을 수집하고 저장합니다.

**포트**: 9090  
**프레임워크**: Prometheus  
**쿼리 언어**: PromQL  
**데이터 보관**: Time Series Database  

---

## 🏗️ 아키텍처

### 1. 디렉토리 구조
```
prometheus_9090/
├── prometheus.yml          # 메인 설정 파일
├── prometheus             # 실행 파일
├── data/                  # 시계열 데이터 저장
├── rules/                 # 알림 규칙
│   └── alerts.yml
└── logs/
    └── prometheus.log
```

### 2. 데이터 수집 구조
```
Prometheus (9090)
    ↓ (scrape)
Node Exporter (9100) → 시스템 메트릭
    ↓
Dashboard Backend (5010) → PromQL 쿼리
    ↓
Dashboard Frontend (3010) → 차트 시각화
```

---

## ⚙️ 설정 파일 (`prometheus.yml`)

### 기본 설정
```yaml
# 글로벌 설정
global:
  scrape_interval: 15s      # 15초마다 메트릭 수집
  evaluation_interval: 15s   # 15초마다 규칙 평가
  external_labels:
    cluster: 'slurm-hpc'
    environment: 'production'

# Alertmanager 설정 (옵션)
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

# 규칙 파일
rule_files:
  - 'rules/alerts.yml'

# 스크랩 설정
scrape_configs:
  # Prometheus 자체 모니터링
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  # Node Exporter (시스템 메트릭)
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          node: 'master'
      - targets: ['node001:9100', 'node002:9100', 'node003:9100', 'node004:9100']
        labels:
          node_group: 'compute'
  
  # NVIDIA GPU Exporter (GPU 메트릭)
  - job_name: 'nvidia_exporter'
    static_configs:
      - targets: ['localhost:9445']
        labels:
          node: 'master'
      - targets: ['node001:9445', 'node002:9445']
        labels:
          node_group: 'gpu'
  
  # Slurm Exporter (Slurm 작업 메트릭)
  - job_name: 'slurm_exporter'
    static_configs:
      - targets: ['localhost:9341']
```

---

## 📊 메트릭 타입

### 1. Node Exporter 메트릭

#### CPU 메트릭
| 메트릭 이름 | 설명 | 단위 |
|------------|------|------|
| `node_cpu_seconds_total` | CPU 시간 누적 | seconds |
| `node_load1` | 1분 평균 부하 | - |
| `node_load5` | 5분 평균 부하 | - |
| `node_load15` | 15분 평균 부하 | - |

**CPU 사용률 계산 (PromQL)**
```promql
# 전체 CPU 사용률
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 코어별 CPU 사용률
100 - (avg by (instance, cpu) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 모드별 CPU 사용률
rate(node_cpu_seconds_total{mode="user"}[5m]) * 100    # user
rate(node_cpu_seconds_total{mode="system"}[5m]) * 100  # system
rate(node_cpu_seconds_total{mode="iowait"}[5m]) * 100  # iowait
```

#### 메모리 메트릭
| 메트릭 이름 | 설명 | 단위 |
|------------|------|------|
| `node_memory_MemTotal_bytes` | 전체 메모리 | bytes |
| `node_memory_MemAvailable_bytes` | 사용 가능 메모리 | bytes |
| `node_memory_MemFree_bytes` | 빈 메모리 | bytes |
| `node_memory_Buffers_bytes` | 버퍼 메모리 | bytes |
| `node_memory_Cached_bytes` | 캐시 메모리 | bytes |

**메모리 사용률 계산 (PromQL)**
```promql
# 메모리 사용률 (%)
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 사용 중인 메모리 (GB)
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024

# 스왑 사용률
(1 - node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes) * 100
```

#### 디스크 메트릭
| 메트릭 이름 | 설명 | 단위 |
|------------|------|------|
| `node_filesystem_size_bytes` | 파일시스템 크기 | bytes |
| `node_filesystem_avail_bytes` | 사용 가능 공간 | bytes |
| `node_filesystem_files` | 전체 inode 수 | - |
| `node_disk_io_time_seconds_total` | 디스크 I/O 시간 | seconds |
| `node_disk_read_bytes_total` | 읽은 바이트 | bytes |
| `node_disk_written_bytes_total` | 쓴 바이트 | bytes |

**디스크 사용률 계산 (PromQL)**
```promql
# 디스크 사용률 (%)
(1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100

# 디스크 I/O 속도 (bytes/sec)
rate(node_disk_read_bytes_total[5m])    # 읽기
rate(node_disk_written_bytes_total[5m]) # 쓰기

# /data 파티션 사용률
(1 - node_filesystem_avail_bytes{mountpoint="/data"} / node_filesystem_size_bytes{mountpoint="/data"}) * 100
```

#### 네트워크 메트릭
| 메트릭 이름 | 설명 | 단위 |
|------------|------|------|
| `node_network_receive_bytes_total` | 수신 바이트 | bytes |
| `node_network_transmit_bytes_total` | 송신 바이트 | bytes |
| `node_network_receive_packets_total` | 수신 패킷 | packets |
| `node_network_transmit_packets_total` | 송신 패킷 | packets |

**네트워크 트래픽 계산 (PromQL)**
```promql
# 수신 속도 (bytes/sec)
rate(node_network_receive_bytes_total{device="eth0"}[5m])

# 송신 속도 (bytes/sec)
rate(node_network_transmit_bytes_total{device="eth0"}[5m])

# 전체 트래픽 (Mbps)
(rate(node_network_receive_bytes_total[5m]) + rate(node_network_transmit_bytes_total[5m])) * 8 / 1000000
```

---

### 2. NVIDIA GPU 메트릭

#### GPU 사용률
| 메트릭 이름 | 설명 | 단위 |
|------------|------|------|
| `nvidia_smi_utilization_gpu_ratio` | GPU 사용률 | ratio (0-1) |
| `nvidia_smi_utilization_memory_ratio` | GPU 메모리 사용률 | ratio (0-1) |
| `nvidia_smi_memory_total_bytes` | 전체 GPU 메모리 | bytes |
| `nvidia_smi_memory_used_bytes` | 사용 중 GPU 메모리 | bytes |
| `nvidia_smi_temperature_gpu` | GPU 온도 | celsius |
| `nvidia_smi_power_draw_watts` | GPU 전력 소비 | watts |

**GPU 메트릭 쿼리 (PromQL)**
```promql
# GPU 사용률 (%)
nvidia_smi_utilization_gpu_ratio * 100

# GPU 메모리 사용률 (%)
nvidia_smi_utilization_memory_ratio * 100

# GPU별 온도
nvidia_smi_temperature_gpu

# GPU별 전력 소비
nvidia_smi_power_draw_watts

# 평균 GPU 사용률
avg(nvidia_smi_utilization_gpu_ratio) * 100

# Top 사용률 GPU
topk(5, nvidia_smi_utilization_gpu_ratio * 100)
```

---

### 3. Slurm Exporter 메트릭

#### 작업 메트릭
| 메트릭 이름 | 설명 |
|------------|------|
| `slurm_queue_jobs` | 큐에 대기 중인 작업 수 |
| `slurm_running_jobs` | 실행 중인 작업 수 |
| `slurm_job_cpus_allocated` | 할당된 CPU 수 |
| `slurm_job_memory_allocated_bytes` | 할당된 메모리 |

#### 노드 메트릭
| 메트릭 이름 | 설명 |
|------------|------|
| `slurm_nodes_total` | 전체 노드 수 |
| `slurm_nodes_idle` | 유휴 노드 수 |
| `slurm_nodes_allocated` | 할당된 노드 수 |
| `slurm_nodes_down` | 다운된 노드 수 |

**Slurm 메트릭 쿼리 (PromQL)**
```promql
# 전체 작업 수
slurm_queue_jobs + slurm_running_jobs

# 노드 사용률
(slurm_nodes_allocated / slurm_nodes_total) * 100

# CPU 할당률
(slurm_job_cpus_allocated / slurm_cpus_total) * 100
```

---

## 🔍 PromQL 쿼리 예제

### 기본 쿼리
```promql
# 단일 메트릭 조회
node_cpu_seconds_total

# 레이블 필터링
node_cpu_seconds_total{cpu="0", mode="idle"}

# 정규표현식 필터
node_cpu_seconds_total{instance=~"node.*"}

# 여러 조건
node_cpu_seconds_total{mode="idle", cpu=~"[0-3]"}
```

### 함수 사용
```promql
# rate() - 초당 변화율
rate(node_cpu_seconds_total[5m])

# irate() - 순간 변화율
irate(node_cpu_seconds_total[5m])

# increase() - 증가량
increase(node_network_receive_bytes_total[1h])

# avg() - 평균
avg(node_cpu_seconds_total) by (instance)

# sum() - 합계
sum(node_memory_MemTotal_bytes) by (instance)

# topk() - 상위 k개
topk(5, node_cpu_seconds_total)
```

### 고급 쿼리
```promql
# CPU 사용률 (모든 코어 평균)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 메모리 사용량 (GB)
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024

# 디스크 I/O (MB/s)
rate(node_disk_read_bytes_total[5m]) / 1024 / 1024

# 네트워크 대역폭 (Mbps)
(rate(node_network_receive_bytes_total[5m]) * 8) / 1000000

# GPU 평균 온도
avg(nvidia_smi_temperature_gpu) by (instance)

# 노드별 Top 5 CPU 사용률
topk(5, 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))
```

### 비교 쿼리
```promql
# CPU vs Memory 사용률 비교
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
or
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 여러 노드 비교
avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100
```

---

## 🚨 알림 규칙 (`rules/alerts.yml`)

### 기본 알림 규칙
```yaml
groups:
  - name: node_alerts
    interval: 30s
    rules:
      # 높은 CPU 사용률
      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
        for: 5m
        labels:
          severity: warning
          component: cpu
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value }}% on {{ $labels.instance }}"
      
      # 높은 메모리 사용률
      - alert: HighMemoryUsage
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
        for: 5m
        labels:
          severity: warning
          component: memory
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value }}% on {{ $labels.instance }}"
      
      # 디스크 공간 부족
      - alert: LowDiskSpace
        expr: (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 > 85
        for: 10m
        labels:
          severity: warning
          component: disk
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Disk usage is {{ $value }}% on {{ $labels.mountpoint }}"
      
      # 높은 GPU 온도
      - alert: HighGPUTemperature
        expr: nvidia_smi_temperature_gpu > 80
        for: 5m
        labels:
          severity: warning
          component: gpu
        annotations:
          summary: "High GPU temperature on {{ $labels.instance }}"
          description: "GPU {{ $labels.gpu }} temperature is {{ $value }}°C"
      
      # 노드 다운
      - alert: NodeDown
        expr: up{job="node_exporter"} == 0
        for: 1m
        labels:
          severity: critical
          component: node
        annotations:
          summary: "Node {{ $labels.instance }} is down"
          description: "Node exporter on {{ $labels.instance }} is not responding"
```

---

## 🔌 API 엔드포인트

### 쿼리 API
```bash
# Instant query
curl 'http://localhost:9090/api/v1/query?query=up'

# Range query
curl 'http://localhost:9090/api/v1/query_range?query=node_cpu_seconds_total&start=2025-10-10T00:00:00Z&end=2025-10-10T01:00:00Z&step=15s'

# 레이블 목록
curl 'http://localhost:9090/api/v1/labels'

# 레이블 값 목록
curl 'http://localhost:9090/api/v1/label/__name__/values'

# 시계열 조회
curl 'http://localhost:9090/api/v1/series?match[]=node_cpu_seconds_total'
```

### 관리 API
```bash
# 타겟 목록
curl 'http://localhost:9090/api/v1/targets'

# 규칙 목록
curl 'http://localhost:9090/api/v1/rules'

# 알림 목록
curl 'http://localhost:9090/api/v1/alerts'

# 설정 조회
curl 'http://localhost:9090/api/v1/status/config'

# Health check
curl 'http://localhost:9090/-/healthy'

# Readiness check
curl 'http://localhost:9090/-/ready'
```

---

## 🖥️ Web UI

### 접속
```
http://localhost:9090
```

### 주요 기능
1. **Graph**: PromQL 쿼리 실행 및 그래프 시각화
2. **Alerts**: 활성 알림 목록
3. **Status**: 
   - Targets: 스크랩 타겟 상태
   - Configuration: 현재 설정
   - Rules: 알림 규칙
   - Service Discovery: 자동 발견 상태
4. **Metrics Explorer**: 메트릭 탐색

---

## 💾 데이터 보관

### 보관 설정
```yaml
# prometheus.yml
global:
  storage:
    tsdb:
      path: ./data
      retention.time: 15d      # 15일 보관
      retention.size: 50GB     # 최대 50GB
```

### 데이터 백업
```bash
# 스냅샷 생성
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

# 스냅샷 위치
# data/snapshots/YYYYMMDDTHHMMSS-XXXXX/
```

---

## 🚀 시작/중지 스크립트

### `start.sh`
```bash
#!/bin/bash
cd "$(dirname "$0")"

./prometheus \
  --config.file=prometheus.yml \
  --storage.tsdb.path=./data \
  --web.console.templates=./consoles \
  --web.console.libraries=./console_libraries \
  --web.listen-address=:9090 \
  --storage.tsdb.retention.time=15d \
  > logs/prometheus.log 2>&1 &

echo $! > .prometheus.pid
echo "✅ Prometheus started on http://localhost:9090"
```

### `stop.sh`
```bash
#!/bin/bash
if [ -f .prometheus.pid ]; then
    kill $(cat .prometheus.pid)
    rm .prometheus.pid
    echo "✅ Prometheus stopped"
fi
```

---

## 🔧 최적화 팁

### 1. 쿼리 최적화
```promql
# 나쁜 예: 모든 시계열 조회
node_cpu_seconds_total

# 좋은 예: 필터링
node_cpu_seconds_total{instance="node001:9100"}

# 나쁜 예: 긴 범위
rate(node_cpu_seconds_total[1h])

# 좋은 예: 적절한 범위
rate(node_cpu_seconds_total[5m])
```

### 2. Recording Rules
자주 사용하는 복잡한 쿼리를 미리 계산하여 저장

```yaml
# rules/recording.yml
groups:
  - name: cpu_rules
    interval: 15s
    rules:
      - record: instance:node_cpu_utilization:rate5m
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
      
      - record: instance:node_memory_utilization:ratio
        expr: 1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
```

사용:
```promql
# 복잡한 원본 쿼리 대신
instance:node_cpu_utilization:rate5m

# 빠르고 간단
instance:node_memory_utilization:ratio * 100
```

---

## 🧪 테스트

### 메트릭 확인
```bash
# Node Exporter 메트릭 확인
curl http://localhost:9100/metrics | grep node_cpu

# Prometheus가 수집하는지 확인
curl 'http://localhost:9090/api/v1/query?query=up{job="node_exporter"}'
```

### 알림 테스트
```bash
# CPU 부하 생성 (테스트용)
stress-ng --cpu 8 --timeout 300s

# 알림 발생 확인
curl 'http://localhost:9090/api/v1/alerts' | jq
```

---

## 📊 대시보드 통합

### Grafana 연동 (옵션)
```bash
# Grafana 설치
sudo apt-get install grafana

# Prometheus 데이터 소스 추가
curl -X POST http://admin:admin@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://localhost:9090",
    "access": "proxy",
    "isDefault": true
  }'
```

---

## 🚀 추가 기능 로드맵

### Phase 1: 현재 구현 완료
- ✅ Node Exporter 연동
- ✅ GPU 메트릭 수집
- ✅ 알림 규칙 설정
- ✅ 15일 데이터 보관

### Phase 2: 개선 예정
- 🔄 **Alertmanager 통합**: 알림 라우팅 및 그룹화
- 🔄 **Remote Storage**: 장기 데이터 보관
- 🔄 **Service Discovery**: 동적 타겟 발견
- 🔄 **Federation**: 여러 Prometheus 서버 통합

### Phase 3: 신규 기능
- 📋 **Custom Exporters**: Slurm 전용 메트릭
- 📋 **Thanos 통합**: 고가용성 및 장기 저장
- 📋 **Machine Learning**: 이상 탐지
- 📋 **Cost Analysis**: 리소스 비용 분석

---

## 📚 참고 자료
- [Prometheus 공식 문서](https://prometheus.io/docs/)
- [PromQL 가이드](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Best Practices](https://prometheus.io/docs/practices/)
