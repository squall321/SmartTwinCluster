#!/bin/bash

echo "=========================================="
echo "🔧 slurmdbd systemd 서비스 수정"
echo "=========================================="
echo ""

# 1. 서비스 중지
echo "1️⃣  slurmdbd 서비스 중지..."
sudo systemctl stop slurmdbd

# 2. 수정된 서비스 파일 생성
echo "2️⃣  systemd 서비스 파일 수정..."

sudo tee /etc/systemd/system/slurmdbd.service > /dev/null << 'EOF'
[Unit]
Description=Slurm Database Daemon
After=network.target munge.service mariadb.service
Wants=mariadb.service
Requires=munge.service

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmdbd
ExecStart=/usr/local/slurm/sbin/slurmdbd -D -vvv
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TimeoutStartSec=300
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "✅ 서비스 파일 수정 완료"
echo ""

# 3. systemd 리로드
echo "3️⃣  systemd daemon-reload..."
sudo systemctl daemon-reload

# 4. 로그 디렉토리 권한 확인
echo "4️⃣  로그 디렉토리 권한 확인..."
sudo mkdir -p /var/log/slurm /var/run/slurm
sudo chown -R slurm:slurm /var/log/slurm /var/run/slurm

# 5. MariaDB 설정 최적화
echo "5️⃣  MariaDB 설정 최적화..."
sudo mysql << 'MYSQL_OPTIMIZE'
SET GLOBAL innodb_buffer_pool_size = 134217728;
SET GLOBAL innodb_lock_wait_timeout = 900;
MYSQL_OPTIMIZE

echo "✅ MariaDB 설정 최적화 완료"
echo ""

# 6. slurmdbd 재시작
echo "6️⃣  slurmdbd 재시작..."
sudo systemctl start slurmdbd

# 7. 시작 대기
echo "   대기 중 (10초)..."
sleep 10

# 8. 상태 확인
echo ""
echo "7️⃣  slurmdbd 상태 확인..."
if sudo systemctl is-active --quiet slurmdbd; then
    echo "✅ slurmdbd 시작 성공!"
    echo ""
    
    # 버전 확인
    VERSION=$(/usr/local/slurm/sbin/slurmdbd -V 2>&1 | head -1)
    echo "   $VERSION"
    echo ""
    
    # 로그 확인
    echo "📝 최근 로그:"
    sudo tail -10 /var/log/slurm/slurmdbd.log
else
    echo "❌ slurmdbd 시작 실패"
    echo ""
    echo "🔍 로그 확인:"
    sudo journalctl -u slurmdbd -n 30 --no-pager
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ slurmdbd 수정 완료!"
echo "=========================================="
echo ""
echo "변경 사항:"
echo "  - Type: forking → simple"
echo "  - TimeoutStartSec: 90s → 300s"
echo "  - Restart: on-failure 추가"
echo "  - 로그 레벨: verbose (-vvv)"
echo ""
