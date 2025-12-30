#!/bin/bash
################################################################################
# Slurm with cgroup v2 Support Installation
# Ubuntu 22.04 + Slurm 23.11.x + cgroup v2 완전 지원
################################################################################

# Don't use set -e - it causes silent failures
# Instead, check exit codes explicitly for critical operations

# Debug mode - show each command before execution
# Uncomment the following line for verbose debugging:
# set -x

# Error handler - called on script exit to show last executed line
LAST_COMMAND=""
CURRENT_LINE=0

# Track command execution for debugging
debug_trap() {
    LAST_COMMAND="$BASH_COMMAND"
    CURRENT_LINE="$1"
}
trap 'debug_trap $LINENO' DEBUG

# On exit, show where we were if there was an error
exit_trap() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "❌ Script exited with code $exit_code"
        echo "   Last command (around line $CURRENT_LINE): $LAST_COMMAND"
    fi
}
trap exit_trap EXIT

SLURM_VERSION="23.11.10"
SLURM_DOWNLOAD_URL="https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2"
INSTALL_PREFIX="/usr/local/slurm"
CONFIG_DIR="/usr/local/slurm/etc"

################################################################################
# YAML 설정에서 UID/GID 읽기 (일관성 유지)
################################################################################
CONFIG_FILE="${1:-my_cluster.yaml}"

# 기본값 (YAML에서 못 읽을 경우)
# 64000번대 사용: 일반 시스템 계정(1000~)과 충돌 회피
SLURM_UID=64001
SLURM_GID=64001
MUNGE_UID=64002
MUNGE_GID=64002

