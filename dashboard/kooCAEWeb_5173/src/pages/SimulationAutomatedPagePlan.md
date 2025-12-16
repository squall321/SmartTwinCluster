# Simulation Automation Page 개선 계획

## 📋 요구사항 요약

### 1. 스마트폰 좌표계 정의
- **디스플레이 면**: +Z 방향 (전면 빨강, 상단 파랑 - DropAttitudeGenerator 기준)
- **원점 위치**: 스마트폰 하단, 좌우 중앙, 두께 중앙
- **크기 기준**: 70mm (x) × 150mm (y) × 8mm (z)
- **색상 표시**:
  - 전면(디스플레이): 빨강
  - 상단: 파랑
  - 나머지: 회색

### 2. 추가할 해석 타입

#### A. 낙추 충격 시험 (Drop Weight Impact)
- **개념**: Ball 또는 Cylinder 형상의 임팩터를 특정 패키지 위치에 낙하시켜 충격 시험
- **임팩터 형상**:
  - **Ball (구형)**: 직경 6mm (기본), 1~50mm 범위 커스텀
  - **Cylinder (원통형)**: 직경 8mm, 15mm (표준), 1~100mm 범위 커스텀
- **패키지 선택**: 와일드카드 패턴 매칭
  - `*pkg*`: pkg가 포함된 모든 패키지 (글자수 제한 없음)
  - `display`: display로 정확히 일치하는 패키지
  - `camera*`: camera로 시작하는 모든 패키지
  - `*battery`: battery로 끝나는 모든 패키지
  - 여러 패턴 지정 가능 (예: `["*pkg*", "display", "camera01"]`)

- **충격 위치 모드**:
  1. **Grid 모드**: 정규 그리드 패턴
     - `1x1`: 중심 1개
     - `2x1`: X방향 2개 (좌 25%, 우 75%)
     - `1x2`: Y방향 2개 (하 25%, 상 75%)
     - `3x1`: X방향 3개 (좌 16.7%, 중 50%, 우 83.3%)
     - `1x3`: Y방향 3개 (하 16.7%, 중 50%, 상 83.3%)
     - `3x3`: 3×3 그리드 (9개 포인트)

  2. **Percentage 모드**: 사용자 정의 백분율 좌표
     - XLocations: `[30, 50, 20]` (%, 좌하단 기준)
     - YLocations: `[10, 60, 20]` (%, 좌하단 기준)
     - 조합: (30%, 10%), (30%, 60%), (30%, 20%), (50%, 10%), ..., (20%, 20%) = 9개

  3. **Random 모드**: 랜덤 위치 생성
     - 개수 지정: 5, 10, 20, 50 등
     - LHS 샘플링으로 균등 분포 보장

#### B. 사전정의 낙하 자세 (Predefined Drop Attitudes)

사용자가 요청한 새로운 분석 타입은 **랜덤성이 없는** predefined 자세들로 구성됩니다:

**26방향 낙하 (DropAttitudeGenerator 참조)**
- **6면 낙하** (Faces: F1~F6)
  ```
  F1: [0, 0, 0]        // 전면 (디스플레이가 바닥)
  F2: [180, 0, 0]      // 배면 (뒷면이 바닥)
  F3: [90, 0, 0]       // 좌측면
  F4: [-90, 0, 0]      // 우측면
  F5: [0, -90, 0]      // 상단
  F6: [0, 90, 0]       // 하단
  ```

- **12엣지 낙하** (Edges: E1~E12)
  ```
  E1~E4: 주 축 대각선 엣지 (45도 조합)
  E5~E8: 추가 대각선 엣지
  E9~E12: 3축 조합 엣지

  예시:
  E1: [-45, 0, 0]
  E2: [45, 0, 0]
  E3: [0, -45, 0]
  E4: [0, 45, 0]
  E5: [0, 0, -45]
  E6: [0, 0, 45]
  E7: [45, 45, 0]
  E8: [-45, -45, 0]
  E9: [0, 45, 45]
  E10: [0, -45, -45]
  E11: [45, 0, 45]
  E12: [-45, 0, -45]
  ```

- **8코너 낙하** (Corners: C1~C8)
  ```
  C1: [-35.264, 45, 0]
  C2: [35.264, 45, 0]
  C3: [-35.264, -45, 0]
  C4: [35.264, -45, 0]
  C5: [-35.264, 45, 180]
  C6: [35.264, 45, 180]
  C7: [-35.264, -45, 180]
  C8: [35.264, -45, 180]
  ```

#### C. 엣지 축 회전 낙하 (Edge Axis Rotation)
- **개념**: 특정 엣지를 회전축으로 삼아 회전각을 분할
- **제어 파라미터**:
  - `rotationAxis`: "top" | "bottom" | "left" | "right" (4개 주요 엣지)
  - `divisions`: 분할 개수 (예: 4, 8, 12, 24 등)
  - 회전 범위: 0° ~ 360° 균등 분할

- **예시**:
  - 상단 엣지 축, 8분할 → 0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°
  - 좌측 엣지 축, 4분할 → 0°, 90°, 180°, 270°

---

## 🔧 구현 계획

### Phase 1: 새로운 Analysis Type 추가

#### 1.1 Type 정의 확장
**파일**: `SimulationAutomationComponent.tsx`

```typescript
export type AnalysisType =
  | "fullAngleMBD"
  | "fullAngle"
  | "fullAngleCumulative"
  | "multiRepeatCumulative"
  | "dropWeightImpact"           // ✨ CHANGED: partialImpact → dropWeightImpact (낙추 충격)
  | "predefinedAttitudes"        // ✨ NEW: 사전정의 낙하 자세
  | "edgeAxisRotation";          // ✨ NEW: 엣지 축 회전

export type PredefinedMode =
  | "faces6"                     // 6면 낙하
  | "edges12"                    // 12엣지 낙하
  | "corners8"                   // 8코너 낙하
  | "all26";                     // 전체 26방향

export type EdgeAxis = "top" | "bottom" | "left" | "right";

export type ImpactGridMode =
  | "1x1"     // 중심 1개
  | "2x1"     // X방향 2개 (좌, 우)
  | "1x2"     // Y방향 2개 (상, 하)
  | "3x1"     // X방향 3개 (좌, 중, 우)
  | "1x3"     // Y방향 3개 (상, 중, 하)
  | "3x3";    // 3×3 그리드 (9개)

export type ImpactLocationMode =
  | "grid"         // 그리드 기반 (1x1, 2x1, 1x2, 3x1, 1x3, 3x3)
  | "percentage"   // 백분율 기반 (Xloc, Yloc 조합)
  | "random";      // 랜덤 생성

export type ImpactorType = "ball" | "cylinder";

export type CylinderDiameter = 8 | 15 | "custom";

export interface ScenarioRow {
  // ... 기존 필드들 ...

  params?: {
    // ... 기존 파라미터들 ...

    // predefinedAttitudes 전용
    predefinedMode?: PredefinedMode;
    predefinedHeight?: number;              // mm (고정 높이)
    predefinedSurface?: SurfaceType;

    // edgeAxisRotation 전용
    rotationAxis?: EdgeAxis;
    rotationDivisions?: number;             // 분할 개수 (4, 8, 12, 24, 36 등)
    rotationHeight?: number;                // mm (고정 높이)
    rotationSurface?: SurfaceType;

    // dropWeightImpact 전용
    impactPackagePatterns?: string[];       // 패키지 패턴 (와일드카드 지원)
    impactLocationMode?: ImpactLocationMode;
    impactGridMode?: ImpactGridMode;        // grid 모드일 때
    impactXLocations?: number[];            // percentage 모드일 때 (%, 0~100)
    impactYLocations?: number[];            // percentage 모드일 때 (%, 0~100)
    impactRandomCount?: number;             // random 모드일 때
    impactHeight?: number;                  // mm (낙추 높이)
    impactSurface?: SurfaceType;
    impactorType?: ImpactorType;            // 임팩터 형상 (ball | cylinder)
    impactorBallDiameter?: number;          // mm (ball 타입일 때, 기본 6mm)
    impactorCylinderDiameter?: CylinderDiameter | number;  // mm (cylinder 타입일 때, 8/15 또는 커스텀)
  };
}
```

