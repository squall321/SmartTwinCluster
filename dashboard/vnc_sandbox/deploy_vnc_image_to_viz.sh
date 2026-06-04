#!/bin/bash
################################################################################
# VNC sif 이미지를 viz/hybrid 노드들의 /opt/apptainers 로 배포
#
# /opt/apptainers 는 노드-로컬이라 빌드한 .sif 를 각 viz 노드로 복사해야 함.
# fix_vnc_node_permissions.sh 의 검증된 멀티노드 패턴 차용:
#   - viz/hybrid 노드를 YAML 에서 enumerate
#   - SSH 키 우선 → sshpass(cluster_info.ssh_password) 폴백 (sshpass -p 금지)
#   - /opt/apptainers 는 root 소유 → /tmp 경유 후 sudo mv
#   - md5 동일하면 스킵(대용량 sif 재전송 방지), 전송 후 md5 검증
#   - 병렬 + 노드별 출력 버퍼링(인터리빙 방지)
#
# 사용법:
#   ./deploy_vnc_image_to_viz.sh [--sif PATH] [--config YAML] [--parallel N]
#                                [--images-dir DIR] [--nodes-file FILE]
#   기본: --sif /opt/apptainers/vnc_desktop_gpu.sif  --images-dir /opt/apptainers
################################################################################
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SIF_PATH="${VNC_IMAGES_DIR:-/opt/apptainers}/vnc_desktop_gpu.sif"
IMAGES_DIR="${VNC_IMAGES_DIR:-/opt/apptainers}"
CONFIG_FILE=""
PARALLEL=4          # 대용량 sif → 기본 병렬 낮게(헤드 업링크 보호). 필요시 올림.
NODES_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --sif) SIF_PATH="$2"; shift 2 ;;
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --parallel) PARALLEL="$2"; shift 2 ;;
        --images-dir) IMAGES_DIR="$2"; shift 2 ;;
        --nodes-file) NODES_FILE="$2"; shift 2 ;;
        --help|-h) grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# \{0,1\}//' | head -25; exit 0 ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -f "$SIF_PATH" ]] || { err "sif 없음: $SIF_PATH (먼저 build_vnc_gpu_sandbox.sh 로 빌드)"; exit 1; }
DEST_PATH="$IMAGES_DIR/$(basename "$SIF_PATH")"

# config 기본값
if [[ -z "$CONFIG_FILE" ]]; then
    for c in "$PROJECT_ROOT/my_multihead_cluster.yaml" "$PROJECT_ROOT/my_multihead_cluster_2.yaml" "$SCRIPT_DIR/my_multihead_cluster.yaml"; do
        [[ -f "$c" ]] && { CONFIG_FILE="$c"; break; }
    done
fi
[[ -f "$CONFIG_FILE" ]] || { err "config 없음: $CONFIG_FILE"; exit 1; }

