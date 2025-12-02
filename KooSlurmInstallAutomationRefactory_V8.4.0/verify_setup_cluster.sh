#!/bin/bash
################################################################################
# setup_cluster_full.sh 최종 검증 및 문제 확인
################################################################################

echo "=========================================="
echo "🔍 setup_cluster_full.sh 최종 검증"
echo "=========================================="
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# Step 개수 확인
echo "1️⃣  Step 개수 확인:"
STEP_COUNT=$(grep -c "^echo.*Step [0-9]" setup_cluster_full.sh || true)
echo "   총 $STEP_COUNT개 Step"

# 각 Step 목록
echo ""
echo "2️⃣  Step 목록:"
grep "^echo.*Step [0-9]" setup_cluster_full.sh | head -20

echo ""
echo "3️⃣  중요 스크립트 존재 확인:"
echo "----------------------------------------"

REQUIRED_SCRIPTS=(
    "install_munge_auto.sh"
    "install_slurm_cgroup_v2.sh"
    "create_slurm_systemd_services.sh"
    "install_slurm_accounting.sh"
    "configure_slurm_from_yaml.py"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo "   ✅ $script"
    else
        echo "   ❌ $script (없음)"
    fi
done

echo ""
echo "4️⃣  systemd Type 확인:"
echo "----------------------------------------"

if grep -q "Type=notify" create_slurm_systemd_services.sh 2>/dev/null; then
    echo "   ✅ create_slurm_systemd_services.sh: Type=notify"
else
    echo "   ⚠️  create_slurm_systemd_services.sh 확인 필요"
fi

if grep -q "Type=notify" install_slurm_accounting.sh 2>/dev/null; then
    echo "   ✅ install_slurm_accounting.sh: Type=notify"
else
    echo "   ⚠️  install_slurm_accounting.sh 확인 필요"
fi

echo ""
echo "5️⃣  setup_cluster_full.sh 주요 기능 확인:"
echo "----------------------------------------"

# Step 6.1 확인
if grep -q "Step 6.1" setup_cluster_full.sh; then
    echo "   ✅ Step 6.1: systemd 서비스 생성"
else
    echo "   ❌ Step 6.1: systemd 서비스 생성 없음"
fi

# Step 6.5 확인  
if grep -q "Step 6.5" setup_cluster_full.sh; then
    echo "   ✅ Step 6.5: slurmdbd 설치"
else
    echo "   ❌ Step 6.5: slurmdbd 설치 없음"
fi

# SSH 타임아웃 확인
if grep -q "timeout.*ssh" setup_cluster_full.sh; then
    echo "   ✅ SSH 타임아웃 설정"
else
    echo "   ⚠️  SSH 타임아웃 권장 (원격 명령 hang 방지)"
fi

echo ""
echo "=========================================="
echo "📋 결론"
echo "=========================================="
echo ""

# 필수 파일 체크
MISSING_FILES=0
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        ((MISSING_FILES++))
    fi
done

if [ $MISSING_FILES -eq 0 ] && grep -q "Step 6.1" setup_cluster_full.sh && grep -q "Step 6.5" setup_cluster_full.sh; then
    echo "✅ setup_cluster_full.sh 사용 준비 완료!"
    echo ""
    echo "실행 방법:"
    echo "  ./setup_cluster_full.sh"
    echo ""
    echo "주의사항:"
    echo "  - Step 6.1에서 Y: systemd 서비스 (Type=notify) 생성"
    echo "  - Step 6.5에서 Y: slurmdbd 설치 (QoS 기능)"
    echo "  - Step 10에서: 원격 노드 slurmd 시작 (시간 소요 가능)"
    echo ""
else
    echo "⚠️  일부 파일이 없거나 설정이 불완전합니다."
    echo ""
    if [ $MISSING_FILES -gt 0 ]; then
        echo "누락된 스크립트: $MISSING_FILES개"
    fi
    if ! grep -q "Step 6.1" setup_cluster_full.sh; then
        echo "- Step 6.1 (systemd 서비스 생성) 추가 필요"
    fi
    if ! grep -q "Step 6.5" setup_cluster_full.sh; then
        echo "- Step 6.5 (slurmdbd 설치) 추가 필요"
    fi
fi

echo ""
