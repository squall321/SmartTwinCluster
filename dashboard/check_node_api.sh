#!/bin/bash

echo "=========================================="
echo "🔍 Node Management API 응답 확인"
echo "=========================================="
echo ""

echo "1. /api/nodes API 응답:"
curl -s http://localhost:5010/api/nodes | jq '{success: .success, mode: .mode, count: .count, nodes: [.nodes[] | .name]}'

echo ""
echo "2. /api/health/status API 응답:"
curl -s http://localhost:5010/api/health/status | jq '{success: .success, overall_status: .overall_status, mode: .mode}'

echo ""
echo "3. Backend 로그에서 MOCK_MODE 확인:"
grep "Running in" /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/logs/backend.log | tail -1

echo ""
echo "4. Backend 프로세스 환경변수:"
backend_pid=$(cat /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/.backend.pid 2>/dev/null)
if [ -n "$backend_pid" ]; then
    echo "MOCK_MODE=$(cat /proc/$backend_pid/environ 2>/dev/null | tr '\0' '\n' | grep MOCK_MODE)"
fi

echo ""
echo "=========================================="
