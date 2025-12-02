/**
 * useApptainerImages Hook
 *
 * Apptainer 이미지 목록을 관리하는 React Hook
 *
 * Features:
 * - 이미지 목록 조회 및 캐싱
 * - 자동 갱신 (Auto Refresh)
 * - 파티션 필터링
 * - 에러 처리
 * - 로딩 상태 관리
 */

import { useState, useEffect, useCallback } from 'react';
import { ApptainerImage } from '../components/ApptainerSelector';

const API_BASE_URL = import.meta.env.VITE_API_URL || '';

interface UseApptainerImagesResult {
  images: ApptainerImage[];
  loading: boolean;
  error: string | null;
  refreshImages: () => Promise<void>;
  scanNodes: (nodes?: string[]) => Promise<void>;
}

export function useApptainerImages(
  partition: 'compute' | 'viz' | null = null,
  autoRefresh: boolean = false,
  refreshInterval: number = 60000 // 1분
): UseApptainerImagesResult {
  const [images, setImages] = useState<ApptainerImage[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

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

  /**
   * 이미지 목록 조회
   */
  const fetchImages = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      // Query parameters 구성
      const params = new URLSearchParams();
      if (partition) {
        params.append('partition', partition);
      }

      const url = `${API_BASE_URL}/api/apptainer/images${params.toString() ? `?${params.toString()}` : ''}`;

      const response = await fetch(url, {
        method: 'GET',
        headers: getHeaders(),
      });

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error('인증이 필요합니다. 다시 로그인해주세요.');
        }
        throw new Error(`이미지 조회 실패: ${response.statusText}`);
      }

      const data = await response.json();

      // 응답 데이터 검증
      if (!data.images || !Array.isArray(data.images)) {
        throw new Error('잘못된 응답 형식입니다.');
      }

      // JSON 문자열 필드 파싱
      const parsedImages = data.images.map((img: any) => ({
        ...img,
        labels: typeof img.labels === 'string' ? JSON.parse(img.labels) : img.labels,
        apps: typeof img.apps === 'string' ? JSON.parse(img.apps) : img.apps,
        env_vars: typeof img.env_vars === 'string' ? JSON.parse(img.env_vars) : img.env_vars,
      }));

      setImages(parsedImages);
      console.log(`[Apptainer] Loaded ${parsedImages.length} images${partition ? ` (partition: ${partition})` : ''}`);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : '알 수 없는 오류가 발생했습니다.';
      setError(errorMessage);
      console.error('[Apptainer] Failed to fetch images:', err);
    } finally {
      setLoading(false);
    }
  }, [partition]);

  /**
   * 이미지 새로고침
   */
  const refreshImages = useCallback(async () => {
    await fetchImages();
  }, [fetchImages]);

  /**
   * 노드 스캔 트리거
   */
  const scanNodes = useCallback(async (nodes?: string[]) => {
    try {
      setLoading(true);
      setError(null);

      const url = `${API_BASE_URL}/api/apptainer/scan`;
      const body = nodes ? { nodes } : {};

      const response = await fetch(url, {
        method: 'POST',
        headers: getHeaders(),
        body: JSON.stringify(body),
      });

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error('인증이 필요합니다. 다시 로그인해주세요.');
        }
        throw new Error(`노드 스캔 실패: ${response.statusText}`);
      }

      const data = await response.json();
      console.log('[Apptainer] Scan completed:', data.stats);

      // 스캔 후 이미지 목록 갱신
      await fetchImages();
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : '노드 스캔 중 오류가 발생했습니다.';
      setError(errorMessage);
      console.error('[Apptainer] Failed to scan nodes:', err);
    } finally {
      setLoading(false);
    }
  }, [fetchImages]);

  /**
   * 초기 로드 및 자동 갱신
   */
  useEffect(() => {
    // 초기 로드
    fetchImages();

    // 자동 갱신 설정
    if (autoRefresh && refreshInterval > 0) {
      const intervalId = setInterval(() => {
        console.log('[Apptainer] Auto-refreshing images...');
        fetchImages();
      }, refreshInterval);

      return () => clearInterval(intervalId);
    }
  }, [fetchImages, autoRefresh, refreshInterval]);

  return {
    images,
    loading,
    error,
    refreshImages,
    scanNodes,
  };
}

/**
 * useApptainerImage Hook
 *
 * 특정 이미지의 상세 정보를 조회하는 Hook
 */
export function useApptainerImage(imageId: string | null) {
  const [image, setImage] = useState<ApptainerImage | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const getJwtToken = (): string | null => {
    return localStorage.getItem('jwt_token');
  };

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

  useEffect(() => {
    if (!imageId) {
      setImage(null);
      return;
    }

    const fetchImage = async () => {
      try {
        setLoading(true);
        setError(null);

        const url = `${API_BASE_URL}/api/apptainer/images/${imageId}/metadata`;

        const response = await fetch(url, {
          method: 'GET',
          headers: getHeaders(),
        });

        if (!response.ok) {
          if (response.status === 404) {
            throw new Error('이미지를 찾을 수 없습니다.');
          }
          if (response.status === 401) {
            throw new Error('인증이 필요합니다. 다시 로그인해주세요.');
          }
          throw new Error(`이미지 조회 실패: ${response.statusText}`);
        }

        const data = await response.json();

        // JSON 문자열 필드 파싱
        const parsedImage = {
          ...data,
          labels: typeof data.labels === 'string' ? JSON.parse(data.labels) : data.labels,
          apps: typeof data.apps === 'string' ? JSON.parse(data.apps) : data.apps,
          env_vars: typeof data.env_vars === 'string' ? JSON.parse(data.env_vars) : data.env_vars,
        };

        setImage(parsedImage);
      } catch (err) {
        const errorMessage = err instanceof Error ? err.message : '알 수 없는 오류가 발생했습니다.';
        setError(errorMessage);
        console.error(`[Apptainer] Failed to fetch image ${imageId}:`, err);
      } finally {
        setLoading(false);
      }
    };

    fetchImage();
  }, [imageId]);

  return { image, loading, error };
}

export default useApptainerImages;
