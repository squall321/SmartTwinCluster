#!/usr/bin/env bash
# Google Drive → 로컬 Apptainer 이미지 다운로드
#
# 사용:
#   ./pull-apptainers.sh                              # 전체 카테고리
#   ./pull-apptainers.sh --category compute           # 특정만
#   ./pull-apptainers.sh --target /opt/apptainers     # 타깃 디렉토리
#   ./pull-apptainers.sh --list                       # Drive 목록
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SCRIPT_DIR/.drive-sync.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || {
    echo -e "${RED}❌ $ENV_FILE 없음${NC}"; exit 1
}

REMOTE_BASE="${STC_DRIVE_REMOTE%/*}/apptainer-images"

CATEGORY=""
TARGET=""
LIST_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --category|-c) CATEGORY="$2"; shift 2 ;;
        --category=*) CATEGORY="${1#*=}"; shift ;;
        --target|-t) TARGET="$2"; shift 2 ;;
        --target=*) TARGET="${1#*=}"; shift ;;
        --list|-l) LIST_ONLY=1; shift ;;
        -h|--help) sed -n '/^# /,/^set/p' "$0" | grep '^#' | sed 's/^# *//'; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

if [[ "$LIST_ONLY" == "1" ]]; then
    echo -e "${BLUE}═══ Drive Apptainer 카테고리 ═══${NC}"
    rclone lsf --dirs-only "$REMOTE_BASE/" 2>/dev/null
    echo ""
    echo -e "${BLUE}═══ 전체 .sif 파일 ═══${NC}"
    rclone lsf -R "$REMOTE_BASE/" --include "*.sif" --format "ps" 2>/dev/null | head -30
    exit 0
fi

# 기본 카테고리 매핑 (Drive 폴더명 → 로컬 위치)
declare -A DEST
DEST["compute-node-images"]="$REPO_ROOT/apptainer/compute-node-images"
DEST["viz-node-images"]="$REPO_ROOT/apptainer/viz-node-images"
DEST["data-apptainers"]="/data/apptainers"

# 카테고리 필터
if [[ -n "$CATEGORY" ]]; then
    declare -A FILTERED
    for k in "${!DEST[@]}"; do
        [[ "$k" == *"$CATEGORY"* ]] && FILTERED["$k"]="${DEST[$k]}"
    done
    [[ ${#FILTERED[@]} -eq 0 ]] && { echo -e "${RED}❌ 카테고리 매칭 없음: $CATEGORY${NC}"; exit 1; }
    unset DEST; declare -A DEST
    for k in "${!FILTERED[@]}"; do DEST["$k"]="${FILTERED[$k]}"; done
fi

# 타깃 오버라이드
[[ -n "$TARGET" ]] && { for k in "${!DEST[@]}"; do DEST["$k"]="$TARGET/$k"; done; }

echo -e "${BLUE}═══ Pull Apptainer Images ═══${NC}"
echo "  remote: $REMOTE_BASE/"
echo ""

for cat in "${!DEST[@]}"; do
    src="$REMOTE_BASE/$cat"
    dst="${DEST[$cat]}"
    echo -e "${BLUE}→ $cat → $dst${NC}"
    mkdir -p "$dst"
    rclone copy --progress --update --transfers 4 \
        --include "*.sif" --include "*.sif.sha256" \
        "$src/" "$dst/"
done

echo ""
echo -e "${GREEN}✅ 완료${NC}"
for cat in "${!DEST[@]}"; do
    dst="${DEST[$cat]}"
    count=$(find "$dst" -maxdepth 1 -name "*.sif" 2>/dev/null | wc -l)
    size=$(du -sh "$dst" 2>/dev/null | awk '{print $1}')
    echo "  $cat → $dst ($count .sif, $size)"
done
