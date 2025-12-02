import { SlurmGroup, SlurmNode } from '../types';

// 370개 노드 초기화 (192.168.1.1부터 시작)
const initializeNodes = (): SlurmNode[] => {
  const nodes: SlurmNode[] = [];
  
  for (let i = 1; i <= 370; i++) {
    const ipSuffix = i;
    const ipThirdOctet = Math.floor((ipSuffix - 1) / 254) + 1;
    const ipFourthOctet = ((ipSuffix - 1) % 254) + 1;
    
    nodes.push({
      id: `node${String(i).padStart(3, '0')}`,
      hostname: `compute${String(i).padStart(3, '0')}`,
      ipAddress: `192.168.${ipThirdOctet}.${ipFourthOctet}`,
      cores: 128,
      memory: 512000, // 512GB
      state: 'idle',
      groupId: 0,
    });
  }
  
  return nodes;
};

// 초기 그룹 설정
export const initializeGroups = (): SlurmGroup[] => {
  const allNodes = initializeNodes();
  
  const groupConfigs = [
    { id: 1, name: 'Group 1', nodeCount: 64, allowedCoreSizes: [8192], color: '#3b82f6', description: 'Large scale jobs' },
    { id: 2, name: 'Group 2', nodeCount: 64, allowedCoreSizes: [1024], color: '#10b981', description: 'Medium jobs' },
    { id: 3, name: 'Group 3', nodeCount: 64, allowedCoreSizes: [1024], color: '#f59e0b', description: 'Medium jobs' },
    { id: 4, name: 'Group 4', nodeCount: 100, allowedCoreSizes: [128], color: '#ef4444', description: 'Small jobs' },
    { id: 5, name: 'Group 5', nodeCount: 14, allowedCoreSizes: [128], color: '#8b5cf6', description: 'Small jobs' },
    { id: 6, name: 'Group 6', nodeCount: 64, allowedCoreSizes: [8, 16, 32, 64], color: '#ec4899', description: 'Flexible jobs' },
  ];
  
  const groups: SlurmGroup[] = [];
  let nodeIndex = 0;
  
  for (const config of groupConfigs) {
    const groupNodes = allNodes.slice(nodeIndex, nodeIndex + config.nodeCount);
    
    groupNodes.forEach(node => {
      node.groupId = config.id;
    });
    
    groups.push({
      id: config.id,
      name: config.name,
      description: config.description,
      color: config.color,
      allowedCoreSizes: config.allowedCoreSizes,
      nodeCount: config.nodeCount,
      totalCores: groupNodes.reduce((sum, n) => sum + n.cores, 0),
      nodes: groupNodes,
      qosName: `group${config.id}_qos`,
      partitionName: `group${config.id}`,
    });
    
    nodeIndex += config.nodeCount;
  }
  
  return groups;
};

export const initialClusterData = {
  groups: initializeGroups(),
  totalNodes: 370,
  totalCores: initializeGroups().reduce((sum, g) => sum + g.totalCores, 0),
  clusterName: 'HPC-Cluster-370',
  controllerIp: '192.168.1.10',
};
