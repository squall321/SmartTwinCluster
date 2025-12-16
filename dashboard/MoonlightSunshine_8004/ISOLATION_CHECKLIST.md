# Moonlight/Sunshine 구현 시 기존 시스템 격리 체크리스트

## ✅ 구현 전 필수 확인사항

### 1. Apptainer 이미지 격리
- [ ] `/opt/apptainers/vnc_*.sif` 파일을 절대 수정하지 않음
- [ ] 새 이미지를 `/opt/apptainers/sunshine_*.sif`로 생성
- [ ] 기존 VNC 이미지와 완전히 독립적인 빌드 수행

### 2. Sandbox 디렉토리 격리
- [ ] `/scratch/vnc_sandboxes/` 디렉토리 건드리지 않음
- [ ] 새 디렉토리 `/scratch/sunshine_sandboxes/` 생성
- [ ] 각 사용자별로 독립된 sandbox 할당

### 3. Redis 키 패턴 격리
- [ ] 기존 `vnc:session:*` 키 패턴과 충돌하지 않음
- [ ] 새 키 패턴 `moonlight:session:*` 사용
- [ ] SessionManager에서 prefix 명확히 분리

### 4. Slurm 리소스 격리
- [ ] QoS `moonlight` 생성하여 리소스 격리
- [ ] 기존 VNC Job은 QoS 없이 그대로 유지
- [ ] viz-node 리소스 경쟁 모니터링 계획 수립

### 5. 포트 충돌 방지
- [ ] 8004, 8005 포트가 사용 가능한지 확인
  ```bash
  sudo lsof -i :8004
  sudo lsof -i :8005
  ```
- [ ] 47989-48010 포트 범위 사용 가능 확인
- [ ] 기존 VNC 포트(5900-5999, 6900-6999)와 겹치지 않음

### 6. Nginx 설정 격리
- [ ] **새 파일 생성하지 않음** (중요!)
- [ ] 기존 `/etc/nginx/conf.d/auth-portal.conf`에 location만 추가
- [ ] 파일 수정 전 백업 필수
  ```bash
  sudo cp /etc/nginx/conf.d/auth-portal.conf \
         /etc/nginx/conf.d/auth-portal.conf.backup_$(date +%Y%m%d_%H%M%S)
  ```
- [ ] `nginx -t`로 문법 검사 후 적용

### 7. API 라우팅 격리
- [ ] 기존 `/api/vnc/*` 경로 유지
- [ ] 새 경로 `/api/moonlight/*` 사용
- [ ] 완전히 별도의 프로세스(Node.js)로 실행

### 8. 프로세스 격리
- [ ] 기존 `backend_5010` (Gunicorn) 건드리지 않음
- [ ] 새 프로세스 `MoonlightSunshine_8004/backend/server.js` (Node.js) 독립 실행
- [ ] Systemd service 파일 별도 생성

## ⚠️ 금지 사항

### ❌ 절대 하지 말 것
1. **기존 VNC 이미지 수정**
   ```bash
   # ❌ 이렇게 하지 마세요!
   sudo apptainer exec --writable /opt/apptainers/vnc_desktop.sif apt-get install sunshine
   ```

2. **기존 VNC Sandbox 수정**
   ```bash
   # ❌ 이렇게 하지 마세요!
   rm -rf /scratch/vnc_sandboxes/*
   ```

3. **Redis 키 충돌**
   ```python
   # ❌ 이렇게 하지 마세요!
   redis.set('vnc:session:moonlight-123', data)  # 'vnc:' prefix 사용 금지
   ```

4. **Nginx 별도 파일로 443 포트 재정의**
   ```nginx
   # ❌ /etc/nginx/conf.d/moonlight.conf 이렇게 하지 마세요!
   server {
       listen 443 ssl http2;  # auth-portal.conf와 충돌!
   }
   ```

5. **기존 VNC API 코드 수정**
   ```python
   # ❌ backend_5010/vnc_api.py를 수정하지 마세요!
   # 완전히 별도의 파일로 작성
   ```

## ✅ 올바른 방법

### 1. 새 Apptainer 이미지 생성
```bash
# ✅ 기존 이미지를 복사하여 새로 생성
sudo apptainer build --sandbox /tmp/sunshine_sandbox /opt/apptainers/vnc_desktop.sif
sudo apptainer exec --writable /tmp/sunshine_sandbox apt-get install sunshine
sudo apptainer build /opt/apptainers/sunshine_xfce4.sif /tmp/sunshine_sandbox
```

