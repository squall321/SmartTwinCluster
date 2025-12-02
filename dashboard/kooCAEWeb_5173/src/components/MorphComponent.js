import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState, useRef, useEffect } from "react";
import DrawingCanvas from "./DrawingCanvas";
import DynaFilePartVisualizerGLBComponent from "./DynaFilePartVisualizerGLBComponent";
import { DeleteOutlined } from "@ant-design/icons";
import { Card, Button, Typography, Space, Form, InputNumber, Divider, } from "antd";
const MorphComponent = () => {
    const [glbFile, setGlbFile] = useState(null);
    const drawingCanvasRef = useRef(null);
    const [defaultDepth, setDefaultDepth] = useState(1.0);
    const [pushValue, setPushValue] = useState(0.5);
    const [effectRadius, setEffectRadius] = useState(0.1);
    const [angle, setAngle] = useState(5);
    const [shapes, setShapes] = useState([]);
    useEffect(() => {
        const interval = setInterval(() => {
            if (drawingCanvasRef.current) {
                const newShapes = drawingCanvasRef.current.getShapes?.();
                setShapes(newShapes || []);
            }
        }, 500);
        return () => clearInterval(interval);
    }, []);
    const updateShapeValue = (id, field, value) => {
        setShapes((prev) => prev.map((shape) => {
            if (shape.id !== id || shape.type !== "box")
                return shape;
            return {
                ...shape,
                modelRect: {
                    ...shape.modelRect,
                    [field]: value,
                },
            };
        }));
    };
    const handleDeleteShape = (id) => {
        const filtered = shapes.filter((s) => s.id !== id);
        setShapes(filtered);
        drawingCanvasRef.current?.setShapes?.(filtered);
    };
    const handleExportScript = () => {
        if (shapes.length === 0)
            return alert("내보낼 박스가 없습니다.");
        const stageScale = drawingCanvasRef.current?.getStageScale?.();
        const modelBounds = drawingCanvasRef.current?.getModelBounds?.();
        if (!stageScale || !modelBounds)
            return alert("모델 정보가 없습니다.");
        const fileName = glbFile?.name || "model.glb";
        const header = [
            "*Inputfile",
            fileName.replace(/\.glb$/i, ".k"),
            "*Mode",
            "PART_MORPHING,1",
            "**PartMorphing,1",
            "#Morph,Part ID,Shape,ShapeKeyword,ShapeKeyword,Direction,Push(+) or Pull(-) Value,EffectRadius,Angle",
        ];
        const boxes = shapes.filter((s) => s.type === "box");
        const body = boxes.map((shape) => {
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
    return (_jsxs("div", { style: { padding: 24, backgroundColor: "#fff", minHeight: "100vh", borderRadius: 24 }, children: [_jsx("div", { style: { marginBottom: 20 }, children: _jsx(DynaFilePartVisualizerGLBComponent, { onReady: ({ glbFile }) => setGlbFile(glbFile) }) }), glbFile && (_jsxs(_Fragment, { children: [_jsxs(Form, { layout: "inline", style: { marginBottom: 16 }, children: [_jsx(Form.Item, { label: "Depth", children: _jsx(InputNumber, { value: defaultDepth, onChange: (v) => setDefaultDepth(v ?? 0), style: { width: 100 } }) }), _jsx(Form.Item, { label: "Push", children: _jsx(InputNumber, { value: pushValue, onChange: (v) => setPushValue(v ?? 0), style: { width: 100 } }) }), _jsx(Form.Item, { label: "EffectRadius", children: _jsx(InputNumber, { value: effectRadius, onChange: (v) => setEffectRadius(v ?? 0), style: { width: 100 } }) }), _jsx(Form.Item, { label: "Angle", children: _jsx(InputNumber, { value: angle, onChange: (v) => setAngle(v ?? 0), style: { width: 100 } }) }), _jsx(Form.Item, { children: _jsx(Button, { type: "primary", onClick: handleExportScript, children: "\uD83D\uDCC4 \uB0B4\uBCF4\uB0B4\uAE30" }) })] }), _jsx(DrawingCanvas, { ref: drawingCanvasRef, glbFile: glbFile }), _jsx(Divider, {}), _jsx(Typography.Title, { level: 3, children: "\uB3C4\uD615 \uB9AC\uC2A4\uD2B8" }), shapes.length === 0 ? (_jsx(Typography.Text, { children: "\uCD94\uAC00\uB41C \uB3C4\uD615\uC774 \uC5C6\uC2B5\uB2C8\uB2E4." })) : (_jsx(Space, { direction: "vertical", style: { width: "100%" }, size: "middle", children: shapes.map((shape) => (_jsx(Card, { size: "small", bordered: true, title: _jsxs("span", { children: [_jsx("strong", { children: "ID:" }), " ", shape.id, " ", _jsx("strong", { children: "Type:" }), " ", shape.type] }), extra: _jsx(Button, { type: "primary", danger: true, icon: _jsx(DeleteOutlined, {}), size: "small", onClick: () => handleDeleteShape(shape.id), children: "\uC0AD\uC81C" }), children: shape.type === "box" && shape.modelRect && (_jsx("div", { style: { backgroundColor: "#fff", padding: "8px", borderRadius: 4 }, children: _jsxs(Form, { layout: "inline", children: [_jsx(Form.Item, { label: "X", children: _jsx(InputNumber, { value: shape.modelRect.x, onChange: (v) => updateShapeValue(shape.id, "x", v ?? 0), style: { width: 100, backgroundColor: "#fff", color: "#000" } }) }), _jsx(Form.Item, { label: "Y", children: _jsx(InputNumber, { value: shape.modelRect.y, onChange: (v) => updateShapeValue(shape.id, "y", v ?? 0), style: { width: 100, backgroundColor: "#fff", color: "#000" } }) }), _jsx(Form.Item, { label: "W", children: _jsx(InputNumber, { value: shape.modelRect.width, onChange: (v) => updateShapeValue(shape.id, "width", v ?? 0), style: { width: 100, backgroundColor: "#fff", color: "#000" } }) }), _jsx(Form.Item, { label: "H", children: _jsx(InputNumber, { value: shape.modelRect.height, onChange: (v) => updateShapeValue(shape.id, "height", v ?? 0), style: { width: 100, backgroundColor: "#fff", color: "#000" } }) })] }) })) }, shape.id))) }))] }))] }));
};
export default MorphComponent;
