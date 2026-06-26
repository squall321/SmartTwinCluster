// 초기 클러스터 더미 데이터
import { SlurmGroup } from '../types';

// 빈 초기 데이터 - API에서 실제 데이터를 로드할 때까지 사용
export const initializeGroups = (): SlurmGroup[] => {
  return [];
};

export const initialClusterData = {
  groups: [],
  totalNodes: 0,
  totalCores: 0,
  clusterName: 'HPC-Cluster',
  controllerIp: '127.0.0.1',
};
