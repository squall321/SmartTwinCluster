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
#   --yes, -y            사용자 확인 없이 자동 실행
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
AUTO_YES=false

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

# SSH 비밀번호 및 sshpass 설정 (cluster/start_multihead.sh 방식 적용)
SSH_PASSWORD=""
HAS_SSHPASS=false

setup_ssh_auth() {
    # YAML에서 ssh_password 읽기
    SSH_PASSWORD=$(python3 << EOPY
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
print(config.get('cluster_info', {}).get('ssh_password', ''))
EOPY
    )

    # sshpass 사용 가능 여부 확인
    if command -v sshpass &> /dev/null; then
        HAS_SSHPASS=true
    else
        # sshpass 설치 시도
        log_info "Installing sshpass..."
        apt-get install -y sshpass > /dev/null 2>&1 || yum install -y sshpass > /dev/null 2>&1 || true
        if command -v sshpass &> /dev/null; then
            HAS_SSHPASS=true
        fi
    fi

    if [[ -n "$SSH_PASSWORD" ]]; then
        log_success "SSH password loaded from YAML config"
        if [[ "$HAS_SSHPASS" == "true" ]]; then
            log_success "sshpass available - passwordless remote sudo enabled"
        else
            log_warning "sshpass not available - may need manual password input"
        fi
    else
        log_warning "No ssh_password in YAML - assuming passwordless sudo is configured"
    fi
}

# 원격 sudo 명령 실행 (비밀번호 자동 처리)
remote_sudo() {
    local node_user="$1"
    local node_ip="$2"
    local cmd="$3"

    if [[ -n "$SSH_PASSWORD" && "$HAS_SSHPASS" == "true" ]]; then
        # sshpass + sudo -S 패턴 사용
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "$node_user@$node_ip" \
            "echo '$SSH_PASSWORD' | sudo -S bash -c '$cmd'" 2>/dev/null
    else
        # 일반 sudo 사용 (NOPASSWD 설정 가정)
        ssh -o StrictHostKeyChecking=no "$node_user@$node_ip" "sudo bash -c '$cmd'" 2>/dev/null
    fi
}

# 계산 노드 목록 추출
get_compute_nodes() {
    local nodes_json
    local py_exit_code

    # Python으로 YAML 파싱 (에러 출력 포함)
    nodes_json=$(python3 << EOPY
import sys
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

import json

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
except FileNotFoundError:
    print(f"ERROR: Config file not found: $CONFIG_FILE", file=sys.stderr)
    sys.exit(1)
except yaml.YAMLError as e:
    print(f"ERROR: Invalid YAML: {e}", file=sys.stderr)
    sys.exit(1)

nodes = []
compute_nodes = config.get('nodes', {}).get('compute_nodes', [])

if not compute_nodes:
    print("WARNING: No compute_nodes found in YAML", file=sys.stderr)
    print("Expected structure: nodes.compute_nodes[].hostname/ip_address", file=sys.stderr)

for node in compute_nodes:
    if 'hostname' not in node or 'ip_address' not in node:
        print(f"WARNING: Skipping invalid node (missing hostname or ip_address): {node}", file=sys.stderr)
        continue
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark')
    })

