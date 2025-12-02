# Real-time Monitoring과 Cluster Management 노드 수 싱크 문제 조사

## 문제 현상
Real-time Monitoring의 노드 수와 Cluster Management의 노드 수가 일치하지 않는 현상

## 조사 결과

### 1. Real-time Monitoring의 노드 수 출처

#### 📍 프론트엔드: `RealtimeMonitoring.tsx`
```typescript
// API 호출: /api/metrics/realtime
const response = await apiGet<{
  success: boolean;
  mode: string;
  data: RealtimeMetrics;
}>(API_ENDPOINTS.metrics);

// 받아오는 데이터
interface RealtimeMetrics {
  totalNodes: number;      // ← 전체 노드 수
  idleNodes: number;
  allocatedNodes: number;
  downNodes: number;
  // ...
}
```

#### 📍 백엔드: `app.py` - `/api/metrics/realtime` 엔드포인트

**Mock Mode:**
```python
if MOCK_MODE:
    metrics = {
        'totalNodes': 370,  # ← 하드코딩된 값!
        'idleNodes': random.randint(100, 150),
        'allocatedNodes': random.randint(200, 250),
        'downNodes': random.randint(0, 5),
    }
```

**Production Mode:**
```python
else:
    metrics = collect_real_metrics()
```

**`collect_real_metrics()` 함수:**
```python
def collect_real_metrics():
    """실제 시스템 메트릭 수집"""
    # sinfo로 노드 상태 파악
    result = get_sinfo('-h', '-o', '%T', timeout=5)
    
    node_states = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
    total_nodes = len(node_states)  # ← sinfo 출력 라인 수로 계산
    idle_nodes = sum(1 for s in node_states if 'idle' in s.lower())
    allocated_nodes = sum(1 for s in node_states if 'alloc' in s.lower() or 'mix' in s.lower())
    down_nodes = sum(1 for s in node_states if 'down' in s.lower() or 'drain' in s.lower())
    
    return {
        'totalNodes': total_nodes,  # ← sinfo 결과 기반
        # ...
    }
```

### 2. Cluster Management의 노드 수 출처

#### 📍 프론트엔드: Cluster Management UI
- 사용자가 직접 그룹별로 노드를 할당하여 구성
- 예시 구성:
  ```
  Group 1: 64 nodes
  Group 2: 64 nodes
  Group 3: 64 nodes
  Group 4: 100 nodes
  Group 5: 14 nodes
  Group 6: 64 nodes
  Total: 370 nodes (사용자 정의)
  ```

#### 📍 백엔드: `cluster_config_api.py`
```python
MOCK_GROUPS = [
    {'id': 1, 'name': 'Group 1', ...},  # 64 nodes
    {'id': 2, 'name': 'Group 2', ...},  # 64 nodes
    # ... 총 370 nodes
]

@cluster_config_bp.route('/config', methods=['GET'])
def get_cluster_config():
    # DB 또는 Mock 데이터에서 구성 반환
    return jsonify({
        'config': {
            'groups': MOCK_GROUPS,
            'totalNodes': 370  # ← 사용자 정의 또는 DB 저장 값
        }
    })
```

## 문제의 원인

### 🔴 원인 1: Mock Mode의 하드코딩
```python
# app.py - /api/metrics/realtime
if MOCK_MODE:
    metrics = {
        'totalNodes': 370,  # ← 하드코딩!
    }
```
- Mock 모드에서는 **하드코딩된 370**을 반환
- Cluster Management에서 사용자가 구성을 변경해도 반영되지 않음

### 🔴 원인 2: Production Mode의 sinfo 의존
```python
def collect_real_metrics():
    result = get_sinfo('-h', '-o', '%T', timeout=5)
    node_states = result.stdout.strip().split('\n')
    total_nodes = len(node_states)  # ← sinfo 출력 라인 수
```
- Production 모드에서는 **실제 Slurm의 sinfo 출력**을 기반으로 계산
- Cluster Management의 사용자 정의 구성과는 **완전히 독립적**
- **실제 Slurm 클러스터의 노드 수**를 반환

### 🔴 원인 3: 데이터 소스의 불일치

| 컴포넌트 | 데이터 소스 | 설명 |
|---------|-----------|------|
| **Real-time Monitoring (Mock)** | 하드코딩 (370) | 변경 불가 |
| **Real-time Monitoring (Production)** | `sinfo` 명령 | 실제 Slurm 상태 |
| **Cluster Management** | 사용자 입력 / DB | 사용자 정의 구성 |

**→ 세 가지가 모두 다른 소스를 사용하므로 싱크가 맞지 않음!**

## 구체적인 시나리오

### Scenario 1: Mock Mode
```
1. Cluster Management에서 총 400 nodes로 구성
   - Group 1: 100 nodes
   - Group 2: 100 nodes
   - ...
   - Total: 400 nodes

2. Real-time Monitoring 확인
   - Total Nodes: 370 ← 하드코딩된 값 표시
   
❌ 불일치: 400 vs 370
```