#### 1.2 Analysis Options 확장
```typescript
const ANALYSIS_OPTIONS = [
  // ... 기존 옵션들 ...
  {
    label: "낙추 충격 (Drop Weight Impact)",
    value: "dropWeightImpact",
    hint: "실린더 임팩터를 이용한 특정 위치 충격"
  },
  {
    label: "사전정의 낙하 자세",
    value: "predefinedAttitudes",
    hint: "6면/12엣지/8코너/26방향 고정 자세"
  },
  {
    label: "엣지 축 회전",
    value: "edgeAxisRotation",
    hint: "특정 엣지를 축으로 회전 분할"
  },
];

const PREDEFINED_MODE_OPTIONS = [
  { label: "6면 낙하", value: "faces6" },
  { label: "12엣지 낙하", value: "edges12" },
  { label: "8코너 낙하", value: "corners8" },
  { label: "전체 26방향 낙하", value: "all26" },
];

const EDGE_AXIS_OPTIONS = [
  { label: "상단 엣지", value: "top" },
  { label: "하단 엣지", value: "bottom" },
  { label: "좌측 엣지", value: "left" },
  { label: "우측 엣지", value: "right" },
];

const ROTATION_DIVISIONS = [4, 8, 12, 16, 24, 36, 48, 72];

const IMPACT_GRID_OPTIONS = [
  { label: "1×1 (중심)", value: "1x1" },
  { label: "2×1 (X방향 좌우)", value: "2x1" },
  { label: "1×2 (Y방향 상하)", value: "1x2" },
  { label: "3×1 (X방향 좌중우)", value: "3x1" },
  { label: "1×3 (Y방향 상중하)", value: "1x3" },
  { label: "3×3 (9개 포인트)", value: "3x3" },
];

const IMPACT_LOCATION_MODE_OPTIONS = [
  { label: "그리드 기반", value: "grid" },
  { label: "백분율 기반", value: "percentage" },
  { label: "랜덤 생성", value: "random" },
];

const IMPACTOR_TYPE_OPTIONS = [
  { label: "Ball (구형)", value: "ball" },
  { label: "Cylinder (원통형)", value: "cylinder" },
];

const CYLINDER_DIAMETER_OPTIONS = [
  { label: "8mm (표준)", value: 8 },
  { label: "15mm (표준)", value: 15 },
  { label: "커스텀", value: "custom" },
];
```

---

### Phase 2: Predefined Angles 상수 정의

**파일**: `SimulationAutomationComponent.tsx`

```typescript
// 6면 낙하 자세 (Roll, Pitch, Yaw)
const FACE_ATTITUDES: Record<string, [number, number, number]> = {
  F1: [0, 0, 0],        // 전면 (디스플레이가 바닥)
  F2: [180, 0, 0],      // 배면
  F3: [90, 0, 0],       // 좌측면
  F4: [-90, 0, 0],      // 우측면
  F5: [0, -90, 0],      // 상단
  F6: [0, 90, 0],       // 하단
};

// 12엣지 낙하 자세
const EDGE_ATTITUDES: Record<string, [number, number, number]> = {
  E1: [-45, 0, 0],
  E2: [45, 0, 0],
  E3: [0, -45, 0],
  E4: [0, 45, 0],
  E5: [0, 0, -45],
  E6: [0, 0, 45],
  E7: [45, 45, 0],
  E8: [-45, -45, 0],
  E9: [0, 45, 45],
  E10: [0, -45, -45],
  E11: [45, 0, 45],
  E12: [-45, 0, -45],
};

// 8코너 낙하 자세
const CORNER_ATTITUDES: Record<string, [number, number, number]> = {
  C1: [-35.264, 45, 0],
  C2: [35.264, 45, 0],
  C3: [-35.264, -45, 0],
  C4: [35.264, -45, 0],
  C5: [-35.264, 45, 180],
  C6: [35.264, 45, 180],
  C7: [-35.264, -45, 180],
  C8: [35.264, -45, 180],
};

// 전체 26방향 (순서: F1~F6, E1~E12, C1~C8)
const ALL_26_ATTITUDES = {
  ...FACE_ATTITUDES,
  ...EDGE_ATTITUDES,
  ...CORNER_ATTITUDES,
};
```

---

### Phase 3: UI Controls 구현

#### 3.1 Drop Weight Impact Controls
**함수**: `renderDropWeightImpactControls(row: ScenarioRow)`

