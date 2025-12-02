#!/bin/bash

################################################################################
# /scratch 디렉토리 권한 수정 스크립트
# 
# 모든 계산 노드의 /scratch 디렉토리 권한을 수정합니다.
################################################################################

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/my_cluster.yaml"

echo ""
echo -e "${CYAN}==================================================================${NC}"
echo -e "${CYAN}  /scratch 디렉토리 권한 수정${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo ""

echo -e "${YELLOW}이 스크립트는 다음을 수행합니다:${NC}"
echo "  1. /scratch 디렉토리가 없으면 생성"
echo "  2. /scratch 권한을 1777 (모든 사용자 쓰기 가능)로 설정"
echo "  3. /scratch/apptainers 디렉토리 생성 및 권한 설정"
echo ""

read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""

# YAML에서 노드 정보 추출
echo "노드 정보를 읽는 중..."
node_info=$(python3 << EOF
import yaml
import sys

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
    sys.exit(1)
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
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}노드: $hostname ($ip)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 1. 현재 /scratch 상태 확인
    echo ""
    echo "[1/4] 현재 /scratch 상태 확인..."
    current_status=$(ssh "${ssh_user}@${ip}" "ls -ld /scratch 2>&1" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "  현재 상태: $current_status"
    else
        echo "  /scratch 디렉토리가 없습니다"
    fi
    
    # 2. /scratch 디렉토리 생성 및 권한 설정
    echo ""
    echo "[2/4] /scratch 디렉토리 생성 및 권한 설정..."
    
    result=$(ssh "${ssh_user}@${ip}" "sudo mkdir -p /scratch && sudo chmod 1777 /scratch && echo 'SUCCESS'" 2>&1)
    
    if echo "$result" | grep -q "SUCCESS"; then
        echo -e "  ${GREEN}✓${NC} /scratch 디렉토리 설정 완료"
    else
        echo -e "  ${RED}✗${NC} 실패: $result"
        echo ""
        echo -e "  ${YELLOW}수동 실행이 필요합니다:${NC}"
        echo "    ssh ${ssh_user}@${ip}"
        echo "    sudo mkdir -p /scratch"
        echo "    sudo chmod 1777 /scratch"
        echo ""
        failed=$((failed + 1))
        continue
    fi
    
    # 3. /scratch/apptainers 디렉토리 생성
    echo ""
    echo "[3/4] /scratch/apptainers 디렉토리 생성..."
    
    result=$(ssh "${ssh_user}@${ip}" "mkdir -p /scratch/apptainers && chmod 755 /scratch/apptainers && echo 'SUCCESS'" 2>&1)
    
    if echo "$result" | grep -q "SUCCESS"; then
        echo -e "  ${GREEN}✓${NC} /scratch/apptainers 디렉토리 생성 완료"
    else
        echo -e "  ${YELLOW}!${NC} 일반 사용자로 실패. sudo로 재시도..."
        
        result=$(ssh "${ssh_user}@${ip}" "sudo mkdir -p /scratch/apptainers && sudo chown ${ssh_user}:${ssh_user} /scratch/apptainers && sudo chmod 755 /scratch/apptainers && echo 'SUCCESS'" 2>&1)
        
        if echo "$result" | grep -q "SUCCESS"; then
            echo -e "  ${GREEN}✓${NC} /scratch/apptainers 디렉토리 생성 완료 (sudo)"
        else
            echo -e "  ${RED}✗${NC} 실패: $result"
            failed=$((failed + 1))
            continue
        fi
    fi
    
    # 4. 최종 확인
    echo ""
    echo "[4/4] 최종 권한 확인..."
    
    scratch_info=$(ssh "${ssh_user}@${ip}" "ls -ld /scratch" 2>/dev/null)
    apptainers_info=$(ssh "${ssh_user}@${ip}" "ls -ld /scratch/apptainers" 2>/dev/null)
    
    echo "  /scratch:"
    echo "    $scratch_info"
    echo "  /scratch/apptainers:"
    echo "    $apptainers_info"
    
    # 쓰기 테스트
    echo ""
    echo "  쓰기 권한 테스트..."
    test_result=$(ssh "${ssh_user}@${ip}" "touch /scratch/test_file_$$ && rm /scratch/test_file_$$ && echo 'WRITE_OK'" 2>&1)
    
    if echo "$test_result" | grep -q "WRITE_OK"; then
        echo -e "  ${GREEN}✓${NC} 쓰기 권한 정상"
        success=$((success + 1))
    else
        echo -e "  ${RED}✗${NC} 쓰기 권한 없음"
        echo "  에러: $test_result"
        failed=$((failed + 1))
    fi
    
    echo ""
    
done <<< "$node_info"

echo -e "${CYAN}==================================================================${NC}"
echo -e "결과: 성공 ${GREEN}$success${NC}, 실패 ${RED}$failed${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✨ 모든 노드의 권한이 설정되었습니다!${NC}"
    echo ""
    echo "이제 동기화를 실행할 수 있습니다:"
    echo "  ./sync_apptainers_to_nodes.sh"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠️  일부 노드에서 실패했습니다.${NC}"
    echo ""
    echo "실패한 노드에 직접 로그인하여 수동으로 설정하세요:"
    echo ""
    while IFS='|' read -r hostname ip ssh_user; do
        echo "# $hostname:"
        echo "ssh ${ssh_user}@${ip}"
        echo "sudo mkdir -p /scratch"
        echo "sudo chmod 1777 /scratch"
        echo "mkdir -p /scratch/apptainers"
        echo "exit"
        echo ""
    done <<< "$node_info"
    
    exit 1
fi
