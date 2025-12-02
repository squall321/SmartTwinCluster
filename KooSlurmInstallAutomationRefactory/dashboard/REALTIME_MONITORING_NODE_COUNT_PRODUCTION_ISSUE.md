# Real-time Monitoring 노드 수 문제 조사 - Production 환경

## 문제 상황
**실제 Production 환경**에서:
- Cluster Management에서 **2개 노드 Apply**
- Real-time Monitoring에는 **1개만 표시**

## 문제 원인 분석

### Real-time Monitoring의 노드 카운팅 로직

#### 📍 `app.py` - `collect_real_metrics()` 함수
```python
def collect_real_metrics():
    """실제 시스템 메트릭 수집"""
    # sinfo로 노드 상태 파악
    result = get_sinfo('-h', '-o', '%T', timeout=5)
    
    node_states = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
    total_nodes = len(node_states)  # ← 여기서 카운트!
    idle_nodes = sum(1 for s in node_states if 'idle' in s.lower())
    allocated_nodes = sum(1 for s in node_states if 'alloc' in s.lower() or 'mix' in s.lower())
    down_nodes = sum(1 for s in node_states if 'down' in s.lower() or 'drain' in s.lower())
```

### 문제: `sinfo -h -o '%T'`의 출력 방식

#### sinfo 출력 형식의 문제
`sinfo -h -o '%T'` 명령은 **파티션별로 그룹화**하여 출력합니다.

**예시 출력:**
```bash
$ sinfo -h -o '%T'
idle          # ← 여러 노드를 한 줄로 표시
allocated     # ← 여러 노드를 한 줄로 표시
```

**실제 시나리오:**
```bash
# 2개 노드가 모두 idle 상태라면
$ sinfo -h -o '%T'
idle          # ← 2개 노드가 한 줄로 표시됨!

# 코드에서 처리
node_states = ['idle']  # ← 1개만 카운트!
total_nodes = len(node_states)  # = 1
```

**1개가 idle, 1개가 allocated라면:**
```bash
$ sinfo -h -o '%T'
idle
allocated

# 코드에서 처리
node_states = ['idle', 'allocated']  # ← 2개 카운트
total_nodes = len(node_states)  # = 2
```

### 근본 원인
- **`sinfo -h -o '%T'`는 상태별로 그룹화**하여 출력
- **같은 상태의 노드들은 한 줄로 합쳐짐**
- 따라서 **줄 수 != 노드 수**

## 올바른 해결 방법

### 옵션 1: 노드 개수를 명시적으로 출력
```python
def collect_real_metrics():
    # 각 상태별 노드 개수를 직접 파악
    result = get_sinfo('-h', '-o', '%D|%T', timeout=5)
    # %D = 노드 개수, %T = 상태
    
    # 출력 예시:
    # 2|idle
    # 1|allocated
    
    total_nodes = 0
    idle_nodes = 0
    allocated_nodes = 0
    down_nodes = 0
    
    for line in result.stdout.strip().split('\n'):
        if not line:
            continue
        parts = line.split('|')
        if len(parts) >= 2:
            count = int(parts[0])  # 노드 개수
            state = parts[1].strip().lower()
            
            total_nodes += count
            
            if 'idle' in state:
                idle_nodes += count
            elif 'alloc' in state or 'mix' in state:
                allocated_nodes += count
            elif 'down' in state or 'drain' in state:
                down_nodes += count
    
    return {
        'totalNodes': total_nodes,
        'idleNodes': idle_nodes,
        'allocatedNodes': allocated_nodes,
        'downNodes': down_nodes,
        # ...
    }
```

### 옵션 2: 노드 이름으로 카운트
```python
def collect_real_metrics():
    # 각 노드를 개별적으로 출력
    result = get_sinfo('-h', '-o', '%n|%T', timeout=5)
    # %n = 노드 이름, %T = 상태
    
    # 출력 예시:
    # node001|idle
    # node002|idle
    
    node_states = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
    total_nodes = len(node_states)  # ← 이제 정확!
    
    # 상태별 카운트
    idle_nodes = sum(1 for line in node_states if 'idle' in line.split('|')[1].lower())
    # ...
```

### 옵션 3: 파티션별 노드 개수
```python
def collect_real_metrics():
    # 파티션별로 노드 개수 확인
    result = get_sinfo('-h', '-o', '%P|%D|%T', timeout=5)
    # %P = 파티션, %D = 노드 개수, %T = 상태
    
    # 출력 예시:
    # group1|2|idle
    # group2|1|allocated
```

## 디버깅 방법

### 1. 실제 sinfo 출력 확인
```bash
# 서버에서 직접 실행
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# 현재 방식
/usr/local/slurm/bin/sinfo -h -o '%T'

# 권장 방식 1 (노드 개수 포함)
/usr/local/slurm/bin/sinfo -h -o '%D|%T'

# 권장 방식 2 (노드 이름별)
/usr/local/slurm/bin/sinfo -h -o '%n|%T'

# 권장 방식 3 (상세 정보)
/usr/local/slurm/bin/sinfo -h -o '%P|%D|%T|%N'
```

### 2. 백엔드 로그 확인
```bash
# 백엔드 로그에서 metrics 수집 시 출력 확인
tail -f /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/backend.log | grep "Real Metrics"
```

### 3. API 직접 호출
```bash
# Real-time Monitoring API 직접 호출
curl http://localhost:5010/api/metrics/realtime | jq

# 응답 확인
{
  "success": true,
  "mode": "production",
  "data": {
    "totalNodes": 1,  # ← 여기 확인
    "idleNodes": 1,
    "allocatedNodes": 0,
    ...
  }
}
```

## 예상되는 실제 상황

### 시나리오: 2개 노드가 모두 같은 상태
```bash
# Cluster Management에서 2개 노드 Apply
# 두 노드 모두 idle 상태

$ sinfo -h -o '%T'
idle          # ← 2개 노드가 한 줄로!

# 코드 처리
node_states = ['idle']
total_nodes = 1  # ← 잘못된 카운트!
```

### 시나리오: 2개 노드가 다른 상태
```bash
# 1개는 idle, 1개는 down

$ sinfo -h -o '%T'
idle
down

# 코드 처리
node_states = ['idle', 'down']
total_nodes = 2  # ← 정확!
```

## 확인이 필요한 사항

1. **실제 sinfo 출력**
   ```bash
   /usr/local/slurm/bin/sinfo -h -o '%T'
   ```
   → 몇 줄이 출력되는지?

2. **실제 노드 목록**
   ```bash
   /usr/local/slurm/bin/sinfo -h -o '%n'
   ```
   → 2개 노드가 표시되는지?

3. **파티션별 노드 수**
   ```bash
   /usr/local/slurm/bin/sinfo -h -o '%P|%D'
   ```
   → 각 파티션에 몇 개 노드가 있는지?

4. **백엔드 로그**
   ```bash
   tail -100 backend.log | grep "Real Metrics"
   ```
   → `Nodes=1` 또는 `Nodes=2`?

## 즉시 수정 필요
- ✅ **문제 확인 완료**: `sinfo -h -o '%T'`는 상태별로 그룹화
- ⏳ **수정 필요**: 노드 개수를 정확히 카운트하는 로직으로 변경
- ⏳ **테스트 필요**: 실제 환경에서 검증

## 다음 단계
1. 위의 디버깅 명령어 실행
2. 실제 출력 확인
3. 올바른 옵션 선택하여 수정
4. 테스트 및 검증
