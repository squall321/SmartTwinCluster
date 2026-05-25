#!/bin/bash
################################################################################
# /etc/hosts 업데이트 (fix_all.sh 패턴 — 키 인증 + sshpass 폴백)
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

# sshpass 보장
command -v sshpass &>/dev/null || sudo apt install -y sshpass 2>/dev/null || true
python3 -c "import yaml" 2>/dev/null || sudo apt install -y python3-yaml 2>/dev/null || true

# YAML 파싱
SSH_PASSWORD=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
print((c.get('environment') or {}).get('ssh_password',''))
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

echo "📋 노드 수: ${#NODES_TSV[@]}"

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

ok=0; fail=0; failed_nodes=()

for line in "${NODES_TSV[@]}"; do
    IFS=$'\t' read -r HOST IP USER <<< "$line"
    [[ -z "$HOST" ]] && continue
    TARGET="${USER}@${IP}"

    # 키 인증 가능한지 먼저 확인
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$TARGET" "echo ok" >/dev/null 2>&1; then
        # 키 인증 모드 (NOPASSWD sudo 가정)
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TARGET" bash <<ENDSSH >/dev/null 2>&1
sudo sed -i '/^# === BEGIN cluster hosts (auto-managed) ===\$/,/^# === END cluster hosts (auto-managed) ===\$/d' /etc/hosts
sudo bash -c 'cat >> /etc/hosts' <<'HOSTSEOF'
$HOSTS_BLOCK
HOSTSEOF
ENDSSH
    else
        # 폴백: sshpass + password + sudo -S
        sshpass -p "$SSH_PASSWORD" ssh \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o PreferredAuthentications=password -o PubkeyAuthentication=no \
            -o ConnectTimeout=10 "$TARGET" bash <<ENDSSH >/dev/null 2>&1
echo '$SSH_PASSWORD' | sudo -S -p '' sed -i '/^# === BEGIN cluster hosts (auto-managed) ===\$/,/^# === END cluster hosts (auto-managed) ===\$/d' /etc/hosts
echo '$SSH_PASSWORD' | sudo -S -p '' bash -c 'cat >> /etc/hosts' <<'HOSTSEOF'
$HOSTS_BLOCK
HOSTSEOF
ENDSSH
    fi

    if [ $? -eq 0 ]; then
        echo "  ✓ $HOST ($IP)"
        ok=$((ok+1))
    else
        echo "  ✗ $HOST ($IP)"
        failed_nodes+=("$HOST")
        fail=$((fail+1))
    fi
done

echo "================================================================================"
echo "✅ 성공 $ok  ❌ 실패 $fail"
[[ $fail -gt 0 ]] && { echo "실패 노드: ${failed_nodes[*]}"; exit 1; }
exit 0
