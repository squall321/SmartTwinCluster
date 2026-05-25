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

# SSH 옵션 — 키 인증 우선, 실패 시 sshpass+password 폴백
SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
SSH_PW_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o LogLevel=ERROR"

ok=0; fail=0; failed_nodes=()

run_remote() {
    # $1=target, $2=local_file, $3=remote_path, $4=cmd
    local target="$1" lfile="$2" rpath="$3" cmd="$4" err="$5"
    # 키 인증 우선
    if scp $SSH_KEY_OPTS "$lfile" "${target}:${rpath}" 2>"$err" \
        && ssh $SSH_KEY_OPTS "$target" "$cmd" 2>>"$err"; then
        return 0
    fi
    # 폴백: sshpass + password
    : > "$err"
    sshpass -p "$SSH_PASSWORD" scp $SSH_PW_OPTS "$lfile" "${target}:${rpath}" 2>"$err" \
        && sshpass -p "$SSH_PASSWORD" ssh $SSH_PW_OPTS "$target" "$cmd" 2>>"$err"
}

while IFS=$'\t' read -r HOST IP USER; do
    [[ -z "$HOST" ]] && continue
    [[ -z "$USER" ]] && USER="koopark"
    TARGET="${USER}@${IP}"

    # 원격 명령: 키 인증이면 sudo NOPASSWD 가정, 폴백이면 -S로 비번 파이프
    REMOTE_CMD=$(cat <<EOF
set -e
SUDO="sudo -n"
\$SUDO true 2>/dev/null || SUDO="echo '$SSH_PASSWORD' | sudo -S -p ''"
eval "\$SUDO sed -i '/^# === BEGIN cluster hosts (auto-managed) ===\$/,/^# === END cluster hosts (auto-managed) ===\$/d' /etc/hosts" 2>/dev/null
eval "\$SUDO bash -c 'cat /tmp/_cluster_hosts_block >> /etc/hosts'"
rm -f /tmp/_cluster_hosts_block
EOF
)

    _err=$(mktemp)
    if run_remote "$TARGET" "$TMPHOSTS" "/tmp/_cluster_hosts_block" "$REMOTE_CMD" "$_err"; then
        echo "  ✓ $HOST ($IP)"
        ok=$((ok+1))
    else
        echo "  ✗ $HOST ($IP) — 실패:"
        sed 's/^/      /' "$_err" | head -5
        failed_nodes+=("$HOST")
        fail=$((fail+1))
    fi
    rm -f "$_err"
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
