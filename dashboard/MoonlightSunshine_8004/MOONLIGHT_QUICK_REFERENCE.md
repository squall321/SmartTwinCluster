# Moonlight/Sunshine Quick Reference Guide

## 접근 URL

### 프론트엔드
```
https://<your-server>/moonlight/
```

### API 엔드포인트
```
https://<your-server>/api/moonlight/health
https://<your-server>/api/moonlight/sessions
https://<your-server>/api/moonlight/create_session
https://<your-server>/api/moonlight/terminate_session
```

---

## 서비스 구성

### Backend
- **포트**: 8004 (localhost only)
- **프로세스**: Python Gunicorn (2 workers, 2 threads each)
- **설정 파일**: `backend_moonlight_8004/gunicorn_config.py`
- **API 파일**: `backend_moonlight_8004/moonlight_api.py`

### Frontend
- **빌드 디렉토리**: `moonlight_frontend_8003/dist/`
- **배포 위치**: `/var/www/html/moonlight/`
- **Vite 개발 서버**: 8003 (개발 시에만)

### Nginx 라우팅
```nginx
# Frontend
location /moonlight {
    alias /var/www/html/moonlight;
    try_files $uri $uri/ /moonlight/index.html;
}

# Backend API
location /api/moonlight/ {
    rewrite ^/api/moonlight/(.*)$ /$1 break;
    proxy_pass http://localhost:8004;
}
```

---

## 서비스 관리

### 전체 서비스 시작
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./start_production.sh
```

### Moonlight만 재시작 (수동)
```bash
cd MoonlightSunshine_8004/backend_moonlight_8004

# 1. 기존 프로세스 종료
pkill -9 -f "gunicorn.*backend_moonlight_8004"
fuser -k -9 8004/tcp

# 2. Python 캐시 삭제
find . -type f -name "*.pyc" -delete
find . -type d -name "__pycache__" -exec rm -rf {} +

# 3. 시작
gunicorn -c gunicorn_config.py moonlight_api:app &
```

### 프론트엔드 빌드 및 배포
```bash
cd moonlight_frontend_8003

# 빌드
npm run build

# 배포 (sudo 필요)
sudo rm -rf /var/www/html/moonlight
sudo cp -r dist /var/www/html/moonlight
sudo chown -R www-data:www-data /var/www/html/moonlight
```

---

## 세션 관리

### Redis 세션 확인
```bash
# 모든 Moonlight 세션 조회
redis-cli -a changeme --scan --pattern "moonlight:session:*"

# 특정 세션 상세 정보
redis-cli -a changeme HGETALL moonlight:session:ml-koopark-1234567890
```

### 세션 상태 전이
```
starting → pending → running → completed/failed
                              ↓
                        (5분 후 자동 삭제)
```

### 수동 세션 정리
```bash
# 모든 Moonlight 세션 삭제
redis-cli -a changeme --scan --pattern "moonlight:session:*" | \
  xargs -I {} redis-cli -a changeme DEL {}

# 완료된 세션만 삭제
for key in $(redis-cli -a changeme --scan --pattern "moonlight:session:*"); do
  status=$(redis-cli -a changeme HGET $key status)
  if [ "$status" = "completed" ] || [ "$status" = "failed" ]; then
    redis-cli -a changeme DEL $key
    echo "Deleted: $key"
  fi
done
```

---

## Slurm 작업 관리

### 사용자 작업 조회
```bash
squeue -u koopark
```

### 특정 작업 상세 정보
```bash
scontrol show job <job_id>
```

### 작업 취소
```bash
scancel <job_id>
```

### 작업 로그 확인 (compute node에서)
```bash
# viz-node001에 SSH 접속 후
cat /scratch/sunshine_logs/ml-koopark-<timestamp>.log
```

---

## 트러블슈팅

### 세션이 "starting"에서 멈춤
**원인**: Slurm job이 실행되지 않거나 실패
**해결**:
1. `squeue -u koopark`로 작업 상태 확인
2. 작업 로그 확인: `/scratch/sunshine_logs/ml-<user>-<timestamp>.log` (compute node에서)
3. GPU 노드 상태 확인: `sinfo -N -o "%N %T %G"`

### Backend API 응답 없음
**원인**: Gunicorn 프로세스 죽음
**해결**:
```bash
# 프로세스 확인
pgrep -f "gunicorn.*backend_moonlight_8004"

