#!/bin/bash
################################################################################
# 클러스터 전체 사용자 추가 자동화
#
# 기능:
#   - 모든 컨트롤러 + 컴퓨트 노드에 동일 UID/GID로 사용자 생성
#   - NFS 홈 디렉토리 자동 생성 (/home/USERNAME)
#   - SSH 키 자동 생성 + 모든 노드에 authorized_keys 배포
#   - Slurm 어카운팅 등록 (선택)
#
# 사용법:
#   sudo ./add_cluster_user.sh USERNAME [--uid UID] [--account ACCOUNT]
#                                       [--config YAML] [--no-slurm]
#
# 옵션:
#   --uid UID            사용자 UID (기본: 자동 할당, 65000~)
#   --account NAME       Slurm 어카운트 (기본: default)
#   --config FILE        클러스터 YAML 설정 (기본: my_multihead_cluster.yaml)
#   --no-slurm          Slurm 어카운팅 등록 스킵
#   --no-ssh-key        SSH 키 자동 생성 스킵
################################################################################

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# 기본값
USERNAME=""
USER_UID=""
SLURM_ACCOUNT="default"
CONFIG_FILE="my_multihead_cluster.yaml"
SKIP_SLURM=false
SKIP_SSH_KEY=false

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --uid)        USER_UID="$2"; shift 2 ;;
        --account)    SLURM_ACCOUNT="$2"; shift 2 ;;
        --config)     CONFIG_FILE="$2"; shift 2 ;;
        --no-slurm)   SKIP_SLURM=true; shift ;;
        --no-ssh-key) SKIP_SSH_KEY=true; shift ;;
        --help|-h)
            head -25 "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            if [[ -z "$USERNAME" ]]; then
                USERNAME="$1"; shift
            else
                log_error "Unknown option: $1"; exit 1
            fi
            ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    log_error "USERNAME 필수"
    head -25 "$0" | grep "^#" | sed 's/^# \?//'
    exit 1
fi

[[ $EUID -ne 0 ]] && { log_error "root 권한 필요 (sudo 사용)"; exit 1; }

# 프로젝트 루트
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

if [[ ! -f "$PROJECT_ROOT/$CONFIG_FILE" ]]; then
    log_error "설정 파일 없음: $PROJECT_ROOT/$CONFIG_FILE"
    exit 1
fi

# UID 자동 할당 (65000~)
if [[ -z "$USER_UID" ]]; then
    USER_UID=$(awk -F: '$3 >= 65000 && $3 < 70000 {print $3}' /etc/passwd | sort -n | tail -1)
    if [[ -z "$USER_UID" ]]; then
        USER_UID=65000
    else
        USER_UID=$((USER_UID + 1))
    fi
fi
USER_GID=$USER_UID

log_info "사용자 추가:"
log_info "  Username: $USERNAME"
log_info "  UID/GID:  $USER_UID"
log_info "  Account:  $SLURM_ACCOUNT (Slurm)"
log_info "  Config:   $CONFIG_FILE"
echo ""

# YAML에서 노드 IP 추출 (Python 사용)
get_all_nodes() {
    python3 - <<EOF
import yaml
with open("$PROJECT_ROOT/$CONFIG_FILE") as f:
    cfg = yaml.safe_load(f)
nodes = cfg.get('nodes', {})
all_ips = set()
ssh_user = ""
# controllers
for c in nodes.get('controllers', []):
    all_ips.add(c['ip_address'])
    if not ssh_user:
        ssh_user = c.get('ssh_user', 'stcx')
# compute_nodes
for n in nodes.get('compute_nodes', []):
    all_ips.add(n['ip_address'])
# viz_nodes
for n in nodes.get('viz_nodes', []):
    all_ips.add(n['ip_address'])
print(ssh_user)
for ip in sorted(all_ips):
    print(ip)
EOF
}

NODES_INFO=$(get_all_nodes)
SSH_USER=$(echo "$NODES_INFO" | head -1)
NODE_IPS=$(echo "$NODES_INFO" | tail -n +2)
TOTAL_NODES=$(echo "$NODE_IPS" | wc -l)

log_info "총 ${TOTAL_NODES}개 노드에 계정 생성 시도 (SSH user: $SSH_USER)"
echo ""

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR"

# 1. 헤드노드(현재 호스트)에 사용자 생성
log_info "[1/4] 헤드노드에 사용자 생성..."
if id "$USERNAME" &>/dev/null; then
    log_warning "  $USERNAME 이미 존재 (UID: $(id -u $USERNAME))"
else
    groupadd -g "$USER_GID" "$USERNAME" 2>/dev/null || groupadd "$USERNAME"
    useradd -u "$USER_UID" -g "$USER_GID" -m -s /bin/bash "$USERNAME"
    log_success "  사용자 생성됨"
fi

# 비밀번호 설정 (선택, 일관성 위해)
USER_PASSWORD="$(openssl rand -base64 12)"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
log_info "  임시 비밀번호: $USER_PASSWORD (사용자에게 알려주세요)"

