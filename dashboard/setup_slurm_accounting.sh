#!/bin/bash

echo "=========================================="
echo "🔧 Slurm Accounting (slurmdbd) 설정"
echo "=========================================="
echo ""

# 1. Check if slurmdbd is installed (소스 빌드 Slurm 23.x 필수)
echo "1️⃣  slurmdbd 설치 확인..."

# 소스 빌드 Slurm 경로 확인
SLURMDBD_PATH=""
SLURM_PREFIX=""
for prefix in /usr/local/slurm /opt/slurm; do
    if [[ -x "$prefix/sbin/slurmdbd" ]]; then
        SLURMDBD_PATH="$prefix/sbin/slurmdbd"
        SLURM_PREFIX="$prefix"
        break
    fi
done

if [[ -n "$SLURMDBD_PATH" ]]; then
    echo "   ✅ slurmdbd가 이미 설치되어 있습니다"
    echo "   경로: $SLURMDBD_PATH"

    # 버전 확인
    SLURM_VERSION=$("$SLURMDBD_PATH" -V 2>/dev/null | head -1 || echo "unknown")
    echo "   버전: $SLURM_VERSION"

    # 버전 23.x 이상인지 확인
    MAJOR_VERSION=$(echo "$SLURM_VERSION" | grep -oP 'slurm \K[0-9]+' | head -1)
    if [[ "$MAJOR_VERSION" -lt 23 ]]; then
        echo ""
        echo "   ⚠️  경고: Slurm 버전이 23.x 미만입니다!"
        echo "   Slurm 23.11.10 이상을 설치해주세요."
    fi
else
    echo "   ❌ slurmdbd가 설치되지 않았습니다"
    echo ""
    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   소스 빌드 Slurm 23.x가 필요합니다!"
    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "   apt/yum 패키지의 Slurm (21.x)은 지원하지 않습니다."
    echo ""
    echo "   설치 방법:"
    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   1. 프리빌드 패키지 사용 (권장):"
    echo "      cd offline_packages/slurm"
    echo "      tar -xzf slurm-23.11.10-prebuilt.tar.gz"
    echo "      sudo bash deploy_slurm.sh"
    echo ""
    echo "   2. 소스에서 빌드:"
    echo "      cd offline_packages/slurm"
    echo "      bash build_slurm_package.sh"
    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "   설치 후 다시 이 스크립트를 실행해주세요."
    exit 1
fi

# 2. Check for MySQL/MariaDB
echo ""
echo "2️⃣  Database 확인 (slurmdbd는 MySQL/MariaDB 필요)..."
if command -v mysql &> /dev/null; then
    echo "   ✅ MySQL/MariaDB가 설치되어 있습니다"
else
    echo "   ❌ MySQL/MariaDB가 설치되지 않았습니다"
    echo ""
    echo "   설치 방법:"
    echo "   sudo apt-get install mariadb-server"
    echo ""
    read -p "   지금 설치하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt-get install -y mariadb-server
        sudo systemctl start mariadb
        sudo systemctl enable mariadb
    else
        echo "   설치를 건너뜁니다."
        exit 1
    fi
fi

# 3. Create Slurm database
echo ""
echo "3️⃣  Slurm 데이터베이스 생성..."
echo ""
echo "   다음 SQL 명령어를 실행해야 합니다:"
echo ""
echo "   sudo mysql -e \"CREATE DATABASE slurm_acct_db;\""
echo "   sudo mysql -e \"CREATE USER 'slurm'@'localhost' IDENTIFIED BY 'slurmdbpass';\""
echo "   sudo mysql -e \"GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';\""
echo "   sudo mysql -e \"FLUSH PRIVILEGES;\""
echo ""
read -p "   지금 실행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS slurm_acct_db;"
    sudo mysql -e "CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY 'slurmdbpass';"
    sudo mysql -e "GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
    echo "   ✅ 데이터베이스 생성 완료"
else
    echo "   건너뜁니다."
fi

# 4. Check slurmdbd.conf
echo ""
echo "4️⃣  slurmdbd.conf 확인..."
SLURMDBD_CONF="/usr/local/slurm/etc/slurmdbd.conf"
if [ ! -f "$SLURMDBD_CONF" ]; then
    SLURMDBD_CONF="/etc/slurm/slurmdbd.conf"
fi

if [ -f "$SLURMDBD_CONF" ]; then
    echo "   ✅ slurmdbd.conf 존재: $SLURMDBD_CONF"
else
    echo "   ❌ slurmdbd.conf가 없습니다"
    echo ""
    echo "   생성 위치를 선택하세요:"
    echo "   1) /usr/local/slurm/etc/slurmdbd.conf"
    echo "   2) /etc/slurm/slurmdbd.conf"
    read -p "   선택 (1/2): " choice
    
    if [ "$choice" = "1" ]; then
        SLURMDBD_CONF="/usr/local/slurm/etc/slurmdbd.conf"
    else
        SLURMDBD_CONF="/etc/slurm/slurmdbd.conf"
    fi
    
    echo "   생성 중: $SLURMDBD_CONF"
fi

# 5. Show next steps
echo ""
echo "=========================================="
echo "📋 다음 단계"
echo "=========================================="
echo ""
echo "1. slurmdbd.conf 설정 확인/생성:"
echo "   sudo vi $SLURMDBD_CONF"
echo ""
echo "   최소 설정:"
echo "   -----------------------------------"
echo "   AuthType=auth/munge"
echo "   DbdHost=localhost"
echo "   StorageType=accounting_storage/mysql"
echo "   StorageHost=localhost"
echo "   StorageUser=slurm"
echo "   StoragePass=slurmdbpass"
echo "   StorageLoc=slurm_acct_db"
echo "   LogFile=/var/log/slurm/slurmdbd.log"
echo "   PidFile=/var/run/slurm/slurmdbd.pid"
echo "   SlurmUser=slurm"
echo "   -----------------------------------"
echo ""
echo "2. 로그 디렉토리 생성:"
echo "   sudo mkdir -p /var/log/slurm"
echo "   sudo chown slurm:slurm /var/log/slurm"
echo ""
echo "3. slurmdbd 시작:"
echo "   sudo systemctl start slurmdbd"
echo "   sudo systemctl enable slurmdbd"
echo ""
echo "4. slurm.conf에 accounting 추가:"
echo "   AccountingStorageType=accounting_storage/slurmdbd"
echo "   AccountingStorageHost=localhost"
echo ""
echo "5. slurmctld 재시작:"
echo "   sudo systemctl restart slurmctld"
echo ""
echo "=========================================="
