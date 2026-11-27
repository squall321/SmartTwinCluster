#!/bin/bash
# 헤드·표본 노드·NFS 의 SmartTwin Pre/Post 이미지 판을 기대값과 대조해 표로 내는 읽기 전용 점검(아무것도 설치·변경하지 않는다)
#
# 쓰는 법(cae00 에서 — 스크립트를 표준입력으로 흘려 넣는다):
#   ssh stcx 'EXPECT_PRE_SHA=1c973c25 EXPECT_POST_SHA=32997e9b EXPECT_POST_VERSION=226eca7 \
#             EXPECT_REMAPPER_COMMIT=e6407dcd EXPECT_KCR_SHA=35511107 bash -s' < cluster/utils/image_version_check.sh
#   헤드에서 직접:  EXPECT_PRE_SHA=… bash cluster/utils/image_version_check.sh
#
# 기대값(모두 선택 — 비우면 실제값만 보이고 판정은 '-'): 앞부분 8자 이상이면 접두 일치로 본다.
#   EXPECT_PRE_SHA · EXPECT_POST_SHA       — SIF sha256
#   EXPECT_POST_VERSION                    — Post SIF /opt/kood3plot/VERSION 의 Version(KooD3plotReader 커밋)
#   EXPECT_REMAPPER_COMMIT                 — Pre SIF 안 KooRemapper.BUILD_INFO.txt 의 소스 커밋
#   EXPECT_KCR_SHA                         — KooChainRun.bin sha256(NFS·SIF 안 공통)
# 표본 노드:
#   NODES="host1 host2"  — 직접 고른다. 비우면 sinfo 로 파티션마다 하나(idle·mix·alloc 중 첫 노드).
#   SAMPLE_PER_PARTITION=1 · SSH_USER(비우면 현재 사용자) · NODE_SHA=1(0 이면 노드 SIF 는 크기·시각만 — 빠르다)
# 종료 코드: 0 = DIFF·ERR 없음, 1 = 하나라도 있음.
#
# 주의: 표준입력으로 도는 스크립트라, 안의 ssh·apptainer 가 표준입력을 읽으면 스크립트 나머지를 먹는다 — 모두 -n / </dev/null.

PRE_SIF=/opt/apptainers/SmartTwinPreprocessor.sif
POST_SIF=/opt/apptainers/SmartTwinPostprocessor.sif
NFS_KCR=/data/SmartTwinPreprocessor/lib/KooChainRun/KooChainRun.bin
NFS_POST_VERSION=/data/SmartTwinPostprocessor/VERSION
SIF_KCR=/opt/SmartTwinPreprocessor/lib/KooChainRun/KooChainRun.bin
SIF_REMAPPER_INFO=/opt/kooremapper/bin/KooRemapper.BUILD_INFO.txt
SIF_POST_VERSION=/opt/kood3plot/VERSION
SSH_OPTS=(-n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

BAD=0
ROWS=()

judge() {   # judge <실제> <기대> → OK|DIFF|-|ERR
    local actual="$1" expect="$2"
    if [ -z "$actual" ] || [ "$actual" = "?" ]; then echo ERR; return; fi
    if [ -z "$expect" ]; then echo "-"; return; fi
    case "$actual" in "$expect"*) echo OK ;; *) echo DIFF ;; esac
}

row() {     # row <위치> <항목> <실제> <기대>
    local verdict; verdict=$(judge "$3" "$4")
    [ "$verdict" = DIFF ] || [ "$verdict" = ERR ] && BAD=1
    ROWS+=("| $1 | $2 | ${3:-?} | ${4:--} | $verdict |")
}

info_row() { ROWS+=("| $1 | $2 | $3 | - | - |"); }

sha_of() { sha256sum "$1" 2>/dev/null </dev/null | cut -d' ' -f1; }
md5_of() { md5sum "$1" 2>/dev/null </dev/null | cut -d' ' -f1; }
size_mtime() { stat -c '%s B, %y' "$1" 2>/dev/null </dev/null | cut -d. -f1; }
in_sif() { apptainer exec "$1" sh -c "$2" 2>/dev/null </dev/null | grep -v '^INFO'; }

HOST=$(hostname -s)

