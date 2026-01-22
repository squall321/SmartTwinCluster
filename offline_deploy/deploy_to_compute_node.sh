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
#   ./deploy_to_compute_node.sh --config my_multihead_cluster.yaml
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

# 로그 파일 설정
LOG_FILE="${SCRIPT_DIR}/deploy.log"
LOG_FILE_TIMESTAMPED="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# 기존 deploy.log가 있으면 백업
if [[ -f "$LOG_FILE" ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.bak"
fi

# stdout/stderr를 tee로 파일과 터미널 모두에 출력
exec > >(tee "$LOG_FILE" | tee "$LOG_FILE_TIMESTAMPED")
exec 2>&1

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
# export하여 서브쉘(병렬 배포)에서도 사용 가능하게 함
export SSH_PASSWORD=""
export HAS_SSHPASS=false
export SSHPASS=""

setup_ssh_auth() {
    # YAML에서 ssh_password 읽기
    SSH_PASSWORD=$(python3 << EOPY
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
print(config.get('cluster_info', {}).get('ssh_password', ''))
EOPY
    )
    export SSH_PASSWORD

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
    export HAS_SSHPASS

    if [[ -n "$SSH_PASSWORD" ]]; then
        # SSHPASS 환경변수 설정 (sshpass -e 옵션용)
        export SSHPASS="$SSH_PASSWORD"
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


# 계산 노드 및 viz 노드 목록 추출
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

# compute_nodes 추출 (node_type 필드로 compute/viz 구분)
compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
for node in compute_nodes:
    if 'hostname' not in node or 'ip_address' not in node:
        print(f"WARNING: Skipping invalid compute node (missing hostname or ip_address): {node}", file=sys.stderr)
        continue
    # node_type 필드로 viz 노드 구분 (기본값: compute)
    node_type = node.get('node_type', 'compute')
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark'),
        'type': node_type
    })

# viz_nodes 추출 (slurmd도 필요)
viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
for node in viz_nodes:
    if 'hostname' not in node or 'ip_address' not in node:
        print(f"WARNING: Skipping invalid viz node (missing hostname or ip_address): {node}", file=sys.stderr)
        continue
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark'),
        'type': 'viz'
    })