print(json.dumps(nodes))
EOPY
    )
    py_exit_code=$?

    if [[ $py_exit_code -ne 0 ]]; then
        log_error "Failed to parse YAML configuration"
        echo "[]"
        return 1
    fi

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
    # SSH/SCP/rsync 명령 구성 (sshpass 사용 여부에 따라)
    local ssh_cmd="ssh -o StrictHostKeyChecking=no"
    local scp_cmd="scp -o StrictHostKeyChecking=no"
    local rsync_rsh="ssh -o StrictHostKeyChecking=no"
    if [[ -n "$SSH_PASSWORD" && "$HAS_SSHPASS" == "true" ]]; then
        ssh_cmd="sshpass -p '$SSH_PASSWORD' ssh -o StrictHostKeyChecking=no"
        scp_cmd="sshpass -p '$SSH_PASSWORD' scp -o StrictHostKeyChecking=no"
        rsync_rsh="sshpass -p '$SSH_PASSWORD' ssh -o StrictHostKeyChecking=no"
    fi

    if ! eval "$ssh_cmd" -o ConnectTimeout=5 "$node_user@$node_ip" "echo OK" &>/dev/null; then
        log_error "[$node_hostname] SSH connection failed"
        return 1
    fi

    log_success "[$node_hostname] SSH connection OK"

    # 원격 디렉토리 생성 (sudo 비밀번호 자동 전달)
    if [[ -n "$SSH_PASSWORD" ]]; then
        eval "$ssh_cmd" "$node_user@$node_ip" "echo '$SSH_PASSWORD' | sudo -S mkdir -p /opt/offline_packages" 2>/dev/null || {
            log_error "[$node_hostname] Failed to create remote directory"
            return 1
        }
    else
        eval "$ssh_cmd" "$node_user@$node_ip" "sudo mkdir -p /opt/offline_packages" || {
            log_error "[$node_hostname] Failed to create remote directory"
            return 1
        }
    fi

    # rsync로 패키지 전송 (sshpass 적용)
    log_info "[$node_hostname] Transferring packages (this may take 5-10 minutes)..."

    rsync -az --info=progress2 \
        --exclude='.git' \
        --exclude='*.log' \
        -e "$rsync_rsh" \
        "$PACKAGE_DIR/" \
        "$node_user@$node_ip:/tmp/offline_packages/" || {
        log_error "[$node_hostname] Package transfer failed"
        return 1
    }

    # 컨트롤러의 slurm.conf도 전송 (PluginDir 경로가 올바른 버전)
    log_info "[$node_hostname] Transferring slurm.conf from controller..."
    local SLURM_CONF_LOCAL="/etc/slurm/slurm.conf"
    if [[ -f "$SLURM_CONF_LOCAL" ]]; then
        eval "$scp_cmd" "$SLURM_CONF_LOCAL" "$node_user@$node_ip:/tmp/offline_packages/slurm.conf" || {
            log_warning "[$node_hostname] Failed to transfer slurm.conf (will use existing)"
        }
        log_success "[$node_hostname] slurm.conf transferred"
    else
        log_warning "[$node_hostname] Controller slurm.conf not found at $SLURM_CONF_LOCAL"
    fi

    # 컨트롤러의 munge.key 전송 (모든 노드가 동일한 키 사용 필수)
    log_info "[$node_hostname] Transferring munge.key from controller..."
    local MUNGE_KEY_LOCAL="/etc/munge/munge.key"
    if [[ -f "$MUNGE_KEY_LOCAL" ]]; then
        # munge 디렉토리에 키 파일 복사 (sudo 불필요 - /tmp는 모든 사용자 쓰기 가능)
        eval "$ssh_cmd" "$node_user@$node_ip" "mkdir -p /tmp/offline_packages/munge" || true
        # munge.key는 root 소유이므로 로컬에서 sudo로 읽어야 함
        # 하지만 이 스크립트 자체가 sudo로 실행되므로 sudo 불필요
        cat "$MUNGE_KEY_LOCAL" | eval "$ssh_cmd" "$node_user@$node_ip" "cat > /tmp/offline_packages/munge/munge.key" || {
            log_warning "[$node_hostname] Failed to transfer munge.key (will use existing)"
        }
        log_success "[$node_hostname] munge.key transferred"
    else
        log_warning "[$node_hostname] Controller munge.key not found at $MUNGE_KEY_LOCAL"
        log_warning "[$node_hostname] Munge authentication may fail if keys don't match!"
    fi

    log_success "[$node_hostname] Packages transferred"

    # 원격 설치 스크립트 실행
    log_info "[$node_hostname] Installing packages..."

    # 원격 설치 스크립트 실행 (sudo 비밀번호 전달)
    eval "$ssh_cmd" "$node_user@$node_ip" bash -s "$gluster_server" "$gluster_volume" "$gluster_mount" "$SSH_PASSWORD" << 'EOFREMOTE'
set -e

GLUSTER_SERVER="$1"
GLUSTER_VOLUME="$2"
GLUSTER_MOUNT="$3"
SUDO_PASS="$4"

