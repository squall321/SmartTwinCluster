import React, { useMemo, useRef, useState } from "react";
import type { UploadProps } from "antd";
import { Button, Card, Divider, Flex, Input, InputNumber, Modal, Radio, Select, Space, Switch, Table, Tag, Typography, Upload, message } from "antd";
import type { ColumnsType } from "antd/es/table";
import { DeleteOutlined, InboxOutlined, PlayCircleOutlined, PlusOutlined, SaveOutlined, UploadOutlined } from "@ant-design/icons";
import StandardScenarioModal from "./StandardScenarioModal";
import type { StandardScenario } from "../../types/standardScenario";

const { Dragger } = Upload;
const { Title, Text } = Typography;

// ---- Types ----
export type AnalysisType =
  | "fullAngleMBD" // 전각도 다물체동역학 낙하 시뮬레이션
  | "fullAngle"    // 전각도 낙하 시뮬레이션
  | "fullAngleCumulative" // 전각도 누적 낙하
  | "multiRepeatCumulative" // 다회 누적 낙하
  | "dropWeightImpact"        // 낙하 중량 충격 시뮬레이션 (renamed from partialImpact)
  | "predefinedAttitudes"     // 사전 정의 낙하 자세
  | "edgeAxisRotation";       // 엣지 축 회전

export type PartialImpactMode = "default" | "txt";
export type AngleSource = "lhs" | "fromMBD" | "usePrevResult"; // LHS 기본, 기존 결과 사용
export type HeightMode = "const" | "lhs"; // 낙하 높이 모드
export type SurfaceType = "steelPlate" | "pavingBlock" | "concrete" | "wood";

// New types for the 3 new analysis modes
export type PredefinedMode = "faces6" | "edges12" | "corners8" | "all26";
export type EdgeAxis = "top" | "bottom" | "left" | "right";
export type ImpactGridMode = "1x1" | "2x1" | "1x2" | "3x1" | "1x3" | "3x3";
export type ImpactLocationMode = "grid" | "percentage" | "random";
export type ImpactorType = "ball" | "cylinder";
export type CylinderDiameter = 8 | 15 | "custom";

export type CumDirection =
  | `F${1|2|3|4|5|6}`  // 6 faces
  | `E${1|2|3|4|5|6|7|8|9|10|11|12}` // 12 edges
  | `C${1|2|3|4|5|6|7|8}`; // 8 corners

// Tolerance types for angle variation
export type ToleranceMode = "disabled" | "enabled";
export type ToleranceSettings = {
  mode: ToleranceMode;
  faceTolerance?: number;    // degrees
  edgeTolerance?: number;    // degrees  
  cornerTolerance?: number;  // degrees
};

export interface ScenarioRow {
  id: string;
  name: string;
  description?: string; // 시나리오 설명
  fileName?: string; // K 파일명
  file?: File;       // K 파일 객체
  objFileName?: string; // OBJ 파일명(MBD용)
  objFile?: File;       // OBJ 파일 객체
  analysisType: AnalysisType;
  params?: {
    // 공통(각도/높이/표면)
    angleSource?: AngleSource; // 기본 lhs (FA/MBD에서 사용)
    angleSourceId?: string; // 기존 결과로 선택한 시나리오 id (MBD/FA 공용)
    angleSourceFileName?: string; // 업로드 파일명(선택)
    angleSourceFile?: File; // 업로드 파일(선택)

    // 높이(모든 전각도 해석 공통)
    heightMode?: HeightMode; // const | lhs
    heightConst?: number;    // m
    heightMin?: number;      // m (when lhs)
    heightMax?: number;      // m (when lhs)

    // 낙하 표면(모든 전각도 해석 공통)
    surface?: SurfaceType;

    // fullAngleMBD 전용
    mbdCount?: number;

    // fullAngle 전용
    faTotal?: number; // 10..1000 among predefined
    includeFace6?: boolean;
    includeEdge12?: boolean;
    includeCorner8?: boolean;

    // fullAngleCumulative 전용
    cumRepeatCount?: 2|3|4|5; // 열 수(낙하 시나리오 개수)
    cumDOECount?: number;     // 행 수(DOE 개수)
    cumDirections?: CumDirection[]; // (구버전 호환) 1D
    cumDirectionsGrid?: CumDirection[][]; // 2D [DOE][repeat]

    // multiRepeatCumulative 전용
    multiRepeatCount?: number;           // 회수 (기본 24)
    multiRepeatDirections?: CumDirection[]; // 1D 배열 [repeat]

    // dropWeightImpact 전용 (renamed from partialImpact)
    piMode?: PartialImpactMode;
    piTxtName?: string; // uploaded filename
    piTxtFile?: File;
    impactPackagePatterns?: string[];    // Wildcard patterns for packages (e.g., ["*pkg*", "display", "camera*"])
    impactLocationMode?: ImpactLocationMode; // grid | percentage | random
    impactGridMode?: ImpactGridMode;     // 1x1, 2x1, 1x2, 3x1, 1x3, 3x3
    impactPercentageX?: number;          // 0-100 (deprecated, for backward compatibility)
    impactPercentageY?: number;          // 0-100 (deprecated, for backward compatibility)
    impactLocations?: Array<{x: number, y: number}>; // Array of (x%, y%) coordinates (when locationMode = percentage)
    impactGridRows?: number;             // Number of rows for auto grid calculation
    impactGridCols?: number;             // Number of columns for auto grid calculation
    applyEdgeMargin?: boolean;           // Apply edge margin (spacing/2) when using percentage mode
    impactPackageWidth?: number;         // Package width in mm (for visualization aspect ratio)
    impactPackageHeight?: number;        // Package height in mm (for visualization aspect ratio)
    impactRandomCount?: number;          // LHS sample count (when locationMode = random)
    impactorType?: ImpactorType;         // ball | cylinder
    impactorBallDiameter?: number;       // 1-50mm, default 6mm
    impactorCylinderDiameter?: CylinderDiameter | number; // 8 | 15 | custom (1-100mm)
    impactorCylinderDiameterCustom?: number; // 1-100mm (when cylinderDiameter = custom)

    // predefinedAttitudes 전용
    predefinedMode?: PredefinedMode;     // faces6 | edges12 | corners8 | all26
    predefinedAngles?: Array<{name: string, phi: number, theta: number, psi: number}>; // Custom angles

    // edgeAxisRotation 전용
    edgeAxis?: EdgeAxis;                 // top | bottom | left | right
    edgeDivisions?: number;              // Number of rotation angles (default 12)

    // Tolerance settings (공통)
    tolerance?: ToleranceSettings;
  };
}

// Helper for ids (no external dep)
let idCounter = 0;
const uid = (prefix = "row"): string => `${prefix}_${Date.now()}_${idCounter++}`;

const ANALYSIS_OPTIONS: { label: string; value: AnalysisType; hint: string }[] = [
  { label: "전각도 다물체동역학 낙하", value: "fullAngleMBD", hint: "PyBullet/Chrono 등 MBD 기반" },
  { label: "전각도 낙하", value: "fullAngle", hint: "Explicit FE 단발/배치" },
  { label: "전각도 누적 낙하", value: "fullAngleCumulative", hint: "DOE(행) × 회수(열) 매트릭스" },
  { label: "다회 누적 낙하", value: "multiRepeatCumulative", hint: "DOE 없이 회수만 지정" },
  { label: "낙하 중량 충격", value: "dropWeightImpact", hint: "패키지 위치별 Ball/Cylinder 충격" },
  { label: "사전 정의 낙하 자세", value: "predefinedAttitudes", hint: "6면/12엣지/8코너 조합" },
  { label: "엣지 축 회전", value: "edgeAxisRotation", hint: "엣지 기준 회전 각도 분할" },
];

// Direction option sets
const FACE_DIRS = Array.from({ length: 6 }, (_, i) => `F${i+1}` as CumDirection);
const EDGE_DIRS = Array.from({ length: 12 }, (_, i) => `E${i+1}` as CumDirection);
const CORNER_DIRS = Array.from({ length: 8 }, (_, i) => `C${i+1}` as CumDirection);
const ALL_DIRS: CumDirection[] = [...FACE_DIRS, ...EDGE_DIRS, ...CORNER_DIRS]; // 26개

const SURFACE_OPTIONS: { label: string; value: SurfaceType }[] = [
  { label: "철판(steel plate)", value: "steelPlate" },
  { label: "보도블럭(paving block)", value: "pavingBlock" },
  { label: "콘크리트(concrete)", value: "concrete" },
  { label: "목재(wood)", value: "wood" },
];

const DEFAULT_DESCRIPTIONS: Record<AnalysisType, string> = {
  "fullAngleMBD": "다물체 동역학을 고려한 전각도 낙하 시험. 다양한 각도에서의 충격 시뮬레이션을 수행합니다.",
  "fullAngle": "전각도 낙하 시험. 주요 각도에서의 충격 특성을 평가합니다.",
  "fullAngleCumulative": "전각도 누적 낙하 시험. 반복 충격에 대한 내구성을 평가합니다.",
  "multiRepeatCumulative": "여러 방향에서의 다회 누적 낙하 시험. 다양한 각도에서의 반복 충격 내구성을 종합 평가합니다.",
  "dropWeightImpact": "낙하 중량 충격 시험. 다양한 중량의 낙하물에 대한 충격 저항성을 평가합니다.",
  "predefinedAttitudes": "사전 정의 낙하 자세 시험. 실제 사고 시나리오를 반영한 다양한 자세에서의 충격 특성을 평가합니다.",
  "edgeAxisRotation": "엣지 축 회전 충격 시험. 회전 충격에 대한 저항성과 안정성을 평가합니다.",
};

const dirLabel = (d: CumDirection) =>
  d.startsWith("F") ? `면 ${d.substring(1)}` : d.startsWith("E") ? `엣지 ${d.substring(1)}` : `코너 ${d.substring(1)}`;

const analysisLabel = (row: ScenarioRow) => {
  if (row.analysisType === "fullAngle") {
    if (row.params?.angleSource === "usePrevResult") return "전각도 누적 낙하";
    return "전각도 낙하";
  }
  if (row.analysisType === "fullAngleCumulative") return "전각도 누적 낙하";
  if (row.analysisType === "multiRepeatCumulative") return "다회 누적 낙하";
  if (row.analysisType === "fullAngleMBD") return "전각도 다물체동역학 낙하";
  if (row.analysisType === "dropWeightImpact") return "낙하 중량 충격";
  if (row.analysisType === "predefinedAttitudes") return "사전 정의 낙하 자세";
  if (row.analysisType === "edgeAxisRotation") return "엣지 축 회전";
  return "알 수 없는 해석 타입";
};

// Predefined counts
const MBD_COUNTS = [1000, 5000, 10000, 50000, 100000, 200000, 500000, 1000000, 2000000, 5000000];
const FULL_ANGLE_COUNTS = [10, 50, 100, 200, 300, 400, 500, 600, 800, 1000];
const DOE_COUNTS = [1,2,3,5,10,20,30,50,100,200,300,500,1000];

