#!/bin/bash
################################################################################
# 모든 compute/viz 노드의 /scratch 폴더 일괄 삭제 스크립트
#
# 설명:
#   YAML 설정 파일에서 노드 목록을 읽고, 각 노드의 /scratch 내부를
#   완전히 비웁니다 (디렉토리 자체는 유지). 병렬 실행 지원.
#
# 사용법:
#   ./wipe_scratch_all_nodes.sh [OPTIONS]
#
# 옵션:
#   --config PATH      YAML 설정 파일 경로 (기본: my_multihead_cluster_2.yaml)
#   --node HOSTNAME    특정 노드 하나만 정리
#   --nodes-file FILE  호스트네임 목록 파일 (한 줄 한 호스트, # 주석/빈줄 무시)
#   --parallel N       병렬 개수 (기본: 5)
#   --keep-dir         /scratch 안만 비우고 디렉토리는 유지 (기본 동작)
#   --remove-dir       /scratch 디렉토리까지 삭제 (위험)
#   --yes, -y          확인 프롬프트 건너뛰기
#   --help, -h         도움말
#
# 작성자: Claude Code
# 날짜: 2026-05-27
################################################################################

# set -e/-u/pipefail 전부 제거 — 한 노드 실패가 메인 루프를 죽이지 않도록
# (feedback_set_e_counter_trap.md 참조)

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="${SCRIPT_DIR}/my_multihead_cluster_2.yaml"

CONFIG_FILE=""
TARGET_NODE=""
NODES_FILE=""
PARALLEL=5
AUTO_YES=false
REMOVE_DIR=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --node) TARGET_NODE="$2"; shift 2 ;;
        --nodes-file) NODES_FILE="$2"; shift 2 ;;
        --parallel) PARALLEL="$2"; shift 2 ;;
        --keep-dir) REMOVE_DIR=false; shift ;;
        --remove-dir) REMOVE_DIR=true; shift ;;
        --yes|-y) AUTO_YES=true; shift ;;
        --help|-h)
            grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //;s/^#//' | head -30
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--config PATH] [--node HOSTNAME] [--nodes-file FILE] [--parallel N] [--remove-dir] [--yes]"
            exit 1
            ;;
    esac
done

command -v sshpass &>/dev/null || apt-get install -y sshpass &>/dev/null || true

if [[ -z "$CONFIG_FILE" ]]; then
    if [[ -f "$DEFAULT_CONFIG" ]]; then
        CONFIG_FILE="$DEFAULT_CONFIG"
    elif [[ -f "${SCRIPT_DIR}/my_multihead_cluster.yaml" ]]; then
        CONFIG_FILE="${SCRIPT_DIR}/my_multihead_cluster.yaml"
    else
        log_error "No config file specified and default not found"
        exit 1
    fi
fi
[[ -f "$CONFIG_FILE" ]] || { log_error "Config file not found: $CONFIG_FILE"; exit 1; }

export SSHPASS=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
print((c.get('cluster_info') or {}).get('ssh_password',''))
")
SUDO_PW="$SSHPASS"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║       /scratch 일괄 정리 (모든 compute/viz 노드)          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Config: $CONFIG_FILE"
if [[ "$REMOVE_DIR" == true ]]; then
    log_warning "모드: /scratch 디렉토리 자체 삭제 (rm -rf /scratch)"
else
    log_info "모드: /scratch 내부만 비움 (rm -rf /scratch/*  /scratch/.[!.]*)"
fi
echo ""

log_info "Reading compute/viz nodes from YAML..."
NODES_JSON=$(python3 << EOPY
import sys, json
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed", file=sys.stderr); sys.exit(1)
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
nodes = []
for n in config.get('nodes', {}).get('compute_nodes', []) or []:
    if 'hostname' in n and 'ip_address' in n:
        nodes.append({'hostname': n['hostname'], 'ip': n['ip_address'],
                      'user': n.get('ssh_user', 'koopark'),
                      'type': n.get('node_type', 'compute')})
for n in config.get('nodes', {}).get('viz_nodes', []) or []:
    if 'hostname' in n and 'ip_address' in n:
        nodes.append({'hostname': n['hostname'], 'ip': n['ip_address'],
                      'user': n.get('ssh_user', 'koopark'), 'type': 'viz'})
print(json.dumps(nodes))
EOPY
)
[[ -z "$NODES_JSON" || "$NODES_JSON" == "[]" ]] && { log_error "노드 목록 비어있음"; exit 1; }

