import { MCKSystem } from "../../types/mck/modelTypes";
import { TransientForce } from "../../types/mck/transientTypes";
export interface TransientResult {
    time: number[];
    displacements: number[][];
}
export declare function runTransientAnalysis(system: MCKSystem, forces: TransientForce[]): TransientResult;