// Generate evenly spaced grid coordinates
const generateGridLocations = (rows: number, cols: number, applyEdgeMargin: boolean = false): Array<{x: number, y: number}> => {
  const locations: Array<{x: number, y: number}> = [];

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      let x: number, y: number;

      if (applyEdgeMargin) {
        // Apply edge margin: spacing/2 from edges
        const xSpacing = cols === 1 ? 0 : 100 / (cols - 1);
        const ySpacing = rows === 1 ? 0 : 100 / (rows - 1);
        const xMargin = xSpacing / 2;
        const yMargin = ySpacing / 2;

        if (cols === 1) {
          x = 50; // Center if only one column
        } else {
          // Map [0, cols-1] to [xMargin, 100-xMargin]
          x = xMargin + (c / (cols - 1)) * (100 - 2 * xMargin);
        }

        if (rows === 1) {
          y = 50; // Center if only one row
        } else {
          // Map [0, rows-1] to [yMargin, 100-yMargin]
          y = yMargin + (r / (rows - 1)) * (100 - 2 * yMargin);
        }
      } else {
        // Original behavior: 0% to 100%
        x = cols === 1 ? 50 : (c / (cols - 1)) * 100;
        y = rows === 1 ? 50 : (r / (rows - 1)) * 100;
      }

      locations.push({ x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10 });
    }
  }
  return locations;
};

// Calculate grid dimensions from sample count
const calculateGridDimensions = (sampleCount: number): {rows: number, cols: number} => {
  const cols = Math.floor(Math.sqrt(sampleCount));
  const rows = Math.ceil(sampleCount / cols);
  return { rows, cols };
};

// Predefined drop attitudes (Roll, Pitch, Yaw) - based on DropAttitudeGenerator.tsx
// Coordinate system: Display facing +Z, origin at bottom center of device
const FACE_ATTITUDES: [number, number, number][] = [
  [0, 0, 0],        // 전면 (Front - display)
  [180, 0, 0],      // 배면 (Back)
  [90, 0, 0],       // 좌측면 (Left side)
  [-90, 0, 0],      // 우측면 (Right side)
  [0, -90, 0],      // 상단 (Top)
  [0, 90, 0],       // 하단 (Bottom)
];

const EDGE_ATTITUDES: [number, number, number][] = [
  [-45, 0, 0],      // 엣지 1
  [45, 0, 0],       // 엣지 2
  [0, -45, 0],      // 엣지 3
  [0, 45, 0],       // 엣지 4
  [0, 0, -45],      // 엣지 5
  [0, 0, 45],       // 엣지 6
  [45, 45, 0],      // 엣지 7
  [-45, -45, 0],    // 엣지 8
  [0, 45, 45],      // 엣지 9
  [0, -45, -45],    // 엣지 10
  [45, 0, 45],      // 엣지 11
  [-45, 0, -45],    // 엣지 12
];

const CORNER_ATTITUDES: [number, number, number][] = [
  [-35.264, 45, 0],     // 코너 1
  [35.264, 45, 0],      // 코너 2
  [-35.264, -45, 0],    // 코너 3
  [35.264, -45, 0],     // 코너 4
  [-35.264, 45, 180],   // 코너 5
  [35.264, 45, 180],    // 코너 6
  [-35.264, -45, 180],  // 코너 7
  [35.264, -45, 180],   // 코너 8
];

// Impact grid options
const IMPACT_GRID_OPTIONS: { label: string; value: ImpactGridMode }[] = [
  { label: "1×1 (중앙)", value: "1x1" },
  { label: "2×1 (가로 2열)", value: "2x1" },
  { label: "1×2 (세로 2열)", value: "1x2" },
  { label: "3×1 (가로 3열)", value: "3x1" },
  { label: "1×3 (세로 3열)", value: "1x3" },
  { label: "3×3 (9포인트)", value: "3x3" },
];

// Edge axis options
const EDGE_AXIS_OPTIONS: { label: string; value: EdgeAxis }[] = [
  { label: "상단 엣지", value: "top" },
  { label: "하단 엣지", value: "bottom" },
  { label: "좌측 엣지", value: "left" },
  { label: "우측 엣지", value: "right" },
];

// Edge divisions (number of rotation angles)
const EDGE_DIVISION_COUNTS = [4, 6, 8, 12, 16, 24, 36, 48, 72];

const bytesToString = async (f: File) => new Promise<string>((res, rej) => {
  const reader = new FileReader();
  reader.onload = () => res(String(reader.result || ""));
  reader.onerror = rej;
  reader.readAsText(f);
});

// LHS sampling for angle variations
const generateLHSVariations = (count: number, maxTolerance: number): number[] => {
  if (maxTolerance <= 0) return new Array(count).fill(0);
  
  const variations: number[] = [];
  for (let i = 0; i < count; i++) {
    // LHS sampling: divide range into equal intervals and sample randomly within each
    const interval = (2 * maxTolerance) / count; // -maxTolerance to +maxTolerance
    const base = -maxTolerance + i * interval;
    const random = Math.random() * interval;
    variations.push(base + random);
  }
  
  // Shuffle to avoid correlation with order
  for (let i = variations.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [variations[i], variations[j]] = [variations[j], variations[i]];
  }
  
  return variations;
};

// 다양한 각도 조합 기본값 생성 (repeatCount 길이에 맞춰 최대 다양성). 행 내 중복 허용.
const diverseDefaultDirs = (n: number): CumDirection[] => {
  if (n <= 0) return [] as CumDirection[];
  const seq: CumDirection[] = [];
  const pools = [FACE_DIRS, EDGE_DIRS, CORNER_DIRS];
  let pi = 0, idx = 0;
  while (seq.length < n) {
    const pool = pools[pi % pools.length];
    seq.push(pool[idx % pool.length]);
    pi++; if (pi % pools.length === 0) idx++;
  }
  return seq;
};

const rotate = <T,>(arr: T[], k: number) => arr.map((_, i) => arr[(i + k) % arr.length]);

const rowsEqual = (a: CumDirection[], b: CumDirection[]) => a.length === b.length && a.every((v, i) => v === b[i]);
const nextDir = (d: CumDirection, step = 1): CumDirection => ALL_DIRS[(ALL_DIRS.indexOf(d) + step) % ALL_DIRS.length];

// 한 행이 기존 행들과 완전히 동일하지 않도록 보정 (행 내 중복은 허용)
const ensureRowUnique = (row: CumDirection[], existing: CumDirection[][]): CumDirection[] => {
  let candidate = row.slice();
  const repeat = candidate.length;
  if (!existing.some(ex => rowsEqual(ex, candidate))) return candidate;
  const maxAttempts = ALL_DIRS.length * Math.max(1, repeat);
  for (let t = 0; t < maxAttempts; t++) {
    const pos = t % repeat;
    const shift = Math.floor(t / repeat) + 1;
    candidate[pos] = nextDir(candidate[pos], shift);
    if (!existing.some(ex => rowsEqual(ex, candidate))) return candidate;
  }
  return row.slice();
};

const dedupGrid = (grid: CumDirection[][]): CumDirection[][] => {
  const out: CumDirection[][] = [];
  for (const r of grid) out.push(ensureRowUnique(r, out));
  return out;
};

// ---- Helper functions for new analysis types ----

// Generate attitudes for predefined modes
const generatePredefinedAttitudes = (mode: PredefinedMode): [number, number, number][] => {
  switch (mode) {
    case "faces6":
      return FACE_ATTITUDES;
    case "edges12":
      return EDGE_ATTITUDES;
    case "corners8":
      return CORNER_ATTITUDES;
    case "all26":
      return [...FACE_ATTITUDES, ...EDGE_ATTITUDES, ...CORNER_ATTITUDES];
    default:
      return FACE_ATTITUDES;
  }
};

// Generate edge rotation attitudes
const generateEdgeRotationAttitudes = (axis: EdgeAxis, divisions: number): [number, number, number][] => {
  const attitudes: [number, number, number][] = [];
  const angleStep = 360 / divisions;

  for (let i = 0; i < divisions; i++) {
    const angle = i * angleStep;

    // Rotation axis depends on edge selection
    switch (axis) {
      case "top":
        // Rotate around top edge (Y-axis at top)
        attitudes.push([0, -90, angle]);
        break;
      case "bottom":
        // Rotate around bottom edge (Y-axis at bottom)
        attitudes.push([0, 90, angle]);
        break;
      case "left":
        // Rotate around left edge (X-axis at left)
        attitudes.push([90, 0, angle]);
        break;
      case "right":
        // Rotate around right edge (X-axis at right)
        attitudes.push([-90, 0, angle]);
        break;
    }
  }

  return attitudes;
};

// Wildcard pattern matching for package names
const matchesPackagePattern = (packageName: string, pattern: string): boolean => {
  // Convert wildcard pattern to regex
  // Escape special regex characters except *
  const regexPattern = pattern
    .split('*')
    .map(part => part.replace(/[.+?^${}()|[\]\\]/g, '\\$&'))
    .join('.*');

  const regex = new RegExp(`^${regexPattern}$`, 'i'); // case-insensitive
  return regex.test(packageName);
};

// Check if package matches any of the patterns
const matchesAnyPattern = (packageName: string, patterns: string[]): boolean => {
  return patterns.some(pattern => matchesPackagePattern(packageName, pattern));
};

// Generate grid coordinates based on mode
const generateGridCoordinates = (mode: ImpactGridMode): Array<{ x: number; y: number }> => {
  const coords: Array<{ x: number; y: number }> = [];

  // Parse grid mode (e.g., "3x3" -> cols=3, rows=3)
  const [colsStr, rowsStr] = mode.split('x');
  const cols = parseInt(colsStr, 10);
  const rows = parseInt(rowsStr, 10);

  // Generate evenly distributed grid points (percentage: 0-100)
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const x = cols === 1 ? 50 : (col / (cols - 1)) * 100;
      const y = rows === 1 ? 50 : (row / (rows - 1)) * 100;
      coords.push({ x, y });
    }
  }

  return coords;
};

// Generate random LHS coordinates
const generateLHSCoordinates = (count: number): Array<{ x: number; y: number }> => {
  const coords: Array<{ x: number; y: number }> = [];

  // LHS sampling for X
  const xSamples = generateLHSVariations(count, 50).map(v => v + 50); // -50~50 -> 0~100
  // LHS sampling for Y
  const ySamples = generateLHSVariations(count, 50).map(v => v + 50); // -50~50 -> 0~100

  for (let i = 0; i < count; i++) {
    coords.push({ x: xSamples[i], y: ySamples[i] });
  }

  return coords;
};

const warnIfDOEExceedsCapacity = (repeat: number, doe: number) => {
  const maxUnique = Math.pow(ALL_DIRS.length, repeat);
  if (doe > maxUnique) {
    message.warning(`DOE 수(${doe})가 가능한 고유 조합 수(${maxUnique.toLocaleString()})를 초과하여 일부 행이 동일할 수 있습니다.`);
  }
};

// DOE×회수 기본 매트릭스: 회전 기반 + 유니크 보정
const diverseDefaultGrid = (repeat: number, doe: number): CumDirection[][] => {
  warnIfDOEExceedsCapacity(repeat, doe);
  const base = diverseDefaultDirs(repeat);
  const grid: CumDirection[][] = [];
  for (let r = 0; r < doe; r++) {
    const proposal = rotate(base, r % repeat) as CumDirection[];
    grid.push(ensureRowUnique(proposal, grid));
  }
  return grid;
};

const normalizeCum = (row: ScenarioRow) => {
  const repeat = (row.params?.cumRepeatCount ?? 3) as 2|3|4|5;
  const doe = (row.params?.cumDOECount ?? 5);
  let grid = row.params?.cumDirectionsGrid;
  if (!grid || !Array.isArray(grid) || grid.length !== doe || grid[0]?.length !== repeat) {
    const oneD = row.params?.cumDirections && row.params.cumDirections.length === repeat ? row.params.cumDirections : undefined;
    grid = diverseDefaultGrid(repeat, doe);
    if (oneD) {
      grid[0] = oneD as CumDirection[];
      grid = dedupGrid(grid);
    }
  }
  return { repeat, doe, grid };
};