```typescript
const renderDropWeightImpactControls = (row: ScenarioRow, setScenarios: ...) => {
  const p = row.params || {};
  const patterns = p.impactPackagePatterns ?? ["*pkg*"];
  const locationMode: ImpactLocationMode = p.impactLocationMode ?? "grid";
  const gridMode: ImpactGridMode = p.impactGridMode ?? "1x1";
  const xLocs = p.impactXLocations ?? [50];
  const yLocs = p.impactYLocations ?? [50];
  const randomCount = p.impactRandomCount ?? 10;
  const height = p.impactHeight ?? 500; // mm
  const surface: SurfaceType = p.impactSurface ?? "steelPlate";
  const impactorType: ImpactorType = p.impactorType ?? "cylinder";
  const ballDiameter = p.impactorBallDiameter ?? 6; // mm
  const cylinderDiameter = p.impactorCylinderDiameter ?? 8; // mm or "custom"
  const isCustomCylinder = cylinderDiameter === "custom";

  // 패키지 패턴 입력 (태그 방식)
  const [patternInput, setPatternInput] = useState("");

  const addPattern = () => {
    if (patternInput.trim()) {
      setScenarios(prev => prev.map(r => r.id === row.id ? {
        ...r,
        params: {
          ...(r.params||{}),
          impactPackagePatterns: [...patterns, patternInput.trim()]
        }
      } : r));
      setPatternInput("");
    }
  };

  const removePattern = (index: number) => {
    setScenarios(prev => prev.map(r => r.id === row.id ? {
      ...r,
      params: {
        ...(r.params||{}),
        impactPackagePatterns: patterns.filter((_, i) => i !== index)
      }
    } : r));
  };

  // 충격 포인트 개수 계산
  const getImpactCount = () => {
    if (locationMode === "grid") {
      const [nx, ny] = gridMode.split("x").map(Number);
      return nx * ny;
    }
    if (locationMode === "percentage") {
      return xLocs.length * yLocs.length;
    }
    return randomCount;
  };

  return (
    <Flex vertical gap={10}>
      {/* 패키지 패턴 */}
      <Card size="small" title="타겟 패키지">
        <Space wrap>
          {patterns.map((p, i) => (
            <Tag
              key={i}
              closable
              onClose={() => removePattern(i)}
              color="blue"
            >
              {p}
            </Tag>
          ))}
        </Space>
        <Space.Compact style={{ width: "100%", marginTop: 8 }}>
          <Input
            size="small"
            placeholder="패턴 입력 (예: *pkg*, display, camera*)"
            value={patternInput}
            onChange={(e) => setPatternInput(e.target.value)}
            onPressEnter={addPattern}
          />
          <Button size="small" onClick={addPattern}>추가</Button>
        </Space.Compact>
        <Text type="secondary" style={{ fontSize: 11 }}>
          • *가 앞뒤 또는 중간에 있으면 와일드카드 매칭<br/>
          • 예: *pkg* (포함), display (정확), camera* (시작)
        </Text>
      </Card>

      {/* 충격 위치 모드 */}
      <Space wrap align="center">
        <Text>충격 위치 모드</Text>
        <Radio.Group
          size="small"
          value={locationMode}
          options={IMPACT_LOCATION_MODE_OPTIONS}
          onChange={(e) => setScenarios(prev => prev.map(r => r.id === row.id ? {
            ...r,
            params: { ...(r.params||{}), impactLocationMode: e.target.value }
          } : r))}
        />
      </Space>

      {/* Grid 모드 */}
      {locationMode === "grid" && (
        <Space wrap align="center">
          <Text>그리드 패턴</Text>
          <Select
            style={{ width: 180 }}
            value={gridMode}
            options={IMPACT_GRID_OPTIONS}
            onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
              ...r,
              params: { ...(r.params||{}), impactGridMode: v }
            } : r))}
          />
          <Tag color="geekblue">{getImpactCount()}개 포인트</Tag>
        </Space>
      )}

      {/* Percentage 모드 */}
      {locationMode === "percentage" && (
        <Flex vertical gap={8}>
          <Space wrap align="center">
            <Text>X 좌표 (%)</Text>
            <Select
              mode="tags"
              style={{ minWidth: 200 }}
              placeholder="예: 30, 50, 70"
              value={xLocs.map(String)}
              onChange={(vals) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                ...r,
                params: { ...(r.params||{}), impactXLocations: vals.map(Number).filter(n => !isNaN(n)) }
              } : r))}
            />
          </Space>
          <Space wrap align="center">
            <Text>Y 좌표 (%)</Text>
            <Select
              mode="tags"
              style={{ minWidth: 200 }}
              placeholder="예: 10, 60, 20"
              value={yLocs.map(String)}
              onChange={(vals) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                ...r,
                params: { ...(r.params||{}), impactYLocations: vals.map(Number).filter(n => !isNaN(n)) }
              } : r))}
            />
          </Space>
          <Tag color="geekblue">{getImpactCount()}개 포인트 (조합)</Tag>
          <Text type="secondary" style={{ fontSize: 11 }}>
            • XLoc, YLoc의 모든 조합 생성 (예: 3×3 = 9개)<br/>
            • 좌하단 기준 백분율 (0~100)
          </Text>
        </Flex>
      )}

      {/* Random 모드 */}
      {locationMode === "random" && (
        <Space wrap align="center">
          <Text>랜덤 포인트 개수</Text>
          <InputNumber
            size="small"
            min={1}
            max={100}
            value={randomCount}
            onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
              ...r,
              params: { ...(r.params||{}), impactRandomCount: Number(v ?? 10) }
            } : r))}
          />
          <Tag color="geekblue">LHS 샘플링</Tag>
        </Space>
      )}

      {/* 임팩터 설정 */}
      <Card size="small" title="임팩터 설정">
        <Flex vertical gap={8}>
          <Space wrap align="center">
            <Text>임팩터 형상</Text>
            <Radio.Group
              size="small"
              value={impactorType}
              options={IMPACTOR_TYPE_OPTIONS}
              onChange={(e) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                ...r,
                params: { ...(r.params||{}), impactorType: e.target.value }
              } : r))}
            />
          </Space>

          {/* Ball 설정 */}
          {impactorType === "ball" && (
            <Space wrap align="center">
              <Text>Ball 직경</Text>
              <InputNumber
                size="small"
                min={1}
                max={50}
                step={0.5}
                value={ballDiameter}
                addonAfter="mm"
                onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                  ...r,
                  params: { ...(r.params||{}), impactorBallDiameter: Number(v ?? 6) }
                } : r))}
              />
              <Tag color="blue">기본: 6mm</Tag>
            </Space>
          )}

          {/* Cylinder 설정 */}
          {impactorType === "cylinder" && (
            <Space wrap align="center">
              <Text>Cylinder 직경</Text>
              <Select
                size="small"
                style={{ width: 140 }}
                value={isCustomCylinder ? "custom" : cylinderDiameter}
                options={CYLINDER_DIAMETER_OPTIONS}
                onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                  ...r,
                  params: { ...(r.params||{}), impactorCylinderDiameter: v }
                } : r))}
              />
              {isCustomCylinder && (
                <InputNumber
                  size="small"
                  min={1}
                  max={100}
                  step={1}
                  value={typeof cylinderDiameter === "number" ? cylinderDiameter : 10}
                  addonAfter="mm"
                  onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                    ...r,
                    params: { ...(r.params||{}), impactorCylinderDiameter: Number(v ?? 10) }
                  } : r))}
                />
              )}
              <Tag color="blue">표준: 8mm, 15mm</Tag>
            </Space>
          )}
        </Flex>
      </Card>

      {/* 낙추 높이 및 표면 */}
      <Space wrap align="center">
        <Text>낙추 높이</Text>
        <InputNumber
          size="small"
          min={50}
          max={2000}
          step={50}
          value={height}
          addonAfter="mm"
          onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
            ...r,
            params: { ...(r.params||{}), impactHeight: Number(v ?? 500) }
          } : r))}
        />
        <Divider type="vertical" />
        <Text>표면</Text>
        <Select
          size="small"
          style={{ width: 180 }}
          value={surface}
          options={SURFACE_OPTIONS}
          onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
            ...r,
            params: { ...(r.params||{}), impactSurface: v }
          } : r))}
        />
      </Space>
    </Flex>
  );
};
```

