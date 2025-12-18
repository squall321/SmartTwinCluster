#!/bin/bash
################################################################################
# 계산 노드 오프라인 배포 스크립트
#
# 설명:
#   오프라인 패키지를 계산 노드에 자동으로 배포하고 설치합니다.
#
# 기능:
#   - YAML에서 계산 노드 목록 자동 추출
#   - rsync로 패키지 전송
#   - 원격 설치 자동화
#   - 병렬 배포 지원
#
# 사용법:
#   sudo ./deploy_to_compute_node.sh --config my_multihead_cluster.yaml
#
# 옵션:
#   --config PATH        YAML 설정 파일
#   --package-dir PATH   오프라인 패키지 디렉토리
#   --node HOSTNAME      특정 노드만 배포
#   --parallel N         병렬 배포 개수 (기본: 3)
#   --dry-run            실제 배포 없이 계획만 표시
#   --help               도움말 표시
#
# 작성자: Claude Code
# 날짜: 2025-11-17
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 기본값
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/my_multihead_cluster.yaml"
PACKAGE_DIR="${PROJECT_ROOT}/offline_packages"
SPECIFIC_NODE=""
PARALLEL=3
DRY_RUN=false

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 도움말
show_help() {
    head -n 25 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# 인자 파싱
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --package-dir)
                PACKAGE_DIR="$2"
                shift 2
                ;;
            --node)
                SPECIFIC_NODE="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
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

# 필수 파일 확인
check_prerequisites() {
    log_info "Checking prerequisites..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    if [[ ! -d "$PACKAGE_DIR" ]]; then
        log_error "Package directory not found: $PACKAGE_DIR"
        exit 1
    fi

    if ! command -v python3 &> /dev/null; then
        log_error "python3 is required"
        exit 1
    fi

    log_success "Prerequisites OK"
}

# 계산 노드 목록 추출
get_compute_nodes() {
    log_info "Extracting compute nodes from YAML..."

    local nodes_json=$(python3 << EOPY
import yaml
import json

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

nodes = []
for node in config.get('nodes', {}).get('compute_nodes', []):
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark')
    })

print(json.dumps(nodes))
EOPY
    )

    echo "$nodes_json"
}

# GlusterFS 설정 추출
get_glusterfs_config() {
    python3 << EOPY
import yaml
import json

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

# GlusterFS 설정
gluster = config.get('shared_storage', {}).get('glusterfs', {})
mount_point = gluster.get('mount_point', '/mnt/gluster')
volume_name = gluster.get('volume_name', 'shared_data')

# 첫 번째 controller IP (GlusterFS 서버)
controllers = config.get('nodes', {}).get('controllers', [])
gluster_server = controllers[0]['ip_address'] if controllers else ''

result = {
    'mount_point': mount_point,
    'volume_name': volume_name,
    'gluster_server': gluster_server
}

print(json.dumps(result))
EOPY
}

