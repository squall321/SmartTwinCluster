# 🚀 HPC Auth Portal 배포 가이드

다른 서버에 Auth Portal을 배포하기 위한 완전한 가이드

---

## 📋 사전 요구사항

### 시스템 요구사항
- **OS**: Ubuntu 22.04 LTS (권장)
- **RAM**: 최소 4GB
- **Disk**: 최소 20GB 여유 공간
- **네트워크**: 인터넷 접속 필요 (패키지 다운로드)

### 필수 권한
- `sudo` 권한 필요
- 방화벽 설정 권한 (포트 개방)

---

## 🎯 빠른 시작 (자동 설치)

### 1. 코드 다운로드
```bash
# Git으로 클론
git clone <repository-url>
cd KooSlurmInstallAutomationRefactory/dashboard

# 또는 압축 파일로 전송
scp -r dashboard/ user@target-server:~/
```

### 2. 일괄 설치 실행
```bash
cd dashboard
chmod +x install_all.sh
./install_all.sh
```

**설치 시간**: 약 15-20분

### 3. 서비스 시작
```bash
./start_phase1.sh
```

### 4. 접속 확인
- **Frontend**: http://localhost:4431
- **Backend API**: http://localhost:4430/health

---

## 📦 수동 설치 (단계별)

자동 설치가 실패하거나 커스터마이징이 필요한 경우:

### Step 1: 시스템 패키지 설치

```bash
# 패키지 목록 업데이트
sudo apt update

# Python 관련
sudo apt install -y python3 python3-pip python3-venv

# Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# XML/SAML 라이브러리
sudo apt install -y libxml2-dev libxmlsec1-dev libxmlsec1-openssl pkg-config

# 기타 필수 도구
sudo apt install -y git curl wget
```

### Step 2: Phase 0 인프라 설치

```bash
# Redis
./setup_phase0_redis.sh

# SAML Identity Provider
./setup_phase0_saml_idp.sh

# Nginx + SSL
./setup_phase0_nginx.sh

# Apptainer Sandbox
./setup_phase0_apptainer.sh

# 또는 일괄 설치
./setup_phase0_all.sh
```

### Step 3: Phase 1 Backend 설치

```bash
cd auth_portal_4430

# Python 가상 환경 생성
python3 -m venv venv
source venv/bin/activate

# 의존성 설치
pip install --upgrade pip
pip install -r requirements.txt

# .env 파일 설정
cp .env.template .env
# .env 파일 편집하여 SECRET_KEY와 JWT_SECRET_KEY 변경

deactivate
cd ..
```

### Step 4: Phase 1 Frontend 설치

```bash
cd auth_portal_4431

# Node.js 의존성 설치
npm install

cd ..
```

### Step 5: 검증

```bash
# Phase 0 검증
./validate_phase0.sh

# 서비스 시작
./start_phase1.sh

# 헬스 체크
curl http://localhost:4430/health
```

---

## 🔧 설정 파일 커스터마이징

### Backend 설정 (.env)

```bash
cd auth_portal_4430
nano .env
```

**중요 설정 항목:**

```env
# 프로덕션에서는 반드시 변경!
SECRET_KEY=your-random-secret-key-here
JWT_SECRET_KEY=your-jwt-secret-key-here

# JWT 만료 시간 (시간 단위)
JWT_EXPIRATION_HOURS=8

# Redis 설정
REDIS_HOST=localhost
REDIS_PORT=6379

# 서비스 URL (실제 도메인으로 변경)
DASHBOARD_URL=https://your-domain.com/dashboard/
CAE_URL=https://your-domain.com/cae/
VNC_URL=https://your-domain.com/vnc/
```

**비밀 키 생성:**
```bash
# SECRET_KEY 생성
openssl rand -hex 32

# JWT_SECRET_KEY 생성
openssl rand -hex 32
```

### Frontend 설정 (vite.config.ts)

실제 서버 환경에 맞게 프록시 설정 변경:

```typescript
export default defineConfig({
  plugins: [react()],
  server: {
    port: 4431,
    host: '0.0.0.0',
    proxy: {
      '/auth': {
        target: 'http://localhost:4430',
        changeOrigin: true
      }
    }
  }
})
```

---

## 🌐 프로덕션 배포

### Nginx 리버스 프록시 설정

```nginx
# /etc/nginx/conf.d/auth-portal.conf

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /path/to/ssl/cert.pem;
    ssl_certificate_key /path/to/ssl/key.pem;

    # Auth Frontend
    location / {
        proxy_pass http://localhost:4431;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Auth Backend
    location /auth/ {
        proxy_pass http://localhost:4430/auth/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Systemd 서비스 등록

**Backend 서비스:**
```bash
sudo nano /etc/systemd/system/auth-backend.service
```

```ini
[Unit]
Description=Auth Portal Backend
After=network.target redis.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/path/to/dashboard/auth_portal_4430
Environment="PATH=/path/to/dashboard/auth_portal_4430/venv/bin"
ExecStart=/path/to/dashboard/auth_portal_4430/venv/bin/python app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Frontend 서비스:**
```bash
sudo nano /etc/systemd/system/auth-frontend.service
```

