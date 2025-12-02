# 실시간 로그 스트리밍 구현 가이드

**기능**: WebSocket 기반 실시간 Job 로그 스트리밍
**목표**: tail -f 같은 실시간 로그 모니터링 제공
**소요 시간**: 2-3일

---

## 📊 현재 상태 vs 목표

### 현재 (Before)
```
❌ 로그 확인 불가
❌ Job이 끝난 후에만 파일 다운로드
❌ 에러 발생 시 즉시 확인 불가
❌ 디버깅 어려움
```

### 목표 (After)
```
✅ 실시간 로그 스트리밍 (tail -f)
✅ 로그 필터링 (stdout/stderr 분리)
✅ 로그 검색 및 하이라이트
✅ 자동 스크롤 / 일시정지
✅ 로그 다운로드
✅ 여러 Job 동시 모니터링
```

---

## 🏗️ 시스템 아키텍처

```
┌─────────────┐         WebSocket          ┌─────────────┐
│  Frontend   │◄────────────────────────────│  Backend    │
│  (React)    │                             │  (Flask)    │
└─────────────┘                             └─────────────┘
      │                                            │
      │                                            │
      │                                            ▼
      │                                     ┌─────────────┐
      │                                     │  Log Tail   │
      │                                     │  Watcher    │
      │                                     └─────────────┘
      │                                            │
      │                                            ▼
      │                                     ┌─────────────┐
      │                                     │  Slurm Log  │
      └─────────────────────────────────────►   Files     │
         (Initial load + Download)          └─────────────┘
```

### 데이터 플로우
```
1. User opens Job detail page
   ↓
2. Frontend establishes WebSocket connection
   ↓
3. Backend starts tailing log file (tail -f)
   ↓
4. New log lines → WebSocket → Frontend
   ↓
5. Frontend displays in real-time
```

---

## 📁 파일 구조

```
dashboard/
├── backend_5010/
│   ├── log_streaming.py           # 신규 - WebSocket 핸들러
│   ├── log_watcher.py              # 신규 - 파일 tail 로직
│   └── app.py                      # 수정 - WebSocket 등록
│
├── frontend_3010/src/
│   ├── hooks/
│   │   └── useLogStreaming.ts     # 신규 - WebSocket hook
│   ├── components/
│   │   ├── JobLogs/
│   │   │   ├── LogViewer.tsx      # 신규 - 로그 뷰어 컴포넌트
│   │   │   ├── LogFilter.tsx      # 신규 - 필터 UI
│   │   │   ├── LogSearch.tsx      # 신규 - 검색 UI
│   │   │   └── index.ts
│   │   └── JobManagement.tsx      # 수정 - LogViewer 통합
│   └── utils/
│       └── logParser.ts            # 신규 - 로그 파싱 유틸
```

---

## 🔧 Backend 구현

### 1. Log Watcher (log_watcher.py)

