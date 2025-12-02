import React, { useState, useRef, useEffect } from "react";
import DrawingCanvas from "./DrawingCanvas";
import DynaFilePartVisualizerGLBComponent from "./DynaFilePartVisualizerGLBComponent";
import { DeleteOutlined } from "@ant-design/icons";
import {
  Card,
  Button,
  Typography,
  Space,
  Form,
  InputNumber,
  Divider,
} from "antd";

const MorphComponent: React.FC = () => {
  const [glbFile, setGlbFile] = useState<File | null>(null);
  const drawingCanvasRef = useRef<any>(null);

  const [defaultDepth, setDefaultDepth] = useState(1.0);
  const [pushValue, setPushValue] = useState(0.5);
  const [effectRadius, setEffectRadius] = useState(0.1);
  const [angle, setAngle] = useState(5);

  const [shapes, setShapes] = useState<any[]>([]);

  useEffect(() => {
    const interval = setInterval(() => {
      if (drawingCanvasRef.current) {
        const newShapes = drawingCanvasRef.current.getShapes?.();
        setShapes(newShapes || []);
      }
    }, 500);
    return () => clearInterval(interval);
  }, []);

  const updateShapeValue = (id: number, field: string, value: number) => {
    setShapes((prev) =>
      prev.map((shape) => {
        if (shape.id !== id || shape.type !== "box") return shape;
        return {
          ...shape,
          modelRect: {
            ...shape.modelRect,
            [field]: value,
          },
        };
      })
    );
  };

  const handleDeleteShape = (id: number) => {
    const filtered = shapes.filter((s) => s.id !== id);
    setShapes(filtered);
    drawingCanvasRef.current?.setShapes?.(filtered);
  };

  const handleExportScript = () => {
    if (shapes.length === 0) return alert("내보낼 박스가 없습니다.");
    const stageScale = drawingCanvasRef.current?.getStageScale?.();
    const modelBounds = drawingCanvasRef.current?.getModelBounds?.();
    if (!stageScale || !modelBounds) return alert("모델 정보가 없습니다.");

    const fileName = glbFile?.name || "model.glb";
    const header = [
      "*Inputfile",
      fileName.replace(/\.glb$/i, ".k"),
      "*Mode",
      "PART_MORPHING,1",
      "**PartMorphing,1",
      "#Morph,Part ID,Shape,ShapeKeyword,ShapeKeyword,Direction,Push(+) or Pull(-) Value,EffectRadius,Angle",
    ];

    const boxes = shapes.filter((s: any) => s.type === "box");
    const body = boxes.map((shape: any) => {
      const { x, y, width, height } = shape.modelRect;
      const rawX1 = x / stageScale + modelBounds.xmin;
      const rawX2 = (x + width) / stageScale + modelBounds.xmin;
      const rawY1 = modelBounds.ymax - y / stageScale;
      const rawY2 = modelBounds.ymax - (y + height) / stageScale;
      const rawWidth = rawX2 - rawX1;
      const rawHeight = rawY1 - rawY2;
      const centerX = (rawX1 + rawX2) / 2;
      const centerY = (rawY1 + rawY2) / 2;
      const centerZ = defaultDepth / 2;
      const center = [centerX, centerY, centerZ].map((v) => v.toFixed(6));
      const size = [rawWidth, rawHeight, defaultDepth].map((v) => v.toFixed(6));
      return `*MorphBox,1,(${center.join(",")}),(${size.join(",")}),(1,0,0),(0,0,-1),${pushValue},${effectRadius},${angle}`;
    });

    const footer = ["**EndPartMorphing", "*End"];
    const content = [...header, ...body, ...footer].join("\n");
    const blob = new Blob([content], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "script.txt";
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div style={{ padding: 24, backgroundColor: "#fff", minHeight: "100vh", borderRadius: 24 }}>
      <div style={{ marginBottom: 20 }}>
        <DynaFilePartVisualizerGLBComponent onReady={({ glbFile }) => setGlbFile(glbFile)} />
      </div>

      {glbFile && (
        <>
          <Form layout="inline" style={{ marginBottom: 16 }}>
            <Form.Item label="Depth">
              <InputNumber value={defaultDepth} onChange={(v) => setDefaultDepth(v ?? 0)} style={{ width: 100 }} />
            </Form.Item>
            <Form.Item label="Push">
              <InputNumber value={pushValue} onChange={(v) => setPushValue(v ?? 0)} style={{ width: 100 }} />
            </Form.Item>
            <Form.Item label="EffectRadius">
              <InputNumber value={effectRadius} onChange={(v) => setEffectRadius(v ?? 0)} style={{ width: 100 }} />
            </Form.Item>
            <Form.Item label="Angle">
              <InputNumber value={angle} onChange={(v) => setAngle(v ?? 0)} style={{ width: 100 }} />
            </Form.Item>
            <Form.Item>
              <Button type="primary" onClick={handleExportScript}>📄 내보내기</Button>
            </Form.Item>
          </Form>

          <DrawingCanvas ref={drawingCanvasRef} glbFile={glbFile} />

          <Divider />

          <Typography.Title level={3}>도형 리스트</Typography.Title>
          {shapes.length === 0 ? (
            <Typography.Text>추가된 도형이 없습니다.</Typography.Text>
          ) : (
            <Space direction="vertical" style={{ width: "100%" }} size="middle">
              {shapes.map((shape) => (
                <Card
                  key={shape.id}
                  size="small"
                  bordered
                  title={<span><strong>ID:</strong> {shape.id} <strong>Type:</strong> {shape.type}</span>}
                  extra={
                    <Button
                      type="primary"
                      danger
                      icon={<DeleteOutlined />}
                      size="small"
                      onClick={() => handleDeleteShape(shape.id)}
                    >삭제</Button>
                  }
                >
           

{shape.type === "box" && shape.modelRect && (
  <div style={{ backgroundColor: "#fff", padding: "8px", borderRadius: 4 }}>
    <Form layout="inline">
      <Form.Item label="X">
        <InputNumber
          value={shape.modelRect.x}
          onChange={(v) => updateShapeValue(shape.id, "x", v ?? 0)}
          style={{ width: 100, backgroundColor: "#fff", color: "#000" }}
        />
      </Form.Item>
      <Form.Item label="Y">
        <InputNumber
          value={shape.modelRect.y}
          onChange={(v) => updateShapeValue(shape.id, "y", v ?? 0)}
          style={{ width: 100, backgroundColor: "#fff", color: "#000" }}
        />
      </Form.Item>
      <Form.Item label="W">
        <InputNumber
          value={shape.modelRect.width}
          onChange={(v) => updateShapeValue(shape.id, "width", v ?? 0)}
          style={{ width: 100, backgroundColor: "#fff", color: "#000" }}
        />
      </Form.Item>
      <Form.Item label="H">
        <InputNumber
          value={shape.modelRect.height}
          onChange={(v) => updateShapeValue(shape.id, "height", v ?? 0)}
          style={{ width: 100, backgroundColor: "#fff", color: "#000" }}
        />
      </Form.Item>
    </Form>
  </div>
)}

                </Card>
              ))}
            </Space>
          )}
        </>
      )}
    </div>
  );
};

export default MorphComponent;