### Scenario 2: Production Mode
```
1. Cluster Management에서 총 400 nodes로 구성
   - 사용자가 의도한 구성

2. 실제 Slurm 클러스터
   - sinfo 출력: 370 nodes (실제 설치된 노드)
   
3. Real-time Monitoring 확인
   - Total Nodes: 370 ← sinfo 결과 표시
   
❌ 불일치: 400 (계획) vs 370 (실제)
```

### Scenario 3: Production Mode - 노드 추가/제거 후
```
1. Cluster Management 구성: 370 nodes

2. 실제 Slurm에서 노드 5개 다운
   - sinfo 출력: 365 nodes (UP 상태만 카운트한다면)
   
3. Real-time Monitoring 확인
   - Total Nodes: 365 ← 다운된 노드 제외
   
❌ 불일치: 370 (구성) vs 365 (실제)
```

## 데이터 플로우 비교

### Real-time Monitoring 데이터 플로우
```
Frontend (RealtimeMonitoring.tsx)
  ↓ GET /api/metrics/realtime
Backend (app.py)
  ↓
  ├─ Mock Mode → 하드코딩 (370)
  └─ Production Mode → collect_real_metrics()
                          ↓ sinfo 명령 실행
                       Slurm 클러스터 상태
```

### Cluster Management 데이터 플로우
```
Frontend (Cluster Management UI)
  ↓ GET /api/cluster/config
Backend (cluster_config_api.py)
  ↓
  ├─ Mock Mode → MOCK_GROUPS (하드코딩)
  └─ Production Mode → Database
                          ↓
                       사용자 저장 구성
```

## 설계상의 문제점

### 1. 의미의 차이
- **Real-time Monitoring의 totalNodes**: "지금 실제로 사용 가능한 노드 수"
- **Cluster Management의 totalNodes**: "계획/구성된 노드 수"

### 2. 목적의 차이
- **Real-time Monitoring**: 실시간 모니터링 (현재 상태)
- **Cluster Management**: 구성 관리 (계획/설정)

### 3. 싱크 메커니즘 부재
- 두 시스템 간에 **데이터를 동기화하는 로직이 전혀 없음**
- Cluster Management에서 구성 변경 시 Real-time Monitoring에 반영 안 됨
- Real-time Monitoring은 항상 sinfo (실제 상태)만 참조

## 예상되는 혼란 시나리오

### 사용자 관점
```
사용자: "Cluster Management에서 400개 노드로 설정했는데,
        Real-time Monitoring에는 370개로 나와요. 왜 다른가요?"

시스템 관점:
- Cluster Management: 사용자가 원하는 구성 (400)
- Real-time Monitoring (Mock): 하드코딩 (370)
- Real-time Monitoring (Prod): 실제 Slurm 상태 (370)
```

## 문제 요약

### Mock Mode
| 항목 | 값 | 출처 |
|-----|---|------|
| Cluster Management totalNodes | 사용자 정의 | 사용자 입력/DB |
| Real-time Monitoring totalNodes | 370 | **하드코딩** |
| 일치 여부 | ❌ | 우연히 둘 다 370이면 일치 |

### Production Mode
| 항목 | 값 | 출처 |
|-----|---|------|
| Cluster Management totalNodes | 사용자 정의 | 사용자 입력/DB |
| Real-time Monitoring totalNodes | 실제 노드 수 | **sinfo 명령** |
| 일치 여부 | ❌ | 구성과 실제가 다를 수 있음 |

## 권장 해결 방향 (수정 전 제안)

### 옵션 1: Real-time Monitoring이 Cluster Management 참조
```python
@app.route('/api/metrics/realtime', methods=['GET'])
def get_realtime_metrics():
    # Cluster Management 구성 가져오기
    cluster_config = get_cluster_config()  # cluster_config_api에서
    total_nodes = cluster_config['totalNodes']
    
    # 나머지는 실제 sinfo로 상태만 파악
    # ...
```
**장점**: 두 시스템이 동일한 totalNodes 표시  
**단점**: 실제 클러스터 상태와 다를 수 있음

### 옵션 2: Cluster Management가 Real-time Monitoring 참조
```python
@cluster_config_bp.route('/config', methods=['GET'])
def get_cluster_config():
    # 실제 sinfo로 노드 수 파악
    real_nodes = collect_real_metrics()['totalNodes']
    
    config['totalNodes'] = real_nodes  # 실제 값으로 덮어쓰기
    # ...
```
**장점**: 항상 실제 상태 반영  
**단점**: 사용자가 구성한 값과 다를 수 있음

### 옵션 3: 두 개념 분리
```json
{
  "plannedNodes": 400,      // Cluster Management의 계획
  "actualNodes": 370,       // Real-time Monitoring의 실제
  "difference": -30,
  "status": "under_planned"
}
```
**장점**: 명확한 구분, 불일치 인지 가능  
**단점**: UI에서 두 값을 모두 표시 필요

## 다음 단계
1. ✅ 문제 원인 파악 완료
2. ⏳ 수정 방향 결정 필요
3. ⏳ 수정 구현 대기

---

**날짜**: 2025-10-12  
**상태**: 조사 완료, 수정 대기
