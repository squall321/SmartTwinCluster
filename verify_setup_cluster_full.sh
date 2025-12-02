#!/bin/bash
################################################################################
# setup_cluster_full.sh 검증 스크립트
#
# 목적:
#   - setup_cluster_full.sh의 모든 구성 요소 검증
#   - Type=simple 전환 확인
#   - 기능 손실 여부 확인
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "🔍 setup_cluster_full.sh 전체 검증"
echo "================================================================================"
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0

################################################################################
# 1. 필수 파일 존재 확인
################################################################################

echo "📁 Step 1/7: 필수 파일 존재 확인"
echo "--------------------------------------------------------------------------------"

REQUIRED_FILES=(
    "setup_cluster_full.sh"
    "my_cluster.yaml"
    "validate_config.py"
    "test_connection.py"
    "install_munge_auto.sh"
    "install_slurm_cgroup_v2.sh"
    "create_slurm_systemd_services.sh"
    "install_slurm_accounting.sh"
    "configure_slurm_from_yaml.py"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ $file (파일 없음)"
        ((CHECKS_FAILED++))
    fi
done

echo ""

################################################################################
# 2. systemd Type 확인
################################################################################

echo "🔧 Step 2/7: systemd Type 확인 (Type=simple)"
echo "--------------------------------------------------------------------------------"

# create_slurm_systemd_services.sh 확인
echo "📄 create_slurm_systemd_services.sh:"

if [ -f "create_slurm_systemd_services.sh" ]; then
    # Type=simple 확인
    if grep -q "Type=simple" create_slurm_systemd_services.sh; then
        echo "  ✅ Type=simple 설정됨"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ Type=simple이 아님"
        echo "     현재: $(grep "Type=" create_slurm_systemd_services.sh | head -1)"
        ((CHECKS_FAILED++))
    fi
    
    # Type=notify 제거 확인
    if ! grep -q "Type=notify" create_slurm_systemd_services.sh; then
        echo "  ✅ Type=notify 제거됨"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ Type=notify가 여전히 존재"
        ((CHECKS_FAILED++))
    fi
    
    # -D 옵션 제거 확인
    if ! grep -q "slurmctld -D" create_slurm_systemd_services.sh && \
       ! grep -q "slurmd -D" create_slurm_systemd_services.sh; then
        echo "  ✅ -D 옵션 제거됨"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ -D 옵션이 여전히 존재"
        ((CHECKS_FAILED++))
    fi
else
    echo "  ❌ create_slurm_systemd_services.sh 파일 없음"
    ((CHECKS_FAILED+=3))
fi

echo ""

# install_slurm_accounting.sh 확인
echo "📄 install_slurm_accounting.sh:"

if [ -f "install_slurm_accounting.sh" ]; then
    # Type=simple 확인
    if grep -q "Type=simple" install_slurm_accounting.sh; then
        echo "  ✅ Type=simple 설정됨"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ Type=simple이 아님"
        ((CHECKS_FAILED++))
    fi
    
    # Type=notify 제거 확인
    if ! grep -q "Type=notify" install_slurm_accounting.sh; then
        echo "  ✅ Type=notify 제거됨"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ Type=notify가 여전히 존재"
        ((CHECKS_FAILED++))
    fi
    
    # -D 옵션 제거 확인
    if ! grep -q "slurmdbd -D" install_slurm_accounting.sh; then
        echo "  ✅ -D 옵션 제거됨"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ -D 옵션이 여전히 존재"
        ((CHECKS_FAILED++))
    fi
else
    echo "  ❌ install_slurm_accounting.sh 파일 없음"
    ((CHECKS_FAILED+=3))
fi

echo ""

################################################################################
# 3. Step 구성 확인
################################################################################

echo "📋 Step 3/7: setup_cluster_full.sh Step 구성 확인"
echo "--------------------------------------------------------------------------------"

if [ -f "setup_cluster_full.sh" ]; then
    # 각 Step 확인
    STEPS=(
        "Step 2"
        "Step 3"
        "Step 4"
        "Step 4.5"
        "Step 5"
        "Step 6"
        "Step 6.1"
        "Step 6.5"
        "Step 7"
        "Step 7.5"
        "Step 8"
        "Step 9"
        "Step 10"
        "Step 11"
        "Step 12"
    )
    
    for step in "${STEPS[@]}"; do
        if grep -q "$step" setup_cluster_full.sh; then
            echo "  ✅ $step"
            ((CHECKS_PASSED++))
        else
            echo "  ❌ $step (없음)"
            ((CHECKS_FAILED++))
        fi
    done
else
    echo "  ❌ setup_cluster_full.sh 파일 없음"
    ((CHECKS_FAILED+=${#STEPS[@]}))
fi

echo ""

################################################################################
# 4. SSH timeout 확인
################################################################################

echo "⏱️  Step 4/7: SSH timeout 설정 확인"
echo "--------------------------------------------------------------------------------"

if [ -f "setup_cluster_full.sh" ]; then
    # Step 10: 원격 서비스 시작 timeout
    if grep -q "timeout 60 ssh" setup_cluster_full.sh; then
        echo "  ✅ Step 10: SSH timeout 60초"
        ((CHECKS_PASSED++))
    else
        echo "  ⚠️  Step 10: SSH timeout 설정 없음 (선택 사항)"
    fi
    
    # Step 7.5: systemd 배포 timeout
    if grep -q "timeout 30 ssh" setup_cluster_full.sh; then
        echo "  ✅ Step 7.5: SSH timeout 30초"
        ((CHECKS_PASSED++))
    else
        echo "  ⚠️  Step 7.5: SSH timeout 설정 없음 (선택 사항)"
    fi
fi

echo ""

################################################################################
# 5. QoS 기능 확인
################################################################################

echo "🗄️  Step 5/7: QoS 기능 (slurmdbd) 확인"
echo "--------------------------------------------------------------------------------"

# Step 6.5 존재 확인
if grep -q "Step 6.5" setup_cluster_full.sh; then
    echo "  ✅ Step 6.5 (slurmdbd 설치) 존재"
    ((CHECKS_PASSED++))
else
    echo "  ❌ Step 6.5 (slurmdbd 설치) 없음"
    ((CHECKS_FAILED++))
fi

# install_slurm_accounting.sh 확인
if [ -f "install_slurm_accounting.sh" ]; then
    echo "  ✅ install_slurm_accounting.sh 존재"
    ((CHECKS_PASSED++))
    
    # MariaDB 설정 확인
    if grep -q "mariadb" install_slurm_accounting.sh; then
        echo "  ✅ MariaDB 설정 포함"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ MariaDB 설정 없음"
        ((CHECKS_FAILED++))
    fi
    
    # slurmdbd.conf 생성 확인
    if grep -q "slurmdbd.conf" install_slurm_accounting.sh; then
        echo "  ✅ slurmdbd.conf 생성 포함"
        ((CHECKS_PASSED++))
    else
        echo "  ❌ slurmdbd.conf 생성 없음"
        ((CHECKS_FAILED++))
    fi
else
    echo "  ❌ install_slurm_accounting.sh 없음"
    ((CHECKS_FAILED+=3))
fi

echo ""

################################################################################
# 6. cgroup v2 지원 확인
################################################################################

echo "⚙️  Step 6/7: cgroup v2 지원 확인"
echo "--------------------------------------------------------------------------------"

# install_slurm_cgroup_v2.sh 확인
if [ -f "install_slurm_cgroup_v2.sh" ]; then
    echo "  ✅ install_slurm_cgroup_v2.sh 존재"
    ((CHECKS_PASSED++))
    
    # cgroup v2 설정 확인
    if grep -q "cgroup" install_slurm_cgroup_v2.sh; then
        echo "  ✅ cgroup 설정 포함"
        ((CHECKS_PASSED++))
    else
        echo "  ⚠️  cgroup 설정 확인 필요"
    fi
else
    echo "  ❌ install_slurm_cgroup_v2.sh 없음"
    ((CHECKS_FAILED++))
fi

# configure_slurm_from_yaml.py 확인
if [ -f "configure_slurm_from_yaml.py" ]; then
    echo "  ✅ configure_slurm_from_yaml.py 존재"
    ((CHECKS_PASSED++))
else
    echo "  ❌ configure_slurm_from_yaml.py 없음"
    ((CHECKS_FAILED++))
fi

echo ""

################################################################################
# 7. 기타 필수 기능 확인
################################################################################

echo "🔍 Step 7/7: 기타 필수 기능 확인"
echo "--------------------------------------------------------------------------------"

# Munge 설치
if [ -f "install_munge_auto.sh" ]; then
    echo "  ✅ Munge 자동 설치 스크립트"
    ((CHECKS_PASSED++))
else
    echo "  ❌ install_munge_auto.sh 없음"
    ((CHECKS_FAILED++))
fi

# PATH 설정
if grep -q "/etc/profile.d/slurm.sh" setup_cluster_full.sh; then
    echo "  ✅ PATH 영구 설정 포함"
    ((CHECKS_PASSED++))
else
    echo "  ⚠️  PATH 영구 설정 확인 필요"
fi

# MPI 설치 (선택)
if [ -f "install_mpi.py" ]; then
    echo "  ✅ MPI 설치 스크립트 (선택)"
    ((CHECKS_PASSED++))
else
    echo "  ℹ️  install_mpi.py 없음 (선택 사항)"
fi

# RebootProgram 설정 (선택)
if grep -q "setup_reboot_program.sh" setup_cluster_full.sh; then
    echo "  ✅ RebootProgram 설정 포함 (선택)"
    ((CHECKS_PASSED++))
else
    echo "  ℹ️  RebootProgram 설정 없음 (선택 사항)"
fi

echo ""

################################################################################
# 최종 결과
################################################################################

echo "================================================================================"
echo "📊 검증 결과"
echo "================================================================================"
echo ""

TOTAL_CHECKS=$((CHECKS_PASSED + CHECKS_FAILED))
SUCCESS_RATE=$((CHECKS_PASSED * 100 / TOTAL_CHECKS))

echo "총 검사 항목: $TOTAL_CHECKS"
echo "통과: $CHECKS_PASSED ✅"
echo "실패: $CHECKS_FAILED ❌"
echo "성공률: $SUCCESS_RATE%"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo "================================================================================"
    echo "🎉 모든 검사 통과! setup_cluster_full.sh 사용 가능!"
    echo "================================================================================"
    echo ""
    echo "✅ Type=simple 전환 완료"
    echo "✅ 모든 기능 정상"
    echo "✅ QoS 지원"
    echo "✅ cgroup v2 지원"
    echo ""
    echo "다음 단계:"
    echo "  ./setup_cluster_full.sh"
    echo ""
elif [ $SUCCESS_RATE -ge 80 ]; then
    echo "================================================================================"
    echo "⚠️  경고: 일부 검사 실패 ($CHECKS_FAILED개)"
    echo "================================================================================"
    echo ""
    echo "대부분의 기능은 정상이지만, 위의 실패 항목을 확인하세요."
    echo ""
    echo "계속 진행하려면:"
    echo "  ./setup_cluster_full.sh"
    echo ""
else
    echo "================================================================================"
    echo "❌ 검증 실패: $CHECKS_FAILED개 항목 실패"
    echo "================================================================================"
    echo ""
    echo "수정이 필요합니다:"
    echo ""
    if ! grep -q "Type=simple" create_slurm_systemd_services.sh 2>/dev/null; then
        echo "  1. Type=simple 전환:"
        echo "     ./convert_systemd_to_simple.sh"
        echo ""
    fi
    
    if [ ! -f "install_slurm_accounting.sh" ]; then
        echo "  2. install_slurm_accounting.sh가 없습니다"
        echo "     해당 파일을 복원하거나 재생성하세요"
        echo ""
    fi
    
    echo "수정 후 다시 검증:"
    echo "  ./verify_setup_cluster_full.sh"
    echo ""
fi

echo "================================================================================"

# 종료 코드
if [ $CHECKS_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
