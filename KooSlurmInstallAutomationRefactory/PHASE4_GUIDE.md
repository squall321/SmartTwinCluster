# Phase 4 실행 가이드: Nginx Reverse Proxy 자동화

## 📋 개요

**목표**: Nginx reverse proxy 설정 자동화 및 프로덕션 배포 준비
**예상 소요 시간**: 3-4시간
**의존성**: Phase 3 완료 필수

---

## ✅ 사전 확인

Phase 4 시작 전 확인사항:

```bash
# Phase 3 완료 여부 확인
./verify_phase3.sh

# Nginx 설치 확인
nginx -v
```

---

## 📅 타임라인

| 단계 | 작업 | 예상 시간 |
|------|------|-----------|
| 1 | Nginx 설정 템플릿 작성 | 90분 |
| 2 | setup_nginx.sh 스크립트 작성 | 60분 |
| 3 | SSL 인증서 설정 | 30분 |
| 4 | 테스트 및 검증 | 40분 |

**총 예상 시간: 3시간 40분**

---

## 🎯 Phase 4 상세 실행 단계

### 1️⃣ Nginx 설정 템플릿 작성 (90분)

#### 목표
Jinja2 템플릿으로 Nginx 설정 자동 생성

#### 1-1. 메인 Nginx 설정 템플릿

```bash
nano web_services/templates/nginx/main.conf.j2
```

**파일 위치**: `web_services/templates/nginx/main.conf.j2`

**기능**:
- 환경별 설정 (development/production)
- 모든 서비스 라우팅
- WebSocket 지원
- SSL 설정 (프로덕션)
- 보안 헤더
- 로깅

**템플릿 구조**:
```nginx
# HPC Cluster Web Services - Nginx Configuration
# Environment: {{ environment }}
# Generated: {{ timestamp }}

{% if environment == 'production' %}
# HTTPS 리다이렉트
server {
    listen 80;
    server_name {{ domain }};
    return 301 https://$server_name$request_uri;
}

# HTTPS 서버
server {
    listen 443 ssl http2;
    server_name {{ domain }};

    # SSL 설정
    ssl_certificate {{ ssl_cert_path }};
    ssl_certificate_key {{ ssl_key_path }};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

{% else %}
# HTTP 서버 (개발 환경)
server {
    listen 80;
    server_name localhost;
{% endif %}

    # 보안 헤더
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 로깅
    access_log {{ access_log_path }};
    error_log {{ error_log_path }};

    # 최대 업로드 크기
    client_max_body_size {{ max_body_size }};

    # Auth Portal API
    location /auth {
        proxy_pass http://localhost:4430;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Dashboard API
    location /api {
        proxy_pass http://localhost:5010;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket (Dashboard)
    location /ws {
        proxy_pass http://localhost:5011;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # CAE API
    location /cae/api {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # CAE Automation API
    location /cae/automation {
        proxy_pass http://localhost:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # CAE Frontend
    location /cae {
        proxy_pass http://localhost:5173;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Dashboard Frontend
    location /dashboard {
        proxy_pass http://localhost:3010;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # VNC Service Frontend
    location /vnc {
        proxy_pass http://localhost:8002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # noVNC WebSocket Proxy
    location /vnc-proxy {
        proxy_pass http://localhost:6080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

{% if environment == 'production' %}
    # Prometheus (관리자 전용)
    location /prometheus {
        auth_basic "Administrator Area";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://localhost:9090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
{% endif %}

    # Auth Portal Frontend (기본 페이지)
    location / {
        proxy_pass http://localhost:4431;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

#### 1-2. 개발 환경 전용 설정

```bash
nano web_services/templates/nginx/development.conf.j2
```

**특징**:
- HTTP만 사용
- localhost 바인딩
- 간소화된 설정

---

#### 1-3. 프로덕션 환경 전용 설정

```bash
nano web_services/templates/nginx/production.conf.j2
```

**특징**:
- HTTPS 강제
- 실제 도메인 사용
- SSL 인증서 설정
- 보안 강화

---

### 2️⃣ setup_nginx.sh 스크립트 작성 (60분)

#### 목표
Nginx 설치, 설정, 검증 자동화

#### 실행

```bash
nano web_services/scripts/setup_nginx.sh
chmod +x web_services/scripts/setup_nginx.sh
```

**기능**:
- Nginx 설치 (미설치 시)
- 설정 파일 생성 (템플릿 렌더링)
- 설정 검증 (nginx -t)
- 설정 백업
- Nginx 재시작

**사용 예시**:
```bash
# 개발 환경 Nginx 설정
./web_services/scripts/setup_nginx.sh development

