#!/bin/bash
################################################################################
# slurmctld 중요 문제 수정 스크립트
# - GID 0 문제 (SlurmUser/SlurmdUser 설정)
# - 노드 이름 오류 수정
# - systemd 서비스 파일 수정
################################################################################

set -e

echo "========================================"
echo "🔧 slurmctld 중요 문제 수정"
echo "========================================"
echo ""

SLURM_CONF="/usr/local/slurm/etc/slurm.conf"
SERVICE_FILE="/etc/systemd/system/slurmctld.service"

echo "📋 Step 1: slurm.conf 확인 및 백업"
echo "----------------------------------------"
if [ ! -f "$SLURM_CONF" ]; then
    echo "❌ $SLURM_CONF 파일이 없습니다"
    exit 1
fi

sudo cp "$SLURM_CONF" "${SLURM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
echo "✅ 백업 완료: ${SLURM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
echo ""

echo "📋 Step 2: slurm.conf에서 SlurmUser/SlurmdUser 확인"
echo "----------------------------------------"
echo "현재 설정:"
sudo grep -E "^SlurmUser|^SlurmdUser" "$SLURM_CONF" || echo "설정 없음"
echo ""

# SlurmUser와 SlurmdUser가 없으면 추가, 있으면 수정
if ! sudo grep -q "^SlurmUser=" "$SLURM_CONF"; then
    echo "SlurmUser 추가 중..."
    sudo sed -i '/^ClusterName=/a SlurmUser=slurm' "$SLURM_CONF"
else
    echo "SlurmUser 수정 중..."
    sudo sed -i 's/^SlurmUser=.*/SlurmUser=slurm/' "$SLURM_CONF"
fi

if ! sudo grep -q "^SlurmdUser=" "$SLURM_CONF"; then
    echo "SlurmdUser 추가 중..."
    sudo sed -i '/^SlurmUser=/a SlurmdUser=slurm' "$SLURM_CONF"
else
    echo "SlurmdUser 수정 중..."
    sudo sed -i 's/^SlurmdUser=.*/SlurmdUser=slurm/' "$SLURM_CONF"
fi

echo "✅ 수정 완료"
echo "새로운 설정:"
sudo grep -E "^SlurmUser|^SlurmdUser" "$SLURM_CONF"
echo ""

echo "📋 Step 3: 파티션의 노드 이름 확인 및 수정"
echo "----------------------------------------"
echo "현재 노드 정의:"
sudo grep "^NodeName=" "$SLURM_CONF" || echo "노드 정의 없음"
echo ""
echo "현재 파티션 정의:"
sudo grep "^PartitionName=" "$SLURM_CONF" || echo "파티션 정의 없음"
echo ""

# my_multihead_cluster.yaml에 따르면 노드는 node001, node002
# 파티션에서 node[1-2]가 아니라 node[001-002]로 수정 필요

echo "파티션 노드 이름 수정 중..."
sudo sed -i 's/PartitionName=normal Nodes=node\[1-2\]/PartitionName=normal Nodes=node[001-002]/' "$SLURM_CONF"
sudo sed -i 's/PartitionName=debug Nodes=node1/PartitionName=debug Nodes=node001/' "$SLURM_CONF"

echo "✅ 수정 완료"
echo "새로운 파티션 설정:"
sudo grep "^PartitionName=" "$SLURM_CONF"
echo ""

echo "📋 Step 4: systemd 서비스 파일 수정"
echo "----------------------------------------"
if [ ! -f "$SERVICE_FILE" ]; then
    echo "❌ $SERVICE_FILE 파일이 없습니다"
    exit 1
fi

sudo cp "$SERVICE_FILE" "${SERVICE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# PIDFile 경로를 /run/slurmctld.pid로 통일
echo "PIDFile 경로 수정 중..."
sudo sed -i 's|PIDFile=/var/run/slurmctld.pid|PIDFile=/run/slurmctld.pid|' "$SERVICE_FILE"
sudo sed -i 's|PIDFile=/var/spool/slurm/state/slurmctld.pid|PIDFile=/run/slurmctld.pid|' "$SERVICE_FILE"

echo "✅ systemd 서비스 파일 수정 완료"
echo ""

echo "📋 Step 5: slurm.conf에서 PidFile 설정 추가/수정"
echo "----------------------------------------"
if ! sudo grep -q "^SlurmctldPidFile=" "$SLURM_CONF"; then
    echo "SlurmctldPidFile 추가 중..."
    sudo sed -i '/^StateSaveLocation=/a SlurmctldPidFile=/run/slurmctld.pid' "$SLURM_CONF"
else
    echo "SlurmctldPidFile 수정 중..."
    sudo sed -i 's|^SlurmctldPidFile=.*|SlurmctldPidFile=/run/slurmctld.pid|' "$SLURM_CONF"
