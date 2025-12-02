import { Face, FaceCell, NetLayout } from "../types";
export declare function faceSizeMM(face: Face, xMM: number, yMM: number, zMM: number): {
    w: number;
    h: number;
};
export declare function buildLayout(xMM: number, yMM: number, zMM: number, ppmm: number, marginPx: number, grid: FaceCell[][]): NetLayout;
