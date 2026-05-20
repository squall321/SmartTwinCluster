#!/bin/bash
################################################################################
# slurmctld "Incorrect permissions on state save loc" 진단 + 자동 복구
#
# 사용:
#   sudo ./cluster/utils/check_slurm_state_dir.sh        # 진단만
#   sudo ./cluster/utils/check_slurm_state_dir.sh --fix  # 진단 + 자동 복구 + restart
################################################################################
set -uo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

FIX=0
[[ "${1:-}" == "--fix" ]] && FIX=1

[[ $EUID -ne 0 ]] && { echo -e "${RED}sudo 필요${NC}"; exit 1; }

# 1) StateSaveLocation
STATE_DIR=$(grep -E '^[[:space:]]*StateSaveLocation' /etc/slurm/slurm.conf 2>/dev/null \
    | head -1 | sed 's/.*=//' | tr -d ' ')
[[ -z "$STATE_DIR" ]] && STATE_DIR="/var/spool/slurmctld"
echo -e "${BLUE}═══ slurm.conf StateSaveLocation: $STATE_DIR ═══${NC}"

# 2) slurm UID/GID
SLURM_UID=$(id -u slurm 2>/dev/null || echo "")
SLURM_GID=$(id -g slurm 2>/dev/null || echo "")
echo "slurm user: uid=$SLURM_UID gid=$SLURM_GID"
[[ -z "$SLURM_UID" ]] && { echo -e "${RED}❌ slurm 사용자 없음${NC}"; exit 1; }

# 3) 디렉토리 존재 + 마운트
echo ""
echo -e "${BLUE}═══ 디렉토리 ═══${NC}"
if [[ ! -d "$STATE_DIR" ]]; then
    echo -e "${RED}✗ $STATE_DIR 존재 안 함${NC}"
    [[ $FIX -eq 1 ]] && mkdir -p "$STATE_DIR" && echo "  → 생성"
fi

if [[ -d "$STATE_DIR" ]]; then
    DIR_UID=$(stat -c '%u' "$STATE_DIR")
    DIR_GID=$(stat -c '%g' "$STATE_DIR")
    DIR_MODE=$(stat -c '%a' "$STATE_DIR")
    DIR_OWN=$(stat -c '%U:%G' "$STATE_DIR")
    REAL_PATH=$(readlink -f "$STATE_DIR")
    echo "stat:        owner=$DIR_OWN mode=$DIR_MODE"
    echo "stat uid/gid: $DIR_UID/$DIR_GID  (slurm 기대: $SLURM_UID/$SLURM_GID)"
    echo "readlink -f: $REAL_PATH"

    # mount 포인트?
    MNT_PARENT=$(echo "$STATE_DIR" | awk -F/ '{print "/"$2"/"$3}')
    if mount | grep -q " on $MNT_PARENT "; then
        echo "마운트:       $MNT_PARENT ($(mount | grep " on $MNT_PARENT " | head -1 | awk '{print $1}'))"
    fi
fi

# 4) UID/모드 검증
echo ""
echo -e "${BLUE}═══ 권한 검증 ═══${NC}"
ERRORS=0

if [[ "$DIR_UID" != "$SLURM_UID" ]]; then
    echo -e "${RED}✗ owner UID 불일치: $DIR_UID ≠ $SLURM_UID${NC}"
    ERRORS=$((ERRORS+1))
    [[ $FIX -eq 1 ]] && chown -R slurm:slurm "$STATE_DIR" "$(dirname "$STATE_DIR")" && \
        echo -e "${GREEN}  → chown -R slurm:slurm $(dirname "$STATE_DIR") 적용${NC}"
else
    echo -e "${GREEN}✓ owner UID 일치${NC}"
fi

# slurmctld 요구: owner read+write+exec (S_IRWXU)
if (( (DIR_MODE / 100) < 7 )); then
    echo -e "${RED}✗ owner 권한 부족: mode $DIR_MODE → owner rwx 필요${NC}"
    ERRORS=$((ERRORS+1))
    [[ $FIX -eq 1 ]] && chmod 755 "$STATE_DIR" && echo "  → chmod 755 적용"
else
    echo -e "${GREEN}✓ owner rwx OK (mode $DIR_MODE)${NC}"
