#!/bin/bash
# 실시간 API 응답 모드 확인 스크립트

echo "=========================================="
echo "🔍 실시간 API 응답 확인"
echo "=========================================="
echo ""

echo "1. /api/nodes 직접 호출:"
response=$(curl -s http://localhost:5010/api/nodes)
echo "$response" | jq '.'

echo ""
echo "2. mode 필드만 추출:"
mode=$(echo "$response" | jq -r '.mode')
echo "Mode: $mode"

echo ""
echo "3. 전체 요약:"
echo "$response" | jq '{success, mode, count, node_count: (.nodes | length), first_node: .nodes[0].name}'

echo ""
echo "=========================================="

if [ "$mode" = "production" ]; then
    echo "✅ API는 production 모드입니다!"
    echo ""
    echo "만약 브라우저에서 여전히 MOCK MODE로 표시된다면:"
    echo "  1. 브라우저 개발자 도구(F12) 열기"
    echo "  2. Console 탭에서 다음 확인:"
    echo "     [NodeManagement] API Response - Mode: production"
    echo ""
    echo "  3. 만약 Console에 production이 표시되는데도"
    echo "     Mode Badge가 MOCK MODE라면:"
    echo "     → React 상태 업데이트 문제"
    echo "     → 브라우저 완전 종료 후 다시 열기"
elif [ "$mode" = "mock" ]; then
    echo "❌ API가 mock 모드로 응답하고 있습니다!"
    echo ""
    echo "Backend가 MOCK_MODE=true로 실행 중입니다."
    echo "해결: ./stop_all.sh && ./start_all.sh"
else
    echo "⚠️  알 수 없는 모드: $mode"
fi

echo "=========================================="
