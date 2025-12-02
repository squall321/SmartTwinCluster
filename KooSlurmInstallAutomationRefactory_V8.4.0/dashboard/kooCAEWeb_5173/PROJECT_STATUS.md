# kooCAEWeb 프로젝트 개발 상황 분석

**작성일**: 2025년 10월 10일  
**프로젝트명**: kooCAEWeb  
**버전**: 0.0.0

---

## 📋 프로젝트 개요

kooCAEWeb은 CAE(Computer-Aided Engineering) 시뮬레이션 및 분석을 위한 웹 기반 플랫폼입니다. React + TypeScript + Vite 스택을 사용하여 구축된 프론트엔드 애플리케이션으로, 다양한 구조 해석, 낙하 시뮬레이션, 재료 모델링 등의 엔지니어링 도구를 제공합니다.

### 기술 스택

- **프론트엔드 프레임워크**: React 18.3.1 + TypeScript 5.8.3
- **빌드 도구**: Vite 6.3.5
- **UI 라이브러리**: Ant Design 5.27.3
- **3D 시각화**: 
  - Babylon.js 8.21.0
  - Three.js 0.177.0
  - React Three Fiber 8.13.7
- **데이터 시각화**: 
  - Plotly.js 3.0.1
  - Ant Design Charts 2.3.0
- **상태 관리**: Zustand 5.0.8
- **라우팅**: React Router DOM 7.6.2
- **수학/계산**: Math.js 14.5.3
- **데이터 처리**: Papa Parse 5.5.3

---

## 🏗️ 프로젝트 구조

```
kooCAEWeb/
├── src/
│   ├── pages/              # 페이지 컴포넌트 (40개 파일, 211.57 KB)
│   ├── components/         # 재사용 가능한 컴포넌트 (48개 파일, 381.03 KB)
│   ├── api/                # API 클라이언트 설정
│   ├── services/           # 비즈니스 로직 및 API 서비스
│   ├── types/              # TypeScript 타입 정의
│   ├── utils/              # 유틸리티 함수
│   ├── layouts/            # 레이아웃 컴포넌트
│   ├── assets/             # 정적 자산
│   ├── images/             # 이미지 파일
│   ├── Icons/              # 아이콘 파일
│   └── ModuleGenerator/    # 모듈 생성기
├── public/                 # 정적 파일
├── .env.development        # 개발 환경 변수
├── .env.production         # 프로덕션 환경 변수
├── vite.config.ts          # Vite 설정
├── tsconfig.json           # TypeScript 설정
└── package.json            # 프로젝트 의존성
```

---

## 🚀 주요 기능 모듈

### 1. 낙하 시뮬레이션 모듈
- **DropAttitudeGenerator** (17.05 KB): 낙하 자세 생성기
- **FullAngleDrops** (4.86 KB): 전각도 낙하 시뮬레이션
- **FullAngleDropsMBDPage** (14.02 KB): 다물체 동역학 낙하 시뮬레이션
- **PostFullAngleDrops** (793 B): 낙하 시뮬레이션 후처리
- **DropWeightImpactTestGenerator** (14.26 KB): 부분 충격 생성기
- **AllPointsDropWeightImpactGenerator** (22.84 KB): 전위치 부분 충격 시뮬레이션

### 2. 구조 해석 및 재료 모델링
- **ABDCalculator** (13.34 KB): 복합재료 적층 구조 ABD 행렬 계산
- **RambergOsgoodPage** (1.07 KB): Ramberg-Osgood 소성 재료 모델
- **ViscoelasticVisualizerPage** (817 B): 점탄성 재료 모델 시각화
- **ThreePointBendingPage** (611 B): 3점 굽힘 시뮬레이션
- **ContactStiffnessDemoPage** (946 B): 충돌 강성 시뮬레이션

### 3. 디스플레이 및 배터리 빌더
- **AdvancedDisplayBuilder** (17.20 KB): 고급 디스플레이 빌더
- **AdvancedBatteryBuilder** (10.09 KB): 고급 배터리 빌더

### 4. 메시 및 모델링 도구
- **MeshModifier** (933 B): 메시 수정 도구
- **BoxMorph** (826 B): 박스 형태 변환
- **WarpToStress** (4.08 KB): 변형을 응력으로 변환
- **ElastictoRigidBuilder** (3.11 KB): 탄성-강체 변환 빌더
- **AutomatedModeller** (1.69 KB): 자동화 모델링 도구

