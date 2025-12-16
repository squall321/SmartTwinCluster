# SimulationAutomationComponent 업데이트 문서

## 업데이트 일자
2025-12-03

## 업데이트 개요
SimulationAutomationComponent에 3가지 새로운 분석 타입을 추가했습니다:
1. **Predefined Drop Attitudes** (사전 정의 낙하 자세)
2. **Edge Axis Rotation** (엣지 축 회전)
3. **Drop Weight Impact** (낙하 중량 충격) - `partialImpact`에서 이름 변경 및 기능 확장

---

## Phase 1: Type 정의 추가 ✅

### 파일 위치
`SimulationAutomationComponent.tsx` 라인 10-31

### 변경 사항

#### 1.1 AnalysisType 확장
```typescript
export type AnalysisType =
  | "fullAngleMBD"
  | "fullAngle"
  | "fullAngleCumulative"
  | "multiRepeatCumulative"
  | "dropWeightImpact"        // ✨ NEW (renamed from partialImpact)
  | "predefinedAttitudes"     // ✨ NEW
  | "edgeAxisRotation";       // ✨ NEW
```

#### 1.2 새로운 Type 정의 추가
```typescript
// Predefined attitudes
export type PredefinedMode = "faces6" | "edges12" | "corners8" | "all26";

// Edge axis rotation
export type EdgeAxis = "top" | "bottom" | "left" | "right";

// Drop weight impact
export type ImpactGridMode = "1x1" | "2x1" | "1x2" | "3x1" | "1x3" | "3x3";
export type ImpactLocationMode = "grid" | "percentage" | "random";
export type ImpactorType = "ball" | "cylinder";
export type CylinderDiameter = 8 | 15 | "custom";
```

#### 1.3 ScenarioRow 인터페이스 확장
`params` 필드에 새로운 속성 추가:

**dropWeightImpact 전용:**
- `impactPackagePatterns?: string[]` - 패키지 이름 패턴 배열 (와일드카드 지원)
- `impactLocationMode?: ImpactLocationMode` - 충격 위치 모드 (grid/percentage/random)
- `impactGridMode?: ImpactGridMode` - 격자 모드
- `impactPercentageX?: number` - X 좌표 (0-100%)
- `impactPercentageY?: number` - Y 좌표 (0-100%)
- `impactRandomCount?: number` - LHS 샘플 개수
- `impactorType?: ImpactorType` - 충격체 타입 (ball/cylinder)
- `impactorBallDiameter?: number` - Ball 지름 (1-50mm, 기본 6mm)
- `impactorCylinderDiameter?: CylinderDiameter | number` - Cylinder 지름
- `impactorCylinderDiameterCustom?: number` - 사용자 정의 Cylinder 지름

**predefinedAttitudes 전용:**
- `predefinedMode?: PredefinedMode` - 낙하 자세 모드

**edgeAxisRotation 전용:**
- `edgeAxis?: EdgeAxis` - 회전 축 엣지
- `edgeDivisions?: number` - 회전 각도 분할 수

---

## Phase 2: 상수 정의 ✅

### 파일 위치
`SimulationAutomationComponent.tsx` 라인 166-222

### 추가된 상수

#### 2.1 사전 정의 낙하 자세
```typescript
// 좌표계: Display facing +Z, origin at bottom center
const FACE_ATTITUDES: [number, number, number][] = [
  [0, 0, 0],        // 전면
  [180, 0, 0],      // 배면
  [90, 0, 0],       // 좌측면
  [-90, 0, 0],      // 우측면
  [0, -90, 0],      // 상단
  [0, 90, 0],       // 하단
];  // 6개

const EDGE_ATTITUDES: [number, number, number][] = [
  [-45, 0, 0], [45, 0, 0], [0, -45, 0], [0, 45, 0],
  [0, 0, -45], [0, 0, 45], [45, 45, 0], [-45, -45, 0],
  [0, 45, 45], [0, -45, -45], [45, 0, 45], [-45, 0, -45]
];  // 12개

const CORNER_ATTITUDES: [number, number, number][] = [
  [-35.264, 45, 0], [35.264, 45, 0],
  [-35.264, -45, 0], [35.264, -45, 0],
  [-35.264, 45, 180], [35.264, 45, 180],
  [-35.264, -45, 180], [35.264, -45, 180]
];  // 8개
```

