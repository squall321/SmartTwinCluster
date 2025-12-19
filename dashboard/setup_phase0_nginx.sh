#!/bin/bash
# Phase 0: Nginx 및 SSL 인증서 설정 스크립트
# SSL 모드 지원: letsencrypt | self_signed | none

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SSL 모드 결정 (인자 또는 YAML에서 읽기)
SSL_MODE="${1:-}"

# 인자가 없으면 YAML에서 읽기 시도
if [[ -z "$SSL_MODE" ]]; then
    # 프로젝트 루트에서 YAML 파일 찾기
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    for yaml_file in "$PROJECT_ROOT/my_multihead_cluster.yaml" "$PROJECT_ROOT/my_cluster.yaml" "$PROJECT_ROOT/config.yaml"; do
        if [[ -f "$yaml_file" ]]; then
            SSL_MODE=$(python3 -c "import yaml; c=yaml.safe_load(open('$yaml_file')); print(c.get('web', {}).get('ssl', {}).get('mode', 'self_signed'))" 2>/dev/null || echo "")
            if [[ -n "$SSL_MODE" ]]; then
                echo "SSL 모드를 YAML에서 읽음: $SSL_MODE ($yaml_file)"
                break
            fi
        fi
    done
fi

# 기본값
SSL_MODE="${SSL_MODE:-self_signed}"

echo "=== Phase 0: Nginx 및 SSL 설정 ==="
echo "SSL 모드: $SSL_MODE"
echo

# Nginx 설치 확인
if ! command -v nginx &> /dev/null; then
    echo "Nginx 설치 중..."
    sudo apt update
    sudo apt install -y nginx
    echo -e "${GREEN}✓${NC} Nginx 설치 완료"
else
    echo -e "${GREEN}✓${NC} Nginx가 이미 설치되어 있습니다: $(nginx -v 2>&1 | awk '{print $3}')"
fi

# SSL 모드가 none이 아닌 경우에만 SSL 설정
if [[ "$SSL_MODE" != "none" ]]; then
    # SSL 디렉토리 생성
    echo
    echo "SSL 인증서 디렉토리 확인..."
    sudo mkdir -p /etc/ssl/private
    sudo chmod 700 /etc/ssl/private

    # 자체 서명 SSL 인증서 생성 (self_signed 모드)
    if [[ "$SSL_MODE" == "self_signed" ]]; then
        echo
        echo "자체 서명 SSL 인증서 생성 중..."

        if [ -f "/etc/ssl/certs/nginx-selfsigned.crt" ]; then
            echo -e "${YELLOW}⚠${NC} 기존 인증서가 있습니다. 덮어쓰시겠습니까? (y/N)"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo "기존 인증서 사용"
            else
                sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                  -keyout /etc/ssl/private/nginx-selfsigned.key \
                  -out /etc/ssl/certs/nginx-selfsigned.crt \
                  -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/CN=slurm-dashboard.local" \
                  2>/dev/null
                echo -e "${GREEN}✓${NC} 자체 서명 인증서 생성 완료 (1년 유효)"
            fi
        else
            sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
              -keyout /etc/ssl/private/nginx-selfsigned.key \
              -out /etc/ssl/certs/nginx-selfsigned.crt \
              -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/CN=slurm-dashboard.local" \
              2>/dev/null
            echo -e "${GREEN}✓${NC} 자체 서명 인증서 생성 완료 (1년 유효)"
        fi

        # 권한 설정
        sudo chmod 600 /etc/ssl/private/nginx-selfsigned.key
        sudo chmod 644 /etc/ssl/certs/nginx-selfsigned.crt
    elif [[ "$SSL_MODE" == "letsencrypt" ]]; then
        echo
        echo -e "${YELLOW}⚠${NC} Let's Encrypt 모드 선택됨"
        echo "  - certbot이 설치되어 있어야 합니다"
        echo "  - 도메인이 공개적으로 접근 가능해야 합니다"
        echo "  - Phase 5 (phase5_web.sh)에서 인증서를 발급받습니다"
    fi

    # DH 파라미터 생성 (시간 소요: 1-5분)
    echo
    echo "DH 파라미터 생성 중 (1-5분 소요)..."

    if [ -f "/etc/ssl/certs/dhparam.pem" ]; then
        echo -e "${GREEN}✓${NC} DH 파라미터가 이미 존재합니다."
    else
        sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 2>/dev/null
        sudo chmod 644 /etc/ssl/certs/dhparam.pem
        echo -e "${GREEN}✓${NC} DH 파라미터 생성 완료"
    fi

    # Nginx snippets 디렉토리 생성
    echo
    echo "Nginx 설정 snippets 생성 중..."
    sudo mkdir -p /etc/nginx/snippets

    # SSL 파라미터 스니펫
    sudo tee /etc/nginx/snippets/ssl-params.conf > /dev/null << 'EOF'
# SSL Configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;

# DH Parameters
ssl_dhparam /etc/ssl/certs/dhparam.pem;

# Security Headers
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options DENY always;
add_header X-Content-Type-Options nosniff always;
add_header X-XSS-Protection "1; mode=block" always;
EOF

    # 인증서 스니펫
    sudo tee /etc/nginx/snippets/self-signed.conf > /dev/null << 'EOF'
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOF

    echo -e "${GREEN}✓${NC} SSL snippets 생성 완료"
else
    echo
    echo -e "${YELLOW}⚠${NC} SSL 모드 'none': SSL 인증서 및 snippets 생성 건너뜀"
    echo -e "${YELLOW}⚠${NC} 주의: HTTP만 사용 - 보안에 취약할 수 있습니다!"
fi

