#!/bin/bash
################################################################################
# setup_cluster_full.sh를 SSH 설정 후 RebootProgram 자동 실행하도록 수정
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "🔧 setup_cluster_full.sh 수정 - RebootProgram 자동화"
echo "================================================================================"
echo ""

# 백업
if [ -f "setup_cluster_full.sh" ]; then
    cp setup_cluster_full.sh setup_cluster_full.sh.backup.$(date +%Y%m%d_%H%M%S)
    echo "✅ 백업 완료: setup_cluster_full.sh.backup.*"
else
    echo "❌ setup_cluster_full.sh 파일을 찾을 수 없습니다!"
    exit 1
fi
echo ""

echo "📝 수정 작업 진행 중..."
echo ""

# 1. 맨 처음 RebootProgram 질문 제거 (14-24줄)
echo "  1. 맨 처음 RebootProgram 질문 제거..."
sed -i '14,24d' setup_cluster_full.sh

# 2. 나머지 중복된 RebootProgram 질문들 제거
echo "  2. 중복된 RebootProgram 질문들 제거..."
# "# Step: RebootProgram 설정"으로 시작하는 블록들을 찾아서 제거
sed -i '/^# Step: RebootProgram 설정/,/^fi$/d' setup_cluster_full.sh

# 3. Step 4 (SSH 연결 테스트) 이후에 RebootProgram 자동 실행 추가
echo "  3. SSH 설정 후 RebootProgram 자동 실행 추가..."

# Step 4의 끝부분 (echo "" 다음)을 찾아서 그 뒤에 추가
sed -i '/^# Step 4: SSH 연결 테스트/,/^echo ""$/{
/^echo ""$/a\
\
################################################################################\
# Step 4.5: RebootProgram 설정 (YAML 기반 자동)\
################################################################################\
\
# YAML에 reboot_program이 정의되어 있으면 자동으로 설정\
if [ -f "my_cluster.yaml" ] && grep -q "reboot_program:" my_cluster.yaml; then\
    echo "🔄 Step 4.5/11: RebootProgram 자동 설정 (YAML 기반)..."\
    echo "--------------------------------------------------------------------------------"\
    echo "✅ YAML에 reboot_program 설정이 감지되었습니다."\
    echo "   웹 대시보드에서 노드 재부팅 기능을 위한 환경을 설정합니다."\
    echo ""\
    \
    if [ -f "./setup_reboot_program.sh" ]; then\
        ./setup_reboot_program.sh\
        \
        if [ $? -eq 0 ]; then\
            echo "✅ RebootProgram 설정 완료"\
        else\
            echo "⚠️  RebootProgram 설정 실패 (계속 진행)"\
        fi\
    else\
        echo "⚠️  setup_reboot_program.sh를 찾을 수 없습니다."\
        echo "   먼저 ./refactor_reboot_setup_to_yaml_fixed.sh를 실행하세요."\
    fi\
    \
    echo ""\
else\
    echo "ℹ️  YAML에 reboot_program 설정이 없습니다 (웹 재부팅 기능 비활성화)"\
    echo ""\
fi\

}' setup_cluster_full.sh

echo ""
echo "================================================================================"
echo "✅ 수정 완료!"
echo "================================================================================"
echo ""
echo "📝 변경 사항:"
echo "  1. ✅ 맨 처음 RebootProgram 질문 제거"
echo "  2. ✅ 중복된 4개의 RebootProgram 질문 제거"
echo "  3. ✅ Step 4 (SSH 연결 테스트) 이후에 YAML 기반 자동 실행 추가"
echo ""
echo "📋 동작 방식:"
echo "  - YAML에 reboot_program이 있으면 → 자동으로 setup_reboot_program.sh 실행"
echo "  - YAML에 reboot_program이 없으면 → 건너뜀"
echo ""
echo "🧪 테스트:"
echo "  ./setup_cluster_full.sh"
echo ""
echo "💾 백업 파일: setup_cluster_full.sh.backup.*"
echo "   복원: cp setup_cluster_full.sh.backup.* setup_cluster_full.sh"
echo ""
