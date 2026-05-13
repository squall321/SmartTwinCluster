#!/bin/bash
################################################################################
# Slurm 설정 전체 노드 수정 스크립트
#
# 문제:
#   컴퓨트 노드들에 apt 패키지용 구버전 slurm.conf가 남아있어
#   PluginDir=/usr/lib/x86_64-linux-gnu/slurm-wlm 에러 발생
#
# 해결:
#   1. 컨트롤러의 최신 slurm.conf를 모든 컴퓨트 노드에 배포
#   2. PluginDir 경로를 /usr/local/slurm/lib/slurm으로 수정
#   3. slurmd 서비스 재시작
#
# 사용법:
#   sudo ./fix_slurm_config_all_nodes.sh [OPTIONS]
#
# 옵션:
#   --config PATH        YAML 설정 파일 (기본: my_multihead_cluster.yaml)
#   --node HOSTNAME      특정 노드만 수정
#   --dry-run            실제 수정 없이 확인만
#   --parallel N         병렬 처리 수 (기본: 5)
#   --help               도움말 표시
#
# 작성자: Claude Code
# 날짜: 2026-01-02
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 기본값
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/my_multihead_cluster.yaml"
SPECIFIC_NODE=""
DRY_RUN=false
PARALLEL=5
SSH_USER="${SSH_USER:-stcx}"

# Slurm 경로 설정
SLURM_PREFIX="/usr/local/slurm"
SLURM_PLUGIN_DIR="${SLURM_PREFIX}/lib/slurm"
SLURM_CONFIG_DIR="/etc/slurm"

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# 도움말
show_help() {
    head -n 28 "$0" | grep "^#" | sed 's/^# \?//'
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
            --node)
                SPECIFIC_NODE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --parallel)
                PARALLEL="$2"
                shift 2
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

    # slurm.conf 존재 확인
    if [[ ! -f "${SLURM_CONFIG_DIR}/slurm.conf" ]]; then
        log_error "slurm.conf not found at ${SLURM_CONFIG_DIR}/slurm.conf"
        log_info "Please ensure Slurm is configured on the controller first"
        exit 1
    fi

    # YAML 설정 파일 확인 (선택적)
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warning "Config file not found: $CONFIG_FILE"
        log_info "Will require --node option to specify target nodes"
        if [[ -z "$SPECIFIC_NODE" ]]; then
            log_error "Either provide --config or --node option"
            exit 1
        fi
    fi

    log_success "Prerequisites OK"
}

# 컴퓨트 노드 목록 추출
get_compute_nodes() {
    if [[ -n "$SPECIFIC_NODE" ]]; then
        echo "$SPECIFIC_NODE"
        return
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Cannot extract nodes: Config file not found"
        exit 1
    fi

    python3 << EOPY
import yaml

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

nodes = []
for node in config.get('nodes', {}).get('compute_nodes', []):
    nodes.append(node['hostname'])

print('\n'.join(nodes))
EOPY
}

# slurm.conf 수정 함수 (PluginDir 및 경로 수정)
fix_slurm_conf() {
    local conf_file="$1"
    local backup_file="${conf_file}.bak.$(date +%Y%m%d_%H%M%S)"

    log_info "Fixing slurm.conf: $conf_file"

    # 백업 생성
    cp "$conf_file" "$backup_file"
    log_info "Backup created: $backup_file"

    # 수정할 패턴들
    # 1. PluginDir 경로 수정 (apt 패키지 -> 소스 빌드)
    sed -i "s|PluginDir=.*/slurm-wlm.*|PluginDir=${SLURM_PLUGIN_DIR}|g" "$conf_file"
    sed -i "s|PluginDir=/usr/lib/x86_64-linux-gnu/slurm-wlm|PluginDir=${SLURM_PLUGIN_DIR}|g" "$conf_file"
    sed -i "s|PluginDir=/usr/lib64/slurm|PluginDir=${SLURM_PLUGIN_DIR}|g" "$conf_file"

    # 2. SlurmctldPidFile 경로 수정
    sed -i "s|SlurmctldPidFile=.*|SlurmctldPidFile=/run/slurm/slurmctld.pid|g" "$conf_file"

    # 3. SlurmdPidFile 경로 수정
    sed -i "s|SlurmdPidFile=.*|SlurmdPidFile=/run/slurm/slurmd.pid|g" "$conf_file"

    # 4. PluginDir 라인이 없으면 추가
    if ! grep -q "^PluginDir=" "$conf_file"; then
        echo "PluginDir=${SLURM_PLUGIN_DIR}" >> "$conf_file"
        log_info "Added PluginDir line"
    fi

    # 변경 확인
    local new_plugin_dir=$(grep "^PluginDir=" "$conf_file" | head -1 || echo "")
    log_success "PluginDir set to: $new_plugin_dir"
}

