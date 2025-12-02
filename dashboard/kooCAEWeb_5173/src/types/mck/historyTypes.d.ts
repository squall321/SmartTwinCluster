import { MCKSystem } from './modelTypes';
export interface SystemHistoryState {
    past: MCKSystem[];
    present: MCKSystem;
    future: MCKSystem[];
}