#### 3.2 Predefined Attitudes Controls
**함수**: `renderPredefinedAttitudesControls(row: ScenarioRow)`

```typescript
const renderPredefinedAttitudesControls = (row: ScenarioRow, setScenarios: ...) => {
  const p = row.params || {};
  const mode: PredefinedMode = p.predefinedMode ?? "faces6";
  const height = p.predefinedHeight ?? 1500; // mm
  const surface: SurfaceType = p.predefinedSurface ?? "steelPlate";

  const attitudeCount =
    mode === "faces6" ? 6 :
    mode === "edges12" ? 12 :
    mode === "corners8" ? 8 :
    26; // all26

  return (
    <Flex vertical gap={10}>
      <Space wrap align="center">
        <Text>자세 모드</Text>
        <Select
          style={{ width: 180 }}
          value={mode}
          options={PREDEFINED_MODE_OPTIONS}
          onChange={(v) => setScenarios(...)}
        />
        <Tag color="blue">{attitudeCount}개 자세</Tag>
      </Space>

      <Space wrap align="center">
        <Text>낙하 높이</Text>
        <InputNumber
          size="small"
          min={100}
          max={5000}
          step={100}
          value={height}
          addonAfter="mm"
          onChange={(v) => setScenarios(...)}
        />
        <Divider type="vertical" />
        <Text>표면</Text>
        <Select
          size="small"
          style={{ width: 180 }}
          value={surface}
          options={SURFACE_OPTIONS}
          onChange={(v) => setScenarios(...)}
        />
      </Space>

      <Text type="secondary" style={{ fontSize: 12 }}>
        • 랜덤성 없이 정의된 자세로만 시뮬레이션 실행
        • 높이와 표면만 지정 가능 (각도는 자동 설정)
      </Text>
    </Flex>
  );
};
```

#### 3.3 Edge Axis Rotation Controls
**함수**: `renderEdgeAxisRotationControls(row: ScenarioRow)`

```typescript
const renderEdgeAxisRotationControls = (row: ScenarioRow, setScenarios: ...) => {
  const p = row.params || {};
  const axis: EdgeAxis = p.rotationAxis ?? "top";
  const divisions = p.rotationDivisions ?? 8;
  const height = p.rotationHeight ?? 1500; // mm
  const surface: SurfaceType = p.rotationSurface ?? "steelPlate";

  return (
    <Flex vertical gap={10}>
      <Space wrap align="center">
        <Text>회전축 엣지</Text>
        <Select
          style={{ width: 140 }}
          value={axis}
          options={EDGE_AXIS_OPTIONS}
          onChange={(v) => setScenarios(...)}
        />
        <Divider type="vertical" />
        <Text>분할 개수</Text>
        <Select
          style={{ width: 120 }}
          value={divisions}
          options={ROTATION_DIVISIONS.map(d => ({ label: `${d}분할`, value: d }))}
          onChange={(v) => setScenarios(...)}
        />
        <Tag color="geekblue">{divisions}개 자세 (360°/{divisions} = {360/divisions}°)</Tag>
      </Space>

      <Space wrap align="center">
        <Text>낙하 높이</Text>
        <InputNumber
          size="small"
          min={100}
          max={5000}
          step={100}
          value={height}
          addonAfter="mm"
          onChange={(v) => setScenarios(...)}
        />
        <Divider type="vertical" />
        <Text>표면</Text>
        <Select
          size="small"
          style={{ width: 180 }}
          value={surface}
          options={SURFACE_OPTIONS}
          onChange={(v) => setScenarios(...)}
        />
      </Space>

      <Text type="secondary" style={{ fontSize: 12 }}>
        • 선택한 엣지를 회전축으로 0°~360° 균등 분할
        • 예: 상단 엣지 8분할 → 0°, 45°, 90°, ..., 315°
      </Text>
    </Flex>
  );
};
```

#### 3.4 `renderOptionControls` 확장

```typescript
const renderOptionControls = (row: ScenarioRow) => {
  // ---- dropWeightImpact ----
  if (row.analysisType === "dropWeightImpact") {
    return renderDropWeightImpactControls(row, setScenarios);
  }

  // ---- predefinedAttitudes ----
  if (row.analysisType === "predefinedAttitudes") {
    return renderPredefinedAttitudesControls(row, setScenarios);
  }

  // ---- edgeAxisRotation ----
  if (row.analysisType === "edgeAxisRotation") {
    return renderEdgeAxisRotationControls(row, setScenarios);
  }

  // ... 기존 코드들 ...
};
```

---

### Phase 4: JSON Payload 생성 로직

#### 4.1 Drop Weight Impact JSON 포맷

**Grid 모드 (3x3 예시, Cylinder 8mm)**:
```json
{
  "id": "scn_1701234567_0",
  "name": "디스플레이 낙추 충격 (3x3)",
  "analysisType": "dropWeightImpact",
  "analysisLabel": "낙추 충격",
  "fileName": "smartphone.k",
  "params": {
    "impactPackagePatterns": ["*display*", "camera01"],
    "impactLocationMode": "grid",
    "impactGridMode": "3x3",
    "impactHeight": 500,
    "impactSurface": "steelPlate",
    "impactorType": "cylinder",
    "impactorCylinderDiameter": 8,
    "impactLocations": [
      { "xPercent": 16.7, "yPercent": 16.7, "packages": ["PKG_DISPLAY_01", "PKG_CAMERA01"] },
      { "xPercent": 50.0, "yPercent": 16.7, "packages": ["PKG_DISPLAY_01"] },
      { "xPercent": 83.3, "yPercent": 16.7, "packages": ["PKG_DISPLAY_01"] },
      { "xPercent": 16.7, "yPercent": 50.0, "packages": ["PKG_DISPLAY_01", "PKG_CAMERA01"] },
      { "xPercent": 50.0, "yPercent": 50.0, "packages": ["PKG_DISPLAY_01"] },
      { "xPercent": 83.3, "yPercent": 50.0, "packages": ["PKG_DISPLAY_01"] },
      { "xPercent": 16.7, "yPercent": 83.3, "packages": ["PKG_DISPLAY_01"] },
      { "xPercent": 50.0, "yPercent": 83.3, "packages": ["PKG_DISPLAY_01"] },
      { "xPercent": 83.3, "yPercent": 83.3, "packages": ["PKG_DISPLAY_01"] }
    ]
  }
}
```

