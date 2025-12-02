// utils/simulationnetwork/layout.ts - Enhanced Version
import dagre from '@dagrejs/dagre';
import { SimulationNode, SimulationEdge } from '../types/simulationnetwork';

// 📐 Layout Configuration
const layoutConfig = {
  nodeWidth: 250,
  nodeHeight: 80,
  rankSep: 100, // Vertical spacing between ranks
  nodeSep: 80,  // Horizontal spacing between nodes
  edgeSep: 20,  // Spacing between edges
  marginX: 50,
  marginY: 50
};

// 🎯 Main layout function with enhanced algorithms
export function getLayoutedElements(
  nodes: SimulationNode[],
  edges: SimulationEdge[],
  direction: 'TB' | 'LR' | 'BT' | 'RL' = 'LR'
) {
  console.log('[Layout] Starting layout calculation:', { 
    nodes: nodes.length, 
    edges: edges.length, 
    direction 
  });

  if (nodes.length === 0) {
    return { nodes: [], edges: [] };
  }

  // Single node case
  if (nodes.length === 1) {
    return {
      nodes: [{
        ...nodes[0],
        position: { x: 0, y: 0 },
        sourcePosition: getSourcePosition(direction),
        targetPosition: getTargetPosition(direction)
      }],
      edges: []
    };
  }

  // Use different layout strategies based on graph characteristics
  const layoutStrategy = analyzeGraphStructure(nodes, edges);
  
  switch (layoutStrategy) {
    case 'hierarchical':
      return getHierarchicalLayout(nodes, edges, direction);
    case 'clustered':
      return getClusteredLayout(nodes, edges, direction);
    case 'force':
      return getForceDirectedLayout(nodes, edges, direction);
    default:
      return getDagreLayout(nodes, edges, direction);
  }
}

// 🔍 Analyze graph structure to choose optimal layout
function analyzeGraphStructure(nodes: SimulationNode[], edges: SimulationEdge[]): 'hierarchical' | 'clustered' | 'force' | 'dagre' {
  const nodeCount = nodes.length;
  const edgeCount = edges.length;
  const density = edgeCount / (nodeCount * (nodeCount - 1) / 2);
  
  // Check for hierarchical structure
  const inDegree = new Map<string, number>();
  const outDegree = new Map<string, number>();
  
  nodes.forEach(node => {
    inDegree.set(node.id, 0);
    outDegree.set(node.id, 0);
  });
  
  edges.forEach(edge => {
    inDegree.set(edge.target, (inDegree.get(edge.target) || 0) + 1);
    outDegree.set(edge.source, (outDegree.get(edge.source) || 0) + 1);
  });
  
  const rootNodes = Array.from(inDegree.entries()).filter(([_, degree]) => degree === 0).length;
  const leafNodes = Array.from(outDegree.entries()).filter(([_, degree]) => degree === 0).length;
  
  // Decision logic
  if (rootNodes > 0 && leafNodes > 0 && density < 0.3) {
    return 'hierarchical';
  } else if (nodeCount > 20 && density > 0.5) {
    return 'clustered';
  } else if (nodeCount > 50) {
    return 'force';
  } else {
    return 'dagre';
  }
}

// 🌳 Hierarchical Layout (Dagre-based)
function getDagreLayout(
  nodes: SimulationNode[], 
  edges: SimulationEdge[], 
  direction: 'TB' | 'LR' | 'BT' | 'RL'
) {
  const dagreGraph = new dagre.graphlib.Graph();
  dagreGraph.setDefaultEdgeLabel(() => ({}));
  
  dagreGraph.setGraph({ 
    rankdir: direction,
    ranksep: layoutConfig.rankSep,
    nodesep: layoutConfig.nodeSep,
    edgesep: layoutConfig.edgeSep,
    marginx: layoutConfig.marginX,
    marginy: layoutConfig.marginY
  });

  nodes.forEach((node) => {
    dagreGraph.setNode(node.id, { 
      width: layoutConfig.nodeWidth, 
      height: layoutConfig.nodeHeight 
    });
  });

  edges.forEach((edge) => {
    dagreGraph.setEdge(edge.source, edge.target);
  });

  dagre.layout(dagreGraph);

  const layoutedNodes = nodes.map((node) => {
    const nodeWithPosition = dagreGraph.node(node.id);
    return {
      ...node,
      position: { 
        x: nodeWithPosition.x - layoutConfig.nodeWidth / 2, 
        y: nodeWithPosition.y - layoutConfig.nodeHeight / 2 
      },
      sourcePosition: getSourcePosition(direction),
      targetPosition: getTargetPosition(direction)
    };
  });

  console.log('[Layout] Dagre layout completed');
  return { nodes: layoutedNodes, edges: [...edges] };
}

