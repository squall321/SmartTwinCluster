#!/usr/bin/env bash
# Google Drive 동기화 사전 설정 — rclone 설치 + 원격 등록 안내 + 환경변수 검증
#
# 한 번만 실행:
#   ./setup-drive-sync.sh
#
# 이후 push-to-drive.sh / pull-from-drive.sh 가 동작.
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.drive-sync.env"

echo -e "${BLUE}═══ rclone Google Drive 동기화 셋업 ═══${NC}"

# 1) rclone 설치 확인
if ! command -v rclone >/dev/null 2>&1; then
    echo -e "${YELLOW}rclone 미설치 — 설치 시도${NC}"
    sudo apt install -y rclone 2>/dev/null || {
        echo -e "${RED}apt 설치 실패. 수동:${NC}"
        echo "  curl https://rclone.org/install.sh | sudo bash"
        exit 1
    }
fi
echo -e "${GREEN}✓ rclone $(rclone version | head -1)${NC}"

# 2) remote 등록 확인
REMOTES=$(rclone listremotes 2>/dev/null)
if [[ -z "$REMOTES" ]]; then
    echo ""
    echo -e "${YELLOW}rclone remote 미등록 — 등록 절차:${NC}"
    cat <<'EOF'

  rclone config

  → n (new remote)
  → name: gdrive  (자유, 'gdrive' 권장)
  → Storage: drive (Google Drive)
  → client_id / secret: 비워둠 (Enter)
  → scope: 1 (Full access)
  → root_folder_id: 비움
  → service_account_file: 비움
  → Edit advanced config: n
  → Use auto config: n  (서버 환경, headless)
  → 브라우저로 URL 열어 인증 → 코드 입력
  → Configure as team drive: n
  → y (yes this is OK)
  → q (quit)

EOF
    echo "등록 후 다시 실행하세요: $0"
    exit 1
fi
echo -e "${GREEN}✓ 등록된 remote:${NC}"
echo "$REMOTES" | sed 's/^/  /'

# 3) env 파일 — 어느 remote/경로 쓸지
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    echo -e "${GREEN}✓ $ENV_FILE 로드됨${NC}"
    echo "  STC_DRIVE_REMOTE=$STC_DRIVE_REMOTE"
    echo "  STC_DRIVE_RETAIN=${STC_DRIVE_RETAIN:-3}"
else
    DEFAULT_REMOTE=$(echo "$REMOTES" | head -1 | tr -d ':')
    echo ""
    echo -e "${YELLOW}.drive-sync.env 작성:${NC}"
    read -p "  업로드할 remote 이름 [$DEFAULT_REMOTE]: " R
    R=${R:-$DEFAULT_REMOTE}
    read -p "  Drive 안 경로 [SmartTwinCluster/offline-packages]: " P
    P=${P:-SmartTwinCluster/offline-packages}
    read -p "  보존할 세트 개수 [3]: " N
    N=${N:-3}

    cat > "$ENV_FILE" <<EOF
# Drive 동기화 설정 (push/pull 공용)
STC_DRIVE_REMOTE="${R}:${P}"
STC_DRIVE_RETAIN=${N}
EOF
    echo -e "${GREEN}✓ $ENV_FILE 저장${NC}"
    source "$ENV_FILE"
fi

# 4) 연결 테스트
echo ""
echo -e "${BLUE}→ 연결 테스트: rclone lsd $STC_DRIVE_REMOTE${NC}"
if rclone lsd "$STC_DRIVE_REMOTE" 2>&1 | head -5; then
    echo -e "${GREEN}✓ 연결 OK${NC}"
else
    echo -e "${YELLOW}경로 없음 — push-to-drive.sh 실행 시 자동 생성됨${NC}"
fi

echo ""
echo -e "${GREEN}═══ 셋업 완료 ═══${NC}"
echo "다음 단계:"
echo "  업로드(헤드노드):  ./offline_packages_2404/push-to-drive.sh"
echo "  다운로드(타깃):    ./offline_packages_2404/pull-from-drive.sh"
