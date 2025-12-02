#!/bin/bash

################################################################################
# Apptainer 관리 기능 설정 스크립트
# 
# 이 스크립트는 새로 추가된 Apptainer 관리 기능을 위한
# 모든 권한과 설정을 확인하고 설정합니다.
################################################################################

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BLUE}==================================================================${NC}"
echo -e "${BLUE}  Apptainer 관리 기능 설정${NC}"
echo -e "${BLUE}==================================================================${NC}"
echo ""

# 1. 실행 권한 설정
echo -e "${GREEN}[1/5]${NC} 스크립트 실행 권한 설정..."
if [ -f "sync_apptainers_to_nodes.sh" ]; then
    chmod +x sync_apptainers_to_nodes.sh
    echo -e "  ${CYAN}✓${NC} sync_apptainers_to_nodes.sh"
else
    echo -e "  ${RED}✗${NC} sync_apptainers_to_nodes.sh 파일이 없습니다"
    exit 1
fi

if [ -f "setup_cluster_full.sh" ]; then
    chmod +x setup_cluster_full.sh
    echo -e "  ${CYAN}✓${NC} setup_cluster_full.sh"
else
    echo -e "  ${YELLOW}!${NC} setup_cluster_full.sh 파일이 없습니다 (경고)"
fi

echo ""

# 2. 디렉토리 확인
echo -e "${GREEN}[2/5]${NC} 디렉토리 구조 확인..."
if [ -d "apptainers" ]; then
    echo -e "  ${CYAN}✓${NC} apptainers/ 디렉토리 존재"
    
    # 파일 개수 확인
    def_count=$(find apptainers -type f -name "*.def" 2>/dev/null | wc -l)
    sif_count=$(find apptainers -type f -name "*.sif" 2>/dev/null | wc -l)
    
    echo -e "  ${CYAN}→${NC} Definition 파일 (.def): $def_count"
    echo -e "  ${CYAN}→${NC} Image 파일 (.sif): $sif_count"
    
    if [ -f "apptainers/README.md" ]; then
        echo -e "  ${CYAN}✓${NC} apptainers/README.md 존재"
    fi
    
    if [ -f "apptainers/ubuntu_python.def" ]; then
        echo -e "  ${CYAN}✓${NC} 예제 파일 (ubuntu_python.def) 존재"
    fi
else
    echo -e "  ${RED}✗${NC} apptainers/ 디렉토리가 없습니다"
    exit 1
fi

echo ""

# 3. 설정 파일 확인
echo -e "${GREEN}[3/5]${NC} 설정 파일 확인..."
if [ -f "my_cluster.yaml" ]; then
    echo -e "  ${CYAN}✓${NC} my_cluster.yaml 존재"
    
    # Apptainer 설정 확인
    if grep -q "apptainer:" my_cluster.yaml; then
        echo -e "  ${CYAN}✓${NC} Apptainer 설정 발견"
        
        # enabled 확인
        if grep -A1 "apptainer:" my_cluster.yaml | grep -q "enabled: true"; then
            echo -e "  ${CYAN}✓${NC} Apptainer 활성화됨"
        else
            echo -e "  ${YELLOW}!${NC} Apptainer가 비활성화되어 있을 수 있습니다"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Apptainer 설정이 없습니다 (선택사항)"
    fi
    
    # 계산 노드 확인
    if grep -q "compute_nodes:" my_cluster.yaml; then
        node_count=$(grep -A100 "compute_nodes:" my_cluster.yaml | grep "hostname:" | wc -l)
        echo -e "  ${CYAN}✓${NC} 계산 노드 수: $node_count"
    else
        echo -e "  ${RED}✗${NC} compute_nodes 설정이 없습니다"
        exit 1
    fi
else
    echo -e "  ${RED}✗${NC} my_cluster.yaml 파일이 없습니다"
    exit 1
fi

echo ""

# 4. 필수 도구 확인
echo -e "${GREEN}[4/5]${NC} 필수 도구 확인..."

tools_ok=true

