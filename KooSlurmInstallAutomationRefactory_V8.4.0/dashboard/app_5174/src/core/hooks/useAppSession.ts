/**
 * useAppSession Hook
 *
 * 앱 세션 생명주기 관리
 */

import { useState, useCallback, useEffect } from 'react';
import { apiService } from '@core/services/api.service';
import type {
  AppSession,
  AppConfig,
  CreateSessionRequest,
  SessionStatus,
} from '@core/types';

export interface UseAppSessionOptions {
  /** 앱 ID */
  appId: string;

  /** 앱 설정 */
  config: AppConfig;

  /** 기존 세션 ID (재연결용) */
  sessionId?: string;

  /** 자동 시작 여부 */
  autoStart?: boolean;

  /** 생명주기 콜백 */
  onSessionCreated?: (session: AppSession) => void;
  onSessionReady?: (session: AppSession) => void;
  onSessionError?: (error: Error) => void;
  onSessionClosed?: () => void;
}

export interface UseAppSessionReturn {
  /** 현재 세션 */
  session: AppSession | null;

  /** 로딩 상태 */
  loading: boolean;

  /** 에러 */
  error: Error | null;

  /** 세션 생성 */
  createSession: () => Promise<void>;

  /** 세션 종료 */
  destroySession: () => Promise<void>;

  /** 세션 재시작 */
  restartSession: () => Promise<void>;

  /** 세션 정보 갱신 */
  refreshSession: () => Promise<void>;
}

/**
 * useAppSession Hook
 */
export function useAppSession(
  options: UseAppSessionOptions
): UseAppSessionReturn {
  const {
    appId,
    config,
    sessionId: existingSessionId,
    autoStart = false,
    onSessionCreated,
    onSessionReady,
    onSessionError,
    onSessionClosed,
  } = options;

  const [session, setSession] = useState<AppSession | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  /**
   * 세션 생성
   */
  const createSession = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const request: CreateSessionRequest = {
        appId,
        config,
      };

      const response = await apiService.createSession(request);
      const newSession = response.session;

      setSession(newSession);
      onSessionCreated?.(newSession);

      // 세션이 running 상태가 될 때까지 폴링
      await pollSessionUntilReady(newSession.sessionId);
    } catch (err) {
      const error = err instanceof Error ? err : new Error('Failed to create session');
      setError(error);
      onSessionError?.(error);
    } finally {
      setLoading(false);
    }
  }, [appId, config, onSessionCreated, onSessionError]);

  /**
   * 세션 종료
   */
  const destroySession = useCallback(async () => {
    if (!session) return;

    setLoading(true);
    setError(null);

    try {
      await apiService.deleteSession(session.sessionId);
      setSession(null);
      onSessionClosed?.();
    } catch (err) {
      const error = err instanceof Error ? err : new Error('Failed to destroy session');
      setError(error);
      onSessionError?.(error);
    } finally {
      setLoading(false);
    }
  }, [session, onSessionClosed, onSessionError]);

  /**
   * 세션 재시작
   */
  const restartSession = useCallback(async () => {
    if (!session) return;

    setLoading(true);
    setError(null);

    try {
      const restarted = await apiService.restartSession(session.sessionId);
      setSession(restarted);
      await pollSessionUntilReady(restarted.sessionId);
    } catch (err) {
      const error = err instanceof Error ? err : new Error('Failed to restart session');
      setError(error);
      onSessionError?.(error);
    } finally {
      setLoading(false);
    }
  }, [session, onSessionError]);

  /**
   * 세션 정보 갱신
   */
  const refreshSession = useCallback(async () => {
    if (!session) return;

    try {
      const updated = await apiService.getSession(session.sessionId);
      setSession(updated);
    } catch (err) {
      const error = err instanceof Error ? err : new Error('Failed to refresh session');
      setError(error);
      onSessionError?.(error);
    }
  }, [session, onSessionError]);

  /**
   * 세션 상태 폴링 (running 될 때까지)
   */
  const pollSessionUntilReady = async (sessionId: string): Promise<void> => {
    const maxAttempts = 30; // 최대 30초
    const interval = 1000; // 1초 간격

    for (let i = 0; i < maxAttempts; i++) {
      const updated = await apiService.getSession(sessionId);
      setSession(updated);

      if (updated.status === 'running') {
        onSessionReady?.(updated);
        return;
      }

      if (updated.status === 'error') {
        throw new Error('Session failed to start');
      }

      await new Promise(resolve => setTimeout(resolve, interval));
    }

    throw new Error('Session start timeout');
  };

  /**
   * 기존 세션 복원 또는 자동 시작
   */
  useEffect(() => {
    if (existingSessionId) {
      // 기존 세션 복원
      refreshSession();
    } else if (autoStart) {
      // 자동 시작
      createSession();
    }
  }, [existingSessionId, autoStart]);

  return {
    session,
    loading,
    error,
    createSession,
    destroySession,
    restartSession,
    refreshSession,
  };
}