# YAML에서 UID/GID 읽기 함수
read_uid_gid_from_yaml() {
    local yaml_file="$1"
    if [ -f "$yaml_file" ]; then
        # Python으로 YAML 파싱 시도
        if python3 -c "import yaml" 2>/dev/null; then
            # YAML에 slurm 섹션과 UID/GID가 정의되어 있는지 확인
            local has_uid=$(python3 -c "
import yaml
with open('$yaml_file') as f:
    c = yaml.safe_load(f)
slurm = c.get('slurm', {})
print('yes' if 'slurm_uid' in slurm else 'no')
" 2>/dev/null)

            SLURM_UID=$(python3 -c "
import yaml
try:
    with open('$yaml_file') as f:
        c = yaml.safe_load(f)
    print(c.get('slurm', {}).get('slurm_uid', 64001))
except: print(64001)
" 2>/dev/null)
            SLURM_GID=$(python3 -c "
import yaml
try:
    with open('$yaml_file') as f:
        c = yaml.safe_load(f)
    print(c.get('slurm', {}).get('slurm_gid', 64001))
except: print(64001)
" 2>/dev/null)
            MUNGE_UID=$(python3 -c "
import yaml
try:
    with open('$yaml_file') as f:
        c = yaml.safe_load(f)
    print(c.get('slurm', {}).get('munge_uid', 64002))
except: print(64002)
" 2>/dev/null)
            MUNGE_GID=$(python3 -c "
import yaml
try:
    with open('$yaml_file') as f:
        c = yaml.safe_load(f)
    print(c.get('slurm', {}).get('munge_gid', 64002))
except: print(64002)
" 2>/dev/null)

            if [ "$has_uid" = "yes" ]; then
                echo "✅ YAML에서 UID/GID 로드: slurm=$SLURM_UID:$SLURM_GID, munge=$MUNGE_UID:$MUNGE_GID"
            else
                echo "⚠️  YAML에 UID/GID 미정의 - 기본값 사용: slurm=$SLURM_UID:$SLURM_GID, munge=$MUNGE_UID:$MUNGE_GID"
                echo "   💡 YAML에 다음을 추가하면 커스텀 UID/GID 사용 가능:"
                echo "      slurm:"
                echo "        slurm_uid: 64001"
                echo "        slurm_gid: 64001"
                echo "        munge_uid: 64002"
                echo "        munge_gid: 64002"
            fi
        else
            echo "⚠️  Python yaml 모듈 없음 - 기본값 사용: slurm=$SLURM_UID:$SLURM_GID"
        fi
    else
        echo "⚠️  설정 파일 없음 ($yaml_file) - 기본값 사용: slurm=$SLURM_UID:$SLURM_GID"
    fi
}

# UID 사용 여부 확인 함수
check_uid_available() {
    local uid=$1
    local username=$2
    if getent passwd "$uid" >/dev/null 2>&1; then
        local existing_user=$(getent passwd "$uid" | cut -d: -f1)
        if [ "$existing_user" != "$username" ]; then
            echo "⚠️  UID $uid가 이미 '$existing_user' 사용자에게 할당됨"
            return 1
        fi
    fi
    return 0
}

# GID 사용 여부 확인 함수
check_gid_available() {
    local gid=$1
    local groupname=$2
    if getent group "$gid" >/dev/null 2>&1; then
        local existing_group=$(getent group "$gid" | cut -d: -f1)
        if [ "$existing_group" != "$groupname" ]; then
            echo "⚠️  GID $gid가 이미 '$existing_group' 그룹에게 할당됨"
            return 1
        fi
    fi
    return 0
}

# 사용 가능한 UID/GID 찾기 함수
find_available_uid() {
    local start_uid=$1
    local username=$2
    local uid=$start_uid

    # 먼저 사용자가 이미 존재하는지 확인
    if id "$username" &>/dev/null; then
        local existing_uid=$(id -u "$username")
        echo "$existing_uid"
        return 0
    fi

    # 사용 가능한 UID 찾기 (최대 100번 시도)
    for i in $(seq 1 100); do
        if ! getent passwd "$uid" >/dev/null 2>&1; then
            echo "$uid"
            return 0
        fi
        uid=$((uid + 1))
    done

    # 실패 시 원래 값 반환
    echo "$start_uid"
    return 1
}

find_available_gid() {
    local start_gid=$1
    local groupname=$2
    local gid=$start_gid

    # 먼저 그룹이 이미 존재하는지 확인
    if getent group "$groupname" >/dev/null 2>&1; then
        local existing_gid=$(getent group "$groupname" | cut -d: -f3)
        echo "$existing_gid"
        return 0
    fi

    # 사용 가능한 GID 찾기 (최대 100번 시도)
    for i in $(seq 1 100); do
        if ! getent group "$gid" >/dev/null 2>&1; then
            echo "$gid"
            return 0
        fi
        gid=$((gid + 1))
    done

    # 실패 시 원래 값 반환
    echo "$start_gid"
    return 1
}

# YAML에서 UID/GID 읽기
read_uid_gid_from_yaml "$CONFIG_FILE"

echo "================================================================================"
echo "🚀 Slurm ${SLURM_VERSION} with cgroup v2 Support Installation"
echo "================================================================================"
echo ""

################################################################################
# Step 1: 필수 의존성 설치 (cgroup v2 지원 포함)
################################################################################

echo "📦 Step 1/7: 필수 패키지 설치 중..."
echo "--------------------------------------------------------------------------------"

# 오프라인 APT 저장소 설정 (SCP로 복사된 로컬 패키지 또는 GlusterFS 기반)
# 이 스크립트가 오프라인 환경에서 실행될 경우, 복사된 패키지를 사용
setup_offline_apt_repo() {
    local repo_list="/etc/apt/sources.list.d/offline-slurm.list"
    local offline_pkg_path=""

    echo "🔍 오프라인 APT 저장소 확인 중..."

    # 1. 먼저 SCP로 복사된 /tmp/offline_packages 확인 (우선순위 높음)
    if [ -d "/tmp/offline_packages" ] && [ -f "/tmp/offline_packages/Packages.gz" ]; then
        offline_pkg_path="/tmp/offline_packages"
        echo "✅ SCP로 복사된 오프라인 패키지 발견: $offline_pkg_path"
    # 1-1. /tmp/offline_packages가 있지만 Packages.gz가 없는 경우
    elif [ -d "/tmp/offline_packages" ]; then
        offline_pkg_path="/tmp/offline_packages"
        echo "⚠️  /tmp/offline_packages 발견했으나 Packages.gz 없음 - 생성 시도"
    # 2. GlusterFS 마운트 확인
    else
        local gluster_mount="${GLUSTER_MOUNT:-/mnt/gluster}"
        local gluster_pkg_path="${gluster_mount}/offline_packages/apt_packages"

        # Check if GlusterFS is mounted (use subshell to prevent ERR trap on grep failure)
        local is_mounted=false
        if (mount | grep -q "$gluster_mount") 2>/dev/null; then
            is_mounted=true
        fi

        if [ "$is_mounted" = "true" ] && [ -d "$gluster_pkg_path" ]; then
            offline_pkg_path="$gluster_pkg_path"
            echo "✅ GlusterFS 오프라인 패키지 발견: $offline_pkg_path"
        fi
    fi

    # 오프라인 패키지를 찾지 못한 경우
    if [ -z "$offline_pkg_path" ]; then
        echo "⚠️  오프라인 패키지 디렉토리를 찾을 수 없음"
        echo "   확인 위치: /tmp/offline_packages, ${GLUSTER_MOUNT:-/mnt/gluster}/offline_packages/apt_packages"
        return 1
    fi

    # Packages.gz 확인 및 생성
    if [ ! -f "$offline_pkg_path/Packages.gz" ]; then
        echo "📦 APT 패키지 인덱스 생성 중..."
        if command -v dpkg-scanpackages &>/dev/null; then
            (cd "$offline_pkg_path" && sudo dpkg-scanpackages . /dev/null > Packages && sudo gzip -k -f Packages)
        else
            echo "⚠️  dpkg-scanpackages 없음, 인덱스 생성 불가"
            return 1
        fi
    fi

    # 로컬 APT 저장소 설정
    echo "✅ 오프라인 APT 저장소 설정: $offline_pkg_path"
    echo "deb [trusted=yes] file://$offline_pkg_path ./" | sudo tee "$repo_list" > /dev/null

    # 전역 변수로 경로 저장 (나중에 사용)
    OFFLINE_PKG_PATH="$offline_pkg_path"

    return 0
}

# 오프라인 저장소 설정 시도
OFFLINE_MODE=false
OFFLINE_PKG_PATH=""
if setup_offline_apt_repo; then
    OFFLINE_MODE=true
    echo "✅ 오프라인 모드로 설치 진행"
    echo "   패키지 경로: $OFFLINE_PKG_PATH"
    # 오프라인 저장소만 사용하도록 apt-get update
    sudo apt-get update -o Dir::Etc::sourcelist="/etc/apt/sources.list.d/offline-slurm.list" \
                        -o Dir::Etc::sourceparts="-" \
                        -o APT::Get::List-Cleanup="0" 2>/dev/null || {
        echo "⚠️  APT 업데이트 실패, 전체 업데이트 시도..."
        sudo apt-get update 2>/dev/null || true
    }
else
    echo "ℹ️  온라인 모드로 설치 진행"
    sudo apt-get update || {
        echo "❌ APT 업데이트 실패 - 네트워크 연결을 확인하세요"
        exit 1
    }
fi

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

# 오프라인 모드에서는 --no-install-recommends 사용
if [ "$OFFLINE_MODE" = true ]; then
    echo "📦 오프라인 모드: 필수 패키지만 설치..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${REQUIRED_PACKAGES[@]}" 2>&1 || {
        echo "⚠️  일부 패키지 설치 실패, 의존성 해결 시도..."
        sudo apt-get install -f -y 2>/dev/null || true
        # 핵심 패키지만 다시 시도
        echo "📦 핵심 패키지 재설치 시도..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            build-essential gcc g++ make munge libmunge-dev libmunge2 \
            libpam0g-dev libreadline-dev libssl-dev libnuma-dev libhwloc-dev \
            libdbus-1-dev libsystemd-dev python3 2>/dev/null || {
            echo "❌ 패키지 설치 실패 - 오프라인 패키지가 불완전할 수 있습니다"
            echo "   /tmp/offline_packages 디렉토리의 .deb 파일을 확인하세요"
            exit 1
        }
    }
else
    sudo apt-get install -y "${REQUIRED_PACKAGES[@]}" || {
        echo "❌ 패키지 설치 실패"
        exit 1
    }
fi

echo "✅ 패키지 설치 완료"
echo ""

################################################################################
# Step 2: Slurm 사용자 생성
################################################################################

echo "👤 Step 2/7: Slurm 사용자 생성..."
echo "--------------------------------------------------------------------------------"

# UID/GID 충돌 자동 해결
echo "🔍 UID/GID 사용 가능 여부 확인 중..."

# Slurm UID 확인 및 자동 조정
if ! check_uid_available "$SLURM_UID" "slurm"; then
    echo "   자동으로 사용 가능한 UID 탐색 중..."
    SLURM_UID=$(find_available_uid "$SLURM_UID" "slurm")
    echo "   ✅ slurm용 새 UID 발견: $SLURM_UID"
fi

# Slurm GID 확인 및 자동 조정
if ! check_gid_available "$SLURM_GID" "slurm"; then
    echo "   자동으로 사용 가능한 GID 탐색 중..."
    SLURM_GID=$(find_available_gid "$SLURM_GID" "slurm")
    echo "   ✅ slurm용 새 GID 발견: $SLURM_GID"
fi

# Munge UID 확인 및 자동 조정 (munge 사용자가 이미 있으면 그 UID 사용)
if ! check_uid_available "$MUNGE_UID" "munge"; then
    echo "   자동으로 사용 가능한 munge UID 탐색 중..."
    MUNGE_UID=$(find_available_uid "$MUNGE_UID" "munge")
    echo "   ✅ munge용 새 UID 발견: $MUNGE_UID"
fi

# Munge GID 확인 및 자동 조정
if ! check_gid_available "$MUNGE_GID" "munge"; then
    echo "   자동으로 사용 가능한 munge GID 탐색 중..."
    MUNGE_GID=$(find_available_gid "$MUNGE_GID" "munge")
    echo "   ✅ munge용 새 GID 발견: $MUNGE_GID"
fi

echo "   최종 UID/GID: slurm=$SLURM_UID:$SLURM_GID, munge=$MUNGE_UID:$MUNGE_GID"

if ! id slurm &>/dev/null; then
    sudo groupadd -g "$SLURM_GID" slurm 2>/dev/null || true
    sudo useradd -u "$SLURM_UID" -g "$SLURM_GID" -m -s /bin/bash slurm
    echo "✅ slurm 사용자 생성 완료 (UID=$SLURM_UID, GID=$SLURM_GID)"
else
    # 기존 사용자의 UID 확인
    existing_uid=$(id -u slurm)
    if [ "$existing_uid" != "$SLURM_UID" ]; then
        echo "⚠️  slurm 사용자가 다른 UID($existing_uid)로 존재합니다 (설정값: $SLURM_UID)"
        echo "   컨트롤러와 계산노드 간 UID가 다르면 권한 문제 발생 가능!"
        SLURM_UID=$existing_uid
    else
        echo "ℹ️  slurm 사용자가 이미 존재합니다 (UID=$existing_uid)"
    fi
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

# 실행 중인 Slurm 서비스 중지 (text file busy 에러 방지)
echo "  ⏹️  기존 Slurm 서비스 중지 중..."
sudo systemctl stop slurmd 2>/dev/null || true
sudo systemctl stop slurmctld 2>/dev/null || true
sudo systemctl stop slurmdbd 2>/dev/null || true
# 프로세스가 완전히 종료될 때까지 대기
sleep 2
# 혹시 남아있는 프로세스 강제 종료
sudo pkill -9 slurmd 2>/dev/null || true
sudo pkill -9 slurmctld 2>/dev/null || true
sudo pkill -9 slurmdbd 2>/dev/null || true
sleep 1

sudo make install

if [ $? -eq 0 ]; then
    echo "✅ 설치 완료"
else
    echo "❌ 설치 실패"
    exit 1
fi

# ldconfig 설정 (동적 라이브러리 캐시 갱신)
echo ""
echo "🔗 라이브러리 캐시 갱신 중..."
echo "/usr/local/slurm/lib" | sudo tee /etc/ld.so.conf.d/slurm.conf > /dev/null
sudo ldconfig
echo "✅ ldconfig 완료"

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
