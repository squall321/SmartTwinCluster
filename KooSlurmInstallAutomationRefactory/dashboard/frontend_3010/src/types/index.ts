/**
 * 공통 타입 정의
 * Dashboard 전체에서 사용하는 공통 타입들
 */

// ============================================================================
// API Response Types
// ============================================================================

export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
  mode?: 'mock' | 'production';
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

// ============================================================================
// Mode Types
// ============================================================================

export type Mode = 'mock' | 'production';

export type Theme = 'light' | 'dark' | 'system';

// ============================================================================
// Job Types
// ============================================================================

export type JobState = 
  | 'PENDING' 
  | 'RUNNING' 
  | 'COMPLETED' 
  | 'FAILED' 
  | 'CANCELLED' 
  | 'TIMEOUT'
  | 'NODE_FAIL';

// Slurm Job (for JobManagement)
export interface SlurmJob {
  jobId: string;
  userId: string;
  jobName: string;
  partition: string;
  qos: string;
  state: JobState;
  nodes: number;
  cpus: number;
  memory: string;
  startTime: string;
  runTime?: string;
  priority: number;
  account: string;
  gpus?: number;
}

// Uploaded File
export interface UploadedFile {
  id: string;
  name: string;
  size: number;
  path: string;
  uploadTime: string;
  status: 'uploading' | 'uploaded' | 'error';
  progress?: number;
  variableName?: string;
}

// Job Submit Request
export interface JobSubmitRequest {
  jobName: string;
  partition: string;
  nodes: number;
  cpus: number;
  memory: string;
  time: string;
  script: string;
  gpus?: number;
  qos?: string;
  account?: string;
  files?: UploadedFile[];
}

// Job Template (legacy support)
export interface JobTemplate extends Template {}

// Generic Job interface
export interface Job {
  id: string;
  name: string;
  user: string;
  state: JobState;
  partition: string;
  nodes: number;
  cpus: number;
  gpus?: number;
  memory: string;
  timeLimit: string;
  timeElapsed?: string;
  qos: string;
  submitTime: string;
  startTime?: string;
  endTime?: string;
  exitCode?: number;
  stdout?: string;
  stderr?: string;
}

export interface JobStats {
  total: number;
  pending: number;
  running: number;
  completed: number;
  failed: number;
}

// ============================================================================
// Node Types
// ============================================================================

export type NodeState = 
  | 'IDLE' 
  | 'ALLOCATED' 
  | 'MIXED' 
  | 'DOWN' 
  | 'DRAIN' 
  | 'DRAINING'
  | 'RESERVED';

export interface Node {
  id: string;
  name: string;
  state: NodeState;
  partition: string;
  cpus: number;
  cpusAllocated: number;
  memory: number;
  memoryAllocated: number;
  gpus?: number;
  gpusAllocated?: number;
  features?: string[];
  reason?: string;
}

export interface NodeStats {
  total: number;
  idle: number;
  allocated: number;
  mixed: number;
  down: number;
}

// ============================================================================
// Storage Types
// ============================================================================

export interface Storage {
  id: string;
  name: string;
  path: string;
  total: number;
  used: number;
  available: number;
  usage: number; // percentage
  type: 'nfs' | 'local' | 'lustre' | 'gpfs';
}

// ============================================================================
// Metrics Types
// ============================================================================

export interface Metric {
  timestamp: number;
  value: number;
}

export interface MetricSeries {
  name: string;
  data: Metric[];
  unit?: string;
}

export interface SystemMetrics {
  cpu: {
    usage: number;
    cores: number;
    allocated: number;
  };
  memory: {
    total: number;
    used: number;
    available: number;
    usage: number;
  };
  gpu?: {
    total: number;
    used: number;
    available: number;
    usage: number;
  };
}

// ============================================================================
// Notification Types
// ============================================================================

export type NotificationSeverity = 'info' | 'warning' | 'error' | 'success';

export interface Notification {
  id: string;
  title: string;
  message: string;
  severity: NotificationSeverity;
  timestamp: string;
  read: boolean;
  source?: string;
  jobId?: string;
  nodeId?: string;
}

// ============================================================================
// Template Types
// ============================================================================

export type TemplateCategory = 
  | 'ml' 
  | 'data' 
  | 'simulation' 
  | 'compute' 
  | 'container' 
  | 'custom';

export interface TemplateConfig {
  partition: string;
  nodes: number;
  cpus: number;
  memory: string;
  time: string;
  gpu?: number;
  script: string;
  [key: string]: any;
}

export interface Template {
  id: string;
  name: string;
  description: string;
  category: TemplateCategory;
  shared: boolean;
  config: TemplateConfig;
  created_by: string;
  created_at: string;
  updated_at: string;
  usage_count: number;
  tags?: string[];
}

export interface Category {
  name: string;
  label: string;
  description?: string;
  icon: string;
  color: string;
  count?: number;
}

// ============================================================================
// Dashboard Widget Types
// ============================================================================

export type WidgetType = 
  | 'cpu' 
  | 'memory' 
  | 'gpu' 
  | 'jobQueue' 
  | 'recentJobs' 
  | 'nodeStatus' 
  | 'storage' 
  | 'alerts';

