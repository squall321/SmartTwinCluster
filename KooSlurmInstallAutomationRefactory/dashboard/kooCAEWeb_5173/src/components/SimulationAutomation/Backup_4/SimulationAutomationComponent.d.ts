import React from "react";
export type AnalysisType = "fullAngleMBD" | "fullAngle" | "fullAngleCumulative" | "partialImpact";
export type PartialImpactMode = "default" | "txt";
export type AngleSource = "lhs" | "fromMBD" | "usePrevResult";
export type HeightMode = "const" | "lhs";
export type SurfaceType = "steelPlate" | "pavingBlock" | "concrete" | "wood";
export type CumDirection = `F${1 | 2 | 3 | 4 | 5 | 6}` | `E${1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12}` | `C${1 | 2 | 3 | 4 | 5 | 6 | 7 | 8}`;
export type ToleranceMode = "disabled" | "enabled";
export type ToleranceSettings = {
    mode: ToleranceMode;
    faceTolerance?: number;
    edgeTolerance?: number;
    cornerTolerance?: number;
};
export interface ScenarioRow {
    id: string;
    name: string;
    fileName?: string;
    file?: File;
    objFileName?: string;
    objFile?: File;
    analysisType: AnalysisType;
    params?: {
        angleSource?: AngleSource;
        angleSourceId?: string;
        angleSourceFileName?: string;
        angleSourceFile?: File;
        heightMode?: HeightMode;
        heightConst?: number;
        heightMin?: number;
        heightMax?: number;
        surface?: SurfaceType;
        mbdCount?: number;
        faTotal?: number;
        includeFace6?: boolean;
        includeEdge12?: boolean;
        includeCorner8?: boolean;
        cumRepeatCount?: 2 | 3 | 4 | 5;
        cumDOECount?: number;
        cumDirections?: CumDirection[];
        cumDirectionsGrid?: CumDirection[][];
        piMode?: PartialImpactMode;
        piTxtName?: string;
        piTxtFile?: File;
        tolerance?: ToleranceSettings;
    };
}
declare const SimulationAutomationComponent: React.FC;
export default SimulationAutomationComponent;
