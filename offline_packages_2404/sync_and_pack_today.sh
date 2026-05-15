#!/bin/bash
################################################################################
# VM에서 오늘 수집한 파일을 호스트로 rsync한 뒤 오늘 mtime 기준 분할 tar.gz
#
# 사용: sudo ./sync_and_pack_today.sh [--mtime N]
#   기본 --mtime 1 (최근 24시간)
################################################################################
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}sudo 필요${NC}"; exit 1; }

MTIME="${1:-1}"
[[ "$1" == "--mtime" ]] && MTIME="$2"

REAL_HOME="${HOME}"
[ -n "$SUDO_USER" ] && REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-${REAL_HOME}/.ssh/id_rsa}"
VM_USER="ubuntu"
VM_NAME="noble-pkg-collector"

VM_IP=$(virsh domifaddr --source arp "$VM_NAME" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1)
[ -z "$VM_IP" ] && { echo -e "${RED}VM IP 못 찾음${NC}"; exit 1; }
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

echo -e "${BLUE}═ 1단계: VM → 호스트 rsync (apt_packages, python_wheels, slurm, munge)${NC}"
for d in apt_packages python_wheels slurm munge; do
    echo "  • $d"
    rsync -a -e "ssh $SSH_OPTS -i $SSH_PRIVATE_KEY" \
        "${VM_USER}@${VM_IP}:/home/${VM_USER}/collect/${d}/" \
        "${SCRIPT_DIR}/${d}/" 2>/dev/null || echo "    (skipped: ${d} 없음)"
done
echo -e "${GREEN}  ✓ rsync 완료${NC}"

echo ""
echo -e "${BLUE}═ 2단계: 최근 ${MTIME}일 변경 파일만 분할 압축${NC}"
exec "${SCRIPT_DIR}/pack_recent.sh" --mtime "$MTIME"