```ini
[Unit]
Description=Auth Portal Frontend
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/path/to/dashboard/auth_portal_4431
ExecStart=/usr/bin/npm run dev
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**서비스 활성화:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable auth-backend auth-frontend
sudo systemctl start auth-backend auth-frontend
```

---

## 📊 포트 사용 현황

| 서비스 | 포트 | 프로토콜 | 설명 |
|--------|------|----------|------|
| Redis | 6379 | TCP | 세션 저장소 |
| SAML-IdP | 7000 | HTTP | 테스트 IdP |
| Auth Backend | 4430 | HTTP | Flask API |
| Auth Frontend | 4431 | HTTP | React 앱 |
| Nginx | 443 | HTTPS | 리버스 프록시 |

**방화벽 설정:**
```bash
# 필요한 포트만 개방
sudo ufw allow 443/tcp    # HTTPS
sudo ufw allow 22/tcp     # SSH
sudo ufw enable
```

---

## 🗂️ 디렉토리 구조

```
dashboard/
├── install_all.sh              # 통합 설치 스크립트 ⭐
├── start_phase1.sh             # 서비스 시작
├── stop_phase1.sh              # 서비스 종료
│
├── setup_phase0_all.sh         # Phase 0 일괄 설치
├── setup_phase0_redis.sh       # Redis 설치
├── setup_phase0_saml_idp.sh    # SAML-IdP 설치
├── setup_phase0_nginx.sh       # Nginx 설치
├── setup_phase0_apptainer.sh   # Apptainer 설정
├── validate_phase0.sh          # Phase 0 검증
│
├── auth_portal_4430/           # Backend
│   ├── app.py
│   ├── requirements.txt        # Python 의존성 ⭐
│   ├── .env.template           # 설정 템플릿 ⭐
│   ├── .env                    # 실제 설정 (git ignore)
│   └── venv/                   # Python 가상 환경
│
├── auth_portal_4431/           # Frontend
│   ├── package.json            # Node.js 의존성 ⭐
│   ├── vite.config.ts          # Vite 설정
│   ├── src/
│   └── node_modules/
│
├── saml_idp_7000/              # SAML IdP
│   ├── start_idp.sh
│   ├── stop_idp.sh
│   └── config/users.json       # 테스트 사용자
│
├── planning_phases/            # 문서
│   ├── Phase0_Prerequisites.md
│   └── Phase1_Auth_Portal.md
│
├── PHASE1_README.md            # Phase 1 사용 가이드
└── DEPLOYMENT.md               # 이 파일 ⭐
```

---

## ✅ 배포 체크리스트

### 설치 전
- [ ] Ubuntu 22.04 LTS 서버 준비
- [ ] sudo 권한 확인
- [ ] 인터넷 연결 확인
- [ ] 디스크 여유 공간 확인 (20GB+)

### 설치 중
- [ ] `install_all.sh` 실행 완료
- [ ] Phase 0 검증 통과
- [ ] .env 파일 SECRET_KEY 변경
- [ ] .env 파일 JWT_SECRET_KEY 변경

### 설치 후
- [ ] `./start_phase1.sh` 정상 실행
- [ ] http://localhost:4430/health 응답 확인
- [ ] http://localhost:4431 접속 확인
- [ ] Redis 연결 테스트: `redis-cli ping`
- [ ] 테스트 로그인 성공

### 프로덕션 배포
- [ ] SSL 인증서 설정
- [ ] Nginx 리버스 프록시 설정
- [ ] Systemd 서비스 등록
- [ ] 방화벽 설정
- [ ] 도메인 DNS 설정
- [ ] 로그 로테이션 설정
- [ ] 백업 스크립트 설정

---

## 🐛 트러블슈팅

### Python 의존성 설치 실패

```bash
# xmlsec1 라이브러리 누락
sudo apt install -y libxml2-dev libxmlsec1-dev libxmlsec1-openssl

# Python 헤더 파일 누락
sudo apt install -y python3-dev
```

### Node.js 버전 문제

```bash
# Node.js 20.x 재설치
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 버전 확인
node -v  # v20.x.x 이상
npm -v   # 10.x.x 이상
```

### Redis 연결 실패

```bash
# Redis 시작
sudo systemctl start redis-server

# 상태 확인
sudo systemctl status redis-server

# 연결 테스트
redis-cli ping
```

### 포트 충돌

```bash
# 포트 사용 중인 프로세스 확인
lsof -i :4430
lsof -i :4431
lsof -i :7000

# 프로세스 종료
sudo kill -9 <PID>
```

---

## 📚 추가 리소스

- **Phase 0 상세 가이드**: `planning_phases/Phase0_Prerequisites.md`
- **Phase 1 사용 가이드**: `PHASE1_README.md`
- **API 문서**: `PHASE1_README.md` 참조

---

## 📞 지원

문제 발생 시:
1. 로그 파일 확인:
   ```bash
   tail -f auth_portal_4430/logs/backend.log
   tail -f auth_portal_4430/logs/auth_portal.log
   ```

2. 검증 스크립트 실행:
   ```bash
   ./validate_phase0.sh
   ```

3. 서비스 재시작:
   ```bash
   ./stop_phase1.sh
   ./start_phase1.sh
   ```

---

**작성일**: 2025-10-16
**버전**: 1.0
**대상 OS**: Ubuntu 22.04 LTS
