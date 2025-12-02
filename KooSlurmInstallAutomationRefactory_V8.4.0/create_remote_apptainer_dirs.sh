#!/bin/bash

################################################################################
# /scratch/apptainers 디렉토리 수동 생성 스크립트
# 
# 모든 계산 노드에 /scratch/apptainers 디렉토리를 생성합니다.
################################################################################

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/my_cluster.yaml"
REMOTE_DIR="/scratch/apptainers"

echo ""
echo -e "${CYAN}==================================================================${NC}"
echo -e "${CYAN}  /scratch/apptainers 디렉토리 수동 생성${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo ""

# YAML에서 노드 정보 추출
echo "노드 정보를 읽는 중..."
node_info=$(python3 << EOF
import yaml

try:
    with open('${CONFIG_FILE}', 'r') as f:
        config = yaml.safe_load(f)
    
    compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
    
    for node in compute_nodes:
        hostname = node.get('hostname', '')
        ip = node.get('ip_address', '')
        ssh_user = node.get('ssh_user', 'koopark')
        
        if hostname and ip:
            print(f"{hostname}|{ip}|{ssh_user}")
            
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    exit(1)
EOF
)

if [ -z "$node_info" ]; then
    echo -e "${RED}✗ 노드 정보를 추출할 수 없습니다${NC}"
    exit 1
fi

echo ""
success=0
failed=0

while IFS='|' read -r hostname ip ssh_user; do
    echo -e "${CYAN}→ $hostname ($ip)${NC}"
    
    # 1. /scratch 디렉토리 생성
    echo "  [1/3] /scratch 디렉토리 확인..."
    ssh "${ssh_user}@${ip}" "sudo mkdir -p /scratch && sudo chmod 1777 /scratch" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} /scratch 디렉토리 준비 완료"
    else
        echo -e "  ${RED}✗${NC} /scratch 디렉토리 생성 실패"
        failed=$((failed + 1))
        continue
    fi
    
    # 2. /scratch/apptainers 디렉토리 생성
    echo "  [2/3] /scratch/apptainers 디렉토리 생성..."
    ssh "${ssh_user}@${ip}" "mkdir -p ${REMOTE_DIR} && chmod 755 ${REMOTE_DIR}" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} ${REMOTE_DIR} 생성 완료"
    else
        echo "  권한 문제 발생. sudo로 재시도..."
        ssh "${ssh_user}@${ip}" "sudo mkdir -p ${REMOTE_DIR} && sudo chown ${ssh_user}:${ssh_user} ${REMOTE_DIR} && sudo chmod 755 ${REMOTE_DIR}" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓${NC} ${REMOTE_DIR} 생성 완료 (sudo 사용)"
        else
            echo -e "  ${RED}✗${NC} 디렉토리 생성 실패"
            failed=$((failed + 1))
            continue
        fi
    fi
    
    # 3. 확인
    echo "  [3/3] 디렉토리 확인..."
    dir_info=$(ssh "${ssh_user}@${ip}" "ls -ld ${REMOTE_DIR}" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "  $dir_info"
        echo -e "  ${GREEN}✓${NC} 모든 설정 완료"
        success=$((success + 1))
    else
        echo -e "  ${RED}✗${NC} 디렉토리 확인 실패"
        failed=$((failed + 1))
    fi
    
    echo ""
    
done <<< "$node_info"

echo -e "${CYAN}==================================================================${NC}"
echo -e "결과: 성공 ${GREEN}$success${NC}, 실패 ${RED}$failed${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✨ 모든 노드에 디렉토리가 생성되었습니다!${NC}"
    echo ""
    echo "이제 동기화를 실행하세요:"
    echo "  ./sync_apptainers_to_nodes.sh"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠️  일부 노드에서 실패했습니다.${NC}"
    echo ""
    echo "수동으로 해결하세요:"
    echo "  ssh <node> 'sudo mkdir -p /scratch/apptainers && sudo chown \$USER:\$USER /scratch/apptainers'"
    echo ""
    exit 1
fi
