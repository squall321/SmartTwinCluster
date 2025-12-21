# Auth Portal Dev 서버 사용 분석

> **작성일**: 2025-12-20
> **목적**: auth_portal_4431이 프로덕션 환경에서 dev 서버를 사용하는 이유 분석 및 해결 방안

---

## 📋 현재 상황

### 1. Auth Portal 배포 방식

**위치**: `dashboard/auth_portal_4431/`

```bash
# dashboard/start_production.sh:150-165

# ==================== 5. Auth Frontend (Dev 서버 - UI 개발용) ====================
echo -e "${BLUE}[5/9] Auth Frontend 시작 중...${NC}"
if pgrep -f "vite.*auth_portal_4431" > /dev/null; then
    echo -e "${YELLOW}  → Auth Frontend 재시작 중...${NC}"
    pkill -f "vite.*auth_portal_4431"
    sleep 1
fi

cd auth_portal_4431
mkdir -p logs
nohup npm run dev > logs/frontend.log 2>&1 &  # ⚠️ Vite dev 서버!
FRONTEND_PID=$!
echo $FRONTEND_PID > logs/frontend.pid
cd "$SCRIPT_DIR"
sleep 5
echo -e "${GREEN}✅ Auth Frontend 시작됨 (PID: $FRONTEND_PID, Port: 4431)${NC}"
```

**특징**:
- ✅ `npm run dev` (Vite 개발 서버)
- ✅ Port: 4431
- ✅ HMR (Hot Module Replacement) 활성화
- ❌ 빌드된 정적 파일 아님

---

### 2. Nginx 라우팅 설정

**위치**: `dashboard/nginx/hpc-portal.conf`

```nginx
# Line 10-11: Upstream 정의
upstream auth_frontend {
    server 127.0.0.1:4431;  # Vite dev 서버로 프록시
}

# Line 57-67: Root location (메인 진입점)
location / {
    proxy_pass http://auth_frontend/;  # Dev 서버로 프록시
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_bypass $http_upgrade;
}
```

**문제점**:
- ⚠️ **프로덕션 환경에서 dev 서버 사용**
- ⚠️ **Nginx가 Vite dev 서버로 프록시** (정적 파일 서빙 아님)

---

### 3. 빌드 스크립트 현황

#### build_all_frontends.sh (dashboard/build_all_frontends.sh)

**빌드 대상** (5개):
1. frontend_3010 (Dashboard) ✅
2. vnc_service_8002 (VNC) ✅
3. moonlight_frontend_8003 (Moonlight) ✅
4. kooCAEWeb_5173 (CAE) ✅
5. app_5174 (App Service) ✅

**auth_portal_4431**: ❌ **빌드 목록에 없음**

---

#### package.json 확인

**위치**: `dashboard/auth_portal_4431/package.json`

```json
{
  "name": "auth_portal_4431",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",  // ✅ 빌드 스크립트 존재!
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^19.1.1",
    "react-dom": "^19.1.1",
    "react-router-dom": "^7.9.4"
  }
}
```

**결론**: 빌드 가능하지만, **build_all_frontends.sh에 포함되지 않음**

---

## 🔍 왜 Dev 서버를 사용하는가?

### 가능한 이유

#### 1. **개발/테스트 편의성** (추정)
- Auth Portal은 인증 시스템으로, 자주 수정/테스트되는 컴포넌트
- HMR(Hot Module Replacement)로 코드 변경 시 즉시 반영
- 빌드 과정 생략으로 빠른 개발 사이클

#### 2. **의도적 분리** (추정)
- Auth Portal은 사용자 로그인 화면으로, 다른 서비스와 독립적
- Dev 서버로 실행하여 다른 프론트엔드와 분리된 개발 환경 유지

#### 3. **설정 누락** (가능성 높음)
- 초기 개발 시 dev 서버로 테스트하다가 프로덕션 전환을 깜빡함
- build_all_frontends.sh 작성 시 auth_portal_4431을 실수로 제외

