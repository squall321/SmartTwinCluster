# Phase 4: HTTPS 설정 가이드 (v4.4.1)

**목적**: 프로덕션 환경에서 JWT 토큰 및 사용자 데이터를 안전하게 전송
**상태**: 📝 가이드 문서 (실제 적용은 프로덕션 배포 시)
**날짜**: 2025-11-05

---

## 📋 개요

현재 시스템은 HTTP로 운영 중이며, JWT 토큰이 평문으로 전송됩니다.
프로덕션 환경에서는 반드시 HTTPS를 설정하여 중간자 공격을 방지해야 합니다.

### 현재 상태 (개발 환경)
- Frontend: `http://localhost:3010`
- Backend API: `http://localhost:5010`
- WebSocket: `ws://localhost:5011`

### 목표 상태 (프로덕션)
- Frontend: `https://dashboard.yourdomain.com`
- Backend API: `https://dashboard.yourdomain.com/api`
- WebSocket: `wss://dashboard.yourdomain.com/ws`

---

## 🎯 필요한 사전 준비

### 1. 도메인 설정
- 도메인 이름 확보 (예: `dashboard.yourdomain.com`)
- DNS A 레코드 설정: `dashboard.yourdomain.com` → `서버 공인 IP`

### 2. 방화벽 설정
```bash
# HTTP/HTTPS 포트 열기
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

### 3. Nginx 설치
```bash
sudo apt-get update
sudo apt-get install nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

---

## 🔐 SSL 인증서 발급 (Let's Encrypt)

### 1. Certbot 설치
```bash
# Certbot 및 Nginx 플러그인 설치
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx

# Certbot 버전 확인
certbot --version
```

### 2. 인증서 발급
```bash
# 자동 설정 모드 (Nginx 자동 설정)
sudo certbot --nginx -d dashboard.yourdomain.com

# 또는 수동 설정 모드 (Nginx 직접 설정)
sudo certbot certonly --nginx -d dashboard.yourdomain.com
```

**대화형 질문**:
- 이메일 주소 입력: 인증서 갱신 알림용
- 서비스 약관 동의: `Y`
- 뉴스레터 수신: `N` (선택)
- HTTP → HTTPS 자동 리다이렉트: `2` (권장)

### 3. 인증서 확인
```bash
# 인증서 파일 위치
ls -la /etc/letsencrypt/live/dashboard.yourdomain.com/

# 출력:
# fullchain.pem  - 인증서 + 중간 인증서
# privkey.pem    - 개인키 (절대 공개 금지!)
# cert.pem       - 인증서
# chain.pem      - 중간 인증서
```

### 4. 자동 갱신 설정
```bash
# 자동 갱신 테스트 (실제 갱신 X)
sudo certbot renew --dry-run

# Cron job 확인 (자동 설정됨)
sudo systemctl list-timers | grep certbot

# 또는 crontab 추가 (선택적)
sudo crontab -e
# 매일 자정에 인증서 갱신 시도
0 0 * * * certbot renew --quiet
```

---

## ⚙️ Nginx 설정

### 1. Nginx 설정 파일 생성

**/etc/nginx/sites-available/dashboard**:
```nginx
# Frontend + API + WebSocket 통합 설정

# HTTPS 서버 (Port 443)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name dashboard.yourdomain.com;

    # SSL 인증서 설정
    ssl_certificate /etc/letsencrypt/live/dashboard.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dashboard.yourdomain.com/privkey.pem;

    # SSL 프로토콜 및 암호화 설정
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # HSTS (HTTP Strict Transport Security) 활성화
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # 보안 헤더
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 로그 설정
    access_log /var/log/nginx/dashboard_access.log;
    error_log /var/log/nginx/dashboard_error.log;

    # Frontend Static Files (React)
    location / {
        root /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010/dist;
        try_files $uri $uri/ /index.html;

        # 캐싱 설정
        expires 1h;
        add_header Cache-Control "public, must-revalidate";
    }

    # Backend API Proxy (Port 5010)
    location /api/ {
        proxy_pass http://localhost:5010;
        proxy_http_version 1.1;

        # 필수 헤더
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 타임아웃 설정 (파일 업로드용)
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;

        # 버퍼 설정 (대용량 파일)
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # WebSocket Proxy (Port 5011)
    location /ws {
        proxy_pass http://localhost:5011;
        proxy_http_version 1.1;

        # WebSocket 필수 헤더
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 타임아웃 설정 (WebSocket 장시간 연결)
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }

    # Static assets 캐싱 (CSS, JS, Images)
    location ~* \.(css|js|jpg|jpeg|png|gif|ico|woff|woff2|ttf|svg)$ {
        root /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010/dist;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}

# HTTP → HTTPS 리다이렉트 (Port 80)
server {
    listen 80;
    listen [::]:80;
    server_name dashboard.yourdomain.com;

    # 모든 HTTP 요청을 HTTPS로 리다이렉트
    return 301 https://$server_name$request_uri;
}
```

