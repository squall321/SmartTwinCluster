# app_5174 시스템 통합 가이드

**작성일**: 2025-10-26
**버전**: 1.0.0
**대상**: App Framework (app_5174) 시스템 셋업 및 운영

---

## 📋 개요

app_5174(App Framework)를 다른 프론트엔드 서비스(Dashboard 3010, VNC 8002, CAE 5173)와 동일한 방식으로 Nginx 통합 및 자동 빌드 시스템에 완전히 통합한 가이드입니다.

---

## ✅ 통합 완료 항목

### 1. **Nginx 심볼릭 링크 설정**
- 소스 파일: `dashboard/nginx/hpc-portal.conf` 편집만으로 Nginx 설정 변경
- 자동 연결: `/etc/nginx/sites-available/` → `/etc/nginx/sites-enabled/`

### 2. **자동 빌드 시스템**
- `build_all_frontends.sh`에 app_5174 포함 (4/4)
- `start_complete.sh` 실행 시 자동 빌드

### 3. **포트 정리**
- Production 모드 시작 시 5174 dev 서버 자동 종료

### 4. **Nginx 라우팅**
- `/app/` 경로로 접속 → `app_5174/dist/` 서빙

---

## 🚀 최초 셋업 (한 번만 실행)

### 1. Nginx 심볼릭 링크 설정

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./setup_nginx_symlink.sh
```

**실행 결과:**
```
소스: dashboard/nginx/hpc-portal.conf
  ↓ (symlink)
/etc/nginx/sites-available/hpc-portal.conf
  ↓ (symlink)
/etc/nginx/sites-enabled/hpc-portal.conf
```

**기능:**
- 기존 일반 파일이 있으면 자동 백업 후 심볼릭 링크로 변경
- Nginx 설정 문법 자동 검사
- 선택적 Nginx 재시작

### 2. 프론트엔드 빌드 (선택 사항)

```bash
./build_all_frontends.sh
```

**빌드 대상:**
1. Dashboard Frontend (3010)
2. VNC Service (8002)
3. CAE Frontend (5173)
4. **App Framework (5174)** ⭐

**출력:**
- `frontend_3010/dist/`
- `vnc_service_8002/dist/`
- `kooCAEWeb_5173/dist/`
- `app_5174/dist/` ⭐

---

## 🎯 운영 모드별 사용법

### **개발 모드 (Dev Mode)**

app_5174만 개발할 때:

```bash
cd app_5174
./dev.sh
# 또는
npm run dev
```

**특징:**
- 포트 **5174**에서 Vite dev 서버 실행
- Hot Module Replacement (HMR) 지원
- 접속: `http://localhost:5174`

**주의:**
- Nginx를 통하지 않고 직접 접속
- 다른 서비스(5000, 5010 등)는 별도 실행 필요

---

### **프로덕션 모드 (Production Mode)**

전체 시스템 운영:

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./start_complete.sh
```

**자동 수행 작업:**

#### [0/8] 프론트엔드 빌드
```
./build_all_frontends.sh 호출
  ↓
[1/4] Dashboard (3010) 빌드
[2/4] VNC Service (8002) 빌드
[3/4] CAE Frontend (5173) 빌드
[4/4] App Framework (5174) 빌드 ⭐
  - npm install (필요 시)
  - npx vite build
  - landing.html → dist/index.html 복사
```

#### [1/8] 기존 서비스 종료
```
Dev 서버 포트 종료:
  - 3010 (Dashboard)
  - 8002 (VNC)
  - 5173 (CAE)
  - 5174 (App) ⭐ 추가됨!

백엔드 서비스 종료:
  - 5000, 5001, 5010, 5011 등
```

#### [2/8~8/8] 서비스 시작
- Redis 확인
- SAML IdP 시작
- Auth Backend/Frontend 시작
- Dashboard Backend + WebSocket 시작
- CAE Backend 시작
- Prometheus + Node Exporter 시작

**최종 접속:**
- Auth Portal: `http://110.15.177.120/`
- Dashboard: `http://110.15.177.120/dashboard/`
- VNC Service: `http://110.15.177.120/vnc/`
- **App Framework: `http://110.15.177.120/app/`** ⭐
- CAE Frontend: `http://110.15.177.120/cae/`

---

