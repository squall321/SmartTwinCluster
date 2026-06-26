#!/bin/bash
# 노드 관리 API 디버그 스크립트

echo "=========================================="
echo "🔍 Node Management API 디버그"
echo "=========================================="
echo ""

# 1. Backend 프로세스 확인
echo "1. Backend 프로세스:"
ps aux | grep "python.*app.py" | grep -v grep
echo ""

# 2. API 직접 테스트
echo "2. GET /api/nodes 테스트:"
response=$(curl -s -w "\n%{http_code}" http://localhost:5010/api/nodes)
http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | head -n -1)

echo "HTTP Status: $http_code"
echo "Response:"
echo "$body" | jq '.' 2>/dev/null || echo "$body"
echo ""

# 3. Health Check
echo "3. GET /api/health 테스트:"
curl -s http://localhost:5010/api/health | jq '.success, .timestamp' 2>/dev/null
echo ""

# 4. API 목록 확인
echo "4. Blueprint 등록 확인 (로그에서):"
grep -i "node management" /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/logs/backend.log | tail -3
echo ""

# 5. 실시간 로그 (마지막 10줄)
echo "5. 최근 Backend 로그:"
tail -10 /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/logs/backend.log
echo ""

echo "=========================================="
echo "✅ 디버그 완료"
echo "=========================================="
