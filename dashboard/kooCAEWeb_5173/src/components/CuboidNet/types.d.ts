export type Face = "+X" | "-X" | "+Y" | "-Y" | "+Z" | "-Z";
export type FaceCell = Face | null;
export type Rect = {
    x: number;
    y: number;
    w: number;
    h: number;
};
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
export declare const FACE_COLOR: Record<Face, string>;
export type NetPreset = "Compact 3×2" | "Vertical Cross 3×4" | "Horizontal Cross 4×3" | "Strip 6×1";
export declare const PRESETS: Record<NetPreset, FaceCell[][]>;
export type PatternKind = "diagWrapX" | "wrap-cross" | "band-h" | "band-v" | "border-only" | "corner-pads";
export type PatternOp = "paint" | "erase";
export type PatternFill = "inside" | "outside";
export type FacePattern = {
    id?: string;
    kind: PatternKind;
    params?: Record<string, number>;
    op?: PatternOp;
    fill?: PatternFill;
};
export type FacePatternMap = Partial<Record<Face, FacePattern[]>>;