**Percentage 모드 (Ball 6mm)**:
```json
{
  "id": "scn_1701234567_1",
  "name": "배터리 패키지 커스텀 위치",
  "analysisType": "dropWeightImpact",
  "analysisLabel": "낙추 충격",
  "fileName": "smartphone.k",
  "params": {
    "impactPackagePatterns": ["*battery*"],
    "impactLocationMode": "percentage",
    "impactXLocations": [30, 50, 70],
    "impactYLocations": [10, 60, 20],
    "impactHeight": 800,
    "impactSurface": "concrete",
    "impactorType": "ball",
    "impactorBallDiameter": 6,
    "impactLocations": [
      { "xPercent": 30, "yPercent": 10, "packages": ["PKG_BATTERY_MAIN"] },
      { "xPercent": 30, "yPercent": 60, "packages": ["PKG_BATTERY_MAIN"] },
      { "xPercent": 30, "yPercent": 20, "packages": ["PKG_BATTERY_MAIN"] },
      { "xPercent": 50, "yPercent": 10, "packages": ["PKG_BATTERY_MAIN"] },
      { "xPercent": 50, "yPercent": 60, "packages": ["PKG_BATTERY_MAIN"] },
      { "xPercent": 50, "yPercent": 20, "packages": ["PKG_BATTERY_MAIN"] },
      { "xPercent": 70, "yPercent": 10, "packages": ["PKG_BATTERY_MAIN"] },
      { "xPercent": 70, "yPercent": 60, "packages": ["PKG_BATTERY_MAIN"] },
      { "xPercent": 70, "yPercent": 20, "packages": ["PKG_BATTERY_MAIN"] }
    ]
  }
}
```

**Random 모드 (Cylinder 15mm)**:
```json
{
  "id": "scn_1701234567_2",
  "name": "다중 패키지 랜덤 충격",
  "analysisType": "dropWeightImpact",
  "analysisLabel": "낙추 충격",
  "fileName": "smartphone.k",
  "params": {
    "impactPackagePatterns": ["*pkg*", "display"],
    "impactLocationMode": "random",
    "impactRandomCount": 20,
    "impactHeight": 600,
    "impactSurface": "pavingBlock",
    "impactorType": "cylinder",
    "impactorCylinderDiameter": 15,
    "impactLocations": [
      { "xPercent": 23.4, "yPercent": 67.8, "packages": ["PKG_001", "PKG_DISPLAY_01"] },
      { "xPercent": 78.9, "yPercent": 12.3, "packages": ["PKG_002"] },
      // ... 20개 (LHS 샘플링)
    ]
  }
}
```

**와일드카드 매칭 헬퍼 함수**:
```typescript
// 패턴 매칭 함수
const matchesPattern = (packageName: string, pattern: string): boolean => {
  if (!pattern.includes("*")) {
    return packageName === pattern; // 정확 일치
  }

  const regex = new RegExp(
    "^" + pattern.split("*").map(s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$"
  );
  return regex.test(packageName);
};

// 패키지 필터링
const filterPackagesByPatterns = (
  allPackages: string[],
  patterns: string[]
): string[] => {
  return allPackages.filter(pkg =>
    patterns.some(pattern => matchesPattern(pkg, pattern))
  );
};

// Grid 좌표 생성
const generateGridLocations = (gridMode: ImpactGridMode): { x: number; y: number }[] => {
  const [nx, ny] = gridMode.split("x").map(Number);
  const locations: { x: number; y: number }[] = [];

  for (let i = 0; i < nx; i++) {
    for (let j = 0; j < ny; j++) {
      const x = nx === 1 ? 50 : (i / (nx - 1)) * 100;
      const y = ny === 1 ? 50 : (j / (ny - 1)) * 100;
      locations.push({ x, y });
    }
  }

  return locations;
};

// Percentage 조합 생성
const generatePercentageLocations = (
  xLocs: number[],
  yLocs: number[]
): { x: number; y: number }[] => {
  const locations: { x: number; y: number }[] = [];

  for (const x of xLocs) {
    for (const y of yLocs) {
      locations.push({ x, y });
    }
  }

  return locations;
};

// Random 위치 생성 (LHS)
const generateRandomLocations = (count: number): { x: number; y: number }[] => {
  const xSamples = generateLHSVariations(count, 50).map(v => v + 50); // 0~100
  const ySamples = generateLHSVariations(count, 50).map(v => v + 50);

  return xSamples.map((x, i) => ({ x, y: ySamples[i] }));
};
```

#### 4.2 Predefined Attitudes JSON 포맷

**실행 시 생성되는 JSON 구조**:

```json
{
  "id": "scn_1234567890",
  "name": "스마트폰 6면 낙하",
  "analysisType": "predefinedAttitudes",
  "analysisLabel": "사전정의 낙하 자세",
  "fileName": "smartphone.k",
  "params": {
    "predefinedMode": "faces6",
    "predefinedHeight": 1500,
    "predefinedSurface": "steelPlate",
    "attitudes": [
      {
        "id": "F1",
        "label": "전면",
        "eulerAngles": [0, 0, 0],
        "height": 1500
      },
      {
        "id": "F2",
        "label": "배면",
        "eulerAngles": [180, 0, 0],
        "height": 1500
      },
      // ... F3~F6
    ]
  }
}
```

**edges12 모드**:
```json
{
  "analysisType": "predefinedAttitudes",
  "params": {
    "predefinedMode": "edges12",
    "predefinedHeight": 1220,
    "predefinedSurface": "concrete",
    "attitudes": [
      {
        "id": "E1",
        "label": "엣지 1",
        "eulerAngles": [-45, 0, 0],
        "height": 1220
      },
      // ... E2~E12 (총 12개)
    ]
  }
}
```

**all26 모드**:
```json
{
  "analysisType": "predefinedAttitudes",
  "params": {
    "predefinedMode": "all26",
    "predefinedHeight": 1800,
    "predefinedSurface": "pavingBlock",
    "attitudes": [
      // F1~F6 (6개)
      // E1~E12 (12개)
      // C1~C8 (8개)
      // 총 26개
    ]
  }
}
```

#### 4.3 Edge Axis Rotation JSON 포맷

```json
{
  "id": "scn_9876543210",
  "name": "상단 엣지 8분할 회전",
  "analysisType": "edgeAxisRotation",
  "analysisLabel": "엣지 축 회전",
  "fileName": "smartphone.k",
  "params": {
    "rotationAxis": "top",
    "rotationDivisions": 8,
    "rotationHeight": 1500,
    "rotationSurface": "steelPlate",
    "attitudes": [
      {
        "index": 0,
        "angle": 0,
        "eulerAngles": [0, -90, 0],      // 상단 엣지 기준 0° 회전
        "height": 1500
      },
      {
        "index": 1,
        "angle": 45,
        "eulerAngles": [0, -90, 45],     // 45° 회전
        "height": 1500
      },
      // ... 8개 자세
    ]
  }
}
```

**회전 각도 계산 로직**:
```typescript
// 엣지별 기준 자세 (base attitude)
const EDGE_BASE_ATTITUDES: Record<EdgeAxis, [number, number, number]> = {
  top: [0, -90, 0],      // 상단 엣지가 바닥에 닿도록
  bottom: [0, 90, 0],    // 하단 엣지
  left: [90, 0, 0],      // 좌측 엣지
  right: [-90, 0, 0],    // 우측 엣지
};

const generateEdgeRotationAttitudes = (
  axis: EdgeAxis,
  divisions: number,
  height: number
) => {
  const baseAngles = EDGE_BASE_ATTITUDES[axis];
  const attitudes = [];

  for (let i = 0; i < divisions; i++) {
    const rotationAngle = (360 / divisions) * i;
    const eulerAngles = applyAxisRotation(baseAngles, axis, rotationAngle);

    attitudes.push({
      index: i,
      angle: rotationAngle,
      eulerAngles,
      height,
    });
  }

  return attitudes;
};
```

