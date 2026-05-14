#!/bin/bash
# ============================================================================
# Phase 6: GPU Driver Installation (NVIDIA/AMD ROCm)
# ============================================================================
# GPU가 있는 노드에 NVIDIA 또는 AMD ROCm 드라이버를 설치합니다.
# 오프라인 패키지 지원
#
# 사용법:
#   ./phase6_gpu.sh --config <yaml_file> [--dry-run] [--nvidia-only] [--rocm-only]
#
# YAML 설정 예시:
#   nodes:
#     viz_nodes:
#       - hostname: viz-node001
#         hardware:
#           gpus: 1
#           gpu_type: nvidia  # 또는 amd
#           gres: gpu:nvidia:1
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# OS 감지 기반 오프라인 패키지 디렉토리 설정
source "${PROJECT_ROOT}/cluster/utils/detect_os.sh"
detect_os_version
set_offline_pkg_dir "$PROJECT_ROOT"

CONFIG_PATH=""
DRY_RUN=false
NVIDIA_ONLY=false
ROCM_ONLY=false

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase() { echo -e "${CYAN}[PHASE 6]${NC} $1"; }

# ============================================================================
# 도움말
# ============================================================================
show_help() {
    cat << EOF
Phase 6: GPU Driver Installation

사용법:
  $0 --config <yaml_file> [옵션]

옵션:
  --config <file>   YAML 설정 파일 경로 (필수)
  --dry-run         실제 설치 없이 계획만 출력
  --nvidia-only     NVIDIA GPU만 설치
  --rocm-only       AMD ROCm만 설치
  --help            도움말 출력

예시:
  $0 --config my_cluster.yaml
  $0 --config my_cluster.yaml --nvidia-only
  $0 --config my_cluster.yaml --dry-run

YAML 설정:
  nodes:
    viz_nodes:
      - hostname: viz-node001
        hardware:
          gpus: 1
          gpu_type: nvidia  # nvidia 또는 amd
          gres: gpu:nvidia:1
EOF
}

# ============================================================================
# 인자 파싱
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                CONFIG_PATH="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --nvidia-only)
                NVIDIA_ONLY=true
                shift
                ;;
            --rocm-only)
                ROCM_ONLY=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$CONFIG_PATH" ]]; then
        log_error "설정 파일이 지정되지 않았습니다"
        show_help
        exit 1
    fi

    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error "설정 파일이 존재하지 않습니다: $CONFIG_PATH"
        exit 1
    fi
}

# ============================================================================
# per-node SSH 인증 설정 (phase8 setup_node_ssh 동일 패턴)
# 호출 후 SSH_CMD / SCP_CMD 전역변수가 세팅됨
# ============================================================================
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6 2>/dev/null || echo "")
SSH_PASSWORD=""
HAS_SSHPASS=false

_SSH_BASE="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o LogLevel=ERROR"
_SSH_BASE_PASS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o LogLevel=ERROR -o BatchMode=no"

SSH_CMD="ssh -n $_SSH_BASE"
SCP_CMD="scp $_SSH_BASE"

load_ssh_auth() {
    SSH_PASSWORD=$(python3 -c "
import yaml
with open('$CONFIG_PATH') as f:
    c = yaml.safe_load(f)
print(c.get('cluster_info', {}).get('ssh_password', ''))
" 2>/dev/null || echo "")
    command -v sshpass &>/dev/null && HAS_SSHPASS=true || true
}

setup_node_ssh() {
    local user="$1" ip="$2"
    local user_home
    user_home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || echo "")
    for _k in "${user_home}/.ssh/id_ed25519" "${user_home}/.ssh/id_rsa" \
              "${ORIGINAL_HOME}/.ssh/id_ed25519" "${ORIGINAL_HOME}/.ssh/id_rsa"; do
        [[ -f "$_k" ]] || continue
        if ssh -n -i "$_k" -o BatchMode=yes -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no "$user@$ip" "exit" &>/dev/null; then
            SSH_CMD="ssh -n -i $_k -o BatchMode=yes $_SSH_BASE"
            SCP_CMD="scp -i $_k $_SSH_BASE"
            return 0
        fi
    done
    if [[ -n "$SSH_PASSWORD" && "$HAS_SSHPASS" == "true" ]]; then
        export SSHPASS="$SSH_PASSWORD"
        if sshpass -e ssh -n $_SSH_BASE_PASS "$user@$ip" "exit" &>/dev/null; then
            SSH_CMD="sshpass -e ssh -n $_SSH_BASE_PASS"
            SCP_CMD="sshpass -e scp $_SSH_BASE_PASS"
            return 0
        fi
    fi
    return 1
}

