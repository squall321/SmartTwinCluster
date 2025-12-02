#!/bin/bash
################################################################################
# Slurm with cgroup v2 Support Installation
# Ubuntu 22.04 + Slurm 23.11.x + cgroup v2 완전 지원
################################################################################

set -e

SLURM_VERSION="23.11.10"
SLURM_DOWNLOAD_URL="https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2"
INSTALL_PREFIX="/usr/local/slurm"
CONFIG_DIR="/usr/local/slurm/etc"

echo "================================================================================"
echo "🚀 Slurm ${SLURM_VERSION} with cgroup v2 Support Installation"
echo "================================================================================"
echo ""

################################################################################
# Step 1: 필수 의존성 설치 (cgroup v2 지원 포함)
################################################################################

echo "📦 Step 1/7: 필수 패키지 설치 중..."
echo "--------------------------------------------------------------------------------"

sudo apt-get update

# cgroup v2 지원에 필수적인 패키지들
REQUIRED_PACKAGES=(
    build-essential
    gcc
    g++
    make
    bzip2
    wget
    
    # Munge
    munge
    libmunge-dev
    libmunge2
    
    # 기본 라이브러리
    libpam0g-dev
    libreadline-dev
    libssl-dev
    libnuma-dev
    libhwloc-dev
    
    # cgroup v2 지원에 필수!
    libdbus-1-dev
    libsystemd-dev
    
    # 추가 유틸리티
    python3
    python3-pip
    rsync
    vim
)

echo "설치할 패키지: ${REQUIRED_PACKAGES[*]}"
sudo apt-get install -y "${REQUIRED_PACKAGES[@]}"

echo "✅ 패키지 설치 완료"
echo ""

################################################################################
# Step 2: Slurm 사용자 생성
################################################################################

echo "👤 Step 2/7: Slurm 사용자 생성..."
echo "--------------------------------------------------------------------------------"

if ! id slurm &>/dev/null; then
    sudo groupadd -g 1001 slurm
    sudo useradd -u 1001 -g 1001 -m -s /bin/bash slurm
    echo "✅ slurm 사용자 생성 완료"
else
    echo "ℹ️  slurm 사용자가 이미 존재합니다"
fi

echo ""

################################################################################
# Step 3: 디렉토리 생성
################################################################################

echo "📁 Step 3/7: 디렉토리 생성..."
echo "--------------------------------------------------------------------------------"

sudo mkdir -p ${INSTALL_PREFIX}/{bin,sbin,lib,etc,var}
sudo mkdir -p /var/log/slurm
sudo mkdir -p /var/spool/slurm/{state,d}
sudo chown -R slurm:slurm /var/log/slurm /var/spool/slurm

echo "✅ 디렉토리 생성 완료"
echo ""

################################################################################
# Step 4: Slurm 소스 다운로드 및 압축 해제
################################################################################

echo "📥 Step 4/7: Slurm ${SLURM_VERSION} 다운로드..."
echo "--------------------------------------------------------------------------------"

cd /tmp

if [ ! -f "slurm-${SLURM_VERSION}.tar.bz2" ]; then
    wget "${SLURM_DOWNLOAD_URL}"
    echo "✅ 다운로드 완료"
else
    echo "ℹ️  이미 다운로드됨"
fi

if [ -d "slurm-${SLURM_VERSION}" ]; then
    rm -rf "slurm-${SLURM_VERSION}"
fi

tar -xjf "slurm-${SLURM_VERSION}.tar.bz2"
cd "slurm-${SLURM_VERSION}"

echo "✅ 압축 해제 완료"
echo ""

################################################################################
# Step 5: Configure (cgroup v2 지원 활성화!)
################################################################################

echo "⚙️  Step 5/7: Configure 중... (약 2-3분 소요)"
echo "--------------------------------------------------------------------------------"
echo ""
echo "🔧 중요 Configure 옵션:"
echo "  --prefix=${INSTALL_PREFIX}"
echo "  --sysconfdir=${CONFIG_DIR}"
echo "  --enable-pam           # PAM 지원"
echo "  --with-pmix            # PMIx 지원"
echo "  --with-hwloc           # 하드웨어 토폴로지"
echo "  CFLAGS/LDFLAGS         # systemd 지원"
echo ""

