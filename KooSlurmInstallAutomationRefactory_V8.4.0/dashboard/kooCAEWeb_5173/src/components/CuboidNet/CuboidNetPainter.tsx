import React, { useCallback, useEffect, useMemo, useRef, useState, forwardRef, useImperativeHandle } from "react";
import { Button, Card, Col, Divider, InputNumber, List, Row, Select, Slider, Space, Tag, Tooltip, Typography } from "antd";
import MiniCubePreview from "./MiniCubePreview";
import NetCanvas from "./NetCanvas";
import FaceLegend from "./FaceLegend";
import {
  Face,
  FacePattern,
  FacePatternMap,
  Mode,
  NetPreset,
  PatternKind,
  PatternOp,
  PatternFill,
  PRESETS
} from "./types";
import { buildLayout, faceSizeMM } from "./utils/layout";
import { drawPatternOnFace } from "./utils/patterns";

const { Text } = Typography;


// ✅ 새로 추가: 부모로 전달할 파일 맵 타입
export type FaceFileMap = {
  box_px: File; box_mx: File;
  box_py: File; box_my: File;
  box_pz: File; box_mz: File;
};

// ✅ 새로 추가: Face → 파일 키 매핑
const FACE_TO_KEY: Record<Face, keyof FaceFileMap> = {
  "+X": "box_px",
  "-X": "box_mx",
  "+Y": "box_py",
  "-Y": "box_my",
  "+Z": "box_pz",
  "-Z": "box_mz",
};


export type CuboidNetPainterHandle = {
  exportFaces: () => Promise<FaceFileMap>;
};


type Props = {
  onExportFaces?: (images: FaceFileMap) => void;
};