# 2. SSH 키 생성
if [[ "$SKIP_SSH_KEY" == "false" ]]; then
    log_info "[2/4] SSH 키 생성..."
    USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
    if [[ ! -f "$USER_HOME/.ssh/id_rsa" ]]; then
        sudo -u "$USERNAME" mkdir -p "$USER_HOME/.ssh"
        sudo -u "$USERNAME" ssh-keygen -t rsa -b 4096 -f "$USER_HOME/.ssh/id_rsa" -N "" -q
        sudo -u "$USERNAME" cp "$USER_HOME/.ssh/id_rsa.pub" "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
        chmod 700 "$USER_HOME/.ssh"
        log_success "  SSH 키 생성됨"
    else
        log_info "  SSH 키 이미 존재"
    fi
else
    log_info "[2/4] SSH 키 생성 스킵 (--no-ssh-key)"
fi

# 3. 모든 노드에 동일 UID/GID로 사용자 생성
log_info "[3/4] 모든 노드에 사용자 동기화..."
SUCCESS=0
FAILED=0
FAILED_NODES=()

while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    # 헤드노드 자기 자신은 스킵
    if ip a 2>/dev/null | grep -q "inet $ip\b"; then
        continue
    fi

    if ! ssh $SSH_OPTS "$SSH_USER@$ip" "echo OK" &>/dev/null; then
        log_warning "  $ip 도달 불가 — 스킵 (나중에 add_cluster_user.sh 재실행)"
        FAILED=$((FAILED + 1))
        FAILED_NODES+=("$ip")
        continue
    fi

    ssh $SSH_OPTS "$SSH_USER@$ip" "
        if id $USERNAME &>/dev/null; then
            existing_uid=\$(id -u $USERNAME)
            if [[ \$existing_uid != $USER_UID ]]; then
                echo \"WARNING: $USERNAME exists with UID \$existing_uid (expected $USER_UID)\"
            fi
        else
            sudo groupadd -g $USER_GID $USERNAME 2>/dev/null || sudo groupadd $USERNAME
            sudo useradd -u $USER_UID -g $USER_GID -m -s /bin/bash $USERNAME 2>/dev/null
            echo '${USERNAME}:${USER_PASSWORD}' | sudo chpasswd
        fi
    " &>/dev/null && {
        log_info "  ✓ $ip"
        SUCCESS=$((SUCCESS + 1))
    } || {
        log_warning "  ✗ $ip 사용자 생성 실패"
        FAILED=$((FAILED + 1))
        FAILED_NODES+=("$ip")
    }
done <<< "$NODE_IPS"

log_success "  사용자 동기화 완료: ${SUCCESS}개 성공"
[[ $FAILED -gt 0 ]] && log_warning "  실패: ${FAILED}개 (${FAILED_NODES[*]})"

# 4. SSH 키 모든 노드에 배포 (사용자 비밀번호 없이 노드 간 SSH 가능하게)
if [[ "$SKIP_SSH_KEY" == "false" ]]; then
    log_info "[4/4] SSH authorized_keys 배포..."
    USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
    PUB_KEY=$(cat "$USER_HOME/.ssh/id_rsa.pub")

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if ip a 2>/dev/null | grep -q "inet $ip\b"; then
            continue
        fi
        ssh $SSH_OPTS "$SSH_USER@$ip" "
            sudo -u $USERNAME mkdir -p /home/$USERNAME/.ssh
            echo '$PUB_KEY' | sudo -u $USERNAME tee -a /home/$USERNAME/.ssh/authorized_keys > /dev/null
            sudo -u $USERNAME sort -u /home/$USERNAME/.ssh/authorized_keys -o /home/$USERNAME/.ssh/authorized_keys
            sudo chmod 700 /home/$USERNAME/.ssh
            sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
        " &>/dev/null || true
    done <<< "$NODE_IPS"
    log_success "  authorized_keys 배포 완료"
fi

# 5. Slurm 어카운트 등록
if [[ "$SKIP_SLURM" == "false" ]]; then
    log_info "[+] Slurm 어카운팅 등록..."
    SACCTMGR="/opt/slurm/bin/sacctmgr"
    [[ ! -x "$SACCTMGR" ]] && SACCTMGR="/usr/local/slurm/bin/sacctmgr"
    [[ ! -x "$SACCTMGR" ]] && SACCTMGR="/usr/bin/sacctmgr"

    if [[ -x "$SACCTMGR" ]]; then
        # 어카운트 없으면 생성
        if ! "$SACCTMGR" -n list account "$SLURM_ACCOUNT" 2>/dev/null | grep -q "$SLURM_ACCOUNT"; then
            "$SACCTMGR" -i add account "$SLURM_ACCOUNT" 2>&1 | tail -3
        fi
        # 사용자 등록
        "$SACCTMGR" -i add user "$USERNAME" account="$SLURM_ACCOUNT" 2>&1 | tail -3
        log_success "  Slurm 등록 완료"
    else
        log_warning "  sacctmgr 없음 — Slurm 등록 스킵"
    fi
fi

echo ""
log_success "=== 사용자 추가 완료 ==="
log_info "Username:    $USERNAME"
log_info "UID/GID:     $USER_UID"
log_info "Password:    $USER_PASSWORD"
log_info "노드 동기화: ${SUCCESS}개 성공 / ${FAILED}개 실패"
[[ $FAILED -gt 0 ]] && {
    log_info ""
    log_info "실패한 노드 살아나면 재실행:"
    log_info "  sudo $0 $USERNAME --uid $USER_UID --account $SLURM_ACCOUNT --no-ssh-key"
}
