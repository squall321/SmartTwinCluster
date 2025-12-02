# App Framework 통합 가이드

**버전**: 0.5.0
**작성일**: 2025-10-24
**대상**: 다른 프론트엔드 개발자

---

## 📋 목차

1. [개요](#개요)
2. [통합 방법 비교](#통합-방법-비교)
3. [방법 1: REST API 직접 호출](#방법-1-rest-api-직접-호출)
4. [방법 2: React 컴포넌트 임베딩](#방법-2-react-컴포넌트-임베딩)
5. [방법 3: iframe 임베딩](#방법-3-iframe-임베딩)
6. [API 레퍼런스](#api-레퍼런스)
7. [실전 예시](#실전-예시)
8. [트러블슈팅](#트러블슈팅)

---

## 개요

App Framework는 Apptainer 컨테이너로 패키징된 리눅스 네이티브 애플리케이션(GEdit, ParaView 등)을 웹 브라우저에서 실행할 수 있게 해주는 프레임워크입니다.

### 주요 기능

- ✅ Apptainer 컨테이너 기반 앱 실행
- ✅ Slurm 워크로드 매니저를 통한 작업 분산
- ✅ noVNC를 통한 브라우저 내 GUI 표시
- ✅ 세션 관리 (생성, 조회, 삭제, 재시작)
- ✅ 여러 프론트엔드에서 통합 가능

### 아키텍처

```
Your Frontend → REST API → Backend (5000) → Slurm → viz-node001
                                                           ↓
                                                    Apptainer Container
                                                           ↓
                                                    VNC + websockify
                                                           ↓
Your Frontend ← WebSocket (noVNC) ←────────────────────────┘
```

---

## 통합 방법 비교

| 방법 | 적용 대상 | 난이도 | 유연성 | 제어 수준 | 추천 대상 |
|------|----------|--------|--------|----------|----------|
| **REST API** | 모든 프론트엔드 | ⭐ 쉬움 | ⭐⭐⭐ 높음 | ⭐⭐⭐ 높음 | 일반적인 경우 |
| **React 컴포넌트** | React only | ⭐⭐ 중간 | ⭐⭐ 중간 | ⭐⭐ 중간 | React 프로젝트 |
| **iframe** | 모든 프론트엔드 | ⭐ 쉬움 | ⭐ 낮음 | ⭐ 낮음 | 빠른 프로토타입 |

### 권장 사항

- **일반적인 경우**: REST API 직접 호출 (완전한 제어)
- **React 프로젝트**: React 컴포넌트 임베딩 (개발 속도)
- **빠른 테스트**: iframe 임베딩 (최소 코드)

---

## 방법 1: REST API 직접 호출

**가장 유연하고 강력한 방법**입니다. 어떤 프론트엔드 프레임워크에서도 사용 가능하며, 완전한 제어가 가능합니다.

### 1-1. 기본 플로우

```typescript
// ===== 전체 플로우 =====
// 1. 세션 생성 (POST /api/app/sessions)
// 2. 세션 상태 폴링 (GET /api/app/sessions/:id) - running 될 때까지
// 3. displayUrl 획득 (ws://node_ip:port)
// 4. noVNC 클라이언트로 연결
// 5. 화면 표시
```

### 1-2. TypeScript 전체 코드

```typescript
import RFB from '@novnc/novnc/core/rfb.js';

interface AppSession {
  id: string;
  session_id?: string; // Backend에 따라 다를 수 있음
  status: 'creating' | 'pending' | 'running' | 'stopped' | 'failed';
  displayUrl: string | null;
  node_ip: string | null;
  vnc_port: number;
  appId: string;
  appName: string;
}

/**
 * App Framework API 클라이언트
 */
class AppFrameworkAPI {
  private baseURL: string;
  private authToken: string | null = null;

  constructor(baseURL: string = 'http://110.15.177.120/cae/api/app') {
    this.baseURL = baseURL;
  }

  /**
   * 인증 토큰 설정 (선택사항)
   */
  setAuthToken(token: string) {
    this.authToken = token;
  }

  /**
   * HTTP 요청 헬퍼
   */
  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const headers: HeadersInit = {
      'Content-Type': 'application/json',
      ...(this.authToken && { 'Authorization': `Bearer ${this.authToken}` })
    };

    const response = await fetch(`${this.baseURL}${endpoint}`, {
      ...options,
      headers: { ...headers, ...options.headers }
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    return response.json();
  }

  /**
   * 1. 앱 목록 조회
   */
  async listApps() {
    const data = await this.request<any>('/apps');
    return data.apps || data;
  }

  /**
   * 2. 세션 생성
   */
  async createSession(appId: string, userId: string): Promise<AppSession> {
    const data = await this.request<any>('/sessions', {
      method: 'POST',
      body: JSON.stringify({ app_id: appId, user_id: userId })
    });
    const session = data.session || data;

    // Backend 응답 정규화
    if (session.id && !session.session_id) {
      session.session_id = session.id;
    }

    return session;
  }

  /**
   * 3. 세션 조회
   */
  async getSession(sessionId: string): Promise<AppSession> {
    const data = await this.request<any>(`/sessions/${sessionId}`);
    const session = data.session || data;

    // Backend 응답 정규화
    if (session.id && !session.session_id) {
      session.session_id = session.id;
    }

    return session;
  }

  /**
   * 4. 세션 목록 조회
   */
  async listSessions(): Promise<AppSession[]> {
    const data = await this.request<any>('/sessions');
    return data.sessions || data;
  }

  /**
   * 5. 세션 삭제
   */
  async deleteSession(sessionId: string): Promise<void> {
    await this.request(`/sessions/${sessionId}`, { method: 'DELETE' });
  }

  /**
   * 6. 세션 재시작
   */
  async restartSession(sessionId: string): Promise<AppSession> {
    const data = await this.request<any>(`/sessions/${sessionId}/restart`, {
      method: 'POST'
    });
    return data.session || data;
  }

  /**
   * 7. 세션이 Running 상태가 될 때까지 대기
   */
  async waitForSessionRunning(
    sessionId: string,
    timeoutSeconds: number = 60
  ): Promise<AppSession> {
    for (let i = 0; i < timeoutSeconds; i++) {
      await new Promise(resolve => setTimeout(resolve, 1000));

      const session = await this.getSession(sessionId);

      console.log(`[${i+1}s] Session status: ${session.status}`);

      if (session.status === 'running' && session.displayUrl) {
        return session;
      }

      if (session.status === 'failed') {
        throw new Error('Session failed to start');
      }
    }

    throw new Error('Timeout waiting for session to be running');
  }
}

/**
 * noVNC 연결 관리자
 */
class VNCConnection {
  private rfb: any = null;
  private canvas: HTMLCanvasElement;
  private onConnect?: () => void;
  private onDisconnect?: () => void;

  constructor(
    canvas: HTMLCanvasElement,
    options?: {
      onConnect?: () => void;
      onDisconnect?: () => void;
    }
  ) {
    this.canvas = canvas;
    this.onConnect = options?.onConnect;
    this.onDisconnect = options?.onDisconnect;
  }

  /**
   * VNC 연결
   */
  async connect(displayUrl: string) {
    // noVNC 동적 import
    const { default: RFB } = await import('@novnc/novnc/core/rfb.js');

    this.rfb = new RFB(this.canvas, displayUrl, {
      credentials: { password: '' }
    });

    // 이벤트 리스너
    this.rfb.addEventListener('connect', () => {
      console.log('VNC connected');
      this.onConnect?.();
    });

    this.rfb.addEventListener('disconnect', () => {
      console.log('VNC disconnected');
      this.onDisconnect?.();
    });

    // 화면 크기 자동 조정
    this.rfb.scaleViewport = true;
    this.rfb.resizeSession = true;

    return this.rfb;
  }

  /**
   * VNC 연결 해제
   */
  disconnect() {
    if (this.rfb) {
      this.rfb.disconnect();
      this.rfb = null;
    }
  }

  /**
   * 클립보드 텍스트 전송
   */
  sendClipboard(text: string) {
    if (this.rfb) {
      this.rfb.clipboardPasteFrom(text);
    }
  }

  /**
   * 키 이벤트 전송
   */
  sendKey(keysym: number, down: boolean = true) {
    if (this.rfb) {
      this.rfb.sendKey(keysym, down);
    }
  }
}

/**
 * 고수준 App 런처
 */
export class AppLauncher {
  private api: AppFrameworkAPI;
  private vncConnection: VNCConnection | null = null;

  constructor(apiBaseURL?: string) {
    this.api = new AppFrameworkAPI(apiBaseURL);
  }

  /**
   * 인증 토큰 설정
   */
  setAuthToken(token: string) {
    this.api.setAuthToken(token);
  }

  /**
   * 앱 실행 (전체 플로우)
   */
  async launchApp(
    appId: string,
    userId: string,
    canvas: HTMLCanvasElement,
    options?: {
      onSessionCreated?: (sessionId: string) => void;
      onSessionRunning?: (session: AppSession) => void;
      onVNCConnected?: () => void;
      onVNCDisconnected?: () => void;
    }
  ): Promise<{ session: AppSession; vnc: VNCConnection }> {
    try {
      // 1. 세션 생성
      console.log(`Creating session for app: ${appId}`);
      const session = await this.api.createSession(appId, userId);
      const sessionId = session.session_id || session.id;

      console.log(`Session created: ${sessionId}`);
      options?.onSessionCreated?.(sessionId);

      // 2. Running 상태 대기
      console.log('Waiting for session to be running...');
      const runningSession = await this.api.waitForSessionRunning(sessionId);

      console.log(`Session is running. VNC URL: ${runningSession.displayUrl}`);
      options?.onSessionRunning?.(runningSession);

      // 3. noVNC 연결
      console.log('Connecting to VNC...');
      this.vncConnection = new VNCConnection(canvas, {
        onConnect: options?.onVNCConnected,
        onDisconnect: options?.onVNCDisconnected
      });

      await this.vncConnection.connect(runningSession.displayUrl!);

      return {
        session: runningSession,
        vnc: this.vncConnection
      };
    } catch (error) {
      console.error('Failed to launch app:', error);
      throw error;
    }
  }

  /**
   * 앱 종료
   */
  async stopApp(sessionId: string) {
    if (this.vncConnection) {
      this.vncConnection.disconnect();
      this.vncConnection = null;
    }

    await this.api.deleteSession(sessionId);
  }

  /**
   * 앱 목록 조회
   */
  async getAvailableApps() {
    return this.api.listApps();
  }

  /**
   * 실행 중인 세션 목록
   */
  async getRunningSessions() {
    return this.api.listSessions();
  }
}
```

### 1-3. 사용 예시 (Vanilla JavaScript)

```javascript
// HTML에 canvas 추가
// <canvas id="vnc-screen"></canvas>

// AppLauncher 사용
const launcher = new AppLauncher('http://110.15.177.120/cae/api/app');

// 인증 토큰 (필요시)
// launcher.setAuthToken('your-jwt-token');

// GEdit 실행
const canvas = document.getElementById('vnc-screen');

launcher.launchApp('gedit', 'user-123', canvas, {
  onSessionCreated: (sessionId) => {
    console.log('Session ID:', sessionId);
    showStatus('Creating session...');
  },
  onSessionRunning: (session) => {
    console.log('Session running:', session);
    showStatus('Session is running. Connecting to VNC...');
  },
  onVNCConnected: () => {
    console.log('VNC connected!');
    showStatus('Connected! GEdit is ready.');
  },
  onVNCDisconnected: () => {
    console.log('VNC disconnected');
    showStatus('Disconnected');
  }
}).then(({ session, vnc }) => {
  console.log('App launched successfully!');

  // 나중에 종료
  // launcher.stopApp(session.session_id);
}).catch(error => {
  console.error('Failed to launch app:', error);
  showStatus('Error: ' + error.message);
});
```

### 1-4. React 예시

```tsx
import { useEffect, useRef, useState } from 'react';
import { AppLauncher } from './AppLauncher';

function GEditApp() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [status, setStatus] = useState('Idle');
  const [sessionId, setSessionId] = useState<string | null>(null);
  const launcherRef = useRef<AppLauncher | null>(null);

  useEffect(() => {
    launcherRef.current = new AppLauncher();
  }, []);

  const handleLaunch = async () => {
    if (!canvasRef.current || !launcherRef.current) return;

    try {
      const { session } = await launcherRef.current.launchApp(
        'gedit',
        'current-user',
        canvasRef.current,
        {
          onSessionCreated: (id) => {
            setSessionId(id);
            setStatus('Creating...');
          },
          onSessionRunning: () => setStatus('Running'),
          onVNCConnected: () => setStatus('Connected'),
          onVNCDisconnected: () => setStatus('Disconnected')
        }
      );

      console.log('Launched:', session);
    } catch (error) {
      setStatus('Error: ' + (error as Error).message);
    }
  };

  const handleStop = async () => {
    if (sessionId && launcherRef.current) {
      await launcherRef.current.stopApp(sessionId);
      setStatus('Stopped');
      setSessionId(null);
    }
  };

  return (
    <div>
      <h2>GEdit Text Editor</h2>
      <p>Status: {status}</p>

      <button onClick={handleLaunch} disabled={!!sessionId}>
        Launch GEdit
      </button>
      <button onClick={handleStop} disabled={!sessionId}>
        Stop
      </button>

      <div style={{ width: '1280px', height: '720px', border: '2px solid #ccc' }}>
        <canvas ref={canvasRef} style={{ width: '100%', height: '100%' }} />
      </div>
    </div>
  );
}
```

### 1-5. Vue 예시

```vue
<template>
  <div>
    <h2>GEdit Text Editor</h2>
    <p>Status: {{ status }}</p>

    <button @click="launchApp" :disabled="!!sessionId">
      Launch GEdit
    </button>
    <button @click="stopApp" :disabled="!sessionId">
      Stop
    </button>

    <div class="vnc-container">
      <canvas ref="canvas"></canvas>
    </div>
  </div>
</template>

<script>
import { ref, onMounted } from 'vue';
import { AppLauncher } from './AppLauncher';

export default {
  setup() {
    const canvas = ref(null);
    const status = ref('Idle');
    const sessionId = ref(null);
    const launcher = ref(null);

    onMounted(() => {
      launcher.value = new AppLauncher();
    });

    const launchApp = async () => {
      if (!canvas.value || !launcher.value) return;

      try {
        const { session } = await launcher.value.launchApp(
          'gedit',
          'current-user',
          canvas.value,
          {
            onSessionCreated: (id) => {
              sessionId.value = id;
              status.value = 'Creating...';
            },
            onSessionRunning: () => status.value = 'Running',
            onVNCConnected: () => status.value = 'Connected',
            onVNCDisconnected: () => status.value = 'Disconnected'
          }
        );
      } catch (error) {
        status.value = 'Error: ' + error.message;
      }
    };

    const stopApp = async () => {
      if (sessionId.value && launcher.value) {
        await launcher.value.stopApp(sessionId.value);
        status.value = 'Stopped';
        sessionId.value = null;
      }
    };

    return { canvas, status, sessionId, launchApp, stopApp };
  }
};
</script>

<style scoped>
.vnc-container {
  width: 1280px;
  height: 720px;
  border: 2px solid #ccc;
}
canvas {
  width: 100%;
  height: 100%;
}
</style>
```

---

## 방법 2: React 컴포넌트 임베딩

**React 프로젝트 전용**입니다. App Framework의 React 컴포넌트를 직접 임포트하여 사용합니다.

### 2-1. 컴포넌트 임포트 방법

```tsx
// ===== Option A: 로컬 경로로 임포트 =====
import { AppContainer } from '@/path/to/app_5174/src/core/components';
import { useAppLifecycle } from '@/path/to/app_5174/src/core/hooks';

// ===== Option B: NPM 패키지로 설치 (Phase 6 이후) =====
// npm install @hpc-portal/app-framework
import { AppContainer, useAppLifecycle } from '@hpc-portal/app-framework';
```

### 2-2. AppContainer 사용

```tsx
import { AppContainer } from '@core/components';

function MyApp() {
  return (
    <AppContainer
      metadata={{
        id: 'gedit',
        name: 'GEdit',
        version: '1.0.0',
        description: 'Text Editor',
        category: 'editor'
      }}
      config={{
        resources: {
          cpus: 2,
          memory: '2Gi',
          gpu: false
        },
        display: {
          type: 'novnc',
          width: 1280,
          height: 720
        },
        container: {
          image: 'gedit-vnc',
          command: '/start-gedit.sh'
        }
      }}
      displayConfig={{
        type: 'novnc',
        width: 1280,
        height: 720,
        quality: 6,
        compression: 2,
        viewOnly: false,
        showControls: true
      }}
      autoStart={true}
      onReady={() => console.log('App ready!')}
      onError={(error) => console.error('Error:', error)}
      onSessionChange={(session) => console.log('Session:', session)}
    />
  );
}
```

### 2-3. useAppLifecycle Hook 사용

```tsx
import { useAppLifecycle } from '@core/hooks';

function CustomGEditApp() {
  const {
    session,
    display,
    websocket,
    startApp,
    stopApp,
    restartApp,
    isLoading,
    error
  } = useAppLifecycle({
    appId: 'gedit',
    config: {
      resources: {
        cpus: 2,
        memory: '2Gi',
        gpu: false
      },
      display: {
        type: 'novnc',
        width: 1280,
        height: 720
      }
    },
    displayConfig: {
      type: 'novnc',
      quality: 6,
      compression: 2
    },
    autoStart: false // 수동으로 시작
  });

  return (
    <div>
      <h2>GEdit Editor</h2>

      {/* 상태 표시 */}
      <div>
        <p>Session Status: {session?.status || 'None'}</p>
        <p>Display Connected: {display.isConnected ? 'Yes' : 'No'}</p>
        {isLoading && <p>Loading...</p>}
        {error && <p style={{ color: 'red' }}>Error: {error.message}</p>}
      </div>

      {/* 컨트롤 */}
      <div>
        <button onClick={startApp} disabled={isLoading || session?.status === 'running'}>
          Start
        </button>
        <button onClick={stopApp} disabled={isLoading || !session}>
          Stop
        </button>
        <button onClick={restartApp} disabled={isLoading || !session}>
          Restart
        </button>
      </div>

      {/* VNC 화면 */}
      {display.isConnected && (
        <div style={{ width: '1280px', height: '720px', border: '2px solid #ccc' }}>
          <canvas ref={display.canvasRef} style={{ width: '100%', height: '100%' }} />
        </div>
      )}
    </div>
  );
}
```

### 2-4. 커스텀 BaseApp 작성

```tsx
import { BaseApp } from '@core/BaseApp';
import type { AppMetadata, AppConfig, DisplayConfig } from '@core/types';

class MyCustomApp extends BaseApp {
  constructor(props: any) {
    super(props);
  }

  // 시작 전 실행
  onBeforeStart(): void {
    console.log('Preparing to start...');
    // 커스텀 로직 (예: 사용자 확인, 리소스 체크 등)
  }

  // 시작 후 실행
  onAfterStart(session: any): void {
    console.log('Started with session:', session);
    // 커스텀 로직 (예: 로깅, 알림 등)
  }

  // 종료 전 실행
  onBeforeStop(): void {
    console.log('Stopping app...');
    if (!confirm('정말로 종료하시겠습니까?')) {
      throw new Error('User cancelled');
    }
  }

  // 커스텀 Toolbar
  renderToolbar(): React.ReactNode {
    return (
      <div className="custom-toolbar">
        <button onClick={() => this.startApp()}>▶ Start</button>
        <button onClick={() => this.stopApp()}>■ Stop</button>
        <button onClick={() => this.restartApp()}>⟳ Restart</button>
        <button onClick={() => this.takeScreenshot()}>📷 Screenshot</button>
      </div>
    );
  }

  // 커스텀 StatusBar
  renderStatusBar(): React.ReactNode {
    return (
      <div className="custom-status">
        <span>Session: {this.state.session?.id}</span>
        <span>Status: {this.state.session?.status}</span>
        <span>Node: {this.state.session?.node}</span>
      </div>
    );
  }

  // 스크린샷 기능 (커스텀 메서드)
  takeScreenshot() {
    // VNC canvas에서 스크린샷 추출
    const canvas = this.displayRef.current?.querySelector('canvas');
    if (canvas) {
      const dataURL = canvas.toDataURL('image/png');
      const link = document.createElement('a');
      link.href = dataURL;
      link.download = `screenshot-${Date.now()}.png`;
      link.click();
    }
  }
}

// 사용
function MyDashboard() {
  const metadata: AppMetadata = {
    id: 'gedit',
    name: 'GEdit',
    version: '1.0.0'
  };

  const config: AppConfig = {
    resources: { cpus: 2, memory: '2Gi' },
    display: { type: 'novnc' }
  };

  const displayConfig: DisplayConfig = {
    type: 'novnc',
    quality: 6
  };

  return (
    <MyCustomApp
      metadata={metadata}
      config={config}
      displayConfig={displayConfig}
      autoStart={false}
    />
  );
}
```

---

## 방법 3: iframe 임베딩

**가장 간단하지만 제어가 제한적**입니다. 모든 프론트엔드에서 사용 가능합니다.

### 3-1. 기본 사용법

```html
<!-- GEdit 앱을 iframe으로 임베딩 -->
<iframe
  src="http://110.15.177.120:5174/app/gedit?autoStart=true"
  width="1280"
  height="720"
  frameborder="0"
  allow="clipboard-read; clipboard-write"
  style="border: 2px solid #ccc; border-radius: 8px;"
></iframe>
```

### 3-2. URL 파라미터

| 파라미터 | 타입 | 설명 | 예시 |
|---------|------|------|------|
| `autoStart` | boolean | 자동 시작 여부 | `?autoStart=true` |
| `quality` | number (0-9) | 화질 (높을수록 선명) | `?quality=8` |
| `compression` | number (0-9) | 압축률 | `?compression=2` |
| `viewOnly` | boolean | 읽기 전용 | `?viewOnly=true` |
| `showControls` | boolean | 컨트롤 표시 | `?showControls=false` |

**예시**:
```
http://110.15.177.120:5174/app/gedit?autoStart=true&quality=8&showControls=true
```

### 3-3. React에서 iframe 사용

```tsx
function GEditIframe() {
  const [isLoading, setIsLoading] = useState(true);

  return (
    <div>
      <h2>GEdit Editor</h2>

      {isLoading && <p>Loading app...</p>}

      <iframe
        src="http://110.15.177.120:5174/app/gedit?autoStart=true"
        width="1280"
        height="720"
        frameBorder="0"
        allow="clipboard-read; clipboard-write"
        style={{
          border: '2px solid #ccc',
          borderRadius: '8px',
          display: isLoading ? 'none' : 'block'
        }}
        onLoad={() => setIsLoading(false)}
      />
    </div>
  );
}
```

### 3-4. Vue에서 iframe 사용

```vue
<template>
  <div>
    <h2>GEdit Editor</h2>
    <p v-if="isLoading">Loading app...</p>

    <iframe
      src="http://110.15.177.120:5174/app/gedit?autoStart=true"
      width="1280"
      height="720"
      frameborder="0"
      allow="clipboard-read; clipboard-write"
      :style="{
        border: '2px solid #ccc',
        borderRadius: '8px',
        display: isLoading ? 'none' : 'block'
      }"
      @load="isLoading = false"
    />
  </div>
</template>

<script>
export default {
  data() {
    return {
      isLoading: true
    };
  }
};
</script>
```

### 3-5. iframe 통신 (PostMessage)

iframe과 부모 창 간 통신이 필요한 경우:

```typescript
// 부모 창 (Your Frontend)
const iframe = document.querySelector('iframe');

// iframe으로 메시지 전송
iframe.contentWindow?.postMessage({
  type: 'START_APP',
  appId: 'gedit'
}, '*');

// iframe으로부터 메시지 수신
window.addEventListener('message', (event) => {
  if (event.data.type === 'APP_STARTED') {
    console.log('App started:', event.data.sessionId);
  }
});

// iframe 내부 (App Framework)
window.addEventListener('message', (event) => {
  if (event.data.type === 'START_APP') {
    // 앱 시작 로직
    startApp(event.data.appId);
  }
});

// 부모 창으로 메시지 전송
window.parent.postMessage({
  type: 'APP_STARTED',
  sessionId: 'session-123'
}, '*');
```

---

## API 레퍼런스

### Base URL

```
Production: http://110.15.177.120/cae/api/app
Development: http://localhost:5000/api/app
```

### 인증

현재 인증이 선택사항입니다. JWT 토큰을 사용하는 경우:

```typescript
headers: {
  'Authorization': 'Bearer YOUR_JWT_TOKEN'
}
```

### 엔드포인트

#### 1. 앱 목록 조회

```http
GET /apps
```

**응답**:
```json
{
  "success": true,
  "apps": [
    {
      "id": "gedit",
      "name": "GEdit",
      "description": "Simple GNOME text editor for Linux",
      "version": "1.0.0",
      "category": "editor",
      "tags": ["text", "editor", "document", "gnome"],
      "container_image": "gedit.sif",
      "default_config": {
        "resources": {
          "cpus": 2,
          "memory": "4Gi",
          "gpu": false
        },
        "display": {
          "type": "novnc",
          "width": 1280,
          "height": 720
        }
      }
    }
  ]
}
```

#### 2. 세션 생성

```http
POST /sessions
Content-Type: application/json

{
  "app_id": "gedit",
  "user_id": "user-123"
}
```

**응답**:
```json
{
  "success": true,
  "session": {
    "id": "b58bb309-6ef9-4139-8114-0b72c9faafa4",
    "appId": "gedit",
    "appName": "GEdit",
    "status": "creating",
    "displayUrl": null,
    "vnc_port": 6080,
    "node": null,
    "node_ip": null,
    "job_id": null,
    "createdAt": "2025-10-24T20:52:26.578556",
    "updatedAt": "2025-10-24T20:52:26.578556"
  }
}
```

#### 3. 세션 조회

```http
GET /sessions/:sessionId
```

**응답** (Running 상태):
```json
{
  "success": true,
  "session": {
    "id": "b58bb309-6ef9-4139-8114-0b72c9faafa4",
    "appId": "gedit",
    "status": "running",
    "displayUrl": "ws://192.168.122.252:6080",
    "vnc_port": 6080,
    "node": "viz-node001",
    "node_ip": "192.168.122.252",
    "job_id": "184",
    "createdAt": "2025-10-24T20:52:26.578556",
    "updatedAt": "2025-10-24T20:52:28.582630"
  }
}
```

#### 4. 세션 목록

```http
GET /sessions
```

**응답**:
```json
{
  "success": true,
  "sessions": [
    { /* session object */ },
    { /* session object */ }
  ]
}
```

#### 5. 세션 삭제

```http
DELETE /sessions/:sessionId
```

**응답**:
```json
{
  "success": true,
  "message": "Session deleted successfully"
}
```

#### 6. 세션 재시작

```http
POST /sessions/:sessionId/restart
```

**응답**:
```json
{
  "success": true,
  "session": { /* new session object */ }
}
```

### 세션 상태

| 상태 | 설명 |
|------|------|
| `creating` | 세션 생성 중 |
| `pending` | Slurm Job 대기 중 |
| `running` | 앱 실행 중 (VNC 연결 가능) |
| `stopped` | 세션 종료됨 |
| `failed` | 오류 발생 |

---

## 실전 예시

### 예시 1: Dashboard에 앱 목록 표시

```tsx
import { useState, useEffect } from 'react';

interface App {
  id: string;
  name: string;
  description: string;
  category: string;
}

function AppGallery() {
  const [apps, setApps] = useState<App[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchApps();
  }, []);

  const fetchApps = async () => {
    try {
      const response = await fetch('http://110.15.177.120/cae/api/app/apps');
      const data = await response.json();
      setApps(data.apps || []);
    } catch (error) {
      console.error('Failed to fetch apps:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleLaunch = (appId: string) => {
    // 앱 실행 로직 (방법 1 사용)
    window.location.href = `/apps/${appId}`;
  };

  if (loading) return <div>Loading apps...</div>;

  return (
    <div className="app-gallery">
      <h1>Available Applications</h1>
      <div className="app-grid">
        {apps.map(app => (
          <div key={app.id} className="app-card">
            <h3>{app.name}</h3>
            <p>{app.description}</p>
            <span className="category">{app.category}</span>
            <button onClick={() => handleLaunch(app.id)}>
              Launch
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
```

### 예시 2: 세션 모니터링 Dashboard

```tsx
import { useState, useEffect } from 'react';

interface Session {
  id: string;
  appId: string;
  appName: string;
  status: string;
  node: string;
  createdAt: string;
}

function SessionMonitor() {
  const [sessions, setSessions] = useState<Session[]>([]);

  useEffect(() => {
    // 5초마다 세션 목록 갱신
    const intervalId = setInterval(fetchSessions, 5000);
    fetchSessions(); // 초기 로드

    return () => clearInterval(intervalId);
  }, []);

  const fetchSessions = async () => {
    try {
      const response = await fetch('http://110.15.177.120/cae/api/app/sessions');
      const data = await response.json();
      setSessions(data.sessions || []);
    } catch (error) {
      console.error('Failed to fetch sessions:', error);
    }
  };

  const handleStop = async (sessionId: string) => {
    if (!confirm('정말로 세션을 종료하시겠습니까?')) return;

    try {
      await fetch(`http://110.15.177.120/cae/api/app/sessions/${sessionId}`, {
        method: 'DELETE'
      });
      fetchSessions(); // 목록 갱신
    } catch (error) {
      console.error('Failed to stop session:', error);
      alert('세션 종료 실패');
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'running': return 'green';
      case 'pending': return 'orange';
      case 'creating': return 'blue';
      case 'failed': return 'red';
      default: return 'gray';
    }
  };

  return (
    <div className="session-monitor">
      <h2>Running Sessions ({sessions.length})</h2>

      {sessions.length === 0 ? (
        <p>No active sessions</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>App</th>
              <th>Session ID</th>
              <th>Status</th>
              <th>Node</th>
              <th>Created</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {sessions.map(session => (
              <tr key={session.id}>
                <td>{session.appName}</td>
                <td>{session.id.slice(0, 8)}...</td>
                <td>
                  <span style={{ color: getStatusColor(session.status) }}>
                    {session.status}
                  </span>
                </td>
                <td>{session.node || '-'}</td>
                <td>{new Date(session.createdAt).toLocaleString()}</td>
                <td>
                  <button onClick={() => handleStop(session.id)}>
                    Stop
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
```

### 예시 3: 전체 통합 (Complete Example)

```tsx
import { useState, useRef } from 'react';
import { AppLauncher } from './AppLauncher';

interface App {
  id: string;
  name: string;
  description: string;
}

function CompleteIntegration() {
  const [apps, setApps] = useState<App[]>([]);
  const [currentSession, setCurrentSession] = useState<any>(null);
  const [status, setStatus] = useState('Idle');
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const launcherRef = useRef<AppLauncher>(new AppLauncher());

  // 앱 목록 로드
  const loadApps = async () => {
    const apps = await launcherRef.current.getAvailableApps();
    setApps(apps);
  };

  // 앱 실행
  const launchApp = async (appId: string) => {
    if (!canvasRef.current) return;

    setStatus('Launching...');

    try {
      const { session, vnc } = await launcherRef.current.launchApp(
        appId,
        'current-user',
        canvasRef.current,
        {
          onSessionCreated: () => setStatus('Creating session...'),
          onSessionRunning: () => setStatus('Session running...'),
          onVNCConnected: () => setStatus('Connected!'),
          onVNCDisconnected: () => setStatus('Disconnected')
        }
      );

      setCurrentSession(session);
    } catch (error) {
      setStatus('Error: ' + (error as Error).message);
    }
  };

  // 앱 종료
  const stopApp = async () => {
    if (currentSession) {
      await launcherRef.current.stopApp(currentSession.session_id);
      setCurrentSession(null);
      setStatus('Stopped');
    }
  };

  return (
    <div className="app-framework-integration">
      {/* 헤더 */}
      <header>
        <h1>App Framework Integration Demo</h1>
        <button onClick={loadApps}>Refresh Apps</button>
      </header>

      {/* 앱 목록 */}
      <section className="app-list">
        <h2>Available Apps</h2>
        <div className="app-grid">
          {apps.map(app => (
            <div key={app.id} className="app-card">
              <h3>{app.name}</h3>
              <p>{app.description}</p>
              <button
                onClick={() => launchApp(app.id)}
                disabled={!!currentSession}
              >
                Launch
              </button>
            </div>
          ))}
        </div>
      </section>

      {/* VNC 뷰어 */}
      {currentSession && (
        <section className="vnc-viewer">
          <div className="vnc-header">
            <h2>Running: {currentSession.appName}</h2>
            <div>
              <span>Status: {status}</span>
              <button onClick={stopApp}>Stop</button>
            </div>
          </div>
          <div className="vnc-canvas-container">
            <canvas ref={canvasRef} />
          </div>
        </section>
      )}
    </div>
  );
}

export default CompleteIntegration;
```

---

## 트러블슈팅

### 문제 1: CORS 오류

**증상**:
```
Access to fetch at 'http://110.15.177.120/cae/api/app/sessions' from origin
'http://localhost:3000' has been blocked by CORS policy
```

**해결**:
1. Backend에서 CORS 허용 설정 필요
2. 또는 개발 시 프록시 사용:

```javascript
// vite.config.ts (Vite)
export default {
  server: {
    proxy: {
      '/api': 'http://110.15.177.120/cae'
    }
  }
}

// package.json (Create React App)
{
  "proxy": "http://110.15.177.120/cae"
}
```

### 문제 2: displayUrl이 null

**증상**:
세션 상태가 `running`인데 `displayUrl`이 `null` 또는 `ws://(null):6080`

**원인**:
- Job info 파일이 생성되지 않음
- Backend 모니터링 스레드가 파일을 읽지 못함

**해결**:
1. Slurm Job 로그 확인:
   ```bash
   ssh viz-node001 "cat /tmp/gedit_vnc_*.out"
   ```
2. Job info 파일 확인:
   ```bash
   ssh viz-node001 "cat /tmp/app_session_*.info"
   ```

### 문제 3: noVNC 검은 화면

**증상**:
VNC 연결은 성공했지만 화면이 검은색

**원인**:
- VNC 서버가 시작되지 않음
- 컨테이너 내부 오류

**해결**:
1. Job 로그 확인:
   ```bash
   ssh viz-node001 "cat /tmp/gedit_vnc_*.err"
   ```
2. VNC 서버 로그 확인:
   ```bash
   ssh viz-node001 "sudo apptainer exec /opt/apptainers/apps/gedit/gedit.sif cat /root/.vnc/*.log"
   ```

### 문제 4: 세션이 pending 상태에서 멈춤

**증상**:
세션이 계속 `pending` 상태

**원인**:
- Slurm 파티션에 사용 가능한 노드 없음
- 리소스 부족 (메모리, CPU)

**해결**:
1. Slurm 상태 확인:
   ```bash
   squeue
   sinfo
   ```
2. Job 요구사항 확인:
   ```bash
   scontrol show job <JOB_ID>
   ```

### 문제 5: WebSocket 연결 실패

**증상**:
```
WebSocket connection to 'ws://192.168.122.252:6080' failed
```

**원인**:
- viz-node001의 포트가 열려있지 않음
- 방화벽 차단

**해결**:
1. 포트 확인:
   ```bash
   ssh viz-node001 "lsof -i:6080"
   ```
2. 방화벽 확인:
   ```bash
   ssh viz-node001 "sudo iptables -L -n | grep 6080"
   ```

---

## 추가 리소스

### 문서
- [README.md](./README.md) - 프로젝트 개요
- [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) - 빠른 참조
- [ARCHITECTURE.md](./docs/ARCHITECTURE.md) - 시스템 아키텍처
- [DEPLOYMENT_GUIDE.md](./docs/DEPLOYMENT_GUIDE.md) - 배포 가이드
- [SUMMARY.md](./docs/SUMMARY.md) - 전체 요약

### 외부 라이브러리
- [noVNC](https://github.com/novnc/noVNC) - VNC 클라이언트
- [Apptainer](https://apptainer.org/docs/) - 컨테이너 런타임
- [Slurm](https://slurm.schedmd.com/) - 워크로드 매니저

### 예제 코드
- [test_vnc.html](./test_vnc.html) - 간단한 테스트 페이지
- [src/apps/GEditApp](./src/apps/GEditApp/) - GEdit 예제 앱

---

## 💬 지원

문제가 발생하거나 질문이 있으신 경우:

1. [GitHub Issues](https://github.com/your-org/app-framework/issues)
2. 내부 Slack: #app-framework
3. Email: support@your-org.com

---

**작성자**: KooSlurmInstallAutomation
**버전**: 0.5.0 (Phase 5 완료)
**최종 업데이트**: 2025-10-24