TOTAL_NODES=$(echo "$NODES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
log_success "Found $TOTAL_NODES compute/viz nodes"

if [[ -n "$NODES_FILE" ]]; then
    [[ -f "$NODES_FILE" ]] || { log_error "--nodes-file 없음: $NODES_FILE"; exit 1; }
    HOSTNAMES_JSON=$(python3 -c "
import json
hns=[ln.split('#',1)[0].strip() for ln in open('$NODES_FILE')]
print(json.dumps([h for h in hns if h]))
")
    NODES_JSON=$(echo "$NODES_JSON" | python3 -c "
import sys, json
ns = json.load(sys.stdin); hns = set($HOSTNAMES_JSON)
print(json.dumps([n for n in ns if n['hostname'] in hns]))
")
    [[ "$NODES_JSON" == "[]" ]] && { log_error "--nodes-file의 호스트네임이 yaml에 매칭 없음"; exit 1; }
    TOTAL_NODES=$(echo "$NODES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
    log_info "Filtered by --nodes-file: $TOTAL_NODES nodes"
fi

if [[ -n "$TARGET_NODE" ]]; then
    NODES_JSON=$(echo "$NODES_JSON" | python3 -c "
import sys, json
ns = json.load(sys.stdin)
print(json.dumps([n for n in ns if n['hostname'] == '$TARGET_NODE']))
")
    [[ "$NODES_JSON" == "[]" ]] && { log_error "Target node not found: $TARGET_NODE"; exit 1; }
    TOTAL_NODES=1
    log_info "Target node: $TARGET_NODE"
fi
echo ""

# 안전장치: 위험한 동작이므로 명시적 확인
if [[ "$AUTO_YES" == false ]]; then
    echo -e "${RED}⚠ 경고: $TOTAL_NODES 개 노드의 /scratch 내용이 영구 삭제됩니다.${NC}"
    echo -e "${RED}  되돌릴 수 없습니다.${NC}"
    if [[ "$REMOVE_DIR" == true ]]; then
        echo -e "${RED}  /scratch 디렉토리 자체도 제거됩니다 (--remove-dir).${NC}"
    fi
    echo ""
    read -p "정말 진행하려면 'WIPE'를 입력하세요: " CONFIRM
    if [[ "$CONFIRM" != "WIPE" ]]; then
        log_info "취소됨"
        exit 0
    fi
    echo ""
fi

wipe_scratch_on_node() {
    local hostname="$1" ip="$2" user="$3" node_type="$4"
    local ssh_target="${user}@${ip}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}[$hostname]${NC} Wiping /scratch ($node_type)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 키 인증 우선, sshpass 폴백 (deploy_to_compute_node.sh 패턴)
    local SSH_CMD REMOTE_SUDO_PREFIX
    if ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        "$ssh_target" "echo OK" &>/dev/null; then
        SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
        if $SSH_CMD "$ssh_target" "sudo -n true" &>/dev/null; then
            REMOTE_SUDO_PREFIX="sudo -n"
        else
            REMOTE_SUDO_PREFIX="echo '$SUDO_PW' | sudo -S -p ''"
        fi
        echo -e "${GREEN}  ✓ SSH 키 인증 OK${NC}"
    elif [[ -n "$SSHPASS" ]] && command -v sshpass &>/dev/null; then
        SSH_CMD="sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=10"
        REMOTE_SUDO_PREFIX="echo '$SUDO_PW' | sudo -S -p ''"
        echo -e "${YELLOW}  ⚠ 키 인증 실패 → sshpass+password${NC}"
    else
        echo -e "${RED}  ✗ [$hostname] SSH 인증 수단 없음${NC}"
        return 1
    fi

    local REMOVE_DIR_FLAG="$REMOVE_DIR"
    $SSH_CMD "$ssh_target" "SUDO_PW='$SUDO_PW' RUSER='$user' REMOVE_DIR='$REMOVE_DIR_FLAG' bash -s" <<'EOF_REMOTE'
# 안전: /scratch가 마운트포인트인지 표시 (정보용)
if mountpoint -q /scratch 2>/dev/null; then
    echo "  ℹ /scratch 는 마운트포인트 (디렉토리 자체는 삭제 불가)"
    IS_MOUNT=1
else
    IS_MOUNT=0
fi

if [ ! -d /scratch ]; then
    echo "  ⚠ /scratch 없음 — 스킵"
    exit 0
fi

# sudo 준비
SUDO=""
if ! sudo -n true 2>/dev/null; then
    if [ -n "${SUDO_PW:-}" ]; then
        SUDO="echo '$SUDO_PW' | sudo -S -p ''"
    fi
else
    SUDO="sudo -n"
fi

BEFORE=$(du -sh /scratch 2>/dev/null | awk '{print $1}')
echo "  → 정리 전 크기: $BEFORE"

# 내용 비우기 (숨김파일 포함, /scratch 디렉토리는 유지)
eval "$SUDO bash -c 'rm -rf /scratch/..?* /scratch/.[!.]* /scratch/*' 2>/dev/null" || true

if [ "$REMOVE_DIR" = "true" ] && [ "$IS_MOUNT" = "0" ]; then
    eval "$SUDO rmdir /scratch" 2>/dev/null && echo "  ✓ /scratch 디렉토리 제거됨" \
        || echo "  ⚠ /scratch 제거 실패 (남은 항목 있음)"
fi

AFTER=$(du -sh /scratch 2>/dev/null | awk '{print $1}')
echo "  ✓ 정리 후 크기: ${AFTER:-(removed)}"
EOF_REMOTE
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        echo -e "${GREEN}[$hostname] ✓ DONE${NC}"
    else
        echo -e "${RED}[$hostname] ✗ FAILED (rc=$rc)${NC}"
    fi
    return $rc
}

log_info "Starting wipe (parallel: $PARALLEL)..."
declare -a PIDS=()
declare -a NODE_LIST=()
SUCCESS_COUNT=0
FAIL_COUNT=0

while IFS='|' read -r hostname ip user node_type; do
    [[ -z "$hostname" ]] && continue
    while [[ ${#PIDS[@]} -ge $PARALLEL ]]; do
        NEW_PIDS=()
        for pid in "${PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                NEW_PIDS+=("$pid")
            fi
        done
        PIDS=("${NEW_PIDS[@]}")
        (( ${#PIDS[@]} >= PARALLEL )) && sleep 1
    done

    # ) </dev/null & : 백그라운드 ssh가 while-read stdin 먹는거 방지
    # (feedback_bg_subshell_stdin.md 참조)
    ( wipe_scratch_on_node "$hostname" "$ip" "$user" "$node_type" ) </dev/null &
    PIDS+=("$!")
    NODE_LIST+=("$hostname:$!")
done < <(echo "$NODES_JSON" | python3 -c "
import sys, json
for n in json.load(sys.stdin):
    print(f\"{n['hostname']}|{n['ip']}|{n['user']}|{n['type']}\")
")

log_info "Waiting for ${#PIDS[@]} background tasks..."
for entry in "${NODE_LIST[@]}"; do
    hn="${entry%%:*}"
    pid="${entry##*:}"
    if wait "$pid"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT+1))
    else
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      결과 요약                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
log_success "성공: $SUCCESS_COUNT / $TOTAL_NODES"
[[ $FAIL_COUNT -gt 0 ]] && log_error "실패: $FAIL_COUNT / $TOTAL_NODES"
echo ""

exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
