import { Face, FaceCell, NetLayout, Rect } from "../types";

export function faceSizeMM(face: Face, xMM: number, yMM: number, zMM: number) {
  switch (face) {
    case "+X":
    case "-X": return { w: zMM, h: yMM };
    case "+Y":
    case "-Y": return { w: xMM, h: zMM };
    case "+Z":
    case "-Z": return { w: xMM, h: yMM };
  }
}

export function buildLayout(
  xMM: number,
  yMM: number,
  zMM: number,
  ppmm: number,
  marginPx: number,
  grid: FaceCell[][]
): NetLayout {
  const faces: Face[] = ["+X","-X","+Y","-Y","+Z","-Z"];
  const facePx = Object.fromEntries(
    faces.map(f => {
      const s = faceSizeMM(f, xMM, yMM, zMM);
      return [f, { w: Math.max(1, Math.round(s.w * ppmm)), h: Math.max(1, Math.round(s.h * ppmm)) }];
    })
  ) as Record<Face, {w:number;h:number}>;

  const nRows = grid.length;
  const nCols = grid.reduce((m, r) => Math.max(m, r.length), 0);
  const colW = Array.from({ length: nCols }, () => 0);
  const rowH = Array.from({ length: nRows }, () => 0);

  for (let r = 0; r < nRows; r++) for (let c = 0; c < nCols; c++) {
    const f = grid[r][c];
    if (!f) continue;
    colW[c] = Math.max(colW[c], facePx[f].w);
    rowH[r] = Math.max(rowH[r], facePx[f].h);
  }

  const colX = Array.from({ length: nCols }, (_, c) =>
    marginPx + colW.slice(0, c).reduce((a, b) => a + b, 0) + marginPx * c
  );
  const rowY = Array.from({ length: nRows }, (_, r) =>
    marginPx + rowH.slice(0, r).reduce((a, b) => a + b, 0) + marginPx * r
  );

  const atlasW = colW.reduce((a, b) => a + b, 0) + marginPx * (nCols + 1);
  const atlasH = rowH.reduce((a, b) => a + b, 0) + marginPx * (nRows + 1);

  const cellRects: Record<string, Rect> = {};
  const faceRects = {} as Record<Face, Rect>;

  for (let r = 0; r < nRows; r++) for (let c = 0; c < nCols; c++) {
    const key = `c${c}r${r}`;
    const w = colW[c], h = rowH[r], x = colX[c], y = rowY[r];
    cellRects[key] = { x, y, w, h };
    const f = grid[r][c];
    if (f) {
      const W = facePx[f].w, H = facePx[f].h;
      faceRects[f] = { x: x + Math.floor((w - W) / 2), y: y + Math.floor((h - H) / 2), w: W, h: H };
    }
  }

  return { atlasW, atlasH, grid, cellRects, faceRects, colW, rowH, colX, rowY, marginPx, nRows, nCols };
}