### 5. 컴포넌트 테스트
- **ComponentTest** (4.34 KB): 컴포넌트 테스트 메인
- **ComponentTestAutomation** (3.35 KB): 컴포넌트 테스트 자동화
- **ComponentTestMeshViewer** (1.59 KB): 메시 뷰어
- **ComponentTestSubComponent** (2.67 KB): 서브 컴포넌트 테스트
- **ComponentTestDrawing** (1.00 KB): 드로잉 기능
- **ComponentTestMetaData** (2.86 KB): 메타데이터 관리

### 6. HPC 클러스터 관리
- **SlurmStatusPage** (1.08 KB): SLURM 상태 모니터링
- **SlurmJobDashboard** (3.12 KB): SLURM 작업 대시보드
- **SubmitLsdynaPage** (943 B): LS-DYNA 작업 제출
- **AutoSubmitLsdynaPage** (1.17 KB): LS-DYNA 자동 제출
- **SubmitBulletPage** (678 B): Bullet 시뮬레이션 제출

### 7. 시뮬레이션 도구
- **MotorLevelSimulationPage** (1.40 KB): 모터 레벨 시뮬레이션
- **PWMGenerator** (896 B): PWM 신호 생성기
- **MCKEditor** (mck 디렉토리): MCK 시뮬레이션 편집기
- **SimulationAutomationPage** (1.32 KB): 시뮬레이션 자동화

### 8. 이론 및 교육
- **FEMStructuralAnalysisPage**: 유한요소법 구조 해석 이론
- **PDEFEMPage**: 편미분방정식 및 FEM 이론

### 9. 기타 유틸리티
- **DimensionalTolerance** (33.50 KB): 치수 공차 분석
- **StreamRunnerPage** (1.52 KB): 스트림 실행기
- **PackageGeneratorPage**: 패키지 생성기

### 10. 사용자 인증
- **LoginPage** (2.08 KB): 로그인
- **SignupPage** (3.61 KB): 회원가입
- **Dashboard** (8.23 KB): 메인 대시보드

---

## 🎨 주요 컴포넌트

### 시각화 컴포넌트
1. **3D 뷰어**: 40.05 KB 규모
   - `CuboidNetPainter`: 큐보이드 네트 페인팅
   - `GLBDynamicViewerComponent`: GLB 동적 뷰어
   - `GLTFViewerComponent`: GLTF 뷰어
   - `StlViewerComponent`: STL 뷰어
   - `ObjViewerComponent`: OBJ 뷰어
   - `MultipleStlViewerComponent`: 다중 STL 뷰어

2. **차트 컴포넌트**
   - `MolbeideStressPlot` (31.58 KB): 응력 플롯
   - `BarChartComponent`: 막대 그래프
   - `LineChartPerEntityComponent`: 엔티티별 선 그래프
   - `ColoredScatter2DComponent`: 2D 산점도
   - `ColoredScatter3DComponent`: 3D 산점도
   - `ParallelCoordinatesPlotComponent`: 평행 좌표 플롯
   - `HeatmapMatrixComponent`: 히트맵 매트릭스

3. **재료 및 물리 시뮬레이션**
   - `RambergOsgoodPanel` (16.54 KB): Ramberg-Osgood 패널
   - `ViscoElasticVisualizer` (21.66 KB): 점탄성 시각화
   - `ContactStiffnessDemoComponent` (11.66 KB): 접촉 강성 데모

4. **드로잉 및 편집**
   - `DrawingCanvas` (23.68 KB): 드로잉 캔버스
   - `DrawingCanvaswithModel` (3.21 KB): 모델이 포함된 드로잉
   - `MorphComponent` (7.09 KB): 형태 변환 컴포넌트

5. **네트워크 및 그래프**
   - `ContactConnectivityGraph` (16.66 KB): 접촉 연결성 그래프
   - `SimulationNetwork`: 시뮬레이션 네트워크

6. **공통 컴포넌트**
   - `FileTreeExplorer`: 파일 트리 탐색기
   - `FileFilterPanel`: 파일 필터 패널
   - `MaterialSelectorComponent`: 재료 선택기
   - `MaterialCacheContext`: 재료 캐시 컨텍스트

