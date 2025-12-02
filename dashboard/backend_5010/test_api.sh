#!/bin/bash

echo "=========================================="
echo "🔍 Backend API 테스트"
echo "=========================================="
echo ""

# Backend 상태 확인
echo "1. Backend 프로세스 확인:"
if pgrep -f "python.*app.py" > /dev/null; then
    echo "✅ Backend 실행 중 (PID: $(pgrep -f 'python.*app.py'))"
else
    echo "❌ Backend 실행 안됨"
fi
echo ""

# Health API 테스트
echo "2. Health API 테스트:"
curl -s http://localhost:5010/api/health/status > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Health API 응답"
else
    echo "❌ Health API 실패"
fi
echo ""

# Nodes API 테스트
echo "3. Nodes API 테스트:"
echo "curl http://localhost:5010/api/nodes"
response=$(curl -s http://localhost:5010/api/nodes)
if [ -n "$response" ]; then
    echo "✅ Nodes API 응답:"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
else
    echo "❌ Nodes API 응답 없음"
fi
echo ""

# Backend 로그 확인
echo "4. Backend 로그 (마지막 20줄):"
if [ -f logs/backend.log ]; then
    tail -20 logs/backend.log
else
    echo "⚠️  로그 파일 없음"
fi
echo ""

echo "=========================================="
echo "✅ 테스트 완료"
echo "=========================================="
