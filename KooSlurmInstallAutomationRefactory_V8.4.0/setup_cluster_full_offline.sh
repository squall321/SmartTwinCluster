#!/bin/bash
################################################################################
# 오프라인 Slurm 클러스터 완전 자동 설치 스크립트
# packages/ 디렉토리의 파일들을 사용하여 인터넷 없이 설치
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PACKAGES_DIR="$SCRIPT_DIR/packages"
DEB_DIR="$PACKAGES_DIR/deb"
SOURCE_DIR="$PACKAGES_DIR/source"
PYTHON_DIR="$PACKAGES_DIR/python"

echo ""

################################################################################
# 사전 검증
################################################################################

echo "🔍 오프라인 패키지 검증..."
echo "--------------------------------------------------------------------------------"

if [ ! -d "$PACKAGES_DIR" ]; then
    echo "❌ packages/ 디렉토리를 찾을 수 없습니다!"
    echo ""
    echo "💡 먼저 온라인 환경에서 다음 명령을 실행하세요:"
    echo "   ./download_packages_all.sh"
    exit 1
fi

# Slurm 소스 확인
SLURM_VERSION="23.11.10"
if [ ! -f "$SOURCE_DIR/slurm-${SLURM_VERSION}.tar.bz2" ]; then
    echo "❌ Slurm 소스를 찾을 수 없습니다: $SOURCE_DIR/slurm-${SLURM_VERSION}.tar.bz2"
    exit 1
fi

