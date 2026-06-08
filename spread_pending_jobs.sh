#!/bin/bash

################################################################################
# Spread Pending Jobs Script
#
# 현재 PENDING 인 Slurm 잡들을, 인자로 지정한 파티션들로 분산한다.
# 파티션 이름을 콤마(,)로 여러 개 지정하면, 펜딩 잡 전부의 Partition 을 그
# 목록으로 변경(scontrol update). Slurm(backfill) 이 그 중 가장 먼저 시작
# 가능한 파티션에서 잡을 띄우므로 비어있는 파티션이 자동 활용된다 → 편중 해소.
#
# 사용법:
#   ./spread_pending_jobs.sh alpha,beta,gamma,share
#   ./spread_pending_jobs.sh alpha,beta,gamma,share --dry-run
#
# 권한: 헤드/컨트롤러에서 Slurm operator/root 로 실행해야 모든 사용자 잡에 적용됨
#       (일반 사용자로 실행하면 본인 잡만 변경 가능).
################################################################################
set -uo pipefail

PARTS=""
DRY=0
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -20; exit 0 ;;
        -*) echo "알 수 없는 옵션: $a"; exit 1 ;;
        *) PARTS="$a" ;;
    esac
done

# 파티션 목록 정리 (공백/중복콤마 제거)
PLIST=$(echo "$PARTS" | tr -d ' ' | tr -s ',' ',' | sed 's/^,//; s/,$//')
[ -n "$PLIST" ] || { echo "사용: $0 <part1,part2,...> [--dry-run]"; exit 1; }

echo "분산 대상 파티션: $PLIST"
[ "$DRY" = "1" ] && echo "(dry-run — 실제 변경 안 함)"

n=0
total=0
while IFS='|' read -r jid cur; do
    [ -n "$jid" ] || continue
    total=$((total + 1))
    if [ "$DRY" = "1" ]; then
        echo "  [DRY] job $jid: $cur -> $PLIST"
        n=$((n + 1))
        continue
    fi
    if err=$(scontrol update jobid="$jid" Partition="$PLIST" 2>&1); then
        echo "  job $jid -> Partition=$PLIST"
        n=$((n + 1))
    else
        echo "  job $jid 실패: ${err:0:160}"
    fi
done < <(squeue -h -t PD -o '%i|%P')

echo "$([ "$DRY" = "1" ] && echo 적용예정 || echo 적용) $n / 펜딩 $total"
