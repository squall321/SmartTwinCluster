#!/bin/bash
################################################################################
# 최근에 변경된 offline_packages_2404 파일만 1GB 분할 tar.gz로 묶기
#
# 사용:
#   sudo ./pack_recent.sh --since "YYYY-MM-DD HH:MM"   # 특정 시각 이후
#   sudo ./pack_recent.sh --mmin 240                   # 최근 240분(4시간)
#   sudo ./pack_recent.sh --mtime 1                    # 최근 1일
################################################################################
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ sudo로 실행하세요${NC}"; exit 1
fi

FIND_OPT=()
LABEL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --since)  FIND_OPT=(-newermt "$2"); LABEL="since_$(date -d "$2" +%Y%m%d%H%M)"; shift 2 ;;
        --mmin)   FIND_OPT=(-mmin -"$2"); LABEL="last${2}min"; shift 2 ;;
        --mtime)  FIND_OPT=(-mtime -"$2"); LABEL="last${2}day"; shift 2 ;;
        *) echo "Usage: $0 [--since 'YYYY-MM-DD HH:MM' | --mmin N | --mtime N]"; exit 1 ;;
    esac
done
[ ${#FIND_OPT[@]} -eq 0 ] && { echo "기준 옵션 필요"; exit 1; }

INCLUDE_DIRS=()
for d in apt_packages python_wheels slurm munge gpu nodejs opencascade; do
    [ -d "$d" ] && INCLUDE_DIRS+=("$d")
done

TS=$(date +%Y%m%d_%H%M%S)
OUT_DIR="${SCRIPT_DIR}/dist"
mkdir -p "$OUT_DIR"
FILELIST="${OUT_DIR}/recent_${LABEL}_${TS}.txt"

echo -e "${BLUE}🔍 변경 파일 검색: ${FIND_OPT[*]}${NC}"
find "${INCLUDE_DIRS[@]}" -type f "${FIND_OPT[@]}" > "$FILELIST"
COUNT=$(wc -l < "$FILELIST")
TOTAL_BYTES=$(du -cb $(cat "$FILELIST") 2>/dev/null | tail -1 | awk '{print $1}')
echo -e "${YELLOW}  → ${COUNT}개 파일, $(numfmt --to=iec ${TOTAL_BYTES:-0})${NC}"
[ "$COUNT" -eq 0 ] && { echo "변경 없음"; exit 0; }
echo "파일 목록: $FILELIST"
echo "샘플 (최대 10개):"
head -10 "$FILELIST" | sed 's/^/   /'

PREFIX="${OUT_DIR}/offline_2404_recent_${LABEL}_${TS}.tar.gz.part-"
echo -e "${BLUE}📦 압축 → ${PREFIX}*${NC}"
tar -C "$SCRIPT_DIR" -cf - -T "$FILELIST" \
    | gzip -1 \
    | split --bytes=1G --numeric-suffixes=0 --suffix-length=3 - "$PREFIX"

( cd "$OUT_DIR" && sha256sum offline_2404_recent_${LABEL}_${TS}.tar.gz.part-* > "offline_2404_recent_${LABEL}_${TS}.sha256" )

ORIG_USER="${SUDO_USER:-koopark}"
chown -R "$ORIG_USER":"$ORIG_USER" "$OUT_DIR" 2>/dev/null || true

echo ""
echo -e "${GREEN}✅ 완료${NC}"
ls -lh "$OUT_DIR"/offline_2404_recent_${LABEL}_${TS}*

cat <<INFO

🔗 서버 측 복원 (기존 위에 덮어쓰기):
   cd offline_packages_2404
   cat dist/offline_2404_recent_${LABEL}_${TS}.tar.gz.part-* | tar -xzf -

🔐 체크섬:
   cd dist && sha256sum -c offline_2404_recent_${LABEL}_${TS}.sha256
INFO
