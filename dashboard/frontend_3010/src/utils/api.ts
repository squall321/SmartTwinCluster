/**
 * API 클라이언트 유틸리티
 * Backend API와의 통신을 담당
 * 
 * Features:
 * - 자동 재시도 (Retry)
 * - 에러 처리 표준화
 * - 로딩 상태 관리
 * - 캐시 전략
 */

import { ApiResponse } from '../types';
import { API_CONFIG } from '../config/api.config';

// Vite proxy를 사용하므로 상대 경로 사용
// vite.config.ts의 proxy 설정이 /api 요청을 http://localhost:5010으로 전달
const API_BASE_URL = (import.meta as any).env?.VITE_API_URL || '';
const AUTH_PORTAL_URL = (import.meta as any).env?.VITE_AUTH_PORTAL_URL || 'http://localhost:4431';

// ============================================================================
// SSO Configuration
// ============================================================================

interface AuthConfig {
  sso_enabled: boolean;
  jwt_required: boolean;
  timestamp: string;
}

let ssoConfig: AuthConfig | null = null;

/**
 * Check SSO configuration from backend
 */
export async function checkSsoConfig(): Promise<AuthConfig> {
  if (ssoConfig) {
    return ssoConfig;
  }

  try {
    const response = await fetch(`${API_BASE_URL}/api/auth/config`);
    if (response.ok) {
      ssoConfig = await response.json();
      console.log('[Auth] SSO config loaded:', ssoConfig);
      return ssoConfig;
    }
  } catch (error) {
    console.warn('[Auth] Failed to load SSO config, defaulting to SSO enabled:', error);
  }

  // Default: SSO enabled
  ssoConfig = { sso_enabled: true, jwt_required: true, timestamp: new Date().toISOString() };
  return ssoConfig;
}

/**
 * Check if SSO is enabled
 */
export function isSsoEnabled(): boolean {
  return ssoConfig?.sso_enabled !== false;
}

// ============================================================================
// JWT Token Management
// ============================================================================

/**
 * Get JWT token from localStorage
 */
function getJwtToken(): string | null {
  return localStorage.getItem('jwt_token');
}

/**
 * Set JWT token in localStorage
 */
export function setJwtToken(token: string): void {
  localStorage.setItem('jwt_token', token);
  console.log('[Auth] JWT token saved to localStorage');
}

/**
 * Clear JWT token (on logout or 401)
 */
export function clearJwtToken(): void {
  localStorage.removeItem('jwt_token');
  console.log('[Auth] JWT token cleared from localStorage');
}

/**
 * Check if user is authenticated
 * In SSO false mode, always authenticated
 */
export function isAuthenticated(): boolean {
  // SSO false mode: always authenticated
  if (ssoConfig && !ssoConfig.sso_enabled) {
    return true;
  }

  return getJwtToken() !== null;
}

/**
 * Parse JWT token payload
 */
function parseJwtPayload(token: string): any | null {
  try {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(
      atob(base64)
        .split('')
        .map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
        .join('')
    );
    return JSON.parse(jsonPayload);
  } catch (error) {
    console.error('[Auth] Failed to parse JWT token:', error);
    return null;
  }
}

/**
 * User information interface
 */
export interface UserInfo {
  username: string;
  email?: string;
  groups: string[];
  permissions?: string[];
  exp?: number;
}

/**
 * Create mock admin user for SSO false mode
 */
function createMockAdminUser(): UserInfo {
  return {
    username: 'admin',
    email: 'admin@local',
    groups: ['admin', 'users', 'GPU-Users', 'HPC-Admins'],
    permissions: ['admin', 'user', 'read', 'write', 'execute', 'delete'],
    exp: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60), // 1 year from now
  };
}

/**
 * Get user information from JWT token
 * In SSO false mode, returns mock admin user
 */
export function getUserInfo(): UserInfo | null {
  // SSO false mode: return mock admin user
  if (ssoConfig && !ssoConfig.sso_enabled) {
    return createMockAdminUser();
  }

  const token = getJwtToken();
  if (!token) {
    return null;
  }

  const payload = parseJwtPayload(token);
  if (!payload) {
    return null;
  }

  return {
    username: payload.sub || payload.username || 'Unknown',
    email: payload.email,
    groups: payload.groups || [],
    permissions: payload.permissions || [],
    exp: payload.exp,
  };
}

/**
 * Check if token is expired
 * In SSO false mode, token never expires
 */
export function isTokenExpired(): boolean {
  // SSO false mode: token never expires
  if (ssoConfig && !ssoConfig.sso_enabled) {
    return false;
  }

  const userInfo = getUserInfo();
  if (!userInfo || !userInfo.exp) {
    return true;
  }

  const now = Math.floor(Date.now() / 1000);
  return userInfo.exp < now;
}

