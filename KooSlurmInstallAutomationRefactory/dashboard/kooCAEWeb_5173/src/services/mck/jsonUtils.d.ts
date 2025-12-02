import { MCKSystem } from '../../types/mck/modelTypes';
export declare const saveSystemAsJSON: (system: MCKSystem) => void;
export declare const loadSystemFromJSON: (file: File, onLoad: (data: MCKSystem) => void) => void;
