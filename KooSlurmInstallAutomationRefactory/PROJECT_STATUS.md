# HPC Cluster Dashboard - 전체 프로젝트 개발 현황 문서

**작성일**: 2025-11-02  
**프로젝트 경로**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory`

---

## 📋 목차

1. [시스템 아키텍처 개요](#시스템-아키텍처-개요)
2. [인증 시스템 (SSO/JWT)](#인증-시스템-ssojwt)
3. [Redis 세션 관리](#redis-세션-관리)
4. [백엔드 서비스](#백엔드-서비스)
5. [프론트엔드 서비스](#프론트엔드-서비스)
6. [Nginx 라우팅 구조](#nginx-라우팅-구조)
7. [데이터베이스](#데이터베이스)
8. [WebSocket 연결](#websocket-연결)
9. [모니터링](#모니터링)
10. [서비스 간 연관관계](#서비스-간-연관관계)
11. [Setup 자동화](#setup-자동화)

---

## 시스템 아키텍처 개요

```
[사용자 브라우저]
       ↓
    HTTPS (443)
       ↓
   [Nginx Reverse Proxy]
       ├─→ / (Auth Frontend - 4431) → JWT 발급
       ├─→ /auth (Auth Backend - 4430) → SSO/JWT 인증
       ├─→ /dashboard (Dashboard Frontend - 3010) → 빌드된 정적 파일
       ├─→ /api (Dashboard Backend - 5010) → REST API
       ├─→ /socket.io (Dashboard Backend - 5010) → SSH WebSocket
       ├─→ /ws (WebSocket Service - 5011) → 실시간 데이터
       ├─→ /vnc (VNC Service - 8002) → VNC 관리
       ├─→ /cae (CAE Frontend - 5173) → CAE 웹
       ├─→ /cae/api (CAE Backend - 5000) → CAE API
       └─→ /vncproxy (동적 VNC 프록시) → noVNC 세션
       
[Redis] ←→ [모든 백엔드 서비스] (세션 저장)
[MariaDB] ←→ [백엔드 서비스] (영구 데이터)
[Slurm] ←→ [Dashboard Backend] (클러스터 관리)
```

---

## 인증 시스템 (SSO/JWT)

### 인증 흐름

```
1. 사용자 접속
   https://110.15.177.120/ 
   ↓
2. Auth Frontend (4431) 로그인 페이지 표시
   - Developer Test Login (로컬 JWT 발급)
   - Sign in with SSO (SAML IdP 연동)
   ↓
3. 인증 방식 선택
   
   [방식 A] Developer Test Login
   → Auth Backend (4430) /auth/dev-login
   → JWT 토큰 발급
   → localStorage에 'jwt_token' 저장
   
   [방식 B] SAML SSO
   → SAML IdP (7000) 리다이렉트
   → 사용자 인증 (config.js 사용자 DB)
   → SAML Response 생성
   → Auth Backend (4430) /auth/saml/acs
   → JWT 토큰 발급
   → localStorage에 'jwt_token' 저장
   
4. 토큰과 함께 Dashboard 리다이렉트
   https://110.15.177.120/dashboard?token=xxx
   ↓
5. Dashboard Frontend가 토큰 저장 후 URL에서 제거
   localStorage.setItem('jwt_token', token)
   ↓
6. 모든 API 요청에 토큰 포함
   Authorization: Bearer <jwt_token>