function CuboidNetPainterImpl(
  { onExportFaces }: Props,
  ref: React.Ref<CuboidNetPainterHandle> // ← ref 받기
) {
  // Geometry
  const [xMM, setXMM] = useState(60);
  const [yMM, setYMM] = useState(150);
  const [zMM, setZMM] = useState(8);
  const [ppmm, setPPMM] = useState(4);
  const [marginPx, setMarginPx] = useState(24);

  // Preset
  const [preset, setPreset] = useState<NetPreset>("Vertical Cross 3×4");

  // Mode / brush
  const [mode, setMode] = useState<Mode>("paint");
  const [brushMM, setBrushMM] = useState(4);

  // Pattern UI state
  const [patterns, setPatterns] = useState<FacePatternMap>({});
  const [patternKind, setPatternKind] = useState<PatternKind>("diagWrapX"); // default
  const [patternOp, setPatternOp] = useState<PatternOp>("paint");
  const [patternFill, setPatternFill] = useState<PatternFill>("inside");
  const [selectedFaces, setSelectedFaces] = useState<Face[]>(["+X"]);
  const [lineMM, setLineMM] = useState(2);
  const [bandMM, setBandMM] = useState(8);
  const [borderMM, setBorderMM] = useState(3);
  const [padMM, setPadMM] = useState(6);
  const [gapMM, setGapMM] = useState(2);
  const [cornerMM, setCornerMM] = useState(12);

  // wrap shortcuts
  const WRAP_Y: Face[] = ["+X","-X","+Z","-Z"];
  const WRAP_X: Face[] = ["+Z","-Z","+Y","-Y"];
  const WRAP_Z: Face[] = ["+X","-X","+Y","-Y"];

  // view
  const [zoom, setZoom] = useState<"fit" | number>("fit");
  const [highlightFace, setHighlightFace] = useState<Face | null>(null);

  // Derived layout
  const grid = useMemo(() => PRESETS[preset], [preset]);
  const layout = useMemo(
    () => buildLayout(xMM, yMM, zMM, ppmm, marginPx, grid),
    [xMM, yMM, zMM, ppmm, marginPx, grid]
  );

  // Mask & Pattern canvases
  const maskCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const patternCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const imageDataRef = useRef<ImageData | null>(null);
  const [version, setVersion] = useState(0);
  const bump = useCallback(() => setVersion(v => v + 1), []);

  // Patterns repaint (layered)
  const repaintPatterns = useCallback(() => {
    const p = patternCanvasRef.current; if (!p) return;
    const ctx = p.getContext("2d")!;
    ctx.clearRect(0, 0, p.width, p.height);

    (Object.keys(layout.faceRects) as Face[]).forEach(face => {
      const specs = patterns[face];
      if (!specs || specs.length === 0) return;
      const r = layout.faceRects[face];
      specs.forEach((spec: FacePattern) => {
        const params: Record<string, number> = {
          lineMM, bandMM, borderMM, padMM, gapMM, cornerMM,
          ...(spec.params || {})
        };
        const op = spec.op ?? "paint";
        const fill = spec.fill ?? "inside";
        drawPatternOnFace(ctx, r, spec.kind, params, ppmm, op, fill);
      });
    });
  }, [layout.faceRects, patterns, ppmm, lineMM, bandMM, borderMM, padMM, gapMM, cornerMM]);


  async function exportFacePNGsToParent() {
    const files = await exportFaces();        // 내부 공통 메서드 호출
    onExportFaces?.(files);                   // 콜백 알림
  }
  
  // Recreate backings on layout change
  useEffect(() => {
    // mask
    const m = document.createElement("canvas");
    m.width = layout.atlasW; m.height = layout.atlasH;
    maskCanvasRef.current = m;
    const mctx = m.getContext("2d")!;
    imageDataRef.current = mctx.createImageData(layout.atlasW, layout.atlasH);
    const d = imageDataRef.current.data;
    for (let i = 0; i < d.length; i += 4) { d[i] = d[i+1] = d[i+2] = d[i+3] = 0; }

    // pattern
    const p = document.createElement("canvas");
    p.width = layout.atlasW; p.height = layout.atlasH;
    patternCanvasRef.current = p;

    repaintPatterns();
    bump();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [layout]);

  // Redraw patterns when state changes
  useEffect(() => { repaintPatterns(); bump(); }, [repaintPatterns]);

  // UI helpers
  function onFaceClick(face: Face) {
    setHighlightFace(face);
    setSelectedFaces([face]);
  }

  // ---------- 패턴 추가/삭제 로직 (id 기반) ----------
  function newPatternId(prefix = "p") {
    return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2,7)}`;
  }

  function applyPatternToSelectedFaces() {
    setPatterns(prev => {
      const next: FacePatternMap = { ...prev };
      selectedFaces.forEach(f => {
        const id = newPatternId(f);
        const spec: FacePattern = {
          id,
          kind: patternKind,
          params: { lineMM, bandMM, borderMM, padMM, gapMM, cornerMM },
          op: patternOp,
          fill: patternFill
        };
        const arr = next[f] ? [...next[f]!] : [];
        arr.push(spec);
        next[f] = arr;
      });
      return next;
    });
  }

  function clearPatternFromSelectedFaces() {
    setPatterns(prev => {
      const next: FacePatternMap = { ...prev };
      selectedFaces.forEach(f => { delete next[f]; });
      return next;
    });
  }

  function clearAllPatterns() { setPatterns({}); }

  function addWrapAround(axis: "X" | "Y" | "Z") {
    const faces = axis === "Y" ? WRAP_Y : axis === "X" ? WRAP_X : WRAP_Z;
    setPatterns(prev => {
      const next: FacePatternMap = { ...prev };
      faces.forEach(f => {
        const id = newPatternId(`wrap_${f}`);
        const spec: FacePattern = {
          id,
          kind: patternKind,
          params: { lineMM, bandMM, borderMM, padMM, gapMM, cornerMM },
          op: patternOp,
          fill: patternFill
        };
        const arr = next[f] ? [...next[f]!] : [];
        arr.push(spec);
        next[f] = arr;
      });
      return next;
    });
    setSelectedFaces(faces);
    setHighlightFace(null);
  }

  // 개별 id 삭제
  function removePatternById(targetId: string) {
    setPatterns(prev => {
      const next: FacePatternMap = {};
      (Object.keys(prev) as Face[]).forEach(face => {
        const arr = prev[face];
        if (!arr) return;
        const filtered = arr.filter(p => p.id !== targetId);
        if (filtered.length > 0) next[face] = filtered;
      });
      return next;
    });
  }

  // 리스트 표시용 플래튼 데이터
  const flatPatternList = useMemo(() => {
    const items: { id: string; face: Face; spec: FacePattern }[] = [];
    (Object.keys(patterns) as Face[]).forEach(face => {
      (patterns[face] || []).forEach(spec => {
        if (!spec.id) return;
        items.push({ id: spec.id, face, spec });
      });
    });
    // 최신 추가가 위로 보이게 정렬
    return items.sort((a, b) => (a.id > b.id ? -1 : 1));
  }, [patterns]);

  // Exports
  function downloadPNG() {
    const m = maskCanvasRef.current; const p = patternCanvasRef.current;
    if (!m && !p) return;
    const exp = document.createElement("canvas");
    exp.width = layout.atlasW; exp.height = layout.atlasH;
    const ectx = exp.getContext("2d")!;
    ectx.fillStyle = "#000"; ectx.fillRect(0,0,exp.width,exp.height);
    if (p) ectx.drawImage(p, 0, 0);
    if (m) ectx.drawImage(m, 0, 0);
    const a = document.createElement("a");
    a.href = exp.toDataURL("image/png");
    a.download = `cuboid_net_${xMM}x${yMM}x${zMM}_pp${ppmm}.png`;
    a.click();
  }

  function downloadJSON() {
    const meta = {
      xMM, yMM, zMM, ppmm, marginPx,
      layout: {
        atlasW: layout.atlasW,
        atlasH: layout.atlasH,
        faceRects: layout.faceRects,
        cellRects: layout.cellRects,
        grid: layout.grid,
      },
      faceMM: {
        "+X": faceSizeMM("+X", xMM, yMM, zMM),
        "-X": faceSizeMM("-X", xMM, yMM, zMM),
        "+Y": faceSizeMM("+Y", xMM, yMM, zMM),
        "-Y": faceSizeMM("-Y", xMM, yMM, zMM),
        "+Z": faceSizeMM("+Z", xMM, yMM, zMM),
        "-Z": faceSizeMM("-Z", xMM, yMM, zMM),
      },
      patterns
    };
    const blob = new Blob([JSON.stringify(meta, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = "cuboid_net_meta.json"; a.click();
    URL.revokeObjectURL(url);
  }

  // Brush clear/fill
  function clearBrush(val: number = 0) {
    const m = maskCanvasRef.current; const img = imageDataRef.current; if (!m || !img) return;
    const d = img.data;
    if (val === 0) for (let i = 0; i < d.length; i += 4) { d[i]=d[i+1]=d[i+2]=d[i+3]=0; }
    else for (let i = 0; i < d.length; i += 4) { d[i]=d[i+1]=d[i+2]=255; d[i+3]=255; }
    m.getContext("2d")!.putImageData(img, 0, 0);
    bump();
  }

  function setZoomFit() { setZoom("fit"); }
  function setZoomPct(p: number) { setZoom(Math.max(0.1, p / 100)); }


// ✅ 새로 추가: 캔버스를 PNG File로 변환
function canvasToFile(canvas: HTMLCanvasElement, name: string): Promise<File> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) return reject(new Error("toBlob failed"));
      resolve(new File([blob], name, { type: "image/png" }));
    }, "image/png");
  });
}
 // ✅ 새로 추가: 현재 아틀라스를 합성(검정 배경 + pattern + mask)
 function composeAtlas(): HTMLCanvasElement | null {
  const m = maskCanvasRef.current; const p = patternCanvasRef.current;
  if (!m && !p) return null;
  const atlas = document.createElement("canvas");
  atlas.width = layout.atlasW; atlas.height = layout.atlasH;
  const ctx = atlas.getContext("2d")!;
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, atlas.width, atlas.height);
  if (p) ctx.drawImage(p, 0, 0);
  if (m) ctx.drawImage(m, 0, 0);
  return atlas;
}

 // ✅ 공통 메서드: FaceFileMap을 만들어 반환 (부모 호출용)
 async function exportFaces(): Promise<FaceFileMap> {
  const atlas = composeAtlas();
  if (!atlas) throw new Error("atlas unavailable");

  const results: Partial<FaceFileMap> = {};
  const faces: Face[] = ["+X","-X","+Y","-Y","+Z","-Z"];
  for (const face of faces) {
    const key = FACE_TO_KEY[face];
    const r = layout.faceRects[face];
    const crop = document.createElement("canvas");
    crop.width = Math.max(1, Math.round(r.w));
    crop.height = Math.max(1, Math.round(r.h));
    const cctx = crop.getContext("2d")!;
    cctx.drawImage(
      atlas,
      Math.round(r.x), Math.round(r.y), Math.round(r.w), Math.round(r.h),
      0, 0, crop.width, crop.height
    );
    const file = await canvasToFile(crop, `${key}.png`);
    (results as any)[key] = file;
  }
  return results as FaceFileMap;
}
// ✅ 부모에게 exportFaces 메서드 공개
useImperativeHandle(ref, () => ({
  exportFaces,
}), [
  layout, maskCanvasRef.current, patternCanvasRef.current,
  xMM, yMM, zMM, ppmm, patterns, version
]);

  const footer = `Atlas: ${layout.atlasW}×${layout.atlasH}px  |  Scale: ${ppmm} px/mm  |  View: ${zoom === "fit" ? "Fit" : `${Math.round(Number(zoom)*100)}%`}`;

  return (
    <div style={{ padding: 16, display:"flex", flexDirection:"column", gap:12 }}>
      {/* 상단 컨트롤 */}
      <Card size="small" style={{ borderRadius:12 }}>
        <Row gutter={[12,8]} align="middle">
          <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">X (mm)</Text><InputNumber value={xMM} min={1} style={{ width:"100%" }} onChange={(v)=>setXMM(Number(v))} /></Col>
          <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Y (mm)</Text><InputNumber value={yMM} min={1} style={{ width:"100%" }} onChange={(v)=>setYMM(Number(v))} /></Col>
          <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Z (mm)</Text><InputNumber value={zMM} min={1} style={{ width:"100%" }} onChange={(v)=>setZMM(Number(v))} /></Col>
          <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Scale (px/mm)</Text><InputNumber value={ppmm} min={1} style={{ width:"100%" }} onChange={(v)=>setPPMM(Number(v))} /></Col>

          <Col xs={24} sm={12} md={8} lg={6}><Text type="secondary">Net preset</Text>
            <Select value={preset} style={{ width:"100%" }} onChange={(v)=>setPreset(v as NetPreset)}
              options={(["Compact 3×2","Vertical Cross 3×4","Horizontal Cross 4×3","Strip 6×1"] as NetPreset[]).map(p=>({value:p, label:p}))} />
          </Col>

          <Col xs={12} sm={12} md={8} lg={6}><Text type="secondary">Mode</Text>
            <Select value={mode} style={{ width:"100%" }} onChange={(v)=>setMode(v as Mode)}
              options={[
                {value:"paint", label:"Paint (tape=white)"},
                {value:"erase", label:"Erase (transparent)"},
                {value:"pattern", label:"Pattern painter"},
              ]} />
          </Col>

          {mode !== "pattern" && (
            <Col xs={12} sm={12} md={8} lg={6}>
              <Text type="secondary">Brush (mm)</Text>
              <Slider min={0.5} max={Math.max(20, zMM)} step={0.5} value={brushMM} onChange={(v)=>setBrushMM(Number(v))} />
            </Col>
          )}

          <Col xs={24} md={12} lg={10}><Text type="secondary">View</Text>
            <Space wrap>
              <Button onClick={setZoomFit}>Fit</Button>
              <Button onClick={()=>setZoomPct(100)}>100%</Button>
              <Button onClick={()=>setZoomPct(200)}>200%</Button>
              <Tooltip title="Export mask (pattern + brush)">
                <Button type="primary" onClick={downloadPNG}>Export PNG</Button>
              </Tooltip>
              <Button type="primary" ghost onClick={downloadJSON}>Export JSON</Button>
              <Button onClick={()=>clearBrush(0)} disabled={mode==="pattern"}>Clear</Button>
              <Button onClick={()=>clearBrush(255)} disabled={mode==="pattern"}>Fill</Button>
                            {/* ✅ 새로 추가: 부모로 6면 파일 전달 */}
              <Button onClick={exportFacePNGsToParent} type="dashed">
                Send 6 faces to parent
              </Button>
            </Space>
          </Col>
        </Row>
      </Card>

      {/* 패턴 컨트롤 */}
      {mode === "pattern" && (
        <Card size="small" style={{ borderRadius:12 }}>
          <Row gutter={[12,8]} align="middle">
            <Col xs={24} md={8} lg={6}><Text type="secondary">Faces</Text>
              <Select mode="multiple" value={selectedFaces} style={{ width:"100%" }}
                onChange={(v)=>setSelectedFaces(v as Face[])}
                options={(["+X","-X","+Y","-Y","+Z","-Z"] as Face[]).map(f=>({label:f, value:f}))} />
            </Col>

            <Col xs={24} md={8} lg={6}><Text type="secondary">Pattern</Text>
              <Select value={patternKind} style={{ width:"100%" }} onChange={(v)=>setPatternKind(v as PatternKind)}
                options={[
                  { value: "diagWrapX", label: "Diagonal Wrap (코너 대각 랩)" },
                  { value: "wrap-cross", label: "Wrap Cross (중앙 십자)" },
                  { value: "band-h", label: "Band Horizontal (가로 띠)" },
                  { value: "band-v", label: "Band Vertical (세로 띠)" },
                  { value: "border-only", label: "Border Only (테두리)" },
                  { value: "corner-pads", label: "Corner Pads (코너 패드)" },
                ]} />
            </Col>

            <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Effect</Text>
              <Select value={patternOp} style={{ width:"100%" }} onChange={(v)=>setPatternOp(v as any)}
                options={[
                  { value: "paint", label: "Paint (흰색 칠하기)" },
                  { value: "erase", label: "Erase (투명 만들기)" },
                ]} />
            </Col>

            <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Coverage</Text>
              <Select value={patternFill} style={{ width:"100%" }} onChange={(v)=>setPatternFill(v as any)}
                options={[
                  { value: "inside", label: "Inside (모양 내부)" },
                  { value: "outside", label: "Outside (모양 외부)" },
                ]} />
            </Col>

            <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Line (mm)</Text><InputNumber min={0.5} value={lineMM} onChange={(v)=>setLineMM(Number(v))} style={{ width:"100%" }}/></Col>
            <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Band (mm)</Text><InputNumber min={1} value={bandMM} onChange={(v)=>setBandMM(Number(v))} style={{ width:"100%" }}/></Col>
            <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Border (mm)</Text><InputNumber min={0.5} value={borderMM} onChange={(v)=>setBorderMM(Number(v))} style={{ width:"100%" }}/></Col>
            <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Pad (mm)</Text><InputNumber min={1} value={padMM} onChange={(v)=>setPadMM(Number(v))} style={{ width:"100%" }}/></Col>
            <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Gap (mm)</Text><InputNumber min={0} value={gapMM} onChange={(v)=>setGapMM(Number(v))} style={{ width:"100%" }}/></Col>
            <Col xs={12} sm={8} md={6} lg={4}><Text type="secondary">Corner (mm)</Text><InputNumber min={0} value={cornerMM} onChange={(v)=>setCornerMM(Number(v))} style={{ width:"100%" }}/></Col>

            <Col xs={24}>
              <Space wrap>
                <Button type="primary" onClick={applyPatternToSelectedFaces}>Apply to face(s)</Button>
                <Button onClick={clearPatternFromSelectedFaces}>Clear selected faces</Button>
                <Button danger onClick={clearAllPatterns}>Clear all patterns</Button>
                <Divider type="vertical" />
                <Button onClick={()=>addWrapAround("Y")}>Add wrap around Y</Button>
                <Button onClick={()=>addWrapAround("X")}>Add wrap around X</Button>
                <Button onClick={()=>addWrapAround("Z")}>Add wrap around Z</Button>
              </Space>
            </Col>
          </Row>
        </Card>
      )}

      <Row gutter={12}>
        <Col xs={24} md={18}>
          <Card size="small" style={{ borderRadius:12, height:"70vh" }} bodyStyle={{ padding:8, height:"100%" }}>
            <NetCanvas
              layout={layout}
              ppmm={ppmm}
              mode={mode}
              brushMM={brushMM}
              zoom={zoom}
              maskCanvasRef={maskCanvasRef}
              patternCanvasRef={patternCanvasRef}
              imageDataRef={imageDataRef}
              maskVersion={version}
              highlightFace={highlightFace}
              onFaceClick={onFaceClick}
              footerText={`Atlas: ${layout.atlasW}×${layout.atlasH}px  |  Scale: ${ppmm} px/mm  |  View: ${zoom === "fit" ? "Fit" : `${Math.round(Number(zoom)*100)}%`}`}
              style={{ borderRadius:8, background:"#f0f2f5", border:"1px solid #e5e7eb" }}
              onMaskEdited={() => setVersion(v => v + 1)}
            />
          </Card>
        </Col>

        <Col xs={24} md={6}>
          <Card size="small" title="3D Preview" style={{ borderRadius:12, marginBottom:12 }}>
            <MiniCubePreview
              xMM={xMM} yMM={yMM} zMM={zMM}
              layout={layout}
              getMaskCanvas={()=>maskCanvasRef.current}
              getPatternCanvas={()=>patternCanvasRef.current}
              version={version}
            />
          </Card>

          

          <Card size="small" title="Face Legend" style={{ borderRadius:12 }}>
            <FaceLegend xMM={xMM} yMM={yMM} zMM={zMM} layout={layout} />
          </Card>
        </Col>
        
      </Row>
      <Row>
        {/* ✅ 적용된 패턴 리스트 / 개별 삭제 */}
        <Card size="small" title="Applied Patterns" style={{ borderRadius:12, marginBottom:12 }}>
            <List
              size="small"
              dataSource={flatPatternList}
              locale={{ emptyText: "No patterns yet" }}
              renderItem={({ id, face, spec }) => (
                <List.Item
                  actions={[
                    <Button size="small" danger onClick={() => removePatternById(id)}>Delete</Button>
                  ]}
                >
                  <Space direction="vertical" size={0} style={{ width:"100%" }}>
                    <Space wrap>
                      <Tag>{face}</Tag>
                      <Tag color="blue">{spec.kind}</Tag>
                      <Tag color={spec.op === "erase" ? "default" : "green"}>{spec.op ?? "paint"}</Tag>
                      <Tag color={spec.fill === "outside" ? "purple" : "geekblue"}>{spec.fill ?? "inside"}</Tag>
                    </Space>
                    <Text type="secondary" style={{ fontSize:12 }}>
                      {Object.entries(spec.params || {}).map(([k,v])=>`${k}:${v}`).join("  ")}
                    </Text>
                  </Space>
                </List.Item>
              )}
            />
          </Card>
      </Row>
    </div>
  );
}
export default forwardRef<CuboidNetPainterHandle, Props>(CuboidNetPainterImpl);
