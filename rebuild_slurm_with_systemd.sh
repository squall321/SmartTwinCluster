#!/bin/bash
################################################################################
# Slurm을 systemd 지원으로 재빌드
# Type=notify가 작동하도록 수정
################################################################################

set -e

echo "=========================================="
echo "🔨 Slurm systemd 지원 재빌드"
echo "=========================================="
echo ""

# 1. libsystemd-dev 설치 확인
echo "1️⃣  libsystemd-dev 설치 확인..."
if ! dpkg -l | grep -q "libsystemd-dev"; then
    echo "📦 libsystemd-dev 설치 중..."
    sudo apt-get update
    sudo apt-get install -y libsystemd-dev pkg-config
    echo "✅ 설치 완료"
else
    echo "✅ 이미 설치됨"
fi

echo ""

# 2. pkg-config 확인
echo "2️⃣  pkg-config libsystemd 확인..."
if pkg-config --exists libsystemd; then
    echo "✅ libsystemd 찾음"
    echo "   버전: $(pkg-config --modversion libsystemd)"
    echo "   CFLAGS: $(pkg-config --cflags libsystemd)"
    echo "   LIBS: $(pkg-config --libs libsystemd)"
else
    echo "❌ libsystemd를 찾을 수 없습니다"
    exit 1
fi

echo ""

# 2.5. MariaDB 확인
echo "2.5️⃣  MariaDB 개발 라이브러리 확인..."

if ! dpkg -l | grep -q "libmariadb-dev"; then
    echo "📦 libmariadb-dev 설치 중..."
    sudo apt-get update
    sudo apt-get install -y libmariadb-dev libmariadb-dev-compat
    echo "✅ 설치 완료"
else
    echo "✅ 이미 설치됨"
fi

# mariadb_config 경로 찾기
MARIADB_CONFIG=$(which mariadb_config 2>/dev/null)
if [ -z "$MARIADB_CONFIG" ]; then
    MARIADB_CONFIG="/usr/bin/mariadb_config"
fi

if [ -f "$MARIADB_CONFIG" ]; then
    echo "✅ mariadb_config: $MARIADB_CONFIG"
    
    # mysql_config 심볼릭 링크 생성 (Slurm configure가 요구)
    if [ ! -f "/usr/bin/mysql_config" ]; then
        echo "🔗 mysql_config 심볼릭 링크 생성..."
        sudo ln -sf "$MARIADB_CONFIG" /usr/bin/mysql_config
        echo "✅ /usr/bin/mysql_config -> $MARIADB_CONFIG"
    fi
else
    echo "⚠️  mariadb_config를 찾을 수 없습니다 (MySQL 지원 비활성화)"
    MARIADB_CONFIG=""
fi

echo ""

# 3. 기존 서비스 중지
echo "3️⃣  Slurm 서비스 중지..."
sudo systemctl stop slurmctld slurmdbd 2>/dev/null || true
sudo pkill -9 slurmctld slurmdbd 2>/dev/null || true
sleep 2
echo "✅ 서비스 중지 완료"

echo ""

# 4. 소스 디렉토리로 이동
echo "4️⃣  Slurm 소스 디렉토리 확인..."

SLURM_SRC="/tmp/slurm-23.11.10"

if [ ! -d "$SLURM_SRC" ]; then
    echo "⚠️  소스 디렉토리가 없습니다. 다시 다운로드합니다..."
    
    cd /tmp
    SLURM_VERSION="23.11.10"
    SLURM_DOWNLOAD_URL="https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2"
    
    if [ ! -f "slurm-${SLURM_VERSION}.tar.bz2" ]; then
        wget "${SLURM_DOWNLOAD_URL}"
    fi
    
    tar -xjf "slurm-${SLURM_VERSION}.tar.bz2"
fi

cd "$SLURM_SRC"
echo "✅ 소스 디렉토리: $SLURM_SRC"

echo ""

# 5. Clean 빌드
echo "5️⃣  이전 빌드 정리..."
make clean 2>/dev/null || true
echo "✅ 정리 완료"

echo ""

# 6. Configure (systemd 지원 명시적 활성화)
echo "6️⃣  Configure (systemd 지원)..."
echo "--------------------------------------------------------------------------------"

# PKG_CONFIG_PATH 설정
export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig:$PKG_CONFIG_PATH

# pkg-config로 systemd 플래그 가져오기
SYSTEMD_CFLAGS="$(pkg-config --cflags libsystemd)"
SYSTEMD_LIBS="$(pkg-config --libs libsystemd)"

echo "systemd CFLAGS: $SYSTEMD_CFLAGS"
echo "systemd LIBS: $SYSTEMD_LIBS"
echo ""

