/**
 * API Configuration - Nginx Reverse Proxy
 *
 * Nginx를 통한 통합 라우팅:
 * - /api -> Dashboard Backend (5010) /api
 * - /ws -> Dashboard WebSocket (5011) /ws
 * - /auth -> Auth Backend (4430) /auth
 */

export const API_CONFIG = {
  // Backend API - Nginx를 통한 상대 경로 (빈 문자열로 설정하여 /api 등을 그대로 사용)
  API_BASE_URL: '',

  // WebSocket - Nginx를 통한 상대 경로
  WS_URL: '/ws',

  // Auth Portal - Nginx를 통한 상대 경로
  AUTH_PORTAL_URL: '/auth',
  AUTH_FRONTEND_URL: '/',  // Root는 Auth Frontend로 라우팅됨

  // Timeout 설정
  TIMEOUT: 30000,

  // Retry 설정
  MAX_RETRIES: 3,
  RETRY_DELAY: 1000,
} as const;

export default API_CONFIG;
