import { SimulationNode, SimulationEdge } from '../types/simulationnetwork';
export declare function getLayoutedElements(nodes: SimulationNode[], edges: SimulationEdge[], direction?: 'TB' | 'LR' | 'BT' | 'RL'): {
    nodes: {
        position: {
            x: number;
            y: number;
        };
        sourcePosition: "left" | "right" | "bottom" | "top";
        targetPosition: "left" | "right" | "bottom" | "top";
        id: string;
        label: string;
        path: string;
        status: import("../types/simulationnetwork").CaseStatus;
        kind: import("../types/simulationnetwork").CaseKind;
    }[];
    edges: SimulationEdge[];
};
export declare function centerGraph(nodes: {
    position: {
        x: number;
        y: number;
    };
}[]): {
    position: {
        x: number;
        y: number;
    };
}[];
export declare function getOptimalSpacing(nodeCount: number): {
    rankSep: number;
    nodeSep: number;
};
