import React, { useEffect, useMemo, useRef, useState } from "react";
import Plotly from "plotly.js-dist-min";
import createPlotlyComponent from "react-plotly.js/factory";
const Plot = createPlotlyComponent(Plotly);
import Papa from "papaparse";
import {
  Card,
  Upload,
  Typography,
  Row,
  Col,
  Form,
  InputNumber,
  Select,
  Switch,
  Button,
  Divider,
  message,
  Slider,
  Space,
  Tag,
  Tooltip,
  Tabs,
  Segmented
} from "antd";
import { InboxOutlined, DownloadOutlined, RedoOutlined, CameraOutlined, AppstoreOutlined, ColumnHeightOutlined } from "@ant-design/icons";

/**
 * MollweideStressPlot.tsx (v2)
 * - Adds: (1) programmatic data injection (props) akin to Python execute()
 *         (2) PNG export of current plot (or all in grid)
 *         (3) Multi-view compare: Tabs (single stat) or 2x2 Grid (mean/max/var/pexceed)
 */

const { Title, Text } = Typography;
const { Dragger } = Upload;

// ---------------------- Types ----------------------
export interface SampleRow { theta: number; phi: number; gamma: number; stress: number; }
export type AggKey = "mean" | "max" | "var" | "pexceed";

export interface ExecuteLikeOptions {
  mode?: "csv" | "sampleA" | "sampleB"; // currently only csv via props.data/props.csvText
  data?: SampleRow[]; // programmatic data injection (takes precedence)
  csvText?: string;   // alternatively pass CSV text (theta,phi,gamma,stress)
  deg?: boolean;      // angles in degrees
  prefix?: string;
  nlat?: number; nlon?: number;
  topN?: number; suppress?: [number, number, number];
  lon0?: number;      // central meridian in degrees
  vmin?: number; vmax?: number;
  levels?: number;
  colorscale?: string; reverse?: boolean;
}

interface ComputeOptions {
  nlat: number;
  nlon: number;
  aggKey: AggKey;
  vmin?: number;
  vmax?: number;
  lon0Deg: number;
  levels: number; // parity with python (Plotly is continuous)
  degInput: boolean;
  topN: number;
  suppress: [number, number, number];
}

interface PlotDataPack {
  z: (number | null)[][];
  x: number[]; y: number[];
  markers: { x: number; y: number; label: string }[];
  vmin?: number; vmax?: number;

  // ✅ 추가: 각 셀의 lon/lat(°) (호버용)
  lonlatDeg: [number, number][][];

  // ✅ 추가: 축 눈금용 투영좌표 & 라벨
  xTickVals: number[]; xTickText: string[];
  yTickVals: number[]; yTickText: string[];
}

// ---------------------- Math helpers ----------------------
const PI = Math.PI; const TAU = 2 * Math.PI; const SQ2 = Math.sqrt(2);
const deg2rad = (x: number) => (x * Math.PI) / 180;

function eulerZYXtoDir(theta: number, phi: number, gamma: number, a: [number, number, number] = [0, 0, 1]) {
  const [ax, ay, az] = a;
  const cθ = Math.cos(theta), sθ = Math.sin(theta);
  const cφ = Math.cos(phi),   sφ = Math.sin(phi);
  const cγ = Math.cos(gamma), sγ = Math.sin(gamma);
  const ax1 = ax;
  const ay1 = cγ * ay - sγ * az;
  const az1 = sγ * ay + cγ * az;
  const ax2 =  cφ * ax1 + sφ * az1;
  const ay2 =  ay1;
  const az2 = -sφ * ax1 + cφ * az1;
  const nx = cθ * ax2 - sθ * ay2;
  const ny = sθ * ax2 + cθ * ay2;
  const nz = az2;
  return [nx, ny, nz] as const;
}
function dirToLonLat(nx: number, ny: number, nz: number) {
  let lon = Math.atan2(ny, nx);
  lon = (lon + TAU) % TAU; // [0, 2π)
  const lat = Math.asin(Math.max(-1, Math.min(1, nz)));
  return [lon, lat] as const;
}
function mollweideForward(lon: number, lat: number, lon0 = 0) {
  const HALF_PI = Math.PI / 2;
  const eps = 1e-9;

  // 극점은 안전하게 처리
  if (Math.abs(lat) >= HALF_PI - eps) {
    return [0, Math.sign(lat) * SQ2] as const; // x=0, y=±√2
  }

  const latClamped = Math.max(-HALF_PI + eps, Math.min(HALF_PI - eps, lat));
  const target = Math.PI * Math.sin(latClamped);
  let theta = latClamped;

  for (let it = 0; it < 16; it++) {
    const f = 2 * theta + Math.sin(2 * theta) - target;
    const df = 2 + 2 * Math.cos(2 * theta);
    const d = f / df;
    if (!Number.isFinite(d)) break;         // 0/0 방지
    theta -= d;
    if (Math.abs(d) < 1e-12) break;
  }

  const x = (2 * SQ2 / Math.PI) * ((((lon - lon0 + TAU) % TAU) - Math.PI)) * Math.cos(theta);
  const y = SQ2 * Math.sin(theta);
  return [x, y] as const;
}


