# 시스템 접속 가이드

**서버 IP**: `110.15.177.120`
**상태**: ✅ Backend Running, ✅ Nginx Running

---

## 🌐 주요 접속 URL

### 1. 메인 랜딩 페이지 (시작점)
```
http://110.15.177.120/app/
```

**화면 구성**:
- 🎮 **Moonlight Streaming** - Ultra-Low Latency GPU 스트리밍
- 🖥️ **VNC Desktop** - 전통적인 원격 데스크탑
- 📝 **GEdit** - 텍스트 에디터

---

### 2. Dashboard (관리자 콘솔)
```
http://110.15.177.120/dashboard/
```

**주요 기능**:
- Cluster Management
- Real-time Monitoring
- Job Management
- VNC Sessions
- **Moonlight Streaming** (사이드바 → Operations 메뉴)
- Prometheus Metrics
- Health Check

**사이드바 메뉴**:
```
Overview
├── Custom Dashboard
└── Cluster Management

Operations
├── Job Management
├── Job Templates
├── Apptainer Images
├── Node Management (admin only)
├── VNC Sessions (admin only)
├── 🎮 Moonlight Streaming  ← 새로 추가!
└── SSH Sessions (admin only)

Monitoring
├── Real-time Monitoring
├── Prometheus Metrics
├── Health Check
└── Reports

Data
├── Data Management
└── File Upload
```

---

### 3. Moonlight Streaming (전용 페이지)
```
http://110.15.177.120/moonlight/
```

**기능**:
- GPU 가속 스트리밍 세션 생성
- 데스크탑 환경 선택 (Ubuntu, KDE Plasma, XFCE)
- 실시간 세션 관리
- Moonlight 클라이언트 연결

---

### 4. CAE Web (시뮬레이션)
```
http://110.15.177.120/cae/
```

**주요 기능**:
- LS-DYNA 시뮬레이션
- 3D 메쉬 뷰어
- Drop Weight Impact Generator
- Automated Modeller

---

## 🔧 Backend API (개발자용)

### API 엔드포인트

| 서비스 | URL | 포트 |
|--------|-----|------|
| Dashboard API | `http://110.15.177.120/api/` | 5010 (프록시) |
| CAE API | `http://110.15.177.120/api/` | 5000 (프록시) |
| Moonlight API | `http://110.15.177.120/api/moonlight/` | 8004 (프록시) |
| Auth Portal | `http://110.15.177.120/auth/` | 4430 (프록시) |

### 성능 최적화 API (신규)

```bash
# 캐시 통계 조회
curl http://110.15.177.120/api/cache/stats | jq

# 캐시 무효화 (admin only)
curl -X POST http://110.15.177.120/api/cache/invalidate/slurm

# 캐시 전체 삭제 (admin only)
curl -X POST http://110.15.177.120/api/cache/clear
```

---

## 📊 모니터링 대시보드

### Prometheus
```
http://110.15.177.120:9090
```

**메트릭**:
- CPU/Memory 사용률
- Nginx 요청 수
- Backend 응답 시간

### Node Exporter
```
http://110.15.177.120:9100/metrics
```

---

## 🧪 테스트 시나리오

### Scenario 1: 랜딩 페이지에서 Moonlight 접속

1. **랜딩 페이지 접속**:
   ```
   http://110.15.177.120/app/
   ```

2. **Moonlight 카드 클릭**:
   - 🎮 아이콘의 "Moonlight" 카드 클릭
   - → `/moonlight/` 페이지로 이동

3. **세션 생성**:
   - Desktop Environment 선택 (Ubuntu Desktop 추천)
   - "Create Session" 버튼 클릭
   - Slurm 작업 제출됨

4. **세션 연결**:
   - 세션 상태가 "Running"이 되면
   - "Connect" 버튼 클릭
   - Moonlight 클라이언트로 연결

---

### Scenario 2: Dashboard에서 Moonlight 관리

1. **Dashboard 접속**:
   ```
   http://110.15.177.120/dashboard/
   ```

2. **로그인** (필요 시):
   - Username/Password 입력
   - JWT 토큰 발급

3. **사이드바 메뉴**:
   - Operations → "Moonlight Streaming" 클릭
   - iframe으로 Moonlight 페이지 임베딩됨

4. **새 창으로 열기**:
   - 우측 상단 "Open in New Tab" 버튼 클릭
   - 전체 화면으로 Moonlight 사용

---

### Scenario 3: 성능 최적화 검증

#### 3.1 Frontend 빌드 검증

