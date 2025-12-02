#!/bin/bash
################################################################################
# 전체 자동 수정 스크립트
# - cgroup.conf 수정 (Slurm 22.05.8 호환)
# - slurm.conf 확인
# - 계산 노드에 설정 배포
# - 모든 서비스 재시작
################################################################################

set -e

CONFIG_DIR="/usr/local/slurm/etc"
NODES=("192.168.122.90" "192.168.122.103")
NODE_NAMES=("node001" "node002")
SSH_USER="koopark"

echo "========================================"
echo "🚀 Slurm 전체 자동 수정"
echo "========================================"
echo ""

################################################################################
# Step 1: cgroup.conf 수정 (컨트롤러)
################################################################################

echo "📝 Step 1/6: cgroup.conf 수정 (Slurm 22.05.8 호환)..."
echo "--------------------------------------------------------------------------------"

if [ -f "${CONFIG_DIR}/cgroup.conf" ]; then
    sudo cp "${CONFIG_DIR}/cgroup.conf" "${CONFIG_DIR}/cgroup.conf.backup.$(date +%Y%m%d_%H%M%S)"
    echo "✅ 기존 설정 백업"
fi

sudo tee ${CONFIG_DIR}/cgroup.conf > /dev/null << 'EOFCGROUP'
###
# Slurm cgroup Configuration
# Compatible with Slurm 22.05.8
###

ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=no
ConstrainDevices=no

AllowedRAMSpace=100
AllowedSwapSpace=0
EOFCGROUP

sudo chown slurm:slurm ${CONFIG_DIR}/cgroup.conf
sudo chmod 644 ${CONFIG_DIR}/cgroup.conf

echo "✅ cgroup.conf 수정 완료"
echo ""

################################################################################
# Step 2: slurm.conf 확인
################################################################################

echo "📝 Step 2/6: slurm.conf 주요 설정 확인..."
echo "--------------------------------------------------------------------------------"

grep -E "^SlurmUser|^SlurmdUser|^PidFile|^NodeName|^PartitionName" ${CONFIG_DIR}/slurm.conf

echo ""
echo "✅ 설정 확인 완료"
echo ""

################################################################################
# Step 3: 컨트롤러 서비스 정지
################################################################################

echo "🛑 Step 3/6: 기존 서비스 정지..."
echo "--------------------------------------------------------------------------------"

sudo systemctl stop slurmctld 2>/dev/null || true
sudo pkill -9 slurmctld 2>/dev/null || true

# PID 파일 정리
sudo rm -f /run/slurmctld.pid
sudo rm -f /var/run/slurmctld.pid
sudo rm -f /var/spool/slurm/state/slurmctld.pid

echo "✅ 정리 완료"
echo ""

################################################################################
# Step 4: 계산 노드에 설정 배포
################################################################################

echo "📤 Step 4/6: 계산 노드에 설정 파일 배포..."
echo "--------------------------------------------------------------------------------"

for i in "${!NODES[@]}"; do
    node_ip="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo ""
    echo "📦 $node_name ($node_ip):"
    
    # 노드의 서비스 정지
    echo "  - 서비스 정지 중..."
    ssh ${SSH_USER}@${node_ip} "sudo systemctl stop slurmd 2>/dev/null || true; sudo pkill -9 slurmd 2>/dev/null || true" || true
    
    # 설정 파일 복사
    echo "  - slurm.conf 복사 중..."
    scp ${CONFIG_DIR}/slurm.conf ${SSH_USER}@${node_ip}:/tmp/
    ssh ${SSH_USER}@${node_ip} "sudo mv /tmp/slurm.conf ${CONFIG_DIR}/ && sudo chown slurm:slurm ${CONFIG_DIR}/slurm.conf"
    
    echo "  - cgroup.conf 복사 중..."
    scp ${CONFIG_DIR}/cgroup.conf ${SSH_USER}@${node_ip}:/tmp/
    ssh ${SSH_USER}@${node_ip} "sudo mv /tmp/cgroup.conf ${CONFIG_DIR}/ && sudo chown slurm:slurm ${CONFIG_DIR}/cgroup.conf"
    
    # systemd 서비스 파일 복사
    echo "  - slurmd.service 복사 중..."
    scp /etc/systemd/system/slurmd.service ${SSH_USER}@${node_ip}:/tmp/
    ssh ${SSH_USER}@${node_ip} "sudo mv /tmp/slurmd.service /etc/systemd/system/ && sudo systemctl daemon-reload"
    
    # 디렉토리 권한 확인
    echo "  - 디렉토리 권한 설정 중..."
    ssh ${SSH_USER}@${node_ip} "sudo mkdir -p /var/spool/slurm/d /var/log/slurm /run/slurm && sudo chown -R slurm:slurm /var/spool/slurm /var/log/slurm /run/slurm"
    
    # PID 파일 정리
    ssh ${SSH_USER}@${node_ip} "sudo rm -f /run/slurmd.pid /var/run/slurmd.pid /var/spool/slurm/d/slurmd.pid" || true
    
    echo "  ✅ $node_name 설정 완료"