// ---------------------- Core pipeline ----------------------
function rasterize(lon: number[], lat: number[], values: number[], Nlat: number, Nlon: number, tau?: number) {
  const sum = Array.from({ length: Nlat }, () => new Float64Array(Nlon));
  const sum2 = Array.from({ length: Nlat }, () => new Float64Array(Nlon));
  const cnt = Array.from({ length: Nlat }, () => new Uint32Array(Nlon));
  const max = Array.from({ length: Nlat }, () => Array(Nlon).fill(-Infinity));
  const exc = Array.from({ length: Nlat }, () => new Uint32Array(Nlon));

  const liArr = new Int32Array(lon.length);
  const ljArr = new Int32Array(lon.length);

  for (let k = 0; k < lon.length; k++) {
    let li = Math.floor(((lat[k] + Math.PI / 2) / Math.PI) * Nlat);
    li = Math.max(0, Math.min(Nlat - 1, li));
    let lj = Math.floor((lon[k] / (2 * Math.PI)) * Nlon);
    lj = Math.max(0, Math.min(Nlon - 1, lj));
    liArr[k] = li; ljArr[k] = lj;
  }
  for (let k = 0; k < lon.length; k++) {
    const i = liArr[k], j = ljArr[k];
    const v = values[k];
    sum[i][j] += v; sum2[i][j] += v * v; cnt[i][j] += 1; if (v > max[i][j]) max[i][j] = v;
  }

  const mean: number[][] = Array.from({ length: Nlat }, () => Array(Nlon).fill(NaN));
  const variance: number[][] = Array.from({ length: Nlat }, () => Array(Nlon).fill(NaN));
  for (let i = 0; i < Nlat; i++) for (let j = 0; j < Nlon; j++) {
    const c = cnt[i][j] || 0;
    if (c > 0) {
      const m = sum[i][j] / c;
      mean[i][j] = m; variance[i][j] = Math.max(0, sum2[i][j] / c - m * m);
    }
  }
  if (tau === undefined) {
    const vals = [...values].sort((a, b) => a - b);
    tau = vals[Math.floor(0.95 * (vals.length - 1))];
  }
  for (let k = 0; k < lon.length; k++) { const i = liArr[k], j = ljArr[k]; exc[i][j] += values[k] > (tau as number) ? 1 : 0; }
  const pex: number[][] = Array.from({ length: Nlat }, () => Array(Nlon).fill(NaN));
  for (let i = 0; i < Nlat; i++) for (let j = 0; j < Nlon; j++) { const c = cnt[i][j] || 0; if (c > 0) pex[i][j] = exc[i][j] / c; }

  return { mean, max, variance, pex, cnt, tau } as const;
}

function inpaintPeriodicLon(M: (number | null)[][], maxIters = 300, tol = 1e-3) {
  const H = M.length, W = H ? M[0].length : 0;
  const known: boolean[][] = Array.from({ length: H }, (_, i) => Array.from({ length: W }, (_, j) => Number.isFinite(M[i][j] as number)));
  let X: number[][] = Array.from({ length: H }, (_, i) => Array.from({ length: W }, (__, j) => (known[i][j] ? (M[i][j] as number) : 0)));
  for (let it = 0; it < maxIters; it++) {
    let maxDelta = 0; const Xold = X; const Xnew: number[][] = Array.from({ length: H }, () => Array(W).fill(0));
    for (let i = 0; i < H; i++) for (let j = 0; j < W; j++) {
      if (known[i][j]) { Xnew[i][j] = Xold[i][j]; continue; }
      const east = Xold[i][(j + 1) % W], west = Xold[i][(j - 1 + W) % W];
      const north = Xold[Math.max(0, i - 1)][j], south = Xold[Math.min(H - 1, i + 1)][j];
      const v = 0.25 * (east + west + north + south);
      Xnew[i][j] = v; const d = Math.abs(v - Xold[i][j]); if (d > maxDelta) maxDelta = d;
    }
    X = Xnew; if (maxDelta < tol) break;
  }
  return X;
}

