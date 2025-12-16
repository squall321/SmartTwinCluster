import { NetLayout } from "./types";
type Props = {
    xMM: number;
    yMM: number;
    zMM: number;
    layout: NetLayout;
    getMaskCanvas: () => HTMLCanvasElement | null;
    getPatternCanvas: () => HTMLCanvasElement | null;
    version: number;
};
export default function MiniCubePreview({ xMM, yMM, zMM, layout, getMaskCanvas, getPatternCanvas, version }: Props): import("react/jsx-runtime").JSX.Element;
export {};
