#!/bin/bash
################################################################################
# Slurm Accounting (slurmdbd) 설치 스크립트
# QoS 기능 활성화를 위한 필수 구성 요소
################################################################################

set -e

echo "================================================================================"
echo "🔧 Slurm Accounting (slurmdbd) 설치"
echo "================================================================================"
echo ""
echo "slurmdbd는 Slurm의 Accounting 기능을 제공하며,"
echo "QoS (Quality of Service) 사용에 필수입니다."
echo ""

################################################################################
# 1. MariaDB/MySQL 설치
################################################################################

echo "1️⃣  MariaDB 설치 확인..."
echo "--------------------------------------------------------------------------------"

if command -v mysql &> /dev/null; then
    echo "✅ MariaDB가 이미 설치되어 있습니다"
    MYSQL_VERSION=$(mysql --version | head -1)
    echo "   $MYSQL_VERSION"
else
    echo "📦 MariaDB 설치 중..."
    sudo apt-get update
    sudo apt-get install -y mariadb-server mariadb-client libmariadb-dev
    
    # MariaDB 시작
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    
    echo "✅ MariaDB 설치 완료"
fi

echo ""

################################################################################
# 2. Slurm Accounting 데이터베이스 생성
################################################################################

echo "2️⃣  Slurm Accounting 데이터베이스 생성..."
echo "--------------------------------------------------------------------------------"

# 데이터베이스 존재 확인
DB_EXISTS=$(sudo mysql -e "SHOW DATABASES LIKE 'slurm_acct_db';" | grep -c "slurm_acct_db" || true)

if [ "$DB_EXISTS" -gt 0 ]; then
    echo "✅ slurm_acct_db 데이터베이스가 이미 존재합니다"
else
    echo "📝 데이터베이스 생성 중..."
    
    sudo mysql << 'MYSQL_SETUP'
CREATE DATABASE slurm_acct_db;
CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY 'slurmdbpass';
GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SETUP
    
    echo "✅ 데이터베이스 생성 완료"
fi

echo ""

################################################################################
# 3. slurmdbd 바이너리 확인
################################################################################

echo "3️⃣  slurmdbd 바이너리 확인..."
echo "--------------------------------------------------------------------------------"

SLURMDBD_PATH="/usr/local/slurm/sbin/slurmdbd"

if [ -f "$SLURMDBD_PATH" ]; then
    echo "✅ slurmdbd가 이미 설치되어 있습니다: $SLURMDBD_PATH"
    VERSION=$($SLURMDBD_PATH -V 2>&1 | head -1)
    echo "   $VERSION"
else
    echo "❌ slurmdbd가 설치되지 않았습니다"
    echo ""
    echo "💡 Slurm을 다시 빌드해야 합니다:"
    echo "   Slurm 소스 디렉토리에서:"
    echo "   ./configure --prefix=/usr/local/slurm --with-mysql_config=/usr/bin/mysql_config"
    echo "   make -j$(nproc)"
    echo "   sudo make install"
    echo ""
    
    read -p "지금 Slurm을 다시 빌드하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Slurm 재빌드 (MySQL 지원 포함)
        if [ -f "./install_slurm_cgroup_v2.sh" ]; then
            echo "📦 Slurm 재빌드 중 (MySQL 지원 포함)..."
            sudo bash install_slurm_cgroup_v2.sh
        else
            echo "❌ install_slurm_cgroup_v2.sh를 찾을 수 없습니다"
            exit 1
        fi
    else
        echo "⏭️  Slurm 재빌드 건너뜀"
        exit 1
    fi
fi

echo ""

################################################################################
# 4. slurmdbd.conf 생성
################################################################################

echo "4️⃣  slurmdbd.conf 생성..."
echo "--------------------------------------------------------------------------------"

SLURMDBD_CONF="/usr/local/slurm/etc/slurmdbd.conf"

if [ -f "$SLURMDBD_CONF" ]; then
    echo "⚠️  $SLURMDBD_CONF가 이미 존재합니다"
    read -p "덮어쓰시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "⏭️  slurmdbd.conf 생성 건너뜀"
    else
        CREATE_CONF=true
    fi
else
    CREATE_CONF=true
fi

if [ "$CREATE_CONF" = true ]; then
    # 실제 호스트명 가져오기
    HOSTNAME=$(hostname -f)

    sudo tee "$SLURMDBD_CONF" > /dev/null << SLURMDBD_CONF_EOF