### 2. Nginx 설정 활성화
```bash
# 심볼릭 링크 생성
sudo ln -s /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/

# 기본 설정 파일 제거 (선택적)
sudo rm /etc/nginx/sites-enabled/default

# 설정 파일 문법 검사
sudo nginx -t

# 예상 출력:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful

# Nginx 재시작
sudo systemctl reload nginx
```

---

## 🔧 프론트엔드 환경 변수 설정

### 1. Production 환경 변수 파일 생성

**frontend_3010/.env.production**:
```env
# Production API URLs
VITE_API_URL=https://dashboard.yourdomain.com
VITE_WEBSOCKET_URL=wss://dashboard.yourdomain.com/ws
VITE_AUTH_PORTAL_URL=https://auth.yourdomain.com

# Production 모드
NODE_ENV=production
```

### 2. API Config 수정 (선택적)

**frontend_3010/src/config/api.config.ts**:
```typescript
export const API_CONFIG = {
  BASE_URL: import.meta.env.VITE_API_URL || '',
  WEBSOCKET_URL: import.meta.env.VITE_WEBSOCKET_URL || 'ws://localhost:5011/ws',
  AUTH_PORTAL_URL: import.meta.env.VITE_AUTH_PORTAL_URL || 'http://localhost:4431',
  TIMEOUT: 30000,
  MAX_RETRIES: 3,
  RETRY_DELAY: 1000,
};
```

### 3. 프론트엔드 빌드
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010

# Production 빌드
npm run build

# 빌드 결과 확인
ls -la dist/
```

---

## 🧪 HTTPS 테스트

### 1. 기본 연결 테스트
```bash
# HTTPS 접속 테스트
curl -I https://dashboard.yourdomain.com

# 예상 출력:
# HTTP/2 200
# server: nginx
# strict-transport-security: max-age=31536000; includeSubDomains

# HTTP → HTTPS 리다이렉트 테스트
curl -I http://dashboard.yourdomain.com

# 예상 출력:
# HTTP/1.1 301 Moved Permanently
# Location: https://dashboard.yourdomain.com/
```

### 2. SSL 인증서 검증
```bash
# SSL 인증서 상세 정보
openssl s_client -connect dashboard.yourdomain.com:443 -servername dashboard.yourdomain.com < /dev/null

# SSL Labs 테스트 (온라인)
# https://www.ssllabs.com/ssltest/analyze.html?d=dashboard.yourdomain.com
```

### 3. API 엔드포인트 테스트
```bash
# JWT 없이 API 호출 (401 예상)
curl https://dashboard.yourdomain.com/api/v2/files/uploads

# 예상 출력:
# {"error": "No authorization header", "message": "Authorization header is required"}
```

### 4. WebSocket 연결 테스트
```javascript
// 브라우저 콘솔에서 테스트
const ws = new WebSocket('wss://dashboard.yourdomain.com/ws');

ws.onopen = () => console.log('✅ WebSocket connected');
ws.onerror = (error) => console.error('❌ WebSocket error:', error);
ws.onmessage = (event) => console.log('📩 Message:', JSON.parse(event.data));
```

---

## 🔍 문제 해결

### 1. Nginx 502 Bad Gateway
```bash
# Backend 서비스 확인
sudo systemctl status dashboard_backend
sudo systemctl status websocket_service

# 포트 리스닝 확인
sudo netstat -tulpn | grep -E '5010|5011'

# Nginx 에러 로그 확인
sudo tail -f /var/log/nginx/dashboard_error.log
```

### 2. SSL 인증서 갱신 실패
```bash
# Certbot 로그 확인
sudo cat /var/log/letsencrypt/letsencrypt.log

# 수동 갱신 시도
sudo certbot renew --force-renewal

# Nginx 설정 재로드
sudo systemctl reload nginx
```

### 3. WebSocket wss:// 연결 실패
```bash
# WebSocket 프록시 설정 확인
sudo nginx -T | grep -A 10 "location /ws"

# WebSocket 서비스 확인
sudo systemctl status websocket_service

# WebSocket 로그 확인
sudo journalctl -u websocket_service -f
```

### 4. Mixed Content 경고 (Chrome)
- 모든 리소스가 HTTPS로 로드되는지 확인
- `http://` URL을 `https://`로 변경
- API_CONFIG에서 VITE_API_URL 확인

---

## 📊 성능 최적화

### 1. Gzip 압축 활성화

**/etc/nginx/nginx.conf**:
```nginx
http {
    # Gzip 압축 설정
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/rss+xml
        application/atom+xml
        image/svg+xml;
}
```

### 2. HTTP/2 활성화 (이미 설정됨)
```nginx
# Nginx 설정에서 http2 확인
listen 443 ssl http2;
```

