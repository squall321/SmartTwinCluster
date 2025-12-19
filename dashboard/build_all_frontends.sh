#!/bin/bash
################################################################################
# 모든 프론트엔드 빌드 스크립트
# Dashboard Frontend, VNC Service, CAE Frontend 빌드
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🔨 프론트엔드 빌드 시작"
echo "=========================================="
echo ""

BUILD_SUCCESS=0
BUILD_FAILED=0

# ==================== 1. Dashboard Frontend (3010) ====================
echo -e "${BLUE}[1/3] Dashboard Frontend 빌드 중...${NC}"
if [ -d "frontend_3010" ]; then
    cd frontend_3010

    # TypeScript 캐시 삭제 (새 코드 반영 보장)
    if [ -f "tsconfig.tsbuildinfo" ]; then
        echo "  → TypeScript 캐시 삭제 중..."
        rm -f tsconfig.tsbuildinfo 2>/dev/null || true
    fi

    # dist 폴더 권한 문제 해결 (강제 삭제)
    if [ -d "dist" ]; then
        echo "  → 기존 dist 폴더 삭제 중..."
        rm -rf dist 2>/dev/null || sudo rm -rf dist 2>/dev/null || true
    fi

    # node_modules 확인
    if [ ! -d "node_modules" ]; then
        echo "  → npm install 실행 중..."
        npm install --silent
    fi

    # 빌드 실행 (TypeScript 컴파일 포함)
    echo "  → 빌드 실행 중..."
    sudo rm -f /tmp/dashboard_build.log 2>/dev/null || true
    if npm run build > /tmp/dashboard_build.log 2>&1; then
        echo -e "${GREEN}✅ Dashboard Frontend 빌드 성공${NC}"
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # Nginx 배포 디렉토리로 복사
        echo "  → Nginx 배포 디렉토리로 복사 중..."
        sudo rm -rf /var/www/html/dashboard 2>/dev/null || true
        sudo mkdir -p /var/www/html/dashboard
        sudo cp -r dist/* /var/www/html/dashboard/
        sudo chown -R www-data:www-data /var/www/html/dashboard
        echo -e "${GREEN}  ✅ 배포 완료: /var/www/html/dashboard${NC}"
    else
        echo -e "${RED}❌ Dashboard Frontend 빌드 실패${NC}"
        echo "  → 로그: /tmp/dashboard_build.log"
        tail -20 /tmp/dashboard_build.log
        BUILD_FAILED=$((BUILD_FAILED + 1))
    fi

    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}⚠  frontend_3010 디렉토리 없음${NC}"
fi
echo ""

# ==================== 2. VNC Service (8002) ====================
echo -e "${BLUE}[2/3] VNC Service 빌드 중...${NC}"
if [ -d "vnc_service_8002" ]; then
    cd vnc_service_8002

    # TypeScript 캐시 삭제 (새 코드 반영 보장)
    if [ -f "tsconfig.tsbuildinfo" ]; then
        echo "  → TypeScript 캐시 삭제 중..."
        rm -f tsconfig.tsbuildinfo 2>/dev/null || true
    fi

    # dist 폴더 권한 문제 해결 (강제 삭제)
    if [ -d "dist" ]; then
        echo "  → 기존 dist 폴더 삭제 중..."
        rm -rf dist 2>/dev/null || sudo rm -rf dist 2>/dev/null || true
    fi

    # node_modules 확인
    if [ ! -d "node_modules" ]; then
        echo "  → npm install 실행 중..."
        npm install --silent
    fi

    # 빌드 실행 (TypeScript 컴파일 포함)
    echo "  → 빌드 실행 중..."
    sudo rm -f /tmp/vnc_build.log 2>/dev/null || true
    if npm run build > /tmp/vnc_build.log 2>&1; then
        echo -e "${GREEN}✅ VNC Service 빌드 성공${NC}"
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # Nginx 배포 디렉토리로 복사
        echo "  → Nginx 배포 디렉토리로 복사 중..."
        sudo rm -rf /var/www/html/vnc_service_8002 2>/dev/null || true
        sudo mkdir -p /var/www/html/vnc_service_8002
        sudo cp -r dist/* /var/www/html/vnc_service_8002/
        sudo chown -R www-data:www-data /var/www/html/vnc_service_8002
        echo -e "${GREEN}  ✅ 배포 완료: /var/www/html/vnc_service_8002${NC}"
    else
        echo -e "${RED}❌ VNC Service 빌드 실패${NC}"
        echo "  → 로그: /tmp/vnc_build.log"
        tail -20 /tmp/vnc_build.log
        BUILD_FAILED=$((BUILD_FAILED + 1))
    fi

    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}⚠  vnc_service_8002 디렉토리 없음${NC}"
fi
echo ""

# ==================== 3. Moonlight Frontend (8003) ====================
echo -e "${BLUE}[3/5] Moonlight Frontend 빌드 중...${NC}"
if [ -d "moonlight_frontend_8003" ]; then
    cd moonlight_frontend_8003

    # TypeScript 캐시 삭제 (새 코드 반영 보장)
    if [ -f "tsconfig.tsbuildinfo" ]; then
        echo "  → TypeScript 캐시 삭제 중..."
        rm -f tsconfig.tsbuildinfo 2>/dev/null || true
    fi

    # dist 폴더 권한 문제 해결 (강제 삭제)
    if [ -d "dist" ]; then
        echo "  → 기존 dist 폴더 삭제 중..."
        rm -rf dist 2>/dev/null || sudo rm -rf dist 2>/dev/null || true
    fi

    # node_modules 확인
    if [ ! -d "node_modules" ]; then
        echo "  → npm install 실행 중..."
        npm install --silent
    fi

    # 빌드 실행 (TypeScript 컴파일 포함)
    echo "  → 빌드 실행 중..."
    sudo rm -f /tmp/moonlight_build.log 2>/dev/null || true
    if npm run build > /tmp/moonlight_build.log 2>&1; then
        echo -e "${GREEN}✅ Moonlight Frontend 빌드 성공${NC}"
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # Nginx 배포 디렉토리로 복사
        echo "  → Nginx 배포 디렉토리로 복사 중..."
        sudo rm -rf /var/www/html/moonlight 2>/dev/null || true
        sudo mkdir -p /var/www/html/moonlight
        sudo cp -r dist/* /var/www/html/moonlight/
        sudo chown -R www-data:www-data /var/www/html/moonlight
        echo -e "${GREEN}  ✅ 배포 완료: /var/www/html/moonlight${NC}"
    else
        echo -e "${RED}❌ Moonlight Frontend 빌드 실패${NC}"
        echo "  → 로그: /tmp/moonlight_build.log"
        tail -20 /tmp/moonlight_build.log
        BUILD_FAILED=$((BUILD_FAILED + 1))
    fi

    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}⚠  moonlight_frontend_8003 디렉토리 없음${NC}"
fi
echo ""

# ==================== 4. CAE Frontend (5173) ====================
echo -e "${BLUE}[4/5] CAE Frontend 빌드 중...${NC}"
if [ -d "kooCAEWeb_5173" ]; then
    cd kooCAEWeb_5173

    # TypeScript 캐시 삭제 (새 코드 반영 보장)
    if [ -f "tsconfig.tsbuildinfo" ]; then
        echo "  → TypeScript 캐시 삭제 중..."
        rm -f tsconfig.tsbuildinfo 2>/dev/null || true
    fi

    # dist 폴더 권한 문제 해결 (강제 삭제)
    if [ -d "dist" ]; then
        echo "  → 기존 dist 폴더 삭제 중..."
        rm -rf dist 2>/dev/null || sudo rm -rf dist 2>/dev/null || true
    fi

    # node_modules 확인 - 주요 의존성 체크 추가
    need_install=false
    if [ ! -d "node_modules" ]; then
        need_install=true
        echo "  → node_modules 없음"
    elif [ ! -d "node_modules/@mui/material" ]; then
        need_install=true
        echo "  → @mui/material 누락됨"
    elif [ ! -d "node_modules/@mui/icons-material" ]; then
        need_install=true
        echo "  → @mui/icons-material 누락됨"
    fi

    if [ "$need_install" = true ]; then
        echo "  → npm install 실행 중... (의존성 설치)"
        npm install 2>&1 | tail -5 || {
            echo -e "${YELLOW}  ⚠ npm install 경고 발생 - 계속 진행${NC}"
        }
    else
        echo "  → node_modules 확인 완료"
    fi

    # 빌드 실행 (TypeScript 컴파일 포함)
    echo "  → 빌드 실행 중..."
    sudo rm -f /tmp/cae_build.log 2>/dev/null || true
    if npm run build > /tmp/cae_build.log 2>&1; then
        echo -e "${GREEN}✅ CAE Frontend 빌드 성공${NC}"
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # Nginx 배포 디렉토리로 복사
        echo "  → Nginx 배포 디렉토리로 복사 중..."
        sudo rm -rf /var/www/html/cae 2>/dev/null || true
        sudo mkdir -p /var/www/html/cae
        sudo cp -r dist/* /var/www/html/cae/
        sudo chown -R www-data:www-data /var/www/html/cae
        echo -e "${GREEN}  ✅ 배포 완료: /var/www/html/cae${NC}"
    else
        echo -e "${RED}❌ CAE Frontend 빌드 실패${NC}"
        echo "  → 로그: /tmp/cae_build.log"
        tail -20 /tmp/cae_build.log
        # 의존성 문제인 경우 npm install 강제 재실행 후 재시도
        if grep -q "Cannot find module" /tmp/cae_build.log 2>/dev/null; then
            echo -e "${YELLOW}  → 모듈 누락 감지, npm install 재실행 후 재빌드 시도...${NC}"
            rm -rf node_modules 2>/dev/null || true
            npm install 2>&1 | tail -5
            if npm run build > /tmp/cae_build.log 2>&1; then
                echo -e "${GREEN}✅ CAE Frontend 재빌드 성공${NC}"
                BUILD_SUCCESS=$((BUILD_SUCCESS + 1))
                sudo rm -rf /var/www/html/cae 2>/dev/null || true
                sudo mkdir -p /var/www/html/cae
                sudo cp -r dist/* /var/www/html/cae/
                sudo chown -R www-data:www-data /var/www/html/cae
                echo -e "${GREEN}  ✅ 배포 완료: /var/www/html/cae${NC}"
            else
                BUILD_FAILED=$((BUILD_FAILED + 1))
            fi
        else
            BUILD_FAILED=$((BUILD_FAILED + 1))
        fi
    fi

    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}⚠  kooCAEWeb_5173 디렉토리 없음${NC}"
fi
echo ""

# ==================== 5. App Service (5174) ====================
echo -e "${BLUE}[5/5] App Service 빌드 중...${NC}"
if [ -d "app_5174" ]; then
    cd app_5174

    # TypeScript 캐시 삭제 (새 코드 반영 보장)
    if [ -f "tsconfig.tsbuildinfo" ]; then
        echo "  → TypeScript 캐시 삭제 중..."
        rm -f tsconfig.tsbuildinfo 2>/dev/null || true
    fi

    # dist 폴더 권한 문제 해결 (강제 삭제)
    if [ -d "dist" ]; then
        echo "  → 기존 dist 폴더 삭제 중..."
        rm -rf dist 2>/dev/null || sudo rm -rf dist 2>/dev/null || true
    fi

    # node_modules 확인
    if [ ! -d "node_modules" ]; then
        echo "  → npm install 실행 중..."
        npm install --silent
    fi

    # 빌드 실행 (TypeScript 컴파일 포함)
    echo "  → 빌드 실행 중..."
    sudo rm -f /tmp/app_build.log 2>/dev/null || true
    if npm run build > /tmp/app_build.log 2>&1; then
        cp landing.html dist/index.html 2>/dev/null || true
        echo -e "${GREEN}✅ App Service 빌드 성공${NC}"
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # Nginx 배포 디렉토리로 복사
        echo "  → Nginx 배포 디렉토리로 복사 중..."
        sudo rm -rf /var/www/html/app_5174 2>/dev/null || true
        sudo mkdir -p /var/www/html/app_5174
        sudo cp -r dist/* /var/www/html/app_5174/
        sudo chown -R www-data:www-data /var/www/html/app_5174
        echo -e "${GREEN}  ✅ 배포 완료: /var/www/html/app_5174${NC}"
    else
        echo -e "${RED}❌ App Service 빌드 실패${NC}"
        echo "  → 로그: /tmp/app_build.log"
        tail -20 /tmp/app_build.log
        BUILD_FAILED=$((BUILD_FAILED + 1))
    fi

    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}⚠  app_5174 디렉토리 없음${NC}"
fi
echo ""


# ==================== 빌드 결과 ====================
echo "=========================================="
if [ $BUILD_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ 모든 프론트엔드 빌드 완료! ($BUILD_SUCCESS/5)${NC}"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}❌ 일부 빌드 실패 (성공: $BUILD_SUCCESS, 실패: $BUILD_FAILED)${NC}"
    echo "=========================================="
    exit 1
fi