// 🏗️ Hierarchical Layout with custom logic
function getHierarchicalLayout(
  nodes: SimulationNode[], 
  edges: SimulationEdge[], 
  direction: 'TB' | 'LR' | 'BT' | 'RL'
) {
  // Build adjacency list
  const adjList = new Map<string, string[]>();
  const inDegree = new Map<string, number>();
  
  nodes.forEach(node => {
    adjList.set(node.id, []);
    inDegree.set(node.id, 0);
  });
  
  edges.forEach(edge => {
    adjList.get(edge.source)?.push(edge.target);
    inDegree.set(edge.target, (inDegree.get(edge.target) || 0) + 1);
  });
  
  // Topological sorting to determine levels
  const levels: string[][] = [];
  const queue: string[] = [];
  const visited = new Set<string>();
  
  // Find root nodes (no incoming edges)
  inDegree.forEach((degree, nodeId) => {
    if (degree === 0) {
      queue.push(nodeId);
    }
  });
  
  while (queue.length > 0) {
    const currentLevel: string[] = [];
    const levelSize = queue.length;
    
    for (let i = 0; i < levelSize; i++) {
      const nodeId = queue.shift()!;
      currentLevel.push(nodeId);
      visited.add(nodeId);
      
      // Add children to queue
      adjList.get(nodeId)?.forEach(childId => {
        const newInDegree = (inDegree.get(childId) || 0) - 1;
        inDegree.set(childId, newInDegree);
        if (newInDegree === 0 && !visited.has(childId)) {
          queue.push(childId);
        }
      });
    }
    
    if (currentLevel.length > 0) {
      levels.push(currentLevel);
    }
  }
  
  // Position nodes based on levels
  const isHorizontal = direction === 'LR' || direction === 'RL';
  const layoutedNodes = nodes.map(node => {
    const levelIndex = levels.findIndex(level => level.includes(node.id));
    const positionInLevel = levels[levelIndex]?.indexOf(node.id) || 0;
    const levelSize = levels[levelIndex]?.length || 1;
    
    let x, y;
    
    if (isHorizontal) {
      x = levelIndex * (layoutConfig.nodeWidth + layoutConfig.rankSep);
      y = (positionInLevel - (levelSize - 1) / 2) * (layoutConfig.nodeHeight + layoutConfig.nodeSep);
    } else {
      x = (positionInLevel - (levelSize - 1) / 2) * (layoutConfig.nodeWidth + layoutConfig.nodeSep);
      y = levelIndex * (layoutConfig.nodeHeight + layoutConfig.rankSep);
    }
    
    return {
      ...node,
      position: { x, y },
      sourcePosition: getSourcePosition(direction),
      targetPosition: getTargetPosition(direction)
    };
  });
  
  console.log('[Layout] Hierarchical layout completed with', levels.length, 'levels');
  return { nodes: layoutedNodes, edges: [...edges] };
}

// 🌐 Clustered Layout
function getClusteredLayout(
  nodes: SimulationNode[], 
  edges: SimulationEdge[], 
  direction: 'TB' | 'LR' | 'BT' | 'RL'
) {
  // Group nodes by status or kind
  const clusters = new Map<string, SimulationNode[]>();
  
  nodes.forEach(node => {
    const clusterKey = `${node.status}_${node.kind}`;
    if (!clusters.has(clusterKey)) {
      clusters.set(clusterKey, []);
    }
    clusters.get(clusterKey)!.push(node);
  });
  
  const clusterArray = Array.from(clusters.entries());
  const clustersPerRow = Math.ceil(Math.sqrt(clusterArray.length));
  
  const layoutedNodes = nodes.map(node => {
    const clusterKey = `${node.status}_${node.kind}`;
    const clusterIndex = clusterArray.findIndex(([key]) => key === clusterKey);
    const cluster = clusters.get(clusterKey)!;
    const nodeIndexInCluster = cluster.indexOf(node);
    
    const clusterRow = Math.floor(clusterIndex / clustersPerRow);
    const clusterCol = clusterIndex % clustersPerRow;
    
    const clusterCenterX = clusterCol * 400;
    const clusterCenterY = clusterRow * 300;
    
    const nodesPerRow = Math.ceil(Math.sqrt(cluster.length));
    const nodeRow = Math.floor(nodeIndexInCluster / nodesPerRow);
    const nodeCol = nodeIndexInCluster % nodesPerRow;
    
    const x = clusterCenterX + (nodeCol - nodesPerRow / 2) * (layoutConfig.nodeWidth + 20);
    const y = clusterCenterY + (nodeRow - Math.ceil(cluster.length / nodesPerRow) / 2) * (layoutConfig.nodeHeight + 20);
    
    return {
      ...node,
      position: { x, y },
      sourcePosition: getSourcePosition(direction),
      targetPosition: getTargetPosition(direction)
    };
  });
  
  console.log('[Layout] Clustered layout completed with', clusterArray.length, 'clusters');
  return { nodes: layoutedNodes, edges: [...edges] };
}

