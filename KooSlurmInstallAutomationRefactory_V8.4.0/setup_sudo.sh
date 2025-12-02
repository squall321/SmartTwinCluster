#!/bin/bash
################################################################################
# sudo 권한 설정 스크립트
# 모든 노드에 사용자 sudo 권한 추가
################################################################################

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   sudo 권한 설정 도구                                      ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# my_cluster.yaml에서 노드 정보 읽기
CONTROLLER_IP=$(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
print(config['nodes']['controller']['ip_address'])
EOFPY
)

CONTROLLER_USER=$(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
print(config['nodes']['controller']['ssh_user'])
EOFPY
)

mapfile -t COMPUTE_NODES < <(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    print(node['ip_address'])
EOFPY
)

# 모든 노드 (현재 머신 제외)
ALL_REMOTE_NODES=()

# 현재 머신이 컨트롤러가 아니면 추가
CURRENT_IP=$(hostname -I | awk '{print $1}')
if [ "$CURRENT_IP" != "$CONTROLLER_IP" ]; then
    ALL_REMOTE_NODES+=("$CONTROLLER_IP")
fi

# 계산 노드들 추가
for node in "${COMPUTE_NODES[@]}"; do
    if [ "$CURRENT_IP" != "$node" ]; then
        ALL_REMOTE_NODES+=("$node")
    fi
done

echo -e "${BLUE}현재 사용자: $CURRENT_USER${NC}"
echo -e "${BLUE}현재 머신: $CURRENT_IP${NC}"
echo ""

# 현재 머신의 sudo 권한 확인
echo -e "${BLUE}1단계: 현재 머신 sudo 권한 확인${NC}"
echo "─────────────────────────────────────────"

if sudo -n true 2>/dev/null; then
    echo -e "${GREEN}✓${NC} 현재 머신에 sudo 권한 있음"
else
    echo -e "${RED}✗${NC} 현재 머신에 sudo 권한 없음"
    echo ""
    echo "현재 머신에 sudo 권한을 먼저 설정해야 합니다."
    echo ""
    echo "방법 1: root로 로그인하여 실행"
    echo "  su - root"
    echo "  usermod -aG sudo $CURRENT_USER"
    echo ""
    echo "방법 2: 관리자에게 요청"
    echo "  sudo usermod -aG sudo $CURRENT_USER"
    echo ""
    exit 1
fi

echo ""
echo -e "${BLUE}2단계: 현재 머신에 passwordless sudo 설정${NC}"
echo "─────────────────────────────────────────"

# 현재 머신에 NOPASSWD 설정
echo -n "설정 확인 중... "
if sudo grep -q "^${CURRENT_USER}.*NOPASSWD" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    echo -e "${GREEN}이미 설정됨${NC}"
else
    echo "필요함"
    echo "  passwordless sudo 추가 중..."
    
    # sudoers.d에 파일 생성
    echo "${CURRENT_USER} ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/${CURRENT_USER} > /dev/null
    sudo chmod 0440 /etc/sudoers.d/${CURRENT_USER}
    
    # 검증
    if sudo -n true 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} 설정 완료"
    else
        echo -e "  ${YELLOW}⚠${NC} 설정했으나 테스트 실패 (재로그인 필요)"
    fi
fi

echo ""
echo -e "${BLUE}3단계: 원격 노드들에 sudo 권한 설정${NC}"
echo "─────────────────────────────────────────"

if [ ${#ALL_REMOTE_NODES[@]} -eq 0 ]; then
    echo -e "${GREEN}✓${NC} 설정할 원격 노드 없음 (현재 머신이 유일)"
else
    echo "총 ${#ALL_REMOTE_NODES[@]}개 노드 처리 예정"
    echo ""
    
    failed_nodes=()
    
    for node_ip in "${ALL_REMOTE_NODES[@]}"; do
        echo "처리 중: $node_ip"
        echo "────────────────────────────"
        
        # SSH 연결 테스트
        echo -n "  [1/3] SSH 연결... "
        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${CURRENT_USER}@${node_ip}" "exit" 2>/dev/null; then
            echo -e "${RED}✗ 실패${NC}"
            failed_nodes+=("$node_ip (SSH 연결 실패)")
            echo ""
            continue
        fi
        echo -e "${GREEN}✓${NC}"
        
        # 현재 sudo 권한 확인
        echo -n "  [2/3] sudo 권한 확인... "
        if ssh "${CURRENT_USER}@${node_ip}" "sudo -n true" 2>/dev/null; then
            echo -e "${GREEN}✓ 이미 있음${NC}"
        else
            echo "없음"
            
            # sudo 권한 추가 시도
            echo "  [3/3] sudo 권한 추가 중..."
            
            # 방법 1: sudo 그룹 추가 시도
            if ssh "${CURRENT_USER}@${node_ip}" "echo '${CURRENT_USER} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${CURRENT_USER} && sudo chmod 0440 /etc/sudoers.d/${CURRENT_USER}" 2>/dev/null; then
                echo -e "        ${GREEN}✓ 완료${NC}"
            else
                # 방법 2: root 권한으로 시도
                echo -e "        ${YELLOW}⚠ 일반 방법 실패, root 비밀번호 필요${NC}"
                echo "        다음 명령을 $node_ip에서 root로 실행하세요:"
                echo "        usermod -aG sudo $CURRENT_USER"
                failed_nodes+=("$node_ip (수동 설정 필요)")
            fi
        fi
        
        # 최종 검증
        echo -n "  검증... "
        if ssh "${CURRENT_USER}@${node_ip}" "sudo -n true" 2>/dev/null; then
            echo -e "${GREEN}✓ 성공${NC}"
        else
            echo -e "${RED}✗ 실패${NC}"
            failed_nodes+=("$node_ip (검증 실패)")
        fi
        
        echo ""
    done
    
    # 결과 요약
    if [ ${#failed_nodes[@]} -eq 0 ]; then
        echo -e "${GREEN}✓${NC} 모든 노드 설정 완료!"
    else
        echo -e "${YELLOW}⚠${NC} 일부 노드 설정 실패:"
        for node in "${failed_nodes[@]}"; do
            echo "  • $node"
        done
        echo ""
        echo "실패한 노드는 수동으로 설정하세요:"
        echo "  ssh <node>"
        echo "  su - root"
        echo "  usermod -aG sudo $CURRENT_USER"
        echo "  또는"
        echo "  echo '$CURRENT_USER ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/$CURRENT_USER"
    fi
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║   ✅ sudo 권한 설정 완료!                                  ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📋 다음 단계:${NC}"
echo ""
echo "1. sudo 권한 테스트"
echo -e "   ${YELLOW}sudo -n whoami${NC}"
echo ""
echo "2. SSH 연결 테스트"
echo -e "   ${YELLOW}./test_connection.py my_cluster.yaml${NC}"
echo ""
echo "3. Slurm 설치"
echo -e "   ${YELLOW}./install_slurm.py -c my_cluster.yaml${NC}"
echo ""

echo "Happy Computing! 🚀"
echo ""