# 프로덕션 환경 Nginx 설정
./web_services/scripts/setup_nginx.sh production

# Dry-run
./web_services/scripts/setup_nginx.sh production --dry-run

# 설정만 업데이트 (재시작 안 함)
./web_services/scripts/setup_nginx.sh development --skip-restart
```

**주요 단계**:
```bash
#!/bin/bash
# setup_nginx.sh

# 1. Nginx 설치 확인 및 설치
# 2. 기존 설정 백업
# 3. 템플릿 렌더링 (Python 스크립트 호출)
# 4. 설정 파일 복사 (/etc/nginx/sites-available/)
# 5. 심볼릭 링크 생성 (/etc/nginx/sites-enabled/)
# 6. 설정 검증 (nginx -t)
# 7. Nginx 재시작 (systemctl restart nginx)
# 8. 상태 확인
```

---

#### Python 스크립트: generate_nginx_config.py

```bash
nano web_services/scripts/generate_nginx_config.py
```

**기능**:
- `web_services_config.yaml` 로드
- Nginx 템플릿 렌더링
- 설정 파일 생성

**사용**:
```bash
python3 web_services/scripts/generate_nginx_config.py development
python3 web_services/scripts/generate_nginx_config.py production
```

---

### 3️⃣ SSL 인증서 설정 (30분)

#### 3-1. 자체 서명 인증서 (개발/테스트)

```bash
# 인증서 생성 스크립트
nano web_services/scripts/generate_self_signed_cert.sh
chmod +x web_services/scripts/generate_self_signed_cert.sh
```

**내용**:
```bash
#!/bin/bash
# generate_self_signed_cert.sh

DOMAIN=${1:-hpc.example.com}
CERT_DIR=${2:-/etc/ssl/certs}
KEY_DIR=${3:-/etc/ssl/private}

echo "자체 서명 SSL 인증서 생성: $DOMAIN"

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$KEY_DIR/$DOMAIN.key" \
  -out "$CERT_DIR/$DOMAIN.crt" \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Cluster/CN=$DOMAIN"

echo "✅ 인증서 생성 완료:"
echo "   Certificate: $CERT_DIR/$DOMAIN.crt"
echo "   Key: $KEY_DIR/$DOMAIN.key"
```

**사용**:
```bash
./web_services/scripts/generate_self_signed_cert.sh hpc.example.com
```

---

#### 3-2. Let's Encrypt 인증서 (프로덕션)

```bash
nano web_services/scripts/setup_letsencrypt.sh
chmod +x web_services/scripts/setup_letsencrypt.sh
```

**내용**:
```bash
#!/bin/bash
# setup_letsencrypt.sh

DOMAIN=${1}
EMAIL=${2}

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "사용법: $0 <domain> <email>"
    exit 1
fi

# Certbot 설치
sudo apt install -y certbot python3-certbot-nginx

# 인증서 발급
sudo certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive

# 자동 갱신 설정
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

echo "✅ Let's Encrypt 인증서 설정 완료"
```

**사용**:
```bash
./web_services/scripts/setup_letsencrypt.sh hpc.example.com admin@example.com
```

---

#### 3-3. web_services_config.yaml SSL 설정 업데이트

**자체 서명 인증서**:
```yaml
nginx:
  production:
    ssl:
      enabled: true
      cert_path: "/etc/ssl/certs/hpc.example.com.crt"
      key_path: "/etc/ssl/private/hpc.example.com.key"
```

**Let's Encrypt**:
```yaml
nginx:
  production:
    ssl:
      enabled: true
      cert_path: "/etc/letsencrypt/live/hpc.example.com/fullchain.pem"
      key_path: "/etc/letsencrypt/live/hpc.example.com/privkey.pem"
```

---

### 4️⃣ 테스트 및 검증 (40분)

#### 테스트 1: 개발 환경 Nginx 설정

```bash
# Nginx 설정
./web_services/scripts/setup_nginx.sh development

# 설정 검증
sudo nginx -t

# Nginx 상태 확인
sudo systemctl status nginx

