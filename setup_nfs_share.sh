#!/bin/bash

################################################################################
# NFS Share Setup Script
#
# 현재 노드의 디렉토리를 NFS로 export하고,
# YAML 설정 파일에 정의된 모든 노드에 NFS 마운트를 설정합니다.
#
# Usage:
#   sudo ./setup_nfs_share.sh --config <yaml_config> <source_path> <mount_path>
#
# Example:
#   sudo ./setup_nfs_share.sh --config my_multihead_cluster_2.yaml /data /data
#   sudo ./setup_nfs_share.sh --config my_multihead_cluster.yaml /scratch /mnt/scratch
#
# Arguments:
#   --config PATH     YAML 클러스터 설정 파일 경로
#   <source_path>     현재 노드에서 NFS export할 절대 경로
#   <mount_path>      각 원격 노드에서 마운트할 절대 경로
#
# 동작:
#   1. 현재 노드에서 source_path를 NFS export 설정
#   2. 각 원격 노드에 SSH로 접속하여 mount_path에 NFS 마운트
#   3. 원격 노드에 이미 해당 경로가 마운트되어 있으면 건너뜀
#   4. 현재 노드는 source_path == mount_path이면 건너뛰고,
#      다르면 mount_path로 NFS 마운트 (자기 자신에게 마운트)
################################################################################

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"

# Defaults
CONFIG_PATH=""
SOURCE_PATH=""
MOUNT_PATH=""

