#!/bin/bash
# 대시보드 백엔드(5010) 재시작 스크립트

echo "=========================================="
echo "🔄 Backend 재시작 (노드 관리 API 추가)"
echo "=========================================="
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# Backend 중지
echo "🛑 Backend 중지..."
./stop.sh
sleep 2

# Backend 시작
echo "🚀 Backend 시작..."
./start.sh
sleep 3

# 상태 확인
echo ""
echo "📊 서비스 상태:"
if curl -s http://localhost:5010/api/health >/dev/null 2>&1; then
    echo "✅ Backend: Running"
else
    echo "❌ Backend: Not running"
fi

echo ""
echo "🧪 노드 관리 API 테스트:"
echo ""
echo "1. 노드 목록 조회:"
curl -s http://localhost:5010/api/nodes | jq -r '.nodes[] | "\(.name): \(.state)"'

echo ""
echo "=========================================="
echo "✅ Backend 재시작 완료!"
echo "=========================================="
