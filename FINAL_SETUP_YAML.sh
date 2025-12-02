#!/bin/bash
################################################################################
# YAML 설정 시스템 - 최종 설정 완료 스크립트
################################################################################

echo "================================================================================"
echo "🎉 YAML 기반 Slurm 설정 시스템 - 최종 설정"
echo "================================================================================"
echo ""

# 실행 권한 부여
echo "📝 실행 권한 부여 중..."
chmod +x configure_slurm_from_yaml.py
chmod +x configure_slurm_cgroup_v2_YAML.sh
chmod +x quickstart_yaml_config.sh
chmod +x patch_setup_cluster_full.sh
chmod +x YAML_CONFIG_SUMMARY.sh
chmod +x chmod_yaml_scripts.sh
chmod +x setup_yaml_all_in_one.sh

echo "  ✅ 모든 스크립트에 실행 권한 부여 완료!"
echo ""

# 파일 확인
echo "📁 생성된 파일 목록:"
echo "--------------------------------------------------------------------------------"
ls -lh configure_slurm_from_yaml.py \
      configure_slurm_cgroup_v2_YAML.sh \
      quickstart_yaml_config.sh \
      patch_setup_cluster_full.sh \
      YAML_CONFIG_SUMMARY.sh \
      setup_yaml_all_in_one.sh \
      YAML_CONFIG_GUIDE.md \
      YAML_CONFIG_README.md 2>/dev/null | grep -E "^-" | awk '{print "  " $9 " (" $5 ")"}'

echo ""
echo "================================================================================"
echo "✅ 설정 완료!"
echo "================================================================================"
echo ""

echo "🚀 다음 단계를 선택하세요:"
echo ""
echo "1. 빠른 시작 (권장)"
echo "   ./quickstart_yaml_config.sh"
echo ""
echo "2. 올인원 메뉴"
echo "   ./setup_yaml_all_in_one.sh"
echo ""
echo "3. Python 직접 실행"
echo "   python3 configure_slurm_from_yaml.py"
echo ""
echo "4. 전체 가이드 보기"
echo "   cat YAML_CONFIG_GUIDE.md"
echo ""
echo "5. 요약 정보 보기"
echo "   ./YAML_CONFIG_SUMMARY.sh"
echo ""
echo "================================================================================"
echo ""

# YAML 파일 확인
if [ -f "my_cluster.yaml" ]; then
    echo "✅ my_cluster.yaml 파일 발견!"
    echo ""
    
    # RebootProgram 설정 확인
    if grep -q "reboot_program:" my_cluster.yaml; then
        REBOOT_PROGRAM=$(grep "reboot_program:" my_cluster.yaml | awk '{print $2}')
        echo "✅ RebootProgram 설정: $REBOOT_PROGRAM"
    else
        echo "⚠️  RebootProgram 설정이 없습니다."
        echo ""
        echo "💡 my_cluster.yaml에 추가하세요:"
        echo "   slurm_config:"
        echo "     reboot_program: /sbin/reboot"
    fi
else
    echo "⚠️  my_cluster.yaml 파일이 없습니다!"
    echo ""
    echo "💡 생성 방법:"
    echo "   cp examples/2node_example.yaml my_cluster.yaml"
    echo "   vim my_cluster.yaml"
fi

echo ""
echo "================================================================================"