### 2. 새 Sandbox 디렉토리 생성
```bash
# ✅ 완전히 별도 디렉토리
mkdir -p /scratch/sunshine_sandboxes/
```

### 3. Redis 키 패턴 분리
```python
# ✅ 명확히 다른 prefix 사용
redis.set('moonlight:session:ml-user01-1234567890', data)
```

### 4. Nginx 기존 파일에 추가
```bash
# ✅ 기존 파일 백업 후 수정
sudo cp /etc/nginx/conf.d/auth-portal.conf \
       /etc/nginx/conf.d/auth-portal.conf.backup

# ✅ 기존 server 블록 내부에 location만 추가
sudo vi /etc/nginx/conf.d/auth-portal.conf
# location /moonlight/ { ... } 추가
```

### 5. 독립된 API 서버 실행
```bash
# ✅ 완전히 별도 프로세스
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004
node backend/server.js
```

## 🔍 구현 후 검증

### 1. 기존 VNC 서비스 정상 동작 확인
```bash
# VNC 세션 생성 테스트
curl -X POST https://110.15.177.120/api/vnc/sessions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"image_id":"xfce4"}'

# VNC 웹 접속 테스트
# https://110.15.177.120/vnc/
```

### 2. 기존 파일 무결성 확인
```bash
# Apptainer 이미지 (수정되지 않았는지 확인)
ls -lh /opt/apptainers/vnc_*.sif
md5sum /opt/apptainers/vnc_desktop.sif  # 변경되면 안 됨

# Sandbox 디렉토리 (건드려지지 않았는지 확인)
ls -lh /scratch/vnc_sandboxes/
```

### 3. Redis 키 충돌 확인
```bash
# VNC 세션 키만 존재해야 함
redis-cli KEYS "vnc:session:*"

# Moonlight 세션 키는 별도
redis-cli KEYS "moonlight:session:*"
```

### 4. 포트 충돌 확인
```bash
# 기존 VNC 포트
sudo lsof -i :5901-5999

# 신규 Moonlight 포트
sudo lsof -i :8004
sudo lsof -i :8005
sudo lsof -i :47989
```

### 5. Nginx 설정 확인
```bash
# 문법 검사
sudo nginx -t

# 설정 확인 (중복 listen 없는지)
sudo nginx -T | grep "listen 443"
# Expected: 1개만 나와야 함
```

## 📊 롤백 계획

만약 Moonlight 구현이 기존 시스템에 영향을 주는 경우:

### 1. Nginx 롤백
```bash
sudo cp /etc/nginx/conf.d/auth-portal.conf.backup \
       /etc/nginx/conf.d/auth-portal.conf
sudo nginx -t && sudo systemctl reload nginx
```

### 2. Moonlight 서비스 중지
```bash
# Systemd service 중지
sudo systemctl stop moonlight-gateway

# 프로세스 강제 종료
pkill -f "node.*server.js"
```

### 3. Moonlight 전용 리소스 정리
```bash
# Sandbox 삭제 (기존 VNC는 건드리지 않음)
rm -rf /scratch/sunshine_sandboxes/

# Redis 키 삭제
redis-cli KEYS "moonlight:session:*" | xargs redis-cli DEL

# Apptainer 이미지 삭제 (선택사항)
# sudo rm /opt/apptainers/sunshine_*.sif
```

### 4. 기존 VNC 서비스 재확인
```bash
# VNC 세션 목록 조회
curl https://110.15.177.120/api/vnc/sessions \
  -H "Authorization: Bearer $TOKEN"

# 웹 접속 테스트
# https://110.15.177.120/vnc/
```

## 🎯 최종 확인

구현 완료 후 다음 사항을 확인하세요:

- [x] 기존 VNC 서비스가 정상 작동함
- [x] 기존 VNC 세션 생성/접속이 정상 작동함
- [x] `/opt/apptainers/vnc_*.sif` 파일이 수정되지 않음
- [x] `/scratch/vnc_sandboxes/` 디렉토리가 건드려지지 않음
- [x] Redis `vnc:session:*` 키가 영향받지 않음
- [x] Nginx에서 기존 VNC 경로(/vnc/, /vncproxy/)가 정상 작동함
- [x] 기존 VNC API(/api/vnc/*)가 정상 작동함

---

**원칙**: "Moonlight/Sunshine은 완전히 독립된 서비스로, 기존 VNC와 공존한다."
