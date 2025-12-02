/**
 * useUploadProgress Hook
 * WebSocket을 통한 실시간 업로드 진행률 추적
 */

import { useState, useEffect, useRef, useCallback } from 'react';
import { UploadProgress } from '../types/upload';

interface UseUploadProgressOptions {
  uploadIds?: string[];
  onProgress?: (progress: UploadProgress) => void;
  onComplete?: (uploadId: string) => void;
  onError?: (uploadId: string, error: string) => void;
}

interface UseUploadProgressResult {
  progressMap: Map<string, UploadProgress>;
  connected: boolean;
  error: Error | null;
  subscribe: (uploadId: string) => void;
  unsubscribe: (uploadId: string) => void;
}

const WS_URL = process.env.REACT_APP_WS_URL || 'ws://localhost:5011/ws';

export const useUploadProgress = (
  options: UseUploadProgressOptions = {}
): UseUploadProgressResult => {
  const { uploadIds = [], onProgress, onComplete, onError } = options;

  const [progressMap, setProgressMap] = useState<Map<string, UploadProgress>>(new Map());
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const subscribedIdsRef = useRef<Set<string>>(new Set(uploadIds));

  /**
   * WebSocket 연결
   */
  const connect = useCallback(() => {
    try {
      const ws = new WebSocket(WS_URL);

      ws.onopen = () => {
        console.log('WebSocket connected for upload progress');
        setConnected(true);
        setError(null);

        // 기존 구독 재등록
        subscribedIdsRef.current.forEach(uploadId => {
          ws.send(JSON.stringify({
            action: 'subscribe',
            topic: 'upload'
          }));
        });
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          // 업로드 진행률 메시지 처리
          if (data.type === 'upload_progress') {
            const progress: UploadProgress = data.data;

            // 구독 중인 업로드인지 확인
            if (subscribedIdsRef.current.has(progress.upload_id)) {
              setProgressMap(prev => {
                const newMap = new Map(prev);
                newMap.set(progress.upload_id, progress);
                return newMap;
              });

              onProgress?.(progress);
            }
          }

          // 업로드 완료 메시지
          else if (data.type === 'upload_complete') {
            const { upload_id } = data.data;

            if (subscribedIdsRef.current.has(upload_id)) {
              onComplete?.(upload_id);
            }
          }

          // 업로드 에러 메시지
          else if (data.type === 'upload_error') {
            const { upload_id, error: errorMsg } = data.data;

            if (subscribedIdsRef.current.has(upload_id)) {
              onError?.(upload_id, errorMsg);
            }
          }
        } catch (err) {
          console.error('Failed to parse WebSocket message:', err);
        }
      };

      ws.onerror = (event) => {
        console.error('WebSocket error:', event);
        setError(new Error('WebSocket connection error'));
      };

      ws.onclose = () => {
        console.log('WebSocket disconnected');
        setConnected(false);
        wsRef.current = null;

        // 5초 후 재연결 시도
        reconnectTimeoutRef.current = setTimeout(() => {
          console.log('Attempting to reconnect WebSocket...');
          connect();
        }, 5000);
      };

      wsRef.current = ws;

    } catch (err) {
      setError(err as Error);
      console.error('Failed to connect WebSocket:', err);
    }
  }, [onProgress, onComplete, onError]);

  /**
   * 특정 업로드 ID 구독
   */
  const subscribe = useCallback((uploadId: string) => {
    subscribedIdsRef.current.add(uploadId);

    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({
        action: 'subscribe',
        topic: 'upload'
      }));
    }
  }, []);

  /**
   * 특정 업로드 ID 구독 해제
   */
  const unsubscribe = useCallback((uploadId: string) => {
    subscribedIdsRef.current.delete(uploadId);

    // 진행률 맵에서도 제거
    setProgressMap(prev => {
      const newMap = new Map(prev);
      newMap.delete(uploadId);
      return newMap;
    });
  }, []);

  /**
   * 초기 연결 및 정리
   */
  useEffect(() => {
    connect();

    return () => {
      // WebSocket 정리
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }

      // 재연결 타이머 정리
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
    };
  }, [connect]);

  /**
   * 초기 uploadIds 구독
   */
  useEffect(() => {
    uploadIds.forEach(uploadId => subscribe(uploadId));
  }, [uploadIds, subscribe]);

  return {
    progressMap,
    connected,
    error,
    subscribe,
    unsubscribe
  };
};

export default useUploadProgress;