---

## ⚠️ Dev 서버 사용의 문제점

### 1. **성능 문제**

| 항목 | Dev 서버 (Vite) | 프로덕션 빌드 (Nginx) |
|------|-----------------|----------------------|
| **응답 속도** | 느림 (실시간 번들링) | 빠름 (정적 파일) |
| **메모리 사용** | 높음 (Node.js 프로세스) | 낮음 (Nginx만) |
| **CPU 사용** | 높음 (HMR, 번들링) | 거의 없음 |
| **동시 접속** | 제한적 (Node.js 단일 스레드) | 매우 높음 (Nginx) |

**영향**:
- 사용자가 많을 때 로그인 페이지 응답 지연
- 서버 리소스 낭비 (Node.js 프로세스 유지)

---

### 2. **보안 문제**

| 항목 | Dev 서버 | 프로덕션 빌드 |
|------|---------|--------------|
| **소스맵 노출** | ⚠️ 가능 | ✅ 제거 가능 |
| **개발 도구** | ⚠️ 포함 | ✅ 제거됨 |
| **에러 상세 정보** | ⚠️ 노출 | ✅ 최소화 |
| **코드 난독화** | ❌ 없음 | ✅ Terser 적용 |

**영향**:
- 소스 코드 구조 노출
- 내부 API 엔드포인트 노출 가능

---

### 3. **안정성 문제**

| 문제 | 설명 |
|------|------|
| **프로세스 크래시** | Vite dev 서버는 프로덕션 용도가 아님, 예상치 못한 크래시 가능 |
| **HMR 오버헤드** | 파일 감시 시스템이 계속 실행되어 리소스 소모 |
| **재시작 필요** | 코드 변경 없어도 가끔 재시작 필요 |

---

### 4. **배포 일관성 문제**

| 서비스 | 배포 방식 | 문제점 |
|--------|----------|--------|
| **frontend_3010** | 빌드 → Nginx | ✅ 일관성 |
| **vnc_service_8002** | 빌드 → Nginx | ✅ 일관성 |
| **moonlight_frontend_8003** | 빌드 → Nginx | ✅ 일관성 |
| **kooCAEWeb_5173** | 빌드 → Nginx | ✅ 일관성 |
| **app_5174** | 빌드 → Nginx | ✅ 일관성 |
| **auth_portal_4431** | Dev 서버 | ❌ **불일치** |

**문제**:
- 6개 프론트엔드 중 1개만 다른 방식으로 배포
- 유지보수 혼란 (왜 auth만 다른지?)

---

## ✅ 해결 방안

### 방안 1: 프로덕션 빌드로 전환 (권장)

#### 장점
- ✅ 성능 향상 (Nginx 정적 파일 서빙)
- ✅ 보안 강화 (소스맵 제거, 코드 난독화)
- ✅ 배포 일관성 (모든 프론트엔드 동일 방식)
- ✅ 리소스 절약 (Node.js 프로세스 불필요)

#### 단점
- ⚠️ 코드 변경 시 빌드 필요 (1-2분)
- ⚠️ HMR 불가 (개발 중에는 별도 dev 서버 실행)

#### 구현 방법

**1. build_all_frontends.sh에 auth_portal_4431 추가**