# 단일 노드 수정
fix_single_node() {
    local node="$1"
    local result_file="/tmp/fix_slurm_result_${node}_$$.txt"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_step "[$node] Starting configuration fix..."

    # DRY-RUN
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[$node] DRY-RUN: Would fix slurm.conf and restart slurmd"
        echo "SUCCESS" > "$result_file"
        return 0
    fi

    # SSH 연결 테스트
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node" "echo OK" &>/dev/null; then
        log_error "[$node] SSH connection failed"
        echo "FAILED:SSH" > "$result_file"
        return 1
    fi

    # 원격에서 수정 스크립트 실행
    ssh -o ConnectTimeout=30 "$SSH_USER@$node" bash -s << 'EOFREMOTE'
set -e

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SLURM_PREFIX="/usr/local/slurm"
SLURM_PLUGIN_DIR="${SLURM_PREFIX}/lib/slurm"
SLURM_CONFIG_DIR="/etc/slurm"
SLURM_LOCAL_CONFIG="${SLURM_PREFIX}/etc"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Slurm Configuration Fix - $(hostname)"
echo "═══════════════════════════════════════════════════════════"
echo ""

# 1. PluginDir 디렉토리 존재 확인
log_info "Checking Slurm installation..."
if [[ ! -d "$SLURM_PLUGIN_DIR" ]]; then
    log_error "Slurm plugin directory not found: $SLURM_PLUGIN_DIR"
    log_error "Please install Slurm first using deploy_slurm.sh"
    exit 1
fi
log_success "Slurm plugin directory exists: $SLURM_PLUGIN_DIR"

# 플러그인 파일 확인
PLUGIN_COUNT=$(ls -1 "$SLURM_PLUGIN_DIR"/*.so 2>/dev/null | wc -l || echo 0)
log_info "Found $PLUGIN_COUNT plugin files in $SLURM_PLUGIN_DIR"

# 2. slurm.conf 수정
fix_conf() {
    local conf_file="$1"

    if [[ ! -f "$conf_file" ]]; then
        log_warning "Config file not found: $conf_file"
        return 1
    fi

    log_info "Fixing: $conf_file"

    # 백업
    sudo cp "$conf_file" "${conf_file}.bak.$(date +%Y%m%d_%H%M%S)"

    # PluginDir 수정 (다양한 패턴 처리)
    sudo sed -i "s|PluginDir=.*/slurm-wlm.*|PluginDir=${SLURM_PLUGIN_DIR}|g" "$conf_file"
    sudo sed -i "s|PluginDir=/usr/lib/x86_64-linux-gnu/slurm-wlm|PluginDir=${SLURM_PLUGIN_DIR}|g" "$conf_file"
    sudo sed -i "s|PluginDir=/usr/lib64/slurm|PluginDir=${SLURM_PLUGIN_DIR}|g" "$conf_file"
    sudo sed -i "s|PluginDir=/usr/lib/slurm|PluginDir=${SLURM_PLUGIN_DIR}|g" "$conf_file"

    # PidFile 경로 수정
    sudo sed -i "s|SlurmctldPidFile=.*|SlurmctldPidFile=/run/slurm/slurmctld.pid|g" "$conf_file"
    sudo sed -i "s|SlurmdPidFile=.*|SlurmdPidFile=/run/slurm/slurmd.pid|g" "$conf_file"

    # PluginDir 라인이 없으면 추가
    if ! grep -q "^PluginDir=" "$conf_file"; then
        echo "PluginDir=${SLURM_PLUGIN_DIR}" | sudo tee -a "$conf_file" > /dev/null
        log_info "Added PluginDir line"
    fi

    # 결과 확인
    local plugin_dir_value=$(grep "^PluginDir=" "$conf_file" | head -1)
    log_success "Updated: $plugin_dir_value"
}

# /etc/slurm/slurm.conf 수정
if [[ -f "${SLURM_CONFIG_DIR}/slurm.conf" ]]; then
    fix_conf "${SLURM_CONFIG_DIR}/slurm.conf"
fi

# /usr/local/slurm/etc/slurm.conf 수정 (있는 경우)
if [[ -f "${SLURM_LOCAL_CONFIG}/slurm.conf" ]]; then
    fix_conf "${SLURM_LOCAL_CONFIG}/slurm.conf"
fi

# 3. /run/slurm 디렉토리 생성
log_info "Creating /run/slurm directory..."
sudo mkdir -p /run/slurm
sudo chown slurm:slurm /run/slurm
sudo chmod 755 /run/slurm
log_success "/run/slurm directory ready"

# 4. slurmd 서비스 파일 확인/수정
log_info "Checking slurmd systemd service..."
SLURMD_SERVICE="/etc/systemd/system/slurmd.service"

if [[ -f "$SLURMD_SERVICE" ]]; then
    # Type=simple 확인
    if grep -q "Type=forking" "$SLURMD_SERVICE"; then
        log_warning "slurmd.service uses Type=forking, updating to Type=simple..."
        sudo sed -i 's/Type=forking/Type=simple/' "$SLURMD_SERVICE"

        # ExecStart에 -D 플래그 추가 (없으면)
        if ! grep -q "ExecStart=.* -D" "$SLURMD_SERVICE"; then
            sudo sed -i 's|ExecStart=\(.*slurmd\)\(.*\)|ExecStart=\1 -D\2|' "$SLURMD_SERVICE"
        fi

        sudo systemctl daemon-reload
        log_success "slurmd.service updated to Type=simple"
    else
        log_success "slurmd.service already uses Type=simple"
    fi
else
    log_warning "slurmd.service not found, creating..."
    sudo tee "$SLURMD_SERVICE" > /dev/null << 'EOFSVC'
[Unit]
Description=Slurm node daemon
After=network-online.target munge.service
Wants=network-online.target
ConditionPathExists=/etc/slurm/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStart=/usr/local/slurm/sbin/slurmd -D $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOFSVC
    sudo systemctl daemon-reload
    log_success "slurmd.service created"
fi

# 5. Munge 상태 확인
log_info "Checking Munge service..."
if systemctl is-active --quiet munge; then
    log_success "Munge is running"
else
    log_warning "Munge is not running, attempting to start..."
    sudo systemctl start munge || log_error "Failed to start Munge"
fi

# 6. slurmd 재시작
log_info "Restarting slurmd service..."
sudo systemctl stop slurmd 2>/dev/null || true
sleep 1
sudo systemctl start slurmd

if systemctl is-active --quiet slurmd; then
    log_success "slurmd started successfully!"

    # 버전 확인
    SLURMD_VERSION=$(/usr/local/slurm/sbin/slurmd -V 2>/dev/null || echo "unknown")
    log_success "slurmd version: $SLURMD_VERSION"
else
    log_error "slurmd failed to start!"
    echo ""
    echo "=== slurmd status ==="
    sudo systemctl status slurmd --no-pager -l || true
    echo ""
    echo "=== Recent logs ==="
    sudo journalctl -u slurmd -n 20 --no-pager || true
    exit 1
fi

# 7. slurmd 서비스 활성화
sudo systemctl enable slurmd 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ Configuration fix complete on $(hostname)"
echo ""
echo "  PluginDir: $SLURM_PLUGIN_DIR"
echo "  slurmd:    $(systemctl is-active slurmd)"
echo "═══════════════════════════════════════════════════════════"
EOFREMOTE

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "[$node] Configuration fixed successfully!"
        echo "SUCCESS" > "$result_file"
        return 0
    else
        log_error "[$node] Configuration fix failed!"
        echo "FAILED:SCRIPT" > "$result_file"
        return 1
    fi
}

