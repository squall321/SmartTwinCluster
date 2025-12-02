# Node Exporter (Port 9100) - 기능 상세 문서

## 📋 개요
시스템 하드웨어 및 OS 메트릭을 수집하여 Prometheus에 노출하는 Exporter입니다.

**포트**: 9100  
**프로토콜**: HTTP  
**메트릭 포맷**: Prometheus Text Format  
**프레임워크**: Prometheus Node Exporter  

---

## 🏗️ 아키텍처

### 1. 디렉토리 구조
```
node_exporter_9100/
├── node_exporter          # 실행 파일
├── start.sh               # 시작 스크립트
├── stop.sh                # 중지 스크립트
├── .node_exporter.pid     # PID 파일
└── logs/
    └── node_exporter.log  # 로그 파일
```

### 2. 데이터 흐름
```
Linux Kernel
    ↓
/proc, /sys 파일시스템
    ↓
Node Exporter (9100) → 메트릭 수집 및 노출
    ↓
Prometheus (9090) → 15초마다 스크랩
    ↓
Dashboard Backend (5010) → PromQL 쿼리
    ↓
Dashboard Frontend (3010) → 시각화
```

---

## 📊 수집 메트릭

### 1. CPU 메트릭

#### node_cpu_seconds_total
CPU가 각 모드에서 소비한 시간 (초)

**레이블**:
- `cpu`: CPU 번호 (0, 1, 2, ...)
- `mode`: CPU 모드
  - `idle`: 유휴
  - `user`: 사용자 프로세스
  - `system`: 시스템/커널
  - `iowait`: I/O 대기
  - `irq`: 하드웨어 인터럽트
  - `softirq`: 소프트웨어 인터럽트
  - `steal`: 가상화 환경에서 다른 VM에 할당된 시간
  - `nice`: nice 값이 설정된 프로세스

**예제 메트릭**:
```
node_cpu_seconds_total{cpu="0",mode="idle"} 123456.78
node_cpu_seconds_total{cpu="0",mode="user"} 45678.90
node_cpu_seconds_total{cpu="0",mode="system"} 12345.67
```

**사용 예제 (PromQL)**:
```promql
# CPU 0의 사용률
100 - (rate(node_cpu_seconds_total{cpu="0",mode="idle"}[5m]) * 100)

# 전체 CPU 평균 사용률
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# user 모드 CPU 사용률
rate(node_cpu_seconds_total{mode="user"}[5m]) * 100
```

---

#### node_load1, node_load5, node_load15
시스템 부하 평균 (1분, 5분, 15분)

**예제 메트릭**:
```
node_load1 2.45
node_load5 1.89
node_load15 1.23
```

**해석**:
- 값 < CPU 코어 수: 시스템이 여유로움
- 값 ≈ CPU 코어 수: 시스템이 적정 부하
- 값 > CPU 코어 수: 시스템이 과부하

---

### 2. 메모리 메트릭

#### 주요 메모리 메트릭
| 메트릭 | 설명 | 단위 |
|--------|------|------|
| `node_memory_MemTotal_bytes` | 전체 물리 메모리 | bytes |
| `node_memory_MemFree_bytes` | 빈 메모리 | bytes |
| `node_memory_MemAvailable_bytes` | 사용 가능한 메모리 | bytes |
| `node_memory_Buffers_bytes` | 버퍼 캐시 | bytes |
| `node_memory_Cached_bytes` | 페이지 캐시 | bytes |
| `node_memory_SwapTotal_bytes` | 전체 스왑 | bytes |
| `node_memory_SwapFree_bytes` | 빈 스왑 | bytes |
| `node_memory_Active_bytes` | 활성 메모리 | bytes |
| `node_memory_Inactive_bytes` | 비활성 메모리 | bytes |

**예제 메트릭**:
```
node_memory_MemTotal_bytes 274877906944  # 256GB
node_memory_MemAvailable_bytes 137438953472  # 128GB
node_memory_MemFree_bytes 68719476736  # 64GB
```

