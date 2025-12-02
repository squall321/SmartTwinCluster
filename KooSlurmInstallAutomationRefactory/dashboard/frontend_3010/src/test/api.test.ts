import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { apiGet, apiPost, ApiError, clearCache } from '../utils/api';

describe('API Client', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    clearCache();
    global.fetch = vi.fn();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('apiGet', () => {
    it('should make GET request successfully', async () => {
      const mockData = { success: true, data: { value: 42 } };

      (global.fetch as any).mockResolvedValueOnce({
        ok: true,
        json: async () => mockData,
      });

      const result = await apiGet('/api/test');

      expect(global.fetch).toHaveBeenCalledWith(
        '/api/test',
        expect.objectContaining({
          method: 'GET',
        })
      );
      expect(result).toEqual(mockData);
    });

    it('should add query parameters', async () => {
      const mockData = { success: true };

      (global.fetch as any).mockResolvedValueOnce({
        ok: true,
        json: async () => mockData,
      });

      await apiGet('/api/test', { foo: 'bar', baz: 123 });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('?foo=bar&baz=123'),
        expect.any(Object)
      );
    });

    it('should use cache on second request', async () => {
      const mockData = { success: true, data: { value: 42 } };

      (global.fetch as any).mockResolvedValueOnce({
        ok: true,
        json: async () => mockData,
      });

      // First request
      const result1 = await apiGet('/api/test');
      expect(result1).toEqual(mockData);
      expect(global.fetch).toHaveBeenCalledTimes(1);

      // Second request (should use cache)
      const result2 = await apiGet('/api/test');
      expect(result2).toEqual(mockData);
      expect(global.fetch).toHaveBeenCalledTimes(1); // Still 1, not 2
    });

    it('should skip cache when skipCache is true', async () => {
      const mockData = { success: true };

      (global.fetch as any).mockResolvedValue({
        ok: true,
        json: async () => mockData,
      });

      // First request
      await apiGet('/api/test');
      expect(global.fetch).toHaveBeenCalledTimes(1);

      // Second request with skipCache
      await apiGet('/api/test', undefined, { skipCache: true });
      expect(global.fetch).toHaveBeenCalledTimes(2);
    });

    it('should throw ApiError on failed request', async () => {
      (global.fetch as any).mockResolvedValueOnce({
        ok: false,
        status: 404,
        json: async () => ({ error: 'Not found' }),
      });

      try {
        await apiGet('/api/test');
        throw new Error('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(ApiError);
        expect((error as ApiError).message).toContain('Not found');
      }
    });

    it('should throw ApiError on network error', async () => {
      (global.fetch as any).mockRejectedValueOnce(new Error('Network error'));

      await expect(apiGet('/api/test', undefined, { skipRetry: true })).rejects.toThrow(ApiError);
    });
  });

  describe('apiPost', () => {
    it('should make POST request with data', async () => {
      const mockData = { success: true };
      const postData = { name: 'test', value: 42 };

      (global.fetch as any).mockResolvedValueOnce({
        ok: true,
        json: async () => mockData,
      });

      const result = await apiPost('/api/test', postData);

      expect(global.fetch).toHaveBeenCalledWith(
        '/api/test',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify(postData),
        })
      );
      expect(result).toEqual(mockData);
    });
  });

  describe('Retry Logic', () => {
    it('should retry on 5xx errors', async () => {
      // First 2 attempts fail, 3rd succeeds
      (global.fetch as any)
        .mockResolvedValueOnce({
          ok: false,
          status: 500,
          json: async () => ({ error: 'Server error' }),
        })
        .mockResolvedValueOnce({
          ok: false,
          status: 503,
          json: async () => ({ error: 'Service unavailable' }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ success: true }),
        });

      const result = await apiGet('/api/test');

      expect(global.fetch).toHaveBeenCalledTimes(3);
      expect(result).toEqual({ success: true });
    });

    it('should not retry on 4xx errors', async () => {
      (global.fetch as any).mockResolvedValueOnce({
        ok: false,
        status: 400,
        json: async () => ({ error: 'Bad request' }),
      });

      await expect(apiGet('/api/test')).rejects.toThrow();

      // Should not retry (only 1 call)
      expect(global.fetch).toHaveBeenCalledTimes(1);
    });

    it('should respect skipRetry option', async () => {
      (global.fetch as any).mockResolvedValueOnce({
        ok: false,
        status: 500,
        json: async () => ({ error: 'Server error' }),
      });

      await expect(apiGet('/api/test', undefined, { skipRetry: true })).rejects.toThrow();

      // Should not retry
      expect(global.fetch).toHaveBeenCalledTimes(1);
    });
  });

  describe('ApiError', () => {
    it('should contain error details', async () => {
      (global.fetch as any).mockResolvedValueOnce({
        ok: false,
        status: 404,
        json: async () => ({ error: 'Not found', details: 'Resource not found' }),
      });

      try {
        await apiGet('/api/test');
        expect.fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(ApiError);
        const apiError = error as ApiError;
        expect(apiError.statusCode).toBe(404);
        expect(apiError.endpoint).toBe('/api/test');
        expect(apiError.message).toContain('Not found');
      }
    });
  });

  describe('Cache Management', () => {
    it('should clear cache', async () => {
      const mockData = { success: true };

      (global.fetch as any).mockResolvedValue({
        ok: true,
        json: async () => mockData,
      });

      // First request
      await apiGet('/api/test');
      expect(global.fetch).toHaveBeenCalledTimes(1);

      // Second request (cached)
      await apiGet('/api/test');
      expect(global.fetch).toHaveBeenCalledTimes(1);

      // Clear cache
      clearCache();

      // Third request (no cache)
      await apiGet('/api/test');
      expect(global.fetch).toHaveBeenCalledTimes(2);
    });
  });
});
