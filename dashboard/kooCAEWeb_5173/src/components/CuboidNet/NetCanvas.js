import { jsx as _jsx } from "react/jsx-runtime";
import { useEffect, useRef, useState } from "react";
import { drawFaceFills, drawHinges, drawSeamsAndLabels, drawCircleToImageData } from "./utils/draw";
export default function NetCanvas({ layout, ppmm, mode, brushMM, zoom, maskCanvasRef, patternCanvasRef, imageDataRef, maskVersion, highlightFace, onFaceClick, footerText, style, onMaskEdited }) {
    const containerRef = useRef(null);
    const canvasRef = useRef(null);
    const [viewScale, setViewScale] = useState(1);
    const [viewOffset, setViewOffset] = useState({ x: 0, y: 0 });
    const isDrawingRef = useRef(false);
    const lastAtlasPosRef = useRef(null);
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
            draw();
        }
        const ro = new ResizeObserver(resize);
        if (containerRef.current)
            ro.observe(containerRef.current);
        window.addEventListener("resize", resize);
        resize();
        return () => { ro.disconnect(); window.removeEventListener("resize", resize); };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);
    useEffect(() => { draw(); /* eslint-disable-next-line */ }, [layout, ppmm, zoom, maskVersion, highlightFace]);
    function draw() {
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
        ctx.fillStyle = "#f7f9fb";
        ctx.fillRect(0, 0, layout.atlasW, layout.atlasH);
        ctx.strokeStyle = "#e6e6e6";
        ctx.lineWidth = 1 / scale;
        for (let r = 0; r < layout.nRows; r++)
            for (let cidx = 0; cidx < layout.nCols; cidx++) {
                if (!layout.grid[r][cidx])
                    continue;
                const R = layout.cellRects[`c${cidx}r${r}`];
                ctx.strokeRect(R.x + 0.5, R.y + 0.5, R.w - 1, R.h - 1);
            }
        drawFaceFills(ctx, layout, ppmm);
        const p = patternCanvasRef.current;
        if (p)
            ctx.drawImage(p, 0, 0);
        const m = maskCanvasRef.current;
        if (m)
            ctx.drawImage(m, 0, 0);
        drawSeamsAndLabels(ctx, layout, highlightFace);
        drawHinges(ctx, layout);
        if (footerText) {
            ctx.setTransform(1, 0, 0, 1, 0, 0);
            ctx.fillStyle = "#444";
            ctx.font = `${12 * dpr}px sans-serif`;
            ctx.fillText(footerText, 8 * dpr, c.height - 8 * dpr);
        }
    }
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
        e.preventDefault(); // 모바일/터치 스크롤 방지
        if (mode === "pattern") {
            const { ax, ay } = screenToAtlas(e);
            const face = Object.keys(layout.faceRects).find((f) => {
                const r = layout.faceRects[f];
                return ax >= r.x && ax <= r.x + r.w && ay >= r.y && ay <= r.y + r.h;
            });
            if (face)
                onFaceClick(face);
            return;
        }
        isDrawingRef.current = true;
        e.target.setPointerCapture(e.pointerId);
        lastAtlasPosRef.current = null;
        paintAt(e);
    }
    function handlePointerMove(e) {
        if (!isDrawingRef.current || mode === "pattern")
            return;
        e.preventDefault(); // 터치 드래그 중 스크롤 방지
        paintAt(e);
    }
    function handlePointerUp(e) {
        isDrawingRef.current = false;
        lastAtlasPosRef.current = null;
        e.target.releasePointerCapture?.(e.pointerId);
    }
    // 안전: 포인터 캔슬 시에도 종료
    function handlePointerCancel(e) {
        isDrawingRef.current = false;
        lastAtlasPosRef.current = null;
        e.target.releasePointerCapture?.(e.pointerId);
    }
    function paintAt(e) {
        const m = maskCanvasRef.current;
        const img = imageDataRef.current;
        if (!m || !img)
            return;
        const mctx = m.getContext("2d");
        const { ax, ay } = screenToAtlas(e);
        // 얼굴 내부만 허용
        const face = Object.keys(layout.faceRects).find((f) => {
            const r = layout.faceRects[f];
            return ax >= r.x && ax <= r.x + r.w && ay >= r.y && ay <= r.y + r.h;
        });
        if (!face) {
            lastAtlasPosRef.current = null;
            return;
        }
        const radiusPx = Math.max(1, Math.round(brushMM * ppmm));
        const paint = mode === "paint";
        // 선 보정: 이전점~현재점 보간
        const prev = lastAtlasPosRef.current;
        if (!prev) {
            drawCircleToImageData(img, ax, ay, radiusPx, paint);
        }
        else {
            const dx = ax - prev.ax, dy = ay - prev.ay;
            const dist = Math.hypot(dx, dy);
            const step = Math.max(1, Math.floor(dist / (radiusPx * 0.5)));
            for (let i = 1; i <= step; i++) {
                const t = i / step;
                const sx = prev.ax + dx * t;
                const sy = prev.ay + dy * t;
                drawCircleToImageData(img, sx, sy, radiusPx, paint);
            }
        }
        lastAtlasPosRef.current = { ax, ay };
        // 반영 + 즉시 전개도 redraw + 부모 알림
        mctx.putImageData(img, 0, 0);
        draw();
        // ✅ 옵션 체이닝 대신 가드 호출 (빨간 줄 방지)
        if (onMaskEdited)
            onMaskEdited();
    }
    return (_jsx("div", { ref: containerRef, style: { position: "relative", width: "100%", height: "100%", ...style }, onContextMenu: (e) => e.preventDefault(), children: _jsx("canvas", { ref: canvasRef, style: { position: "absolute", inset: 0, width: "100%", height: "100%", cursor: mode === "pattern" ? "pointer" : "crosshair" }, onPointerDown: handlePointerDown, onPointerMove: handlePointerMove, onPointerUp: handlePointerUp, onPointerLeave: handlePointerUp, onPointerCancel: handlePointerCancel }) }));
}