**사용 예제 (PromQL)**:
```promql
# 메모리 사용률 (%)
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 사용 중인 메모리 (GB)
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024

# 스왑 사용률 (%)
(1 - node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes) * 100

# 캐시 메모리 (GB)
node_memory_Cached_bytes / 1024 / 1024 / 1024
```

---

### 3. 디스크 메트릭

#### Filesystem 메트릭
| 메트릭 | 설명 | 단위 |
|--------|------|------|
| `node_filesystem_size_bytes` | 파일시스템 전체 크기 | bytes |
| `node_filesystem_avail_bytes` | 사용 가능 공간 | bytes |
| `node_filesystem_free_bytes` | 빈 공간 | bytes |
| `node_filesystem_files` | 전체 inode 수 | - |
| `node_filesystem_files_free` | 빈 inode 수 | - |

**레이블**:
- `device`: 장치 이름 (/dev/sda1)
- `fstype`: 파일시스템 타입 (ext4, xfs, nfs)
- `mountpoint`: 마운트 포인트 (/, /data, /scratch)

**예제 메트릭**:
```
node_filesystem_size_bytes{device="/dev/sda1",fstype="ext4",mountpoint="/"} 107374182400
node_filesystem_avail_bytes{device="/dev/sda1",fstype="ext4",mountpoint="/"} 53687091200
```

**사용 예제 (PromQL)**:
```promql
# / 파티션 사용률
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# /data 파티션 사용 가능 공간 (TB)
node_filesystem_avail_bytes{mountpoint="/data"} / 1024 / 1024 / 1024 / 1024

# inode 사용률
(1 - node_filesystem_files_free / node_filesystem_files) * 100
```

---

#### Disk I/O 메트릭
| 메트릭 | 설명 | 단위 |
|--------|------|------|
| `node_disk_read_bytes_total` | 읽은 총 바이트 | bytes |
| `node_disk_written_bytes_total` | 쓴 총 바이트 | bytes |
| `node_disk_reads_completed_total` | 완료된 읽기 작업 | count |
| `node_disk_writes_completed_total` | 완료된 쓰기 작업 | count |
| `node_disk_io_time_seconds_total` | I/O 작업에 소비된 시간 | seconds |
| `node_disk_read_time_seconds_total` | 읽기에 소비된 시간 | seconds |
| `node_disk_write_time_seconds_total` | 쓰기에 소비된 시간 | seconds |

**레이블**:
- `device`: 장치 이름 (sda, sdb, nvme0n1)

**예제 메트릭**:
```
node_disk_read_bytes_total{device="sda"} 123456789012
node_disk_written_bytes_total{device="sda"} 987654321098
```

**사용 예제 (PromQL)**:
```promql
# 읽기 속도 (MB/s)
rate(node_disk_read_bytes_total[5m]) / 1024 / 1024

# 쓰기 속도 (MB/s)
rate(node_disk_written_bytes_total[5m]) / 1024 / 1024

# 총 I/O 속도 (MB/s)
(rate(node_disk_read_bytes_total[5m]) + rate(node_disk_written_bytes_total[5m])) / 1024 / 1024

# IOPS
rate(node_disk_reads_completed_total[5m]) + rate(node_disk_writes_completed_total[5m])

# 디스크 사용률 (%)
rate(node_disk_io_time_seconds_total[5m]) * 100
```

---

### 4. 네트워크 메트릭

#### 네트워크 트래픽 메트릭
| 메트릭 | 설명 | 단위 |
|--------|------|------|
| `node_network_receive_bytes_total` | 수신한 총 바이트 | bytes |
| `node_network_transmit_bytes_total` | 송신한 총 바이트 | bytes |
| `node_network_receive_packets_total` | 수신한 총 패킷 | packets |
| `node_network_transmit_packets_total` | 송신한 총 패킷 | packets |
| `node_network_receive_errs_total` | 수신 오류 | count |
| `node_network_transmit_errs_total` | 송신 오류 | count |
| `node_network_receive_drop_total` | 수신 드롭 | count |
| `node_network_transmit_drop_total` | 송신 드롭 | count |

**레이블**:
- `device`: 네트워크 인터페이스 (eth0, enp0s3, ib0)

**예제 메트릭**:
```
node_network_receive_bytes_total{device="eth0"} 9876543210987
node_network_transmit_bytes_total{device="eth0"} 1234567890123
```

