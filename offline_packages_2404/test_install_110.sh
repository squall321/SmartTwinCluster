#!/bin/bash
################################################################################
# 110 커널 테스트 VM 생성 + 오프라인 패키지 설치 검증
#
# 동작:
#   1. 새 VM 'noble-test-110' 생성 (기존 noble-pkg-collector와 별개)
#   2. cloud-init으로 kr.archive.ubuntu.com 미러 + kernel 6.8.0-110 설치 + 재부팅
#   3. 호스트의 offline_packages_2404/apt_packages 를 9p로 VM에 마운트 (재다운로드 X)
#   4. VM 안에서 install_offline_packages.sh 실행하여 의존성 충돌 검증
#
# 사용:
#   sudo bash offline_packages_2404/test_install_110.sh
#   sudo bash offline_packages_2404/test_install_110.sh --cleanup   # VM 제거
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_PKG_DIR="$SCRIPT_DIR/apt_packages"
VM_NAME="noble-test-110"
VM_DIR="/var/lib/libvirt/images/${VM_NAME}"
CLOUD_IMG="/var/lib/libvirt/images/noble-pkg-collector/noble-server-cloudimg-amd64.img"
SSH_KEY_PUB="/home/koopark/.ssh/id_rsa.pub"
SSH_KEY_PRIV="/home/koopark/.ssh/id_rsa"
VM_USER="ubuntu"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

[[ $EUID -ne 0 ]] && { err "root 필요"; exit 1; }

if [[ "${1:-}" == "--cleanup" ]]; then
    log "VM '${VM_NAME}' 정리..."
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    rm -rf "$VM_DIR"
    ok "정리 완료"
    exit 0
fi

# 사전 검사
if [[ ! -f "$CLOUD_IMG" ]]; then
    err "클라우드 이미지 없음: $CLOUD_IMG"
    err "→ prepare_offline_packages_2404.sh 한 번 실행해서 받아두세요"
    exit 1
fi
if [[ ! -d "$HOST_PKG_DIR" ]]; then
    err "오프라인 패키지 디렉토리 없음: $HOST_PKG_DIR"
    exit 1
fi
if virsh dominfo "$VM_NAME" &>/dev/null; then
    warn "VM '$VM_NAME' 이미 존재. --cleanup 후 다시 실행"
    exit 1
fi

# 디스크 준비 (cloud-img 복사)
mkdir -p "$VM_DIR"
log "디스크 이미지 복사..."
cp --reflink=auto "$CLOUD_IMG" "$VM_DIR/disk.qcow2"
qemu-img resize "$VM_DIR/disk.qcow2" 30G
ok "디스크 준비 완료"

# cloud-init: 미러 변경 + 110 커널 설치 + 재부팅
PUB_KEY=$(cat "$SSH_KEY_PUB")
cat > "$VM_DIR/user-data" <<EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
users:
  - name: ${VM_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${PUB_KEY}
ssh_pwauth: false
chpasswd:
  expire: false
package_update: false
package_upgrade: false
runcmd:
  # 미러 변경: 카카오 → kr.archive (110 커널 있는 곳)
  - sed -i 's|^URIs: http://archive.ubuntu.com/ubuntu\$|URIs: http://kr.archive.ubuntu.com/ubuntu|' /etc/apt/sources.list.d/ubuntu.sources
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-6.8.0-110-generic linux-modules-6.8.0-110-generic linux-headers-6.8.0-110-generic
  # GRUB 110으로 부팅
  - sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 6.8.0-110-generic"/' /etc/default/grub
  - update-grub
  - touch /tmp/cloud-init-done
  - reboot
EOF
cat > "$VM_DIR/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF
genisoimage -output "$VM_DIR/cloud-init.iso" -volid cidata -joliet -rock "$VM_DIR/user-data" "$VM_DIR/meta-data" 2>/dev/null
ok "cloud-init ISO 생성"

# 호스트 디렉토리 9p 공유 (apt_packages 만)
log "VM 생성 + 호스트 패키지 9p 공유..."
virt-install \
    --name "$VM_NAME" \
    --memory 4096 \
    --vcpus 4 \
    --disk path="$VM_DIR/disk.qcow2",bus=virtio \
    --disk path="$VM_DIR/cloud-init.iso",device=cdrom \
    --os-variant ubuntu24.04 \
    --network network=default,model=virtio \
    --graphics none \
    --import \
    --noautoconsole \
    --filesystem source="$HOST_PKG_DIR",target=hostpkgs,accessmode=passthrough \
    || { err "VM 생성 실패"; exit 1; }
ok "VM 생성 완료"

# IP 대기
log "VM IP 할당 대기 (최대 180초)..."
VM_IP=""
for i in $(seq 1 36); do
    sleep 5
    VM_IP=$(virsh domifaddr "$VM_NAME" --source arp 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d'/' -f1 | head -1)
    [[ -n "$VM_IP" ]] && break
done
[[ -z "$VM_IP" ]] && { err "IP 할당 실패"; exit 1; }
ok "VM IP: $VM_IP"

# cloud-init + kernel 110 설치 + 재부팅 대기
log "cloud-init 완료 + 재부팅 대기 (최대 10분)..."
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -i $SSH_KEY_PRIV"
for i in $(seq 1 120); do
    sleep 5
    if ssh $SSH_OPTS "$VM_USER@$VM_IP" "uname -r" 2>/dev/null | grep -q "6.8.0-110"; then
        ok "VM이 6.8.0-110 커널로 부팅됨!"
        break
    fi
    [[ $((i % 6)) -eq 0 ]] && log "  대기 중... ($((i*5))초)"
done

# 커널 확인
KERNEL=$(ssh $SSH_OPTS "$VM_USER@$VM_IP" "uname -r" 2>/dev/null)
if [[ "$KERNEL" != "6.8.0-110-generic" ]]; then
    warn "VM 커널이 110이 아님: $KERNEL"
    log "수동 확인: ssh -i $SSH_KEY_PRIV $VM_USER@$VM_IP"
    exit 1
fi

# 호스트 패키지 마운트
log "호스트 패키지를 VM에 마운트..."
ssh $SSH_OPTS "$VM_USER@$VM_IP" "
    sudo mkdir -p /mnt/hostpkgs
    sudo mount -t 9p -o trans=virtio,version=9p2000.L hostpkgs /mnt/hostpkgs
    ls /mnt/hostpkgs/*.deb | wc -l
" 2>&1 | tail -5

# install_offline_packages.sh 실행
log "install_offline_packages.sh 실행 (실제 install 테스트)..."
ssh $SSH_OPTS "$VM_USER@$VM_IP" "
    cd /mnt/hostpkgs
    sudo bash install_offline_packages.sh 2>&1 | tail -50
" || warn "install 도중 일부 실패 — 위 로그 확인"

echo ""
ok "테스트 완료"
log "VM 접속: ssh -i $SSH_KEY_PRIV $VM_USER@$VM_IP"
log "VM 정리: sudo bash $0 --cleanup"
