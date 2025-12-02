import React, { useMemo, useRef, useState } from "react";
import type { UploadProps } from "antd";
import { Button, Card, Divider, Flex, Input, InputNumber, Modal, Radio, Select, Space, Switch, Table, Tag, Typography, Upload, message } from "antd";
import type { ColumnsType } from "antd/es/table";
import { DeleteOutlined, InboxOutlined, PlayCircleOutlined, PlusOutlined, SaveOutlined, UploadOutlined } from "@ant-design/icons";

const { Dragger } = Upload;
const { Title, Text } = Typography;

// ---- Types ----
export type AnalysisType =
  | "fullAngleMBD" // 전각도 다물체동역학 낙하 시뮬레이션
  | "fullAngle"    // 전각도 낙하 시뮬레이션
  | "fullAngleCumulative" // 전각도 누적 낙하
  | "multiRepeatCumulative" // 다회 누적 낙하
  | "partialImpact"; // 전위치 부분 충격 시뮬레이션

export type PartialImpactMode = "default" | "txt";
export type AngleSource = "lhs" | "fromMBD" | "usePrevResult"; // LHS 기본, 기존 결과 사용
export type HeightMode = "const" | "lhs"; // 낙하 높이 모드
export type SurfaceType = "steelPlate" | "pavingBlock" | "concrete" | "wood";

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

    // partialImpact 전용
    piMode?: PartialImpactMode;
    piTxtName?: string; // uploaded filename
    piTxtFile?: File;

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
  { label: "전위치 부분 충격", value: "partialImpact", hint: "배면 XY 격자 포인트 충격" },
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
  return "전위치 부분 충격";
};

// Predefined counts
const MBD_COUNTS = [1000, 5000, 10000, 50000, 100000, 200000, 500000, 1000000, 2000000, 5000000];
const FULL_ANGLE_COUNTS = [10, 50, 100, 200, 300, 400, 500, 600, 800, 1000];
const DOE_COUNTS = [1,2,3,5,10,20,30,50,100,200,300,500,1000];

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
        setScenarios(prev => prev.map(r => r.id === sel.id ? { ...r, objFileName: f.name, objFile: f, analysisType: r.analysisType === "partialImpact" ? "fullAngleMBD" : r.analysisType } : r));
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
        setScenarios(prev => prev.map(r => r.id === sel.id ? { ...r, fileName: f.name, file: f, analysisType: r.analysisType === "partialImpact" ? "fullAngle" : r.analysisType } : r));
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
      title: "시나리오",
      dataIndex: "name",
      key: "name",
      width: 320,
      onCell: () => topCell,
      render: (value: string, row) => (
        <Flex vertical>
          <Input
            size="small"
            value={row.name}
            onChange={(e)=> setScenarios(prev => prev.map(r => r.id===row.id? { ...r, name: e.target.value } : r))}
            placeholder="시나리오 이름"
            style={{ maxWidth: 420 }}
          />
          <Space size={4} wrap>
            <Tag>id: {row.id}</Tag>
            {row.fileName && <Tag color="geekblue">K: {row.fileName}</Tag>}
            {row.objFileName && <Tag color="purple">OBJ: {row.objFileName}</Tag>}
          </Space>
        </Flex>
      ),
    },
    {
      title: "해석 항목",
      dataIndex: "analysisType",
      key: "analysisType",
      width: 260,
      onCell: () => topCell,
      render: (_: any, row) => (
        <Select
          style={{ width: "100%" }}
          size="small"
          value={row.analysisType}
          onChange={(v: AnalysisType) => {
            setScenarios((prev) => prev.map((r) => (r.id === row.id ? {
              ...r,
              analysisType: v,
              params:
                v === "fullAngleMBD" ? { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                v === "fullAngle" ? { faTotal: 100, includeFace6: true, includeEdge12: true, includeCorner8: true, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                v === "fullAngleCumulative" ? { cumRepeatCount: 3, cumDOECount: 5, cumDirectionsGrid: diverseDefaultGrid(3,5), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                v === "multiRepeatCumulative" ? { multiRepeatCount: 24, multiRepeatDirections: diverseDefaultDirs(24), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                { piMode: "default", tolerance: { mode: "disabled" } },
            } : r)));
          }}
          options={ANALYSIS_OPTIONS.map((o) => ({ label: (
            <Flex justify="space-between" gap={8}>
              <span>{o.label}</span>
              <Text type="secondary" style={{ fontSize: 12 }}>{o.hint}</Text>
            </Flex>
          ), value: o.value }))}
        />
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
      { id: uid("scn"), name: "새 시나리오", analysisType: "fullAngleMBD", params: { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } },
    ]));
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
    </Flex>
  );
};

export default SimulationAutomationComponent;

