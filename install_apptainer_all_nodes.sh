#!/bin/bash
################################################################################
# apptainer 일괄 설치 스크립트 (모든 compute/viz 노드)
#
# 설명:
#   YAML 설정 파일에서 compute/viz 노드 목록을 읽고,
#   모든 노드에 apptainer를 오프라인 APT 저장소로 설치합니다.
#
# 사용법:
#   sudo ./install_apptainer_all_nodes.sh [OPTIONS]
#
# 옵션:
#   --config PATH        YAML 설정 파일 경로 (기본: my_multihead_cluster_2.yaml)
#   --node HOSTNAME      특정 노드만 설치 (생략 시 전체)
#   --parallel N         병렬 설치 개수 (기본: 3)
#   --yes, -y            확인 프롬프트 건너뛰기
#   --help               도움말 표시
#
# 예제:
#   # 모든 노드에 설치
#   sudo ./install_apptainer_all_nodes.sh
#
#   # 특정 노드만 설치
#   sudo ./install_apptainer_all_nodes.sh --node node001
#
#   # 병렬 설치 (5개씩)
#   sudo ./install_apptainer_all_nodes.sh --parallel 5
#
# 전제조건:
#   - 각 노드에 /etc/apt/sources.list.d/offline-local.list 설정되어 있어야 함
#   - 또는 오프라인 패키지 디렉토리가 각 노드에 있어야 함
#
# 작성자: Claude Code
# 날짜: 2026-01-21
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="${SCRIPT_DIR}/my_multihead_cluster_2.yaml"

# 기본값
CONFIG_FILE=""
TARGET_NODE=""
PARALLEL=3
AUTO_YES=false

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --node)
            TARGET_NODE="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL="$2"
            shift 2
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --help|-h)
            echo ""
            echo "╔════════════════════════════════════════════════════════════╗"
            echo "║       apptainer 일괄 설치 (모든 compute/viz 노드)         ║"
            echo "╚════════════════════════════════════════════════════════════╝"
            echo ""
            grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//' | head -42
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--config PATH] [--node HOSTNAME] [--parallel N] [--yes] [--help]"
            exit 1
            ;;
    esac
done

# Root 권한 확인
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    echo "Usage: sudo $0 [OPTIONS]"
    exit 1
fi

# 설정 파일 기본값
if [[ -z "$CONFIG_FILE" ]]; then
    if [[ -f "$DEFAULT_CONFIG" ]]; then
        CONFIG_FILE="$DEFAULT_CONFIG"
    elif [[ -f "${SCRIPT_DIR}/my_multihead_cluster.yaml" ]]; then
        CONFIG_FILE="${SCRIPT_DIR}/my_multihead_cluster.yaml"
    else
        log_error "No config file specified and default not found"
        echo "Usage: $0 --config <path_to_yaml>"
        exit 1
    fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║       apptainer 일괄 설치 (모든 compute/viz 노드)         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Config: $CONFIG_FILE"
echo ""

# Python으로 YAML 파싱하여 노드 목록 추출
log_info "Reading compute/viz nodes from YAML..."
echo ""

NODES_JSON=$(python3 << EOPY
import sys
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

import json

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
except FileNotFoundError:
    print(f"ERROR: Config file not found: $CONFIG_FILE", file=sys.stderr)
    sys.exit(1)
except yaml.YAMLError as e:
    print(f"ERROR: Invalid YAML: {e}", file=sys.stderr)
    sys.exit(1)

nodes = []

# compute_nodes 추출 (node_type 필드로 compute/viz 구분)
compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
for node in compute_nodes:
    if 'hostname' not in node or 'ip_address' not in node:
        print(f"WARNING: Skipping invalid compute node: {node}", file=sys.stderr)
        continue
    node_type = node.get('node_type', 'compute')
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark'),
        'type': node_type
    })

# viz_nodes 추출 (별도 섹션이 있는 경우)
viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
for node in viz_nodes:
    if 'hostname' not in node or 'ip_address' not in node:
        print(f"WARNING: Skipping invalid viz node: {node}", file=sys.stderr)
        continue
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark'),
        'type': 'viz'
    })

if not nodes:
    print("WARNING: No compute_nodes or viz_nodes found in YAML", file=sys.stderr)

print(json.dumps(nodes))
EOPY
)

if [[ $? -ne 0 ]] || [[ "$NODES_JSON" == "[]" ]]; then
    log_error "Failed to read nodes from YAML or no nodes found"
    exit 1
fi

