#!/bin/bash
################################################################################
# /etc/hosts 잔재 정리 — deploy_to_compute_node.sh 패턴 (sshpass -e)
################################################################################

CONFIG_FILE="${CONFIG_FILE:-my_multihead_cluster.yaml}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --config=*) CONFIG_FILE="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

SSH_PW=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
print((c.get('cluster_info') or {}).get('ssh_password',''))
")
export SSHPASS="$SSH_PW"

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

echo "📋 노드 수: ${#NODES_TSV[@]}"
ok=0; fail=0
for line in "${NODES_TSV[@]}"; do
    IFS=$'\t' read -r HOST IP USER <<< "$line"
    [[ -z "$HOST" ]] && continue
    TARGET="${USER}@${IP}"
    printf "→ %s (%s) ... " "$HOST" "$IP"

    if ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$TARGET" "echo OK" &>/dev/null; then
        SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
        USE_PW=0
    elif [ -n "$SSH_PW" ] && command -v sshpass &>/dev/null; then
        SSH_CMD="sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=10"
        USE_PW=1
    else
        echo "✗ (인증수단 없음)"; fail=$((fail+1)); continue
    fi

    if [ "$USE_PW" = "1" ]; then
        $SSH_CMD "$TARGET" bash <<ENDSSH >/dev/null 2>&1
TS=\$(date +%Y%m%d-%H%M%S)
echo '$SSH_PW' | sudo -S -p '' cp /etc/hosts /etc/hosts.bak.\$TS
echo '$SSH_PW' | sudo -S -p '' sed -i '/^비밀번호\$/d;/^Password:\$/d;/^[Pp]assword\$/d' /etc/hosts
echo '$SSH_PW' | sudo -S -p '' bash -c "awk 'BEGIN{b=0} /^\\\$/{b++; if(b<=1)print; next} {b=0; print}' /etc/hosts > /tmp/_hosts && cat /tmp/_hosts > /etc/hosts && rm -f /tmp/_hosts"
ENDSSH
    else
        $SSH_CMD "$TARGET" bash <<'ENDSSH' >/dev/null 2>&1
TS=$(date +%Y%m%d-%H%M%S)
sudo cp /etc/hosts /etc/hosts.bak.$TS
sudo sed -i '/^비밀번호$/d;/^Password:$/d;/^[Pp]assword$/d' /etc/hosts
sudo bash -c "awk 'BEGIN{b=0} /^\$/{b++; if(b<=1)print; next} {b=0; print}' /etc/hosts > /tmp/_hosts && cat /tmp/_hosts > /etc/hosts && rm -f /tmp/_hosts"
ENDSSH
    fi

    if [ $? -eq 0 ]; then echo "✓ [$([ $USE_PW = 1 ] && echo pw || echo key)]"; ok=$((ok+1))
    else echo "✗"; fail=$((fail+1)); fi
done
echo "================================================================================"
echo "✅ 성공 $ok  ❌ 실패 $fail"