```python
#!/usr/bin/env python3
"""
Log Watcher - Slurm Job 로그 파일 실시간 추적
"""

import os
import time
import threading
from pathlib import Path
from typing import Callable, Optional
import logging

logger = logging.getLogger(__name__)


class LogWatcher:
    """
    파일 tail -f 기능 구현
    """

    def __init__(self, log_path: str, callback: Callable[[str], None]):
        """
        Args:
            log_path: 로그 파일 경로
            callback: 새 라인이 발견되면 호출될 함수
        """
        self.log_path = Path(log_path)
        self.callback = callback
        self.running = False
        self.thread: Optional[threading.Thread] = None
        self.position = 0

    def start(self):
        """로그 감시 시작"""
        if self.running:
            logger.warning(f"LogWatcher already running for {self.log_path}")
            return

        self.running = True
        self.thread = threading.Thread(target=self._watch, daemon=True)
        self.thread.start()
        logger.info(f"Started watching log: {self.log_path}")

    def stop(self):
        """로그 감시 중지"""
        self.running = False
        if self.thread:
            self.thread.join(timeout=2.0)
        logger.info(f"Stopped watching log: {self.log_path}")

    def _watch(self):
        """메인 감시 루프"""
        # 파일이 생성될 때까지 대기 (최대 30초)
        wait_time = 0
        while not self.log_path.exists() and wait_time < 30:
            time.sleep(1)
            wait_time += 1

        if not self.log_path.exists():
            logger.error(f"Log file not found: {self.log_path}")
            return

        # 파일 열기 및 tail 시작
        with open(self.log_path, 'r', encoding='utf-8', errors='replace') as f:
            # 파일 끝으로 이동 (또는 처음부터 읽기)
            f.seek(0, os.SEEK_END)
            self.position = f.tell()

            while self.running:
                # 현재 위치 저장
                where = f.tell()

                # 새 라인 읽기
                line = f.readline()

                if line:
                    # 새 라인 발견 - callback 호출
                    self.callback(line.rstrip('\n'))
                else:
                    # 새 라인 없음 - 파일 크기 확인
                    time.sleep(0.5)

                    # 파일이 truncate되었는지 확인 (로그 로테이션)
                    f.seek(0, os.SEEK_END)
                    if f.tell() < where:
                        logger.info(f"Log file truncated, restarting from beginning")
                        f.seek(0)


class MultiLogWatcher:
    """
    여러 로그 파일 동시 감시 (stdout + stderr)
    """

    def __init__(self, job_id: str, log_dir: str, callback: Callable[[str, str], None]):
        """
        Args:
            job_id: Slurm Job ID
            log_dir: 로그 파일 디렉토리
            callback: (log_type, line) 형태로 호출
        """
        self.job_id = job_id
        self.log_dir = Path(log_dir)
        self.callback = callback

        # 로그 파일 경로
        self.stdout_path = self.log_dir / f"slurm-{job_id}.out"
        self.stderr_path = self.log_dir / f"slurm-{job_id}.err"

        # Watcher 인스턴스
        self.stdout_watcher: Optional[LogWatcher] = None
        self.stderr_watcher: Optional[LogWatcher] = None

    def start(self):
        """모든 로그 감시 시작"""
        # stdout watcher
        self.stdout_watcher = LogWatcher(
            str(self.stdout_path),
            lambda line: self.callback('stdout', line)
        )
        self.stdout_watcher.start()

        # stderr watcher
        self.stderr_watcher = LogWatcher(
            str(self.stderr_path),
            lambda line: self.callback('stderr', line)
        )
        self.stderr_watcher.start()

    def stop(self):
        """모든 로그 감시 중지"""
        if self.stdout_watcher:
            self.stdout_watcher.stop()
        if self.stderr_watcher:
            self.stderr_watcher.stop()

    def get_initial_logs(self, max_lines: int = 100) -> dict:
        """
        초기 로그 로드 (WebSocket 연결 시 최근 N줄)

        Returns:
            {
                'stdout': ['line1', 'line2', ...],
                'stderr': ['line1', 'line2', ...]
            }
        """
        result = {
            'stdout': [],
            'stderr': []
        }

        # stdout 읽기
        if self.stdout_path.exists():
            with open(self.stdout_path, 'r', encoding='utf-8', errors='replace') as f:
                lines = f.readlines()
                result['stdout'] = [line.rstrip('\n') for line in lines[-max_lines:]]

        # stderr 읽기
        if self.stderr_path.exists():
            with open(self.stderr_path, 'r', encoding='utf-8', errors='replace') as f:
                lines = f.readlines()
                result['stderr'] = [line.rstrip('\n') for line in lines[-max_lines:]]

        return result
```

---

### 2. WebSocket Handler (log_streaming.py)