```bash
# dashboard/build_all_frontends.sh

# ==================== Auth Portal (추가) ====================
echo -e "${BLUE}[0/5] Auth Portal 빌드 중...${NC}"
if [ -d "auth_portal_4431" ]; then
    cd auth_portal_4431

    # TypeScript 캐시 삭제
    if [ -f "tsconfig.tsbuildinfo" ]; then
        echo "  → TypeScript 캐시 삭제 중..."
        rm -f tsconfig.tsbuildinfo 2>/dev/null || true
    fi

    # dist 폴더 권한 문제 해결
    if [ -d "dist" ]; then
        echo "  → 기존 dist 폴더 삭제 중..."
        rm -rf dist 2>/dev/null || sudo rm -rf dist 2>/dev/null || true
    fi

    # node_modules 확인 (하드카피 전제)
    if [ ! -d "node_modules" ]; then
        echo -e "${RED}❌ node_modules not found${NC}"
        echo "   Please copy node_modules via rsync/tar before building"
        exit 1
    fi

    # 빌드 실행
    echo "  → 빌드 실행 중..."
    sudo rm -f /tmp/auth_portal_build.log 2>/dev/null || true
    if npm run build > /tmp/auth_portal_build.log 2>&1; then
        echo -e "${GREEN}✅ Auth Portal 빌드 성공${NC}"
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # Nginx 배포 디렉토리로 복사
        echo "  → Nginx 배포 디렉토리로 복사 중..."
        sudo rm -rf /var/www/html/auth_portal 2>/dev/null || true
        sudo mkdir -p /var/www/html/auth_portal
        sudo cp -r dist/* /var/www/html/auth_portal/
        sudo chown -R www-data:www-data /var/www/html/auth_portal
        echo -e "${GREEN}  ✅ 배포 완료: /var/www/html/auth_portal${NC}"
    else
        echo -e "${RED}❌ Auth Portal 빌드 실패${NC}"
        echo "  → 로그: /tmp/auth_portal_build.log"
        tail -20 /tmp/auth_portal_build.log
        BUILD_FAILED=$((BUILD_FAILED + 1))
    fi

    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}⚠  auth_portal_4431 디렉토리 없음${NC}"
fi
echo ""
```

**2. Nginx 설정 변경**

```nginx
# dashboard/nginx/hpc-portal.conf

# 기존: Dev 서버로 프록시
# upstream auth_frontend {
#     server 127.0.0.1:4431;
# }
# location / {
#     proxy_pass http://auth_frontend/;
#     ...
# }

# 변경: 정적 파일 서빙
location / {
    root /var/www/html/auth_portal;
    try_files $uri $uri/ /index.html;

    # Cache control
    add_header Cache-Control "public, max-age=3600";

    # Security headers
    add_header X-Content-Type-Options "nosniff";
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
}
```

**3. start_production.sh 수정**

```bash
# dashboard/start_production.sh

# 기존: Dev 서버 시작 (제거)
# # ==================== 5. Auth Frontend (Dev 서버 - UI 개발용) ====================
# echo -e "${BLUE}[5/9] Auth Frontend 시작 중...${NC}"
# if pgrep -f "vite.*auth_portal_4431" > /dev/null; then
#     echo -e "${YELLOW}  → Auth Frontend 재시작 중...${NC}"
#     pkill -f "vite.*auth_portal_4431"
#     sleep 1
# fi
#
# cd auth_portal_4431
# mkdir -p logs
# nohup npm run dev > logs/frontend.log 2>&1 &
# FRONTEND_PID=$!
# echo $FRONTEND_PID > logs/frontend.pid
# cd "$SCRIPT_DIR"
# sleep 5
# echo -e "${GREEN}✅ Auth Frontend 시작됨 (PID: $FRONTEND_PID, Port: 4431)${NC}"
# echo ""

# 변경: 아무것도 하지 않음 (Nginx가 정적 파일 서빙)
echo -e "${BLUE}[5/9] Auth Frontend (정적 파일 - Nginx)${NC}"
echo -e "${GREEN}✅ Auth Frontend는 Nginx에서 서빙됨 (/var/www/html/auth_portal)${NC}"
echo ""
```

---

### 방안 2: Dev 서버 유지 (비권장)

#### 조건
Auth Portal을 **자주 수정**하는 경우에만 고려

#### 개선 사항
Dev 서버를 유지하더라도 다음 개선 필요:

1. **PM2로 프로세스 관리**
   ```bash
   # Vite dev 서버를 PM2로 관리하여 자동 재시작
   pm2 start "npm run dev" --name auth_portal
   ```

