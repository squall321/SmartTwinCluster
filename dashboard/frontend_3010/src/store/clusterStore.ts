// 클러스터 상태 zustand 스토어
import { create } from 'zustand';
import { SlurmGroup, SlurmNode, ClusterConfig } from '../types';
import { initialClusterData } from '../data/initialData';
import { apiPost, apiGet } from '../utils/api';

interface ClusterStore extends ClusterConfig {
  // 상태
  hasUnsavedChanges: boolean;
  isApplying: boolean;
  isLoading: boolean;
  configLoaded: boolean;

  // 액션
  moveNode: (nodeId: string, fromGroupId: number, toGroupId: number) => void;
  moveNodes: (nodeIds: string[], fromGroupId: number, toGroupId: number) => void;
  updateGroupConfig: (groupId: number, updates: Partial<SlurmGroup>) => void;
  addCoreSize: (groupId: number, coreSize: number) => void;
  removeCoreSize: (groupId: number, coreSize: number) => void;
  resetChanges: () => void;
  applyConfiguration: () => Promise<{ success: boolean; mode: string; message: string; details?: any; error?: string }>;
  setApplying: (isApplying: boolean) => void;

  // 🆕 그룹 관리 기능
  addGroup: () => void;
  removeGroup: (groupId: number) => void;

  // 🆕 저장/로드 기능
  exportConfiguration: () => string;
  importConfiguration: (jsonData: string) => boolean;
  downloadConfiguration: (filename?: string) => void;
  loadConfiguration: (config: ClusterConfig) => void;

  // 🆕 API에서 설정 로드
  fetchClusterConfig: () => Promise<void>;
}

