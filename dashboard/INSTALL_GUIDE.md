# 설치 가이드 (Installation Guide)

HPC Auth Portal 시스템 설치 방법

---

## 📋 설치 전 준비사항

### 시스템 요구사항
- **OS**: Ubuntu 22.04 LTS
- **Python**: 3.10+
- **Node.js**: 18+ (20.x 권장)
- **권한**: sudo 권한 필요
- **디스크**: 최소 10GB 여유 공간
- **메모리**: 최소 4GB RAM

---

## 🚀 빠른 설치 (자동)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard

# 자동 설치 (-y 옵션으로 대화형 확인 건너뛰기)
./install_all.sh -y
```

**설치되는 항목:**
- ✅ Phase 0: Redis, Nginx, SAML-IdP, Apptainer
- ✅ Phase 1: Auth Backend, Auth Frontend
- ✅ 의존성: Python 패키지, Node.js 패키지

**예상 소요 시간:** 15-20분

---

## 📝 단계별 설치 (수동)

### 1. Phase 0 인프라 설치

```bash
# Redis 설치 (세션 저장소)
./setup_phase0_redis.sh

# Nginx 설치 (리버스 프록시)
./setup_phase0_nginx.sh

# SAML IdP 설치 (개발/테스트용)
./setup_phase0_saml_idp.sh

# Apptainer 설치 (GPU VNC용)
./setup_phase0_apptainer.sh
```

### 2. Phase 0 검증

```bash
./validate_phase0.sh
```

**예상 결과:**
```
[PASS] Redis is running
[PASS] Redis responds to PING
[PASS] Nginx is running
[PASS] Nginx config is valid
...
결과: 17 PASS, 0 FAIL, 4 WARN
```

### 3. Phase 1 Auth Portal 설치

```bash
# Auth Backend 설치
cd auth_portal_4430
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Auth Frontend 설치
cd ../auth_portal_4431
npm install
```

### 4. Phase 1 시작

```bash
./start_phase1.sh
```

**확인:**
```bash
# Auth Backend Health Check
curl http://localhost:4430/health
# {"service":"auth-portal","status":"healthy"}

# Auth Frontend
curl http://localhost:4431
# React 앱 HTML 반환
```

---

## 🔧 문제 해결

### 문제 1: `saml-idp: command not found`

**원인**: saml-idp가 글로벌로 설치되지 않음

**해결책**:
```bash
# setup_phase0_saml_idp.sh가 이미 수정됨 (npx 사용)
# 또는 수동으로 수정
cd saml_idp_7000
# start_idp.sh 에서 saml-idp → npx saml-idp 로 변경
```

### 문제 2: `install_all.sh`가 멈춤

**원인**: 사용자 입력 대기 중

**해결책**:
```bash
# -y 옵션 사용
./install_all.sh -y

# 또는 수동으로 'y' 입력
./install_all.sh
# 프롬프트에서 'y' 입력
```

### 문제 3: Redis 시작 실패

**원인**: 포트 6379 사용 중

**해결책**:
```bash
# 기존 Redis 확인
sudo systemctl status redis-server

# Redis 재시작
sudo systemctl restart redis-server

# 포트 확인
sudo lsof -i :6379
```

### 문제 4: Nginx 설정 오류

**원인**: 설정 파일 문법 오류

**해결책**:
```bash
# 설정 검증
sudo nginx -t

# 로그 확인
sudo tail -f /var/log/nginx/error.log

# 재시작
sudo systemctl restart nginx
```

### 문제 5: Python venv 생성 실패

**원인**: `python3-venv` 패키지 미설치

**해결책**:
```bash
# Ubuntu 22.04
sudo apt install -y python3.10-venv

# 또는
sudo apt install -y python3-venv
```

### 문제 6: xmlsec 설치 실패

**원인**: 시스템 의존성 누락

**해결책**:
```bash
sudo apt install -y libxml2-dev libxmlsec1-dev libxmlsec1-openssl pkg-config
```

---

## ✅ 설치 확인 체크리스트

### Phase 0 확인
- [ ] Redis 실행 중 (`redis-cli PING` → PONG)
- [ ] Nginx 실행 중 (`sudo systemctl status nginx`)
- [ ] SAML IdP 실행 중 (`curl http://localhost:7000/metadata`)
- [ ] Apptainer 설치됨 (`apptainer --version`)

### Phase 1 확인
- [ ] Auth Backend 실행 중 (`curl http://localhost:4430/health`)
- [ ] Auth Frontend 실행 중 (`curl http://localhost:4431`)
- [ ] JWT 토큰 발급 가능 (`curl POST http://localhost:4430/auth/test/login`)

### 통합 테스트
- [ ] 브라우저에서 http://localhost:4431 접속 가능
- [ ] SSO 로그인 화면 표시
- [ ] Dashboard (5010) JWT 인증 작동

---

## 🔄 재설치

```bash
# Phase 1 완전 삭제
./stop_phase1.sh
rm -rf auth_portal_4430/venv
rm -rf auth_portal_4431/node_modules
rm -rf saml_idp_7000

# Phase 0 서비스 중지 (주의!)
sudo systemctl stop redis-server
sudo systemctl stop nginx

# 재설치
./install_all.sh -y
```

---

## 📦 오프라인 설치

### 1. 패키지 다운로드 (온라인 환경)

```bash
# Python 패키지
pip download -r auth_portal_4430/requirements.txt -d ./packages/python

# Node.js 패키지
cd auth_portal_4431
npm pack
cd ..
```

### 2. 오프라인 설치

```bash
# Python 패키지
pip install --no-index --find-links=./packages/python -r requirements.txt

# Node.js 패키지
npm install --offline
```

---

## 🚀 Production 배포

### 보안 체크리스트

- [ ] JWT_SECRET_KEY 변경 (32바이트 이상 랜덤 값)
- [ ] Redis 비밀번호 설정
- [ ] Nginx HTTPS 인증서 설치
- [ ] `/auth/test/login` 엔드포인트 비활성화
- [ ] CORS 설정 제한
- [ ] 방화벽 설정

### JWT Secret Key 변경

```bash
# 1. 랜덤 키 생성
openssl rand -hex 32

# 2. Auth Backend 설정
vim auth_portal_4430/.env
JWT_SECRET_KEY=<new_secret>

# 3. Dashboard Backend 설정 (동일한 키!)
vim backend_5010/.env
JWT_SECRET_KEY=<new_secret>

# 4. 재시작
./stop_phase1.sh
./start_phase1.sh
```

### Nginx HTTPS 설정

```bash
# Let's Encrypt 인증서
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com

# Nginx 설정 업데이트
sudo vim /etc/nginx/sites-available/hpc-portal
# HTTP → HTTPS 리다이렉트 추가
```

---

## 📞 지원

설치 중 문제가 발생하면:

1. **로그 확인**: 각 서비스의 로그 파일 검토
2. **검증 실행**: `./validate_phase0.sh`
3. **문서 참조**: USER_GUIDE.md, QUICK_REFERENCE.md
4. **Issue 등록**: GitHub Issues (있는 경우)

---

**작성일**: 2025-10-16  
**버전**: v1.0
