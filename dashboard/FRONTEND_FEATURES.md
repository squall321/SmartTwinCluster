# Frontend Server (Port 3010) - 기능 상세 문서

## 📋 개요
React + TypeScript 기반의 SPA(Single Page Application)로, Slurm 클러스터 대시보드의 모든 UI를 담당합니다.

**포트**: 3010  
**프레임워크**: React 18 + TypeScript + Vite  
**스타일링**: Tailwind CSS  
**상태 관리**: Zustand  
**3D 렌더링**: Three.js  
**차트**: Recharts  

---

## 🏗️ 프로젝트 구조

```
src/
├── components/           # React 컴포넌트
│   ├── ClusterStats.tsx            # 클러스터 통계 요약
│   ├── ClusterVisualization3D.tsx  # 3D 시각화
│   ├── ConfigurationManager.tsx    # Slurm 설정 관리
│   ├── CustomDashboard/            # 커스텀 대시보드
│   ├── Dashboard.tsx               # 메인 대시보드
│   ├── DataManagement/             # 데이터 관리
│   ├── GlobalSearch/               # 전역 검색
│   ├── GroupPanel.tsx              # 그룹 패널
│   ├── JobManagement/              # 작업 관리
│   ├── JobTemplates/               # Job 템플릿
│   ├── ModeBadge.tsx               # Mock/Production 모드 배지
│   ├── NodeCard.tsx                # 노드 카드
│   ├── NotificationBell.tsx        # 알림 벨
│   ├── NotificationCenter/         # 알림 센터
│   ├── PrometheusMetrics/          # Prometheus 메트릭
│   ├── RealtimeMonitoring.tsx      # 실시간 모니터링
│   ├── Reports/                    # 리포트
│   └── ThemeToggle.tsx             # 다크모드 토글
├── contexts/             # React Context
│   └── ThemeContext.tsx            # 테마 컨텍스트
├── hooks/                # 커스텀 Hooks
│   ├── useWebSocket.ts             # WebSocket 연결
│   └── usePrometheus.ts            # Prometheus 데이터
├── store/                # Zustand Store
│   ├── dashboardStore.ts           # 대시보드 상태
│   ├── notificationStore.ts        # 알림 상태
│   └── themeStore.ts               # 테마 상태
├── types/                # TypeScript 타입 정의
│   └── index.ts
├── utils/                # 유틸리티 함수
│   ├── api.ts                      # API 클라이언트
│   └── formatters.ts               # 데이터 포맷터
├── App.tsx               # 루트 컴포넌트
└── main.tsx              # 엔트리 포인트
```

---

## 🎨 주요 컴포넌트

### 1. Dashboard (메인 대시보드)

#### 기능
- **클러스터 개요**: 전체 노드, 작업, 리소스 현황
- **실시간 모니터링**: CPU, 메모리, GPU 사용률 차트
- **알림 센터**: 실시간 알림 표시
- **빠른 액션**: 작업 제출, 취소, 일시정지

#### 구성 요소
```tsx
<Dashboard>
  <ClusterStats />          {/* 상단 통계 카드 */}
  <RealtimeMonitoring />    {/* 실시간 차트 */}
  <JobManagement />         {/* 작업 테이블 */}
  <NotificationBell />      {/* 알림 아이콘 */}
</Dashboard>
```

#### 상태 관리
```typescript
interface DashboardState {
  nodes: Node[];
  jobs: Job[];
  partitions: Partition[];
  loading: boolean;
  error: string | null;
  refreshInterval: number;
}
```

---

### 2. CustomDashboard (커스텀 대시보드)

#### 기능
- **드래그 앤 드롭**: React Grid Layout 기반 위젯 배치
- **위젯 선택**: 20+ 종류의 위젯 라이브러리
- **레이아웃 저장**: 개인별 대시보드 설정 저장/로드
- **반응형**: 브레이크포인트별 레이아웃 자동 조정

#### 위젯 종류
| 카테고리 | 위젯 |
|---------|------|
| **Cluster** | ClusterOverview, NodeStatus, PartitionInfo |
| **Jobs** | JobQueue, RunningJobs, CompletedJobs, TopUsers |
| **Resources** | CPUUsage, MemoryUsage, GPUUsage, StorageUsage |
| **Performance** | JobSuccessRate, AverageWaitTime, NodeUtilization |
| **System** | SystemAlerts, RecentActivity, QuickStats |
| **Prometheus** | PrometheusChart, MetricCard, GaugeWidget |

