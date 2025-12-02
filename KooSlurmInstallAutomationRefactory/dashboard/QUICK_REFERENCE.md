# 빠른 참조 가이드 (Quick Reference)

HPC 인증 포털 관리자용 치트시트

---

## 🚀 시스템 시작/종료

```bash
# Phase 0 검증
./validate_phase0.sh

# Phase 1 시작 (Auth Portal)
./start_phase1.sh

# Phase 1 종료
./stop_phase1.sh

# Dashboard Backend 시작 (선택적)
cd backend_5010
source venv/bin/activate
python3 app.py
```

---

## 🔍 서비스 상태 확인

```bash
# 모든 프로세스 확인
ps aux | grep -E "auth_portal|backend_5010|saml-idp" | grep -v grep

# 포트 사용 확인
ss -tlnp | grep -E "4430|4431|5010|7000"

# Health Check
curl http://localhost:4430/health          # Auth Backend
curl http://localhost:5010/api/health      # Dashboard Backend
redis-cli PING                             # Redis
```

---

## 🔐 JWT 토큰 관리

### 테스트 토큰 발급

```bash
# Admin 권한
curl -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","groups":["HPC-Admins"]}' | jq -r '.token'

# User 권한
curl -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{"username":"user","groups":["HPC-Users"]}' | jq -r '.token'
```

### 토큰 검증

```bash
# 토큰 변수에 저장
TOKEN="eyJhbGc..."

# 토큰 검증
curl -X POST http://localhost:4430/auth/verify \
  -H "Authorization: Bearer $TOKEN" | jq

# 사용자 정보 조회
curl http://localhost:4430/auth/user \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Redis 세션 관리

```bash
redis-cli

# 모든 세션 확인
KEYS jwt:*

# 특정 사용자 세션 확인
GET jwt:admin

# 세션 삭제 (강제 로그아웃)
DEL jwt:admin

# 모든 세션 삭제
FLUSHDB
```

---

## 🧪 API 테스트

### 인증 없이 테스트 (401 예상)

```bash
curl -X POST http://localhost:5010/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -d '{"jobName":"test","partition":"group1","nodes":1}'
```

### JWT 토큰으로 테스트 (200 예상)

```bash
# 1. 토큰 발급
TOKEN=$(curl -s -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","groups":["HPC-Admins"]}' | jq -r '.token')

# 2. 작업 제출
curl -X POST http://localhost:5010/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jobName": "test_job",
    "partition": "group1",
    "nodes": 1,
    "cpus": 128,
    "memory": "16GB",
    "time": "01:00:00",
    "script": "echo Hello World"
  }' | jq

