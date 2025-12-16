/**
 * Moonlight API Client
 * Backend API와 통신하는 함수들
 */

import axios from 'axios';

// Production: Nginx 프록시를 통해 요청 (/api/moonlight/ → localhost:8004)
// Development: Vite dev server proxy 사용
const API_BASE = import.meta.env.VITE_API_BASE_URL || '';  // Empty string = same origin
const MOONLIGHT_API = '/api/moonlight';

const apiClient = axios.create({
  baseURL: API_BASE,
  headers: {
    'Content-Type': 'application/json',
  },
});

// 요청 인터셉터: 인증 토큰 추가 (향후)
apiClient.interceptors.request.use((config) => {
  // TODO: JWT 토큰 추가
  // const token = localStorage.getItem('token');
  // if (token) {
  //   config.headers.Authorization = `Bearer ${token}`;
  // }

  // 임시: X-Username 헤더 (개발용)
  const username = localStorage.getItem('username') || 'testuser';
  config.headers['X-Username'] = username;

  return config;
});

// Image 타입
export interface MoonlightImage {
  id: string;
  name: string;
  description: string;
  icon: string;
  default: boolean;
  available: boolean;
}

// Session 타입
export interface MoonlightSession {
  session_id: string;
  username: string;
  image_id: string;
  image_name: string;
  status: 'pending' | 'running' | 'failed' | 'stopped';
  display_num: number;
  sunshine_port: number;
  job_id?: string;
  created_at: string;
  started_at?: string;
  stopped_at?: string;
  slurm_node?: string;
  error?: string;
}

// Session 생성 요청
export interface CreateSessionRequest {
  image_id: string;
}

// API 함수들

/**
 * 사용 가능한 이미지 목록 조회
 */
export async function getImages(): Promise<MoonlightImage[]> {
  const response = await apiClient.get<{ images: MoonlightImage[] }>(
    `${MOONLIGHT_API}/images`
  );
  return response.data.images;
}

/**
 * 현재 사용자의 세션 목록 조회
 */
export async function getSessions(): Promise<MoonlightSession[]> {
  const response = await apiClient.get<{ sessions: MoonlightSession[] }>(
    `${MOONLIGHT_API}/sessions`
  );
  return response.data.sessions;
}

/**
 * 새 세션 생성
 */
export async function createSession(
  request: CreateSessionRequest
): Promise<MoonlightSession> {
  const response = await apiClient.post<MoonlightSession>(
    `${MOONLIGHT_API}/sessions`,
    request
  );
  return response.data;
}

/**
 * 특정 세션 조회
 */
export async function getSession(sessionId: string): Promise<MoonlightSession> {
  const response = await apiClient.get<MoonlightSession>(
    `${MOONLIGHT_API}/sessions/${sessionId}`
  );
  return response.data;
}

/**
 * 세션 중지
 */
export async function stopSession(sessionId: string): Promise<void> {
  await apiClient.delete(`${MOONLIGHT_API}/sessions/${sessionId}`);
}

/**
 * Health check
 */
export async function healthCheck(): Promise<{ status: string; service: string; port: number }> {
  const response = await apiClient.get(`${MOONLIGHT_API}/health`);
  return response.data;
}
