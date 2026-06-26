#!/bin/bash
# scontrol reboot 명령 문법 수정 스크립트

echo "================================================================================"
echo "🔧 scontrol reboot 명령어 문법 수정"
echo "================================================================================"
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# 백업
cp node_management_api.py node_management_api.py.backup_syntax

# reboot 명령어 문법 수정
# 기존: [SCONTROL_PATH, 'reboot', node_name, f'reason={reason}']
# 수정: [SCONTROL_PATH, 'reboot', 'ASAP', f'reason={reason}', node_name]

sed -i "s/\[SCONTROL_PATH, 'reboot', node_name, f'reason={reason}'\]/[SCONTROL_PATH, 'reboot', 'ASAP', f'reason={reason}', node_name]/g" node_management_api.py

echo "✅ 수정 완료"
echo ""
echo "변경된 코드:"
grep -A 3 "scontrol.*reboot.*ASAP" node_management_api.py
echo ""

echo "🔄 백엔드 재시작 필요"
echo "  cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory"
echo "  ./stop_all.sh"
echo "  ./start_all.sh"
echo ""