#### 저장/로드 기능
```typescript
// 레이아웃 저장
const saveLayout = async (name: string) => {
  await fetch('/api/dashboard/config', {
    method: 'POST',
    body: JSON.stringify({
      name,
      layout: gridLayout,
      widgets: selectedWidgets
    })
  });
};

// 레이아웃 로드
const loadLayout = async (id: string) => {
  const response = await fetch(`/api/dashboard/config?id=${id}`);
  const config = await response.json();
  setGridLayout(config.layout);
  setSelectedWidgets(config.widgets);
};
```

#### 위젯 추가/제거
```tsx
<CustomDashboard>
  <WidgetLibrary onSelectWidget={addWidget} />
  <GridLayout
    layout={layout}
    onLayoutChange={handleLayoutChange}
    draggableHandle=".drag-handle"
  >
    {widgets.map(widget => (
      <div key={widget.id} data-grid={widget.gridData}>
        <WidgetHeader onRemove={() => removeWidget(widget.id)} />
        <WidgetComponent type={widget.type} {...widget.props} />
      </div>
    ))}
  </GridLayout>
</CustomDashboard>
```

---

### 3. JobManagement (작업 관리)

#### 기능
- **작업 목록**: 모든 작업 조회 (pending, running, completed)
- **필터링**: 상태, 사용자, 파티션별 필터
- **정렬**: 시작 시간, 종료 시간, 우선순위별 정렬
- **상세 정보**: 작업 로그, 리소스 사용량, 노드 할당
- **작업 제어**: 제출, 취소, 일시정지, 재시작

#### 작업 제출 폼
```tsx
<JobSubmitForm>
  <Input name="jobName" label="Job Name" required />
  <Select name="partition" options={partitions} />
  <NumberInput name="nodes" label="Nodes" min={1} />
  <NumberInput name="cpus" label="CPUs per Node" />
  <NumberInput name="memory" label="Memory (GB)" />
  <Select name="qos" options={qosList} />
  <Textarea name="script" label="Job Script" />
  <Button type="submit">Submit Job</Button>
</JobSubmitForm>
```

#### 작업 상태 배지
```tsx
const statusColors = {
  PENDING: 'bg-yellow-500',
  RUNNING: 'bg-green-500',
  COMPLETED: 'bg-blue-500',
  FAILED: 'bg-red-500',
  CANCELLED: 'bg-gray-500'
};

<Badge className={statusColors[job.status]}>
  {job.status}
</Badge>
```

---

### 4. JobTemplates (작업 템플릿)

#### 기능
- **템플릿 라이브러리**: 사전 정의된 작업 스크립트
- **템플릿 생성**: 커스텀 템플릿 작성 및 저장
- **파라미터 입력**: 동적 변수를 위한 폼 자동 생성
- **빠른 제출**: 템플릿 선택 후 즉시 작업 제출

#### 템플릿 카드
```tsx
<TemplateCard template={template}>
  <h3>{template.name}</h3>
  <p>{template.description}</p>
  <Badge>{template.category}</Badge>
  <div className="flex gap-2">
    <Button onClick={() => useTemplate(template.id)}>Use</Button>
    <Button variant="outline" onClick={() => editTemplate(template.id)}>
      Edit
    </Button>
  </div>
</TemplateCard>
```

#### 템플릿 사용 플로우
1. 템플릿 선택
2. 파라미터 입력 폼 표시
3. 값 입력 및 검증
4. 스크립트 미리보기
5. 작업 제출

---

### 5. DataManagement (데이터 관리)

#### 기능
- **파일 브라우저**: 디렉토리 트리 탐색
- **파일 업로드**: 드래그 앤 드롭 또는 파일 선택
- **파일 다운로드**: 단일/다중 파일 다운로드
- **파일 검색**: 이름, 확장자, 크기로 검색
- **미리보기**: 텍스트, 이미지, CSV 파일 미리보기
- **스토리지 모니터링**: Data/Scratch 사용량 차트

#### 파일 트리 컴포넌트
```tsx
<FileTree>
  {directories.map(dir => (
    <TreeNode
      key={dir.path}
      label={dir.name}
      icon={<FolderIcon />}
      onExpand={() => loadChildren(dir.path)}
    >
      {dir.children?.map(child => (
        <TreeNode
          key={child.path}
          label={child.name}
          icon={getFileIcon(child.type)}
          onClick={() => selectFile(child)}
        />
      ))}
    </TreeNode>
  ))}
</FileTree>
```

