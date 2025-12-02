#!/bin/bash

echo "================================================================================"
echo "🔧 백엔드 API에서 sudo 제거"
echo "================================================================================"
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# 백업
cp node_management_api.py node_management_api.py.backup_nosudo

# reboot_node 함수에서 use_sudo=True를 제거
sed -i 's/use_sudo=True  # 🔧 sudo 권한 사용/use_sudo=False  # 🔧 sudo 제거/g' node_management_api.py

echo "✅ 수정 완료"
echo ""
echo "변경 사항:"
grep -A 2 "use_sudo" node_management_api.py | grep -v "def run_slurm_command"
echo ""

echo "🔄 백엔드 재시작 필요"
echo "  cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory"
echo "  ./stop_all.sh"
echo "  ./start_all.sh"
echo ""
