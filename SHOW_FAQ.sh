#!/bin/bash
################################################################################
# 모든 권한 부여 및 FAQ 표시
################################################################################

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 모든 스크립트에 실행 권한 부여
chmod +x configure_slurm_from_yaml.py
chmod +x configure_slurm_cgroup_v2_YAML.sh
chmod +x quickstart_yaml_config.sh
chmod +x patch_setup_cluster_full.sh
chmod +x YAML_CONFIG_SUMMARY.sh
chmod +x chmod_yaml_scripts.sh
chmod +x setup_yaml_all_in_one.sh
chmod +x FINAL_SETUP_YAML.sh
chmod +x FAQ_YAML_CONFIG.sh

# FAQ 표시
./FAQ_YAML_CONFIG.sh
