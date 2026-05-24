#!/usr/bin/env bash
# 레거시 DSA 키 정리 — paramiko "q must be exactly 160/224/256 bits" 에러 해결용
#
# 동작:
#   - $HOME/.ssh/id_dsa{,.pub} 백업(.bak.YYYYMMDD-HHMMSS)
#   - /root/.ssh/id_dsa{,.pub} 백업 (sudo 있을 때)
#   - ssh-agent에 올라간 DSA 키도 제거
#
# 사용:
#   ./cleanup_legacy_dsa_keys.sh           # 백업
#   ./cleanup_legacy_dsa_keys.sh --restore # 직전 백업 복구
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

TS=$(date +%Y%m%d-%H%M%S)
MODE="backup"
[[ "${1:-}" == "--restore" ]] && MODE="restore"

backup_key() {
    local f="$1"
    local use_sudo="$2"
    local SUDO=""
    [[ "$use_sudo" == "1" ]] && SUDO="sudo"

    if $SUDO test -f "$f"; then
        local bak="${f}.bak.${TS}"
        $SUDO mv "$f" "$bak"
        echo -e "  ${GREEN}✓${NC} $f → $bak"
        return 0
    fi
    return 1
}

restore_latest() {
    local dir="$1"
    local use_sudo="$2"
    local SUDO=""
    [[ "$use_sudo" == "1" ]] && SUDO="sudo"

    for base in id_dsa id_dsa.pub; do
        local latest
        latest=$($SUDO bash -c "ls -1t ${dir}/${base}.bak.* 2>/dev/null | head -1" || true)
        if [[ -n "$latest" ]]; then
            $SUDO mv "$latest" "${dir}/${base}"
            echo -e "  ${GREEN}✓ 복구${NC} $latest → ${dir}/${base}"
        fi
    done
}

echo -e "${BLUE}═══ Legacy DSA Key Cleanup ═══${NC}"
echo "  mode: $MODE"
echo "  time: $TS"
echo ""

if [[ "$MODE" == "restore" ]]; then
    echo -e "${BLUE}→ $HOME/.ssh 복구${NC}"
    restore_latest "$HOME/.ssh" 0
    if command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
        echo -e "${BLUE}→ /root/.ssh 복구${NC}"
        restore_latest "/root/.ssh" 1
    fi
    echo -e "${GREEN}✅ 복구 완료${NC}"
    exit 0
fi

# 현재 상태
echo -e "${BLUE}→ 현재 DSA 키 검색${NC}"
found=0
for f in "$HOME/.ssh/id_dsa" "$HOME/.ssh/id_dsa.pub"; do
    [[ -f "$f" ]] && { ls -la "$f"; found=1; }
done
if command -v sudo >/dev/null; then
    for f in "/root/.ssh/id_dsa" "/root/.ssh/id_dsa.pub"; do
        sudo test -f "$f" && { sudo ls -la "$f"; found=1; }
    done
fi
[[ "$found" == "0" ]] && {
    echo -e "${YELLOW}DSA 키 없음 — 정리할 게 없습니다${NC}"
}
echo ""

# 백업
echo -e "${BLUE}→ $HOME/.ssh DSA 백업${NC}"
backup_key "$HOME/.ssh/id_dsa" 0 || echo -e "  ${YELLOW}(없음)${NC}"
backup_key "$HOME/.ssh/id_dsa.pub" 0 || echo -e "  ${YELLOW}(없음)${NC}"

if command -v sudo >/dev/null; then
    echo -e "${BLUE}→ /root/.ssh DSA 백업${NC}"
    backup_key "/root/.ssh/id_dsa" 1 || echo -e "  ${YELLOW}(없음)${NC}"
    backup_key "/root/.ssh/id_dsa.pub" 1 || echo -e "  ${YELLOW}(없음)${NC}"
fi

# ssh-agent 청소
if command -v ssh-add >/dev/null && ssh-add -l &>/dev/null; then
    if ssh-add -l 2>/dev/null | grep -qi "DSA"; then
        echo -e "${BLUE}→ ssh-agent에 DSA 키 발견 — 전체 키 제거${NC}"
        ssh-add -D 2>/dev/null && echo -e "  ${GREEN}✓ agent 비움${NC}"
    fi
fi

# 검증
echo ""
echo -e "${BLUE}→ 검증${NC}"
remaining=0
for f in "$HOME/.ssh/id_dsa" "$HOME/.ssh/id_dsa.pub" "/root/.ssh/id_dsa" "/root/.ssh/id_dsa.pub"; do
    if [[ "$f" == /root/* ]]; then
        sudo test -f "$f" 2>/dev/null && { echo -e "  ${RED}✗ 남음: $f${NC}"; remaining=1; }
    else
        [[ -f "$f" ]] && { echo -e "  ${RED}✗ 남음: $f${NC}"; remaining=1; }
    fi
done
[[ "$remaining" == "0" ]] && echo -e "  ${GREEN}✓ DSA 키 모두 정리됨${NC}"

echo ""
echo -e "${GREEN}✅ 완료${NC}"
echo "  복구가 필요하면: $0 --restore"
echo "  이제 ./update_etc_hosts.sh 또는 paramiko 사용 스크립트 재실행"
