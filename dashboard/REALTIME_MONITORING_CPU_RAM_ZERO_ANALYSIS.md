# Real-time Monitoring CPU/RAM 사용률 0% 문제 분석

## 현상
Real-time Monitoring에서 CPU와 RAM 사용률이 **항상 0%로 표시**

## 분석 결과

### 현재 CPU/RAM 계산 로직

#### 📍 `app.py` - `collect_real_metrics()` 함수
```python
# CPU 사용률 계산 (allocated + mixed 노드 비율)
cpu_usage = (allocated_nodes / total_nodes * 100) if total_nodes > 0 else 0

# 메모리 사용률 계산 (간단한 추정)
memory_usage = cpu_usage * 0.9  # CPU 사용률과 비례한다고 가정

# GPU 사용률 (sinfo에서 GRES 정보로 확인 가능, 여기서는 간단히 추정)
gpu_usage = cpu_usage * 0.7 if allocated_nodes > 0 else 0
```

### 🔴 문제의 핵심

**CPU 사용률 = (allocated_nodes / total_nodes) × 100**

이것은 **Slurm Job에 할당된 노드 비율**이지, **실제 CPU 사용률**이 아닙니다!

#### 시나리오 분석

##### Case 1: Job이 없는 경우 (현재 상황으로 추정)
```
total_nodes = 2
idle_nodes = 2
allocated_nodes = 0  # ← Job이 없으므로 0

cpu_usage = (0 / 2) × 100 = 0%  # ← 항상 0!
memory_usage = 0 × 0.9 = 0%
gpu_usage = 0 × 0.7 = 0%
```

##### Case 2: 1개 노드가 Job에 할당된 경우
```
total_nodes = 2
allocated_nodes = 1  # ← 1개 노드에 Job 실행 중

cpu_usage = (1 / 2) × 100 = 50%  # ← 노드 할당 비율!
memory_usage = 50 × 0.9 = 45%
```

##### Case 3: 2개 노드 모두 할당된 경우
```
total_nodes = 2
allocated_nodes = 2  # ← 모든 노드에 Job 실행 중

cpu_usage = (2 / 2) × 100 = 100%  # ← 노드 할당 비율!
memory_usage = 100 × 0.9 = 90%
```

### ⚠️ 의미의 혼동

| 현재 계산 | 의미 | 실제 원하는 값 |
|----------|------|--------------|
| `(allocated_nodes / total_nodes) × 100` | **Job에 할당된 노드 비율** | **실제 CPU 사용률** |
| 노드 단위 측정 | 노드가 할당되었는가? | CPU 코어가 사용 중인가? |

### 예시: 잘못된 표현

```
현재 상황:
- 2개 노드 모두 idle
- Job 없음

현재 표시:
- CPU Usage: 0% ✅ (Job 없으니 맞음)
- 하지만 의미가 "CPU 사용률"이 아니라 "노드 할당률"

만약 Job이 실행 중이라면:
- 1개 Job이 1개 노드의 10% CPU만 사용 중
- 현재 표시: CPU Usage 50% ← 틀림! (노드 할당률)
- 실제: CPU Usage 5% (전체 클러스터 기준)
```

## 두 가지 가능성

### 가능성 1: Job이 없어서 0%가 정상 ✅
```
상황:
- 2개 노드 모두 idle
- 실행 중인 Job 없음

결과:
- allocated_nodes = 0
- cpu_usage = 0%
- memory_usage = 0%

→ 이 경우 0%는 "정상"이지만, 
  "Job에 할당된 노드가 없다"는 의미이지
  "실제 CPU를 사용하지 않는다"는 의미는 아님
```

#### 확인 방법
```bash
# Job 확인
/usr/local/slurm/bin/squeue -h

# 노드 상태 확인
/usr/local/slurm/bin/sinfo -h -o '%n|%T'
```

**예상 출력 (Job 없음):**
```bash
$ squeue -h
(출력 없음)

$ sinfo -h -o '%n|%T'
node001|idle
node002|idle
```

### 가능성 2: 계산 로직이 실제 CPU 사용률과 무관 ⚠️
```
문제:
- 현재 로직은 "노드 할당률"만 계산
- 실제 CPU/RAM 사용률은 전혀 측정하지 않음

영향:
- Job이 실행 중이어도 실제 CPU를 얼마나 쓰는지 모름
- 노드가 할당되었지만 CPU를 거의 안 쓰는 경우 구분 불가
- 실제 시스템 부하와 표시된 값이 다를 수 있음
```

## 실제 CPU/RAM을 측정하려면?

### 옵션 1: Slurm의 CPU 사용량 정보 활용
```bash
# sinfo에서 CPU 정보 가져오기
sinfo -h -o '%C'
# 출력: Allocated/Idle/Other/Total
# 예: 128/128/0/256
```

```python
# 개선된 로직
result = get_sinfo('-h', '-o', '%C', timeout=5)
# 출력 예: 128/128/0/256

cpu_info = result.stdout.strip()
parts = cpu_info.split('/')
allocated_cpus = int(parts[0])
total_cpus = int(parts[3])

cpu_usage = (allocated_cpus / total_cpus * 100) if total_cpus > 0 else 0
```

**장점**: Slurm이 관리하는 CPU 정보 사용  
**단점**: 여전히 "할당된 CPU 비율"이지 "실제 사용률"은 아님

