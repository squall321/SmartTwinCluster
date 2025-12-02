#!/bin/bash

##############################################################################
# Reports 고도화 기능 설치 스크립트
# PDF/Excel 생성을 위한 추가 패키지 설치
##############################################################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "📦 Reports 고도화 패키지 설치"
echo "PDF/Excel 생성 기능"
echo "=========================================="
echo ""

# 가상환경 확인
if [ ! -d "${SCRIPT_DIR}/venv" ]; then
    echo -e "${RED}❌ 가상환경이 없습니다!${NC}"
    exit 1
fi

echo -e "${BLUE}가상환경 활성화...${NC}"
source "${SCRIPT_DIR}/venv/bin/activate"

echo ""
echo -e "${CYAN}Python: $(python --version)${NC}"
echo -e "${CYAN}경로: $(which python)${NC}"
echo ""

# 패키지 설치
echo "=========================================="
echo -e "${BLUE}추가 패키지 설치...${NC}"
echo "=========================================="
echo ""

packages=(
    "reportlab>=4.0.0"
    "Pillow>=10.0.0"
    "matplotlib>=3.7.0"
)

INSTALL_SUCCESS=0
INSTALL_FAILED=0

for package in "${packages[@]}"; do
    package_name=$(echo "$package" | cut -d'>' -f1 | cut -d'=' -f1)
    echo -e "${BLUE}설치 중: $package${NC}"
    
    if pip install "$package" --quiet 2>/dev/null; then
        installed_version=$(pip show "$package_name" 2>/dev/null | grep Version | cut -d' ' -f2)
        echo -e "  ${GREEN}✅ 성공${NC} (v$installed_version)"
        INSTALL_SUCCESS=$((INSTALL_SUCCESS + 1))
    else
        echo -e "  ${RED}❌ 실패${NC}"
        INSTALL_FAILED=$((INSTALL_FAILED + 1))
    fi
    echo ""
done

if [ $INSTALL_FAILED -gt 0 ]; then
    echo -e "${RED}❌ 일부 패키지 설치 실패${NC}"
    deactivate
    exit 1
fi

# 검증
echo "=========================================="
echo -e "${BLUE}설치 검증...${NC}"
echo "=========================================="
echo ""

modules=("reportlab" "PIL" "matplotlib")
module_names=("reportlab" "Pillow" "matplotlib")

for i in "${!modules[@]}"; do
    module="${modules[$i]}"
    name="${module_names[$i]}"
    
    echo -n "테스트: $name ... "
    
    if python -c "import $module" 2>/dev/null; then
        if [ "$module" = "PIL" ]; then
            version=$(python -c "import PIL; print(PIL.__version__)" 2>/dev/null || echo "unknown")
        else
            version=$(python -c "import $module; print($module.__version__)" 2>/dev/null || echo "unknown")
        fi
        echo -e "${GREEN}✅ OK${NC} (v$version)"
    else
        echo -e "${RED}❌ 실패${NC}"
    fi
done

echo ""

# report_exporter Import 테스트
echo "=========================================="
echo -e "${BLUE}report_exporter Import 테스트...${NC}"
echo "=========================================="
echo ""

if python -c "from report_exporter import report_exporter; print('✅ OK')" 2>/dev/null; then
    echo -e "${GREEN}✅ report_exporter import 성공!${NC}"
else
    echo -e "${RED}❌ report_exporter import 실패${NC}"
    echo ""
    echo "상세 에러:"
    python -c "from report_exporter import report_exporter"
    echo ""
    deactivate
    exit 1
fi

echo ""

deactivate

echo "=========================================="
echo -e "${GREEN}✨ 설치 완료!${NC}"
echo "=========================================="
echo ""

echo -e "${CYAN}설치된 패키지:${NC}"
source "${SCRIPT_DIR}/venv/bin/activate"
pip list | grep -E "reportlab|Pillow|matplotlib"
deactivate

echo ""
echo -e "${CYAN}다음 단계:${NC}"
echo "  1. Backend 재시작:"
echo "     cd ${SCRIPT_DIR}/.."
echo "     ./restart_backend.sh"
echo ""
echo "  2. PDF 다운로드 테스트:"
echo "     curl http://localhost:5010/api/reports/download/usage/pdf?period=week -o usage_report.pdf"
echo ""
echo "  3. Excel 다운로드 테스트:"
echo "     curl http://localhost:5010/api/reports/download/usage/excel?period=week -o usage_report.xlsx"
echo ""