command -v sshpass &>/dev/null || sudo apt-get install -y sshpass &>/dev/null || true
export SSHPASS=$(python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE'))
print((c.get('cluster_info') or {}).get('ssh_password',''))
" 2>/dev/null)

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

# viz/hybrid 노드 (hostname|ip|user) — fix_vnc 패턴 동일
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

if [[ -n "$NODES_FILE" && -f "$NODES_FILE" ]]; then
    _filter=$(grep -vE '^\s*#|^\s*$' "$NODES_FILE" | tr -d ' ')
    NODE_LIST=$(echo "$NODE_LIST" | while IFS='|' read -r hn ip u; do
        echo "$_filter" | grep -qx "$hn" && echo "$hn|$ip|$u"
    done)
fi
[[ -z "$NODE_LIST" ]] && { warn "viz/hybrid 노드 없음"; exit 0; }
TOTAL=$(echo "$NODE_LIST" | grep -c '|')

LSIZE=$(stat -c%s "$SIF_PATH")
LMD5=$(md5sum "$SIF_PATH" | cut -d' ' -f1)
log "배포: $(basename "$SIF_PATH") ($(numfmt --to=iec "$LSIZE" 2>/dev/null || echo "$LSIZE")B, md5=${LMD5:0:8}) → ${TOTAL}개 노드 $DEST_PATH (parallel=$PARALLEL)"

# 단일 노드 배포
deploy_node() {
    local hn="$1" ip="$2" user="$3"
    local target="${user}@${ip}"
    # 키 우선, sshpass 폴백
    local SSH="ssh -n $SSH_OPTS" SCP="scp -O $SSH_OPTS"
    if ! ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$target" "echo OK" &>/dev/null; then
        if [[ -n "$SSHPASS" ]] && command -v sshpass &>/dev/null; then
            SSH="sshpass -e ssh -n $SSH_OPTS -o PreferredAuthentications=password -o PubkeyAuthentication=no"
            SCP="sshpass -e scp -O $SSH_OPTS -o PreferredAuthentications=password -o PubkeyAuthentication=no"
        else
            printf '  ✗ [%s] SSH 인증 불가\n' "$hn"; return 1
        fi
    fi
    # sudo 방식 (NOPASSWD 우선, 없으면 비번 stdin)
    local _SUDO
    if $SSH "$target" "sudo -n true" &>/dev/null; then _SUDO="sudo -n"; else _SUDO="echo '$SSHPASS' | sudo -S -p ''"; fi

    # 이미 동일(md5) 이면 스킵
    local rmd5
    rmd5=$($SSH "$target" "md5sum '$DEST_PATH' 2>/dev/null | cut -d' ' -f1" 2>/dev/null | tr -d '\r ')
    if [[ "$rmd5" == "$LMD5" ]]; then
        printf '  ✓ [%s] 이미 최신 — 스킵\n' "$hn"; return 0
    fi

    # /tmp 경유 전송 → md5 검증 → sudo mv
    local bn; bn=$(basename "$DEST_PATH")
    local tmpd="/tmp/vnc_sif_deploy_${ip}"
    $SSH "$target" "rm -rf '$tmpd' 2>/dev/null; mkdir -p '$tmpd'" 2>/dev/null
    if ! $SCP "$SIF_PATH" "$target:$tmpd/$bn" &>/dev/null; then
        $SSH "$target" "rm -rf '$tmpd'" 2>/dev/null
        printf '  ✗ [%s] scp 실패\n' "$hn"; return 1
    fi
    local res
    res=$($SSH "$target" "
        rmd5=\$(md5sum '$tmpd/$bn' 2>/dev/null | cut -d' ' -f1)
        if [ \"\$rmd5\" = '$LMD5' ]; then
            $_SUDO mkdir -p '$IMAGES_DIR' 2>/dev/null
            $_SUDO mv '$tmpd/$bn' '$DEST_PATH' 2>/dev/null && $_SUDO chmod 644 '$DEST_PATH' 2>/dev/null && echo OK || echo MOVE_FAIL
        else echo MD5_MISMATCH; fi
        rm -rf '$tmpd' 2>/dev/null
    " 2>/dev/null | tr -d '\r')
    if echo "$res" | grep -q '^OK$'; then
        printf '  ✓ [%s] 배포완료\n' "$hn"
    else
        printf '  ✗ [%s] 실패(%s)\n' "$hn" "$(echo "$res" | tr '\n' ' ')"; return 1
    fi
}

# 병렬 실행 (per-node 출력 버퍼링 → 인터리빙 방지, fix_vnc 패턴)
_OUTDIR=$(mktemp -d /tmp/vncsifdeploy.XXXXXX)
trap 'rm -rf "$_OUTDIR"' EXIT
declare -a PIDS=() OUTS=()
_idx=0
while IFS='|' read -r hn ip user; do
    [[ -z "$hn" ]] && continue
    while [[ $(jobs -rp | wc -l) -ge $PARALLEL ]]; do sleep 0.3; done
    _of="$_OUTDIR/$_idx"
    ( deploy_node "$hn" "$ip" "$user" >"$_of" 2>/dev/null ) </dev/null &
    PIDS+=("$!"); OUTS+=("$_of"); _idx=$((_idx+1))
done < <(echo "$NODE_LIST")

SUCCESS=0; FAIL=0
for i in "${!PIDS[@]}"; do
    wait "${PIDS[$i]}"
    cat "${OUTS[$i]}" 2>/dev/null
    if grep -q '✓' "${OUTS[$i]}" 2>/dev/null; then SUCCESS=$((SUCCESS+1)); else FAIL=$((FAIL+1)); fi
done

echo
ok "배포 완료 — 성공 $SUCCESS / 실패 $FAIL (총 $TOTAL)"
[[ $FAIL -eq 0 ]] || { err "일부 노드 실패 — 위 ✗ 노드 확인 후 재실행"; exit 1; }
echo "→ dashboard/start_production.sh 재기동 후 웹에서 GPU 이미지 사용 가능"
