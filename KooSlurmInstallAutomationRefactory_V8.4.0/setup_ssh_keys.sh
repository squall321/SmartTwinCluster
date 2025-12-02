#!/bin/bash
################################################################################
# SSH 키 자동 설정 스크립트 (완전 자동화 버전)
# 모든 노드에 SSH 키를 복사합니다
# 비밀번호 한 번 입력으로 모든 노드 설정 가능
################################################################################

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   SSH 키 자동 설정 도구 (완전 자동화)                      ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# 노드 정보 (여기에 실제 IP를 입력하세요)
CONTROLLER_IP="192.168.122.1"
CONTROLLER_USER="koopark"

COMPUTE_NODES=(
    "192.168.122.90"
    "192.168.122.103"
)
COMPUTE_USER="koopark"

# SSH 설정
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
SSH_PUB_KEY_PATH="$HOME/.ssh/id_rsa.pub"
SSH_TIMEOUT=10
MAX_RETRIES=3

# sshpass 확인
USE_SSHPASS=false
if command -v sshpass &> /dev/null; then
    USE_SSHPASS=true
    echo -e "${GREEN}✓${NC} sshpass 사용 가능 - 비밀번호 한 번만 입력하면 됩니다"
else
    echo -e "${YELLOW}ℹ${NC} sshpass가 설치되어 있지 않습니다"
    echo "  sshpass를 설치하면 비밀번호를 한 번만 입력할 수 있습니다"
    echo ""
    read -p "지금 sshpass를 설치하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v apt &> /dev/null; then
            sudo apt install -y sshpass
            USE_SSHPASS=true
        elif command -v yum &> /dev/null; then
            sudo yum install -y sshpass
            USE_SSHPASS=true
        else
            echo -e "${YELLOW}⚠${NC} 자동 설치 실패. 수동으로 설치해주세요"
        fi
    fi
fi
echo ""

# 현재 머신의 모든 IP 주소 가져오기
get_current_ips() {
    {
        hostname -I 2>/dev/null
        ip addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
        ifconfig 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
        echo "127.0.0.1"
        echo "localhost"
    } | sort -u
}

CURRENT_IPS=$(get_current_ips)

# 현재 머신이 컨트롤러인지 확인
is_current_machine_controller() {
    while IFS= read -r current_ip; do
        if [ "$current_ip" = "$CONTROLLER_IP" ]; then
            return 0
        fi
    done <<< "$CURRENT_IPS"
    
    if [ "$CONTROLLER_IP" = "localhost" ] || [ "$CONTROLLER_IP" = "127.0.0.1" ]; then
        return 0
    fi
    
    if [ "$CONTROLLER_IP" = "$(hostname)" ] || [ "$CONTROLLER_IP" = "$(hostname -f)" ]; then
        return 0
    fi
    
    return 1
}

echo -e "${BLUE}현재 실행 환경 확인${NC}"
echo "─────────────────────────────────────────"
echo "현재 호스트명: $(hostname)"
echo "현재 IP 주소들:"
echo "$CURRENT_IPS" | sed 's/^/  • /'
echo "컨트롤러 IP: $CONTROLLER_IP"
echo ""

if is_current_machine_controller; then
    echo -e "${GREEN}✓${NC} 현재 머신이 컨트롤러 노드입니다"
    echo "  → 컨트롤러에 SSH 키 복사 단계를 건너뜁니다"
    SKIP_CONTROLLER=true
else
    echo -e "${BLUE}ℹ${NC} 현재 머신은 컨트롤러가 아닙니다"
    echo "  → 컨트롤러에도 SSH 키를 복사합니다"
    SKIP_CONTROLLER=false
fi

echo ""
echo -e "${BLUE}1단계: SSH 키 확인 및 설정${NC}"
echo "─────────────────────────────────────────"

# SSH 키가 있는지 확인
if [ -f "$SSH_KEY_PATH" ] && [ -f "$SSH_PUB_KEY_PATH" ]; then
    echo -e "${GREEN}✓${NC} SSH 키가 이미 존재합니다: $SSH_KEY_PATH"
