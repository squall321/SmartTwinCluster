#!/bin/bash
################################################################################
# 오프라인 설치를 위한 모든 패키지 다운로드 스크립트
# packages/ 디렉토리에 필요한 모든 파일을 저장
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PACKAGES_DIR="$SCRIPT_DIR/packages"
DEB_DIR="$PACKAGES_DIR/deb"
SOURCE_DIR="$PACKAGES_DIR/source"
PYTHON_DIR="$PACKAGES_DIR/python"

echo "================================================================================"
echo "📦 오프라인 설치용 패키지 다운로드"
echo "================================================================================"
echo ""
echo "다운로드 경로: $PACKAGES_DIR"
echo ""

################################################################################
# Step 1: 디렉토리 구조 생성
################################################################################

echo "1️⃣  디렉토리 구조 생성..."
echo "--------------------------------------------------------------------------------"

mkdir -p "$DEB_DIR"
mkdir -p "$SOURCE_DIR"
mkdir -p "$PYTHON_DIR"
mkdir -p "$PACKAGES_DIR/configs"
mkdir -p "$PACKAGES_DIR/scripts"

echo "✅ 디렉토리 생성 완료"
echo ""

################################################################################
# Step 2: Slurm 소스 다운로드
################################################################################

echo "2️⃣  Slurm 소스 다운로드..."
echo "--------------------------------------------------------------------------------"

SLURM_VERSION="23.11.10"
SLURM_URL="https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2"

cd "$SOURCE_DIR"

if [ -f "slurm-${SLURM_VERSION}.tar.bz2" ]; then
    echo "✓ slurm-${SLURM_VERSION}.tar.bz2 (이미 존재)"
else
    echo "📥 Slurm ${SLURM_VERSION} 다운로드 중..."
    wget -q --show-progress "$SLURM_URL"
    echo "✅ Slurm 다운로드 완료"
fi

echo ""

################################################################################
# Step 3: Ubuntu/Debian 패키지 다운로드 (.deb)
################################################################################

echo "3️⃣  Ubuntu/Debian 패키지 다운로드..."
echo "--------------------------------------------------------------------------------"

cd "$DEB_DIR"

# 필수 빌드 도구
BUILD_PACKAGES=(
    build-essential
    gcc
    g++
    make
    bzip2
    wget
    curl
    rsync
    vim
)

# Munge 인증
MUNGE_PACKAGES=(
    munge
    libmunge-dev
    libmunge2
)

# Slurm 빌드 의존성
SLURM_BUILD_DEPS=(
    libpam0g-dev
    libreadline-dev
    libssl-dev
    libnuma-dev
    libhwloc-dev
    libdbus-1-dev
    libsystemd-dev
    pkg-config
)

# MariaDB/MySQL (slurmdbd용)
DATABASE_PACKAGES=(
    mariadb-server
    mariadb-client
    libmariadb-dev
    libmariadb-dev-compat
)

# Python 및 유틸리티
PYTHON_PACKAGES=(
    python3
    python3-pip
    python3-yaml
    python3-paramiko
)

# 모든 패키지 리스트 합치기
ALL_PACKAGES=(
    "${BUILD_PACKAGES[@]}"
    "${MUNGE_PACKAGES[@]}"
    "${SLURM_BUILD_DEPS[@]}"
    "${DATABASE_PACKAGES[@]}"
    "${PYTHON_PACKAGES[@]}"
)

echo "📋 다운로드할 패키지 수: ${#ALL_PACKAGES[@]}"
echo ""

echo "📥 .deb 패키지 및 의존성 다운로드 중..."
echo "  (apt-get을 사용하여 모든 의존성 자동 포함)"
echo ""

sudo apt-get update -qq

# apt-cache를 사용하여 모든 의존성 목록 가져오기
echo "  🔍 의존성 분석 중..."

ALL_DEPS=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
           --no-breaks --no-replaces --no-enhances "${ALL_PACKAGES[@]}" 2>/dev/null | \
           grep "^\w" | sort -u)

# 배열로 변환
UNIQUE_DEPS=($(echo "$ALL_DEPS" | sort -u))

echo "  📊 총 ${#UNIQUE_DEPS[@]}개 패키지 (의존성 포함) 다운로드 필요"
echo ""

echo "  📥 패키지 다운로드 중... (시간이 걸릴 수 있습니다)"