```bash
# 브라우저 DevTools > Network
# 1. Dashboard 접속
http://110.15.177.120/dashboard/

# 2. Vendor chunks 확인
# vendor-react-[hash].js
# vendor-chart-[hash].js
# vendor-3d-[hash].js
# vendor-utils-[hash].js
# vendor-terminal-[hash].js

# 3. 캐시 헤더 확인
Cache-Control: public, immutable; max-age=31536000
Content-Encoding: gzip
```

#### 3.2 API 캐싱 검증

```bash
# 첫 요청 (MISS)
time curl -s http://110.15.177.120/api/nodes > /dev/null
# real: 0.2s

# 두 번째 요청 (HIT) - 5초 이내
time curl -s http://110.15.177.120/api/nodes > /dev/null
# real: 0.01s (20배 빠름!)

# 캐시 통계
curl http://110.15.177.120/api/cache/stats | jq
```

#### 3.3 Nginx Gzip 검증

```bash
# Gzip 압축 확인
curl -I -H "Accept-Encoding: gzip" http://110.15.177.120/dashboard/assets/index.js

# 확인 항목:
# Content-Encoding: gzip
# Content-Type: application/javascript
# Cache-Control: public, immutable
```

---

## 🔍 문제 해결

### 문제 1: "Connection refused" 또는 접속 안 됨

**확인 사항**:
```bash
# Nginx 상태
sudo systemctl status nginx

# Backend 상태
pgrep -f "gunicorn.*dashboard_backend_5010"

# 포트 확인
sudo netstat -tlnp | grep -E "80|5010|8004"
```

**해결**:
```bash
# Nginx 재시작
sudo systemctl restart nginx

# Backend 재시작
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./start_production.sh
```

---

### 문제 2: Moonlight 페이지가 404

**확인**:
```bash
# Frontend 빌드 여부
ls -la /var/www/html/moonlight/

# Nginx 설정
sudo nginx -T | grep "location /moonlight"
```

**해결**:
```bash
# Frontend 빌드
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./build_all_frontends.sh

# Nginx 재시작
sudo systemctl reload nginx
```

---

### 문제 3: Dashboard 사이드바에 Moonlight 메뉴 안 보임

**원인**: Frontend 빌드 안 됨 또는 권한 없음

**확인**:
```bash
# Dashboard 빌드 여부
ls -la /var/www/html/dashboard/assets/

# TypeScript 컴파일 에러 확인
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010
npm run build
```

**해결**:
- Dashboard Frontend 재빌드
- 브라우저 캐시 삭제 (Ctrl+Shift+R)

---

### 문제 3-1: React Router 경고 (2025-12-06 해결됨)

**증상**: 브라우저 콘솔에 "No routes matched location '/moonlight/'" 경고

**원인**:
- react-router-dom 패키지가 설치되어 있지만 코드에서 사용하지 않음
- Vite 빌드 시 번들에 포함되어 경고 발생

**해결됨**:
✅ react-router-dom 제거
✅ TypeScript 엄격 모드 호환 수정
✅ MUI v7 Grid API 변경 대응
✅ Vite esbuild minify로 변경

**상세 내용**: `MOONLIGHT_FRONTEND_FIX.md` 참고

---

### 문제 4: 캐시 API가 동작 안 함

**확인**:
```bash
# Redis 실행 여부
redis-cli ping

# Backend 로그 확인
tail -f /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010/logs/gunicorn.log
```

**해결**:
```bash
# Redis 시작
sudo systemctl start redis

# Backend 재시작 (환경 변수 포함)
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010
export CACHE_ENABLED=true
export REDIS_HOST=localhost
export REDIS_PORT=6379
pkill -f gunicorn
nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
```

---

## 📱 모바일 접속

모바일 브라우저에서도 동일한 URL로 접속 가능:
```
http://110.15.177.120/app/
```

**반응형 디자인**:
- Dashboard: ✅ 모바일 최적화
- Moonlight: ✅ 터치 지원
- CAE: ⚠️ 데스크탑 권장 (3D 뷰어)

---

## 🎯 추천 테스트 순서

1. **랜딩 페이지** → `http://110.15.177.120/app/`
2. **Moonlight 카드 클릭** → Moonlight 전용 페이지
3. **Dashboard 접속** → `http://110.15.177.120/dashboard/`
4. **사이드바 → Moonlight Streaming** → iframe 임베딩 확인
5. **성능 테스트** → DevTools Network 탭으로 캐싱 확인
6. **API 테스트** → `curl http://110.15.177.120/api/cache/stats`

---

## 📞 지원

문제 발생 시:
1. 로그 확인: `tail -f dashboard/backend_5010/logs/gunicorn.log`
2. Nginx 로그: `sudo tail -f /var/log/nginx/error.log`
3. 재시작: `cd dashboard && ./start_production.sh`

**Happy Testing! 🚀**