---

### Phase 5: Helper 함수 구현

Drop Weight Impact를 위한 헬퍼 함수들을 Phase 6에 추가합니다.

---

### Phase 6: `handleRun` 확장

**파일**: `SimulationAutomationComponent.tsx` (1100~1130줄)

```typescript
const handleRun = (ids?: string[]) => {
  const runIds = (ids && ids.length ? ids : selectedRowKeys) as string[];
  if (!runIds.length) return message.info("실행할 시나리오를 선택하세요.");

  const payload = scenarios.filter((s) => runIds.includes(s.id)).map((s) => {
    const basePayload = {
      id: s.id,
      name: s.name,
      analysisType: s.analysisType,
      analysisLabel: analysisLabel(s),
      fileName: s.fileName,
      objFileName: s.objFileName,
      params: s.params ?? {},
    };

    // ✨ Drop Weight Impact 처리
    if (s.analysisType === "dropWeightImpact") {
      const patterns = s.params?.impactPackagePatterns ?? ["*pkg*"];
      const locationMode = s.params?.impactLocationMode ?? "grid";

      let locations: { x: number; y: number }[] = [];

      if (locationMode === "grid") {
        const gridMode = s.params?.impactGridMode ?? "1x1";
        locations = generateGridLocations(gridMode);
      } else if (locationMode === "percentage") {
        const xLocs = s.params?.impactXLocations ?? [50];
        const yLocs = s.params?.impactYLocations ?? [50];
        locations = generatePercentageLocations(xLocs, yLocs);
      } else {
        const count = s.params?.impactRandomCount ?? 10;
        locations = generateRandomLocations(count);
      }

      // NOTE: 실제로는 서버에서 패키지 매칭을 수행하므로
      // 여기서는 패턴만 전달하고, impactLocations는 서버가 생성
      return {
        ...basePayload,
        params: {
          ...basePayload.params,
          impactLocations: locations.map(loc => ({
            xPercent: loc.x,
            yPercent: loc.y,
            packages: [], // 서버에서 채움
          })),
        },
      };
    }

    // ✨ Predefined Attitudes 처리
    if (s.analysisType === "predefinedAttitudes") {
      const mode = s.params?.predefinedMode ?? "faces6";
      const height = s.params?.predefinedHeight ?? 1500;
      const attitudes = generatePredefinedAttitudes(mode, height);

      return {
        ...basePayload,
        params: {
          ...basePayload.params,
          attitudes,
        },
      };
    }

    // ✨ Edge Axis Rotation 처리
    if (s.analysisType === "edgeAxisRotation") {
      const axis = s.params?.rotationAxis ?? "top";
      const divisions = s.params?.rotationDivisions ?? 8;
      const height = s.params?.rotationHeight ?? 1500;
      const attitudes = generateEdgeRotationAttitudes(axis, divisions, height);

      return {
        ...basePayload,
        params: {
          ...basePayload.params,
          attitudes,
        },
      };
    }

    return basePayload;
  });

  // ... 기존 Modal.confirm 로직 ...
};
```

---

### Phase 7: Helper 함수 구현 (기존 유지)

```typescript
// Predefined attitudes 생성
const generatePredefinedAttitudes = (
  mode: PredefinedMode,
  height: number
) => {
  let attitudeMap: Record<string, [number, number, number]> = {};

  switch (mode) {
    case "faces6":
      attitudeMap = FACE_ATTITUDES;
      break;
    case "edges12":
      attitudeMap = EDGE_ATTITUDES;
      break;
    case "corners8":
      attitudeMap = CORNER_ATTITUDES;
      break;
    case "all26":
      attitudeMap = ALL_26_ATTITUDES;
      break;
  }

  return Object.entries(attitudeMap).map(([id, angles]) => ({
    id,
    label: getLabelForId(id),
    eulerAngles: angles,
    height,
  }));
};

// ID에 대한 한글 라벨
const getLabelForId = (id: string): string => {
  if (id.startsWith("F")) return `면 ${id.substring(1)}`;
  if (id.startsWith("E")) return `엣지 ${id.substring(1)}`;
  if (id.startsWith("C")) return `코너 ${id.substring(1)}`;
  return id;
};

// 엣지 축 회전 자세 생성
const generateEdgeRotationAttitudes = (
  axis: EdgeAxis,
  divisions: number,
  height: number
) => {
  const baseAngles = EDGE_BASE_ATTITUDES[axis];
  const attitudes = [];

  for (let i = 0; i < divisions; i++) {
    const rotationAngle = (360 / divisions) * i;

    // 축에 따라 Yaw 회전 적용
    const eulerAngles: [number, number, number] = [
      baseAngles[0],
      baseAngles[1],
      baseAngles[2] + rotationAngle,
    ];

    attitudes.push({
      index: i,
      angle: rotationAngle,
      eulerAngles,
      height,
    });
  }

  return attitudes;
};
```

---

### Phase 8: analysisLabel 확장

```typescript
const analysisLabel = (row: ScenarioRow) => {
  if (row.analysisType === "dropWeightImpact") {
    const locationMode = row.params?.impactLocationMode ?? "grid";
    const count =
      locationMode === "grid" ?
        (row.params?.impactGridMode?.split("x").map(Number).reduce((a,b)=>a*b, 1) ?? 1) :
      locationMode === "percentage" ?
        ((row.params?.impactXLocations?.length ?? 1) * (row.params?.impactYLocations?.length ?? 1)) :
        (row.params?.impactRandomCount ?? 10);
    return `낙추 충격 (${count}개)`;
  }

  if (row.analysisType === "predefinedAttitudes") {
    const mode = row.params?.predefinedMode;
    if (mode === "faces6") return "6면 낙하";
    if (mode === "edges12") return "12엣지 낙하";
    if (mode === "corners8") return "8코너 낙하";
    if (mode === "all26") return "26방향 낙하";
    return "사전정의 낙하 자세";
  }

  if (row.analysisType === "edgeAxisRotation") {
    const axis = row.params?.rotationAxis ?? "top";
    const divisions = row.params?.rotationDivisions ?? 8;
    const axisLabel =
      axis === "top" ? "상단" :
      axis === "bottom" ? "하단" :
      axis === "left" ? "좌측" : "우측";
    return `${axisLabel} 엣지 ${divisions}분할`;
  }

  // ... 기존 코드 ...
};
```

---

## 📄 최종 JSON 출력 예시

