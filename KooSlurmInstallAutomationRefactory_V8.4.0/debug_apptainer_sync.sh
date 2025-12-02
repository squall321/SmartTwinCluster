#!/bin/bash

################################################################################
# Apptainer 동기화 디버그 스크립트
# 
# SSH 연결 및 디렉토리 생성 문제를 진단합니다.
################################################################################

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/my_cluster.yaml"
REMOTE_APPTAINER_DIR="/scratch/apptainers"

echo ""
echo -e "${BLUE}==================================================================${NC}"
echo -e "${BLUE}  Apptainer 동기화 문제 진단${NC}"
echo -e "${BLUE}==================================================================${NC}"
echo ""

# 1. YAML에서 노드 정보 추출
echo -e "${CYAN}[1] 노드 정보 추출 중...${NC}"
echo ""

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
        ssh_port = node.get('ssh_port', 22)
        ssh_key = node.get('ssh_key_path', '~/.ssh/id_rsa')
        
        if hostname and ip:
            print(f"{hostname}|{ip}|{ssh_user}|{ssh_port}|{ssh_key}")
            
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
)

if [ -z "$node_info" ]; then
    echo -e "${RED}✗ 노드 정보를 추출할 수 없습니다${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 노드 정보 추출 성공${NC}"
echo ""

