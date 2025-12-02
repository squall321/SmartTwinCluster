#!/bin/bash

echo "=========================================="
echo "🔧 slurmctld를 Type=simple로 전환"
echo "=========================================="
echo ""

echo "1️⃣  현재 Type 확인..."
grep "^Type=" /etc/systemd/system/slurmctld.service || echo "Type 설정 없음"
echo ""

echo "2️⃣  Type=simple로 변경..."
sudo sed -i 's/^Type=.*/Type=simple/' /etc/systemd/system/slurmctld.service

# Type이 없으면 추가
if ! grep -q "^Type=" /etc/systemd/system/slurmctld.service; then
    sudo sed -i '/^\[Service\]/a Type=simple' /etc/systemd/system/slurmctld.service
fi

echo "✅ 변경 완료"
echo ""

echo "3️⃣  변경된 내용:"
echo "----------------------------------------"
grep -A10 "^\[Service\]" /etc/systemd/system/slurmctld.service | head -15
echo ""

echo "4️⃣  daemon-reload..."
sudo systemctl daemon-reload
echo "✅ 완료"
echo ""

echo "5️⃣  slurmctld 재시작..."
sudo systemctl stop slurmctld
sleep 2
sudo systemctl start slurmctld

echo "⏱️  서비스 준비 대기 (10초)..."
sleep 10
echo ""

echo "6️⃣  상태 확인..."
echo "----------------------------------------"
if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 실행 중!"
    sudo systemctl status slurmctld --no-pager | head -15
else
    echo "❌ slurmctld 실행 실패"
    sudo systemctl status slurmctld --no-pager
    exit 1
fi

echo ""
echo "7️⃣  클러스터 상태 확인..."
echo "----------------------------------------"
export PATH=/usr/local/slurm/bin:$PATH
sinfo

echo ""
echo "=========================================="
echo "✅ Type=simple 전환 완료!"
echo "=========================================="
echo ""
echo "📋 Type=simple 사용 시 주의사항:"
echo ""
echo "1. 재시작 후 5-10초 대기:"
echo "   sudo systemctl restart slurmctld"
echo "   sleep 10"
echo "   scontrol show config"
echo ""
echo "2. 자동화 스크립트에서 대기 추가:"
echo "   systemctl restart slurmctld && sleep 10"
echo ""
echo "3. 빠른 연속 명령 시 재시도 로직:"
echo "   for i in {1..5}; do"
echo "     scontrol ping && break"
echo "     sleep 2"
echo "   done"
echo ""
echo "이것만 지키면 Type=simple로 완벽하게 운영 가능합니다! ✅"
echo ""
