#!/bin/bash
################################################################################
# Ubuntu 24.04 (Noble) 오프라인 패키지 수집 자동화 스크립트
#
# 설명:
#   Ubuntu 22.04 호스트에서 KVM을 이용해 24.04 VM을 생성하고,
#   오프라인 설치에 필요한 APT 패키지와 Python wheels을 수집한 뒤
#   호스트로 복사합니다. VM은 작업 완료 후 자동으로 정리됩니다.
#
# 기능:
#   - Ubuntu 24.04 (Noble Numbat) 클라우드 이미지 자동 다운로드
#   - cloud-init 기반 SSH 키 주입 및 VM 프로비저닝
#   - virt-install을 이용한 일회성 패키지 수집 VM 생성
#   - VM 내에서 APT 패키지 수집 (collect_apt_packages_2404.sh)
#   - VM 내에서 Python wheel 다운로드 (download_python_wheels_2404.sh)
#   - rsync로 수집 결과를 호스트로 전송
#   - 22.04/24.04 공용 스크립트 및 GPU 패키지 연결
#
# 요구사항:
#   - Ubuntu 22.04 호스트 (root 권한)
#   - 인터넷 연결
#   - KVM/libvirt 패키지 (qemu-kvm, libvirt-daemon-system, virt-install 등)
#   - 최소 60GB 디스크 여유 공간
#
# 사용법:
#   sudo ./prepare_offline_packages_2404.sh [OPTIONS]
#
# 옵션:
#   --skip-vm-cleanup    VM을 삭제하지 않고 유지 (디버깅용)
#   --reuse-vm           기존 VM이 있으면 재사용 (VM 생성 건너뛰기)
#   --help               도움말 표시
#
# 작성자: Claude Code
# 날짜: 2026-03-06
################################################################################

set -euo pipefail

################################################################################
# 상수 및 기본값
################################################################################

# VM 설정
VM_NAME="noble-pkg-collector"
VM_VCPUS=8
VM_RAM_MB=16384
VM_DISK_GB=120
VM_USER="ubuntu"

# 클라우드 이미지
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
CLOUD_IMAGE_FILENAME="noble-server-cloudimg-amd64.img"

# 네트워크 (기본 NAT)
VM_NETWORK="default"

# 타임아웃 (초)
BOOT_TIMEOUT=180
SSH_TIMEOUT=300
SCRIPT_TIMEOUT=3600

# 스크립트 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
LEGACY_PKG_DIR="${PARENT_DIR}/offline_packages"

# VM 작업 디렉토리
VM_WORK_DIR="/var/lib/libvirt/images/${VM_NAME}"

# 결과 수집 디렉토리 (SCRIPT_DIR 하위)
APT_DIR="${SCRIPT_DIR}/apt_packages"
WHEELS_DIR="${SCRIPT_DIR}/python_wheels"
SLURM_DIR="${SCRIPT_DIR}/slurm"
MUNGE_DIR="${SCRIPT_DIR}/munge"
NODEJS_DIR="${SCRIPT_DIR}/nodejs"
GPU_DIR="${SCRIPT_DIR}/gpu"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 플래그
SKIP_VM_CLEANUP=false
REUSE_VM=false
AUTO_YES=false

################################################################################
# 로깅 함수
################################################################################

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase()   { echo -e "${CYAN}[PHASE $1]${NC} $2"; }

################################################################################
# 도움말
################################################################################

show_help() {
    head -n 38 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

################################################################################
# 인자 파싱
################################################################################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-vm-cleanup)
                SKIP_VM_CLEANUP=true
                shift
                ;;
            --reuse-vm)
                REUSE_VM=true
                shift
                ;;
            --yes|-y)
                AUTO_YES=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

################################################################################
# 사전 검사
################################################################################

# Root 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행해야 합니다."
        log_info "사용법: sudo $0"
        exit 1
    fi
}

# 인터넷 연결 확인
check_internet() {
    log_info "인터넷 연결 확인 중..."
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        log_success "인터넷 연결 확인됨"
    else
        log_error "인터넷에 연결되어 있지 않습니다."
        log_error "이 스크립트는 클라우드 이미지와 패키지를 다운로드하기 위해 인터넷이 필요합니다."
        exit 1
    fi
}

# KVM/libvirt 의존성 확인
check_kvm_dependencies() {
    log_info "KVM/libvirt 의존성 확인 중..."

    local missing_pkgs=()

    # 필수 명령어 확인
    local required_cmds=(
        "virsh"
        "virt-install"
        "qemu-img"
        "genisoimage"
        "rsync"
        "ssh-keygen"
    )

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_pkgs+=("$cmd")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        log_error "다음 명령어가 설치되어 있지 않습니다: ${missing_pkgs[*]}"
        log_info "설치 명령:"
        log_info "  sudo apt-get install -y qemu-kvm libvirt-daemon-system virtinst genisoimage rsync"
        exit 1
    fi

    # libvirtd 서비스 상태 확인
    if ! systemctl is-active --quiet libvirtd 2>/dev/null; then
        log_info "libvirtd 서비스를 시작합니다..."
        systemctl start libvirtd
        systemctl enable libvirtd
    fi

    # 기본 NAT 네트워크 확인 및 시작
    if ! virsh net-info "$VM_NETWORK" &>/dev/null; then
        log_info "기본 NAT 네트워크(${VM_NETWORK})를 정의하고 시작합니다..."
        virsh net-define /usr/share/libvirt/networks/default.xml 2>/dev/null || true
    fi
    if ! virsh net-info "$VM_NETWORK" 2>/dev/null | grep -q "Active:.*yes"; then
        virsh net-start "$VM_NETWORK" 2>/dev/null || true
        virsh net-autostart "$VM_NETWORK" 2>/dev/null || true
    fi

    log_success "KVM/libvirt 환경 준비 완료"
}