```

### JWT 구조

```json
{
  "sub": "koopark",
  "email": "koopark@hpc.local",
  "groups": ["HPC-Admins"],
  "permissions": ["vnc:create", "vnc:read", "vnc:delete"],
  "exp": 1760741566
}
```

### 그룹별 권한

| 그룹 | 권한 | 접근 가능 메뉴 |
|------|------|---------------|
| HPC-Admins | 전체 관리자 | 모든 메뉴 (Cluster Mgmt, Node Mgmt, VNC, SSH, Metrics, Reports 등) |
| DX-Users | 일반 사용자 | Dashboard, Monitoring, VNC Sessions, SSH Sessions |
| CAEG-Users | CAE 사용자 | CAE 페이지, Dashboard, VNC Sessions, SSH Sessions |

### 관련 파일

**Auth Backend (4430)**:
- `dashboard/auth_portal_4430/app.py` - Flask 서버
- `dashboard/auth_portal_4430/middleware/jwt_middleware.py` - JWT 검증
- `dashboard/auth_portal_4430/config/groups.json` - 그룹 권한 정의

**Auth Frontend (4431)**:
- `dashboard/auth_portal_4431/src/pages/LoginPage.tsx` - 로그인 페이지
- `dashboard/auth_portal_4431/src/context/AuthContext.tsx` - 인증 상태 관리

**SAML IdP (7000)**:
- `dashboard/saml_idp_7000/config.js` - 사용자 DB (JavaScript module.exports)
- `dashboard/saml_idp_7000/certs/` - SSL 인증서

---

## Redis 세션 관리

### Redis 설정

- **호스트**: localhost
- **포트**: 6379
- **비밀번호**: `changeme`
- **설정파일**: `/etc/redis/redis.conf`

### 환경변수 (.env 파일)

모든 백엔드 서비스의 `.env` 파일에 Redis 설정:
```bash
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=changeme
```

### 세션 저장 구조

#### VNC 세션
```
Key: vnc:session:<session_id>
Type: string (JSON)
Value: {
  "session_id": "vnc-koopark-1762044387",
  "job_id": 398,
  "username": "koopark",
  "email": "koopark@hpc.local",
  "image_id": "xfce4",
  "vnc_port": 5989,
  "novnc_port": 6989,
  "geometry": "1920x1080",
  "status": "running",
  "node": "192.168.122.252",
  "novnc_url": "/vncproxy/6989/vnc.html",
  "created_at": "2025-11-02T00:46:27",
  "_service": "vnc"
}
```

#### SSH 세션
```
Key: ssh:session:<session_id>
Type: string (JSON)
Value: {
  "session_id": "ssh-koopark-xxx",
  "username": "koopark",
  "node": "node001",
  "status": "connected",
  "created_at": "2025-11-02T01:00:00"
}
```

### Redis 명령어

```bash
# Redis 접속
REDISCLI_AUTH=changeme redis-cli

# 모든 키 조회
KEYS *

# VNC 세션 조회
KEYS vnc:session:*

# 특정 세션 데이터 조회
GET vnc:session:vnc-koopark-1762044387

