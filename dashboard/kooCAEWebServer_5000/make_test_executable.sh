#!/bin/bash
# make_test_executable.sh - 테스트 스크립트들 실행 권한 부여

echo "🔧 테스트 스크립트 실행 권한 설정..."

chmod +x quick_test.sh
chmod +x simple_test.sh
chmod +x check_all_features.py
chmod +x test_job_templates.py

echo "✅ 실행 권한 설정 완료!"
echo ""
echo "📋 사용 가능한 테스트 스크립트:"
echo "  ./simple_test.sh      - 간단한 연결 테스트"
echo "  ./quick_test.sh       - 빠른 기능 테스트"
echo "  ./check_all_features.py - 종합 기능 테스트"
echo "  ./test_job_templates.py - 템플릿 시스템 상세 테스트"
