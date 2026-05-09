#!/bin/bash
################################################################################
# 110 커널 테스트 VM 생성 + 오프라인 패키지 설치 검증
#
# 동작:
#   1. 새 VM 'noble-test-110' 생성 (검증된 prepare 스크립트와 동일 cloud-init 패턴)
#   2. 부팅 후 SSH 접근 가능해지면 → 6.8.0-110 커널 apt install + reboot
#   3. 110으로 부팅되면 호스트의 apt_packages 를 9p로 마운트
#   4. install_offline_packages.sh 실행하여 의존성 충돌 검증
#
# 사용:
#   sudo bash offline_packages_2404/test_install_110.sh
#   sudo bash offline_packages_2404/test_install_110.sh --cleanup
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
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    rm -rf "$VM_DIR"
    ok "정리 완료"
    exit 0
fi

[[ ! -f "$CLOUD_IMG" ]] && { err "클라우드 이미지 없음: $CLOUD_IMG"; exit 1; }
[[ ! -d "$HOST_PKG_DIR" ]] && { err "패키지 디렉토리 없음: $HOST_PKG_DIR"; exit 1; }
virsh dominfo "$VM_NAME" &>/dev/null && { warn "VM '$VM_NAME' 이미 존재. --cleanup 후 재실행"; exit 1; }

# 디스크 준비
mkdir -p "$VM_DIR"
log "디스크 이미지 복사..."
cp --reflink=auto "$CLOUD_IMG" "$VM_DIR/disk.qcow2"
qemu-img resize "$VM_DIR/disk.qcow2" 30G >/dev/null
ok "디스크 준비 완료"

# cloud-init: 검증된 prepare 패턴 그대로 (kernel 110은 부팅 후 별도 설치)
PUB_KEY=$(cat "$SSH_KEY_PUB")
mkdir -p "$VM_DIR/cloud-init"
cat > "$VM_DIR/cloud-init/user-data" <<USERDATA_EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true

users:
  - name: ${VM_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${PUB_KEY}

ssh_authorized_keys:
  - ${PUB_KEY}

package_update: true
package_upgrade: false
packages:
  - openssh-server
  - rsync

runcmd:
  - sed -i 's|^URIs: http://archive.ubuntu.com/ubuntu\$|URIs: http://kr.archive.ubuntu.com/ubuntu|' /etc/apt/sources.list.d/ubuntu.sources
  - systemctl enable ssh
  - systemctl start ssh
  - echo "cloud-init done" > /tmp/cloud-init-done

final_message: "Cloud-init complete after \$UPTIME seconds"
USERDATA_EOF

cat > "$VM_DIR/cloud-init/meta-data" <<EOF
instance-id: ${VM_NAME}-$(date +%s)
local-hostname: ${VM_NAME}
EOF

genisoimage -output "$VM_DIR/cloud-init.iso" -volid cidata -joliet -rock \
    "$VM_DIR/cloud-init/user-data" "$VM_DIR/cloud-init/meta-data" 2>/dev/null
ok "cloud-init ISO 생성"

# VM 생성 + 호스트 apt_packages 9p 공유
log "VM 생성 (4 vCPU, 4GB, 9p 공유)..."
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
    >/dev/null 2>&1 || { err "VM 생성 실패"; exit 1; }
ok "VM 생성 완료"

# IP 대기
log "VM IP 할당 대기..."
VM_IP=""
for i in $(seq 1 60); do
    sleep 5
    VM_IP=$(virsh domifaddr "$VM_NAME" --source lease 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d'/' -f1 | head -1)
    [[ -n "$VM_IP" ]] && break
done
[[ -z "$VM_IP" ]] && { err "IP 할당 실패"; exit 1; }
ok "VM IP: $VM_IP"

# SSH 대기
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -i $SSH_KEY_PRIV"
log "SSH 접속 대기..."
for i in $(seq 1 60); do
    sleep 5
    if ssh $SSH_OPTS -o BatchMode=yes "$VM_USER@$VM_IP" "echo ok" 2>/dev/null | grep -q ok; then
        ok "SSH 접속 가능: $VM_USER@$VM_IP"
        break
    fi
done

# cloud-init 완료 대기
log "cloud-init 완료 대기..."
ssh $SSH_OPTS "$VM_USER@$VM_IP" "cloud-init status --wait" 2>&1 | tail -3

# 110 커널 설치
log "6.8.0-110 커널 설치 중..."
ssh $SSH_OPTS "$VM_USER@$VM_IP" "
    sudo apt-get update >/dev/null 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        linux-image-6.8.0-110-generic \
        linux-modules-6.8.0-110-generic \
        linux-headers-6.8.0-110-generic \
        2>&1 | tail -5
"

# GRUB 110으로 변경 + 재부팅
log "GRUB 110 부팅 설정 + 재부팅..."
ssh $SSH_OPTS "$VM_USER@$VM_IP" "
    # 사용 가능한 커널 확인
    grep -E '^menuentry|submenu' /boot/grub/grub.cfg | grep -i '6.8.0-110' | head -3
    sudo sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux 6.8.0-110-generic\"|' /etc/default/grub
    sudo update-grub 2>&1 | tail -3
    sudo reboot
" 2>&1 || true
sleep 10

# 110으로 부팅 대기
log "110 커널 부팅 대기..."
for i in $(seq 1 60); do
    sleep 5
    K=$(ssh $SSH_OPTS -o BatchMode=yes "$VM_USER@$VM_IP" "uname -r" 2>/dev/null)
    if [[ "$K" == "6.8.0-110-generic" ]]; then
        ok "VM이 6.8.0-110 커널로 부팅됨!"
        break
    fi
done

KERNEL=$(ssh $SSH_OPTS "$VM_USER@$VM_IP" "uname -r" 2>/dev/null)
log "현재 커널: $KERNEL"
[[ "$KERNEL" != "6.8.0-110-generic" ]] && warn "110 부팅 안 됨. 수동 확인 필요"

# 호스트 패키지 9p 마운트
log "호스트 apt_packages 9p 마운트..."
ssh $SSH_OPTS "$VM_USER@$VM_IP" "
    sudo mkdir -p /mnt/hostpkgs
    sudo mount -t 9p -o trans=virtio,version=9p2000.L hostpkgs /mnt/hostpkgs
    echo 'mounted .deb count:' \$(ls /mnt/hostpkgs/*.deb 2>/dev/null | wc -l)
"

# install_offline_packages.sh 실행
log "install_offline_packages.sh 실행..."
echo "════════════════════════════════════════════════════════"
ssh $SSH_OPTS "$VM_USER@$VM_IP" "
    cd /mnt/hostpkgs
    sudo bash install_offline_packages.sh 2>&1
" | tee /tmp/install_test_output.log
echo "════════════════════════════════════════════════════════"

ok "테스트 완료"
log "전체 로그: /tmp/install_test_output.log"
log "VM 접속: ssh -i $SSH_KEY_PRIV $VM_USER@$VM_IP"
log "VM 정리: sudo bash $0 --cleanup"
