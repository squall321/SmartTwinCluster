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

# 단일 노드 배포
deploy_to_node() {
    local node_hostname="$1"
    local node_ip="$2"
    local node_user="$3"

    log_info "[$node_hostname] Starting deployment..."

    # DRY-RUN
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[$node_hostname] DRY-RUN: Would deploy to $node_user@$node_ip"
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

    ssh "$node_user@$node_ip" bash << 'EOFREMOTE'
set -e

echo "═══════════════════════════════════════════════════════════"
echo "  Offline Package Installation"
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

echo ""
echo "✅ Offline package installation complete!"
echo ""
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
    local total_nodes=$(echo "$nodes_json" | jq '. | length')

    log_info "Total compute nodes: $total_nodes"

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
            if deploy_to_node "$hostname" "$ip" "$user"; then
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
    log_info "Next Steps:"
    echo "  1. Verify Munge authentication:"
    echo "     ssh node001 'munge -n | unmunge'"
    echo ""
    echo "  2. Check Slurm version:"
    echo "     ssh node001 'slurmd -V'"
    echo ""
    echo "  3. Start slurmd on all nodes:"
    echo "     sudo ./cluster/start_multihead.sh --phase slurm"
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

    if deploy_all_nodes "$nodes"; then
        print_summary
        log_success "All nodes deployed successfully!"
        exit 0
    else
        log_error "Some nodes failed to deploy"
        exit 1
    fi
}

main "$@"