```python
#!/usr/bin/env python3
"""
Log Streaming API - Flask-SocketIO WebSocket
"""

from flask import request
from flask_socketio import SocketIO, emit, join_room, leave_room, disconnect
from flask_jwt_extended import jwt_required, get_jwt_identity
import logging
from log_watcher import MultiLogWatcher

logger = logging.getLogger(__name__)

# SocketIO 인스턴스 (app.py에서 초기화)
socketio = None

# Active watchers: {room_id: MultiLogWatcher}
active_watchers = {}

# Slurm 로그 디렉토리
LOG_DIR = '/var/log/slurm'


def init_socketio(app):
    """SocketIO 초기화"""
    global socketio
    socketio = SocketIO(
        app,
        cors_allowed_origins="*",
        async_mode='threading',
        logger=True,
        engineio_logger=True
    )

    # Event handlers 등록
    socketio.on_event('connect', handle_connect)
    socketio.on_event('disconnect', handle_disconnect)
    socketio.on_event('subscribe_logs', handle_subscribe_logs)
    socketio.on_event('unsubscribe_logs', handle_unsubscribe_logs)

    return socketio


def handle_connect():
    """클라이언트 연결"""
    logger.info(f"Client connected: {request.sid}")
    emit('connected', {'message': 'Connected to log streaming server'})


def handle_disconnect():
    """클라이언트 연결 해제"""
    logger.info(f"Client disconnected: {request.sid}")

    # 이 클라이언트의 모든 watcher 정리
    cleanup_client_watchers(request.sid)


def handle_subscribe_logs(data):
    """
    로그 구독 시작

    Args:
        data: {
            'job_id': '12345',
            'include_initial': True  # 최근 100줄 포함 여부
        }
    """
    job_id = data.get('job_id')
    include_initial = data.get('include_initial', True)

    if not job_id:
        emit('error', {'message': 'job_id required'})
        return

    # JWT 검증 (optional - 보안 강화)
    # user_id = get_jwt_identity()

    logger.info(f"Client {request.sid} subscribing to job {job_id}")

    # Room ID 생성 (job_id 기반)
    room_id = f"job_{job_id}"
    join_room(room_id)

    # Watcher 생성 (같은 job에 여러 클라이언트가 연결 가능)
    watcher_key = f"{room_id}_{request.sid}"

    if watcher_key in active_watchers:
        logger.warning(f"Watcher already exists: {watcher_key}")
        return

    # Callback: 새 로그 라인 → WebSocket emit
    def log_callback(log_type: str, line: str):
        socketio.emit(
            'log_line',
            {
                'job_id': job_id,
                'type': log_type,
                'line': line,
                'timestamp': time.time()
            },
            room=room_id
        )

    # MultiLogWatcher 생성 및 시작
    watcher = MultiLogWatcher(job_id, LOG_DIR, log_callback)

    # 초기 로그 전송
    if include_initial:
        initial_logs = watcher.get_initial_logs(max_lines=100)
        emit('initial_logs', {
            'job_id': job_id,
            'stdout': initial_logs['stdout'],
            'stderr': initial_logs['stderr']
        })

    # Watcher 시작
    watcher.start()
    active_watchers[watcher_key] = watcher

    emit('subscribed', {'job_id': job_id, 'room': room_id})
    logger.info(f"Started watcher: {watcher_key}")


def handle_unsubscribe_logs(data):
    """
    로그 구독 중지

    Args:
        data: {'job_id': '12345'}
    """
    job_id = data.get('job_id')

    if not job_id:
        emit('error', {'message': 'job_id required'})
        return

    room_id = f"job_{job_id}"
    watcher_key = f"{room_id}_{request.sid}"

    # Watcher 중지 및 제거
    if watcher_key in active_watchers:
        active_watchers[watcher_key].stop()
        del active_watchers[watcher_key]
        logger.info(f"Stopped watcher: {watcher_key}")

    # Room 나가기
    leave_room(room_id)
    emit('unsubscribed', {'job_id': job_id})


def cleanup_client_watchers(client_sid: str):
    """클라이언트의 모든 watcher 정리"""
    keys_to_remove = [
        key for key in active_watchers.keys()
        if key.endswith(f"_{client_sid}")
    ]

    for key in keys_to_remove:
        active_watchers[key].stop()
        del active_watchers[key]
        logger.info(f"Cleaned up watcher: {key}")


# Health check endpoint
def get_active_watchers_count():
    """활성 watcher 개수 반환"""
    return len(active_watchers)
```

---

### 3. Flask App 통합 (app.py 수정)

```python
from flask import Flask
from flask_cors import CORS
from log_streaming import init_socketio, get_active_watchers_count

app = Flask(__name__)
CORS(app)

# ... 기존 설정 ...

# SocketIO 초기화
socketio = init_socketio(app)


# Health check
@app.route('/api/logs/health', methods=['GET'])
def log_streaming_health():
    return jsonify({
        'status': 'ok',
        'active_watchers': get_active_watchers_count()
    })


if __name__ == '__main__':
    # Development: SocketIO run
    socketio.run(
        app,
        host='0.0.0.0',
        port=5010,
        debug=True,
        use_reloader=False  # SocketIO와 호환 문제
    )
```

---

## 🎨 Frontend 구현

### 1. WebSocket Hook (useLogStreaming.ts)

