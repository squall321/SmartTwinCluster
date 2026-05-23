#!/bin/bash
################################################################################
# YAML 기반 Slurm 설정 - 빠른 시작 스크립트
################################################################################

echo "================================================================================"
echo "🚀 YAML 기반 Slurm 설정 - 빠른 시작"
echo "================================================================================"
echo ""

# 1. 실행 권한 부여
echo "📝 Step 1/4: 실행 권한 부여..."
chmod +x configure_slurm_from_yaml.py
chmod +x configure_slurm_cgroup_v2_YAML.sh
chmod +x setup_yaml_config.sh
chmod +x patch_setup_cluster_full.sh
echo "  ✅ 권한 부여 완료"
echo ""

# 2. YAML 파일 확인
echo "📝 Step 2/4: YAML 파일 확인..."
if [ ! -f "my_multihead_cluster.yaml" ]; then
    echo "  ⚠️  my_multihead_cluster.yaml이 없습니다!"
    echo "  💡 예시 파일을 복사하세요:"
    echo "     cp examples/2node_example.yaml my_multihead_cluster.yaml"
    echo ""
    exit 1
else
    echo "  ✅ my_multihead_cluster.yaml 존재"
    
    # reboot_program 설정 확인
    if grep -q "reboot_program:" my_multihead_cluster.yaml; then
        REBOOT_PROGRAM=$(grep "reboot_program:" my_multihead_cluster.yaml | awk '{print $2}')
        echo "  ✅ RebootProgram 설정 발견: $REBOOT_PROGRAM"
    else
        echo "  ⚠️  reboot_program 설정이 없습니다!"
        echo "  💡 my_multihead_cluster.yaml에 추가하세요:"
        echo "     slurm_config:"
        echo "       reboot_program: /sbin/reboot"
    fi
fi
echo ""

# 3. 미리보기
echo "📝 Step 3/4: 설정 미리보기 (처음 50줄)..."
echo "--------------------------------------------------------------------------------"
python3 configure_slurm_from_yaml.py --dry-run 2>/dev/null | head -50
echo "..."
echo "--------------------------------------------------------------------------------"
echo ""

# 4. 사용자 확인
echo "📝 Step 4/4: 실제 생성 여부 확인..."
read -p "지금 설정 파일을 생성하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🚀 설정 파일 생성 중..."
    echo ""
    
    python3 configure_slurm_from_yaml.py
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "================================================================================"
        echo "✅ 완료!"
        echo "================================================================================"
        echo ""
        echo "📋 다음 단계:"
        echo ""
        echo "1. 설정 확인:"
        echo "   cat /usr/local/slurm/etc/slurm.conf"
        echo "   grep RebootProgram /usr/local/slurm/etc/slurm.conf"
        echo ""
        echo "2. 계산 노드에 배포:"
        echo "   ./sync_config_to_nodes.sh"
        echo ""
        echo "3. Slurm 재시작:"
        echo "   sudo systemctl restart slurmctld"
        echo "   ssh node001 'sudo systemctl restart slurmd'"
        echo ""
        echo "4. 상태 확인:"
        echo "   sinfo"
        echo "   scontrol show config | grep RebootProgram"
        echo ""
    else
        echo ""
        echo "❌ 설정 파일 생성 실패!"
        echo ""
        echo "💡 수동 실행:"
        echo "   python3 configure_slurm_from_yaml.py"
        echo ""
    fi
else
    echo ""
    echo "⏭️  건너뜀"
    echo ""
    echo "💡 나중에 실행하려면:"
    echo "   python3 configure_slurm_from_yaml.py"
    echo ""
fi

echo "================================================================================"
