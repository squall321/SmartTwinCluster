#!/bin/bash
################################################################################
# Munge 수동 설치 스크립트
# 모든 노드에서 실행
################################################################################

echo "🔐 Munge 수동 설치"
echo "================================================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_PKGS="$SCRIPT_DIR/offline_packages/apt_packages"

# Try offline installation first
if [ -d "$OFFLINE_PKGS" ] && [ -f "$OFFLINE_PKGS/munge_0.5.14-6_amd64.deb" ]; then
    echo "📦 오프라인 패키지에서 Munge 설치 중..."

    # Install munge packages from local .deb files
    sudo dpkg -i \
        "$OFFLINE_PKGS/libmunge2_0.5.14-6_amd64.deb" \
        "$OFFLINE_PKGS/munge_0.5.14-6_amd64.deb" \
        "$OFFLINE_PKGS/libmunge-dev_0.5.14-6_amd64.deb" \
        2>/dev/null || true

    # Fix any dependency issues
    sudo dpkg --configure -a 2>/dev/null || true

    echo "✅ 오프라인 패키지 설치 완료"

# Ubuntu/Debian (online fallback)
elif command -v apt-get &> /dev/null; then
    echo "📦 Ubuntu/Debian에서 Munge 설치 중 (온라인)..."
    sudo apt-get update
    sudo apt-get install -y munge libmunge2 libmunge-dev

# CentOS/RHEL (online fallback)
elif command -v yum &> /dev/null; then
    echo "📦 CentOS/RHEL에서 Munge 설치 중 (온라인)..."
    sudo yum install -y munge munge-libs munge-devel
fi

# 디렉토리 생성
echo "📁 디렉토리 생성 중..."
sudo mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge
sudo chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge 2>/dev/null || true
sudo chmod 700 /etc/munge /var/lib/munge /run/munge
sudo chmod 755 /var/log/munge

# 키 생성 (컨트롤러에서만)
if [ "$1" == "controller" ]; then
    echo "🔑 Munge 키 생성 중..."
    
    # 기존 키 백업
    if [ -f /etc/munge/munge.key ]; then
        sudo cp /etc/munge/munge.key /etc/munge/munge.key.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 새 키 생성
    if command -v create-munge-key &> /dev/null; then
        sudo create-munge-key -f
    elif [ -f /usr/sbin/create-munge-key ]; then
        sudo /usr/sbin/create-munge-key -f
    else
        sudo dd if=/dev/urandom bs=1 count=1024 of=/etc/munge/munge.key
    fi
    
    # 권한 설정
    sudo chown munge:munge /etc/munge/munge.key
    sudo chmod 400 /etc/munge/munge.key
    
    echo "✅ Munge 키 생성 완료"
    echo "📤 다른 노드로 키를 복사하세요:"
    echo "   scp /etc/munge/munge.key node1:/tmp/"
    echo "   ssh node1 'sudo mv /tmp/munge.key /etc/munge/ && sudo chown munge:munge /etc/munge/munge.key && sudo chmod 400 /etc/munge/munge.key'"
fi

# 서비스 시작
echo "🚀 Munge 서비스 시작 중..."
sudo systemctl enable munge
sudo systemctl restart munge

# 상태 확인
sleep 2
if sudo systemctl is-active munge > /dev/null 2>&1; then
    echo "✅ Munge 서비스 실행 중"
else
    echo "❌ Munge 서비스 시작 실패"
    sudo systemctl status munge
    exit 1
fi

# 테스트
echo "🧪 Munge 테스트 중..."
if munge -n | unmunge > /dev/null 2>&1; then
    echo "✅ Munge 테스트 성공!"
elif /usr/bin/munge -n | /usr/bin/unmunge > /dev/null 2>&1; then
    echo "✅ Munge 테스트 성공!"
else
    echo "⚠️ Munge 테스트 실패"
    echo "PATH 확인:"
    which munge
    which unmunge
fi

echo "================================================================================"
echo "✅ Munge 설치 완료!"
