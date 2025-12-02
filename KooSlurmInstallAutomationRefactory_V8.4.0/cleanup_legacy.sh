#!/bin/bash
################################################################################
# 레거시 파일 정리 스크립트
# 중복되거나 더 이상 사용하지 않는 파일들을 legacy 디렉토리로 이동
################################################################################

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          레거시 파일 정리 스크립트                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# 백업 확인
echo -e "${YELLOW}⚠ 주의: 이 스크립트는 파일들을 legacy/ 디렉토리로 이동합니다.${NC}"
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
echo -e "${BLUE}1. 디렉토리 생성${NC}"
echo "────────────────────────────────────────"

# 레거시 디렉토리 생성
mkdir -p legacy/old_scripts
mkdir -p legacy/old_docs
mkdir -p legacy/old_configs

echo -e "${GREEN}✓${NC} legacy/old_scripts/"
echo -e "${GREEN}✓${NC} legacy/old_docs/"
echo -e "${GREEN}✓${NC} legacy/old_configs/"

echo ""
echo -e "${BLUE}2. 중복 스크립트 정리${NC}"
echo "────────────────────────────────────────"

# setup.sh로 통합되므로 이동
scripts_to_move=(
    "make_executable.sh"
    "make_scripts_executable.sh"
    "setup_venv.sh"
    "setup_dashboard_permissions.sh"
    "setup_performance_monitoring.sh"
)

for script in "${scripts_to_move[@]}"; do
    if [ -f "$script" ]; then
        mv "$script" legacy/old_scripts/
        echo -e "${GREEN}✓${NC} $script → legacy/old_scripts/"
    fi
done

# 검증 스크립트들 (기능이 메인 스크립트에 통합됨)
verify_scripts=(
    "verify_fixes.sh"
    "update_configs.sh"
)

for script in "${verify_scripts[@]}"; do
    if [ -f "$script" ]; then
        mv "$script" legacy/old_scripts/
        echo -e "${GREEN}✓${NC} $script → legacy/old_scripts/"
    fi
done

echo ""
echo -e "${BLUE}3. 중복 문서 정리${NC}"
echo "────────────────────────────────────────"

# 개발 과정에서 생성된 임시 문서들
docs_to_move=(
    "ALL_IMPROVEMENTS_COMPLETE.md"
    "BUGFIX_REPORT.md"
    "CHECKLIST.md"
    "CHECKLIST_COMPLETE.md"
    "COMPREHENSIVE_FIXES_REPORT.md"
    "FINAL_FIXES_SUMMARY.md"
    "FINAL_SUMMARY.md"
    "FIXES_REPORT.md"
    "FUNCTIONALITY_VERIFICATION.md"
    "IMPLEMENTATION_COMPLETE.md"
    "INTEGRATION_GUIDE.md"
    "PERFORMANCE_UPDATE.md"
    "PHASE1_COMPLETE.md"
    "PHASE2_COMPLETE.md"
    "QUICKSTART_PHASE1.md"
    "README_UPDATED.md"
    "SUMMARY.md"
    "UPDATES.md"
)

for doc in "${docs_to_move[@]}"; do
    if [ -f "$doc" ]; then
        mv "$doc" legacy/old_docs/
        echo -e "${GREEN}✓${NC} $doc → legacy/old_docs/"
    fi
done

echo ""
echo -e "${BLUE}4. 레거시 README 생성${NC}"
echo "────────────────────────────────────────"

cat > legacy/README.md << 'EOF'
# Legacy Files

이 디렉토리에는 더 이상 사용하지 않는 레거시 파일들이 보관되어 있습니다.

## 디렉토리 구조

- **old_scripts/**: 통합되거나 대체된 구버전 스크립트들
- **old_docs/**: 개발 과정에서 생성된 임시 문서들
- **old_configs/**: 사용하지 않는 구버전 설정 파일들

## 파일별 설명

### old_scripts/

| 파일명 | 대체된 기능 | 비고 |
|--------|------------|------|
| make_executable.sh | setup.sh | 통합됨 |
| make_scripts_executable.sh | setup.sh | 통합됨 |
| setup_venv.sh | setup.sh | 통합됨 |
| setup_dashboard_permissions.sh | setup.sh | 통합됨 |
| setup_performance_monitoring.sh | setup.sh | 통합됨 |
| verify_fixes.sh | validate_config.py | 기능 통합 |
| update_configs.sh | 자동 처리 | 더 이상 불필요 |

### old_docs/

개발 과정에서 생성된 체크리스트, 리포트, 요약 문서들입니다.
최종 문서는 다음과 같습니다:

- **README.md**: 전체 프로젝트 문서
- **QUICKSTART.md**: 빠른 시작 가이드
- **docs/**: 상세 기술 문서

## 복원이 필요한 경우

```bash
# 특정 파일 복원
cp legacy/old_scripts/파일명 ./

# 전체 복원 (권장하지 않음)
cp -r legacy/old_scripts/* ./
```

## 삭제 시점

이 파일들은 다음 마일스톤 이후 완전히 삭제될 예정입니다:
- v2.0.0 릴리스 이후
- 3개월간 이슈가 없는 경우

---

마지막 업데이트: $(date +%Y-%m-%d)
EOF

echo -e "${GREEN}✓${NC} legacy/README.md 생성"

echo ""
echo -e "${BLUE}5. 정리 완료 요약${NC}"
echo "────────────────────────────────────────"

# 통계
script_count=$(ls -1 legacy/old_scripts/ 2>/dev/null | wc -l)
doc_count=$(ls -1 legacy/old_docs/ 2>/dev/null | wc -l)

echo -e "${GREEN}✓${NC} 이동된 스크립트: ${script_count}개"
echo -e "${GREEN}✓${NC} 이동된 문서: ${doc_count}개"
echo ""

echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║   ✅ 레거시 파일 정리가 완료되었습니다!                    ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📁 현재 프로젝트 구조:${NC}"
echo ""
echo "KooSlurmInstallAutomation/"
echo "├── 📝 주요 실행 파일"
echo "│   ├── setup.sh                  ← 통합 설정 스크립트 (새로 추가!)"
echo "│   ├── install_slurm.py          ← Slurm 설치"
echo "│   ├── generate_config.py        ← 설정 생성"
echo "│   ├── validate_config.py        ← 설정 검증"
echo "│   ├── test_connection.py        ← SSH 테스트"
echo "│   └── pre_install_check.sh      ← 사전 점검"
echo "├── 📚 문서"
echo "│   ├── README.md                 ← 전체 문서"
echo "│   ├── QUICKSTART.md             ← 빠른 시작 (새로 추가!)"
echo "│   └── docs/                     ← 상세 문서"
echo "├── 📦 소스 코드"
echo "│   └── src/                      ← Python 모듈"
echo "├── 📋 설정 및 예시"
echo "│   ├── templates/                ← 설정 템플릿"
echo "│   └── examples/                 ← 예시 설정"
echo "└── 🗄️  레거시"
echo "    └── legacy/                   ← 구버전 파일 (보관용)"
echo ""

echo -e "${YELLOW}💡 다음 단계:${NC}"
echo "  1. 새로운 통합 스크립트 사용"
echo "     ./setup.sh"
echo ""
echo "  2. 빠른 시작 가이드 확인"
echo "     cat QUICKSTART.md"
echo ""
echo "  3. 기존 작업 계속"
echo "     source venv/bin/activate"
echo "     ./install_slurm.py -c my_cluster.yaml"
echo ""

echo "Happy Computing! 🚀"
echo ""
