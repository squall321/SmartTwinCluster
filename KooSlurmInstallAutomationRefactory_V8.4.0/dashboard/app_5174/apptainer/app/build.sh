#!/bin/bash
set -e

echo "==================================="
echo "Apptainer App Builder"
echo "==================================="
echo ""

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 빌드할 앱 목록
APPS=("gedit")

# 현재 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Build directory: $SCRIPT_DIR"
echo ""

# Apptainer 버전 확인
if ! command -v apptainer &> /dev/null; then
    echo -e "${RED}❌ Apptainer not found${NC}"
    echo "Please install Apptainer first"
    exit 1
fi

echo "Apptainer version:"
apptainer --version
echo ""

# 각 앱 빌드
for app in "${APPS[@]}"; do
    echo -e "${YELLOW}==================================="
    echo "Building: $app"
    echo -e "===================================${NC}"

    if [ ! -d "$app" ]; then
        echo -e "${RED}❌ Directory not found: $app${NC}"
        continue
    fi

    cd "$app"

    # 필수 파일 확인
    if [ ! -f "${app}.def" ]; then
        echo -e "${RED}❌ Definition file not found: ${app}.def${NC}"
        cd "$SCRIPT_DIR"
        continue
    fi

    # start 스크립트가 있으면 실행 가능하게 만들기
    if [ -f "start-${app}.sh" ]; then
        chmod +x "start-${app}.sh"
        echo -e "${GREEN}✅ Made start-${app}.sh executable${NC}"
    fi

    # Apptainer 빌드
    echo ""
    echo "Building ${app}.sif..."

    if sudo apptainer build --force "${app}.sif" "${app}.def"; then
        echo ""
        echo -e "${GREEN}✅ ${app} built successfully${NC}"

        # 파일 크기 확인
        if [ -f "${app}.sif" ]; then
            SIZE=$(du -h "${app}.sif" | cut -f1)
            echo "   Size: $SIZE"
        fi
    else
        echo ""
        echo -e "${RED}❌ ${app} build failed${NC}"
    fi

    cd "$SCRIPT_DIR"
    echo ""
done

# 결과 요약
echo ""
echo -e "${YELLOW}==================================="
echo "Build Summary"
echo -e "===================================${NC}"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for app in "${APPS[@]}"; do
    if [ -f "${app}/${app}.sif" ]; then
        SIZE=$(du -h "${app}/${app}.sif" | cut -f1)
        echo -e "${GREEN}✅ ${app}.sif${NC} ($SIZE)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}❌ ${app}.sif (not built)${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "Total: ${SUCCESS_COUNT} success, ${FAIL_COUNT} failed"
echo ""

# 사용 방법 안내
if [ $SUCCESS_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Usage:${NC}"
    echo "  apptainer run gedit/gedit.sif"
    echo ""
    echo -e "${YELLOW}Or with environment variables:${NC}"
    echo "  apptainer run --env VNC_PORT=5901 gedit/gedit.sif"
    echo ""
fi

echo "==================================="