# 세션 삭제
DEL vnc:session:vnc-koopark-1762044387
```

### 관련 파일

- `dashboard/backend_5010/vnc_api.py` - VNC 세션 Redis 관리
- `dashboard/backend_5010/ssh_api.py` - SSH 세션 관리
- `dashboard/kooCAEWebServer_5000/services/vnc_session_service.py` - VNC Redis 서비스

---

## 백엔드 서비스

### 1. Auth Backend (Port 4430)

**목적**: 인증 및 권한 관리

**기술 스택**: Python Flask

**주요 API**:
- `POST /auth/dev-login` - Developer 로그인
- `POST /auth/saml/acs` - SAML 인증 콜백
- `GET /auth/validate` - JWT 토큰 검증

**환경변수**:
```bash
JWT_SECRET_KEY=your-secret-key-change-this-in-production
JWT_EXPIRATION_HOURS=720
REDIS_PASSWORD=changeme
```

**파일 위치**: `dashboard/auth_portal_4430/`

---

### 2. Dashboard Backend (Port 5010)

**목적**: 클러스터 관리, VNC/SSH 세션, 모니터링

**기술 스택**: Python Flask + SocketIO

**주요 API**:
- `/api/slurm/*` - Slurm 클러스터 관리
- `/api/vnc/*` - VNC 세션 CRUD
- `/api/ssh/*` - SSH 세션 CRUD
- `/api/nodes/*` - 노드 관리
- `/api/cluster/*` - 클러스터 설정
- `/socket.io/` - SSH WebSocket namespace `/ssh-ws`

**Blueprint 구조**:
```python
# app.py에 등록된 Blueprint들
from vnc_api import vnc_bp          # /api/vnc
from ssh_api import ssh_bp          # /api/ssh
from node_api import node_bp        # /api/nodes
from cluster_config_api import cluster_config_bp  # /api/cluster
from prometheus_api import prometheus_bp  # /api/prometheus
from ssh_websocket import init_ssh_websocket  # SocketIO /ssh-ws
```

**환경변수**:
```bash
MOCK_MODE=false
PORT=5010
REDIS_PASSWORD=changeme
SLURM_BIN_DIR=/usr/local/slurm/bin
```

**파일 위치**: `dashboard/backend_5010/`

---

### 3. CAE Backend (Port 5000)

**목적**: CAE 애플리케이션 세션 관리

**기술 스택**: Python Flask

**주요 API**:
- `/api/apps` - 앱 목록
- `/api/sessions` - CAE 세션 관리

**파일 위치**: `dashboard/kooCAEWebServer_5000/`

---

### 4. CAE Automation (Port 5001)

**목적**: CAE 자동화 워크플로우

**파일 위치**: `dashboard/kooCAEWebAutomationServer_5001/`

---

### 5. WebSocket Service (Port 5011)

**목적**: 실시간 모니터링 데이터 스트리밍

**기술 스택**: Python WebSocket

**네임스페이스**: `/ws`

**파일 위치**: `dashboard/websocket_5011/`

---

## 프론트엔드 서비스

### 빌드 방식

**중요**: 모든 프론트엔드는 **정적 파일로 빌드**되어 Nginx가 서빙합니다.
- ❌ `npm run dev` (개발 모드) 사용 안 함
- ✅ `npm run build` → `/var/www/html/<service>/`로 배포

### 1. Auth Frontend (Port 4431 - Dev 모드)

**⚠️ 유일하게 dev 모드로 실행되는 서비스**

**목적**: SSO 로그인 페이지

**기술 스택**: React + TypeScript + Vite

**systemd 서비스**: `auth_frontend.service`

**빌드 위치**: `/var/www/html/auth_portal_4431/`

**주요 컴포넌트**:
- `LoginPage.tsx` - 로그인 페이지
  - Developer Test Login (3가지 그룹 선택)
  - Sign in with SSO (SAML)

**파일 위치**: `dashboard/auth_portal_4431/`

---

### 2. Dashboard Frontend (정적 빌드)

**접근 URL**: `https://110.15.177.120/dashboard`

**목적**: 메인 대시보드

**기술 스택**: React + TypeScript + Vite

**빌드 위치**: `/var/www/html/dashboard/`

**주요 컴포넌트**:
- `Dashboard.tsx` - 메인 대시보드
- `ClusterManagement.tsx` - 클러스터 관리 (Admin only)
- `NodeManagement.tsx` - 노드 관리 (Admin only)
- `VNCSessionManager.tsx` - VNC 세션 관리
- `SSHSessionManager.tsx` - SSH 세션 관리
- `SSHTerminal.tsx` - SSH 웹 터미널 (SocketIO)
- `PrometheusMetrics.tsx` - 모니터링 (Admin only)

**API 설정** (`src/config/api.config.ts`):
```typescript
export const API_CONFIG = {
  API_BASE_URL: '',        // /api로 시작
  WS_URL: '/ws',           // WebSocket
  AUTH_PORTAL_URL: '/auth',
  AUTH_FRONTEND_URL: '/'
}
```

**파일 위치**: `dashboard/frontend_3010/`

---

### 3. VNC Service (정적 빌드)

**접근 URL**: `https://110.15.177.120/vnc`

**목적**: VNC 세션 생성 및 관리 (독립 서비스)

**기술 스택**: React + TypeScript + Vite

**빌드 위치**: `/var/www/html/vnc_service_8002/`

**주요 기능**:
- VNC 이미지 선택 (XFCE4, KDE Plasma 등)
- 새 세션 생성
- 노드 상태 표시 (Job ID, Node, Geometry, Ports)
- 연결 준비 상태 확인 (readiness check)
- noVNC 연결

**API 엔드포인트**:
- `GET /dashboardapi/vnc/images` - 이미지 목록
- `GET /dashboardapi/vnc/sessions` - 세션 목록
- `POST /dashboardapi/vnc/sessions` - 세션 생성
- `GET /dashboardapi/vnc/sessions/{id}/ready` - Readiness 체크
- `DELETE /dashboardapi/vnc/sessions/{id}` - 세션 종료

**파일 위치**: `dashboard/vnc_service_8002/`

---

### 4. CAE Frontend (Port 5173 - systemd)

**접근 URL**: `https://110.15.177.120/cae`

**목적**: CAE 웹 인터페이스

**systemd 서비스**: `koo_cae_web.service` (Node.js)

**파일 위치**: `dashboard/kooCAEWeb_5173/`

---

### 5. App Service (Port 5174 - systemd)

**접근 URL**: `https://110.15.177.120/app`

**목적**: 애플리케이션 런처

**systemd 서비스**: Running on port 5174

**파일 위치**: `dashboard/app_5174/`

---

## Nginx 라우팅 구조

### 설정 파일

**주 설정파일**: `/etc/nginx/conf.d/auth-portal.conf`

### 라우팅 규칙

```nginx
# Root - Auth Frontend (4431 dev 모드)
location / {
    proxy_pass http://localhost:4431;
}

# Auth Backend API
location /auth/ {
    proxy_pass http://localhost:4430/auth/;
}

# Dashboard Backend API
location /dashboardapi/ {
    proxy_pass http://localhost:5010/api/;
}

location /api/ {
    proxy_pass http://localhost:5010/api/;
}

# WebSocket (실시간 모니터링)
location /ws {
    proxy_pass http://localhost:5011/ws;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

# SocketIO (SSH WebSocket) ⭐ 최근 추가
location /socket.io/ {
    proxy_pass http://localhost:5010/socket.io/;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

# Dashboard Frontend (정적 파일)
location /dashboard {
    alias /var/www/html/dashboard;
    try_files $uri $uri/ /dashboard/index.html;
}

# VNC Frontend (정적 파일)
location /vnc {
    alias /var/www/html/vnc_service_8002;
    try_files $uri $uri/ /vnc/index.html;
}

# CAE Frontend (정적 파일)
location /cae {
    alias /var/www/html/cae;
}

# App Frontend (정적 파일)
location /app {
    alias /var/www/html/app_5174;
}

# VNC Proxy (동적 포트)
location ~ ^/vncproxy/([0-9]+)/(.*)$ {
    set $vnc_port $1;
    proxy_pass http://127.0.0.1:$vnc_port/$2$is_args$args;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

# CAE API
location /cae/api/ {
    proxy_pass http://localhost:5000/;
}

location /cae/automation/ {
    proxy_pass http://localhost:5001/;
}
```

---

## 데이터베이스

### MariaDB

**용도**: 영구 데이터 저장 (사용자, 작업 이력 등)

**상태**: 실행 중

**접근**: `localhost:3306`

**관련 서비스**: 백엔드 서비스들이 필요시 사용

---

## WebSocket 연결

### 1. 실시간 모니터링 WebSocket (5011)

**엔드포인트**: `/ws`

**프로토콜**: WebSocket

**용도**: 클러스터 상태 실시간 업데이트

**클라이언트**: Dashboard Frontend

---

### 2. SSH WebSocket (5010 - SocketIO)

**엔드포인트**: `/socket.io/`

**네임스페이스**: `/ssh-ws`

**프로토콜**: SocketIO

**용도**: SSH 웹 터미널

**클라이언트**: `SSHTerminal.tsx`

**연결 코드**:
```typescript
const socket = io(`${protocol}//${host}/ssh-ws`, {
  path: '/socket.io',
  transports: ['websocket', 'polling'],
  auth: { token: jwt_token }
});
```

**Nginx 프록시 설정**:
```nginx
location /socket.io/ {
    proxy_pass http://localhost:5010/socket.io/;
}
```

---

## 모니터링

### Prometheus (Port 9090)

**목적**: 메트릭 수집 및 저장

**설정파일**: `dashboard/prometheus_9090/prometheus.yml`

**Targets**:
- Node Exporter (9100)
- 백엔드 서비스들

---

### Node Exporter (Port 9100)

**목적**: 시스템 메트릭 수집

**메트릭**: CPU, 메모리, 디스크, 네트워크 등

---

### SAML IdP (Port 7000)

**목적**: SSO 테스트용 SAML Identity Provider

**설정**: `dashboard/saml_idp_7000/config.js`

**사용자 DB**:
```javascript
module.exports = {
  user: {
    "koopark@hpc.local": {
      password: "admin123",
      userName: "koopark",
      groups: "HPC-Admins",
      ...
    },
    "dx_user@hpc.local": {
      password: "password123",
      userName: "dx_user",
      groups: "DX-Users",
      ...
    },
    "caeg_user@hpc.local": {
      password: "password123",
      userName: "caeg_user",
      groups: "CAEG-Users",
      ...
    }
  }
}
```

---

## 서비스 간 연관관계

### 인증 흐름

```
[사용자]
   ↓
[Auth Frontend 4431] → [SAML IdP 7000] (SSO 선택 시)
   ↓
[Auth Backend 4430] → JWT 토큰 발급
   ↓
[Dashboard Frontend] ← JWT 토큰 저장
   ↓
[Dashboard Backend 5010] ← JWT로 API 호출
   ↓ ↓ ↓
[Redis] [MariaDB] [Slurm]
```

### VNC 세션 생성 흐름

```
[VNC Frontend 8002]
   ↓ POST /dashboardapi/vnc/sessions
[Dashboard Backend 5010]
   ↓ Slurm sbatch 실행
[Slurm Cluster]
   ↓ Job 실행
[VNC Container on Node]
   ↓ Session 정보 저장
[Redis] vnc:session:<id>
   ↓ Frontend가 polling
[VNC Frontend] → Readiness 체크
   ↓ Ready 시
[사용자] → noVNC 연결 (/vncproxy/<port>/)
```

### SSH 세션 연결 흐름

```
[SSH Session Manager]
   ↓ POST /api/ssh/sessions
[Dashboard Backend 5010]
   ↓ SSH 연결 생성
[Redis] ssh:session:<id>
   ↓
[SSH Terminal Component]
   ↓ SocketIO 연결
/socket.io/ → /ssh-ws namespace
   ↓
[Dashboard Backend 5010]
   ↓ SSH 프로세스
[Target Node]
```

### 데이터 흐름

```
[프론트엔드] → Nginx → [백엔드]
                           ↓
                    [Redis] (세션)
                           ↓
                    [MariaDB] (영구 데이터)
                           ↓
                    [Slurm] (작업 관리)
```

---

## Setup 자동화

### Setup 스크립트 구조

**위치**: `cluster/setup/`

**주요 스크립트**:
1. `phase0_*.sh` - 기본 환경 설정
2. `phase1_*.sh` - VM 생성
3. `phase2_*.sh` - 네트워크 설정
4. `phase3_slurm.sh` - Slurm 설치
5. **`phase5_web.sh`** - 웹 서비스 배포 ⭐

### phase5_web.sh 주요 기능

```bash
main() {
    check_prerequisites      # Python, Node, Nginx 등 확인
    stop_manual_web_services # 기존 프로세스 정리
    load_config              # my_multihead_cluster.yaml
    create_directories       # 디렉토리 생성
    deploy_web_services      # 소스 코드 배포
    build_all_frontends      # 모든 프론트엔드 빌드 ⭐
    deploy_vnc_scripts       # VNC 스크립트 배포
    create_systemd_services  # systemd 서비스 생성
    configure_nginx          # Nginx 설정
    fix_ssh_api_and_nginx   # SSH/VNC 수정사항 적용 ⭐
    setup_ssl                # Let's Encrypt SSL
    start_services           # 서비스 시작
    verify_services          # 검증
}
```

### build_all_frontends() 함수

```bash
local frontends=(
    "frontend_3010"      # Dashboard
    "auth_portal_4431"   # Auth Portal
    "kooCAEWeb_5173"     # CAE Web
    "app_5174"           # App Service
    "vnc_service_8002"   # VNC Service
)

for frontend in "${frontends[@]}"; do
    cd "$dashboard_dir/$frontend"
    npm install
    npm run build
    cp -r dist/* /var/www/html/$frontend/
done
```

### fix_ssh_api_and_nginx() 함수 ⭐

**최근 추가된 함수 - 자동 수정 작업**:

1. `ssh_api.py` URL prefix 수정 (`/ssh` → `/api/ssh`)
2. `SSHSessionManager.tsx` API 경로 수정
3. Nginx `auth-portal.conf` dashboard 경로 수정
4. SocketIO proxy 추가 (`/socket.io/`)
5. 오래된 `frontend_dashboard.service` 삭제
6. Nginx 재시작

---

## 최근 해결한 주요 이슈

### 1. SSH Session API 404 에러 (2025-11-02)

**문제**: `Unexpected token '<', "<!doctype "... is not valid JSON`

**원인**: 
- 프론트엔드: `/ssh/nodes` 호출
- 백엔드: `/api/ssh` 경로로 등록됨

**해결**: 
- `ssh_api.py`: `url_prefix='/api/ssh'`
- `SSHSessionManager.tsx`: `/api/ssh/*` 경로 사용

---

### 2. 브라우저 캐싱 문제

**문제**: 새 빌드가 로드되지 않음

**원인**: Nginx가 `/var/www/html/frontend_3010` (이전 경로) 참조

**해결**: 
- Nginx 경로 변경 → `/var/www/html/dashboard`
- `frontend_dashboard.service` 삭제 (dev 모드 중지)

---

### 3. SocketIO WebSocket timeout

**문제**: SSH/VNC에서 `SocketIO connection error: timeout`

**원인**: Nginx에 `/socket.io/` 프록시 설정 없음

**해결**: 
```nginx
location /socket.io/ {
    proxy_pass http://localhost:5010/socket.io/;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

---

### 4. VNC 페이지 폰트 색상 문제

**문제**: 노드 정보 텍스트가 흰색으로 안 보임

**원인**: CSS에 `info-label`, `info-value` 스타일 없음

**해결**:
```css
.info-label {
  color: #666 !important;
  font-weight: 500;
}
.info-value {
  color: #333 !important;
}
```

---

## 환경변수 요약

### 공통 (.env)

```bash
# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=changeme

# JWT (Auth Backend만)
JWT_SECRET_KEY=your-secret-key-change-this-in-production
JWT_EXPIRATION_HOURS=720

# Slurm (Dashboard Backend만)
MOCK_MODE=false
SLURM_BIN_DIR=/usr/local/slurm/bin
```

---

## 포트 매핑 전체 요약

| 포트 | 서비스 | 타입 | 접근 경로 | 설명 |
|------|--------|------|-----------|------|
| 443 | Nginx | HTTPS | / | 메인 엔트리포인트 |
| 4430 | auth_backend | Python | /auth | JWT 인증 API |
| 4431 | auth_frontend | Node (dev) | / | 로그인 페이지 |
| 5000 | cae_backend | Python | /cae/api | CAE API |
| 5001 | cae_automation | Python | /cae/automation | CAE 자동화 |
| 5010 | dashboard_backend | Python | /api, /socket.io | 메인 백엔드 + SSH WS |
| 5011 | websocket_service | Python | /ws | 실시간 모니터링 |
| 5173 | koo_cae_web | Node | /cae | CAE 프론트엔드 |
| 5174 | app_service | Node | /app | 앱 런처 |
| 7000 | saml_idp | Node | - | SAML IdP (테스트) |
| 8002 | - | 정적 | /vnc | VNC 서비스 (빌드) |
| 9090 | prometheus | Monitoring | - | 메트릭 수집 |
| 9100 | node_exporter | Monitoring | - | 시스템 메트릭 |
| 3010 | - | 정적 | /dashboard | 대시보드 (빌드) |

**정적 파일**: Nginx가 `/var/www/html/`에서 직접 서빙
**동적 서비스**: systemd로 실행, Nginx가 프록시

---

## 다음 세션을 위한 체크리스트

### 확인 사항

- [ ] Redis 연결 상태 확인
- [ ] JWT 토큰 유효성 확인
- [ ] 모든 백엔드 서비스 실행 중
- [ ] Nginx 설정 유효성 확인
- [ ] 프론트엔드 빌드 최신 상태

### 문제 발생 시

1. **인증 안 됨**: Redis 상태 및 JWT_SECRET_KEY 확인
2. **API 404**: Nginx 프록시 경로 확인
3. **WebSocket 연결 실패**: `/socket.io/` 프록시 확인
4. **VNC/SSH 세션 없음**: Redis 세션 키 확인

### 유용한 명령어

```bash
# 서비스 상태 확인
systemctl status auth_backend dashboard_backend websocket_service

# Redis 확인
REDISCLI_AUTH=changeme redis-cli
> KEYS *
> GET vnc:session:<id>

# Nginx 설정 테스트
sudo nginx -t
sudo systemctl reload nginx

# 프론트엔드 재빌드
cd dashboard/<frontend_name>
npm run build
sudo cp -r dist/* /var/www/html/<frontend_name>/

# 로그 확인
sudo journalctl -u dashboard_backend.service -n 50
sudo tail -f /var/log/nginx/error.log
```

---

## 프로젝트 파일 구조

```
/home/koopark/claude/KooSlurmInstallAutomationRefactory/
├── cluster/
│   ├── setup/
│   │   ├── phase5_web.sh          ⭐ 웹 서비스 setup
│   │   ├── apply_post_setup_fixes.sh
│   │   └── ...
│   └── config/
│       └── my_multihead_cluster.yaml
├── dashboard/
│   ├── auth_portal_4430/          # Auth Backend
│   │   ├── app.py
│   │   ├── middleware/jwt_middleware.py
│   │   └── config/groups.json
│   ├── auth_portal_4431/          # Auth Frontend
│   │   └── src/
│   │       ├── pages/LoginPage.tsx
│   │       └── context/AuthContext.tsx
│   ├── backend_5010/              # Dashboard Backend
│   │   ├── app.py
│   │   ├── vnc_api.py
│   │   ├── ssh_api.py
│   │   ├── ssh_websocket.py
│   │   └── ...
│   ├── frontend_3010/             # Dashboard Frontend
│   │   └── src/
│   │       ├── components/
│   │       │   ├── SSHSessionManager.tsx
│   │       │   ├── SSHTerminal.tsx
│   │       │   └── VNCSessionManager.tsx
│   │       └── config/api.config.ts
│   ├── vnc_service_8002/          # VNC Service
│   │   └── src/
│   │       ├── App.tsx
│   │       └── App.css
│   ├── saml_idp_7000/             # SAML IdP
│   │   └── config.js
│   ├── kooCAEWebServer_5000/      # CAE Backend
│   ├── websocket_5011/            # WebSocket
│   ├── prometheus_9090/
│   └── node_exporter_9100/
└── /var/www/html/                 # Nginx 정적 파일
    ├── dashboard/                 # 빌드된 Dashboard
    ├── auth_portal_4431/          # 빌드된 Auth Portal
    ├── vnc_service_8002/          # 빌드된 VNC Service
    ├── cae/
    └── app_5174/
```

---

**문서 버전**: 1.0  
**마지막 업데이트**: 2025-11-02 01:30 UTC