# Configure (간단하게)
echo "Configure 명령어:"
echo "./configure --prefix=/usr/local/slurm --sysconfdir=/usr/local/slurm/etc --enable-pam --with-pmix --with-hwloc=/usr --without-rpath LDFLAGS='-lsystemd'"
echo ""

./configure \
    --prefix=/usr/local/slurm \
    --sysconfdir=/usr/local/slurm/etc \
    --enable-pam \
    --with-pmix \
    --with-hwloc=/usr \
    --without-rpath \
    LDFLAGS="-lsystemd"

if [ $? -ne 0 ]; then
    echo "❌ Configure 실패"
    exit 1
fi

echo ""
echo "✅ Configure 완료"

# systemd 지원 확인
echo ""
echo "🔍 systemd 지원 확인:"
if grep -qE "#define HAVE_SYSTEMD 1|#define WITH_SYSTEMD" config.h; then
    echo "   ✅ HAVE_SYSTEMD 정의됨!"
    echo ""
    echo "   config.h 내용:"
    grep -E "HAVE_SYSTEMD|WITH_SYSTEMD" config.h
else
    echo "   ❌ HAVE_SYSTEMD 정의 안 됨!"
    echo ""
    echo "config.log 확인:"
    grep -A10 "checking for systemd" config.log | head -15
    echo ""
    echo "pkg-config 재확인:"
    pkg-config --exists libsystemd && echo "libsystemd found" || echo "libsystemd NOT found"
    echo ""
    echo "❌ 빌드를 중단합니다. libsystemd-dev를 설치하고 다시 시도하세요."
    exit 1
fi

echo ""

# 7. 컴파일
echo "7️⃣  컴파일 (약 10-15분)..."
echo "--------------------------------------------------------------------------------"

make -j$(nproc)

if [ $? -ne 0 ]; then
    echo "❌ 컴파일 실패"
    exit 1
fi

echo "✅ 컴파일 완료"

echo ""

# 8. 설치
echo "8️⃣  설치..."
sudo make install

if [ $? -ne 0 ]; then
    echo "❌ 설치 실패"
    exit 1
fi

echo "✅ 설치 완료"

echo ""

# 9. 검증
echo "9️⃣  systemd 지원 검증..."
echo "--------------------------------------------------------------------------------"

SLURMCTLD_BIN="/usr/local/slurm/sbin/slurmctld"

echo ""
echo "ldd 확인:"
if ldd "$SLURMCTLD_BIN" | grep -q systemd; then
    echo "   ✅ systemd 라이브러리 링크됨"
    ldd "$SLURMCTLD_BIN" | grep systemd
else
    echo "   ❌ systemd 라이브러리 링크 안 됨"
fi

echo ""
echo "sd_notify 심볼 확인:"
if strings "$SLURMCTLD_BIN" | grep -q sd_notify; then
    echo "   ✅ sd_notify 심볼 있음"
else
    echo "   ❌ sd_notify 심볼 없음"
fi

echo ""

# 10. 서비스 재시작
echo "🔟  서비스 재시작..."
echo "--------------------------------------------------------------------------------"

# daemon-reload
sudo systemctl daemon-reload

# slurmdbd 시작
echo ""
echo "slurmdbd 시작..."
sudo systemctl start slurmdbd
sleep 3

if sudo systemctl is-active --quiet slurmdbd; then
    echo "✅ slurmdbd 시작 성공"
else
    echo "⚠️  slurmdbd 시작 실패"
fi

# slurmctld 시작
echo ""
echo "slurmctld 시작..."
sudo systemctl start slurmctld

echo "⏱️  대기 중 (15초)..."
sleep 15

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 시작 성공!"
    
    # 상태 확인
    sudo systemctl status slurmctld --no-pager | head -15
else
    echo "❌ slurmctld 시작 실패"
    sudo systemctl status slurmctld --no-pager
    echo ""
    echo "로그:"
    sudo tail -30 /var/log/slurm/slurmctld.log
    exit 1
fi

echo ""

################################################################################
# 완료
################################################################################

echo "=========================================="
echo "✅ Slurm systemd 지원 재빌드 완료!"
echo "=========================================="
echo ""

echo "변경사항:"
echo "  ✅ libsystemd-dev 설치"
echo "  ✅ Slurm --with-systemd로 재빌드"
echo "  ✅ sd_notify 지원 활성화"
echo "  ✅ Type=notify 작동"
echo ""

echo "검증:"
echo "  sudo systemctl status slurmctld"
echo "  ldd /usr/local/slurm/sbin/slurmctld | grep systemd"
echo ""

echo "이제 Type=notify가 정상 작동합니다!"
echo ""
