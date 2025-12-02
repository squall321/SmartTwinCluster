#!/bin/bash
################################################################################
# setup_cluster_full.sh를 YAML 기반 설정으로 업데이트하는 패치
################################################################################

SETUP_FILE="setup_cluster_full.sh"
BACKUP_FILE="${SETUP_FILE}.backup_$(date +%Y%m%d_%H%M%S)"

echo "================================================================================"
echo "🔧 setup_cluster_full.sh 업데이트 - YAML 기반 설정 사용"
echo "================================================================================"
echo ""

# 백업
if [ -f "$SETUP_FILE" ]; then
    cp "$SETUP_FILE" "$BACKUP_FILE"
    echo "✅ 백업 생성: $BACKUP_FILE"
else
    echo "❌ $SETUP_FILE을 찾을 수 없습니다!"
    exit 1
fi

echo ""
echo "📝 Step 8 수정 중..."
echo ""

# Step 8 부분을 찾아서 변경
# 기존: sudo bash configure_slurm_cgroup_v2.sh
# 변경: python3 configure_slurm_from_yaml.py

sed -i.tmp '
/^echo "🔧 Step 8\/11: Slurm 설정 파일 생성/,/^echo ""$/ {
    /sudo bash configure_slurm_cgroup_v2.sh/ {
        s|sudo bash configure_slurm_cgroup_v2.sh|python3 configure_slurm_from_yaml.py|
        a\        echo "  💡 YAML 기반 동적 설정 생성 사용"
    }
    /chmod +x configure_slurm_cgroup_v2.sh/ {
        s|chmod +x configure_slurm_cgroup_v2.sh|chmod +x configure_slurm_from_yaml.py|
    }
}
' "$SETUP_FILE"

rm -f "${SETUP_FILE}.tmp"

echo "✅ setup_cluster_full.sh 수정 완료"
echo ""

# 변경 내용 확인
echo "📋 변경된 부분 (Step 8):"
echo "--------------------------------------------------------------------------------"
grep -A 15 "Step 8/11: Slurm 설정 파일 생성" "$SETUP_FILE" | head -20
echo "--------------------------------------------------------------------------------"
echo ""

echo "✅ 패치 완료!"
echo ""
echo "📋 다음 단계:"
echo "  1. 변경 확인:"
echo "     diff $BACKUP_FILE $SETUP_FILE"
echo ""
echo "  2. 테스트:"
echo "     ./setup_cluster_full.sh"
echo ""
echo "  3. 문제 발생시 복원:"
echo "     mv $BACKUP_FILE $SETUP_FILE"
echo ""
echo "================================================================================"