**사용 예제 (PromQL)**:
```promql
# 수신 속도 (Mbps)
rate(node_network_receive_bytes_total{device="eth0"}[5m]) * 8 / 1000000

# 송신 속도 (Mbps)
rate(node_network_transmit_bytes_total{device="eth0"}[5m]) * 8 / 1000000

# 총 대역폭 (Mbps)
(rate(node_network_receive_bytes_total[5m]) + rate(node_network_transmit_bytes_total[5m])) * 8 / 1000000

# 패킷 손실률 (%)
(rate(node_network_receive_drop_total[5m]) / rate(node_network_receive_packets_total[5m])) * 100

# 오류율 (%)
(rate(node_network_receive_errs_total[5m]) / rate(node_network_receive_packets_total[5m])) * 100
```

---

### 5. 시스템 메트릭

#### 부팅 및 시간
| 메트릭 | 설명 | 단위 |
|--------|------|------|
| `node_boot_time_seconds` | 시스템 부팅 시간 (Unix timestamp) | seconds |
| `node_time_seconds` | 현재 시스템 시간 (Unix timestamp) | seconds |

**사용 예제 (PromQL)**:
```promql
# 업타임 (일)
(time() - node_boot_time_seconds) / 86400

# 시스템 시계 차이 (초)
node_time_seconds - time()
```

---

#### 프로세스 메트릭
| 메트릭 | 설명 |
|--------|------|
| `node_procs_running` | 실행 중인 프로세스 수 |
| `node_procs_blocked` | I/O 대기 중인 프로세스 수 |
| `node_processes_max_processes` | 최대 프로세스 수 |

**예제**:
```
node_procs_running 3
node_procs_blocked 0
```

---

#### Context Switch 및 Interrupt
| 메트릭 | 설명 | 단위 |
|--------|------|------|
| `node_context_switches_total` | 컨텍스트 스위치 총 횟수 | count |
| `node_intr_total` | 인터럽트 총 횟수 | count |

**사용 예제 (PromQL)**:
```promql
# 초당 컨텍스트 스위치
rate(node_context_switches_total[5m])

# 초당 인터럽트
rate(node_intr_total[5m])
```

---

### 6. 온도 메트릭 (hwmon)

#### 하드웨어 모니터링
| 메트릭 | 설명 | 단위 |
|--------|------|------|
| `node_hwmon_temp_celsius` | 온도 센서 값 | celsius |
| `node_hwmon_temp_max_celsius` | 최대 온도 | celsius |
| `node_hwmon_temp_crit_celsius` | 임계 온도 | celsius |

**레이블**:
- `chip`: 칩 이름
- `sensor`: 센서 이름

**예제 메트릭**:
```
node_hwmon_temp_celsius{chip="coretemp-isa-0000",sensor="temp1"} 45.0
node_hwmon_temp_celsius{chip="coretemp-isa-0000",sensor="temp2"} 47.0
```

**사용 예제 (PromQL)**:
```promql
# 평균 CPU 온도
avg(node_hwmon_temp_celsius{chip="coretemp-isa-0000"})

# 최고 온도
max(node_hwmon_temp_celsius)

# 온도 임계값 초과
node_hwmon_temp_celsius > node_hwmon_temp_max_celsius
```

---

## 🔧 설정 및 실행

### 1. 기본 실행
```bash
./node_exporter
```

기본적으로 다음 URL에서 메트릭 노출:
```
http://localhost:9100/metrics
```

---

### 2. 고급 옵션
```bash
./node_exporter \
  --web.listen-address=":9100" \
  --web.telemetry-path="/metrics" \
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+)($|/)" \
  --collector.netclass.ignored-devices="^(veth.*|docker.*|br-.*|lo)$" \
  --collector.diskstats.ignored-devices="^(ram|loop|fd)\\d+$" \
  --log.level=info \
  --log.format=logfmt
```