#
# slurmdbd.conf - Slurm Database Daemon Configuration
#

# Authentication
AuthType=auth/munge
AuthInfo=/var/run/munge/munge.socket.2

# Database Connection
DbdHost=$HOSTNAME
StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=3306
StorageUser=slurm
StoragePass=slurmdbpass
StorageLoc=slurm_acct_db

# Logging
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/run/slurm/slurmdbd.pid
SlurmUser=slurm

# Debug
DebugLevel=info
SLURMDBD_CONF_EOF

    # 권한 설정 (600 - 보안상 중요)
    sudo chmod 600 "$SLURMDBD_CONF"
    sudo chown slurm:slurm "$SLURMDBD_CONF"

    echo "✅ slurmdbd.conf 생성 완료: $SLURMDBD_CONF"
    echo "   DbdHost=$HOSTNAME (실제 호스트명)"
fi

echo ""

################################################################################
# 5. 로그 디렉토리 생성
################################################################################

echo "5️⃣  로그 디렉토리 생성..."
echo "--------------------------------------------------------------------------------"

sudo mkdir -p /var/log/slurm
sudo mkdir -p /var/run/slurm
sudo chown -R slurm:slurm /var/log/slurm
sudo chown -R slurm:slurm /var/run/slurm

echo "✅ 로그 디렉토리 생성 완료"
echo ""

################################################################################
# 6. slurmdbd systemd 서비스 생성
################################################################################

echo "6️⃣  slurmdbd systemd 서비스 생성..."
echo "--------------------------------------------------------------------------------"

SLURMDBD_SERVICE="/etc/systemd/system/slurmdbd.service"

sudo tee "$SLURMDBD_SERVICE" > /dev/null << 'SLURMDBD_SERVICE_EOF'
[Unit]
Description=Slurm Database Daemon
After=network.target munge.service mariadb.service mysql.service
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
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SLURMDBD_SERVICE_EOF

sudo systemctl daemon-reload

echo "✅ systemd 서비스 생성 완료"
echo ""

################################################################################
# 7. slurm.conf에 Accounting 설정 추가
################################################################################

echo "7️⃣  slurm.conf에 Accounting 설정 추가..."
echo "--------------------------------------------------------------------------------"

SLURM_CONF="/usr/local/slurm/etc/slurm.conf"

if [ -f "$SLURM_CONF" ]; then
    # 기존 Accounting 설정 제거 (none 설정)
    if grep -q "AccountingStorageType.*none" "$SLURM_CONF"; then
        echo "📝 기존 AccountingStorageType=none 제거 중..."
        sudo sed -i '/^AccountingStorageType=accounting_storage\/none/d' "$SLURM_CONF"
    fi
    
    # Accounting 설정이 이미 있는지 확인
    if grep -q "AccountingStorageType.*slurmdbd" "$SLURM_CONF"; then
        echo "✅ slurm.conf에 이미 Accounting 설정이 있습니다"
    else
        echo "📝 slurm.conf에 Accounting 설정 추가 중..."
        
        # 백업
        sudo cp "$SLURM_CONF" "${SLURM_CONF}.backup_$(date +%Y%m%d_%H%M%S)"
        
        # Accounting 설정 추가 (ClusterName 다음에)
        sudo sed -i '/^ClusterName=/a \
# Accounting\
AccountingStorageType=accounting_storage/slurmdbd\
AccountingStorageHost=localhost\
AccountingStoragePort=6819' "$SLURM_CONF"
        
        echo "✅ slurm.conf 업데이트 완료"
    fi
else
    echo "⚠️  slurm.conf를 찾을 수 없습니다: $SLURM_CONF"
    echo "   먼저 Slurm을 설치하고 설정하세요"
fi

echo ""

################################################################################
# 8. slurmdbd 시작
################################################################################

echo "8️⃣  slurmdbd 서비스 시작..."
echo "--------------------------------------------------------------------------------"

# MariaDB 설정 최적화
echo "📝 MariaDB 설정 최적화..."
sudo mysql << 'MYSQL_OPTIMIZE'
SET GLOBAL innodb_buffer_pool_size = 134217728;
SET GLOBAL innodb_lock_wait_timeout = 900;
MYSQL_OPTIMIZE

echo "✅ MariaDB 최적화 완료"
echo ""

# slurmdbd 시작
sudo systemctl enable slurmdbd
sudo systemctl start slurmdbd