export const useClusterStore = create<ClusterStore>((set, get) => ({
  // 초기 상태
  ...initialClusterData,
  hasUnsavedChanges: false,
  isApplying: false,
  isLoading: false,
  configLoaded: false,
  
  // 단일 노드 이동
  moveNode: (nodeId, fromGroupId, toGroupId) => {
    const { groups } = get();
    
    const fromGroup = groups.find(g => g.id === fromGroupId);
    const toGroup = groups.find(g => g.id === toGroupId);
    
    if (!fromGroup || !toGroup) return;
    
    const nodeIndex = fromGroup.nodes.findIndex(n => n.id === nodeId);
    if (nodeIndex === -1) return;
    
    const [node] = fromGroup.nodes.splice(nodeIndex, 1);
    node.groupId = toGroupId;
    toGroup.nodes.push(node);
    
    // 그룹 통계 업데이트 (실제 코어 수 기반)
    fromGroup.nodeCount = fromGroup.nodes.length;
    fromGroup.totalCores = fromGroup.nodes.reduce((sum, n) => sum + n.cores, 0);
    toGroup.nodeCount = toGroup.nodes.length;
    toGroup.totalCores = toGroup.nodes.reduce((sum, n) => sum + n.cores, 0);
    
    set({
      groups: [...groups],
      hasUnsavedChanges: true,
    });
  },
  
  // 다중 노드 이동
  moveNodes: (nodeIds, fromGroupId, toGroupId) => {
    const { groups } = get();
    
    const fromGroup = groups.find(g => g.id === fromGroupId);
    const toGroup = groups.find(g => g.id === toGroupId);
    
    if (!fromGroup || !toGroup) return;
    
    // 이동할 노드들 찾기
    const nodesToMove: SlurmNode[] = [];
    
    nodeIds.forEach(nodeId => {
      const nodeIndex = fromGroup.nodes.findIndex(n => n.id === nodeId);
      if (nodeIndex !== -1) {
        const [node] = fromGroup.nodes.splice(nodeIndex, 1);
        node.groupId = toGroupId;
        nodesToMove.push(node);
      }
    });
    
    // 대상 그룹에 추가
    toGroup.nodes.push(...nodesToMove);
    
    // 그룹 통계 업데이트 (실제 코어 수 기반)
    fromGroup.nodeCount = fromGroup.nodes.length;
    fromGroup.totalCores = fromGroup.nodes.reduce((sum, n) => sum + n.cores, 0);
    toGroup.nodeCount = toGroup.nodes.length;
    toGroup.totalCores = toGroup.nodes.reduce((sum, n) => sum + n.cores, 0);
    
    set({
      groups: [...groups],
      hasUnsavedChanges: true,
    });
  },
  
  // 그룹 설정 업데이트
  updateGroupConfig: (groupId, updates) => {
    const { groups } = get();
    
    const groupIndex = groups.findIndex(g => g.id === groupId);
    if (groupIndex === -1) return;
    
    // If name is being updated, also update partitionName to match
    if (updates.name) {
      // Sanitize: lowercase, remove spaces and special chars
      const sanitizedName = updates.name.toLowerCase().replace(/\s+/g, '').replace(/[^a-z0-9_-]/g, '');
      updates.partitionName = sanitizedName;
      
      // Also update QoS name to match
      updates.qosName = `${sanitizedName}_qos`;
    }
    
    groups[groupIndex] = {
      ...groups[groupIndex],
      ...updates,
    };
    
    set({
      groups: [...groups],
      hasUnsavedChanges: true,
    });
  },
  
  // 허용 코어 크기 추가
  addCoreSize: (groupId, coreSize) => {
    const { groups } = get();
    
    const group = groups.find(g => g.id === groupId);
    if (!group) return;
    
    if (!group.allowedCoreSizes.includes(coreSize)) {
      group.allowedCoreSizes.push(coreSize);
      group.allowedCoreSizes.sort((a, b) => a - b);
      
      set({
        groups: [...groups],
        hasUnsavedChanges: true,
      });
    }
  },
  
  // 허용 코어 크기 제거
  removeCoreSize: (groupId, coreSize) => {
    const { groups } = get();
    
    const group = groups.find(g => g.id === groupId);
    if (!group) return;
    
    group.allowedCoreSizes = group.allowedCoreSizes.filter(size => size !== coreSize);
    
    set({
      groups: [...groups],
      hasUnsavedChanges: true,
    });
  },
  
  // 변경사항 초기화 (API에서 다시 로드)
  resetChanges: () => {
    // Reset configLoaded flag to force re-fetch
    set({
      configLoaded: false,
      hasUnsavedChanges: false,
    });
    // Trigger re-fetch from API
    get().fetchClusterConfig();
  },
  
  // 설정 적용 (API 호출)
  applyConfiguration: async () => {
    set({ isApplying: true });
    
    try {
      const state = get();
      const { groups, clusterName, controllerIp, totalNodes, totalCores } = state;
      
      // 1. Slurm 설정 적용 (QoS + Partitions)
      console.log('🚀 Applying Slurm configuration...');
      const slurmResult = await apiPost<{
        success: boolean;
        mode: string;
        message: string;
        details?: any;
        error?: string;
      }>('/api/slurm/apply-config', { groups });
      
      console.log('Slurm apply result:', slurmResult);
      console.log('slurmResult.success:', slurmResult.success);
      console.log('slurmResult.error:', slurmResult.error);
      console.log('slurmResult.message:', slurmResult.message);
      console.log('Full response:', JSON.stringify(slurmResult, null, 2));
      
      if (!slurmResult.success) {
        throw new Error(slurmResult.error || slurmResult.message || 'Failed to apply Slurm configuration');
      }
      
      // 2. 클러스터 구성 저장 (DB에 저장)
      console.log('💾 Saving cluster configuration to DB...');
      const config: ClusterConfig = {
        groups: groups.map(g => ({
          id: g.id,
          name: g.name,
          description: g.description,
          color: g.color,
          partitionName: g.partitionName,
          qosName: g.qosName,
          allowedCoreSizes: g.allowedCoreSizes,
          nodeCount: g.nodeCount,
          totalCores: g.totalCores,
          nodes: []  // 노드 정보는 저장하지 않음 (너무 큼)
        })),
        clusterName,
        controllerIp,
        totalNodes,
        totalCores
      };
      
      const configResult = await apiPost<{
        success: boolean;
        mode: string;
        message: string;
      }>('/api/cluster/config', config);
      
      if (!configResult.success) {
        console.warn('Failed to save cluster config:', configResult.message);
        // 경고만 하고 계속 진행 (Slurm 설정은 적용됨)
      }
      
      set({
        hasUnsavedChanges: false,
        isApplying: false,
      });
      
      return slurmResult;
    } catch (error) {
      console.error('Apply configuration error:', error);
      set({ isApplying: false });
      throw error;
    }
  },
  
  setApplying: (isApplying) => {
    set({ isApplying });
  },
  
  // 🆕 그룹 추가
  addGroup: () => {
    const { groups } = get();
    const newId = groups.length > 0 ? Math.max(...groups.map(g => g.id)) + 1 : 1;
    
    const colors = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'];
    const color = colors[(newId - 1) % colors.length];
    
    const newGroup: SlurmGroup = {
      id: newId,
      name: `Group ${newId}`,
      description: 'New group - configure as needed',
      color: color,
      allowedCoreSizes: [128],
      nodeCount: 0,
      totalCores: 0,
      nodes: [],
      qosName: `group${newId}_qos`,
      partitionName: `group${newId}`,
    };
    
    set({
      groups: [...groups, newGroup],
      hasUnsavedChanges: true,
    });
  },
  
  // 🆕 그룹 제거
  removeGroup: (groupId) => {
    const { groups } = get();
    
    if (groups.length <= 1) {
      alert('Cannot remove the last group. At least one group must exist.');
      return;
    }
    
    const groupToRemove = groups.find(g => g.id === groupId);
    if (!groupToRemove) return;
    
    // If group has nodes, move them to the first remaining group
    if (groupToRemove.nodes.length > 0) {
      const firstGroup = groups.find(g => g.id !== groupId);
      if (firstGroup) {
        groupToRemove.nodes.forEach(node => {
          node.groupId = firstGroup.id;
        });
        firstGroup.nodes.push(...groupToRemove.nodes);
        firstGroup.nodeCount = firstGroup.nodes.length;
        firstGroup.totalCores = firstGroup.nodes.reduce((sum, n) => sum + n.cores, 0);
      }
    }
    
    // Remove the group
    const updatedGroups = groups.filter(g => g.id !== groupId);
    
    set({
      groups: updatedGroups,
      hasUnsavedChanges: true,
    });
  },
  
  // 🆕 설정 내보내기 (JSON 문자열 반환)
  exportConfiguration: () => {
    const state = get();
    const config: ClusterConfig = {
      groups: state.groups,
      totalNodes: state.totalNodes,
      totalCores: state.totalCores,
      clusterName: state.clusterName,
      controllerIp: state.controllerIp,
    };
    
    const exportData = {
      version: '2.0.0',
      exportedAt: new Date().toISOString(),
      config,
    };
    
    return JSON.stringify(exportData, null, 2);
  },
  
  // 🆕 설정 가져오기 (JSON 문자열 파싱)
  importConfiguration: (jsonData: string) => {
    try {
      const importData = JSON.parse(jsonData);
      
      // 버전 체크
      if (!importData.version || !importData.config) {
        throw new Error('Invalid configuration format');
      }
      
      const config = importData.config as ClusterConfig;
      
      // 기본 검증
      if (!config.groups || !Array.isArray(config.groups)) {
        throw new Error('Invalid groups data');
      }
      
      // 상태 업데이트
      set({
        ...config,
        hasUnsavedChanges: true,
      });
      
      return true;
    } catch (error) {
      console.error('Failed to import configuration:', error);
      return false;
    }
  },
  
  // 🆕 파일로 다운로드
  downloadConfiguration: (filename?: string) => {
    const jsonData = get().exportConfiguration();
    const blob = new Blob([jsonData], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const a = document.createElement('a');
    a.href = url;
    a.download = filename || `cluster-config-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  },
  
  // 🆕 설정 로드 (ClusterConfig 객체 직접 로드)
  loadConfiguration: (config: ClusterConfig) => {
    set({
      ...config,
      hasUnsavedChanges: true,
    });
  },

  // 🆕 API에서 클러스터 설정 로드
  fetchClusterConfig: async () => {
    const { configLoaded } = get();
    if (configLoaded) {
      console.log('[ClusterStore] Config already loaded, skipping fetch');
      return;
    }

    set({ isLoading: true });

    try {
      console.log('[ClusterStore] Fetching cluster config from API...');
      const response = await apiGet<{
        success: boolean;
        mode: string;
        config: ClusterConfig;
        note?: string;
      }>('/api/cluster/config');

      if (response.success && response.config) {
        console.log(`[ClusterStore] Loaded config: ${response.config.totalNodes} nodes, ${response.config.groups?.length || 0} groups (mode: ${response.mode})`);

        // Ensure nodes have id field for drag-drop functionality
        const groups = response.config.groups?.map(group => ({
          ...group,
          nodes: group.nodes?.map((node, idx) => ({
            ...node,
            id: node.id || `${group.partitionName}-${node.hostname || idx}`,
            groupId: group.id,
            cores: node.cpus || node.cores || 128
          })) || []
        })) || [];

        set({
          groups,
          clusterName: response.config.clusterName || 'HPC-Cluster',
          controllerIp: response.config.controllerIp || '127.0.0.1',
          totalNodes: response.config.totalNodes || groups.reduce((sum, g) => sum + (g.nodes?.length || 0), 0),
          totalCores: response.config.totalCores || groups.reduce((sum, g) => sum + (g.totalCores || 0), 0),
          isLoading: false,
          configLoaded: true,
          hasUnsavedChanges: false,
        });
      } else {
        console.warn('[ClusterStore] Failed to load config, using defaults');
        set({ isLoading: false, configLoaded: true });
      }
    } catch (error) {
      console.error('[ClusterStore] Error fetching cluster config:', error);
      set({ isLoading: false, configLoaded: true });
    }
  },
}));