/**
 * Check if user has specific group
 */
export function hasGroup(groupName: string): boolean {
  const userInfo = getUserInfo();
  return userInfo?.groups.includes(groupName) || false;
}

/**
 * Check if user is admin (HPC-Admins group)
 */
export function isAdmin(): boolean {
  return hasGroup('HPC-Admins');
}

/**
 * Redirect to Auth Portal
 */
function redirectToAuthPortal(): void {
  console.log('[Auth] Redirecting to Auth Portal due to authentication failure');
  clearJwtToken();
  window.location.href = AUTH_PORTAL_URL;
}

// ============================================================================
// Cache Configuration
// ============================================================================

const CACHE_CONFIG = {
  enabled: true,
  duration: 5 * 60 * 1000, // 5 minutes
};

// ============================================================================
// Cache Management
// ============================================================================

interface CacheEntry<T> {
  data: T;
  timestamp: number;
}

const cache = new Map<string, CacheEntry<any>>();

function getCacheKey(endpoint: string, params?: Record<string, any>): string {
  return params ? `${endpoint}?${JSON.stringify(params)}` : endpoint;
}

function getFromCache<T>(key: string): T | null {
  if (!CACHE_CONFIG.enabled) return null;

  const entry = cache.get(key);
  if (!entry) return null;

  const age = Date.now() - entry.timestamp;
  if (age > CACHE_CONFIG.duration) {
    cache.delete(key);
    return null;
  }

  return entry.data as T;
}

function setCache<T>(key: string, data: T): void {
  if (!CACHE_CONFIG.enabled) return;
  
  cache.set(key, {
    data,
    timestamp: Date.now(),
  });
}

export function clearCache(): void {
  cache.clear();
}

// ============================================================================
// Error Handling
// ============================================================================

export class ApiError extends Error {
  constructor(
    message: string,
    public statusCode?: number,
    public endpoint?: string,
    public originalError?: any
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

// ============================================================================
// Retry Logic
// ============================================================================

async function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function withRetry<T>(
  fn: () => Promise<T>,
  retries: number = API_CONFIG.MAX_RETRIES
): Promise<T> {
  let lastError: any;

  for (let i = 0; i <= retries; i++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      // 마지막 시도면 에러 던지기
      if (i === retries) {
        throw error;
      }

      // HTTP 4xx 에러는 재시도하지 않음
      if (error instanceof ApiError && error.statusCode && error.statusCode >= 400 && error.statusCode < 500) {
        throw error;
      }

      // 다음 시도 전 대기
      const delay = API_CONFIG.RETRY_DELAY * Math.pow(2, i); // Exponential backoff
      console.warn(`[API] Retry ${i + 1}/${retries} after ${delay}ms`);
      await sleep(delay);
    }
  }

  throw lastError;
}

// ============================================================================
// API Endpoints
// ============================================================================

export const API_ENDPOINTS = {
  health: '/api/health',
  metrics: '/api/metrics/realtime',
  jobs: '/api/slurm/jobs',
  jobSubmit: '/api/slurm/jobs/submit',
  jobCancel: (jobId: string) => `/api/slurm/jobs/${jobId}/cancel`,
  jobHold: (jobId: string) => `/api/slurm/jobs/${jobId}/hold`,
  jobRelease: (jobId: string) => `/api/slurm/jobs/${jobId}/release`,
  applyConfig: '/api/slurm/apply-config',
  status: '/api/slurm/status',
  qos: '/api/slurm/qos',
  nodesReal: '/api/slurm/nodes/real',
  nodeDetail: (hostname: string) => `/api/slurm/nodes/${hostname}`,
  syncNodes: '/api/slurm/sync-nodes',
} as const;

/**
 * API 요청 헬퍼 함수 (개선됨)
 * - 자동 재시도
 * - 타임아웃 처리
 * - 에러 표준화
 */
export async function apiRequest<T>(
  endpoint: string,
  options: RequestInit = {},
  skipRetry: boolean = false
): Promise<T> {
  const url = `${API_BASE_URL}${endpoint}`;

  // Add JWT token to headers if available
  const token = getJwtToken();
  const authHeaders = token ? { 'Authorization': `Bearer ${token}` } : {};

  const defaultOptions: RequestInit = {
    headers: {
      'Content-Type': 'application/json',
      ...authHeaders,
      ...options.headers,
    },
    ...options,
  };

  const fetchWithTimeout = async (): Promise<Response> => {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), API_CONFIG.TIMEOUT);

