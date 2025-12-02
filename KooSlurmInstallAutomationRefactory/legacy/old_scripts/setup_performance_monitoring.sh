#!/bin/bash
# 성능 모니터링 기능 설정 스크립트

echo "🚀 성능 모니터링 기능 설정 시작..."
echo ""

# 1. 실행 권한 설정
echo "📝 실행 권한 설정 중..."
chmod +x view_performance_report.py
chmod +x test_performance_monitor.py
echo "✅ 실행 권한 설정 완료"
echo ""

# 2. 성능 로그 디렉토리 생성
echo "📁 성능 로그 디렉토리 생성 중..."
mkdir -p performance_logs
chmod 755 performance_logs
echo "✅ performance_logs/ 디렉토리 생성 완료"
echo ""

# 3. psutil 설치 확인
echo "🔍 psutil 라이브러리 확인 중..."
if python3 -c "import psutil" 2>/dev/null; then
    echo "✅ psutil 이미 설치됨"
else
    echo "⚠️  psutil 미설치"
    echo "   설치 방법: pip install psutil>=5.9.0"
    echo "   또는: pip install -r requirements.txt"
fi
echo ""

# 4. 테스트 실행 (선택)
read -p "성능 모니터링 테스트를 실행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🧪 성능 모니터링 테스트 실행 중..."
    python3 test_performance_monitor.py
else
    echo "⏭️  테스트 건너뛰기"
fi
echo ""

# 5. 완료 메시지
echo "=" * 60
echo "✅ 성능 모니터링 기능 설정 완료!"
echo "=" * 60
echo ""
echo "📚 다음 단계:"
echo "  1. 테스트 실행:"
echo "     python3 test_performance_monitor.py"
echo ""
echo "  2. 실제 사용:"
echo "     ./install_slurm.py -c config.yaml --stage all"
echo ""
echo "  3. 리포트 확인:"
echo "     ./view_performance_report.py"
echo ""
echo "  4. 상세 문서:"
echo "     cat docs/PERFORMANCE_MONITORING.md"
echo ""
echo "Happy Monitoring! 📊🚀"