function findTopNLocalMaxima(
  theta: number[], phi: number[], gamma: number[], stress: number[],
  Nθ = 72, Nφ = 36, Nγ = 36, topN = 10, suppress: [number, number, number] = [2, 2, 2]
) {
  const wrap = (x: number, mod: number) => ((x % mod) + mod) % mod;
  const θw = theta.map((t) => wrap(t, TAU)); const φw = phi.map((p) => wrap(p, TAU)); const γw = gamma.map((g) => wrap(g, TAU));
  const iθ = θw.map((t) => Math.floor((t / TAU) * Nθ) % Nθ);
  const iφ = φw.map((p) => Math.floor((p / TAU) * Nφ) % Nφ);
  const iγ = γw.map((g) => Math.floor((g / TAU) * Nγ) % Nγ);
  const M: number[][][] = Array.from({ length: Nθ }, () => Array.from({ length: Nφ }, () => Array(Nγ).fill(-Infinity)));
  const I: number[][][] = Array.from({ length: Nθ }, () => Array.from({ length: Nφ }, () => Array(Nγ).fill(-1)));
  for (let idx = 0; idx < stress.length; idx++) { const ii = iθ[idx], jj = iφ[idx], kk = iγ[idx]; const v = stress[idx]; if (v > M[ii][jj][kk]) { M[ii][jj][kk] = v; I[ii][jj][kk] = idx; } }
  const cand: boolean[][][] = Array.from({ length: Nθ }, () => Array.from({ length: Nφ }, () => Array(Nγ).fill(true)));
  const roll = (arr: number[][][], di: number, dj: number, dk: number) => {
    const out = Array.from({ length: Nθ }, () => Array.from({ length: Nφ }, () => Array(Nγ).fill(-Infinity)));
    for (let i = 0; i < Nθ; i++) for (let j = 0; j < Nφ; j++) for (let k = 0; k < Nγ; k++) {
      const ii = (i + di + Nθ) % Nθ; const jj = (j + dj + Nφ) % Nφ; const kk = (k + dk + Nγ) % Nγ; out[i][j][k] = M[ii][jj][kk];
    }
    return out;
  };
  for (let di = -1; di <= 1; di++) for (let dj = -1; dj <= 1; dj++) for (let dk = -1; dk <= 1; dk++) {
    if (di === 0 && dj === 0 && dk === 0) continue; const neigh = roll(M, di, dj, dk);
    for (let i = 0; i < Nθ; i++) for (let j = 0; j < Nφ; j++) for (let k = 0; k < Nγ; k++) { cand[i][j][k] &&= M[i][j][k] >= neigh[i][j][k]; }
  }
  type P = { i: number; j: number; k: number; val: number; idx: number };
  const list: P[] = []; for (let i = 0; i < Nθ; i++) for (let j = 0; j < Nφ; j++) for (let k = 0; k < Nγ; k++) {
    if (cand[i][j][k] && Number.isFinite(M[i][j][k]) && I[i][j][k] >= 0) list.push({ i, j, k, val: M[i][j][k], idx: I[i][j][k] });
  }
  list.sort((a, b) => b.val - a.val);
  const sel: P[] = []; const [rθ, rφ, rγ] = suppress; const torusDist = (a: number, b: number, n: number) => Math.min(Math.abs(a - b), n - Math.abs(a - b));
  for (const p of list) {
    let ok = true; for (const q of sel) { const dθ = torusDist(p.i, q.i, Nθ); const dφ = torusDist(p.j, q.j, Nφ); const dγ = torusDist(p.k, q.k, Nγ); if (dθ <= rθ && dφ <= rφ && dγ <= rγ) { ok = false; break; } }
    if (ok) { sel.push(p); if (sel.length >= topN) break; }
  }
  return sel.map((p, rank) => { const idx = p.idx; const [nx, ny, nz] = eulerZYXtoDir(θw[idx], φw[idx], γw[idx], [0, 0, 1]); const [lon, lat] = dirToLonLat(nx, ny, nz); return { rank: rank + 1, value: p.val, idx, lon, lat }; });
}


function polylinePathXY(pts: [number, number][]) {
  if (!pts.length) return "";
  const head = `M ${pts[0][0]} ${pts[0][1]}`;
  const tail = pts.slice(1).map(([x, y]) => `L ${x} ${y}`).join(" ");
  return `${head} ${tail}`;
}


function splitWrappedPolyline(
  pts: [number, number][],
  jumpThreshold = 2.5 // 몰바이데 반폭(~2.828)보다 조금 작게
): [number, number][][] {
  const segs: [number, number][][] = [];
  let cur: [number, number][] = [];
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i];
    if (!cur.length) { cur.push(p); continue; }
    const prev = cur[cur.length - 1];
    const dx = Math.abs(p[0] - prev[0]);
    if (dx > jumpThreshold) {
      if (cur.length >= 2) segs.push(cur);
      cur = [p];
    } else {
      cur.push(p);
    }
  }
  if (cur.length >= 2) segs.push(cur);
  return segs;
}



