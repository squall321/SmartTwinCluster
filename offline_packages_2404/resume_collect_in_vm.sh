#!/bin/bash
################################################################################
# VM에서 collect_apt_packages_2404.sh를 특정 알파벳부터 이어서 실행
#
# 사용:
#   sudo ./resume_collect_in_vm.sh n         # 'n'부터 시작 (m까지 한 경우)
#   sudo ./resume_collect_in_vm.sh n 8       # n부터, 병렬 8 스레드
################################################################################
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_FROM="${1:-n}"
JOBS="${2:-8}"

VM_USER="ubuntu"
VM_NAME="noble-pkg-collector"
SSH_PRIVATE_KEY="${HOME}/.ssh/vm-pkg-collector"
[ -n "$SUDO_USER" ] && SSH_PRIVATE_KEY="$(getent passwd "$SUDO_USER" | cut -d: -f6)/.ssh/vm-pkg-collector"

[[ $EUID -ne 0 ]] && { echo "sudo 필요"; exit 1; }

VM_IP=$(virsh domifaddr --source arp "$VM_NAME" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1)
[ -z "$VM_IP" ] && { echo "VM IP 못 찾음 ($VM_NAME)"; exit 1; }
echo "VM_IP=$VM_IP, START_FROM=$START_FROM, JOBS=$JOBS"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# 최신 collect 스크립트 VM에 동기화
scp $SSH_OPTS -i "$SSH_PRIVATE_KEY" \
    "$SCRIPT_DIR/collect_apt_packages_2404.sh" \
    "${VM_USER}@${VM_IP}:/home/${VM_USER}/collect/collect_apt_packages_2404.sh"

# 이어서 실행
ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
    "sudo bash /home/${VM_USER}/collect/collect_apt_packages_2404.sh \
        --output-dir /home/${VM_USER}/collect/apt_packages \
        --service all \
        --clone-host-list /home/${VM_USER}/collect/host_packages.txt \
        --start-from '$START_FROM' \
        --jobs $JOBS \
        --yes" 2>&1 | tee "${SCRIPT_DIR}/resume_collect_$(date +%Y%m%d_%H%M%S).log"

echo ""
echo "수집 완료 후 rsync로 가져오기:"
echo "  sudo rsync -av -e 'ssh $SSH_OPTS -i $SSH_PRIVATE_KEY' \\"
echo "    ${VM_USER}@${VM_IP}:/home/${VM_USER}/collect/apt_packages/ \\"
echo "    ${SCRIPT_DIR}/apt_packages/"
