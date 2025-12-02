#!/bin/bash
################################################################################
# 한 번에 모든 정리 및 설정 작업 수행
################################################################################

set -e

# 색상
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   KooSlurmInstallAutomation 프로젝트 재구성              ║
║                                                          ║
║   레거시 정리 + 통합 설정을 한 번에 수행합니다           ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo -e "${YELLOW}이 스크립트는 다음 작업을 수행합니다:${NC}"
echo "  1. 레거시 파일 정리 (legacy/ 디렉토리로 이동)"
echo "  2. 실행 권한 설정"
echo "  3. 환경 설정 (가상환경 + 패키지 설치)"
echo ""
echo -e "${YELLOW}⚠ 주의: 일부 파일이 이동됩니다!${NC}"
echo ""
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  1단계: 실행 권한 설정${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

chmod +x setup.sh
chmod +x cleanup_legacy.sh
chmod +x pre_install_check.sh 2>/dev/null || true
chmod +x install_slurm.py 2>/dev/null || true
chmod +x generate_config.py 2>/dev/null || true
chmod +x validate_config.py 2>/dev/null || true
chmod +x test_connection.py 2>/dev/null || true
chmod +x view_performance_report.py 2>/dev/null || true
chmod +x run_tests.py 2>/dev/null || true

echo -e "${GREEN}✓${NC} 모든 스크립트에 실행 권한 설정 완료"

echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  2단계: 레거시 파일 정리${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

./cleanup_legacy.sh

echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  3단계: 환경 설정${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

./setup.sh

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║   🎉 프로젝트 재구성이 완료되었습니다!                     ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📋 변경 사항 요약:${NC}"
echo ""
echo "✅ 새로 추가된 파일:"
echo "   • setup.sh - 통합 설정 스크립트"
echo "   • QUICKSTART.md - 빠른 시작 가이드"
echo "   • REORGANIZATION_GUIDE.md - 재구성 가이드"
echo ""
echo "✅ 정리된 파일:"
echo "   • 7개의 중복 스크립트 → legacy/old_scripts/"
echo "   • 18개의 임시 문서 → legacy/old_docs/"
echo ""
echo "✅ 환경 설정:"
echo "   • Python 가상환경 생성 완료"
echo "   • 의존성 패키지 설치 완료"
echo "   • 실행 권한 설정 완료"
echo ""

echo -e "${BLUE}📖 다음 단계:${NC}"
echo ""
echo "1. 빠른 시작 가이드 확인"
echo -e "   ${YELLOW}cat QUICKSTART.md${NC}"
echo ""
echo "2. 재구성 가이드 확인 (선택사항)"
echo -e "   ${YELLOW}cat REORGANIZATION_GUIDE.md${NC}"
echo ""
echo "3. 가상환경 활성화"
echo -e "   ${YELLOW}source venv/bin/activate${NC}"
echo ""
echo "4. 설정 파일 준비"
echo -e "   ${YELLOW}cp examples/2node_example.yaml my_cluster.yaml${NC}"
echo -e "   ${YELLOW}vim my_cluster.yaml${NC}"
echo ""
echo "5. Slurm 설치 시작"
echo -e "   ${YELLOW}./install_slurm.py -c my_cluster.yaml${NC}"
echo ""

echo -e "${BLUE}💡 유용한 명령어:${NC}"
echo "   • 시스템 사전 점검: ./pre_install_check.sh"
echo "   • 설정 파일 검증: ./validate_config.py my_cluster.yaml"
echo "   • SSH 연결 테스트: ./test_connection.py my_cluster.yaml"
echo ""

echo "Happy Computing! 🚀"
echo ""
