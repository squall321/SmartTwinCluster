#!/bin/bash
################################################################################
# 모든 프론트엔드 빌드 스크립트
#
# 사용법:
#   ./build_all_frontends.sh                      # 전체 빌드
#   ./build_all_frontends.sh --frontend <name>    # 선택적 빌드
#
# 옵션:
#   --frontend <name>   특정 프론트엔드만 빌드 (예: frontend_3010)
#
# 주의:
#   - node_modules는 사전에 하드카피로 배포되어 있어야 함
#   - npm install은 실행하지 않음 (오프라인 환경)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 인자 파싱
TARGET_FRONTEND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --frontend)
            TARGET_FRONTEND="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "🔨 프론트엔드 빌드 시작"
if [[ -n "$TARGET_FRONTEND" ]]; then
    echo "   (선택적 빌드: $TARGET_FRONTEND)"
fi
echo "=========================================="
echo ""

BUILD_SUCCESS=0
BUILD_FAILED=0

# 프론트엔드 목록 (auth_portal_4431 포함)
frontends=(
    "auth_portal_4431"        # Auth Portal (NEW!)
    "frontend_3010"           # Dashboard
    "vnc_service_8002"        # VNC
    "moonlight_frontend_8003" # Moonlight
    "kooCAEWeb_5173"          # CAE
    "app_5174"                # App Service
)

# Nginx 배포 경로 매핑
declare -A nginx_paths=(
    ["auth_portal_4431"]="/var/www/html/auth_portal"
    ["frontend_3010"]="/var/www/html/dashboard"
    ["vnc_service_8002"]="/var/www/html/vnc_service_8002"
    ["moonlight_frontend_8003"]="/var/www/html/moonlight"
    ["kooCAEWeb_5173"]="/var/www/html/cae"
    ["app_5174"]="/var/www/html/app_5174"
)

# 프론트엔드 빌드 함수
build_frontend() {
    local frontend=$1
    local index=$2
    local total=$3

    echo -e "${BLUE}[$index/$total] $frontend 빌드 중...${NC}"

    if [ ! -d "$frontend" ]; then
        echo -e "${YELLOW}⚠  $frontend 디렉토리 없음${NC}"
        echo ""
        return 1
    fi

    cd "$frontend"

    # 1. TypeScript 캐시 삭제
    if [ -f "tsconfig.tsbuildinfo" ]; then
        echo "  → TypeScript 캐시 삭제 중..."
        rm -f tsconfig.tsbuildinfo 2>/dev/null || true
    fi

    # 2. dist 폴더 삭제
    if [ -d "dist" ]; then
        echo "  → 기존 dist 폴더 삭제 중..."
        rm -rf dist 2>/dev/null || sudo rm -rf dist 2>/dev/null || true
    fi

    # 3. node_modules 검증 (하드카피 전제 - npm install 하지 않음)
    if [ ! -d "node_modules" ]; then
        echo -e "${RED}❌ node_modules not found for $frontend${NC}"
        echo "   Please copy node_modules via rsync/tar before building"
        cd "$SCRIPT_DIR"
        return 1
    fi

    # 4. 주요 의존성 추가 체크 (CAE Frontend)
    if [[ "$frontend" == "kooCAEWeb_5173" ]]; then
        if [ ! -d "node_modules/@mui/material" ] || [ ! -d "node_modules/@mui/icons-material" ]; then
            echo -e "${RED}❌ Critical MUI packages missing in $frontend${NC}"
            echo "   Please ensure complete node_modules are copied"
            cd "$SCRIPT_DIR"
            return 1
        fi
    fi

    # 5. 빌드 실행
    echo "  → 빌드 실행 중 (using existing node_modules)..."
    sudo rm -f "/tmp/${frontend}_build.log" 2>/dev/null || true

    if npm run build > "/tmp/${frontend}_build.log" 2>&1; then
        echo -e "${GREEN}✅ $frontend 빌드 성공${NC}"
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # 6. app_5174 특별 처리: landing.html 복사
        if [[ "$frontend" == "app_5174" && -f "landing.html" ]]; then
            cp landing.html dist/index.html 2>/dev/null || true
            echo "  → landing.html copied to dist/index.html"
        fi

        # 7. Nginx 배포 디렉토리로 복사
        local nginx_path="${nginx_paths[$frontend]}"
        echo "  → Nginx 배포 디렉토리로 복사 중..."
        sudo rm -rf "$nginx_path" 2>/dev/null || true
        sudo mkdir -p "$nginx_path"
        sudo cp -r dist/* "$nginx_path/"
        sudo chown -R www-data:www-data "$nginx_path" 2>/dev/null || sudo chown -R nginx:nginx "$nginx_path" 2>/dev/null || true
        sudo chmod -R 755 "$nginx_path"
        echo -e "${GREEN}  ✅ 배포 완료: $nginx_path${NC}"
    else
        echo -e "${RED}❌ $frontend 빌드 실패${NC}"
        echo "  → 로그: /tmp/${frontend}_build.log"
        tail -20 "/tmp/${frontend}_build.log"
        BUILD_FAILED=$((BUILD_FAILED + 1))
    fi

    cd "$SCRIPT_DIR"
    echo ""
}

# 빌드 실행
if [[ -n "$TARGET_FRONTEND" ]]; then
    # 선택적 빌드
    build_frontend "$TARGET_FRONTEND" 1 1
else
    # 전체 빌드
    total=${#frontends[@]}
    index=1
    for frontend in "${frontends[@]}"; do
        build_frontend "$frontend" $index $total
        ((index++))
    done
fi

# ==================== 빌드 결과 ====================
echo "=========================================="
if [ $BUILD_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ 모든 프론트엔드 빌드 완료! (성공: $BUILD_SUCCESS)${NC}"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}❌ 일부 빌드 실패 (성공: $BUILD_SUCCESS, 실패: $BUILD_FAILED)${NC}"
    echo "=========================================="
    exit 1
fi
