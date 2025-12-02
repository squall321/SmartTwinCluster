# HPC 웹 서비스 운영 가이드

## 📋 목차

- [일상 운영 작업](#일상-운영-작업)
- [서비스 관리](#서비스-관리)
- [로그 확인 방법](#로그-확인-방법)
- [환경 전환 절차](#환경-전환-절차)
- [성능 모니터링](#성능-모니터링)
- [유지보수 작업](#유지보수-작업)

---

## 일상 운영 작업

### 서비스 상태 확인

```bash
# 헬스 체크 (권장: 매일 1회)
./web_services/scripts/health_check.sh
```

**예상 출력**:
```
🔍 웹 서비스 헬스 체크
====================
✅ Dashboard Frontend             (3010) - HEALTHY
✅ Auth Portal Backend            (4430) - HEALTHY
✅ Auth Portal Frontend           (4431) - HEALTHY
✅ CAE Backend                    (5000) - HEALTHY
...
✅ 전체: 11/11 서비스 정상
```

**상태 코드**:
- `✅ HEALTHY`: 정상 (포트 열림 + 프로세스 실행 중)
- `⚠️ DEGRADED`: 부분 동작 (포트만 열림 또는 프로세스만 실행 중)
- `❌ DOWN`: 중지됨

### Nginx 상태 확인

```bash
# Nginx 실행 상태
sudo systemctl status nginx

# Nginx 설정 검증
sudo nginx -t

# Nginx 프로세스 확인
ps aux | grep nginx
```

### 디스크 사용량 확인

```bash
# 전체 디스크 사용량
df -h

# 프로젝트 디렉토리 크기
du -sh /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 로그 파일 크기
du -sh /var/log/nginx/
```

---

## 서비스 관리

### 서비스 시작

```bash
# 전체 서비스 시작
./start.sh

# 특정 서비스만 시작 (예: Auth Portal Backend)
cd dashboard/auth_portal_4430
source venv/bin/activate
python3 app.py
```

### 서비스 중지

```bash
# 전체 서비스 중지
./stop.sh

# 특정 포트의 서비스 중지
PORT=4430
PID=$(lsof -ti:$PORT)
kill $PID
```

### 서비스 재시작

```bash
# 전체 서비스 재시작
./stop.sh
sleep 2
./start.sh

# Nginx만 재시작
sudo systemctl restart nginx
```

### 서비스별 시작 스크립트

각 서비스의 시작 방법:

**Python 백엔드 서비스**:
```bash
# Auth Portal Backend (4430)
cd dashboard/auth_portal_4430
source venv/bin/activate
python3 app.py

# Dashboard Backend (5010)
cd dashboard/backend_5010
source venv/bin/activate
python3 app.py

# CAE Backend (5000)
cd dashboard/kooCAEWebServer_5000
source venv/bin/activate
python3 main.py
```

**Node.js 프론트엔드 서비스**:
```bash
# Auth Portal Frontend (4431)
cd dashboard/auth_portal_4431
npm run dev

# Dashboard Frontend (3010)
cd dashboard/frontend_3010
npm run dev

# CAE Frontend (5173)
cd dashboard/kooCAEWeb_5173
npm run dev
```

**모니터링 서비스**:
```bash
# Prometheus (9090)
cd dashboard/prometheus-2.45.0.linux-amd64
./prometheus --config.file=prometheus.yml

# Node Exporter (9100)
cd dashboard/node_exporter-1.6.0.linux-amd64
./node_exporter
```

---

## 로그 확인 방법

### Nginx 로그

```bash
# Access 로그 (실시간)
sudo tail -f /var/log/nginx/hpc_access.log

# Error 로그 (실시간)
sudo tail -f /var/log/nginx/hpc_error.log

# 최근 100줄 확인
sudo tail -n 100 /var/log/nginx/hpc_access.log

# 특정 IP 필터링
sudo grep "192.168.1.100" /var/log/nginx/hpc_access.log

# 오류만 필터링
sudo grep "error" /var/log/nginx/hpc_error.log
```

### 서비스 로그

```bash
# Auth Portal Backend
tail -f dashboard/auth_portal_4430/logs/app.log

# Dashboard Backend
tail -f dashboard/backend_5010/logs/app.log

# CAE Backend
tail -f dashboard/kooCAEWebServer_5000/logs/app.log
```

### 시스템 로그

```bash
# 시스템 전체 로그
sudo journalctl -f

# Nginx 서비스 로그
sudo journalctl -u nginx -f

# 특정 시간대 로그
sudo journalctl --since "1 hour ago"
sudo journalctl --since "2025-10-19 14:00" --until "2025-10-19 15:00"
```

### 로그 분석 예시

**502 Bad Gateway 오류 확인**:
```bash
sudo grep "502" /var/log/nginx/hpc_error.log | tail -20
```

**가장 많이 접속한 IP 확인**:
```bash
sudo awk '{print $1}' /var/log/nginx/hpc_access.log | sort | uniq -c | sort -rn | head -10
```

**응답 시간 분석**:
```bash
sudo awk '{print $NF}' /var/log/nginx/hpc_access.log | sort -n | tail -100
```

---

## 환경 전환 절차

### Development → Production

```bash
# 1. 백업 생성 (자동)
./web_services/scripts/reconfigure_web_services.sh production --dry-run

# 2. 실제 전환
./web_services/scripts/reconfigure_web_services.sh production

# 3. .env 파일 확인
cat dashboard/auth_portal_4430/.env | grep -E "FLASK_ENV|SSO_ENABLED"
# 예상:
# FLASK_ENV=production
# SSO_ENABLED=true

# 4. Nginx 설정 업데이트
./web_services/scripts/setup_nginx.sh production

# 5. 서비스 재시작
./stop.sh
./start.sh

# 6. 헬스 체크
./web_services/scripts/health_check.sh

# 7. 브라우저 접속 테스트
# https://your-domain.com/
```

**소요 시간**: 약 2-3분

### Production → Development

```bash
# 1. 개발 환경으로 전환
./web_services/scripts/reconfigure_web_services.sh development

# 2. Nginx 설정 업데이트
./web_services/scripts/setup_nginx.sh development

# 3. 서비스 재시작
./stop.sh
./start.sh

# 4. 확인
cat dashboard/auth_portal_4430/.env | grep FLASK_ENV
# 예상: FLASK_ENV=development
```

### 롤백 (긴급 복구)

```bash
# 최신 백업으로 롤백
./web_services/scripts/rollback.sh --latest

# 백업 목록 확인
./web_services/scripts/rollback.sh --list

# 특정 백업으로 롤백
./web_services/scripts/rollback.sh --backup 20241019_123456

# 롤백 후 서비스 재시작
./stop.sh
./start.sh
```

**롤백 소요 시간**: 약 10초

---

## 성능 모니터링

### Prometheus 사용

**접속**:
- 개발: http://localhost:9090
- 프로덕션: https://your-domain.com/prometheus (인증 필요)

**주요 쿼리**:

```promql
# CPU 사용률
100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 메모리 사용률
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

# 디스크 사용률
100 - ((node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"} * 100) / node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"})

# 네트워크 수신률
rate(node_network_receive_bytes_total[5m])
```

### 시스템 리소스 확인

```bash
# CPU 사용률
top -bn1 | head -20

# 메모리 사용량
free -h

# 네트워크 연결 상태
netstat -tuln | grep LISTEN

# 프로세스별 메모리 사용량
ps aux --sort=-%mem | head -10

# 프로세스별 CPU 사용량
ps aux --sort=-%cpu | head -10
```

### 서비스 응답 시간 측정

```bash
# Auth Portal
time curl -I http://localhost:4430/auth/health

# Dashboard Backend
time curl -I http://localhost:5010/api/health

# CAE Backend
time curl -I http://localhost:5000/cae/api/health
```

### 포트 사용 현황

```bash
# 모든 서비스 포트 확인
for PORT in 3010 4430 4431 5000 5001 5010 5011 5173 8002 9090 9100; do
  echo "Port $PORT:"
  lsof -i:$PORT | tail -1
done
```

---

## 유지보수 작업

### 로그 정리

```bash
# Nginx 로그 정리 (30일 이상 된 로그)
sudo find /var/log/nginx/ -name "*.log.*" -mtime +30 -delete

# 서비스 로그 정리
find dashboard/*/logs/ -name "*.log.*" -mtime +30 -delete

# 로그 압축
sudo gzip /var/log/nginx/hpc_access.log.1
```

### 백업 정리

```bash
# 30일 이상 된 백업 삭제
find web_services/backups/ -type d -mtime +30 -exec rm -rf {} +

# 백업 목록 확인
ls -lt web_services/backups/
```

### 의존성 업데이트

```bash
# Python 패키지 업데이트
cd dashboard/auth_portal_4430
source venv/bin/activate
pip install --upgrade pip
pip list --outdated

# 특정 패키지 업데이트
pip install --upgrade flask pyyaml

# Node.js 패키지 업데이트
cd dashboard/frontend_3010
npm outdated
npm update
```

### SSL 인증서 갱신

**Let's Encrypt (자동)**:
```bash
# 자동 갱신 상태 확인
sudo systemctl status certbot.timer

# 수동 갱신 (필요시)
sudo certbot renew
sudo systemctl reload nginx
```

**자체 서명 인증서**:
```bash
# 새 인증서 생성 (기존 자동 백업)
sudo ./web_services/scripts/generate_self_signed_cert.sh your-domain.com

# Nginx 재시작
sudo systemctl reload nginx
```

### 설정 파일 업데이트

```bash
# web_services_config.yaml 수정 후
nano web_services_config.yaml

# 환경 변수 재생성
python3 web_services/scripts/generate_env_files.py production

# 서비스 재시작
./stop_complete.sh
./start_complete.sh
```

---

## 정기 점검 체크리스트

### 일일 점검

- [ ] 헬스 체크 실행
- [ ] Nginx 상태 확인
- [ ] 에러 로그 확인
- [ ] 디스크 사용량 확인

### 주간 점검

- [ ] 전체 서비스 재시작
- [ ] 로그 파일 확인 및 정리
- [ ] 백업 목록 확인
- [ ] 성능 메트릭 검토 (Prometheus)

### 월간 점검

- [ ] 의존성 업데이트 확인
- [ ] SSL 인증서 만료일 확인
- [ ] 백업 정리 (30일 이상)
- [ ] 보안 패치 적용
- [ ] 전체 시스템 백업

---

## 빠른 참조

### 주요 명령어

| 작업 | 명령어 |
|------|--------|
| 헬스 체크 | `./web_services/scripts/health_check.sh` |
| 전체 시작 | `./start_complete.sh` |
| 전체 중지 | `./stop_complete.sh` |
| 환경 전환 | `./web_services/scripts/reconfigure_web_services.sh <env>` |
| 롤백 | `./web_services/scripts/rollback.sh --latest` |
| Nginx 재시작 | `sudo systemctl reload nginx` |

### 주요 포트

| 서비스 | 포트 | 설명 |
|--------|------|------|
| Auth Portal Backend | 4430 | 인증 API |
| Auth Portal Frontend | 4431 | 로그인 UI |
| Dashboard Frontend | 3010 | 대시보드 UI |
| Dashboard Backend | 5010 | 대시보드 API |
| Dashboard WebSocket | 5011 | 실시간 통신 |
| CAE Backend | 5000 | CAE API |
| CAE Automation | 5001 | CAE 자동화 |
| CAE Frontend | 5173 | CAE UI |
| VNC Service | 8002 | VNC 관리 |
| Prometheus | 9090 | 모니터링 |
| Node Exporter | 9100 | 시스템 메트릭 |
| Nginx HTTP | 80 | 웹 서버 |
| Nginx HTTPS | 443 | 보안 웹 서버 |

### 주요 디렉토리

| 경로 | 설명 |
|------|------|
| `dashboard/` | 서비스 소스 코드 |
| `web_services/` | 자동화 스크립트 및 설정 |
| `web_services/backups/` | 설정 백업 |
| `web_services/templates/` | Jinja2 템플릿 |
| `/etc/nginx/sites-available/` | Nginx 설정 |
| `/var/log/nginx/` | Nginx 로그 |
| `/etc/ssl/certs/` | SSL 인증서 |
| `/etc/ssl/private/` | SSL 개인키 |

---

## 문제 발생 시 절차

1. **헬스 체크 실행**
   ```bash
   ./web_services/scripts/health_check.sh
   ```

2. **로그 확인**
   ```bash
   sudo tail -f /var/log/nginx/hpc_error.log
   ```

3. **서비스 재시작**
   ```bash
   ./stop_complete.sh
   ./start_complete.sh
   ```

4. **롤백 (필요시)**
   ```bash
   ./web_services/scripts/rollback.sh --latest
   ```

5. **문제 지속 시**
   - [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 참조
   - 로그 파일 분석
   - 시스템 관리자에게 문의

---

**작성일**: 2025-10-19
**버전**: 1.0
**관련 문서**: [DEPLOYMENT.md](DEPLOYMENT.md), [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