# 설정 파일 확인
sudo cat /etc/nginx/sites-enabled/hpc_web_services.conf
```

#### 테스트 2: 프로덕션 환경 설정 (Dry-run)

```bash
# Dry-run
./web_services/scripts/setup_nginx.sh production --dry-run

# 생성된 설정 파일 확인
cat /tmp/nginx_config_preview.conf
```

#### 테스트 3: 전체 통합 테스트

```bash
# 1. 환경 변수 파일 생성
python3 web_services/scripts/generate_env_files.py development

# 2. 서비스 시작
./start_complete.sh

# 3. Nginx 설정
./web_services/scripts/setup_nginx.sh development

# 4. 브라우저에서 접속
# http://localhost/
# http://localhost/dashboard
# http://localhost/cae
# http://localhost/vnc

# 5. 헬스 체크
./web_services/scripts/health_check.sh
```

#### 테스트 4: Reverse Proxy 동작 확인

```bash
# Auth Portal
curl -I http://localhost/auth/health

# Dashboard API
curl -I http://localhost/api/health

# CAE API
curl -I http://localhost/cae/api/health
```

#### 테스트 5: WebSocket 연결 확인

```bash
# wscat 설치 (Node.js)
npm install -g wscat

# WebSocket 연결 테스트
wscat -c ws://localhost/ws
```

#### 테스트 6: SSL 인증서 확인 (프로덕션)

```bash
# 자체 서명 인증서 생성
./web_services/scripts/generate_self_signed_cert.sh hpc.example.com

# Nginx 설정 (프로덕션)
./web_services/scripts/setup_nginx.sh production

# SSL 확인
openssl s_client -connect hpc.example.com:443 -servername hpc.example.com

# 브라우저에서 접속
# https://hpc.example.com/
```

---

## ⚠️ 주의사항

### ❌ 하지 말아야 할 것

1. **Nginx 기본 설정 파일 직접 수정 금지**
   - `/etc/nginx/nginx.conf` - 건드리지 말 것
   - 항상 `sites-available/` 사용

2. **SSL 인증서 Git에 커밋 금지**
   - `.key`, `.crt` 파일은 민감 정보
   - `.gitignore`에 추가

3. **프로덕션에서 자체 서명 인증서 사용 금지**
   - 브라우저 경고 발생
   - Let's Encrypt 사용 권장

### ✅ 반드시 해야 할 것

1. **Nginx 설정 검증**
   ```bash
   sudo nginx -t
   ```

2. **방화벽 설정 (프로덕션)**
   ```bash
   # HTTP
   sudo ufw allow 80/tcp

   # HTTPS
   sudo ufw allow 443/tcp

   # 내부 포트는 막기
   sudo ufw deny 4430/tcp
   sudo ufw deny 4431/tcp
   # ... 기타 포트
   ```

3. **SSL 인증서 자동 갱신 확인 (Let's Encrypt)**
   ```bash
   sudo systemctl status certbot.timer
   ```

---

## 🔧 트러블슈팅

### 문제 1: Nginx 설정 검증 실패

**증상**:
```
nginx: [emerg] unknown directive "proxy_pass"
```

**해결**:
```bash
# Nginx 모듈 확인
nginx -V 2>&1 | grep -o with-http_[a-z_]*_module

# http_proxy_module 확인
# 없으면 Nginx 재설치
sudo apt install --reinstall nginx-full
```

### 문제 2: 502 Bad Gateway

**증상**:
```
502 Bad Gateway
```

**해결**:
```bash
# 백엔드 서비스 실행 확인
./web_services/scripts/health_check.sh

# 특정 서비스 시작
cd dashboard/auth_portal_4430
python3 app.py

# Nginx 로그 확인
sudo tail -f /var/log/nginx/error.log
```

### 문제 3: WebSocket 연결 실패

**증상**:
```
WebSocket connection to 'ws://localhost/ws' failed
```

**해결**:
```bash
# Nginx 설정 확인
sudo nginx -T | grep -A 10 "location /ws"

# WebSocket 헤더 확인
# proxy_http_version 1.1
# proxy_set_header Upgrade $http_upgrade
# proxy_set_header Connection "upgrade"
```

### 문제 4: SSL 인증서 오류

**증상**:
```
SSL: error:0B080074:x509 certificate routines
```

**해결**:
```bash
# 인증서 파일 권한 확인
ls -la /etc/ssl/certs/hpc.example.com.crt
ls -la /etc/ssl/private/hpc.example.com.key