#### 주요 옵션 설명
| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--web.listen-address` | 리스닝 주소:포트 | `:9100` |
| `--web.telemetry-path` | 메트릭 경로 | `/metrics` |
| `--collector.filesystem.mount-points-exclude` | 제외할 마운트 포인트 (정규식) | - |
| `--collector.netclass.ignored-devices` | 제외할 네트워크 장치 (정규식) | - |
| `--collector.diskstats.ignored-devices` | 제외할 디스크 장치 (정규식) | - |
| `--log.level` | 로그 레벨 (debug, info, warn, error) | `info` |

---

### 3. Collector 활성화/비활성화

#### 기본 활성화된 Collector
- cpu
- diskstats
- filesystem
- loadavg
- meminfo
- netdev
- netstat
- stat
- time
- uname

#### 추가 Collector 활성화
```bash
./node_exporter \
  --collector.systemd \
  --collector.processes \
  --collector.tcpstat \
  --collector.hwmon
```

#### Collector 비활성화
```bash
./node_exporter \
  --no-collector.arp \
  --no-collector.bcache \
  --no-collector.bonding
```

---

## 🚀 시작/중지 스크립트

### `start.sh`
```bash
#!/bin/bash
cd "$(dirname "$0")"

./node_exporter \
  --web.listen-address=":9100" \
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|run|var/lib/docker)($|/)" \
  --collector.netclass.ignored-devices="^(veth.*|docker.*|br-.*|lo)$" \
  --log.level=info \
  > logs/node_exporter.log 2>&1 &

echo $! > .node_exporter.pid
echo "✅ Node Exporter started on http://localhost:9100"
```

### `stop.sh`
```bash
#!/bin/bash
if [ -f .node_exporter.pid ]; then
    kill $(cat .node_exporter.pid)
    rm .node_exporter.pid
    echo "✅ Node Exporter stopped"
fi
```

---

## 🔍 메트릭 확인

### 1. 브라우저로 확인
```
http://localhost:9100/metrics
```

### 2. curl로 확인
```bash
# 모든 메트릭 조회
curl http://localhost:9100/metrics

# CPU 메트릭만 필터링
curl http://localhost:9100/metrics | grep node_cpu

# 메모리 메트릭만 필터링
curl http://localhost:9100/metrics | grep node_memory

# 특정 메트릭 개수 확인
curl -s http://localhost:9100/metrics | grep -c "^node_"
```

### 3. 메트릭 샘플
```
# HELP node_cpu_seconds_total Seconds the CPUs spent in each mode.
# TYPE node_cpu_seconds_total counter
node_cpu_seconds_total{cpu="0",mode="idle"} 123456.78
node_cpu_seconds_total{cpu="0",mode="system"} 12345.67
node_cpu_seconds_total{cpu="0",mode="user"} 45678.90

# HELP node_memory_MemTotal_bytes Memory information field MemTotal_bytes.
# TYPE node_memory_MemTotal_bytes gauge
node_memory_MemTotal_bytes 274877906944

# HELP node_filesystem_size_bytes Filesystem size in bytes.
# TYPE node_filesystem_size_bytes gauge
node_filesystem_size_bytes{device="/dev/sda1",fstype="ext4",mountpoint="/"} 107374182400
```

---

## 📊 대시보드 통합

### Dashboard Backend에서 사용
```python
import requests

def get_cpu_usage():
    """Node Exporter에서 CPU 사용률 조회"""
    response = requests.get(
        'http://localhost:9090/api/v1/query',
        params={
            'query': '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
        }
    )
    data = response.json()
    return float(data['data']['result'][0]['value'][1])

def get_memory_usage():
    """Node Exporter에서 메모리 사용률 조회"""
    response = requests.get(
        'http://localhost:9090/api/v1/query',
        params={
            'query': '(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100'
        }
    )
    data = response.json()
    return float(data['data']['result'][0]['value'][1])
```

---

## 🔒 보안 고려사항

### 1. 네트워크 접근 제한
```bash
# 로컬호스트만 허용
./node_exporter --web.listen-address="127.0.0.1:9100"

# 특정 인터페이스만 허용
./node_exporter --web.listen-address="10.0.0.1:9100"
```

### 2. 방화벽 설정
```bash
# Prometheus 서버만 접근 허용
sudo ufw allow from 10.0.0.10 to any port 9100

