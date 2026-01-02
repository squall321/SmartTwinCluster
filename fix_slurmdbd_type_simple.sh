#!/bin/bash
################################################################################
# slurmdbd Type=simple 수정 스크립트
################################################################################

set -e

echo "================================================================================"
echo "🔧 slurmdbd.service Type=simple 수정"
echo "================================================================================"
echo ""

# 1. 기존 slurmdbd 프로세스 정리
echo "1️⃣  기존 slurmdbd 프로세스 정리..."
sudo systemctl stop slurmdbd || true
sleep 2
pkill -9 slurmdbd 2>/dev/null || true
sleep 1
echo "✅ 프로세스 정리 완료"
echo ""

# 2. PID 파일 삭제
echo "2️⃣  PID 파일 삭제..."
sudo rm -f /var/run/slurm/slurmdbd.pid
sudo rm -f /run/slurm/slurmdbd.pid
echo "✅ PID 파일 삭제 완료"
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
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStartPre=/bin/sh -c 'pkill -9 slurmdbd || true'
ExecStartPre=/bin/sleep 1
ExecStart=/usr/local/slurm/sbin/slurmdbd -D $SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmdbd.pid
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

# 5. PID 디렉토리 생성
echo "5️⃣  PID 디렉토리 생성..."
sudo mkdir -p /run/slurm
sudo chown slurm:slurm /run/slurm
sudo chmod 755 /run/slurm
echo "✅ PID 디렉토리 생성 완료"
echo ""

# 6. slurmdbd 시작
echo "6️⃣  slurmdbd 시작..."
sudo systemctl start slurmdbd
sleep 5

if systemctl is-active --quiet slurmdbd; then
    echo "✅ slurmdbd 시작 성공"
else
    echo "⚠️  slurmdbd 시작 확인 필요"
    echo "  상태 확인: sudo systemctl status slurmdbd"
fi
echo ""

# 7. 상태 확인
echo "7️⃣  상태 확인..."
echo ""
sudo systemctl status slurmdbd --no-pager || true
echo ""

################################################################################
# 완료
################################################################################

echo "================================================================================"
echo "🎉 slurmdbd Type=simple 수정 완료!"
echo "================================================================================"
echo ""

echo "✅ 변경사항:"
echo "   - Type=simple (foreground 실행)"
echo "   - ExecStart: -D 옵션 추가"
echo "   - ExecStartPre: 좀비 프로세스 자동 정리"
echo "   - PIDFile=/run/slurm/slurmdbd.pid"
echo ""

echo "🧪 테스트:"
echo "   # 서비스 상태"
echo "   sudo systemctl status slurmdbd"
echo ""
echo "   # QoS 확인"
echo "   sacctmgr show qos"
echo ""
echo "   # Slurm 상태"
echo "   sinfo"
echo ""

echo "================================================================================"
