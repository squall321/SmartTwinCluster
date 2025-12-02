import { CaseStatus } from '../types/simulationnetwork';
export declare const STATUS_COLORS: Record<CaseStatus, string>;
export declare const ALL_STATUSES: CaseStatus[];
export declare function getStatusColor(status: CaseStatus): string;