// ---- Tolerance controls ----
const renderToleranceControls = (row: ScenarioRow, setScenarios: React.Dispatch<React.SetStateAction<ScenarioRow[]>>) => {
  const tolerance = row.params?.tolerance || { mode: "disabled" as ToleranceMode };
  const isEnabled = tolerance.mode === "enabled";
  
  return (
    <Card size="small" style={{ marginTop: 8 }}>
      <Flex vertical gap={8}>
        <Flex align="center" gap={8}>
          <Text strong>각도 변동 허용</Text>
          <Switch 
            size="small" 
            checked={isEnabled}
            onChange={(checked) => setScenarios(prev => prev.map(r => 
              r.id === row.id ? { 
                ...r, 
                params: { 
                  ...(r.params||{}), 
                  tolerance: { 
                    ...tolerance, 
                    mode: checked ? "enabled" : "disabled" 
                  } 
                } 
              } : r
            ))}
          />
          {isEnabled && <Tag color="blue">활성화됨</Tag>}
        </Flex>
        
        {isEnabled && (
          <Space wrap size={16}>
            <Space size={8}>
              <Text>면 (6개)</Text>
              <InputNumber
                size="small"
                min={0}
                max={180}
                step={1}
                value={tolerance.faceTolerance || 0}
                addonAfter="°"
                style={{ width: 80 }}
                onChange={(v) => setScenarios(prev => prev.map(r => 
                  r.id === row.id ? { 
                    ...r, 
                    params: { 
                      ...(r.params||{}), 
                      tolerance: { 
                        ...tolerance, 
                        faceTolerance: Number(v || 0) 
                      } 
                    } 
                  } : r
                ))}
              />
            </Space>
            
            <Space size={8}>
              <Text>엣지 (12개)</Text>
              <InputNumber
                size="small"
                min={0}
                max={180}
                step={1}
                value={tolerance.edgeTolerance || 0}
                addonAfter="°"
                style={{ width: 80 }}
                onChange={(v) => setScenarios(prev => prev.map(r => 
                  r.id === row.id ? { 
                    ...r, 
                    params: { 
                      ...(r.params||{}), 
                      tolerance: { 
                        ...tolerance, 
                        edgeTolerance: Number(v || 0) 
                      } 
                    } 
                  } : r
                ))}
              />
            </Space>
            
            <Space size={8}>
              <Text>코너 (8개)</Text>
              <InputNumber
                size="small"
                min={0}
                max={180}
                step={1}
                value={tolerance.cornerTolerance || 0}
                addonAfter="°"
                style={{ width: 80 }}
                onChange={(v) => setScenarios(prev => prev.map(r => 
                  r.id === row.id ? { 
                    ...r, 
                    params: { 
                      ...(r.params||{}), 
                      tolerance: { 
                        ...tolerance, 
                        cornerTolerance: Number(v || 0) 
                      } 
                    } 
                  } : r
                ))}
              />
            </Space>
          </Space>
        )}
        
        {isEnabled && (
          <Text type="secondary" style={{ fontSize: 12 }}>
            • 각 방향별로 최대 변동량(도)을 설정하면 LHS 샘플링으로 실제 각도가 생성됩니다
            • 변동 범위: -최대값 ~ +최대값 (예: 5° 설정 시 -5° ~ +5°)
          </Text>
        )}
      </Flex>
    </Card>
  );
};

// ---- UI Controls for new analysis types ----

// 1. Predefined Attitudes Controls
const renderPredefinedAttitudesControls = (row: ScenarioRow, setScenarios: React.Dispatch<React.SetStateAction<ScenarioRow[]>>) => {
  const p = row.params || {};
  const predefinedMode: PredefinedMode = p.predefinedMode ?? "all26";
  const defaultAttitudes = generatePredefinedAttitudes(predefinedMode);

  // Initialize custom angles if not present
  const customAngles = p.predefinedAngles || defaultAttitudes.map((att, idx) => ({
    name: `자세 ${idx + 1}`,
    phi: att[0],
    theta: att[1],
    psi: att[2]
  }));

  const updateAngle = (index: number, field: 'name' | 'phi' | 'theta' | 'psi', value: string | number) => {
    setScenarios(prev => prev.map(r => {
      if (r.id !== row.id) return r;
      const newAngles = [...customAngles];
      if (field === 'name') {
        newAngles[index] = { ...newAngles[index], name: value as string };
      } else {
        newAngles[index] = { ...newAngles[index], [field]: Number(value) || 0 };
      }
      return { ...r, params: { ...(r.params||{}), predefinedAngles: newAngles } };
    }));
  };

  const addAngle = () => {
    setScenarios(prev => prev.map(r => {
      if (r.id !== row.id) return r;
      const newAngles = [...customAngles, { name: `자세 ${customAngles.length + 1}`, phi: 0, theta: 0, psi: 0 }];
      return { ...r, params: { ...(r.params||{}), predefinedAngles: newAngles } };
    }));
  };

  const removeAngle = (index: number) => {
    if (customAngles.length <= 1) {
      message.warning('최소 1개의 자세는 필요합니다.');
      return;
    }
    setScenarios(prev => prev.map(r => {
      if (r.id !== row.id) return r;
      const newAngles = customAngles.filter((_, i) => i !== index);
      return { ...r, params: { ...(r.params||{}), predefinedAngles: newAngles } };
    }));
  };

  const resetToDefault = () => {
    const resetAngles = defaultAttitudes.map((att, idx) => ({
      name: `자세 ${idx + 1}`,
      phi: att[0],
      theta: att[1],
      psi: att[2]
    }));
    setScenarios(prev => prev.map(r =>
      r.id === row.id ? { ...r, params: { ...(r.params||{}), predefinedAngles: resetAngles } } : r
    ));
  };

  const angleColumns: ColumnsType<any> = [
    { title: '#', dataIndex: 'index', width: 50, render: (_: any, __: any, idx: number) => idx + 1 },
    {
      title: '자세 이름',
      dataIndex: 'name',
      width: 180,
      render: (val: string, _: any, idx: number) => (
        <Input
          size="small"
          value={val}
          onChange={(e) => updateAngle(idx, 'name', e.target.value)}
          placeholder="자세 이름"
        />
      )
    },
    {
      title: 'φ (Roll, °)',
      dataIndex: 'phi',
      width: 120,
      render: (val: number, _: any, idx: number) => (
        <InputNumber
          size="small"
          value={val}
          onChange={(v) => updateAngle(idx, 'phi', v ?? 0)}
          style={{ width: '100%' }}
          step={1}
        />
      )
    },
    {
      title: 'θ (Pitch, °)',
      dataIndex: 'theta',
      width: 120,
      render: (val: number, _: any, idx: number) => (
        <InputNumber
          size="small"
          value={val}
          onChange={(v) => updateAngle(idx, 'theta', v ?? 0)}
          style={{ width: '100%' }}
          step={1}
        />
      )
    },
    {
      title: 'ψ (Yaw, °)',
      dataIndex: 'psi',
      width: 120,
      render: (val: number, _: any, idx: number) => (
        <InputNumber
          size="small"
          value={val}
          onChange={(v) => updateAngle(idx, 'psi', v ?? 0)}
          style={{ width: '100%' }}
          step={1}
        />
      )
    },
    {
      title: '액션',
      width: 80,
      render: (_: any, __: any, idx: number) => (
        <Button
          size="small"
          danger
          icon={<DeleteOutlined />}
          onClick={() => removeAngle(idx)}
        />
      )
    }
  ];

  return (
    <Flex vertical gap={10}>
      {/* Height & Surface (공통) */}
      {renderCommonDropControls(row, setScenarios)}

      <Divider />

      <Space size={8} wrap align="center">
        <Text strong>낙하 자세 선택</Text>
        <Radio.Group
          size="small"
          value={predefinedMode}
          onChange={(e) => {
            const newMode = e.target.value as PredefinedMode;
            const newAttitudes = generatePredefinedAttitudes(newMode);
            const resetAngles = newAttitudes.map((att, idx) => ({
              name: `자세 ${idx + 1}`,
              phi: att[0],
              theta: att[1],
              psi: att[2]
            }));
            setScenarios(prev => prev.map(r =>
              r.id === row.id ? { ...r, params: { ...(r.params||{}), predefinedMode: newMode, predefinedAngles: resetAngles } } : r
            ));
          }}
        >
          <Radio value="faces6">6면 (6개)</Radio>
          <Radio value="edges12">12엣지 (12개)</Radio>
          <Radio value="corners8">8코너 (8개)</Radio>
          <Radio value="all26">전체 (26개)</Radio>
        </Radio.Group>
        <Tag color="blue">총 {customAngles.length}개 자세</Tag>
        <Button size="small" onClick={resetToDefault}>기본값 복원</Button>
      </Space>

      <Card size="small" style={{ backgroundColor: '#fafafa' }}>
        <Flex vertical gap={8}>
          <Flex justify="space-between" align="center">
            <Text strong>낙하 자세 각도 (오일러 각도)</Text>
            <Button size="small" type="dashed" icon={<PlusOutlined />} onClick={addAngle}>
              자세 추가
            </Button>
          </Flex>
          <div style={{ overflowX: 'auto', maxHeight: '400px' }}>
            <Table
              size="small"
              pagination={false}
              columns={angleColumns}
              dataSource={customAngles}
              rowKey={(_, idx) => idx!}
              bordered
            />
          </div>
          <Text type="secondary" style={{ fontSize: 12 }}>
            • φ (Roll): X축 회전, θ (Pitch): Y축 회전, ψ (Yaw): Z축 회전 (단위: 도)
          </Text>
        </Flex>
      </Card>

      {/* Tolerance controls */}
      {renderToleranceControls(row, setScenarios)}
    </Flex>
  );
};

// 2. Edge Axis Rotation Controls
const renderEdgeAxisRotationControls = (row: ScenarioRow, setScenarios: React.Dispatch<React.SetStateAction<ScenarioRow[]>>) => {
  const p = row.params || {};
  const edgeAxis: EdgeAxis = p.edgeAxis ?? "top";
  const edgeDivisions: number = p.edgeDivisions ?? 12;
  const attitudes = generateEdgeRotationAttitudes(edgeAxis, edgeDivisions);

  return (
    <Flex vertical gap={10}>
      {/* Height & Surface (공통) */}
      {renderCommonDropControls(row, setScenarios)}

      <Divider />

      <Space size={8} wrap align="center">
        <Text strong>회전 엣지 선택</Text>
        <Select
          size="small"
          style={{ width: 140 }}
          value={edgeAxis}
          options={EDGE_AXIS_OPTIONS}
          onChange={(v) => setScenarios(prev => prev.map(r =>
            r.id === row.id ? { ...r, params: { ...(r.params||{}), edgeAxis: v as EdgeAxis } } : r
          ))}
        />

        <Divider type="vertical" />

        <Text strong>분할 수</Text>
        <Select
          size="small"
          style={{ width: 100 }}
          value={edgeDivisions}
          options={EDGE_DIVISION_COUNTS.map(v => ({ label: `${v}등분`, value: v }))}
          onChange={(v) => setScenarios(prev => prev.map(r =>
            r.id === row.id ? { ...r, params: { ...(r.params||{}), edgeDivisions: v } } : r
          ))}
        />

        <Tag color="blue">총 {attitudes.length}개 각도</Tag>
      </Space>

      {/* Tolerance controls */}
      {renderToleranceControls(row, setScenarios)}
    </Flex>
  );
};

