import { PatternFill, PatternOp, PatternKind, Rect } from "../types";
export declare function drawPatternOnFace(ctx: CanvasRenderingContext2D, r: Rect, kind: PatternKind, params: Record<string, number>, ppmm: number, op?: PatternOp, fill?: PatternFill): void;
