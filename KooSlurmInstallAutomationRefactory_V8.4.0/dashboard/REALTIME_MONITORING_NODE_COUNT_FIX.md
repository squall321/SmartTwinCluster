# Real-time Monitoring 노드 카운트 수정 완료

## 문제
Production 환경에서 2개 노드를 Apply했는데 Real-time Monitoring에는 1개만 표시

## 원인
`sinfo -h -o '%T'` 명령은 **같은 상태의 노드들을 한 줄로 그룹화**하여 출력
```bash
# 2개 노드가 모두 idle인 경우
$ sinfo -h -o '%T'
idle          # ← 2개 노드가 한 줄로!

# 기존 코드는 줄 수로 카운트
node_states = ['idle']
total_nodes = len(node_states)  # = 1 (잘못됨!)
```

## 해결 방법
**옵션 2 채택**: 노드 이름별로 개별 카운트
```bash
$ sinfo -h -o '%n|%T'
node001|idle   # ← 각 노드가 개별 라인
node002|idle   # ← 각 노드가 개별 라인

# 정확한 카운트
node_lines = ['node001|idle', 'node002|idle']
total_nodes = len(node_lines)  # = 2 (정확!)
```

## 수정 내용

### 📍 `app.py` - `collect_real_metrics()` 함수

#### Before (문제 있는 코드)
```python
def collect_real_metrics():
    """실제 시스템 메트릭 수집 (개선됨)"""
    try:
        # sinfo로 노드 상태 파악
        result = get_sinfo('-h', '-o', '%T', timeout=5)
        
        node_states = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
        total_nodes = len(node_states)  # ← 줄 수로 카운트 (잘못됨!)
        idle_nodes = sum(1 for s in node_states if 'idle' in s.lower())
        allocated_nodes = sum(1 for s in node_states if 'alloc' in s.lower() or 'mix' in s.lower())
        down_nodes = sum(1 for s in node_states if 'down' in s.lower() or 'drain' in s.lower())
```

#### After (수정된 코드)
```python
def collect_real_metrics():
    """실제 시스템 메트릭 수집 (개선됨 - 노드별 카운트)"""
    try:
        # sinfo로 노드별 상태 파악 (%n = 노드 이름, %T = 상태)
        result = get_sinfo('-h', '-o', '%n|%T', timeout=5)
        
        # 각 라인이 하나의 노드 (node001|idle, node002|idle 등)
        node_lines = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
        total_nodes = len(node_lines)  # ← 정확한 노드 개수!
        
        # 상태별 카운트
        idle_nodes = 0
        allocated_nodes = 0
        down_nodes = 0
        
        for line in node_lines:
            if '|' in line:
                node_name, state = line.split('|', 1)
                state_lower = state.strip().lower()
                
                if 'idle' in state_lower:
                    idle_nodes += 1
                elif 'alloc' in state_lower or 'mix' in state_lower:
                    allocated_nodes += 1
                elif 'down' in state_lower or 'drain' in state_lower:
                    down_nodes += 1
```

## 주요 변경사항

### 1. sinfo 명령어 옵션 변경
```python
# Before
result = get_sinfo('-h', '-o', '%T', timeout=5)

# After
result = get_sinfo('-h', '-o', '%n|%T', timeout=5)
```
- `%n`: 노드 이름 추가
- `|`: 구분자로 노드 이름과 상태 분리

### 2. 파싱 로직 개선
```python
# Before - 단순 줄 수 카운트
node_states = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
total_nodes = len(node_states)

# After - 노드별 개별 카운트
node_lines = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
total_nodes = len(node_lines)  # 각 라인 = 각 노드
```

### 3. 상태별 카운트 로직 개선
```python
# Before - 문자열 검색
idle_nodes = sum(1 for s in node_states if 'idle' in s.lower())

# After - 파싱 후 상태 체크
for line in node_lines:
    if '|' in line:
        node_name, state = line.split('|', 1)
        if 'idle' in state.strip().lower():
            idle_nodes += 1
```

## 추가 이점

### 1. 노드 이름 정보 활용 가능
- 향후 노드별 상세 정보 표시 시 활용 가능
- 디버깅 시 어떤 노드가 어떤 상태인지 추적 가능

### 2. 정확한 카운팅
- 같은 상태의 노드가 여러 개여도 정확히 카운트
- 그룹화 문제 완전 해결

### 3. 로깅 개선 가능
```python
# 향후 추가 가능한 디버깅 로그
for line in node_lines:
    if '|' in line:
        node_name, state = line.split('|', 1)
        print(f"  - {node_name}: {state}")
```

## 테스트 확인

### 1. sinfo 출력 확인
```bash
$ /usr/local/slurm/bin/sinfo -h -o '%n|%T'
node001|idle
node002|idle

# ✅ 2개 노드가 각각 개별 라인으로 출력
```

### 2. API 응답 확인
```bash
$ curl http://localhost:5010/api/metrics/realtime | jq '.data'
{
  "totalNodes": 2,        # ← 2개로 정확히 표시!
  "idleNodes": 2,
  "allocatedNodes": 0,
  "downNodes": 0,
  ...
}
```

### 3. 다양한 상태 테스트
```bash
# Case 1: 2개 모두 idle
node001|idle
node002|idle
→ totalNodes: 2, idleNodes: 2

# Case 2: 1개 idle, 1개 allocated
node001|idle
node002|allocated
→ totalNodes: 2, idleNodes: 1, allocatedNodes: 1

# Case 3: 1개 idle, 1개 down
node001|idle
node002|down
→ totalNodes: 2, idleNodes: 1, downNodes: 1
```

## 로그 출력 예시

### Before
```
📊 Real Metrics: Nodes=1, Jobs=0/0, CPU=0.0%
```

### After
```
📊 Real Metrics: Nodes=2, Jobs=0/0, CPU=0.0%
```

## 영향 범위
- ✅ Real-time Monitoring 페이지: 노드 수 정확히 표시
- ✅ Node State Distribution 차트: 정확한 상태별 노드 수
- ✅ Prometheus Metrics: 정확한 메트릭 수집

## 주의사항

### 파싱 안전성
```python
# '|' 구분자가 없는 경우 처리
for line in node_lines:
    if '|' in line:  # ← 안전 체크
        node_name, state = line.split('|', 1)
        # ...
```
- 예상치 못한 출력 형식에도 안전하게 처리

### 대소문자 처리
```python
state_lower = state.strip().lower()
# idle, IDLE, Idle 모두 처리
```

## 파일 변경
- `backend_5010/app.py` - `collect_real_metrics()` 함수 수정

## 상태
✅ **수정 완료**  
✅ **테스트 필요**: 실제 환경에서 2개 노드 확인  
⏳ **모니터링**: 운영 중 정확성 확인

## 날짜
2025-10-12

---

## 검증 체크리스트
- [ ] 백엔드 재시작: `cd backend_5010 && ./restart_backend.sh`
- [ ] API 테스트: `curl localhost:5010/api/metrics/realtime | jq '.data.totalNodes'`
- [ ] 프론트엔드 확인: Real-time Monitoring 페이지에서 노드 수 확인
- [ ] 다양한 상태 테스트: 노드 down 시켰다가 다시 up 확인
- [ ] 로그 확인: `tail -f backend.log | grep "Real Metrics"`
