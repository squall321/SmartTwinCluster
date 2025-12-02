#!/bin/bash
################################################################################
# 시간 동기화 자동 설정 스크립트
# YAML 설정 기반 chrony/systemd-timesyncd 자동 구성
# Munge 인증에 필수 (노드 간 ±2분 이내 동기화 필요)
################################################################################

set -e

CONFIG_FILE="${1:-my_cluster.yaml}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================================================"
echo "🕐 시간 동기화 자동 설정"
echo "================================================================================"
echo ""

################################################################################
# YAML에서 설정 읽기
################################################################################

# 기본값
NTP_SERVERS=("time.google.com" "pool.ntp.org")
TIMEZONE="Asia/Seoul"
ENABLED=true

if [ -f "$CONFIG_FILE" ] && python3 -c "import yaml" 2>/dev/null; then
    echo "📖 설정 파일 읽는 중: $CONFIG_FILE"

    ENABLED=$(python3 -c "
import yaml
try:
    with open('$CONFIG_FILE') as f:
        c = yaml.safe_load(f)
    print(str(c.get('time_synchronization', {}).get('enabled', True)).lower())
except: print('true')
" 2>/dev/null)

    TIMEZONE=$(python3 -c "
import yaml
try:
    with open('$CONFIG_FILE') as f:
        c = yaml.safe_load(f)
    print(c.get('time_synchronization', {}).get('timezone', 'Asia/Seoul'))
except: print('Asia/Seoul')
" 2>/dev/null)

    # NTP 서버 목록 읽기
    readarray -t NTP_SERVERS < <(python3 -c "
import yaml
try:
    with open('$CONFIG_FILE') as f:
        c = yaml.safe_load(f)
    servers = c.get('time_synchronization', {}).get('ntp_servers', ['time.google.com', 'pool.ntp.org'])
    for s in servers:
        print(s)
except:
    print('time.google.com')
    print('pool.ntp.org')
" 2>/dev/null)

    echo "   시간대: $TIMEZONE"
    echo "   NTP 서버: ${NTP_SERVERS[*]}"
    echo ""
else
    echo -e "${YELLOW}⚠️  설정 파일을 찾을 수 없어 기본값 사용${NC}"
    echo "   시간대: $TIMEZONE"
    echo "   NTP 서버: ${NTP_SERVERS[*]}"
    echo ""
fi

if [ "$ENABLED" != "true" ]; then
    echo -e "${YELLOW}⚠️  시간 동기화가 비활성화되어 있습니다 (설정: enabled=false)${NC}"
    exit 0
fi

################################################################################
# 시간대 설정
################################################################################

echo "📍 시간대 설정: $TIMEZONE"
sudo timedatectl set-timezone "$TIMEZONE" 2>/dev/null || {
    echo -e "${YELLOW}⚠️  timedatectl 실패, /etc/timezone 직접 설정${NC}"
    echo "$TIMEZONE" | sudo tee /etc/timezone > /dev/null
    sudo ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}
echo -e "${GREEN}✅ 시간대 설정 완료${NC}"
echo ""

################################################################################
# NTP 서비스 설정 (Ubuntu: chrony 또는 systemd-timesyncd)
################################################################################

echo "🔧 NTP 서비스 설정 중..."

# chrony 설정 생성
generate_chrony_conf() {
    local conf_file="/etc/chrony/chrony.conf"

    echo "# Slurm 클러스터 시간 동기화 설정"
    echo "# 자동 생성됨: $(date)"
    echo ""

    for server in "${NTP_SERVERS[@]}"; do
        echo "server $server iburst"
    done

    cat << 'CHRONY_EOF'

# 시간 동기화 설정
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync

# 로깅
logdir /var/log/chrony

# Allow NTP client access from local network (클러스터 내 동기화)
allow 192.168.0.0/16
allow 10.0.0.0/8

# Serve time even if not synchronized to a time source
local stratum 10
CHRONY_EOF
}

# systemd-timesyncd 설정 생성
generate_timesyncd_conf() {
    echo "[Time]"
    echo "NTP=${NTP_SERVERS[*]}"
    echo "FallbackNTP=pool.ntp.org"
}

# 우분투에서 chrony 사용 (더 정확함)
if command -v apt-get &> /dev/null; then
    echo "   Ubuntu 감지 - chrony 설치 중..."

    # chrony 설치
    if ! dpkg -l chrony 2>/dev/null | grep -q "^ii"; then
        sudo apt-get update -qq
        sudo apt-get install -y chrony > /dev/null 2>&1
    fi

    # chrony 설정
    echo "   chrony 설정 생성 중..."
    generate_chrony_conf | sudo tee /etc/chrony/chrony.conf > /dev/null

    # 서비스 재시작
    sudo systemctl restart chrony
    sudo systemctl enable chrony

    # systemd-timesyncd 비활성화 (충돌 방지)
    sudo systemctl stop systemd-timesyncd 2>/dev/null || true
    sudo systemctl disable systemd-timesyncd 2>/dev/null || true

    echo -e "${GREEN}✅ chrony 설정 완료${NC}"

# RHEL/CentOS
elif command -v yum &> /dev/null; then
    echo "   RHEL/CentOS 감지 - chrony 설치 중..."

    if ! rpm -q chrony &>/dev/null; then
        sudo yum install -y chrony > /dev/null 2>&1
    fi

    generate_chrony_conf | sudo tee /etc/chrony.conf > /dev/null

    sudo systemctl restart chronyd
    sudo systemctl enable chronyd

    echo -e "${GREEN}✅ chronyd 설정 완료${NC}"
else
    echo -e "${YELLOW}⚠️  알 수 없는 배포판 - systemd-timesyncd 사용${NC}"

    generate_timesyncd_conf | sudo tee /etc/systemd/timesyncd.conf > /dev/null
    sudo systemctl restart systemd-timesyncd
    sudo systemctl enable systemd-timesyncd
fi

echo ""

################################################################################
# 동기화 상태 확인
################################################################################

echo "🔍 시간 동기화 상태 확인..."
echo "--------------------------------------------------------------------------------"

# 현재 시간
echo "현재 시간: $(date)"
echo ""

# chrony 상태
if command -v chronyc &> /dev/null; then
    echo "📊 chrony 동기화 상태:"
    chronyc tracking 2>/dev/null | grep -E "Reference|System time|Last offset|RMS offset" || true
    echo ""
    chronyc sources -v 2>/dev/null | head -10 || true
# systemd-timesyncd 상태
elif command -v timedatectl &> /dev/null; then
    echo "📊 systemd-timesyncd 상태:"
    timedatectl status
fi

echo ""

################################################################################
# 원격 노드 설정 (선택적)
################################################################################

echo "================================================================================"
echo "📌 원격 노드 설정 방법"
echo "================================================================================"
echo ""
echo "모든 계산 노드에서 동일한 시간 동기화 필요 (Munge 인증)"
echo ""
echo "방법 1: 스크립트 복사 및 실행"
echo "   scp setup_time_sync.sh $CONFIG_FILE node001:/tmp/"
echo "   ssh node001 'cd /tmp && sudo bash setup_time_sync.sh $CONFIG_FILE'"
echo ""
echo "방법 2: setup_ssh_passwordless.sh 실행 시 자동 설정"
echo "   --setup-ntp 옵션 추가 (추후 지원 예정)"
echo ""
echo "================================================================================"
echo -e "${GREEN}🎉 로컬 시간 동기화 설정 완료!${NC}"
echo "================================================================================"