function graticuleShapes(lon0Deg: number, spacingDeg = 30, density = 241) {
  const lon0 = deg2rad(lon0Deg);
  const shapes: any[] = [];

  // ── 경도선: lon 고정, lat를 -90..90 사이 "중간점"으로만 샘플
  for (let lonDeg = -180 + spacingDeg; lonDeg <= 180 - spacingDeg; lonDeg += spacingDeg) {
    const raw: [number, number][] = [];
    for (let i = 0; i < density; i++) {
      const latDeg = -90 + (180 * (i + 0.5)) / density; // ★ 극(±90°) 회피
      const [x, y] = mollweideForward(deg2rad(lonDeg), deg2rad(latDeg), lon0);
      raw.push([x, y]);
    }
    for (const seg of splitWrappedPolyline(raw)) {
      shapes.push({
        type: "path",
        xref: "x", yref: "y",
        path: polylinePathXY(seg),
        line: { width: 0.8, color: "rgba(0,0,0,0.35)" },
        layer: "above",
      });
    }
  }

  // ── 위도선: 기존 그대로 (이미 극 자체를 그리지 않음)
  for (let latDeg = -90 + spacingDeg; latDeg <= 90 - spacingDeg; latDeg += spacingDeg) {
    const raw: [number, number][] = [];
    for (let i = 0; i < density; i++) {
      const lonDeg = -180 + (360 * i) / (density - 1);
      const [x, y] = mollweideForward(deg2rad(lonDeg), deg2rad(latDeg), lon0);
      raw.push([x, y]);
    }
    for (const seg of splitWrappedPolyline(raw)) {
      shapes.push({
        type: "path",
        xref: "x", yref: "y",
        path: polylinePathXY(seg),
        line: { width: 0.6, color: "rgba(0,0,0,0.25)" },
        layer: "above",
      });
    }
  }

  return shapes;
}


function computePack(rows: SampleRow[], opt: ComputeOptions): PlotDataPack | null {
  if (rows.length === 0) return null;

  const toRad = (v: number) => (opt.degInput ? deg2rad(v) : v);
  const theta = rows.map(r => toRad(r.theta));
  const phi   = rows.map(r => toRad(r.phi));
  const gamma = rows.map(r => toRad(r.gamma));
  const stress = rows.map(r => r.stress);

  // 방향 → (lon, lat)
  const lon: number[] = [], lat: number[] = [];
  for (let i = 0; i < rows.length; i++) {
    const [nx, ny, nz] = eulerZYXtoDir(theta[i], phi[i], gamma[i], [0, 0, 1]);
    const [L, B] = dirToLonLat(nx, ny, nz);
    lon.push(L); lat.push(B);
  }

  const { mean, max, variance, pex } =
    rasterize(lon, lat, stress, opt.nlat, opt.nlon, undefined);

  const pick = (() => {
    const m = opt.aggKey === "mean" ? mean
            : opt.aggKey === "max"  ? max
            : opt.aggKey === "var"  ? variance
            :                         pex;
    return m.map(row => row.map(v => (Number.isFinite(v) ? v : null)));
  })();

  const inpainted = inpaintPeriodicLon(pick, 300, 1e-3);

  const flat = inpainted.flat().filter(v => v !== null && Number.isFinite(v)) as number[];
  let vmin = opt.vmin, vmax = opt.vmax;
  if (flat.length) {
    const sorted = [...flat].sort((a, b) => a - b);
    const p = (q: number) => sorted[Math.max(0, Math.min(sorted.length - 1, Math.floor(q * (sorted.length - 1))))];
    if (vmin === undefined) vmin = p(0.02);
    if (vmax === undefined) vmax = p(0.98);
  } else { vmin = undefined; vmax = undefined; }

  // 축 좌표 (투영 x/y)
  const xAxis: number[] = [];
  const yAxis: number[] = [];
  const lon0 = deg2rad(opt.lon0Deg);
  for (let j = 0; j < opt.nlon; j++) {
    const lj = ((j + 0.5) / opt.nlon) * TAU;
    const [x] = mollweideForward(lj, 0, lon0);
    xAxis.push(x);
  }
  for (let i = 0; i < opt.nlat; i++) {
    const li = ((i + 0.5) / opt.nlat) * PI - PI / 2;
    const [, y] = mollweideForward(0, li, lon0);
    yAxis.push(y);
  }

  // Top-N 마커
  const peaks = findTopNLocalMaxima(theta, phi, gamma, stress, 72, 36, 36, opt.topN, opt.suppress);
  const markers = peaks.map(p => {
    const [x, y] = mollweideForward(p.lon, p.lat, lon0);
    return { x, y, label: String(p.rank) };
  });

  // ✅ 각 셀 중심의 lon/lat(°) (호버용)
  const lonlatDeg: [number, number][][] = Array.from({ length: opt.nlat }, (_, i) =>
    Array.from({ length: opt.nlon }, (_, j) => {
      const lonDeg = (((j + 0.5) / opt.nlon) * 360 - 180 + opt.lon0Deg + 540) % 360 - 180;
      const latDeg = ((i + 0.5) / opt.nlat) * 180 - 90;
      return [lonDeg, latDeg];
    })
  );

  // ✅ 축 눈금 (경도/위도) – lon0는 mollweideForward의 세 번째 인자로 이미 반영됨
  const xTicksDeg = [-150,-120,-90,-60,-30,0,30,60,90,120,150];
  const xTickVals: number[] = [];
  const xTickText: string[] = [];
  for (const d of xTicksDeg) {
    // ⛔️ d + opt.lon0Deg (이중 보정) 금지!
    const [xTick] = mollweideForward(deg2rad(d), 0, lon0);
    xTickVals.push(xTick);
    xTickText.push(`${d}°`);
  }

  const yTicksDeg = [-90,-60,-30,0,30,60,90];
  const yTickVals: number[] = [];
  const yTickText: string[] = [];
  for (const b of yTicksDeg) {
    if (Math.abs(b) === 90) {
      yTickVals.push(Math.sign(b) * SQ2);  // y=±√2
    } else {
      const [, yTick] = mollweideForward(0, deg2rad(b), lon0);
      yTickVals.push(yTick);
    }
    yTickText.push(`${b}°`);
  }
  

  // ✅ 타원 마스크: 경계 밖은 null 처리
  const a = 2 * SQ2;
  const b = SQ2;
  const maskedZ: (number | null)[][] = inpainted.map((row, i) =>
    row.map((v, j) => {
      const x = xAxis[j];
      const y = yAxis[i];
      const inside = (x * x) / (a * a) + (y * y) / (b * b) <= 1 + 1e-12;
      return inside ? v : null;
    })
  );

  // ✅ 마커도 경계 내부만 남김
  const maskedMarkers = markers.filter(m => {
    const inside = (m.x * m.x) / (a * a) + (m.y * m.y) / (b * b) <= 1 + 1e-12;
    return inside;
  });

  return {
    z: maskedZ,
    x: xAxis,
    y: yAxis,
    markers: maskedMarkers,
    vmin, vmax,
    lonlatDeg,
    xTickVals, xTickText,
    yTickVals, yTickText,
  };
}


