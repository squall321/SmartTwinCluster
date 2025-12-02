#!/bin/bash

echo "=========================================="
echo "🔄 Backend 최종 재시작"
echo "=========================================="
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# Backend 중지
echo "🛑 Backend 중지..."
./stop.sh
sleep 3

# Backend 시작
echo "🚀 Backend 시작..."
./start.sh
sleep 5

# 상태 확인
echo ""
echo "📊 서비스 상태:"
if curl -s http://localhost:5010/api/health >/dev/null 2>&1; then
    echo "✅ Backend: Running"
else
    echo "❌ Backend: Not running"
    exit 1
fi

echo ""
echo "🧪 API 테스트:"
echo ""
echo "1. /api/nodes 엔드포인트:"
curl -s http://localhost:5010/api/nodes | jq '{success, mode, count, sample_node: .nodes[0].name}'

echo ""
echo "2. 노드 목록:"
curl -s http://localhost:5010/api/nodes | jq -r '.nodes[] | "\(.name): \(.state)"'

echo ""
echo "=========================================="
echo "✅ Backend 재시작 완료!"
echo "✅ Frontend를 Hard Refresh (Ctrl+F5) 하세요"
echo "=========================================="
