# HPC 웹 서비스 문제 해결 가이드

## 📋 목차

- [일반적인 문제](#일반적인-문제)
- [서비스별 문제](#서비스별-문제)
- [네트워크 문제](#네트워크-문제)
- [SSL 인증서 문제](#ssl-인증서-문제)
- [성능 문제](#성능-문제)
- [로그 분석](#로그-분석)

---

## 일반적인 문제

### 문제: 서비스가 시작되지 않음

**증상**:
```bash
./web_services/scripts/health_check.sh
# ❌ Auth Portal Backend (4430) - DOWN
```

**원인 및 해결**:

#### 1. 포트 이미 사용 중
```bash
# 확인
lsof -i:4430

# 해결: 기존 프로세스 종료
kill $(lsof -ti:4430)
```

#### 2. 가상환경 활성화 안 됨 (Python 서비스)
```bash
# 확인
cd dashboard/auth_portal_4430
which python3  # venv 경로가 나와야 함

# 해결
source venv/bin/activate
python3 app.py
```

#### 3. 의존성 미설치
```bash
# 확인
cd dashboard/auth_portal_4430
source venv/bin/activate
pip list

# 해결
pip install -r requirements.txt
```

#### 4. .env 파일 없음
```bash
# 확인
ls dashboard/auth_portal_4430/.env

# 해결
python3 web_services/scripts/generate_env_files.py development
```

---

### 문제: Nginx 502 Bad Gateway

**증상**:
브라우저에서 "502 Bad Gateway" 오류

**원인 및 해결**:

#### 1. 백엔드 서비스 다운
```bash
# 확인
./web_services/scripts/health_check.sh

# 해결: 서비스 재시작
./stop_complete.sh
./start_complete.sh
```

#### 2. Nginx 설정 오류
```bash
# 확인
sudo nginx -t

# 로그 확인
sudo tail -f /var/log/nginx/hpc_error.log

# 해결: 설정 재생성
./web_services/scripts/setup_nginx.sh development
sudo systemctl reload nginx
```

#### 3. 포트 불일치
```bash
# Nginx 설정 확인
sudo grep "proxy_pass" /etc/nginx/sites-enabled/hpc_web_services.conf

# 서비스 포트 확인
./web_services/scripts/health_check.sh

# 불일치 시: 설정 재생성
python3 web_services/scripts/generate_nginx_config.py development
sudo systemctl reload nginx
```

---

### 문제: 환경 전환 후 서비스 오류

**증상**:
```bash
./web_services/scripts/reconfigure_web_services.sh production
# 실행 후 서비스 접속 불가
```

**원인 및 해결**:

#### 1. 서비스 미재시작
```bash
# 환경 전환 후 반드시 재시작
./stop_complete.sh
./start_complete.sh
```

#### 2. .env 파일 불일치
```bash
# 확인
cat dashboard/auth_portal_4430/.env | grep FLASK_ENV

# production이어야 하는데 development인 경우
python3 web_services/scripts/generate_env_files.py production
./stop_complete.sh
./start_complete.sh
```

#### 3. Nginx 설정 미업데이트
```bash
# Nginx도 환경에 맞게 업데이트 필요
./web_services/scripts/setup_nginx.sh production
sudo systemctl reload nginx
```

---

### 문제: 롤백 후에도 문제 지속

**증상**:
롤백 실행했지만 여전히 서비스 오류

**해결**:

```bash
# 1. 현재 백업 목록 확인
./web_services/scripts/rollback.sh --list

# 2. 더 이전 백업으로 롤백
./web_services/scripts/rollback.sh --backup 20241018_120000

# 3. 수동 확인
cat dashboard/auth_portal_4430/.env

# 4. 필요 시 수동 재생성
python3 web_services/scripts/generate_env_files.py development

# 5. 서비스 재시작
./stop_complete.sh
./start_complete.sh
```

---

## 서비스별 문제

### Auth Portal Backend (4430)

**문제**: JWT 인증 실패

**로그**:
```
Invalid JWT signature
```

**해결**:
```bash
# JWT_SECRET_KEY 확인
cat dashboard/auth_portal_4430/.env | grep JWT_SECRET_KEY

# 모든 서비스가 동일한 SECRET_KEY 사용하는지 확인
grep JWT_SECRET_KEY dashboard/*/.env

# 불일치 시: 재생성
python3 web_services/scripts/generate_env_files.py development
./stop_complete.sh && ./start_complete.sh
```

---

### Dashboard Backend (5010)

**문제**: 데이터베이스 연결 실패

**로그**:
```
Connection refused to Redis
```

**해결**:
```bash
# Redis 설치 확인
redis-cli ping
# 예상: PONG

# Redis 미설치 시
sudo apt install -y redis-server
sudo systemctl start redis-server
sudo systemctl enable redis-server

# Redis 포트 확인
cat dashboard/backend_5010/.env | grep REDIS_PORT
# 기본: 6379
```

---

### CAE Backend (5000)

**문제**: 시작 시 즉시 종료

**확인**:
```bash
# 로그 확인
tail -f dashboard/kooCAEWebServer_5000/logs/app.log

# 수동 실행으로 오류 확인
cd dashboard/kooCAEWebServer_5000
source venv/bin/activate
python3 main.py
```

**일반적인 원인**:
- 필수 디렉토리 없음
- 설정 파일 오류
- Python 패키지 버전 충돌

**해결**:
```bash
# 가상환경 재생성
cd dashboard/kooCAEWebServer_5000
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

### Frontend 서비스 (3010, 4431, 5173, 8002)

**문제**: npm run dev 실행 시 포트 충돌

**오류**:
```
Error: listen EADDRINUSE: address already in use :::5173
```

**해결**:
```bash
# 포트 사용 프로세스 확인
lsof -i:5173

# 종료
kill $(lsof -ti:5173)

# 재시작
cd dashboard/kooCAEWeb_5173
npm run dev
```

**문제**: 빌드 오류

**오류**:
```
Module not found: Can't resolve 'module_name'
```

**해결**:
```bash
# node_modules 재설치
cd dashboard/kooCAEWeb_5173
rm -rf node_modules package-lock.json
npm install
npm run dev
```

---

## 네트워크 문제

### 문제: 외부에서 접속 불가

**증상**:
로컬에서는 접속 가능하지만 외부에서 접속 불가

**확인 및 해결**:

#### 1. 방화벽 확인
```bash
# UFW 상태 확인
sudo ufw status

# 80, 443 포트 허용 확인
sudo ufw status | grep -E "80|443"

# 미허용 시
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

#### 2. Nginx 리스닝 확인
```bash
# Nginx가 모든 인터페이스에서 리스닝하는지 확인
sudo netstat -tuln | grep -E ":80|:443"

# 0.0.0.0:80 또는 :::80 이어야 함
# 127.0.0.1:80 이면 로컬만 접속 가능
```

#### 3. 클라우드 보안 그룹 (AWS/GCP/Azure)
```bash
# 클라우드 콘솔에서 보안 그룹 확인
# Inbound Rules: 80, 443 포트 허용 확인
```

---

### 문제: DNS 해석 실패

**증상**:
```bash
curl https://your-domain.com/
# curl: (6) Could not resolve host: your-domain.com
```

**확인 및 해결**:

```bash
# DNS 조회
dig your-domain.com

# A 레코드 확인
nslookup your-domain.com

# 서버 IP 확인
curl ifconfig.me

# /etc/hosts에 임시 추가 (테스트용)
echo "YOUR_SERVER_IP your-domain.com" | sudo tee -a /etc/hosts
```

---

## SSL 인증서 문제

### 문제: SSL 인증서 만료

**증상**:
```
ERR_CERT_DATE_INVALID
```

**확인**:
```bash
# 인증서 만료일 확인
openssl x509 -in /etc/ssl/certs/your-domain.crt -noout -dates
```

**해결**:

**Let's Encrypt**:
```bash
# 갱신
sudo certbot renew
sudo systemctl reload nginx

# 자동 갱신 확인
sudo systemctl status certbot.timer
```

**자체 서명**:
```bash
# 새 인증서 생성
sudo ./web_services/scripts/generate_self_signed_cert.sh your-domain.com
sudo systemctl reload nginx
```

---

### 문제: SSL 인증서 경로 오류

**증상**:
```bash
sudo nginx -t
# nginx: [emerg] cannot load certificate "/etc/ssl/certs/your-domain.crt": BIO_new_file() failed
```

**확인 및 해결**:
```bash
# 인증서 파일 존재 확인
ls -la /etc/ssl/certs/your-domain.crt
ls -la /etc/ssl/private/your-domain.key

# 파일 없음 시: 인증서 생성
sudo ./web_services/scripts/generate_self_signed_cert.sh your-domain.com

# 권한 확인
sudo chmod 644 /etc/ssl/certs/your-domain.crt
sudo chmod 600 /etc/ssl/private/your-domain.key
```

---

### 문제: 자체 서명 인증서 브라우저 경고

**증상**:
"Your connection is not private" (NET::ERR_CERT_AUTHORITY_INVALID)

**설명**:
자체 서명 인증서는 브라우저가 신뢰하지 않는 정상적인 동작입니다.

**해결 방법**:

**옵션 1: 경고 무시하고 진행 (개발 환경)**
- Chrome: "고급" → "안전하지 않은 사이트로 이동"

**옵션 2: Let's Encrypt 사용 (프로덕션)**
```bash
./web_services/scripts/setup_letsencrypt.sh your-domain.com admin@your-domain.com
```

**옵션 3: 브라우저에 인증서 수동 추가 (개발 환경)**
```bash
# 인증서 다운로드
sudo cp /etc/ssl/certs/your-domain.crt ~/

# 브라우저 설정 → 인증서 관리 → 신뢰할 수 있는 루트 인증 기관에 추가
```

---

## 성능 문제

### 문제: 응답 속도 느림

**확인**:
```bash
# 응답 시간 측정
time curl -I http://localhost:4430/auth/health

# 0.1초 이상이면 느린 것
```

**원인 및 해결**:

#### 1. 시스템 리소스 부족
```bash
# CPU 확인
top

# 메모리 확인
free -h

# 디스크 I/O 확인
iostat -x 1

# 해결: 불필요한 프로세스 종료, 서버 스펙 업그레이드
```

#### 2. 데이터베이스 쿼리 느림
```bash
# Redis 응답 시간 확인
redis-cli --latency

# 해결: Redis 재시작
sudo systemctl restart redis-server
```

#### 3. Nginx 타임아웃
```bash
# Nginx 타임아웃 설정 확인
sudo grep timeout /etc/nginx/sites-enabled/hpc_web_services.conf

# web_services_config.yaml에서 조정 가능
nano web_services_config.yaml
# nginx.timeouts 섹션 수정

# 재생성
python3 web_services/scripts/generate_nginx_config.py development
sudo systemctl reload nginx
```

---

### 문제: 메모리 부족

**증상**:
```bash
free -h
#               total        used        free
# Mem:           8.0G        7.8G        200M
```

**확인**:
```bash
# 메모리 사용량 상위 프로세스
ps aux --sort=-%mem | head -10
```

**해결**:

```bash
# 1. 불필요한 서비스 중지
./stop_complete.sh

# 2. 필요한 서비스만 시작
# 예: CAE 서비스만 사용
cd dashboard/kooCAEWebServer_5000
source venv/bin/activate
python3 main.py &

cd dashboard/kooCAEWeb_5173
npm run dev &

# 3. 스왑 메모리 추가 (임시 해결)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 4. 서버 스펙 업그레이드 (영구 해결)
```

---

## 로그 분석

### Nginx 로그 분석

**502 오류 발생 시**:
```bash
# 최근 502 오류 확인
sudo grep "502" /var/log/nginx/hpc_error.log | tail -20

# upstream 연결 실패 확인
sudo grep "upstream" /var/log/nginx/hpc_error.log | tail -20

# → 백엔드 서비스 다운: ./start_complete.sh
```

**504 Timeout 발생 시**:
```bash
# 타임아웃 오류 확인
sudo grep "upstream timed out" /var/log/nginx/hpc_error.log

# → Nginx 타임아웃 증가 필요 또는 백엔드 성능 개선
```

---

### Python 서비스 로그 분석

**Import Error**:
```bash
# 로그 확인
tail -f dashboard/auth_portal_4430/logs/app.log
# ModuleNotFoundError: No module named 'flask'

# 해결
cd dashboard/auth_portal_4430
source venv/bin/activate
pip install -r requirements.txt
```

**환경 변수 오류**:
```bash
# 로그 확인
# KeyError: 'JWT_SECRET_KEY'

# 해결
cat dashboard/auth_portal_4430/.env | grep JWT_SECRET_KEY
# 없으면: python3 web_services/scripts/generate_env_files.py development
```

---

## 긴급 복구 절차

### 전체 시스템 다운 시

```bash
# 1. 모든 서비스 중지
./stop_complete.sh
pkill -f python3
pkill -f node
pkill -f vite

# 2. 최신 백업으로 롤백
./web_services/scripts/rollback.sh --latest

# 3. Nginx 재시작
sudo systemctl restart nginx

# 4. 서비스 재시작
./start_complete.sh

# 5. 헬스 체크
./web_services/scripts/health_check.sh

# 6. 문제 지속 시: 수동 재설정
python3 web_services/scripts/generate_env_files.py development
./web_services/scripts/setup_nginx.sh development
sudo systemctl reload nginx
```

---

## 자주 묻는 질문 (FAQ)

### Q: 환경 전환 후 서비스가 안 됩니다

A: 서비스 재시작 필요합니다.
```bash
./stop_complete.sh
./start_complete.sh
```

### Q: Nginx 502 오류가 계속 발생합니다

A: 백엔드 서비스 상태 확인:
```bash
./web_services/scripts/health_check.sh
# DOWN 서비스 확인 후 재시작
```

### Q: SSL 인증서 오류가 발생합니다

A: 인증서 경로 및 만료일 확인:
```bash
openssl x509 -in /etc/ssl/certs/your-domain.crt -noout -dates
sudo ./web_services/scripts/generate_self_signed_cert.sh your-domain.com
```

### Q: 롤백이 안 됩니다

A: 백업 목록 확인:
```bash
./web_services/scripts/rollback.sh --list
# 백업 없으면: 수동 재생성
python3 web_services/scripts/generate_env_files.py development
```

### Q: 특정 포트가 사용 중이라고 나옵니다

A: 기존 프로세스 종료:
```bash
lsof -i:PORT_NUMBER
kill $(lsof -ti:PORT_NUMBER)
```

---

## 연락처 및 지원

### 로그 제출

문제 해결을 위해 다음 로그를 함께 제출해주세요:

```bash
# 시스템 정보
uname -a > system_info.txt
df -h >> system_info.txt
free -h >> system_info.txt

# 서비스 상태
./web_services/scripts/health_check.sh > health_check.txt

# Nginx 로그
sudo tail -n 100 /var/log/nginx/hpc_error.log > nginx_error.txt

# 서비스 로그
tail -n 100 dashboard/*/logs/app.log > service_logs.txt

# 압축
tar czf logs_$(date +%Y%m%d_%H%M%S).tar.gz system_info.txt health_check.txt nginx_error.txt service_logs.txt
```

### 추가 리소스

- **설치 가이드**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **운영 가이드**: [OPERATIONS.md](OPERATIONS.md)
- **Phase 가이드**: PHASE0_GUIDE.md ~ PHASE5_GUIDE.md

---

**작성일**: 2025-10-19
**버전**: 1.0
**최종 업데이트**: 2025-10-19