if command -v python3 &> /dev/null; then
    version=$(python3 --version 2>&1 | awk '{print $2}')
    echo -e "  ${CYAN}✓${NC} Python3: $version"
else
    echo -e "  ${RED}✗${NC} Python3가 설치되어 있지 않습니다"
    tools_ok=false
fi

if command -v ssh &> /dev/null; then
    echo -e "  ${CYAN}✓${NC} SSH 클라이언트"
else
    echo -e "  ${RED}✗${NC} SSH 클라이언트가 설치되어 있지 않습니다"
    tools_ok=false
fi

if command -v rsync &> /dev/null; then
    version=$(rsync --version | head -1 | awk '{print $3}')
    echo -e "  ${CYAN}✓${NC} rsync: $version"
else
    echo -e "  ${RED}✗${NC} rsync가 설치되어 있지 않습니다"
    echo -e "      설치: sudo apt-get install rsync"
    tools_ok=false
fi

if command -v apptainer &> /dev/null; then
    version=$(apptainer --version 2>&1)
    echo -e "  ${CYAN}✓${NC} Apptainer: $version"
else
    echo -e "  ${YELLOW}!${NC} Apptainer가 설치되어 있지 않습니다 (선택사항)"
    echo -e "      이미지 빌드 시 필요합니다"
fi

if [ "$tools_ok" = false ]; then
    echo ""
    echo -e "${RED}필수 도구가 설치되지 않았습니다. 위의 지시사항을 따라 설치하세요.${NC}"
    exit 1
fi

echo ""

# 5. SSH 연결 테스트
echo -e "${GREEN}[5/5]${NC} SSH 연결 테스트..."
echo -e "  ${CYAN}→${NC} YAML 파일에서 노드 정보 추출 중..."

# Python으로 노드 정보 추출
node_info=$(python3 << 'EOF'
import yaml
import sys

try:
    with open('my_cluster.yaml', 'r') as f:
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
    echo -e "  ${RED}✗${NC} 노드 정보를 추출할 수 없습니다"
    exit 1
fi

echo ""
ssh_ok=true
while IFS='|' read -r hostname ip ssh_user; do
    echo -e "  ${CYAN}→${NC} $hostname ($ip) 연결 테스트..."
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "${ssh_user}@${ip}" "exit" 2>/dev/null; then
        echo -e "    ${GREEN}✓${NC} 연결 성공"
    else
        echo -e "    ${RED}✗${NC} 연결 실패"
        echo -e "      SSH 키를 설정하세요: ssh-copy-id ${ssh_user}@${ip}"
        ssh_ok=false
    fi
done <<< "$node_info"

if [ "$ssh_ok" = false ]; then
    echo ""
    echo -e "${YELLOW}경고: 일부 노드에 SSH 연결할 수 없습니다.${NC}"
    echo -e "${YELLOW}계속 진행하려면 SSH 키를 설정하세요.${NC}"
fi

echo ""
echo -e "${BLUE}==================================================================${NC}"
echo -e "${GREEN}  설정 완료!${NC}"
echo -e "${BLUE}==================================================================${NC}"
echo ""

# 사용 가이드 출력
echo -e "${CYAN}다음 단계:${NC}"
echo ""
echo "1. Apptainer 이미지 준비:"
echo "   cd apptainers/"
echo "   sudo apptainer build myapp.sif myapp.def"
echo ""
echo "2. 노드로 동기화:"
echo "   cd .."
echo "   ./sync_apptainers_to_nodes.sh"
echo ""
echo "3. 자동 설치 스크립트에서 사용:"
echo "   ./setup_cluster_full.sh"
echo "   (Step 13에서 자동으로 동기화 여부를 물어봅니다)"
echo ""
echo "4. 상세 가이드:"
echo "   cat APPTAINER_MANAGEMENT_GUIDE.md"
echo "   cat APPTAINER_SETUP_COMPLETE.md"
echo "   cat apptainers/README.md"
echo ""

echo -e "${GREEN}✨ 모든 설정이 완료되었습니다!${NC}"
echo ""
