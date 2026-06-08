#!/bin/bash

################################################################################
# Move Stale Simulation Folders
#
# 지정경로 바로 아래의 각 폴더(= 시뮬레이션 결과 폴더, 내부는 깊을 수 있음)를
# 검사해서, 그 폴더 하위 전체에서 '지정 시간' 동안 수정된 파일이 하나도 없으면
# (= 그만큼 업데이트가 멈춘 = 끝난 시뮬레이션) 그 폴더를 통째로 타겟경로로 이동한다.
#
# 사용법:
#   ./move_stale_sims.sh <지정경로> <타겟경로> <시간> [--dry-run]
#
#   <시간> 형식:  15H(시간) · 30M(분) · 3D(일) · 1W(주) · 600S(초)   (단위 없으면 시간)
#
# 예:
#   ./move_stale_sims.sh /data/runs /data/runs_done 15H
#   ./move_stale_sims.sh /data/runs /data/runs_done 15H --dry-run
#
# 주의: 지정/타겟이 다른 파일시스템이면 mv 가 복사+삭제라 느릴 수 있음.
################################################################################
set -uo pipefail

DRY=0
POS=()
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -22; exit 0 ;;
        -*) echo "알 수 없는 옵션: $a"; exit 1 ;;
        *) POS+=("$a") ;;
    esac
done

[ "${#POS[@]}" -ge 3 ] || { echo "사용: $0 <지정경로> <타겟경로> <시간(예:15H)> [--dry-run]"; exit 1; }
SRC="${POS[0]}"; DST="${POS[1]}"; AGE="${POS[2]}"

[ -d "$SRC" ] || { echo "지정경로 없음: $SRC"; exit 1; }

# 시간 파싱: 숫자 + 단위(H/M/D/W/S, 없으면 시간)
NUM=$(echo "$AGE" | grep -oE '^[0-9]+' || true)
UNIT=$(echo "$AGE" | grep -oE '[A-Za-z]+$' || true)
[ -n "$NUM" ] || { echo "시간 형식 오류: '$AGE' (예: 15H)"; exit 1; }
case "$(echo "${UNIT:-H}" | tr '[:upper:]' '[:lower:]')" in
    h|hour|hours)     WORD=hours ;;
    m|min|minute|minutes) WORD=minutes ;;
    d|day|days)       WORD=days ;;
    w|week|weeks)     WORD=weeks ;;
    s|sec|second|seconds) WORD=seconds ;;
    *) echo "알 수 없는 시간단위: '$UNIT' (H/M/D/W/S)"; exit 1 ;;
esac

# 기준 시각 파일: 지금부터 NUM WORD 전. 이보다 새로 수정된 파일이 있으면 '활동중'.
REF=$(mktemp)
trap 'rm -f "$REF"' EXIT
touch -d "-${NUM} ${WORD}" "$REF" || { echo "시간 계산 실패"; exit 1; }

mkdir -p "$DST" || { echo "타겟경로 생성 실패: $DST"; exit 1; }
SRC_REAL=$(realpath "$SRC"); DST_REAL=$(realpath "$DST")

echo "지정: $SRC  →  타겟: $DST   (기준: 최근 ${NUM}${UNIT:-H} 내 수정 없으면 이동)"
[ "$DRY" = "1" ] && echo "(dry-run — 실제 이동 안 함)"

moved=0
total=0
shopt -s nullglob
for D in "$SRC"/*/; do
    D="${D%/}"
    [ -d "$D" ] || continue
    # 타겟이 지정 하위에 있을 경우 자기 자신/타겟 폴더는 건너뜀
    [ "$(realpath "$D")" = "$DST_REAL" ] && continue
    total=$((total + 1))

    # 하위 전체에서 기준시각보다 새 파일이 하나라도 있으면 '활동중' → 유지
    recent=$(find "$D" -newer "$REF" -print -quit 2>/dev/null)
    if [ -n "$recent" ]; then
        continue
    fi

    base=$(basename "$D")
    if [ "$DRY" = "1" ]; then
        echo "  [DRY] 이동: $base  →  $DST/"
        moved=$((moved + 1))
    else
        if mv -- "$D" "$DST/"; then
            echo "  이동: $base  →  $DST/"
            moved=$((moved + 1))
        else
            echo "  실패: $D"
        fi
    fi
done

echo "$([ "$DRY" = "1" ] && echo 이동예정 || echo 이동) $moved / 폴더 $total"
