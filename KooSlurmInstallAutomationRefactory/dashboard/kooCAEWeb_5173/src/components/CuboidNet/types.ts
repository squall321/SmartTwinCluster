export type Face = "+X" | "-X" | "+Y" | "-Y" | "+Z" | "-Z";
export type FaceCell = Face | null;
export type Rect = { x: number; y: number; w: number; h: number };

export type NetLayout = {
  atlasW: number;
  atlasH: number;
  grid: FaceCell[][];
  cellRects: Record<string, Rect>;
  faceRects: Record<Face, Rect>;
  colW: number[];
  rowH: number[];
  colX: number[];
  rowY: number[];
  marginPx: number;
  nRows: number;
  nCols: number;
};

export type Mode = "paint" | "erase" | "pattern";

export const FACE_COLOR: Record<Face, string> = {
  "+X": "#1677FF",
  "-X": "#FA8C16",
  "+Y": "#52C41A",
  "-Y": "#13C2C2",
  "+Z": "#722ED1",
  "-Z": "#EB2F96",
};

export type NetPreset =
  | "Compact 3×2"
  | "Vertical Cross 3×4"
  | "Horizontal Cross 4×3"
  | "Strip 6×1";

export const PRESETS: Record<NetPreset, FaceCell[][]> = {
  "Compact 3×2": [
    ["+X", "-X", "+Y"],
    ["-Y", "+Z", "-Z"],
  ],
  "Vertical Cross 3×4": [
    [null, "+Y", null],
    ["-X", "+Z", "+X"],
    [null, "-Y", null],
    [null, "-Z", null],
  ],
  "Horizontal Cross 4×3": [
    [null, "+Y", null, null],
    ["-X", "+Z", "+X", "-Z"],
    [null, "-Y", null, null],
  ],
  "Strip 6×1": [["-X", "+Z", "+X", "-Z", "+Y", "-Y"]],
};

export type PatternKind =
  | "diagWrapX"
  | "wrap-cross"
  | "band-h"
  | "band-v"
  | "border-only"
  | "corner-pads";

export type PatternOp = "paint" | "erase";
export type PatternFill = "inside" | "outside";

// ✅ 개별 삭제를 위해 id 추가
export type FacePattern = {
  id?: string;
  kind: PatternKind;
  params?: Record<string, number>;
  op?: PatternOp;
  fill?: PatternFill;
};

// ✅ 면마다 여러 개 패턴을 쌓는 구조(레이어링)
export type FacePatternMap = Partial<Record<Face, FacePattern[]>>;