usage() {
    echo "Usage: sudo $0 --config <yaml_config> <source_path> <mount_path>"
    echo ""
    echo "NFS Share Setup - 현재 노드의 디렉토리를 클러스터 전체에 NFS 마운트"
    echo ""
    echo "Options:"
    echo "  --config PATH     YAML 클러스터 설정 파일 경로 (필수)"
    echo "  --help, -h        도움말 표시"
    echo ""
    echo "Arguments:"
    echo "  <source_path>     현재 노드에서 NFS export할 절대 경로 (예: /data)"
    echo "  <mount_path>      각 원격 노드에서 마운트할 절대 경로 (예: /data)"
    echo ""
    echo "Examples:"
    echo "  sudo $0 --config my_multihead_cluster_2.yaml /data /data"
    echo "  sudo $0 --config my_multihead_cluster.yaml /scratch /mnt/scratch"
    exit 0
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_skip() {
    echo -e "${CYAN}[SKIP]${NC} $*"
}

# Parse arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        -*)
            log_error "알 수 없는 옵션: $1"
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Extract positional arguments
if [[ ${#POSITIONAL_ARGS[@]} -lt 2 ]]; then
    log_error "source_path와 mount_path를 모두 지정해야 합니다."
    echo ""
    usage
fi

SOURCE_PATH="${POSITIONAL_ARGS[0]}"
MOUNT_PATH="${POSITIONAL_ARGS[1]}"

# Validate config
if [[ -z "$CONFIG_PATH" ]]; then
    log_error "--config 옵션이 필요합니다."
    echo ""
    usage
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
    # Try relative to project root
    if [[ -f "$PROJECT_ROOT/$CONFIG_PATH" ]]; then
        CONFIG_PATH="$PROJECT_ROOT/$CONFIG_PATH"
    else
        log_error "설정 파일을 찾을 수 없습니다: $CONFIG_PATH"
        exit 1
    fi
fi

# Validate paths are absolute
if [[ "$SOURCE_PATH" != /* ]]; then
    log_error "source_path는 절대 경로여야 합니다: $SOURCE_PATH"
    exit 1
fi

if [[ "$MOUNT_PATH" != /* ]]; then
    log_error "mount_path는 절대 경로여야 합니다: $MOUNT_PATH"
    exit 1
fi

# Validate source path exists
if [[ ! -d "$SOURCE_PATH" ]]; then
    log_error "소스 경로가 존재하지 않습니다: $SOURCE_PATH"
    exit 1
fi

# Check root privileges
if [[ $EUID -ne 0 ]]; then
    log_error "이 스크립트는 root 권한이 필요합니다. sudo로 실행해주세요."
    exit 1
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                         NFS Share Setup                                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Config:${NC}      $CONFIG_PATH"
echo -e "${BLUE}Source Path:${NC} $SOURCE_PATH (현재 노드에서 export)"
echo -e "${BLUE}Mount Path:${NC}  $MOUNT_PATH (각 노드에서 마운트)"
echo ""

# Get current node IP
CURRENT_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true)
CURRENT_HOSTNAME=$(hostname -s 2>/dev/null || hostname)

log_info "현재 노드: $CURRENT_HOSTNAME (IPs: $(echo $CURRENT_IPS | tr '\n' ' '))"
echo ""

# Parse all nodes from YAML
all_nodes_json=$(python3 -c "
import yaml, json, sys
try:
    with open('$CONFIG_PATH') as f:
        config = yaml.safe_load(f)

    controllers = config.get('nodes', {}).get('controllers', [])
    for c in controllers:
        c['node_role'] = 'controller'

    compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
    for c in compute_nodes:
        c['node_role'] = 'compute'

    all_nodes = controllers + compute_nodes
    print(json.dumps(all_nodes))
except Exception as e:
    print(json.dumps([]), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "[]")

if [[ -z "$all_nodes_json" ]] || [[ "$all_nodes_json" == "[]" ]]; then
    log_error "설정 파일에서 노드 목록을 로드할 수 없습니다."
    exit 1
fi

NODE_COUNT=$(echo "$all_nodes_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
log_info "총 ${NODE_COUNT}개 노드를 설정합니다."
echo ""

# ============================================================================
# Step 0: NFS 오프라인 패키지 준비
# ============================================================================
NFS_PKG_DIR="$PROJECT_ROOT/offline_packages/nfs"

prepare_nfs_packages() {
    echo -e "${BLUE}━━━ Step 0: NFS 오프라인 패키지 준비 ━━━${NC}"
    echo ""

    if [[ -d "$NFS_PKG_DIR" ]] && ls "$NFS_PKG_DIR"/*.deb >/dev/null 2>&1; then
        local pkg_count
        pkg_count=$(ls "$NFS_PKG_DIR"/*.deb 2>/dev/null | wc -l)
        log_ok "NFS 오프라인 패키지 이미 존재 (${pkg_count}개 .deb)"
    else
        log_info "NFS 패키지를 현재 노드에서 수집합니다..."
        mkdir -p "$NFS_PKG_DIR"

        local tmp_download
        tmp_download=$(mktemp -d)

        cd "$tmp_download"
        apt-get download \
            nfs-common nfs-kernel-server \
            rpcbind keyutils libnfsidmap1 libtirpc3 libtirpc-common \
            libwrap0 libevent-core-2.1-7 libdevmapper1.02.1 \
            ucf 2>/dev/null || true

        for pkg in nfs-common nfs-kernel-server; do
            apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
                --no-breaks --no-replaces --no-enhances "$pkg" 2>/dev/null \
                | grep "^\w" | sort -u | while read -r dep; do
                apt-get download "$dep" 2>/dev/null || true
            done
        done
        cd - >/dev/null

        mv "$tmp_download"/*.deb "$NFS_PKG_DIR/" 2>/dev/null || true
        rm -rf "$tmp_download"

        local final_count
        final_count=$(ls "$NFS_PKG_DIR"/*.deb 2>/dev/null | wc -l)
        if [[ "$final_count" -eq 0 ]]; then
            log_error "NFS 패키지를 수집할 수 없습니다. 현재 노드에 apt 캐시가 있는지 확인해주세요."
            exit 1
        fi
        log_ok "NFS 오프라인 패키지 수집 완료 (${final_count}개 .deb -> $NFS_PKG_DIR)"
    fi

    # 로컬 APT 저장소 인덱스 생성 (Packages.gz)
    if [[ ! -f "$NFS_PKG_DIR/Packages.gz" ]] || [[ ! -f "$NFS_PKG_DIR/Packages" ]]; then
        log_info "APT 저장소 인덱스 생성 중..."
        cd "$NFS_PKG_DIR"
        dpkg-scanpackages . /dev/null > Packages 2>/dev/null
        gzip -k -f Packages
        cd - >/dev/null
        log_ok "APT 저장소 인덱스 생성 완료"
    fi

    echo ""
}

# 로컬 APT 저장소를 설정하고 apt-get install로 패키지 설치
# 인자: 설치할 패키지명 목록
setup_local_repo_and_install() {
    local pkg_dir="$1"
    shift
    local packages=("$@")

    local repo_list="/etc/apt/sources.list.d/nfs-offline-local.list"

    # 로컬 저장소만 사용하는 공통 APT 옵션
    local APT_LOCAL_OPTS=(
        -o "Dir::Etc::sourcelist=$repo_list"
        -o "Dir::Etc::sourceparts=-"
        -o "APT::Get::List-Cleanup=0"
    )

    # 로컬 저장소 등록
    echo "deb [trusted=yes] file://${pkg_dir} ./" > "$repo_list"

    # APT 캐시 업데이트 (로컬 저장소만)
    apt-get update "${APT_LOCAL_OPTS[@]}" >/dev/null 2>&1 || true

    # apt-get install 실행 (로컬 저장소만 참조 + needrestart 억제)
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 \
        apt-get install -y --no-install-recommends "${APT_LOCAL_OPTS[@]}" "${packages[@]}" 2>&1 || {
        log_warn "apt-get install 재시도 (의존성 복구)..."
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 \
            apt-get install -f -y "${APT_LOCAL_OPTS[@]}" 2>&1 || true
    }

    # 로컬 저장소 설정 제거 (정리)
    rm -f "$repo_list"
}

prepare_nfs_packages

# ============================================================================
# Step 1: NFS Server Setup on Current Node
# ============================================================================
echo -e "${BLUE}━━━ Step 1: NFS 서버 설정 (현재 노드) ━━━${NC}"
echo ""

# Ensure source path exists on current node (NFS export 대상)
if [[ ! -d "$SOURCE_PATH" ]]; then
    mkdir -p "$SOURCE_PATH"
    log_ok "소스 디렉토리 생성: $SOURCE_PATH"
else
    log_ok "소스 디렉토리 존재 확인: $SOURCE_PATH"
fi

# Install NFS server if not installed
if ! dpkg -s nfs-kernel-server &>/dev/null; then
    log_info "nfs-kernel-server 패키지 설치 중 (오프라인 apt)..."
    setup_local_repo_and_install "$NFS_PKG_DIR" nfs-kernel-server nfs-common
    if dpkg -s nfs-kernel-server &>/dev/null; then
        log_ok "nfs-kernel-server 설치 완료"
    else
        log_error "nfs-kernel-server 설치 실패"
        exit 1
    fi
else
    log_ok "nfs-kernel-server 이미 설치됨"
fi

# Get all unique network subnets from node IPs in YAML config
# management_network만으로는 실제 노드 IP 대역을 커버 못할 수 있으므로
# 노드 IP에서 /24 서브넷을 추출하여 모든 대역을 export에 추가
NETWORKS=$(python3 -c "
import yaml, sys
with open('$CONFIG_PATH') as f:
    config = yaml.safe_load(f)
nodes = config.get('nodes', {})
subnets = set()
# management_network도 포함
mgmt = config.get('network', {}).get('management_network', '')
if mgmt:
    subnets.add(mgmt)
# 모든 노드 IP에서 /24 서브넷 추출
for group in ['controllers', 'compute_nodes']:
    for node in nodes.get(group, []):
        ip = node.get('ip_address', '')
        if ip:
            parts = ip.split('.')
            if len(parts) == 4:
                subnets.add(parts[0] + '.' + parts[1] + '.' + parts[2] + '.0/24')
for s in sorted(subnets):
    print(s)
" 2>/dev/null)

if [[ -z "$NETWORKS" ]]; then
    NETWORKS="10.0.0.0/24"
    log_warn "네트워크 대역을 감지하지 못했습니다. 기본값 사용: $NETWORKS"
fi

# Build export line with all subnets
EXPORT_CLIENTS=""
while IFS= read -r subnet; do
    EXPORT_CLIENTS="${EXPORT_CLIENTS} ${subnet}(rw,sync,no_subtree_check,no_root_squash)"
done <<< "$NETWORKS"
EXPORT_LINE="$SOURCE_PATH${EXPORT_CLIENTS}"

log_info "NFS export 대상 네트워크: $(echo "$NETWORKS" | tr '\n' ' ')"

# Add/update export entry
# 기존 SOURCE_PATH 관련 export 라인을 모두 제거 후 새로 추가
if grep -qF "$SOURCE_PATH" /etc/exports 2>/dev/null; then
    EXISTING_LINE=$(grep -F "$SOURCE_PATH" /etc/exports | head -1)
    if [[ "$EXISTING_LINE" == "$EXPORT_LINE" ]]; then
        log_ok "NFS export 이미 설정됨: $SOURCE_PATH"
    else
        log_warn "기존 NFS export 설정이 다릅니다. 업데이트합니다."
        log_info "  기존: $EXISTING_LINE"
        log_info "  변경: $EXPORT_LINE"
        sed -i "\|^${SOURCE_PATH} |d" /etc/exports
        echo "$EXPORT_LINE" >> /etc/exports
        log_ok "NFS export 업데이트 완료"
    fi
else
    echo "$EXPORT_LINE" >> /etc/exports
    log_ok "NFS export 추가 완료: $EXPORT_LINE"
fi

# Apply exports
if ! exportfs -ra 2>&1; then
    log_error "exportfs -ra 실패"
    exit 1
fi
log_ok "NFS export 적용 완료"

# Verify export is active
ACTIVE_EXPORTS=$(exportfs -v 2>/dev/null || true)
if echo "$ACTIVE_EXPORTS" | grep -qF "$SOURCE_PATH"; then
    log_ok "NFS export 활성 확인: $SOURCE_PATH"
else
    log_error "NFS export가 활성화되지 않았습니다: $SOURCE_PATH"
    log_info "exportfs -v 출력:"
    echo "$ACTIVE_EXPORTS"
    exit 1
fi

# Start/restart NFS server
systemctl enable nfs-kernel-server >/dev/null 2>&1
if ! systemctl restart nfs-kernel-server 2>&1; then
    log_error "NFS 서버 재시작 실패"
    systemctl status nfs-kernel-server --no-pager 2>&1 || true
    exit 1
fi
log_ok "NFS 서버 시작 완료"

echo ""

# ============================================================================
# Step 2: Mount NFS on All Nodes
# ============================================================================
echo -e "${BLUE}━━━ Step 2: 각 노드에 NFS 마운트 설정 ━━━${NC}"
echo ""

# Get current node's IP that's in the cluster network
CURRENT_NODE_IP=""
echo "$all_nodes_json" | python3 -c "
import json, sys
nodes = json.load(sys.stdin)
for n in nodes:
    print(n.get('ip_address','') + ' ' + n.get('hostname',''))
" | while IFS=' ' read -r node_ip node_hostname; do
    if echo "$CURRENT_IPS" | grep -qw "$node_ip" || [[ "$CURRENT_HOSTNAME" == "$node_hostname" ]]; then
        echo "$node_ip" > /tmp/_nfs_setup_current_ip
    fi
done

if [[ -f /tmp/_nfs_setup_current_ip ]]; then
    CURRENT_NODE_IP=$(cat /tmp/_nfs_setup_current_ip)
    rm -f /tmp/_nfs_setup_current_ip
fi

if [[ -z "$CURRENT_NODE_IP" ]]; then
    # Fallback: use first IP from hostname -I
    CURRENT_NODE_IP=$(echo "$CURRENT_IPS" | head -1)
    log_warn "클러스터 설정에서 현재 노드 IP를 찾지 못했습니다. ${CURRENT_NODE_IP}를 사용합니다."
fi

NFS_SERVER_IP="$CURRENT_NODE_IP"
log_info "NFS 서버 IP: $NFS_SERVER_IP"
echo ""

printf "%-25s %-18s %-12s %-40s\n" "HOSTNAME" "IP ADDRESS" "ROLE" "STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

# Get SSH password from config
SSH_PASSWORD=$(python3 -c "
import yaml, sys
with open('$CONFIG_PATH') as f:
    config = yaml.safe_load(f)
print(config.get('cluster_info', {}).get('ssh_password', ''))
" 2>/dev/null || echo "")

echo "$all_nodes_json" | python3 -c "
import json, sys
nodes = json.load(sys.stdin)
for n in nodes:
    ip = n.get('ip_address','')
    hostname = n.get('hostname','')
    role = n.get('node_role','unknown')
    ssh_user = n.get('ssh_user','root')
    ssh_port = n.get('ssh_port', 22)
    ssh_key = n.get('ssh_key_path','')
    print(f'{ip}|{hostname}|{role}|{ssh_user}|{ssh_port}|{ssh_key}')
" | while IFS='|' read -r NODE_IP NODE_HOSTNAME NODE_ROLE SSH_USER SSH_PORT SSH_KEY; do
    IS_CURRENT=false
    if echo "$CURRENT_IPS" | grep -qw "$NODE_IP" || [[ "$CURRENT_HOSTNAME" == "$NODE_HOSTNAME" ]]; then
        IS_CURRENT=true
    fi

    # Build SSH options
    SSH_OPTS="-n -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes -p $SSH_PORT"
    if [[ -n "$SSH_KEY" ]] && [[ "$SSH_KEY" != "null" ]]; then
        # Expand ~ to actual home directory
        EXPANDED_KEY="${SSH_KEY/#\~/$HOME}"
        if [[ -f "$EXPANDED_KEY" ]]; then
            SSH_OPTS="$SSH_OPTS -i $EXPANDED_KEY"
        fi
    fi

    SSH_TARGET="${SSH_USER}@${NODE_IP}"

    # --- Current node handling ---
    if [[ "$IS_CURRENT" == "true" ]]; then
        if [[ "$SOURCE_PATH" == "$MOUNT_PATH" ]]; then
            printf "%-25s %-18s %-12s ${CYAN}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[SKIP] 현재 노드 - 소스/마운트 경로 동일"
            SKIP_COUNT=$((SKIP_COUNT + 1))
            echo "$SKIP_COUNT" > /tmp/_nfs_skip_count
            continue
        else
            # Current node but different path - bind mount or NFS loopback
            if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
                CURRENT_MOUNT_SRC=$(findmnt -n -o SOURCE "$MOUNT_PATH" 2>/dev/null || echo "")
                if echo "$CURRENT_MOUNT_SRC" | grep -q "$SOURCE_PATH"; then
                    printf "%-25s %-18s %-12s ${CYAN}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[SKIP] 현재 노드 - 이미 마운트됨"
                    SKIP_COUNT=$((SKIP_COUNT + 1))
                    echo "$SKIP_COUNT" > /tmp/_nfs_skip_count
                    continue
                fi
            fi
            # Create mount point and bind mount
            mkdir -p "$MOUNT_PATH"
            mount --bind "$SOURCE_PATH" "$MOUNT_PATH" 2>/dev/null
            # Add to fstab if not exists
            FSTAB_ENTRY="$SOURCE_PATH $MOUNT_PATH none bind 0 0"
            if ! grep -qF "$MOUNT_PATH" /etc/fstab 2>/dev/null; then
                echo "$FSTAB_ENTRY" >> /etc/fstab
            fi
            printf "%-25s %-18s %-12s ${GREEN}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[OK] 현재 노드 - bind mount 설정 완료"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            echo "$SUCCESS_COUNT" > /tmp/_nfs_success_count
            continue
        fi
    fi

    # --- Remote node handling ---
    # Check SSH connectivity
    if ! ssh $SSH_OPTS "$SSH_TARGET" "echo ok" >/dev/null 2>&1; then
        printf "%-25s %-18s %-12s ${RED}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[FAIL] SSH 연결 실패"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "$FAIL_COUNT" > /tmp/_nfs_fail_count
        continue
    fi

    # Check if already mounted
    MOUNT_CHECK=$(ssh $SSH_OPTS "$SSH_TARGET" "
        if mountpoint -q '$MOUNT_PATH' 2>/dev/null; then
            MOUNT_SRC=\$(findmnt -n -o SOURCE '$MOUNT_PATH' 2>/dev/null || echo '')
            if echo \"\$MOUNT_SRC\" | grep -q '$NFS_SERVER_IP'; then
                echo 'ALREADY_MOUNTED'
            else
                echo 'DIFFERENT_MOUNT'
            fi
        elif [ -d '$MOUNT_PATH' ] && [ \"\$(ls -A '$MOUNT_PATH' 2>/dev/null)\" ]; then
            echo 'PATH_EXISTS_NOT_EMPTY'
        else
            echo 'NOT_MOUNTED'
        fi
    " 2>/dev/null || echo "SSH_ERROR")

    case "$MOUNT_CHECK" in
        ALREADY_MOUNTED)
            printf "%-25s %-18s %-12s ${CYAN}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[SKIP] 이미 마운트됨 ($MOUNT_PATH)"
            SKIP_COUNT=$((SKIP_COUNT + 1))
            echo "$SKIP_COUNT" > /tmp/_nfs_skip_count
            ;;
        PATH_EXISTS_NOT_EMPTY)
            printf "%-25s %-18s %-12s ${YELLOW}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[WARN] 경로에 데이터 존재 - 건너뜀 ($MOUNT_PATH)"
            SKIP_COUNT=$((SKIP_COUNT + 1))
            echo "$SKIP_COUNT" > /tmp/_nfs_skip_count
            ;;
        DIFFERENT_MOUNT)
            printf "%-25s %-18s %-12s ${YELLOW}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[WARN] 다른 소스로 마운트됨 - 건너뜀"
            SKIP_COUNT=$((SKIP_COUNT + 1))
            echo "$SKIP_COUNT" > /tmp/_nfs_skip_count
            ;;
        NOT_MOUNTED)
            # Install NFS client (offline apt) if needed, then mount
            NFS_INSTALLED=$(ssh $SSH_OPTS "$SSH_TARGET" "dpkg -s nfs-common &>/dev/null && echo YES || echo NO" 2>/dev/null || echo "NO")

            if [[ "$NFS_INSTALLED" == "NO" ]]; then
                # Transfer NFS packages to remote node
                REMOTE_TMP="/tmp/_nfs_offline_pkgs"
                ssh $SSH_OPTS "$SSH_TARGET" "mkdir -p $REMOTE_TMP" 2>/dev/null
                SCP_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes -P $SSH_PORT"
                if [[ -n "$SSH_KEY" ]] && [[ "$SSH_KEY" != "null" ]]; then
                    EXPANDED_KEY="${SSH_KEY/#\~/$HOME}"
                    if [[ -f "$EXPANDED_KEY" ]]; then
                        SCP_OPTS="$SCP_OPTS -i $EXPANDED_KEY"
                    fi
                fi
                scp $SCP_OPTS "$NFS_PKG_DIR"/*.deb "$NFS_PKG_DIR/Packages" "$NFS_PKG_DIR/Packages.gz" "${SSH_TARGET}:${REMOTE_TMP}/" >/dev/null 2>&1

                # Setup local APT repo on remote and install via apt-get (sudo 필요)
                ssh $SSH_OPTS "$SSH_TARGET" "sudo bash -c '
                    REPO_LIST=/etc/apt/sources.list.d/nfs-offline-local.list
                    echo \"deb [trusted=yes] file://${REMOTE_TMP} ./\" > \"\$REPO_LIST\"
                    APT_OPTS=\"-o Dir::Etc::sourcelist=\$REPO_LIST -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0\"
                    apt-get update \$APT_OPTS >/dev/null 2>&1 || true
                    DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 \
                        apt-get install -y --no-install-recommends \$APT_OPTS nfs-common 2>&1 || \
                    DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 \
                        apt-get install -f -y \$APT_OPTS 2>&1 || true
                    rm -f \"\$REPO_LIST\"
                    rm -rf \"${REMOTE_TMP}\"
                '" 2>/dev/null

                # Verify installation
                NFS_VERIFY=$(ssh $SSH_OPTS "$SSH_TARGET" "dpkg -s nfs-common &>/dev/null && echo YES || echo NO" 2>/dev/null || echo "NO")
                if [[ "$NFS_VERIFY" == "NO" ]]; then
                    printf "%-25s %-18s %-12s ${RED}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[FAIL] nfs-common 패키지 설치 실패"
                    FAIL_COUNT=$((FAIL_COUNT + 1))
                    echo "$FAIL_COUNT" > /tmp/_nfs_fail_count
                    continue
                fi
            fi

            SETUP_RESULT=$(ssh $SSH_OPTS "$SSH_TARGET" "sudo bash -c '
                # Create mount point
                mkdir -p \"$MOUNT_PATH\"

                # Mount NFS
                mount -t nfs \"$NFS_SERVER_IP:$SOURCE_PATH\" \"$MOUNT_PATH\" -o rw,hard,intr,nfsvers=3 >/dev/null 2>&1

                # Verify mount by checking mountpoint (systemd 메시지에 영향받지 않음)
                if mountpoint -q \"$MOUNT_PATH\" 2>/dev/null; then
                    # Add to fstab for persistent mount
                    FSTAB_LINE=\"$NFS_SERVER_IP:$SOURCE_PATH $MOUNT_PATH nfs rw,hard,intr,nfsvers=3 0 0\"
                    if ! grep -qF \"$MOUNT_PATH\" /etc/fstab 2>/dev/null; then
                        echo \"\$FSTAB_LINE\" >> /etc/fstab
                    fi
                    echo MOUNT_OK
                else
                    echo \"MOUNT_FAIL:\$(mount -t nfs \"$NFS_SERVER_IP:$SOURCE_PATH\" \"$MOUNT_PATH\" -o rw,hard,intr,nfsvers=3 2>&1)\"
                fi
            '" 2>&1 || echo "MOUNT_FAIL:SSH command failed")

            if echo "$SETUP_RESULT" | grep -q "MOUNT_OK"; then
                printf "%-25s %-18s %-12s ${GREEN}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[OK] NFS 마운트 완료 ($MOUNT_PATH)"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                echo "$SUCCESS_COUNT" > /tmp/_nfs_success_count
            else
                FAIL_REASON=$(echo "$SETUP_RESULT" | grep "MOUNT_FAIL" | sed 's/MOUNT_FAIL://' | head -1)
                printf "%-25s %-18s %-12s ${RED}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[FAIL] NFS 마운트 실패"
                if [[ -n "$FAIL_REASON" ]]; then
                    echo -e "  ${RED}  -> $FAIL_REASON${NC}"
                fi
                FAIL_COUNT=$((FAIL_COUNT + 1))
                echo "$FAIL_COUNT" > /tmp/_nfs_fail_count
            fi
            ;;
        *)
            printf "%-25s %-18s %-12s ${RED}%-40s${NC}\n" "$NODE_HOSTNAME" "$NODE_IP" "$NODE_ROLE" "[FAIL] 상태 확인 실패"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo "$FAIL_COUNT" > /tmp/_nfs_fail_count
            ;;
    esac
done

# Read final counts from temp files (subshell workaround)
FINAL_SUCCESS=$(cat /tmp/_nfs_success_count 2>/dev/null || echo "0")
FINAL_SKIP=$(cat /tmp/_nfs_skip_count 2>/dev/null || echo "0")
FINAL_FAIL=$(cat /tmp/_nfs_fail_count 2>/dev/null || echo "0")
rm -f /tmp/_nfs_success_count /tmp/_nfs_skip_count /tmp/_nfs_fail_count

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}[결과 요약]${NC}"
echo -e "  ${GREEN}성공:${NC} ${FINAL_SUCCESS}개 노드"
echo -e "  ${CYAN}건너뜀:${NC} ${FINAL_SKIP}개 노드"
echo -e "  ${RED}실패:${NC} ${FINAL_FAIL}개 노드"
echo ""

if [[ "$FINAL_FAIL" -gt 0 ]]; then
    log_warn "일부 노드에서 실패했습니다. SSH 연결 및 NFS 설정을 확인해주세요."
    exit 1
fi

log_ok "NFS 공유 설정이 완료되었습니다."
