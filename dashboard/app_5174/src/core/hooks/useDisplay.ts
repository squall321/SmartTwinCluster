/**
 * useDisplay Hook
 *
 * Display (noVNC) 연결 관리 - standalone PWA 페이지 redirect
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import type { DisplayConfig, DisplayStatus, DisplayStats } from '@core/types';

export interface UseDisplayOptions {
  /** Display URL */
  displayUrl?: string;

  /** Session ID */
  sessionId?: string;

  /** Display 설정 */
  config: DisplayConfig;

  /** 자동 연결 여부 */
  autoConnect?: boolean;

  /** 연결 콜백 */
  onConnected?: () => void;
  onDisconnected?: () => void;
  onError?: (error: Error) => void;
}

export interface UseDisplayReturn {
  /** 연결 상태 */
  status: DisplayStatus;

  /** 통계 */
  stats: DisplayStats | null;

  /** 연결 */
  connect: () => void;

  /** 연결 해제 */
  disconnect: () => void;

  /** 전체화면 토글 */
  toggleFullscreen: () => void;

  /** 품질 조정 */
  setQuality: (quality: number) => void;

  /** 압축 조정 */
  setCompression: (compression: number) => void;

  /** Display 컨테이너 Ref */
  containerRef: React.RefObject<HTMLDivElement>;

  /** iframe Ref (호환성 유지) */
  iframeRef: React.RefObject<HTMLIFrameElement>;
}

/**
 * useDisplay Hook - iframe 임베딩 방식 + 준비 상태 폴링
 */
export function useDisplay(options: UseDisplayOptions): UseDisplayReturn {
  const {
    displayUrl,
    sessionId,
    onConnected,
    onDisconnected,
    onError,
  } = options;

  const [status, setStatus] = useState<DisplayStatus>('disconnected');
  const [stats, setStats] = useState<DisplayStats | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const pollingIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  /**
   * VNC 서버 준비 상태 확인
   */
  const checkVncReady = async (url: string): Promise<boolean> => {
    try {
      const response = await fetch(url.replace('/vnc.html', '/'), {
        method: 'HEAD',
        mode: 'no-cors', // CORS 우회
      });
      return true; // no-cors mode에서는 항상 opaque response
    } catch (error) {
      return false;
    }
  };

  /**
   * 연결 - Standalone PWA 페이지로 redirect
   */
  const connect = useCallback(() => {
    if (!sessionId) {
      onError?.(new Error('Session ID not available'));
      return;
    }

    console.log('[useDisplay] Redirecting to standalone PWA page for session:', sessionId);
    setStatus('connecting');

    try {
      // Standalone PWA 페이지로 redirect
      const standalonePage = `/apps/gedit/index.html?sessionId=${sessionId}`;
      window.open(standalonePage, '_blank');

      setStatus('connected');
      onConnected?.();
      startStatsCollection();
    } catch (error) {
      console.error('[useDisplay] Error opening standalone page:', error);
      setStatus('error');
      onError?.(error instanceof Error ? error : new Error('Failed to open standalone page'));
    }
  }, [sessionId, onConnected, onError]);

  /**
   * 연결 해제
   */
  const disconnect = useCallback(() => {
    // 폴링 중지
    if (pollingIntervalRef.current) {
      clearInterval(pollingIntervalRef.current);
      pollingIntervalRef.current = null;
    }

    // iframe src 제거
    if (iframeRef.current) {
      iframeRef.current.src = 'about:blank';
    }

    setStatus('disconnected');
    setStats(null);
    onDisconnected?.();
  }, [onDisconnected]);

  /**
   * 통계 수집 시작 (Mock)
   */
  const startStatsCollection = () => {
    // Mock 통계
    const statsInterval = setInterval(() => {
      if (status !== 'connected') {
        clearInterval(statsInterval);
        return;
      }

      setStats({
        latency: 30 + Math.random() * 20, // 30-50ms
        fps: 25 + Math.random() * 10, // 25-35 fps
        bandwidth: (500 + Math.random() * 500) * 1024, // 500-1000 KB/s
        dropped_frames: Math.floor(Math.random() * 3),
      });
    }, 1000);

    return () => clearInterval(statsInterval);
  };

  /**
   * 전체화면 토글
   */
  const toggleFullscreen = useCallback(() => {
    console.log('[useDisplay] Fullscreen toggle - not implemented for window.open mode');
  }, []);

  /**
   * 품질 조정
   */
  const setQuality = useCallback((quality: number) => {
    console.log('[useDisplay] Quality set to:', quality);
  }, []);

  /**
   * 압축 조정
   */
  const setCompression = useCallback((compression: number) => {
    console.log('[useDisplay] Compression set to:', compression);
  }, []);

  return {
    status,
    stats,
    connect,
    disconnect,
    toggleFullscreen,
    setQuality,
    setCompression,
    containerRef: containerRef as React.RefObject<HTMLDivElement>,
    iframeRef: iframeRef as React.RefObject<HTMLIFrameElement>,
  };
}