## 🔧 파일 수정 시 작업 흐름

### 1. Nginx 설정 수정

```bash
# 1. 소스 파일 편집
vi dashboard/nginx/hpc-portal.conf

# 2. 문법 검사
sudo nginx -t

# 3. 적용
sudo systemctl reload nginx
```

**장점:**
- `/etc/nginx/` 직접 수정 불필요
- Git으로 버전 관리 가능
- 자동으로 sites-available, sites-enabled에 반영

---

### 2. app_5174 프론트엔드 코드 수정

#### 개발 중
```bash
cd app_5174
npm run dev  # 5174 포트에서 개발
# → 코드 수정 시 HMR로 즉시 반영
# → http://localhost:5174 접속
```

#### Production 배포
```bash
cd dashboard

# 방법 1: 빌드만
./build_all_frontends.sh
sudo systemctl reload nginx

# 방법 2: 전체 재시작 (빌드 포함)
./start_complete.sh
```

**참고:** Static 파일이므로 Nginx reload만으로 충분

---

### 3. 백엔드 코드 수정

app_5174는 백엔드로 **kooCAEWebServer_5000**을 사용합니다.

```bash
cd dashboard

# 백엔드만 재시작
cd kooCAEWebServer_5000
./stop.sh
./start.sh

# 또는 전체 재시작
cd ..
./stop_complete.sh
./start_complete.sh
```

---

## 📁 주요 파일 및 디렉토리

### Nginx 설정
| 파일 | 용도 |
|------|------|
| `dashboard/nginx/hpc-portal.conf` | **편집용 소스 파일** (Git 관리) |
| `/etc/nginx/sites-available/hpc-portal.conf` | 심볼릭 링크 → 소스 |
| `/etc/nginx/sites-enabled/hpc-portal.conf` | 심볼릭 링크 → sites-available |

### app_5174 구조
| 경로 | 설명 |
|------|------|
| `app_5174/src/` | 소스 코드 |
| `app_5174/dist/` | 빌드 출력 (Nginx 서빙) |
| `app_5174/package.json` | npm 설정 |
| `app_5174/vite.config.ts` | Vite 설정 (base: '/app/') |
| `app_5174/landing.html` | 랜딩 페이지 |
| `app_5174/dev.sh` | 개발 서버 시작 스크립트 |
| `app_5174/start.sh` | Production 시작 스크립트 |

### 통합 스크립트
| 스크립트 | 기능 |
|----------|------|
| `dashboard/setup_nginx_symlink.sh` | Nginx 심볼릭 링크 설정 |
| `dashboard/build_all_frontends.sh` | 4개 프론트엔드 빌드 |
| `dashboard/start_complete.sh` | Production 전체 시작 |
| `dashboard/stop_complete.sh` | 전체 서비스 종료 |

---

## 🔍 문제 해결

### 1. `/app/` 접속이 안 됨

**확인 사항:**
```bash
# 1. 빌드 파일 존재 확인
ls -la app_5174/dist/

# 2. Nginx 설정 확인
grep -A 5 "location /app" dashboard/nginx/hpc-portal.conf

# 3. Nginx 문법 검사
sudo nginx -t

# 4. Nginx 로그 확인
sudo tail -f /var/log/nginx/error.log
```

**해결 방법:**
```bash
# 빌드 파일 없으면
cd dashboard
./build_all_frontends.sh

# Nginx 설정 문제면
sudo systemctl reload nginx
```

---

### 2. dev 서버(5174)가 종료되지 않음

**확인:**
```bash
lsof -ti:5174
ps aux | grep 5174
```

**수동 종료:**
```bash
# 방법 1: fuser
fuser -k 5174/tcp

# 방법 2: kill
lsof -ti:5174 | xargs kill -9

# 방법 3: pkill
pkill -9 -f "vite.*5174"
```

**원인:** start_complete.sh가 최신 버전이 아닐 수 있음

---

### 3. Nginx 심볼릭 링크가 꼬임

**증상:**
```
nginx: [emerg] duplicate upstream ...
```

**해결:**
```bash
# 백업 파일 제거
sudo rm /etc/nginx/sites-enabled/*.backup_*

# 심볼릭 링크 재생성
cd dashboard
./setup_nginx_symlink.sh

# Nginx 테스트
sudo nginx -t
```

