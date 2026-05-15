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

# tar → gzip → split (스트리밍, 임시 파일 X)
tar -C "$SCRIPT_DIR" -cf - "${INCLUDE_DIRS[@]}" \
    | gzip -1 \
    | split --bytes=1G --numeric-suffixes=0 --suffix-length=3 - "$PREFIX"

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
