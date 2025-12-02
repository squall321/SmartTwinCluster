import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState, useEffect, useRef } from "react";
import DrawingCanvas from "./DrawingCanvas";
const DrawingCanvasWithModel = () => {
    const [glbUrl, setGlbUrl] = useState(null);
    const [stlUrl, setStlUrl] = useState(null);
    const canvasRef = useRef(null);
    const [shapes, setShapes] = useState([]);
    const handleFileDrop = (e) => {
        e.preventDefault();
        const file = e.dataTransfer.files[0];
        if (!file)
            return;
        if (file.name.toLowerCase().endsWith(".glb")) {
            const url = URL.createObjectURL(file);
            setGlbUrl(url);
        }
        else if (file.name.toLowerCase().endsWith(".stl")) {
            const url = URL.createObjectURL(file);
            setStlUrl(url);
        }
        else {
            alert("GLB 또는 STL 파일만 지원됩니다.");
        }
    };
    const handleFileInput = (e) => {
        const file = e.target.files?.[0];
        if (!file)
            return;
        if (file.name.toLowerCase().endsWith(".glb")) {
            const url = URL.createObjectURL(file);
            setGlbUrl(url);
        }
        else if (file.name.toLowerCase().endsWith(".stl")) {
            const url = URL.createObjectURL(file);
            setStlUrl(url);
        }
        else {
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
    return (_jsxs("div", { children: [_jsxs("div", { onDrop: handleFileDrop, onDragOver: (e) => e.preventDefault(), style: {
                    border: "2px dashed #aaa",
                    padding: 20,
                    marginBottom: 10,
                    textAlign: "center",
                }, children: [_jsx("p", { children: "GLB \uD30C\uC77C\uC744 \uC5EC\uAE30\uB85C \uB04C\uC5B4\uC624\uAC70\uB098 \uC120\uD0DD\uD558\uC138\uC694." }), _jsx("input", { type: "file", accept: ".glb", onChange: handleFileInput })] }), _jsx(DrawingCanvas, { ref: canvasRef, glbUrl: glbUrl ?? undefined }), _jsxs("div", { style: { marginTop: 20, borderTop: "1px solid #ccc", paddingTop: 10 }, children: [_jsx("h3", { children: "\uB3C4\uD615 \uB9AC\uC2A4\uD2B8" }), shapes.length === 0 && _jsx("p", { children: "\uCD94\uAC00\uB41C \uB3C4\uD615\uC774 \uC5C6\uC2B5\uB2C8\uB2E4." }), shapes.map((shape) => (_jsxs("div", { style: { marginBottom: 10 }, children: [_jsx("strong", { children: "ID:" }), " ", shape.id, " ", _jsx("br", {}), _jsx("strong", { children: "Type:" }), " ", shape.type, " ", _jsx("br", {}), shape.type === "poly" && (_jsxs(_Fragment, { children: [_jsx("strong", { children: "Points:" }), " ", shape.modelPoints
                                        .map((p) => `(${p.x}, ${p.y})`)
                                        .join(", ")] })), shape.type === "box" && (_jsxs(_Fragment, { children: [_jsx("strong", { children: "Rect:" }), " ", "x: ", shape.modelRect.x, ", y: ", shape.modelRect.y, ", width: ", shape.modelRect.width, ", height: ", shape.modelRect.height] }))] }, shape.id)))] })] }));
};
export default DrawingCanvasWithModel;
