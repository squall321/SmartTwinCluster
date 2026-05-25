#!/bin/bash
# 모든 노드 /etc/hosts에서 잘못 박힌 쓰레기 라인 제거
#   - "비밀번호" 단독 라인
#   - "Password:" / "password" 라인
#   - 빈 라인 연속 정리
# 키 인증 우선, sshpass+password 폴백
set -e

CONFIG_FILE="${CONFIG_FILE:-my_multihead_cluster.yaml}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --config=*) CONFIG_FILE="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

SSH_PASSWORD=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
print((c.get('environment') or {}).get('ssh_password',''))
")

NODES_TSV=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
n=c.get('nodes',{}) or {}
nodes=[]
if n.get('controller'): nodes.append(n['controller'])
nodes+= n.get('controllers',[]) or []
nodes+= n.get('compute_nodes',[]) or []
nodes+= n.get('viz_nodes',[]) or []
for x in nodes:
    print(f\"{x.get('hostname','')}\t{x.get('ip_address',x.get('hostname',''))}\t{x.get('ssh_user','')}\")
")

SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
SSH_PW_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o LogLevel=ERROR"

REMOTE_CMD=$(cat <<EOF
set -e
SUDO="sudo -n"
\$SUDO true 2>/dev/null || SUDO="echo '$SSH_PASSWORD' | sudo -S -p ''"
TS=\$(date +%Y%m%d-%H%M%S)
eval "\$SUDO cp /etc/hosts /etc/hosts.bak.\$TS"
eval "\$SUDO sed -i '/^비밀번호\$/d;/^Password:\$/d;/^[Pp]assword\$/d' /etc/hosts"
# 빈줄 2개 이상 연속이면 1개로 압축
eval "\$SUDO bash -c \"awk 'BEGIN{b=0} /^\\\$/{b++; if(b<=1)print; next} {b=0; print}' /etc/hosts > /tmp/_hosts && cat /tmp/_hosts > /etc/hosts && rm -f /tmp/_hosts\""
echo "  → 라인 수: \$(wc -l < /etc/hosts), 백업: /etc/hosts.bak.\$TS"
EOF
)

ok=0; fail=0
while IFS=$'\t' read -r HOST IP USER; do
    [[ -z "$HOST" ]] && continue
    [[ -z "$USER" ]] && USER="koopark"
    TARGET="${USER}@${IP}"
    echo "→ $HOST ($IP, $USER)"
    _err=$(mktemp)
    if ssh $SSH_KEY_OPTS "$TARGET" "$REMOTE_CMD" 2>"$_err"; then
        ok=$((ok+1))
    elif sshpass -p "$SSH_PASSWORD" ssh $SSH_PW_OPTS "$TARGET" "$REMOTE_CMD" 2>"$_err"; then
        ok=$((ok+1))
    else
        echo "    ✗ 실패:"
        sed 's/^/      /' "$_err" | head -3
        fail=$((fail+1))
    fi
    rm -f "$_err"
done <<< "$NODES_TSV"

echo ""
echo "✅ 성공 $ok  ❌ 실패 $fail"
echo "복구 필요시: 각 노드의 /etc/hosts.bak.<TS> 참조"
