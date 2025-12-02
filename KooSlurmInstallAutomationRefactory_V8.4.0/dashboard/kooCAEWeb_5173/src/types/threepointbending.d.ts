export type DeformationModel = "Small" | "Large";
export type MaterialModel = "LinearElastic" | "PowerLaw" | "RambergOsgood";
export interface LinearElasticParams {
    E: number;
}
export interface PowerLawParams {
    E: number;
    sigmaY: number;
    K: number;
    n: number;
}
export interface RambergOsgoodParams {
    E: number;
    sigma0: number;
    K: number;
    n: number;
}
export type MaterialParams = {
    model: "LinearElastic";
    params: LinearElasticParams;
} | {
    model: "PowerLaw";
    params: PowerLawParams;
} | {
    model: "RambergOsgood";
    params: RambergOsgoodParams;
};
export interface BeamGeometry {
    span: number;
    height: number;
    width: number;
}
export interface LoadConfig {
    maxLoad: number;
    step: number;
}
export type LoadType = "Point" | "UDL";
export type SupportCondition = "SimplySupported" | "Cantilever";
export interface AnalysisConditions {
    loadType: LoadType;
    loadPosition: number;
    integrationSteps: number;
    supportCondition: SupportCondition;
}
export interface DeformedShape {
    xPositions: number[];
    yPositions: number[];
}
export interface SimulationResult {
    loads: number[];
    deflections: number[];
    curvatures: number[];
    moments: number[];
    shapes: DeformedShape[];
}
