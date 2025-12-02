#!/bin/bash
################################################################################
# 한 번에 모든 준비 및 실행
# YAML 기반 Slurm 설정 자동화 - 올인원 스크립트
################################################################################

echo "================================================================================"
echo "🚀 YAML 기반 Slurm 설정 - 올인원 설정"
echo "================================================================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. 실행 권한 부여
echo "📝 Step 1/5: 실행 권한 부여..."
chmod +x configure_slurm_from_yaml.py
chmod +x configure_slurm_cgroup_v2_YAML.sh
chmod +x quickstart_yaml_config.sh
chmod +x patch_setup_cluster_full.sh
chmod +x YAML_CONFIG_SUMMARY.sh
chmod +x chmod_yaml_scripts.sh
echo "  ✅ 완료"
echo ""

# 2. 요약 정보 출력
echo "📝 Step 2/5: 시스템 정보 확인..."
./YAML_CONFIG_SUMMARY.sh

echo ""
echo "================================================================================"
echo ""

# 3. 사용자 선택
echo "📝 Step 3/5: 다음 작업을 선택하세요:"
echo ""
echo "1) 설정 미리보기 (dry-run)"
echo "2) 설정 파일 생성"
echo "3) setup_cluster_full.sh 패치"
echo "4) 전체 가이드 보기"
echo "5) 종료"
echo ""
read -p "선택 (1-5): " choice

case $choice in
    1)
        echo ""
        echo "🔍 설정 미리보기..."
        echo ""
        python3 configure_slurm_from_yaml.py --dry-run
        ;;
    2)
        echo ""
        echo "🚀 설정 파일 생성..."
        echo ""
        ./quickstart_yaml_config.sh
        ;;
    3)
        echo ""
        echo "🔨 setup_cluster_full.sh 패치..."
        echo ""
        ./patch_setup_cluster_full.sh
        ;;
    4)
        echo ""
        echo "📚 전체 가이드..."
        echo ""
        cat YAML_CONFIG_GUIDE.md | less
        ;;
    5)
        echo ""
        echo "👋 종료합니다."
        echo ""
        exit 0
        ;;
    *)
        echo ""
        echo "❌ 잘못된 선택입니다."
        echo ""
        exit 1
        ;;
esac

echo ""
echo "================================================================================"
echo "✅ 완료!"
echo "================================================================================"
echo ""