# 디스크 공간 확인
check_disk_space() {
    log_info "디스크 공간 확인 중..."

    local available_gb
    available_gb=$(df -BG "$SCRIPT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ $available_gb -lt 60 ]]; then
        log_warning "디스크 공간이 부족할 수 있습니다: ${available_gb}GB 가용"
        log_warning "권장: 최소 60GB"
        if [[ "$AUTO_YES" != true ]]; then
            read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        log_success "디스크 공간: ${available_gb}GB 가용"
    fi
}

################################################################################
# SSH 키 준비
################################################################################

prepare_ssh_key() {
    log_info "SSH 키 준비 중..."

    # 호출한 사용자의 홈 디렉토리 확인 (sudo 경유 시 SUDO_USER 사용)
    local real_user="${SUDO_USER:-root}"
    local real_home
    real_home=$(eval echo "~${real_user}")

    SSH_PRIVATE_KEY="${real_home}/.ssh/id_rsa"
    SSH_PUBLIC_KEY="${real_home}/.ssh/id_rsa.pub"

    if [[ -f "$SSH_PUBLIC_KEY" ]]; then
        log_info "기존 SSH 공개키 사용: ${SSH_PUBLIC_KEY}"
    else
        log_info "SSH 키 쌍이 없습니다. 새로 생성합니다..."
        mkdir -p "${real_home}/.ssh"
        ssh-keygen -t rsa -b 4096 -f "$SSH_PRIVATE_KEY" -N "" -C "vm-pkg-collector"
        chown -R "${real_user}:${real_user}" "${real_home}/.ssh" 2>/dev/null || true
        log_success "SSH 키 생성 완료: ${SSH_PUBLIC_KEY}"
    fi

    SSH_PUBKEY_CONTENT=$(cat "$SSH_PUBLIC_KEY")
}

################################################################################
# Phase 1: 클라우드 이미지 다운로드
################################################################################

download_cloud_image() {
    log_phase "1" "Ubuntu 24.04 클라우드 이미지 다운로드"

    mkdir -p "$VM_WORK_DIR"

    local image_path="${VM_WORK_DIR}/${CLOUD_IMAGE_FILENAME}"

    if [[ -f "$image_path" ]]; then
        log_info "클라우드 이미지가 이미 존재합니다: ${image_path}"
        log_info "크기: $(du -sh "$image_path" | cut -f1)"
    else
        log_info "다운로드 중: ${CLOUD_IMAGE_URL}"
        log_info "이 작업은 네트워크 속도에 따라 몇 분 소요될 수 있습니다..."

        if wget -q --show-progress -O "$image_path" "$CLOUD_IMAGE_URL"; then
            log_success "클라우드 이미지 다운로드 완료: $(du -sh "$image_path" | cut -f1)"
        else
            log_error "클라우드 이미지 다운로드 실패"
            rm -f "$image_path"
            exit 1
        fi
    fi
}

################################################################################
# Phase 2: cloud-init user-data ISO 생성
################################################################################

create_cloud_init_iso() {
    log_phase "2" "cloud-init user-data ISO 생성"

    local ci_dir="${VM_WORK_DIR}/cloud-init"
    mkdir -p "$ci_dir"

    # user-data 생성 (SSH 키 주입, 패키지 업데이트, 기본 도구 설치)
    cat > "${ci_dir}/user-data" << USERDATA_EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true

users:
  - name: ${VM_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${SSH_PUBKEY_CONTENT}

# root 사용자에도 SSH 키 주입 (scp/rsync 편의)
ssh_authorized_keys:
  - ${SSH_PUBKEY_CONTENT}

# 패키지 업데이트 및 기본 도구 설치
package_update: true
package_upgrade: false
packages:
  - openssh-server
  - rsync
  - wget
  - curl
  - python3
  - python3-pip
  - python3-venv

# SSH 서비스 자동 시작
runcmd:
  # APT 미러를 kr.archive.ubuntu.com 으로 변경 (한국 공식 미러, archive와 동기화 보장)
  # 주의: mirror.kakao.com 은 동기화 지연으로 최신 커널(6.8.0-110+) 누락 사례 있음
  - sed -i 's|^URIs: http://archive.ubuntu.com/ubuntu\$|URIs: http://kr.archive.ubuntu.com/ubuntu|' /etc/apt/sources.list.d/ubuntu.sources
  - systemctl enable ssh
  - systemctl start ssh
  - echo "cloud-init provisioning complete" > /tmp/cloud-init-done

final_message: "Cloud-init provisioning completed after \$UPTIME seconds"
USERDATA_EOF

    # meta-data 생성
    cat > "${ci_dir}/meta-data" << METADATA_EOF
instance-id: ${VM_NAME}-$(date +%s)
local-hostname: ${VM_NAME}
METADATA_EOF

    # ISO 이미지 생성
    local iso_path="${VM_WORK_DIR}/cloud-init.iso"

    genisoimage -output "$iso_path" \
        -volid cidata \
        -joliet \
        -rock \
        "${ci_dir}/user-data" \
        "${ci_dir}/meta-data" \
        2>/dev/null

    if [[ -f "$iso_path" ]]; then
        log_success "cloud-init ISO 생성 완료: ${iso_path}"
    else
        log_error "cloud-init ISO 생성 실패"
        exit 1
    fi
}

################################################################################
# Phase 3: VM 생성
################################################################################

create_vm() {
    log_phase "3" "Ubuntu 24.04 VM 생성 (${VM_VCPUS} vCPU, ${VM_RAM_MB}MB RAM, ${VM_DISK_GB}GB 디스크)"

    # --reuse-vm 플래그 처리: 기존 VM이 있으면 재사용
    if [[ "$REUSE_VM" == "true" ]]; then
        if virsh dominfo "$VM_NAME" &>/dev/null; then
            log_info "--reuse-vm 플래그 활성: 기존 VM '${VM_NAME}'을 재사용합니다."

            # VM이 꺼져 있으면 시작
            if ! virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
                log_info "VM을 시작합니다..."
                virsh start "$VM_NAME" 2>/dev/null || true
            fi

            return 0
        else
            log_info "--reuse-vm 플래그 활성이나 기존 VM이 없습니다. 새로 생성합니다."
        fi
    fi

    # 기존 VM이 남아있으면 정리
    if virsh dominfo "$VM_NAME" &>/dev/null; then
        log_warning "기존 VM '${VM_NAME}'이 존재합니다. 정리합니다..."
        virsh destroy "$VM_NAME" 2>/dev/null || true
        virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
        sleep 2
    fi

    # 디스크 이미지 생성 (클라우드 이미지를 backing file로 사용)
    local base_image="${VM_WORK_DIR}/${CLOUD_IMAGE_FILENAME}"
    local disk_image="${VM_WORK_DIR}/${VM_NAME}.qcow2"
    local ci_iso="${VM_WORK_DIR}/cloud-init.iso"

    log_info "VM 디스크 이미지 생성 중 (${VM_DISK_GB}GB)..."
    qemu-img create -f qcow2 -b "$base_image" -F qcow2 "$disk_image" "${VM_DISK_GB}G"

    log_info "virt-install로 VM을 생성합니다..."
    virt-install \
        --name "$VM_NAME" \
        --vcpus "$VM_VCPUS" \
        --memory "$VM_RAM_MB" \
        --disk "path=${disk_image},format=qcow2" \
        --disk "path=${ci_iso},device=cdrom" \
        --os-variant ubuntu24.04 \
        --network "network=${VM_NETWORK}" \
        --graphics none \
        --console pty,target_type=serial \
        --import \
        --noautoconsole \
        --wait 0

    if virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
        log_success "VM '${VM_NAME}' 생성 및 시작 완료"
    else
        log_error "VM 생성 실패"
        exit 1
    fi
}

################################################################################
# Phase 4: VM 부팅 대기 및 SSH 접속 가능 확인
################################################################################

wait_for_vm_ssh() {
    log_phase "4" "VM 부팅 대기 및 SSH 접속 확인"

    # VM IP 주소 획득 대기
    log_info "VM에 IP 주소가 할당될 때까지 대기 중... (최대 ${BOOT_TIMEOUT}초)"

    local vm_ip=""
    local elapsed=0

    # 새 VM이 부팅되고 DHCP lease를 받을 시간 확보 (stale lease 방지)
    log_info "VM 부팅 대기 (30초)..."
    sleep 30
    elapsed=30

    while [[ -z "$vm_ip" && $elapsed -lt $BOOT_TIMEOUT ]]; do
        # 방법 1 (우선): virsh domifaddr --source arp — 실제 ARP 트래픽 기반 (stale 없음)
        vm_ip=$(virsh domifaddr "$VM_NAME" --source arp 2>/dev/null \
            | grep -oP '\d+\.\d+\.\d+\.\d+' \
            | head -1 || true)

        if [[ -z "$vm_ip" ]]; then
            # 방법 2: virsh domifaddr (기본) — lease 기반
            vm_ip=$(virsh domifaddr "$VM_NAME" 2>/dev/null \
                | grep -oP '\d+\.\d+\.\d+\.\d+' \
                | head -1 || true)
        fi

        # IP를 찾았으면 ping으로 실제 응답 확인 (stale IP 방지)
        if [[ -n "$vm_ip" ]]; then
            if ! ping -c 1 -W 2 "$vm_ip" &>/dev/null; then
                log_info "  IP ${vm_ip}가 응답하지 않음 (stale lease?), 재탐색..."
                vm_ip=""
            fi
        fi

        if [[ -z "$vm_ip" ]]; then
            sleep 5
            elapsed=$((elapsed + 5))
            printf "\r  대기 중... %d/%d초" "$elapsed" "$BOOT_TIMEOUT"
        fi
    done
    echo ""

    if [[ -z "$vm_ip" ]]; then
        log_error "VM IP 주소를 획득하지 못했습니다. (${BOOT_TIMEOUT}초 초과)"
        log_info "디버깅: virsh domifaddr ${VM_NAME}"
        virsh domifaddr "$VM_NAME" 2>/dev/null || true
        log_info "디버깅: virsh net-dhcp-leases ${VM_NETWORK}"
        virsh net-dhcp-leases "$VM_NETWORK" 2>/dev/null || true
        exit 1
    fi

    VM_IP="$vm_ip"
    log_info "VM IP 주소: ${VM_IP}"

    # SSH 접속 가능 대기
    log_info "SSH 서비스가 준비될 때까지 대기 중... (최대 ${SSH_TIMEOUT}초)"

    local ssh_ok=false
    elapsed=0

    # SSH 옵션 (StrictHostKeyChecking 비활성화 - 일회성 VM)
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"

    while [[ "$ssh_ok" == "false" && $elapsed -lt $SSH_TIMEOUT ]]; do
        if ssh $ssh_opts -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" "echo ssh-ready" &>/dev/null; then
            ssh_ok=true
        else
            sleep 5
            elapsed=$((elapsed + 5))
            printf "\r  SSH 대기 중... %d/%d초" "$elapsed" "$SSH_TIMEOUT"
        fi
    done
    echo ""

    if [[ "$ssh_ok" == "false" ]]; then
        log_error "SSH 접속 시간 초과 (${SSH_TIMEOUT}초)"
        log_info "VM 콘솔 확인: virsh console ${VM_NAME}"
        exit 1
    fi

    # cloud-init 완료 대기
    log_info "cloud-init 프로비저닝 완료 대기 중..."
    local ci_elapsed=0
    local ci_timeout=300

    while [[ $ci_elapsed -lt $ci_timeout ]]; do
        if ssh $ssh_opts -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
            "test -f /tmp/cloud-init-done" &>/dev/null; then
            break
        fi
        sleep 5
        ci_elapsed=$((ci_elapsed + 5))
        printf "\r  cloud-init 대기 중... %d/%d초" "$ci_elapsed" "$ci_timeout"
    done
    echo ""

    # 최종 확인: OS 버전 출력
    local os_version
    os_version=$(ssh $ssh_opts -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "unknown")

    log_success "VM SSH 접속 준비 완료"
    log_info "VM OS: ${os_version}"

    # SSH_OPTS를 전역 변수로 저장 (이후 단계에서 사용)
    SSH_OPTS="$ssh_opts"
}

################################################################################
# Phase 5: 수집 스크립트를 VM으로 복사
################################################################################

copy_scripts_to_vm() {
    log_phase "5" "수집 스크립트를 VM으로 복사"

    local remote_dir="/home/${VM_USER}/collect"

    # VM 내 작업 디렉토리 생성
    ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "mkdir -p ${remote_dir}"

    # 24.04용 수집 스크립트 + Slurm 빌드 스크립트 복사
    local project_root
    project_root="$(cd "${SCRIPT_DIR}/.." && pwd)"

    local scripts_to_copy=(
        "${SCRIPT_DIR}/collect_apt_packages_2404.sh"
        "${SCRIPT_DIR}/download_python_wheels_2404.sh"
        "${project_root}/offline_packages/slurm/build_slurm_package.sh"
    )

    local copy_count=0
    for script in "${scripts_to_copy[@]}"; do
        if [[ -f "$script" ]]; then
            scp $SSH_OPTS -i "$SSH_PRIVATE_KEY" \
                "$script" \
                "${VM_USER}@${VM_IP}:${remote_dir}/"
            copy_count=$((copy_count + 1))
            log_info "  복사: $(basename "$script")"
        else
            log_warning "  스크립트 없음: $(basename "$script")"
        fi
    done

    # VM 내에서 스크립트에 실행 권한 부여
    ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "chmod +x ${remote_dir}/*.sh 2>/dev/null || true"

    if [[ $copy_count -eq 0 ]]; then
        log_error "복사된 수집 스크립트가 없습니다."
        log_error "다음 파일이 필요합니다:"
        for script in "${scripts_to_copy[@]}"; do
            log_error "  - $(basename "$script")"
        done
        exit 1
    fi

    log_success "${copy_count}개 스크립트가 VM의 ${remote_dir}/로 복사됨"

    # ───────────────────────────────────────────────────────────
    # 5b. Requirements 파일 스테이징 (wheels 다운로드용)
    # ───────────────────────────────────────────────────────────
    log_info "─── 5b. Requirements 파일 스테이징 ───"

    local project_root
    project_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
    local remote_req_dir="${remote_dir}/requirements"

    # VM에 requirements 디렉토리 구조 생성
    ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "mkdir -p ${remote_req_dir}/python3.12 ${remote_req_dir}/python3.13"

    # Python 3.12 서비스: auth_portal, websocket, backend_5010, backend_moonlight
    local req_count=0
    declare -A REQ_FILES_312=(
        ["auth_portal_4430"]="${project_root}/dashboard/auth_portal_4430/requirements.txt"
        ["websocket_5011"]="${project_root}/dashboard/websocket_5011/requirements.txt"
        ["backend_5010"]="${project_root}/dashboard/backend_5010/requirements.txt"
        ["backend_moonlight_8004"]="${project_root}/dashboard/MoonlightSunshine_8004/backend_moonlight_8004/requirements.txt"
    )

    for service in "${!REQ_FILES_312[@]}"; do
        local req_file="${REQ_FILES_312[$service]}"
        if [[ -f "$req_file" ]]; then
            scp $SSH_OPTS -i "$SSH_PRIVATE_KEY" \
                "$req_file" \
                "${VM_USER}@${VM_IP}:${remote_req_dir}/python3.12/${service}_requirements.txt"
            req_count=$((req_count + 1))
            log_info "  복사: ${service} -> python3.12/"
        else
            log_warning "  requirements 없음: ${req_file}"
        fi
    done

    # Python 3.13 서비스: kooCAEWebServer, kooCAEWebAutomationServer
    declare -A REQ_FILES_313=(
        ["kooCAEWebServer_5000"]="${project_root}/dashboard/kooCAEWebServer_5000/requirements.txt"
        ["kooCAEWebAutomationServer_5001"]="${project_root}/dashboard/kooCAEWebAutomationServer_5001/requirements.txt"
    )

    for service in "${!REQ_FILES_313[@]}"; do
        local req_file="${REQ_FILES_313[$service]}"
        if [[ -f "$req_file" ]]; then
            scp $SSH_OPTS -i "$SSH_PRIVATE_KEY" \
                "$req_file" \
                "${VM_USER}@${VM_IP}:${remote_req_dir}/python3.13/${service}_requirements.txt"
            req_count=$((req_count + 1))
            log_info "  복사: ${service} -> python3.13/"
        else
            log_warning "  requirements 없음: ${req_file}"
        fi
    done

    log_success "${req_count}개 requirements 파일이 VM의 ${remote_req_dir}/로 복사됨"
}

################################################################################
# Phase 6: VM 내에서 패키지 수집 실행
################################################################################

run_collection_in_vm() {
    log_phase "6" "VM 내에서 패키지 수집 실행"

    local remote_dir="/home/${VM_USER}/collect"

    # ───────────────────────────────────────────────────────────
    # 6a. 호스트 패키지 목록 생성 + VM 전송 (--clone-host-list용)
    # ───────────────────────────────────────────────────────────
    local host_pkg_list="${SCRIPT_DIR}/host_packages.txt"
    log_info "호스트 22.04 설치 패키지 목록 생성 중..."
    dpkg-query -W -f='${Package}\n' 2>/dev/null | sort -u > "$host_pkg_list"
    local host_count=$(wc -l < "$host_pkg_list")
    log_success "호스트 패키지 ${host_count}개 → ${host_pkg_list}"

    # VM으로 전송
    scp $SSH_OPTS -i "$SSH_PRIVATE_KEY" "$host_pkg_list" \
        "${VM_USER}@${VM_IP}:${remote_dir}/host_packages.txt" &>/dev/null
    log_info "호스트 패키지 목록 VM 전송 완료"

    # ───────────────────────────────────────────────────────────
    # 6b. APT 패키지 수집 (호스트 목록 + 27 카테고리 + Ubuntu Desktop 메타패키지)
    # ───────────────────────────────────────────────────────────
    if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "test -f ${remote_dir}/collect_apt_packages_2404.sh" &>/dev/null; then

        log_info "─── 6b. APT 패키지 수집 시작 (Clone-Host-List 모드) ───"
        log_info "이 작업은 1~3시간 소요될 수 있습니다 (호스트 ${host_count}개 + Ubuntu Desktop 메타패키지)..."

        if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
            "sudo bash ${remote_dir}/collect_apt_packages_2404.sh \
                --output-dir ${remote_dir}/apt_packages \
                --service all \
                --clone-host-list ${remote_dir}/host_packages.txt \
                --yes" \
            2>&1 | tee "${SCRIPT_DIR}/collect_apt_2404.log"; then
            log_success "APT 패키지 수집 완료"
        else
            log_warning "APT 패키지 수집 중 일부 오류 발생 (로그 확인: ${SCRIPT_DIR}/collect_apt_2404.log)"
        fi
    else
        log_warning "collect_apt_packages_2404.sh 스크립트가 VM에 없습니다. APT 수집을 건너뜁니다."
    fi

    echo ""

    # ───────────────────────────────────────────────────────────
    # 6b. Python wheels 다운로드
    # ───────────────────────────────────────────────────────────
    if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "test -f ${remote_dir}/download_python_wheels_2404.sh" &>/dev/null; then

        log_info "─── 6b. Python wheels 다운로드 시작 ───"

        if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
            "sudo bash ${remote_dir}/download_python_wheels_2404.sh \
                --output-dir ${remote_dir}/python_wheels \
                --requirements-dir ${remote_dir}/requirements \
                --skip-confirm" \
            2>&1 | tee "${SCRIPT_DIR}/download_wheels_2404.log"; then
            log_success "Python wheels 다운로드 완료"
        else
            log_warning "Python wheels 다운로드 중 일부 오류 발생 (로그 확인: ${SCRIPT_DIR}/download_wheels_2404.log)"
        fi
    else
        log_warning "download_python_wheels_2404.sh 스크립트가 VM에 없습니다. Wheels 수집을 건너뜁니다."
    fi

    echo ""

    # ───────────────────────────────────────────────────────────
    # 6c. Slurm 소스 빌드 (24.04 라이브러리 링킹)
    # ───────────────────────────────────────────────────────────
    if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "test -f ${remote_dir}/build_slurm_package.sh" &>/dev/null; then

        log_info "─── 6c. Slurm 소스 빌드 시작 ───"
        log_info "24.04 라이브러리에 링크된 Slurm 바이너리를 빌드합니다..."
        log_info "이 작업은 15-20분 소요될 수 있습니다..."

        # 빌드 의존성 설치
        log_info "빌드 의존성 설치 중..."
        ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
            "sudo apt-get update -qq && sudo apt-get install -y \
                build-essential gcc g++ make wget bzip2 \
                munge libmunge-dev libmunge2 \
                libpam0g-dev libreadline-dev libssl-dev \
                libnuma-dev libhwloc-dev libdbus-1-dev \
                libsystemd-dev libpmix-dev pkg-config" \
            2>&1 | tail -5
        log_success "빌드 의존성 설치 완료"

        # Slurm 소스 빌드 실행
        if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
            "sudo bash ${remote_dir}/build_slurm_package.sh \
                --output-dir ${remote_dir}/slurm_build" \
            2>&1 | tee "${SCRIPT_DIR}/build_slurm_2404.log"; then
            log_success "Slurm 소스 빌드 완료"
        else
            log_warning "Slurm 빌드 중 오류 발생 (로그 확인: ${SCRIPT_DIR}/build_slurm_2404.log)"
        fi
    else
        log_warning "build_slurm_package.sh 스크립트가 VM에 없습니다. Slurm 빌드를 건너뜁니다."
    fi
}

################################################################################
# Phase 7: 결과를 호스트로 복사
################################################################################

fetch_results_from_vm() {
    log_phase "7" "수집 결과를 호스트로 복사"

    local remote_dir="/home/${VM_USER}/collect"

    # 결과 디렉토리 생성
    mkdir -p "$APT_DIR" "$WHEELS_DIR" "$SLURM_DIR" "$MUNGE_DIR" "$NODEJS_DIR"

    # ───────────────────────────────────────────────────────────
    # 7a. APT 패키지 복사
    # ───────────────────────────────────────────────────────────
    log_info "─── 7a. APT 패키지 (.deb) 복사 ───"

    local remote_apt_dir="${remote_dir}/apt_packages"
    if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "test -d ${remote_apt_dir}" &>/dev/null; then

        rsync -avz --progress \
            -e "ssh $SSH_OPTS -i $SSH_PRIVATE_KEY" \
            "${VM_USER}@${VM_IP}:${remote_apt_dir}/" \
            "$APT_DIR/"

        local deb_count
        deb_count=$(find "$APT_DIR" -name "*.deb" 2>/dev/null | wc -l)
        log_success "APT 패키지 복사 완료: ${deb_count}개 .deb 파일"
    else
        log_warning "VM에 APT 패키지 결과가 없습니다."
    fi

    echo ""

    # ───────────────────────────────────────────────────────────
    # 7b. Python wheels 복사
    # ───────────────────────────────────────────────────────────
    log_info "─── 7b. Python wheels 복사 ───"

    local remote_wheels_dir="${remote_dir}/python_wheels"
    if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "test -d ${remote_wheels_dir}" &>/dev/null; then

        rsync -avz --progress \
            -e "ssh $SSH_OPTS -i $SSH_PRIVATE_KEY" \
            "${VM_USER}@${VM_IP}:${remote_wheels_dir}/" \
            "$WHEELS_DIR/"

        local wheel_count
        wheel_count=$(find "$WHEELS_DIR" \( -name "*.whl" -o -name "*.tar.gz" \) 2>/dev/null | wc -l)
        log_success "Python wheels 복사 완료: ${wheel_count}개 파일"
    else
        log_warning "VM에 Python wheels 결과가 없습니다."
    fi

    echo ""

    # ───────────────────────────────────────────────────────────
    # 7c. Slurm 프리빌드 tarball 복사
    # ───────────────────────────────────────────────────────────
    log_info "─── 7c. Slurm 프리빌드 tarball 복사 ───"

    local remote_slurm_dir="${remote_dir}/slurm_build"
    if ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY" "${VM_USER}@${VM_IP}" \
        "ls ${remote_slurm_dir}/slurm-*-prebuilt.tar.gz" &>/dev/null; then

        mkdir -p "$SLURM_DIR"
        rsync -avz --progress \
            -e "ssh $SSH_OPTS -i $SSH_PRIVATE_KEY" \
            "${VM_USER}@${VM_IP}:${remote_slurm_dir}/slurm-*-prebuilt.tar.gz" \
            "$SLURM_DIR/"

        # MD5도 복사
        rsync -avz \
            -e "ssh $SSH_OPTS -i $SSH_PRIVATE_KEY" \
            "${VM_USER}@${VM_IP}:${remote_slurm_dir}/slurm-*-prebuilt.tar.gz.md5" \
            "$SLURM_DIR/" 2>/dev/null || true

        local slurm_size
        slurm_size=$(du -sh "$SLURM_DIR"/slurm-*-prebuilt.tar.gz 2>/dev/null | cut -f1)
        log_success "Slurm 프리빌드 tarball 복사 완료 (${slurm_size})"
    else
        log_warning "VM에 Slurm 프리빌드 tarball이 없습니다."
    fi
}

################################################################################
# Phase 8: 공용 스크립트 및 GPU 패키지 연결
################################################################################

link_shared_resources() {
    log_phase "8" "22.04/24.04 공용 스크립트 및 GPU 패키지 연결"

    # ───────────────────────────────────────────────────────────
    # 8a. APT 설치 스크립트 복사 (OS 버전 무관한 로직)
    # ───────────────────────────────────────────────────────────
    local src_apt_install="${LEGACY_PKG_DIR}/apt_packages/install_offline_packages.sh"
    if [[ -f "$src_apt_install" ]]; then
        cp "$src_apt_install" "${APT_DIR}/install_offline_packages.sh"
        chmod +x "${APT_DIR}/install_offline_packages.sh"
        log_info "복사: apt_packages/install_offline_packages.sh"
    else
        log_warning "원본 install_offline_packages.sh 없음: ${src_apt_install}"
    fi

    # ───────────────────────────────────────────────────────────
    # 8b. Slurm 스크립트 복사 (빌드/배포 스크립트만, tarball은 6c/7c에서 처리)
    # ───────────────────────────────────────────────────────────
    mkdir -p "$SLURM_DIR"
    for f in build_slurm_package.sh deploy_slurm.sh; do
        local src="${LEGACY_PKG_DIR}/slurm/${f}"
        if [[ -f "$src" && ! -f "${SLURM_DIR}/${f}" ]]; then
            cp "$src" "${SLURM_DIR}/${f}"
            chmod +x "${SLURM_DIR}/${f}"
            log_info "복사: slurm/${f}"
        fi
    done

    # Note: Slurm prebuilt tarball은 Phase 6c/7c에서 24.04 VM 내 빌드 결과를 사용합니다.
    # 22.04 tarball을 복사하지 않습니다 (OS별 라이브러리 링킹 차이).
    if ls "${SLURM_DIR}"/slurm-*-prebuilt.tar.gz &>/dev/null; then
        log_info "Slurm 프리빌드 tarball이 이미 있음 (VM에서 빌드된 24.04 버전)"
    else
        log_warning "Slurm 프리빌드 tarball이 없음 — Phase 6c에서 빌드되지 않았을 수 있음"
    fi

    # ───────────────────────────────────────────────────────────
    # 8c. Munge 스크립트 복사
    # ───────────────────────────────────────────────────────────
    mkdir -p "$MUNGE_DIR"
    for f in deploy_munge.sh munge.key; do
        local src="${LEGACY_PKG_DIR}/munge/${f}"
        if [[ -f "$src" ]]; then
            cp "$src" "${MUNGE_DIR}/${f}"
            if [[ "$f" == "deploy_munge.sh" ]]; then
                chmod +x "${MUNGE_DIR}/${f}"
            fi
            log_info "복사: munge/${f}"
        fi
    done

    # ───────────────────────────────────────────────────────────
    # 8d. Node.js 패키지 복사
    # ───────────────────────────────────────────────────────────
    mkdir -p "$NODEJS_DIR"
    if [[ -d "${LEGACY_PKG_DIR}/nodejs" ]]; then
        # Node.js 스크립트 및 tarball 복사
        for f in "${LEGACY_PKG_DIR}/nodejs"/*; do
            if [[ -f "$f" ]]; then
                cp "$f" "${NODEJS_DIR}/"
                log_info "복사: nodejs/$(basename "$f")"
            fi
        done
    fi

    # ───────────────────────────────────────────────────────────
    # 8e. GPU 패키지 심볼릭 링크 (NVIDIA .run 파일은 OS 독립)
    # ───────────────────────────────────────────────────────────
    if [[ -d "${LEGACY_PKG_DIR}/gpu" ]]; then
        # 이미 gpu/ 심볼릭 링크 또는 디렉토리가 있으면 제거
        if [[ -e "$GPU_DIR" || -L "$GPU_DIR" ]]; then
            rm -rf "$GPU_DIR"
        fi

        ln -sfn "${LEGACY_PKG_DIR}/gpu" "$GPU_DIR"
        log_info "심볼릭 링크: gpu/ -> ${LEGACY_PKG_DIR}/gpu/"
        log_info "  (NVIDIA/ROCm .run 파일은 OS 독립적이므로 심볼릭 링크로 공유)"
    else
        log_warning "GPU 패키지 디렉토리 없음: ${LEGACY_PKG_DIR}/gpu"
    fi

    log_success "공용 리소스 연결 완료"
}

################################################################################
# Phase 9: VM 정리 (cleanup)
################################################################################

cleanup_vm() {
    # 이 함수는 정상 종료 시와 trap에서 모두 호출될 수 있음
    if [[ "$SKIP_VM_CLEANUP" == "true" ]]; then
        log_warning "--skip-vm-cleanup 플래그 활성: VM '${VM_NAME}'을 유지합니다."
        log_info "수동 정리 명령:"
        log_info "  virsh destroy ${VM_NAME}"
        log_info "  virsh undefine ${VM_NAME} --remove-all-storage"
        log_info "  rm -rf ${VM_WORK_DIR}"
        return 0
    fi

    log_phase "9" "VM 정리"

    # VM 중지
    if virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
        log_info "VM 중지 중..."
        virsh destroy "$VM_NAME" 2>/dev/null || true
        sleep 2
    fi

    # VM 정의 제거 및 디스크 삭제
    if virsh dominfo "$VM_NAME" &>/dev/null; then
        log_info "VM 정의 및 디스크 제거 중..."
        virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || {
            # --remove-all-storage 실패 시 수동 정리
            virsh undefine "$VM_NAME" 2>/dev/null || true
        }
    fi

    # 작업 디렉토리 정리 (클라우드 이미지는 재사용 가능하므로 보존)
    if [[ -d "$VM_WORK_DIR" ]]; then
        # VM 디스크 및 cloud-init ISO만 삭제, 클라우드 이미지는 보존
        rm -f "${VM_WORK_DIR}/${VM_NAME}.qcow2"
        rm -f "${VM_WORK_DIR}/cloud-init.iso"
        rm -rf "${VM_WORK_DIR}/cloud-init"
        log_info "VM 디스크 및 cloud-init 파일 삭제 완료"
        log_info "클라우드 이미지 보존: ${VM_WORK_DIR}/${CLOUD_IMAGE_FILENAME}"
    fi

    log_success "VM 정리 완료"
}

################################################################################
# cleanup trap (비정상 종료 시 VM 정리)
################################################################################

cleanup_on_exit() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo ""
        log_error "스크립트가 오류로 종료되었습니다. (exit code: ${exit_code})"

        # VM이 실행 중이면 정리 시도
        if virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
            if [[ "$SKIP_VM_CLEANUP" == "true" ]]; then
                log_warning "VM '${VM_NAME}'이 실행 중입니다. --skip-vm-cleanup 플래그로 인해 유지됩니다."
                log_info "SSH 접속: ssh -i ${SSH_PRIVATE_KEY:-~/.ssh/id_rsa} ${VM_USER}@${VM_IP:-<IP>}"
            else
                log_info "오류 발생으로 VM을 정리합니다..."
                cleanup_vm
            fi
        fi
    fi
}

trap cleanup_on_exit EXIT

################################################################################
# 요약 출력
################################################################################

print_summary() {
    local apt_count
    apt_count=$(find "$APT_DIR" -name "*.deb" 2>/dev/null | wc -l)
    local wheel_count
    wheel_count=$(find "$WHEELS_DIR" \( -name "*.whl" -o -name "*.tar.gz" \) 2>/dev/null | wc -l)
    local total_size
    total_size=$(du -sh "$SCRIPT_DIR" 2>/dev/null | cut -f1)

    echo ""
    echo "==============================================================================="
    echo "  Ubuntu 24.04 (Noble) 오프라인 패키지 수집 완료!"
    echo "==============================================================================="
    echo ""
    log_info "수집 결과 요약:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  APT 패키지:      ${apt_count}개 .deb 파일"
    echo "  Python Wheels:   ${wheel_count}개 파일"
    echo "  Slurm:           $(ls "${SLURM_DIR}/"*.tar.gz 2>/dev/null | wc -l)개 tarball"
    echo "  Munge:           $(ls "${MUNGE_DIR}/munge.key" 2>/dev/null && echo '키 존재' || echo '키 없음')"
    echo "  GPU:             $(test -L "$GPU_DIR" && echo '심볼릭 링크 설정됨' || echo '직접 복사')"
    echo "  전체 크기:       ${total_size}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "디렉토리 구조:"
    echo "  ${SCRIPT_DIR}/"
    echo "  ├── apt_packages/              # 24.04용 APT .deb 패키지"
    echo "  │   └── install_offline_packages.sh"
    echo "  ├── python_wheels/             # 24.04용 Python wheels"
    echo "  ├── slurm/                     # Slurm 프리빌드 (OS 독립)"
    echo "  │   ├── build_slurm_package.sh"
    echo "  │   └── deploy_slurm.sh"
    echo "  ├── munge/                     # Munge 인증 (OS 독립)"
    echo "  │   └── deploy_munge.sh"
    echo "  ├── nodejs/                    # Node.js 패키지"
    echo "  └── gpu/ -> ../offline_packages/gpu/  # GPU 드라이버 (심볼릭 링크)"
    echo ""
    log_info "다음 단계:"
    echo "  1. 오프라인 환경으로 전송:"
    echo "     rsync -avz ${SCRIPT_DIR}/ user@offline-cluster:/opt/offline_packages_2404/"
    echo ""
    echo "  2. 오프라인 설치 실행:"
    echo "     cd /opt/offline_packages_2404/apt_packages"
    echo "     sudo bash install_offline_packages.sh"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "==============================================================================="
    echo "  Ubuntu 24.04 (Noble) 오프라인 패키지 수집 자동화"
    echo "  호스트 OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo "==============================================================================="
    echo ""

    # 플래그 상태 출력
    if [[ "$SKIP_VM_CLEANUP" == "true" ]]; then
        log_warning "플래그: --skip-vm-cleanup (VM 정리 건너뜀)"
    fi
    if [[ "$REUSE_VM" == "true" ]]; then
        log_warning "플래그: --reuse-vm (기존 VM 재사용)"
    fi
    echo ""

    # 사전 검사
    check_root
    check_internet
    check_kvm_dependencies
    check_disk_space
    prepare_ssh_key
    echo ""

    # 확인
    log_info "VM 설정: ${VM_NAME} (${VM_VCPUS} vCPU, ${VM_RAM_MB}MB RAM, ${VM_DISK_GB}GB disk)"
    log_info "결과 디렉토리: ${SCRIPT_DIR}"
    echo ""
    if [[ "$AUTO_YES" != true ]]; then
        read -p "패키지 수집을 시작하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "사용자에 의해 취소됨"
            exit 0
        fi
    fi

    echo ""

    # Phase 1: 클라우드 이미지 다운로드
    download_cloud_image
    echo ""

    # Phase 2: cloud-init ISO 생성
    create_cloud_init_iso
    echo ""

    # Phase 3: VM 생성
    create_vm
    echo ""

    # Phase 4: VM SSH 대기
    wait_for_vm_ssh
    echo ""

    # Phase 5: 스크립트 복사
    copy_scripts_to_vm
    echo ""

    # Phase 6: VM 내 패키지 수집
    run_collection_in_vm
    echo ""

    # Phase 7: 결과 복사
    fetch_results_from_vm
    echo ""

    # Phase 8: 공용 스크립트/GPU 연결
    link_shared_resources
    echo ""

    # Phase 9: VM 정리
    cleanup_vm
    echo ""

    # 요약
    print_summary

    log_success "Ubuntu 24.04 오프라인 패키지 수집이 완료되었습니다!"
}

main "$@"