# ============================================================================
# GPU가 있는 노드 목록 가져오기
# ============================================================================
get_gpu_nodes() {
    python3 << EOPY
import yaml
import sys

try:
    with open('$CONFIG_PATH', 'r') as f:
        config = yaml.safe_load(f)

    nodes = config.get('nodes', {})

    # viz_nodes와 compute_nodes 모두 확인
    all_nodes = []
    all_nodes.extend(nodes.get('viz_nodes', []))
    all_nodes.extend(nodes.get('compute_nodes', []))

    for node in all_nodes:
        hardware = node.get('hardware', {})
        gpus = hardware.get('gpus', 0)
        gpu_type = hardware.get('gpu_type', '').lower()

        if gpus > 0 and gpu_type:
            hostname = node.get('hostname', '')
            ip = node.get('ip_address', '')
            user = node.get('ssh_user', 'root')

            if hostname and ip:
                print(f"{hostname}|{ip}|{user}|{gpu_type}|{gpus}")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOPY
}

# ============================================================================
# 노드에 GPU가 물리적으로 있는지 확인
# ============================================================================
check_gpu_hardware() {
    local ip="$1"
    local user="$2"
    local expected_type="$3"

    local result
    result=$($SSH_CMD "$user@$ip" "
        # NVIDIA GPU 확인
        nvidia_count=\$(lspci | grep -ci 'nvidia' 2>/dev/null || echo 0)

        # AMD GPU 확인 (VGA 중 AMD/ATI, QXL 제외)
        amd_count=\$(lspci | grep -i 'vga\|3d' | grep -ci 'amd\|ati\|radeon' 2>/dev/null || echo 0)
        # QXL 가상 그래픽 제외
        qxl_count=\$(lspci | grep -ci 'qxl' 2>/dev/null || echo 0)
        amd_count=\$((amd_count > qxl_count ? amd_count - qxl_count : 0))

        echo \"nvidia:\$nvidia_count,amd:\$amd_count\"
    " 2>/dev/null)

    echo "$result"
}

# ============================================================================
# 드라이버 설치 여부 확인
# ============================================================================
check_nvidia_installed() {
    local ip="$1"
    local user="$2"

    # nvidia-smi가 정상 동작하면 설치됨
    $SSH_CMD "$user@$ip" "nvidia-smi &>/dev/null && echo 'installed'" 2>/dev/null | grep -q "installed"
}

check_rocm_installed() {
    local ip="$1"
    local user="$2"

    # rocm-smi가 정상 동작하면 설치됨
    $SSH_CMD "$user@$ip" "rocm-smi &>/dev/null && echo 'installed'" 2>/dev/null | grep -q "installed"
}

# ============================================================================
# NVIDIA 드라이버 설치 (원격) - apt 방식
# ============================================================================
install_nvidia_driver() {
    local ip="$1"
    local user="$2"
    local hostname="$3"

    local gpu_pkg_dir="${OFFLINE_PKG_DIR}/gpu/nvidia"

    # 이미 설치되어 있는지 확인
    if check_nvidia_installed "$ip" "$user"; then
        local driver_info
        driver_info=$(ssh -o ConnectTimeout=10 "$user@$ip" "nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1" || echo "unknown")
        log_success "[$hostname] NVIDIA 드라이버 이미 설치됨 (버전: $driver_info) - 건너뜀"
        return 0
    fi

    log_info "[$hostname] NVIDIA 드라이버 설치 중..."

    # deb 패키지 확인
    local deb_count
    deb_count=$(ls -1 "$gpu_pkg_dir"/*.deb 2>/dev/null | wc -l)

    if [[ "$deb_count" -eq 0 ]]; then
        # .run 파일 확인 (deb 없을 때 fallback)
        local run_file
        run_file=$(ls -1 "$gpu_pkg_dir"/NVIDIA-Linux-*.run 2>/dev/null | head -1)

        if [[ -n "$run_file" ]]; then
            log_info "[$hostname] .run 파일로 NVIDIA 드라이버 설치: $(basename $run_file)"

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] scp $run_file $user@$ip:/tmp/"
                log_info "[DRY-RUN] ssh $user@$ip 'bash /tmp/$(basename $run_file) --silent'"
            else
                # Nouveau 확인
                local nouveau_active
                nouveau_active=$(ssh -o ConnectTimeout=10 "$user@$ip" "lsmod | grep -c nouveau 2>/dev/null || echo 0")
                if [[ "$nouveau_active" -gt 0 ]]; then
                    ssh "$user@$ip" "
                        echo 'blacklist nouveau' > /etc/modprobe.d/blacklist-nouveau.conf
                        echo 'options nouveau modeset=0' >> /etc/modprobe.d/blacklist-nouveau.conf
                        update-initramfs -u
                    "
                    log_warning "[$hostname] Nouveau 비활성화됨 - 재부팅 후 다시 실행 필요"
                    return 100
                fi

                # .run 파일 전송 및 설치
                $SCP_CMD -o ConnectTimeout=60 "$run_file" "$user@$ip:/tmp/" || {
                    log_error "[$hostname] .run 파일 전송 실패"
                    return 1
                }

                # GPU 드라이버 설치는 10분+ 소요 가능 — 1200초 타임아웃
                timeout 1200 ssh -o ConnectTimeout=30 -o ServerAliveInterval=60 -o ServerAliveCountMax=20 "$user@$ip" "
                    sudo bash /tmp/$(basename $run_file) --silent --no-questions --ui=none 2>&1
                    rm -f /tmp/$(basename $run_file)
                "
                local exit_code=$?
                if [[ $exit_code -eq 0 ]]; then
                    log_success "[$hostname] NVIDIA 드라이버 설치 완료 (.run)"
                else
                    log_error "[$hostname] NVIDIA 드라이버 .run 설치 실패 (exit: $exit_code)"
                    return 1
                fi
            fi
            return 0
        fi

        log_warning "[$hostname] NVIDIA deb/run 패키지 없음: $gpu_pkg_dir"
        log_info "  온라인 apt 설치 시도..."

        # 온라인 설치 (apt 사용)
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] ssh $user@$ip 'apt install -y nvidia-driver-550'"
        else
            $SSH_CMD "$user@$ip" "
                # Nouveau 비활성화
                if lsmod | grep -q nouveau; then
                    echo 'blacklist nouveau' > /etc/modprobe.d/blacklist-nouveau.conf
                    echo 'options nouveau modeset=0' >> /etc/modprobe.d/blacklist-nouveau.conf
                    update-initramfs -u
                    echo 'Nouveau 비활성화됨 - 재부팅 후 다시 실행 필요'
                    exit 100
                fi

                apt-get update
                DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nvidia-driver-550 || {
                    echo 'NVIDIA 드라이버 설치 실패'
                    exit 1
                }
                # NetworkManager 자동 활성화 방지 (netplan 정책 유지)
                if systemctl is-active --quiet NetworkManager 2>/dev/null && ls /etc/netplan/*.yaml &>/dev/null; then
                    echo '[정책 보호] NetworkManager 비활성화 (netplan 유지)'
                    systemctl disable --now NetworkManager 2>/dev/null || true
                    systemctl mask NetworkManager 2>/dev/null || true
                fi
            "
            local exit_code=$?
            if [[ $exit_code -eq 100 ]]; then
                log_warning "[$hostname] 재부팅 필요 (Nouveau 비활성화)"
                return 100
            elif [[ $exit_code -eq 0 ]]; then
                log_success "[$hostname] NVIDIA 드라이버 설치 완료 (온라인 apt)"
            else
                log_error "[$hostname] NVIDIA 드라이버 설치 실패"
                return 1
            fi
        fi
        return 0
    fi

    # 오프라인 로컬 APT 저장소를 통한 설치 (deb 패키지)
    log_info "[$hostname] 오프라인 로컬 APT 저장소로 NVIDIA 드라이버 설치 중..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] deb 패키지를 로컬 APT 저장소에 등록 후 apt install"
    else
        # Nouveau 확인
        local nouveau_active
        nouveau_active=$(ssh -o ConnectTimeout=10 "$user@$ip" "lsmod | grep -c nouveau 2>/dev/null || echo 0")
        if [[ "$nouveau_active" -gt 0 ]]; then
            $SSH_CMD "$user@$ip" "
                echo 'blacklist nouveau' > /etc/modprobe.d/blacklist-nouveau.conf
                echo 'options nouveau modeset=0' >> /etc/modprobe.d/blacklist-nouveau.conf
                update-initramfs -u
            "
            log_warning "[$hostname] Nouveau 비활성화됨 - 재부팅 후 다시 실행 필요"
            return 100
        fi

        # deb 패키지를 로컬 APT 저장소 디렉토리로 전송
        local remote_repo_dir="/opt/offline_packages/gpu/nvidia"
        $SSH_CMD "$user@$ip" "sudo mkdir -p $remote_repo_dir"
        $SCP_CMD -o ConnectTimeout=60 "$gpu_pkg_dir"/*.deb "$user@$ip:/tmp/" || {
            log_error "[$hostname] 파일 전송 실패"
            return 1
        }
        $SSH_CMD "$user@$ip" "sudo mv /tmp/*.deb $remote_repo_dir/ 2>/dev/null || true"

        # 로컬 APT 저장소 등록 및 설치
        $SSH_CMD "$user@$ip" "
            cd $remote_repo_dir
            sudo dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz

            # 로컬 저장소 등록
            echo 'deb [trusted=yes] file://$remote_repo_dir ./' | sudo tee /etc/apt/sources.list.d/nvidia-local.list > /dev/null

            sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/nvidia-local.list -o Dir::Etc::sourceparts='-' -o APT::Get::List-Cleanup='0' 2>/dev/null

            echo '=== NVIDIA 드라이버 설치 ==='
            # 운영팀 정책 준수: --no-install-recommends 로 NetworkManager 등 부가 의존성 차단
            DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --allow-unauthenticated --no-install-recommends nvidia-driver-550 || {
                echo 'WARNING: apt install 실패, dpkg fallback 시도'
                sudo dpkg -i $remote_repo_dir/*.deb 2>/dev/null || true
                sudo apt-get -f install --no-install-recommends -y 2>/dev/null || true
            }

            # NVIDIA 설치 후 NetworkManager가 자동 활성화되었으면 원복 (netplan 정책 유지)
            if systemctl is-active --quiet NetworkManager 2>/dev/null && \
               ls /etc/netplan/*.yaml &>/dev/null; then
                echo '[정책 보호] NetworkManager 자동 활성화 감지 → 비활성화 (netplan 유지)'
                sudo systemctl disable --now NetworkManager 2>/dev/null || true
                sudo systemctl mask NetworkManager 2>/dev/null || true
            fi
        "

        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            log_error "[$hostname] NVIDIA 드라이버 설치 실패"
            return 1
        fi

        log_success "[$hostname] NVIDIA 드라이버 설치 완료 (로컬 APT 저장소)"
    fi
}

# ============================================================================
# AMD ROCm 설치 (원격)
# ============================================================================
install_rocm_driver() {
    local ip="$1"
    local user="$2"
    local hostname="$3"

    local gpu_pkg_dir="${OFFLINE_PKG_DIR}/gpu/rocm"

    # 이미 설치되어 있는지 확인
    if check_rocm_installed "$ip" "$user"; then
        local rocm_info
        rocm_info=$(ssh -o ConnectTimeout=10 "$user@$ip" "cat /opt/rocm/.info/version 2>/dev/null || echo 'unknown'")
        log_success "[$hostname] AMD ROCm 이미 설치됨 (버전: $rocm_info) - 건너뜀"
        return 0
    fi

    log_info "[$hostname] AMD ROCm 설치 중..."

    # amdgpu-install 파일 확인
    local amdgpu_file
    amdgpu_file=$(ls -1 "$gpu_pkg_dir"/amdgpu-install_*.deb 2>/dev/null | head -1)

    if [[ -z "$amdgpu_file" ]] || [[ ! -f "$amdgpu_file" ]]; then
        log_warning "[$hostname] ROCm 패키지 없음: $gpu_pkg_dir"
        log_info "  온라인 설치 시도..."

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] ssh $user@$ip 'amdgpu-install --usecase=rocm'"
        else
            $SSH_CMD "$user@$ip" "
                # ROCm 저장소 추가 및 설치
                wget -q https://repo.radeon.com/amdgpu-install/6.0.2/ubuntu/${OS_CODENAME}/amdgpu-install_6.0.60002-1_all.deb -O /tmp/amdgpu-install.deb
                dpkg -i /tmp/amdgpu-install.deb
                amdgpu-install --usecase=rocm --no-dkms -y
                rm -f /tmp/amdgpu-install.deb
            " && log_success "[$hostname] ROCm 설치 완료 (온라인)" || {
                log_error "[$hostname] ROCm 설치 실패"
                return 1
            }
        fi
        return 0
    fi

    # 오프라인 설치
    log_info "[$hostname] 오프라인 패키지 전송 중..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] scp $gpu_pkg_dir/*.deb $user@$ip:/tmp/rocm/"
        log_info "[DRY-RUN] ssh $user@$ip 'dpkg -i /tmp/rocm/*.deb'"
    else
        $SSH_CMD "$user@$ip" "mkdir -p /tmp/rocm"
        $SCP_CMD -o ConnectTimeout=30 "$gpu_pkg_dir"/*.deb "$user@$ip:/tmp/rocm/" || {
            log_error "[$hostname] 파일 전송 실패"
            return 1
        }

        $SSH_CMD "$user@$ip" "
            cd /tmp/rocm
            dpkg -i amdgpu-install_*.deb 2>/dev/null || apt-get -f install -y
            dpkg -i *.deb 2>/dev/null || apt-get -f install -y

            # 환경변수 설정
            cat > /etc/profile.d/rocm.sh << 'EOF'
export PATH=/opt/rocm/bin:\$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:\$LD_LIBRARY_PATH
EOF

            # 사용자 그룹 추가
            for u in \$(getent passwd | awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1}'); do
                usermod -aG render,video \"\$u\" 2>/dev/null || true
            done

            rm -rf /tmp/rocm
        " && log_success "[$hostname] ROCm 설치 완료" || {
            log_error "[$hostname] ROCm 설치 실패"
            return 1
        }
    fi
}

# ============================================================================
# 설치 확인
# ============================================================================
verify_gpu_installation() {
    local ip="$1"
    local user="$2"
    local hostname="$3"
    local gpu_type="$4"

    log_info "[$hostname] GPU 설치 확인 중..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] GPU 확인 건너뜀"
        return 0
    fi

    local result
    if [[ "$gpu_type" == "nvidia" ]]; then
        result=$(ssh -o ConnectTimeout=10 "$user@$ip" "nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo 'FAILED'")
        if [[ "$result" != "FAILED" ]]; then
            log_success "[$hostname] NVIDIA GPU: $result"
            return 0
        else
            log_warning "[$hostname] nvidia-smi 실행 실패 (재부팅 필요할 수 있음)"
            return 1
        fi
    else
        result=$(ssh -o ConnectTimeout=10 "$user@$ip" "rocm-smi --showproductname 2>/dev/null | head -5 || echo 'FAILED'")
        if [[ "$result" != "FAILED" ]]; then
            log_success "[$hostname] AMD GPU: $result"
            return 0
        else
            log_warning "[$hostname] rocm-smi 실행 실패"
            return 1
        fi
    fi
}

# ============================================================================
# 메인
# ============================================================================
main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║  Phase 6: GPU Driver Installation                            ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Config: $CONFIG_PATH"
    log_info "Dry-run: $DRY_RUN"
    load_ssh_auth
    echo ""

    # GPU 노드 목록 가져오기
    log_phase "=== GPU 노드 검색 ==="
    local gpu_nodes
    gpu_nodes=$(get_gpu_nodes)

    if [[ -z "$gpu_nodes" ]]; then
        log_warning "GPU가 설정된 노드가 없습니다"
        log_info "YAML에서 hardware.gpus와 hardware.gpu_type을 설정하세요"
        exit 0
    fi

    echo ""
    log_info "GPU 노드 목록:"
    echo "$gpu_nodes" | while IFS='|' read -r hostname ip user gpu_type gpu_count; do
        echo "  - $hostname ($ip): ${gpu_type^^} x$gpu_count"
    done
    echo ""

    # 각 노드에 드라이버 설치
    log_phase "=== GPU 드라이버 설치 ==="

    local success_count=0
    local fail_count=0
    local reboot_needed=""

    while IFS='|' read -r hostname ip user gpu_type gpu_count; do
        [[ -z "$hostname" ]] && continue

        echo ""
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_phase "처리 중: $hostname ($ip) - ${gpu_type^^}"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # 필터 확인
        if [[ "$NVIDIA_ONLY" == "true" ]] && [[ "$gpu_type" != "nvidia" ]]; then
            log_info "[$hostname] 건너뜀 (--nvidia-only)"
            continue
        fi
        if [[ "$ROCM_ONLY" == "true" ]] && [[ "$gpu_type" != "amd" ]]; then
            log_info "[$hostname] 건너뜀 (--rocm-only)"
            continue
        fi

        # SSH 연결 확인 (phase8 패턴: 키 우선, sshpass fallback)
        if ! setup_node_ssh "$user" "$ip"; then
            log_error "[$hostname] SSH 연결 실패"
            ((fail_count++))
            continue
        fi

        # 물리적 GPU 확인
        local hw_check
        hw_check=$(check_gpu_hardware "$ip" "$user" "$gpu_type")
        log_info "[$hostname] 하드웨어 감지: $hw_check"

        # 드라이버 설치
        local install_result=0
        if [[ "$gpu_type" == "nvidia" ]]; then
            install_nvidia_driver "$ip" "$user" "$hostname"
            install_result=$?
        elif [[ "$gpu_type" == "amd" ]]; then
            install_rocm_driver "$ip" "$user" "$hostname"
            install_result=$?
        else
            log_warning "[$hostname] 지원하지 않는 GPU 타입: $gpu_type"
            continue
        fi

        if [[ $install_result -eq 100 ]]; then
            reboot_needed="$reboot_needed $hostname"
            ((success_count++))
        elif [[ $install_result -eq 0 ]]; then
            verify_gpu_installation "$ip" "$user" "$hostname" "$gpu_type"
            ((success_count++))
        else
            ((fail_count++))
        fi

    done <<< "$gpu_nodes"

    # 요약
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_phase "설치 요약"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "성공: $success_count"
    log_info "실패: $fail_count"

    if [[ -n "$reboot_needed" ]]; then
        log_warning "재부팅 필요:$reboot_needed"
        log_info "재부팅 후 이 스크립트를 다시 실행하세요"
    fi

    echo ""
    if [[ $fail_count -eq 0 ]]; then
        log_success "Phase 6: GPU Driver Installation 완료!"
    else
        log_warning "Phase 6: 일부 노드에서 설치 실패"
    fi
}

main "$@"