export type WidgetSize = 'small' | 'medium' | 'large';

export interface WidgetLayout {
  i: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface Widget {
  id: string;
  type: WidgetType;
  title: string;
  size: WidgetSize;
  layout: WidgetLayout;
  config?: Record<string, any>;
}

// ============================================================================
// User Types
// ============================================================================

export interface User {
  id: string;
  username: string;
  email?: string;
  role: 'admin' | 'user' | 'guest';
  groups?: string[];
  createdAt: string;
}

// ============================================================================
// Cluster Configuration Types
// ============================================================================

export interface Partition {
  name: string;
  nodes: string[];
  state: 'UP' | 'DOWN' | 'DRAIN';
  maxTime: string;
  defaultTime: string;
  maxNodes: number;
  allowedAccounts?: string[];
}

export interface QoS {
  name: string;
  priority: number;
  maxJobsPerUser: number;
  maxSubmitJobsPerUser: number;
  maxTRESPerUser?: Record<string, number>;
}

export interface ClusterConfig {
  name: string;
  partitions: Partition[];
  qos: QoS[];
  nodes: Node[];
}

// ============================================================================
// Search Types
// ============================================================================

export type SearchScope = 'jobs' | 'nodes' | 'templates' | 'files' | 'all';

export interface SearchResult {
  id: string;
  type: SearchScope;
  title: string;
  description: string;
  metadata?: Record<string, any>;
  score?: number;
}

// ============================================================================
// Prometheus Types
// ============================================================================

export interface PrometheusQuery {
  query: string;
  start?: number;
  end?: number;
  step?: number;
}

export interface PrometheusResult {
  metric: Record<string, string>;
  values: Array<[number, string]>;
}

export interface PrometheusResponse {
  status: 'success' | 'error';
  data: {
    resultType: 'matrix' | 'vector' | 'scalar' | 'string';
    result: PrometheusResult[];
  };
  error?: string;
}

// ============================================================================
// Utility Types
// ============================================================================

export type SortOrder = 'asc' | 'desc';

export interface SortConfig<T = string> {
  field: T;
  order: SortOrder;
}

export interface FilterConfig<T = any> {
  field: string;
  operator: 'eq' | 'ne' | 'gt' | 'gte' | 'lt' | 'lte' | 'in' | 'contains';
  value: T;
}

export interface PaginationConfig {
  page: number;
  pageSize: number;
}

// ============================================================================
// Event Types
// ============================================================================

export type EventType = 
  | 'job_submitted'
  | 'job_started'
  | 'job_completed'
  | 'job_failed'
  | 'node_down'
  | 'node_up'
  | 'storage_full'
  | 'system_alert';

export interface Event {
  id: string;
  type: EventType;
  timestamp: string;
  data: Record<string, any>;
  userId?: string;
}

// ============================================================================
// Type Guards
// ============================================================================

export function isJob(obj: any): obj is Job {
  return obj && typeof obj === 'object' && 'state' in obj && 'partition' in obj;
}

export function isNode(obj: any): obj is Node {
  return obj && typeof obj === 'object' && 'name' in obj && 'cpus' in obj;
}

export function isTemplate(obj: any): obj is Template {
  return obj && typeof obj === 'object' && 'category' in obj && 'config' in obj;
}

// ============================================================================
// Enum Types
// ============================================================================

export enum JobStateEnum {
  PENDING = 'PENDING',
  RUNNING = 'RUNNING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED',
  TIMEOUT = 'TIMEOUT',
  NODE_FAIL = 'NODE_FAIL',
}

export enum NodeStateEnum {
  IDLE = 'IDLE',
  ALLOCATED = 'ALLOCATED',
  MIXED = 'MIXED',
  DOWN = 'DOWN',
  DRAIN = 'DRAIN',
  DRAINING = 'DRAINING',
  RESERVED = 'RESERVED',
}

// ============================================================================
// Constants
// ============================================================================

export const JOB_STATE_COLORS: Record<JobState, string> = {
  PENDING: 'text-yellow-600 bg-yellow-100',
  RUNNING: 'text-blue-600 bg-blue-100',
  COMPLETED: 'text-green-600 bg-green-100',
  FAILED: 'text-red-600 bg-red-100',
  CANCELLED: 'text-gray-600 bg-gray-100',
  TIMEOUT: 'text-orange-600 bg-orange-100',
  NODE_FAIL: 'text-red-700 bg-red-200',
};

export const NODE_STATE_COLORS: Record<NodeState, string> = {
  IDLE: 'text-green-600 bg-green-100',
  ALLOCATED: 'text-blue-600 bg-blue-100',
  MIXED: 'text-yellow-600 bg-yellow-100',
  DOWN: 'text-red-600 bg-red-100',
  DRAIN: 'text-orange-600 bg-orange-100',
  DRAINING: 'text-orange-700 bg-orange-200',
  RESERVED: 'text-purple-600 bg-purple-100',
};

export const NOTIFICATION_SEVERITY_COLORS: Record<NotificationSeverity, string> = {
  info: 'text-blue-600 bg-blue-100',
  warning: 'text-yellow-600 bg-yellow-100',
  error: 'text-red-600 bg-red-100',
  success: 'text-green-600 bg-green-100',
};
