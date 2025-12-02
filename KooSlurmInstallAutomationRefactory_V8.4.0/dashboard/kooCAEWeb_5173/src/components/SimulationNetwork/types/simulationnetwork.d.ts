export type CaseStatus = 'Running' | 'Completed' | 'Failed' | 'Pending' | 'Cancelled';
export type CaseKind = 'DropSet' | 'DropImpactor';
export interface SimulationNode {
    id: string;
    label: string;
    path: string;
    status: CaseStatus;
    kind: CaseKind;
    position?: {
        x: number;
        y: number;
    };
    sourcePosition?: 'left' | 'right' | 'top' | 'bottom';
    targetPosition?: 'left' | 'right' | 'top' | 'bottom';
}
export interface SimulationEdge {
    id: string;
    source: string;
    target: string;
    label?: string;
}