### 3. 캐싱 설정
```nginx
# Static assets 캐싱 (이미 설정됨)
location ~* \.(css|js|jpg|jpeg|png|gif|ico)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}
```

---

## 🔒 보안 강화

### 1. Firewall 설정
```bash
# UFW (Uncomplicated Firewall) 활성화
sudo ufw enable

# 필요한 포트만 열기
sudo ufw allow ssh
sudo ufw allow 80/tcp   # HTTP (리다이렉트용)
sudo ufw allow 443/tcp  # HTTPS

# 상태 확인
sudo ufw status
```

### 2. Fail2ban 설정 (선택적)
```bash
# Fail2ban 설치
sudo apt-get install fail2ban

# Nginx 보호 설정
sudo cat > /etc/fail2ban/jail.local << 'EOF'
[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/dashboard_error.log

[nginx-noscript]
enabled = true
port = http,https
logpath = /var/log/nginx/dashboard_access.log
EOF

# Fail2ban 재시작
sudo systemctl restart fail2ban
```

### 3. Rate Limiting (Nginx 레벨)
```nginx
# /etc/nginx/nginx.conf에 추가
http {
    # Rate limiting zone 정의
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=general_limit:10m rate=100r/s;

    # ...
}

# /etc/nginx/sites-available/dashboard에 적용
location /api/ {
    # API 요청 제한 (초당 10개)
    limit_req zone=api_limit burst=20 nodelay;

    proxy_pass http://localhost:5010;
    # ...
}
```

---

## ✅ 배포 체크리스트

### 프로덕션 배포 전 확인사항
- [ ] 도메인 DNS 설정 완료
- [ ] SSL 인증서 발급 완료
- [ ] Nginx 설정 파일 작성 및 테스트
- [ ] 프론트엔드 Production 빌드 완료
- [ ] HTTP → HTTPS 리다이렉트 확인
- [ ] API 엔드포인트 HTTPS 접속 확인
- [ ] WebSocket wss:// 연결 확인
- [ ] JWT 토큰 암호화 전송 확인
- [ ] 방화벽 설정 완료
- [ ] SSL Labs 테스트 A+ 등급 확인
- [ ] 브라우저 Mixed Content 경고 없음
- [ ] 자동 인증서 갱신 설정 확인

---

## 📝 주의사항

### 1. 인증서 갱신
- Let's Encrypt 인증서는 **90일마다 갱신 필요**
- Certbot이 자동으로 갱신하지만, 주기적으로 확인 필요
- 갱신 실패 시 이메일 알림 확인

### 2. Backend 환경 변수 (선택적)
```bash
# /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010/.env
# 필요 시 CORS 설정 추가
CORS_ORIGINS=https://dashboard.yourdomain.com
```

### 3. 백업
```bash
# Nginx 설정 백업
sudo cp -r /etc/nginx/sites-available /backup/nginx-$(date +%Y%m%d)

# SSL 인증서 백업 (안전한 장소에 보관)
sudo cp -r /etc/letsencrypt /backup/letsencrypt-$(date +%Y%m%d)
```

---

## 🚀 빠른 설정 스크립트

프로덕션 배포 시 사용할 수 있는 자동화 스크립트입니다.

**setup_https.sh**:
```bash
#!/bin/bash

# HTTPS 설정 자동화 스크립트
DOMAIN="dashboard.yourdomain.com"
FRONTEND_PATH="/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010"

echo "🔐 Starting HTTPS setup for ${DOMAIN}..."

# 1. Certbot 설치
echo "📦 Installing Certbot..."
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx

# 2. 인증서 발급
echo "🎫 Requesting SSL certificate..."
sudo certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email admin@${DOMAIN}

# 3. Nginx 설정 파일 복사 (미리 준비된 파일)
echo "⚙️  Configuring Nginx..."
sudo cp dashboard.nginx.conf /etc/nginx/sites-available/dashboard
sudo ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/

# 4. Nginx 테스트 및 재시작
echo "🔄 Reloading Nginx..."
sudo nginx -t && sudo systemctl reload nginx

# 5. 방화벽 설정
echo "🔥 Configuring firewall..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload

# 6. 프론트엔드 빌드
echo "🏗️  Building frontend..."
cd ${FRONTEND_PATH}
npm run build

echo "✅ HTTPS setup complete!"
echo "🌐 Visit: https://${DOMAIN}"
```

---

## 📞 지원

HTTPS 설정 중 문제가 발생하면:
1. Nginx 에러 로그 확인: `/var/log/nginx/dashboard_error.log`
2. Certbot 로그 확인: `/var/log/letsencrypt/letsencrypt.log`
3. SSL Labs 테스트: https://www.ssllabs.com/ssltest/

---

**HTTPS 설정 가이드 완료!**

프로덕션 배포 시 이 가이드를 따라 HTTPS를 설정하세요.
