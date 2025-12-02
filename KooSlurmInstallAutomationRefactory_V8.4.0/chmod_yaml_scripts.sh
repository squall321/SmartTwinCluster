#!/bin/bash
# YAML 설정 관련 모든 스크립트에 실행 권한 부여

chmod +x configure_slurm_from_yaml.py
chmod +x configure_slurm_cgroup_v2_YAML.sh
chmod +x setup_yaml_config.sh
chmod +x patch_setup_cluster_full.sh
chmod +x quickstart_yaml_config.sh

echo "✅ 모든 YAML 설정 스크립트 실행 권한 부여 완료!"
echo ""
echo "📁 파일 목록:"
ls -lh configure_slurm_from_yaml.py \
      configure_slurm_cgroup_v2_YAML.sh \
      setup_yaml_config.sh \
      patch_setup_cluster_full.sh \
      quickstart_yaml_config.sh \
      YAML_CONFIG_GUIDE.md
