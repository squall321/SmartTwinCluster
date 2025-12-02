import { FACE_COLOR } from "../types";
export function drawHinges(ctx, layout) {
    const { grid, cellRects, nRows, nCols, marginPx } = layout;
    ctx.save();
    ctx.strokeStyle = "#666";
    ctx.setLineDash([5, 5]);
    ctx.lineWidth = 1.2;
    for (let r = 0; r < nRows; r++)
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
    for (let r = 0; r < nRows - 1; r++)
        for (let c = 0; c < nCols; c++) {
            const uf = grid[r][c], df = grid[r + 1][c];
            if (!uf || !df)
                continue;
            const U = cellRects[`c${c}r${r}`];
            const y = U.y + U.h + marginPx / 2;
            ctx.beginPath();
            ctx.moveTo(U.x, y + 0.5);
            ctx.lineTo(U.x + U.w, y + 0.5);
            ctx.stroke();
        }
    ctx.restore();
}
export function drawFaceFills(ctx, layout, ppmm) {
    Object.keys(layout.faceRects).forEach((f) => {
        const r = layout.faceRects[f];
        ctx.fillStyle = FACE_COLOR[f] + "B0";
        ctx.fillRect(r.x, r.y, r.w, r.h);
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
export function drawSeamsAndLabels(ctx, layout, highlight) {
    Object.keys(layout.faceRects).forEach((f) => {
        const r = layout.faceRects[f];
        if (highlight && f === highlight) {
            ctx.save();
            ctx.strokeStyle = "#1677ff";
            ctx.lineWidth = 3;
            ctx.setLineDash([6, 4]);
            ctx.strokeRect(r.x + 1.5, r.y + 1.5, r.w - 3, r.h - 3);
            ctx.restore();
        }
        ctx.strokeStyle = "#222";
        ctx.lineWidth = 2;
        ctx.setLineDash([]);
        ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
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
export function drawCircleToImageData(img, cx, cy, radius, paint) {
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
