import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useDataWithFallback } from '../hooks/useDataWithFallback';
import * as api from '../utils/api';

// Mock the api module
vi.mock('../utils/api', async () => {
  const actual = await vi.importActual<typeof import('../utils/api')>('../utils/api');
  return {
    ...actual,
    apiGet: vi.fn(),
  };
});

describe('useDataWithFallback', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should return mock data in mock mode', async () => {
    const mockData = { value: 42 };

    const { result } = renderHook(() =>
      useDataWithFallback({
        apiEndpoint: '/api/test',
        mockData,
        mode: 'mock',
      })
    );

    // Wait for mock data to load
    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    }, { timeout: 1000 });

    expect(result.current.data).toEqual(mockData);
    expect(result.current.usingMockData).toBe(true);
    expect(result.current.isError).toBe(false);
  });

  it('should fetch data from API in production mode', async () => {
    const mockData = { value: 42 };
    const apiData = { value: 100 };

    vi.mocked(api.apiGet).mockResolvedValueOnce(apiData);

    const { result } = renderHook(() =>
      useDataWithFallback({
        apiEndpoint: '/api/test',
        mockData,
        mode: 'production',
      })
    );

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.data).toEqual(apiData);
    expect(result.current.usingMockData).toBe(false);
    expect(result.current.isError).toBe(false);
  });

  it('should fallback to mock data when API fails', async () => {
    const mockData = { value: 42 };

    vi.mocked(api.apiGet).mockRejectedValueOnce(new Error('API Error'));

    const { result } = renderHook(() =>
      useDataWithFallback({
        apiEndpoint: '/api/test',
        mockData,
        mode: 'production',
      })
    );

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.data).toEqual(mockData);
    expect(result.current.usingMockData).toBe(true);
    expect(result.current.isError).toBe(true);
  });

  it('should not fetch when disabled', () => {
    const mockData = { value: 42 };

    const { result } = renderHook(() =>
      useDataWithFallback({
        apiEndpoint: '/api/test',
        mockData,
        mode: 'production',
        enabled: false,
      })
    );

    // Should stay in loading state when disabled
    expect(result.current.isLoading).toBe(true);
    expect(api.apiGet).not.toHaveBeenCalled();
  });

  it('should call onSuccess callback on successful fetch', async () => {
    const mockData = { value: 42 };
    const apiData = { value: 100 };
    const onSuccess = vi.fn();

    vi.mocked(api.apiGet).mockResolvedValueOnce(apiData);

    renderHook(() =>
      useDataWithFallback({
        apiEndpoint: '/api/test',
        mockData,
        mode: 'production',
        onSuccess,
      })
    );

    await waitFor(() => {
      expect(onSuccess).toHaveBeenCalledWith(apiData);
    });
  });

  it('should call onError callback on failed fetch', async () => {
    const mockData = { value: 42 };
    const onError = vi.fn();
    const apiError = new Error('API Error');

    vi.mocked(api.apiGet).mockRejectedValueOnce(apiError);

    renderHook(() =>
      useDataWithFallback({
        apiEndpoint: '/api/test',
        mockData,
        mode: 'production',
        onError,
      })
    );

    await waitFor(() => {
      expect(onError).toHaveBeenCalledWith(expect.any(Error));
    });
  });

  it('should support manual refetch', async () => {
    const mockData = { value: 42 };
    const apiData1 = { value: 100 };
    const apiData2 = { value: 200 };

    vi.mocked(api.apiGet)
      .mockResolvedValueOnce(apiData1)
      .mockResolvedValueOnce(apiData2);

    const { result } = renderHook(() =>
      useDataWithFallback({
        apiEndpoint: '/api/test',
        mockData,
        mode: 'production',
      })
    );

    // Wait for initial fetch
    await waitFor(() => {
      expect(result.current.data).toEqual(apiData1);
    });

    // Manual refetch
    await result.current.refetch();

    await waitFor(() => {
      expect(result.current.data).toEqual(apiData2);
    });
  });

  it('should auto-refresh with refreshInterval', async () => {
    const mockData = { value: 42 };
    const apiData1 = { value: 100 };
    const apiData2 = { value: 200 };

    vi.mocked(api.apiGet)
      .mockResolvedValueOnce(apiData1)
      .mockResolvedValueOnce(apiData2);

    const { result } = renderHook(() =>
      useDataWithFallback({
        apiEndpoint: '/api/test',
        mockData,
        mode: 'production',
        refreshInterval: 1000, // Reduced to 1 second for faster test
      })
    );

    // Wait for initial fetch
    await waitFor(() => {
      expect(result.current.data).toEqual(apiData1);
    }, { timeout: 2000 });

    // Wait for refresh (1 second + buffer)
    await waitFor(() => {
      expect(result.current.data).toEqual(apiData2);
    }, { timeout: 3000 });

    // Verify apiGet was called twice
    expect(api.apiGet).toHaveBeenCalledTimes(2);
  }, 5000);
});
