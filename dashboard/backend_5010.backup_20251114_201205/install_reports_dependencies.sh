#!/bin/bash

##############################################################################
# Reports 기능 의존성 설치 스크립트 (가상환경 세밀 관리)
# Python 버전 확인 및 호환성 검증 포함
##############################################################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "📦 Reports 기능 의존성 설치"
echo "=========================================="
echo ""

# ============================================
# Step 1: 가상환경 확인 및 검증
# ============================================
echo -e "${BLUE}[1/6] 가상환경 확인...${NC}"
echo ""

if [ ! -d "${SCRIPT_DIR}/venv" ]; then
    echo -e "${RED}❌ 가상환경이 없습니다!${NC}"
    echo ""
    echo "가상환경 생성 방법:"
    echo "  cd ${SCRIPT_DIR}"
    echo "  python3 -m venv venv"
    echo "  source venv/bin/activate"
    echo "  pip install --upgrade pip"
    echo "  pip install -r requirements.txt"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ 가상환경 발견: ${SCRIPT_DIR}/venv${NC}"
echo ""

# ============================================
# Step 2: 가상환경 활성화
# ============================================
echo -e "${BLUE}[2/6] 가상환경 활성화...${NC}"
echo ""

source "${SCRIPT_DIR}/venv/bin/activate"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 가상환경 활성화 실패${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 가상환경 활성화 완료${NC}"
echo ""

# ============================================
# Step 3: Python 환경 정보 출력
# ============================================
echo -e "${BLUE}[3/6] Python 환경 정보...${NC}"
echo ""

echo -e "${CYAN}Python 경로:${NC}"
which python
echo ""

echo -e "${CYAN}Python 버전:${NC}"
PYTHON_VERSION=$(python --version 2>&1)
echo "$PYTHON_VERSION"
echo ""

echo -e "${CYAN}pip 버전:${NC}"
pip --version
echo ""

echo -e "${CYAN}가상환경 위치:${NC}"
echo "$VIRTUAL_ENV"
echo ""

# Python 버전 파싱 (예: 3.12.11 -> 3.12)
PYTHON_MAJOR_MINOR=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo -e "${CYAN}Python 메이저.마이너 버전:${NC} $PYTHON_MAJOR_MINOR"
echo ""

# Python 버전 호환성 확인
echo -e "${CYAN}패키지 호환성 확인:${NC}"

# pandas 최소 요구사항: Python 3.9+
if python -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)"; then
    echo -e "  pandas (requires Python 3.9+): ${GREEN}✅ 호환${NC}"
else
    echo -e "  pandas (requires Python 3.9+): ${RED}❌ Python 3.9 이상 필요${NC}"
    deactivate
    exit 1
fi

# numpy 최소 요구사항: Python 3.9+
if python -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)"; then
    echo -e "  numpy (requires Python 3.9+): ${GREEN}✅ 호환${NC}"
else
    echo -e "  numpy (requires Python 3.9+): ${RED}❌ Python 3.9 이상 필요${NC}"
    deactivate
    exit 1
fi

echo ""

# ============================================
# Step 4: pip 업그레이드 (선택적)
# ============================================
echo -e "${BLUE}[4/6] pip 업그레이드...${NC}"
echo ""

CURRENT_PIP=$(pip --version | grep -oP '\d+\.\d+\.\d+' | head -1)
echo "현재 pip 버전: $CURRENT_PIP"

# pip 업그레이드 (조용히)
pip install --upgrade pip --quiet

NEW_PIP=$(pip --version | grep -oP '\d+\.\d+\.\d+' | head -1)
if [ "$CURRENT_PIP" != "$NEW_PIP" ]; then
    echo -e "${GREEN}✅ pip 업그레이드: $CURRENT_PIP → $NEW_PIP${NC}"
else
    echo -e "${GREEN}✅ pip 최신 버전 사용 중${NC}"
fi

echo ""

# ============================================
# Step 5: 패키지 설치
# ============================================
echo -e "${BLUE}[5/6] Reports 패키지 설치...${NC}"
echo ""

# Python 버전별 최적 패키지 버전 선택
if python -c "import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)"; then
    # Python 3.12+
    echo -e "${CYAN}Python 3.12+ 감지 - 최신 버전 사용${NC}"
    packages=(
        "pandas>=2.1.0"
        "numpy>=1.26.0"
        "openpyxl>=3.1.0"
        "reportlab>=4.0.0"
    )
elif python -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)"; then
    # Python 3.10-3.11
    echo -e "${CYAN}Python 3.10-3.11 감지 - 안정 버전 사용${NC}"
    packages=(
        "pandas>=2.0.0,<2.2.0"
        "numpy>=1.24.0,<1.27.0"
        "openpyxl>=3.1.0"
        "reportlab>=4.0.0"
    )