// 🎯 Force-directed Layout for large graphs
function getForceDirectedLayout(
  nodes: SimulationNode[], 
  edges: SimulationEdge[], 
  direction: 'TB' | 'LR' | 'BT' | 'RL'
) {
  // Simple force-directed simulation
  const positions = new Map<string, { x: number; y: number }>();
  
  // Initialize random positions
  nodes.forEach((node, index) => {
    const angle = (index / nodes.length) * 2 * Math.PI;
    const radius = Math.min(400, nodes.length * 20);
    positions.set(node.id, {
      x: Math.cos(angle) * radius,
      y: Math.sin(angle) * radius
    });
  });
  
  // Simple force simulation iterations
  for (let iteration = 0; iteration < 50; iteration++) {
    const forces = new Map<string, { x: number; y: number }>();
    
    // Initialize forces
    nodes.forEach(node => {
      forces.set(node.id, { x: 0, y: 0 });
    });
    
    // Repulsion forces between all nodes
    nodes.forEach(node1 => {
      nodes.forEach(node2 => {
        if (node1.id === node2.id) return;
        
        const pos1 = positions.get(node1.id)!;
        const pos2 = positions.get(node2.id)!;
        const dx = pos1.x - pos2.x;
        const dy = pos1.y - pos2.y;
        const distance = Math.max(Math.sqrt(dx * dx + dy * dy), 1);
        
        const repulsionForce = 10000 / (distance * distance);
        const force1 = forces.get(node1.id)!;
        force1.x += (dx / distance) * repulsionForce;
        force1.y += (dy / distance) * repulsionForce;
      });
    });
    
    // Attraction forces for connected nodes
    edges.forEach(edge => {
      const pos1 = positions.get(edge.source)!;
      const pos2 = positions.get(edge.target)!;
      const dx = pos2.x - pos1.x;
      const dy = pos2.y - pos1.y;
      const distance = Math.sqrt(dx * dx + dy * dy);
      
      const attractionForce = distance * 0.01;
      
      const force1 = forces.get(edge.source)!;
      const force2 = forces.get(edge.target)!;
      
      force1.x += (dx / distance) * attractionForce;
      force1.y += (dy / distance) * attractionForce;
      force2.x -= (dx / distance) * attractionForce;
      force2.y -= (dy / distance) * attractionForce;
    });
    
    // Apply forces with damping
    const damping = 0.9;
    nodes.forEach(node => {
      const pos = positions.get(node.id)!;
      const force = forces.get(node.id)!;
      
      pos.x += force.x * damping;
      pos.y += force.y * damping;
    });
  }
  
  const layoutedNodes = nodes.map(node => {
    const pos = positions.get(node.id)!;
    return {
      ...node,
      position: pos,
      sourcePosition: getSourcePosition(direction),
      targetPosition: getTargetPosition(direction)
    };
  });
  
  console.log('[Layout] Force-directed layout completed');
  return { nodes: layoutedNodes, edges: [...edges] };
}

// 🧭 Helper functions for position calculation
function getSourcePosition(direction: 'TB' | 'LR' | 'BT' | 'RL'): 'top' | 'right' | 'bottom' | 'left' {
  switch (direction) {
    case 'TB': return 'bottom';
    case 'BT': return 'top';
    case 'LR': return 'right';
    case 'RL': return 'left';
    default: return 'right';
  }
}

function getTargetPosition(direction: 'TB' | 'LR' | 'BT' | 'RL'): 'top' | 'right' | 'bottom' | 'left' {
  switch (direction) {
    case 'TB': return 'top';
    case 'BT': return 'bottom';
    case 'LR': return 'left';
    case 'RL': return 'right';
    default: return 'left';
  }
}

// 🎨 Additional layout utilities
export function centerGraph(nodes: { position: { x: number; y: number } }[]) {
  if (nodes.length === 0) return nodes;
  
  const bounds = nodes.reduce(
    (acc, node) => ({
      minX: Math.min(acc.minX, node.position.x),
      maxX: Math.max(acc.maxX, node.position.x),
      minY: Math.min(acc.minY, node.position.y),
      maxY: Math.max(acc.maxY, node.position.y)
    }),
    { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity }
  );
  
  const centerX = (bounds.minX + bounds.maxX) / 2;
  const centerY = (bounds.minY + bounds.maxY) / 2;
  
  return nodes.map(node => ({
    ...node,
    position: {
      x: node.position.x - centerX,
      y: node.position.y - centerY
    }
  }));
}

// 📏 Calculate optimal spacing based on node count
export function getOptimalSpacing(nodeCount: number) {
  if (nodeCount < 10) {
    return { rankSep: 150, nodeSep: 100 };
  } else if (nodeCount < 50) {
    return { rankSep: 120, nodeSep: 80 };
  } else {
    return { rankSep: 100, nodeSep: 60 };
  }
}