    try {
      const response = await fetch(url, {
        ...defaultOptions,
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      return response;
    } catch (error) {
      clearTimeout(timeoutId);
      if (error instanceof Error && error.name === 'AbortError') {
        throw new ApiError('Request timeout', 408, endpoint, error);
      }
      throw error;
    }
  };

  const executeRequest = async (): Promise<T> => {
    try {
      const response = await fetchWithTimeout();

      if (!response.ok) {
        // Handle 401 Unauthorized - token expired or invalid
        if (response.status === 401) {
          console.warn('[Auth] 401 Unauthorized - token may be expired or invalid');
          // Don't redirect immediately, just throw error
          // The calling component can decide what to do
          const errorData = await response.json().catch(() => ({}));
          throw new ApiError(
            errorData.error || errorData.message || 'Authentication required',
            401,
            endpoint,
            errorData
          );
        }

        const errorData = await response.json().catch(() => ({}));
        throw new ApiError(
          errorData.error || errorData.message || `API request failed: ${response.statusText}`,
          response.status,
          endpoint,
          errorData
        );
      }

      return await response.json();
    } catch (error) {
      console.error(`[API Error] ${endpoint}:`, error);
      throw error instanceof ApiError
        ? error
        : new ApiError('Network error', undefined, endpoint, error);
    }
  };

  // 재시도 적용
  if (skipRetry) {
    return executeRequest();
  } else {
    return withRetry(executeRequest);
  }
}

/**
 * GET 요청 (캐시 지원)
 */
export async function apiGet<T>(
  endpoint: string, 
  params?: Record<string, any>,
  options?: { skipCache?: boolean; skipRetry?: boolean }
): Promise<T> {
  let url = endpoint;
  
  // Query parameters 추가
  if (params) {
    const searchParams = new URLSearchParams();
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        searchParams.append(key, String(value));
      }
    });
    const queryString = searchParams.toString();
    if (queryString) {
      url += `?${queryString}`;
    }
  }
  
  // 캐시 확인
  if (!options?.skipCache) {
    const cacheKey = getCacheKey(endpoint, params);
    const cachedData = getFromCache<T>(cacheKey);
    if (cachedData) {
      console.log(`[API] Cache hit: ${cacheKey}`);
      return cachedData;
    }
  }
  
  // API 요청
  const data = await apiRequest<T>(url, { method: 'GET' }, options?.skipRetry);
  
  // 캐시 저장
  if (!options?.skipCache) {
    const cacheKey = getCacheKey(endpoint, params);
    setCache(cacheKey, data);
  }
  
  return data;
}

/**
 * POST 요청
 */
export async function apiPost<T>(endpoint: string, data?: any): Promise<T> {
  return apiRequest<T>(endpoint, {
    method: 'POST',
    body: data ? JSON.stringify(data) : undefined,
  });
}

/**
 * PUT 요청
 */
export async function apiPut<T>(endpoint: string, data?: any): Promise<T> {
  return apiRequest<T>(endpoint, {
    method: 'PUT',
    body: data ? JSON.stringify(data) : undefined,
  });
}

/**
 * PATCH 요청
 */
export async function apiPatch<T>(endpoint: string, data?: any): Promise<T> {
  return apiRequest<T>(endpoint, {
    method: 'PATCH',
    body: data ? JSON.stringify(data) : undefined,
  });
}

/**
 * DELETE 요청
 */
export async function apiDelete<T>(endpoint: string): Promise<T> {
  return apiRequest<T>(endpoint, { method: 'DELETE' });
}

/**
 * Health Check
 */
export async function checkHealth() {
  return apiGet<{
    status: string;
    mode: 'mock' | 'production';
    timestamp: string;
  }>(API_ENDPOINTS.health);
}

export default {
  apiRequest,
  apiGet,
  apiPost,
  apiPut,
  apiPatch,
  apiDelete,
  checkHealth,
  API_BASE_URL,
  API_ENDPOINTS,
};

// ============================================================================
// Reports API
// ============================================================================

/**
 * 리포트 타입
 */
export type ReportType = 'usage' | 'jobs' | 'users' | 'costs' | 'efficiency' | 'overview';
export type ReportPeriod = 'today' | 'yesterday' | 'week' | 'month' | 'year';
export type ReportFormat = 'json' | 'pdf' | 'excel';

/**
 * Overview Report 조회
 */
export async function getOverviewReport() {
  return apiGet<any>('/api/reports/overview');
}

/**
 * Usage Report 조회
 */
export async function getUsageReport(period: ReportPeriod = 'week') {
  return apiGet<any>(`/api/reports/usage?period=${period}`);
}

/**
 * Jobs Report 조회
 */
export async function getJobsReport(period: ReportPeriod = 'week') {
  return apiGet<any>(`/api/reports/jobs?period=${period}`);
}

/**
 * Users Report 조회
 */
export async function getUsersReport(period: ReportPeriod = 'month', limit: number = 10) {
  return apiGet<any>(`/api/reports/users?period=${period}&limit=${limit}`);
}

