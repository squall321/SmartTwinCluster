#!/bin/bash
#
# diagnose_nodes.sh - Slurm 노드 상태 진단 스크립트
#
# 모든 compute/viz 노드의 Slurm 상태를 확인하고
# down/drain/idle* 노드의 원인을 진단합니다.
#
# 사용법: ./diagnose_nodes.sh <cluster_yaml>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-}"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 사용법 출력
usage() {
    echo "Usage: $0 <cluster_yaml>"
    echo ""
    echo "Example:"
    echo "  $0 my_multihead_cluster.yaml"
    exit 1
}

if [[ -z "$CONFIG_FILE" ]]; then
    log_error "Configuration file not specified"
    usage
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Slurm Cluster Node Diagnostics                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Slurm 명령어 경로 확인
SINFO="/usr/local/slurm/bin/sinfo"
SCONTROL="/usr/local/slurm/bin/scontrol"

if [[ ! -x "$SINFO" ]]; then
    SINFO="sinfo"
fi

if [[ ! -x "$SCONTROL" ]]; then
    SCONTROL="scontrol"
fi

# 1. 전체 노드 상태 요약
echo "═══════════════════════════════════════════════════════════"
echo "1. CLUSTER OVERVIEW"
echo "═══════════════════════════════════════════════════════════"
echo ""

$SINFO -N -l 2>/dev/null || {
    log_error "Failed to run sinfo. Is slurmctld running?"
    exit 1
}

echo ""

# 2. 노드 상태별 분류
echo "═══════════════════════════════════════════════════════════"
echo "2. NODE STATE SUMMARY"
echo "═══════════════════════════════════════════════════════════"
echo ""

IDLE_COUNT=$($SINFO -N -h -o "%T" 2>/dev/null | grep -c "^idle$" || echo 0)
IDLE_STAR_COUNT=$($SINFO -N -h -o "%T" 2>/dev/null | grep -c "idle\*" || echo 0)
DOWN_COUNT=$($SINFO -N -h -o "%T" 2>/dev/null | grep -c "down" || echo 0)
DRAIN_COUNT=$($SINFO -N -h -o "%T" 2>/dev/null | grep -c "drain" || echo 0)
ALLOC_COUNT=$($SINFO -N -h -o "%T" 2>/dev/null | grep -c "alloc" || echo 0)
MIX_COUNT=$($SINFO -N -h -o "%T" 2>/dev/null | grep -c "mix" || echo 0)

log_success "IDLE (healthy):        $IDLE_COUNT nodes"
if [[ $IDLE_STAR_COUNT -gt 0 ]]; then
    log_warning "IDLE* (not responding): $IDLE_STAR_COUNT nodes"
fi
if [[ $DOWN_COUNT -gt 0 ]]; then
    log_error "DOWN:                  $DOWN_COUNT nodes"
fi
if [[ $DRAIN_COUNT -gt 0 ]]; then
    log_warning "DRAIN:                 $DRAIN_COUNT nodes"
fi
if [[ $ALLOC_COUNT -gt 0 ]]; then
    log_info "ALLOCATED:             $ALLOC_COUNT nodes"
fi
if [[ $MIX_COUNT -gt 0 ]]; then
    log_info "MIXED:                 $MIX_COUNT nodes"
fi

echo ""

# 문제 노드 목록 추출
PROBLEM_NODES=$($SINFO -N -h -o "%N %T" 2>/dev/null | grep -E "down|drain|idle\*|unknown" | awk '{print $1}' || true)

if [[ -z "$PROBLEM_NODES" ]]; then
    log_success "All nodes are healthy! (IDLE or ALLOCATED)"
    exit 0
fi

echo "═══════════════════════════════════════════════════════════"
echo "3. PROBLEM NODES DETAILED DIAGNOSIS"
echo "═══════════════════════════════════════════════════════════"
echo ""

# YAML에서 노드 정보 가져오기
get_node_info() {
    local hostname="$1"
    python3 << EOPY
import yaml
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)

    # compute_nodes 검색
    for node in config.get('nodes', {}).get('compute_nodes', []):
        if node.get('hostname') == '$hostname':
            print(f"{node.get('ip_address', 'unknown')}|{node.get('ssh_user', 'koopark')}")
            exit(0)

    # viz_nodes 검색
    for node in config.get('nodes', {}).get('viz_nodes', []):
        if node.get('hostname') == '$hostname':
            print(f"{node.get('ip_address', 'unknown')}|{node.get('ssh_user', 'koopark')}")
            exit(0)

    print("unknown|koopark")
