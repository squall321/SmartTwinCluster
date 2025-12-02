// store/simulationnetworkStore.ts
import { create } from 'zustand';
export const useSimulationNetworkStore = create((set) => ({
    nodes: [],
    edges: [],
    selectedNode: null,
    searchQuery: '',
    statusFilter: [],
    autoRefresh: false,
    nodeDetails: null,
    nodeLogs: null,
    nodeArtifacts: null,
    setNodes: (nodes, edges) => set((state) => {
        console.log('[Store] setNodes called with:', nodes.length, 'nodes and', edges.length, 'edges');
        let newSelectedNode = state.selectedNode;
        if (newSelectedNode) {
            const stillExists = nodes.find(n => n.id === newSelectedNode.id);
            if (!stillExists)
                newSelectedNode = null;
        }
        console.log('[Store] Updating state with new nodes/edges');
        return { nodes, edges, selectedNode: newSelectedNode };
    }),
    setSelectedNode: (node) => (set({
        selectedNode: node,
        nodeDetails: null,
        nodeLogs: null,
        nodeArtifacts: null
    })),
    setSearchQuery: (query) => set({ searchQuery: query }),
    setStatusFilter: (statuses) => set({ statusFilter: statuses }),
    toggleAutoRefresh: () => set((s) => ({ autoRefresh: !s.autoRefresh })),
    setNodeDetails: (details) => set({ nodeDetails: details }),
    setNodeLogs: (logs) => set({ nodeLogs: logs }),
    setNodeArtifacts: (artifacts) => set({ nodeArtifacts: artifacts })
}));