# 배치 다운로드: 10개씩 묶어서 다운로드 (속도 향상)
BATCH_SIZE=10
DOWNLOADED=0
SKIPPED=0
TOTAL=${#UNIQUE_DEPS[@]}

for ((i=0; i<$TOTAL; i+=BATCH_SIZE)); do
    # 현재 배치의 패키지 목록
    batch=("${UNIQUE_DEPS[@]:i:BATCH_SIZE}")

    # 가상 패키지 제외하고 실제 패키지만 다운로드
    real_packages=()
    for pkg in "${batch[@]}"; do
        # 패키지 이름 검증
        if [ -z "$pkg" ] || [[ ! "$pkg" =~ ^[a-zA-Z0-9] ]]; then
            ((SKIPPED++))
            continue
        fi

        # 가상 패키지 확인
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            # 이미 다운로드되었는지 확인
            if ! ls ${pkg}_*.deb 1>/dev/null 2>&1; then
                real_packages+=("$pkg")
            else
                ((SKIPPED++))
            fi
        else
            ((SKIPPED++))
        fi
    done

    # 실제 패키지가 있으면 배치 다운로드
    if [ ${#real_packages[@]} -gt 0 ]; then
        apt-get download "${real_packages[@]}" >/dev/null 2>&1
        DOWNLOADED=$((DOWNLOADED + ${#real_packages[@]}))

        # 진행 상황 출력
        progress=$((i * 100 / TOTAL))
        echo -ne "\r    진행: $progress% ($DOWNLOADED개 다운로드, $SKIPPED개 건너뜀)      "
    fi
done

echo ""
echo ""

DEB_COUNT=$(ls -1 *.deb 2>/dev/null | wc -l)
DEB_SIZE=$(du -sh . | awk '{print $1}')

echo "✅ .deb 패키지 다운로드 완료"
echo "  - 패키지 수: $DEB_COUNT개"
echo "  - 총 크기: $DEB_SIZE"
echo ""

################################################################################
# Step 4: Python 패키지 다운로드 (pip)
################################################################################

echo "4️⃣  Python 패키지 다운로드..."
echo "--------------------------------------------------------------------------------"

cd "$PYTHON_DIR"

PYTHON_PACKAGES_PIP=(
    PyYAML
    paramiko
    cryptography
)

echo "📥 pip 패키지 다운로드 중..."

for package in "${PYTHON_PACKAGES_PIP[@]}"; do
    if [ -d "$package" ]; then
        echo "  ✓ $package (이미 존재)"
    else
        echo "  📥 $package 다운로드 중..."
        pip3 download "$package" --dest . 2>/dev/null || echo "  ⚠️  $package 다운로드 실패"
    fi
done

PIP_COUNT=$(ls -1 *.whl *.tar.gz 2>/dev/null | wc -l)
echo "✅ Python 패키지 다운로드 완료 (총 $PIP_COUNT 개)"
echo ""

################################################################################
# Step 5: 설정 파일 백업
################################################################################

echo "5️⃣  설정 파일 백업..."
echo "--------------------------------------------------------------------------------"

cd "$SCRIPT_DIR"

# 현재 스크립트 및 설정 파일들을 packages/scripts에 복사
SCRIPT_FILES=(
    "my_cluster.yaml"
    "install_slurm_cgroup_v2.sh"
    "install_munge_auto.sh"
    "install_slurm_accounting.sh"
    "create_slurm_systemd_services.sh"
    "configure_slurm_from_yaml.py"
    "complete_slurm_setup.py"
    "setup_ssh_passwordless.sh"
)

for file in "${SCRIPT_FILES[@]}"; do
    if [ -f "$file" ]; then
        cp "$file" "$PACKAGES_DIR/scripts/"
        echo "  ✓ $file"
    fi
done

# src 디렉토리 전체 복사
if [ -d "src" ]; then
    cp -r src "$PACKAGES_DIR/scripts/"
    echo "  ✓ src/ (전체)"
fi

echo "✅ 설정 파일 백업 완료"
echo ""

################################################################################
# Step 6: 메타 정보 저장
################################################################################

echo "6️⃣  메타 정보 저장..."
echo "--------------------------------------------------------------------------------"

cat > "$PACKAGES_DIR/package_info.txt" << 'EOF'
################################################################################
# 오프라인 패키지 정보
################################################################################

생성 날짜: $(date)
Slurm 버전: 23.11.10
Ubuntu 버전: 22.04

디렉토리 구조:
  packages/
    ├── deb/              # Ubuntu/Debian 패키지 (.deb)
    ├── source/           # Slurm 소스 코드
    ├── python/           # Python 패키지 (pip)
    ├── scripts/          # 설치 스크립트 및 설정 파일
    └── configs/          # 추가 설정 파일

사용 방법:
  1. 이 디렉토리를 오프라인 환경으로 복사
  2. ./setup_cluster_full_offline.sh 실행

패키지 수:
  - .deb 패키지: $(ls -1 deb/*.deb 2>/dev/null | wc -l)개
  - Python 패키지: $(ls -1 python/*.whl python/*.tar.gz 2>/dev/null | wc -l)개
  - Slurm 소스: slurm-23.11.10.tar.bz2
EOF

echo "✅ 메타 정보 저장 완료"
echo ""

################################################################################
# Step 7: 압축 아카이브 생성 (선택)
################################################################################

echo "7️⃣  압축 아카이브 생성..."
echo "--------------------------------------------------------------------------------"

cd "$SCRIPT_DIR"

ARCHIVE_NAME="slurm-offline-packages-$(date +%Y%m%d).tar.gz"

echo "📦 압축 중... (시간이 걸릴 수 있습니다)"
tar -czf "$ARCHIVE_NAME" packages/

ARCHIVE_SIZE=$(du -sh "$ARCHIVE_NAME" | awk '{print $1}')

echo "✅ 압축 완료: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
echo ""

################################################################################
# 완료
################################################################################

echo "================================================================================"
echo "🎉 오프라인 패키지 다운로드 완료!"
echo "================================================================================"
echo ""
echo "📁 패키지 위치: $PACKAGES_DIR"
echo "📦 압축 파일: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
echo ""
echo "📊 다운로드 요약:"
echo "  - .deb 패키지: $(ls -1 $DEB_DIR/*.deb 2>/dev/null | wc -l)개"
echo "  - Python 패키지: $(ls -1 $PYTHON_DIR/*.whl $PYTHON_DIR/*.tar.gz 2>/dev/null | wc -l)개"
echo "  - Slurm 소스: slurm-${SLURM_VERSION}.tar.bz2"
echo "  - 스크립트: $(ls -1 $PACKAGES_DIR/scripts/ 2>/dev/null | wc -l)개"
echo ""
echo "🚀 오프라인 환경에서 사용:"
echo "  1. $ARCHIVE_NAME를 오프라인 환경으로 복사"
echo "  2. tar -xzf $ARCHIVE_NAME"
echo "  3. cd $(basename $SCRIPT_DIR)"
echo "  4. ./setup_cluster_full_offline.sh"
echo ""
echo "================================================================================"
