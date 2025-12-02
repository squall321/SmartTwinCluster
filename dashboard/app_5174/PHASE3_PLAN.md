# 📋 Phase 3: Example App & noVNC Integration - 구현 계획

**작성일**: 2025-10-23
**목표**: 실제 동작하는 앱 예제 구현 + noVNC 통합

---

## 🎯 Phase 3 목표

1. **noVNC 라이브러리 통합** - 실제 VNC 연결 기능 구현
2. **GEdit 예제 앱** - BaseApp을 상속받는 실제 앱 구현
3. **App Launcher UI** - 앱 선택 및 실행 인터페이스
4. **Apptainer 컨테이너** - GEdit용 컨테이너 정의

---

## 📦 구현 항목

### 1. noVNC 라이브러리 통합

#### 1.1 패키지 설치
```bash
npm install @novnc/novnc
```

#### 1.2 DisplayFrame 업데이트
**파일**: `src/core/hooks/useDisplay.ts`

**변경사항**:
- Mock 연결 제거
- 실제 noVNC RFB 객체 생성
- noVNC 이벤트 핸들러 연결
- 키보드/마우스 입력 처리

**구현 내용**:
```typescript
import RFB from '@novnc/novnc/core/rfb';

const connectNoVNC = (url: string) => {
  const rfb = new RFB(containerRef.current, url, {
    credentials: { password: '' },
  });

  rfb.addEventListener('connect', () => {
    setStatus('connected');
    onConnected?.();
  });

  rfb.addEventListener('disconnect', () => {
    setStatus('disconnected');
    onDisconnected?.();
  });

  rfb.scaleViewport = true;
  rfb.resizeSession = true;

  clientRef.current = rfb;
};
```

#### 1.3 품질/압축 동적 조정
```typescript
const setQuality = (quality: number) => {
  if (clientRef.current) {
    clientRef.current.qualityLevel = quality;
  }
};

const setCompression = (compression: number) => {
  if (clientRef.current) {
    clientRef.current.compressionLevel = compression;
  }
};
```

---

### 2. GEdit 예제 앱 구현

#### 2.1 디렉토리 구조
```
src/apps/example/
├── GEditApp.tsx          # GEdit 앱 컴포넌트
├── GEditApp.config.ts    # GEdit 기본 설정
└── index.ts              # Export
```

#### 2.2 GEditApp 구현
**파일**: `src/apps/example/GEditApp.tsx`

```typescript
import { Component } from 'react';
import { BaseApp, BaseAppProps, BaseAppState } from '@apps/base';
import { AppContainer } from '@core/components';
import type { AppConfig, DisplayConfig } from '@core/types';

export class GEditApp extends BaseApp {
  protected getDefaultConfig(): AppConfig {
    return {
      resources: {
        cpus: 2,
        memory: '4Gi',
        gpu: false,
      },
      display: {
        type: 'novnc',
        width: 1280,
        height: 720,
      },
      container: {
        image: 'gedit-vnc',
        command: '/start-gedit.sh',
      },
    };
  }

  protected getDisplayConfig(): DisplayConfig {
    return {
      type: 'novnc',
      width: 1280,
      height: 720,
      quality: 6,
      compression: 2,
      viewOnly: false,
      showControls: true,
    };
  }

  protected renderToolbar() {
    return (
      <button onClick={() => this.handleNewDocument()}>
        📄 New Document
      </button>
    );
  }

  private handleNewDocument() {
    // WebSocket으로 새 문서 생성 명령 전송
    console.log('Creating new document...');
  }

  render() {
    return (
      <AppContainer
        metadata={{
          id: 'gedit',
          name: 'GEdit Text Editor',
          version: '1.0.0',
          description: 'Simple text editor',
          category: 'editor',
          icon: '/assets/gedit-icon.svg',
        }}
        config={this.getDefaultConfig()}
        displayConfig={this.getDisplayConfig()}
        toolbarChildren={this.renderToolbar()}
      />
    );
  }
}
```

#### 2.3 앱 등록
**파일**: `src/apps/example/index.ts`

```typescript
import { appRegistry } from '@core/services/app.registry';

// GEdit 앱 등록
appRegistry.register({
  metadata: {
    id: 'gedit',
    name: 'GEdit',
    version: '1.0.0',
    description: 'Text editor for Linux',
    category: 'editor',
    tags: ['text', 'editor', 'document'],
    icon: '/assets/gedit-icon.svg',
  },
  component: () => import('./GEditApp'),
});
```

---

### 3. App Launcher UI