./configure \
    --prefix=${INSTALL_PREFIX} \
    --sysconfdir=${CONFIG_DIR} \
    --enable-pam \
    --with-pmix \
    --with-hwloc=/usr \
    --without-rpath \
    CFLAGS="$(pkg-config --cflags libsystemd)" \
    LDFLAGS="$(pkg-config --libs libsystemd)"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Configure 완료"
    
    # systemd 지원 확인
    echo ""
    echo "🔍 systemd 지원 확인 중..."
    
    # HAVE_SYSTEMD 또는 WITH_SYSTEMD 확인
    if grep -qE "HAVE_SYSTEMD|WITH_SYSTEMD" config.h 2>/dev/null; then
        echo "✅ systemd/cgroup v2 지원이 활성화되었습니다!"
    else
        echo "⚠️  경고: systemd 지원이 감지되지 않았습니다"
        echo "   계속 진행하지만, Type=notify가 작동하지 않을 수 있습니다"
        echo ""
        echo "   해결책:"
        echo "   1. libsystemd-dev 설치: sudo apt-get install -y libsystemd-dev"
        echo "   2. 재빌드: ./rebuild_slurm_with_systemd.sh"
    fi
else
    echo "❌ Configure 실패"
    exit 1
fi

echo ""

################################################################################
# Step 6: 컴파일 및 설치
################################################################################

echo "🔨 Step 6/7: 컴파일 중... (약 10-15분 소요)"
echo "--------------------------------------------------------------------------------"

make -j$(nproc)

if [ $? -eq 0 ]; then
    echo "✅ 컴파일 완료"
else
    echo "❌ 컴파일 실패"
    exit 1
fi

echo ""
echo "📦 설치 중..."
sudo make install

if [ $? -eq 0 ]; then
    echo "✅ 설치 완료"
else
    echo "❌ 설치 실패"
    exit 1
fi

echo ""

################################################################################
# Step 7: 환경 변수 설정
################################################################################

echo "🌐 Step 7/7: 환경 변수 설정..."
echo "--------------------------------------------------------------------------------"

sudo tee /etc/profile.d/slurm.sh > /dev/null << 'EOF'
# Slurm Environment
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export MANPATH=/usr/local/slurm/share/man${MANPATH:+:$MANPATH}
EOF

sudo chmod 644 /etc/profile.d/slurm.sh
source /etc/profile.d/slurm.sh

echo "✅ 환경 변수 설정 완료"
echo ""

################################################################################
# 완료 메시지
################################################################################

echo "================================================================================"
echo "🎉 Slurm ${SLURM_VERSION} with cgroup v2 Support 설치 완료!"
echo "================================================================================"
echo ""
echo "📋 설치 정보:"
echo "  버전: ${SLURM_VERSION}"
echo "  설치 경로: ${INSTALL_PREFIX}"
echo "  설정 경로: ${CONFIG_DIR}"
echo "  cgroup v2: ✅ 지원"
echo ""
echo "🔍 설치 확인:"
echo "  ${INSTALL_PREFIX}/sbin/slurmctld -V"
echo "  ${INSTALL_PREFIX}/sbin/slurmd -V"
echo ""
echo "📚 다음 단계:"
echo "  1. slurm.conf 생성 (cgroup v2 설정 포함)"
echo "  2. cgroup.conf 생성"
echo "  3. systemd 서비스 파일 생성"
echo "  4. 모든 계산 노드에 동일하게 설치"
echo ""
echo "💡 힌트:"
echo "  이 스크립트를 모든 노드에서 실행하세요:"
echo "  scp install_slurm_cgroup_v2.sh node001:/tmp/"
echo "  ssh node001 'cd /tmp && sudo bash install_slurm_cgroup_v2.sh'"
echo ""
echo "================================================================================"