#### 2.2 충격 격자 옵션
```typescript
const IMPACT_GRID_OPTIONS: { label: string; value: ImpactGridMode }[] = [
  { label: "1×1 (중앙)", value: "1x1" },
  { label: "2×1 (가로 2열)", value: "2x1" },
  { label: "1×2 (세로 2열)", value: "1x2" },
  { label: "3×1 (가로 3열)", value: "3x1" },
  { label: "1×3 (세로 3열)", value: "1x3" },
  { label: "3×3 (9포인트)", value: "3x3" },
];
```

#### 2.3 엣지 축 옵션
```typescript
const EDGE_AXIS_OPTIONS: { label: string; value: EdgeAxis }[] = [
  { label: "상단 엣지", value: "top" },
  { label: "하단 엣지", value: "bottom" },
  { label: "좌측 엣지", value: "left" },
  { label: "우측 엣지", value: "right" },
];

const EDGE_DIVISION_COUNTS = [4, 6, 8, 12, 16, 24, 36, 48, 72];
```

---

## Phase 3: Helper 함수 구현 ✅

### 파일 위치
`SimulationAutomationComponent.tsx` 라인 293-396

### 추가된 Helper 함수

#### 3.1 generatePredefinedAttitudes
```typescript
const generatePredefinedAttitudes = (mode: PredefinedMode): [number, number, number][] => {
  // Returns: 6, 12, 8, or 26 attitudes based on mode
}
```
**기능:** 선택한 모드에 따라 사전 정의된 낙하 자세 배열 반환

#### 3.2 generateEdgeRotationAttitudes
```typescript
const generateEdgeRotationAttitudes = (axis: EdgeAxis, divisions: number): [number, number, number][] => {
  // Generates rotation angles around specified edge
}
```
**기능:** 지정된 엣지를 축으로 회전하는 각도 배열 생성
- Top edge: `[0, -90, angle]`
- Bottom edge: `[0, 90, angle]`
- Left edge: `[90, 0, angle]`
- Right edge: `[-90, 0, angle]`

#### 3.3 matchesPackagePattern & matchesAnyPattern
```typescript
const matchesPackagePattern = (packageName: string, pattern: string): boolean => {
  // Wildcard pattern matching (* support)
}

const matchesAnyPattern = (packageName: string, patterns: string[]): boolean => {
  // Check if packageName matches any pattern
}
```
**기능:** 와일드카드 패턴 매칭 (`*pkg*`, `display`, `camera*` 등)

#### 3.4 generateGridCoordinates
```typescript
const generateGridCoordinates = (mode: ImpactGridMode): Array<{ x: number; y: number }> => {
  // Returns evenly distributed grid points (0-100%)
}
```
**기능:** 격자 모드에 따라 균등 분포 좌표 생성
- 예: `3x3` → 9개 포인트 `[(0,0), (50,0), (100,0), (0,50), ...]`

#### 3.5 generateLHSCoordinates
```typescript
const generateLHSCoordinates = (count: number): Array<{ x: number; y: number }> => {
  // Returns LHS sampled random coordinates
}
```
**기능:** Latin Hypercube Sampling을 사용한 랜덤 좌표 생성

---

## Phase 4: UI Controls 함수 구현 ✅

### 파일 위치
`SimulationAutomationComponent.tsx` 라인 551-827

### 추가된 UI 함수

#### 4.1 renderPredefinedAttitudesControls
**위치:** 라인 554-587

**UI 구성:**
- 높이 & 표면 컨트롤 (공통)
- 낙하 자세 선택 (6면/12엣지/8코너/전체26)
- 자세 개수 표시 Tag
- Tolerance 컨트롤 (공통)

**기본값:**
- `predefinedMode`: "all26" (26개 전체)

#### 4.2 renderEdgeAxisRotationControls
**위치:** 라인 590-635

**UI 구성:**
- 높이 & 표면 컨트롤 (공통)
- 회전 엣지 선택 (상단/하단/좌측/우측)
- 분할 수 선택 (4/6/8/12/16/24/36/48/72등분)
- 각도 개수 표시 Tag
- Tolerance 컨트롤 (공통)

**기본값:**
- `edgeAxis`: "top"
- `edgeDivisions`: 12