#### 3.1 AppLauncher 컴포넌트
**파일**: `src/core/components/AppLauncher.tsx`

**기능**:
- 등록된 앱 목록 표시
- 카테고리별 필터링
- 검색 기능
- 앱 카드 UI (아이콘, 이름, 설명)
- 앱 선택 시 실행

**UI 구조**:
```
┌─────────────────────────────────────┐
│ App Launcher                         │
│ ┌─────────────────────────────┐     │
│ │ 🔍 Search apps...            │     │
│ └─────────────────────────────┘     │
│                                      │
│ 📂 Categories                        │
│ [ All ] [ Editor ] [ Tools ]         │
│                                      │
│ Apps (3)                             │
│ ┌──────┐ ┌──────┐ ┌──────┐         │
│ │ 📝   │ │ 🖼️   │ │ 🔧   │         │
│ │GEdit │ │GIMP  │ │Term  │         │
│ └──────┘ └──────┘ └──────┘         │
└─────────────────────────────────────┘
```

**구현**:
```typescript
export function AppLauncher(props: AppLauncherProps) {
  const [apps, setApps] = useState<AppMetadata[]>([]);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('all');

  useEffect(() => {
    const allApps = appRegistry.listMetadata();
    setApps(allApps);
  }, []);

  const filteredApps = apps.filter(app => {
    const matchSearch = app.name.toLowerCase().includes(search.toLowerCase());
    const matchCategory = category === 'all' || app.category === category;
    return matchSearch && matchCategory;
  });

  const handleLaunch = (appId: string) => {
    props.onLaunch?.(appId);
  };

  return (
    <div className="app-launcher">
      {/* Search bar */}
      <input
        type="text"
        placeholder="Search apps..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      {/* Categories */}
      <div className="categories">
        {['all', 'editor', 'tools', 'graphics'].map(cat => (
          <button
            key={cat}
            onClick={() => setCategory(cat)}
            className={category === cat ? 'active' : ''}
          >
            {cat}
          </button>
        ))}
      </div>

      {/* App cards */}
      <div className="app-grid">
        {filteredApps.map(app => (
          <AppCard
            key={app.id}
            app={app}
            onLaunch={() => handleLaunch(app.id)}
          />
        ))}
      </div>
    </div>
  );
}
```

#### 3.2 AppCard 컴포넌트
```typescript
function AppCard({ app, onLaunch }: AppCardProps) {
  return (
    <div className="app-card" onClick={onLaunch}>
      <div className="app-icon">
        {app.icon ? <img src={app.icon} /> : '📦'}
      </div>
      <div className="app-name">{app.name}</div>
      <div className="app-description">{app.description}</div>
    </div>
  );
}
```

---

### 4. Apptainer 컨테이너 정의

#### 4.1 디렉토리 구조
```
apptainer/app/
├── gedit/
│   ├── gedit.def            # Apptainer definition
│   ├── start-gedit.sh       # Startup script
│   └── README.md            # 설명서
└── build.sh                 # Build script
```

#### 4.2 GEdit Apptainer Definition
**파일**: `apptainer/app/gedit/gedit.def`

```bash
Bootstrap: docker
From: ubuntu:22.04

%post
    # 기본 패키지 설치
    apt-get update
    apt-get install -y \
        gedit \
        tigervnc-standalone-server \
        tigervnc-common \
        novnc \
        websockify \
        xfce4 \
        dbus-x11 \
        x11-utils

    # VNC 비밀번호 설정 (빈 비밀번호)
    mkdir -p /root/.vnc
    echo "" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd

    # 정리
    apt-get clean
    rm -rf /var/lib/apt/lists/*

%files
    start-gedit.sh /start-gedit.sh

%runscript
    /start-gedit.sh

%labels
    Author KooSlurmAutomation
    Version 1.0.0
    App gedit
```

#### 4.3 Startup Script
**파일**: `apptainer/app/gedit/start-gedit.sh`

```bash
#!/bin/bash

# VNC Display 설정
export DISPLAY=:1
VNC_PORT=5901

# VNC 서버 시작
vncserver :1 -geometry 1280x720 -depth 24 &

# VNC 서버 대기
sleep 2

# GEdit 실행
gedit &

# WebSocket 프록시 시작 (noVNC용)
websockify 6080 localhost:$VNC_PORT &

# 무한 대기 (컨테이너 종료 방지)
wait
```

#### 4.4 Build Script
**파일**: `apptainer/app/build.sh`

