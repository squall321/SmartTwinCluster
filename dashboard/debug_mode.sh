#!/bin/bash
# Mock/Production 모드 디버깅 스크립트

echo "=========================================="
echo "🔍 Mock/Production Mode 디버깅"
echo "=========================================="
echo ""

# 1. Backend 프로세스 환경변수 확인
echo "1. Backend 프로세스 환경변수:"
backend_pid=$(cat /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/.backend.pid 2>/dev/null)
if [ -n "$backend_pid" ]; then
    echo "Backend PID: $backend_pid"
    cat /proc/$backend_pid/environ 2>/dev/null | tr '\0' '\n' | grep MOCK_MODE
else
    echo "❌ Backend 실행 안됨"
fi
echo ""

# 2. API 모드 확인
echo "2. API 응답 모드:"
curl -s http://localhost:5010/api/nodes | jq -r '{"success": .success, "mode": .mode, "count": .count, "first_node": .nodes[0].name}' 2>/dev/null
echo ""

# 3. Backend 로그에서 MOCK_MODE 확인
echo "3. Backend 로그 (MOCK_MODE 관련):"
grep -i "running in\|mock_mode" /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/logs/backend.log | tail -5
echo ""

# 4. start_all.sh가 설정한 환경변수 확인
echo "4. start_all.sh 내용 확인:"
grep "export MOCK_MODE" /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/start_all.sh
echo ""

# 5. 어떤 스크립트로 시작했는지 확인
echo "5. 최근 실행된 스크립트:"
ls -lt /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/start_all*.sh | head -3
echo ""

echo "=========================================="
echo "✅ 디버깅 완료"
echo "=========================================="