---

## 🔧 백엔드 통신

### API 설정
- **개발 환경**: `http://localhost:5000`
- **프로덕션 환경**: `https://api.myserver.com`
- **프록시 설정**: `/api` 경로를 Flask 서버로 프록시

### 주요 서비스
- **slurmapi.ts**: SLURM 클러스터 관리 API
  - 노드 상태 조회 (sinfo)
  - 작업 큐 조회 (squeue)
  - 작업 제출
  - 작업 취소

---

## 📊 프로젝트 규모

### 파일 통계
- **총 페이지**: 40개 (211.57 KB)
- **총 컴포넌트**: 48개 (381.03 KB)
- **총 라우트**: 42개

### 주요 페이지 크기별 분류
| 순위 | 파일명 | 크기 |
|------|--------|------|
| 1 | DimensionalTolerance | 33.50 KB |
| 2 | AllPointsDropWeightImpactGenerator | 22.84 KB |
| 3 | AdvancedDisplayBuilder | 17.20 KB |
| 4 | DropAttitudeGenerator | 17.05 KB |
| 5 | DropWeightImpactTestGenerator | 14.26 KB |

### 주요 컴포넌트 크기별 분류
| 순위 | 파일명 | 크기 |
|------|--------|------|
| 1 | CuboidNetPainter | 40.05 KB |
| 2 | MolbeideStressPlot | 31.58 KB |
| 3 | DrawingCanvas | 23.68 KB |
| 4 | ViscoElasticVisualizer | 21.66 KB |
| 5 | DrawingCanvaswithModelBackup | 16.74 KB |

---

## 🔑 핵심 기능

### 1. 사용자 인증
- 로컬 스토리지 기반 인증 시스템
- 사용자별 prefix 관리
- 로그인/회원가입 페이지

### 2. 대시보드
- 42개의 기능 모듈로 구성된 메인 대시보드
- 카드 기반 네비게이션
- 파일 트리 탐색기 통합

### 3. 3D 시각화
- Babylon.js 및 Three.js 기반 고급 3D 렌더링
- GLB, GLTF, STL, OBJ 파일 형식 지원
- 동적 메시 시각화 및 애니메이션

### 4. 데이터 분석
- 다양한 차트 및 플롯 컴포넌트
- 실시간 데이터 시각화
- CSV 데이터 파싱 및 분석 (Papa Parse)

### 5. HPC 통합
- SLURM 클러스터 모니터링
- LS-DYNA 및 Bullet 시뮬레이션 제출
- 작업 상태 추적

---

## 🛠️ 개발 환경 설정

### 필수 요구사항
- Node.js (최신 LTS 버전 권장)
- npm 또는 yarn

### 설치 및 실행
```bash
# 의존성 설치
npm install

# 개발 서버 실행 (포트 5173)
npm run dev

# 프로덕션 빌드
npm run build

# 빌드 미리보기
npm run preview

# 린팅
npm run lint
```

### 환경 변수
- **개발**: `.env.development` 파일에서 `VITE_API_BASE_URL` 설정
- **프로덕션**: `.env.production` 파일에서 API URL 설정

---

## 🎯 TypeScript 설정

### Path Aliases
```json
{
  "@components/*": ["./src/components/*"],
  "@pages/*": ["./src/pages/*"]
}
```

### 컴파일러 옵션
- Target: ESNext
- Module: ESNext
- JSX: react-jsx
- Strict mode 활성화

---

## 📦 주요 의존성