# 2. 각 노드별 진단
while IFS='|' read -r hostname ip ssh_user ssh_port ssh_key; do
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}노드: $hostname ($ip)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # SSH 키 경로 확장
    ssh_key_expanded=$(eval echo "$ssh_key")
    
    echo -e "${CYAN}[2-1] SSH 키 확인${NC}"
    echo "  경로: $ssh_key_expanded"
    if [ -f "$ssh_key_expanded" ]; then
        echo -e "  ${GREEN}✓ SSH 키 파일 존재${NC}"
        ls -lh "$ssh_key_expanded"
    else
        echo -e "  ${RED}✗ SSH 키 파일이 없습니다${NC}"
        echo "  해결: ssh-keygen -t rsa -b 4096 -f $ssh_key_expanded"
    fi
    echo ""
    
    echo -e "${CYAN}[2-2] SSH 연결 테스트${NC}"
    echo "  명령: ssh -p $ssh_port -i $ssh_key_expanded ${ssh_user}@${ip} 'echo OK'"
    
    if ssh -o BatchMode=yes \
           -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no \
           -p "$ssh_port" \
           -i "$ssh_key_expanded" \
           "${ssh_user}@${ip}" \
           "echo 'SSH 연결 성공'" 2>/dev/null; then
        echo -e "  ${GREEN}✓ SSH 연결 성공${NC}"
    else
        echo -e "  ${RED}✗ SSH 연결 실패${NC}"
        echo ""
        echo -e "  ${YELLOW}디버그 정보:${NC}"
        ssh -v -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=no \
            -p "$ssh_port" \
            -i "$ssh_key_expanded" \
            "${ssh_user}@${ip}" \
            "echo 'TEST'" 2>&1 | tail -20
        echo ""
        echo -e "  ${YELLOW}해결 방법:${NC}"
        echo "    1. SSH 키 복사: ssh-copy-id -i ${ssh_key_expanded}.pub -p ${ssh_port} ${ssh_user}@${ip}"
        echo "    2. 수동 테스트: ssh -p ${ssh_port} ${ssh_user}@${ip} 'hostname'"
        echo ""
        continue
    fi
    echo ""
    
    echo -e "${CYAN}[2-3] /scratch 디렉토리 확인${NC}"
    scratch_check=$(ssh -o StrictHostKeyChecking=no \
                        -p "$ssh_port" \
                        -i "$ssh_key_expanded" \
                        "${ssh_user}@${ip}" \
                        "ls -ld /scratch 2>&1" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓ /scratch 디렉토리 존재${NC}"
        echo "  $scratch_check"
    else
        echo -e "  ${RED}✗ /scratch 디렉토리 없음${NC}"
        echo "  $scratch_check"
        echo ""
        echo -e "  ${YELLOW}해결 방법:${NC}"
        echo "    ssh -p ${ssh_port} ${ssh_user}@${ip} 'sudo mkdir -p /scratch && sudo chmod 1777 /scratch'"
    fi
    echo ""
    
    echo -e "${CYAN}[2-4] 디렉토리 생성 권한 테스트${NC}"
    test_dir="/scratch/test_$$"
    
    create_result=$(ssh -o StrictHostKeyChecking=no \
                        -p "$ssh_port" \
                        -i "$ssh_key_expanded" \
                        "${ssh_user}@${ip}" \
                        "mkdir -p $test_dir && echo 'SUCCESS' && rmdir $test_dir" 2>&1)
    
    if echo "$create_result" | grep -q "SUCCESS"; then
        echo -e "  ${GREEN}✓ 디렉토리 생성 가능${NC}"
    else
        echo -e "  ${RED}✗ 디렉토리 생성 실패${NC}"
        echo "  에러: $create_result"
        echo ""
        echo -e "  ${YELLOW}가능한 원인:${NC}"
        echo "    1. /scratch 디렉토리 권한 부족"
        echo "    2. 디스크 공간 부족"
        echo "    3. 파일시스템이 읽기 전용"
        echo ""
        echo -e "  ${YELLOW}해결 방법:${NC}"
        echo "    ssh -p ${ssh_port} ${ssh_user}@${ip} 'sudo chmod 1777 /scratch'"
    fi
    echo ""
    
    echo -e "${CYAN}[2-5] 실제 Apptainer 디렉토리 생성 시도${NC}"
    echo "  경로: $REMOTE_APPTAINER_DIR"
    
    create_apptainer_result=$(ssh -o StrictHostKeyChecking=no \
                                 -p "$ssh_port" \
                                 -i "$ssh_key_expanded" \
                                 "${ssh_user}@${ip}" \
                                 "mkdir -p $REMOTE_APPTAINER_DIR && chmod 755 $REMOTE_APPTAINER_DIR && echo 'SUCCESS'" 2>&1)
    
    if echo "$create_apptainer_result" | grep -q "SUCCESS"; then
        echo -e "  ${GREEN}✓ $REMOTE_APPTAINER_DIR 생성 성공${NC}"
        
        # 확인
        dir_info=$(ssh -o StrictHostKeyChecking=no \
                      -p "$ssh_port" \
                      -i "$ssh_key_expanded" \
                      "${ssh_user}@${ip}" \
                      "ls -ld $REMOTE_APPTAINER_DIR" 2>/dev/null)
        echo "  $dir_info"
    else
        echo -e "  ${RED}✗ 디렉토리 생성 실패${NC}"
        echo "  에러: $create_apptainer_result"
        echo ""
        echo -e "  ${YELLOW}수동 해결:${NC}"
        echo "    ssh -p ${ssh_port} ${ssh_user}@${ip}"
        echo "    sudo mkdir -p $REMOTE_APPTAINER_DIR"
        echo "    sudo chown ${ssh_user}:${ssh_user} $REMOTE_APPTAINER_DIR"
        echo "    sudo chmod 755 $REMOTE_APPTAINER_DIR"
    fi
    echo ""
    
    echo -e "${CYAN}[2-6] 디스크 공간 확인${NC}"
    disk_info=$(ssh -o StrictHostKeyChecking=no \
                   -p "$ssh_port" \
                   -i "$ssh_key_expanded" \
                   "${ssh_user}@${ip}" \
                   "df -h /scratch" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "$disk_info"
    else
        echo -e "  ${YELLOW}! 디스크 정보를 가져올 수 없습니다${NC}"
    fi
    echo ""
    
done <<< "$node_info"

echo -e "${BLUE}==================================================================${NC}"
echo -e "${GREEN}  진단 완료${NC}"
echo -e "${BLUE}==================================================================${NC}"
echo ""

echo -e "${CYAN}다음 단계:${NC}"
echo ""
echo "1. 위의 오류를 모두 해결한 후 동기화 재시도:"
echo "   ./sync_apptainers_to_nodes.sh"
echo ""
echo "2. 수동으로 디렉토리 생성이 필요한 경우:"
echo "   ssh node001 'sudo mkdir -p /scratch/apptainers && sudo chown \$USER:\$USER /scratch/apptainers'"
echo "   ssh node002 'sudo mkdir -p /scratch/apptainers && sudo chown \$USER:\$USER /scratch/apptainers'"
echo ""
