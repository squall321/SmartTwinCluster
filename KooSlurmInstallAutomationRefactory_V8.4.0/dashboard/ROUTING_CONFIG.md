# HPC Portal - Complete Routing Configuration

## 라우팅 아키텍처

모든 서비스는 Nginx 리버스 프록시를 통해 포트 80으로 통합 접근합니다.
각 프론트엔드의 Vite 개발 서버도 동일한 상대 경로를 사용하도록 설정되어 있습니다.

## 서비스 맵핑

### 📱 SSO 로그인 포털 (Phase 1)

| 서비스 | 내부 포트 | Nginx 경로 | 최종 URL |
|--------|-----------|------------|----------|
| Auth Frontend | 4431 | `/` | `http://110.15.177.120/` |
| Auth Backend | 4430 | `/auth` | `http://110.15.177.120/auth` |

**Auth Portal (4431) 설정:**
- API Config: `/auth`, `/dashboardapi`
- Vite Proxy: `/auth` → `localhost:4430`, `/dashboardapi` → `localhost:5010`

---

### 📊 Dashboard (Phase 2-4)

| 서비스 | 내부 포트 | Nginx 경로 | 최종 URL |
|--------|-----------|------------|----------|
| Frontend | 3010 | `/dashboard` | `http://110.15.177.120/dashboard` |
| Backend API | 5010 | `/dashboardapi` | `http://110.15.177.120/dashboardapi` |
| WebSocket | 5011 | `/ws` | `ws://110.15.177.120/ws` |
| Prometheus | 9090 | `/prometheus` | `http://110.15.177.120/prometheus` |
| Node Exporter | 9100 | `/metrics` | `http://110.15.177.120/metrics` |

**Dashboard Frontend (3010) 설정:**
- API Config: `/dashboardapi`, `/ws`, `/auth`
- Vite Proxy:
  - `/dashboardapi` → `localhost:5010/api` (rewrite)
  - `/ws` → `localhost:5011/ws`
  - `/auth` → `localhost:4430/auth`

**Dashboard Backend (5010) 구조:**
- Flask Blueprint 기반
- URL prefix: `/api`
- 예: `/api/vnc/sessions`, `/api/jobs`, `/api/nodes`

---

### 🖥️ VNC Service (Phase 5)

| 서비스 | 내부 포트 | Nginx 경로 | 최종 URL |
|--------|-----------|------------|----------|
| VNC Frontend | 8002 | `/vnc` | `http://110.15.177.120/vnc` |

**VNC Service (8002) 설정:**
- API Calls: `/dashboardapi/vnc/...`로 호출
- Vite Proxy: `/dashboardapi` → `localhost:5010/api` (rewrite)

---

### 🚀 App Framework (Phase 6)

| 서비스 | 내부 포트 | Nginx 경로 | 최종 URL |
|--------|-----------|------------|----------|
| App Frontend | 5174 (dev) / static | `/app` | `http://110.15.177.120/app` |
| App Backend | 5000 (CAE 공유) | `/api/app` | `http://110.15.177.120/api/app` |

**App Framework (5174) 설정:**
- API Calls: `/api/app/...`로 호출 (CAE Backend 5000 공유)
- Vite Config: `base: '/app/'`
- Vite Proxy: `/api` → `localhost:5000/api`
- **Production**: Nginx가 `app_5174/dist/` 정적 파일 서빙
- **Development**: 5174 포트 Vite dev 서버 (HMR 지원)

**관련 문서:**
- [App Framework 셋업 가이드](./APP_5174_SETUP_GUIDE.md)

---

### 🔧 CAE Services (Phase 4)

| 서비스 | 내부 포트 | Nginx 경로 | 최종 URL |
|--------|-----------|------------|----------|
| CAE Frontend | 5173 | `/cae` | `http://110.15.177.120/cae` |
| CAE Backend | 5000 | `/api` | `http://110.15.177.120/api` |
| CAE Automation | 5001 | (프록시됨) | (5000을 통해 접근) |

**CAE Frontend (5173) 설정:**
- API Calls: `/api/...`로 호출
- Vite Proxy: `/api` → `localhost:5000/api`

**CAE Backend (5000):**
- 5001 포트로 프록시 연결됨

---

## Nginx 설정 파일

위치: `/etc/nginx/sites-available/hpc-portal.conf`

### 주요 설정

