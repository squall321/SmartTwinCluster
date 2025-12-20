# Setup vs Start 스크립트 분리 및 오프라인 환경 검증 분석

> **작성일**: 2025-12-20
> **목적**: Setup/Start 스크립트 역할 분담 분석 및 오프라인 환경 문제점 도출

---

## 📋 목차

1. [실행 개요](#1-실행-개요)
2. [현재 구조 분석](#2-현재-구조-분석)
3. [문제점 분석](#3-문제점-분석)
4. [오프라인 환경 검증](#4-오프라인-환경-검증)
5. [해결 방안](#5-해결-방안)
6. [구현 계획](#6-구현-계획)

---

## 1. 실행 개요

### 1.1 스크립트 실행 흐름

```
[초기 설치]
setup_cluster_full_multihead_offline.sh
  └─> cluster/start_multihead.sh
        ├─> phase0: infrastructure
        ├─> phase1: storage (GlusterFS)
        ├─> phase2: database (MariaDB Galera)
        ├─> phase3: redis
        ├─> phase4: slurm
        ├─> phase5: web (phase5_web.sh)
        │     └─> build_all_frontends() 함수 ⚠️
        ├─> phase6: backup
        ├─> phase7: (미사용)
        ├─> phase8: containers (SIF 배포)
        └─> phase9: software (MPI, Apptainer)

[서비스 시작]
start.sh
  └─> dashboard/start_production.sh
        ├─> build_all_frontends.sh ⚠️
        ├─> SAML-IdP 시작
        ├─> Auth Backend (Gunicorn + venv)
        ├─> Auth Frontend (npm run dev)
        ├─> Dashboard Backend (Gunicorn + venv)
        ├─> WebSocket (Python + venv)
        ├─> CAE Backend (Gunicorn + venv)
        ├─> CAE Automation (Gunicorn + venv)
        ├─> Moonlight Backend (Gunicorn + venv)
        └─> Nginx 재시작
```

---

## 2. 현재 구조 분석

### 2.1 Setup 스크립트 (cluster/setup/phase5_web.sh)

**위치**: `cluster/setup/phase5_web.sh`
**실행 시점**: 초기 설치 시 1회

#### 주요 기능

1. **시스템 의존성 설치**
   ```bash
   # Line 173-174
   npm install -g typescript ts-node pnpm terser vite
   ```

2. **프론트엔드 빌드** (lines 1370-1491)
   ```bash
   build_all_frontends() {
       frontends=(
           "frontend_3010"       # Dashboard
           "auth_portal_4431"    # Auth Portal
           "kooCAEWeb_5173"      # CAE
           "app_5174"            # App Service
           "vnc_service_8002"    # VNC
       )

       for frontend in "${frontends[@]}"; do
           npm install  # ⚠️ 온라인 다운로드!
           npm run build
           cp -r dist/* /var/www/html/$frontend/
       done
   }
   ```

3. **venv 사용** (lines 706-712)
   ```bash
   # venv가 이미 존재한다고 가정
   cd "$service_dir"
   source venv/bin/activate
   pip install redis python-dotenv  # ⚠️ 온라인 다운로드!
   deactivate
   ```

**문제점**:
- ❌ venv를 생성하지 않고, 이미 존재한다고 가정
- ❌ `npm install` / `pip install`이 온라인 다운로드
- ❌ 빌드 로직이 dashboard/build_all_frontends.sh와 중복 (440줄)

---

### 2.2 Start 스크립트 (dashboard/start_production.sh)

**위치**: `dashboard/start_production.sh`
**실행 시점**: 서비스 시작/재시작 시 매번

#### 주요 기능

1. **프론트엔드 빌드** (lines 22-32)
   ```bash
   # ==================== 0. 프론트엔드 빌드 ====================
   echo -e "${BLUE}[0/9] 프론트엔드 빌드 중...${NC}"
   if [ -f "./build_all_frontends.sh" ]; then
       ./build_all_frontends.sh  # ⚠️ 매번 5-10분 소요!
   ```

2. **백엔드 서비스 시작** (venv 사용)
   ```bash
   # Line 126-127: Auth Backend
   if [ -d "venv" ]; then
       nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
   fi

   # Line 212-213: Dashboard Backend
   if [ -d "venv" ]; then
       MOCK_MODE=false nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &
   fi

   # ... 동일 패턴 반복 (총 5개 백엔드)
   ```

**문제점**:
- ❌ **매번 재시작마다 전체 프론트엔드 빌드** (5-10분 낭비)
- ❌ 백엔드만 수정해도 불필요한 프론트엔드 빌드
- ❌ venv가 존재하지 않으면 `gunicorn` 실행 실패 (fallback 없음)

---

### 2.3 빌드 스크립트 (dashboard/build_all_frontends.sh)

**위치**: `dashboard/build_all_frontends.sh`
**실행 시점**: start_production.sh에서 호출

#### 빌드 대상

```bash
# Line 24-256 (5개 프론트엔드)
1. frontend_3010      (Dashboard)   → /var/www/html/dashboard
2. vnc_service_8002   (VNC)         → /var/www/html/vnc_service_8002
3. moonlight_frontend_8003          → /var/www/html/moonlight
4. kooCAEWeb_5173     (CAE)         → /var/www/html/cae
5. app_5174           (App Service) → /var/www/html/app_5174
```

#### 빌드 프로세스

```bash
for frontend in "${frontends[@]}"; do
    # 1. TypeScript 캐시 삭제
    rm -f tsconfig.tsbuildinfo

    # 2. dist 폴더 삭제
    rm -rf dist

    # 3. node_modules 확인
    if [ ! -d "node_modules" ]; then
        npm install  # ⚠️ 온라인 다운로드!
    fi

    # 4. 빌드
    npm run build

    # 5. Nginx 디렉토리에 배포
    sudo cp -r dist/* /var/www/html/$frontend/
done
```

**문제점**:
- ❌ `npm install`이 node_modules 없을 때마다 온라인 다운로드
- ❌ 선택적 빌드 불가 (전체 or 없음)
- ❌ phase5_web.sh의 build_all_frontends()와 중복

---

### 2.4 프론트엔드 목록 불일치

| 스크립트 | frontend_3010 | auth_portal_4431 | vnc_service_8002 | moonlight_frontend_8003 | kooCAEWeb_5173 | app_5174 |
|---------|---------------|------------------|------------------|-------------------------|----------------|----------|
| **phase5_web.sh** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **build_all_frontends.sh** | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |

**결과**:
- `auth_portal_4431`: setup 시 빌드, start 시 dev 서버 (`npm run dev`)
- `moonlight_frontend_8003`: start 시만 빌드, setup 시 누락

---

## 3. 문제점 분석

### 3.1 코드 중복

#### build_all_frontends() 로직 중복

| 항목 | phase5_web.sh | build_all_frontends.sh |
|------|---------------|------------------------|
| **위치** | cluster/setup/phase5_web.sh:1370-1491 | dashboard/build_all_frontends.sh |
| **라인 수** | 121줄 | 321줄 |
| **빌드 대상** | 5개 (auth 포함, moonlight 제외) | 5개 (moonlight 포함, auth 제외) |
| **npm install** | ✅ 있음 | ✅ 있음 |
| **캐시 삭제** | ❌ 없음 | ✅ 있음 (tsconfig.tsbuildinfo) |
| **dist 삭제** | ❌ 없음 | ✅ 있음 (sudo rm -rf dist) |
| **에러 처리** | 모듈 누락 시 재설치 | 모듈 누락 시 재설치 |

**중복 코드량**: 약 440줄 (유사 로직 포함)

---

### 3.2 venv 환경 불일치

#### venv 생성 위치 확인

```bash
# dashboard/install_all.sh:131
python3 -m venv venv  # ✅ auth_portal_4430/venv 생성
```

**문제**:
1. **install_all.sh는 단일 서비스 설치 스크립트**
   - auth_portal_4430/venv만 생성
   - 다른 백엔드 서비스(backend_5010, kooCAEWebServer_5000 등)는 venv 생성 안 함

2. **phase5_web.sh는 venv 생성하지 않음**
   ```bash
   # Line 706-712
   if [[ ! -d "$service_dir/venv" ]]; then
       log_warning "No venv found for $service, skipping redis installation"
       continue
   fi
   ```
   - venv가 없으면 경고만 출력하고 건너뜀
   - pip install 시도 안 함

3. **start_production.sh는 venv 필수**
   ```bash
   # Line 126-127
   if [ -d "venv" ]; then
       nohup venv/bin/gunicorn -c gunicorn_config.py app:app
   else
       # ❌ else 블록 없음 → gunicorn 실행 안 됨
       nohup gunicorn -c gunicorn_config.py app:app
   fi
   ```

**결과**:
- ❌ venv가 없으면 시스템 Python의 gunicorn 사용 (버전 불일치 가능)
- ❌ 의존성 격리 실패 (Redis, PyJWT 등)

---

#### venv 사용 현황

| 백엔드 서비스 | venv 생성 스크립트 | start_production.sh에서 사용 |
|--------------|-------------------|------------------------------|
| auth_portal_4430 | install_all.sh:131 | ✅ Line 126-127 |
| backend_5010 | ❌ 없음 | ✅ Line 212-213 |
| websocket_5011 | ❌ 없음 | ✅ Line 245-246 |
| kooCAEWebServer_5000 | ❌ 없음 | ✅ Line 326-327 |
| kooCAEAutoBackend_5001 | ❌ 없음 | ✅ Line 399-400 |
| MoonlightSunshine_8004 | ❌ 없음 | ✅ Line 459-460 |

**심각도**: 🔴 **Critical**
**영향**: 서비스 시작 실패 또는 의존성 충돌

---

### 3.3 오프라인 환경 문제

#### 온라인 다운로드가 발생하는 위치

| 스크립트 | 명령어 | 위치 | 문제 |
|---------|--------|------|------|
| **install_all.sh** | `apt update` | Line 66 | ❌ 온라인 저장소 접근 |
| **install_all.sh** | `curl -fsSL https://deb.nodesource.com/setup_20.x` | Line 78 | ❌ Node.js 저장소 다운로드 |
| **install_all.sh** | `apt install -y nodejs` | Line 79 | ❌ 온라인 패키지 다운로드 |
| **install_all.sh** | `pip install --upgrade pip` | Line 138 | ❌ PyPI 접근 |
| **install_all.sh** | `pip install -r requirements.txt` | Line 139 | ❌ PyPI 패키지 다운로드 |
| **install_all.sh** | `npm install` | Line 201 | ❌ npm registry 접근 |
| **phase5_web.sh** | `npm install -g typescript ...` | Line 174 | ❌ 글로벌 패키지 다운로드 |
| **phase5_web.sh** | `pip install redis python-dotenv` | Line 707 | ❌ PyPI 접근 |
| **build_all_frontends.sh** | `npm install` | Line 44, 94, 144, 206, 278 | ❌ 5개 프론트엔드마다 반복 |

**총 온라인 접근 횟수**: 14회 (setup 1회 + start 매번)

---

## 4. 오프라인 환경 검증

> **⚠️ 중요 전제**: venv와 node_modules는 **전체 하드카피**로 배포
> - Python venv는 `dashboard/*/venv/` 디렉토리 전체를 rsync/tar로 복사
> - Node.js node_modules는 `dashboard/*/node_modules/` 디렉토리 전체를 복사
> - 따라서 `pip install`, `npm install`은 **setup 시에도 실행하지 않음**

### 4.1 오프라인 패키지 현황

```bash
$ ls -la offline_packages/

drwxr-xr-x  2 koopark koopark      4096 11월 17 22:28 apt_mirror
drwxr-xr-x  2 root    root        36864 12월 17 21:10 apt_packages
-rw-r--r--  1 root    root    361005220 12월 17 21:10 apt-packages-20251217.tar.gz
drwxr-xr-x  2 koopark koopark      4096 12월 19 03:05 nodejs
-rw-r--r--  1 koopark koopark  26495741 12월 19 03:05 npm_global_bundle.tar.gz
```

#### Node.js 오프라인 패키지

**위치**: `offline_packages/nodejs/`

```bash
$ ls -la offline_packages/nodejs/

-rwx--x--x  1 koopark koopark     8858 12월 19 03:03 install_nodejs.sh
-rw-r--r--  1 root    root    31966076 12월  4 19:20 nodejs_20.19.6-1nodesource1_amd64.deb
-rw-r--r--  1 koopark koopark 26495741 12월 19 03:05 npm_global_bundle.tar.gz
-rwx--x--x  1 koopark koopark     8619 12월 18 23:36 collect_npm_packages.sh
-rw-r--r--  1 koopark koopark      101 12월 18 21:32 global_packages.txt
```

**install_nodejs.sh 분석**:

```bash
# Line 76-82: Node.js deb 설치
dpkg -i "$NODEJS_DEB"

# Line 98-228: npm 글로벌 패키지 설치 (3가지 방법)

# 방법 1: npm_global_bundle.tar.gz 사용 (완전 오프라인)
if [[ -f "$NPM_BUNDLE_TAR" ]]; then
    tar -xzf "$NPM_BUNDLE_TAR" -C "$TEMP_EXTRACT"
    # node_modules와 bin을 직접 복사
    cp -r node_modules/* /usr/lib/node_modules/
    ln -sf /usr/lib/node_modules/typescript/bin/tsc /usr/bin/tsc
    # ... (Line 102-177)
fi

# 방법 2: tgz 캐시 사용 (온라인 fallback 포함)
elif [[ -d "$NPM_CACHE_DIR" ]]; then
    npm cache add "$tgz"  # ⚠️ 완전 오프라인 아님
    npm install -g "$pkg_file" --prefer-offline  # ⚠️ 여전히 온라인 시도
fi

# 방법 3: 온라인 fallback
else
    echo "You can install packages manually when online:"
    echo "  npm install -g typescript ts-node pnpm terser vite"
fi
```

**결론**:
- ✅ `npm_global_bundle.tar.gz` 사용 시 **100% 오프라인 가능**
- ❌ 방법 2, 3은 온라인 접근 시도

---

#### Python 오프라인 패키지

**확인 필요**: Python venv 의존성 패키지

```bash
# 예상 위치 (확인 필요)
offline_packages/python/
  ├─ gunicorn-*.whl
  ├─ flask-*.whl
  ├─ redis-*.whl
  ├─ PyJWT-*.whl
  └─ ... (requirements.txt 전체)
```

**현재 상태**:
- ❌ Python 오프라인 패키지 디렉토리 없음
- ❌ `pip install -r requirements.txt`가 온라인 PyPI 접근

---

### 4.2 오프라인 설치 흐름 검증

#### 현재 오프라인 설치 절차

```bash
# 1. Node.js 오프라인 설치
sudo ./offline_packages/nodejs/install_nodejs.sh
  → ✅ nodejs_20.19.6-1nodesource1_amd64.deb 설치
  → ✅ npm_global_bundle.tar.gz 전개 (typescript, pnpm, vite 등)

# 2. 클러스터 setup 실행
sudo ./setup_cluster_full_multihead_offline.sh
  → cluster/start_multihead.sh
    → phase5_web.sh
      → ❌ npm install -g typescript ...  # 이미 설치됨, 중복
      → ❌ build_all_frontends() 내부에서 npm install  # 온라인 접근!
      → ❌ pip install redis python-dotenv  # venv 없고 온라인 접근!

# 3. 서비스 start
./start.sh
  → dashboard/start_production.sh
    → ❌ build_all_frontends.sh → npm install  # 또 온라인 접근!
    → venv/bin/gunicorn  # venv가 없으면 실행 실패
```

**문제점**:
1. **Node.js는 오프라인 OK**, 하지만 **npm 패키지는 setup/start 시 온라인 접근**
2. **Python venv가 생성되지 않아** gunicorn 실행 실패 가능
3. **pip install이 온라인 PyPI 접근**

---

## 5. 해결 방안

### 5.1 Setup vs Start 역할 재정의

#### 원칙

| 역할 | 실행 시점 | 책임 범위 |
|------|----------|----------|
| **Setup** | 초기 설치 1회 | 시스템 의존성, venv 생성, 초기 빌드, 설정 파일 생성 |
| **Start** | 재시작 시 매번 | 서비스 시작/재시작, 프로세스 관리 |
| **Build** | 코드 변경 시 필요할 때 | 프론트엔드 빌드 (선택적/전체) |

#### 구체적 책임

| 작업 | Setup | Start | Build |
|------|-------|-------|-------|
| apt/yum 패키지 설치 | ✅ | ❌ | ❌ |
| Node.js/npm 설치 | ✅ | ❌ | ❌ |
| npm 글로벌 패키지 (tsc, vite 등) | ✅ | ❌ | ❌ |
| Python venv 생성 | ✅ | ❌ | ❌ |
| pip install -r requirements.txt | ✅ | ❌ | ❌ |
| npm install (프론트엔드 의존성) | ✅ | ❌ | ⚠️ 필요시 |
| 프론트엔드 빌드 (npm run build) | ✅ 1회 | ❌ | ✅ 선택적 |
| Nginx 설정 | ✅ | ❌ | ❌ |
| 서비스 시작/재시작 | ❌ | ✅ | ❌ |
| 프로세스 종료/확인 | ❌ | ✅ | ❌ |

---

### 5.2 빌드 로직 통합

#### 현재 문제

```
phase5_web.sh:build_all_frontends()  ────┐
                                          ├─> 440줄 중복
dashboard/build_all_frontends.sh  ───────┘
```

#### 해결 방안: 단일 빌드 스크립트

```bash
# dashboard/build_all_frontends.sh (개선)

#!/bin/bash
# 사용법:
#   ./build_all_frontends.sh              # 전체 빌드
#   ./build_all_frontends.sh --frontend frontend_3010  # 선택적 빌드
#   ./build_all_frontends.sh --skip-install  # npm install 건너뛰기

SKIP_INSTALL=false
TARGET_FRONTEND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        --frontend)
            TARGET_FRONTEND="$2"
            shift 2
            ;;
    esac
done

frontends=(
    "frontend_3010"
    "vnc_service_8002"
    "moonlight_frontend_8003"
    "kooCAEWeb_5173"
    "app_5174"
)

build_frontend() {
    local frontend=$1

    cd "$frontend"

    # 1. TypeScript 캐시 삭제
    rm -f tsconfig.tsbuildinfo

    # 2. dist 폴더 삭제
    sudo rm -rf dist

    # 3. npm install (--skip-install 플래그 확인)
    if [[ "$SKIP_INSTALL" == false ]] && [[ ! -d "node_modules" ]]; then
        echo "Installing dependencies for $frontend..."
        npm install --offline 2>/dev/null || npm install  # 오프라인 우선
    fi

    # 4. 빌드
    npm run build

    # 5. Nginx 디렉토리 배포
    sudo cp -r dist/* /var/www/html/$frontend/
}

# 선택적 or 전체 빌드
if [[ -n "$TARGET_FRONTEND" ]]; then
    build_frontend "$TARGET_FRONTEND"
else
    for frontend in "${frontends[@]}"; do
        build_frontend "$frontend"
    done
fi
```

#### phase5_web.sh 수정

```bash
# cluster/setup/phase5_web.sh

build_all_frontends() {
    log_info "Building frontend services for production..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"

    # 빌드 스크립트 호출 (중복 제거)
    if [[ -f "$dashboard_dir/build_all_frontends.sh" ]]; then
        cd "$dashboard_dir"
        ./build_all_frontends.sh
        cd "$PROJECT_ROOT"
        log_success "All frontends built"
    else
        log_error "build_all_frontends.sh not found"
        return 1
    fi
}
```

**장점**:
- ✅ 코드 중복 제거 (440줄 → 단일 스크립트)
- ✅ 선택적 빌드 지원
- ✅ `--skip-install` 플래그로 npm install 제어

---

### 5.3 venv 하드카피 배포

#### 배포 전략

**전제**: venv와 node_modules는 사전 빌드 후 전체 디렉토리를 복사

```bash
# 온라인 빌드 서버에서 (setup_cluster_full_multihead_offline.sh 실행 전)

# 1. Python venv 생성 및 패키지 설치
backends=(
    "auth_portal_4430"
    "backend_5010"
    "websocket_5011"
    "kooCAEWebServer_5000"
    "kooCAEAutoBackend_5001"
    "MoonlightSunshine_8004"
)

for backend in "${backends[@]}"; do
    cd dashboard/$backend
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    deactivate
    cd ../..
done

# 2. Node.js node_modules 설치
frontends=(
    "frontend_3010"
    "auth_portal_4431"
    "vnc_service_8002"
    "moonlight_frontend_8003"
    "kooCAEWeb_5173"
    "app_5174"
)

for frontend in "${frontends[@]}"; do
    cd dashboard/$frontend
    npm install
    cd ../..
done

# 3. 전체 패키징
tar -czf dashboard_with_deps.tar.gz dashboard/
# 또는 rsync로 직접 복사
rsync -av --progress dashboard/ target_server:/path/to/dashboard/
```

#### 해결 방안: phase5_web.sh는 venv 검증만

```bash
# cluster/setup/phase5_web.sh (수정)

validate_all_venvs() {
    log_info "Validating Python virtual environments for all backends..."

    local backends=(
        "auth_portal_4430"
        "backend_5010"
        "websocket_5011"
        "kooCAEWebServer_5000"
        "kooCAEAutoBackend_5001"
        "MoonlightSunshine_8004"
    )

    local dashboard_dir="$PROJECT_ROOT/dashboard"
    local missing_venvs=()

    for backend in "${backends[@]}"; do
        local backend_dir="$dashboard_dir/$backend"
        local venv_dir="$backend_dir/venv"

        if [[ ! -d "$venv_dir" ]]; then
            log_error "❌ venv not found: $backend_dir/venv"
            missing_venvs+=("$backend")
        else
            # venv 존재 확인 및 gunicorn 확인
            if [[ -f "$venv_dir/bin/gunicorn" ]]; then
                log_success "✅ venv valid: $backend (gunicorn found)"
            else
                log_warning "⚠️  venv exists but gunicorn not found: $backend"
                missing_venvs+=("$backend")
            fi
        fi
    done

    if [[ ${#missing_venvs[@]} -gt 0 ]]; then
        log_error "Missing or invalid venvs: ${missing_venvs[*]}"
        log_error "Please ensure venv and node_modules are copied via rsync/tar before running setup"
        return 1
    fi

    log_success "All venvs validated"
    return 0
}

validate_all_node_modules() {
    log_info "Validating node_modules for all frontends..."

    local frontends=(
        "frontend_3010"
        "vnc_service_8002"
        "moonlight_frontend_8003"
        "kooCAEWeb_5173"
        "app_5174"
    )

    local dashboard_dir="$PROJECT_ROOT/dashboard"
    local missing_modules=()

    for frontend in "${frontends[@]}"; do
        local frontend_dir="$dashboard_dir/$frontend"
        local modules_dir="$frontend_dir/node_modules"

        if [[ ! -d "$modules_dir" ]]; then
            log_error "❌ node_modules not found: $frontend_dir/node_modules"
            missing_modules+=("$frontend")
        else
            log_success "✅ node_modules found: $frontend"
        fi
    done

    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        log_error "Missing node_modules: ${missing_modules[*]}"
        log_error "Please ensure node_modules are copied via rsync/tar before running setup"
        return 1
    fi

    log_success "All node_modules validated"
    return 0
}

# main() 함수에 추가
main() {
    # ... 기존 코드 ...

    # venv와 node_modules 검증 (생성하지 않음)
    validate_all_venvs || exit 1
    validate_all_node_modules || exit 1

    build_all_frontends

    # ... 기존 코드 ...
}
```

---

### 5.4 오프라인 환경 완전 지원

#### Python 오프라인 패키지 수집

```bash
# offline_packages/python/collect_python_packages.sh (신규 작성)

#!/bin/bash
# Python 오프라인 패키지 수집 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELS_DIR="$SCRIPT_DIR/wheels"
DASHBOARD_DIR="$(cd "$SCRIPT_DIR/../../dashboard" && pwd)"

mkdir -p "$WHEELS_DIR"

echo "Collecting Python packages from all backends..."

# 모든 requirements.txt 수집
backends=(
    "auth_portal_4430"
    "backend_5010"
    "websocket_5011"
    "kooCAEWebServer_5000"
    "kooCAEAutoBackend_5001"
    "MoonlightSunshine_8004"
)

# 중복 제거를 위한 requirements 통합
TEMP_REQ="/tmp/all_requirements.txt"
rm -f "$TEMP_REQ"

for backend in "${backends[@]}"; do
    req_file="$DASHBOARD_DIR/$backend/requirements.txt"
    if [[ -f "$req_file" ]]; then
        cat "$req_file" >> "$TEMP_REQ"
    fi
done

# 중복 제거 및 정렬
sort -u "$TEMP_REQ" -o "$TEMP_REQ"

echo "Downloading wheels..."
pip download -r "$TEMP_REQ" -d "$WHEELS_DIR"

echo "Creating archive..."
tar -czf "$SCRIPT_DIR/python_wheels.tar.gz" -C "$SCRIPT_DIR" wheels

echo "Python packages collected: $(ls -1 $WHEELS_DIR/*.whl | wc -l) wheels"
echo "Archive: $SCRIPT_DIR/python_wheels.tar.gz"
```

#### 오프라인 설치 스크립트

```bash
# offline_packages/python/install_python_packages.sh (신규 작성)

#!/bin/bash
# Python 오프라인 패키지 설치 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELS_TAR="$SCRIPT_DIR/python_wheels.tar.gz"
WHEELS_DIR="$SCRIPT_DIR/wheels"

if [[ -f "$WHEELS_TAR" ]]; then
    echo "Extracting Python wheels..."
    tar -xzf "$WHEELS_TAR" -C "$SCRIPT_DIR"
    echo "✅ Python wheels extracted to $WHEELS_DIR"
else
    echo "❌ python_wheels.tar.gz not found"
    exit 1
fi

echo ""
echo "Python offline packages ready!"
echo "Use: pip install -r requirements.txt --no-index --find-links=$WHEELS_DIR"
```

#### npm 오프라인 패키지 수집

```bash
# offline_packages/nodejs/collect_npm_packages.sh (개선)

#!/bin/bash
# npm 오프라인 패키지 수집 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/npm_cache"
DASHBOARD_DIR="$(cd "$SCRIPT_DIR/../../dashboard" && pwd)"

mkdir -p "$CACHE_DIR"

echo "Collecting npm packages from all frontends..."

frontends=(
    "frontend_3010"
    "vnc_service_8002"
    "moonlight_frontend_8003"
    "kooCAEWeb_5173"
    "app_5174"
    "auth_portal_4431"
)

for frontend in "${frontends[@]}"; do
    frontend_dir="$DASHBOARD_DIR/$frontend"

    if [[ ! -d "$frontend_dir" ]]; then
        echo "⚠️  $frontend not found, skipping"
        continue
    fi

    echo "Processing $frontend..."
    cd "$frontend_dir"

    # node_modules가 있으면 캐시에 추가
    if [[ -d "node_modules" ]]; then
        # 모든 패키지를 tgz로 pack
        npm pack $(npm list --depth=0 --parseable | tail -n +2 | xargs -n1 basename) \
            --pack-destination="$CACHE_DIR" 2>/dev/null || true
    else
        echo "⚠️  node_modules not found in $frontend"
    fi
done

echo "Creating npm cache archive..."
tar -czf "$SCRIPT_DIR/npm_cache.tar.gz" -C "$SCRIPT_DIR" npm_cache

echo "npm packages collected: $(ls -1 $CACHE_DIR/*.tgz | wc -l) packages"
echo "Archive: $SCRIPT_DIR/npm_cache.tar.gz"
```

#### build_all_frontends.sh 오프라인 대응

**전제**: node_modules가 이미 하드카피로 존재

```bash
# dashboard/build_all_frontends.sh (개선)

build_frontend() {
    local frontend=$1

    cd "$frontend"

    # 1. node_modules 검증
    if [[ ! -d "node_modules" ]]; then
        log_error "❌ node_modules not found for $frontend"
        log_error "   Please copy node_modules via rsync/tar before building"
        return 1
    fi

    # 2. TypeScript 캐시 삭제
    rm -f tsconfig.tsbuildinfo

    # 3. dist 폴더 삭제
    sudo rm -rf dist

    # 4. 빌드 (npm install 생략)
    log_info "Building $frontend (using existing node_modules)..."
    npm run build

    # 5. Nginx 디렉토리 배포
    sudo cp -r dist/* /var/www/html/$frontend/
}
```

**중요**: npm install은 **절대 실행하지 않음**
- node_modules는 사전 빌드 서버에서 `npm install` 후 전체 복사
- build_all_frontends.sh는 빌드만 수행 (`npm run build`)

---

### 5.5 start_production.sh 개선

#### 빌드 건너뛰기 플래그 추가

```bash
# dashboard/start_production.sh (개선)

#!/bin/bash

# 기본값: 빌드하지 않음
BUILD_FRONTENDS=false

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild|--build)
            BUILD_FRONTENDS=true
            shift
            ;;
        --skip-build)
            BUILD_FRONTENDS=false
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "=========================================="
echo "🚀 HPC Cluster Production 모드 시작 (Gunicorn)"
echo "=========================================="
echo ""

# ==================== 0. 프론트엔드 빌드 (선택적) ====================
if [[ "$BUILD_FRONTENDS" == true ]]; then
    echo -e "${BLUE}[0/9] 프론트엔드 빌드 중...${NC}"
    if [ -f "./build_all_frontends.sh" ]; then
        ./build_all_frontends.sh
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ 프론트엔드 빌드 실패. 계속 진행합니다...${NC}"
        fi
    else
        echo -e "${YELLOW}⚠  빌드 스크립트 없음.${NC}"
    fi
else
    echo -e "${YELLOW}[0/9] 프론트엔드 빌드 건너뜀 (--rebuild 플래그로 빌드 가능)${NC}"
fi
echo ""

# ... 나머지 서비스 시작 로직 ...
```

**사용 예시**:

```bash
# 기본: 빌드 안 함 (30초)
./start_production.sh

# 빌드 포함 (5-10분)
./start_production.sh --rebuild

# 명시적으로 빌드 건너뛰기 (기본과 동일)
./start_production.sh --skip-build
```

---

## 6. 구현 계획

### Phase 1: venv 통합 (우선순위: 🔴 High)

**작업 항목**:
1. `cluster/setup/phase5_web.sh`에 `create_all_venvs()` 함수 추가
2. Python 오프라인 패키지 수집 스크립트 작성
   - `offline_packages/python/collect_python_packages.sh`
   - `offline_packages/python/install_python_packages.sh`
3. phase5_web.sh에서 오프라인 pip install 지원

**예상 소요 시간**: 1일

**검증**:
```bash
# 테스트
sudo ./cluster/setup/phase5_web.sh --dry-run

# 확인
for backend in auth_portal_4430 backend_5010 websocket_5011 \
               kooCAEWebServer_5000 kooCAEAutoBackend_5001 MoonlightSunshine_8004; do
    ls -ld dashboard/$backend/venv
    dashboard/$backend/venv/bin/python --version
    dashboard/$backend/venv/bin/pip list | grep -E "gunicorn|redis|PyJWT"
done
```

---

### Phase 2: 빌드 로직 통합 (우선순위: 🔴 High)

**작업 항목**:
1. `dashboard/build_all_frontends.sh` 개선
   - `--skip-install` 플래그 추가
   - `--frontend <name>` 선택적 빌드 추가
   - npm 오프라인 캐시 지원
2. `phase5_web.sh`의 `build_all_frontends()` 함수를 스크립트 호출로 변경
3. 프론트엔드 목록 통일 (auth_portal_4431 제외, moonlight 포함)

**예상 소요 시간**: 1일

**검증**:
```bash
# 전체 빌드 테스트
./dashboard/build_all_frontends.sh

# 선택적 빌드 테스트
./dashboard/build_all_frontends.sh --frontend frontend_3010

# npm install 건너뛰기 테스트
./dashboard/build_all_frontends.sh --skip-install

# phase5_web.sh 통합 테스트
sudo ./cluster/setup/phase5_web.sh --dry-run
```

---

### Phase 3: start_production.sh 개선 (우선순위: 🟡 Medium)

**작업 항목**:
1. `--rebuild` / `--skip-build` 플래그 추가
2. 기본 동작을 빌드 건너뛰기로 변경
3. venv fallback 로직 추가 (venv 없으면 경고 출력)

**예상 소요 시간**: 0.5일

**검증**:
```bash
# 빌드 없이 시작 (30초)
./start_production.sh

# 빌드 포함 시작 (5-10분)
./start_production.sh --rebuild

# venv 없을 때 동작 확인
rm -rf dashboard/backend_5010/venv
./start_production.sh 2>&1 | grep -i "venv"
```

---

### Phase 4: 오프라인 환경 완전 지원 (우선순위: 🟡 Medium)

**작업 항목**:
1. Python 오프라인 패키지 수집 및 설치 자동화
   - `collect_python_packages.sh` 작성
   - `install_python_packages.sh` 작성
2. npm 오프라인 캐시 개선
   - `collect_npm_packages.sh` 개선
   - `build_all_frontends.sh`에 오프라인 우선 로직 추가
3. 오프라인 설치 문서 업데이트

**예상 소요 시간**: 2일

**검증**:
```bash
# 오프라인 패키지 수집 (온라인 환경)
./offline_packages/python/collect_python_packages.sh
./offline_packages/nodejs/collect_npm_packages.sh

# 오프라인 설치 테스트 (네트워크 차단 환경)
sudo iptables -A OUTPUT -p tcp --dport 80 -j REJECT
sudo iptables -A OUTPUT -p tcp --dport 443 -j REJECT

./offline_packages/python/install_python_packages.sh
./offline_packages/nodejs/install_nodejs.sh

sudo ./cluster/setup/phase5_web.sh
# → npm install, pip install이 모두 오프라인에서 성공해야 함

sudo iptables -F  # 규칙 초기화
```

---

### Phase 5: 문서화 (우선순위: 🟢 Low)

**작업 항목**:
1. `DEVELOPMENT_WORKFLOW.md` 작성
2. 오프라인 설치 가이드 업데이트
3. README 업데이트

**예상 소요 시간**: 1일

---

## 7. 요약

### 7.1 핵심 문제

| 문제 | 심각도 | 영향 범위 |
|------|--------|----------|
| **venv 미생성** | 🔴 Critical | 5개 백엔드 서비스 시작 실패 가능 |
| **온라인 의존성** | 🔴 Critical | 오프라인 환경에서 설치 실패 (14회 접근) |
| **빌드 로직 중복** | 🟡 Medium | 유지보수 부담, 440줄 중복 |
| **매번 프론트엔드 빌드** | 🟡 Medium | 재시작마다 5-10분 낭비 |

---

### 7.2 해결 방안 요약

| 항목 | 현재 | 개선 후 |
|------|------|---------|
| **venv 배포** | install_all.sh (auth만 생성) | 하드카피 (사전 빌드 서버에서 전체 복사) |
| **node_modules 배포** | npm install (온라인 접근) | 하드카피 (사전 빌드 서버에서 전체 복사) |
| **venv 검증** | 없음 (누락 시 실패) | phase5_web.sh에서 전체 검증 |
| **node_modules 검증** | 없음 (누락 시 실패) | phase5_web.sh에서 전체 검증 |
| **빌드 로직** | 2곳 중복 (440줄) | 단일 스크립트 |
| **start 시 빌드** | 매번 빌드 (5-10분) | 기본 skip (30초) |
| **선택적 빌드** | 불가능 | 가능 (--frontend 플래그) |
| **npm install 제거** | build 시마다 실행 | 완전 제거 (하드카피 전제) |
| **pip install 제거** | phase5_web.sh에서 실행 | 완전 제거 (하드카피 전제) |

---

### 7.3 기대 효과

| 항목 | 개선 효과 |
|------|-----------|
| **개발 속도** | 백엔드 변경 시 재시작 30초 (5-10분 → 30초) |
| **오프라인 지원** | 100% 오프라인 설치 가능 (온라인 의존성 제거) |
| **유지보수성** | 빌드 로직 단일화 (440줄 중복 제거) |
| **안정성** | venv 격리로 의존성 충돌 방지 |

---

**문서 끝**