#### 업로드 컴포넌트
```tsx
<UploadZone
  onDrop={handleDrop}
  accept="*"
  maxSize={10 * 1024 * 1024 * 1024} // 10GB
>
  <div className="upload-area">
    <UploadIcon />
    <p>Drag & Drop files here or click to browse</p>
  </div>
  <ProgressBar value={uploadProgress} />
</UploadZone>
```

---

### 6. PrometheusMetrics (Prometheus 메트릭)

#### 기능
- **실시간 차트**: CPU, 메모리, GPU, 네트워크 메트릭
- **커스텀 쿼리**: PromQL 쿼리 빌더
- **다중 시계열**: 여러 노드/GPU 비교
- **시간 범위 선택**: 1시간, 6시간, 24시간, 7일, 커스텀
- **자동 갱신**: 15초마다 데이터 업데이트

#### 차트 타입
| 타입 | 용도 |
|------|------|
| **LineChart** | 시계열 데이터 (CPU, 메모리) |
| **AreaChart** | 누적 데이터 (네트워크, 디스크 I/O) |
| **BarChart** | 비교 데이터 (노드별 사용률) |
| **GaugeChart** | 현재 값 (GPU 온도, 디스크 사용률) |

#### PromQL 쿼리 예제
```typescript
const queries = {
  cpuUsage: '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)',
  memoryUsage: '(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100',
  gpuUsage: 'nvidia_smi_utilization_gpu_ratio * 100',
  networkIn: 'rate(node_network_receive_bytes_total[5m])',
  diskIO: 'rate(node_disk_io_time_seconds_total[5m])'
};
```

#### 차트 컴포넌트
```tsx
<PrometheusChart
  query={queries.cpuUsage}
  timeRange="1h"
  refreshInterval={15000}
  chartType="line"
  title="CPU Usage by Node"
  unit="%"
  colors={['#3b82f6', '#10b981', '#f59e0b', '#ef4444']}
/>
```

---

### 7. NotificationCenter (알림 센터)

#### 기능
- **실시간 알림**: WebSocket을 통한 즉시 알림
- **알림 목록**: 모든 알림 히스토리
- **필터링**: 읽음/읽지 않음, 타입별 필터
- **알림 액션**: 읽음 처리, 삭제, 상세 보기
- **배지**: 읽지 않은 알림 수 표시

#### 알림 타입
```typescript
type NotificationType = 
  | 'job_completed'
  | 'job_failed'
  | 'job_started'
  | 'alert'
  | 'system'
  | 'info';

interface Notification {
  id: string;
  type: NotificationType;
  title: string;
  message: string;
  timestamp: string;
  read: boolean;
  data?: any;
}
```

#### WebSocket 연결
```typescript
const useNotifications = () => {
  const { subscribe, unsubscribe } = useWebSocket();
  
  useEffect(() => {
    const handleNotification = (data: any) => {
      if (data.type === 'notification') {
        addNotification(data.data);
        showToast(data.data.title);
      }
    };
    
    subscribe('notifications', handleNotification);
    return () => unsubscribe('notifications', handleNotification);
  }, []);
};
```

#### 알림 UI
```tsx
<NotificationCenter>
  <div className="header">
    <h2>Notifications</h2>
    <Badge>{unreadCount}</Badge>
    <Button onClick={markAllAsRead}>Mark all as read</Button>
  </div>
  <div className="filters">
    <Button active={filter === 'all'} onClick={() => setFilter('all')}>
      All
    </Button>
    <Button active={filter === 'unread'} onClick={() => setFilter('unread')}>
      Unread
    </Button>
  </div>
  <div className="list">
    {notifications.map(notif => (
      <NotificationItem
        key={notif.id}
        notification={notif}
        onRead={() => markAsRead(notif.id)}
        onDelete={() => deleteNotification(notif.id)}
      />
    ))}
  </div>
</NotificationCenter>
```

---

### 8. Reports (리포트)

#### 기능
- **리포트 생성**: 작업 사용량, 시스템 성능, 사용자 활동 리포트
- **포맷 선택**: PDF, Excel, CSV
- **커스터마이징**: 날짜 범위, 메트릭, 차트 선택
- **다운로드**: 생성된 리포트 즉시 다운로드
- **히스토리**: 과거 생성 리포트 목록