except:
    print("unknown|koopark")
EOPY
}

# 각 문제 노드 진단
NODE_NUM=0
for node in $PROBLEM_NODES; do
    NODE_NUM=$((NODE_NUM + 1))

    echo ""
    echo "───────────────────────────────────────────────────────────"
    echo "Problem Node #$NODE_NUM: $node"
    echo "───────────────────────────────────────────────────────────"

    # scontrol로 노드 상태 확인
    NODE_STATE=$($SCONTROL show node "$node" 2>/dev/null | grep "State=" | head -1 || echo "State=UNKNOWN")
    NODE_REASON=$($SCONTROL show node "$node" 2>/dev/null | grep "Reason=" | head -1 || echo "Reason=unknown")

    echo "  Slurm State: $NODE_STATE"
    echo "  Reason:      $NODE_REASON"
    echo ""

    # YAML에서 노드 정보 가져오기
    NODE_INFO=$(get_node_info "$node")
    NODE_IP=$(echo "$NODE_INFO" | cut -d'|' -f1)
    NODE_USER=$(echo "$NODE_INFO" | cut -d'|' -f2)

    if [[ "$NODE_IP" == "unknown" ]]; then
        log_warning "  ⚠️  Node $node not found in YAML config"
        continue
    fi

    echo "  IP Address:  $NODE_IP"
    echo "  SSH User:    $NODE_USER"
    echo ""

    # SSH 접속 테스트
    echo "  → Testing SSH connection..."
    SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes -o PasswordAuthentication=no"

    # 먼저 SSH 키로 접속 시도
    SSH_TEST_OUTPUT=$(ssh $SSH_OPTS "$NODE_USER@$NODE_IP" "echo ok" 2>&1)
    SSH_TEST_RESULT=$?

    if [[ $SSH_TEST_RESULT -ne 0 ]]; then
        log_warning "  ⚠️  SSH key authentication failed, trying with password..."
        echo "    Error: $SSH_TEST_OUTPUT" | head -3 | sed 's/^/    /'

        # SSH 키 실패 시 비밀번호 사용 (sshpass 필요)
        # YAML에서 SSH 비밀번호 가져오기
        SSH_PASSWORD=$(python3 << EOPY
import yaml
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
    print(config.get('cluster_info', {}).get('ssh_password', ''))
except:
    print('')
EOPY
)

        if [[ -n "$SSH_PASSWORD" ]] && command -v sshpass &>/dev/null; then
            if sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$NODE_USER@$NODE_IP" "echo ok" &>/dev/null; then
                log_success "  ✓ SSH connection OK (using password)"
                SSH_CMD="sshpass -p '$SSH_PASSWORD' ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no"
            else
                log_error "  ✗ SSH connection failed with both key and password!"
                echo "    Please check:"
                echo "      - Node is powered on and reachable: ping $NODE_IP"
                echo "      - SSH service running: ssh $NODE_USER@$NODE_IP"
                echo "      - Correct password in YAML: cluster_info.ssh_password"
                continue
            fi
        else
            log_error "  ✗ SSH key authentication failed and sshpass not available"
            echo "    Install sshpass: sudo apt install sshpass"
            echo "    Or add SSH key to node: ssh-copy-id $NODE_USER@$NODE_IP"
            continue
        fi
    else
        log_success "  ✓ SSH connection OK (using SSH key)"
        SSH_CMD="ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no"
    fi
    echo ""

    # 원격 진단 실행
    echo "  → Running remote diagnostics..."
    $SSH_CMD "$NODE_USER@$NODE_IP" bash << 'EOFDIAG'

echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 1. slurmd service status                            │"
echo "  └─────────────────────────────────────────────────────┘"

if systemctl is-active --quiet slurmd; then
    echo "    ✓ slurmd is running"
else
    echo "    ✗ slurmd is NOT running"
    echo ""
    systemctl status slurmd --no-pager -l 2>&1 | head -15 | sed 's/^/    /'
fi

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 2. slurmd binary check                              │"
echo "  └─────────────────────────────────────────────────────┘"

if [[ -x /usr/local/slurm/sbin/slurmd ]]; then
    echo "    ✓ /usr/local/slurm/sbin/slurmd exists"
    SLURMD_VER=$(/usr/local/slurm/sbin/slurmd -V 2>/dev/null || echo "unknown")
    echo "    Version: $SLURMD_VER"