# 로그 확인
tail -f backend_moonlight_8004/logs/gunicorn_error.log

# 재시작
./start_production.sh
```

### Frontend 404 에러
**원인**: `/var/www/html/moonlight/` 배포 안 됨
**해결**:
```bash
# 빌드 파일 존재 확인
ls moonlight_frontend_8003/dist/

# 재배포
sudo cp -r moonlight_frontend_8003/dist /var/www/html/moonlight
sudo chown -R www-data:www-data /var/www/html/moonlight
```

### GPU 없음 에러
**원인**: Compute node에 NVIDIA GPU가 없거나 nvidia-smi 설치 안 됨
**해결**:
- 테스트 환경: viz-node001/002는 AMD GPU 또는 오프라인 (정상)
- 프로덕션: NVIDIA GPU 있는 노드에서 실행 필요
- Partition 확인: `sinfo -o "%P %G %N"`

### NFS 마운트 이슈
**원인**: Compute node에서 `/scratch`, `/home` 접근 불가
**해결**:
```bash
# Head node에서 NFS export 설정
sudo exportfs -v

# Compute node에서 마운트 확인
ssh viz-node001 "df -h | grep -E 'scratch|home'"
```

---

## Health Check

### Backend 상태 확인
```bash
curl http://localhost:8004/health
# {"port":8004,"service":"moonlight_backend","status":"healthy"}

curl -k https://localhost/api/moonlight/health
# 동일한 응답
```

### 전체 시스템 점검
```bash
# 프로세스
pgrep -f "gunicorn.*backend_moonlight_8004"

# 포트
ss -tlnp | grep 8004

# Redis 연결
redis-cli -a changeme PING

# Nginx 설정
sudo nginx -t
```

---

## 로그 파일 위치

### Backend Logs
```
backend_moonlight_8004/logs/gunicorn_access.log  # 접근 로그
backend_moonlight_8004/logs/gunicorn_error.log   # 에러 로그
backend_moonlight_8004/logs/gunicorn.pid         # PID 파일
```

### Slurm Job Logs (Compute Node)
```
/scratch/sunshine_logs/ml-<username>-<timestamp>.log
```

### Nginx Logs
```
/var/log/nginx/auth-portal-access.log
/var/log/nginx/auth-portal-error.log
```

---

## 프로덕션 배포 체크리스트

### 필수 사항
- [ ] NVIDIA GPU 노드 확보 (NVENC 지원)
- [ ] NFS 공유 설정 (`/home`, `/scratch`, `/opt/apptainers`)
- [ ] Apptainer 이미지 배포 (`/opt/apptainers/sunshine_desktop.sif`)
- [ ] SSL 인증서 교체 (Self-signed → CA-signed)
- [ ] Redis 바인딩 변경 (0.0.0.0 → 127.0.0.1)

### 권장 사항
- [ ] Prometheus 메트릭 수집 설정
- [ ] 로그 로테이션 설정
- [ ] 백업 전략 수립
- [ ] 모니터링 알림 설정

---

## 개발 참고

### Backend API 추가
1. `moonlight_api.py`에 엔드포인트 추가
2. Python 캐시 삭제: `find . -name "*.pyc" -delete`
3. Gunicorn 재시작: `pkill -9 -f gunicorn.*8004 && gunicorn -c gunicorn_config.py moonlight_api:app`

### Frontend 수정
1. `moonlight_frontend_8003/src/` 파일 수정
2. 빌드: `npm run build`
3. 배포: `sudo cp -r dist /var/www/html/moonlight`

### Gunicorn 설정 변경
- 파일: `backend_moonlight_8004/gunicorn_config.py`
- Workers/Threads 조정
- Timeout 설정
- 로그 레벨 변경

---

**마지막 업데이트**: 2025-12-14 23:20 UTC
**작성자**: Claude Code
**상태**: Production Ready (GPU 노드 제외)
