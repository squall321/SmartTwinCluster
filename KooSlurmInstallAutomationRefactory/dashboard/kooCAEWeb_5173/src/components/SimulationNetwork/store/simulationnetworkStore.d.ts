import { SimulationNode, SimulationEdge, CaseStatus } from '../types/simulationnetwork';
interface SimulationNetworkState {
    nodes: SimulationNode[];
    edges: SimulationEdge[];
    selectedNode: SimulationNode | null;
    searchQuery: string;
    statusFilter: CaseStatus[];
    autoRefresh: boolean;
    nodeDetails: any | null;
    nodeLogs: string | null;
    nodeArtifacts: string[] | null;
    setNodes: (nodes: SimulationNode[], edges: SimulationEdge[]) => void;
    setSelectedNode: (node: SimulationNode | null) => void;
    setSearchQuery: (query: string) => void;
    setStatusFilter: (statuses: CaseStatus[]) => void;
    toggleAutoRefresh: () => void;
    setNodeDetails: (details: any) => void;
    setNodeLogs: (logs: string) => void;
    setNodeArtifacts: (artifacts: string[]) => void;
}
export declare const useSimulationNetworkStore: import("zustand").UseBoundStore<import("zustand").StoreApi<SimulationNetworkState>>;
export {};