---

### 4. 빌드 실패

**로그 확인:**
```bash
tail -50 /tmp/app_build.log
```

**일반적인 원인:**
1. **node_modules 없음**
   ```bash
   cd app_5174
   npm install
   ```

2. **타입 에러**
   ```bash
   # build_all_frontends.sh는 타입 체크 스킵하므로 문제 없음
   # 직접 빌드 시
   npx vite build
   ```

3. **디스크 공간 부족**
   ```bash
   df -h
   ```

---

## 📊 시스템 상태 확인

### Nginx 상태
```bash
# 서비스 상태
sudo systemctl status nginx

# 설정 테스트
sudo nginx -t

# 심볼릭 링크 체인 확인
ls -la /etc/nginx/sites-enabled/hpc-portal.conf
readlink -f /etc/nginx/sites-enabled/hpc-portal.conf
```

### app_5174 상태
```bash
# 빌드 파일 확인
ls -lh app_5174/dist/

# 프로세스 확인
ps aux | grep 5174

# 포트 확인
lsof -i:5174
```

### 전체 프론트엔드 빌드 상태
```bash
ls -ld */dist/ 2>/dev/null
```

**결과 예시:**
```
drwxr-xr-x 6 koopark koopark 4096 10월 25 22:32 app_5174/dist/
drwxr-xr-x 4 koopark koopark 4096 10월 25 14:25 frontend_3010/dist/
drwxr-xr-x 3 koopark koopark 4096 10월 25 14:25 kooCAEWeb_5173/dist/
drwxr-xr-x 3 koopark koopark 4096 10월 25 14:25 vnc_service_8002/dist/
```

---

## 🎯 체크리스트

### 최초 셋업 시
- [ ] `./setup_nginx_symlink.sh` 실행
- [ ] `./build_all_frontends.sh` 실행 (또는 start_complete.sh)
- [ ] `http://110.15.177.120/app/` 접속 확인

### 코드 수정 후
- [ ] 개발: `npm run dev` (5174)
- [ ] 테스트: `http://localhost:5174` 접속
- [ ] 빌드: `./build_all_frontends.sh`
- [ ] 배포: `sudo systemctl reload nginx`
- [ ] 확인: `http://110.15.177.120/app/` 접속

### Nginx 설정 수정 후
- [ ] `vi dashboard/nginx/hpc-portal.conf` 편집
- [ ] `sudo nginx -t` 문법 검사
- [ ] `sudo systemctl reload nginx` 적용
- [ ] 브라우저에서 확인

---

## 📚 관련 문서

- [전체 시스템 구조](./README.md)
- [Nginx 라우팅 설정](./ROUTING_CONFIG.md)
- [app_5174 README](./app_5174/README.md)
- [app_5174 아키텍처](./app_5174/docs/ARCHITECTURE.md)
- [Phase별 개발 문서](./app_5174/PHASE*.md)

---

## 🔄 업데이트 이력

### 2025-10-26 (v1.0.0)
- ✅ Nginx 심볼릭 링크 자동 설정 스크립트 추가
- ✅ build_all_frontends.sh에 app_5174 포함 확인
- ✅ start_complete.sh에 5174 포트 정리 추가
- ✅ 소스 nginx 설정 파일 동기화 완료

---

## 💡 팁

### 개발 효율화
```bash
# 개발 중 자주 쓰는 명령어를 alias로
alias app-dev='cd app_5174 && npm run dev'
alias app-build='cd dashboard && ./build_all_frontends.sh'
alias app-restart='cd dashboard && ./start_complete.sh'
```

### Git 관리
```bash
# Nginx 설정 변경 시 커밋
git add dashboard/nginx/hpc-portal.conf
git commit -m "Update nginx config for app_5174"

# /etc/nginx/는 Git 관리 대상 아님 (심볼릭 링크로 자동 연결)
```

### 빠른 디버깅
```bash
# 개발 서버 로그
cd app_5174
npm run dev 2>&1 | tee dev.log

# 빌드 로그
cat /tmp/app_build.log

# Nginx 에러 로그
sudo tail -f /var/log/nginx/error.log
```

---

**작성자**: Claude AI Assistant
**최종 수정**: 2025-10-26
**문의**: HPC 시스템 관리자
