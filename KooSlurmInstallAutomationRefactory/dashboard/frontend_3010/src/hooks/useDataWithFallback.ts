import { useState, useEffect, useCallback } from 'react';
import { apiGet } from '../utils/api';

/**
 * useDataWithFallback Hook
 * API 호출을 시도하고 실패 시 Mock 데이터로 fallback하는 공통 로직
 */

interface UseDataWithFallbackOptions<T> {
  apiEndpoint: string;           // API 엔드포인트 (예: '/api/jobs')
  params?: Record<string, any>;  // Query parameters (NEW!)
  mockData: T;                   // Mock 데이터
  mode: 'mock' | 'production';   // 모드
  refreshInterval?: number;       // 자동 새로고침 (밀리초, 선택)
  enabled?: boolean;              // 훅 활성화 여부 (기본: true)
  onSuccess?: (data: T) => void;  // 성공 콜백
  onError?: (error: Error) => void; // 에러 콜백
}

interface UseDataWithFallbackResult<T> {
  data: T | null;                 // 데이터
  isLoading: boolean;             // 로딩 상태
  isError: boolean;               // 에러 상태
  error: Error | null;            // 에러 객체
  usingMockData: boolean;         // Mock 데이터 사용 여부
  refetch: () => Promise<void>;   // 수동 재로딩
}

export function useDataWithFallback<T>(
  options: UseDataWithFallbackOptions<T>
): UseDataWithFallbackResult<T> {
  const {
    apiEndpoint,
    params,
    mockData,
    mode,
    refreshInterval,
    enabled = true,
    onSuccess,
    onError,
  } = options;

  const [data, setData] = useState<T | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isError, setIsError] = useState<boolean>(false);
  const [error, setError] = useState<Error | null>(null);
  const [usingMockData, setUsingMockData] = useState<boolean>(false);

  // 데이터 fetching 함수
  const fetchData = useCallback(async () => {
    if (!enabled) return;

    setIsLoading(true);
    setIsError(false);
    setError(null);

    // Mock 모드면 바로 Mock 데이터 사용
    if (mode === 'mock') {
      setData(mockData);
      setUsingMockData(true);
      setIsLoading(false);
      
      if (onSuccess) {
        onSuccess(mockData);
      }
      
      console.log(`[useDataWithFallback] Mock mode: ${apiEndpoint}`);
      return;
    }

    // Production 모드: 실제 API 호출 시도
    try {
      const response = await apiGet<T>(apiEndpoint, params);
      
      setData(response);
      setUsingMockData(false);
      setIsLoading(false);
      
      if (onSuccess) {
        onSuccess(response);
      }
      
      console.log(`[useDataWithFallback] API success: ${apiEndpoint}`, params);
    } catch (err) {
      // API 실패 시 Mock 데이터로 fallback
      console.warn(`[useDataWithFallback] API failed for ${apiEndpoint}, using mock data:`, err);
      
      setData(mockData);
      setUsingMockData(true);
      setIsError(true);
      setError(err instanceof Error ? err : new Error(String(err)));
      setIsLoading(false);
      
      if (onError) {
        onError(err instanceof Error ? err : new Error(String(err)));
      }
    }
  }, [apiEndpoint, params, mockData, mode, enabled, onSuccess, onError]);

  // 초기 로딩 및 자동 새로고침
  useEffect(() => {
    fetchData();

    // 자동 새로고침 설정
    if (refreshInterval && refreshInterval > 0) {
      const intervalId = setInterval(fetchData, refreshInterval);
      return () => clearInterval(intervalId);
    }
  }, [fetchData, refreshInterval]);

  return {
    data,
    isLoading,
    isError,
    error,
    usingMockData,
    refetch: fetchData,
  };
}

/**
 * useDataWithFallbackQuery Hook
 * Query parameter를 지원하는 버전 (별칭)
 */

interface UseDataWithFallbackQueryOptions<T> extends Omit<UseDataWithFallbackOptions<T>, 'params'> {
  apiEndpoint: string;
  queryParams?: Record<string, string | number | boolean | undefined>;
}

export function useDataWithFallbackQuery<T>(
  options: UseDataWithFallbackQueryOptions<T>
): UseDataWithFallbackResult<T> {
  const { queryParams, ...restOptions } = options;

  return useDataWithFallback<T>({
    ...restOptions,
    params: queryParams,
  });
}

/**
 * 사용 예시:
 * 
 * // 기본 사용
 * const { data, isLoading, usingMockData } = useDataWithFallback({
 *   apiEndpoint: '/api/jobs',
 *   mockData: mockJobs,
 *   mode: 'production',
 * });
 * 
 * // Query parameter 사용 (NEW!)
 * const { data, isLoading, usingMockData } = useDataWithFallback({
 *   apiEndpoint: '/api/prometheus/query',
 *   params: { query: 'node_cpu_usage' },  // ← Query params!
 *   mockData: mockData,
 *   mode: 'production',
 * });
 * 
 * // 자동 새로고침
 * const { data, isLoading, usingMockData, refetch } = useDataWithFallback({
 *   apiEndpoint: '/api/nodes',
 *   mockData: mockNodes,
 *   mode: 'production',
 *   refreshInterval: 5000, // 5초마다
 * });
 * 
 * // 수동 새로고침
 * <button onClick={refetch}>Refresh</button>
 * 
 * // 조건부 활성화
 * const { data } = useDataWithFallback({
 *   apiEndpoint: '/api/storage',
 *   mockData: mockStorage,
 *   mode: 'production',
 *   enabled: isVisible, // isVisible이 true일 때만 fetch
 * });
 * 
 * // 콜백 사용
 * const { data } = useDataWithFallback({
 *   apiEndpoint: '/api/alerts',
 *   mockData: mockAlerts,
 *   mode: 'production',
 *   onSuccess: (data) => console.log('Data loaded:', data),
 *   onError: (error) => console.error('Failed:', error),
 * });
 */
