#!/bin/bash
################################################################################
# 모든 노드의 ssh_user 계정에 NOPASSWD sudo 영구 설정 (yaml 기반)
#   - 각 노드는 자기 계정만 비번 면제 (cross-account 권한 부여 아님)
#   - 한 번 실행해두면 이후 install/deploy/update 스크립트가 비번 처리 불필요
################################################################################

CONFIG_FILE="${CONFIG_FILE:-my_multihead_cluster.yaml}"
PARALLEL=20
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --config=*) CONFIG_FILE="${1#*=}"; shift ;;
        --parallel|-j) PARALLEL="$2"; shift 2 ;;
        *) shift ;;
    esac
done
[[ ! -f "$CONFIG_FILE" ]] && { echo "❌ YAML 없음: $CONFIG_FILE"; exit 1; }

command -v sshpass &>/dev/null || sudo apt install -y sshpass 2>/dev/null || true

export SSHPASS=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
print((c.get('cluster_info') or {}).get('ssh_password',''))
")

mapfile -t NODES_TSV < <(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
n=c.get('nodes',{}) or {}
nodes=[]
if n.get('controller'): nodes.append(n['controller'])
nodes+= n.get('controllers',[]) or []
nodes+= n.get('compute_nodes',[]) or []
nodes+= n.get('viz_nodes',[]) or []
for x in nodes:
    print(f\"{x.get('hostname','')}\t{x.get('ip_address',x.get('hostname',''))}\t{x.get('ssh_user','') or 'koopark'}\")
")

echo "📋 노드 수: ${#NODES_TSV[@]}  병렬: $PARALLEL"

RESULTS_DIR=$(mktemp -d)
trap "rm -rf $RESULTS_DIR" EXIT

setup_one() {
    local HOST="$1" IP="$2" USER="$3"
    local TARGET="${USER}@${IP}"
    local REMOTE_SCRIPT="
set -e
SUDO_FILE=/etc/sudoers.d/_nopasswd_$USER
LINE='$USER ALL=(ALL) NOPASSWD:ALL'
if sudo -n true 2>/dev/null && [ -f \"\$SUDO_FILE\" ] && grep -qF \"\$LINE\" \"\$SUDO_FILE\"; then
    echo SKIP
    exit 0
fi
echo '$SSHPASS' | sudo -S -p '' bash -c \"echo '\$LINE' > \$SUDO_FILE && chmod 440 \$SUDO_FILE && visudo -cf \$SUDO_FILE\"
sudo -n true 2>/dev/null && echo OK || { echo VERIFY_FAIL; exit 1; }
"
    local OUT
    if ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$TARGET" "echo ok" &>/dev/null; then
        OUT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TARGET" "$REMOTE_SCRIPT" 2>&1)
    elif [ -n "$SSHPASS" ]; then
        OUT=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o PreferredAuthentications=password -o PubkeyAuthentication=no \
            -o ConnectTimeout=10 "$TARGET" "$REMOTE_SCRIPT" 2>&1)
    else
        echo "FAIL no auth" > "$RESULTS_DIR/$HOST"; return
    fi
    local STATUS=$(echo "$OUT" | tail -1)
    case "$STATUS" in
        OK)   echo "OK" > "$RESULTS_DIR/$HOST" ;;
        SKIP) echo "SKIP" > "$RESULTS_DIR/$HOST" ;;
        *)    echo "FAIL $STATUS" > "$RESULTS_DIR/$HOST" ;;
    esac
}

_pids=()
for line in "${NODES_TSV[@]}"; do
    IFS=$'\t' read -r HOST IP USER <<< "$line"
    [[ -z "$HOST" ]] && continue
    while (( ${#_pids[@]} >= PARALLEL )); do
        new=(); for p in "${_pids[@]}"; do kill -0 "$p" 2>/dev/null && new+=("$p") || wait "$p" 2>/dev/null || true; done
        _pids=("${new[@]}"); (( ${#_pids[@]} >= PARALLEL )) && sleep 0.5
    done
    setup_one "$HOST" "$IP" "$USER" &
    _pids+=($!)
done
for p in "${_pids[@]}"; do wait "$p" 2>/dev/null || true; done

ok=0; skip=0; fail=0; failed=()
for f in "$RESULTS_DIR"/*; do
    [[ -e "$f" ]] || continue
    h=$(basename "$f"); s=$(cat "$f")
    case "$s" in
        OK)   echo "  ✓ $h (설정 완료)"; ok=$((ok+1)) ;;
        SKIP) echo "  = $h (이미 설정됨)"; skip=$((skip+1)) ;;
        *)    echo "  ✗ $h ($s)"; failed+=("$h"); fail=$((fail+1)) ;;
    esac
done
echo "================================================================================"
echo "✅ 신규 $ok / 기존 $skip / ❌ 실패 $fail"
[[ $fail -gt 0 ]] && { echo "실패: ${failed[*]}"; exit 1; }
exit 0
