export interface SampleRow {
    theta: number;
    phi: number;
    gamma: number;
    stress: number;
}
export type AggKey = "mean" | "max" | "var" | "pexceed";
export interface ExecuteLikeOptions {
    mode?: "csv" | "sampleA" | "sampleB";
    data?: SampleRow[];
    csvText?: string;
    deg?: boolean;
    prefix?: string;
    nlat?: number;
    nlon?: number;
    topN?: number;
    suppress?: [number, number, number];
    lon0?: number;
    vmin?: number;
    vmax?: number;
    levels?: number;
    colorscale?: string;
    reverse?: boolean;
}
export default function MollweideStressPlot(props?: ExecuteLikeOptions): import("react/jsx-runtime").JSX.Element;
