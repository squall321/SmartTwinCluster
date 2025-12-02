import React, { useState, useEffect, useRef, DragEvent } from "react";
import DrawingCanvas from "./DrawingCanvas";

const DrawingCanvasWithModel: React.FC = () => {
  const [glbUrl, setGlbUrl] = useState<string | null>(null);
  const [stlUrl, setStlUrl] = useState<string | null>(null);

  const canvasRef = useRef<any>(null);

  const [shapes, setShapes] = useState<any[]>([]);

  const handleFileDrop = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    const file = e.dataTransfer.files[0];
    if (!file) return;

    if (file.name.toLowerCase().endsWith(".glb")) {
      const url = URL.createObjectURL(file);
      setGlbUrl(url);
    } else if (file.name.toLowerCase().endsWith(".stl")) {
      const url = URL.createObjectURL(file);
      setStlUrl(url);
    } else {
      alert("GLB 또는 STL 파일만 지원됩니다.");
    }
  };

  const handleFileInput = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.name.toLowerCase().endsWith(".glb")) {
      const url = URL.createObjectURL(file);
      setGlbUrl(url);
    } else if (file.name.toLowerCase().endsWith(".stl")) {
      const url = URL.createObjectURL(file);
      setStlUrl(url);
    } else {
      alert("GLB 또는 STL 파일만 지원됩니다.");
    }
  };

  // 주기적으로 DrawingCanvas shapes 가져오기
  useEffect(() => {
    const interval = setInterval(() => {
      if (canvasRef.current) {
        const newShapes = canvasRef.current.getShapes?.();
        setShapes(newShapes || []);
      }
    }, 500);

    return () => clearInterval(interval);
  }, []);

  return (
    <div>
      <div
        onDrop={handleFileDrop}
        onDragOver={(e) => e.preventDefault()}
        style={{
          border: "2px dashed #aaa",
          padding: 20,
          marginBottom: 10,
          textAlign: "center",
        }}
      >
        <p>GLB 파일을 여기로 끌어오거나 선택하세요.</p>
        <input type="file" accept=".glb" onChange={handleFileInput} />
      </div>

      <DrawingCanvas
        ref={canvasRef}
        glbUrl={glbUrl ?? undefined}
      />

      <div style={{ marginTop: 20, borderTop: "1px solid #ccc", paddingTop: 10 }}>
        <h3>도형 리스트</h3>
        {shapes.length === 0 && <p>추가된 도형이 없습니다.</p>}
        {shapes.map((shape) => (
          <div key={shape.id} style={{ marginBottom: 10 }}>
            <strong>ID:</strong> {shape.id} <br />
            <strong>Type:</strong> {shape.type} <br />
            {shape.type === "poly" && (
              <>
                <strong>Points:</strong>{" "}
                {shape.modelPoints
                  .map((p: any) => `(${p.x}, ${p.y})`)
                  .join(", ")}
              </>
            )}
            {shape.type === "box" && (
              <>
                <strong>Rect:</strong>{" "}
                x: {shape.modelRect.x}, y: {shape.modelRect.y},
                width: {shape.modelRect.width}, height: {shape.modelRect.height}
              </>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};

export default DrawingCanvasWithModel;