else
    echo "SSH 키 생성 중..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
    echo -e "${GREEN}✓${NC} SSH 키 생성 완료"
fi

# SSH 키 권한 확인
KEY_PERM=$(stat -c %a "$SSH_KEY_PATH")
if [ "$KEY_PERM" != "600" ]; then
    chmod 600 "$SSH_KEY_PATH"
    echo -e "${GREEN}✓${NC} SSH 키 권한 설정 (600)"
fi

# 자기 자신에게 SSH 키 등록 (컨트롤러에서 실행하는 경우)
echo ""
echo -n "자기 자신에게 SSH 키 등록 확인... "
if ssh -o BatchMode=yes -o ConnectTimeout=3 -o LogLevel=ERROR localhost "exit" 2>/dev/null; then
    echo -e "${GREEN}✓ 이미 등록됨${NC}"
else
    echo "필요함"
    echo "  자기 자신에게 공개키를 등록하는 중..."
    
    # authorized_keys 파일 생성 및 권한 설정
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    # 공개키 추가 (중복 방지)
    if ! grep -q "$(cat $SSH_PUB_KEY_PATH)" ~/.ssh/authorized_keys 2>/dev/null; then
        cat "$SSH_PUB_KEY_PATH" >> ~/.ssh/authorized_keys
        echo -e "  ${GREEN}✓${NC} 공개키 추가 완료"
    fi
    
    # 테스트
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -o LogLevel=ERROR localhost "exit" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} 자기 자신 SSH 연결 성공!"
    else
        echo -e "  ${YELLOW}⚠${NC} SSH 연결 확인 실패 (계속 진행)"
    fi
fi

# 공통 비밀번호 입력 (sshpass 사용시)
SSH_PASSWORD=""
if [ "$USE_SSHPASS" = true ]; then
    echo ""
    echo -e "${BLUE}비밀번호 입력${NC}"
    echo "─────────────────────────────────────────"
    echo "모든 노드의 비밀번호가 같다면 한 번만 입력하세요"
    echo "(노드마다 다르면 나중에 개별 입력 가능)"
    echo ""
    read -s -p "SSH 비밀번호 (Enter로 건너뛰기): " SSH_PASSWORD
    echo
    
    if [ -n "$SSH_PASSWORD" ]; then
        echo -e "${GREEN}✓${NC} 비밀번호 저장됨 - 이제 자동으로 진행됩니다"
    else
        echo -e "${YELLOW}ℹ${NC} 비밀번호 건너뜀 - 각 노드마다 입력해야 합니다"
        USE_SSHPASS=false
    fi
fi

# 네트워크 연결 확인 함수
check_network() {
    local ip=$1
    if ping -c 1 -W 2 "$ip" &> /dev/null; then
        return 0
    fi
    return 1
}

# SSH 포트 확인 함수
check_ssh_port() {
    local ip=$1
    if timeout 3 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null; then
        return 0
    fi
    return 1
}

# SSH 키 복사 함수
copy_ssh_key() {
    local user=$1
    local ip=$2
    
    # SSH 옵션 (fingerprint 자동 수락)
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT -o LogLevel=ERROR"
    
    if [ "$USE_SSHPASS" = true ] && [ -n "$SSH_PASSWORD" ]; then
        # sshpass 사용 (비밀번호 자동 입력)
        if sshpass -p "$SSH_PASSWORD" ssh-copy-id $ssh_opts -i "$SSH_PUB_KEY_PATH" "$user@$ip" 2>&1 | grep -v "Warning"; then
            return 0
        fi
        return 1
    else
        # 일반 ssh-copy-id (사용자가 비밀번호 입력)
        if ssh-copy-id $ssh_opts -i "$SSH_PUB_KEY_PATH" "$user@$ip" 2>&1 | grep -v "Warning"; then
            return 0
        fi
        return 1
    fi
}

