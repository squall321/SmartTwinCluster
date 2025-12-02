#!/bin/bash
################################################################################
# YAML 기반 Slurm 설정 - 최종 요약 및 테스트
################################################################################

echo "================================================================================"
echo "🎉 YAML 기반 Slurm 설정 시스템 완성!"
echo "================================================================================"
echo ""

echo "📦 생성된 파일 목록:"
echo "--------------------------------------------------------------------------------"
echo ""
echo "1. 📝 configure_slurm_from_yaml.py"
echo "   - 메인 Python 스크립트"
echo "   - YAML에서 모든 설정을 읽어서 slurm.conf, cgroup.conf, systemd 서비스 파일 생성"
echo "   - RebootProgram, 노드, 파티션 모두 동적 생성"
echo ""
echo "2. 🔧 configure_slurm_cgroup_v2_YAML.sh"
echo "   - Bash 래퍼 스크립트"
echo "   - Python 스크립트를 간편하게 실행"
echo ""
echo "3. ⚡ quickstart_yaml_config.sh"
echo "   - 빠른 시작 스크립트"
echo "   - 권한 부여, YAML 확인, 미리보기, 생성까지 한번에"
echo ""
echo "4. 🔨 patch_setup_cluster_full.sh"
echo "   - setup_cluster_full.sh의 Step 8을 YAML 기반으로 업데이트"
echo ""
echo "5. 📚 YAML_CONFIG_GUIDE.md"
echo "   - 완전한 사용 가이드"
echo ""
echo "================================================================================"
echo ""

echo "🚀 사용 방법 (3가지 옵션):"
echo "--------------------------------------------------------------------------------"
echo ""
echo "옵션 1: 빠른 시작 (권장)"
echo "  ./quickstart_yaml_config.sh"
echo ""
echo "옵션 2: Python 직접 실행"
echo "  python3 configure_slurm_from_yaml.py"
echo ""
echo "옵션 3: Bash 래퍼 사용"
echo "  ./configure_slurm_cgroup_v2_YAML.sh"
echo ""
echo "================================================================================"
echo ""

echo "📋 YAML 설정 확인:"
echo "--------------------------------------------------------------------------------"

if [ -f "my_cluster.yaml" ]; then
    echo "✅ my_cluster.yaml 존재"
    echo ""
    
    # 주요 설정 추출
    echo "🔍 주요 설정값:"
    
    # ClusterName
    if command -v python3 &> /dev/null; then
        python3 << 'EOFPY'
import yaml
try:
    with open('my_cluster.yaml', 'r') as f:
        config = yaml.safe_load(f)
    
    print(f"  - ClusterName: {config['cluster_info']['cluster_name']}")
    
    controller = config['nodes']['controller']
    print(f"  - Controller: {controller['hostname']} ({controller['ip_address']})")
    
    reboot_program = config['slurm_config'].get('reboot_program', '❌ 설정 없음')
    print(f"  - RebootProgram: {reboot_program}")
    
    nodes = config['nodes']['compute_nodes']
    print(f"  - 계산 노드: {len(nodes)}개")
    for node in nodes:
        print(f"    • {node['hostname']} ({node['ip_address']})")
    
    partitions = config['slurm_config']['partitions']
    print(f"  - 파티션: {len(partitions)}개")
    for part in partitions:
        default = " (기본)" if part.get('default', False) else ""
        print(f"    • {part['name']}{default}: {part['nodes']}")

except Exception as e:
    print(f"  ⚠️  YAML 파싱 오류: {e}")
EOFPY
    fi
else
    echo "❌ my_cluster.yaml 없음"
    echo ""
    echo "💡 생성 방법:"
    echo "  cp examples/2node_example.yaml my_cluster.yaml"
    echo "  vim my_cluster.yaml"
fi

echo ""
echo "================================================================================"
echo ""

echo "✨ 주요 개선사항:"
echo "--------------------------------------------------------------------------------"
echo "❌ 이전 (configure_slurm_cgroup_v2.sh):"
echo "  - 하드코딩된 노드 정보"
echo "  - 하드코딩된 ClusterName"
echo "  - RebootProgram 설정 없음"
echo "  - YAML 수정해도 반영 안됨"
echo ""
echo "✅ 현재 (configure_slurm_from_yaml.py):"
echo "  - 모든 설정을 YAML에서 읽음"
echo "  - RebootProgram 자동 반영"
echo "  - 노드/파티션 동적 생성"
echo "  - YAML만 수정하면 됨"
echo ""
echo "================================================================================"
echo ""

echo "📋 다음 단계:"
echo "--------------------------------------------------------------------------------"
echo ""
echo "1. YAML 파일 확인 및 수정"
echo "   vim my_cluster.yaml"
echo ""
echo "2. 설정 미리보기"
echo "   python3 configure_slurm_from_yaml.py --dry-run"
echo ""
echo "3. 설정 파일 생성"
echo "   ./quickstart_yaml_config.sh"
echo "   또는"
echo "   python3 configure_slurm_from_yaml.py"
echo ""
echo "4. 계산 노드에 배포"
echo "   ./sync_config_to_nodes.sh"
echo ""
echo "5. Slurm 재시작"
echo "   sudo systemctl restart slurmctld"
echo "   ssh node001 'sudo systemctl restart slurmd'"
echo ""
echo "6. 확인"
echo "   sinfo"
echo "   scontrol show config | grep RebootProgram"
echo ""
echo "================================================================================"
echo ""

echo "📚 도움말:"
echo "  cat YAML_CONFIG_GUIDE.md"
echo ""
echo "================================================================================"