# 3. 작업 목록 조회 (JWT 선택적)
curl http://localhost:5010/api/slurm/jobs | jq
```

### 권한 테스트

```bash
# GPU-Users (dashboard 권한 없음, 403 예상)
TOKEN_GPU=$(curl -s -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{"username":"gpu_user","groups":["GPU-Users"]}' | jq -r '.token')

curl -X POST http://localhost:5010/api/slurm/jobs/submit \
  -H "Authorization: Bearer $TOKEN_GPU" \
  -H "Content-Type: application/json" \
  -d '{"jobName":"test","partition":"group1","nodes":1}' | jq
```

---

## 📝 로그 확인

```bash
# Phase 1 서비스 로그
tail -f /tmp/phase1_auth_backend.log      # Auth Backend
tail -f /tmp/phase1_auth_frontend.log     # Auth Frontend
tail -f /tmp/phase1_saml_idp.log          # SAML IdP

# Dashboard Backend 로그 (직접 실행 시)
# 터미널에서 실시간 확인 가능

# 에러만 필터링
grep -i error /tmp/phase1_*.log

# 최근 100줄
tail -100 /tmp/phase1_auth_backend.log
```

---

## ⚙️ 설정 파일 위치

```bash
# Auth Portal Backend
auth_portal_4430/.env                     # JWT Secret, Redis 설정
auth_portal_4430/config/config.py         # 그룹 권한 매핑

# Dashboard Backend
backend_5010/.env                         # JWT Secret (Auth와 동일해야 함)
backend_5010/app.py                       # API 엔드포인트

# Nginx
/etc/nginx/sites-available/hpc-portal     # 리버스 프록시 설정

# Redis
/etc/redis/redis.conf                     # Redis 설정
```

---

## 🔄 서비스 재시작

### 전체 재시작

```bash
./stop_phase1.sh
./start_phase1.sh
```

### 개별 재시작

```bash
# Auth Backend만
pkill -f "auth_portal_4430.*python"
cd auth_portal_4430
source venv/bin/activate
python3 app.py &

# Auth Frontend만
pkill -f "auth_portal_4431"
cd auth_portal_4431
npm run dev &

# Dashboard Backend만
pkill -f "backend_5010.*python"
cd backend_5010
source venv/bin/activate
python3 app.py &
```

---

## 🐛 문제 해결

### Redis 연결 실패

```bash
# Redis 상태 확인
sudo systemctl status redis-server

# Redis 재시작
sudo systemctl restart redis-server

# 연결 테스트
redis-cli PING
```

### 포트 충돌

```bash
# 포트 사용 프로세스 확인
sudo lsof -i :4430
sudo lsof -i :4431
sudo lsof -i :5010

# 프로세스 종료
kill -9 <PID>
```

### JWT 검증 실패

```bash
# 1. Secret Key 일치 확인
grep JWT_SECRET_KEY auth_portal_4430/.env
grep JWT_SECRET_KEY backend_5010/.env

# 2. 토큰 디코드 테스트
python3 << 'EOF'
import jwt
token = "eyJhbGc..."
secret = "your-jwt-secret-key-change-this-in-production"
try:
    payload = jwt.decode(token, secret, algorithms=["HS256"])
    print("Success:", payload)
except Exception as e:
    print("Error:", e)
EOF
```

### SAML IdP 오류

```bash
# IdP 재시작
pkill -f "saml-idp"
cd auth_portal_4430/saml-idp
npm start &

# IdP 메타데이터 확인
curl http://localhost:7000/metadata
```

---

## 📊 모니터링

### Prometheus Metrics

```bash
# Dashboard Backend 메트릭
curl http://localhost:5010/metrics

# 특정 메트릭 확인
curl http://localhost:5010/metrics | grep slurm_active_jobs
```

### 실시간 모니터링

```bash
# 요청 로그 실시간 확인
tail -f /tmp/phase1_auth_backend.log | grep -E "POST|GET"

# 에러 로그 실시간 확인
tail -f /tmp/phase1_*.log | grep -i error

# Redis 모니터링
redis-cli MONITOR
```

---

## 🔐 보안 체크리스트

### Production 배포 전 필수 체크

- [ ] JWT_SECRET_KEY 변경 (랜덤 32바이트 이상)
- [ ] Auth Portal과 Dashboard Backend의 JWT_SECRET_KEY 동일한지 확인
- [ ] Redis 비밀번호 설정 (`requirepass` in redis.conf)
- [ ] Nginx HTTPS 설정 (SSL 인증서 적용)
- [ ] SAML IdP 메타데이터 URL을 실제 IdP로 변경
- [ ] `/auth/test/login` 엔드포인트 비활성화 (Production)
- [ ] CORS 설정 검토 (특정 도메인만 허용)
- [ ] 로그 파일 권한 확인 (640 또는 600)

```bash
# Secret Key 생성
openssl rand -hex 32

# 파일 권한 설정
chmod 600 auth_portal_4430/.env
chmod 600 backend_5010/.env
```

---

## 📦 백업/복구

### 설정 백업

```bash
# 설정 파일 백업
tar czf hpc-auth-config-$(date +%Y%m%d).tar.gz \
  auth_portal_4430/.env \
  auth_portal_4430/config/ \
  backend_5010/.env \
  /etc/nginx/sites-available/hpc-portal

# Redis 데이터 백업
redis-cli BGSAVE
cp /var/lib/redis/dump.rdb backup/redis-$(date +%Y%m%d).rdb
```

### 복구

```bash
# 설정 복구
tar xzf hpc-auth-config-YYYYMMDD.tar.gz

# Redis 데이터 복구
sudo systemctl stop redis-server
sudo cp backup/redis-YYYYMMDD.rdb /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb
sudo systemctl start redis-server
```

---

## 📈 성능 튜닝

### Redis 최적화

```bash
# redis.conf 설정
maxmemory 512mb
maxmemory-policy allkeys-lru

# 연결 수 제한
maxclients 10000

# 영속성 비활성화 (세션 전용이므로)
save ""
```

### Backend 성능

```bash
# Production 환경에서는 Gunicorn 사용
pip install gunicorn

# Gunicorn으로 실행 (4 workers)
gunicorn -w 4 -b 0.0.0.0:5010 app:app
```

---

## 🔗 유용한 링크

- [상세 사용자 가이드](USER_GUIDE.md)
- [Phase 0 설치](setup_phase0_all.sh)
- [Phase 1 문서](PHASE1_README.md)
- [Phase 2 JWT 통합](PHASE2_README.md)
- [배포 가이드](DEPLOYMENT.md)

---

**업데이트**: 2025-10-16
**버전**: v1.0
