#!/bin/bash
# setup_server_scripts.sh - 서버 관리 스크립트들 권한 설정

echo "🔧 서버 관리 스크립트 설정 중..."

# 실행 권한 부여
chmod +x server_manager.sh
chmod +x quick_start.sh
chmod +x check_all_features.py
chmod +x simple_test.sh
chmod +x quick_test.sh

echo "✅ 실행 권한 설정 완료!"
echo ""
echo "🚀 사용 가능한 명령어:"
echo ""
echo "📋 기본 서버 관리:"
echo "  ./server_manager.sh start     # 서버 시작"
echo "  ./server_manager.sh stop      # 서버 중지"  
echo "  ./server_manager.sh status    # 상태 확인"
echo "  ./server_manager.sh logs      # 로그 보기"
echo "  ./server_manager.sh test      # 연결 테스트"
echo ""
echo "⚡ 빠른 시작:"
echo "  ./quick_start.sh              # 서버 시작 + 자동 테스트"
echo ""
echo "🧪 테스트 도구들:"
echo "  python check_all_features.py  # 종합 기능 테스트"
echo "  ./simple_test.sh              # 간단한 연결 테스트"
echo "  python test_job_templates.py  # 템플릿 시스템 테스트"
echo ""
echo "🌟 추천 시작 방법:"
echo "  1. ./quick_start.sh           # 처음 사용 시"
echo "  2. ./server_manager.sh start  # 일반 사용 시"
