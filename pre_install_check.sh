#!/bin/bash
# Pre-installation Check Script
# Phase 1: 설치 전 시스템 점검

echo "============================================"
echo "  Slurm 설치 전 시스템 점검"
echo "============================================"
echo ""

# 색상 코드
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 체크 함수
check_item() {
    local item_name=$1
    local check_command=$2
    
    echo -n "  $item_name: "
    
    if eval $check_command > /dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        return 1
    fi
}

# 경고 함수
warn_item() {
    local item_name=$1
    local current_value=$2
    local recommended_value=$3
    
    echo -e "  ${YELLOW}⚠ WARNING${NC}: $item_name"
    echo "    현재값: $current_value"
    echo "    권장값: $recommended_value"
}

failed_checks=0

echo "📋 1. 기본 시스템 정보"
echo "─────────────────────────────────────────"
echo "  호스트명: $(hostname)"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  커널: $(uname -r)"
echo "  아키텍처: $(uname -m)"
echo ""

echo "💾 2. 디스크 공간"
echo "─────────────────────────────────────────"

# 디스크 공간 파싱 함수 (G, T 단위 처리)
parse_disk_space() {
    local space_str=$1
    local value=$(echo $space_str | sed 's/[^0-9.]//g')
    local unit=$(echo $space_str | sed 's/[0-9.]//g')
    
    # T(테라)를 GB로 변환
    if [[ $unit == *"T"* ]]; then
        value=$(echo "$value * 1024" | bc)
        unit="G"
    fi
    
    echo "$value"
}

root_avail_raw=$(df -h / | awk 'NR==2 {print $4}')
root_avail=$(parse_disk_space $root_avail_raw)
root_unit=$(echo $root_avail_raw | sed 's/[0-9.]//g')

# 테라바이트면 표시
if [[ $root_unit == *"T"* ]]; then
    root_display=$(echo "scale=1; $root_avail / 1024" | bc)
    root_display_unit="TB"
else
    root_display=$root_avail
    root_display_unit="GB"
fi

if (( $(echo "$root_avail > 10" | bc -l) )); then
    echo -e "  / 파티션 여유 공간: ${GREEN}${root_display}${root_display_unit} ✓${NC}"
else
    echo -e "  / 파티션 여유 공간: ${RED}${root_display}${root_display_unit} (최소 10GB 필요)${NC}"
    ((failed_checks++))
fi

tmp_avail_raw=$(df -h /tmp | awk 'NR==2 {print $4}')
tmp_avail=$(parse_disk_space $tmp_avail_raw)
tmp_unit=$(echo $tmp_avail_raw | sed 's/[0-9.]//g')

# 테라바이트면 표시
if [[ $tmp_unit == *"T"* ]]; then
    tmp_display=$(echo "scale=1; $tmp_avail / 1024" | bc)
    tmp_display_unit="TB"
else
    tmp_display=$tmp_avail
    tmp_display_unit="GB"
fi

if (( $(echo "$tmp_avail > 5" | bc -l) )); then
    echo -e "  /tmp 여유 공간: ${GREEN}${tmp_display}${tmp_display_unit} ✓${NC}"
else
    echo -e "  /tmp 여유 공간: ${YELLOW}${tmp_display}${tmp_display_unit} (5GB 권장)${NC}"
fi
echo ""

echo "🔌 3. 네트워크 연결"
echo "─────────────────────────────────────────"
if ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1; then
    echo -e "  인터넷 연결: ${GREEN}✓ OK${NC}"
else
    echo -e "  인터넷 연결: ${YELLOW}⚠ 불가 (오프라인 설치 필요)${NC}"
fi

if ping -c 1 -W 3 download.schedmd.com > /dev/null 2>&1; then
    echo -e "  Slurm 다운로드 서버: ${GREEN}✓ OK${NC}"
else
    echo -e "  Slurm 다운로드 서버: ${YELLOW}⚠ 접근 불가${NC}"
fi
echo ""

echo "🔑 4. SSH 설정"
echo "─────────────────────────────────────────"
if [ -f ~/.ssh/id_rsa ]; then
    echo -e "  SSH 개인키 (~/.ssh/id_rsa): ${GREEN}✓ 존재${NC}"
    key_perm=$(stat -c %a ~/.ssh/id_rsa)
    if [ "$key_perm" == "600" ]; then
        echo -e "  SSH 키 권한: ${GREEN}✓ 600${NC}"
    else
        echo -e "  SSH 키 권한: ${YELLOW}⚠ $key_perm (600 권장)${NC}"
        echo "    수정: chmod 600 ~/.ssh/id_rsa"
    fi
else
    echo -e "  SSH 개인키: ${RED}✗ 없음${NC}"
    echo "    생성: ssh-keygen -t rsa -b 4096"
    ((failed_checks++))
fi

