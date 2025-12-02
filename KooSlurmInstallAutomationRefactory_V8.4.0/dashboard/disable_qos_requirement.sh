#!/bin/bash

echo "=========================================="
echo "🔧 QoS 없이 Slurm 운영 설정"
echo "=========================================="
echo ""
echo "QoS (Quality of Service)가 없어도 Slurm은 정상 작동합니다."
echo "QoS는 작업 우선순위와 리소스 제한 관리에 사용됩니다."
echo ""
echo "QoS 없이 운영 시:"
echo "  ✅ Partition 기반 노드 할당 가능"
echo "  ✅ 작업 제출 및 실행 가능"
echo "  ❌ 그룹별 CPU 제한 불가"
echo "  ❌ 작업 우선순위 관리 불가"
echo ""
read -p "QoS 없이 계속 진행하시겠습니까? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 1
fi

# 1. Disable QoS in apply_configuration
echo ""
echo "1️⃣  slurm_config_manager.py 수정..."

SLURM_CONFIG="/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/slurm_config_manager.py"

# Backup
cp "$SLURM_CONFIG" "${SLURM_CONFIG}.backup_$(date +%Y%m%d_%H%M%S)"

# Modify to skip QoS step entirely
python3 << 'EOF'
import re

file_path = '/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/slurm_config_manager.py'

with open(file_path, 'r') as f:
    content = f.read()

# Find and modify the QoS section in apply_configuration
# Change to skip QoS creation entirely
modified = re.sub(
    r"(\s+# 1\. QoS 생성/업데이트\s+print\(.*\s+print\(\"Step 1: Creating/Updating QoS\"\)\s+print\(.*\s+)(for group in groups:.*?# 2\. 파티션 업데이트)",
    r'\1# QoS 생성 건너뛰기 (slurmdbd 미설치)\nprint("⚠️  Skipping QoS creation (slurmdbd not configured)")\nprint("   Partitions will be created without QoS restrictions")\n\n# 2. 파티션 업데이트',
    content,
    flags=re.DOTALL
)

with open(file_path, 'w') as f:
    f.write(modified)

print("✅ QoS 단계 건너뛰기 설정 완료")
EOF

echo "   ✅ 수정 완료"

# 2. Set default to skip QoS in partition config
echo ""
echo "2️⃣  Backend 재시작..."
cd backend_5010
./stop.sh
sleep 1
export MOCK_MODE=false
./start.sh
sleep 2

echo ""
echo "=========================================="
echo "✅ 설정 완료"
echo "=========================================="
echo ""
echo "이제 Apply Configuration을 실행하면:"
echo "  1. QoS 생성 건너뜀"
echo "  2. Partition만 생성 (QoS 설정 없이)"
echo "  3. slurm.conf 업데이트"
echo "  4. Slurm reconfigure"
echo ""
echo "나중에 QoS를 추가하려면:"
echo "  ./setup_slurm_accounting.sh 실행"
echo ""
