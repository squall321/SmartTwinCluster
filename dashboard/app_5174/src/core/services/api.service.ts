/**
 * API Service
 * - kooCAEWebServer_5000 백엔드 통신
 */

import type {
  AppSession,
  CreateSessionRequest,
  CreateSessionResponse,
  ListSessionsResponse,
} from '@core/types';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api';

/**
 * HTTP 요청 헬퍼
 */
async function request<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  const url = `${API_BASE_URL}${endpoint}`;

  const defaultHeaders: HeadersInit = {
    'Content-Type': 'application/json',
  };

  // JWT 토큰 (필요 시)
  const token = localStorage.getItem('jwt_token');
  if (token) {
    defaultHeaders['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch(url, {
    ...options,
    headers: {
      ...defaultHeaders,
      ...options.headers,
    },
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({
      message: response.statusText,
    }));
    throw new Error(error.message || `HTTP ${response.status}`);
  }

  return response.json();
}

/**
 * API Client
 */
export const apiService = {
  /**
   * 세션 생성
   */
  async createSession(
    sessionRequest: CreateSessionRequest
  ): Promise<CreateSessionResponse> {
    const response = await request<any>('/app/sessions', {
      method: 'POST',
      body: JSON.stringify(sessionRequest),
    });
    // Backend 응답 형식: { success: true, session: {...} }
    const session = response.session || response;
    // Backend는 id를 반환하지만 Frontend는 sessionId 기대
    if (session.id && !session.sessionId) {
      session.sessionId = session.id;
    }
    // userId가 없으면 기본값 설정
    if (!session.userId) {
      session.userId = 'default-user';
    }
    return { session };
  },

  /**
   * 세션 목록 조회
   */
  async listSessions(): Promise<ListSessionsResponse> {
    return await request<ListSessionsResponse>('/app/sessions');
  },

  /**
   * 세션 상세 조회
   */
  async getSession(sessionId: string): Promise<AppSession> {
    const response = await request<any>(`/app/sessions/${sessionId}`);
    // Backend 응답 형식: { success: true, session: {...} }
    const session = response.session || response;
    // Backend는 id를 반환하지만 Frontend는 sessionId 기대
    if (session.id && !session.sessionId) {
      session.sessionId = session.id;
    }
    // userId가 없으면 기본값 설정
    if (!session.userId) {
      session.userId = 'default-user';
    }
    return session;
  },

  /**
   * 세션 종료
   */
  async deleteSession(sessionId: string): Promise<void> {
    await request(`/app/sessions/${sessionId}`, {
      method: 'DELETE',
    });
  },

  /**
   * 세션 재시작
   */
  async restartSession(sessionId: string): Promise<AppSession> {
    return await request<AppSession>(`/app/sessions/${sessionId}/restart`, {
      method: 'POST',
    });
  },

  /**
   * 앱 목록 조회
   */
  async listApps(): Promise<any> {
    const response = await request<any>('/app/apps');
    // Backend 응답 형식: { success: true, apps: [...] }
    return response.apps || response;
  },

  /**
   * 앱 상세 정보
   */
  async getAppInfo(appId: string): Promise<any> {
    const response = await request<any>(`/app/apps/${appId}`);
    // Backend 응답 형식: { success: true, app: {...} }
    return response.app || response;
  },
};
