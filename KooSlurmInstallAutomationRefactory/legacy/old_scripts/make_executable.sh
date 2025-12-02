#!/bin/bash
"""
스크립트 실행 권한 설정
"""

echo "🔧 실행 권한 설정 중..."

# Python 스크립트들에 실행 권한 부여
chmod +x install_slurm.py
chmod +x validate_config.py
chmod +x test_connection.py
chmod +x generate_config.py
chmod +x run_tests.py
chmod +x config_generator.py
chmod +x view_performance_report.py

# 기존 스크립트들도 실행 권한 확인
chmod +x setup_venv.sh
chmod +x main.py

echo "✅ 모든 스크립트에 실행 권한이 설정되었습니다!"

echo ""
echo "📋 사용 가능한 명령어들:"
echo "  ./generate_config.py          - 설정 파일 생성"
echo "  ./validate_config.py <file>   - 설정 파일 검증"
echo "  ./test_connection.py <file>   - SSH 연결 테스트"
echo "  ./install_slurm.py -c <file>  - Slurm 설치"
echo "  ./view_performance_report.py  - 성능 리포트 보기"
echo "  ./run_tests.py                - 단위 테스트 실행"