# 노드 목록 출력
TOTAL_NODES=$(echo "$NODES_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
log_success "Found $TOTAL_NODES compute/viz nodes:"
echo ""

echo "$NODES_JSON" | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
for i, node in enumerate(nodes, 1):
    print(f'  {i}. {node[\"hostname\"]:20s} {node[\"ip\"]:16s} [{node[\"type\"]}]')
"
echo ""

# 특정 노드만 설치하는 경우
if [[ -n "$TARGET_NODE" ]]; then
    log_info "Filtering by target node: $TARGET_NODE"
    NODES_JSON=$(echo "$NODES_JSON" | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
filtered = [n for n in nodes if n['hostname'] == '$TARGET_NODE']
print(json.dumps(filtered))
")

    if [[ "$NODES_JSON" == "[]" ]]; then
        log_error "Target node not found: $TARGET_NODE"
        exit 1
    fi

    TOTAL_NODES=1
    log_info "Target node: $TARGET_NODE"
    echo ""
fi

# 확인 프롬프트
if [[ "$AUTO_YES" == false ]]; then
    read -p "Install apptainer on $TOTAL_NODES node(s)? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    echo ""
fi

# apptainer 설치 함수 (단일 노드)
install_apptainer_on_node() {
    local hostname="$1"
    local ip="$2"
    local user="$3"
    local node_type="$4"

    local ssh_target="${user}@${hostname}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}[$hostname]${NC} Installing apptainer ($node_type node)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # SSH 연결 테스트
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$ssh_target" "echo SSH OK" &>/dev/null; then
        echo -e "${RED}  ✗ SSH connection failed${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ SSH connected${NC}"

    # apptainer 이미 설치 여부 확인
    if ssh "$ssh_target" "command -v apptainer" &>/dev/null; then
        local current_version
        current_version=$(ssh "$ssh_target" "apptainer --version 2>/dev/null" || echo "unknown")
        echo -e "${YELLOW}  ℹ apptainer already installed: $current_version${NC}"
        echo -e "${CYAN}  Skipping (already installed)${NC}"
        return 0
    fi

    # 원격 노드에서 apptainer 설치
    ssh "$ssh_target" bash << 'EOF_REMOTE'
        set -euo pipefail

        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        NC='\033[0m'

        echo -e "${YELLOW}  Installing apptainer via APT (offline repository)...${NC}"

        # APT 로컬 저장소 확인
        REPO_LIST="/etc/apt/sources.list.d/offline-local.list"

        if [[ -f "$REPO_LIST" ]]; then
            echo -e "${GREEN}  ✓ Offline APT repository found${NC}"

            # apt-get install로 설치 (의존성 및 설정 파일 자동 처리)
            APT_OPTS=(-o Dir::Etc::sourcelist="$REPO_LIST" -o Dir::Etc::sourceparts="-")

            if sudo apt-get "${APT_OPTS[@]}" install -y apptainer &>/dev/null; then
                VERSION=$(apptainer --version 2>/dev/null || echo "unknown")
                echo -e "${GREEN}  ✓ apptainer installed via APT: $VERSION${NC}"
            else
                echo -e "${YELLOW}  ⚠️  APT install failed (local-only), trying with all sources...${NC}"
                if sudo apt-get install -y apptainer &>/dev/null; then
                    VERSION=$(apptainer --version 2>/dev/null || echo "unknown")
                    echo -e "${GREEN}  ✓ apptainer installed: $VERSION${NC}"
                else
                    echo -e "${RED}  ✗ ERROR: apptainer installation failed${NC}"
                    exit 1
                fi
            fi
        else
            echo -e "${RED}  ✗ ERROR: Offline APT repository not configured: $REPO_LIST${NC}"
            echo -e "${YELLOW}  Please run Step 1 (install_offline_packages.sh) first${NC}"
            exit 1
        fi

        # /scratch/vnc_sandboxes 디렉토리 생성
        echo -e "${YELLOW}  Creating /scratch/vnc_sandboxes...${NC}"
        sudo mkdir -p /scratch/vnc_sandboxes
        sudo chmod 1777 /scratch/vnc_sandboxes
        echo -e "${GREEN}  ✓ /scratch/vnc_sandboxes created${NC}"

        # apptainer 설정 파일 확인
        if [[ -f /etc/apptainer/apptainer.conf ]]; then
            echo -e "${GREEN}  ✓ Configuration file exists: /etc/apptainer/apptainer.conf${NC}"
        else
            echo -e "${RED}  ✗ WARNING: Configuration file missing: /etc/apptainer/apptainer.conf${NC}"
        fi
EOF_REMOTE

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}  ✅ [$hostname] apptainer installation successful${NC}"
        return 0
    else
        echo -e "${RED}  ❌ [$hostname] apptainer installation failed${NC}"
        return 1
    fi
}

# 병렬 설치 관리
log_info "Starting installation (parallel: $PARALLEL)..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# 노드별 설치 (병렬 처리)
declare -a PIDS=()
declare -a NODE_NAMES=()

echo "$NODES_JSON" | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
for node in nodes:
    print(f'{node[\"hostname\"]}|{node[\"ip\"]}|{node[\"user\"]}|{node[\"type\"]}')
" | while IFS='|' read -r hostname ip user node_type; do

    # 병렬 제한
    while [[ ${#PIDS[@]} -ge $PARALLEL ]]; do
        for i in "${!PIDS[@]}"; do
            if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
                wait "${PIDS[$i]}" || true
                unset "PIDS[$i]"
                unset "NODE_NAMES[$i]"
            fi
        done
        PIDS=("${PIDS[@]}")  # 배열 재정렬
        NODE_NAMES=("${NODE_NAMES[@]}")
        sleep 1
    done

    # 백그라운드로 설치 시작
    (
        install_apptainer_on_node "$hostname" "$ip" "$user" "$node_type"
    ) &

    PIDS+=($!)
    NODE_NAMES+=("$hostname")

    sleep 0.5  # SSH 연결 간격
done

# 모든 작업 대기
log_info "Waiting for all installations to complete..."
for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        wait "$pid" || true
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Installation Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 설치 결과 확인
echo "$NODES_JSON" | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
for node in nodes:
    print(node['hostname'])
" | while read -r hostname; do
    if ssh "${hostname}" "command -v apptainer && apptainer --version" &>/dev/null; then
        VERSION=$(ssh "${hostname}" "apptainer --version 2>/dev/null" || echo "unknown")
        echo -e "${GREEN}  ✓ $hostname: $VERSION${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}  ✗ $hostname: Installation failed or not found${NC}"
        ((FAIL_COUNT++))
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          ✅ apptainer 일괄 설치 완료!                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Installation completed"
echo "  Total nodes: $TOTAL_NODES"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    log_warning "Some installations failed. Check logs above for details."
    exit 1
fi

log_success "All installations completed successfully!"
echo ""