function mollweideBoundaryPath() {
  const pts: [number, number][] = []; for (let i = 0; i <= 360; i++) { const t = (i / 360) * TAU; const x = 2 * SQ2 * Math.cos(t); const y = SQ2 * Math.sin(t); pts.push([x, y]); }
  const d = ["M", pts[0][0], pts[0][1], ...pts.slice(1).flatMap(([x, y]) => ["L", x, y]), "Z"].join(" ");
  return d;
}

function Code({ children }: { children: React.ReactNode }) { return <code style={{ background: "#f6f8fa", padding: "0 4px", borderRadius: 4 }}>{children}</code>; }
function EmptyHint() { return (<div className="flex flex-col items-center justify-center py-16"><Title level={5} style={{ marginBottom: 8 }}>No data loaded</Title><Text type="secondary">Upload a CSV or pass data via props to render the Mollweide stress map.</Text></div>); }

// ---------------------- Main Component ----------------------
const DEFAULT_COLORSCALES = ["Turbo", "Viridis", "Plasma", "Jet", "Cividis", "Inferno", "Magma", "IceFire", "Portland"] as const;

type CompareMode = "Tabs" | "Grid";

export default function MollweideStressPlot(props: ExecuteLikeOptions = {}) {
  // Programmatic defaults
  const initDeg = props.deg ?? true;
  const initNlat = props.nlat ?? 50;
  const initNlon = props.nlon ?? 100;
  const initLevels = props.levels ?? 64;
  const initTopN = props.topN ?? 10;
  const initSuppress: [number, number, number] = props.suppress ?? [2, 2, 2];
  const initLon0 = props.lon0 ?? 0;
  const initColorscale = props.colorscale ?? "Jet";
  const initReverse = props.reverse ?? false;

  const [rows, setRows] = useState<SampleRow[]>(props.data ?? []);
  const [degInput, setDegInput] = useState(initDeg);
  const [nlat, setNlat] = useState(initNlat);
  const [nlon, setNlon] = useState(initNlon);
  const [levels, setLevels] = useState(initLevels);
  const [vmin, setVmin] = useState<number | undefined>(props.vmin);
  const [vmax, setVmax] = useState<number | undefined>(props.vmax);
  const [lon0Deg, setLon0Deg] = useState(initLon0);
  const [topN, setTopN] = useState(initTopN);
  const [suppress, setSuppress] = useState<[number, number, number]>(initSuppress);
  const [colorscale, setColorscale] = useState<string>(initColorscale);
  const [reverse, setReverse] = useState(initReverse);
  const [compareMode, setCompareMode] = useState<CompareMode>("Tabs");
  const [tabAgg, setTabAgg] = useState<AggKey>("mean");
  const [showControlPanel, setShowControlPanel] = useState(false);

  // Load csvText if provided programmatically
  useEffect(() => {
    if (props.csvText && !rows.length) {
      Papa.parse(props.csvText, { header: true, dynamicTyping: true, skipEmptyLines: true, complete: (res) => {
        const parsed: SampleRow[] = [];
        for (const r of res.data as any[]) {
          if (r.theta == null || r.phi == null || r.gamma == null || r.stress == null) continue;
          const t = Number(r.theta), p = Number(r.phi), g = Number(r.gamma), s = Number(r.stress);
          if (Number.isFinite(t) && Number.isFinite(p) && Number.isFinite(g) && Number.isFinite(s)) parsed.push({ theta: t, phi: p, gamma: g, stress: s });
        }
        if (parsed.length) setRows(parsed);
      }});
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.csvText]);

  // Compute per-agg packs (for Grid compare efficiency)
  const commonOptBase = useMemo(() => ({ nlat, nlon, vmin, vmax, lon0Deg, levels, degInput, topN, suppress }), [nlat, nlon, vmin, vmax, lon0Deg, levels, degInput, topN, suppress]);
  const packByAgg = useMemo(() => {
    const map = new Map<AggKey, PlotDataPack | null>();
    (['mean','max','var','pexceed'] as AggKey[]).forEach((agg) => {
      map.set(agg, computePack(rows, { ...commonOptBase, aggKey: agg }));
    });
    return map;
  }, [rows, commonOptBase]);

  // Upload handler
  const onUpload = (file: File) => {
    Papa.parse(file, { header: true, dynamicTyping: true, skipEmptyLines: true, complete: (res) => {
      try {
        const data = res.data as any[]; const parsed: SampleRow[] = [];
        for (const r of data) {
          if (r.theta == null || r.phi == null || r.gamma == null || r.stress == null) continue;
          const t = Number(r.theta), p = Number(r.phi), g = Number(r.gamma), s = Number(r.stress);
          if (Number.isFinite(t) && Number.isFinite(p) && Number.isFinite(g) && Number.isFinite(s)) parsed.push({ theta: t, phi: p, gamma: g, stress: s });
        }
        if (!parsed.length) throw new Error("No valid rows found."); setRows(parsed); message.success(`Loaded ${parsed.length} rows.`);
      } catch (e) { console.error(e); message.error("Parse failed. Expect columns: theta, phi, gamma, stress"); }
    }, error: () => message.error("CSV parse failed") });
    return false;
  };

  const downloadCSV = () => {
    if (!rows.length) return; const header = "theta,phi,gamma,stress"; const body = rows.map(r => `${r.theta},${r.phi},${r.gamma},${r.stress}`).join("\n");
    const blob = new Blob([header + body], { type: "text/csv;charset=utf-8;" }); const url = URL.createObjectURL(blob); const a = document.createElement("a"); a.href = url; a.download = "angles_stress.csv"; a.click(); URL.revokeObjectURL(url);
  };
  const resetRanges = () => { setVmin(undefined); setVmax(undefined); };

  // Export PNG (current view or all grid panels)
  const plotRefs = useRef<Record<string, any>>({});
  const exportPNG = async (key: string, filename: string) => {
    const ref = plotRefs.current[key]; if (!ref) { message.warning("Plot is not ready"); return; }
    try {
      const url = await Plotly.toImage(ref.el, { format: "png", width: ref.el.offsetWidth, height: ref.el.offsetHeight, scale: 2 });
      const a = document.createElement("a"); a.href = url; a.download = filename; a.click();
    } catch (e) { console.error(e); message.error("Export failed"); }
  };
  const exportAllGrid = async () => {
    const keys: AggKey[] = ["mean","max","var","pexceed"]; for (const k of keys) { await exportPNG(k, `mollweide_${k}.png`); }
  };

  const controlPanel = (
    <Form layout="vertical">
      <Form.Item label="Angles in degrees"><Switch checked={degInput} onChange={setDegInput} /></Form.Item>
      <Row gutter={12}>
        <Col span={12}><Form.Item label="Lat bins (Nlat)"><InputNumber min={2} max={720} value={nlat} onChange={(v)=>setNlat(v||50)} /></Form.Item></Col>
        <Col span={12}><Form.Item label="Lon bins (Nlon)"><InputNumber min={2} max={1440} value={nlon} onChange={(v)=>setNlon(v||100)} /></Form.Item></Col>
      </Row>
      <Form.Item label={<Space>Levels <Tooltip title="Info: kept for parity; Plotly is continuous."><Text type="secondary">(info)</Text></Tooltip></Space>}>
        <Slider min={8} max={256} step={1} value={levels} onChange={setLevels} />
      </Form.Item>
      <Row gutter={12}>
        <Col span={12}><Form.Item label="vmin"><InputNumber value={vmin} onChange={(v)=>setVmin(v||undefined)} placeholder="auto" /></Form.Item></Col>
        <Col span={12}><Form.Item label="vmax"><InputNumber value={vmax} onChange={(v)=>setVmax(v||undefined)} placeholder="auto" /></Form.Item></Col>
      </Row>
      <Button size="small" onClick={resetRanges} style={{ marginBottom: 12 }}>Auto range</Button>
      <Row gutter={12}>
        <Col span={12}><Form.Item label="Central meridian (°)"><InputNumber value={lon0Deg} onChange={(v)=>setLon0Deg(v||0)} /></Form.Item></Col>
        <Col span={12}><Form.Item label="Top‑N peaks"><InputNumber min={0} max={50} value={topN} onChange={(v)=>setTopN(v||0)} /></Form.Item></Col>
      </Row>
      <Row gutter={12}>
        <Col span={8}><Form.Item label="NMS rθ"><InputNumber min={0} max={20} value={suppress[0]} onChange={(v)=>setSuppress([v||0, suppress[1], suppress[2]])} /></Form.Item></Col>
        <Col span={8}><Form.Item label="NMS rφ"><InputNumber min={0} max={20} value={suppress[1]} onChange={(v)=>setSuppress([suppress[0], v||0, suppress[2]])} /></Form.Item></Col>
        <Col span={8}><Form.Item label="NMS rγ"><InputNumber min={0} max={20} value={suppress[2]} onChange={(v)=>setSuppress([suppress[0], suppress[1], v||0])} /></Form.Item></Col>
      </Row>
      <Row gutter={12}>
        <Col span={14}><Form.Item label="Colorscale"><Select value={colorscale} onChange={setColorscale} options={DEFAULT_COLORSCALES.map(c=>({value:c,label:c}))} /></Form.Item></Col>
        <Col span={10}><Form.Item label="Reverse"><Switch checked={reverse} onChange={setReverse} /></Form.Item></Col>
      </Row>
    </Form>
  );

  const headerActions = (
    <Space wrap>
      <Segmented
        options={[{ label: "Tabs", value: "Tabs", icon: <ColumnHeightOutlined /> }, { label: "Grid", value: "Grid", icon: <AppstoreOutlined /> }]}
        value={compareMode}
        onChange={(v) => setCompareMode(v as CompareMode)}
      />
      <Button icon={<DownloadOutlined />} disabled={!rows.length} onClick={downloadCSV}>CSV</Button>
      {compareMode === "Tabs" ? (
        <Button icon={<CameraOutlined />} onClick={() => exportPNG(tabAgg, `mollweide_${tabAgg}.png`)}>Export PNG</Button>
      ) : (
        <Button icon={<CameraOutlined />} onClick={exportAllGrid}>Export PNG (all)</Button>
      )}
      <Button icon={<RedoOutlined />} onClick={() => setRows([])}>Clear</Button>
      {rows.length ? <Tag color="blue">rows: {rows.length}</Tag> : null}
    </Space>
  );




  
  return (
    <div className="p-6">      
      <Card className="shadow-lg rounded-2xl">
        <Row gutter={[24, 24]}>
          <Col>
            <Title level={4} style={{ marginTop: 0 }}>Mollweide Stress Map</Title>
            <Text type="secondary">CSV columns <Code>theta</Code>, <Code>phi</Code>, <Code>gamma</Code>, <Code>stress</Code>. You can also inject <Code>data</Code> or <Code>csvText</Code> via props.</Text>
          </Col>
        </Row>
        <Divider />
        <Row gutter={[24, 24]}>
          <Col xs={24} lg={24} xl={24}>            
          <Dragger
            beforeUpload={onUpload}
            multiple={false}
            showUploadList={false}
            style={{ padding: "12px 0", maxHeight: "150px" }} // 높이 줄이기
          >
            <p className="ant-upload-drag-icon"><InboxOutlined /></p>
            <p className="ant-upload-text">Click or drag CSV file here</p>
            <p className="ant-upload-hint">Angles in degrees by default (toggle below for radians)</p>
          </Dragger>
          
          
          
          </Col>          
        </Row>
        <Divider />
        <Row gutter={[24, 24]} align="top">          

          <Col xs={24} lg={24} xl={24}>
            <Card className="rounded-2xl" title={headerActions} bodyStyle={{ padding: 12 }}>
              {!rows.length ? (
                <EmptyHint />
              ) : compareMode === "Tabs" ? (
                <Tabs activeKey={tabAgg} onChange={(k) => setTabAgg(k as AggKey)} items={(['mean','max','var','pexceed'] as AggKey[]).map((key) => ({
                  key,
                  label: key.toUpperCase(),
                  children: <OnePlot agg={key} pack={packByAgg.get(key) || null} colorscaleFinal={colorscale} plotRefs={plotRefs} lon0Deg={lon0Deg} />
                }))} />
              ) : (
                <Row gutter={[12, 12]}>
                  {(['mean','max','var','pexceed'] as AggKey[]).map((key) => (
                    <Col xs={24} md={12} key={key}>
                      <Card size="small" title={key.toUpperCase()} bodyStyle={{ padding: 6 }}>
                        <OnePlot agg={key} pack={packByAgg.get(key) || null} colorscaleFinal={colorscale} plotRefs={plotRefs} height={360} lon0Deg={lon0Deg} />
                      </Card>
                    </Col>
                  ))}
                </Row>
              )}
            </Card>
          </Col>
        </Row>
      </Card>
      <Divider />
      <Button onClick={() => setShowControlPanel(!showControlPanel)}>
        {showControlPanel ? "Hide Control Panel" : "Show Control Panel"}
      </Button>
      {showControlPanel && controlPanel}
    </div>
  );
}

function OnePlot({
  agg, pack, colorscaleFinal, plotRefs, height = 600, lon0Deg = 0
}: {
  agg: AggKey;
  pack: PlotDataPack | null;
  colorscaleFinal: string;
  plotRefs: React.MutableRefObject<Record<string, any>>;
  height?: number;
  lon0Deg?: number;
}) {
  if (!pack) return <EmptyHint />;

  return (
    <Plot
      onInitialized={(fig, graphDiv) => { plotRefs.current[agg] = { fig, el: graphDiv }; }}
      onUpdate={(fig, graphDiv) => { plotRefs.current[agg] = { fig, el: graphDiv }; }}
      data={[
        {
          type: "heatmap",
          z: pack.z,
          x: pack.x,
          y: pack.y,
          colorscale: colorscaleFinal,
          // reversescale: reverse, // ← reverse 쓰면 prop 내려와서 연결
          zmin: pack.vmin,
          zmax: pack.vmax,
          zauto: pack.vmin === undefined || pack.vmax === undefined,
          hoverongaps: false,
          showscale: true,
          colorbar: { title: { text: "Stress" } },
          customdata: pack.lonlatDeg,               // ✅ 각 셀의 [lon°, lat°]
          hovertemplate:
            "lon=%{customdata[0]:.1f}°, lat=%{customdata[1]:.1f}°<br>value=%{z:.3f}<extra></extra>",
        } as any,
        {
          type: "scatter",
          mode: "markers+text",
          x: pack.markers.map(m => m.x),
          y: pack.markers.map(m => m.y),
          text: pack.markers.map(m => m.label),
          textposition: "middle right",
          marker: { symbol: "star", size: 10 },
          hoverinfo: "text",
          name: "Top-N",
        } as any,
      ]}
      layout={{
        autosize: true,
        margin: { l: 10, r: 10, t: 10, b: 10 },
        // ✅ 축을 보이게 하고 눈금 넣기
        xaxis: {
          showgrid: false,
          zeroline: false,
          visible: true,
          tickmode: "array",
          tickvals: pack.xTickVals,
          ticktext: pack.xTickText,
        },
        yaxis: {
          showgrid: false,
          zeroline: false,
          visible: true,
          scaleanchor: "x",
          scaleratio: 1,
          tickmode: "array",
          tickvals: pack.yTickVals,
          ticktext: pack.yTickText,
        },
        shapes: [
          ...graticuleShapes(lon0Deg, 30, 241), // ✅ 경위선

          {                                      // ✅ 외곽 타원
            type: "path",
            xref: "x", yref: "y",
            path: mollweideBoundaryPath(),
            line: { width: 1.1, color: "rgba(0,0,0,0.45)" },
            layer: "above",
          },
        ],
      }}
      style={{ width: "100%", height }}
      config={{ displayModeBar: true, responsive: true }}
    />
  );
}