fi

if ! sudo grep -q "^SlurmdPidFile=" "$SLURM_CONF"; then
    echo "SlurmdPidFile 추가 중..."
    sudo sed -i '/^SlurmctldPidFile=/a SlurmdPidFile=/run/slurmd.pid' "$SLURM_CONF"
else
    echo "SlurmdPidFile 수정 중..."
    sudo sed -i 's|^SlurmdPidFile=.*|SlurmdPidFile=/run/slurmd.pid|' "$SLURM_CONF"
fi

echo "✅ PidFile 설정 완료"
echo ""

echo "📋 Step 6: 디렉토리 권한 재설정"
echo "----------------------------------------"
sudo mkdir -p /var/spool/slurm/state
sudo mkdir -p /var/spool/slurm/d
sudo mkdir -p /var/log/slurm
sudo mkdir -p /run/slurm

sudo chown -R slurm:slurm /var/spool/slurm
sudo chown -R slurm:slurm /var/log/slurm
sudo chown -R slurm:slurm /run/slurm

sudo chmod 755 /var/spool/slurm
sudo chmod 755 /var/spool/slurm/state
sudo chmod 755 /var/log/slurm
sudo chmod 755 /run/slurm

echo "✅ 디렉토리 권한 설정 완료"
echo ""

echo "📋 Step 7: systemd 타임아웃 설정"
echo "----------------------------------------"
sudo mkdir -p /etc/systemd/system/slurmctld.service.d

sudo tee /etc/systemd/system/slurmctld.service.d/timeout.conf > /dev/null <<EOF
[Service]
TimeoutStartSec=300
TimeoutStopSec=300
EOF

echo "✅ 타임아웃 300초로 설정"
echo ""

echo "📋 Step 8: systemd 리로드"
echo "----------------------------------------"
sudo systemctl daemon-reload
echo "✅ systemd 설정 리로드 완료"
echo ""

echo "📋 Step 9: 기존 프로세스 및 PID 파일 정리"
echo "----------------------------------------"
sudo systemctl stop slurmctld 2>/dev/null || true
sudo pkill -9 slurmctld 2>/dev/null || true
sudo rm -f /run/slurmctld.pid
sudo rm -f /var/run/slurmctld.pid
sudo rm -f /var/spool/slurm/state/slurmctld.pid
echo "✅ 정리 완료"
echo ""

echo "📋 Step 10: Munge 재시작"
echo "----------------------------------------"
sudo systemctl restart munge
sleep 2

if systemctl is-active --quiet munge; then
    echo "✅ Munge 정상 작동"
else
    echo "❌ Munge 오류"
    systemctl status munge --no-pager
    exit 1
fi
echo ""

echo "📋 Step 11: 설정 파일 최종 검증"
echo "----------------------------------------"
echo "주요 설정 확인:"
echo ""
echo "1. 사용자 설정:"
sudo grep -E "^SlurmUser|^SlurmdUser" "$SLURM_CONF"
echo ""
echo "2. PID 파일 설정:"
sudo grep -E "^SlurmctldPidFile|^SlurmdPidFile" "$SLURM_CONF"
echo ""
echo "3. 노드 정의:"
sudo grep "^NodeName=" "$SLURM_CONF"
echo ""
echo "4. 파티션 정의:"
sudo grep "^PartitionName=" "$SLURM_CONF"
echo ""

echo "📋 Step 12: slurmctld 서비스 시작"
echo "----------------------------------------"
echo "slurmctld 시작 중..."

if sudo systemctl start slurmctld; then
    echo "✅ slurmctld 시작 명령 성공"
    sleep 5
    
    if systemctl is-active --quiet slurmctld; then
        echo "✅✅ slurmctld 정상 작동 중!"
        echo ""
        systemctl status slurmctld --no-pager -l
        
        echo ""
        echo "✅ slurmctld 서비스 활성화..."
        sudo systemctl enable slurmctld
        
    else
        echo "❌ slurmctld가 시작되었으나 곧 중단됨"
        echo ""
        echo "상세 로그:"
        journalctl -u slurmctld -n 30 --no-pager
        exit 1
    fi
else
    echo "❌ slurmctld 시작 실패"
    echo ""
    echo "상세 로그:"
    journalctl -u slurmctld -n 30 --no-pager
    exit 1
fi

echo ""
echo "========================================"
echo "✅ 수정 완료!"
echo "========================================"
echo ""
echo "📊 확인 명령어:"
echo "   systemctl status slurmctld"
echo "   journalctl -u slurmctld -f"
echo "   sinfo"
echo "   scontrol show config | grep -i user"
echo ""