fi

# 5) slurm 으로 실제 쓰기 가능?
if sudo -u slurm test -w "$STATE_DIR" 2>/dev/null && \
   sudo -u slurm touch "$STATE_DIR/.diag_$$" 2>/dev/null; then
    rm -f "$STATE_DIR/.diag_$$"
    echo -e "${GREEN}✓ slurm 사용자 쓰기 가능${NC}"
else
    echo -e "${RED}✗ slurm 사용자 쓰기 불가 (실제 마운트 ACL/ro 가능성)${NC}"
    ERRORS=$((ERRORS+1))
fi

# 6) ACL/속성
echo ""
echo -e "${BLUE}═══ 추가 검사 ═══${NC}"
if command -v getfacl &>/dev/null; then
    ACL=$(getfacl --absolute-names "$STATE_DIR" 2>/dev/null | grep -v '^#' | tr -d ' ')
    echo "ACL:"
    echo "$ACL" | sed 's/^/  /' | head -10
fi

if command -v lsattr &>/dev/null; then
    ATTR=$(lsattr -d "$STATE_DIR" 2>/dev/null | awk '{print $1}')
    [[ -n "$ATTR" ]] && echo "lsattr: $ATTR"
fi

# log/spool 도 같이
for sub in log spool; do
    sub_dir="$(dirname "$STATE_DIR")/$sub"
    if [[ -d "$sub_dir" ]]; then
        sub_own=$(stat -c '%U:%G %a' "$sub_dir")
        if [[ "$(stat -c '%u' "$sub_dir")" != "$SLURM_UID" ]]; then
            echo -e "${RED}✗ $sub_dir 권한 비정상: $sub_own${NC}"
            ERRORS=$((ERRORS+1))
            [[ $FIX -eq 1 ]] && chown -R slurm:slurm "$sub_dir" && echo "  → chown 적용"
        fi
    fi
done

# 7) systemd 서비스에 ExecStartPre 있나
echo ""
echo -e "${BLUE}═══ systemd ExecStartPre 검사 ═══${NC}"
if [[ -f /etc/systemd/system/slurmctld.service ]] && \
   grep -q "ExecStartPre.*chown.*slurm.*gluster" /etc/systemd/system/slurmctld.service; then
    echo -e "${GREEN}✓ slurmctld.service 에 자동 chown ExecStartPre 박혀있음${NC}"
else
    echo -e "${YELLOW}⚠️  ExecStartPre 자동 chown 미설치${NC}"
    if [[ $FIX -eq 1 ]] && [[ -f /etc/systemd/system/slurmctld.service ]]; then
        sed -i '/^ExecStart=.*slurmctld/i ExecStartPre=-/bin/bash -c '\''mkdir -p '"$STATE_DIR"' '"$(dirname "$STATE_DIR")"'/log '"$(dirname "$STATE_DIR")"'/spool \&\& chown -R slurm:slurm '"$(dirname "$STATE_DIR")"' 2>/dev/null \&\& chmod 755 '"$STATE_DIR"' 2>/dev/null; true'\''' /etc/systemd/system/slurmctld.service
        systemctl daemon-reload
        echo "  → ExecStartPre 추가 + daemon-reload"
    fi
fi

# 8) slurmctld 재시작 + 결과
echo ""
echo -e "${BLUE}═══ 요약 ═══${NC}"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ 모든 검사 통과${NC}"
else
    echo -e "${RED}✗ ${ERRORS}개 문제${NC} $([ $FIX -eq 1 ] && echo "(자동 복구 완료, 재시작 시도)")"
fi

if [[ $FIX -eq 1 ]]; then
    echo ""
    echo -e "${BLUE}═══ slurmctld 재시작 ═══${NC}"
    systemctl restart slurmctld
    sleep 3
    systemctl is-active slurmctld --quiet && \
        echo -e "${GREEN}✅ slurmctld active${NC}" || \
        echo -e "${RED}❌ slurmctld 시작 실패 — journalctl -u slurmctld -n 30${NC}"
    echo ""
    sinfo 2>&1 | head -10
else
    echo ""
    echo "복구 자동 실행: sudo $0 --fix"
fi
