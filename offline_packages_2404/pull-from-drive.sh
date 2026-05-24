#!/usr/bin/env bash
# Google Drive → 로컬 offline_packages 다운로드 + 검증 + 추출
#
# 사용:
#   ./pull-from-drive.sh                       # 24.04 최신 자동
#   ./pull-from-drive.sh --os 22.04            # 22.04
#   ./pull-from-drive.sh --set stc-offline-...  # 특정 세트
#   ./pull-from-drive.sh --list                # 사용 가능 세트 목록
#   ./pull-from-drive.sh --no-extract          # 다운로드만, tar 풀지 않음
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.drive-sync.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || {
    echo -e "${RED}❌ $ENV_FILE 없음 — 먼저 ./setup-drive-sync.sh${NC}"; exit 1
}
[[ -z "${STC_DRIVE_REMOTE:-}" ]] && { echo -e "${RED}❌ STC_DRIVE_REMOTE 미설정${NC}"; exit 1; }

OS_VER="24.04"
SET_NAME=""
LIST_ONLY=0
NO_EXTRACT=0
TARGET_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --os) OS_VER="$2"; shift 2 ;;
        --os=*) OS_VER="${1#*=}"; shift ;;
        --set) SET_NAME="$2"; shift 2 ;;
        --set=*) SET_NAME="${1#*=}"; shift ;;
        --list|-l) LIST_ONLY=1; shift ;;
        --no-extract) NO_EXTRACT=1; shift ;;
        --target) TARGET_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '/^# /,/^set/p' "$0" | grep '^#' | sed 's/^# *//'; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# 타깃 디렉토리
if [[ -z "$TARGET_DIR" ]]; then
    case "$OS_VER" in
        24.04) TARGET_DIR="$(dirname "$SCRIPT_DIR")/offline_packages_2404" ;;
        22.04) TARGET_DIR="$(dirname "$SCRIPT_DIR")/offline_packages" ;;
        *) echo "지원 OS: 22.04 / 24.04"; exit 1 ;;
    esac
fi

# 목록만 출력
if [[ "$LIST_ONLY" == "1" ]]; then
    echo -e "${BLUE}═══ 사용 가능 세트 ($STC_DRIVE_REMOTE) ═══${NC}"
    rclone lsf --dirs-only "$STC_DRIVE_REMOTE/" 2>/dev/null | \
        sed 's|/$||' | sort -r | head -20 | nl -ba
    exit 0
fi

# 자동 — OS_VER 의 최신 세트 (incremental 우선 제외)
if [[ -z "$SET_NAME" ]]; then
    echo -e "${BLUE}→ 최신 세트 검색 (OS=$OS_VER)${NC}"
    SET_NAME=$(rclone lsf --dirs-only "$STC_DRIVE_REMOTE/" 2>/dev/null | \
        sed 's|/$||' | grep -E "^stc-offline-${OS_VER}-" | grep -v incr | sort | tail -1)
    [[ -z "$SET_NAME" ]] && {
        echo -e "${RED}❌ OS=$OS_VER 의 세트 없음 — --list 확인${NC}"; exit 1
    }
fi
echo -e "${GREEN}  세트: $SET_NAME${NC}"

# manifest 먼저 확인
echo -e "${BLUE}→ manifest 다운로드${NC}"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
rclone copy "$STC_DRIVE_REMOTE/$SET_NAME/manifest.json" "$TMP/" 2>/dev/null || {
    echo -e "${YELLOW}⚠️ manifest 없음 (옛 버전 세트) — 그대로 진행${NC}"
}
[[ -f "$TMP/manifest.json" ]] && {
    echo "  $(cat $TMP/manifest.json | python3 -m json.tool 2>/dev/null | head -10)"
}

# 다운로드
echo -e "${BLUE}→ 전체 다운로드 (parts + sha256 + RESTORE.md)${NC}"
DOWNLOAD_DIR="$TARGET_DIR/dist/$SET_NAME"
mkdir -p "$DOWNLOAD_DIR"
rclone copy --progress "$STC_DRIVE_REMOTE/$SET_NAME/" "$DOWNLOAD_DIR/"

# 검증
echo -e "${BLUE}→ sha256 검증${NC}"
if [[ -f "$DOWNLOAD_DIR/sha256.txt" ]]; then
    ( cd "$DOWNLOAD_DIR" && sha256sum -c sha256.txt ) && \
        echo -e "${GREEN}✓ 체크섬 OK${NC}" || {
            echo -e "${RED}❌ 체크섬 실패 — 다시 받기${NC}"; exit 1
        }
else
    echo -e "${YELLOW}⚠️ sha256.txt 없음 — 검증 스킵${NC}"
fi

if [[ "$NO_EXTRACT" == "1" ]]; then
    echo ""
    echo -e "${GREEN}✅ 다운로드 완료 (extract 스킵)${NC}"
    echo "  위치: $DOWNLOAD_DIR"
    echo "  수동 추출: cat $DOWNLOAD_DIR/parts.tar.gz.part-* | tar -xzf - -C $TARGET_DIR"
    exit 0
fi

# 추출
echo -e "${BLUE}→ tar 추출 → $TARGET_DIR${NC}"
cat "$DOWNLOAD_DIR"/parts.tar.gz.part-* | tar -xzf - -C "$TARGET_DIR"
echo -e "${GREEN}✓ 추출 완료${NC}"

# 권한 보정 (root 소유 파일 대비)
[[ -n "${SUDO_USER:-}" ]] && {
    sudo chown -R "$SUDO_USER":"$SUDO_USER" "$DOWNLOAD_DIR" 2>/dev/null || true
}

# Packages.gz 재인덱싱 (apt 저장소 사용 시)
if [[ -d "$TARGET_DIR/apt_packages" ]] && command -v dpkg-scanpackages &>/dev/null; then
    echo -e "${BLUE}→ APT Packages.gz 재인덱싱${NC}"
    ( cd "$TARGET_DIR/apt_packages" &&
      sudo dpkg-scanpackages . /dev/null > Packages 2>/dev/null &&
      sudo gzip -9c Packages > Packages.gz &&
      sudo apt-get update -o Dir::Etc::sourcelist="/etc/apt/sources.list.d/offline-local.list" \
          -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null ) || true
fi

echo ""
echo -e "${GREEN}✅ 완료 — $TARGET_DIR 에 적용됨${NC}"
echo "  로컬 dist 정리: rm -rf '$DOWNLOAD_DIR'"