### 예시 1: 6면 낙하
```json
{
  "id": "scn_1701234567_0",
  "name": "iPhone 15 Pro 6면 낙하",
  "analysisType": "predefinedAttitudes",
  "analysisLabel": "6면 낙하",
  "fileName": "iphone15_pro.k",
  "params": {
    "predefinedMode": "faces6",
    "predefinedHeight": 1500,
    "predefinedSurface": "steelPlate",
    "attitudes": [
      { "id": "F1", "label": "면 1", "eulerAngles": [0, 0, 0], "height": 1500 },
      { "id": "F2", "label": "면 2", "eulerAngles": [180, 0, 0], "height": 1500 },
      { "id": "F3", "label": "면 3", "eulerAngles": [90, 0, 0], "height": 1500 },
      { "id": "F4", "label": "면 4", "eulerAngles": [-90, 0, 0], "height": 1500 },
      { "id": "F5", "label": "면 5", "eulerAngles": [0, -90, 0], "height": 1500 },
      { "id": "F6", "label": "면 6", "eulerAngles": [0, 90, 0], "height": 1500 }
    ]
  }
}
```

### 예시 2: 전체 26방향 낙하
```json
{
  "id": "scn_1701234567_1",
  "name": "Samsung Galaxy S24 전방향 낙하",
  "analysisType": "predefinedAttitudes",
  "analysisLabel": "26방향 낙하",
  "fileName": "galaxy_s24.k",
  "params": {
    "predefinedMode": "all26",
    "predefinedHeight": 1220,
    "predefinedSurface": "concrete",
    "attitudes": [
      { "id": "F1", "label": "면 1", "eulerAngles": [0, 0, 0], "height": 1220 },
      { "id": "F2", "label": "면 2", "eulerAngles": [180, 0, 0], "height": 1220 },
      // ... F3~F6 (총 6개)
      { "id": "E1", "label": "엣지 1", "eulerAngles": [-45, 0, 0], "height": 1220 },
      { "id": "E2", "label": "엣지 2", "eulerAngles": [45, 0, 0], "height": 1220 },
      // ... E3~E12 (총 12개)
      { "id": "C1", "label": "코너 1", "eulerAngles": [-35.264, 45, 0], "height": 1220 },
      { "id": "C2", "label": "코너 2", "eulerAngles": [35.264, 45, 0], "height": 1220 },
      // ... C3~C8 (총 8개)
    ]
  }
}
```

### 예시 3: 상단 엣지 12분할 회전
```json
{
  "id": "scn_1701234567_2",
  "name": "상단 엣지 회전 테스트",
  "analysisType": "edgeAxisRotation",
  "analysisLabel": "상단 엣지 12분할",
  "fileName": "smartphone.k",
  "params": {
    "rotationAxis": "top",
    "rotationDivisions": 12,
    "rotationHeight": 1800,
    "rotationSurface": "pavingBlock",
    "attitudes": [
      { "index": 0, "angle": 0, "eulerAngles": [0, -90, 0], "height": 1800 },
      { "index": 1, "angle": 30, "eulerAngles": [0, -90, 30], "height": 1800 },
      { "index": 2, "angle": 60, "eulerAngles": [0, -90, 60], "height": 1800 },
      { "index": 3, "angle": 90, "eulerAngles": [0, -90, 90], "height": 1800 },
      // ... 12개 (30도 간격)
    ]
  }
}
```

---

## 🔄 Component vs Page 변경 사항

### Component 레벨 (`SimulationAutomationComponent.tsx`)

**변경/추가 사항**:
1. ✅ Type 정의 확장 (`AnalysisType`, `PredefinedMode`, `EdgeAxis`)
2. ✅ 상수 정의 (`FACE_ATTITUDES`, `EDGE_ATTITUDES`, `CORNER_ATTITUDES`)
3. ✅ UI Controls 함수 추가 (`renderPredefinedAttitudesControls`, `renderEdgeAxisRotationControls`)
4. ✅ Helper 함수 추가 (`generatePredefinedAttitudes`, `generateEdgeRotationAttitudes`)
5. ✅ `handleRun` 확장 (새 타입 처리 로직)
6. ✅ `analysisLabel` 확장
7. ✅ `ANALYSIS_OPTIONS` 배열 확장

**영향 범위**:
- 약 200~300줄 추가
- 기존 코드 호환성 유지
- 독립적인 기능 추가 (기존 타입에 영향 없음)

### Page 레벨 (`SimulationAutomationPage.tsx`)

**변경 사항**:
- ❌ **변경 없음** (Component만 확장하면 자동 반영)
- Page는 단순히 `<SimulationAutomationComponent />`를 렌더링하므로 별도 수정 불필요

---

## 📊 데이터 흐름

```
사용자 입력 (UI Controls)
    ↓
ScenarioRow.params 업데이트
    ↓
handleRun 호출
    ↓
analysisType 분기 처리
    ↓
generatePredefinedAttitudes() 또는 generateEdgeRotationAttitudes()
    ↓
JSON Payload 생성 (attitudes 배열 포함)
    ↓
Modal 확인
    ↓
API 전송 (미래 구현)
```

---

## ✅ 체크리스트

### 구현 순서
1. [ ] Type 정의 추가
   - `AnalysisType` (dropWeightImpact 추가, partialImpact → dropWeightImpact 변경)
   - `PredefinedMode`, `EdgeAxis`
   - `ImpactGridMode`, `ImpactLocationMode`
2. [ ] 상수 정의
   - Predefined: `FACE_ATTITUDES`, `EDGE_ATTITUDES`, `CORNER_ATTITUDES`, `EDGE_BASE_ATTITUDES`
   - Impact: `IMPACT_GRID_OPTIONS`, `IMPACT_LOCATION_MODE_OPTIONS`
3. [ ] Helper 함수 구현
   - Predefined: `generatePredefinedAttitudes`, `generateEdgeRotationAttitudes`
   - Impact: `matchesPattern`, `filterPackagesByPatterns`, `generateGridLocations`, `generatePercentageLocations`, `generateRandomLocations`
4. [ ] UI Controls 함수 구현
   - `renderDropWeightImpactControls`
   - `renderPredefinedAttitudesControls`
   - `renderEdgeAxisRotationControls`
5. [ ] `renderOptionControls` 확장 (3개 타입 추가)
6. [ ] `analysisLabel` 확장 (3개 타입 추가)
7. [ ] `handleRun` 확장 (3개 타입 처리)
8. [ ] `ANALYSIS_OPTIONS` 배열 확장
9. [ ] 테스트 (각 모드별 JSON 출력 확인)

### 테스트 시나리오
**Drop Weight Impact**:
- [ ] Grid 1x1 JSON 생성 (Cylinder 8mm)
- [ ] Grid 3x3 JSON 생성 (Cylinder 8mm)
- [ ] Percentage 모드 (3×3 조합) JSON 생성 (Ball 6mm)
- [ ] Random 모드 (20개) JSON 생성 (Cylinder 15mm)
- [ ] 커스텀 직경 설정 (Ball 10mm, Cylinder 20mm)
- [ ] 와일드카드 패턴 매칭 (*pkg*, camera*, *battery) 테스트
- [ ] 임팩터 타입 전환 (Ball ↔ Cylinder) 테스트

