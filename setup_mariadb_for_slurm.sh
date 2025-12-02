#!/bin/bash
################################################################################
# MariaDB 설정 통일 - mysql_config 대신 mariadb 사용
################################################################################

echo "=========================================="
echo "🔧 MariaDB 설정 확인 및 통일"
echo "=========================================="
echo ""

# 1. MariaDB 개발 라이브러리 확인
echo "1️⃣  MariaDB 개발 라이브러리 확인..."

if ! dpkg -l | grep -q "libmariadb-dev"; then
    echo "📦 libmariadb-dev 설치 중..."
    sudo apt-get update
    sudo apt-get install -y libmariadb-dev libmariadb-dev-compat
    echo "✅ 설치 완료"
else
    echo "✅ 이미 설치됨"
    dpkg -l | grep libmariadb
fi

echo ""

# 2. mariadb_config 경로 확인
echo "2️⃣  mariadb_config 확인..."

MARIADB_CONFIG=$(which mariadb_config 2>/dev/null)

if [ -n "$MARIADB_CONFIG" ]; then
    echo "✅ mariadb_config 찾음: $MARIADB_CONFIG"
else
    # 일반적인 위치들 확인
    for path in /usr/bin/mariadb_config /usr/local/bin/mariadb_config; do
        if [ -f "$path" ]; then
            MARIADB_CONFIG="$path"
            echo "✅ mariadb_config 찾음: $MARIADB_CONFIG"
            break
        fi
    done
    
    if [ -z "$MARIADB_CONFIG" ]; then
        echo "❌ mariadb_config를 찾을 수 없습니다"
        echo "   libmariadb-dev를 설치하세요"
        exit 1
    fi
fi

echo ""
echo "MariaDB 설정:"
echo "  버전: $($MARIADB_CONFIG --version)"
echo "  Include: $($MARIADB_CONFIG --include)"
echo "  Libs: $($MARIADB_CONFIG --libs)"

echo ""
echo "=========================================="
echo "✅ MariaDB 설정 확인 완료"
echo "=========================================="
echo ""

echo "Slurm configure에 사용할 옵션:"
echo "  --with-mysql_config=$MARIADB_CONFIG"
echo ""
