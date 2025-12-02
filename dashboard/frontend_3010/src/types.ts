// Slurm 노드 타입 정의
export interface SlurmNode {
  id: string;
  hostname: string;
  ipAddress: string;
  cores: number;
  memory: number; // MB
  state: 'idle' | 'allocated' | 'mixed' | 'down';
  groupId: number;
}

// Slurm 그룹 타입 정의
export interface SlurmGroup {
  id: number;
  name: string;
  description: string;
  color: string;
  allowedCoreSizes: number[]; // 허용된 코어 수 목록
  nodeCount: number;
  totalCores: number;
  nodes: SlurmNode[];
  qosName: string;
  partitionName: string;
}

// QoS 설정
export interface QoSConfig {
  name: string;
  maxTRESPerJob: string; // e.g., "cpu=8192"
  maxJobsPerUser: number;
  maxWall: string; // e.g., "7-00:00:00"
  priority: number;
}

// 파티션 설정
export interface PartitionConfig {
  name: string;
  nodes: string; // e.g., "node[001-064]"
  maxNodes: number;
  state: string;
  allowQOS: string;
}

// 클러스터 전체 설정
export interface ClusterConfig {
  groups: SlurmGroup[];
  totalNodes: number;
  totalCores: number;
  clusterName: string;
  controllerIp: string;
}

// API 응답 타입
export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

// 노드 이동 요청
export interface MoveNodeRequest {
  nodeId: string;
  fromGroupId: number;
  toGroupId: number;
}

// 그룹 설정 업데이트 요청
export interface UpdateGroupRequest {
  groupId: number;
  name?: string;
  description?: string;
  allowedCoreSizes?: number[];
  color?: string;
}

// Slurm 적용 요청
export interface ApplySlurmConfigRequest {
  groups: SlurmGroup[];
  dryRun?: boolean;
}

// 통계 데이터
export interface ClusterStats {
  totalJobs: number;
  runningJobs: number;
  pendingJobs: number;
  totalCpuUsage: number;
  groupStats: GroupStats[];
}

export interface GroupStats {
  groupId: number;
  groupName: string;
  jobCount: number;
  cpuUsage: number;
  nodeUtilization: number;
}

// 작업 정보 (확장)
export interface SlurmJob {
  jobId: string;
  userId: string;
  jobName: string;
  partition: string;
  qos: string;
  state: 'PENDING' | 'RUNNING' | 'COMPLETED' | 'FAILED' | 'CANCELLED' | 'TIMEOUT';
  nodes: number;
  cpus: number;
  memory?: string;
  startTime?: string;
  endTime?: string;
  runTime?: string;
  priority?: number;
  account?: string;
  workDir?: string;
  stdOut?: string;
  stdErr?: string;
}

// 실시간 모니터링 데이터
export interface RealtimeMetrics {
  timestamp: string;
  cpuUsage: number;        // 0-100
  memoryUsage: number;     // 0-100
  gpuUsage?: number;       // 0-100
  activeJobs: number;
  pendingJobs: number;
  totalNodes: number;
  idleNodes: number;
  allocatedNodes: number;
  downNodes: number;
}

// 시계열 데이터
export interface TimeSeriesData {
  timestamp: string;
  value: number;
  label?: string;
}

// 노드 상세 정보
export interface NodeDetails extends SlurmNode {
  cpuUsage: number;
  memoryUsage: number;
  gpuUsage?: number;
  temperature?: number;
  uptime: string;
  jobs: string[];  // Job IDs
  features?: string[];
  gres?: string;
  weight?: number;
}

// 작업 제출 요청
export interface JobSubmitRequest {
  jobName: string;
  partition: string;
  nodes: number;
  cpus?: number;
  memory?: string;
  time?: string;
  account?: string;
  qos?: string;
  script: string;
  workDir?: string;
}