```typescript
/**
 * useLogStreaming Hook
 *
 * WebSocket 기반 실시간 로그 스트리밍
 */

import { useState, useEffect, useRef, useCallback } from 'react';
import io, { Socket } from 'socket.io-client';

export interface LogLine {
  type: 'stdout' | 'stderr';
  line: string;
  timestamp: number;
  lineNumber?: number;
}

export interface UseLogStreamingOptions {
  jobId: string;
  autoConnect?: boolean;
  includeInitial?: boolean;
  maxLines?: number;  // 메모리 관리: 최대 라인 수
}

export interface UseLogStreamingReturn {
  logs: LogLine[];
  isConnected: boolean;
  isLoading: boolean;
  error: string | null;
  connect: () => void;
  disconnect: () => void;
  clear: () => void;
}

const SOCKET_URL = 'http://localhost:5010';  // Backend WebSocket URL

export function useLogStreaming({
  jobId,
  autoConnect = true,
  includeInitial = true,
  maxLines = 1000,
}: UseLogStreamingOptions): UseLogStreamingReturn {
  const [logs, setLogs] = useState<LogLine[]>([]);
  const [isConnected, setIsConnected] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const socketRef = useRef<Socket | null>(null);
  const lineNumberRef = useRef(0);

  // Connect to WebSocket
  const connect = useCallback(() => {
    if (socketRef.current?.connected) {
      console.log('Already connected');
      return;
    }

    setIsLoading(true);
    setError(null);

    // Socket.IO 연결
    const socket = io(SOCKET_URL, {
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionAttempts: 5,
      reconnectionDelay: 1000,
    });

    // Connection events
    socket.on('connect', () => {
      console.log(`Connected to log streaming server`);
      setIsConnected(true);
      setIsLoading(false);

      // 로그 구독
      socket.emit('subscribe_logs', {
        job_id: jobId,
        include_initial: includeInitial,
      });
    });

    socket.on('disconnect', () => {
      console.log('Disconnected from log streaming server');
      setIsConnected(false);
    });

    socket.on('connect_error', (err) => {
      console.error('Connection error:', err);
      setError(`Connection failed: ${err.message}`);
      setIsLoading(false);
    });

    // Log events
    socket.on('subscribed', (data) => {
      console.log('Subscribed to logs:', data);
    });

    socket.on('initial_logs', (data: { stdout: string[]; stderr: string[] }) => {
      console.log('Received initial logs');

      const initialLogs: LogLine[] = [];

      // stdout
      data.stdout.forEach((line) => {
        initialLogs.push({
          type: 'stdout',
          line,
          timestamp: Date.now(),
          lineNumber: lineNumberRef.current++,
        });
      });

      // stderr
      data.stderr.forEach((line) => {
        initialLogs.push({
          type: 'stderr',
          line,
          timestamp: Date.now(),
          lineNumber: lineNumberRef.current++,
        });
      });

      setLogs(initialLogs);
    });

    socket.on('log_line', (data: { type: 'stdout' | 'stderr'; line: string; timestamp: number }) => {
      const newLog: LogLine = {
        type: data.type,
        line: data.line,
        timestamp: data.timestamp,
        lineNumber: lineNumberRef.current++,
      };

      setLogs((prev) => {
        const updated = [...prev, newLog];

        // 메모리 관리: 최대 라인 수 제한
        if (updated.length > maxLines) {
          return updated.slice(-maxLines);
        }

        return updated;
      });
    });

    socket.on('error', (data) => {
      console.error('Socket error:', data);
      setError(data.message);
    });

    socketRef.current = socket;
  }, [jobId, includeInitial, maxLines]);

  // Disconnect from WebSocket
  const disconnect = useCallback(() => {
    if (socketRef.current) {
      socketRef.current.emit('unsubscribe_logs', { job_id: jobId });
      socketRef.current.disconnect();
      socketRef.current = null;
      setIsConnected(false);
    }
  }, [jobId]);

  // Clear logs
  const clear = useCallback(() => {
    setLogs([]);
    lineNumberRef.current = 0;
  }, []);

  // Auto-connect on mount
  useEffect(() => {
    if (autoConnect) {
      connect();
    }

    return () => {
      disconnect();
    };
  }, [autoConnect, connect, disconnect]);

  return {
    logs,
    isConnected,
    isLoading,
    error,
    connect,
    disconnect,
    clear,
  };
}
```

---

### 2. Log Viewer Component (LogViewer.tsx)