```bash
#!/bin/bash

set -e

APPS=("gedit")

for app in "${APPS[@]}"; do
    echo "Building $app..."
    cd "$app"

    # Apptainer 빌드
    sudo apptainer build \
        --force \
        "${app}.sif" \
        "${app}.def"

    echo "✅ $app built successfully"
    cd ..
done

echo ""
echo "All apps built!"
ls -lh */*.sif
```

---

## 🔗 통합 작업

### 5. App.tsx 업데이트

**변경사항**:
- App Launcher 추가
- 앱 선택 시 해당 앱 컴포넌트 로드
- 라우팅 추가 (Home → Launcher → App)

```typescript
function App() {
  const [view, setView] = useState<'home' | 'launcher' | 'app'>('home');
  const [selectedApp, setSelectedApp] = useState<string | null>(null);

  const handleLaunchApp = async (appId: string) => {
    setSelectedApp(appId);
    setView('app');
  };

  if (view === 'launcher') {
    return (
      <AppLauncher
        onLaunch={handleLaunchApp}
        onBack={() => setView('home')}
      />
    );
  }

  if (view === 'app' && selectedApp) {
    // 동적으로 앱 컴포넌트 로드
    const AppComponent = await appRegistry.loadComponent(selectedApp);
    return <AppComponent />;
  }

  return <HomePage onLaunch={() => setView('launcher')} />;
}
```

---

## 📊 작업 순서

### Step 1: noVNC 통합 (1-2일)
1. ✅ npm install @novnc/novnc
2. ✅ useDisplay.ts 업데이트
3. ✅ 연결 테스트

### Step 2: GEdit 앱 구현 (1일)
1. ✅ GEditApp 컴포넌트 작성
2. ✅ 앱 등록
3. ✅ 테스트

### Step 3: App Launcher UI (1일)
1. ✅ AppLauncher 컴포넌트
2. ✅ AppCard 컴포넌트
3. ✅ 검색/필터 기능
4. ✅ 스타일링

### Step 4: Apptainer 컨테이너 (1일)
1. ✅ gedit.def 작성
2. ✅ start-gedit.sh 작성
3. ✅ 빌드 및 테스트

### Step 5: 통합 테스트 (1일)
1. ✅ End-to-end 테스트
2. ✅ 버그 수정
3. ✅ 문서화

**예상 소요 시간**: 5-7일

---

## 🎯 성공 기준

### Phase 3 완료 조건

1. **noVNC 통합**
   - ✅ 실제 VNC 연결 성공
   - ✅ 키보드/마우스 입력 동작
   - ✅ 품질/압축 동적 조정 가능

2. **GEdit 앱**
   - ✅ BaseApp 상속 구현
   - ✅ AppContainer 통합
   - ✅ 실제 GEdit 실행 가능

3. **App Launcher**
   - ✅ 앱 목록 표시
   - ✅ 검색/필터 동작
   - ✅ 앱 선택 및 실행

4. **Apptainer**
   - ✅ gedit.sif 빌드 성공
   - ✅ VNC 서버 정상 시작
   - ✅ GEdit 실행 확인

5. **End-to-End**
   - ✅ Launcher → 앱 선택 → 실행 → VNC 연결 → 사용

---

## 📝 문서화

### 생성 예정 문서

1. **PHASE3_COMPLETE.md**
   - 구현 내용 상세 설명
   - 코드 예시
   - 사용법

2. **GEDIT_APP_GUIDE.md**
   - GEdit 앱 개발 가이드
   - BaseApp 상속 방법
   - 커스터마이징 방법

3. **APPTAINER_GUIDE.md**
   - 컨테이너 빌드 방법
   - 앱 추가 방법
   - 트러블슈팅

---

## 🔧 기술 스택

### 추가 라이브러리
- **@novnc/novnc**: VNC 클라이언트
- 기존 React/TypeScript/Vite 유지

### Backend 요구사항
- `/api/app/sessions` 엔드포인트 구현 필요
- Apptainer 실행 로직 필요
- VNC 포트 관리 필요

---

## ⚠️ 주의사항

### 잠재적 이슈

1. **noVNC CORS 이슈**
   - WebSocket 프록시 필요
   - nginx 설정 필요할 수 있음

2. **Apptainer 권한**
   - sudo 권한 필요
   - 사전 빌드 권장

3. **포트 충돌**
   - VNC 포트 동적 할당 필요
   - 포트 범위 관리

4. **성능**
   - noVNC 품질 설정 최적화 필요
   - 네트워크 대역폭 고려

---

**계획 작성 완료!**
**다음**: Step 1 (noVNC 통합) 시작
