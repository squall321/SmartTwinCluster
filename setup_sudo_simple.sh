#!/bin/bash
################################################################################
# passwordless sudo 설정 스크립트 (간단 버전)
# 각 노드에서 비밀번호 입력하여 설정
################################################################################

# 색상
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   passwordless sudo 설정 (간단 버전)                      ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

USER="koopark"

echo -e "${YELLOW}⚠ 각 노드에서 비밀번호를 입력해야 합니다${NC}"
echo ""

# my_cluster.yaml에서 노드 목록 읽기
mapfile -t REMOTE_NODES < <(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    print(node['ip_address'])
EOFPY
)

# localhost 추가
NODES=("localhost" "${REMOTE_NODES[@]}")

for node in "${NODES[@]}"; do
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}노드: $node${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$node" = "localhost" ]; then
        echo "현재 노드 설정 중..."
        echo ""
        echo "비밀번호를 입력하세요:"
        
        # sudo 테스트
        if sudo -v; then
            # passwordless sudo 설정
            echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
            sudo chmod 0440 /etc/sudoers.d/$USER
            
            # 검증
            if sudo -n true 2>/dev/null; then
                echo -e "${GREEN}✓${NC} 설정 완료 - 이제 비밀번호 없이 sudo 사용 가능"
            else
                echo -e "${YELLOW}⚠${NC} 설정했으나 재로그인 필요할 수 있음"
            fi
        else
            echo -e "${YELLOW}⚠${NC} 설정 실패 - sudo 권한이 없습니다"
        fi
    else
        echo "원격 노드 설정 중..."
        echo ""
        
        # SSH 연결 확인
        if ssh -o ConnectTimeout=5 -o BatchMode=yes $USER@$node "exit" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} SSH 키 인증 사용 가능"
            echo "sudo 비밀번호를 입력하세요:"
            
            # passwordless sudo 설정
            ssh -t $USER@$node "echo '$USER ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/$USER > /dev/null && sudo chmod 0440 /etc/sudoers.d/$USER"
            
            if [ $? -eq 0 ]; then
                # 검증
                if ssh $USER@$node "sudo -n true" 2>/dev/null; then
                    echo -e "${GREEN}✓${NC} 설정 완료"
                else
                    echo -e "${YELLOW}⚠${NC} 설정했으나 검증 실패"
                fi
            else
                echo -e "${YELLOW}⚠${NC} 설정 실패"
            fi
        else
            echo -e "${YELLOW}⚠${NC} SSH 연결 실패 - SSH 키를 먼저 설정하세요"
            echo "   ./setup_ssh_keys.sh 실행 필요"
        fi
    fi
done

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║   ✅ 설정 완료!                                            ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📋 테스트:${NC}"
echo ""
echo "# 현재 노드"
echo "sudo -n whoami"
echo ""
echo "# 원격 노드"
echo "ssh 192.168.122.230 'sudo -n whoami'"
echo ""

echo -e "${BLUE}📋 다음 단계:${NC}"
echo "  ./test_connection.py my_cluster.yaml"
echo ""