#### 리포트 생성 폼
```tsx
<ReportGenerator>
  <Select
    name="type"
    options={[
      { value: 'job_usage', label: 'Job Usage Report' },
      { value: 'system_performance', label: 'System Performance' },
      { value: 'user_activity', label: 'User Activity' }
    ]}
  />
  <DateRangePicker
    startDate={startDate}
    endDate={endDate}
    onChange={(start, end) => {
      setStartDate(start);
      setEndDate(end);
    }}
  />
  <Select
    name="format"
    options={[
      { value: 'pdf', label: 'PDF' },
      { value: 'excel', label: 'Excel' },
      { value: 'csv', label: 'CSV' }
    ]}
  />
  <MultiSelect
    name="metrics"
    options={availableMetrics}
    value={selectedMetrics}
    onChange={setSelectedMetrics}
  />
  <Button onClick={generateReport}>Generate Report</Button>
</ReportGenerator>
```

#### 리포트 히스토리
```tsx
<ReportHistory>
  {reports.map(report => (
    <ReportCard key={report.id}>
      <h3>{report.title}</h3>
      <p>{report.type} • {report.format.toUpperCase()}</p>
      <p>{formatDate(report.created_at)}</p>
      <p>{formatSize(report.file_size)}</p>
      <div className="actions">
        <Button onClick={() => downloadReport(report.id)}>
          Download
        </Button>
        <Button variant="outline" onClick={() => deleteReport(report.id)}>
          Delete
        </Button>
      </div>
    </ReportCard>
  ))}
</ReportHistory>
```

---

### 9. ClusterVisualization3D (3D 시각화)

#### 기능
- **3D 노드 배치**: Three.js로 노드를 3D 공간에 배치
- **상태 표시**: 노드 상태에 따라 색상 변경
- **인터랙티브**: 클릭, 줌, 회전 가능
- **정보 툴팁**: 노드 호버 시 상세 정보 표시

#### Three.js 구현
```typescript
const ClusterVisualization3D = ({ nodes }: Props) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  
  useEffect(() => {
    if (!canvasRef.current) return;
    
    // Scene 생성
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 1000);
    const renderer = new THREE.WebGLRenderer({ canvas: canvasRef.current });
    
    // 노드를 큐브로 표현
    nodes.forEach((node, index) => {
      const geometry = new THREE.BoxGeometry(1, 1, 1);
      const material = new THREE.MeshPhongMaterial({
        color: getNodeColor(node.state)
      });
      const cube = new THREE.Mesh(geometry, material);
      
      // 그리드 배치
      const row = Math.floor(index / 4);
      const col = index % 4;
      cube.position.set(col * 2, 0, row * 2);
      
      scene.add(cube);
    });
    
    // 조명
    const light = new THREE.DirectionalLight(0xffffff, 1);
    light.position.set(5, 5, 5);
    scene.add(light);
    
    // 애니메이션 루프
    const animate = () => {
      requestAnimationFrame(animate);
      renderer.render(scene, camera);
    };
    animate();
  }, [nodes]);
  
  return <canvas ref={canvasRef} />;
};
```

---

### 10. GlobalSearch (전역 검색)

#### 기능
- **통합 검색**: 작업, 노드, 파일, 사용자 검색
- **자동완성**: 입력 시 실시간 제안
- **필터**: 타입, 날짜별 필터
- **바로가기**: 검색 결과 클릭 시 해당 페이지로 이동

#### 검색 컴포넌트
```tsx
<GlobalSearch>
  <SearchInput
    placeholder="Search jobs, nodes, files..."
    value={query}
    onChange={handleSearchChange}
    onKeyDown={handleKeyDown}
  />
  {showResults && (
    <SearchResults>
      <ResultCategory title="Jobs" count={jobResults.length}>
        {jobResults.map(job => (
          <SearchResultItem
            key={job.id}
            icon={<JobIcon />}
            title={job.name}
            subtitle={`Status: ${job.status}`}
            onClick={() => navigateToJob(job.id)}
          />
        ))}
      </ResultCategory>
      <ResultCategory title="Nodes" count={nodeResults.length}>
        {nodeResults.map(node => (
          <SearchResultItem
            key={node.name}
            icon={<ServerIcon />}
            title={node.name}
            subtitle={`State: ${node.state}`}
            onClick={() => navigateToNode(node.name)}
          />
        ))}
      </ResultCategory>
    </SearchResults>
  )}
</GlobalSearch>
```

---

## 🎨 스타일링

### Tailwind CSS 설정
```javascript
// tailwind.config.js
module.exports = {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          100: '#dbeafe',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
        },
        dark: {
          bg: '#0f172a',
          card: '#1e293b',
          border: '#334155',
        }
      }
    }
  }
};
```

