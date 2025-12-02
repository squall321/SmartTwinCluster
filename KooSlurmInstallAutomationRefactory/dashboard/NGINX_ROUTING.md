# HPC Portal - Nginx Reverse Proxy Routing

모든 서비스가 포트 80을 통해 서브 경로로 접근 가능합니다.

## 📋 라우팅 맵

| 서비스 | 경로 | 백엔드 포트 | 설명 |
|--------|------|-------------|------|
| **Auth Portal (Root)** | `/` | 4431 | 메인 인증 포털 프론트엔드 |
| **Auth Backend** | `/auth` | 4430 | 인증 API |
| **Dashboard** | `/dashboard` | 3010 | 대시보드 프론트엔드 |
| **Dashboard API** | `/dashboardapi` | 5010 | 대시보드 백엔드 API |
| **WebSocket** | `/ws` | 5011 | 실시간 통신 |
| **VNC Service** | `/vnc` | 8002 | VNC 원격 데스크톱 |
| **CAE Frontend** | `/cae` | 5173 | CAE 시뮬레이션 UI |
| **CAE Backend** | `/api` | 5000 | CAE API (5001도 5000으로 프록시) |
| **Prometheus** | `/prometheus` | 9090 | 메트릭 모니터링 |
| **Node Exporter** | `/metrics` | 9100 | 노드 메트릭 |

## 🔗 접근 방법

### 브라우저에서:
```
http://110.15.177.120/              # Auth Portal (메인)
http://110.15.177.120/dashboard     # Dashboard
http://110.15.177.120/vnc           # VNC Service
http://110.15.177.120/cae           # CAE Simulation
http://110.15.177.120/prometheus    # Prometheus
```

### API 호출 (프론트엔드에서):
```javascript
// Auth API
fetch('/auth/login', {...})

// Dashboard API (VNC 포함)
fetch('/dashboardapi/vnc/sessions', {...})
fetch('/dashboardapi/jobs', {...})

// CAE API
fetch('/api/simulations', {...})

// WebSocket
new WebSocket('ws://110.15.177.120/ws')
```

## ⚙️ 설정 파일

- **Nginx 설정**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/nginx/hpc-portal.conf`
- **심볼릭 링크**: `/etc/nginx/sites-enabled/hpc-portal.conf`

## 🔧 Nginx 관리

```bash
# Nginx 재시작
sudo systemctl restart nginx

# Nginx 리로드 (다운타임 없음)
sudo systemctl reload nginx

# Nginx 상태 확인
sudo systemctl status nginx

# 설정 테스트
sudo nginx -t

# 로그 확인
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## 🔒 CORS 및 인증

- 모든 API는 JWT 토큰으로 인증
- Nginx가 모든 요청에 적절한 헤더 추가:
  - `X-Real-IP`
  - `X-Forwarded-For`
  - `X-Forwarded-Proto`
- 백엔드 CORS 설정은 `*` (모든 오리진 허용)

## 📝 프론트엔드 API 설정

### Auth Portal (`auth_portal_4431/src/config/api.config.ts`):
```typescript
export const API_CONFIG = {
  API_BASE_URL: '/auth',
  VNC_API_BASE_URL: '/dashboardapi',
  DASHBOARD_URL: '/dashboard',
  VNC_SERVICE_URL: '/vnc',
  CAE_URL: '/cae',
}
```

### VNCPage.tsx:
```typescript
const API_URL = `${API_CONFIG.VNC_API_BASE_URL}/vnc`;
// Results in: /dashboardapi/vnc/sessions
```

## 🧪 테스트

```bash
# Auth Portal 접근
curl http://110.15.177.120/

# VNC API 접근 (JWT 토큰 필요)
curl -H "Authorization: Bearer <token>" http://110.15.177.120/dashboardapi/vnc/sessions

# Dashboard API
curl http://110.15.177.120/dashboardapi/nodes

# Prometheus
curl http://110.15.177.120/prometheus/
```

## 🚀 시작하기

1. 모든 백엔드 서비스가 실행 중인지 확인:
   ```bash
   cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
   ./start.sh
   ```

2. Nginx 실행 확인:
   ```bash
   sudo systemctl status nginx
   ```

3. 브라우저에서 접속:
   ```
   http://110.15.177.120/
   ```

## ⚠️ 주의사항

- **포트 80**이 사용 가능해야 합니다
- 모든 백엔드 서비스가 **localhost**에서 실행되어야 합니다
- JWT 토큰은 **localStorage**에 `jwt_token` 키로 저장됩니다
- WebSocket 연결은 **ws://** 프로토콜 사용

## 🐛 문제 해결

### VNC 세션이 로드되지 않는 경우:
1. Backend 5010이 실행 중인지 확인
2. Nginx 로그 확인: `sudo tail -f /var/log/nginx/error.log`
3. 브라우저 F12 > Network 탭에서 `/dashboardapi/vnc/sessions` 요청 확인
4. JWT 토큰이 localStorage에 있는지 확인

### 401 Unauthorized 에러:
1. 로그인 다시 시도
2. JWT 토큰 만료 확인
3. Backend 로그 확인: `tail -f dashboard/backend_5010/logs/backend.log`
