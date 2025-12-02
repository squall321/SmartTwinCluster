# WebSocket Server (Port 5011) - 기능 상세 문서

## 📋 개요
실시간 양방향 통신을 위한 WebSocket 서버로, 클라이언트에게 즉각적인 업데이트를 제공합니다.

**포트**: 5011  
**프로토콜**: WebSocket (ws://)  
**프레임워크**: Python websockets + asyncio  
**메시지 포맷**: JSON  

---

## 🏗️ 아키텍처

### 1. 서버 구조
```
websocket_5011/
├── websocket_server.py              # 기본 WebSocket 서버
├── websocket_server_enhanced.py     # 고급 기능 (채널, 브로드캐스트)
├── websocket_server_monitored.py    # 모니터링 및 로깅 강화
├── monitoring.py                    # Slurm 모니터링 로직
├── slurm_data_collector.py          # Slurm 데이터 수집
├── notifications_api.py             # 알림 브로드캐스트
└── database.py                      # 데이터베이스 연결 (공유)
```

### 2. 메시지 타입
```python
MessageType = Literal[
    'subscribe',      # 채널 구독
    'unsubscribe',    # 구독 해제
    'broadcast',      # 브로드캐스트
    'ping',           # 연결 유지
    'pong'            # Ping 응답
]
```

---

## 🔌 연결 및 통신

### 1. WebSocket 연결
```python
# 클라이언트 연결
ws = await websockets.connect('ws://localhost:5011')

# 메시지 수신
async for message in ws:
    data = json.loads(message)
    handle_message(data)

# 메시지 송신
await ws.send(json.dumps({
    'type': 'subscribe',
    'channel': 'jobs'
}))
```

### 2. 채널 시스템
클라이언트는 여러 채널을 구독하여 필터링된 메시지만 수신할 수 있습니다.

#### 사용 가능한 채널
| 채널 | 설명 | 업데이트 주기 |
|------|------|--------------|
| `jobs` | 작업 상태 변화 | 실시간 |
| `nodes` | 노드 상태 변화 | 5초 |
| `metrics` | 시스템 메트릭 | 15초 |
| `notifications` | 알림 메시지 | 실시간 |
| `alerts` | 긴급 알림 | 실시간 |

#### 채널 구독/해제
```python
# 구독
{
    "type": "subscribe",
    "channel": "jobs"
}

# 구독 해제
{
    "type": "unsubscribe",
    "channel": "jobs"
}

# 여러 채널 동시 구독
{
    "type": "subscribe",
    "channels": ["jobs", "nodes", "notifications"]
}
```

---

## 📡 실시간 데이터 업데이트

### 1. 작업 상태 모니터링 (`jobs` 채널)

#### 전송 메시지 구조
```json
{
  "channel": "jobs",
  "type": "job_update",
  "timestamp": "2025-10-10T14:30:00Z",
  "data": {
    "job_id": "12345",
    "name": "training_job",
    "status": "RUNNING",
    "previous_status": "PENDING",
    "user": "koopark",
    "partition": "gpu",
    "nodes": ["node001", "node002"],
    "start_time": "2025-10-10T14:25:00Z",
    "resources": {
      "cpus": 16,
      "memory": "64GB",
      "gpus": 2
    }
  }
}
```

#### 감지 이벤트
- 작업 제출 (PENDING)
- 작업 시작 (RUNNING)
- 작업 완료 (COMPLETED)
- 작업 실패 (FAILED)
- 작업 취소 (CANCELLED)

#### 구현
```python
async def monitor_jobs():
    """작업 상태 모니터링 및 브로드캐스트"""
    previous_jobs = {}
    
    while True:
        current_jobs = get_squeue()  # Slurm 작업 조회
        
        for job in current_jobs:
            job_id = job['JobId']
            current_status = job['State']
            
            # 상태 변화 감지
            if job_id in previous_jobs:
                prev_status = previous_jobs[job_id]['State']
                if prev_status != current_status:
                    # 상태 변화 브로드캐스트
                    await broadcast_to_channel('jobs', {
                        'type': 'job_update',
                        'data': {
                            'job_id': job_id,
                            'status': current_status,
                            'previous_status': prev_status,
                            **job
                        }
                    })
            
            previous_jobs[job_id] = job
        
        await asyncio.sleep(5)  # 5초마다 확인
```

---

### 2. 노드 상태 모니터링 (`nodes` 채널)

#### 전송 메시지 구조
```json
{
  "channel": "nodes",
  "type": "node_update",
  "timestamp": "2025-10-10T14:30:00Z",
  "data": {
    "node": "node001",
    "state": "IDLE",
    "previous_state": "ALLOCATED",
    "cpus": {
      "total": 64,
      "allocated": 0,
      "idle": 64
    },
    "memory": {
      "total": "256GB",
      "allocated": "0GB",
      "free": "256GB"
    },
    "gpus": {
      "total": 4,
      "allocated": 0,
      "idle": 4
    }
  }
}
```

#### 감지 이벤트
- 노드 상태 변화 (IDLE, ALLOCATED, DOWN, DRAIN)
- 리소스 사용량 변화
- 노드 추가/제거

---

### 3. 시스템 메트릭 (`metrics` 채널)

#### 전송 메시지 구조
```json
{
  "channel": "metrics",
  "type": "metrics_update",
  "timestamp": "2025-10-10T14:30:00Z",
  "data": {
    "cluster": {
      "cpu_usage": 65.5,
      "memory_usage": 72.3,
      "gpu_usage": 45.8
    },
    "nodes": [
      {
        "node": "node001",
        "cpu_usage": 85.2,
        "memory_usage": 78.4,
        "gpu_usage": 92.1
      }
    ]
  }
}
```

#### 모니터링 항목
- CPU 사용률
- 메모리 사용률
- GPU 사용률
- 네트워크 I/O
- 디스크 I/O

---

### 4. 알림 메시지 (`notifications` 채널)

#### 전송 메시지 구조
```json
{
  "channel": "notifications",
  "type": "notification",
  "timestamp": "2025-10-10T14:30:00Z",
  "data": {
    "id": "notif-001",
    "type": "job_completed",
    "title": "Job Completed",
    "message": "Job #12345 has finished successfully",
    "severity": "info",
    "read": false,
    "data": {
      "job_id": "12345",
      "duration": "2h 30m"
    }
  }
}
```

#### 알림 타입
- `job_completed`: 작업 완료
- `job_failed`: 작업 실패
- `alert`: 시스템 알림
- `system`: 시스템 공지
- `info`: 일반 정보

---

## 🔧 서버 구현

### 1. WebSocket 서버 (`websocket_server_enhanced.py`)

```python
import asyncio
import json
import websockets
from typing import Set, Dict, Any
from datetime import datetime

# 연결된 클라이언트 관리
clients: Set[websockets.WebSocketServerProtocol] = set()
subscriptions: Dict[str, Set[websockets.WebSocketServerProtocol]] = {
    'jobs': set(),
    'nodes': set(),
    'metrics': set(),
    'notifications': set(),
    'alerts': set()
}

async def handle_client(websocket: websockets.WebSocketServerProtocol):
    """클라이언트 연결 핸들러"""
    clients.add(websocket)
    print(f"✅ Client connected: {websocket.remote_address}")
    
    try:
        async for message in websocket:
            data = json.loads(message)
            await handle_message(websocket, data)
    
    except websockets.exceptions.ConnectionClosed:
        print(f"❌ Client disconnected: {websocket.remote_address}")
    
    finally:
        clients.remove(websocket)
        # 모든 구독 해제
        for channel in subscriptions.values():
            channel.discard(websocket)

async def handle_message(websocket: websockets.WebSocketServerProtocol, data: Dict[str, Any]):
    """메시지 처리"""
    msg_type = data.get('type')
    
    if msg_type == 'subscribe':
        channel = data.get('channel')
        if channel in subscriptions:
            subscriptions[channel].add(websocket)
            await websocket.send(json.dumps({
                'type': 'subscribed',
                'channel': channel,
                'message': f'Subscribed to {channel}'
            }))
    
    elif msg_type == 'unsubscribe':
        channel = data.get('channel')
        if channel in subscriptions:
            subscriptions[channel].discard(websocket)
            await websocket.send(json.dumps({
                'type': 'unsubscribed',
                'channel': channel,
                'message': f'Unsubscribed from {channel}'
            }))
    
    elif msg_type == 'ping':
        await websocket.send(json.dumps({'type': 'pong'}))

async def broadcast_to_channel(channel: str, message: Dict[str, Any]):
    """특정 채널 구독자에게 브로드캐스트"""
    if channel not in subscriptions:
        return
    
    message['channel'] = channel
    message['timestamp'] = datetime.now().isoformat()
    message_json = json.dumps(message)
    
    # 연결이 끊긴 클라이언트 제거
    disconnected = set()
    
    for websocket in subscriptions[channel]:
        try:
            await websocket.send(message_json)
        except websockets.exceptions.ConnectionClosed:
            disconnected.add(websocket)
    
    # 연결 끊긴 클라이언트 정리
    subscriptions[channel] -= disconnected

async def broadcast_to_all(message: Dict[str, Any]):
    """모든 클라이언트에게 브로드캐스트"""
    message['timestamp'] = datetime.now().isoformat()
    message_json = json.dumps(message)
    
    disconnected = set()
    
    for websocket in clients:
        try:
            await websocket.send(message_json)
        except websockets.exceptions.ConnectionClosed:
            disconnected.add(websocket)
    
    clients -= disconnected

async def start_monitoring_tasks():
    """모니터링 태스크 시작"""
    asyncio.create_task(monitor_jobs())
    asyncio.create_task(monitor_nodes())
    asyncio.create_task(monitor_metrics())

async def main():
    """서버 시작"""
    print("🚀 Starting WebSocket server on ws://localhost:5011")
    
    # 모니터링 태스크 시작
    await start_monitoring_tasks()
    
    # WebSocket 서버 시작
    async with websockets.serve(handle_client, "0.0.0.0", 5011):
        await asyncio.Future()  # 영구 실행

if __name__ == "__main__":
    asyncio.run(main())
```

---

### 2. HTTP API 엔드포인트

WebSocket 서버는 HTTP 엔드포인트도 제공하여 REST API로 브로드캐스트 가능합니다.

```python
from aiohttp import web

async def http_broadcast(request):
    """HTTP POST로 브로드캐스트"""
    data = await request.json()
    channel = data.get('channel', 'all')
    message = data.get('message', {})
    
    if channel == 'all':
        await broadcast_to_all(message)
    else:
        await broadcast_to_channel(channel, message)
    
    return web.json_response({'success': True})

async def http_health(request):
    """Health check"""
    return web.json_response({
        'status': 'healthy',
        'clients': len(clients),
        'subscriptions': {
            channel: len(subs) for channel, subs in subscriptions.items()
        }
    })

# HTTP 서버 설정
app = web.Application()
app.router.add_post('/broadcast', http_broadcast)
app.router.add_get('/health', http_health)

# HTTP 서버 실행 (별도 포트)
web.run_app(app, port=5012)
```

---

## 🔄 모니터링 로직

### 1. Slurm 작업 모니터링 (`monitoring.py`)

```python
from slurm_data_collector import SlurmDataCollector
import asyncio

collector = SlurmDataCollector()

async def monitor_jobs():
    """작업 상태 변화 감지 및 알림"""
    previous_jobs = {}
    
    while True:
        try:
            current_jobs = collector.get_jobs()
            
            # 새 작업 감지
            for job in current_jobs:
                job_id = job['job_id']
                
                if job_id not in previous_jobs:
                    # 새 작업 제출
                    await broadcast_to_channel('jobs', {
                        'type': 'job_submitted',
                        'data': job
                    })
                    
                    # 알림 생성
                    await broadcast_to_channel('notifications', {
                        'type': 'notification',
                        'data': {
                            'type': 'job_submitted',
                            'title': 'New Job Submitted',
                            'message': f'Job {job["name"]} has been submitted',
                            'data': job
                        }
                    })
                
                elif previous_jobs[job_id]['state'] != job['state']:
                    # 상태 변화
                    await broadcast_to_channel('jobs', {
                        'type': 'job_state_changed',
                        'data': {
                            **job,
                            'previous_state': previous_jobs[job_id]['state']
                        }
                    })
                    
                    # 완료/실패 시 알림
                    if job['state'] in ['COMPLETED', 'FAILED', 'CANCELLED']:
                        await broadcast_to_channel('notifications', {
                            'type': 'notification',
                            'data': {
                                'type': f'job_{job["state"].lower()}',
                                'title': f'Job {job["state"].title()}',
                                'message': f'Job {job["name"]} has {job["state"].lower()}',
                                'data': job
                            }
                        })
            
            previous_jobs = {job['job_id']: job for job in current_jobs}
            
        except Exception as e:
            print(f"❌ Job monitoring error: {e}")
        
        await asyncio.sleep(5)

async def monitor_nodes():
    """노드 상태 변화 감지"""
    previous_nodes = {}
    
    while True:
        try:
            current_nodes = collector.get_nodes()
            
            for node in current_nodes:
                node_name = node['name']
                
                if node_name in previous_nodes:
                    prev = previous_nodes[node_name]
                    
                    # 상태 변화
                    if prev['state'] != node['state']:
                        await broadcast_to_channel('nodes', {
                            'type': 'node_state_changed',
                            'data': {
                                **node,
                                'previous_state': prev['state']
                            }
                        })
                    
                    # 리소스 사용량 크게 변화
                    cpu_diff = abs(prev['cpu_usage'] - node['cpu_usage'])
                    if cpu_diff > 20:  # 20% 이상 변화
                        await broadcast_to_channel('nodes', {
                            'type': 'node_resource_change',
                            'data': node
                        })
            
            previous_nodes = {node['name']: node for node in current_nodes}
            
        except Exception as e:
            print(f"❌ Node monitoring error: {e}")
        
        await asyncio.sleep(10)

async def monitor_metrics():
    """시스템 메트릭 수집 및 브로드캐스트"""
    while True:
        try:
            metrics = collector.get_cluster_metrics()
            
            await broadcast_to_channel('metrics', {
                'type': 'metrics_update',
                'data': metrics
            })
            
            # 임계값 초과 시 알림
            if metrics['cluster']['cpu_usage'] > 90:
                await broadcast_to_channel('alerts', {
                    'type': 'alert',
                    'severity': 'warning',
                    'message': 'High CPU usage detected',
                    'data': {'cpu_usage': metrics['cluster']['cpu_usage']}
                })
            
        except Exception as e:
            print(f"❌ Metrics monitoring error: {e}")
        
        await asyncio.sleep(15)
```

---

### 2. Slurm 데이터 수집기 (`slurm_data_collector.py`)

```python
import subprocess
import json
from typing import List, Dict

class SlurmDataCollector:
    """Slurm 데이터 수집 유틸리티"""
    
    def get_jobs(self) -> List[Dict]:
        """모든 작업 조회"""
        try:
            result = subprocess.run(
                ['squeue', '-o', '%i|%j|%t|%u|%P|%D|%C|%m'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            lines = result.stdout.strip().split('\n')[1:]  # 헤더 제외
            jobs = []
            
            for line in lines:
                parts = line.split('|')
                if len(parts) >= 8:
                    jobs.append({
                        'job_id': parts[0],
                        'name': parts[1],
                        'state': parts[2],
                        'user': parts[3],
                        'partition': parts[4],
                        'nodes': int(parts[5]),
                        'cpus': int(parts[6]),
                        'memory': parts[7]
                    })
            
            return jobs
            
        except Exception as e:
            print(f"Error getting jobs: {e}")
            return []
    
    def get_nodes(self) -> List[Dict]:
        """모든 노드 조회"""
        try:
            result = subprocess.run(
                ['sinfo', '-N', '-o', '%N|%T|%c|%m|%G'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            lines = result.stdout.strip().split('\n')[1:]
            nodes = []
            
            for line in lines:
                parts = line.split('|')
                if len(parts) >= 5:
                    nodes.append({
                        'name': parts[0],
                        'state': parts[1],
                        'cpus': int(parts[2]),
                        'memory': parts[3],
                        'gpus': parts[4]
                    })
            
            return nodes
            
        except Exception as e:
            print(f"Error getting nodes: {e}")
            return []
    
    def get_cluster_metrics(self) -> Dict:
        """클러스터 전체 메트릭"""
        jobs = self.get_jobs()
        nodes = self.get_nodes()
        
        total_cpus = sum(n['cpus'] for n in nodes)
        allocated_cpus = sum(j['cpus'] for j in jobs if j['state'] == 'R')
        
        return {
            'cluster': {
                'cpu_usage': (allocated_cpus / total_cpus * 100) if total_cpus > 0 else 0,
                'total_jobs': len(jobs),
                'running_jobs': sum(1 for j in jobs if j['state'] == 'R'),
                'pending_jobs': sum(1 for j in jobs if j['state'] == 'PD'),
                'total_nodes': len(nodes),
                'idle_nodes': sum(1 for n in nodes if n['state'] == 'idle')
            },
            'nodes': nodes
        }
```

---

## 🧪 클라이언트 연동 예제

### JavaScript/TypeScript
```typescript
class WebSocketClient {
  private ws: WebSocket | null = null;
  private subscriptions: Map<string, Set<Function>> = new Map();
  
  connect(url: string = 'ws://localhost:5011') {
    this.ws = new WebSocket(url);
    
    this.ws.onopen = () => {
      console.log('✅ WebSocket connected');
    };
    
    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      this.handleMessage(data);
    };
    
    this.ws.onerror = (error) => {
      console.error('❌ WebSocket error:', error);
    };
    
    this.ws.onclose = () => {
      console.log('❌ WebSocket disconnected');
      // 재연결 로직
      setTimeout(() => this.connect(url), 5000);
    };
  }
  
  subscribe(channel: string, callback: Function) {
    // 구독 등록
    if (!this.subscriptions.has(channel)) {
      this.subscriptions.set(channel, new Set());
    }
    this.subscriptions.get(channel)!.add(callback);
    
    // 서버에 구독 요청
    this.send({
      type: 'subscribe',
      channel: channel
    });
  }
  
  unsubscribe(channel: string, callback?: Function) {
    if (callback) {
      this.subscriptions.get(channel)?.delete(callback);
    } else {
      this.subscriptions.delete(channel);
    }
    
    this.send({
      type: 'unsubscribe',
      channel: channel
    });
  }
  
  send(data: any) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }
  
  private handleMessage(data: any) {
    const channel = data.channel;
    const callbacks = this.subscriptions.get(channel);
    
    if (callbacks) {
      callbacks.forEach(callback => callback(data));
    }
  }
}

// 사용 예제
const wsClient = new WebSocketClient();
wsClient.connect();

// 작업 업데이트 구독
wsClient.subscribe('jobs', (data) => {
  console.log('Job update:', data);
  updateJobUI(data.data);
});

// 알림 구독
wsClient.subscribe('notifications', (data) => {
  console.log('Notification:', data);
  showNotification(data.data);
});
```

---

## 🔒 보안 고려사항

### 1. 인증
```python
async def authenticate(websocket: websockets.WebSocketServerProtocol):
    """WebSocket 연결 인증"""
    # 첫 메시지로 토큰 받기
    auth_message = await asyncio.wait_for(websocket.recv(), timeout=5.0)
    data = json.loads(auth_message)
    
    token = data.get('token')
    if not verify_token(token):
        await websocket.close(code=1008, reason="Authentication failed")
        return False
    
    return True
```

### 2. Rate Limiting
```python
from collections import defaultdict
from datetime import datetime, timedelta

message_counts = defaultdict(list)
MAX_MESSAGES_PER_MINUTE = 60

async def check_rate_limit(websocket: websockets.WebSocketServerProtocol) -> bool:
    """메시지 전송 속도 제한"""
    client_id = websocket.remote_address
    now = datetime.now()
    
    # 1분 이전 메시지 제거
    message_counts[client_id] = [
        ts for ts in message_counts[client_id]
        if now - ts < timedelta(minutes=1)
    ]
    
    if len(message_counts[client_id]) >= MAX_MESSAGES_PER_MINUTE:
        return False
    
    message_counts[client_id].append(now)
    return True
```

---

## 🚀 시작/중지 스크립트

### `start.sh`
```bash
#!/bin/bash
cd "$(dirname "$0")"

export MOCK_MODE=true
export PYTHONPATH="${PYTHONPATH}:$(pwd)"

source venv/bin/activate

python websocket_server_enhanced.py > websocket.log 2>&1 &
echo $! > .websocket.pid

echo "✅ WebSocket server started on ws://localhost:5011"
```

### `stop.sh`
```bash
#!/bin/bash
if [ -f .websocket.pid ]; then
    kill $(cat .websocket.pid)
    rm .websocket.pid
    echo "✅ WebSocket server stopped"
fi
```

---

## 📊 모니터링 및 디버깅

### 연결 상태 확인
```bash
curl http://localhost:5012/health
```

### 로그 확인
```bash
tail -f websocket.log
```

### 클라이언트 수 확인
```python
print(f"Connected clients: {len(clients)}")
for channel, subs in subscriptions.items():
    print(f"  {channel}: {len(subs)} subscribers")
```

---

## 🚀 추가 기능 로드맵

### Phase 1: 현재 구현 완료
- ✅ 채널 기반 구독 시스템
- ✅ 작업/노드 상태 모니터링
- ✅ 실시간 알림 브로드캐스트
- ✅ HTTP API 통합

### Phase 2: 개선 예정
- 🔄 **JWT 인증**: 토큰 기반 인증
- 🔄 **메시지 압축**: gzip 압축으로 대역폭 절약
- 🔄 **재연결 로직**: 자동 재연결 및 메시지 버퍼링
- 🔄 **클러스터링**: 여러 WebSocket 서버 간 메시지 동기화

### Phase 3: 신규 기능
- 📋 **Private 채널**: 사용자별 개인 채널
- 📋 **메시지 이력**: 최근 N개 메시지 캐싱
- 📋 **필터링**: 클라이언트 측 메시지 필터
- 📋 **Binary 전송**: 효율적인 데이터 전송

---

## 📚 참고 자료
- [websockets 라이브러리](https://websockets.readthedocs.io/)
- [asyncio 공식 문서](https://docs.python.org/3/library/asyncio.html)
- [WebSocket 프로토콜 RFC 6455](https://tools.ietf.org/html/rfc6455)