# Auth Portal용 Nginx 설정 생성
echo
echo "Auth Portal용 Nginx 설정 생성 중 (SSL 모드: $SSL_MODE)..."

if [[ "$SSL_MODE" == "none" ]]; then
    # HTTP only 모드 (SSL 비활성화)
    sudo tee /etc/nginx/conf.d/auth-portal.conf > /dev/null << 'EOF'
# HTTP Server (SSL disabled)
server {
    listen 80;
    listen [::]:80;
    server_name _;

    # Logging
    access_log /var/log/nginx/auth-portal-access.log;
    error_log /var/log/nginx/auth-portal-error.log;

    # Root location (Auth Frontend)
    location / {
        proxy_pass http://localhost:4431;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Auth Backend API
    location /auth/ {
        proxy_pass http://localhost:4430/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # CORS headers
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
    }

    # Dashboard (existing service)
    location /dashboard/ {
        proxy_pass http://localhost:3010/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # CAE (existing service)
    location /cae/ {
        proxy_pass http://localhost:5173/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    echo -e "${GREEN}✓${NC} auth-portal.conf 생성 완료 (HTTP only)"
else
    # HTTPS 모드 (self_signed 또는 letsencrypt)
    sudo tee /etc/nginx/conf.d/auth-portal.conf > /dev/null << 'EOF'
# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name _;

    return 301 https://$host$request_uri;
}

# HTTPS Server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    # SSL Certificates
    include snippets/self-signed.conf;
    include snippets/ssl-params.conf;

    # Logging
    access_log /var/log/nginx/auth-portal-access.log;
    error_log /var/log/nginx/auth-portal-error.log;

    # Root location (Auth Frontend will be here later in Phase 1)
    location / {
        # Placeholder - will proxy to auth_portal_4431 in Phase 1
        proxy_pass http://localhost:4431;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Auth Backend API
    location /auth/ {
        # Placeholder - will proxy to auth_portal_4430 in Phase 1
        proxy_pass http://localhost:4430/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # CORS headers
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
    }

    # Dashboard (existing service)
    location /dashboard/ {
        proxy_pass http://localhost:3010/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # CAE (existing service)
    location /cae/ {
        proxy_pass http://localhost:5173/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    echo -e "${GREEN}✓${NC} auth-portal.conf 생성 완료 (HTTPS)"
fi

# Nginx 설정 테스트
echo
echo "Nginx 설정 테스트 중..."

if sudo nginx -t 2>&1 | grep -q "syntax is ok"; then
    echo -e "${GREEN}✓${NC} Nginx 설정 문법 검사 통과"
else
    echo -e "${RED}✗${NC} Nginx 설정 오류"
    sudo nginx -t
    exit 1
fi

# Nginx 시작 및 활성화
echo
echo "Nginx 서비스 시작 중..."

sudo systemctl enable nginx
sudo systemctl restart nginx

sleep 2
if sudo systemctl is-active --quiet nginx; then
    echo -e "${GREEN}✓${NC} Nginx 서비스 실행 중"
else
    echo -e "${RED}✗${NC} Nginx 서비스 시작 실패"
    sudo systemctl status nginx
    exit 1
fi

# 방화벽 설정 (ufw가 활성화된 경우)
echo
echo "방화벽 포트 확인 중..."

if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    echo "UFW 방화벽이 활성화되어 있습니다. 포트 허용 중..."
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 4430/tcp  # Auth Backend
    sudo ufw allow 4431/tcp  # Auth Frontend
    sudo ufw allow 7000/tcp  # SAML-IdP
    echo -e "${GREEN}✓${NC} 방화벽 포트 허용 완료"
else
    echo -e "${YELLOW}⚠${NC} UFW 방화벽이 비활성화되어 있습니다."
fi

# 접속 테스트 (SSL 모드에 따라 다름)
echo

if [[ "$SSL_MODE" == "none" ]]; then
    echo "HTTP 접속 테스트 중..."
    if curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -qE "200|502"; then
        echo -e "${GREEN}✓${NC} HTTP 접속 가능 (Phase 1에서 4431 서비스 시작 시 정상 동작)"
    else
        echo -e "${YELLOW}⚠${NC} HTTP 접속 테스트 - 응답: $(curl -s -o /dev/null -w "%{http_code}" http://localhost)"
    fi
else
    echo "HTTPS 접속 테스트 중..."
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost | grep -qE "200|502"; then
        echo -e "${GREEN}✓${NC} HTTPS 접속 가능 (Phase 1에서 4431 서비스 시작 시 정상 동작)"
    else
        echo -e "${YELLOW}⚠${NC} HTTPS 접속 테스트 - 응답: $(curl -k -s -o /dev/null -w "%{http_code}" https://localhost)"
    fi

    # HTTP → HTTPS 리다이렉트 테스트
    if curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "301"; then
        echo -e "${GREEN}✓${NC} HTTP → HTTPS 리다이렉트 동작"
    else
        echo -e "${YELLOW}⚠${NC} HTTP → HTTPS 리다이렉트 확인 필요"
    fi
fi

echo
echo -e "${GREEN}✓✓✓ Phase 0: Nginx 및 SSL 설정 완료! ✓✓✓${NC}"
echo
echo "SSL 모드: $SSL_MODE"
echo "Nginx 상태: sudo systemctl status nginx"
echo "Nginx 재시작: sudo systemctl restart nginx"
echo "설정 파일: /etc/nginx/conf.d/auth-portal.conf"
echo "SSL 인증서: /etc/ssl/certs/nginx-selfsigned.crt"
echo
echo "다음 단계: ./setup_phase0_apptainer.sh"
