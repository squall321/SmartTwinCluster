import { SystemHistoryState } from '../../types/mck/historyTypes';
import { MCKSystem } from '../../types/mck/modelTypes';
export declare const applyChange: (state: SystemHistoryState, newPresent: MCKSystem) => SystemHistoryState;
export declare const undo: (state: SystemHistoryState) => SystemHistoryState;
export declare const redo: (state: SystemHistoryState) => SystemHistoryState;