// 작업 템플릿
export interface JobTemplate {
  id: string;
  name: string;
  description: string;
  partition: string;
  nodes: number;
  cpus: number;
  memory: string;
  time: string;
  script: string;
  category: 'cpu' | 'gpu' | 'memory' | 'io' | 'custom';
}

// 알림
export interface Notification {
  id: string;
  type: 'info' | 'warning' | 'error' | 'success';
  title: string;
  message: string;
  timestamp: string;
  read: boolean;
  actionUrl?: string;
}

// 3D 시각화용 노드 위치
export interface NodePosition {
  nodeId: string;
  x: number;
  y: number;
  z: number;
  groupId: number;
}

// ==================== Storage Management Types ====================

export interface StorageStats {
  totalCapacity: string;
  usedSpace: string;
  availableSpace: string;
  usagePercent: number;
  datasetCount: number;
  fileCount: number;
  lastAnalysis: string;
}

export interface Dataset {
  id: string;
  name: string;
  path: string;
  size: string;
  sizeBytes: number;
  fileCount: number;
  createdAt: string;
  lastAccessed: string;
  owner: string;
  group?: string;
  status: 'active' | 'archived' | 'processing';
  tags?: string[];
}

export interface NodeScratchData {
  nodeId: string;
  nodeName: string;
  totalSpace: string;
  totalSpaceBytes: number;
  usedSpace: string;
  usedSpaceBytes: number;
  availableSpace: string;
  availableSpaceBytes: number;
  usagePercent: number;
  fileCount: number;
  directories: ScratchDirectory[];
  status: 'online' | 'offline' | 'maintenance';
  lastUpdated?: string;
}

export interface ScratchDirectory {
  id: string;
  name: string;
  path: string;
  size: string;
  sizeBytes: number;
  fileCount: number;
  createdAt: string;
  owner: string;
  group?: string;
  jobId?: string;
  lastModified?: string;
}

export interface FileItem {
  id: string;
  name: string;
  path: string;
  type: 'file' | 'directory';
  size: string;
  sizeBytes: number;
  permissions: string;
  owner: string;
  group: string;
  modifiedAt: string;
  isSymlink?: boolean;
  mimeType?: string;
  extension?: string;
}

export interface BreadcrumbItem {
  name: string;
  path: string;
}

export interface TransferTask {
  id: string;
  type: 'move' | 'copy' | 'delete' | 'upload' | 'download';
  source: string;
  destination?: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  progress: number;
  speed?: string;
  eta?: string;
  startTime?: string;
  endTime?: string;
  error?: string;
  fileCount?: number;
  totalSize?: string;
}

export interface QuotaInfo {
  user: string;
  path: string;
  used: string;
  usedBytes: number;
  limit: string;
  limitBytes: number;
  usagePercent: number;
  fileCount: number;
  fileLimit: number;
  fileUsagePercent: number;
}

export interface StorageAnalytics {
  fileTypeDistribution: {
    type: string;
    count: number;
    size: string;
    sizeBytes: number;
    percent: number;
  }[];
  topUsers: {
    user: string;
    size: string;
    sizeBytes: number;
    fileCount: number;
    percent: number;
  }[];
  usageTrend: {
    date: string;
    used: number;
    percent: number;
  }[];
  largestDirectories: {
    path: string;
    size: string;
    sizeBytes: number;
    fileCount: number;
  }[];
}

export interface FilePreview {
  path: string;
  type: 'text' | 'image' | 'pdf' | 'csv' | 'json' | 'binary';
  content?: string;
  imageUrl?: string;
  lines?: number;
  encoding?: string;
  error?: string;
}

export type SortField = 'name' | 'size' | 'modified' | 'owner' | 'type';
export type SortDirection = 'asc' | 'desc';

export interface FileFilter {
  search: string;
  type?: 'all' | 'file' | 'directory';
  owner?: string;
  minSize?: number;
  maxSize?: number;
  modifiedAfter?: string;
  modifiedBefore?: string;
}
