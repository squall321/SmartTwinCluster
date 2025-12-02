#!/bin/bash
################################################################################
# 빠른 실행 권한 설정 스크립트
# 모든 실행 파일에 권한 부여
################################################################################

echo "🔧 실행 권한 설정 중..."

# 새로운 통합 스크립트들
chmod +x reorganize.sh 2>/dev/null && echo "✓ reorganize.sh"
chmod +x setup.sh 2>/dev/null && echo "✓ setup.sh"
chmod +x cleanup_legacy.sh 2>/dev/null && echo "✓ cleanup_legacy.sh"

# 기존 스크립트들
chmod +x pre_install_check.sh 2>/dev/null && echo "✓ pre_install_check.sh"

# Python 스크립트들
chmod +x install_slurm.py 2>/dev/null && echo "✓ install_slurm.py"
chmod +x generate_config.py 2>/dev/null && echo "✓ generate_config.py"
chmod +x validate_config.py 2>/dev/null && echo "✓ validate_config.py"
chmod +x test_connection.py 2>/dev/null && echo "✓ test_connection.py"
chmod +x view_performance_report.py 2>/dev/null && echo "✓ view_performance_report.py"
chmod +x run_tests.py 2>/dev/null && echo "✓ run_tests.py"

echo ""
echo "✅ 모든 실행 권한이 설정되었습니다!"
echo ""
echo "다음 단계:"
echo "  ./reorganize.sh  # 프로젝트 재구성 및 환경 설정"
echo ""