# .deb 패키지 확인
DEB_COUNT=$(ls -1 $DEB_DIR/*.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -eq 0 ]; then
    echo "❌ .deb 패키지를 찾을 수 없습니다: $DEB_DIR/"
    exit 1
fi

echo "✅ 오프라인 패키지 검증 완료"
echo "  - Slurm 소스: slurm-${SLURM_VERSION}.tar.bz2"
echo "  - .deb 패키지: $DEB_COUNT개"
echo ""

################################################################################
# Step 2: Python 가상환경 확인
################################################################################

echo "🐍 Step 2/14: Python 가상환경 확인..."
echo "--------------------------------------------------------------------------------"

if [ ! -d "venv" ]; then
    echo "⚠️  가상환경이 없습니다. 생성합니다..."
    python3 -m venv venv
fi

source venv/bin/activate
echo "✅ 가상환경 활성화 완료"
echo ""

################################################################################
# Step 3: Python 패키지 오프라인 설치
################################################################################

echo "🐍 Step 3/14: Python 패키지 오프라인 설치..."
echo "--------------------------------------------------------------------------------"

if [ -d "$PYTHON_DIR" ] && [ "$(ls -A $PYTHON_DIR/*.whl $PYTHON_DIR/*.tar.gz 2>/dev/null)" ]; then
    echo "📦 오프라인 Python 패키지 설치 중..."
    pip3 install --no-index --find-links="$PYTHON_DIR" PyYAML paramiko cryptography || {
        echo "⚠️  일부 패키지 설치 실패 (계속 진행)"
    }
    echo "✅ Python 패키지 설치 완료"
else
    echo "⚠️  Python 패키지 디렉토리가 비어있습니다 (건너뜀)"
fi

echo ""

################################################################################
# Step 4: .deb 패키지 오프라인 설치
################################################################################

echo "📦 Step 4/14: 시스템 패키지 오프라인 설치..."
echo "--------------------------------------------------------------------------------"

cd "$DEB_DIR"

echo "📥 .deb 패키지 설치 중..."
echo "  (의존성 순서대로 설치)"

# dpkg로 직접 설치 (의존성 오류 무시)
sudo dpkg -i *.deb 2>/dev/null || true

# apt-get으로 의존성 해결
echo "🔧 의존성 해결 중..."
sudo apt-get install -f -y --no-install-recommends 2>/dev/null || {
    echo "⚠️  일부 의존성 해결 실패 (수동 확인 필요)"
}

echo "✅ 시스템 패키지 설치 완료"
echo ""

################################################################################
# Step 5: Slurm 사용자 생성
################################################################################

echo "👤 Step 5/14: Slurm 사용자 생성..."
echo "--------------------------------------------------------------------------------"

if ! id slurm &>/dev/null; then
    sudo groupadd -g 1001 slurm 2>/dev/null || true
    sudo useradd -u 1001 -g 1001 -m -s /bin/bash slurm 2>/dev/null || true
    echo "✅ slurm 사용자 생성 완료"
else
    echo "ℹ️  slurm 사용자가 이미 존재합니다"
fi

if ! id munge &>/dev/null; then
    sudo groupadd -g 1002 munge 2>/dev/null || true
    sudo useradd -u 1002 -g 1002 -m -s /bin/bash munge 2>/dev/null || true
    echo "✅ munge 사용자 생성 완료"
else
    echo "ℹ️  munge 사용자가 이미 존재합니다"
fi

echo ""

################################################################################
# Step 6: Slurm 빌드 (오프라인)
################################################################################

echo "🔨 Step 6/14: Slurm ${SLURM_VERSION} 빌드..."
echo "--------------------------------------------------------------------------------"

INSTALL_PREFIX="/usr/local/slurm"
CONFIG_DIR="/usr/local/slurm/etc"

# 디렉토리 생성
sudo mkdir -p ${INSTALL_PREFIX}/{bin,sbin,lib,etc,var}
sudo mkdir -p /var/log/slurm
sudo mkdir -p /var/spool/slurm/{state,d}
sudo mkdir -p /run/slurm
sudo chown -R slurm:slurm /var/log/slurm /var/spool/slurm /run/slurm

cd /tmp

# 소스 압축 해제
if [ -d "slurm-${SLURM_VERSION}" ]; then
    rm -rf "slurm-${SLURM_VERSION}"
fi

echo "📦 소스 압축 해제 중..."
tar -xjf "$SOURCE_DIR/slurm-${SLURM_VERSION}.tar.bz2"
cd "slurm-${SLURM_VERSION}"

echo "⚙️  Configure 중... (약 2-3분)"
./configure \
    --prefix=${INSTALL_PREFIX} \
    --sysconfdir=${CONFIG_DIR} \
    --enable-pam \
    --with-pmix \
    --with-hwloc=/usr \
    --without-rpath \
    --with-mysql_config=/usr/bin/mysql_config \
    CFLAGS="$(pkg-config --cflags libsystemd 2>/dev/null || echo '')" \
    LDFLAGS="$(pkg-config --libs libsystemd 2>/dev/null || echo '')" \
    > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Configure 실패"
    exit 1
fi

echo "🔨 빌드 중... (약 10-15분, CPU 코어 수에 따라 다름)"
make -j$(nproc) > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 빌드 실패"
    exit 1
fi

echo "📥 설치 중..."
sudo make install > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 설치 실패"
    exit 1
fi

echo "✅ Slurm ${SLURM_VERSION} 빌드 및 설치 완료"
echo ""

################################################################################
# Step 7: Munge 설정
################################################################################

echo "🔐 Step 7/14: Munge 인증 시스템 설정..."
echo "--------------------------------------------------------------------------------"

if [ -f "$PACKAGES_DIR/scripts/install_munge_auto.sh" ]; then
    cd "$SCRIPT_DIR"
    chmod +x "$PACKAGES_DIR/scripts/install_munge_auto.sh"
    "$PACKAGES_DIR/scripts/install_munge_auto.sh"
else
    echo "⚠️  install_munge_auto.sh를 찾을 수 없습니다"
    echo "   수동으로 Munge를 설정하세요"
fi

echo ""

################################################################################
# Step 8: systemd 서비스 파일 생성
################################################################################

echo "📝 Step 8/14: systemd 서비스 파일 생성..."
echo "--------------------------------------------------------------------------------"

if [ -f "$PACKAGES_DIR/scripts/create_slurm_systemd_services.sh" ]; then
    cd "$SCRIPT_DIR"
    chmod +x "$PACKAGES_DIR/scripts/create_slurm_systemd_services.sh"
    sudo bash "$PACKAGES_DIR/scripts/create_slurm_systemd_services.sh"
else
    echo "⚠️  create_slurm_systemd_services.sh를 찾을 수 없습니다"
fi

echo ""

################################################################################
# Step 9: slurmdbd 설치 (선택)
################################################################################

echo "🗄️  Step 9/14: Slurm Accounting (slurmdbd) 설치..."
echo "--------------------------------------------------------------------------------"

read -p "slurmdbd를 설치하시겠습니까? (권장: Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if [ -f "$PACKAGES_DIR/scripts/install_slurm_accounting.sh" ]; then
        cd "$SCRIPT_DIR"
        chmod +x "$PACKAGES_DIR/scripts/install_slurm_accounting.sh"
        sudo bash "$PACKAGES_DIR/scripts/install_slurm_accounting.sh"
    else
        echo "⚠️  install_slurm_accounting.sh를 찾을 수 없습니다"
    fi
else
    echo "⏭️  slurmdbd 설치 건너뜀"
fi

echo ""

################################################################################
# Step 10: /etc/hosts 자동 설정
################################################################################

echo "🌐 Step 10/14: /etc/hosts 자동 설정..."
echo "--------------------------------------------------------------------------------"

if [ -f "$PACKAGES_DIR/scripts/complete_slurm_setup.py" ] && [ -f "$PACKAGES_DIR/scripts/my_cluster.yaml" ]; then
    cd "$SCRIPT_DIR"

    # scripts에서 필요한 파일 복사
    cp "$PACKAGES_DIR/scripts/my_cluster.yaml" . 2>/dev/null || true
    cp "$PACKAGES_DIR/scripts/complete_slurm_setup.py" . 2>/dev/null || true
    cp -r "$PACKAGES_DIR/scripts/src" . 2>/dev/null || true

    echo "📝 complete_slurm_setup.py --only-hosts 실행 중..."
    python3 complete_slurm_setup.py --only-hosts || {
        echo "⚠️  /etc/hosts 설정 실패 (수동 확인 필요)"
    }
else
    echo "⚠️  complete_slurm_setup.py 또는 my_cluster.yaml을 찾을 수 없습니다"
    echo "   수동으로 /etc/hosts를 설정하세요"
fi

echo ""

################################################################################
# Step 11: 계산 노드에 Slurm 설치
################################################################################

echo "📦 Step 11/14: 계산 노드에 Slurm 설치..."
echo "--------------------------------------------------------------------------------"

read -p "계산 노드에 Slurm을 설치하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    # my_cluster.yaml에서 노드 목록 읽기
    mapfile -t COMPUTE_NODES < <(python3 << 'EOFPY'
import yaml
try:
    with open('my_cluster.yaml', 'r') as f:
        config = yaml.safe_load(f)
    for node in config['nodes']['compute_nodes']:
        print(f"{node['ssh_user']}@{node['ip_address']}")
except Exception as e:
    print(f"", file=sys.stderr)
EOFPY
)

    if [ ${#COMPUTE_NODES[@]} -gt 0 ]; then
        echo "📋 검색된 계산 노드:"
        for node in "${COMPUTE_NODES[@]}"; do
            echo "  - $node"
        done
        echo ""

        # packages 디렉토리를 각 노드로 복사
        for node in "${COMPUTE_NODES[@]}"; do
            echo "📤 $node: packages 디렉토리 복사 중..."

            # packages 디렉토리 압축
            if [ ! -f "/tmp/slurm-offline-packages.tar.gz" ]; then
                tar -czf /tmp/slurm-offline-packages.tar.gz -C "$SCRIPT_DIR" packages
            fi

            # 원격 노드로 복사
            scp /tmp/slurm-offline-packages.tar.gz "$node:/tmp/" || {
                echo "  ⚠️  파일 복사 실패"
                continue
            }

            # 원격에서 압축 해제 및 설치 스크립트 실행
            ssh "$node" "cd /tmp && tar -xzf slurm-offline-packages.tar.gz && cd packages && sudo bash ../../../install_slurm_cgroup_v2.sh" 2>/dev/null || {
                echo "  ⚠️  설치 실패 (수동 확인 필요)"
            }
        done
    else
        echo "⚠️  my_cluster.yaml에서 노드 정보를 읽을 수 없습니다"
    fi
else
    echo "⏭️  계산 노드 설치 건너뜀"
fi

echo ""

################################################################################
# Step 12: Slurm 설정 파일 생성
################################################################################

echo "🔧 Step 12/14: Slurm 설정 파일 생성..."
echo "--------------------------------------------------------------------------------"

read -p "Slurm 설정 파일을 생성하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if [ -f "$PACKAGES_DIR/scripts/configure_slurm_from_yaml.py" ]; then
        cd "$SCRIPT_DIR"
        cp "$PACKAGES_DIR/scripts/configure_slurm_from_yaml.py" . 2>/dev/null || true
        chmod +x configure_slurm_from_yaml.py
        python3 configure_slurm_from_yaml.py
    else
        echo "⚠️  configure_slurm_from_yaml.py를 찾을 수 없습니다"
    fi
else
    echo "⏭️  설정 파일 생성 건너뜀"
fi

echo ""

################################################################################
# Step 13: 설정 파일 배포
################################################################################

echo "📤 Step 13/14: 설정 파일 배포..."
echo "--------------------------------------------------------------------------------"

read -p "설정 파일을 계산 노드에 배포하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if [ ${#COMPUTE_NODES[@]} -gt 0 ]; then
        for node in "${COMPUTE_NODES[@]}"; do
            echo "📤 $node: 설정 파일 배포 중..."

            # slurm.conf
            scp /usr/local/slurm/etc/slurm.conf "$node:/tmp/" 2>/dev/null || true
            ssh "$node" "sudo mv /tmp/slurm.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/slurm.conf" 2>/dev/null || true

            # cgroup.conf
            scp /usr/local/slurm/etc/cgroup.conf "$node:/tmp/" 2>/dev/null || true
            ssh "$node" "sudo mv /tmp/cgroup.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/cgroup.conf" 2>/dev/null || true

            echo "  ✅ 완료"
        done
    fi
else
    echo "⏭️  설정 파일 배포 건너뜀"
fi

echo ""

################################################################################
# Step 14: Slurm 서비스 시작
################################################################################

echo "▶️  Step 14/14: Slurm 서비스 시작..."
echo "--------------------------------------------------------------------------------"

read -p "Slurm 서비스를 시작하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    # 컨트롤러
    echo "🔧 컨트롤러: slurmctld 시작 중..."
    sudo systemctl enable slurmctld
    sudo systemctl stop slurmctld 2>/dev/null || true
    sleep 1
    sudo systemctl start slurmctld

    sleep 3

    if sudo systemctl is-active --quiet slurmctld; then
        echo "✅ slurmctld 시작 성공"
    else
        echo "❌ slurmctld 시작 실패"
        sudo systemctl status slurmctld --no-pager
    fi

    # 계산 노드
    if [ ${#COMPUTE_NODES[@]} -gt 0 ]; then
        for node in "${COMPUTE_NODES[@]}"; do
            echo "🔧 $node: slurmd 시작 중..."
            ssh "$node" "sudo systemctl enable slurmd && sudo systemctl restart slurmd" 2>/dev/null || {
                echo "  ⚠️  시작 실패"
            }
        done
    fi

    echo "✅ Slurm 서비스 시작 완료"
else
    echo "⏭️  서비스 시작 건너뜀"
fi

echo ""

################################################################################
# 완료
################################################################################

echo "================================================================================"
echo "🎉 오프라인 Slurm 클러스터 설치 완료!"
echo "================================================================================"
echo ""

# PATH 설정
export PATH=/usr/local/slurm/bin:$PATH

if command -v sinfo &> /dev/null; then
    echo "📊 클러스터 상태:"
    sinfo || true
    echo ""
fi

echo "📋 다음 단계:"
echo "  1. 노드 상태 확인: sinfo"
echo "  2. 노드 활성화 (필요시): scontrol update NodeName=node001 State=RESUME"
echo "  3. 테스트 작업 제출: sbatch test_job.sh"
echo ""
echo "================================================================================"