```nginx
# Dashboard Backend API
location /dashboardapi/ {
    proxy_pass http://dashboard_backend/api/;  # 127.0.0.1:5010
    proxy_http_version 1.1;
    proxy_set_header Authorization $http_authorization;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    # CORS 헤더
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type' always;

    # 타임아웃 설정
    proxy_connect_timeout 120s;
    proxy_read_timeout 120s;
}

# Dashboard WebSocket
location /ws {
    proxy_pass http://dashboard_websocket/ws;  # 127.0.0.1:5011
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;
}

# VNC Service Frontend
location /vnc {
    proxy_pass http://vnc_service/;  # 127.0.0.1:8002
}

# CAE Backend API
location /api {
    proxy_pass http://cae_backend/api;  # 127.0.0.1:5000
}
```

---

## 라우팅 플로우

### 1. VNC 세션 조회 예시

브라우저 → Nginx → VNC Frontend(8002) → Vite Dev Server → Backend(5010)

```
사용자: http://110.15.177.120/vnc
  ↓ (Nginx)
VNC Frontend (8002) 로드
  ↓ (JavaScript fetch)
GET /dashboardapi/vnc/sessions
  ↓ (Vite Proxy: /dashboardapi → /api)
GET http://localhost:5010/api/vnc/sessions
  ↓ (Flask Backend)
200 OK with session data
```

### 2. Dashboard API 호출 예시

```
사용자: http://110.15.177.120/dashboard
  ↓ (Nginx)
Dashboard Frontend (3010) 로드
  ↓ (JavaScript fetch)
GET /dashboardapi/jobs
  ↓ (Vite Proxy: /dashboardapi → /api)
GET http://localhost:5010/api/jobs
  ↓ (Flask Backend)
200 OK with jobs data
```

---

## 프로덕션 vs 개발 환경

### 개발 환경 (Vite Dev Server)
- 각 프론트엔드가 자체 포트에서 실행
- Vite proxy가 API 요청을 백엔드로 전달
- Hot Module Replacement (HMR) 지원

### 프로덕션 환경 (Nginx Only)
- 모든 요청이 Nginx를 통해 라우팅
- 정적 파일은 빌드된 파일 제공
- Vite proxy 사용 안 함 (Nginx가 직접 라우팅)

---

## 문제 해결

### VNC 페이지에서 API 타임아웃 발생
**원인**: Vite proxy 설정에 `/dashboardapi` 경로가 없음
**해결**: vite.config.ts에 다음 추가:
```typescript
'/dashboardapi': {
  target: 'http://localhost:5010',
  changeOrigin: true,
  rewrite: (path) => path.replace(/^\/dashboardapi/, '/api')
}
```

### CORS 에러 발생
**원인**: Nginx에서 CORS 헤더가 설정되지 않음
**해결**: Nginx location 블록에 CORS 헤더 추가

### WebSocket 연결 실패
**원인**: WebSocket 업그레이드 헤더가 전달되지 않음
**해결**: Nginx에 WebSocket 지원 추가:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 86400;
```

---

## 설정 파일 위치

| 서비스 | 설정 파일 |
|--------|-----------|
| Nginx | `/etc/nginx/sites-available/hpc-portal.conf` |
| Auth Portal (4431) | `dashboard/auth_portal_4431/vite.config.ts`<br>`dashboard/auth_portal_4431/src/config/api.config.ts` |
| Dashboard (3010) | `dashboard/frontend_3010/vite.config.ts`<br>`dashboard/frontend_3010/src/config/api.config.ts` |
| VNC Service (8002) | `dashboard/vnc_service_8002/vite.config.ts`<br>`dashboard/vnc_service_8002/src/App.tsx` |
| CAE Frontend (5173) | `dashboard/kooCAEWeb_5173/vite.config.ts` |

---

## 변경 이력

### 2025-10-20
- ✅ Nginx 리버스 프록시 통합 설정 완료
- ✅ Auth Portal (4431) Vite proxy 설정
- ✅ Dashboard Frontend (3010) API config 및 Vite proxy 수정
- ✅ VNC Service (8002) API 호출 경로 변경 및 Vite proxy 설정
- ✅ 모든 프론트엔드에서 상대 경로 사용하도록 통일
- ✅ Authorization 헤더 및 CORS 설정 추가

---

## 테스트 명령어

### Nginx 설정 테스트
```bash
sudo nginx -t
sudo systemctl reload nginx
```

### API 엔드포인트 테스트
```bash
# Auth 테스트
curl -X POST http://110.15.177.120/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}'

# Dashboard API 테스트
curl -H "Authorization: Bearer <token>" \
  http://110.15.177.120/dashboardapi/vnc/sessions

# CAE API 테스트
curl -H "Authorization: Bearer <token>" \
  http://110.15.177.120/api/jobs
```

### 개발 서버 시작
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./start.sh
```

---

**생성일**: 2025-10-20
**작성자**: Claude AI Assistant
**버전**: 1.0
