#!/bin/bash
################################################################################
# VNC 작업 디렉토리 권한 일괄 수정 (각 viz/hybrid 노드)
#
# 설명:
#   VNC 잡은 system_user(stcx 등)로 노드에서 실행됨. 노드 로컬의
#   /scratch/vnc_sandboxes, /scratch/vnc_sessions, /scratch/vnc_logs 가
#   root 소유면 apptainer build --sandbox / 세션쓰기 실패 → 잡 exit 1.
#   각 viz/hybrid 노드에 SSH 접속해서 1777(sticky) 적용한다.
#   공유스토리지 /shared/logs 는 헤드(이 스크립트 실행 노드)에서 직접 처리.
#
# 사용법:
#   ./fix_vnc_node_permissions.sh [--config YAML] [--parallel N] [--nodes-file FILE]
#
# start_production.sh [4.5] 에서 자동 호출됨 (단독 실행도 가능).
################################################################################

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
PARALLEL=8
NODES_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --parallel) PARALLEL="$2"; shift 2 ;;
        --nodes-file) NODES_FILE="$2"; shift 2 ;;
        --help|-h)
            grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //;s/^#//' | head -20
            exit 0 ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

# 설정 파일 기본값
if [[ -z "$CONFIG_FILE" ]]; then
    for c in "$SCRIPT_DIR/my_multihead_cluster.yaml" "$SCRIPT_DIR/my_multihead_cluster_2.yaml"; do
        [[ -f "$c" ]] && { CONFIG_FILE="$c"; break; }
    done
fi
[[ -f "$CONFIG_FILE" ]] || { err "config 없음: $CONFIG_FILE"; exit 1; }

# 적용할 디렉토리 + 권한
VNC_DIRS="/scratch/vnc_sandboxes /scratch/vnc_sessions /scratch/vnc_logs /shared/logs"

# SSH 비번 (cluster_info.ssh_password) → SSHPASS env (deploy 패턴)
command -v sshpass &>/dev/null || sudo apt-get install -y sshpass &>/dev/null || true
export SSHPASS=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
print((c.get('cluster_info') or {}).get('ssh_password',''))
" 2>/dev/null)

SSH_OPTS="-n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

# 1) 헤드에서 공유스토리지 /shared/logs 먼저 (모든 노드 공통)
log "헤드: 공유 디렉토리 권한 적용..."
for d in /shared/logs; do
    sudo mkdir -p "$d" 2>/dev/null || true
    sudo chmod 1777 "$d" 2>/dev/null && ok "  $d (1777)" || warn "  $d 실패"
done

# 2) viz/hybrid 노드 목록 (hostname|ip|user)
NODE_LIST=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
n=c.get('nodes',{}) or {}
seen=set()
def emit(x):
    hn=x.get('hostname'); ip=x.get('ip_address'); u=x.get('ssh_user','koopark')
    if hn and ip and ip not in seen:
        seen.add(ip); print(f'{hn}|{ip}|{u}')
for x in (n.get('viz_nodes') or []): emit(x)
for x in (n.get('compute_nodes') or []):
    if x.get('node_type') in ('viz','hybrid'): emit(x)
")

# --nodes-file 필터
if [[ -n "$NODES_FILE" && -f "$NODES_FILE" ]]; then
    _filter=$(grep -vE '^\s*#|^\s*$' "$NODES_FILE" | tr -d ' ')
    NODE_LIST=$(echo "$NODE_LIST" | while IFS='|' read -r hn ip u; do
        echo "$_filter" | grep -qx "$hn" && echo "$hn|$ip|$u"
    done)
fi

[[ -z "$NODE_LIST" ]] && { warn "viz/hybrid 노드 없음"; exit 0; }
TOTAL=$(echo "$NODE_LIST" | grep -c '|')
log "viz/hybrid 노드 ${TOTAL}개에 VNC 디렉토리 권한 적용 (parallel=$PARALLEL)..."

# 단일 노드 처리 함수
fix_node() {
    local hn="$1" ip="$2" user="$3"
    local target="${user}@${ip}"
    # 키 우선, sshpass 폴백 (deploy_to_compute_node 패턴)
    local SSH="ssh $SSH_OPTS"
    if ! ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$target" "echo OK" &>/dev/null; then
        if [[ -n "$SSHPASS" ]] && command -v sshpass &>/dev/null; then
            SSH="sshpass -e ssh $SSH_OPTS -o PreferredAuthentications=password -o PubkeyAuthentication=no"
        else
            echo "  ✗ [$hn] SSH 인증 불가"; return 1
        fi
    fi
    # 노드 로컬 /scratch/vnc_* 1777 (sudo -n, 없으면 sshpass 비번으로 sudo -S)
    if $SSH "$target" "sudo -n true" &>/dev/null; then
        _SUDO="sudo -n"
    else
        _SUDO="echo '$SSHPASS' | sudo -S -p ''"
    fi
    $SSH "$target" "
        for d in $VNC_DIRS; do
            $_SUDO mkdir -p \$d 2>/dev/null || true
            $_SUDO chmod 1777 \$d 2>/dev/null || true
        done
        echo '  권한:' \$(for d in /scratch/vnc_sandboxes /scratch/vnc_sessions; do stat -c '%a' \$d 2>/dev/null; done | tr '\n' ' ')
    " 2>/dev/null && echo "  ✓ [$hn]" || echo "  ⚠ [$hn] 일부 실패"
}

# 병렬 실행 () </dev/null & (stdin 보호 — feedback_bg_subshell_stdin)
declare -a PIDS=()
SUCCESS=0; FAIL=0
while IFS='|' read -r hn ip user; do
    [[ -z "$hn" ]] && continue
    while [[ ${#PIDS[@]} -ge $PARALLEL ]]; do
        NEW=(); for p in "${PIDS[@]}"; do kill -0 "$p" 2>/dev/null && NEW+=("$p"); done
        PIDS=("${NEW[@]}"); (( ${#PIDS[@]} >= PARALLEL )) && sleep 0.5
    done
    ( fix_node "$hn" "$ip" "$user" ) </dev/null &
    PIDS+=("$!")
done < <(echo "$NODE_LIST")

for p in "${PIDS[@]}"; do wait "$p" && SUCCESS=$((SUCCESS+1)) || FAIL=$((FAIL+1)); done

echo ""
ok "VNC 디렉토리 권한 완료 — 성공 추정 $SUCCESS / 실패 $FAIL (총 $TOTAL)"
