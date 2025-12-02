# Dashboard.tsx에 Health Check 탭 추가 가이드

## 수정할 파일
`frontend_3010/src/components/Dashboard.tsx`

---

## 1단계: Import 추가

파일 상단 import 섹션에 추가:

```typescript
import HealthCheck from './HealthCheck';
import { Stethoscope } from 'lucide-react';  // 아이콘 추가
```

기존 import 다음에 추가하면 됩니다 (약 20번째 줄 근처):

```typescript
import Reports from './Reports';
import ThemeToggle from './ThemeToggle';
import HealthCheck from './HealthCheck';  // 🆕 추가
```

그리고 lucide-react import에 Stethoscope 추가:

```typescript
import { 
  Save, RotateCcw, AlertCircle, 
  LayoutGrid, Activity, Briefcase, FolderOpen, Plus, Database, BarChart3, FileCode, Layout,
  Stethoscope  // 🆕 추가
} from 'lucide-react';
```

---

## 2단계: TabType 타입에 'health' 추가

약 25번째 줄 근처:

```typescript
type TabType = 'cluster' | 'monitoring' | 'data' | 'jobs' | 'prometheus' | 'templates' | 'customdash' | 'reports' | 'health';  // 🆕 'health' 추가
```

---

## 3단계: tabs 배열에 Health Check 탭 추가

약 130번째 줄 근처 tabs 배열에 추가:

```typescript
const tabs = [
  { id: 'cluster' as TabType, label: 'Cluster Management', icon: LayoutGrid },
  { id: 'customdash' as TabType, label: 'Custom Dashboard', icon: Layout },
  { id: 'monitoring' as TabType, label: 'Real-time Monitoring', icon: Activity },
  { id: 'prometheus' as TabType, label: 'Prometheus Metrics', icon: BarChart3 },
  { id: 'reports' as TabType, label: 'Reports', icon: FileCode },
  { id: 'jobs' as TabType, label: 'Job Management', icon: Briefcase },
  { id: 'templates' as TabType, label: 'Job Templates', icon: FileCode },
  { id: 'data' as TabType, label: 'Data Management', icon: Database },
  { id: 'health' as TabType, label: 'Health Check', icon: Stethoscope },  // 🆕 추가
];
```

---

## 4단계: Health Check 탭 렌더링 추가

리포트 탭 렌더링 다음에 추가 (약 220번째 줄 근처):

```typescript
{/* 리포트 탭 */}
{activeTab === 'reports' && (
  <Reports />
)}

{/* 🆕 Health Check 탭 */}
{activeTab === 'health' && (
  <HealthCheck />
)}
```

---

## 완료!

이제 다음 명령으로 프론트엔드를 재시작하세요:

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/frontend_3010
npm run dev
```

브라우저에서 `http://localhost:3010`에 접속하면 새로운 "Health Check" 탭이 보입니다!

---

## 전체 수정 요약

1. ✅ Import 2개 추가 (HealthCheck 컴포넌트, Stethoscope 아이콘)
2. ✅ TabType에 'health' 추가
3. ✅ tabs 배열에 Health Check 탭 객체 추가
4. ✅ JSX에서 activeTab === 'health' 조건부 렌더링 추가

총 4곳만 수정하면 완료됩니다!
