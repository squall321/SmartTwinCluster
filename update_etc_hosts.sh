#!/bin/bash
################################################################################
# /etc/hosts 업데이트 스크립트 (sshpass 기반 — paramiko 비의존)
# my_multihead_cluster.yaml 기반으로 모든 노드의 /etc/hosts 자동 업데이트
################################################################################

set -e

# --config <yaml> 옵션 처리 (기본: my_multihead_cluster.yaml)
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
[[ ! -f "$CONFIG_FILE" ]] && { echo "❌ YAML 없음: $CONFIG_FILE"; echo "사용: $0 [--config <yaml>]"; exit 1; }
echo "📄 Config: $CONFIG_FILE"

echo "================================================================================"
echo "🌐 /etc/hosts 자동 업데이트 (YAML 기반, sshpass)"
echo "================================================================================"
echo ""

# sshpass 보장
if ! command -v sshpass &>/dev/null; then
    echo "⚠️  sshpass 미설치 → 오프라인 패키지로 자동 설치"
    sudo apt install -y sshpass 2>/dev/null || {
        for d in offline_packages_2404/apt_packages offline_packages/apt_packages; do
            f=$(ls "$d"/sshpass_*.deb 2>/dev/null | head -1)
            [ -n "$f" ] && sudo apt install -y "$f" && break
        done
    }
    command -v sshpass &>/dev/null || { echo "❌ sshpass 설치 실패"; exit 1; }
fi

# pyyaml 보장
python3 -c "import yaml" 2>/dev/null || sudo apt install -y python3-yaml 2>/dev/null || true

# YAML 파싱 — 노드 목록 + 공통 password 추출
read -r SSH_PASSWORD <<<"$(python3 -c "
import yaml,sys
with open('$CONFIG_FILE') as f: c = yaml.safe_load(f)
env = c.get('environment', {}) or {}
print(env.get('ssh_password', ''))
")"

NODES_TSV=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f: c = yaml.safe_load(f)
n = c.get('nodes', {}) or {}
all_nodes = []
if n.get('controller'): all_nodes.append(n['controller'])
all_nodes += n.get('controllers', []) or []
all_nodes += n.get('compute_nodes', []) or []
all_nodes += n.get('viz_nodes', []) or []
for x in all_nodes:
    h = x.get('hostname','')
    ip = x.get('ip_address', h)
    user = x.get('ssh_user','')
    print(f'{h}\t{ip}\t{user}')
")

if [[ -z "$NODES_TSV" ]]; then
    echo "❌ 노드 목록을 파싱할 수 없습니다"
    exit 1
fi

# 전체 hosts 블록 (BEGIN/END 마커로 idempotent)
MARK_BEGIN="# === BEGIN cluster hosts (auto-managed) ==="
MARK_END="# === END cluster hosts (auto-managed) ==="
HOSTS_BLOCK=$(printf '%s\n' "$MARK_BEGIN"; while IFS=$'\t' read -r h ip _; do
    [[ -z "$h" ]] && continue
    printf '%s %s\n' "$ip" "$h"
done <<< "$NODES_TSV"; printf '%s\n' "$MARK_END")

NODE_COUNT=$(wc -l <<< "$NODES_TSV")
echo "📋 노드 수: $NODE_COUNT"
echo ""

# 임시 hosts 블록 파일
TMPHOSTS=$(mktemp)
trap "rm -f $TMPHOSTS" EXIT
printf '%s\n' "$HOSTS_BLOCK" > "$TMPHOSTS"

# SSH 옵션 (호스트키 자동수락 + 인증 강제)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=password,publickey -o PubkeyAcceptedKeyTypes=+ssh-rsa,rsa-sha2-256,rsa-sha2-512,ssh-ed25519,ecdsa-sha2-nistp256 -o LogLevel=ERROR"

ok=0; fail=0; failed_nodes=()

while IFS=$'\t' read -r HOST IP USER; do
    [[ -z "$HOST" ]] && continue
    USER="${USER:-$USER}"
    TARGET="${USER}@${IP}"

    # 원격에서 마커 블록 교체 (sed로 idempotent)
    REMOTE_CMD=$(cat <<EOF
set -e
sudo sed -i '/^# === BEGIN cluster hosts (auto-managed) ===\$/,/^# === END cluster hosts (auto-managed) ===\$/d' /etc/hosts
sudo bash -c 'cat >> /etc/hosts' < /tmp/_cluster_hosts_block
rm -f /tmp/_cluster_hosts_block
EOF
)

    if sshpass -p "$SSH_PASSWORD" scp $SSH_OPTS "$TMPHOSTS" "${TARGET}:/tmp/_cluster_hosts_block" 2>/dev/null \
        && sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS "$TARGET" "$REMOTE_CMD" 2>/dev/null; then
        echo "  ✓ $HOST ($IP)"
        ok=$((ok+1))
    else
        echo "  ✗ $HOST ($IP) — 연결/업데이트 실패"
        failed_nodes+=("$HOST")
        fail=$((fail+1))
    fi
done <<< "$NODES_TSV"

echo ""
echo "================================================================================"
echo "✅ 성공: $ok  ❌ 실패: $fail"
[[ $fail -gt 0 ]] && {
    echo "실패 노드:"
    printf '  - %s\n' "${failed_nodes[@]}"
    exit 1
}
echo "================================================================================"