# 단일 노드 배포
deploy_to_node() {
    local node_hostname="$1"
    local node_ip="$2"
    local node_user="$3"
    local gluster_server="$4"
    local gluster_volume="$5"
    local gluster_mount="$6"

    log_info "[$node_hostname] Starting deployment..."

    # DRY-RUN
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[$node_hostname] DRY-RUN: Would deploy to $node_user@$node_ip"
        log_warning "[$node_hostname] DRY-RUN: GlusterFS: $gluster_server:/$gluster_volume -> $gluster_mount"
        return 0
    fi

    # SSH 연결 테스트
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node_user@$node_ip" "echo OK" &>/dev/null; then
        log_error "[$node_hostname] SSH connection failed"
        return 1
    fi

    log_success "[$node_hostname] SSH connection OK"

    # 원격 디렉토리 생성
    ssh "$node_user@$node_ip" "sudo mkdir -p /opt/offline_packages" || {
        log_error "[$node_hostname] Failed to create remote directory"
        return 1
    }

    # rsync로 패키지 전송
    log_info "[$node_hostname] Transferring packages (this may take 5-10 minutes)..."

    rsync -az --info=progress2 \
        --exclude='.git' \
        --exclude='*.log' \
        "$PACKAGE_DIR/" \
        "$node_user@$node_ip:/tmp/offline_packages/" || {
        log_error "[$node_hostname] Package transfer failed"
        return 1
    }

    log_success "[$node_hostname] Packages transferred"

    # 원격 설치 스크립트 실행
    log_info "[$node_hostname] Installing packages..."

    ssh "$node_user@$node_ip" bash -s "$gluster_server" "$gluster_volume" "$gluster_mount" << 'EOFREMOTE'
set -e

GLUSTER_SERVER="$1"
GLUSTER_VOLUME="$2"
GLUSTER_MOUNT="$3"

echo "═══════════════════════════════════════════════════════════"
echo "  Offline Package Installation (Compute Node)"
echo "═══════════════════════════════════════════════════════════"

# 1. APT 패키지 설치
if [[ -f /tmp/offline_packages/apt_packages/install_offline_packages.sh ]]; then
    echo ""
    echo "Step 1: Installing APT packages..."
    cd /tmp/offline_packages/apt_packages
    sudo bash install_offline_packages.sh
else
    echo "WARNING: APT packages not found"
fi

# 2. Slurm 배포
if [[ -f /tmp/offline_packages/slurm/slurm-*-prebuilt.tar.gz ]]; then
    echo ""
    echo "Step 2: Deploying Slurm..."
    cd /tmp/offline_packages/slurm
    tar -xzf slurm-*-prebuilt.tar.gz
    sudo bash deploy_slurm.sh
else
    echo "WARNING: Slurm package not found"
fi

# 3. Munge 배포
if [[ -f /tmp/offline_packages/munge/deploy_munge.sh ]]; then
    echo ""
    echo "Step 3: Deploying Munge..."
    cd /tmp/offline_packages/munge
    sudo bash deploy_munge.sh
else
    echo "WARNING: Munge package not found"
fi

# 4. GlusterFS 클라이언트 + autofs 설정
echo ""
echo "Step 4: Setting up GlusterFS client with autofs..."

if [[ -n "$GLUSTER_SERVER" ]] && [[ -n "$GLUSTER_VOLUME" ]]; then
    # GlusterFS 클라이언트 설치 확인
    if ! dpkg -l | grep -q glusterfs-client; then
        echo "  Installing glusterfs-client..."
        sudo apt-get update -qq
        sudo apt-get install -y glusterfs-client autofs 2>/dev/null || {
            echo "  WARNING: Could not install glusterfs-client (may need offline package)"
        }
    else
        echo "  glusterfs-client already installed"
    fi

    # autofs 설치 확인
    if ! dpkg -l | grep -q autofs; then
        sudo apt-get install -y autofs 2>/dev/null || {
            echo "  WARNING: Could not install autofs"
        }
    fi

    # autofs 설정
    echo "  Configuring autofs for GlusterFS..."

    # /etc/auto.master에 gluster 맵 추가
    AUTOFS_MASTER="/etc/auto.master"
    AUTOFS_GLUSTER="/etc/auto.gluster"

    # 마운트 포인트의 부모 디렉토리 (예: /mnt/gluster -> /mnt)
    MOUNT_PARENT=$(dirname "$GLUSTER_MOUNT")
    MOUNT_NAME=$(basename "$GLUSTER_MOUNT")

    # auto.master 설정 (이미 있으면 건너뜀)
    if ! grep -q "auto.gluster" "$AUTOFS_MASTER" 2>/dev/null; then
        echo "" | sudo tee -a "$AUTOFS_MASTER" > /dev/null
        echo "# GlusterFS autofs mount (added by cluster deploy)" | sudo tee -a "$AUTOFS_MASTER" > /dev/null
        echo "$MOUNT_PARENT /etc/auto.gluster --timeout=300 --ghost" | sudo tee -a "$AUTOFS_MASTER" > /dev/null
        echo "  Added entry to $AUTOFS_MASTER"
    else
        echo "  autofs entry already exists in $AUTOFS_MASTER"
    fi

    # auto.gluster 맵 파일 생성
    # 옵션 설명:
    #   -fstype=glusterfs  : GlusterFS 타입
    #   backup-volfile-servers : 백업 서버 (HA)
    #   log-level=WARNING  : 로그 레벨
    #   _netdev            : 네트워크 의존
    sudo tee "$AUTOFS_GLUSTER" > /dev/null << EOFAUTOFS
# GlusterFS autofs map
# Format: mount_name  -options  server:/volume
$MOUNT_NAME  -fstype=glusterfs,log-level=WARNING,backup-volfile-servers=$GLUSTER_SERVER  $GLUSTER_SERVER:/$GLUSTER_VOLUME
EOFAUTOFS

    echo "  Created $AUTOFS_GLUSTER"

    # autofs 재시작
    sudo systemctl enable autofs
    sudo systemctl restart autofs

    echo "  autofs service restarted"

    # 마운트 테스트 (접근하면 자동 마운트됨)
    echo "  Testing GlusterFS mount..."
    if ls "$GLUSTER_MOUNT" &>/dev/null; then
        echo "  ✓ GlusterFS mount accessible at $GLUSTER_MOUNT"
    else
        echo "  WARNING: GlusterFS mount test failed (server may be down)"
        echo "  Mount will be attempted automatically when accessed"
    fi
else
    echo "  Skipping GlusterFS setup (no server configured)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ Offline package installation complete!"
echo ""
echo "GlusterFS autofs configuration:"
echo "  - Mount point: $GLUSTER_MOUNT (auto-mount on access)"
echo "  - Server: $GLUSTER_SERVER"
echo "  - Volume: $GLUSTER_VOLUME"
echo "  - Timeout: 300s (unmount after 5min idle)"
echo ""
echo "Test with: ls $GLUSTER_MOUNT"
echo "═══════════════════════════════════════════════════════════"
EOFREMOTE

    if [[ $? -eq 0 ]]; then
        log_success "[$node_hostname] Deployment complete!"
        return 0
    else
        log_error "[$node_hostname] Deployment failed"
        return 1
    fi
}

