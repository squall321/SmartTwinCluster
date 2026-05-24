#!/usr/bin/env bash
# Apptainer (.sif) 이미지 → Google Drive 업로드
# .sif 는 SquashFS 라 이미 압축됨 → 파일 그대로 rclone copy (tar 안 함)
#
# 기본 업로드 대상:
#   apptainer/compute-node-images   (~17 GB)
#   apptainer/viz-node-images       (~2.6 GB)
#   /data/apptainers                (~41 GB)
#
# 사용:
#   ./push-apptainers.sh                          # 기본 3개 폴더
#   ./push-apptainers.sh --dirs path1,path2       # 커스텀
#   ./push-apptainers.sh --note "+lsdyna-r16"
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SCRIPT_DIR/.drive-sync.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || {
    echo -e "${RED}❌ $ENV_FILE 없음 — 먼저 ./setup-drive-sync.sh${NC}"; exit 1
}

NOTE=""
CUSTOM_DIRS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --note) NOTE="$2"; shift 2 ;;
        --note=*) NOTE="${1#*=}"; shift ;;
        --dirs) CUSTOM_DIRS="$2"; shift 2 ;;
        --dirs=*) CUSTOM_DIRS="${1#*=}"; shift ;;
        -h|--help) sed -n '/^# /,/^set/p' "$0" | grep '^#' | sed 's/^# *//'; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# 기본 디렉토리 (절대경로 + Drive 안의 카테고리 폴더명)
declare -A DIRS
if [[ -n "$CUSTOM_DIRS" ]]; then
    IFS=',' read -ra _arr <<< "$CUSTOM_DIRS"
    for p in "${_arr[@]}"; do
        name=$(basename "$p")
        DIRS["$p"]="$name"
    done
else
    DIRS["$REPO_ROOT/apptainer/compute-node-images"]="compute-node-images"
    DIRS["$REPO_ROOT/apptainer/viz-node-images"]="viz-node-images"
    DIRS["/data/apptainers"]="data-apptainers"
fi

TS=$(date -u +%Y%m%d-%H%M%SZ)
REMOTE_BASE="${STC_DRIVE_REMOTE%/*}/apptainer-images"

echo -e "${BLUE}═══ Apptainer 이미지 → Drive ═══${NC}"
echo "  remote: $REMOTE_BASE/"
echo "  note:   ${NOTE:-(없음)}"
echo ""

# 총 크기 추정
TOTAL=0
for d in "${!DIRS[@]}"; do
    [ -d "$d" ] || continue
    sz=$(du -sb "$d" 2>/dev/null | awk '{print $1}')
    TOTAL=$((TOTAL + sz))
    echo "  → $d ($(numfmt --to=iec $sz))"
done
echo "  총: $(numfmt --to=iec $TOTAL)"
echo ""

# 매니페스트 임시
MANIFEST=$(mktemp)
trap "rm -f $MANIFEST" EXIT
{
    echo "# Apptainer Images Manifest — $TS"
    echo "# host: $(hostname) · user: ${SUDO_USER:-$USER}"
    echo "# note: ${NOTE:-(없음)}"
    echo ""
    for d in "${!DIRS[@]}"; do
        [ -d "$d" ] || continue
        echo "## ${DIRS[$d]} (source: $d)"
        find "$d" -maxdepth 2 -name "*.sif" -printf "  %f  %s bytes  %TY-%Tm-%Td\n"
        echo ""
    done
} > "$MANIFEST"

# 업로드 — 각 카테고리 폴더로
for src in "${!DIRS[@]}"; do
    [ -d "$src" ] || { echo -e "${YELLOW}⚠ skip: $src 없음${NC}"; continue; }
    dest="$REMOTE_BASE/${DIRS[$src]}"
    echo -e "${BLUE}→ $src → $dest${NC}"
    # --update: 더 최신 파일만, --transfers 4: 대용량이라 동시 4
    rclone copy --progress --update --transfers 4 \
        --include "*.sif" --include "*.sif.sha256" \
        "$src/" "$dest/"
done

# 매니페스트도 업로드 (타임스탬프 명시)
rclone copy "$MANIFEST" "$REMOTE_BASE/" --no-traverse 2>/dev/null
mv "$MANIFEST" "/tmp/manifest-apptainers-$TS.txt"
rclone copy "/tmp/manifest-apptainers-$TS.txt" "$REMOTE_BASE/" 2>/dev/null
rm -f "/tmp/manifest-apptainers-$TS.txt"

echo ""
echo -e "${GREEN}✅ 업로드 완료${NC}"
rclone size "$REMOTE_BASE/" 2>&1 | head -3
echo ""
echo "복원: ./offline_packages_2404/pull-apptainers.sh"
