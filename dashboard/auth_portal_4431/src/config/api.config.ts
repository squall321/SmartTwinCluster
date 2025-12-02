/**
 * Auth Portal API Configuration
 *
 * Nginx 리버스 프록시를 통해 모든 서비스에 접근:
 * - /auth -> Auth Backend (4430)
 * - /dashboardapi -> Dashboard Backend (5010)
 * - /vnc -> VNC Service (8002)
 * - /cae -> CAE Frontend (5173)
 * - /api -> CAE Backend (5000)
 */

export const API_CONFIG = {
  // Nginx를 통한 상대 경로 사용
  API_BASE_URL: '/auth',
  VNC_API_BASE_URL: '/dashboardapi',
  DASHBOARD_URL: '/dashboard',
  VNC_SERVICE_URL: '/vnc',
  CAE_URL: '/cae',
  TIMEOUT: 30000,
} as const;

export default API_CONFIG;