else
    # Python 3.9
    echo -e "${CYAN}Python 3.9 감지 - 호환 버전 사용${NC}"
    packages=(
        "pandas>=2.0.0,<2.1.0"
        "numpy>=1.24.0,<1.25.0"
        "openpyxl>=3.1.0"
        "reportlab>=4.0.0"
    )
fi

echo ""

INSTALL_SUCCESS=0
INSTALL_FAILED=0

for package in "${packages[@]}"; do
    package_name=$(echo "$package" | cut -d'>' -f1 | cut -d'=' -f1 | cut -d'<' -f1)
    echo -e "${BLUE}설치 중: $package${NC}"
    
    # 설치 시도
    if pip install "$package" --quiet 2>/dev/null; then
        # 설치된 버전 확인
        installed_version=$(pip show "$package_name" 2>/dev/null | grep Version | cut -d' ' -f2)
        echo -e "  ${GREEN}✅ 성공${NC} (v$installed_version)"
        INSTALL_SUCCESS=$((INSTALL_SUCCESS + 1))
    else
        echo -e "  ${RED}❌ 실패${NC}"
        echo ""
        echo "상세 에러:"
        pip install "$package" 2>&1 | tail -10
        echo ""
        INSTALL_FAILED=$((INSTALL_FAILED + 1))
    fi
    echo ""
done

if [ $INSTALL_FAILED -gt 0 ]; then
    echo -e "${RED}❌ 일부 패키지 설치 실패: $INSTALL_FAILED개${NC}"
    echo ""
    deactivate
    exit 1
fi

# ============================================
# Step 6: 설치 검증
# ============================================
echo -e "${BLUE}[6/6] 설치 검증...${NC}"
echo ""

echo "=========================================="
echo -e "${CYAN}패키지 Import 테스트${NC}"
echo "=========================================="
echo ""

modules=("pandas" "numpy" "openpyxl" "reportlab")
IMPORT_SUCCESS=0
IMPORT_FAILED=0

for module in "${modules[@]}"; do
    echo -n "테스트: $module ... "
    
    if python -c "import $module" 2>/dev/null; then
        version=$(python -c "import $module; print($module.__version__)" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✅ OK${NC} (v$version)"
        IMPORT_SUCCESS=$((IMPORT_SUCCESS + 1))
    else
        echo -e "${RED}❌ 실패${NC}"
        IMPORT_FAILED=$((IMPORT_FAILED + 1))
    fi
done

echo ""

if [ $IMPORT_FAILED -gt 0 ]; then
    echo -e "${RED}❌ Import 실패: $IMPORT_FAILED개${NC}"
    echo ""
    deactivate
    exit 1
fi

# reports_api.py Import 테스트
echo "=========================================="
echo -e "${CYAN}reports_api.py Import 테스트${NC}"
echo "=========================================="
echo ""

if python -c "from reports_api import reports_bp; print('✅ reports_api import 성공')" 2>/dev/null; then
    echo -e "${GREEN}✅ reports_api.py import 성공!${NC}"
    echo ""
else
    echo -e "${RED}❌ reports_api.py import 실패${NC}"
    echo ""
    echo "상세 에러:"
    python -c "from reports_api import reports_bp" 2>&1
    echo ""
    deactivate
    exit 1
fi

# ============================================
# 최종 요약
# ============================================
echo "=========================================="
echo -e "${GREEN}✨ 설치 완료!${NC}"
echo "=========================================="
echo ""

echo -e "${CYAN}환경 정보:${NC}"
echo "  가상환경: ${SCRIPT_DIR}/venv"
echo "  Python: $PYTHON_VERSION"
echo "  Python 버전: $PYTHON_MAJOR_MINOR"
echo ""

echo -e "${CYAN}설치된 패키지:${NC}"
pip list | grep -E "pandas|numpy|openpyxl|reportlab" | while read line; do
    echo "  $line"
done

echo ""
echo -e "${CYAN}패키지 상세 정보:${NC}"
for module in "${modules[@]}"; do
    version=$(python -c "import $module; print($module.__version__)" 2>/dev/null)
    location=$(python -c "import $module; print($module.__file__)" 2>/dev/null | sed "s|${SCRIPT_DIR}/venv|<venv>|")
    echo "  $module v$version"
    echo "    위치: $location"
done

deactivate

echo ""
echo "=========================================="
echo -e "${GREEN}🎉 모든 검증 완료!${NC}"
echo "=========================================="
echo ""

echo -e "${CYAN}다음 단계:${NC}"
echo "  1. Backend 재시작:"
echo "     cd ${SCRIPT_DIR}/.."
echo "     ./restart_backend.sh"
echo ""
echo "  2. API 테스트:"
echo "     curl http://localhost:5010/api/reports/overview | jq"
echo ""
echo "  3. 전체 테스트:"
echo "     ./test_reports_api.sh"
echo ""