### 다크 모드
```tsx
const ThemeToggle = () => {
  const { theme, toggleTheme } = useThemeStore();
  
  useEffect(() => {
    if (theme === 'dark') {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
  }, [theme]);
  
  return (
    <button onClick={toggleTheme}>
      {theme === 'dark' ? <SunIcon /> : <MoonIcon />}
    </button>
  );
};
```

---

## 📊 상태 관리 (Zustand)

### Dashboard Store
```typescript
interface DashboardStore {
  // State
  nodes: Node[];
  jobs: Job[];
  loading: boolean;
  
  // Actions
  fetchNodes: () => Promise<void>;
  fetchJobs: () => Promise<void>;
  submitJob: (job: JobSubmitData) => Promise<void>;
  cancelJob: (jobId: string) => Promise<void>;
}

const useDashboardStore = create<DashboardStore>((set, get) => ({
  nodes: [],
  jobs: [],
  loading: false,
  
  fetchNodes: async () => {
    set({ loading: true });
    const response = await fetch('/api/nodes');
    const data = await response.json();
    set({ nodes: data, loading: false });
  },
  
  // ... other actions
}));
```

### Notification Store
```typescript
const useNotificationStore = create<NotificationStore>((set, get) => ({
  notifications: [],
  unreadCount: 0,
  
  addNotification: (notification: Notification) => {
    set(state => ({
      notifications: [notification, ...state.notifications],
      unreadCount: state.unreadCount + 1
    }));
  },
  
  markAsRead: (id: string) => {
    set(state => ({
      notifications: state.notifications.map(n =>
        n.id === id ? { ...n, read: true } : n
      ),
      unreadCount: Math.max(0, state.unreadCount - 1)
    }));
  }
}));
```

---

## 🔌 API 클라이언트

### API Utils
```typescript
// utils/api.ts
const API_BASE = 'http://localhost:5010';

export const api = {
  get: async (endpoint: string) => {
    const response = await fetch(`${API_BASE}${endpoint}`);
    if (!response.ok) throw new Error(`API error: ${response.statusText}`);
    return response.json();
  },
  
  post: async (endpoint: string, data: any) => {
    const response = await fetch(`${API_BASE}${endpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!response.ok) throw new Error(`API error: ${response.statusText}`);
    return response.json();
  },
  
  // ... other methods
};

// 특정 API 함수
export const getNodes = () => api.get('/api/nodes');
export const getJobs = () => api.get('/api/jobs');
export const submitJob = (data: JobSubmitData) => api.post('/api/jobs', data);
```

---

## 🧪 테스트

### Vitest 설정
```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'json']
    }
  }
});
```

### 컴포넌트 테스트 예제
```typescript
import { render, screen, fireEvent } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import JobManagement from './JobManagement';

describe('JobManagement', () => {
  it('renders job list', async () => {
    render(<JobManagement />);
    expect(screen.getByText('Job Management')).toBeInTheDocument();
  });
  
  it('submits job on form submit', async () => {
    const mockSubmit = vi.fn();
    render(<JobManagement onSubmit={mockSubmit} />);
    
    fireEvent.change(screen.getByLabelText('Job Name'), {
      target: { value: 'test-job' }
    });
    fireEvent.click(screen.getByText('Submit'));
    
    expect(mockSubmit).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'test-job' })
    );
  });
});
```

---

## 🚀 빌드 및 배포

### 개발 서버
```bash
npm run dev
# http://localhost:3010
```

### 프로덕션 빌드
```bash
npm run build
# dist/ 폴더에 빌드 파일 생성
```

### 프리뷰
```bash
npm run preview
# 빌드된 파일 로컬 서버로 확인
```

---

## 🔧 환경 설정

### Vite 설정
```typescript
// vite.config.ts
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3010,
    proxy: {
      '/api': {
        target: 'http://localhost:5010',
        changeOrigin: true
      },
      '/ws': {
        target: 'ws://localhost:5011',
        ws: true
      }
    }
  }
});
```

---

## 📚 참고 자료
- [React 공식 문서](https://react.dev/)
- [TypeScript 공식 문서](https://www.typescriptlang.org/)
- [Tailwind CSS 공식 문서](https://tailwindcss.com/)
- [Zustand 공식 문서](https://zustand-demo.pmnd.rs/)
- [Three.js 공식 문서](https://threejs.org/)
- [Recharts 공식 문서](https://recharts.org/)
