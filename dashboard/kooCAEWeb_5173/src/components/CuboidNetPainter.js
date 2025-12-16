import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useMemo, useRef, useState } from "react";
import { Button, Space, InputNumber, Select, Divider, Card, Row, Col, Typography, Slider, Tag, Tooltip } from "antd";
import * as THREE from "three";
const { Text } = Typography;
// Face → physical size (mm) on the unfolded net
function faceSizeMM(face, xMM, yMM, zMM) {
    switch (face) {
        case "+X":
        case "-X":
            return { w: zMM, h: yMM }; // side faces
        case "+Y":
        case "-Y":
            return { w: xMM, h: zMM }; // top/bottom bands relative
        case "+Z":
        case "-Z":
            return { w: xMM, h: yMM }; // front/back
    }
}
// 강한 팔레트(legend/라벨용) — 면 채움은 알파로 파스텔 느낌 유지
const FACE_COLOR = {
    "+X": "#1677FF", // blue-6
    "-X": "#FA8C16", // orange-6
    "+Y": "#52C41A", // green-6
    "-Y": "#13C2C2", // cyan-6
    "+Z": "#722ED1", // purple-6
    "-Z": "#EB2F96", // magenta-6
};
const PRESETS = {
    // 기존 3×2 (촘촘)
    "Compact 3×2": [
        ["+X", "-X", "+Y"],
        ["-Y", "+Z", "-Z"],
    ],
    // 가장 직관적인 세로 십자
    "Vertical Cross 3×4": [
        [null, "+Y", null],
        ["-X", "+Z", "+X"],
        [null, "-Y", null],
        [null, "-Z", null],
    ],
    // 가로 십자
    "Horizontal Cross 4×3": [
        [null, "+Y", null, null],
        ["-X", "+Z", "+X", "-Z"],
        [null, "-Y", null, null],
    ],
    // 일렬 배치
    "Strip 6×1": [
        ["-X", "+Z", "+X", "-Z", "+Y", "-Y"],
    ],
};
// Build native (atlas) layout in pixels based on mm and px/mm; supports arbitrary grid with nulls
function buildLayout(xMM, yMM, zMM, ppmm, marginPx, grid) {
    // per-face pixel size
    const facePx = {
        "+X": { w: 0, h: 0 }, "-X": { w: 0, h: 0 },
        "+Y": { w: 0, h: 0 }, "-Y": { w: 0, h: 0 },
        "+Z": { w: 0, h: 0 }, "-Z": { w: 0, h: 0 },
    };
    Object.keys(facePx).forEach((f) => {
        const s = faceSizeMM(f, xMM, yMM, zMM);
        facePx[f] = { w: Math.max(1, Math.round(s.w * ppmm)), h: Math.max(1, Math.round(s.h * ppmm)) };
    });
    const nRows = grid.length;
    const nCols = grid.reduce((m, r) => Math.max(m, r.length), 0);
    const colW = Array.from({ length: nCols }, () => 0);
    const rowH = Array.from({ length: nRows }, () => 0);
    for (let r = 0; r < nRows; r++) {
        for (let c = 0; c < nCols; c++) {
            const f = grid[r][c] ?? null;
            if (!f)
                continue;
            colW[c] = Math.max(colW[c], facePx[f].w);
            rowH[r] = Math.max(rowH[r], facePx[f].h);
        }
    }
    const colX = Array.from({ length: nCols }, (_, c) => marginPx + colW.slice(0, c).reduce((a, b) => a + b, 0) + marginPx * c);
    const rowY = Array.from({ length: nRows }, (_, r) => marginPx + rowH.slice(0, r).reduce((a, b) => a + b, 0) + marginPx * r);
    const atlasW = colW.reduce((a, b) => a + b, 0) + marginPx * (nCols + 1);
    const atlasH = rowH.reduce((a, b) => a + b, 0) + marginPx * (nRows + 1);
    const cellRects = {};
    const faceRects = {};
    for (let r = 0; r < nRows; r++) {
        for (let c = 0; c < nCols; c++) {
            const key = `c${c}r${r}`;
            const w = colW[c], h = rowH[r], x = colX[c], y = rowY[r];
            cellRects[key] = { x, y, w, h };
            const f = grid[r][c] ?? null;
            if (f) {
                const W = facePx[f].w, H = facePx[f].h;
                faceRects[f] = { x: x + Math.floor((w - W) / 2), y: y + Math.floor((h - H) / 2), w: W, h: H };
            }
        }
    }
    return { atlasW, atlasH, grid, cellRects, faceRects, colW, rowH, colX, rowY, marginPx, nRows, nCols };
}
// Draw helpers (native space)
function drawHinges(ctx, layout) {
    const { grid, cellRects, nRows, nCols, marginPx } = layout;
    ctx.save();
    ctx.strokeStyle = "#666";
    ctx.setLineDash([5, 5]);
    ctx.lineWidth = 1.2;
    // vertical hinges between (r,c) and (r,c+1)
    for (let r = 0; r < nRows; r++) {
        for (let c = 0; c < nCols - 1; c++) {
            const lf = grid[r][c], rf = grid[r][c + 1];
            if (!lf || !rf)
                continue;
            const L = cellRects[`c${c}r${r}`];
            const R = cellRects[`c${c + 1}r${r}`];
            const x = L.x + L.w + marginPx / 2;
            ctx.beginPath();
            ctx.moveTo(x + 0.5, L.y);
            ctx.lineTo(x + 0.5, L.y + L.h);
            ctx.stroke();
        }
    }
    // horizontal hinges between (r,c) and (r+1,c)
    for (let r = 0; r < nRows - 1; r++) {
        for (let c = 0; c < nCols; c++) {
            const uf = grid[r][c], df = grid[r + 1][c];
            if (!uf || !df)
                continue;
            const U = cellRects[`c${c}r${r}`];
            const D = cellRects[`c${c}r${r + 1}`];
            const y = U.y + U.h + marginPx / 2;
            ctx.beginPath();
            ctx.moveTo(U.x, y + 0.5);
            ctx.lineTo(U.x + U.w, y + 0.5);
            ctx.stroke();
        }
    }
    ctx.restore();
}
function drawFaceFills(ctx, layout, ppmm) {
    Object.keys(layout.faceRects).forEach((f) => {
        const r = layout.faceRects[f];
        ctx.fillStyle = FACE_COLOR[f] + "B0"; // (#RRGGBBAA) → 약간 투명
        ctx.fillRect(r.x, r.y, r.w, r.h);
        // (선택) 내부 눈금은 채움과 함께 아래에 깔리게
        const pxPer20mm = 20 * ppmm;
        if (pxPer20mm >= 40) {
            ctx.save();
            ctx.strokeStyle = "#999";
            ctx.lineWidth = 1;
            ctx.setLineDash([2, 6]);
            for (let x = r.x; x <= r.x + r.w; x += pxPer20mm) {
                ctx.beginPath();
                ctx.moveTo(x + 0.5, r.y);
                ctx.lineTo(x + 0.5, r.y + r.h);
                ctx.stroke();
            }
            for (let y = r.y; y <= r.y + r.h; y += pxPer20mm) {
                ctx.beginPath();
                ctx.moveTo(r.x, y + 0.5);
                ctx.lineTo(r.x + r.w, y + 0.5);
                ctx.stroke();
            }
            ctx.restore();
        }
    });
}
function drawSeamsAndLabels(ctx, layout, highlight) {
    Object.keys(layout.faceRects).forEach((f) => {
        const r = layout.faceRects[f];
        // 하이라이트(선택 면)
        if (highlight && f === highlight) {
            ctx.save();
            ctx.strokeStyle = "#1677ff";
            ctx.lineWidth = 3;
            ctx.setLineDash([6, 4]);
            ctx.strokeRect(r.x + 1.5, r.y + 1.5, r.w - 3, r.h - 3);
            ctx.restore();
        }
        // 외곽선
        ctx.strokeStyle = "#222";
        ctx.lineWidth = 2;
        ctx.setLineDash([]);
        ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
        // 라벨
        ctx.save();
        ctx.font = "12px sans-serif";
        ctx.fillStyle = "rgba(0,0,0,0.65)";
        const text = f;
        const pad = 4;
        const tw = ctx.measureText(text).width + pad * 2;
        ctx.fillRect(r.x + 6, r.y + 6, tw, 18);
        ctx.fillStyle = "#fff";
        ctx.textBaseline = "middle";
        ctx.fillText(text, r.x + 6 + pad, r.y + 6 + 9);
        ctx.restore();
    });
}
// Brush: paint=true → 흰색/불투명, paint=false → 투명(지우개)
function drawCircleToImageData(img, cx, cy, radius, paint) {
    const { width: W, height: H, data } = img;
    const r2 = radius * radius;
    const x0 = Math.max(0, Math.floor(cx - radius));
    const y0 = Math.max(0, Math.floor(cy - radius));
    const x1 = Math.min(W - 1, Math.ceil(cx + radius));
    const y1 = Math.min(H - 1, Math.ceil(cy + radius));
    for (let y = y0; y <= y1; y++)
        for (let x = x0; x <= x1; x++) {
            const dx = x - cx, dy = y - cy;
            if (dx * dx + dy * dy <= r2) {
                const idx = (y * W + x) * 4;
                if (paint) {
                    data[idx] = 255;
                    data[idx + 1] = 255;
                    data[idx + 2] = 255;
                    data[idx + 3] = 255;
                }
                else {
                    data[idx] = 0;
                    data[idx + 1] = 0;
                    data[idx + 2] = 0;
                    data[idx + 3] = 0;
                }
            }
        }
}
// 패턴을 patternCanvas 위에만 그림(흰색=테이프)
function drawPatternOnFace(ctx, r, kind, params, ppmm) {
    ctx.save();
    ctx.imageSmoothingEnabled = true;
    ctx.fillStyle = "#fff";
    ctx.strokeStyle = "#fff";
    switch (kind) {
        case "wrap-cross": {
            const lineMM = params.lineMM ?? 2;
            const lw = Math.max(1, Math.round(lineMM * ppmm));
            ctx.lineWidth = lw;
            // 중앙 가로/세로
            ctx.beginPath();
            ctx.moveTo(r.x, r.y + r.h / 2);
            ctx.lineTo(r.x + r.w, r.y + r.h / 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(r.x + r.w / 2, r.y);
            ctx.lineTo(r.x + r.w / 2, r.y + r.h);
            ctx.stroke();
            break;
        }
        case "band-h": {
            const bandMM = params.bandMM ?? 8;
            const bh = Math.round(bandMM * ppmm);
            const y = Math.round(r.y + (r.h - bh) / 2);
            ctx.fillRect(r.x, y, r.w, bh);
            break;
        }
        case "band-v": {
            const bandMM = params.bandMM ?? 8;
            const bw = Math.round(bandMM * ppmm);
            const x = Math.round(r.x + (r.w - bw) / 2);
            ctx.fillRect(x, r.y, bw, r.h);
            break;
        }
        case "border-only": {
            const borderMM = params.borderMM ?? 3;
            const b = Math.max(1, Math.round(borderMM * ppmm));
            // 네 변 스트립
            ctx.fillRect(r.x, r.y, r.w, b); // top
            ctx.fillRect(r.x, r.y + r.h - b, r.w, b); // bottom
            ctx.fillRect(r.x, r.y, b, r.h); // left
            ctx.fillRect(r.x + r.w - b, r.y, b, r.h); // right
            break;
        }
        case "corner-pads": {
            const padMM = params.padMM ?? 6;
            const gMM = params.gapMM ?? 2;
            const s = Math.max(1, Math.round(padMM * ppmm));
            const g = Math.max(0, Math.round(gMM * ppmm));
            // 4개 코너
            ctx.fillRect(r.x + g, r.y + g, s, s);
            ctx.fillRect(r.x + r.w - s - g, r.y + g, s, s);
            ctx.fillRect(r.x + g, r.y + r.h - s - g, s, s);
            ctx.fillRect(r.x + r.w - s - g, r.y + r.h - s - g, s, s);
            break;
        }
    }
    ctx.restore();
}
function MiniCubePreview({ xMM, yMM, zMM, layout, getMaskCanvas, getPatternCanvas, maskVersion }) {
    const mountRef = useRef(null);
    const sceneRef = useRef(null);
    const rendererRef = useRef(null);
    const cameraRef = useRef(null);
    const cubeRef = useRef(null);
    const materialsRef = useRef([]);
    const rafRef = useRef(null);
    const draggingRef = useRef(false);
    const lastPosRef = useRef({ x: 0, y: 0 });
    const edgesRef = useRef(null);
    // faces order for BoxGeometry: +X, -X, +Y, -Y, +Z, -Z
    const faceOrder = ["+X", "-X", "+Y", "-Y", "+Z", "-Z"];
    function makeFaceTexture(face) {
        const size = 512;
        const cvs = document.createElement("canvas");
        cvs.width = size;
        cvs.height = size;
        const ctx = cvs.getContext("2d");
        // 1) 금속 바탕 + 틴트
        ctx.fillStyle = "#AEB6C1";
        ctx.fillRect(0, 0, size, size);
        ctx.globalAlpha = 0.28;
        ctx.fillStyle = FACE_COLOR[face];
        ctx.fillRect(0, 0, size, size);
        ctx.globalAlpha = 1;
        // 2) 라이트 그리드
        ctx.strokeStyle = "rgba(0,0,0,0.15)";
        ctx.lineWidth = 1;
        const step = 64;
        for (let x = step; x < size; x += step) {
            ctx.beginPath();
            ctx.moveTo(x + 0.5, 0);
            ctx.lineTo(x + 0.5, size);
            ctx.stroke();
        }
        for (let y = step; y < size; y += step) {
            ctx.beginPath();
            ctx.moveTo(0, y + 0.5);
            ctx.lineTo(size, y + 0.5);
            ctx.stroke();
        }
        // 3) 패턴 합성
        const pattern = getPatternCanvas();
        const fr = layout.faceRects[face];
        if (pattern && fr && fr.w > 0 && fr.h > 0) {
            ctx.drawImage(pattern, fr.x, fr.y, fr.w, fr.h, 0, 0, size, size);
        }
        // 4) 브러쉬 마스크 합성
        const mask = getMaskCanvas();
        if (mask && fr && fr.w > 0 && fr.h > 0) {
            ctx.drawImage(mask, fr.x, fr.y, fr.w, fr.h, 0, 0, size, size);
        }
        // 5) 가장자리 + 라벨
        ctx.strokeStyle = "#222";
        ctx.lineWidth = 4;
        ctx.strokeRect(2, 2, size - 4, size - 4);
        ctx.fillStyle = "#111";
        ctx.font = "bold 48px system-ui, sans-serif";
        const text = face;
        const tw = ctx.measureText(text).width;
        ctx.fillText(text, (size - tw) / 2, size - 28);
        const tex = new THREE.CanvasTexture(cvs);
        tex.colorSpace = THREE.SRGBColorSpace;
        tex.minFilter = THREE.LinearFilter;
        tex.magFilter = THREE.LinearFilter;
        tex.needsUpdate = true;
        return tex;
    }
    function rebuildMaterials() {
        const mats = faceOrder.map((f) => new THREE.MeshBasicMaterial({ map: makeFaceTexture(f) }));
        materialsRef.current.forEach(m => { m.map?.dispose(); m.dispose(); });
        materialsRef.current = mats;
        if (cubeRef.current)
            cubeRef.current.material.splice(0, 6, ...mats);
    }
    // 크기 변경 시 지오메트리와 엣지 업데이트
    useEffect(() => {
        if (!cubeRef.current || !cameraRef.current)
            return;
        const cube = cubeRef.current;
        const oldGeo = cube.geometry;
        const newGeo = new THREE.BoxGeometry(xMM, yMM, zMM);
        cube.geometry = newGeo;
        oldGeo.dispose();
        if (!edgesRef.current) {
            const e = new THREE.EdgesGeometry(newGeo);
            edgesRef.current = new THREE.LineSegments(e, new THREE.LineBasicMaterial({ color: 0x111111 }));
            cube.add(edgesRef.current);
        }
        else {
            const prev = edgesRef.current;
            prev.geometry.dispose();
            prev.geometry = new THREE.EdgesGeometry(newGeo);
            prev.material.needsUpdate = true;
        }
        const maxDim = Math.max(xMM, yMM, zMM);
        const cam = cameraRef.current;
        cam.position.set(maxDim * 1.8, maxDim * 1.2, maxDim * 2.2);
        cam.lookAt(0, 0, 0);
    }, [xMM, yMM, zMM]);
    useEffect(() => {
        if (!mountRef.current)
            return;
        const mount = mountRef.current;
        const scene = new THREE.Scene();
        scene.background = null;
        sceneRef.current = scene;
        const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
        rendererRef.current = renderer;
        mount.appendChild(renderer.domElement);
        const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 1000);
        cameraRef.current = camera;
        const light = new THREE.AmbientLight(0xffffff, 0.9);
        scene.add(light);
        const geo = new THREE.BoxGeometry(xMM, yMM, zMM);
        const mats = faceOrder.map((f) => new THREE.MeshBasicMaterial({ map: makeFaceTexture(f) }));
        materialsRef.current = mats;
        const cube = new THREE.Mesh(geo, mats);
        cubeRef.current = cube;
        scene.add(cube);
        const edges = new THREE.EdgesGeometry(geo);
        const line = new THREE.LineSegments(edges, new THREE.LineBasicMaterial({ color: 0x111111 }));
        cube.add(line);
        edgesRef.current = line;
        const maxDim = Math.max(xMM, yMM, zMM);
        camera.position.set(maxDim * 1.8, maxDim * 1.2, maxDim * 2.2);
        camera.lookAt(0, 0, 0);
        function resize() {
            const w = mount.clientWidth || 240;
            const h = mount.clientHeight || 240;
            renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
            renderer.setSize(w, h, false);
            camera.aspect = w / h;
            camera.updateProjectionMatrix();
        }
        const ro = new ResizeObserver(resize);
        ro.observe(mount);
        resize();
        function onDown(e) { draggingRef.current = true; lastPosRef.current = { x: e.clientX, y: e.clientY }; mount.setPointerCapture(e.pointerId); }
        function onMove(e) {
            if (!draggingRef.current || !cubeRef.current)
                return;
            const dx = (e.clientX - lastPosRef.current.x) / 150;
            const dy = (e.clientY - lastPosRef.current.y) / 150;
            cubeRef.current.rotation.y += dx;
            cubeRef.current.rotation.x += dy;
            lastPosRef.current = { x: e.clientX, y: e.clientY };
        }
        function onUp(e) { draggingRef.current = false; mount.releasePointerCapture?.(e.pointerId); }
        mount.addEventListener("pointerdown", onDown);
        mount.addEventListener("pointermove", onMove);
        mount.addEventListener("pointerup", onUp);
        mount.addEventListener("pointerleave", onUp);
        const animate = () => {
            rafRef.current = requestAnimationFrame(animate);
            if (cubeRef.current && !draggingRef.current)
                cubeRef.current.rotation.y += 0.006;
            renderer.render(scene, camera);
        };
        animate();
        return () => {
            if (rafRef.current)
                cancelAnimationFrame(rafRef.current);
            mount.removeEventListener("pointerdown", onDown);
            mount.removeEventListener("pointermove", onMove);
            mount.removeEventListener("pointerup", onUp);
            mount.removeEventListener("pointerleave", onUp);
            ro.disconnect();
            scene.clear();
            materialsRef.current.forEach(m => { m.map?.dispose(); m.dispose(); });
            cubeRef.current?.geometry.dispose();
            renderer.dispose();
            mount.removeChild(renderer.domElement);
            if (edgesRef.current) {
                edgesRef.current.geometry.dispose();
                edgesRef.current.material.dispose();
            }
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);
    // 레이아웃/마스크/패턴 변경 시 텍스처 재빌드
    useEffect(() => {
        rebuildMaterials();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [xMM, yMM, zMM, layout.atlasW, layout.atlasH, layout.faceRects, maskVersion]);
    return _jsx("div", { ref: mountRef, style: { width: "100%", height: 240 } });
}
// ===== Main Component =====
export default function CuboidNetPainter() {
    // Geometry (mm)
    const [xMM, setXMM] = useState(60);
    const [yMM, setYMM] = useState(150);
    const [zMM, setZMM] = useState(8);
    const [ppmm, setPPMM] = useState(4); // pixels per mm (native)
    const [marginPx, setMarginPx] = useState(24);
    // Net preset
    const [preset, setPreset] = useState("Vertical Cross 3×4");
    const [mode, setMode] = useState("paint");
    const [brushMM, setBrushMM] = useState(4);
    // Pattern state
    const [patterns, setPatterns] = useState({});
    const [patternKind, setPatternKind] = useState("wrap-cross");
    const [selectedFaces, setSelectedFaces] = useState(["+X"]); // pattern 적용 대상
    // 패턴 파라미터(공통 폼). 필요한 것만 사용
    const [lineMM, setLineMM] = useState(2);
    const [bandMM, setBandMM] = useState(8);
    const [borderMM, setBorderMM] = useState(3);
    const [padMM, setPadMM] = useState(6);
    const [gapMM, setGapMM] = useState(2);
    // Wrap helper sets
    const WRAP_Y = ["+X", "-X", "+Z", "-Z"]; // Y축 둘레(옆면 띠)
    const WRAP_X = ["+Z", "-Z", "+Y", "-Y"]; // X축 둘레
    const WRAP_Z = ["+X", "-X", "+Y", "-Y"]; // Z축 둘레
    // View (screen) controls
    const [zoom, setZoom] = useState("fit");
    const [viewScale, setViewScale] = useState(1);
    const [viewOffset, setViewOffset] = useState({ x: 0, y: 0 });
    const [highlightFace, setHighlightFace] = useState(null);
    // Derived layout
    const grid = useMemo(() => PRESETS[preset], [preset]);
    const layout = useMemo(() => buildLayout(xMM, yMM, zMM, ppmm, marginPx, grid), [xMM, yMM, zMM, ppmm, marginPx, grid]);
    // Visible canvas + container
    const canvasRef = useRef(null);
    const containerRef = useRef(null);
    const maskCanvasRef = useRef(null); // freehand brush
    const patternCanvasRef = useRef(null); // generated patterns
    const imageDataRef = useRef(null);
    const [maskVersion, setMaskVersion] = useState(0); // bump to refresh 3D textures
    // Resize observer
    useEffect(() => {
        function resize() {
            const dpr = Math.max(1, window.devicePixelRatio || 1);
            const c = canvasRef.current;
            const div = containerRef.current;
            if (!c || !div)
                return;
            const w = Math.max(200, div.clientWidth);
            const h = Math.max(200, Math.floor(div.clientHeight));
            c.width = Math.floor(w * dpr);
            c.height = Math.floor(h * dpr);
            c.style.width = w + "px";
            c.style.height = h + "px";
            redraw();
        }
        const ro = new ResizeObserver(resize);
        if (containerRef.current)
            ro.observe(containerRef.current);
        window.addEventListener("resize", resize);
        resize();
        return () => { ro.disconnect(); window.removeEventListener("resize", resize); };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);
    // Recreate mask & pattern backing stores when layout changes
    useEffect(() => {
        // mask
        const m = document.createElement("canvas");
        m.width = layout.atlasW;
        m.height = layout.atlasH;
        maskCanvasRef.current = m;
        const mctx = m.getContext("2d");
        if (!mctx)
            return;
        imageDataRef.current = mctx.createImageData(layout.atlasW, layout.atlasH);
        const d = imageDataRef.current.data;
        for (let i = 0; i < d.length; i += 4) {
            d[i] = 0;
            d[i + 1] = 0;
            d[i + 2] = 0;
            d[i + 3] = 0;
        }
        // pattern
        const p = document.createElement("canvas");
        p.width = layout.atlasW;
        p.height = layout.atlasH;
        patternCanvasRef.current = p;
        repaintPatterns();
        setMaskVersion(v => v + 1);
        redraw();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [layout]);
    // 패턴 다시 그리기 (patterns/치수/스케일 변하면)
    useEffect(() => {
        repaintPatterns();
        setMaskVersion(v => v + 1);
        redraw();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [patterns, ppmm, xMM, yMM, zMM]);
    function repaintPatterns() {
        const p = patternCanvasRef.current;
        if (!p)
            return;
        const ctx = p.getContext("2d");
        ctx.clearRect(0, 0, p.width, p.height);
        Object.keys(layout.faceRects).forEach(face => {
            const spec = patterns[face];
            if (!spec)
                return;
            const r = layout.faceRects[face];
            const params = {
                lineMM, bandMM, borderMM, padMM, gapMM,
                ...(spec.params || {})
            };
            drawPatternOnFace(ctx, r, spec.kind, params, ppmm);
        });
    }
    // Compute viewScale & offset then draw
    function redraw() {
        const c = canvasRef.current;
        const ctx = c?.getContext("2d");
        if (!c || !ctx)
            return;
        const dpr = Math.max(1, window.devicePixelRatio || 1);
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, c.width, c.height);
        const fitScale = Math.min((c.width - 20 * dpr) / layout.atlasW, (c.height - 20 * dpr) / layout.atlasH);
        const desiredScale = zoom === "fit" ? fitScale : Number(zoom) * dpr;
        const scale = Math.max(0.05 * dpr, desiredScale);
        const ox = Math.floor((c.width - layout.atlasW * scale) / 2);
        const oy = Math.floor((c.height - layout.atlasH * scale) / 2);
        setViewScale(scale);
        setViewOffset({ x: ox, y: oy });
        ctx.translate(ox, oy);
        ctx.scale(scale, scale);
        // 배경
        ctx.fillStyle = "#f7f9fb";
        ctx.fillRect(0, 0, layout.atlasW, layout.atlasH);
        // 그리드(얼굴 있는 셀만)
        ctx.strokeStyle = "#e6e6e6";
        ctx.lineWidth = 1 / scale;
        for (let r = 0; r < layout.nRows; r++) {
            for (let cidx = 0; cidx < layout.nCols; cidx++) {
                if (!layout.grid[r][cidx])
                    continue;
                const R = layout.cellRects[`c${cidx}r${r}`];
                ctx.strokeRect(R.x + 0.5, R.y + 0.5, R.w - 1, R.h - 1);
            }
        }
        // 1) 면 채움(아래)
        drawFaceFills(ctx, layout, ppmm);
        // 2) 패턴(흰/투명)
        const p = patternCanvasRef.current;
        if (p)
            ctx.drawImage(p, 0, 0);
        // 3) 브러쉬 마스크(흰/투명)
        const m = maskCanvasRef.current;
        if (m)
            ctx.drawImage(m, 0, 0);
        // 4) 경계/라벨(맨 위)
        drawSeamsAndLabels(ctx, layout, highlightFace);
        // 5) 힌지
        drawHinges(ctx, layout);
        // footer
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.fillStyle = "#444";
        ctx.font = `${12 * dpr}px sans-serif`;
        ctx.fillText(`Atlas: ${layout.atlasW}×${layout.atlasH}px  |  Scale: ${ppmm} px/mm  |  View: ${zoom === "fit" ? "Fit" : `${Math.round(Number(zoom) * 100)}%`}`, 8 * dpr, c.height - 8 * dpr);
    }
    // Drawing (paint/erase) in native space with screen mapping
    const isDrawingRef = useRef(false);
    function screenToAtlas(e) {
        const c = canvasRef.current;
        const rect = c.getBoundingClientRect();
        const sx = (e.clientX - rect.left) * (c.width / rect.width);
        const sy = (e.clientY - rect.top) * (c.height / rect.height);
        const ax = (sx - viewOffset.x) / viewScale;
        const ay = (sy - viewOffset.y) / viewScale;
        return { ax, ay };
    }
    function handlePointerDown(e) {
        // pattern 모드에선 브러쉬 비활성
        if (mode === "pattern") {
            // 클릭한 위치의 face 하이라이트/선택용
            const { ax, ay } = screenToAtlas(e);
            const face = Object.keys(layout.faceRects).find((f) => {
                const r = layout.faceRects[f];
                return ax >= r.x && ax <= r.x + r.w && ay >= r.y && ay <= r.y + r.h;
            });
            if (face) {
                setHighlightFace(face);
                setSelectedFaces([face]);
                redraw();
            }
            return;
        }
        isDrawingRef.current = true;
        e.target.setPointerCapture(e.pointerId);
        paintAt(e);
    }
    function handlePointerMove(e) {
        if (!isDrawingRef.current)
            return;
        if (mode === "pattern")
            return; // pattern 모드에서는 그리지 않음
        paintAt(e);
    }
    function handlePointerUp(e) {
        isDrawingRef.current = false;
        e.target.releasePointerCapture?.(e.pointerId);
    }
    function paintAt(e) {
        const m = maskCanvasRef.current;
        const img = imageDataRef.current;
        if (!m || !img)
            return;
        const mctx = m.getContext("2d");
        const { ax, ay } = screenToAtlas(e);
        // Only paint inside any face rect
        const face = Object.keys(layout.faceRects).find((f) => {
            const r = layout.faceRects[f];
            return ax >= r.x && ax <= r.x + r.w && ay >= r.y && ay <= r.y + r.h;
        });
        if (!face)
            return;
        const radiusPx = Math.max(1, Math.round(brushMM * ppmm));
        const paint = mode === "paint";
        drawCircleToImageData(img, ax, ay, radiusPx, paint);
        mctx.putImageData(img, 0, 0);
        setMaskVersion(v => v + 1);
        redraw();
    }
    // Pattern helpers
    function applyPatternToSelectedFaces() {
        const spec = {
            kind: patternKind,
            params: { lineMM, bandMM, borderMM, padMM, gapMM }
        };
        setPatterns(prev => {
            const next = { ...prev };
            selectedFaces.forEach(f => (next[f] = spec));
            return next;
        });
    }
    function clearPatternFromSelectedFaces() {
        setPatterns(prev => {
            const next = { ...prev };
            selectedFaces.forEach(f => (next[f] = null));
            return next;
        });
    }
    function clearAllPatterns() {
        setPatterns({});
    }
    function addWrapAround(axis) {
        const faces = axis === "Y" ? WRAP_Y : axis === "X" ? WRAP_X : WRAP_Z;
        const spec = { kind: patternKind, params: { lineMM, bandMM, borderMM, padMM, gapMM } };
        setPatterns(prev => {
            const next = { ...prev };
            faces.forEach(f => (next[f] = spec));
            return next;
        });
        setSelectedFaces(faces);
        setHighlightFace(null);
    }
    // Export PNG (pattern + brush 포함)
    function downloadPNG() {
        const m = maskCanvasRef.current;
        const p = patternCanvasRef.current;
        if (!m && !p)
            return;
        const exp = document.createElement("canvas");
        exp.width = layout.atlasW;
        exp.height = layout.atlasH;
        const ectx = exp.getContext("2d");
        ectx.fillStyle = "#000";
        ectx.fillRect(0, 0, exp.width, exp.height);
        if (p)
            ectx.drawImage(p, 0, 0);
        if (m)
            ectx.drawImage(m, 0, 0);
        const a = document.createElement("a");
        a.href = exp.toDataURL("image/png");
        a.download = `cuboid_net_${xMM}x${yMM}x${zMM}_pp${ppmm}.png`;
        a.click();
    }
    // Export JSON
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
        a.href = url;
        a.download = "cuboid_net_meta.json";
        a.click();
        URL.revokeObjectURL(url);
    }
    // Clear mask
    function clearAll(val = 0) {
        const m = maskCanvasRef.current;
        const img = imageDataRef.current;
        if (!m || !img)
            return;
        const d = img.data;
        if (val === 0) {
            for (let i = 0; i < d.length; i += 4) {
                d[i] = d[i + 1] = d[i + 2] = 0;
                d[i + 3] = 0;
            }
        }
        else {
            for (let i = 0; i < d.length; i += 4) {
                d[i] = d[i + 1] = d[i + 2] = 255;
                d[i + 3] = 255;
            }
        }
        const mctx = m.getContext("2d");
        mctx.putImageData(img, 0, 0);
        setMaskVersion(v => v + 1);
        redraw();
    }
    // Toolbar actions
    function setZoomFit() { setZoom("fit"); redraw(); }
    function setZoomPct(p) { setZoom(Math.max(0.1, p / 100)); redraw(); }
    const faceOptions = ["+X", "-X", "+Y", "-Y", "+Z", "-Z"].map(f => ({ label: f, value: f }));
    const patternOptions = [
        { value: "wrap-cross", label: "Wrap Cross (중앙 십자)" },
        { value: "band-h", label: "Band Horizontal (가로 띠)" },
        { value: "band-v", label: "Band Vertical (세로 띠)" },
        { value: "border-only", label: "Border Only (테두리)" },
        { value: "corner-pads", label: "Corner Pads (코너 패드)" },
    ];
    return (_jsxs("div", { style: { padding: 16, display: "flex", flexDirection: "column", gap: 12 }, children: [_jsx(Card, { size: "small", style: { borderRadius: 12 }, children: _jsxs(Row, { gutter: [12, 8], align: "middle", children: [_jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "X (mm)" }), _jsx(InputNumber, { value: xMM, min: 1, style: { width: "100%" }, onChange: (v) => setXMM(Number(v)) })] }), _jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "Y (mm)" }), _jsx(InputNumber, { value: yMM, min: 1, style: { width: "100%" }, onChange: (v) => setYMM(Number(v)) })] }), _jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "Z (mm)" }), _jsx(InputNumber, { value: zMM, min: 1, style: { width: "100%" }, onChange: (v) => setZMM(Number(v)) })] }), _jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "Scale (px/mm)" }), _jsx(InputNumber, { value: ppmm, min: 1, style: { width: "100%" }, onChange: (v) => setPPMM(Number(v)) })] }), _jsxs(Col, { xs: 24, sm: 12, md: 8, lg: 6, children: [_jsx(Text, { type: "secondary", children: "Net preset" }), _jsx(Select, { value: preset, style: { width: "100%" }, onChange: (v) => setPreset(v), options: ["Compact 3×2", "Vertical Cross 3×4", "Horizontal Cross 4×3", "Strip 6×1"]
                                        .map(p => ({ value: p, label: p })) })] }), _jsxs(Col, { xs: 12, sm: 12, md: 8, lg: 6, children: [_jsx(Text, { type: "secondary", children: "Mode" }), _jsx(Select, { value: mode, style: { width: "100%" }, onChange: (v) => setMode(v), options: [
                                        { value: "paint", label: "Paint (tape=white)" },
                                        { value: "erase", label: "Erase (transparent)" },
                                        { value: "pattern", label: "Pattern painter" },
                                    ] })] }), mode !== "pattern" && (_jsxs(Col, { xs: 12, sm: 12, md: 8, lg: 6, children: [_jsx(Text, { type: "secondary", children: "Brush (mm)" }), _jsx(Slider, { min: 0.5, max: Math.max(20, zMM), step: 0.5, value: brushMM, onChange: (v) => setBrushMM(Number(v)) })] })), _jsxs(Col, { xs: 24, md: 12, lg: 10, children: [_jsx(Text, { type: "secondary", children: "View" }), _jsxs(Space, { wrap: true, children: [_jsx(Button, { onClick: setZoomFit, children: "Fit" }), _jsx(Button, { onClick: () => setZoomPct(100), children: "100%" }), _jsx(Button, { onClick: () => setZoomPct(200), children: "200%" }), _jsx(Tooltip, { title: "Export mask (pattern + brush)", children: _jsx(Button, { type: "primary", onClick: downloadPNG, children: "Export PNG" }) }), _jsx(Button, { type: "primary", ghost: true, onClick: downloadJSON, children: "Export JSON" }), _jsx(Button, { onClick: () => clearAll(0), disabled: mode === "pattern", children: "Clear" }), _jsx(Button, { onClick: () => clearAll(255), disabled: mode === "pattern", children: "Fill" })] })] })] }) }), mode === "pattern" && (_jsx(Card, { size: "small", style: { borderRadius: 12 }, children: _jsxs(Row, { gutter: [12, 8], align: "middle", children: [_jsxs(Col, { xs: 24, md: 8, lg: 6, children: [_jsx(Text, { type: "secondary", children: "Faces" }), _jsx(Select, { mode: "multiple", value: selectedFaces, style: { width: "100%" }, onChange: (vals) => setSelectedFaces(vals), options: faceOptions, placeholder: "Select faces to apply" })] }), _jsxs(Col, { xs: 24, md: 8, lg: 6, children: [_jsx(Text, { type: "secondary", children: "Pattern" }), _jsx(Select, { value: patternKind, style: { width: "100%" }, onChange: (v) => setPatternKind(v), options: patternOptions })] }), _jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "Line (mm)" }), _jsx(InputNumber, { min: 0.5, value: lineMM, onChange: (v) => setLineMM(Number(v)), style: { width: "100%" } })] }), _jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "Band (mm)" }), _jsx(InputNumber, { min: 1, value: bandMM, onChange: (v) => setBandMM(Number(v)), style: { width: "100%" } })] }), _jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "Border (mm)" }), _jsx(InputNumber, { min: 0.5, value: borderMM, onChange: (v) => setBorderMM(Number(v)), style: { width: "100%" } })] }), _jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "Pad (mm)" }), _jsx(InputNumber, { min: 1, value: padMM, onChange: (v) => setPadMM(Number(v)), style: { width: "100%" } })] }), _jsxs(Col, { xs: 12, sm: 8, md: 6, lg: 4, children: [_jsx(Text, { type: "secondary", children: "Gap (mm)" }), _jsx(InputNumber, { min: 0, value: gapMM, onChange: (v) => setGapMM(Number(v)), style: { width: "100%" } })] }), _jsx(Col, { xs: 24, md: 24, lg: 24, children: _jsxs(Space, { wrap: true, children: [_jsx(Button, { type: "primary", onClick: applyPatternToSelectedFaces, children: "Apply to face(s)" }), _jsx(Button, { onClick: clearPatternFromSelectedFaces, children: "Clear selected faces" }), _jsx(Button, { danger: true, onClick: clearAllPatterns, children: "Clear all patterns" }), _jsx(Divider, { type: "vertical" }), _jsx(Button, { onClick: () => addWrapAround("Y"), children: "Add wrap around Y" }), _jsx(Button, { onClick: () => addWrapAround("X"), children: "Add wrap around X" }), _jsx(Button, { onClick: () => addWrapAround("Z"), children: "Add wrap around Z" })] }) })] }) })), _jsxs(Row, { gutter: 12, children: [_jsx(Col, { xs: 24, md: 18, children: _jsx(Card, { size: "small", style: { borderRadius: 12, height: "70vh" }, bodyStyle: { padding: 8, height: "100%" }, children: _jsx("div", { ref: containerRef, style: {
                                    position: "relative",
                                    width: "100%",
                                    height: "100%",
                                    overflow: "hidden",
                                    borderRadius: 8,
                                    background: "#f0f2f5",
                                    border: "1px solid #e5e7eb",
                                }, children: _jsx("canvas", { ref: canvasRef, style: { position: "absolute", inset: 0, width: "100%", height: "100%", cursor: mode === "pattern" ? "pointer" : "crosshair" }, onPointerDown: handlePointerDown, onPointerMove: handlePointerMove, onPointerUp: handlePointerUp, onPointerLeave: handlePointerUp }) }) }) }), _jsxs(Col, { xs: 24, md: 6, children: [_jsx(Card, { size: "small", title: "3D Preview", style: { borderRadius: 12, marginBottom: 12 }, children: _jsx(MiniCubePreview, { xMM: xMM, yMM: yMM, zMM: zMM, layout: layout, getMaskCanvas: () => maskCanvasRef.current, getPatternCanvas: () => patternCanvasRef.current, maskVersion: maskVersion }) }), _jsxs(Card, { size: "small", title: "Face Legend", style: { borderRadius: 12 }, children: [["+X", "-X", "+Y", "-Y", "+Z", "-Z"].map((f) => {
                                        const mm = faceSizeMM(f, xMM, yMM, zMM);
                                        const r = layout.faceRects[f];
                                        return (_jsxs("div", { style: { display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }, children: [_jsxs(Space, { children: [_jsx("span", { style: {
                                                                display: "inline-block", width: 16, height: 16,
                                                                background: FACE_COLOR[f],
                                                                border: "1px solid rgba(0,0,0,0.35)",
                                                                borderRadius: 3,
                                                                boxShadow: "0 0 0 1px rgba(255,255,255,0.6) inset"
                                                            } }), _jsx(Text, { strong: true, children: f })] }), _jsxs(Text, { type: "secondary", children: [mm.w, "\u00D7", mm.h, " mm ", r ? `(${r.w}×${r.h}px)` : ""] })] }, f));
                                    }), _jsx(Divider, {}), _jsxs(Space, { direction: "vertical", size: 2, children: [_jsx(Tag, { color: "geekblue", children: "Bold lines" }), _jsx(Text, { type: "secondary", children: "face seams" }), _jsx(Tag, { color: "default", children: "Dashed" }), _jsx(Text, { type: "secondary", children: "hinges between faces" })] })] })] })] })] }));
}