### 옵션 2: 각 노드에서 실제 CPU 사용률 수집
```python
import subprocess

def get_actual_cpu_usage(node):
    """각 노드의 실제 CPU 사용률 가져오기"""
    cmd = f"ssh {node} \"top -bn1 | grep 'Cpu(s)' | awk '{{print $2}}'\""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return float(result.stdout.strip().rstrip('%'))

# 모든 노드의 평균
total_cpu = 0
for node in ['node001', 'node002']:
    total_cpu += get_actual_cpu_usage(node)
avg_cpu_usage = total_cpu / 2
```

**장점**: 실제 CPU 사용률 측정  
**단점**: SSH 연결 필요, 성능 오버헤드

### 옵션 3: Node Exporter + Prometheus 연동 (권장)
```
이미 설치된 node_exporter_9100 활용:
- 각 노드에서 node_exporter가 실제 CPU/RAM 수집
- Prometheus가 메트릭 저장
- 백엔드에서 Prometheus API 쿼리
```

**장점**: 정확하고 확장 가능, 히스토리 저장  
**단점**: 이미 설치되어 있다면 단점 없음

### 옵션 4: `scontrol show node` 사용
```bash
# 노드별 상세 정보
scontrol show node node001

# 출력:
# CPUAlloc=0 CPUTot=128 CPULoad=0.05
# RealMemory=128000 AllocMem=0
```

```python
# 각 노드의 CPULoad 수집
def get_node_cpu_load(node):
    result = get_scontrol('show', 'node', node, timeout=5)
    # CPULoad= 파싱
    for line in result.stdout.split('\n'):
        if 'CPULoad' in line:
            # CPULoad=0.05 추출
            load = float(line.split('CPULoad=')[1].split()[0])
            return load
    return 0.0
```

**장점**: Slurm 기본 명령 사용  
**단점**: CPULoad는 load average (사용률과 다름)

## 현재 상태 요약

### 표시되는 값
```json
{
  "cpuUsage": 0,      // ← Job에 할당된 노드 비율
  "memoryUsage": 0,   // ← cpu_usage × 0.9 (추정치)
  "gpuUsage": 0       // ← cpu_usage × 0.7 (추정치)
}
```

### 실제 의미
- **cpuUsage**: Job에 의해 **할당(allocated)된 노드 비율**
  - NOT: 실제 CPU 사용률
  - NOT: 시스템 부하
- **memoryUsage**: CPU 할당률 기반 **추정치**
  - NOT: 실제 메모리 사용량
- **gpuUsage**: CPU 할당률 기반 **추정치**
  - NOT: 실제 GPU 사용률

### 0%가 표시되는 이유
```
가능성 1: Job이 없어서 (정상)
- allocated_nodes = 0
- 따라서 cpu_usage = 0%

가능성 2: 노드 상태 파악 오류
- sinfo가 제대로 동작하지 않음
- allocated_nodes를 잘못 카운트
```

## 디버깅 방법

### 1. 현재 노드 상태 확인
```bash
/usr/local/slurm/bin/sinfo -h -o '%n|%T'

# 예상 출력
node001|idle
node002|idle

# allocated가 있는지 확인
```

### 2. 실행 중인 Job 확인
```bash
/usr/local/slurm/bin/squeue -h

# Job이 있으면 출력됨
# 없으면 빈 출력
```

### 3. 백엔드 로그 확인
```bash
tail -f backend.log | grep "Real Metrics"

# 출력 예시:
# 📊 Real Metrics: Nodes=2, Jobs=0/0, CPU=0.0%
#                            ^^^^^^^^
#                            Job이 없음을 확인
```

### 4. API 직접 호출
```bash
curl http://localhost:5010/api/metrics/realtime | jq '.data'

{
  "cpuUsage": 0,
  "memoryUsage": 0,
  "activeJobs": 0,     # ← 0이면 Job 없음
  "allocatedNodes": 0   # ← 0이면 할당된 노드 없음
}
```

### 5. 실제 노드 CPU 확인 (시스템 레벨)
```bash
# 각 노드에 직접 접속해서 확인
ssh node001 "top -bn1 | grep 'Cpu(s)'"

# 출력:
# %Cpu(s):  5.2 us,  2.1 sy, ... ← 실제 CPU 사용률
```

## 결론

### 현재 상황 (추정)
```
✅ Real-time Monitoring이 0%를 표시하는 것은:
   → Job이 없어서 allocated_nodes = 0
   → 따라서 cpu_usage = 0%는 "정상"

⚠️  하지만 이것은:
   → "Job에 할당된 노드가 없다"는 의미
   → "실제 CPU/RAM을 사용하지 않는다"는 의미가 아님
```

### 표시값의 의미
- **Slurm Job 관련 지표만 표시**
  - ✅ Job에 할당된 노드 비율
  - ❌ 실제 시스템 CPU/RAM 사용률
  
- **Job이 없으면 항상 0%**
  - Job이 없으면: 0%
  - Job이 실행 중이면: 노드 할당 비율 표시
  
- **실제 CPU/RAM 사용률과는 다름**
  - 노드가 idle이어도 OS, 백그라운드 프로세스가 CPU 사용
  - 하지만 Slurm Job이 없으면 0%로 표시

## 다음 단계

### 확인 사항
1. **Job 실행 여부 확인**: `squeue -h`
2. **노드 상태 확인**: `sinfo -h -o '%n|%T'`
3. **실제 CPU 확인**: `ssh node001 top -bn1`

### 개선 방향 (선택)
1. **레이블 명확화**: "CPU Usage" → "Job CPU Allocation"
2. **실제 CPU 수집**: Node Exporter 데이터 활용
3. **두 값 모두 표시**: Job 할당률 + 실제 사용률

---

**날짜**: 2025-10-12  
**상태**: 분석 완료, 수정 대기
