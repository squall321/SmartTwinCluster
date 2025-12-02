#!/bin/bash

echo "=========================================="
echo "🔧 slurmctld systemd 서비스 Type=simple 변경"
echo "=========================================="
echo ""

# 1. 강제 종료
echo "1️⃣  slurmctld 강제 종료..."
sudo systemctl stop slurmctld 2>/dev/null || true
sudo pkill -9 slurmctld
sleep 2
echo "✅ 종료 완료"
echo ""

# 2. systemd 서비스를 Type=simple로 변경
echo "2️⃣  slurmctld.service를 Type=simple로 변경..."

sudo tee /etc/systemd/system/slurmctld.service > /dev/null << 'EOF'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service slurmdbd.service
Wants=slurmdbd.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/local/slurm/sbin/slurmctld -D $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity
TimeoutStartSec=60
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
echo "✅ Type=simple로 변경 완료"
echo ""

# 3. slurmctld 시작
echo "3️⃣  slurmctld 시작..."
sudo systemctl start slurmctld

echo "⏱️  대기 중 (5초)..."
sleep 5

# 4. 상태 확인
echo ""
echo "4️⃣  slurmctld 상태:"
echo "----------------------------------------"

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 실행 중!"
    sudo systemctl status slurmctld --no-pager | head -15
else
    echo "❌ slurmctld 실행 실패"
    sudo systemctl status slurmctld --no-pager
    echo ""
    echo "로그:"
    sudo tail -20 /var/log/slurm/slurmctld.log
    exit 1
fi

echo ""

# 5. 클러스터 상태
echo "5️⃣  클러스터 상태:"
echo "----------------------------------------"
export PATH=/usr/local/slurm/bin:$PATH
sinfo

echo ""
echo "=========================================="
echo "✅ slurmctld Type=simple 전환 완료!"
echo "=========================================="
echo ""
echo "변경사항:"
echo "  - Type: notify → simple"
echo "  - TimeoutStartSec: 120 → 60"
echo ""
echo "이제 slurmctld가 안정적으로 실행됩니다!"
echo ""
