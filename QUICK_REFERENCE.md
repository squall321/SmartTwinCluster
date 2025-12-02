# HPC Cluster Dashboard - 빠른 참조 가이드

## 📍 주요 접속 URL

| URL | 서비스 | 설명 |
|-----|--------|------|
| https://110.15.177.120/ | 로그인 페이지 | SSO/Developer 로그인 |
| https://110.15.177.120/dashboard | 메인 대시보드 | 클러스터 관리 |
| https://110.15.177.120/vnc | VNC 서비스 | VNC 세션 관리 |
| https://110.15.177.120/cae | CAE 웹 | CAE 인터페이스 |
| https://110.15.177.120/app | 앱 런처 | 애플리케이션 |

## 🔑 테스트 계정

### Developer Test Login
- **HPC-Admins**: 전체 관리자 권한
- **DX-Users**: 일반 사용자 (Dashboard, VNC, SSH)
- **CAEG-Users**: CAE 사용자 (CAE, Dashboard, VNC, SSH)

### SAML SSO Login (7000 포트)
| 이메일 | 비밀번호 | 그룹 |
|--------|---------|------|
| koopark@hpc.local | admin123 | HPC-Admins |
| dx_user@hpc.local | password123 | DX-Users |
| caeg_user@hpc.local | password123 | CAEG-Users |

## 🔌 포트 매핑 (핵심만)

| 포트 | 서비스 | 타입 |
|------|--------|------|
| 4430 | Auth Backend | Python API |
| 4431 | Auth Frontend | Node.js (dev) |
| 5010 | Dashboard Backend | Python + SocketIO |
| 5011 | WebSocket | 실시간 데이터 |
| 7000 | SAML IdP | 테스트용 |

## 🗄️ Redis

```bash
# 접속
REDISCLI_AUTH=changeme redis-cli

# VNC 세션 조회
KEYS vnc:session:*
GET vnc:session:<session_id>

# SSH 세션 조회
KEYS ssh:session:*
```

## 🔧 주요 명령어

### 서비스 상태
```bash
systemctl status auth_backend dashboard_backend websocket_service
```

### Nginx
```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 프론트엔드 빌드
```bash
cd dashboard/<service_name>
npm run build
sudo cp -r dist/* /var/www/html/<service_name>/
```

### Setup 실행
```bash
cd cluster/setup
sudo ./phase5_web.sh
```

## 🐛 문제 해결

### 인증 실패
1. Redis 상태 확인: `systemctl status redis-server`
2. JWT 토큰 확인: localStorage에 'jwt_token' 있는지
3. Backend 로그: `sudo journalctl -u auth_backend -n 50`

### API 404
1. Nginx 설정: `/etc/nginx/conf.d/auth-portal.conf`
2. Backend 실행: `systemctl status dashboard_backend`
3. API 경로 확인: `/api/*`, `/socket.io/*`

### WebSocket 연결 실패
1. `/socket.io/` 프록시 확인
2. Backend SocketIO 실행 확인
3. 브라우저 콘솔 에러 확인

### 세션 없음
1. Redis 연결: `REDISCLI_AUTH=changeme redis-cli ping`
2. 세션 키 확인: `KEYS vnc:session:*`
3. Backend .env 파일 확인: `REDIS_PASSWORD=changeme`

## 📂 중요 파일 위치

```
/home/koopark/claude/KooSlurmInstallAutomationRefactory/
├── cluster/setup/phase5_web.sh         # Setup 스크립트
├── dashboard/
│   ├── auth_portal_4430/               # Auth Backend
│   ├── auth_portal_4431/               # Auth Frontend
│   ├── backend_5010/                   # Dashboard Backend
│   ├── frontend_3010/                  # Dashboard Frontend
│   ├── vnc_service_8002/               # VNC Service
│   └── saml_idp_7000/config.js         # SAML 사용자 DB
└── /var/www/html/                      # Nginx 정적 파일
    ├── dashboard/
    ├── vnc_service_8002/
    └── ...
```

## 📊 아키텍처 (간단)

```
브라우저 → Nginx (443)
           ├→ / (Auth 4431)
           ├→ /auth (Auth Backend 4430)
           ├→ /dashboard (정적)
           ├→ /api (Backend 5010)
           ├→ /socket.io (SocketIO 5010)
           ├→ /ws (WebSocket 5011)
           └→ /vnc (정적)

백엔드 ↔ Redis (세션)
       ↔ MariaDB (영구 데이터)
       ↔ Slurm (클러스터)
```

## 🔄 데이터 흐름

### 로그인
```
사용자 → Auth Frontend → Auth Backend → JWT 발급 → localStorage 저장
```

### API 호출
```
Dashboard → Nginx /api → Backend 5010 (JWT 검증) → Redis/Slurm → 응답
```

### VNC 세션
```
VNC Frontend → POST /dashboardapi/vnc/sessions
→ Backend → Slurm Job 실행
→ Redis에 세션 저장
→ Frontend Polling → Readiness 확인
→ noVNC 연결 (/vncproxy/<port>/)
```

### SSH 터미널
```
SSH Manager → POST /api/ssh/sessions
→ SocketIO 연결 (/socket.io/)
→ namespace: /ssh-ws
→ Backend SSH 프로세스
→ Target Node
```

---

**상세 내용**: `PROJECT_STATUS.md` 참조

