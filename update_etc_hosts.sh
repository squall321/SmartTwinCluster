#!/bin/bash
################################################################################
# /etc/hosts 업데이트 — deploy_to_compute_node.sh 패턴 (sshpass -e)
################################################################################

CONFIG_FILE="${CONFIG_FILE:-my_multihead_cluster.yaml}"
_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --config=*) CONFIG_FILE="${1#*=}"; shift ;;
        *) _args+=("$1"); shift ;;
    esac
done
set -- "${_args[@]+"${_args[@]}"}"
[[ ! -f "$CONFIG_FILE" ]] && { echo "❌ YAML 없음: $CONFIG_FILE"; exit 1; }
echo "📄 Config: $CONFIG_FILE"
echo "================================================================================"
echo "🌐 /etc/hosts 자동 업데이트"
echo "================================================================================"

# sshpass / yaml 보장
command -v sshpass &>/dev/null || sudo apt install -y sshpass 2>/dev/null || true
python3 -c "import yaml" 2>/dev/null || sudo apt install -y python3-yaml 2>/dev/null || true

# YAML 파싱 — cluster_info.ssh_password (deploy_to_compute_node.sh와 동일)
SSH_PW=$(python3 -c "
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

echo "📋 노드 수: ${#NODES_TSV[@]}  비번: ${SSH_PW:+설정됨}${SSH_PW:-(없음)}"

# 전체 hosts 블록
MARK_BEGIN="# === BEGIN cluster hosts (auto-managed) ==="
MARK_END="# === END cluster hosts (auto-managed) ==="
HOSTS_BLOCK="$MARK_BEGIN"$'\n'
for line in "${NODES_TSV[@]}"; do
    IFS=$'\t' read -r h ip _ <<< "$line"
    [[ -z "$h" ]] && continue
    HOSTS_BLOCK+="$ip $h"$'\n'
done
HOSTS_BLOCK+="$MARK_END"

# sshpass용 환경변수 (특수문자 안전)
export SSHPASS="$SSH_PW"

ok=0; fail=0; failed_nodes=()
for line in "${NODES_TSV[@]}"; do
    IFS=$'\t' read -r HOST IP USER <<< "$line"
    [[ -z "$HOST" ]] && continue
    TARGET="${USER}@${IP}"

    # 키 인증 가능 여부 — deploy_to_compute_node.sh 와 동일 검사
    if ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        "$TARGET" "echo OK" &>/dev/null; then
        SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
        USE_PW=0
    elif [ -n "$SSH_PW" ] && command -v sshpass &>/dev/null; then
        SSH_CMD="sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=10"
        USE_PW=1
    else
        echo "  ✗ $HOST ($IP) — SSH 인증 수단 없음"
        failed_nodes+=("$HOST"); fail=$((fail+1)); continue
    fi

    if [ "$USE_PW" = "1" ]; then
        $SSH_CMD "$TARGET" bash <<ENDSSH >/dev/null 2>&1
echo '$SSH_PW' | sudo -S -p '' sed -i '/^# === BEGIN cluster hosts (auto-managed) ===\$/,/^# === END cluster hosts (auto-managed) ===\$/d' /etc/hosts
echo '$SSH_PW' | sudo -S -p '' bash -c 'cat >> /etc/hosts' <<'HOSTSEOF'
$HOSTS_BLOCK
HOSTSEOF
ENDSSH
    else
        $SSH_CMD "$TARGET" bash <<ENDSSH >/dev/null 2>&1
sudo sed -i '/^# === BEGIN cluster hosts (auto-managed) ===\$/,/^# === END cluster hosts (auto-managed) ===\$/d' /etc/hosts
sudo bash -c 'cat >> /etc/hosts' <<'HOSTSEOF'
$HOSTS_BLOCK
HOSTSEOF
ENDSSH
    fi

    if [ $? -eq 0 ]; then
        echo "  ✓ $HOST ($IP) [$([ $USE_PW = 1 ] && echo pw || echo key)]"
        ok=$((ok+1))
    else
        echo "  ✗ $HOST ($IP)"
        failed_nodes+=("$HOST"); fail=$((fail+1))
    fi
done

echo "================================================================================"
echo "✅ 성공 $ok  ❌ 실패 $fail"
[[ $fail -gt 0 ]] && { echo "실패: ${failed_nodes[*]}"; exit 1; }
exit 0