# 연결 테스트 함수
test_connection() {
    local user=$1
    local ip=$2
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR "$user@$ip" "hostname" 2>/dev/null; then
        return 0
    fi
    return 1
}

# 모든 노드 목록 생성
ALL_NODES=()
if [ "$SKIP_CONTROLLER" = false ]; then
    ALL_NODES+=("$CONTROLLER_USER@$CONTROLLER_IP:controller")
fi

for NODE_IP in "${COMPUTE_NODES[@]}"; do
    ALL_NODES+=("$COMPUTE_USER@$NODE_IP:compute")
done

echo ""
echo -e "${BLUE}2단계: SSH 키 복사${NC}"
echo "─────────────────────────────────────────"
echo "총 ${#ALL_NODES[@]}개 노드 처리 예정"
echo ""

failed_nodes=()
node_count=0

for node_info in "${ALL_NODES[@]}"; do
    node_count=$((node_count + 1))
    
    # 노드 정보 파싱
    user_host="${node_info%%:*}"
    node_type="${node_info##*:}"
    user="${user_host%%@*}"
    ip="${user_host##*@}"
    
    echo "[$node_count/${#ALL_NODES[@]}] $user@$ip ($node_type)"
    echo "────────────────────────────"
    
    # 네트워크 체크
    echo -n "  [1/4] 네트워크 확인... "
    if check_network "$ip"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        failed_nodes+=("$ip (네트워크 연결 실패)")
        echo ""
        continue
    fi
    
    # SSH 포트 체크
    echo -n "  [2/4] SSH 포트 확인... "
    if check_ssh_port "$ip"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        failed_nodes+=("$ip (SSH 포트 접근 불가)")
        echo ""
        continue
    fi
    
    # SSH 키 확인
    echo -n "  [3/4] SSH 키 확인... "
    if test_connection "$user" "$ip"; then
        echo -e "${GREEN}✓ 이미 설정됨${NC}"
        echo -n "  [4/4] 연결 테스트... "
        HOSTNAME=$(ssh -o LogLevel=ERROR "$user@$ip" "hostname" 2>/dev/null)
        echo -e "${GREEN}✓ $HOSTNAME${NC}"
    else
        echo "필요함"
        echo "  [4/4] SSH 키 복사 중..."
        
        if copy_ssh_key "$user" "$ip"; then
            # 복사 성공 후 테스트
            if test_connection "$user" "$ip"; then
                HOSTNAME=$(ssh -o LogLevel=ERROR "$user@$ip" "hostname" 2>/dev/null)
                echo -e "        ${GREEN}✓ 완료 ($HOSTNAME)${NC}"
            else
                echo -e "        ${YELLOW}⚠ 복사는 됐으나 연결 실패${NC}"
            fi
        else
            echo -e "        ${RED}✗ 실패${NC}"
            failed_nodes+=("$ip (SSH 키 복사 실패)")
        fi
    fi
    
    echo ""
done

# 결과 요약
echo "═══════════════════════════════════════════════════════════"

if [ ${#failed_nodes[@]} -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║   ✅ 모든 노드의 SSH 키 설정이 완료되었습니다!             ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                           ║${NC}"
    echo -e "${YELLOW}║   ⚠ 일부 노드에서 실패했습니다 (${#failed_nodes[@]}개)                        ║${NC}"
    echo -e "${YELLOW}║                                                           ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}실패한 노드:${NC}"
    for node in "${failed_nodes[@]}"; do
        echo "  • $node"
    done
    echo ""
fi

echo ""
echo -e "${BLUE}📋 다음 단계:${NC}"
echo ""
echo "1. 설정 파일 검증"
echo -e "   ${YELLOW}./validate_config.py my_cluster.yaml${NC}"
echo ""
echo "2. SSH 연결 테스트"
echo -e "   ${YELLOW}./test_connection.py my_cluster.yaml${NC}"
echo ""
echo "3. Slurm 설치 시작"
echo -e "   ${YELLOW}./install_slurm.py -c my_cluster.yaml${NC}"
echo ""

echo "Happy Computing! 🚀"
echo ""