```typescript
/**
 * LogViewer Component
 *
 * 실시간 로그 표시 및 제어
 */

import React, { useState, useRef, useEffect } from 'react';
import { Play, Pause, Download, Trash2, Search, Filter } from 'lucide-react';
import { useLogStreaming, LogLine } from '../../hooks/useLogStreaming';

export interface LogViewerProps {
  jobId: string;
  height?: string;
}

export const LogViewer: React.FC<LogViewerProps> = ({
  jobId,
  height = '600px'
}) => {
  const { logs, isConnected, isLoading, error, connect, disconnect, clear } = useLogStreaming({
    jobId,
    autoConnect: true,
    includeInitial: true,
    maxLines: 1000,
  });

  const [autoScroll, setAutoScroll] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterType, setFilterType] = useState<'all' | 'stdout' | 'stderr'>('all');

  const logContainerRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom
  useEffect(() => {
    if (autoScroll && logContainerRef.current) {
      logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  // Filter logs
  const filteredLogs = logs.filter((log) => {
    // Type filter
    if (filterType !== 'all' && log.type !== filterType) {
      return false;
    }

    // Search filter
    if (searchTerm && !log.line.toLowerCase().includes(searchTerm.toLowerCase())) {
      return false;
    }

    return true;
  });

  // Download logs
  const handleDownload = () => {
    const content = filteredLogs.map((log) => `[${log.type}] ${log.line}`).join('\n');
    const blob = new Blob([content], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `job-${jobId}-logs.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // Highlight search term
  const highlightLine = (line: string) => {
    if (!searchTerm) return line;

    const regex = new RegExp(`(${searchTerm})`, 'gi');
    return line.replace(regex, '<mark class="bg-yellow-300">$1</mark>');
  };

  return (
    <div className="flex flex-col h-full border border-gray-300 rounded-lg overflow-hidden">
      {/* Header */}
      <div className="bg-gray-800 text-white px-4 py-2 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <h3 className="font-semibold">Job #{jobId} Logs</h3>
          <div className="flex items-center gap-1">
            {isConnected ? (
              <span className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
            ) : (
              <span className="w-2 h-2 bg-red-400 rounded-full"></span>
            )}
            <span className="text-xs">
              {isLoading ? 'Connecting...' : isConnected ? 'Live' : 'Disconnected'}
            </span>
          </div>
          <span className="text-xs text-gray-400">{filteredLogs.length} lines</span>
        </div>

        {/* Controls */}
        <div className="flex items-center gap-2">
          {/* Search */}
          <div className="relative">
            <input
              type="text"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder="Search..."
              className="text-sm px-3 py-1 pl-8 bg-gray-700 text-white rounded border-none focus:ring-2 focus:ring-blue-500"
            />
            <Search className="w-4 h-4 absolute left-2 top-1/2 -translate-y-1/2 text-gray-400" />
          </div>

          {/* Filter */}
          <select
            value={filterType}
            onChange={(e) => setFilterType(e.target.value as any)}
            className="text-sm px-2 py-1 bg-gray-700 text-white rounded border-none"
          >
            <option value="all">All</option>
            <option value="stdout">stdout</option>
            <option value="stderr">stderr</option>
          </select>

          {/* Auto-scroll toggle */}
          <button
            onClick={() => setAutoScroll(!autoScroll)}
            className={`px-2 py-1 rounded text-sm ${
              autoScroll ? 'bg-blue-600' : 'bg-gray-700'
            }`}
            title={autoScroll ? 'Disable auto-scroll' : 'Enable auto-scroll'}
          >
            {autoScroll ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
          </button>

          {/* Download */}
          <button
            onClick={handleDownload}
            className="px-2 py-1 bg-gray-700 rounded text-sm hover:bg-gray-600"
            title="Download logs"
          >
            <Download className="w-4 h-4" />
          </button>

          {/* Clear */}
          <button
            onClick={clear}
            className="px-2 py-1 bg-gray-700 rounded text-sm hover:bg-gray-600"
            title="Clear logs"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="bg-red-100 border-l-4 border-red-500 text-red-700 p-2 text-sm">
          {error}
        </div>
      )}

      {/* Log content */}
      <div
        ref={logContainerRef}
        className="flex-1 overflow-y-auto bg-gray-900 text-gray-100 font-mono text-sm p-2"
        style={{ height }}
      >
        {filteredLogs.length === 0 ? (
          <div className="text-gray-500 text-center py-8">
            {isLoading ? 'Loading logs...' : 'No logs available'}
          </div>
        ) : (
          filteredLogs.map((log, index) => (
            <div
              key={`${log.lineNumber}-${index}`}
              className={`py-0.5 px-1 ${
                log.type === 'stderr' ? 'text-red-400' : 'text-green-400'
              }`}
            >
              <span className="text-gray-600 mr-2 select-none">{log.lineNumber}│</span>
              <span dangerouslySetInnerHTML={{ __html: highlightLine(log.line) }} />
            </div>
          ))
        )}
      </div>

      {/* Footer */}
      <div className="bg-gray-800 text-white px-4 py-1 text-xs flex items-center justify-between">
        <span>
          Auto-scroll: {autoScroll ? 'ON' : 'OFF'} |
          Filter: {filterType} |
          Showing: {filteredLogs.length} / {logs.length}
        </span>
        {searchTerm && (
          <span className="text-yellow-400">
            Searching for: "{searchTerm}"
          </span>
        )}
      </div>
    </div>
  );
};
```

---

## 🔧 설치 및 설정

### Backend 패키지 설치

```bash
cd dashboard/backend_5010