# sudo 래퍼 함수 (비밀번호 자동 전달)
run_sudo() {
    if [[ -n "$SUDO_PASS" ]]; then
        # -S: stdin에서 비밀번호 읽기, [sudo] 프롬프트는 stderr로 가므로 /dev/null
        echo "$SUDO_PASS" | sudo -S "$@"
    else
        sudo "$@"
    fi
}

echo "═══════════════════════════════════════════════════════════"
echo "  Offline Package Installation (Compute Node)"
echo "═══════════════════════════════════════════════════════════"

# 1. APT 패키지 설치
if [[ -f /tmp/offline_packages/apt_packages/install_offline_packages.sh ]]; then
    echo ""
    echo "Step 1: Installing APT packages..."
    cd /tmp/offline_packages/apt_packages
    run_sudo bash install_offline_packages.sh
else
    echo "WARNING: APT packages not found"
fi

# 2. Slurm 배포
if [[ -f /tmp/offline_packages/slurm/slurm-*-prebuilt.tar.gz ]]; then
    echo ""
    echo "Step 2: Deploying Slurm..."
    cd /tmp/offline_packages/slurm
    tar -xzf slurm-*-prebuilt.tar.gz
    run_sudo bash deploy_slurm.sh
else
    echo "WARNING: Slurm package not found"
fi

# 2.5. slurm.conf 복사 (컨트롤러에서 전송된 파일 사용)
echo ""
echo "Step 2.5: Configuring slurm.conf..."
SLURM_CONF_SRC="/tmp/offline_packages/slurm.conf"
SLURM_CONF_DEST="/etc/slurm/slurm.conf"
SLURM_LOCAL_CONF="/usr/local/slurm/etc/slurm.conf"

if [[ -f "$SLURM_CONF_SRC" ]]; then
    echo "  Found slurm.conf from controller"

    # /etc/slurm 디렉토리 생성
    run_sudo mkdir -p /etc/slurm
    run_sudo mkdir -p /usr/local/slurm/etc

    # 기존 파일 백업
    if [[ -f "$SLURM_CONF_DEST" ]]; then
        run_sudo mv "$SLURM_CONF_DEST" "${SLURM_CONF_DEST}.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    # 복사
    run_sudo cp "$SLURM_CONF_SRC" "$SLURM_CONF_DEST"
    run_sudo cp "$SLURM_CONF_SRC" "$SLURM_LOCAL_CONF"
    run_sudo chown slurm:slurm "$SLURM_CONF_DEST" "$SLURM_LOCAL_CONF" 2>/dev/null || true
    run_sudo chmod 644 "$SLURM_CONF_DEST" "$SLURM_LOCAL_CONF"

    echo "  ✓ slurm.conf installed to $SLURM_CONF_DEST"
    echo "  ✓ slurm.conf installed to $SLURM_LOCAL_CONF"

    # PluginDir 확인
    PLUGIN_DIR=$(grep "^PluginDir=" "$SLURM_CONF_DEST" 2>/dev/null | head -1)
    echo "  ✓ $PLUGIN_DIR"
else
    echo "  WARNING: slurm.conf not found in /tmp/offline_packages/"
    echo "  Using existing configuration (may cause PluginDir errors)"
fi

# 3. Munge 배포
if [[ -f /tmp/offline_packages/munge/deploy_munge.sh ]]; then
    echo ""
    echo "Step 3: Deploying Munge..."
    cd /tmp/offline_packages/munge
    run_sudo bash deploy_munge.sh
else
    echo "WARNING: Munge package not found"
fi

# 4. GlusterFS 클라이언트 + autofs 설정
echo ""
echo "Step 4: Setting up GlusterFS client with autofs..."