done

echo ""
echo "✅ 모든 노드에 설정 배포 완료"
echo ""

################################################################################
# Step 5: 계산 노드 slurmd 시작
################################################################################

echo "▶️  Step 5/6: 계산 노드 slurmd 시작..."
echo "--------------------------------------------------------------------------------"

for i in "${!NODES[@]}"; do
    node_ip="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo ""
    echo "🚀 $node_name: slurmd 시작 중..."
    
    ssh ${SSH_USER}@${node_ip} "sudo systemctl enable slurmd && sudo systemctl start slurmd"
    
    sleep 3
    
    if ssh ${SSH_USER}@${node_ip} "sudo systemctl is-active --quiet slurmd"; then
        echo "✅ $node_name: slurmd 시작 성공"
    else
        echo "❌ $node_name: slurmd 시작 실패"
        echo "로그 확인:"
        ssh ${SSH_USER}@${node_ip} "sudo journalctl -u slurmd -n 10 --no-pager"
    fi
done

echo ""

################################################################################
# Step 6: 컨트롤러 slurmctld 시작
################################################################################

echo "▶️  Step 6/6: 컨트롤러 slurmctld 시작..."
echo "--------------------------------------------------------------------------------"

echo "slurmctld 시작 중..."
sudo systemctl enable slurmctld
sudo systemctl start slurmctld

sleep 5

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 시작 성공"
    echo ""
    sudo systemctl status slurmctld --no-pager -l
else
    echo "❌ slurmctld 시작 실패"
    echo ""
    echo "로그:"
    sudo journalctl -u slurmctld -n 20 --no-pager
    exit 1
fi

echo ""

################################################################################
# 완료 및 검증
################################################################################

echo "========================================"
echo "✅ 수정 및 재시작 완료!"
echo "========================================"
echo ""

sleep 3

# PATH 설정
export PATH=/usr/local/slurm/bin:$PATH

echo "📊 클러스터 상태 확인..."
echo ""

if command -v sinfo &> /dev/null; then
    echo "노드 상태:"
    sinfo -N -l || true
    echo ""
    
    echo "파티션 상태:"
    sinfo || true
    echo ""
else
    echo "⚠️  sinfo를 찾을 수 없습니다"
    echo "PATH 설정: export PATH=/usr/local/slurm/bin:\$PATH"
fi

echo ""
echo "========================================"
echo "📋 다음 단계"
echo "========================================"
echo ""
echo "1️⃣  노드가 DOWN 상태라면 활성화:"
echo "   scontrol update NodeName=node001 State=RESUME"
echo "   scontrol update NodeName=node002 State=RESUME"
echo ""
echo "2️⃣  테스트 Job 제출:"
echo "   echo '#!/bin/bash' > test.sh"
echo "   echo 'hostname' >> test.sh"
echo "   echo 'date' >> test.sh"
echo "   sbatch -N1 test.sh"
echo ""
echo "3️⃣  상태 모니터링:"
echo "   squeue"
echo "   sinfo"
echo ""