#### 4.3 renderDropWeightImpactControls
**위치:** 라인 638-827

**UI 구성:**

**패키지 패턴 섹션:**
- 입력 필드 (쉼표 구분, 와일드카드 지원)
- 현재 패턴 표시

**충격 위치 모드 섹션:**
- 모드 선택: Grid / Percentage / Random
- Grid 모드: 격자 선택 (1x1 ~ 3x3), 포인트 개수 표시
- Percentage 모드: X, Y 좌표 입력 (0-100%)
- Random 모드: LHS 샘플 개수 입력

**충격체 타입 섹션:**
- 타입 선택: Ball / Cylinder
- Ball: 지름 입력 (1-50mm, 기본 6mm)
- Cylinder: 표준 (8mm/15mm) 또는 사용자 정의 (1-100mm)

**기본값:**
- `impactPackagePatterns`: `["*pkg*"]`
- `impactLocationMode`: "grid"
- `impactGridMode`: "3x3"
- `impactorType`: "ball"
- `impactorBallDiameter`: 6mm

---

## Phase 5: renderOptionControls 확장 ✅

### 파일 위치
`SimulationAutomationComponent.tsx` 라인 1252-1276

### 변경 사항
renderOptionControls 함수 시작 부분에 새로운 3개 타입 처리 추가:

```typescript
const renderOptionControls = (row: ScenarioRow) => {
  // ---- NEW: predefinedAttitudes ----
  if (row.analysisType === "predefinedAttitudes") {
    return renderPredefinedAttitudesControls(row, setScenarios);
  }

  // ---- NEW: edgeAxisRotation ----
  if (row.analysisType === "edgeAxisRotation") {
    return renderEdgeAxisRotationControls(row, setScenarios);
  }

  // ---- NEW: dropWeightImpact ----
  if (row.analysisType === "dropWeightImpact") {
    return renderDropWeightImpactControls(row, setScenarios);
  }

  // ... existing types
}
```

---

## Phase 6: analysisLabel 확장 ✅

### 파일 위치
`SimulationAutomationComponent.tsx` 라인 147-159

### 변경 사항
```typescript
const analysisLabel = (row: ScenarioRow) => {
  // ... existing types
  if (row.analysisType === "dropWeightImpact") return "낙하 중량 충격";
  if (row.analysisType === "predefinedAttitudes") return "사전 정의 낙하 자세";
  if (row.analysisType === "edgeAxisRotation") return "엣지 축 회전";
  return "알 수 없는 해석 타입";
};
```

---

## Phase 7: ANALYSIS_OPTIONS 배열 확장 ✅

### 파일 위치
`SimulationAutomationComponent.tsx` 라인 121-129

### 추가된 옵션
```typescript
const ANALYSIS_OPTIONS: { label: string; value: AnalysisType; hint: string }[] = [
  // ... existing options
  { label: "낙하 중량 충격", value: "dropWeightImpact", hint: "패키지 위치별 Ball/Cylinder 충격" },
  { label: "사전 정의 낙하 자세", value: "predefinedAttitudes", hint: "6면/12엣지/8코너 조합" },
  { label: "엣지 축 회전", value: "edgeAxisRotation", hint: "엣지 기준 회전 각도 분할" },
];
```

---

## Phase 8: 분석 타입 변경 시 기본값 추가 ✅

### 8.1 테이블 컬럼 onChange 핸들러
**위치:** 라인 1515-1529

### 8.2 handleBulkSetType 함수
**위치:** 라인 1575-1592

### 추가된 기본값
```typescript
// predefinedAttitudes
v === "predefinedAttitudes" ? {
  predefinedMode: "all26",
  heightMode: "const", heightConst: 1.0,
  heightMin: 0.5, heightMax: 1.5,
  surface: "steelPlate",
  tolerance: { mode: "disabled" }
}

// edgeAxisRotation
v === "edgeAxisRotation" ? {
  edgeAxis: "top",
  edgeDivisions: 12,
  heightMode: "const", heightConst: 1.0,
  heightMin: 0.5, heightMax: 1.5,
  surface: "steelPlate",
  tolerance: { mode: "disabled" }
}

// dropWeightImpact
v === "dropWeightImpact" ? {
  impactPackagePatterns: ["*pkg*"],
  impactLocationMode: "grid",
  impactGridMode: "3x3",
  impactPercentageX: 50, impactPercentageY: 50,
  impactRandomCount: 10,
  impactorType: "ball",
  impactorBallDiameter: 6,
  impactorCylinderDiameter: 8,
  impactorCylinderDiameterCustom: 10,
  tolerance: { mode: "disabled" }
}
```

