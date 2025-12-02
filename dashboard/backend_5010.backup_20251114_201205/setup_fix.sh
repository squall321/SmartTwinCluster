#!/bin/bash

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

echo "🔧 실행 권한 부여 중..."
chmod +x fix_node_api.sh
chmod +x restart_node_api.sh
echo "✅ 권한 부여 완료"
echo ""
echo "이제 실행하세요:"
echo "  ./fix_node_api.sh          # API 수정"
echo "  ./restart_node_api.sh      # 백엔드 재시작"
