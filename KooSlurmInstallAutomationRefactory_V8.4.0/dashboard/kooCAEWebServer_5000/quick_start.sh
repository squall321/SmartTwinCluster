#!/bin/bash
# quick_start.sh - 한 번에 서버 시작하고 테스트하기

echo "🚀 KooCAE 서버 빠른 시작 가이드"
echo "================================"

# 실행 권한 설정
chmod +x server_manager.sh
chmod +x check_all_features.py

# 서버 시작
echo "1️⃣ 서버 시작 중..."
./server_manager.sh start

if [ $? -eq 0 ]; then
    echo ""
    echo "2️⃣ 서버 연결 확인 (5초 대기)..."
    sleep 5
    
    ./server_manager.sh test
    
    echo ""
    echo "3️⃣ 종합 기능 테스트 실행..."
    python check_all_features.py
    
    echo ""
    echo "🎉 빠른 시작 완료!"
    echo ""
    echo "📋 다음 단계:"
    echo "  - 웹 브라우저에서 확인: http://localhost:5000"
    echo "  - 로그 보기: ./server_manager.sh logs"
    echo "  - 서버 중지: ./server_manager.sh stop"
    echo "  - 상태 확인: ./server_manager.sh status"
else
    echo "❌ 서버 시작 실패"
fi
