import { MCKSystem } from '../../types/mck/modelTypes';
import { ModeResult, HarmonicResult, TransientResult } from "../../types/mck/simulationTypes";
import { TransientForce } from '../../types/mck/transientTypes';
export declare function modalAnalysis(system: MCKSystem, numModes: number): ModeResult;
export declare function harmonicResponse(system: MCKSystem, freqRange: [number, number], numPoints: number): HarmonicResult;
export declare function runTransientAnalysis(system: MCKSystem, forces: TransientForce[]): TransientResult;
export declare function transientResponse(system: MCKSystem, time: number[], forcesPerNode: Record<string, number[]>): TransientResult;
