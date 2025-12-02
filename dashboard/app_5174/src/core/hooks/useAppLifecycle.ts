/**
 * useAppLifecycle Hook
 *
 * 앱 생명주기 전체 관리 (Session + Display + WebSocket 통합)
 */

import { useCallback, useEffect } from 'react';
import { useAppSession, UseAppSessionOptions } from './useAppSession';
import { useDisplay, UseDisplayOptions } from './useDisplay';
import { useWebSocket, UseWebSocketOptions } from './useWebSocket';
import type { AppConfig, DisplayConfig } from '@core/types';

export interface UseAppLifecycleOptions {
  /** 앱 ID */
  appId: string;

  /** 앱 설정 */
  config: AppConfig;

  /** Display 설정 */
  displayConfig: DisplayConfig;

  /** 기존 세션 ID */
  sessionId?: string;

  /** 자동 시작 여부 */
  autoStart?: boolean;

  /** 생명주기 콜백 */
  onReady?: () => void;
  onError?: (error: Error) => void;
  onClosed?: () => void;
}

export interface UseAppLifecycleReturn {
  /** 세션 Hook */
  session: ReturnType<typeof useAppSession>;

  /** Display Hook */
  display: ReturnType<typeof useDisplay>;

  /** WebSocket Hook */
  websocket: ReturnType<typeof useWebSocket>;

  /** 전체 준비 상태 */
  ready: boolean;

  /** 전체 시작 */
  start: () => Promise<void>;

  /** 전체 종료 */
  stop: () => Promise<void>;
}

/**
 * useAppLifecycle Hook
 *
 * 세션 생성 → Display 연결 → WebSocket 연결을 순차적으로 수행
 */
export function useAppLifecycle(
  options: UseAppLifecycleOptions
): UseAppLifecycleReturn {
  const {
    appId,
    config,
    displayConfig,
    sessionId: existingSessionId,
    autoStart = false,
    onReady,
    onError,
    onClosed,
  } = options;

  // 1. Session Hook
  const session = useAppSession({
    appId,
    config,
    sessionId: existingSessionId,
    autoStart: false, // 수동 제어
    onSessionReady: (session) => {
      console.log('[useAppLifecycle] Session ready, connecting display...');
      // Display 자동 연결은 useEffect에서 처리
    },
    onSessionError: (error) => {
      console.error('[useAppLifecycle] Session error:', error);
      onError?.(error);
    },
    onSessionClosed: () => {
      console.log('[useAppLifecycle] Session closed');
      display.disconnect();
      websocket.disconnect();
      onClosed?.();
    },
  });

  // 2. Display Hook
  const display = useDisplay({
    displayUrl: session.session?.displayUrl,
    config: displayConfig,
    autoConnect: false, // 수동 제어
    onConnected: () => {
      console.log('[useAppLifecycle] Display connected, connecting websocket...');
      // WebSocket 자동 연결은 useEffect에서 처리
    },
    onError: (error) => {
      console.error('[useAppLifecycle] Display error:', error);
      onError?.(error);
    },
  });

  // 3. WebSocket Hook
  const websocket = useWebSocket({
    url: session.session?.websocketUrl,
    autoConnect: false, // 수동 제어
    onOpen: () => {
      console.log('[useAppLifecycle] WebSocket connected, app ready!');
      onReady?.();
    },
    onError: (error) => {
      console.error('[useAppLifecycle] WebSocket error:', error);
    },
  });

  /**
   * 전체 시작
   */
  const start = useCallback(async () => {
    try {
      // 1단계: 세션 생성
      await session.createSession();
      // 이후 단계는 useEffect에서 자동 진행
    } catch (error) {
      onError?.(error instanceof Error ? error : new Error('Failed to start app'));
    }
  }, [session, onError]);

  /**
   * 전체 종료
   */
  const stop = useCallback(async () => {
    websocket.disconnect();
    display.disconnect();
    await session.destroySession();
  }, [session, display, websocket]);

  /**
   * 세션 준비 완료 → Display 연결
   */
  useEffect(() => {
    if (session.session?.status === 'running' && display.status === 'disconnected') {
      console.log('[useAppLifecycle] Auto-connecting display...');
      display.connect();
    }
  }, [session.session?.status, display.status]);

  /**
   * Display 연결 완료 → WebSocket 연결
   */
  useEffect(() => {
    if (display.status === 'connected' && !websocket.connected) {
      console.log('[useAppLifecycle] Auto-connecting websocket...');
      websocket.connect();
    }
  }, [display.status, websocket.connected]);

  /**
   * 자동 시작
   */
  useEffect(() => {
    if (autoStart) {
      start();
    }
  }, [autoStart]);

  /**
   * 전체 준비 상태
   */
  const ready =
    session.session?.status === 'running' &&
    display.status === 'connected' &&
    websocket.connected;

  return {
    session,
    display,
    websocket,
    ready,
    start,
    stop,
  };
}
