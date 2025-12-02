#!/bin/bash

echo "=========================================="
echo "🔍 Apply Configuration 실시간 디버깅"
echo "=========================================="
echo ""
echo "이 터미널에서 Backend 로그를 실시간으로 모니터링합니다."
echo ""
echo "📝 테스트 방법:"
echo "   1. 브라우저에서 Cluster Management 열기"
echo "   2. 그룹 설정 변경 (아무거나)"
echo "   3. Apply Configuration 버튼 클릭"
echo "   4. 이 터미널에서 로그 확인"
echo ""
echo "----------------------------------------"
echo "실시간 로그 시작..."
echo "----------------------------------------"
echo ""

# Clear log markers
LOG_FILE="/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/backend.log"

# Add marker
echo "" >> "$LOG_FILE"
echo "=== DEBUG START $(date) ===" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Tail with grep for relevant lines
tail -f "$LOG_FILE" | grep --line-buffered -E "(apply|Apply|Production|Mock|🚀|❌|✅|ERROR|Error|POST /api/slurm|Groups:|Calling|Results:)"
