#!/bin/bash
################################################################################
# spc 사용자 일회성 부트스트랩 (사용 후 삭제)
#
# 동작:
#   - 각 노드에 spc/password1! 로 SSH 접속
#   - spc 비밀번호를 SmartTwinCluster321! 로 변경
#   - passwordless sudo 등록
#   - 헤드노드 SSH 공개키 등록
#
# 사용법:
#   sudo bash bootstrap_spc_oneshot.sh [--config YAML]
################################################################################

set -uo pipefail

# 인자 파싱 (set -u 안전)
CONFIG_FILE="${1:-my_multihead_cluster.yaml}"
if [[ "${1:-}" == "--config" ]]; then
    CONFIG_FILE="${2:-}"
    [[ -z "$CONFIG_FILE" ]] && { echo "ERROR: --config 다음에 YAML 경로 필요"; exit 1; }
fi

# ⚠️ 하드코딩 (사용 후 스크립트 삭제 권장)
BOOTSTRAP_USER="spc"
BOOTSTRAP_PASSWORD='password1!'
TARGET_USER="stcx"
TARGET_PASSWORD='SmartTwinCluster321!'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

[[ $EUID -ne 0 ]] && { log_error "root 필요 (sudo)"; exit 1; }

if ! command -v sshpass &>/dev/null; then
    log_warning "sshpass 자동 설치..."
    apt-get install -y sshpass 2>&1 | tail -3 || { log_error "sshpass 설치 실패"; exit 1; }
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# CONFIG_FILE 경로 해석: 절대경로 / 현재 디렉토리 / PROJECT_ROOT 순서
if [[ "$CONFIG_FILE" = /* ]]; then
    CONFIG_PATH="$CONFIG_FILE"
elif [[ -f "$CONFIG_FILE" ]]; then
    CONFIG_PATH="$(realpath "$CONFIG_FILE")"
elif [[ -f "$PROJECT_ROOT/$CONFIG_FILE" ]]; then
    CONFIG_PATH="$PROJECT_ROOT/$CONFIG_FILE"
else
    log_error "설정 파일 없음: $CONFIG_FILE (검색: ., $PROJECT_ROOT/)"
    exit 1
fi
log_info "사용 YAML: $CONFIG_PATH"

# ────────────────────────────────────────────────────────────
# 헤드노드 부트스트랩: stcx — 있으면 보존, 없을 때만 생성 (안전)
# ────────────────────────────────────────────────────────────
HASHED_PASSWORD=$(openssl passwd -6 "$TARGET_PASSWORD")

if id "$TARGET_USER" &>/dev/null; then
    log_info "헤드노드 $TARGET_USER 이미 존재 → 보존 (홈 디렉토리/세션 유지)"
    # sudoers + 비번 + 키만 보강 (있으면 OK, 없으면 추가)
    [[ -f /etc/sudoers.d/$TARGET_USER ]] || {
        echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$TARGET_USER
        chmod 440 /etc/sudoers.d/$TARGET_USER
        log_info "  sudoers.d/$TARGET_USER 추가"
    }
else
    log_info "헤드노드 $TARGET_USER 없음 → 신규 생성"
    useradd -m -s /bin/bash -G sudo "$TARGET_USER"
    echo "$TARGET_USER:$HASHED_PASSWORD" | chpasswd -e
    echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$TARGET_USER
    chmod 440 /etc/sudoers.d/$TARGET_USER
    log_success "  $TARGET_USER 생성 완료"
fi

# SSH 키 (없으면 생성)
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
mkdir -p "$TARGET_HOME/.ssh"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"
chmod 700 "$TARGET_HOME/.ssh"
if [[ ! -f "$TARGET_HOME/.ssh/id_rsa.pub" ]]; then
    sudo -u "$TARGET_USER" ssh-keygen -t rsa -b 4096 -N "" -f "$TARGET_HOME/.ssh/id_rsa" -q
    log_success "  헤드노드 $TARGET_USER SSH 키 생성"
else
    log_info "  헤드노드 $TARGET_USER SSH 키 보존"
fi

PUBKEY_FILE="$TARGET_HOME/.ssh/id_rsa.pub"

if [[ ! -f "$PUBKEY_FILE" ]]; then
    log_error "SSH 키 생성 실패: $PUBKEY_FILE"
    exit 1
fi

PUBKEY=$(cat "$PUBKEY_FILE")
if [[ -z "$PUBKEY" ]]; then
    log_error "SSH 공개키 비어있음"
    exit 1
fi
log_info "헤드노드 $TARGET_USER 키: ${PUBKEY:0:50}..."
log_info "비밀번호 해시 생성 완료 (SHA-512): ${HASHED_PASSWORD:0:8}..."

# 헤드노드 자기 자신 authorized_keys에도 등록 (root로 직접)
touch "$TARGET_HOME/.ssh/authorized_keys"
echo "$PUBKEY" >> "$TARGET_HOME/.ssh/authorized_keys"
sort -u "$TARGET_HOME/.ssh/authorized_keys" -o "$TARGET_HOME/.ssh/authorized_keys"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh/authorized_keys"
chmod 600 "$TARGET_HOME/.ssh/authorized_keys"

# YAML에서 노드 IP 추출
NODE_IPS=$(python3 -c "
import yaml
with open('$CONFIG_PATH') as f:
    cfg = yaml.safe_load(f)
nodes = cfg.get('nodes', {})
ips = set()
for c in nodes.get('controllers', []): ips.add(c['ip_address'])
for n in nodes.get('compute_nodes', []): ips.add(n['ip_address'])
for ip in sorted(ips): print(ip)
")

TOTAL=$(echo "$NODE_IPS" | wc -l)
log_info "총 ${TOTAL}개 노드 부트스트랩"
log_info "  현재 비밀번호: password1!"
log_info "  변경 비밀번호: SmartTwinCluster321!"
echo ""

SSH_OPTS="-n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"

# 노드별 실행 명령 (상세 로그 출력)
remote_cmd() {
cat <<EOF
set -e

# SUDO_ASKPASS 방식: sudo가 ASKPASS 스크립트로 비번 받음 → stdin 자유
ASKPASS=\$(mktemp)
cat > \$ASKPASS <<'ASKEOF'
#!/bin/sh
echo '$BOOTSTRAP_PASSWORD'
ASKEOF
chmod +x \$ASKPASS
export SUDO_ASKPASS=\$ASKPASS
trap "rm -f \$ASKPASS" EXIT

SUDO() { sudo -A "\$@"; }

# 0. 환경 정보
echo "    [0/7] 노드 정보: \$(hostname) (\$(hostname -I | awk '{print \$1}'))"

# 1. sudo 가능 확인 (ASKPASS 통해)
if ! SUDO true 2>/dev/null; then
    echo "    [1/7] ❌ sudo 권한 없음 또는 비번 틀림"
    echo "      진단: ssh spc@<IP> 후 sudo whoami 직접 시도해보세요"
    echo "ERROR_NO_SUDO"
    exit 1
fi
echo "    [1/7] ✓ spc sudo 권한 OK"

# 2. 기존 $TARGET_USER 완전 삭제 + 재생성 (clean slate)
if id $TARGET_USER &>/dev/null; then
    echo "    [2/7] 기존 $TARGET_USER 발견 → 완전 삭제 + 재생성"
    SUDO pkill -KILL -u $TARGET_USER 2>/dev/null || true
    sleep 1
    SUDO userdel -r $TARGET_USER 2>/dev/null || SUDO userdel $TARGET_USER 2>/dev/null || true
    SUDO rm -rf /home/$TARGET_USER
fi
SUDO useradd -m -s /bin/bash -G sudo $TARGET_USER
echo "    [2/7] ✓ $TARGET_USER 신규 생성 (UID: \$(id -u $TARGET_USER))"

# 3. 비밀번호 설정 (해시 전달 — 싱글쿼터로 \$ 보호)
echo '$TARGET_USER:$HASHED_PASSWORD' | SUDO chpasswd -e
echo "    [3/7] ✓ 비밀번호 설정 완료 (해시)"

# 4. passwordless sudo
echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" | SUDO tee /etc/sudoers.d/$TARGET_USER >/dev/null
SUDO chmod 440 /etc/sudoers.d/$TARGET_USER
SUDO usermod -aG sudo $TARGET_USER
echo "    [4/7] ✓ passwordless sudo 등록 + sudo 그룹 추가"

# 5. SSH 디렉토리 (root로 만들고 chown)
TARGET_HOME=\$(getent passwd $TARGET_USER | cut -d: -f6)
SUDO mkdir -p \$TARGET_HOME/.ssh
SUDO chown $TARGET_USER:$TARGET_USER \$TARGET_HOME/.ssh
SUDO chmod 700 \$TARGET_HOME/.ssh
echo "    [5/7] ✓ \$TARGET_HOME/.ssh 디렉토리 준비"

# 6. authorized_keys 등록 (root tee → chown)
echo '$PUBKEY' | SUDO tee -a \$TARGET_HOME/.ssh/authorized_keys >/dev/null
SUDO sort -u \$TARGET_HOME/.ssh/authorized_keys -o \$TARGET_HOME/.ssh/authorized_keys
SUDO chown $TARGET_USER:$TARGET_USER \$TARGET_HOME/.ssh/authorized_keys
SUDO chmod 600 \$TARGET_HOME/.ssh/authorized_keys
KEY_COUNT=\$(SUDO wc -l \$TARGET_HOME/.ssh/authorized_keys | awk '{print \$1}')
echo "    [6/7] ✓ authorized_keys 등록 (총 \${KEY_COUNT}개 키)"

# 7. 검증
id $TARGET_USER >/dev/null
SUDO test -f /etc/sudoers.d/$TARGET_USER
SUDO test -f \$TARGET_HOME/.ssh/authorized_keys
echo "    [7/7] ✓ 검증 통과 (계정/sudoers/키 모두 OK)"

echo 'BOOTSTRAP_OK'
EOF
}

SUCCESS=0; FAILED=0; SKIPPED=0

while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    if ip a 2>/dev/null | grep -q "inet $ip\b"; then
        log_info "  자기 자신 스킵: $ip"
        continue
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "[$ip] 부트스트랩 시작"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 1. 22번 포트 접속 가능한지
    if ! timeout 3 bash -c "</dev/tcp/$ip/22" 2>/dev/null; then
        log_warning "  ✗ 22번 포트 닫힘 또는 노드 OFF — 스킵"
        FAILED=$((FAILED + 1))
        continue
    fi
    log_info "  ✓ TCP 22 도달 가능"

    # 2. 시나리오 분기
    # 시나리오 A: stcx 키 인증 + 비번 정상 → 완전 정상, 스킵
    # 시나리오 B: stcx 키 인증 OK, 비번 깨짐 → stcx 통해 비번만 재설정 (수리 모드)
    # 시나리오 C: stcx 키 인증 안 됨 → spc 통해 풀 부트스트랩

    if ssh -o BatchMode=yes $SSH_OPTS "$TARGET_USER@$ip" "sudo -n true" &>/dev/null; then
        log_info "  ✓ $TARGET_USER 키 인증 + NOPASSWD sudo OK"
        # 비번 형식 확인 (해시되어 있는가)
        pwd_state=$(ssh -o BatchMode=yes $SSH_OPTS "$TARGET_USER@$ip" \
            "sudo cat /etc/shadow | grep '^$TARGET_USER:' | cut -d: -f2 | head -c 3" 2>/dev/null)

        if [[ "$pwd_state" =~ ^\$[y6]\$ ]]; then
            log_success "[$ip] ✅ 이미 정상 (스킵)"
            SKIPPED=$((SKIPPED + 1))
            continue
        else
            # 시나리오 B: 키는 되는데 비번 이상 → stcx 통해 비번만 수정
            log_warning "  ⚠️  비번 형식 이상 (state: '$pwd_state') — stcx 키 인증으로 비번만 재설정"
            # 해시는 base64로 안전 전달 ($ 보호)
            HASH_B64=$(printf '%s' "$HASHED_PASSWORD" | base64 -w0)
            result=$(ssh -o BatchMode=yes $SSH_OPTS "$TARGET_USER@$ip" \
                "HASH=\$(echo '$HASH_B64' | base64 -d); \
                 echo \"$TARGET_USER:\$HASH\" | sudo chpasswd -e && \
                 sudo getent shadow $TARGET_USER | cut -d: -f2 | head -c 3 && echo" 2>&1)
            echo "    재설정 후 비번 state: $result"
            if echo "$result" | grep -qE '\$[y6]\$'; then
                log_success "[$ip] ✅ 비번 수리 성공"
                SUCCESS=$((SUCCESS + 1))
            else
                log_error "[$ip] ❌ 비번 수리 실패: $result"
                FAILED=$((FAILED + 1))
            fi
            continue
        fi
    fi

    # 시나리오 C: 키 인증 안 됨 → spc 통해 풀 부트스트랩
    log_info "  → $BOOTSTRAP_USER 로 SSH 접속 + 풀 부트스트랩 명령 실행..."
    result=$(sshpass -p "$BOOTSTRAP_PASSWORD" ssh $SSH_OPTS "$BOOTSTRAP_USER@$ip" "$(remote_cmd)" 2>&1)
    echo "$result"

    if echo "$result" | grep -q "BOOTSTRAP_OK"; then
        log_success "[$ip] ✅ 부트스트랩 성공"
        SUCCESS=$((SUCCESS + 1))
    else
        err_msg=$(echo "$result" | grep -iE "permission denied|connection|host key|timeout|unable|ERROR_NO_SUDO" | head -1)
        [[ -z "$err_msg" ]] && err_msg=$(echo "$result" | tail -1)
        log_error "[$ip] ❌ 실패: $err_msg"
        FAILED=$((FAILED + 1))
    fi
done <<< "$NODE_IPS"

echo ""
log_success "=== 완료 ==="
log_info "  성공: ${SUCCESS}, 이미 설정: ${SKIPPED}, 실패: ${FAILED}"
log_warning ""
log_warning "⚠️  비밀번호 하드코딩 — 사용 후 스크립트 삭제:"
log_warning "    sudo shred -uvz $0"
echo ""
log_info "이제 setup_cluster_full_multihead_offline.sh 실행 가능"
