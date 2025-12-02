#!/bin/bash
# 모든 새 스크립트에 실행 권한 부여

chmod +x /home/koopark/claude/KooSlurmInstallAutomation/fix_config.py
chmod +x /home/koopark/claude/KooSlurmInstallAutomation/install_mpi.py
chmod +x /home/koopark/claude/KooSlurmInstallAutomation/sync_apptainer_images.py
chmod +x /home/koopark/claude/KooSlurmInstallAutomation/manage_images.py
chmod +x /home/koopark/claude/KooSlurmInstallAutomation/setup_cluster_full.sh
chmod +x /home/koopark/claude/KooSlurmInstallAutomation/set_permissions.sh
chmod +x /home/koopark/claude/KooSlurmInstallAutomation/SUMMARY.sh
chmod +x /home/koopark/claude/KooSlurmInstallAutomation/job_templates/submit_mpi_apptainer.sh

echo "✅ 모든 스크립트에 실행 권한이 부여되었습니다!"
