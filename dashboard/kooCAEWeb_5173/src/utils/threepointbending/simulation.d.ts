import { BeamGeometry, LoadConfig, MaterialParams, DeformationModel, SimulationResult, AnalysisConditions } from "../../types/threepointbending";
export declare function runSimulation(geometry: BeamGeometry, loadCfg: LoadConfig, material: MaterialParams, deformation: DeformationModel, analysis: AnalysisConditions): SimulationResult;