# 시작 대기 (simple 모드는 즉시 반환하지만 실제 초기화는 시간이 걸림)
echo "⏱️  slurmdbd 초기화 대기 중 (10초)..."
sleep 10

if sudo systemctl is-active --quiet slurmdbd; then
    echo "✅ slurmdbd 시작 성공"
    
    # 버전 확인
    VERSION=$(/usr/local/slurm/sbin/slurmdbd -V 2>&1 | head -1)
    echo "   $VERSION"
else
    echo "❌ slurmdbd 시작 실패"
    echo ""
    echo "🔍 로그 확인:"
    sudo journalctl -u slurmdbd -n 50 --no-pager
    echo ""
    echo "또는:"
    echo "   sudo tail -50 /var/log/slurm/slurmdbd.log"
    exit 1
fi

echo ""

################################################################################
# 9. slurmctld 재시작
################################################################################

echo "9️⃣  slurmctld 재시작 (Accounting 설정 적용)..."
echo "--------------------------------------------------------------------------------"

if sudo systemctl is-active --quiet slurmctld; then
    sudo systemctl restart slurmctld
    sleep 2
    
    if sudo systemctl is-active --quiet slurmctld; then
        echo "✅ slurmctld 재시작 성공"
    else
        echo "❌ slurmctld 재시작 실패"
        sudo systemctl status slurmctld --no-pager
    fi
else
    echo "⚠️  slurmctld가 실행되고 있지 않습니다"
    echo "   수동으로 시작하세요: sudo systemctl start slurmctld"
fi

echo ""

################################################################################
# 10. Cluster 및 Account 등록
################################################################################

echo "🔟  Cluster 및 Account 등록..."
echo "--------------------------------------------------------------------------------"

# PATH 설정
export PATH=/usr/local/slurm/bin:$PATH

# Cluster 이름 가져오기
CLUSTER_NAME=$(grep "^ClusterName=" "$SLURM_CONF" | cut -d'=' -f2)

if [ -z "$CLUSTER_NAME" ]; then
    CLUSTER_NAME="mycluster"
    echo "⚠️  ClusterName을 찾을 수 없습니다. 기본값 사용: $CLUSTER_NAME"
fi

echo "📝 Cluster 등록: $CLUSTER_NAME"

# Cluster 등록 (이미 등록되어 있으면 무시)
sudo sacctmgr -i add cluster "$CLUSTER_NAME" 2>&1 | grep -v "already exists" || true

# Default Account 생성
echo "📝 Default Account 생성..."
sudo sacctmgr -i add account root Cluster="$CLUSTER_NAME" Description="Root Account" Organization="Root" 2>&1 | grep -v "already exists" || true

echo "✅ Cluster 및 Account 등록 완료"
echo ""

################################################################################
# 완료
################################################################################

echo "================================================================================"
echo "🎉 Slurm Accounting (slurmdbd) 설치 완료!"
echo "================================================================================"
echo ""

echo "✅ 설치된 구성 요소:"
echo "  - MariaDB"
echo "  - slurm_acct_db 데이터베이스"
echo "  - slurmdbd 데몬"
echo "  - slurm.conf Accounting 설정"
echo ""

echo "🧪 테스트:"
echo ""
echo "1️⃣  QoS 목록 확인:"
echo "   sacctmgr show qos"
echo ""
echo "2️⃣  QoS 생성:"
echo "   sacctmgr -i add qos normal"
echo "   sacctmgr -i add qos high Priority=100"
echo ""
echo "3️⃣  QoS에 제한 설정:"
echo "   sacctmgr -i modify qos normal set MaxTRESPerJob=cpu=128"
echo "   sacctmgr -i modify qos high set MaxTRESPerJob=cpu=256"
echo ""
echo "4️⃣  Cluster 정보 확인:"
echo "   sacctmgr show cluster"
echo ""
echo "5️⃣  Account 확인:"
echo "   sacctmgr show account"
echo ""

echo "📋 서비스 상태 확인:"
echo "   sudo systemctl status slurmdbd"
echo "   sudo systemctl status slurmctld"
echo ""

echo "📝 로그 확인:"
echo "   sudo tail -f /var/log/slurm/slurmdbd.log"
echo ""

echo "🔧 이제 Dashboard에서 Apply Configuration을 실행하면"
echo "   QoS가 정상적으로 생성됩니다!"
echo ""

echo "================================================================================"
