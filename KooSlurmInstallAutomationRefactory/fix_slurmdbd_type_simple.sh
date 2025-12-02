#!/bin/bash
################################################################################
# slurmdbd를 Type=simple로 즉시 수정 및 재시작
################################################################################

set -e

echo "================================================================================"
echo "🔧 slurmdbd Type=simple 즉시 적용"
echo "================================================================================"
echo ""

# 1. 현재 상태 확인
echo "1️⃣  현재 slurmdbd 상태 확인..."
echo ""
sudo systemctl status slurmdbd --no-pager || true
echo ""

# 2. slurmdbd 중지
echo "2️⃣  slurmdbd 중지 중..."
sudo systemctl stop slurmdbd || true
sleep 2
echo "✅ slurmdbd 중지 완료"
echo ""

# 3. Type=simple로 서비스 파일 재생성
echo "3️⃣  slurmdbd.service Type=simple로 재생성..."

sudo tee /etc/systemd/system/slurmdbd.service > /dev/null << 'EOF'
[Unit]
Description=Slurm Database Daemon
After=network.target munge.service mariadb.service
Wants=mariadb.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurmdbd.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmdbd
ExecStart=/usr/local/slurm/sbin/slurmdbd $SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmdbd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "✅ slurmdbd.service Type=simple로 재생성 완료"
echo ""

# 4. systemd 리로드
echo "4️⃣  systemd daemon-reload..."
sudo systemctl daemon-reload
echo "✅ systemd 리로드 완료"
echo ""

# 5. slurmdbd 재시작
echo "5️⃣  slurmdbd 재시작..."
sudo systemctl start slurmdbd
sleep 3

if sudo systemctl is-active --quiet slurmdbd; then
    echo "✅ slurmdbd 시작 성공!"
    
    # 버전 확인
    VERSION=$(/usr/local/slurm/sbin/slurmdbd -V 2>&1 | head -1)
    echo "   $VERSION"
else
    echo "❌ slurmdbd 시작 실패"
    echo ""
    echo "로그 확인:"
    sudo journalctl -u slurmdbd -n 50 --no-pager
    exit 1
fi

echo ""

# 6. Type 확인
echo "6️⃣  Type 확인..."
TYPE=$(systemctl show slurmdbd | grep "^Type=" | cut -d'=' -f2)
echo "   현재 Type: $TYPE"

if [ "$TYPE" = "simple" ]; then
    echo "   ✅ Type=simple 확인!"
else
    echo "   ⚠️  Type이 simple이 아닙니다: $TYPE"
fi

echo ""

# 7. slurmctld 재시작
echo "7️⃣  slurmctld 재시작 (Accounting 연결)..."
sudo systemctl restart slurmctld
sleep 2

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 재시작 성공!"
else
    echo "❌ slurmctld 재시작 실패"
    sudo systemctl status slurmctld --no-pager
    exit 1
fi

echo ""

################################################################################
# 완료
################################################################################

echo "================================================================================"
echo "🎉 slurmdbd Type=simple 적용 완료!"
echo "================================================================================"
echo ""

echo "✅ 변경사항:"
echo "   - slurmdbd.service: Type=simple"
echo "   - ExecStart: -D 옵션 제거"
echo "   - slurmdbd, slurmctld 재시작 완료"
echo ""

echo "🧪 테스트:"
echo "   # Type 확인"
echo "   systemctl show slurmdbd | grep Type"
echo ""
echo "   # QoS 확인"
echo "   sacctmgr show qos"
echo ""
echo "   # Slurm 상태"
echo "   sinfo"
echo ""

echo "================================================================================"
