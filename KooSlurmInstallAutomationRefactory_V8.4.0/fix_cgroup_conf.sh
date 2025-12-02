#!/bin/bash
################################################################################
# cgroup.conf 수정 - Slurm 22.05.8 호환 버전
# cgroup v2 옵션 제거, v1 호환 설정으로 변경
################################################################################

set -e

CONFIG_DIR="/usr/local/slurm/etc"

echo "========================================"
echo "🔧 cgroup.conf 수정 (Slurm 22.05.8용)"
echo "========================================"
echo ""

# 백업
if [ -f "${CONFIG_DIR}/cgroup.conf" ]; then
    sudo cp "${CONFIG_DIR}/cgroup.conf" "${CONFIG_DIR}/cgroup.conf.backup.$(date +%Y%m%d_%H%M%S)"
    echo "✅ 기존 설정 백업 완료"
fi

echo "📝 Slurm 22.05.8 호환 cgroup.conf 생성..."
echo ""

# Slurm 22.05.8 호환 버전
sudo tee ${CONFIG_DIR}/cgroup.conf > /dev/null << 'EOFCGROUP'
###
# Slurm cgroup Support Configuration
# Compatible with Slurm 22.05.8 (cgroup v1 & v2)
###

# 리소스 제한 활성화
ConstrainCores=yes
ConstrainRAMSpace=yes

# Swap 제한
ConstrainSwapSpace=no

# 디바이스 제한
ConstrainDevices=no

# 메모리 제한 설정
AllowedRAMSpace=100
AllowedSwapSpace=0

# CPU 친화성 (cgroup v1/v2 모두 지원)
# TaskAffinity는 task/affinity 플러그인에서 관리
EOFCGROUP

sudo chown slurm:slurm ${CONFIG_DIR}/cgroup.conf
sudo chmod 644 ${CONFIG_DIR}/cgroup.conf

echo "✅ cgroup.conf 생성 완료"
echo ""

echo "생성된 설정:"
cat ${CONFIG_DIR}/cgroup.conf
echo ""

echo "========================================"
echo "✅ 완료!"
echo "========================================"
echo ""
echo "제거된 옵션 (Slurm 22.05.8에서 미지원):"
echo "  ❌ CgroupAutomount (defunct)"
echo "  ❌ TaskAffinity (cgroup.conf에서 제거)"
echo "  ❌ MemorySwappiness"
echo "  ❌ MemoryLimitEnforce"
echo ""
echo "다음 단계:"
echo "  1. 계산 노드에 설정 배포"
echo "  2. 서비스 재시작"
echo ""