# ── 헤드 ──
for kind in PRE POST; do
    sif=$PRE_SIF; exp=${EXPECT_PRE_SHA:-}
    [ $kind = POST ] && sif=$POST_SIF && exp=${EXPECT_POST_SHA:-}
    if [ -f "$sif" ]; then
        row "헤드 $HOST" "$(basename $sif) sha256" "$(sha_of $sif)" "$exp"
        info_row "헤드 $HOST" "$(basename $sif) 크기·시각" "$(size_mtime $sif)"
    else
        row "헤드 $HOST" "$(basename $sif)" "?" "$exp"
    fi
done

if command -v apptainer >/dev/null 2>&1; then
    [ -f "$POST_SIF" ] && row "헤드 Post SIF 안" "$SIF_POST_VERSION Version" \
        "$(in_sif $POST_SIF "sed -n 's/^Version: *//p' $SIF_POST_VERSION")" "${EXPECT_POST_VERSION:-}"
    if [ -f "$PRE_SIF" ]; then
        row "헤드 Pre SIF 안" "KooRemapper 소스 커밋" \
            "$(in_sif $PRE_SIF "sed -n 's/^.*소스 커밋[^0-9a-f]*\([0-9a-f]\{7,40\}\).*/\1/p' $SIF_REMAPPER_INFO" | head -1)" \
            "${EXPECT_REMAPPER_COMMIT:-}"
        row "헤드 Pre SIF 안" "KooChainRun.bin sha256" "$(in_sif $PRE_SIF "sha256sum $SIF_KCR" | cut -d' ' -f1)" "${EXPECT_KCR_SHA:-}"
    fi
else
    row "헤드 $HOST" "apptainer" "?" ""
fi

# ── NFS ──
row "NFS" "KooChainRun.bin sha256" "$(sha_of $NFS_KCR)" "${EXPECT_KCR_SHA:-}"
info_row "NFS" "KooChainRun.bin md5" "$(md5_of $NFS_KCR)"
row "NFS" "$NFS_POST_VERSION Version" "$(sed -n 's/^Version: *//p' $NFS_POST_VERSION 2>/dev/null </dev/null)" "${EXPECT_POST_VERSION:-}"

# ── 표본 노드 ──
if [ -z "${NODES:-}" ] && command -v sinfo >/dev/null 2>&1; then
    declare -A seen=()
    while read -r node part; do
        part=${part%\*}
        [ "${seen[$part]:-0}" -ge "${SAMPLE_PER_PARTITION:-1}" ] && continue
        [ "$node" = "$HOST" ] && continue
        seen[$part]=$(( ${seen[$part]:-0} + 1 ))
        NODES="${NODES:-} $node"
    done < <(sinfo -h -N -t idle,mix,alloc -o '%N %P' 2>/dev/null </dev/null | sort -u -k2,2 -k1,1)
fi

for node in ${NODES:-}; do
    target=${SSH_USER:+$SSH_USER@}$node
    for sif in $PRE_SIF $POST_SIF; do
        exp=${EXPECT_PRE_SHA:-}; [ $sif = $POST_SIF ] && exp=${EXPECT_POST_SHA:-}
        if [ "${NODE_SHA:-1}" = 1 ]; then
            actual=$(ssh "${SSH_OPTS[@]}" "$target" "sha256sum $sif 2>/dev/null | cut -d' ' -f1" 2>/dev/null)
            row "노드 $node" "$(basename $sif) sha256" "${actual:-?}" "$exp"
        else
            actual=$(ssh "${SSH_OPTS[@]}" "$target" "stat -c '%s B, %y' $sif 2>/dev/null | cut -d. -f1" 2>/dev/null)
            if [ -n "$actual" ]; then info_row "노드 $node" "$(basename $sif) 크기·시각" "$actual"
            else row "노드 $node" "$(basename $sif) (ssh 불가 또는 파일 없음)" "?" ""; fi
        fi
    done
done
[ -z "${NODES// /}" ] && info_row "노드" "표본" "없음(NODES 를 주거나 sinfo 로 고를 노드가 없다)"

echo "| 위치 | 항목 | 실제 | 기대 | 판정 |"
echo "|---|---|---|---|---|"
printf '%s\n' "${ROWS[@]}"
echo
echo "점검: $(date '+%F %T %Z') · $HOST · $( [ $BAD = 0 ] && echo '이상 없음' || echo 'DIFF 또는 ERR 있음')"
exit $BAD
