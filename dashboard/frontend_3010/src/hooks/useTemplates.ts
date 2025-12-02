/**
 * useTemplates Hook
 *
 * Template API 연동 및 상태 관리
 *
 * Features:
 * - 템플릿 목록 조회
 * - 카테고리/소스 필터링
 * - 검색 기능
 * - 자동 갱신 (선택적)
 * - JWT 인증
 */

import { useState, useEffect, useCallback } from 'react';
import { Template, TemplatesResponse, TemplateSource } from '../types/template';

const API_BASE_URL = import.meta.env.VITE_API_URL || '';

interface UseTemplatesOptions {
  category?: string;
  source?: TemplateSource;
  autoRefresh?: boolean;
  refreshInterval?: number;
}

interface UseTemplatesResult {
  templates: Template[];
  loading: boolean;
  error: string | null;
  refreshTemplates: () => Promise<void>;
  scanTemplates: () => Promise<void>;
}

/**
 * JWT 토큰 가져오기
 */
const getJwtToken = (): string | null => {
  return localStorage.getItem('jwt_token');
};

/**
 * API 요청 헤더 생성
 */
const getHeaders = (): HeadersInit => {
  const headers: HeadersInit = {
    'Content-Type': 'application/json',
  };

  const token = getJwtToken();
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  return headers;
};

export function useTemplates(options: UseTemplatesOptions = {}): UseTemplatesResult {
  const { category, source, autoRefresh = false, refreshInterval = 60000 } = options;

  const [templates, setTemplates] = useState<Template[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  /**
   * 템플릿 목록 조회
   */
  const fetchTemplates = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      // Query parameters 구성
      const params = new URLSearchParams();
      if (category) {
        params.append('category', category);
      }
      if (source && source !== 'all') {
        params.append('source', source);
      }

      const url = `${API_BASE_URL}/api/v2/templates${params.toString() ? `?${params.toString()}` : ''}`;

      const response = await fetch(url, {
        method: 'GET',
        headers: getHeaders(),
      });

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error('인증이 필요합니다. 다시 로그인해주세요.');
        }
        throw new Error(`템플릿 조회 실패: ${response.statusText}`);
      }

      const data: TemplatesResponse = await response.json();

      if (!data.templates || !Array.isArray(data.templates)) {
        throw new Error('잘못된 응답 형식입니다.');
      }

      setTemplates(data.templates);
      console.log(`[Templates] Loaded ${data.templates.length} templates${category ? ` (category: ${category})` : ''}${source && source !== 'all' ? ` (source: ${source})` : ''}`);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : '알 수 없는 오류가 발생했습니다.';
      setError(errorMessage);
      console.error('[Templates] Failed to fetch templates:', err);
    } finally {
      setLoading(false);
    }
  }, [category, source]);

  /**
   * 템플릿 새로고침
   */
  const refreshTemplates = useCallback(async () => {
    await fetchTemplates();
  }, [fetchTemplates]);

  /**
   * 템플릿 스캔 트리거
   */
  const scanTemplates = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const url = `${API_BASE_URL}/api/v2/templates/scan`;

      const response = await fetch(url, {
        method: 'POST',
        headers: getHeaders(),
      });

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error('인증이 필요합니다. 다시 로그인해주세요.');
        }
        throw new Error(`템플릿 스캔 실패: ${response.statusText}`);
      }

      const data = await response.json();
      console.log('[Templates] Scan completed:', data.stats);

      // 스캔 후 템플릿 목록 갱신
      await fetchTemplates();
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : '템플릿 스캔 중 오류가 발생했습니다.';
      setError(errorMessage);
      console.error('[Templates] Failed to scan templates:', err);
    } finally {
      setLoading(false);
    }
  }, [fetchTemplates]);

  /**
   * 초기 로드 및 자동 갱신
   */
  useEffect(() => {
    // 초기 로드
    fetchTemplates();

    // 자동 갱신 설정
    if (autoRefresh && refreshInterval > 0) {
      const intervalId = setInterval(() => {
        console.log('[Templates] Auto-refreshing templates...');
        fetchTemplates();
      }, refreshInterval);

      return () => clearInterval(intervalId);
    }
  }, [fetchTemplates, autoRefresh, refreshInterval]);

  return {
    templates,
    loading,
    error,
    refreshTemplates,
    scanTemplates,
  };
}

/**
 * useTemplate Hook
 *
 * 특정 템플릿의 상세 정보를 조회하는 Hook
 */
export function useTemplate(templateId: string | null) {
  const [template, setTemplate] = useState<Template | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!templateId) {
      setTemplate(null);
      return;
    }

    const fetchTemplate = async () => {
      try {
        setLoading(true);
        setError(null);

        const url = `${API_BASE_URL}/api/v2/templates/${templateId}`;

        const response = await fetch(url, {
          method: 'GET',
          headers: getHeaders(),
        });

        if (!response.ok) {
          if (response.status === 404) {
            throw new Error('템플릿을 찾을 수 없습니다.');
          }
          if (response.status === 401) {
            throw new Error('인증이 필요합니다. 다시 로그인해주세요.');
          }
          throw new Error(`템플릿 조회 실패: ${response.statusText}`);
        }

        const data: Template = await response.json();
        setTemplate(data);
      } catch (err) {
        const errorMessage = err instanceof Error ? err.message : '알 수 없는 오류가 발생했습니다.';
        setError(errorMessage);
        console.error(`[Templates] Failed to fetch template ${templateId}:`, err);
      } finally {
        setLoading(false);
      }
    };

    fetchTemplate();
  }, [templateId]);

  return { template, loading, error };
}

export default useTemplates;