### 프로덕션 의존성
- **UI/UX**: antd, framer-motion
- **3D**: @babylonjs/*, @react-three/*, three
- **차트**: @ant-design/charts, plotly.js, react-plotly.js
- **수학**: mathjs
- **라우팅**: react-router-dom
- **상태관리**: zustand
- **HTTP**: axios
- **데이터**: papaparse
- **드래그앤드롭**: react-dnd, react-dnd-html5-backend
- **캔버스**: konva, react-konva
- **수식**: react-katex, react-latex-next, better-react-mathjax

### 개발 의존성
- TypeScript 5.8.3
- ESLint 9.25.0
- Vite 6.3.5
- @vitejs/plugin-react 4.4.1

---

## 🚧 현재 개발 상태

### ✅ 완료된 기능
1. 기본 프로젝트 구조 및 라우팅 설정
2. 사용자 인증 시스템
3. 메인 대시보드
4. 42개의 기능 모듈 페이지
5. 다양한 3D 시각화 컴포넌트
6. SLURM 클러스터 통합
7. 재료 모델링 도구
8. 낙하 시뮬레이션 도구
9. 데이터 시각화 컴포넌트

### 🔄 진행 중
- 컴포넌트 최적화 및 코드 리팩토링
- 추가 기능 모듈 개발
- 백엔드 API 통합 확대

### 📋 개선 필요 사항
1. **README 업데이트**: 현재 README는 Vite 템플릿 기본 내용만 포함
2. **문서화**: 각 모듈에 대한 상세 문서 필요
3. **테스트**: 단위 테스트 및 통합 테스트 추가
4. **타입 정의**: 일부 컴포넌트의 타입 정의 강화
5. **에러 처리**: 통합적인 에러 처리 메커니즘 구축
6. **성능 최적화**: 대용량 3D 모델 로딩 최적화
7. **접근성**: WCAG 가이드라인 준수
8. **국제화**: 다국어 지원 (현재 한국어 하드코딩)

---

## 🔐 보안 고려사항

### 현재 구현
- 로컬 스토리지 기반 인증 (개선 필요)
- HTTPS API 통신 설정

### 개선 필요
1. JWT 토큰 기반 인증 구현
2. 리프레시 토큰 메커니즘
3. CSRF 보호
4. XSS 방어 강화
5. 보안 헤더 설정

---

## 📈 성능 최적화

### 현재 구현
- Vite 기반 빠른 HMR
- 코드 스플리팅 (React Router)
- 레이지 로딩

### 개선 가능
1. 이미지 최적화 및 레이지 로딩
2. 3D 모델 LOD (Level of Detail)
3. 메모이제이션 활용 확대
4. 번들 크기 최적화
5. 캐싱 전략 강화

---

## 🐛 알려진 이슈

1. **README 미완성**: 프로젝트 소개 문서 업데이트 필요
2. **로컬 인증**: 보안성 낮은 로컬스토리지 인증 방식
3. **타입 안정성**: 일부 컴포넌트에서 `any` 타입 사용
4. **에러 바운더리**: 전역 에러 처리 미흡
5. **빈 컴포넌트**: `FiniteElementTheoryComponent.tsx` (0 B) 구현 필요

---

## 🎓 학습 리소스

프로젝트에서 사용되는 주요 기술에 대한 학습 리소스:

- **React**: https://react.dev/
- **TypeScript**: https://www.typescriptlang.org/
- **Vite**: https://vitejs.dev/
- **Ant Design**: https://ant.design/
- **Babylon.js**: https://www.babylonjs.com/
- **Three.js**: https://threejs.org/
- **Plotly**: https://plotly.com/javascript/

---

## 📞 연락처 및 지원

프로젝트 관리자: koopark  
프로젝트 경로: `/home/koopark/claude/kooCAEWeb`

---

## 🔮 향후 계획

### 단기 목표 (1-3개월)
1. 사용자 인증 시스템 개선
2. 전체 컴포넌트 테스트 커버리지 확보
3. API 문서화 완료
4. 성능 프로파일링 및 최적화

### 중기 목표 (3-6개월)
1. 실시간 협업 기능 추가
2. 클라우드 저장소 통합
3. 모바일 반응형 UI 개선
4. 고급 분석 대시보드

### 장기 목표 (6-12개월)
1. AI 기반 시뮬레이션 최적화
2. 플러그인 시스템 구축
3. 엔터프라이즈 버전 개발
4. 국제화 및 다국어 지원

---

## 📊 프로젝트 메트릭스

- **개발 기간**: 진행 중
- **코드베이스 크기**: ~592 KB (페이지 + 컴포넌트)
- **주요 언어**: TypeScript, TSX
- **총 라우트 수**: 42개
- **주요 의존성 수**: 30+개
- **지원 파일 형식**: GLB, GLTF, STL, OBJ, CSV, K 파일

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025년 10월 10일