# 병렬 배포
deploy_all_nodes() {
    local nodes_json="$1"
    local gluster_server="$2"
    local gluster_volume="$3"
    local gluster_mount="$4"
    local total_nodes=$(echo "$nodes_json" | jq '. | length')

    log_info "Total compute nodes: $total_nodes"
    log_info "GlusterFS: $gluster_server:/$gluster_volume -> $gluster_mount"

    if [[ "$SPECIFIC_NODE" != "" ]]; then
        log_info "Deploying to specific node only: $SPECIFIC_NODE"
    fi

    local success_count=0
    local failed_count=0
    local pids=()

    # 노드 순회
    while IFS= read -r node_json; do
        local hostname=$(echo "$node_json" | jq -r '.hostname')
        local ip=$(echo "$node_json" | jq -r '.ip')
        local user=$(echo "$node_json" | jq -r '.user')

        # 특정 노드만 배포
        if [[ -n "$SPECIFIC_NODE" ]] && [[ "$hostname" != "$SPECIFIC_NODE" ]]; then
            continue
        fi

        # 병렬 제한
        while [[ ${#pids[@]} -ge $PARALLEL ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[$i]'
                fi
            done
            pids=("${pids[@]}")  # Re-index array
            sleep 1
        done

        # 백그라운드 배포
        (
            if deploy_to_node "$hostname" "$ip" "$user" "$gluster_server" "$gluster_volume" "$gluster_mount"; then
                echo "SUCCESS:$hostname" >> /tmp/deploy_results_$$.txt
            else
                echo "FAILED:$hostname" >> /tmp/deploy_results_$$.txt
            fi
        ) &
        pids+=($!)

        log_info "Launched deployment for $hostname (PID: $!)"

    done < <(echo "$nodes_json" | jq -c '.[]')

    # 모든 배포 완료 대기
    log_info "Waiting for all deployments to complete..."

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    # 결과 집계
    if [[ -f /tmp/deploy_results_$$.txt ]]; then
        success_count=$(grep -c "^SUCCESS:" /tmp/deploy_results_$$.txt 2>/dev/null || echo 0)
        failed_count=$(grep -c "^FAILED:" /tmp/deploy_results_$$.txt 2>/dev/null || echo 0)
        rm -f /tmp/deploy_results_$$.txt
    fi

    echo ""
    log_info "Deployment Summary:"
    log_success "  Successful: $success_count nodes"

    if [[ $failed_count -gt 0 ]]; then
        log_error "  Failed: $failed_count nodes"
        return 1
    fi

    return 0
}

# 요약
print_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          계산 노드 배포 완료!                             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "설치된 항목:"
    echo "  ✓ APT 패키지 (오프라인)"
    echo "  ✓ Slurm (slurmd)"
    echo "  ✓ Munge 인증"
    echo "  ✓ GlusterFS 클라이언트 + autofs"
    echo ""
    log_info "Next Steps:"
    echo "  1. Verify Munge authentication:"
    echo "     ssh node001 'munge -n | unmunge'"
    echo ""
    echo "  2. Check Slurm version:"
    echo "     ssh node001 'slurmd -V'"
    echo ""
    echo "  3. Test GlusterFS mount (autofs):"
    echo "     ssh node001 'ls /mnt/gluster'"
    echo ""
    echo "  4. Start slurmd on all nodes:"
    echo "     sudo ./cluster/start_multihead.sh --phase slurm"
    echo ""
    log_info "autofs 특징:"
    echo "  - 부팅 시 마운트하지 않음 (부팅 실패 방지)"
    echo "  - 접근 시 자동 마운트"
    echo "  - 5분 미사용 시 자동 언마운트"
    echo "  - Controller 다운 시에도 부팅 정상"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          계산 노드 오프라인 배포                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites

    log_info "Config:       $CONFIG_FILE"
    log_info "Package Dir:  $PACKAGE_DIR"
    log_info "Parallel:     $PARALLEL"
    echo ""

    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi

    local nodes=$(get_compute_nodes)

    # GlusterFS 설정 추출
    log_info "Extracting GlusterFS configuration..."
    local gluster_config=$(get_glusterfs_config)
    local gluster_server=$(echo "$gluster_config" | jq -r '.gluster_server')
    local gluster_volume=$(echo "$gluster_config" | jq -r '.volume_name')
    local gluster_mount=$(echo "$gluster_config" | jq -r '.mount_point')

    log_info "GlusterFS Server: $gluster_server"
    log_info "GlusterFS Volume: $gluster_volume"
    log_info "Mount Point:      $gluster_mount"
    echo ""

    if deploy_all_nodes "$nodes" "$gluster_server" "$gluster_volume" "$gluster_mount"; then
        print_summary
        log_success "All nodes deployed successfully!"
        exit 0
    else
        log_error "Some nodes failed to deploy"
        exit 1
    fi
}

main "$@"
