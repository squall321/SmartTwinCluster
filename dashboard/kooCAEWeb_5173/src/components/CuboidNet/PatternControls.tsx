import React from "react";
import { Button, Col, InputNumber, Row, Select, Space } from "antd";
import type { Face, PatternKind } from "./types";

type Props = {
  selectedFaces: Face[];
  setSelectedFaces: (f: Face[]) => void;
  patternKind: PatternKind;
  setPatternKind: (k: PatternKind) => void;
  lineMM: number; setLineMM: (n:number)=>void;
  bandMM: number; setBandMM: (n:number)=>void;
  borderMM: number; setBorderMM: (n:number)=>void;
  padMM: number; setPadMM: (n:number)=>void;
  gapMM: number; setGapMM: (n:number)=>void;
  onApply: () => void;
  onClearSelected: () => void;
  onClearAll: () => void;
  onWrapX: () => void;
  onWrapY: () => void;
  onWrapZ: () => void;
};

const faceOptions = (["+X","-X","+Y","-Y","+Z","-Z"] as Face[]).map(f=>({label:f, value:f}));
const patternOptions = [
  { value: "wrap-cross", label: "Wrap Cross (중앙 십자)" },
  { value: "band-h", label: "Band Horizontal (가로 띠)" },
  { value: "band-v", label: "Band Vertical (세로 띠)" },
  { value: "border-only", label: "Border Only (테두리)" },
  { value: "corner-pads", label: "Corner Pads (코너 패드)" },
] as const;

export default function PatternControls(p: Props){
  return (
    <Row gutter={[12,8]} align="middle">
      <Col xs={24} md={8} lg={6}>
        <small>Faces</small>
        <Select mode="multiple" value={p.selectedFaces} style={{ width:"100%" }} onChange={(v)=>p.setSelectedFaces(v as Face[])} options={faceOptions} />
      </Col>
      <Col xs={24} md={8} lg={6}>
        <small>Pattern</small>
        <Select value={p.patternKind} style={{ width:"100%" }} onChange={(v)=>p.setPatternKind(v as PatternKind)} options={patternOptions as any} />
      </Col>
      <Col xs={12} sm={8} md={6} lg={4}>
        <small>Line (mm)</small>
        <InputNumber min={0.5} value={p.lineMM} onChange={(v)=>p.setLineMM(Number(v))} style={{ width:"100%" }}/>
      </Col>
      <Col xs={12} sm={8} md={6} lg={4}>
        <small>Band (mm)</small>
        <InputNumber min={1} value={p.bandMM} onChange={(v)=>p.setBandMM(Number(v))} style={{ width:"100%" }}/>
      </Col>
      <Col xs={12} sm={8} md={6} lg={4}>
        <small>Border (mm)</small>
        <InputNumber min={0.5} value={p.borderMM} onChange={(v)=>p.setBorderMM(Number(v))} style={{ width:"100%" }}/>
      </Col>
      <Col xs={12} sm={8} md={6} lg={4}>
        <small>Pad (mm)</small>
        <InputNumber min={1} value={p.padMM} onChange={(v)=>p.setPadMM(Number(v))} style={{ width:"100%" }}/>
      </Col>
      <Col xs={12} sm={8} md={6} lg={4}>
        <small>Gap (mm)</small>
        <InputNumber min={0} value={p.gapMM} onChange={(v)=>p.setGapMM(Number(v))} style={{ width:"100%" }}/>
      </Col>
      <Col xs={24}>
        <Space wrap>
          <Button type="primary" onClick={p.onApply}>Apply to face(s)</Button>
          <Button onClick={p.onClearSelected}>Clear selected faces</Button>
          <Button danger onClick={p.onClearAll}>Clear all patterns</Button>
          <Button onClick={p.onWrapY}>Add wrap around Y</Button>
          <Button onClick={p.onWrapX}>Add wrap around X</Button>
          <Button onClick={p.onWrapZ}>Add wrap around Z</Button>
        </Space>
      </Col>
    </Row>
  );
}