# 권한 수정
sudo chmod 644 /etc/ssl/certs/hpc.example.com.crt
sudo chmod 600 /etc/ssl/private/hpc.example.com.key

# Nginx 재시작
sudo systemctl restart nginx
```

---

## 📈 진행 상황 체크

### Phase 4 완료 기준

- [x] Phase 3 완료 확인
- [ ] Nginx 설정 템플릿 작성 (main.conf.j2)
- [ ] `setup_nginx.sh` 스크립트 작성
- [ ] `generate_nginx_config.py` 스크립트 작성
- [ ] SSL 인증서 설정 스크립트 작성 (자체 서명)
- [ ] Let's Encrypt 설정 스크립트 작성 (선택)
- [ ] 개발 환경 Nginx 테스트 통과
- [ ] Reverse proxy 동작 확인
- [ ] `verify_phase4.sh` 통과

### 완료 후 다음 단계

```bash
# Phase 4 완료 확인
./verify_phase4.sh

# 성공 시 출력 예상:
# ✅✅✅ Phase 4 완료!
#
# 📋 다음 단계:
#    cat PHASE5_GUIDE.md
```

---

## 🎓 Phase 4에서 생성된 파일 목록

### 신규 생성 파일

```
web_services/
├── templates/
│   └── nginx/
│       ├── main.conf.j2                # 메인 Nginx 템플릿
│       ├── development.conf.j2         # 개발 환경 전용 (선택)
│       └── production.conf.j2          # 프로덕션 전용 (선택)
└── scripts/
    ├── setup_nginx.sh                  # Nginx 설정 자동화
    ├── generate_nginx_config.py        # Nginx 설정 생성
    ├── generate_self_signed_cert.sh    # 자체 서명 인증서
    └── setup_letsencrypt.sh            # Let's Encrypt (선택)
```

### 생성될 시스템 파일

```
/etc/nginx/
├── sites-available/
│   └── hpc_web_services.conf          # Nginx 설정
└── sites-enabled/
    └── hpc_web_services.conf          # 심볼릭 링크

/etc/ssl/
├── certs/
│   └── hpc.example.com.crt            # SSL 인증서
└── private/
    └── hpc.example.com.key            # SSL 개인키
```

---

## 🚀 사용 시나리오 예시

### 시나리오 1: 개발 서버에 Nginx 설정

```bash
# 1. 환경 변수 파일 생성
python3 web_services/scripts/generate_env_files.py development

# 2. 서비스 시작
./start_complete.sh

# 3. Nginx 설정
./web_services/scripts/setup_nginx.sh development

# 4. 브라우저 접속
# http://localhost/
```

### 시나리오 2: 프로덕션 배포

```bash
# 1. SSL 인증서 생성
./web_services/scripts/setup_letsencrypt.sh hpc.example.com admin@example.com

# 2. 환경 변수 파일 생성 (프로덕션)
python3 web_services/scripts/generate_env_files.py production

# 3. 서비스 시작
./start_complete.sh

# 4. Nginx 설정 (프로덕션)
./web_services/scripts/setup_nginx.sh production

# 5. 방화벽 설정
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 6. 브라우저 접속
# https://hpc.example.com/
```

### 시나리오 3: Nginx 설정만 업데이트

```bash
# 설정 파일만 재생성 (서비스 재시작 안 함)
./web_services/scripts/setup_nginx.sh production --skip-restart

# 수동으로 재시작
sudo systemctl reload nginx
```

---

## ⏭️ Phase 5 준비사항

Phase 4 완료 후 Phase 5에서는:

1. **통합 테스트**
   - 전체 워크플로우 테스트
   - 새 서버 배포 시뮬레이션

2. **문서 완성**
   - 최종 사용자 가이드
   - 운영 매뉴얼

3. **최종 검증**
   - 모든 Phase 통합 확인
   - 성능 테스트

---

## 💬 질문 및 지원

Phase 4 진행 중 문제 발생 시:

1. `verify_phase4.sh` 실행하여 누락 확인
2. Nginx 로그 확인: `sudo tail -f /var/log/nginx/error.log`
3. 설정 검증: `sudo nginx -t`

**예상 소요 시간: 3-4시간**
**난이도: 중상급 (Nginx, SSL, 네트워크 지식 필요)**