# 특정 서브넷만 허용
sudo ufw allow from 10.0.0.0/24 to any port 9100
```

### 3. TLS 설정 (HTTPS)
```bash
./node_exporter \
  --web.config.file=web-config.yml
```

**web-config.yml**:
```yaml
tls_server_config:
  cert_file: server.crt
  key_file: server.key
  client_auth_type: RequireAndVerifyClientCert
  client_ca_file: ca.crt
```

---

## 🐛 문제 해결

### 1. 메트릭이 노출되지 않음
```bash
# Node Exporter 프로세스 확인
ps aux | grep node_exporter

# 포트 리스닝 확인
netstat -tlnp | grep 9100
# 또는
ss -tlnp | grep 9100

# 메트릭 직접 확인
curl http://localhost:9100/metrics
```

### 2. 특정 메트릭이 없음
```bash
# 활성화된 collector 확인
curl http://localhost:9100/metrics | grep "collector_"

# 수동으로 collector 활성화
./node_exporter --collector.systemd
```

### 3. Permission Denied 오류
```bash
# 실행 권한 추가
chmod +x node_exporter

# root 권한으로 실행 (일부 메트릭은 root 필요)
sudo ./node_exporter
```

### 4. 높은 메모리 사용
```bash
# 불필요한 collector 비활성화
./node_exporter \
  --no-collector.arp \
  --no-collector.bcache \
  --no-collector.bonding \
  --no-collector.infiniband

# 파일시스템 필터 추가
./node_exporter \
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|run)($|/)"
```

---

## 📊 성능 최적화

### 1. 불필요한 Collector 비활성화
```bash
./node_exporter \
  --no-collector.arp \
  --no-collector.bcache \
  --no-collector.bonding \
  --no-collector.infiniband \
  --no-collector.xfs \
  --no-collector.zfs
```

### 2. 파일시스템 필터링
```bash
./node_exporter \
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|run|snap|var/lib/docker)($|/)"
```

### 3. 네트워크 장치 필터링
```bash
./node_exporter \
  --collector.netclass.ignored-devices="^(veth.*|docker.*|br-.*|lo|cali.*|tunl.*)$"
```

---

## 📈 모니터링 Best Practices

### 1. 기본 메트릭 모니터링
```promql
# CPU 사용률
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 메모리 사용률
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 디스크 사용률
(1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100

# 네트워크 트래픽
rate(node_network_receive_bytes_total[5m]) + rate(node_network_transmit_bytes_total[5m])
```

### 2. 알림 설정
```yaml
# alerts.yml
groups:
  - name: node_exporter_alerts
    rules:
      - alert: HighCPU
        expr: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        annotations:
          summary: "High CPU usage detected"
      
      - alert: HighMemory
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
        for: 5m
        annotations:
          summary: "High memory usage detected"
      
      - alert: DiskFull
        expr: (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 > 85
        for: 10m
        annotations:
          summary: "Disk space running low"
```

---

## 🚀 추가 기능 로드맵

### Phase 1: 현재 구현 완료
- ✅ 기본 시스템 메트릭 수집
- ✅ CPU, 메모리, 디스크, 네트워크 모니터링
- ✅ Prometheus 통합

### Phase 2: 개선 예정
- 🔄 **Custom Collector**: Slurm 특화 메트릭
- 🔄 **Textfile Collector**: 외부 스크립트 메트릭
- 🔄 **Process Exporter**: 프로세스별 메트릭
- 🔄 **SNMP Exporter**: 네트워크 장비 모니터링

### Phase 3: 신규 기능
- 📋 **IPMI Exporter**: 하드웨어 센서 (온도, 팬 속도)
- 📋 **Smart Exporter**: 디스크 SMART 데이터
- 📋 **UPS Exporter**: UPS 상태 모니터링
- 📋 **Custom Metrics**: 사용자 정의 메트릭

---

## 📚 참고 자료
- [Node Exporter GitHub](https://github.com/prometheus/node_exporter)
- [Node Exporter 공식 문서](https://prometheus.io/docs/guides/node-exporter/)
- [PromQL 가이드](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Best Practices](https://prometheus.io/docs/practices/naming/)
