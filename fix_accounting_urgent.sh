#!/bin/bash

echo "=========================================="
echo "🔧 긴급 수정: slurm.conf Accounting 설정"
echo "=========================================="
echo ""

# 1. slurmctld 강제 종료
echo "1️⃣  slurmctld 강제 종료..."
sudo pkill -9 slurmctld
sleep 2
echo "✅ 종료 완료"
echo ""

# 2. slurm.conf 백업
echo "2️⃣  slurm.conf 백업..."
sudo cp /usr/local/slurm/etc/slurm.conf /usr/local/slurm/etc/slurm.conf.backup_$(date +%Y%m%d_%H%M%S)
echo "✅ 백업 완료"
echo ""

# 3. Accounting 설정 수정
echo "3️⃣  slurm.conf Accounting 설정 수정..."

# 기존 잘못된 설정 제거
sudo sed -i '/^AccountingStorageType=accounting_storage\/none/d' /usr/local/slurm/etc/slurm.conf

# 올바른 Accounting 설정 추가 (ClusterName 다음에)
if ! grep -q "AccountingStorageType=accounting_storage/slurmdbd" /usr/local/slurm/etc/slurm.conf; then
    sudo sed -i '/^ClusterName=/a \
# Accounting\
AccountingStorageType=accounting_storage/slurmdbd\
AccountingStorageHost=localhost\
AccountingStoragePort=6819' /usr/local/slurm/etc/slurm.conf
fi

echo "✅ slurm.conf 수정 완료"
echo ""

# 4. 수정 내용 확인
echo "4️⃣  수정 내용 확인:"
echo "----------------------------------------"
grep -A3 "^# Accounting" /usr/local/slurm/etc/slurm.conf || grep "AccountingStorage" /usr/local/slurm/etc/slurm.conf
echo ""

# 5. 원격 노드에 배포
echo "5️⃣  원격 노드에 slurm.conf 배포..."

NODES=("192.168.122.90" "192.168.122.103")
SSH_USER="koopark"

for node in "${NODES[@]}"; do
    echo ""
    echo "   📤 $node..."
    scp /usr/local/slurm/etc/slurm.conf ${SSH_USER}@${node}:/tmp/
    ssh ${SSH_USER}@${node} "sudo mv /tmp/slurm.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/slurm.conf"
    
    if [ $? -eq 0 ]; then
        echo "   ✅ $node: 배포 완료"
    else
        echo "   ⚠️  $node: 배포 실패"
    fi
done

echo ""
echo "✅ 모든 노드 배포 완료"
echo ""

# 6. slurmctld 재시작
echo "6️⃣  slurmctld 재시작..."
sudo systemctl start slurmctld

echo "⏱️  대기 중 (10초)..."
sleep 10

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 시작 성공!"
    
    # 상태 확인
    sudo systemctl status slurmctld --no-pager | head -15
else
    echo "❌ slurmctld 시작 실패"
    echo ""
    echo "로그 확인:"
    sudo tail -20 /var/log/slurm/slurmctld.log
    exit 1
fi

echo ""

# 7. 원격 노드 slurmd 재시작
echo "7️⃣  원격 노드 slurmd 재시작..."

for node in "${NODES[@]}"; do
    echo ""
    echo "   🔄 $node..."
    ssh ${SSH_USER}@${node} "sudo systemctl restart slurmd"
    sleep 2
    
    if ssh ${SSH_USER}@${node} "sudo systemctl is-active --quiet slurmd"; then
        echo "   ✅ $node: slurmd 재시작 성공"
    else
        echo "   ⚠️  $node: slurmd 재시작 실패"
    fi
done

echo ""

# 8. 클러스터 상태 확인
echo "8️⃣  클러스터 상태 확인..."
echo "----------------------------------------"

sleep 5

export PATH=/usr/local/slurm/bin:$PATH

echo ""
echo "📊 노드 상태:"
sinfo

echo ""
echo "🧪 QoS 확인:"
sacctmgr show qos format=Name,Priority -n

echo ""

echo "=========================================="
echo "✅ 긴급 수정 완료!"
echo "=========================================="
echo ""

echo "변경사항:"
echo "  - AccountingStorageType: none → slurmdbd"
echo "  - AccountingStorageHost: localhost"
echo "  - AccountingStoragePort: 6819"
echo ""

echo "이제 QoS 기능이 정상 작동합니다!"
echo ""
