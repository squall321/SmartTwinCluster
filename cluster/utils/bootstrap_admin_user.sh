#!/bin/bash
################################################################################
# 컴퓨트 노드 초기 부트스트랩 — admin user 생성
#
# 깡 OS 노드(예: ubuntu/admin/ec2-user 등 다른 초기 사용자)에
# 'koopark' admin user를 자동 생성하고 SSH 키 + passwordless sudo 설정.
#
# 시나리오:
#   - OS 설치 시 다른 사용자명으로 admin 만들어진 경우
#   - 클라우드 이미지(ubuntu) 사용 중인 경우
#
# 사용법:
#   sudo bash bootstrap_admin_user.sh \
#       --bootstrap-user ubuntu \
#       --bootstrap-password 'CurrentPassword' \
#       --target-user koopark \
#       --target-password 'Soseks314!' \
#       --config my_multihead_cluster_2.yaml
################################################################################

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

BOOTSTRAP_USER="ubuntu"
BOOTSTRAP_PASSWORD=""
TARGET_USER="koopark"
TARGET_PASSWORD=""
CONFIG_FILE="my_multihead_cluster.yaml"

while [[ $# -gt 0 ]]; do
    case $1 in
        --bootstrap-user)     BOOTSTRAP_USER="$2"; shift 2 ;;
        --bootstrap-password) BOOTSTRAP_PASSWORD="$2"; shift 2 ;;
        --target-user)        TARGET_USER="$2"; shift 2 ;;
        --target-password)    TARGET_PASSWORD="$2"; shift 2 ;;
        --config)             CONFIG_FILE="$2"; shift 2 ;;
        --help|-h)
            head -25 "$0" | grep "^#" | sed 's/^# \?//'; exit 0 ;;
        *)
            log_error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ $EUID -ne 0 ]] && { log_error "root 필요"; exit 1; }

if ! command -v sshpass &>/dev/null; then
    log_error "sshpass 필요: sudo apt install sshpass"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# YAML 비밀번호 자동 추출 (지정 안 했을 경우)
[[ -z "$TARGET_PASSWORD" ]] && TARGET_PASSWORD=$(python3 -c "
import yaml
with open('$PROJECT_ROOT/$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('cluster_info', {}).get('ssh_password', ''))
")

# 헤드노드에 koopark 사용자 SSH 공개키 (없으면 생성)
PUBKEY_FILE="/home/$TARGET_USER/.ssh/id_rsa.pub"
if [[ ! -f "$PUBKEY_FILE" ]]; then
    log_warning "헤드노드 $TARGET_USER 의 SSH 키 없음 — 생성"
    sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.ssh"
    sudo -u "$TARGET_USER" ssh-keygen -t rsa -b 4096 -N "" -f "/home/$TARGET_USER/.ssh/id_rsa" -q
fi
PUBKEY=$(cat "$PUBKEY_FILE")

# YAML에서 노드 IP 추출
NODE_IPS=$(python3 -c "
import yaml
with open('$PROJECT_ROOT/$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
nodes = cfg.get('nodes', {})
ips = set()
for c in nodes.get('controllers', []): ips.add(c['ip_address'])
for n in nodes.get('compute_nodes', []): ips.add(n['ip_address'])
for n in nodes.get('viz_nodes', []): ips.add(n['ip_address'])
for ip in sorted(ips): print(ip)
")

TOTAL=$(echo "$NODE_IPS" | wc -l)
log_info "총 ${TOTAL}개 노드에 ${TARGET_USER} 부트스트랩"
log_info "  Bootstrap user: $BOOTSTRAP_USER"
log_info "  Target user:    $TARGET_USER"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o LogLevel=ERROR"
SUCCESS=0; FAILED=0; SKIPPED=0

# 부트스트랩 명령 (각 노드에서 실행)
BOOTSTRAP_CMD="
# 1. 사용자 생성 (이미 있으면 스킵)
if id $TARGET_USER &>/dev/null; then
    echo 'EXISTS'
else
    sudo useradd -m -s /bin/bash -G sudo $TARGET_USER
    echo '$TARGET_USER:$TARGET_PASSWORD' | sudo chpasswd
    echo 'CREATED'
fi

# 2. passwordless sudo
echo '$TARGET_USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$TARGET_USER >/dev/null
sudo chmod 440 /etc/sudoers.d/$TARGET_USER

# 3. SSH 디렉토리 + 공개키 등록
sudo -u $TARGET_USER mkdir -p /home/$TARGET_USER/.ssh
echo '$PUBKEY' | sudo -u $TARGET_USER tee -a /home/$TARGET_USER/.ssh/authorized_keys >/dev/null
sudo -u $TARGET_USER sort -u /home/$TARGET_USER/.ssh/authorized_keys -o /home/$TARGET_USER/.ssh/authorized_keys
sudo chmod 700 /home/$TARGET_USER/.ssh
sudo chmod 600 /home/$TARGET_USER/.ssh/authorized_keys
"

while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    # 헤드노드 자기 자신 스킵
    if ip a 2>/dev/null | grep -q "inet $ip\b"; then
        log_info "  자기 자신 스킵: $ip"
        continue
    fi

    # 이미 target 사용자로 SSH 가능한지 확인
    if ssh -o BatchMode=yes $SSH_OPTS "$TARGET_USER@$ip" "exit" &>/dev/null; then
        log_info "  ✓ $ip 이미 설정됨 ($TARGET_USER 키 인증 OK)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # bootstrap user로 시도
    log_info "  $ip → $BOOTSTRAP_USER 로 부트스트랩 시도..."
    result=$(sshpass -p "$BOOTSTRAP_PASSWORD" ssh $SSH_OPTS "$BOOTSTRAP_USER@$ip" "$BOOTSTRAP_CMD" 2>&1)
    if echo "$result" | grep -qE "CREATED|EXISTS"; then
        log_success "  ✓ $ip 완료"
        SUCCESS=$((SUCCESS + 1))
    else
        log_warning "  ✗ $ip 실패: $(echo "$result" | tail -1)"
        FAILED=$((FAILED + 1))
    fi
done <<< "$NODE_IPS"

echo ""
log_success "=== 부트스트랩 완료 ==="
log_info "  성공: ${SUCCESS}, 이미 설정: ${SKIPPED}, 실패: ${FAILED}"
echo ""
log_info "이제 setup_cluster_full_multihead_offline.sh 실행 가능"