**Predefined Attitudes**:
- [ ] 6면 낙하 JSON 생성
- [ ] 12엣지 낙하 JSON 생성
- [ ] 8코너 낙하 JSON 생성
- [ ] 26방향 낙하 JSON 생성

**Edge Axis Rotation**:
- [ ] 상단 엣지 8분할 JSON 생성
- [ ] 하단/좌측/우측 엣지 회전 JSON 생성

**통합**:
- [ ] Export/Import 호환성 확인
- [ ] 기존 타입과의 호환성 확인

---

## 🎯 핵심 차별점

### 기존 타입 vs 새 타입 비교

| 특징 | 기존 타입 (fullAngle 등) | dropWeightImpact | predefined/edgeRotation |
|------|-------------------------|------------------|------------------------|
| 랜덤성 | LHS 샘플링 (랜덤) | 선택 가능 (grid/percentage/random) | 없음 (고정 자세) |
| 테스트 대상 | 전체 제품 낙하 | 특정 패키지 충격 | 전체 제품 낙하 |
| 위치 지정 | 각도 (Euler) | XY 좌표 (%) | 각도 (Euler) |
| 각도 지정 | 자동 생성 | N/A | 사전 정의 |
| 파라미터 | 총 개수, 분포 옵션 | 패키지 패턴, 위치 모드 | 모드 선택만 |
| 높이 | LHS 범위 가능 | 고정값만 | 고정값만 |
| 용도 | 통계적 분석 | 취약 부품 테스트 | 표준 테스트 |

---

## 📝 추가 고려사항

### 1. Drop Weight Impact 관련
- **패키지 정보 소스**: 서버에서 K 파일 파싱하여 패키지 목록 추출
- **와일드카드 처리**: 클라이언트에서 UI 표시용, 실제 매칭은 서버
- **임팩터 형상**:
  - **Ball (구형)**: 직경 6mm (기본), 1~50mm 범위에서 커스텀 가능
  - **Cylinder (원통형)**: 직경 8mm, 15mm (표준), 또는 1~100mm 커스텀
  - 높이/길이는 서버 기본값 또는 추후 추가 파라미터
- **충격 각도**: 수직 충격 (z축 방향)만 지원, 추후 각도 옵션 추가 가능
- **임팩터 질량**: 직경과 형상에 따라 서버에서 자동 계산 (재질 밀도 기반)

### 2. Tolerance (각도 변동 허용)
- 새 타입(predefined, edgeRotation, dropWeightImpact)에서는 **지원하지 않음**
- Predefined는 고정 자세만 사용하므로 tolerance 설정 불필요
- Drop Weight Impact는 위치만 지정하므로 각도 tolerance 무관

### 3. 기존 결과 재사용
- `angleSource: "usePrevResult"`는 새 타입에서 **지원하지 않음**
- Predefined는 항상 독립적인 자세 사용
- Drop Weight Impact는 각도 개념 없음

### 4. 표면/높이 외 초기 속도
- 현재 계획에는 초기 속도(Vx, Vy, Vz) 및 각속도(ωx, ωy, ωz) 파라미터 없음
- Drop Weight Impact는 낙추 충격이므로 초기 속도 0
- 필요시 Phase 2에서 추가 가능

### 5. 시각화
- DropAttitudeGenerator처럼 3D 시각화 추가 고려 가능
- React-Plotly.js로 자세 미리보기 제공 가능
- Drop Weight Impact: 패키지 위치에 충격 포인트 오버레이 표시

---

## 🚀 향후 확장 가능성

### Drop Weight Impact 관련
1. **임팩터 형상 확장**: 반구(hemisphere), 평판(flat), 원추형(cone) 등 추가
2. **임팩터 높이/길이 설정**: Cylinder의 높이, Ball의 반경 등 세밀한 제어
3. **충격 각도 설정**: 수직 외 경사 충격 (15°, 30°, 45° 등)
4. **임팩터 속도 제어**: 낙하 높이 외 초기 속도 직접 지정
5. **임팩터 재질 설정**: 강철, 플라스틱, 고무 등 재질별 밀도/강성 선택
6. **다중 임팩터**: 동시 다발 충격 시뮬레이션
7. **패키지 강도 분석**: 충격 후 변형/응력 자동 분석
8. **위치 히트맵**: 패키지별 취약 위치 시각화

### Predefined Attitudes 관련
1. **커스텀 자세 정의**: 사용자가 직접 Roll/Pitch/Yaw 입력
2. **자세 세트 저장**: 자주 사용하는 자세 조합을 프리셋으로 저장
3. **자세 시각화**: 실시간 3D 미리보기
4. **회전 보간**: 두 자세 사이를 부드럽게 보간
5. **충격 위치 지정**: 특정 면/엣지/코너의 특정 지점 지정

### 통합
1. **혼합 시나리오**: Drop + Attitude 조합 (특정 자세에서 특정 패키지 충격)
2. **시퀀스 정의**: 다단계 충격 시나리오 (1차 낙하 → 2차 충격)
3. **조건부 실행**: 이전 결과에 따라 다음 테스트 결정

---

## 📌 요약

이 계획서는 SimulationAutomationPage에 **3개의 새로운 분석 타입**을 추가합니다:

### 1️⃣ Drop Weight Impact (낙추 충격)
- **변경**: `partialImpact` → `dropWeightImpact` (이름 변경 + 기능 재정의)
- **목적**: Ball 또는 Cylinder 임팩터를 이용한 특정 패키지 충격 시험
- **핵심 기능**:
  - 와일드카드 패턴 매칭 (`*pkg*`, `camera*`, `*battery`)
  - 3가지 위치 모드: Grid (1x1~3x3), Percentage (커스텀%), Random (LHS)
  - 2가지 임팩터 형상:
    - **Ball**: 직경 6mm (기본), 1~50mm 커스텀
    - **Cylinder**: 직경 8mm/15mm (표준), 1~100mm 커스텀
  - 패키지별 XY 좌표 지정

### 2️⃣ Predefined Attitudes (사전정의 낙하 자세)
- **목적**: 표준 테스트를 위한 고정 낙하 자세
- **핵심 기능**:
  - 6면, 12엣지, 8코너, 26방향 (DropAttitudeGenerator 기반)
  - 랜덤성 없음, 재현 가능한 테스트
  - 높이/표면만 설정

### 3️⃣ Edge Axis Rotation (엣지 축 회전)
- **목적**: 특정 엣지를 축으로 회전 분할
- **핵심 기능**:
  - 상단/하단/좌측/우측 엣지 선택
  - 0°~360° 균등 분할 (4, 8, 12, 24분할 등)
  - 고정 자세 세트 생성

### 구현 영향
- **Component 레벨**: ~600줄 추가 (Type, UI, Helper 함수)
  - Type 정의: ~50줄 (ImpactorType, CylinderDiameter 등)
  - UI Controls: ~200줄 (임팩터 설정 UI 포함)
  - Helper 함수: ~150줄
  - JSON 생성 로직: ~200줄
- **Page 레벨**: 변경 없음 (자동 반영)
- **기존 코드**: 호환성 유지, 독립적 추가
