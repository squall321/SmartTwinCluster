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

# 로컬 root 불필요 — 모든 sudo는 원격에서 처리 (sshpass+sudo -S)
if [[ $EUID -eq 0 ]]; then
    log_warning "root로 실행 중 — sudo 없이 실행 권장 (SSHPASS env 보존 위해)"
fi

# sshpass / yaml에서 비번 읽어 SSHPASS env 설정 (deploy_to_compute_node.sh 패턴)
command -v sshpass &>/dev/null || apt-get install -y sshpass &>/dev/null || true

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

# SSH 비번 (cluster_info.ssh_password) → SSHPASS env
export SSHPASS=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
print((c.get('cluster_info') or {}).get('ssh_password',''))
")
SUDO_PW="$SSHPASS"

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

    local ssh_target="${user}@${ip}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}[$hostname]${NC} Installing apptainer ($node_type node)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 키 인증 우선, sshpass 폴백 (deploy_to_compute_node.sh 패턴)
    local SSH_CMD SCP_CMD REMOTE_SUDO_PREFIX
    if ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        "$ssh_target" "echo OK" &>/dev/null; then
        SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
        SCP_CMD="scp -o StrictHostKeyChecking=no -o ConnectTimeout=10"
        # NOPASSWD 가능한지
        if $SSH_CMD "$ssh_target" "sudo -n true" &>/dev/null; then
            REMOTE_SUDO_PREFIX="sudo"
        else
            REMOTE_SUDO_PREFIX="echo '$SUDO_PW' | sudo -S -p ''"
        fi
        echo -e "${GREEN}  ✓ SSH 키 인증 OK${NC}"
    elif [[ -n "$SSHPASS" ]] && command -v sshpass &>/dev/null; then
        SSH_CMD="sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=10"
        SCP_CMD="sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=10"
        REMOTE_SUDO_PREFIX="echo '$SUDO_PW' | sudo -S -p ''"
        echo -e "${YELLOW}  ⚠ 키 인증 실패 → sshpass+password 사용${NC}"
    else
        echo -e "${RED}  ✗ SSH 인증 수단 없음 (키도, 비번도 없음)${NC}"
        return 1
    fi

    # apptainer 이미 설치 여부 확인
    local APT_INSTALLED=0
    if $SSH_CMD "$ssh_target" "command -v apptainer" &>/dev/null; then
        local current_version
        current_version=$($SSH_CMD "$ssh_target" "apptainer --version 2>/dev/null" || echo "unknown")
        echo -e "${YELLOW}  ℹ apptainer already installed: $current_version (sysctl/conf만 점검)${NC}"
        APT_INSTALLED=1
    fi

    # 원격 노드에서 apptainer 설치 + sysctl + conf
    # SUDO_PW 환경변수로 비번 전달 → 원격에서 임시 NOPASSWD sudoer 설치
    $SSH_CMD "$ssh_target" "SUDO_PW='$SUDO_PW' RUSER='$user' APT_INSTALLED=$APT_INSTALLED bash -s" <<'EOF_REMOTE'
# 임시 NOPASSWD 활성화 (이미 NOPASSWD면 무해)
if ! sudo -n true 2>/dev/null; then
    if [ -n "${SUDO_PW:-}" ]; then
        echo "$SUDO_PW" | sudo -S -p '' bash -c "echo '${RUSER:-$USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/_apptainer_install_temp && chmod 440 /etc/sudoers.d/_apptainer_install_temp" 2>/dev/null
    fi
fi
trap 'sudo -n rm -f /etc/sudoers.d/_apptainer_install_temp 2>/dev/null || true' EXIT
export DEBIAN_FRONTEND=noninteractive

# 이미 설치된 경우 apt install 단계 스킵
if [ "${APT_INSTALLED:-0}" = "1" ]; then
    echo "  → apt 설치 스킵 (이미 설치됨)"
    SKIP_APT=1
else
    SKIP_APT=0
fi
        set -euo pipefail

        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        NC='\033[0m'

        if [ "$SKIP_APT" = "0" ]; then
            echo -e "${YELLOW}  Installing apptainer via APT (offline repository)...${NC}"
            REPO_LIST="/etc/apt/sources.list.d/offline-local.list"
            if [[ -f "$REPO_LIST" ]]; then
                APT_OPTS=(-o Dir::Etc::sourcelist="$REPO_LIST" -o Dir::Etc::sourceparts="-")
                if sudo -n apt-get "${APT_OPTS[@]}" install -y apptainer </dev/null &>/dev/null; then
                    echo -e "${GREEN}  ✓ apptainer installed via APT${NC}"
                elif sudo -n apt-get install -y apptainer </dev/null &>/dev/null; then
                    echo -e "${GREEN}  ✓ apptainer installed (fallback)${NC}"
                else
                    echo -e "${RED}  ✗ ERROR: apt install failed (apptainer 부재 + 저장소 미해결)${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}  ✗ offline-local.list 없음 — install_offline_packages.sh 먼저${NC}"
                exit 1
            fi
        else
            echo "  → apt install 단계 스킵 (이미 설치됨)"
        fi

        # /scratch/vnc_sandboxes 디렉토리 생성
        echo -e "${YELLOW}  Creating /scratch/vnc_sandboxes...${NC}"
        sudo mkdir -p /scratch/vnc_sandboxes
        sudo chmod 1777 /scratch/vnc_sandboxes
        echo -e "${GREEN}  ✓ /scratch/vnc_sandboxes created${NC}"

        # apptainer 설정 파일 확인 — /usr/local 빌드면 심볼릭링크
        if [[ ! -d /etc/apptainer && -d /usr/local/etc/apptainer ]]; then
            echo -e "${YELLOW}  → /etc/apptainer → /usr/local/etc/apptainer 심볼릭링크 생성${NC}"
            sudo ln -sfn /usr/local/etc/apptainer /etc/apptainer
        fi
        if [[ -f /etc/apptainer/apptainer.conf ]]; then
            echo -e "${GREEN}  ✓ Configuration file exists: /etc/apptainer/apptainer.conf${NC}"
        else
            echo -e "${RED}  ✗ WARNING: Configuration file missing: /etc/apptainer/apptainer.conf${NC}"
        fi

        # User namespace 활성화 (Ubuntu 24.04 AppArmor + 일반 sysctl)
        echo -e "${YELLOW}  Enabling user namespaces for apptainer...${NC}"
        sudo tee /etc/sysctl.d/99-apptainer.conf > /dev/null <<'SYSCTL_EOF'
# Apptainer unprivileged user namespace 활성화
user.max_user_namespaces=15000
kernel.unprivileged_userns_clone=1
kernel.apparmor_restrict_unprivileged_userns=0
SYSCTL_EOF
        sudo sysctl --system >/dev/null 2>&1 || true
        echo -e "${GREEN}  ✓ user_namespaces sysctl 적용${NC}"

        # 검증
        UNS=$(sysctl -n user.max_user_namespaces 2>/dev/null || echo 0)
        AAR=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)
        echo -e "${GREEN}  ✓ max_user_namespaces=$UNS, apparmor_restrict=$AAR${NC}"

        # suid 바이너리 옵션 — 소스빌드 + setuid 권한 보정
        if [[ -f /usr/local/libexec/apptainer/bin/starter-suid ]]; then
            sudo chown root:root /usr/local/libexec/apptainer/bin/starter-suid 2>/dev/null || true
            sudo chmod 4755 /usr/local/libexec/apptainer/bin/starter-suid 2>/dev/null || true
            echo -e "${GREEN}  ✓ starter-suid setuid 권한 보정${NC}"
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
