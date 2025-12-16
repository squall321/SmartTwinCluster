# Nginx 통합 가이드 - Moonlight/Sunshine

**기존 파일**: `/etc/nginx/conf.d/auth-portal.conf`
**작업**: 기존 파일에 Moonlight 경로 추가 (새 파일 생성 ❌)

---

## ✅ 기존 Nginx 설정 분석 완료

### 현재 경로 매핑

| 경로 | 프록시 대상 | 포트 | 서비스 |
|------|-------------|------|--------|
| `/` | `localhost:4431` | 4431 | Auth Frontend |
| `/auth/` | `localhost:4430/auth/` | 4430 | Auth Backend API |
| `/dashboardapi/` | `localhost:5010/api/` | 5010 | Dashboard Backend API |
| `/api/` | `localhost:5010/api/` | 5010 | Dashboard Backend API (범용) |
| `/api/v2/templates` | `localhost:5010` (rewrite) | 5010 | Templates API v2 |
| `/ws` | `localhost:5011/ws` | 5011 | WebSocket |
| `/socket.io/` | `localhost:5010/socket.io/` | 5010 | SSH WebSocket (SocketIO) |
| `/cae/api/` | `localhost:5000/api/` | 5000 | CAE Backend API |
| `/cae/automation/` | `localhost:5001/` | 5001 | CAE Automation API |
| `/dashboard` | Static files | - | Dashboard Frontend |
| `/vnc` | Static files | - | VNC Frontend |
| `/cae` | Static files | - | CAE Frontend |
| `/app` | Static files | - | App Frontend |
| `/vncproxy/<port>/` | `localhost:<port>/` | 6901-8999 | VNC noVNC Proxy |

---

## ⚠️ 중요: `/api/` 경로 충돌 해결

### 문제점
```nginx
# Line 102-118: 현재 설정
location /api/ {
    proxy_pass http://localhost:5010/api/;
    # ...
}
```

**이 설정은 `/api/`로 시작하는 모든 요청을 backend_5010으로 보냄!**

### 해결 방법

Nginx는 **먼저 정의된 구체적인 경로가 우선**이므로:

```nginx
# ✅ 올바른 순서
location /api/moonlight/ {      # 구체적 (먼저)
    proxy_pass http://localhost:8004/;
}

location /api/ {                # 범용 (나중)
    proxy_pass http://localhost:5010/api/;
}
```

이렇게 하면:
- `/api/moonlight/*` → `localhost:8004/` (Moonlight Backend)
- `/api/vnc/*` → `localhost:5010/api/vnc/*` (Dashboard Backend)
- `/api/jobs/*` → `localhost:5010/api/jobs/*` (Dashboard Backend)
- ...기타 모든 `/api/*` → `localhost:5010/api/*` (Dashboard Backend)

---

## 📝 추가할 Nginx 설정

### 1. Upstream 정의 (파일 상단에 추가)

**위치**: Line 1 (server 블록 위)

```nginx
# Moonlight/Sunshine Backend Upstreams
upstream moonlight_backend {
    server 127.0.0.1:8004;
}

upstream moonlight_signaling {
    server 127.0.0.1:8005;
}

# Connection upgrade map for WebSocket
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
```

### 2. Moonlight API 경로 (Line 102 **위에** 추가)

**⚠️ 중요**: `/api/` **위에** 삽입!

```nginx
    # ========== Moonlight/Sunshine Backend API (Port 8004) ==========
    # ⚠️ 주의: /api/ 위에 정의되어야 우선순위 확보
    location /api/moonlight/ {
        proxy_pass http://moonlight_backend/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # CORS headers
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type' always;

        if ($request_method = 'OPTIONS') {
            return 204;
        }
    }

    # 기존 /api/ 경로 (Line 102-118) 그대로 유지
    location /api/ {
        proxy_pass http://localhost:5010/api/;
        # ...
    }
```

### 3. Moonlight WebSocket Signaling (Line 133 근처에 추가)

**위치**: WebSocket 섹션 (`/ws`, `/socket.io/` 근처)

```nginx
    # ========== Moonlight WebRTC Signaling WebSocket (Port 8005) ==========
    location /moonlight/signaling {
        proxy_pass http://moonlight_signaling;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket specific settings
        proxy_read_timeout 86400s;  # 24시간
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }
```

### 4. Moonlight Frontend (Line 220 근처에 추가)

**위치**: Static files 섹션 (`/dashboard`, `/vnc`, `/cae` 근처)

```nginx
    # ========== Moonlight Frontend (Static Files) ==========
    location /moonlight/ {
        alias /var/www/html/moonlight_8004/;
        try_files $uri $uri/ /moonlight/index.html;
        index index.html;

        # Enable gzip
        gzip on;
        gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

        # Prevent caching of index.html
        location = /moonlight/index.html {
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            add_header Pragma "no-cache";
            add_header Expires "0";
        }

        # Cache static assets
        location ~* /moonlight/.*\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
```

---

## 🔧 적용 절차

### Step 1: 백업
```bash
sudo cp /etc/nginx/conf.d/auth-portal.conf \
     /etc/nginx/conf.d/auth-portal.conf.backup_$(date +%Y%m%d_%H%M%S)

# 백업 확인
ls -lh /etc/nginx/conf.d/auth-portal.conf.backup_*
```

### Step 2: 파일 편집
```bash
sudo vi /etc/nginx/conf.d/auth-portal.conf
```

**편집 순서**:

1. **Line 1**: Upstream 정의 추가
   ```nginx
   upstream moonlight_backend { server 127.0.0.1:8004; }
   upstream moonlight_signaling { server 127.0.0.1:8005; }
   map $http_upgrade $connection_upgrade { default upgrade; '' close; }
   ```

