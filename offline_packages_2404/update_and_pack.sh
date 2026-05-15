#!/bin/bash
################################################################################
# VM 기반 offline_packages_2404 업데이트 + 1GB 분할 tar 압축
#
# 1. prepare_offline_packages_2404.sh --yes 실행 (VM dist-upgrade + collect)
# 2. apt_packages/, python_wheels/, slurm/, munge/, gpu/, nodejs/, opencascade/
#    를 묶어 1GB 단위 tar.gz로 분할 압축
#
# 사용:  sudo ./offline_packages_2404/update_and_pack.sh
################################################################################
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ sudo로 실행하세요: sudo $0${NC}"; exit 1
fi

# --incremental: 이번 실행에서 새로 받은/갱신된 파일만 tar
MODE="full"
for a in "$@"; do
    case "$a" in
        --incremental|-i) MODE="incremental" ;;
        --help|-h) echo "Usage: sudo $0 [--incremental]"; exit 0 ;;
    esac
done
echo -e "${BLUE}모드: $MODE${NC}"

# 시작 시점 마커 (mtime 비교 기준)
MARKER="${SCRIPT_DIR}/.update_start_$(date +%s)"
touch "$MARKER"

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE} 1단계: VM 기반 패키지 재수집 (1~3시간)${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

LOG_FILE="${SCRIPT_DIR}/update_and_pack_$(date +%Y%m%d_%H%M%S).log"
echo "로그: $LOG_FILE"

bash ./prepare_offline_packages_2404.sh --yes 2>&1 | tee "$LOG_FILE"

if ! grep -q "completed" "$LOG_FILE" && ! grep -q "완료" "$LOG_FILE"; then
    echo -e "${YELLOW}⚠️  prepare 스크립트 완료 표시 없음. 로그 확인 후 계속 진행${NC}"
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE} 2단계: 1GB 분할 tar.gz 압축${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

OUT_DIR="${SCRIPT_DIR}/dist"
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/offline_packages_2404.tar.gz.part-* 2>/dev/null || true

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PREFIX="${OUT_DIR}/offline_packages_2404_${TIMESTAMP}.tar.gz.part-"

INCLUDE_DIRS=()
for d in apt_packages python_wheels slurm munge gpu nodejs opencascade; do
    [ -d "$SCRIPT_DIR/$d" ] && INCLUDE_DIRS+=("$d")
done

echo "포함 디렉토리: ${INCLUDE_DIRS[*]}"
echo "출력 prefix:  $PREFIX"

if [ "$MODE" = "incremental" ]; then
    # 마커보다 새로운 파일 목록 생성
    FILELIST="${OUT_DIR}/filelist_${TIMESTAMP}.txt"
    ( cd "$SCRIPT_DIR" && find "${INCLUDE_DIRS[@]}" -type f -newer "$MARKER" ) > "$FILELIST"
    NEW_COUNT=$(wc -l < "$FILELIST")
    echo -e "${YELLOW}🆕 신규/갱신 파일: ${NEW_COUNT}개${NC}"
    if [ "$NEW_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}변경 없음. 압축 생략.${NC}"
        rm -f "$MARKER"
        exit 0
    fi
    tar -C "$SCRIPT_DIR" -cf - -T "$FILELIST" \
        | gzip -1 \
        | split --bytes=1G --numeric-suffixes=0 --suffix-length=3 - "$PREFIX"
else
    tar -C "$SCRIPT_DIR" -cf - "${INCLUDE_DIRS[@]}" \
        | gzip -1 \
        | split --bytes=1G --numeric-suffixes=0 --suffix-length=3 - "$PREFIX"
fi

rm -f "$MARKER"

# 체크섬
( cd "$OUT_DIR" && sha256sum offline_packages_2404_${TIMESTAMP}.tar.gz.part-* > "offline_packages_2404_${TIMESTAMP}.sha256" )

echo ""
echo -e "${GREEN}✅ 완료${NC}"
ls -lh "$OUT_DIR"/offline_packages_2404_${TIMESTAMP}*

# 원래 사용자 소유로 복원
ORIG_USER="${SUDO_USER:-koopark}"
chown -R "$ORIG_USER":"$ORIG_USER" "$OUT_DIR" 2>/dev/null || true

cat <<INFO

🔗 복원 방법 (서버 측):
   cd offline_packages_2404
   cat dist/offline_packages_2404_${TIMESTAMP}.tar.gz.part-* | tar -xzf -

🔐 체크섬 검증:
   cd dist && sha256sum -c offline_packages_2404_${TIMESTAMP}.sha256
INFO