if [[ -n "$GLUSTER_SERVER" ]] && [[ -n "$GLUSTER_VOLUME" ]]; then
    # GlusterFS 클라이언트 설치 확인 (Step 1의 APT 오프라인 패키지에 포함)
    if ! dpkg -l | grep -q glusterfs-client; then
        echo "  WARNING: glusterfs-client not installed"
        echo "  Should have been installed in Step 1 (APT packages)"
        echo "  Checking offline packages..."
        # 오프라인 패키지에서 설치 시도
        if ls /tmp/offline_packages/apt_packages/*.deb &>/dev/null; then
            run_sudo dpkg -i /tmp/offline_packages/apt_packages/glusterfs*.deb 2>/dev/null || true
            run_sudo dpkg -i /tmp/offline_packages/apt_packages/autofs*.deb 2>/dev/null || true
        fi
    else
        echo "  ✓ glusterfs-client already installed"
    fi

    # autofs 설치 확인
    if ! dpkg -l | grep -q autofs; then
        echo "  WARNING: autofs not installed"
        if ls /tmp/offline_packages/apt_packages/autofs*.deb &>/dev/null; then
            run_sudo dpkg -i /tmp/offline_packages/apt_packages/autofs*.deb 2>/dev/null || true
        fi
    else
        echo "  ✓ autofs already installed"
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
        echo "" | run_sudo tee -a "$AUTOFS_MASTER" > /dev/null
        echo "# GlusterFS autofs mount (added by cluster deploy)" | run_sudo tee -a "$AUTOFS_MASTER" > /dev/null
        echo "$MOUNT_PARENT /etc/auto.gluster --timeout=300 --ghost" | run_sudo tee -a "$AUTOFS_MASTER" > /dev/null
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
    run_sudo tee "$AUTOFS_GLUSTER" > /dev/null << EOFAUTOFS
# GlusterFS autofs map
# Format: mount_name  -options  server:/volume
$MOUNT_NAME  -fstype=glusterfs,log-level=WARNING,backup-volfile-servers=$GLUSTER_SERVER  $GLUSTER_SERVER:/$GLUSTER_VOLUME
EOFAUTOFS

    echo "  Created $AUTOFS_GLUSTER"

    # autofs 재시작
    run_sudo systemctl enable autofs
    run_sudo systemctl restart autofs

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

# 5. slurmd 서비스 시작
echo ""
echo "Step 5: Starting slurmd service..."

# slurmd 서비스 파일 확인/생성
SLURMD_SERVICE="/etc/systemd/system/slurmd.service"
if [[ ! -f "$SLURMD_SERVICE" ]]; then
    echo "  Creating slurmd.service..."
    run_sudo tee "$SLURMD_SERVICE" > /dev/null << 'EOFSVC'
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
    run_sudo systemctl daemon-reload
    echo "  ✓ slurmd.service created"
fi

# Type=forking이면 Type=simple로 수정
if grep -q "Type=forking" "$SLURMD_SERVICE" 2>/dev/null; then
    echo "  Updating slurmd.service from Type=forking to Type=simple..."
    run_sudo sed -i 's/Type=forking/Type=simple/' "$SLURMD_SERVICE"
    if ! grep -q "ExecStart=.* -D" "$SLURMD_SERVICE"; then
        run_sudo sed -i 's|ExecStart=\(.*slurmd\)\(.*\)|ExecStart=\1 -D\2|' "$SLURMD_SERVICE"
    fi
    run_sudo systemctl daemon-reload
fi

# /run/slurm 디렉토리 생성
run_sudo mkdir -p /run/slurm
run_sudo chown slurm:slurm /run/slurm 2>/dev/null || true

# slurmd 시작
echo "  Starting slurmd..."
run_sudo systemctl stop slurmd 2>/dev/null || true
sleep 1
run_sudo systemctl start slurmd

if systemctl is-active --quiet slurmd; then
    echo "  ✓ slurmd started successfully!"
    run_sudo systemctl enable slurmd 2>/dev/null || true
    SLURMD_VERSION=$(/usr/local/slurm/sbin/slurmd -V 2>/dev/null || echo "unknown")
    echo "  ✓ slurmd version: $SLURMD_VERSION"
else
    echo "  ✗ slurmd failed to start!"
    echo ""
    echo "=== slurmd status ==="
    run_sudo systemctl status slurmd --no-pager -l 2>&1 | head -20 || true
    echo ""
    echo "=== Recent logs ==="
    run_sudo journalctl -u slurmd -n 10 --no-pager 2>&1 || true
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ Offline package installation complete!"
echo ""
echo "Slurm configuration:"
echo "  - slurmd: $(systemctl is-active slurmd 2>/dev/null || echo 'unknown')"
echo "  - Config: /etc/slurm/slurm.conf"
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

    # JSON을 임시 파일에 저장 (bash 변수 전달 시 특수문자 문제 방지)
    local nodes_file="/tmp/deploy_nodes_$$.json"
    echo "$nodes_json" > "$nodes_file"

    # 디버깅: temp 파일 확인
    if [[ ! -s "$nodes_file" ]]; then
        log_error "Failed to create nodes temp file: $nodes_file"
        return 1
    fi

    # Python으로 노드 수 계산 (에러 출력 활성화)
    local total_nodes
    total_nodes=$(python3 -c "
import json
import sys
try:
    with open('$nodes_file', 'r') as f:
        nodes = json.load(f)
    print(len(nodes))
except Exception as e:
    print(f'Error parsing JSON: {e}', file=sys.stderr)
    print('0')
" 2>&1)

    # 숫자가 아닌 경우 에러 표시
    if ! [[ "$total_nodes" =~ ^[0-9]+$ ]]; then
        log_error "Failed to count nodes. Python output: $total_nodes"
        log_error "Temp file content (first 500 chars):"
        head -c 500 "$nodes_file" >&2
        rm -f "$nodes_file"
        return 1
    fi

    log_info "Total compute nodes: $total_nodes"
    log_info "GlusterFS: $gluster_server:/$gluster_volume -> $gluster_mount"

    if [[ "$SPECIFIC_NODE" != "" ]]; then
        log_info "Deploying to specific node only: $SPECIFIC_NODE"
    fi

    local success_count=0
    local failed_count=0
    local pids=()

    # 노드 순회 (Python으로 파일에서 읽기)
    while IFS='|' read -r hostname ip user; do
        # 빈 줄 스킵
        [[ -z "$hostname" ]] && continue

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

    done < <(python3 -c "
import json
with open('$nodes_file', 'r') as f:
    nodes = json.load(f)
for n in nodes:
    print(f\"{n['hostname']}|{n['ip']}|{n['user']}\")
" 2>/dev/null)

    # 임시 파일 정리
    rm -f "$nodes_file"

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

    # SSH 인증 설정 (YAML에서 ssh_password 로드, sshpass 확인)
    setup_ssh_auth

    log_info "Config:       $CONFIG_FILE"
    log_info "Package Dir:  $PACKAGE_DIR"
    log_info "Parallel:     $PARALLEL"
    echo ""

    if [[ "$DRY_RUN" == "false" ]] && [[ "$AUTO_YES" == "false" ]]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi

    # 계산 노드 목록 추출 (디버그 출력 추가)
    log_info "Extracting compute nodes..."
    local nodes=$(get_compute_nodes)

    # 디버깅: 노드 JSON 확인
    if [[ -z "$nodes" ]] || [[ "$nodes" == "[]" ]]; then
        log_error "No compute nodes found in YAML configuration"
        log_error "Check 'nodes.compute_nodes' section in: $CONFIG_FILE"
        exit 1
    fi

    # 노드 수 확인
    local node_count=$(python3 -c "import json; print(len(json.loads('''$nodes''')))" 2>/dev/null || echo "parse_error")
    if [[ "$node_count" == "parse_error" ]]; then
        log_error "Failed to parse compute nodes JSON"
        log_error "Raw output: $nodes"
        exit 1
    fi
    log_success "Found $node_count compute nodes"

    # GlusterFS 설정 추출 (jq 대신 Python 사용)
    log_info "Extracting GlusterFS configuration..."
    local gluster_config=$(get_glusterfs_config)

    # Python으로 JSON 파싱 (jq 의존성 제거)
    local gluster_server=$(python3 -c "import json; print(json.loads('''$gluster_config''')['gluster_server'])" 2>/dev/null || echo "")
    local gluster_volume=$(python3 -c "import json; print(json.loads('''$gluster_config''')['volume_name'])" 2>/dev/null || echo "shared_data")
    local gluster_mount=$(python3 -c "import json; print(json.loads('''$gluster_config''')['mount_point'])" 2>/dev/null || echo "/mnt/gluster")

    if [[ -z "$gluster_server" ]]; then
        log_warning "GlusterFS server not found in config - using first controller IP"
        gluster_server=$(python3 -c "
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
controllers = config.get('nodes', {}).get('controllers', [])
if controllers:
    print(controllers[0].get('ip_address', ''))
" 2>/dev/null || echo "")
    fi

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