2. **Line 102 위**: `/api/moonlight/` 추가 (⚠️ `/api/` 위에!)

3. **Line 133 근처**: `/moonlight/signaling` 추가

4. **Line 220 근처**: `/moonlight/` (Static) 추가

### Step 3: 문법 검사
```bash
sudo nginx -t

# 예상 출력:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**오류 발생 시**:
```bash
# 백업 복원
sudo cp /etc/nginx/conf.d/auth-portal.conf.backup_YYYYMMDD_HHMMSS \
     /etc/nginx/conf.d/auth-portal.conf

# 다시 확인
sudo nginx -t
```

### Step 4: Nginx 재시작
```bash
# Reload (무중단)
sudo systemctl reload nginx

# 또는 Restart
sudo systemctl restart nginx

# 상태 확인
sudo systemctl status nginx
```

### Step 5: 검증
```bash
# 1. Nginx 설정 확인
sudo nginx -T | grep -A 10 "location /api/moonlight"
sudo nginx -T | grep -A 10 "location /moonlight"

# 2. 포트 리스닝 확인
lsof -i :8004  # Moonlight Backend (아직 실행 안 됨)
lsof -i :8005  # Moonlight Signaling (아직 실행 안 됨)

# 3. Nginx 에러 로그 확인
sudo tail -f /var/log/nginx/auth-portal-error.log
```

---

## 📊 최종 경로 매핑 (추가 후)

| 경로 | 프록시 대상 | 포트 | 서비스 | 상태 |
|------|-------------|------|--------|------|
| `/` | `localhost:4431` | 4431 | Auth Frontend | 기존 |
| `/auth/` | `localhost:4430/auth/` | 4430 | Auth Backend API | 기존 |
| `/dashboardapi/` | `localhost:5010/api/` | 5010 | Dashboard Backend API | 기존 |
| **`/api/moonlight/`** ✅ | **`localhost:8004/`** | **8004** | **Moonlight Backend API** | **신규** |
| `/api/v2/templates` | `localhost:5010` | 5010 | Templates API v2 | 기존 |
| `/api/` | `localhost:5010/api/` | 5010 | Dashboard Backend API | 기존 |
| `/ws` | `localhost:5011/ws` | 5011 | WebSocket | 기존 |
| `/socket.io/` | `localhost:5010/socket.io/` | 5010 | SSH WebSocket | 기존 |
| **`/moonlight/signaling`** ✅ | **`localhost:8005`** | **8005** | **Moonlight WebSocket** | **신규** |
| `/cae/api/` | `localhost:5000/api/` | 5000 | CAE Backend API | 기존 |
| `/cae/automation/` | `localhost:5001/` | 5001 | CAE Automation API | 기존 |
| `/dashboard` | Static files | - | Dashboard Frontend | 기존 |
| `/vnc` | Static files | - | VNC Frontend | 기존 |
| `/cae` | Static files | - | CAE Frontend | 기존 |
| `/app` | Static files | - | App Frontend | 기존 |
| **`/moonlight/`** ✅ | **Static files** | **-** | **Moonlight Frontend** | **신규** |
| `/vncproxy/<port>/` | `localhost:<port>/` | 6901-8999 | VNC noVNC Proxy | 기존 |

---

## 🧪 테스트 계획

### 1. 기존 서비스 정상 동작 확인 ✅
```bash
# Dashboard API
curl -k https://110.15.177.120/api/health

# VNC API
curl -k https://110.15.177.120/api/vnc/images

# CAE API
curl -k https://110.15.177.120/cae/api/standard-scenarios/health

# Auth API
curl -k https://110.15.177.120/auth/health
```

### 2. Moonlight 경로 응답 확인 (Backend 실행 후)
```bash
# Moonlight API (Backend 실행 필요)
curl -k https://110.15.177.120/api/moonlight/images

# Moonlight Frontend
curl -k https://110.15.177.120/moonlight/

# Expected: HTML 또는 404 (아직 Frontend 배포 전)
```

---

## ⚠️ 주의사항

### 1. `/api/` 경로 순서
```nginx
# ❌ 잘못된 순서
location /api/ { ... }           # 먼저 정의 (모든 /api/* 매칭)
location /api/moonlight/ { ... } # 절대 실행 안 됨!

# ✅ 올바른 순서
location /api/moonlight/ { ... } # 먼저 정의 (구체적)
location /api/ { ... }           # 나중에 정의 (범용)
```

### 2. Trailing Slash
```nginx
# proxy_pass에 trailing slash 주의
proxy_pass http://localhost:8004/;  # ✅ /api/moonlight/sessions → /sessions
proxy_pass http://localhost:8004;   # ❌ /api/moonlight/sessions → /api/moonlight/sessions
```

### 3. CORS 설정
- 개발 환경: `Access-Control-Allow-Origin: *`
- 프로덕션: 특정 도메인으로 제한 권장

---

## 🎯 롤백 절차

문제 발생 시:

```bash
# 1. 백업 복원
sudo cp /etc/nginx/conf.d/auth-portal.conf.backup_YYYYMMDD_HHMMSS \
     /etc/nginx/conf.d/auth-portal.conf

# 2. 문법 검사
sudo nginx -t

# 3. Nginx 재시작
sudo systemctl reload nginx

# 4. 기존 서비스 확인
curl -k https://110.15.177.120/api/health
curl -k https://110.15.177.120/vnc/
```

---

**완료 후**: IMPLEMENTATION_PLAN.md의 Phase 5.2 체크 ✅