---

## Phase 9: 코드 정리 및 기타 수정 ✅

### 9.1 partialImpact → dropWeightImpact 이름 변경
- 모든 `"partialImpact"` 문자열을 `"dropWeightImpact"`로 변경
- 파일 업로드 핸들러에서 타입 비교 수정 (라인 458, 488)

### 9.2 코드 구조 개선
- UI Controls 함수들을 논리적 순서로 배치
- 주석을 통한 섹션 구분 강화
- 일관된 코딩 스타일 유지

---

## 테스트 체크리스트

### Predefined Attitudes
- [ ] 6면 모드 선택 → 6개 자세 표시
- [ ] 12엣지 모드 선택 → 12개 자세 표시
- [ ] 8코너 모드 선택 → 8개 자세 표시
- [ ] 전체26 모드 선택 → 26개 자세 표시
- [ ] 높이/표면 설정 변경
- [ ] Tolerance 설정 활성화/비활성화

### Edge Axis Rotation
- [ ] 4가지 엣지 선택 (상/하/좌/우)
- [ ] 분할 수 변경 (4~72등분)
- [ ] 생성되는 각도 개수 확인
- [ ] 높이/표면 설정 변경

### Drop Weight Impact
- [ ] 패키지 패턴 입력 (와일드카드 포함)
- [ ] Grid 모드: 모든 격자 옵션 테스트 (1x1 ~ 3x3)
- [ ] Percentage 모드: X, Y 좌표 입력
- [ ] Random 모드: 샘플 개수 변경
- [ ] Ball 타입: 지름 변경 (1-50mm)
- [ ] Cylinder 타입: 8mm, 15mm, 사용자 정의 테스트

### 통합 테스트
- [ ] 분석 타입 변경 시 기본값 정상 로드
- [ ] 일괄 적용 기능 동작
- [ ] JSON 내보내기/불러오기
- [ ] 실행 버튼 클릭 시 JSON payload 확인

---

## 향후 개선 사항

1. **handleRun 함수 확장**
   - 3가지 새 타입에 대한 JSON payload 생성 로직 추가 필요
   - 서버 API 연동 시 payload 형식 확인 필요

2. **Validation 추가**
   - 패키지 패턴 유효성 검사
   - 좌표 범위 검증
   - 충격체 지름 범위 검증

3. **UI/UX 개선**
   - 격자 포인트 시각화 미리보기
   - 회전 각도 시각화
   - 패키지 패턴 자동완성

4. **성능 최적화**
   - 대량 좌표 생성 시 성능 측정
   - 메모이제이션 적용 검토

---

## 변경된 파일 목록

1. `/dashboard/kooCAEWeb_5173/src/components/SimulationAutomation/SimulationAutomationComponent.tsx`
   - 약 300+ 라인 추가
   - Type definitions (7개 새 타입)
   - Constants (3개 섹션)
   - Helper functions (6개 함수)
   - UI Controls (3개 render 함수)
   - 기존 함수 확장 및 수정

---

## 참고 자료

- 원본 계획 문서: `SimulationAutomatedPagePlan.md`
- 참고 파일: `DropAttitudeGenerator.tsx` (낙하 자세 정의)
- 좌표계: Display facing +Z, origin at bottom center
- 스마트폰 크기 가정: 70×150×8mm

---

## 업데이트 완료 상태

✅ Phase 1: Type 정의 추가
✅ Phase 2: 상수 정의
✅ Phase 3: Helper 함수 구현
✅ Phase 4: UI Controls 함수 구현
✅ Phase 5: renderOptionControls 확장
✅ Phase 6: analysisLabel 확장
✅ Phase 7: ANALYSIS_OPTIONS 배열 확장
✅ Phase 8: 분석 타입 변경 시 기본값 추가
⏳ Phase 9: 코드 정리 및 테스트 (진행 중)

**다음 단계:** handleRun 함수에서 3가지 새 타입에 대한 JSON payload 생성 로직 추가 필요
