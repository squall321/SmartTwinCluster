#!/bin/bash
################################################################################
# slurmdbd 좀비 프로세스 제거 및 Type=simple 완전 수정
################################################################################

set -e

echo "================================================================================"
echo "🔧 slurmdbd 완전 수정 (좀비 프로세스 + Type=simple)"
echo "================================================================================"
echo ""

# 1. 모든 slurmdbd 프로세스 강제 종료
echo "1️⃣  모든 slurmdbd 프로세스 강제 종료..."
sudo systemctl stop slurmdbd || true
sleep 2

# 좀비 프로세스 확인 및 종료
SLURMDBD_PIDS=$(pgrep -f "slurmdbd" || true)
if [ -n "$SLURMDBD_PIDS" ]; then
    echo "   ⚠️  좀비 slurmdbd 프로세스 발견: $SLURMDBD_PIDS"
    echo "   강제 종료 중..."
    sudo kill -9 $SLURMDBD_PIDS || true
    sleep 2
fi

# 재확인
REMAINING=$(pgrep -f "slurmdbd" || true)
if [ -n "$REMAINING" ]; then
    echo "   ❌ 여전히 프로세스가 남아있습니다"
    ps aux | grep slurmdbd | grep -v grep
else
    echo "   ✅ 모든 slurmdbd 프로세스 종료 완료"
fi

echo ""

# 2. PID 파일 정리
echo "2️⃣  PID 파일 정리..."
sudo rm -f /var/run/slurm/slurmdbd.pid
sudo rm -f /run/slurm/slurmdbd.pid
echo "✅ PID 파일 정리 완료"
echo ""

# 3. Type=simple + PIDFile 수정 + NotifyAccess
echo "3️⃣  slurmdbd.service 완전 수정 (Type=simple + forking 방식)..."

sudo tee /etc/systemd/system/slurmdbd.service > /dev/null << 'EOF'
[Unit]
Description=Slurm Database Daemon
After=network.target munge.service mariadb.service
Wants=mariadb.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurmdbd.conf

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmdbd
ExecStart=/usr/local/slurm/sbin/slurmdbd $SLURMDBD_OPTIONS
PIDFile=/run/slurm/slurmdbd.pid
KillMode=mixed
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
TimeoutStartSec=300
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

echo "✅ slurmdbd.service 완전 수정 완료 (Type=forking)"
echo ""

# 4. PID 디렉토리 재생성
echo "4️⃣  PID 디렉토리 재생성..."
sudo mkdir -p /run/slurm
sudo chown slurm:slurm /run/slurm
sudo chmod 755 /run/slurm
echo "✅ PID 디렉토리 생성 완료"
echo ""

# 5. systemd 리로드
echo "5️⃣  systemd daemon-reload..."
sudo systemctl daemon-reload
echo "✅ systemd 리로드 완료"
echo ""

# 6. MariaDB 최적화 (innodb_buffer_pool_size 경고 해결)
echo "6️⃣  MariaDB 설정 최적화..."
sudo mysql << 'MYSQL_FIX'
SET GLOBAL innodb_buffer_pool_size = 536870912;
SET GLOBAL innodb_lock_wait_timeout = 900;
MYSQL_FIX
echo "✅ MariaDB 최적화 완료"
echo ""

# 7. slurmdbd 시작 (최대 대기)
echo "7️⃣  slurmdbd 시작 (최대 300초 대기)..."
sudo systemctl start slurmdbd

echo "   대기 중..."
sleep 10

# 프로세스 확인
if pgrep -f "slurmdbd" > /dev/null; then
    echo "   ✅ slurmdbd 프로세스 실행 중"
    
    # systemd 상태 확인
    if sudo systemctl is-active --quiet slurmdbd; then
        echo "   ✅ slurmdbd 서비스 active"
    else
        echo "   ⚠️  서비스 상태: $(systemctl is-active slurmdbd)"
    fi
else
    echo "   ❌ slurmdbd 프로세스가 없습니다"
fi

echo ""

# 8. 상태 확인
echo "8️⃣  상태 확인..."
echo ""
sudo systemctl status slurmdbd --no-pager || true

echo ""
echo "Type 확인:"
systemctl show slurmdbd | grep "^Type="

echo ""

# 9. slurmctld 재시작
echo "9️⃣  slurmctld 재시작..."
if sudo systemctl is-active --quiet slurmctld; then
    sudo systemctl restart slurmctld
    sleep 3
    
    if sudo systemctl is-active --quiet slurmctld; then
        echo "✅ slurmctld 재시작 성공"
    else
        echo "⚠️  slurmctld 재시작 확인 필요"
    fi
else
    echo "⚠️  slurmctld가 실행 중이 아닙니다"
fi

echo ""

################################################################################
# 완료
################################################################################

echo "================================================================================"
echo "🎉 slurmdbd 수정 완료!"
echo "================================================================================"
echo ""

echo "✅ 변경사항:"
echo "   - Type=forking (더 안정적)"
echo "   - PIDFile=/run/slurm/slurmdbd.pid"
echo "   - KillMode=mixed (좀비 프로세스 방지)"
echo "   - TimeoutStartSec=300 (5분)"
echo "   - 좀비 프로세스 제거"
echo "   - MariaDB 최적화"
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

echo "💡 참고:"
echo "   slurmdbd는 초기화에 시간이 걸립니다 (최대 5분)"
echo "   'activating' 상태가 정상입니다"
echo ""

echo "================================================================================"