if not nodes:
    print("WARNING: No compute_nodes or viz_nodes found in YAML", file=sys.stderr)
    print("Expected structure: nodes.compute_nodes[]/viz_nodes[].hostname/ip_address", file=sys.stderr)

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
    # SSH/SCP 명령 구성 (sshpass 사용 여부에 따라)
    # sshpass -e 옵션: SSHPASS 환경변수에서 비밀번호 읽기 (특수문자 안전)
    # SSH 옵션: -n으로 stdin을 /dev/null로 리다이렉트 (백그라운드 실행 시 stdin 충돌 방지)
    # 단, heredoc을 사용하는 SSH 호출은 -n 없이 별도 변수 사용
    local ssh_cmd="ssh -n -o StrictHostKeyChecking=no"
    local ssh_cmd_stdin="ssh -o StrictHostKeyChecking=no"  # heredoc용 (stdin 필요)
    local scp_cmd="scp -o StrictHostKeyChecking=no"
    if [[ -n "$SSH_PASSWORD" && "$HAS_SSHPASS" == "true" ]]; then
        export SSHPASS="$SSH_PASSWORD"
        ssh_cmd="sshpass -e ssh -n -o StrictHostKeyChecking=no"
        ssh_cmd_stdin="sshpass -e ssh -o StrictHostKeyChecking=no"
        scp_cmd="sshpass -e scp -o StrictHostKeyChecking=no"
    fi

    if ! $ssh_cmd -o ConnectTimeout=5 "$node_user@$node_ip" "echo OK" &>/dev/null; then
        log_error "[$node_hostname] SSH connection failed"
        return 1
    fi

    log_success "[$node_hostname] SSH connection OK"

    # scp로 패키지 전송 (rsync 권한 문제 회피)
    # 홈 디렉토리 사용 - 사용자 권한으로 접근 가능
    local REMOTE_PKG_DIR="~/offline_packages"
    log_info "[$node_hostname] Transferring packages to $REMOTE_PKG_DIR (this may take 5-10 minutes)..."

    # 기존 디렉토리 삭제 후 재생성 (완전히 새로운 패키지로 배포)
    log_info "[$node_hostname] Removing old packages directory: $REMOTE_PKG_DIR"

    # 권한 문제 대비: 먼저 소유권 복원 시도 (root 소유 파일 방지)
    $ssh_cmd "$node_user@$node_ip" "if [[ -d $REMOTE_PKG_DIR ]]; then sudo chown -R \$(whoami):\$(whoami) $REMOTE_PKG_DIR 2>/dev/null || true; fi"

    # 삭제 후 재생성
    if ! $ssh_cmd "$node_user@$node_ip" "rm -rf $REMOTE_PKG_DIR && mkdir -p $REMOTE_PKG_DIR"; then
        log_warning "[$node_hostname] Failed to remove with user permission, trying sudo..."
        $ssh_cmd "$node_user@$node_ip" "sudo rm -rf $REMOTE_PKG_DIR && mkdir -p $REMOTE_PKG_DIR" || {
            log_error "[$node_hostname] Failed to recreate remote directory $REMOTE_PKG_DIR"
            return 1
        }
    fi
    log_success "[$node_hostname] Old packages removed - starting fresh deployment"

    # 개별 디렉토리 전송 (munge/munge.key 권한 문제 회피)
    # offline_packages/munge/munge.key는 root만 읽기 가능하므로 scp로 복사 불가
    local pkg_dir="${PACKAGE_DIR%/}"
    local transfer_failed=false

    for subdir in "$pkg_dir"/*; do
        [[ ! -e "$subdir" ]] && continue
        local name=$(basename "$subdir")

        # munge 디렉토리는 munge.key 때문에 스킵 (나중에 /etc/munge/munge.key에서 복사)
        if [[ "$name" == "munge" ]]; then
            # deploy_munge.sh만 복사
            $ssh_cmd "$node_user@$node_ip" "mkdir -p $REMOTE_PKG_DIR/munge" || true
            if [[ -f "$subdir/deploy_munge.sh" ]]; then
                $scp_cmd "$subdir/deploy_munge.sh" "$node_user@$node_ip:$REMOTE_PKG_DIR/munge/" || true
            fi
            continue
        fi

        # slurm 디렉토리는 tar.gz만 복사하고, sh 파일들은 별도로 복사 (유지보수 용이)
        if [[ "$name" == "slurm" ]]; then
            $ssh_cmd "$node_user@$node_ip" "mkdir -p $REMOTE_PKG_DIR/slurm" || true
            # tar.gz 파일만 복사
            for tarfile in "$subdir"/*.tar.gz; do
                [[ -f "$tarfile" ]] && $scp_cmd "$tarfile" "$node_user@$node_ip:$REMOTE_PKG_DIR/slurm/" || true
            done
            # sh 파일들 별도 복사 (서버의 최신 버전 사용)
            for shfile in "$subdir"/*.sh; do
                [[ -f "$shfile" ]] && $scp_cmd "$shfile" "$node_user@$node_ip:$REMOTE_PKG_DIR/slurm/" || true
            done
            continue
        fi

        $scp_cmd -r "$subdir" "$node_user@$node_ip:$REMOTE_PKG_DIR/" || {
            log_warning "[$node_hostname] Failed to transfer $name"
            transfer_failed=true
        }
    done

    if [[ "$transfer_failed" == "true" ]]; then
        log_warning "[$node_hostname] Some packages failed to transfer, continuing..."
    fi

    # 컨트롤러의 slurm.conf 전송 (PluginDir 경로가 올바른 버전)
    log_info "[$node_hostname] Transferring slurm.conf from controller..."
    local SLURM_CONF_LOCAL="/etc/slurm/slurm.conf"
    if [[ -f "$SLURM_CONF_LOCAL" ]]; then
        $scp_cmd "$SLURM_CONF_LOCAL" "$node_user@$node_ip:$REMOTE_PKG_DIR/slurm.conf" || {
            log_warning "[$node_hostname] Failed to transfer slurm.conf (will use existing)"
        }
        log_success "[$node_hostname] slurm.conf transferred"
    else
        log_warning "[$node_hostname] Controller slurm.conf not found at $SLURM_CONF_LOCAL"
    fi

    # gres.conf 전송 (GPU 노드용)
    log_info "[$node_hostname] Transferring gres.conf from controller (if exists)..."
    local GRES_CONF_LOCAL="/etc/slurm/gres.conf"
    if [[ -f "$GRES_CONF_LOCAL" ]]; then
        $scp_cmd "$GRES_CONF_LOCAL" "$node_user@$node_ip:$REMOTE_PKG_DIR/gres.conf" || {
            log_warning "[$node_hostname] Failed to transfer gres.conf"
        }
        log_success "[$node_hostname] gres.conf transferred"
    else
        log_info "[$node_hostname] gres.conf not found on controller (OK for non-GPU clusters)"
    fi

    # 컨트롤러의 munge.key 전송 (모든 노드가 동일한 키 사용 필수)
    # sudo cat으로 파이프하여 권한 문제 회피 (munge.key는 400 권한, munge 소유)
    log_info "[$node_hostname] Transferring munge.key from controller..."
    local MUNGE_KEY_LOCAL="/etc/munge/munge.key"
    if /usr/bin/sudo test -f "$MUNGE_KEY_LOCAL"; then
        # 원격에서 $HOME 환경변수를 사용하여 경로 확장 (~ 대신 $HOME 사용)
        $ssh_cmd "$node_user@$node_ip" 'mkdir -p $HOME/offline_packages/munge' || {
            log_error "[$node_hostname] Failed to create munge directory"
            return 1
        }

        # 기존 munge.key 및 디렉토리 권한 정리 (이전 배포에서 root 소유일 수 있음)
        log_info "[$node_hostname] Cleaning old munge.key and fixing permissions..."
        # 원격에서 run_sudo 사용 - 디렉토리 소유권을 현재 사용자로 변경 후 파일 삭제
        # ssh_cmd_stdin 사용 (heredoc이므로 stdin 필요)
        # SSH_PASSWORD를 인자로 전달, heredoc은 큰따옴표로 원격 변수 확장 허용
        $ssh_cmd_stdin "$node_user@$node_ip" bash -s "$SSH_PASSWORD" <<EOFCLEAN
SUDO_PASS="\$1"
# 디렉토리가 존재하면 소유권을 현재 사용자로 변경
if [[ -d \$HOME/offline_packages/munge ]]; then
    if [[ -n "\$SUDO_PASS" ]]; then
        echo "\$SUDO_PASS" | sudo -S chown -R \$(whoami):\$(whoami) \$HOME/offline_packages/munge 2>/dev/null || true
    else
        sudo chown -R \$(whoami):\$(whoami) \$HOME/offline_packages/munge 2>/dev/null || true
    fi
fi
# 이제 일반 사용자 권한으로 파일 삭제 가능
rm -f \$HOME/offline_packages/munge/munge.key 2>/dev/null || true
EOFCLEAN

        # sudo cat 사용 (munge.key는 400 권한이라 일반 사용자가 읽을 수 없음)
        # 원격 셸에서 $HOME이 확장되도록 작은따옴표 사용
        if /usr/bin/sudo cat "$MUNGE_KEY_LOCAL" | $ssh_cmd_stdin "$node_user@$node_ip" 'cat > $HOME/offline_packages/munge/munge.key'; then
            # 전송 확인 (파일 크기 비교)
            local local_size=$(/usr/bin/sudo stat -c%s "$MUNGE_KEY_LOCAL" 2>/dev/null || echo "0")
            local remote_size=$($ssh_cmd "$node_user@$node_ip" 'stat -c%s $HOME/offline_packages/munge/munge.key 2>/dev/null || echo "0"')

            if [[ "$local_size" -eq "$remote_size" ]] && [[ "$local_size" -gt 0 ]]; then
                log_success "[$node_hostname] munge.key transferred and verified ($local_size bytes)"
            else
                log_error "[$node_hostname] munge.key transfer verification failed (local: $local_size, remote: $remote_size)"
                return 1
            fi
        else
            log_error "[$node_hostname] Failed to transfer munge.key"
            log_error "[$node_hostname] Munge authentication WILL fail without matching key!"
            return 1
        fi
    else
        log_error "[$node_hostname] Controller munge.key not found at $MUNGE_KEY_LOCAL"
        log_error "[$node_hostname] Cannot deploy without munge key - run setup on controller first!"
        return 1
    fi

    log_success "[$node_hostname] Packages transferred"

    # /etc/hosts 업데이트 (컨트롤러 호스트명 추가)
    log_info "[$node_hostname] Updating /etc/hosts with cluster hostnames..."

    # YAML에서 모든 노드의 hostname/IP 추출하여 원격에 전달
    local hosts_entries
    hosts_entries=$(python3 << EOPY
import yaml

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

entries = []

# Controllers
for ctrl in config.get('nodes', {}).get('controllers', []):
    if ctrl.get('enabled', True):
        entries.append(f"{ctrl['ip_address']} {ctrl['hostname']}")

# Compute nodes
for node in config.get('nodes', {}).get('compute_nodes', []):
    entries.append(f"{node['ip_address']} {node['hostname']}")

# Viz nodes
for node in config.get('nodes', {}).get('viz_nodes', []):
    entries.append(f"{node['ip_address']} {node['hostname']}")

print('\\n'.join(entries))
EOPY
    )

    if [[ -n "$hosts_entries" ]]; then
        # hosts_entries를 base64로 인코딩하여 전달
        local encoded_hosts=$(echo "$hosts_entries" | base64 -w 0)

        # 원격에서 /etc/hosts 업데이트
        if [[ -n "$SSH_PASSWORD" ]]; then
            local encoded_pass_hosts=$(echo -n "$SSH_PASSWORD" | base64)
            $ssh_cmd_stdin "$node_user@$node_ip" bash -s "$encoded_hosts" "$encoded_pass_hosts" << 'EOFHOSTS'
HOSTS_B64="$1"
SUDO_PASS_B64="$2"

# base64 디코딩
HOSTS_ENTRIES=$(echo "$HOSTS_B64" | base64 -d)
SUDO_PASS=""
if [[ -n "$SUDO_PASS_B64" ]]; then
    SUDO_PASS=$(echo "$SUDO_PASS_B64" | base64 -d)
fi

run_sudo() {
    if [[ -n "$SUDO_PASS" ]]; then
        echo "$SUDO_PASS" | sudo -S "$@"
    else
        sudo "$@"
    fi
}

# 클러스터 호스트 섹션 마커
MARKER_START="# === Cluster Hosts (auto-generated) ==="
MARKER_END="# === End Cluster Hosts ==="

# 기존 클러스터 호스트 섹션 제거
run_sudo sed -i "/$MARKER_START/,/$MARKER_END/d" /etc/hosts 2>/dev/null || true

# 새 섹션 추가 (임시 파일 사용 - run_sudo tee의 stdin 문제 회피)
HOSTS_TMP="/tmp/hosts_entries.$$"
{
    echo ""
    echo "$MARKER_START"
    echo "$HOSTS_ENTRIES"
    echo "$MARKER_END"
} > "$HOSTS_TMP"
cat "$HOSTS_TMP" | run_sudo tee -a /etc/hosts > /dev/null
rm -f "$HOSTS_TMP"

echo "  /etc/hosts updated with cluster hostnames"
EOFHOSTS
        else
            $ssh_cmd_stdin "$node_user@$node_ip" bash -s "$encoded_hosts" << 'EOFHOSTS2'
HOSTS_B64="$1"
HOSTS_ENTRIES=$(echo "$HOSTS_B64" | base64 -d)

MARKER_START="# === Cluster Hosts (auto-generated) ==="
MARKER_END="# === End Cluster Hosts ==="

sudo sed -i "/$MARKER_START/,/$MARKER_END/d" /etc/hosts 2>/dev/null || true

{
    echo ""
    echo "$MARKER_START"
    echo "$HOSTS_ENTRIES"
    echo "$MARKER_END"
} | sudo tee -a /etc/hosts > /dev/null

echo "  /etc/hosts updated with cluster hostnames"
EOFHOSTS2
        fi
        log_success "[$node_hostname] /etc/hosts updated"
    else
        log_warning "[$node_hostname] Failed to extract hosts entries from YAML"
    fi

    # 원격 설치 스크립트 실행
    log_info "[$node_hostname] Installing packages..."

    # 원격 설치 스크립트 실행 (sudo 비밀번호는 base64 인코딩하여 전달)
    local encoded_pass=""
    if [[ -n "$SSH_PASSWORD" ]]; then
        encoded_pass=$(echo -n "$SSH_PASSWORD" | base64)
    fi

    # heredoc을 사용하므로 stdin이 필요한 ssh_cmd_stdin 사용
    log_info "[$node_hostname] Starting remote deployment script via SSH heredoc..."
    log_info "[$node_hostname] SSH command: $ssh_cmd_stdin $node_user@$node_ip bash -s [args...]"

    # 에러 캡처를 위한 임시 파일
    local ssh_error_log="/tmp/deploy_ssh_error_${node_hostname}_$$.log"

    # SSH heredoc 실행 (exit code 저장)
    $ssh_cmd_stdin "$node_user@$node_ip" bash -s "$gluster_server" "$gluster_volume" "$gluster_mount" "$encoded_pass" "$HEADNODE_SLURM_UID" "$HEADNODE_SLURM_GID" 2>"$ssh_error_log" << 'EOFREMOTE'
# set -e는 Step 0 이후에 활성화 (초기화 작업은 실패해도 계속 진행)

GLUSTER_SERVER="$1"
GLUSTER_VOLUME="$2"
GLUSTER_MOUNT="$3"
SUDO_PASS_B64="$4"
SLURM_UID="$5"
SLURM_GID="$6"

# 패키지 디렉토리 (홈 디렉토리 사용)
PKG_DIR="$HOME/offline_packages"

# base64 디코딩하여 실제 비밀번호 복원 (실패해도 계속 진행)
SUDO_PASS=""
if [[ -n "$SUDO_PASS_B64" ]]; then
    SUDO_PASS=$(echo "$SUDO_PASS_B64" | base64 -d 2>/dev/null) || {
        echo "ERROR: Failed to decode password (base64 invalid input)"
        echo "This may indicate SSH_PASSWORD is not properly set"
        exit 1
    }
fi

# sudo 래퍼 함수 (비밀번호 자동 전달)
run_sudo() {
    if [[ -n "$SUDO_PASS" ]]; then
        # -S: stdin에서 비밀번호 읽기
        echo "$SUDO_PASS" | sudo -S "$@"
    else
        sudo "$@"
    fi
}

echo "═══════════════════════════════════════════════════════════"
echo "  Offline Package Installation (Compute Node)"
echo "  Package directory: $PKG_DIR"
echo "═══════════════════════════════════════════════════════════"

# 0. 강제 초기화 - 기존 서비스 중지 및 설정 정리
echo ""
echo "Step 0: Force cleanup (idempotent deployment)..."

# slurmd 강제 중지
echo "  Stopping slurmd..."
run_sudo systemctl stop slurmd 2>/dev/null || true
run_sudo systemctl disable slurmd 2>/dev/null || true

# 기존 slurmd.service 파일 삭제 (잘못된 경로 설정 방지)
echo "  Removing old slurmd.service..."

# 여러 방법으로 삭제 시도 (권한 문제 대비)
if [[ -f /etc/systemd/system/slurmd.service ]]; then
    echo "  Found existing slurmd.service, removing..."
    run_sudo rm -f /etc/systemd/system/slurmd.service 2>/dev/null || \
    sudo rm -f /etc/systemd/system/slurmd.service 2>/dev/null || \
    rm -f /etc/systemd/system/slurmd.service 2>/dev/null || true

    # 삭제 확인
    if [[ -f /etc/systemd/system/slurmd.service ]]; then
        echo "  ⚠️  WARNING: Failed to remove slurmd.service, forcing removal..."
        sudo chmod 666 /etc/systemd/system/slurmd.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/slurmd.service 2>/dev/null || true
    fi

    if [[ ! -f /etc/systemd/system/slurmd.service ]]; then
        echo "  ✓ Old slurmd.service removed successfully"
    else
        echo "  ✗ ERROR: Could not remove slurmd.service!"
    fi
else
    echo "  No old slurmd.service found"
fi

run_sudo rm -f /lib/systemd/system/slurmd.service 2>/dev/null || true
run_sudo systemctl daemon-reload 2>/dev/null || true

# munge 강제 중지
echo "  Stopping munge..."
run_sudo systemctl stop munge 2>/dev/null || true

# 기존 slurm 설정 정리 (모든 가능한 경로)
echo "  Cleaning old slurm configs..."
run_sudo rm -f /etc/slurm/slurm.conf 2>/dev/null || true
run_sudo rm -f /usr/local/slurm/etc/slurm.conf 2>/dev/null || true
run_sudo rm -f /opt/slurm/etc/slurm.conf 2>/dev/null || true
run_sudo rm -f /etc/slurm/gres.conf 2>/dev/null || true
run_sudo rm -f /usr/local/slurm/etc/gres.conf 2>/dev/null || true
run_sudo rm -f /opt/slurm/etc/gres.conf 2>/dev/null || true

# 기존 munge 키 정리 (새 키로 교체 준비)
echo "  Cleaning old munge key..."
run_sudo rm -f /etc/munge/munge.key 2>/dev/null || true

# PID 파일 정리
echo "  Cleaning stale PID files..."
run_sudo rm -f /run/slurm/slurmd.pid 2>/dev/null || true
run_sudo rm -f /run/munge/munged.pid 2>/dev/null || true

# $HOME/offline_packages 디렉토리 소유권 복원 (root가 만든 파일이 있을 수 있음)
echo "  Restoring ownership of $PKG_DIR..."
if [[ -d "$PKG_DIR" ]]; then
    run_sudo chown -R $(whoami):$(whoami) "$PKG_DIR" 2>/dev/null || true
fi

echo "  ✓ Cleanup complete"

# Step 0 완료 - 이제부터 set -e 활성화 (에러 발생 시 즉시 종료)
set -e

# 현재 노드가 controller인지 확인
IS_CONTROLLER=false
HOSTNAME=$(hostname)
if systemctl is-active --quiet slurmctld 2>/dev/null || \
   systemctl is-enabled --quiet slurmctld 2>/dev/null || \
   [[ -f /etc/systemd/system/slurmctld.service ]] || \
   pgrep -x slurmctld >/dev/null 2>&1; then
    IS_CONTROLLER=true
    echo ""
    echo "  ℹ️  Detected: This node ($HOSTNAME) is a controller"
    echo "  ℹ️  Controller+compute/viz mode: installing only missing packages"
fi

# 1. APT 패키지 설치
if [[ -f "$PKG_DIR/apt_packages/install_offline_packages.sh" ]]; then
    echo ""
    if [[ "$IS_CONTROLLER" == "true" ]]; then
        echo "Step 1: Installing missing packages (controller already has most)..."

        # apptainer만 체크해서 설치
        if ! command -v apptainer &>/dev/null; then
            echo "  Installing apptainer for job execution..."
            run_sudo apt-get update >/dev/null 2>&1
            run_sudo apt-get install -y apptainer 2>&1 | grep -E "Setting up|installed|apptainer" || true
            if command -v apptainer &>/dev/null; then
                echo "  ✓ apptainer installed: $(apptainer --version)"
            else
                echo "  ⚠️  apptainer installation failed - trying offline packages"
                cd "$PKG_DIR/apt_packages"
                run_sudo bash install_offline_packages.sh
            fi
        else
            echo "  ✓ apptainer already installed: $(apptainer --version)"
        fi
    else
        echo "Step 1: Installing APT packages..."
        cd "$PKG_DIR/apt_packages"
        run_sudo bash install_offline_packages.sh
    fi
else
    echo "WARNING: APT packages not found"
fi

# 2. Slurm 배포 (controller는 이미 설치되어 있으므로 스킵)
if [[ "$IS_CONTROLLER" == "true" ]]; then
    echo ""
    echo "Step 2: Skipping Slurm deployment (already installed as controller)..."
    echo "  ✓ Slurm version: $(sinfo --version 2>/dev/null || echo 'installed')"
    # Skip to Step 2.5
fi

# 2. Slurm 배포 (compute 노드만)
# Note: [[ -f glob ]]는 glob 확장하지 않으므로 ls 사용
SLURM_PKG=$(ls "$PKG_DIR/slurm"/slurm-*-prebuilt.tar.gz 2>/dev/null | head -1 || true)
if [[ "$IS_CONTROLLER" == "false" ]] && [[ -n "$SLURM_PKG" && -f "$SLURM_PKG" ]]; then
    echo ""
    echo "Step 2: Deploying Slurm..."
    echo "  Found: $SLURM_PKG"
    cd "$PKG_DIR/slurm"

    # tar 압축 해제 (sh 파일 제외 - 서버에서 복사한 최신 버전 사용)
    echo "  Extracting to: $(pwd)"
    tar -xzf "$SLURM_PKG" --exclude='*.sh'

    # 압축 해제 결과 확인
    if [[ -d "opt/slurm" ]]; then
        echo "  ✓ Extraction successful: opt/slurm exists"
        ls -la opt/slurm/ | head -5
    else
        echo "  ✗ Extraction failed: opt/slurm not found"
        echo "  Contents of $(pwd):"
        ls -la
    fi

    # deploy_slurm.sh 실행 (UID/GID 환경변수 전달)
    if [[ -f "deploy_slurm.sh" ]]; then
        SLURM_UID="$SLURM_UID" SLURM_GID="$SLURM_GID" run_sudo -E bash deploy_slurm.sh
    else
        echo "  ✗ deploy_slurm.sh not found after extraction"
    fi
else
    echo "WARNING: Slurm package not found"
    echo "  Expected: $PKG_DIR/slurm/slurm-*-prebuilt.tar.gz"
    ls -la "$PKG_DIR/slurm/" 2>/dev/null || echo "  Directory not found"
fi

# 2.5. slurm.conf 복사 (컨트롤러에서 전송된 파일 사용)
echo ""
echo "Step 2.5: Configuring slurm.conf..."
SLURM_CONF_SRC="$PKG_DIR/slurm.conf"
SLURM_CONF_DEST="/etc/slurm/slurm.conf"
SLURM_LOCAL_CONF="/usr/local/slurm/etc/slurm.conf"

if [[ -f "$SLURM_CONF_SRC" ]]; then
    echo "  Found slurm.conf from controller"

    # /etc/slurm 디렉토리 생성
    run_sudo mkdir -p /etc/slurm
    run_sudo mkdir -p /usr/local/slurm/etc

    # 강제 덮어쓰기 (Step 0에서 이미 삭제됨)
    run_sudo cp -f "$SLURM_CONF_SRC" "$SLURM_CONF_DEST"
    run_sudo cp "$SLURM_CONF_SRC" "$SLURM_LOCAL_CONF"
    run_sudo chown slurm:slurm "$SLURM_CONF_DEST" "$SLURM_LOCAL_CONF" 2>/dev/null || true
    run_sudo chmod 644 "$SLURM_CONF_DEST" "$SLURM_LOCAL_CONF"

    echo "  ✓ slurm.conf installed to $SLURM_CONF_DEST"
    echo "  ✓ slurm.conf installed to $SLURM_LOCAL_CONF"

    # PluginDir 확인
    PLUGIN_DIR=$(grep "^PluginDir=" "$SLURM_CONF_DEST" 2>/dev/null | head -1)
    echo "  ✓ $PLUGIN_DIR"
else
    echo "  WARNING: slurm.conf not found in $PKG_DIR/"
    echo "  Using existing configuration (may cause PluginDir errors)"
fi

# 2.6. gres.conf 복사 (GPU 노드인 경우)
echo ""
echo "Step 2.6: Configuring gres.conf (GPU resources)..."
GRES_CONF_SRC="$PKG_DIR/gres.conf"
GRES_CONF_DEST="/etc/slurm/gres.conf"

if [[ -f "$GRES_CONF_SRC" ]]; then
    echo "  Found gres.conf from controller"

    # /etc/slurm 디렉토리 생성 (이미 있을 것임)
    run_sudo mkdir -p /etc/slurm

    # 강제 덮어쓰기
    run_sudo cp -f "$GRES_CONF_SRC" "$GRES_CONF_DEST"
    run_sudo chown slurm:slurm "$GRES_CONF_DEST" 2>/dev/null || true
    run_sudo chmod 644 "$GRES_CONF_DEST"

    echo "  ✓ gres.conf installed to $GRES_CONF_DEST"

    # 이 노드가 GPU 노드인지 확인
    HOSTNAME=$(hostname)
    if grep -q "^NodeName=$HOSTNAME.*Name=gpu" "$GRES_CONF_DEST" 2>/dev/null; then
        echo "  ✓ This node ($HOSTNAME) is configured for GPU resources"
    else
        echo "  ℹ️  This node ($HOSTNAME) has no GPU configuration (OK for non-GPU nodes)"
    fi
else
    echo "  ℹ️  gres.conf not found - no GPU resources configured"
fi

# 3. Munge 배포
if [[ -f "$PKG_DIR/munge/deploy_munge.sh" ]]; then
    echo ""
    echo "Step 3: Deploying Munge..."
    cd "$PKG_DIR/munge"
    run_sudo bash deploy_munge.sh

    # Munge 서비스 재시작 확인 및 slurmd 재시작
    echo ""
    echo "  Verifying munge service..."
    sleep 2  # munge 시작 대기

    if run_sudo systemctl is-active --quiet munge; then
        echo "  ✓ Munge is running"
    else
        echo "  ⚠️  Munge not running, attempting restart..."
        run_sudo systemctl restart munge
        sleep 3
        if run_sudo systemctl is-active --quiet munge; then
            echo "  ✓ Munge restarted successfully"
        else
            echo "  ✗ ERROR: Munge failed to start"
            run_sudo systemctl status munge --no-pager || true
        fi
    fi

    # slurmd 재시작 (새 munge key 적용)
    echo "  Restarting slurmd to apply new munge key..."
    if run_sudo systemctl is-active --quiet slurmd; then
        run_sudo systemctl restart slurmd
    else
        echo "  Note: slurmd not running yet (will be started in Step 5)"
    fi

    echo "  Waiting for services to stabilize..."
    sleep 5

    # 최종 서비스 상태 확인
    echo "  Final service status check:"
    if run_sudo systemctl is-active --quiet munge; then
        echo "    ✓ munge: running"
    else
        echo "    ✗ munge: NOT running"
    fi

    if run_sudo systemctl is-active --quiet slurmd 2>/dev/null; then
        echo "    ✓ slurmd: running"
    else
        echo "    - slurmd: not started yet (normal if first deployment)"
    fi
else
    echo "WARNING: Munge package not found"
fi

# 3.5. apptainer 설치 (모든 compute/viz 노드 필수 - 모든 Slurm job을 apptainer로 실행)
echo ""
echo "Step 3.5: Installing apptainer..."

# apptainer가 이미 설치되어 있는지 확인
if command -v apptainer &>/dev/null; then
    CURRENT_VERSION=$(apptainer --version 2>/dev/null || echo "unknown")
    echo "  ✓ apptainer already installed: $CURRENT_VERSION"
else
    echo "  Installing apptainer via APT (uses local offline repository)..."

    # APT 로컬 저장소 설정 확인
    REPO_LIST="/etc/apt/sources.list.d/offline-local.list"
    if [[ -f "$REPO_LIST" ]]; then
        echo "  ✓ Offline APT repository found: $REPO_LIST"

        # apt-get install로 설치 (의존성 및 설정 파일 자동 처리)
        APT_OPTS=(-o Dir::Etc::sourcelist="$REPO_LIST" -o Dir::Etc::sourceparts="-")
        if run_sudo apt-get "${APT_OPTS[@]}" install -y apptainer 2>/dev/null; then
            VERSION=$(apptainer --version 2>/dev/null || echo "unknown")
            echo "  ✓ apptainer installed via APT: $VERSION"
        else
            echo "  ⚠️  APT install failed, trying with all sources..."
            if run_sudo apt-get install -y apptainer 2>/dev/null; then
                VERSION=$(apptainer --version 2>/dev/null || echo "unknown")
                echo "  ✓ apptainer installed: $VERSION"
            else
                echo "  ✗ ERROR: apptainer installation failed"
                echo "  Check: $PKG_DIR/apt_packages/apptainer_*.deb exists"
            fi
        fi
    else
        echo "  ⚠️  WARNING: Offline APT repository not configured"
        echo "  Step 1 (APT packages) should have configured it"
        echo "  Falling back to direct dpkg install..."

        # Fallback: dpkg 직접 설치
        APPTAINER_DEB="$PKG_DIR/apt_packages/apptainer_1.4.5-1~jammy_amd64.deb"
        if [[ -f "$APPTAINER_DEB" ]]; then
            if run_sudo dpkg -i "$APPTAINER_DEB" 2>/dev/null || run_sudo apt-get install -f -y; then
                VERSION=$(apptainer --version 2>/dev/null || echo "unknown")
                echo "  ✓ apptainer installed via dpkg: $VERSION"
            else
                echo "  ✗ ERROR: apptainer installation failed"
            fi
        else
            echo "  ✗ ERROR: apptainer package not found: $APPTAINER_DEB"
        fi
    fi
fi

# /scratch/vnc_sandboxes 디렉토리 생성 (VNC 세션용)
echo "  Creating /scratch/vnc_sandboxes..."
run_sudo mkdir -p /scratch/vnc_sandboxes
run_sudo chmod 1777 /scratch/vnc_sandboxes
echo "  ✓ /scratch/vnc_sandboxes created"

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
        if ls "$PKG_DIR/apt_packages"/*.deb &>/dev/null; then
            run_sudo dpkg -i "$PKG_DIR/apt_packages"/glusterfs*.deb 2>/dev/null || true
            run_sudo dpkg -i "$PKG_DIR/apt_packages"/autofs*.deb 2>/dev/null || true
        fi
    else
        echo "  ✓ glusterfs-client already installed"
    fi

    # autofs 설치 확인
    if ! dpkg -l | grep -q autofs; then
        echo "  WARNING: autofs not installed"
        if ls "$PKG_DIR/apt_packages"/autofs*.deb &>/dev/null; then
            run_sudo dpkg -i "$PKG_DIR/apt_packages"/autofs*.deb 2>/dev/null || true
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
    # 임시 파일 사용 - run_sudo tee의 stdin 문제 회피
    if ! grep -q "auto.gluster" "$AUTOFS_MASTER" 2>/dev/null; then
        AUTOFS_TMP="/tmp/auto.master.entry.$$"
        {
            echo ""
            echo "# GlusterFS autofs mount (added by cluster deploy)"
            echo "$MOUNT_PARENT /etc/auto.gluster --timeout=300 --ghost"
        } > "$AUTOFS_TMP"
        cat "$AUTOFS_TMP" | run_sudo tee -a "$AUTOFS_MASTER" > /dev/null
        rm -f "$AUTOFS_TMP"
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
    # 임시 파일 사용 - run_sudo tee의 stdin 문제 회피
    GLUSTER_TMP="/tmp/auto.gluster.$$"
    cat > "$GLUSTER_TMP" << EOFAUTOFS
# GlusterFS autofs map
# Format: mount_name  -options  server:/volume
$MOUNT_NAME  -fstype=glusterfs,log-level=WARNING,backup-volfile-servers=$GLUSTER_SERVER  $GLUSTER_SERVER:/$GLUSTER_VOLUME
EOFAUTOFS
    run_sudo cp -f "$GLUSTER_TMP" "$AUTOFS_GLUSTER"
    rm -f "$GLUSTER_TMP"

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

    # /shared 심볼릭 링크 및 로그 디렉토리 생성
    echo "  Setting up /shared symlinks..."

    # autofs를 사용하는 경우 마운트 트리거
    if [[ "$GLUSTER_MOUNT" != "/shared" ]]; then
        echo "  Triggering autofs mount by accessing $GLUSTER_MOUNT..."
        run_sudo ls "$GLUSTER_MOUNT" >/dev/null 2>&1 || true
        sleep 2

        # 마운트 확인
        if run_sudo test -d "$GLUSTER_MOUNT"; then
            echo "  ✓ $GLUSTER_MOUNT is accessible"

            # logs와 jobs 디렉토리 생성 (GlusterFS에)
            run_sudo mkdir -p "$GLUSTER_MOUNT/logs" "$GLUSTER_MOUNT/jobs" 2>/dev/null || true
            run_sudo chmod 1777 "$GLUSTER_MOUNT/logs" 2>/dev/null || true
            run_sudo chmod 1777 "$GLUSTER_MOUNT/jobs" 2>/dev/null || true
            echo "  ✓ Created logs and jobs directories in GlusterFS"
        else
            echo "  ⚠ Warning: $GLUSTER_MOUNT not accessible, creating local directories"
            run_sudo mkdir -p /shared/logs /shared/jobs 2>/dev/null || true
            run_sudo chmod 1777 /shared/logs /shared/jobs 2>/dev/null || true
        fi

        # /shared 처리
        if run_sudo test -L /shared; then
            # Already a symlink
            CURRENT_TARGET=$(run_sudo readlink -f /shared 2>/dev/null || echo "")
            if [[ "$CURRENT_TARGET" != "$GLUSTER_MOUNT" ]]; then
                echo "  Updating /shared symlink -> $GLUSTER_MOUNT"
                run_sudo rm -f /shared
                run_sudo ln -s "$GLUSTER_MOUNT" /shared
            fi
        elif run_sudo test -d /shared; then
            # /shared exists as directory - create symlinks for logs and jobs
            echo "  /shared exists as directory, creating symlinks for logs and jobs..."

            if ! run_sudo test -L /shared/logs; then
                if run_sudo test -d /shared/logs && ! run_sudo test -L /shared/logs; then
                    run_sudo mv /shared/logs "/shared/logs.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
                fi
                run_sudo ln -sf "$GLUSTER_MOUNT/logs" /shared/logs
                echo "  ✓ Created /shared/logs -> $GLUSTER_MOUNT/logs"
            fi

            if ! run_sudo test -L /shared/jobs; then
                if run_sudo test -d /shared/jobs && ! run_sudo test -L /shared/jobs; then
                    run_sudo mv /shared/jobs "/shared/jobs.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
                fi
                run_sudo ln -sf "$GLUSTER_MOUNT/jobs" /shared/jobs
                echo "  ✓ Created /shared/jobs -> $GLUSTER_MOUNT/jobs"
            fi
        else
            # /shared doesn't exist - create symlink
            run_sudo ln -s "$GLUSTER_MOUNT" /shared
            echo "  ✓ Created /shared symlink -> $GLUSTER_MOUNT"
        fi
    else
        # GLUSTER_MOUNT == /shared인 경우 - 직접 디렉토리 생성
        run_sudo mkdir -p /shared/logs /shared/jobs 2>/dev/null || true
        run_sudo chmod 1777 /shared/logs /shared/jobs 2>/dev/null || true
        echo "  ✓ Created /shared/logs and /shared/jobs directories"
    fi
else
    echo "  Skipping GlusterFS setup (no server configured)"
fi

# 5. slurmd 서비스 시작
echo ""
echo "Step 5: Starting slurmd service..."

# slurmd.service 강제 재생성 (멱등성 보장)
SLURMD_SERVICE="/etc/systemd/system/slurmd.service"

echo "  Creating/recreating slurmd.service..."

# 임시 파일에 서비스 내용 작성 후 sudo cp로 복사 (run_sudo tee의 stdin 문제 회피)
SLURMD_TMP="/tmp/slurmd.service.$$"
cat > "$SLURMD_TMP" << 'EOFSVC'
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
ExecStart=/usr/local/slurm/sbin/slurmd -D
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
run_sudo cp -f "$SLURMD_TMP" "$SLURMD_SERVICE"
rm -f "$SLURMD_TMP"
run_sudo systemctl daemon-reload
echo "  ✓ slurmd.service created/updated"

# /run/slurm 디렉토리 생성
run_sudo mkdir -p /run/slurm
run_sudo chown slurm:slurm /run/slurm 2>/dev/null || true

# Unmask slurmd if masked (controller에서 mask되었을 수 있음)
run_sudo systemctl unmask slurmd 2>/dev/null || true

# slurmd 시작
echo "  Starting slurmd..."
run_sudo systemctl stop slurmd 2>/dev/null || true
sleep 1
run_sudo systemctl daemon-reload
run_sudo systemctl start slurmd

DEPLOY_STATUS=0
if systemctl is-active --quiet slurmd; then
    echo "  ✓ slurmd started successfully!"
    run_sudo systemctl enable slurmd 2>/dev/null || true
    SLURMD_VERSION=$(/usr/local/slurm/sbin/slurmd -V 2>/dev/null || echo "unknown")
    echo "  ✓ slurmd version: $SLURMD_VERSION"
else
    echo "  ✗ slurmd failed to start!"
    DEPLOY_STATUS=1
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           SLURMD STARTUP FAILURE DIAGNOSIS               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "=== 1. systemd service status ==="
    run_sudo systemctl status slurmd --no-pager -l 2>&1 | head -25 || true
    echo ""
    echo "=== 2. slurmd.service file content ==="
    cat /etc/systemd/system/slurmd.service 2>/dev/null || echo "  Service file not found!"
    echo ""
    echo "=== 3. slurmd binary check ==="
    if [[ -x /usr/local/slurm/sbin/slurmd ]]; then
        echo "  ✓ /usr/local/slurm/sbin/slurmd exists and executable"
        /usr/local/slurm/sbin/slurmd -V 2>&1 || echo "  ✗ Failed to get version"
    else
        echo "  ✗ /usr/local/slurm/sbin/slurmd NOT found or not executable!"
        ls -la /usr/local/slurm/sbin/ 2>/dev/null || echo "  /usr/local/slurm/sbin/ directory not found"
    fi
    echo ""
    echo "=== 4. slurm.conf check ==="
    if [[ -f /etc/slurm/slurm.conf ]]; then
        echo "  ✓ /etc/slurm/slurm.conf exists"
        echo "  ClusterName: $(grep -E '^ClusterName=' /etc/slurm/slurm.conf 2>/dev/null || echo 'not found')"
        echo "  SlurmctldHost: $(grep -E '^SlurmctldHost=' /etc/slurm/slurm.conf 2>/dev/null || echo 'not found')"
    else
        echo "  ✗ /etc/slurm/slurm.conf NOT found!"
    fi
    echo ""
    echo "=== 5. munge status ==="
    if systemctl is-active --quiet munge; then
        echo "  ✓ munge is running"
    else
        echo "  ✗ munge is NOT running!"
        run_sudo systemctl status munge --no-pager 2>&1 | head -10 || true
    fi
    echo ""
    echo "=== 6. munge.key check ==="
    if [[ -f /etc/munge/munge.key ]]; then
        echo "  ✓ /etc/munge/munge.key exists"
        ls -la /etc/munge/munge.key
    else
        echo "  ✗ /etc/munge/munge.key NOT found!"
    fi
    echo ""
    echo "=== 7. munge authentication test ==="
    munge -n 2>/dev/null | unmunge 2>&1 | head -5 || echo "  ✗ munge test failed"
    echo ""
    echo "=== 8. Recent journalctl logs ==="
    run_sudo journalctl -u slurmd -n 20 --no-pager 2>&1 || true
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  COMMON CAUSES OF SLURMD FAILURE:                        ║"
    echo "║  1. munge.key mismatch with controller                   ║"
    echo "║  2. slurm.conf mismatch (version, hostname, etc.)        ║"
    echo "║  3. Cannot reach slurmctld (network/firewall)            ║"
    echo "║  4. Wrong slurmd binary path                             ║"
    echo "║  5. Time sync issue (munge requires synced clocks)       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
if [[ $DEPLOY_STATUS -eq 0 ]]; then
    echo "✅ Offline package installation complete!"
else
    echo "⚠️  Offline package installation completed with WARNINGS!"
    echo "   slurmd service failed to start - see diagnosis above"
fi
echo ""
echo "Slurm configuration:"
echo "  - slurmd: $(systemctl is-active slurmd 2>/dev/null || echo 'FAILED')"
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

# slurmd 실패 시 비정상 종료 코드 반환
exit $DEPLOY_STATUS
EOFREMOTE

    # SSH 실행 결과 저장
    local ssh_exit_code=$?

    # Exit code 기반 성공/실패 판단 (stderr 내용은 무시)
    if [[ $ssh_exit_code -eq 0 ]]; then
        log_success "[$node_hostname] Deployment complete!"

        # stderr에 systemd 정보성 메시지가 있을 수 있으므로 경고만 표시
        if [[ -f "$ssh_error_log" ]] && [[ -s "$ssh_error_log" ]]; then
            # systemd-sysv-install 같은 정보성 메시지는 무시
            if ! grep -q "systemd-sysv-install\|Synchronizing state" "$ssh_error_log"; then
                log_warning "[$node_hostname] Deployment succeeded but had warnings:"
                cat "$ssh_error_log" | head -20
            fi
        fi

        rm -f "$ssh_error_log"
        return 0
    else
        log_error "[$node_hostname] Deployment failed - SSH heredoc execution error"
        log_error "[$node_hostname] Exit code: $ssh_exit_code"

        # 에러 로그 출력
        if [[ -f "$ssh_error_log" ]] && [[ -s "$ssh_error_log" ]]; then
            log_error "[$node_hostname] SSH Error output:"
            echo "========================================" >&2
            cat "$ssh_error_log" >&2
            echo "========================================" >&2
        else
            log_error "[$node_hostname] No SSH error output captured"
        fi

        # 에러 로그를 영구 저장
        if [[ -f "$ssh_error_log" ]]; then
            local permanent_log="/tmp/deploy_error_${node_hostname}_$(date +%Y%m%d_%H%M%S).log"
            mv "$ssh_error_log" "$permanent_log"
            log_error "[$node_hostname] Error log saved to: $permanent_log"
        fi

        return 1
    fi
}

# 병렬 배포
deploy_all_nodes() {
    local nodes_json="$1"
    local gluster_server="$2"
    local gluster_volume="$3"
    local gluster_mount="$4"

    # 노드 목록을 임시 파일에 저장 (bash 변수 대신 파일 사용)
    local nodes_list_file="/tmp/deploy_nodes_$$.txt"

    # Python으로 직접 YAML에서 노드 목록 생성 (compute + viz 노드)
    python3 << EOPY > "$nodes_list_file"
import yaml
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: Failed to read config: {e}", file=sys.stderr)
    sys.exit(1)

# 중복 제거를 위한 set (hostname 기준)
seen_hostnames = set()

# compute_nodes (compute + viz 모두 포함)
compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
for node in compute_nodes:
    hostname = node.get('hostname', '')
    ip = node.get('ip_address', '')
    user = node.get('ssh_user', 'koopark')
    if hostname and ip and hostname not in seen_hostnames:
        print(f"{hostname}|{ip}|{user}")
        seen_hostnames.add(hostname)

# viz_nodes (별도 섹션 - 구버전 YAML 지원)
viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
for node in viz_nodes:
    hostname = node.get('hostname', '')
    ip = node.get('ip_address', '')
    user = node.get('ssh_user', 'koopark')
    if hostname and ip and hostname not in seen_hostnames:
        print(f"{hostname}|{ip}|{user}")
        seen_hostnames.add(hostname)
EOPY

    if [[ $? -ne 0 ]] || [[ ! -s "$nodes_list_file" ]]; then
        log_error "Failed to extract node list from YAML"
        rm -f "$nodes_list_file"
        return 1
    fi

    # 노드 수 계산
    local total_nodes
    total_nodes=$(wc -l < "$nodes_list_file")
    total_nodes=${total_nodes//[^0-9]/}

    if [[ -z "$total_nodes" ]] || [[ "$total_nodes" -eq 0 ]]; then
        log_error "No compute nodes found in configuration"
        rm -f "$nodes_list_file"
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

    # ============================================================================
    # SSH host key 사전 등록 (idle* 문제 방지)
    # ============================================================================
    log_info "Pre-registering SSH host keys to prevent idle* issues..."

    local hostkey_count=0
    while IFS='|' read -r hostname ip user; do
        [[ -z "$hostname" ]] && continue

        # 특정 노드만 배포 시 해당 노드만 처리
        if [[ -n "$SPECIFIC_NODE" ]] && [[ "$hostname" != "$SPECIFIC_NODE" ]]; then
            continue
        fi

        # SSH host key를 known_hosts에 추가
        log_info "  Registering SSH key for $hostname ($ip)..."

        # hostname과 ip 모두 등록
        ssh-keyscan -H "$hostname" >> ~/.ssh/known_hosts 2>/dev/null || true
        ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null || true

        ((hostkey_count++))
    done < "$nodes_list_file"

    log_success "Registered $hostkey_count SSH host keys"
    echo ""

    # 노드 순회 (파일에서 직접 읽기 - 더 안정적)
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

        # 백그라운드 배포 (stdin을 /dev/null로 리다이렉트하여 파일 읽기 방해 방지)
        (
            if deploy_to_node "$hostname" "$ip" "$user" "$gluster_server" "$gluster_volume" "$gluster_mount"; then
                echo "SUCCESS:$hostname" >> /tmp/deploy_results_$$.txt
            else
                echo "FAILED:$hostname" >> /tmp/deploy_results_$$.txt
            fi
        ) < /dev/null &
        pids+=($!)

        log_info "Launched deployment for $hostname (PID: $!)"

    done < "$nodes_list_file"

    # 임시 파일 정리
    rm -f "$nodes_list_file"

    # 모든 배포 완료 대기
    log_info "Waiting for all deployments to complete..."

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    # 결과 집계
    local failed_nodes=""
    local success_nodes=""
    if [[ -f /tmp/deploy_results_$$.txt ]]; then
        success_count=$(grep -c "^SUCCESS:" /tmp/deploy_results_$$.txt 2>/dev/null || true)
        failed_count=$(grep -c "^FAILED:" /tmp/deploy_results_$$.txt 2>/dev/null || true)
        # grep -c가 빈 문자열이나 개행을 반환할 경우 0으로 처리
        success_count=${success_count//[^0-9]/}
        failed_count=${failed_count//[^0-9]/}
        [[ -z "$success_count" ]] && success_count=0
        [[ -z "$failed_count" ]] && failed_count=0

        # 실패한 노드 목록 추출
        failed_nodes=$(grep "^FAILED:" /tmp/deploy_results_$$.txt 2>/dev/null | cut -d: -f2 | tr '\n' ' ' || true)
        success_nodes=$(grep "^SUCCESS:" /tmp/deploy_results_$$.txt 2>/dev/null | cut -d: -f2 | tr '\n' ' ' || true)
        rm -f /tmp/deploy_results_$$.txt
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              DEPLOYMENT SUMMARY                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_success "  Successful: $success_count nodes"
    if [[ -n "$success_nodes" ]]; then
        echo "    → $success_nodes"
    fi

    if [[ "$failed_count" -gt 0 ]]; then
        log_error "  Failed: $failed_count nodes"
        echo "    → $failed_nodes"
        echo ""
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  TROUBLESHOOTING FAILED NODES                              ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  각 실패한 노드에서 다음을 확인하세요:"
        echo ""
        echo "  1. SSH로 접속하여 slurmd 상태 확인:"
        echo "     ssh <node> 'sudo systemctl status slurmd'"
        echo ""
        echo "  2. slurmd 로그 확인:"
        echo "     ssh <node> 'sudo journalctl -u slurmd -n 50'"
        echo ""
        echo "  3. munge 인증 테스트:"
        echo "     ssh <node> 'munge -n | unmunge'"
        echo ""
        echo "  4. munge.key 존재 여부:"
        echo "     ssh <node> 'ls -la /etc/munge/munge.key'"
        echo ""
        echo "  5. slurm.conf 존재 여부:"
        echo "     ssh <node> 'ls -la /etc/slurm/slurm.conf'"
        echo ""
        return 1
    fi

    return 0
}

# 배포 후 노드 상태 검증
verify_deployed_nodes() {
    local config_file="$1"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          POST-DEPLOYMENT VERIFICATION                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Waiting 10 seconds for services to stabilize..."
    sleep 10

    log_info "Checking Slurm cluster node states..."
    echo ""

    # sinfo로 노드 상태 확인
    if ! command -v sinfo &>/dev/null && [[ -x /usr/local/slurm/bin/sinfo ]]; then
        SINFO="/usr/local/slurm/bin/sinfo"
    else
        SINFO="sinfo"
    fi

    $SINFO -N -l 2>/dev/null || {
        log_error "Failed to run sinfo - is slurmctld running on controller?"
        return 1
    }

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Detailed Node Verification"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # YAML에서 배포된 노드 목록 가져오기
    local nodes_list=$(python3 << EOPY
import yaml
try:
    with open('$config_file', 'r') as f:
        config = yaml.safe_load(f)

    nodes = []
    for node in config.get('nodes', {}).get('compute_nodes', []):
        nodes.append(f"{node.get('hostname')}|{node.get('ip_address')}|{node.get('ssh_user', 'koopark')}")

    for node in config.get('nodes', {}).get('viz_nodes', []):
        nodes.append(f"{node.get('hostname')}|{node.get('ip_address')}|{node.get('ssh_user', 'koopark')}")

    for node in nodes:
        print(node)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
EOPY
)

    local total_nodes=0
    local healthy_nodes=0
    local problem_nodes=0

    for node_info in $nodes_list; do
        IFS='|' read -r hostname ip user <<< "$node_info"
        total_nodes=$((total_nodes + 1))

        echo "Checking $hostname ($ip)..."

        # Slurm 상태 확인
        local slurm_state=$($SINFO -N -h -n "$hostname" -o "%T" 2>/dev/null || echo "UNKNOWN")

        if [[ "$slurm_state" == "idle" ]]; then
            log_success "  ✓ Slurm state: $slurm_state"
            healthy_nodes=$((healthy_nodes + 1))
        else
            log_warning "  ⚠️  Slurm state: $slurm_state"
            problem_nodes=$((problem_nodes + 1))

            # 문제 노드는 상세 진단
            echo "  → Running diagnostic checks..."

            # SSH 연결 테스트
            if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$user@$ip" "echo ok" &>/dev/null; then
                # slurmd 상태
                local slurmd_status=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$user@$ip" "systemctl is-active slurmd 2>/dev/null || echo 'inactive'")
                if [[ "$slurmd_status" == "active" ]]; then
                    echo "    slurmd service: ✓ running"
                else
                    log_error "    slurmd service: ✗ $slurmd_status"
                fi

                # munge 상태
                local munge_status=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$user@$ip" "systemctl is-active munge 2>/dev/null || echo 'inactive'")
                if [[ "$munge_status" == "active" ]]; then
                    echo "    munge service: ✓ running"
                else
                    log_error "    munge service: ✗ $munge_status"
                fi

                # munge 인증 테스트
                local munge_test=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$user@$ip" "munge -n 2>/dev/null | unmunge 2>&1 | grep -q SUCCESS && echo 'OK' || echo 'FAIL'")
                if [[ "$munge_test" == "OK" ]]; then
                    echo "    munge auth: ✓ success"
                else
                    log_error "    munge auth: ✗ failed"
                fi

                # 시간 동기화 체크
                local node_time=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$user@$ip" "date +%s 2>/dev/null || echo '0'")
                local controller_time=$(date +%s)
                if [[ "$node_time" != "0" ]]; then
                    local time_diff=$((controller_time - node_time))
                    local abs_diff=${time_diff#-}
                    if [[ $abs_diff -gt 300 ]]; then
                        log_error "    time sync: ✗ ${abs_diff}s difference (>5min)"
                    elif [[ $abs_diff -gt 60 ]]; then
                        log_warning "    time sync: ⚠️  ${abs_diff}s difference"
                    else
                        echo "    time sync: ✓ ${abs_diff}s difference"
                    fi
                fi

                # 최근 slurmd 에러 로그
                echo "    Recent slurmd errors:"
                ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$user@$ip" "sudo journalctl -u slurmd -p err -n 3 --no-pager 2>/dev/null | sed 's/^/      /'" || echo "      (no errors or journalctl failed)"

            else
                log_error "    SSH connection: ✗ failed"
            fi
        fi
        echo ""
    done

    echo "═══════════════════════════════════════════════════════════"
    echo "Verification Summary"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Total nodes checked: $total_nodes"
    log_success "Healthy (IDLE):      $healthy_nodes"
    if [[ $problem_nodes -gt 0 ]]; then
        log_error "Problem nodes:       $problem_nodes"
        echo ""
        echo "Problem nodes require attention. Common fixes:"
        echo "  1. Time sync: Install chrony/ntp on all nodes"
        echo "  2. Munge key: Verify /etc/munge/munge.key matches controller"
        echo "  3. Restart services: sudo systemctl restart munge slurmd"
        echo "  4. Check logs: sudo journalctl -u slurmd -n 50"
        echo ""
        return 1
    else
        echo ""
        log_success "All nodes are healthy!"
        return 0
    fi
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
    echo "  ✓ apptainer (컨테이너 런타임)"
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

    # 헤드노드의 slurm UID/GID 확인 (계산 노드와 동일하게 맞추기 위함)
    log_info "Detecting headnode slurm UID/GID..."
    HEADNODE_SLURM_UID=""
    HEADNODE_SLURM_GID=""

    # YAML에서 헤드노드 정보 가져오기
    local headnode_ip=$(python3 -c "
import yaml
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
    controllers = config.get('nodes', {}).get('controllers', [])
    if controllers:
        print(controllers[0].get('ip_address', ''))
except:
    pass
" 2>/dev/null)

    if [[ -n "$headnode_ip" ]]; then
        # 헤드노드에서 slurm UID/GID 가져오기
        local uid_gid_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
            "koopark@$headnode_ip" "id slurm 2>/dev/null" 2>/dev/null || echo "")

        if [[ -n "$uid_gid_output" ]]; then
            HEADNODE_SLURM_UID=$(echo "$uid_gid_output" | grep -oP 'uid=\K[0-9]+')
            HEADNODE_SLURM_GID=$(echo "$uid_gid_output" | grep -oP 'gid=\K[0-9]+')

            if [[ -n "$HEADNODE_SLURM_UID" ]] && [[ -n "$HEADNODE_SLURM_GID" ]]; then
                log_success "Detected headnode slurm UID=$HEADNODE_SLURM_UID, GID=$HEADNODE_SLURM_GID"
            else
                log_warning "Could not parse slurm UID/GID from headnode, using default 64001"
                HEADNODE_SLURM_UID=64001
                HEADNODE_SLURM_GID=64001
            fi
        else
            log_warning "Could not detect slurm user on headnode, using default 64001"
            HEADNODE_SLURM_UID=64001
            HEADNODE_SLURM_GID=64001
        fi
    else
        log_warning "Could not find headnode IP, using default UID/GID 64001"
        HEADNODE_SLURM_UID=64001
        HEADNODE_SLURM_GID=64001
    fi
    echo ""

    log_info "Config:       $CONFIG_FILE"
    log_info "Package Dir:  $PACKAGE_DIR"
    log_info "Parallel:     $PARALLEL"
    log_info "Log File:     $LOG_FILE"
    log_info "Log Backup:   $LOG_FILE_TIMESTAMPED"
    echo ""

    if [[ "$DRY_RUN" == "false" ]] && [[ "$AUTO_YES" == "false" ]]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi

    # 계산 노드 + viz 노드 확인
    log_info "Checking compute/viz nodes in configuration..."
    local node_count
    node_count=$(python3 -c "
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
print(len(compute_nodes) + len(viz_nodes))
" 2>/dev/null || echo "0")

    if [[ "$node_count" -eq 0 ]]; then
        log_error "No compute/viz nodes found in YAML configuration"
        log_error "Check 'nodes.compute_nodes' or 'nodes.viz_nodes' section in: $CONFIG_FILE"
        exit 1
    fi
    log_success "Found $node_count compute/viz nodes in configuration"

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

    if deploy_all_nodes "" "$gluster_server" "$gluster_volume" "$gluster_mount"; then
        # 배포 후 노드 상태 검증
        if verify_deployed_nodes "$CONFIG_FILE"; then
            print_summary
            log_success "All nodes deployed successfully and verified healthy!"
            exit 0
        else
            print_summary
            log_warning "Deployment completed but some nodes have issues"
            log_warning "Run ./diagnose_nodes.sh $CONFIG_FILE for detailed diagnosis"
            exit 1
        fi
    else
        log_error "Some nodes failed to deploy"
        exit 1
    fi
}

main "$@"