# 모든 노드 수정 (병렬 처리)
fix_all_nodes() {
    local nodes=("$@")
    local total=${#nodes[@]}
    local success_count=0
    local failed_count=0
    local pids=()
    local results_dir="/tmp/fix_slurm_results_$$"

    mkdir -p "$results_dir"

    log_info "Total nodes to fix: $total"
    log_info "Parallel jobs: $PARALLEL"
    echo ""

    for node in "${nodes[@]}"; do
        # 병렬 제한
        while [[ ${#pids[@]} -ge $PARALLEL ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[$i]'
                fi
            done
            pids=("${pids[@]}")
            sleep 0.5
        done

        # 백그라운드에서 노드 수정
        (
            if fix_single_node "$node"; then
                echo "SUCCESS:$node" >> "$results_dir/results.txt"
            else
                echo "FAILED:$node" >> "$results_dir/results.txt"
            fi
        ) &
        pids+=($!)
    done

    # 모든 작업 완료 대기
    log_info "Waiting for all nodes to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 결과 집계
    if [[ -f "$results_dir/results.txt" ]]; then
        success_count=$(grep -c "^SUCCESS:" "$results_dir/results.txt" 2>/dev/null || echo 0)
        failed_count=$(grep -c "^FAILED:" "$results_dir/results.txt" 2>/dev/null || echo 0)

        if [[ $failed_count -gt 0 ]]; then
            echo ""
            log_error "Failed nodes:"
            grep "^FAILED:" "$results_dir/results.txt" | cut -d: -f2 | while read node; do
                echo "  - $node"
            done
        fi

        rm -rf "$results_dir"
    fi

    echo ""
    log_info "Summary:"
    log_success "  Successful: $success_count nodes"
    if [[ $failed_count -gt 0 ]]; then
        log_error "  Failed: $failed_count nodes"
    fi

    return $failed_count
}

# 컨트롤러 slurm.conf도 수정
fix_controller_config() {
    log_step "Fixing controller slurm.conf..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN: Would fix controller slurm.conf"
        return 0
    fi

    fix_slurm_conf "${SLURM_CONFIG_DIR}/slurm.conf"

    # /usr/local/slurm/etc/slurm.conf도 수정 (있는 경우)
    if [[ -f "${SLURM_PREFIX}/etc/slurm.conf" ]]; then
        fix_slurm_conf "${SLURM_PREFIX}/etc/slurm.conf"
    fi

    log_success "Controller slurm.conf fixed"
}

# 노드 상태 확인
verify_nodes() {
    log_step "Verifying node states..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN: Would verify node states"
        return 0
    fi

    # 잠시 대기 후 노드 상태 확인
    sleep 5

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Node Status Check"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # sinfo로 노드 상태 확인
    if command -v sinfo &>/dev/null || [[ -x "${SLURM_PREFIX}/bin/sinfo" ]]; then
        ${SLURM_PREFIX}/bin/sinfo -N -l 2>/dev/null || sinfo -N -l 2>/dev/null || {
            log_warning "Cannot get node status (slurmctld may not be running)"
        }
    fi

    echo ""

    # UNKNOWN 상태 노드 확인
    local unknown_nodes=$(${SLURM_PREFIX}/bin/sinfo -h -t unknown -o "%N" 2>/dev/null || echo "")
    if [[ -n "$unknown_nodes" ]]; then
        log_warning "Nodes still in UNKNOWN state: $unknown_nodes"
        log_info "These nodes may need manual intervention or slurmd restart"
    else
        log_success "No nodes in UNKNOWN state"
    fi
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Slurm Configuration Fix - All Compute Nodes           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN MODE - No actual changes will be made"
        echo ""
    fi

    check_prerequisites

    # 컨트롤러 slurm.conf 먼저 수정
    fix_controller_config

    # 노드 목록 가져오기
    log_info "Getting compute node list..."
    local nodes_list
    nodes_list=$(get_compute_nodes)

    if [[ -z "$nodes_list" ]]; then
        log_error "No compute nodes found"
        exit 1
    fi

    # 배열로 변환
    local nodes=()
    while IFS= read -r node; do
        [[ -n "$node" ]] && nodes+=("$node")
    done <<< "$nodes_list"

    log_info "Found ${#nodes[@]} compute node(s):"
    for node in "${nodes[@]}"; do
        echo "  - $node"
    done
    echo ""

    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Proceed with fixing all nodes? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi

    # 모든 노드 수정
    fix_all_nodes "${nodes[@]}"
    local failed=$?

    # 노드 상태 확인
    verify_nodes

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Fix Complete!                                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Next steps:"
    echo "  1. Check node status:"
    echo "     sinfo -N -l"
    echo ""
    echo "  2. If nodes still show UNKNOWN, restart slurmctld:"
    echo "     sudo systemctl restart slurmctld"
    echo ""
    echo "  3. Force node state update:"
    echo "     sudo scontrol update nodename=<node> state=resume"
    echo ""

    exit $failed
}

main "$@"
