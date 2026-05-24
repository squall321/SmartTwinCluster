#!/usr/bin/env bash
# offline_packages_2404 (또는 _22) → Google Drive 업로드
#
# 동작:
#   1) apt_packages/python_wheels/slurm/munge/gpu 를 tar.gz 1GB 분할
#   2) sha256 + manifest.json 생성
#   3) rclone copy 로 Drive 업로드 (세트 폴더 안에)
#   4) 보존정책: STC_DRIVE_RETAIN 개만 유지
#
# 사용:
#   ./push-to-drive.sh                       # 24.04 패키지 업로드
#   ./push-to-drive.sh --os 22.04            # 22.04 패키지
#   ./push-to-drive.sh --note "before-libpmix-update"
#   ./push-to-drive.sh --incremental         # 최근 24시간 변경분만 (가벼움)
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.drive-sync.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || {
    echo -e "${RED}❌ $ENV_FILE 없음 — 먼저 ./setup-drive-sync.sh${NC}"; exit 1
}
[[ -z "${STC_DRIVE_REMOTE:-}" ]] && { echo -e "${RED}❌ STC_DRIVE_REMOTE 미설정${NC}"; exit 1; }

# 옵션
OS_VER="24.04"
NOTE=""
INCR=0
SOURCE_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --os) OS_VER="$2"; shift 2 ;;
        --os=*) OS_VER="${1#*=}"; shift ;;
        --note) NOTE="$2"; shift 2 ;;
        --note=*) NOTE="${1#*=}"; shift ;;
        --incremental|-i) INCR=1; shift ;;
        --source) SOURCE_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '/^# /,/^set/p' "$0" | grep '^#' | sed 's/^# *//'; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# 소스 디렉토리 자동 판별
if [[ -z "$SOURCE_DIR" ]]; then
    case "$OS_VER" in
        24.04) SOURCE_DIR="$(dirname "$SCRIPT_DIR")/offline_packages_2404" ;;
        22.04) SOURCE_DIR="$(dirname "$SCRIPT_DIR")/offline_packages" ;;
        *) echo "지원 OS: 22.04 / 24.04"; exit 1 ;;
    esac
fi
[[ ! -d "$SOURCE_DIR" ]] && { echo -e "${RED}❌ 소스 없음: $SOURCE_DIR${NC}"; exit 1; }

TS=$(date -u +%Y%m%d-%H%M%SZ)
SET_NAME="stc-offline-${OS_VER}-${TS}"
[[ "$INCR" == "1" ]] && SET_NAME="${SET_NAME}-incr"
DIST_DIR="$SOURCE_DIR/dist/$SET_NAME"
mkdir -p "$DIST_DIR"

echo -e "${BLUE}═══ Push to Drive ═══${NC}"
echo "  source: $SOURCE_DIR"
echo "  set:    $SET_NAME"
echo "  remote: $STC_DRIVE_REMOTE/$SET_NAME/"
echo "  note:   ${NOTE:-(없음)}"
echo ""

# 1) tar 분할 (기존 pack 스크립트 재사용)
PARTS_PREFIX="$DIST_DIR/parts.tar.gz.part-"
if [[ "$INCR" == "1" ]]; then
    echo -e "${BLUE}→ 최근 24시간 변경 파일만 tar${NC}"
    INCLUDE=()
    for d in apt_packages python_wheels slurm munge gpu nodejs opencascade; do
        [ -d "$SOURCE_DIR/$d" ] && INCLUDE+=("$d")
    done
    FILELIST="$DIST_DIR/filelist.txt"
    ( cd "$SOURCE_DIR" && find "${INCLUDE[@]}" -type f -mtime -1 ) > "$FILELIST"
    COUNT=$(wc -l < "$FILELIST")
    [[ "$COUNT" -eq 0 ]] && { echo -e "${YELLOW}변경 없음. 종료${NC}"; rm -rf "$DIST_DIR"; exit 0; }
    echo "  변경 파일: $COUNT 개"
    tar -C "$SOURCE_DIR" -cf - -T "$FILELIST" | gzip -1 | \
        split --bytes=1G --numeric-suffixes=0 --suffix-length=3 - "$PARTS_PREFIX"
