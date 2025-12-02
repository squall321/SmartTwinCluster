import { Face, NetLayout } from "../types";
export declare function drawHinges(ctx: CanvasRenderingContext2D, layout: NetLayout): void;
export declare function drawFaceFills(ctx: CanvasRenderingContext2D, layout: NetLayout, ppmm: number): void;
export declare function drawSeamsAndLabels(ctx: CanvasRenderingContext2D, layout: NetLayout, highlight?: Face | null): void;
export declare function drawCircleToImageData(img: ImageData, cx: number, cy: number, radius: number, paint: boolean): void;
