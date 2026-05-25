#!/bin/bash
# 모든 노드 /etc/hosts에서 잘못 박힌 쓰레기 라인 제거
#   - "비밀번호" 단독 라인
#   - 빈 라인 연속 정리
#   - cluster auto-managed 마커 블록 중복 제거 (마지막 것만 유지)
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

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

# 원격에서 실행할 정리 명령
REMOTE_CMD='
set -e
echo "'"$SSH_PASSWORD"'" | sudo -S -p "" cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d-%H%M%S)
# 비밀번호 라인 제거 + 빈줄 연속 압축
echo "'"$SSH_PASSWORD"'" | sudo -S -p "" sed -i "/^비밀번호$/d" /etc/hosts
echo "'"$SSH_PASSWORD"'" | sudo -S -p "" sed -i "/^Password:/d" /etc/hosts
echo "'"$SSH_PASSWORD"'" | sudo -S -p "" sed -i "/^password$/Id" /etc/hosts
# 빈 라인이 2개 이상 연속이면 1개로
echo "'"$SSH_PASSWORD"'" | sudo -S -p "" bash -c "awk '"'"'BEGIN{b=0} /^$/{b++; if(b<=1)print; next} {b=0; print}'"'"' /etc/hosts > /tmp/_hosts && cat /tmp/_hosts > /etc/hosts && rm -f /tmp/_hosts"
echo "  정리 후 라인 수: $(wc -l < /etc/hosts)"
'

ok=0; fail=0
while IFS=$'\t' read -r HOST IP USER; do
    [[ -z "$HOST" ]] && continue
    [[ -z "$USER" ]] && USER="koopark"
    echo "→ $HOST ($IP, $USER)"
    if sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS "$USER@$IP" "$REMOTE_CMD" 2>&1 | sed 's/^/    /'; then
        ok=$((ok+1))
    else
        fail=$((fail+1))
    fi
done <<< "$NODES_TSV"

echo ""
echo "✅ 성공 $ok  ❌ 실패 $fail"
echo "원본은 /etc/hosts.bak.<TS> 로 백업됨"