if [ -f ~/.ssh/id_rsa.pub ]; then
    echo -e "  SSH 공개키 (~/.ssh/id_rsa.pub): ${GREEN}✓ 존재${NC}"
else
    echo -e "  SSH 공개키: ${RED}✗ 없음${NC}"
    ((failed_checks++))
fi
echo ""

echo "🐍 5. Python 환경"
echo "─────────────────────────────────────────"
if command -v python3 &> /dev/null; then
    python_version=$(python3 --version | awk '{print $2}')
    echo -e "  Python 3: ${GREEN}✓ $python_version${NC}"
else
    echo -e "  Python 3: ${RED}✗ 설치 필요${NC}"
    ((failed_checks++))
fi

if command -v pip3 &> /dev/null; then
    echo -e "  pip3: ${GREEN}✓ 설치됨${NC}"
else
    echo -e "  pip3: ${YELLOW}⚠ 없음 (설치 권장)${NC}"
fi

# Python 패키지 확인
if python3 -c "import paramiko" 2>/dev/null; then
    echo -e "  paramiko: ${GREEN}✓ 설치됨${NC}"
else
    echo -e "  paramiko: ${YELLOW}⚠ 없음${NC}"
    echo "    설치: pip3 install paramiko"
fi

if python3 -c "import yaml" 2>/dev/null; then
    echo -e "  PyYAML: ${GREEN}✓ 설치됨${NC}"
else
    echo -e "  PyYAML: ${YELLOW}⚠ 없음${NC}"
    echo "    설치: pip3 install PyYAML"
fi
echo ""

echo "🛠️  6. 빌드 도구 (소스 컴파일 시 필요)"
echo "─────────────────────────────────────────"
check_item "gcc" "command -v gcc" || ((failed_checks++))
check_item "make" "command -v make"
check_item "automake" "command -v automake"
echo ""

echo "⏰ 7. 시간 동기화"
echo "─────────────────────────────────────────"
if systemctl is-active chronyd &> /dev/null || systemctl is-active ntpd &> /dev/null; then
    echo -e "  NTP 서비스: ${GREEN}✓ 실행 중${NC}"
else
    echo -e "  NTP 서비스: ${YELLOW}⚠ 중지됨 (시간 동기화 권장)${NC}"
    echo "    시작: systemctl start chronyd"
fi

current_time=$(date +%s)
echo "  현재 시간: $(date)"
echo ""

echo "🔥 8. 방화벽"
echo "─────────────────────────────────────────"
if systemctl is-active firewalld &> /dev/null; then
    echo -e "  firewalld: ${GREEN}실행 중${NC}"
    echo "    Slurm 포트 개방 필요: 6817, 6818, 6819"
elif systemctl is-active ufw &> /dev/null; then
    echo -e "  ufw: ${GREEN}실행 중${NC}"
    echo "    Slurm 포트 개방 필요: 6817, 6818, 6819"
else
    echo -e "  방화벽: ${YELLOW}비활성화${NC}"
fi
echo ""

echo "🔒 9. SELinux"
echo "─────────────────────────────────────────"
if command -v getenforce &> /dev/null; then
    selinux_status=$(getenforce)
    if [ "$selinux_status" == "Enforcing" ]; then
        echo -e "  SELinux: ${YELLOW}⚠ Enforcing (Permissive 권장)${NC}"
        echo "    변경: setenforce 0"
    else
        echo -e "  SELinux: ${GREEN}✓ $selinux_status${NC}"
    fi
else
    echo "  SELinux: 설치되지 않음"
fi
echo ""

echo "💪 10. 시스템 리소스"
echo "─────────────────────────────────────────"
cpu_count=$(nproc)
echo "  CPU 코어 수: $cpu_count"

mem_total=$(free -g | awk '/^Mem:/{print $2}')
if [ "$mem_total" -ge 4 ]; then
    echo -e "  총 메모리: ${GREEN}${mem_total}GB ✓${NC}"
else
    echo -e "  총 메모리: ${YELLOW}${mem_total}GB (최소 4GB 권장)${NC}"
fi

load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
echo "  현재 로드: $load_avg"
echo ""

echo "============================================"
echo "  점검 결과 요약"
echo "============================================"
echo ""

if [ $failed_checks -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 필수 항목이 준비되었습니다!${NC}"
    echo ""
    echo "다음 단계:"
    echo "  1. 설정 파일 준비: cp examples/2node_example_improved.yaml my_cluster.yaml"
    echo "  2. 설정 파일 수정: vim my_cluster.yaml"
    echo "  3. 설정 검증: ./validate_config.py my_cluster.yaml"
    echo "  4. Slurm 설치: ./install_slurm.py -c my_cluster.yaml"
    exit 0
else
    echo -e "${RED}✗ $failed_checks 개의 필수 항목이 준비되지 않았습니다.${NC}"
    echo ""
    echo "위의 오류를 수정한 후 다시 실행하세요."
    exit 1
fi