// 3. Drop Weight Impact Controls
const renderDropWeightImpactControls = (row: ScenarioRow, setScenarios: React.Dispatch<React.SetStateAction<ScenarioRow[]>>) => {
  const p = row.params || {};
  const packagePatterns = p.impactPackagePatterns ?? ["*pkg*"];
  const locationMode: ImpactLocationMode = p.impactLocationMode ?? "grid";
  const gridMode: ImpactGridMode = p.impactGridMode ?? "3x3";
  const percentageX = p.impactPercentageX ?? 50;
  const percentageY = p.impactPercentageY ?? 50;
  const randomCount = p.impactRandomCount ?? 10;
  const impactorType: ImpactorType = p.impactorType ?? "ball";
  const ballDiameter = p.impactorBallDiameter ?? 6;
  const cylinderDiameter = p.impactorCylinderDiameter ?? 8;
  const cylinderDiameterCustom = p.impactorCylinderDiameterCustom ?? 10;

  const updateParams = (updates: Partial<ScenarioRow['params']>) => {
    setScenarios(prev => prev.map(r =>
      r.id === row.id ? { ...r, params: { ...(r.params||{}), ...updates } } : r
    ));
  };

  return (
    <Flex vertical gap={10}>
      {/* Package patterns */}
      <Card size="small" style={{ backgroundColor: '#f5f5f5' }}>
        <Flex vertical gap={8}>
          <Text strong>패키지 패턴 (쉼표로 구분, *는 와일드카드)</Text>
          <Input
            size="small"
            placeholder="예: *pkg*, display, camera*"
            value={packagePatterns.join(', ')}
            onChange={(e) => {
              const patterns = e.target.value.split(',').map(s => s.trim()).filter(s => s.length > 0);
              updateParams({ impactPackagePatterns: patterns.length > 0 ? patterns : ["*pkg*"] });
            }}
          />
          <Text type="secondary" style={{ fontSize: 12 }}>
            현재 패턴: {packagePatterns.map(p => `"${p}"`).join(', ')}
          </Text>
        </Flex>
      </Card>

      {/* Impact location mode */}
      <Card size="small" style={{ backgroundColor: '#f5f5f5' }}>
        <Flex vertical gap={8}>
          <Text strong>충격 위치 모드</Text>
          <Radio.Group
            size="small"
            value={locationMode}
            onChange={(e) => updateParams({ impactLocationMode: e.target.value as ImpactLocationMode })}
          >
            <Radio value="grid">격자 (Grid)</Radio>
            <Radio value="percentage">좌표 지정 (%)</Radio>
            <Radio value="random">랜덤 (LHS)</Radio>
          </Radio.Group>

          {locationMode === "grid" && (
            <Space size={8}>
              <Text>격자 모드</Text>
              <Select
                size="small"
                style={{ width: 160 }}
                value={gridMode}
                options={IMPACT_GRID_OPTIONS}
                onChange={(v) => updateParams({ impactGridMode: v as ImpactGridMode })}
              />
              <Tag color="green">{generateGridCoordinates(gridMode).length}개 포인트</Tag>
            </Space>
          )}

          {locationMode === "percentage" && (() => {
            // Initialize locations if not present
            const locations = p.impactLocations || [];
            const rows = p.impactGridRows || 3;
            const cols = p.impactGridCols || 3;
            const packageWidth = p.impactPackageWidth || 100;
            const packageHeight = p.impactPackageHeight || 100;
            const applyEdgeMargin = p.applyEdgeMargin ?? false;
            const sampleCount = rows * cols;

            // Auto-generate if empty
            if (locations.length === 0) {
              const newLocations = generateGridLocations(rows, cols, applyEdgeMargin);
              updateParams({
                impactLocations: newLocations,
                impactGridRows: rows,
                impactGridCols: cols,
                applyEdgeMargin: applyEdgeMargin,
                impactPackageWidth: packageWidth,
                impactPackageHeight: packageHeight
              });
              return <Text type="secondary">초기화 중...</Text>;
            }

            const updateGridCell = (rowIdx: number, colIdx: number, field: 'x' | 'y', value: number) => {
              const flatIndex = rowIdx * cols + colIdx;
              const newLocations = [...locations];
              if (flatIndex < newLocations.length) {
                newLocations[flatIndex] = { ...newLocations[flatIndex], [field]: value };
                updateParams({ impactLocations: newLocations });
              }
            };

            const regenerateGrid = (newRows: number, newCols: number, newApplyEdgeMargin?: boolean) => {
              const useMargin = newApplyEdgeMargin ?? applyEdgeMargin;
              const newLocations = generateGridLocations(newRows, newCols, useMargin);
              updateParams({ impactLocations: newLocations, impactGridRows: newRows, impactGridCols: newCols, applyEdgeMargin: useMargin });
            };

            const updateSampleCount = (count: number) => {
              const { rows: newRows, cols: newCols } = calculateGridDimensions(count);
              regenerateGrid(newRows, newCols);
            };

            // SVG visualization settings
            const svgWidth = 400;
            const aspectRatio = packageHeight / packageWidth;
            const svgHeight = svgWidth * aspectRatio;
            const padding = 20;
            const rectWidth = svgWidth - 2 * padding;
            const rectHeight = svgHeight - 2 * padding;

            return (
              <Card size="small" style={{ backgroundColor: '#fff', marginTop: 8 }}>
                <Flex vertical gap={12}>
                  {/* Controls */}
                  <Flex gap={8} wrap align="center">
                    <Text strong>샘플 수</Text>
                    <InputNumber
                      size="small"
                      value={sampleCount}
                      onChange={(v) => updateSampleCount(v ?? 9)}
                      min={1}
                      max={1000}
                      style={{ width: 100 }}
                    />
                    <Text type="secondary">→</Text>
                    <Text strong>가로</Text>
                    <InputNumber
                      size="small"
                      value={cols}
                      onChange={(v) => regenerateGrid(rows, v ?? 3)}
                      min={1}
                      max={100}
                      style={{ width: 80 }}
                    />
                    <Text strong>세로</Text>
                    <InputNumber
                      size="small"
                      value={rows}
                      onChange={(v) => regenerateGrid(v ?? 3, cols)}
                      min={1}
                      max={100}
                      style={{ width: 80 }}
                    />
                    <Divider type="vertical" />
                    <Space size="small">
                      <Switch
                        size="small"
                        checked={applyEdgeMargin}
                        onChange={(checked) => regenerateGrid(rows, cols, checked)}
                      />
                      <Text strong>외곽 마진 적용</Text>
                      <Text type="secondary" style={{ fontSize: 11 }}>
                        (간격/2)
                      </Text>
                    </Space>
                    <Divider type="vertical" />
                    <Text strong>패키지 가로(mm)</Text>
                    <InputNumber
                      size="small"
                      value={packageWidth}
                      onChange={(v) => updateParams({ impactPackageWidth: v ?? 100 })}
                      min={1}
                      max={10000}
                      style={{ width: 100 }}
                    />
                    <Text strong>세로(mm)</Text>
                    <InputNumber
                      size="small"
                      value={packageHeight}
                      onChange={(v) => updateParams({ impactPackageHeight: v ?? 100 })}
                      min={1}
                      max={10000}
                      style={{ width: 100 }}
                    />
                  </Flex>

                  {/* Grid Table + Visualization */}
                  <Flex gap={16} wrap>
                    {/* Grid Table */}
                    <div style={{ flex: '0 0 auto' }}>
                      <Text strong style={{ display: 'block', marginBottom: 8 }}>좌표 입력 (X%, Y%)</Text>
                      <table style={{
                        borderCollapse: 'collapse',
                        border: '1px solid #d9d9d9',
                        fontSize: '12px'
                      }}>
                        <tbody>
                          {Array.from({ length: rows }).map((_, rowIdx) => (
                            <tr key={rowIdx}>
                              {Array.from({ length: cols }).map((_, colIdx) => {
                                const flatIndex = rowIdx * cols + colIdx;
                                const loc = locations[flatIndex] || { x: 0, y: 0 };
                                return (
                                  <td key={colIdx} style={{
                                    border: '1px solid #d9d9d9',
                                    padding: '4px',
                                    backgroundColor: '#fafafa'
                                  }}>
                                    <Flex vertical gap={2}>
                                      <InputNumber
                                        size="small"
                                        value={loc.x}
                                        onChange={(v) => updateGridCell(rowIdx, colIdx, 'x', v ?? 0)}
                                        min={0}
                                        max={100}
                                        step={0.1}
                                        placeholder="X%"
                                        style={{ width: 70 }}
                                      />
                                      <InputNumber
                                        size="small"
                                        value={loc.y}
                                        onChange={(v) => updateGridCell(rowIdx, colIdx, 'y', v ?? 0)}
                                        min={0}
                                        max={100}
                                        step={0.1}
                                        placeholder="Y%"
                                        style={{ width: 70 }}
                                      />
                                    </Flex>
                                  </td>
                                );
                              })}
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>

                    {/* Visualization */}
                    <div style={{ flex: '1 1 auto' }}>
                      <Text strong style={{ display: 'block', marginBottom: 8 }}>
                        시각화 ({packageWidth}mm × {packageHeight}mm)
                      </Text>
                      <svg width={svgWidth} height={svgHeight} style={{ border: '1px solid #d9d9d9' }}>
                        {/* Background rectangle (package) */}
                        <rect
                          x={padding}
                          y={padding}
                          width={rectWidth}
                          height={rectHeight}
                          fill="#f0f0f0"
                          stroke="#999"
                          strokeWidth="2"
                        />

                        {/* Grid lines */}
                        {Array.from({ length: cols + 1 }).map((_, i) => (
                          <line
                            key={`v${i}`}
                            x1={padding + (i / cols) * rectWidth}
                            y1={padding}
                            x2={padding + (i / cols) * rectWidth}
                            y2={padding + rectHeight}
                            stroke="#ddd"
                            strokeWidth="1"
                          />
                        ))}
                        {Array.from({ length: rows + 1 }).map((_, i) => (
                          <line
                            key={`h${i}`}
                            x1={padding}
                            y1={padding + (i / rows) * rectHeight}
                            x2={padding + rectWidth}
                            y2={padding + (i / rows) * rectHeight}
                            stroke="#ddd"
                            strokeWidth="1"
                          />
                        ))}

                        {/* Impact points */}
                        {locations.map((loc, idx) => {
                          const x = padding + (loc.x / 100) * rectWidth;
                          const y = padding + (loc.y / 100) * rectHeight;
                          return (
                            <g key={idx}>
                              <circle
                                cx={x}
                                cy={y}
                                r="4"
                                fill="red"
                                stroke="darkred"
                                strokeWidth="1"
                              />
                              <text
                                x={x}
                                y={y - 8}
                                textAnchor="middle"
                                fontSize="10"
                                fill="#333"
                              >
                                {idx + 1}
                              </text>
                            </g>
                          );
                        })}
                      </svg>
                    </div>
                  </Flex>

                  <Text type="secondary" style={{ fontSize: 11 }}>
                    • 그리드 테이블에서 각 셀의 X%, Y% 좌표를 직접 입력
                    <br />
                    • 우측 시각화에서 빨간 점으로 충격 위치 확인
                    <br />
                    • 패키지 크기를 입력하면 시각화 비율이 자동 조정됨
                  </Text>
                </Flex>
              </Card>
            );
          })()}

          {locationMode === "random" && (
            <Space size={8}>
              <Text>샘플 개수</Text>
              <InputNumber
                size="small"
                min={1}
                max={1000}
                step={1}
                value={randomCount}
                style={{ width: 100 }}
                onChange={(v) => updateParams({ impactRandomCount: Number(v ?? 10) })}
              />
              <Tag color="orange">{randomCount}개 LHS 샘플</Tag>
            </Space>
          )}
        </Flex>
      </Card>

      {/* Impactor type and size */}
      <Card size="small" style={{ backgroundColor: '#f5f5f5' }}>
        <Flex vertical gap={8}>
          <Text strong>충격체 타입</Text>
          <Radio.Group
            size="small"
            value={impactorType}
            onChange={(e) => updateParams({ impactorType: e.target.value as ImpactorType })}
          >
            <Radio value="ball">Ball</Radio>
            <Radio value="cylinder">Cylinder</Radio>
          </Radio.Group>

          {impactorType === "ball" && (
            <Space size={8}>
              <Text>Ball 지름</Text>
              <InputNumber
                size="small"
                min={1}
                max={50}
                step={0.5}
                value={ballDiameter}
                addonAfter="mm"
                style={{ width: 100 }}
                onChange={(v) => updateParams({ impactorBallDiameter: Number(v ?? 6) })}
              />
              <Tag color="blue">기본: 6mm</Tag>
            </Space>
          )}

          {impactorType === "cylinder" && (
            <Flex vertical gap={8}>
              <Space size={8}>
                <Text>Cylinder 지름</Text>
                <Radio.Group
                  size="small"
                  value={typeof cylinderDiameter === 'number' && cylinderDiameter !== 8 && cylinderDiameter !== 15 ? "custom" : cylinderDiameter}
                  onChange={(e) => {
                    const val = e.target.value;
                    if (val === "custom") {
                      updateParams({ impactorCylinderDiameter: "custom" });
                    } else {
                      updateParams({ impactorCylinderDiameter: val as CylinderDiameter });
                    }
                  }}
                >
                  <Radio value={8}>8mm</Radio>
                  <Radio value={15}>15mm</Radio>
                  <Radio value="custom">사용자 정의</Radio>
                </Radio.Group>
              </Space>

              {(cylinderDiameter === "custom" || (typeof cylinderDiameter === 'number' && cylinderDiameter !== 8 && cylinderDiameter !== 15)) && (
                <Space size={8}>
                  <Text>지름 입력</Text>
                  <InputNumber
                    size="small"
                    min={1}
                    max={100}
                    step={0.5}
                    value={cylinderDiameterCustom}
                    addonAfter="mm"
                    style={{ width: 110 }}
                    onChange={(v) => updateParams({ impactorCylinderDiameterCustom: Number(v ?? 10) })}
                  />
                </Space>
              )}
            </Flex>
          )}
        </Flex>
      </Card>

      {/* Tolerance controls */}
      {renderToleranceControls(row, setScenarios)}
    </Flex>
  );
};

// ---- Shared controls (Height & Surface) ----
const renderCommonDropControls = (row: ScenarioRow, setScenarios: React.Dispatch<React.SetStateAction<ScenarioRow[]>>) => {
  const p = row.params || {};
  const heightMode: HeightMode = p.heightMode ?? "const";
  const heightConst = p.heightConst ?? 1.0;
  const heightMin = p.heightMin ?? 0.5;
  const heightMax = p.heightMax ?? 1.5;
  const surface: SurfaceType = p.surface ?? "steelPlate";
  return (
    <Space size={8} wrap>
      <Text>높이</Text>
      <Radio.Group
        size="small"
        value={heightMode}
        onChange={(e)=> setScenarios(prev => prev.map(r => r.id===row.id ? { ...r, params: { ...(r.params||{}), heightMode: e.target.value as HeightMode } } : r))}
      >
        <Radio value="const">고정값</Radio>
        <Radio value="lhs">LHS</Radio>
      </Radio.Group>
      {heightMode === "const" ? (
        <Space size={4}>
          <InputNumber size="small" min={0.01} step={0.05} value={heightConst} addonAfter="m"
            onChange={(v)=> setScenarios(prev => prev.map(r => r.id===row.id ? { ...r, params: { ...(r.params||{}), heightConst: Number(v ?? 1.0) } } : r))}
          />
        </Space>
      ) : (
        <Space size={4}>
          <Text type="secondary">min</Text>
          <InputNumber size="small" min={0.01} step={0.05} value={heightMin} addonAfter="m"
            onChange={(v)=> setScenarios(prev => prev.map(r => r.id===row.id ? { ...r, params: { ...(r.params||{}), heightMin: Number(v ?? 0.5) } } : r))}
          />
          <Text type="secondary">max</Text>
          <InputNumber size="small" min={0.01} step={0.05} value={heightMax} addonAfter="m"
            onChange={(v)=> setScenarios(prev => prev.map(r => r.id===row.id ? { ...r, params: { ...(r.params||{}), heightMax: Number(v ?? 1.5) } } : r))}
          />
        </Space>
      )}
      <Divider type="vertical" />
      <Text>표면</Text>
      <Select size="small" style={{ width: 180 }} value={surface}
        options={SURFACE_OPTIONS}
        onChange={(v)=> setScenarios(prev => prev.map(r => r.id===row.id ? { ...r, params: { ...(r.params||{}), surface: v as SurfaceType } } : r))}
      />
    </Space>
  );
};

// ---- Component ----
const SimulationAutomationComponent: React.FC = () => {
  const [scenarios, setScenarios] = useState<ScenarioRow[]>([]);
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);
  const [bulkType, setBulkType] = useState<AnalysisType | undefined>();
  const [standardModalVisible, setStandardModalVisible] = useState(false);
  const kFileBufferRef = useRef<File[]>([]);
  const objFileBufferRef = useRef<File[]>([]);

  const selectedSingleRow = (): ScenarioRow | undefined => {
    if (selectedRowKeys.length === 1) {
      return scenarios.find(s => s.id === selectedRowKeys[0]);
    }
    return undefined;
  };

  // OBJ uploader (MBD용)
  const uploadPropsOBJ: UploadProps = {
    name: "obj",
    multiple: true,
    accept: ".obj",
    beforeUpload: (file) => { objFileBufferRef.current.push(file); return false; },
    onChange: () => {
      const sel = selectedSingleRow();
      if (objFileBufferRef.current.length === 0) return;
      if (sel) {
        const f = objFileBufferRef.current[objFileBufferRef.current.length - 1];
        setScenarios(prev => prev.map(r => r.id === sel.id ? { ...r, objFileName: f.name, objFile: f, analysisType: r.analysisType === "dropWeightImpact" ? "fullAngleMBD" : r.analysisType } : r));
        message.success(`선택한 시나리오에 OBJ(${f.name})를 연결했습니다.`);
      } else {
        const newRows: ScenarioRow[] = objFileBufferRef.current.map((f) => ({
          id: uid("scn"),
          name: f.name.replace(/\.obj$/i, ""),
          objFileName: f.name,
          objFile: f,
          analysisType: "fullAngleMBD",
          params: { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } },
        }));
        setScenarios(prev => [...prev,...newRows]);
        message.success(`${newRows.length}개 OBJ 파일을 시나리오로 추가했습니다.`);
      }
      objFileBufferRef.current = [];
    },
    itemRender: () => null,
  };

  // K uploader — 선택된 1개 행이 있으면 그 행에 붙이고, 없으면 새 시나리오 생성
  const uploadPropsK: UploadProps = {
    name: "file",
    multiple: true,
    accept: ".k,.key,.dyn,k",
    beforeUpload: (file) => { kFileBufferRef.current.push(file); return false; },
    onChange: () => {
      if (kFileBufferRef.current.length === 0) return;
      const sel = selectedSingleRow();
      if (sel) {
        const f = kFileBufferRef.current[kFileBufferRef.current.length - 1];
        setScenarios(prev => prev.map(r => r.id === sel.id ? { ...r, fileName: f.name, file: f, analysisType: r.analysisType === "dropWeightImpact" ? "fullAngle" : r.analysisType } : r));
        message.success(`선택한 시나리오에 K(${f.name})를 연결했습니다.`);
      } else {
        const newRows: ScenarioRow[] = kFileBufferRef.current.map((f) => ({
          id: uid("scn"),
          name: f.name.replace(/\.(k|key|dyn)$/i, ""),
          fileName: f.name,
          file: f,
          analysisType: "fullAngle",
          params: { faTotal: 100, includeFace6: true, includeEdge12: true, includeCorner8: true, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } },
        }));
        setScenarios(prev => [...prev,...newRows]);
        message.success(`${newRows.length}개 K 파일을 시나리오로 추가했습니다.`);
      }
      kFileBufferRef.current = [];
    },
    itemRender: () => null,
  };

  const makeAnglesUploadProps = (row: ScenarioRow): UploadProps => ({
    name: "angles",
    multiple: false,
    accept: ".json,.csv",
    beforeUpload: async (file) => {
      try {
        const content = await bytesToString(file);
        if (!content.trim()) { message.error("빈 파일입니다."); return Upload.LIST_IGNORE as unknown as false; }
        setScenarios(prev => prev.map(r => r.id === row.id ? {
          ...r,
          params: { ...(r.params||{}), angleSource: "usePrevResult", angleSourceFileName: file.name, angleSourceFile: file },
        } : r));
        message.success(`${file.name} 각도 소스로 설정됨`);
      } catch {
        message.error("파일 읽기 실패");
        return Upload.LIST_IGNORE as unknown as false;
      }
      return false;
    },
    itemRender: () => null,
  });

  // Build dropdown options using scenarios above current row
  const priorMbdOptions = (row: ScenarioRow) => {
    const idx = scenarios.findIndex(s => s.id === row.id);
    const prior = scenarios.slice(0, idx).filter(s => s.analysisType === "fullAngleMBD");
    return prior.map(s => ({ label: `[MBD] ${s.name} • ${s.params?.mbdCount?.toLocaleString?.() ?? "?"}개`, value: s.id }));
  };
  const priorFaOptions = (row: ScenarioRow) => {
    const idx = scenarios.findIndex(s => s.id === row.id);
    const prior = scenarios.slice(0, idx).filter(s => s.analysisType === "fullAngle" || s.analysisType === "fullAngleCumulative");
    return prior.map(s => ({ label: `[FA] ${s.name} • ${s.params?.faTotal ?? s.params?.cumRepeatCount ?? "?"}`, value: s.id }));
  };

  // ---- 다회 누적 낙하 전용 컨트롤: 회수만 지정 (DOE 없음) ----
  const renderMultiRepeatControls = (row: ScenarioRow) => {
    const p = row.params || {};
    const repeat = p.multiRepeatCount ?? 24;
    const directions = p.multiRepeatDirections ?? diverseDefaultDirs(repeat);

    // 유효성 검사
    const validDirections = Array.isArray(directions) && directions.length === repeat 
      ? directions 
      : diverseDefaultDirs(repeat);

    const dirOptions = ALL_DIRS.map(d => ({ label: `${dirLabel(d)} (${d})`, value: d }));

    const setRepeat = (v: number) => {
      setScenarios(prev => prev.map(r => {
        if (r.id !== row.id) return r;
        const oldDirs = r.params?.multiRepeatDirections ?? diverseDefaultDirs(repeat);
        const newDirs = v <= oldDirs.length 
          ? oldDirs.slice(0, v) 
          : [...oldDirs, ...diverseDefaultDirs(v - oldDirs.length)];
        return { 
          ...r, 
          params: { 
            ...(r.params||{}), 
            multiRepeatCount: v, 
            multiRepeatDirections: newDirs as CumDirection[] 
          } 
        };
      }));
    };

    const setCell = (ci: number, val: CumDirection) => {
      setScenarios(prev => prev.map(r => {
        if (r.id !== row.id) return r;
        const oldDirs = r.params?.multiRepeatDirections ?? diverseDefaultDirs(repeat);
        const newDirs = oldDirs.map((cv, j) => j === ci ? val : cv);
        return { 
          ...r, 
          params: { 
            ...(r.params||{}), 
            multiRepeatDirections: newDirs as CumDirection[] 
          } 
        };
      }));
    };

    const handleAuto = () => {
      const auto = diverseDefaultDirs(repeat);
      setScenarios(prev => prev.map(r => r.id===row.id ? { 
        ...r, 
        params: { 
          ...(r.params||{}), 
          multiRepeatCount: repeat, 
          multiRepeatDirections: auto as CumDirection[] 
        } 
      } : r));
      message.success(`${repeat}회 시나리오를 다양한 조합으로 자동 채움`);
    };

    // 6개씩 끊어서 여러 행으로 표시
    const COLS_PER_ROW = 6;
    const numRows = Math.ceil(repeat / COLS_PER_ROW);
    
    const vtopCell = { style: { verticalAlign: "top", padding: "4px 6px" } } as const;
    const matrixColumns: ColumnsType<any> = [
      { title: "낙하 순서", dataIndex: "__idx", width: 90, onCell: () => vtopCell, fixed: "left" },
      ...Array.from({ length: COLS_PER_ROW }).map((_, c) => ({
        title: `시나리오`,
        dataIndex: `c${c}`,
        width: 140,
        onCell: () => vtopCell,
        render: (_: any, rec: any) => {
          const actualIndex = rec.__rowIndex * COLS_PER_ROW + c;
          if (actualIndex >= repeat) return null;
          return (
            <Flex vertical gap={4}>
              <Text type="secondary" style={{ fontSize: 11 }}>#{actualIndex + 1}</Text>
              <Select
                size="small"
                style={{ width: 120 }}
                dropdownMatchSelectWidth={false}
                value={rec[`c${c}`]}
                options={dirOptions}
                onChange={(v)=> setCell(actualIndex, v as CumDirection)}
                showSearch
                optionFilterProp="label"
              />
            </Flex>
          );
        }
      }))
    ];

    const matrixData = Array.from({ length: numRows }).map((_, rowIdx) => {
      const rowObj: any = { 
        key: rowIdx, 
        __idx: `${rowIdx * COLS_PER_ROW + 1}-${Math.min((rowIdx + 1) * COLS_PER_ROW, repeat)}`,
        __rowIndex: rowIdx 
      };
      for (let c = 0; c < COLS_PER_ROW; c++) {
        const actualIndex = rowIdx * COLS_PER_ROW + c;
        rowObj[`c${c}`] = actualIndex < repeat ? validDirections[actualIndex] : null;
      }
      return rowObj;
    });

    return (
      <Flex vertical gap={10}>
        {/* Height & Surface (공통) */}
        {renderCommonDropControls(row, setScenarios)}

        {/* Tolerance controls */}
        {renderToleranceControls(row, setScenarios)}

        {/* local CSS for tight spacing & top align */}
        <style>{`
          .multi-repeat-matrix .ant-table-tbody > tr > td { vertical-align: top; padding: 4px 6px; }
          .multi-repeat-matrix .ant-select-selector { padding: 0 6px !important; }
        `}</style>
        <Space wrap align="center">
          <Text>회수</Text>
          <InputNumber 
            style={{ width: 100 }} 
            value={repeat} 
            min={1} 
            max={100} 
            onChange={(v)=>setRepeat(Number(v ?? 24))} 
          />
          <Button size="small" onClick={handleAuto}>자동 분포</Button>
          <Tag color="geekblue">{analysisLabel(row)}</Tag>
          <Text type="secondary" style={{ fontSize: 12 }}>({COLS_PER_ROW}개씩 {numRows}행으로 표시)</Text>
        </Space>
        <div className="multi-repeat-matrix" style={{ overflowX: "auto" }}>
          <Table
            size="small"
            pagination={false}
            columns={matrixColumns}
            dataSource={matrixData}
            rowClassName={() => "tight-vtop"}
            bordered
          />
        </div>
      </Flex>
    );
  };

  // ---- 누적 낙하 전용 컨트롤: DOE(행) x 회수(열) 매트릭스 ----
  const renderCumControls = (row: ScenarioRow) => {
    const { repeat, doe, grid } = normalizeCum(row);
    const dirOptions = ALL_DIRS.map(d => ({ label: `${dirLabel(d)} (${d})`, value: d }));

    const setRepeat = (v: 2|3|4|5) => {
      setScenarios(prev => prev.map(r => {
        if (r.id !== row.id) return r;
        const old = normalizeCum(r);
        const newGrid = old.grid.map(rw => {
          const base = rw.length ? rw : diverseDefaultDirs(old.repeat);
          const resized = v <= base.length ? base.slice(0, v) : [...base, ...diverseDefaultDirs(v - base.length)];
          return resized as CumDirection[];
        });
        const deduped = dedupGrid(newGrid);
        warnIfDOEExceedsCapacity(v, old.doe);
        return { ...r, params: { ...(r.params||{}), cumRepeatCount: v, cumDOECount: old.doe, cumDirectionsGrid: deduped } };
      }));
    };

    const setDOE = (v: number) => {
      setScenarios(prev => prev.map(r => {
        if (r.id !== row.id) return r;
        const old = normalizeCum(r);
        warnIfDOEExceedsCapacity(old.repeat, v);
        let newGrid = old.grid.slice(0, v);
        if (v > old.grid.length) {
          const toAdd = v - old.grid.length;
          for (let i=0; i<toAdd; i++) {
            const proposal = rotate(old.grid[0], (old.grid.length + i) % old.repeat) as CumDirection[];
            newGrid.push(ensureRowUnique(proposal, newGrid));
          }
        }
        newGrid = dedupGrid(newGrid);
        return { ...r, params: { ...(r.params||{}), cumRepeatCount: old.repeat, cumDOECount: v, cumDirectionsGrid: newGrid } };
      }));
    };

    const setCell = (ri: number, ci: number, val: CumDirection) => {
      setScenarios(prev => prev.map(r => {
        if (r.id !== row.id) return r;
        const old = normalizeCum(r);
        const newGrid = old.grid.map((rw, i) => i===ri ? rw.map((cv, j) => j===ci ? val : cv) as CumDirection[] : rw);
        const deduped = dedupGrid(newGrid);
        return { ...r, params: { ...(r.params||{}), cumRepeatCount: old.repeat, cumDOECount: old.doe, cumDirectionsGrid: deduped } };
      }));
    };

    const handleAuto = () => {
      warnIfDOEExceedsCapacity(repeat, doe);
      const auto = diverseDefaultGrid(repeat, doe) as CumDirection[][];
      setScenarios(prev => prev.map(r => r.id===row.id ? { ...r, params: { ...(r.params||{}), cumRepeatCount: repeat, cumDOECount: doe, cumDirectionsGrid: auto } } : r));
      message.success("DOE×회수 매트릭스를 다양한 조합(행 유니크)으로 자동 채움");
    };

    // Build matrix table — 상단 정렬 + 타이트 패딩 + 고정 폭 레이아웃
    const vtopCell = { style: { verticalAlign: "top", padding: "4px 6px" } } as const;
    const matrixColumns: ColumnsType<any> = [
      { title: "DOE #", dataIndex: "__idx", width: 64, onCell: () => vtopCell },
      ...Array.from({ length: repeat }).map((_, c) => ({
        title: `낙하 #${c+1}`,
        dataIndex: `c${c}`,
        width: 140,
        onCell: () => vtopCell,
        render: (_: any, rec: any) => (
          <Select
            size="small"
            style={{ width: 120 }}
            dropdownMatchSelectWidth={false}
            value={rec[`c${c}`]}
            options={dirOptions}
            onChange={(v)=> setCell(rec.__rowIndex, c, v as CumDirection)}
            showSearch
            optionFilterProp="label"
          />
        )
      }))
    ];

    const matrixData = Array.from({ length: doe }).map((_, rIdx) => {
      const rowObj: any = { key: rIdx, __idx: `#${rIdx+1}`, __rowIndex: rIdx };
      for (let c=0; c<repeat; c++) rowObj[`c${c}`] = grid[rIdx][c];
      return rowObj;
    });

    return (
      <Flex vertical gap={10}>
        {/* Height & Surface (공통) */}
        {renderCommonDropControls(row, setScenarios)}

        {/* Tolerance controls */}
        {renderToleranceControls(row, setScenarios)}

        {/* local CSS for tight spacing & top align */}
        <style>{`
          .doe-matrix .ant-table-tbody > tr > td { vertical-align: top; padding: 4px 6px; }
          .doe-matrix .ant-select-selector { padding: 0 6px !important; }
        `}</style>
        <Space wrap align="center">
          <Text>회수(열)</Text>
          <Select style={{ width: 120 }} value={repeat} options={[2,3,4,5].map(v=>({label:`${v}회`, value:v}))} onChange={(v)=>setRepeat(v as 2|3|4|5)} />
          <Divider type="vertical" />
          <Text>DOE 수(행)</Text>
          <Select style={{ width: 160 }} value={doe} options={DOE_COUNTS.map(v=>({label:`${v}`, value:v}))} onChange={(v)=>setDOE(v)} />
          <Button size="small" onClick={handleAuto}>자동 분포</Button>
          <Tag color="geekblue">{analysisLabel(row)}</Tag>
        </Space>
        <div className="doe-matrix" style={{ overflowX: "hidden" }}>
          <Table
            size="small"
            pagination={false}
            columns={matrixColumns}
            dataSource={matrixData}
            rowClassName={() => "tight-vtop"}
            style={{ tableLayout: "fixed" }}
          />
        </div>
      </Flex>
    );
  };

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

    // ---- multiRepeatCumulative ----
    if (row.analysisType === "multiRepeatCumulative") {
      return renderMultiRepeatControls(row);
    }

    // ---- fullAngleCumulative ----
    if (row.analysisType === "fullAngleCumulative") {
      return renderCumControls(row);
    }

    // ---- fullAngleMBD ----
    if (row.analysisType === "fullAngleMBD") {
      const value = row.params?.mbdCount ?? 1000;
      const angleSource: AngleSource = row.params?.angleSource ?? "lhs";
      const angleSourceId = row.params?.angleSourceId ?? "";
      const angleSourceFileName = row.params?.angleSourceFileName;

      return (
        <Flex vertical gap={10}>
          <Flex gap={10} align="center" wrap style={{ alignItems: "flex-start" }}>
            {/* Height & Surface (공통) */}
            {renderCommonDropControls(row, setScenarios)}

            <Divider type="vertical" />
          <Text>샘플</Text>
          <Select
            style={{ width: 160 }}
            value={value}
            options={MBD_COUNTS.map(v => ({ label: v.toLocaleString(), value: v }))}
            onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params||{}), mbdCount: v } } : r))}
            size="small"
          />
          <Divider type="vertical" />
          <Text>각도 선택</Text>
          <Radio.Group
            size="small"
            value={angleSource}
            onChange={(e) => setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), angleSource: e.target.value as AngleSource } } : r))}
          >
            <Radio value="lhs">LHS(기본)</Radio>
            <Radio value="fromMBD">기존 MBD 결과 사용</Radio>
          </Radio.Group>
          {angleSource === "fromMBD" && (
            <Space wrap size={8}>
              <Select
                style={{ width: 260 }}
                placeholder="위(이전) MBD 시나리오 선택"
                value={angleSourceId || undefined}
                options={priorMbdOptions(row)}
                onChange={(v)=> setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), angleSourceId: v } } : r))}
                disabled={priorMbdOptions(row).length === 0}
                size="small"
                dropdownMatchSelectWidth={false}
              />
              <Upload {...makeAnglesUploadProps(row)}>
                <Button size="small" icon={<UploadOutlined />}>각도 파일(.json/.csv)</Button>
              </Upload>
              {angleSourceFileName && <Tag color="geekblue">{angleSourceFileName}</Tag>}
            </Space>
          )}
          <Tag>{analysisLabel(row)}</Tag>
          </Flex>
          
          {/* Tolerance controls */}
          {renderToleranceControls(row, setScenarios)}
        </Flex>
      );
    }

    // ---- fullAngle ----
    if (row.analysisType === "fullAngle") {
      const total = row.params?.faTotal ?? 100;
      const face = !!row.params?.includeFace6;
      const edge = !!row.params?.includeEdge12;
      const corner = !!row.params?.includeCorner8;
      const fixedShots = (face ? 6 : 0) + (edge ? 12 : 0) + (corner ? 8 : 0);
      const remaining = total - fixedShots;

      const angleSource: AngleSource = row.params?.angleSource ?? "lhs";
      const angleSourceId = row.params?.angleSourceId ?? "";
      const angleSourceFileName = row.params?.angleSourceFileName;

      const remainingTag = (
        <Tag color={remaining < 0 ? "error" : remaining === 0 ? "warning" : undefined}>
          나머지 자동 배치: {remaining}
        </Tag>
      );

      return (
        <Flex vertical gap={10}>
          <Flex gap={10} align="center" wrap style={{ alignItems: "flex-start" }}>
            {/* Height & Surface (공통) */}
            {renderCommonDropControls(row, setScenarios)}

            <Divider type="vertical" />
          <Text>총 개수</Text>
          <Select
            style={{ width: 120 }}
            value={total}
            options={FULL_ANGLE_COUNTS.map(v => ({ label: v.toString(), value: v }))}
            onChange={(v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params||{}), faTotal: v } } : r))}
            size="small"
          />
          <Divider type="vertical" />
          <Space size={8} wrap>
            <span><Switch size="small" checked={face} onChange={(val)=> setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), includeFace6: val } }: r))} /> 면(+6)</span>
            <span><Switch size="small" checked={edge} onChange={(val)=> setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), includeEdge12: val } }: r))} /> 엣지(+12)</span>
            <span><Switch size="small" checked={corner} onChange={(val)=> setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), includeCorner8: val } }: r))} /> 코너(+8)</span>
          </Space>
          {remainingTag}

          <Divider type="vertical" />
          <Text>각도 선택</Text>
          <Radio.Group
            size="small"
            value={angleSource}
            onChange={(e) => setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), angleSource: e.target.value as AngleSource } } : r))}
          >
            <Radio value="lhs">LHS(기본)</Radio>
            <Radio value="fromMBD">이전 MBD 결과 사용</Radio>
            <Radio value="usePrevResult">이전 단계 해석 사용</Radio>
          </Radio.Group>

          {(angleSource === "fromMBD" || angleSource === "usePrevResult") && (
            <Space wrap size={8}>
              {angleSource === "fromMBD" ? (
                <Select
                  style={{ width: 260 }}
                  placeholder="위(이전) MBD 시나리오 선택"
                  value={angleSourceId || undefined}
                  options={priorMbdOptions(row)}
                  onChange={(v)=> setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), angleSourceId: v } } : r))}
                  disabled={priorMbdOptions(row).length === 0}
                  size="small"
                  dropdownMatchSelectWidth={false}
                />
              ) : (
                <Select
                  style={{ width: 260 }}
                  placeholder="위(이전) 시나리오 선택"
                  value={angleSourceId || undefined}
                  options={priorFaOptions(row)}
                  onChange={(v)=> setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), angleSourceId: v } } : r))}
                  disabled={priorFaOptions(row).length === 0}
                  size="small"
                  dropdownMatchSelectWidth={false}
                />
              )}
              <Upload {...makeAnglesUploadProps(row)}>
                <Button size="small" icon={<UploadOutlined />}>각도 파일(.json/.csv)</Button>
              </Upload>
              {angleSourceFileName && <Tag color="geekblue">{angleSourceFileName}</Tag>}
              {angleSource === "usePrevResult" && (
                <Tag color="purple">표시명: 전각도 누적 낙하</Tag>
              )}
            </Space>
          )}

          <Tag>{analysisLabel(row)}</Tag>
          </Flex>
          
          {/* Tolerance controls */}
          {renderToleranceControls(row, setScenarios)}
        </Flex>
      );
    }

    // ---- partialImpact ----
    const mode: PartialImpactMode = row.params?.piMode ?? "default";
    const fileName = row.params?.piTxtName;

    const uploadPropsPI: UploadProps = {
      name: "txt",
      multiple: false,
      accept: ".txt",
      beforeUpload: async (file) => {
        try {
          const content = await bytesToString(file);
          if (!content.trim()) { message.error("빈 txt 파일입니다."); return Upload.LIST_IGNORE as unknown as false; }
          setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params||{}), piMode: "txt", piTxtName: file.name, piTxtFile: file } } : r));
          message.success(`${file.name} 업로드됨`);
        } catch {
          message.error("txt 읽기 실패");
          return Upload.LIST_IGNORE as unknown as false;
        }
        return false;
      },
      itemRender: () => null,
    };

    return (
      <Flex vertical gap={10}>
        <Flex gap={12} align="center" wrap style={{ alignItems: "flex-start" }}>
          <Radio.Group
            size="small"
            value={mode}
            onChange={(e) => setScenarios(prev => prev.map(r => r.id===row.id? { ...r, params: { ...(r.params||{}), piMode: e.target.value as PartialImpactMode } } : r))}
          >
            <Radio value="default">default (자동 선택)</Radio>
            <Radio value="txt">txt 업로드 (패키지 이름)</Radio>
          </Radio.Group>
          {fileName && <Tag color="geekblue">{fileName}</Tag>}
        </Flex>
        
        {/* Tolerance controls */}
        {renderToleranceControls(row, setScenarios)}
      </Flex>
    );
  };

  // Table columns (상단 정렬 적용)
  const topCell = { style: { verticalAlign: "top" } } as const;
  const columns = useMemo<ColumnsType<ScenarioRow>>(() => [
    {
      title: "시나리오 / 해석 항목",
      dataIndex: "name",
      key: "name",
      width: 340,
      onCell: () => topCell,
      render: (value: string, row) => (
        <Flex vertical gap={8}>
          <Flex vertical gap={4}>
            <Text strong style={{ fontSize: 12, color: '#666' }}>시나리오 이름</Text>
            <Input
              size="small"
              value={row.name}
              onChange={(e)=> setScenarios(prev => prev.map(r => r.id===row.id? { ...r, name: e.target.value } : r))}
              placeholder="시나리오 이름"
            />
          </Flex>
          <Flex vertical gap={4}>
            <Text strong style={{ fontSize: 12, color: '#666' }}>해석 항목</Text>
            <Select
              style={{ width: "100%" }}
              size="small"
              value={row.analysisType}
              onChange={(v: AnalysisType) => {
                setScenarios((prev) => prev.map((r) => (r.id === row.id ? {
                  ...r,
                  analysisType: v,
                  description: DEFAULT_DESCRIPTIONS[v],
                  params:
                    v === "fullAngleMBD" ? { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                    v === "fullAngle" ? { faTotal: 100, includeFace6: true, includeEdge12: true, includeCorner8: true, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                    v === "fullAngleCumulative" ? { cumRepeatCount: 3, cumDOECount: 5, cumDirectionsGrid: diverseDefaultGrid(3,5), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                    v === "multiRepeatCumulative" ? { multiRepeatCount: 24, multiRepeatDirections: diverseDefaultDirs(24), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                    v === "predefinedAttitudes" ? { predefinedMode: "all26", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                    v === "edgeAxisRotation" ? { edgeAxis: "top", edgeDivisions: 12, heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                    v === "dropWeightImpact" ? { impactPackagePatterns: ["*pkg*"], impactLocationMode: "grid", impactGridMode: "3x3", impactPercentageX: 50, impactPercentageY: 50, impactRandomCount: 10, impactorType: "ball", impactorBallDiameter: 6, impactorCylinderDiameter: 8, impactorCylinderDiameterCustom: 10, tolerance: { mode: "disabled" } } :
                    { piMode: "default", tolerance: { mode: "disabled" } },
                } : r)));
              }}
              options={ANALYSIS_OPTIONS.map((o) => ({ label: o.label, value: o.value }))}
            />
          </Flex>
          {row.description && (
            <Text type="secondary" style={{ fontSize: 11, fontStyle: 'italic', lineHeight: '1.4' }}>
              {row.description}
            </Text>
          )}
          <Space size={4} wrap>
            <Tag style={{ fontSize: 11 }}>ID: {row.id}</Tag>
            {row.fileName && <Tag color="geekblue" style={{ fontSize: 11 }}>K: {row.fileName}</Tag>}
            {row.objFileName && <Tag color="purple" style={{ fontSize: 11 }}>OBJ: {row.objFileName}</Tag>}
          </Space>
        </Flex>
      ),
    },
    {
      title: "옵션",
      key: "options",
      onCell: () => topCell,
      render: (_: any, row) => renderOptionControls(row),
    },
    {
      title: "액션",
      key: "actions",
      fixed: "right",
      width: 120,
      onCell: () => topCell,
      render: (_: any, row) => (
        <Space>
          <Button size="small" icon={<PlayCircleOutlined />} type="primary" onClick={() => handleRun([row.id])}>실행</Button>
          <Button size="small" icon={<DeleteOutlined />} danger onClick={() => handleDelete(row.id)} />
        </Space>
      ),
    },
  ], [scenarios]);

  const rowSelection = { selectedRowKeys, onChange: (keys: React.Key[]) => setSelectedRowKeys(keys) };

  // Actions
  const handleAddEmpty = () => {
    setScenarios((prev) => ([
      ...prev,
      {
        id: uid("scn"),
        name: "새 시나리오",
        description: DEFAULT_DESCRIPTIONS["fullAngleMBD"],
        analysisType: "fullAngleMBD",
        params: { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } }
      },
    ]));
  };

  const handleStandardScenarioSelect = (scenario: StandardScenario) => {
    // Map standard scenario to internal format
    const analysisTypeMap: Record<string, AnalysisType> = {
      "multibody": "fullAngleMBD",
      "fall": "fullAngle",
      "cumulative": "fullAngleCumulative",
      "multiCumulative": "multiRepeatCumulative",
      "weightImpact": "dropWeightImpact",
      "predefined": "predefinedAttitudes",
      "edgeRotation": "edgeAxisRotation",
    };

    const analysisType = analysisTypeMap[scenario.parameters.analysisType as string] || "fullAngleMBD";

    // Build params based on analysis type
    let params: ScenarioRow['params'] = {
      heightMode: "const",
      heightConst: scenario.parameters.dropHeight as number || 1.0,
      surface: (scenario.parameters.impactSurface as SurfaceType) || "steelPlate",
      tolerance: { mode: "disabled" },
    };

    // Add type-specific parameters
    if (analysisType === "fullAngleMBD") {
      params.mbdCount = scenario.angles.length;
      params.angleSource = "lhs";
    } else if (analysisType === "fullAngle") {
      params.faTotal = scenario.angles.length;
      params.includeFace6 = true;
      params.includeEdge12 = true;
      params.includeCorner8 = true;
      params.angleSource = "lhs";
    } else if (analysisType === "fullAngleCumulative") {
      // DOE x repeat matrix - use angles as DOE rows
      const repeatCount = (scenario.parameters.repeatCount as number) || 3;
      params.cumRepeatCount = (repeatCount >= 2 && repeatCount <= 5 ? repeatCount : 3) as 2|3|4|5;
      params.cumDOECount = scenario.angles.length;
      // Initialize with default grid (will be customizable by user)
      params.cumDirectionsGrid = diverseDefaultGrid(params.cumRepeatCount, params.cumDOECount);
    } else if (analysisType === "multiRepeatCumulative") {
      // Multiple repeats without DOE - use angles as repeat sequence
      const repeatCount = (scenario.parameters.repeatCount as number) || scenario.angles.length;
      params.multiRepeatCount = repeatCount;
      params.multiRepeatDirections = diverseDefaultDirs(repeatCount);
    } else if (analysisType === "predefinedAttitudes") {
      // Determine mode from angle count
      const count = scenario.angles.length;
      params.predefinedMode = count === 6 ? "faces6" : count === 12 ? "edges12" : count === 8 ? "corners8" : "all26";
      // Initialize with scenario angles
      params.predefinedAngles = scenario.angles.map((angle) => ({
        name: angle.name,
        phi: angle.phi,
        theta: angle.theta,
        psi: angle.psi
      }));
    } else if (analysisType === "edgeAxisRotation") {
      params.edgeAxis = "top";
      params.edgeDivisions = scenario.angles.length;
    } else if (analysisType === "dropWeightImpact") {
      params.impactPackagePatterns = ["*pkg*"];
      params.impactLocationMode = "grid";
      params.impactGridMode = "3x3";
      params.impactPercentageX = 50;
      params.impactPercentageY = 50;
      params.impactRandomCount = 10;
      params.impactorType = "ball";
      params.impactorBallDiameter = 6;
      params.impactorCylinderDiameter = 8;
      params.impactorCylinderDiameterCustom = 10;
    }

    const newScenario: ScenarioRow = {
      id: uid("scn"),
      name: scenario.name,
      description: scenario.description,
      analysisType,
      params,
    };

    setScenarios((prev) => [...prev, newScenario]);
    setStandardModalVisible(false);
    message.success(`규격 시나리오 "${scenario.name}"를 추가했습니다.`);
  };

  const handleDelete = (id: string) => {
    setScenarios((prev) => prev.filter((r) => r.id !== id));
    setSelectedRowKeys((prev) => prev.filter((k) => k !== id));
  };

  const handleBulkSetType = () => {
    if (!bulkType) return message.warning("먼저 상단 드롭다운에서 해석 항목을 선택하세요.");
    if (!selectedRowKeys.length) return message.warning("변경할 시나리오를 선택하세요.");
    setScenarios((prev) => prev.map((r) => selectedRowKeys.includes(r.id) ? ({
      ...r,
      analysisType: bulkType,
      params:
        bulkType === "fullAngleMBD" ? { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
        bulkType === "fullAngle" ? { faTotal: 100, includeFace6: true, includeEdge12: true, includeCorner8: true, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
        bulkType === "fullAngleCumulative" ? { cumRepeatCount: 3, cumDOECount: 5, cumDirectionsGrid: diverseDefaultGrid(3,5), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
        bulkType === "multiRepeatCumulative" ? { multiRepeatCount: 24, multiRepeatDirections: diverseDefaultDirs(24), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
        bulkType === "predefinedAttitudes" ? { predefinedMode: "all26", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
        bulkType === "edgeAxisRotation" ? { edgeAxis: "top", edgeDivisions: 12, heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
        bulkType === "dropWeightImpact" ? { impactPackagePatterns: ["*pkg*"], impactLocationMode: "grid", impactGridMode: "3x3", impactPercentageX: 50, impactPercentageY: 50, impactRandomCount: 10, impactorType: "ball", impactorBallDiameter: 6, impactorCylinderDiameter: 8, impactorCylinderDiameterCustom: 10, tolerance: { mode: "disabled" } } :
        { piMode: "default", tolerance: { mode: "disabled" } },
    }) : r));
    message.success(`선택한 ${selectedRowKeys.length}개 시나리오에 적용했습니다.`);
  };

  const handleRun = (ids?: string[]) => {
    const runIds = (ids && ids.length ? ids : selectedRowKeys) as string[];
    if (!runIds.length) return message.info("실행할 시나리오를 선택하세요.");

    const payload = scenarios.filter((s) => runIds.includes(s.id)).map((s) => ({
      id: s.id,
      name: s.name,
      analysisType: s.analysisType,
      analysisLabel: analysisLabel(s),
      fileName: s.fileName,
      objFileName: s.objFileName,
      params: s.params ?? {},
    }));

    Modal.confirm({
      title: "시뮬레이션 실행",
      content: (
        <div>
          <p>{`${payload.length}개 시나리오를 실행합니다.`}</p>
          <pre style={{ maxHeight: 240, overflow: "auto", background: "#0b1021", color: "#e6e6e6", padding: 12, borderRadius: 8 }}>
            {JSON.stringify(payload, null, 2)}
          </pre>
        </div>
      ),
      onOk: async () => {
        // await api.post("/api/submit/dyna/jobs", payload)
        await new Promise((r) => setTimeout(r, 600));
        message.success("작업 큐에 제출했습니다.");
      },
    });
  };

  const handleExport = () => {
    const blob = new Blob([JSON.stringify(scenarios, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `scenarios_${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleImport: React.ChangeEventHandler<HTMLInputElement> = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const text = await file.text();
      const data = JSON.parse(text) as ScenarioRow[];
      if (!Array.isArray(data)) throw new Error("Invalid format");
      const safe = data.map((d) => ({
        id: d.id || uid("scn"),
        name: d.name || "Imported",
        fileName: d.fileName,
        analysisType: (ANALYSIS_OPTIONS.some(o => o.value === d.analysisType) ? d.analysisType : "fullAngleMBD") as AnalysisType,
        params: d.params ?? {},
      }));
      setScenarios(safe);
      message.success("시나리오를 불러왔습니다.");
    } catch (err) {
      console.error(err);
      message.error("불러오기 실패: JSON 형식을 확인하세요.");
    } finally {
      e.currentTarget.value = "";
    }
  };

  return (
    <Flex vertical gap={16} className="p-4">
      <Title level={3} style={{ margin: 0 }}>Simulation Automation</Title>
      <Text type="secondary">TypeScript + Vite + React + Ant Design · OBJ/K 드래그&드롭 · 상단정렬 UI · 높이/표면 공통 옵션 · 누적 낙하 DOE×회수 매트릭스 · 각도 변동 허용 (면/엣지/코너)</Text>

      {/* OBJ 먼저, 그 아래 K */}
      <Card bodyStyle={{ padding: 0 }}>
        <Dragger {...uploadPropsOBJ} style={{ padding: 20 }}>
          <p className="ant-upload-drag-icon"><InboxOutlined /></p>
          <p className="ant-upload-text">여기로 <b>.obj</b> 파일을 끌어오거나 클릭하여 선택 (MBD)</p>
          <p className="ant-upload-hint">선택한 1개 행이 있으면 그 행에 연결, 없으면 새 시나리오 생성</p>
        </Dragger>
        <Divider style={{ margin: 0 }} />
        <Dragger {...uploadPropsK} style={{ padding: 20 }}>
          <p className="ant-upload-drag-icon"><InboxOutlined /></p>
          <p className="ant-upload-text">여기로 <b>.k/.key/.dyn</b> 파일을 끌어오거나 클릭하여 선택 (FE)</p>
          <p className="ant-upload-hint">선택한 1개 행이 있으면 그 행에 연결, 없으면 새 시나리오 생성</p>
        </Dragger>
      </Card>

      <Card>
        <Flex gap={8} wrap align="center" justify="space-between" style={{ marginBottom: 12 }}>
          <Space wrap>
            <Button type="dashed" icon={<PlusOutlined />} onClick={handleAddEmpty}>빈 시나리오 추가</Button>
            <Button type="primary" icon={<PlusOutlined />} onClick={() => setStandardModalVisible(true)}>규격 시나리오 추가</Button>

            <Select
              style={{ width: 300 }}
              placeholder="선택한 시나리오에 일괄 적용할 해석 항목"
              value={bulkType}
              onChange={setBulkType}
              options={ANALYSIS_OPTIONS.map(o => ({ label: o.label, value: o.value }))}
              size="small"
            />
            <Button size="small" onClick={handleBulkSetType}>일괄 적용</Button>

            <Divider type="vertical" />

            <Button size="small" icon={<PlayCircleOutlined />} type="primary" onClick={() => handleRun()}>선택 실행</Button>
          </Space>

          <Space wrap>
            <label>
              <input type="file" accept="application/json" onChange={handleImport} style={{ display: "none" }} id="scenario-import" />
              <Button size="small" icon={<UploadOutlined />} onClick={() => document.getElementById("scenario-import")?.click()}>불러오기</Button>
            </label>
            <Button size="small" icon={<SaveOutlined />} onClick={handleExport}>내보내기</Button>
          </Space>
        </Flex>

        <Table
          rowKey="id"
          size="small"
          rowSelection={rowSelection}
          columns={columns}
          dataSource={scenarios}
          pagination={{ pageSize: 10, showSizeChanger: true }}
          locale={{ emptyText: "상단 드래거로 OBJ 또는 K 파일을 추가하세요." }}
          style={{ tableLayout: "fixed" }}
        />
      </Card>

      <Card size="small">
        <Text type="secondary">
          • 모든 전각도 해석(MBD/FA/누적)에서 공통으로 <b>낙하 높이(고정값 또는 LHS 범위)</b>와 <b>낙하 표면(철판/보도블럭/콘크리트/목재)</b>을 정의합니다.
          <br/>• 높이 모드가 LHS일 때는 <b>min/max</b>를 지정합니다(단위: m).
          <br/>• 누적 매트릭스는 <b>타이트 패딩 + 고정 폭</b>으로 표시하며, 행 간 완전 동일 조합을 방지합니다(행 내 중복 허용).
          <br/>• "기존 결과 사용"은 현재 행 <b>위쪽</b> 시나리오만 드롭다운으로 표시합니다.
          <br/>• <b>각도 변동 허용</b>을 활성화하면 면(6개), 엣지(12개), 코너(8개)별로 최대 변동량을 설정할 수 있으며, LHS 샘플링으로 실제 각도가 생성됩니다.
        </Text>
      </Card>

      <StandardScenarioModal
        visible={standardModalVisible}
        onClose={() => setStandardModalVisible(false)}
        onSelect={handleStandardScenarioSelect}
      />
    </Flex>
  );
};

export default SimulationAutomationComponent;