2. **Nginx 캐싱 추가**
   ```nginx
   location / {
       proxy_pass http://auth_frontend/;
       proxy_cache my_cache;
       proxy_cache_valid 200 1m;
   }
   ```

3. **빌드 스크립트에 경고 추가**
   ```bash
   # build_all_frontends.sh
   echo "⚠️  Warning: auth_portal_4431 uses dev server (not included in build)"
   ```

**단점**:
- 여전히 성능/보안/안정성 문제 존재

---

## 📊 비교 분석

| 항목 | Dev 서버 (현재) | 프로덕션 빌드 (권장) |
|------|----------------|---------------------|
| **성능** | ⚠️ 느림 (실시간 번들링) | ✅ 빠름 (정적 파일) |
| **보안** | ⚠️ 소스 노출 가능 | ✅ 난독화/최소화 |
| **안정성** | ⚠️ 크래시 가능 | ✅ 안정적 |
| **메모리** | ⚠️ Node.js 프로세스 | ✅ Nginx만 |
| **배포 일관성** | ❌ 다른 방식 | ✅ 모든 FE 동일 |
| **개발 편의성** | ✅ HMR 즉시 반영 | ⚠️ 빌드 필요 (1-2분) |
| **코드 변경 반영** | ✅ 즉시 | ⚠️ 빌드 후 |

---

## 🎯 권장 사항

### 즉시 적용: 프로덕션 빌드로 전환

**이유**:
1. **성능**: 로그인 페이지는 모든 사용자가 최초 접근하는 페이지
   - Dev 서버의 느린 응답은 첫인상에 부정적 영향
   - 정적 파일 서빙으로 응답 속도 10배 이상 향상 예상

2. **보안**: 인증 시스템의 소스 코드 노출은 보안 위험
   - 로그인 로직, API 엔드포인트 노출 가능
   - 난독화로 리버스 엔지니어링 난이도 증가

3. **안정성**: 프로덕션 환경에서 dev 도구 사용은 부적절
   - Vite dev 서버는 개발 목적으로만 설계됨
   - 예상치 못한 크래시 위험

4. **일관성**: 모든 프론트엔드를 동일 방식으로 배포
   - 유지보수 편의성
   - 문서화 간소화

---

### 개발 워크플로우

**프로덕션 빌드 전환 후 개발 방법**:

```bash
# 1. 로컬 개발 (HMR 사용)
cd dashboard/auth_portal_4431
npm run dev
# → http://localhost:5173 에서 개발

# 2. 변경사항 커밋 후 빌드
cd dashboard
./build_all_frontends.sh --frontend auth_portal_4431

# 3. 서비스 재시작 (빌드만)
./start_production.sh --rebuild
# 또는 선택적 빌드 후
./start_production.sh --skip-build
```

**장점**:
- 개발 중에는 로컬에서 HMR 사용 (편리함 유지)
- 배포 시에만 빌드 (프로덕션 품질 보장)

---

## 📝 구현 체크리스트

- [ ] build_all_frontends.sh에 auth_portal_4431 추가
- [ ] Nginx 설정 변경 (프록시 → 정적 파일)
- [ ] start_production.sh 수정 (dev 서버 시작 제거)
- [ ] 빌드 테스트
  ```bash
  cd dashboard
  ./build_all_frontends.sh
  ls -la /var/www/html/auth_portal/
  ```
- [ ] Nginx 설정 테스트
  ```bash
  sudo nginx -t
  sudo systemctl reload nginx
  ```
- [ ] 브라우저 접속 테스트
  ```bash
  curl -I http://110.15.177.120/
  # → 200 OK, auth portal 정적 파일 응답 확인
  ```
- [ ] 로그인 기능 테스트
- [ ] 문서 업데이트 (DEVELOPMENT_WORKFLOW.md)

---

**문서 끝**
