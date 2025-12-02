#!/bin/bash

echo "=========================================="
echo "🔍 setup_cluster_full.sh 준비 상태 확인"
echo "=========================================="
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 1. Step 6.5가 추가되었는지 확인
echo "1️⃣  Step 6.5 추가 확인:"
if grep -q "Step 6.5" setup_cluster_full.sh; then
    echo "   ✅ Step 6.5 (slurmdbd 설치) 추가됨"
    grep -n "Step 6.5" setup_cluster_full.sh | head -1
else
    echo "   ❌ Step 6.5가 없습니다"
    echo "   → setup_cluster_full.sh를 다시 수정해야 합니다"
fi
echo ""

# 2. install_slurm_accounting.sh 존재 확인
echo "2️⃣  install_slurm_accounting.sh 확인:"
if [ -f "install_slurm_accounting.sh" ]; then
    echo "   ✅ install_slurm_accounting.sh 존재"
    
    # systemd 서비스 타입 확인
    if grep -q "Type=simple" install_slurm_accounting.sh; then
        echo "   ✅ systemd Type=simple (수정됨)"
    else
        echo "   ❌ systemd Type=forking (구버전)"
        echo "   → install_slurm_accounting.sh를 다시 수정해야 합니다"
    fi
    
    if grep -q "TimeoutStartSec=300" install_slurm_accounting.sh; then
        echo "   ✅ TimeoutStartSec=300 (수정됨)"
    else
        echo "   ❌ TimeoutStartSec 설정 없음"
    fi
else
    echo "   ❌ install_slurm_accounting.sh가 없습니다"
fi
echo ""

# 3. 현재 slurmdbd 상태
echo "3️⃣  현재 slurmdbd 상태:"
if sudo systemctl is-active --quiet slurmdbd; then
    echo "   ✅ slurmdbd 실행 중"
    VERSION=$(sudo /usr/local/slurm/sbin/slurmdbd -V 2>&1 | head -1)
    echo "   $VERSION"
else
    echo "   ⚠️  slurmdbd 실행 안 됨 (정상, 아직 설치 안 했을 수 있음)"
fi
echo ""

# 4. QoS 테스트
echo "4️⃣  QoS 기능 확인:"
if command -v sacctmgr &> /dev/null; then
    export PATH=/usr/local/slurm/bin:$PATH
    if sudo sacctmgr show qos -n 2>&1 | grep -q "normal\|qos"; then
        echo "   ✅ QoS 작동 중"
    else
        echo "   ⚠️  QoS 데이터 없음 (첫 설치시 정상)"
    fi
else
    echo "   ⚠️  sacctmgr 명령어 없음"
fi
echo ""

echo "=========================================="
echo "📋 결론"
echo "=========================================="
echo ""

# 모든 체크 통과 여부
CHECKS_PASSED=true

if ! grep -q "Step 6.5" setup_cluster_full.sh; then
    CHECKS_PASSED=false
fi

if [ ! -f "install_slurm_accounting.sh" ]; then
    CHECKS_PASSED=false
fi

if [ -f "install_slurm_accounting.sh" ] && ! grep -q "Type=simple" install_slurm_accounting.sh; then
    CHECKS_PASSED=false
fi

if [ "$CHECKS_PASSED" = true ]; then
    echo "✅ setup_cluster_full.sh 사용 가능!"
    echo ""
    echo "   새 클러스터 설치 시:"
    echo "   ./setup_cluster_full.sh"
    echo ""
    echo "   Step 6.5에서 'Y'를 입력하면 slurmdbd가 설치되고"
    echo "   QoS 기능이 활성화됩니다."
else
    echo "❌ setup_cluster_full.sh 사용 불가"
    echo ""
    echo "🔧 수정 필요:"
    
    if ! grep -q "Step 6.5" setup_cluster_full.sh; then
        echo "   1. setup_cluster_full.sh에 Step 6.5 추가 필요"
    fi
    
    if [ ! -f "install_slurm_accounting.sh" ]; then
        echo "   2. install_slurm_accounting.sh 파일이 없음"
    elif ! grep -q "Type=simple" install_slurm_accounting.sh; then
        echo "   2. install_slurm_accounting.sh의 systemd 설정 수정 필요"
    fi
fi

echo ""