else
    echo -e "${BLUE}→ 전체 tar (1GB 분할)${NC}"
    INCLUDE=()
    for d in apt_packages python_wheels slurm munge gpu nodejs opencascade; do
        [ -d "$SOURCE_DIR/$d" ] && INCLUDE+=("$d")
    done
    tar -C "$SOURCE_DIR" -cf - "${INCLUDE[@]}" | gzip -1 | \
        split --bytes=1G --numeric-suffixes=0 --suffix-length=3 - "$PARTS_PREFIX"
fi

# 2) sha256
echo -e "${BLUE}→ sha256 계산${NC}"
( cd "$DIST_DIR" && sha256sum parts.tar.gz.part-* > sha256.txt )
TOTAL_SIZE=$(du -cb "$DIST_DIR"/parts.tar.gz.part-* | tail -1 | awk '{print $1}')

# 3) manifest
cat > "$DIST_DIR/manifest.json" <<EOF
{
  "set_name": "$SET_NAME",
  "os_version": "$OS_VER",
  "timestamp_utc": "$TS",
  "incremental": ${INCR},
  "note": "$NOTE",
  "host": "$(hostname)",
  "user": "${SUDO_USER:-$USER}",
  "total_bytes": $TOTAL_SIZE,
  "parts_count": $(ls "$DIST_DIR"/parts.tar.gz.part-* | wc -l),
  "rclone_remote": "$STC_DRIVE_REMOTE/$SET_NAME"
}
EOF

# 4) 복원 안내 md
cat > "$DIST_DIR/RESTORE.md" <<EOF
# SmartTwin Cluster Offline Packages — Restore

| 항목 | 값 |
|------|----|
| Set | \`$SET_NAME\` |
| OS | $OS_VER |
| 시각(UTC) | $TS |
| Incremental | $([ "$INCR" = "1" ] && echo "Yes" || echo "No (전체)") |
| 총 크기 | $(numfmt --to=iec "$TOTAL_SIZE") |
| 노트 | ${NOTE:-(없음)} |

## 타깃 머신에서 복원

\`\`\`
git clone <repo>
cd <repo>
./offline_packages_2404/setup-drive-sync.sh   # 최초 1회 rclone 설정
./offline_packages_2404/pull-from-drive.sh    # 최신 자동
# 또는 특정 세트
./offline_packages_2404/pull-from-drive.sh --set $SET_NAME
\`\`\`
EOF

# 5) 업로드
echo -e "${BLUE}→ rclone 업로드: $STC_DRIVE_REMOTE/$SET_NAME/${NC}"
rclone copy --progress "$DIST_DIR/" "$STC_DRIVE_REMOTE/$SET_NAME/"

# 6) 보존정책
RETAIN="${STC_DRIVE_RETAIN:-3}"
if [[ "$RETAIN" -gt 0 ]]; then
    echo -e "${BLUE}→ 보존정책: 최신 $RETAIN 세트만 유지${NC}"
    mapfile -t _sets < <(rclone lsf --dirs-only "$STC_DRIVE_REMOTE/" 2>/dev/null | \
        grep -E "^stc-offline-${OS_VER}-" | sed 's|/$||' | sort)
    if (( ${#_sets[@]} > RETAIN )); then
        _del=$(( ${#_sets[@]} - RETAIN ))
        for i in $(seq 0 $((_del - 1))); do
            echo "  - delete: ${_sets[$i]}"
            rclone purge "$STC_DRIVE_REMOTE/${_sets[$i]}" 2>/dev/null || true
        done
    fi
fi

echo ""
echo -e "${GREEN}✅ 업로드 완료${NC}"
echo "  Set: $SET_NAME"
echo "  Size: $(numfmt --to=iec "$TOTAL_SIZE")"
echo "  Drive: $STC_DRIVE_REMOTE/$SET_NAME/"
echo ""
echo "로컬 dist 정리: rm -rf '$DIST_DIR'"