# Flask-SocketIO 설치
pip install flask-socketio python-socketio

# requirements.txt에 추가
echo "flask-socketio==5.3.6" >> requirements.txt
echo "python-socketio==5.11.0" >> requirements.txt
```

### Frontend 패키지 설치

```bash
cd dashboard/frontend_3010

# Socket.IO client 설치
npm install socket.io-client

# package.json 확인
```

---

## 🧪 테스트

### 1. Backend 테스트

```bash
# Backend 실행
python app.py

# 다른 터미널에서 WebSocket 테스트
python -c "
import socketio

sio = socketio.Client()

@sio.on('connected')
def on_connect(data):
    print('Connected:', data)
    sio.emit('subscribe_logs', {'job_id': '12345'})

@sio.on('log_line')
def on_log(data):
    print(f'[{data["type"]}] {data["line"]}')

sio.connect('http://localhost:5010')
sio.wait()
"
```

### 2. Frontend 테스트

```typescript
// JobManagement.tsx에 추가
import { LogViewer } from './JobLogs/LogViewer';

// Job 상세 모달에 LogViewer 추가
{selectedJob && (
  <div className="mt-4">
    <LogViewer jobId={selectedJob.jobId} height="400px" />
  </div>
)}
```

---

## 📊 성능 최적화

### 1. 메모리 관리
```typescript
// maxLines 설정으로 메모리 제한
const { logs } = useLogStreaming({
  jobId,
  maxLines: 1000,  // 최근 1000줄만 유지
});
```

### 2. 로그 버퍼링
```python
# Backend: 로그를 버퍼링해서 전송 (N줄마다)
class BufferedLogWatcher:
    def __init__(self, buffer_size=10):
        self.buffer = []
        self.buffer_size = buffer_size

    def add_line(self, line):
        self.buffer.append(line)
        if len(self.buffer) >= self.buffer_size:
            self.flush()

    def flush(self):
        if self.buffer:
            socketio.emit('log_batch', {'lines': self.buffer})
            self.buffer = []
```

### 3. Reconnection 처리
```typescript
// Frontend: 재연결 시 마지막 line number부터
socket.on('reconnect', () => {
  socket.emit('subscribe_logs', {
    job_id: jobId,
    from_line: lastLineNumber,
  });
});
```

---

## 🎯 사용 시나리오

### 시나리오 1: 실시간 디버깅
```
1. Job 제출
2. Job Management 페이지에서 Job 클릭
3. LogViewer 자동 열림 + 실시간 스트리밍 시작
4. 에러 발생 시 즉시 확인
5. 필요시 Job 취소
```

### 시나리오 2: 여러 Job 동시 모니터링
```
1. Job 여러 개 실행 중
2. 각 Job의 LogViewer 탭으로 열기
3. 각 탭에서 독립적으로 로그 스트리밍
4. 에러 발생한 Job만 필터링해서 확인
```

### 시나리오 3: 로그 검색 및 분석
```
1. Job 완료 후 LogViewer 열기
2. Search: "error" 입력 → 에러만 하이라이트
3. Filter: stderr만 표시
4. Download 버튼으로 전체 로그 저장
```

---

## ✅ 완료 체크리스트

- [ ] Backend log_watcher.py 작성
- [ ] Backend log_streaming.py 작성
- [ ] Backend app.py SocketIO 통합
- [ ] Frontend useLogStreaming hook 작성
- [ ] Frontend LogViewer component 작성
- [ ] JobManagement에 LogViewer 통합
- [ ] 테스트 (단일 Job)
- [ ] 테스트 (여러 Job 동시)
- [ ] 성능 테스트 (대용량 로그)
- [ ] 문서화

---

**구현 시간**: 2-3일
**난이도**: 중급
**ROI**: 매우 높음 (사용자 경험 대폭 향상)