/**
 * Costs Report 조회
 */
export async function getCostsReport(period: ReportPeriod = 'week') {
  return apiGet<any>(`/api/reports/costs?period=${period}`);
}

/**
 * Efficiency Report 조회
 */
export async function getEfficiencyReport(period: ReportPeriod = 'week') {
  return apiGet<any>(`/api/reports/efficiency?period=${period}`);
}

/**
 * Trends Analysis 조회
 */
export async function getTrendsAnalysis(resource: string = 'cpu', period: ReportPeriod = 'month') {
  return apiGet<any>(`/api/reports/stats/trends?resource=${resource}&period=${period}`);
}

/**
 * 리포트 다운로드 URL 생성
 */
export function getReportDownloadUrl(
  reportType: 'usage' | 'costs',
  format: 'pdf' | 'excel',
  period: ReportPeriod = 'week'
): string {
  const base = API_BASE_URL || API_CONFIG.API_BASE_URL;
  return `${base}/api/reports/download/${reportType}/${format}?period=${period}`;
}

/**
 * 리포트 생성 (직접 다운로드)
 */
export async function generateReport(
  reportType: ReportType,
  format: ReportFormat,
  period: ReportPeriod
) {
  return apiPost<any>('/api/reports/generate', {
    type: reportType,
    format,
    period
  });
}

// ============================================================================
// Dashboard API (v3.4.0)
// ============================================================================

/**
 * Dashboard 리소스 사용률 데이터 인터페이스
 */
export interface DashboardResourceData {
  status: string;
  mode: 'mock' | 'demo' | 'production';
  timestamps: string[];
  cpu_usage: number[];
  gpu_usage: number[];
  memory_usage: number[];
}

/**
 * Dashboard Top 사용자 데이터 인터페이스
 */
export interface DashboardTopUser {
  rank: number;
  username: string;
  cpu_hours: number;
  gpu_hours: number;
  memory_gb_hours: number;
  jobs_count: number;
  jobs_success: number;
  jobs_failed: number;
  cost: number;
  cpu_utilization: number;
  gpu_utilization: number;
}

export interface DashboardTopUsersData {
  status: string;
  mode: 'mock' | 'demo' | 'production';
  users: DashboardTopUser[];
  count: number;
}

/**
 * Dashboard 작업 상태 데이터 인터페이스
 */
export interface DashboardJobStatusData {
  status: string;
  mode: 'mock' | 'demo' | 'production';
  running: number;
  pending: number;
  completed: number;
  failed: number;
  cancelled: number;
  total: number;
}

/**
 * Dashboard 비용 추이 데이터 인터페이스
 */
export interface DashboardCostTrendsData {
  status: string;
  mode: 'mock' | 'demo' | 'production';
  period: 'week' | 'month' | 'year';
  dates: string[];
  daily_costs: number[];
  cumulative_costs: number[];
  total_cost: number;
  average_daily_cost: number;
}

/**
 * Dashboard 리소스 사용률 조회 (24시간)
 * GET /api/reports/dashboard/resources
 */
export async function getDashboardResources(): Promise<DashboardResourceData> {
  return apiGet<DashboardResourceData>('/api/reports/dashboard/resources', undefined, {
    skipCache: true // 실시간 데이터이므로 캐시 사용 안 함
  });
}

/**
 * Dashboard Top 사용자 조회
 * GET /api/reports/dashboard/top-users?limit=10
 */
export async function getDashboardTopUsers(limit: number = 10): Promise<DashboardTopUsersData> {
  return apiGet<DashboardTopUsersData>('/api/reports/dashboard/top-users', { limit }, {
    skipCache: true
  });
}

/**
 * Dashboard 작업 상태 분포 조회
 * GET /api/reports/dashboard/job-status
 */
export async function getDashboardJobStatus(): Promise<DashboardJobStatusData> {
  return apiGet<DashboardJobStatusData>('/api/reports/dashboard/job-status', undefined, {
    skipCache: true
  });
}

/**
 * Dashboard 비용 추이 조회
 * GET /api/reports/dashboard/cost-trends?period=week
 */
export async function getDashboardCostTrends(
  period: 'week' | 'month' | 'year' = 'week'
): Promise<DashboardCostTrendsData> {
  return apiGet<DashboardCostTrendsData>('/api/reports/dashboard/cost-trends', { period }, {
    skipCache: true
  });
}

/**
 * Dashboard Health Check
 * GET /api/reports/dashboard/health
 */
export async function checkDashboardHealth() {
  return apiGet<{
    status: string;
    service: string;
    version: string;
    mock_mode: boolean;
    slurm_available: boolean;
    timestamp: string;
  }>('/api/reports/dashboard/health');
}