else
    echo "    ✗ /usr/local/slurm/sbin/slurmd NOT found!"
fi

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 3. slurm.conf check                                 │"
echo "  └─────────────────────────────────────────────────────┘"

if [[ -f /etc/slurm/slurm.conf ]]; then
    echo "    ✓ /etc/slurm/slurm.conf exists"
    CLUSTER_NAME=$(grep -E "^ClusterName=" /etc/slurm/slurm.conf 2>/dev/null | cut -d'=' -f2 || echo "not found")
    SLURMCTLD_HOST=$(grep -E "^SlurmctldHost=" /etc/slurm/slurm.conf 2>/dev/null | cut -d'=' -f2 || echo "not found")
    echo "    ClusterName: $CLUSTER_NAME"
    echo "    SlurmctldHost: $SLURMCTLD_HOST"
else
    echo "    ✗ /etc/slurm/slurm.conf NOT found!"
fi

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 4. munge service status                             │"
echo "  └─────────────────────────────────────────────────────┘"

if systemctl is-active --quiet munge; then
    echo "    ✓ munge is running"
else
    echo "    ✗ munge is NOT running!"
    systemctl status munge --no-pager 2>&1 | head -8 | sed 's/^/    /'
fi

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 5. munge.key check                                  │"
echo "  └─────────────────────────────────────────────────────┘"

if [[ -f /etc/munge/munge.key ]]; then
    echo "    ✓ /etc/munge/munge.key exists"
    ls -la /etc/munge/munge.key | sed 's/^/    /'
else
    echo "    ✗ /etc/munge/munge.key NOT found!"
fi

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 6. munge authentication test                        │"
echo "  └─────────────────────────────────────────────────────┘"

if munge -n 2>/dev/null | unmunge 2>&1 | grep -q "SUCCESS"; then
    echo "    ✓ munge authentication successful"
else
    echo "    ✗ munge authentication failed"
    munge -n 2>/dev/null | unmunge 2>&1 | head -5 | sed 's/^/    /'
fi

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 7. Network connectivity to slurmctld                │"
echo "  └─────────────────────────────────────────────────────┘"

# slurm.conf에서 SlurmctldHost 추출
if [[ -f /etc/slurm/slurm.conf ]]; then
    SLURMCTLD=$(grep -E "^SlurmctldHost=" /etc/slurm/slurm.conf 2>/dev/null | head -1 | sed 's/SlurmctldHost=\([^(]*\).*/\1/' | tr -d ' ')
    if [[ -n "$SLURMCTLD" ]]; then
        echo "    Testing connection to: $SLURMCTLD:6817"
        if timeout 2 bash -c "echo > /dev/tcp/$SLURMCTLD/6817" 2>/dev/null; then
            echo "    ✓ Can reach slurmctld at $SLURMCTLD:6817"
        else
            echo "    ✗ Cannot reach slurmctld at $SLURMCTLD:6817"
            echo "      (firewall or slurmctld not running?)"
        fi
    else
        echo "    ⚠️  Could not extract SlurmctldHost from slurm.conf"
    fi
else
    echo "    ⚠️  slurm.conf not found, cannot test slurmctld connection"
fi

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 8. Recent slurmd logs                               │"
echo "  └─────────────────────────────────────────────────────┘"

if journalctl -u slurmd -n 10 --no-pager 2>&1 | grep -q "slurmd"; then
    journalctl -u slurmd -n 10 --no-pager 2>&1 | sed 's/^/    /'
else
    echo "    (no recent slurmd logs)"
fi

EOFDIAG

done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "4. DIAGNOSIS SUMMARY"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Common issues and solutions:"
echo ""
echo "  1. munge.key mismatch:"
echo "     → Redeploy: ./offline_deploy/deploy_to_compute_node.sh $CONFIG_FILE --nodes <node>"
echo ""
echo "  2. slurmd not running:"
echo "     → SSH to node: ssh <node> 'sudo systemctl start slurmd'"
echo ""
echo "  3. Cannot reach slurmctld:"
echo "     → Check firewall, verify slurmctld is running on controller"
echo ""
echo "  4. Time sync issue:"
echo "     → Check NTP: ssh <node> 'timedatectl'"
echo ""
echo "  5. Wrong slurm.conf:"
echo "     → Update on controller and redeploy to nodes"
echo ""
