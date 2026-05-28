#!/bin/bash
################################################################################
# spc 사용자 일회성 부트스트랩 + UID/GID 싱크
#
# 동작:
#   - 각 노드에 spc/password1! 로 SSH 접속
#   - stcx 계정 생성/보정 + UID/GID 클러스터 전체 통일
#   - passwordless sudo + SSH 키 등록
#
# 모드:
#   기본 (sync)        : 계정 보존, UID/GID 어긋나면 usermod로 정렬, /home/stcx chown
#   --force-recreate   : 옛 동작 (userdel -r → useradd, 데이터 손실)
#
# UID/GID 결정 우선순위:
#   1. CLI: --target-uid N --target-gid N
#   2. YAML: cluster_info.target_uid / cluster_info.target_gid
#   3. 헤드노드의 현재 stcx UID/GID 자동 사용
#
# 사용법:
#   sudo bash bootstrap_spc_oneshot.sh [--config YAML] [--target-uid N] [--target-gid N] [--force-recreate]
################################################################################

set -uo pipefail

# 인자 파싱
CONFIG_FILE="my_multihead_cluster.yaml"
TARGET_UID=""
TARGET_GID=""
FORCE_RECREATE=false
while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --config)          CONFIG_FILE="${2:-}"; shift 2 ;;
        --target-uid)      TARGET_UID="${2:-}"; shift 2 ;;
        --target-gid)      TARGET_GID="${2:-}"; shift 2 ;;
        --force-recreate)  FORCE_RECREATE=true; shift ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^#//' | head -25; exit 0 ;;
        *)
            # 위치 인자 (옛 호환): 첫 인자를 config로
            if [[ "$CONFIG_FILE" == "my_multihead_cluster.yaml" && -f "$1" ]]; then
                CONFIG_FILE="$1"; shift
            else
                echo "Unknown option: $1"; exit 1
            fi ;;
    esac
done

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
# 추가 사용자 (admin_user + cluster_users) 추출
# 출력: TSV (name<TAB>uid<TAB>gid<TAB>sudo<TAB>pw_mode<TAB>groups_csv)
#   pw_mode: 'set' (TARGET_PASSWORD 해시 적용) 또는 'lock' (잠금)
# ────────────────────────────────────────────────────────────
EXTRA_USERS_TSV=$(CONFIG_PATH="$CONFIG_PATH" python3 <<'EOPY'
import yaml, os
with open(os.environ['CONFIG_PATH']) as f:
    cfg = yaml.safe_load(f) or {}
u = cfg.get('users', {}) or {}
rows = []
if u.get('admin_user'):
    grps = 'sudo' if u.get('admin_sudo') else ''
    rows.append((u['admin_user'], u.get('admin_uid',''), u.get('admin_gid',''),
                 'true' if u.get('admin_sudo') else 'false', 'set', grps))
for cu in (u.get('cluster_users') or []):
    grps = ','.join(cu.get('groups') or [])
    rows.append((cu.get('username',''), cu.get('uid',''), cu.get('gid',''),
                 'false', 'lock', grps))
for r in rows:
    print('\t'.join(str(x) for x in r))
EOPY
)
log_info "추가 동기화 사용자 (admin+cluster):"
while IFS=$'\t' read -r n uid gid s pm g; do
    [[ -z "$n" ]] && continue
    log_info "  - $n (uid=$uid gid=$gid sudo=$s pw=$pm groups=$g)"
done <<< "$EXTRA_USERS_TSV"

# ssh_user/uid/gid도 yaml에서 (TARGET_USER 덮어쓰기)
YAML_SSH=$(CONFIG_PATH="$CONFIG_PATH" python3 <<'EOPY'
import yaml, os
with open(os.environ['CONFIG_PATH']) as f:
    cfg = yaml.safe_load(f) or {}
u = cfg.get('users', {}) or {}
print(u.get('ssh_user', '') or '')
print(u.get('ssh_uid', '') or '')
print(u.get('ssh_gid', '') or '')
EOPY
)
YAML_SSH_USER=$(sed -n '1p' <<<"$YAML_SSH")
YAML_SSH_UID=$(sed -n '2p' <<<"$YAML_SSH")
YAML_SSH_GID=$(sed -n '3p' <<<"$YAML_SSH")
[[ -n "$YAML_SSH_USER" ]] && TARGET_USER="$YAML_SSH_USER"
[[ -z "$TARGET_UID" && -n "$YAML_SSH_UID" ]] && TARGET_UID="$YAML_SSH_UID"
[[ -z "$TARGET_GID" && -n "$YAML_SSH_GID" ]] && TARGET_GID="$YAML_SSH_GID"

# ────────────────────────────────────────────────────────────
# UID/GID 결정: CLI > YAML > 헤드의 현재 stcx
# ────────────────────────────────────────────────────────────
if [[ -z "$TARGET_UID" || -z "$TARGET_GID" ]]; then
    YAML_IDS=$(python3 -c "
import yaml
with open('$CONFIG_PATH') as f: cfg = yaml.safe_load(f) or {}
ci = cfg.get('cluster_info', {}) or {}
print(ci.get('target_uid', '') or '')
print(ci.get('target_gid', '') or '')
" 2>/dev/null)
    [[ -z "$TARGET_UID" ]] && TARGET_UID=$(sed -n '1p' <<<"$YAML_IDS")
    [[ -z "$TARGET_GID" ]] && TARGET_GID=$(sed -n '2p' <<<"$YAML_IDS")
fi
# 그래도 없으면 헤드의 현재 stcx에서 추출 (없으면 useradd 자동)
if [[ -z "$TARGET_UID" ]] && id "$TARGET_USER" &>/dev/null; then
    TARGET_UID=$(id -u "$TARGET_USER")
fi
if [[ -z "$TARGET_GID" ]] && id "$TARGET_USER" &>/dev/null; then
    TARGET_GID=$(id -g "$TARGET_USER")
fi
log_info "TARGET UID=${TARGET_UID:-(auto)} GID=${TARGET_GID:-(auto)} (모드: $([[ $FORCE_RECREATE == true ]] && echo destructive || echo sync))"

# ────────────────────────────────────────────────────────────
# 헤드노드 부트스트랩: stcx 생성 또는 UID/GID 정렬
# ────────────────────────────────────────────────────────────
HASHED_PASSWORD=$(openssl passwd -6 "$TARGET_PASSWORD")

ensure_uid_gid_local() {
    local cur_uid cur_gid
    cur_uid=$(id -u "$TARGET_USER")
    cur_gid=$(id -g "$TARGET_USER")
    if [[ -n "$TARGET_GID" && "$cur_gid" != "$TARGET_GID" ]]; then
        log_warning "헤드 GID 어긋남 ($cur_gid → $TARGET_GID) — groupmod"
        groupmod -g "$TARGET_GID" "$TARGET_USER" 2>/dev/null || \
            groupadd -g "$TARGET_GID" "$TARGET_USER" 2>/dev/null || true
        find /home/$TARGET_USER -gid "$cur_gid" -exec chgrp -h "$TARGET_GID" {} + 2>/dev/null || true
    fi
    if [[ -n "$TARGET_UID" && "$cur_uid" != "$TARGET_UID" ]]; then
        log_warning "헤드 UID 어긋남 ($cur_uid → $TARGET_UID) — usermod"
        pkill -KILL -u "$TARGET_USER" 2>/dev/null || true
        sleep 1
        usermod -u "$TARGET_UID" "$TARGET_USER"
        find /home/$TARGET_USER -uid "$cur_uid" -exec chown -h "$TARGET_UID" {} + 2>/dev/null || true
    fi
}

if id "$TARGET_USER" &>/dev/null; then
    log_info "헤드노드 $TARGET_USER 이미 존재 → 보존 (UID/GID 정렬만 수행)"
    ensure_uid_gid_local
    [[ -f /etc/sudoers.d/$TARGET_USER ]] || {
        echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$TARGET_USER
        chmod 440 /etc/sudoers.d/$TARGET_USER
    }
else
    log_info "헤드노드 $TARGET_USER 없음 → 신규 생성"
    if [[ -n "$TARGET_GID" ]]; then
        getent group "$TARGET_GID" &>/dev/null || groupadd -g "$TARGET_GID" "$TARGET_USER"
        useradd -m -s /bin/bash -G sudo -u "${TARGET_UID:-65000}" -g "$TARGET_GID" "$TARGET_USER"
    elif [[ -n "$TARGET_UID" ]]; then
        useradd -m -s /bin/bash -G sudo -u "$TARGET_UID" "$TARGET_USER"
    else
        useradd -m -s /bin/bash -G sudo "$TARGET_USER"
    fi
    echo "$TARGET_USER:$HASHED_PASSWORD" | chpasswd -e
    echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$TARGET_USER
    chmod 440 /etc/sudoers.d/$TARGET_USER
    [[ -z "$TARGET_UID" ]] && TARGET_UID=$(id -u "$TARGET_USER")
    [[ -z "$TARGET_GID" ]] && TARGET_GID=$(id -g "$TARGET_USER")
    log_success "  $TARGET_USER 생성 완료 (UID=$TARGET_UID GID=$TARGET_GID)"
fi
# 이후 원격에 보낼 때 사용할 결정값
[[ -z "$TARGET_UID" ]] && TARGET_UID=$(id -u "$TARGET_USER")
[[ -z "$TARGET_GID" ]] && TARGET_GID=$(id -g "$TARGET_USER")

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

# ────────────────────────────────────────────────────────────
# 헤드 로컬: admin_user + cluster_users 생성/UID 정렬
# ────────────────────────────────────────────────────────────
RUNNING_USER="${SUDO_USER:-$(whoami)}"
sync_local_user() {
    local name="$1" uid="$2" gid="$3" sudo_flag="$4" pw_mode="$5" groups_csv="$6"
    [[ -z "$name" ]] && return
    # 그룹 보장
    if [[ -n "$gid" ]] && ! getent group "$gid" &>/dev/null; then
        groupadd -g "$gid" "$name" 2>/dev/null || true
    fi
    if id "$name" &>/dev/null; then
        local cur_uid cur_gid
        cur_uid=$(id -u "$name"); cur_gid=$(id -g "$name")
        if [[ "$name" == "$RUNNING_USER" && -n "$uid" && "$cur_uid" != "$uid" ]]; then
            log_warning "헤드: $name 은 현재 실행 계정 — UID 변경 스킵 (현재 $cur_uid, 목표 $uid)"
        else
            if [[ -n "$gid" && "$cur_gid" != "$gid" ]]; then
                log_warning "헤드 GID 정렬 $name: $cur_gid → $gid"
                groupmod -g "$gid" "$name" 2>/dev/null || usermod -g "$gid" "$name" 2>/dev/null || true
                find /home/$name -gid "$cur_gid" -exec chgrp -h "$gid" {} + 2>/dev/null || true
            fi
            if [[ -n "$uid" && "$cur_uid" != "$uid" ]]; then
                log_warning "헤드 UID 정렬 $name: $cur_uid → $uid"
                pkill -KILL -u "$name" 2>/dev/null || true; sleep 1
                usermod -u "$uid" "$name"
                find /home/$name -uid "$cur_uid" -exec chown -h "$uid" {} + 2>/dev/null || true
            fi
        fi
    else
        local args=(-m -s /bin/bash)
        [[ -n "$uid" ]] && args+=(-u "$uid")
        [[ -n "$gid" ]] && args+=(-g "$gid")
        [[ -n "$groups_csv" ]] && args+=(-G "$groups_csv")
        useradd "${args[@]}" "$name"
        if [[ "$pw_mode" == "set" ]]; then
            echo "$name:$HASHED_PASSWORD" | chpasswd -e
        else
            passwd -l "$name" >/dev/null
        fi
        if [[ "$sudo_flag" == "true" ]]; then
            echo "$name ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$name
            chmod 440 /etc/sudoers.d/$name
        fi
        log_success "헤드: $name 신규 생성 (uid=$(id -u $name) gid=$(id -g $name))"
    fi
}

while IFS=$'\t' read -r n uid gid s pm g; do
    [[ -z "$n" ]] && continue
    sync_local_user "$n" "$uid" "$gid" "$s" "$pm" "$g"
done <<< "$EXTRA_USERS_TSV"

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
for n in nodes.get('viz_nodes', []): ips.add(n['ip_address'])
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

# 2. $TARGET_USER 생성 또는 UID/GID 정렬
TGT_UID="$TARGET_UID"
TGT_GID="$TARGET_GID"
FORCE_RC="$FORCE_RECREATE"

# 충돌 UID/GID 점유자 비우기 (다른 사용자가 같은 UID 가지면 useradd 실패)
CUR_OWNER_UID=\$(getent passwd "\$TGT_UID" 2>/dev/null | cut -d: -f1)
if [[ -n "\$CUR_OWNER_UID" && "\$CUR_OWNER_UID" != "$TARGET_USER" ]]; then
    echo "    [2/7] ⚠ UID \$TGT_UID 가 \$CUR_OWNER_UID 에 점유됨 — 충돌"
    echo "ERROR_UID_CONFLICT"
    exit 1
fi
CUR_OWNER_GID=\$(getent group "\$TGT_GID" 2>/dev/null | cut -d: -f1)

if id $TARGET_USER &>/dev/null; then
    CUR_UID=\$(id -u $TARGET_USER)
    CUR_GID=\$(id -g $TARGET_USER)
    if [[ "\$FORCE_RC" == "true" ]]; then
        echo "    [2/7] 기존 $TARGET_USER 삭제 후 재생성 (force-recreate)"
        SUDO pkill -KILL -u $TARGET_USER 2>/dev/null || true
        sleep 1
        SUDO userdel -r $TARGET_USER 2>/dev/null || SUDO userdel $TARGET_USER 2>/dev/null || true
        SUDO rm -rf /home/$TARGET_USER
        # 그룹: 동일 GID 그룹 없으면 생성
        if [[ -z "\$CUR_OWNER_GID" ]]; then
            SUDO groupadd -g "\$TGT_GID" $TARGET_USER 2>/dev/null || true
        fi
        SUDO useradd -m -s /bin/bash -G sudo -u "\$TGT_UID" -g "\$TGT_GID" $TARGET_USER
        echo "    [2/7] ✓ 재생성 완료 (UID=\$(id -u $TARGET_USER) GID=\$(id -g $TARGET_USER))"
    else
        # sync 모드
        if [[ "\$CUR_GID" != "\$TGT_GID" ]]; then
            echo "    [2/7] GID 정렬: \$CUR_GID → \$TGT_GID"
            if [[ -z "\$CUR_OWNER_GID" ]]; then
                SUDO groupadd -g "\$TGT_GID" $TARGET_USER 2>/dev/null || true
            fi
            SUDO groupmod -g "\$TGT_GID" $TARGET_USER 2>/dev/null || \
                SUDO usermod -g "\$TGT_GID" $TARGET_USER 2>/dev/null || true
            SUDO find /home/$TARGET_USER -gid "\$CUR_GID" -exec chgrp -h "\$TGT_GID" {} + 2>/dev/null || true
        fi
        if [[ "\$CUR_UID" != "\$TGT_UID" ]]; then
            echo "    [2/7] UID 정렬: \$CUR_UID → \$TGT_UID"
            SUDO pkill -KILL -u $TARGET_USER 2>/dev/null || true
            sleep 1
            SUDO usermod -u "\$TGT_UID" $TARGET_USER
            SUDO find /home/$TARGET_USER -uid "\$CUR_UID" -exec chown -h "\$TGT_UID" {} + 2>/dev/null || true
        fi
        echo "    [2/7] ✓ $TARGET_USER 유지 (UID=\$(id -u $TARGET_USER) GID=\$(id -g $TARGET_USER))"
    fi
else
    if [[ -z "\$CUR_OWNER_GID" ]]; then
        SUDO groupadd -g "\$TGT_GID" $TARGET_USER 2>/dev/null || true
    fi
    SUDO useradd -m -s /bin/bash -G sudo -u "\$TGT_UID" -g "\$TGT_GID" $TARGET_USER
    echo "    [2/7] ✓ $TARGET_USER 신규 생성 (UID=\$(id -u $TARGET_USER) GID=\$(id -g $TARGET_USER))"
fi

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

# ────────────────────────────────────────────────────────────
# 원격 추가-사용자 동기화 스크립트 (admin_user + cluster_users)
# stdin으로 TSV 받아서 처리 (한 번에 모두)
# ────────────────────────────────────────────────────────────
extra_users_cmd() {
cat <<EOF
set -uo pipefail
sync_user() {
    local name="\$1" uid="\$2" gid="\$3" sudo_flag="\$4" pw_mode="\$5" groups_csv="\$6"
    [[ -z "\$name" ]] && return 0
    if [[ -n "\$gid" ]] && ! getent group "\$gid" &>/dev/null; then
        sudo groupadd -g "\$gid" "\$name" 2>/dev/null || true
    fi
    if id "\$name" &>/dev/null; then
        local cur_uid=\$(id -u "\$name") cur_gid=\$(id -g "\$name")
        # 타깃 UID/GID 충돌 검사 (다른 사용자가 점유)
        if [[ -n "\$uid" && "\$cur_uid" != "\$uid" ]]; then
            local owner=\$(getent passwd "\$uid" 2>/dev/null | cut -d: -f1)
            if [[ -n "\$owner" && "\$owner" != "\$name" ]]; then
                echo "    ERROR \$name UID \$uid 가 '\$owner' 에 점유됨 — 스킵"
                return 1
            fi
        fi
        # 사용자 관련 경로만 chown — 시스템 전체 스캔 안 함
        local USER_PATHS=()
        [[ -d /home/\$name ]] && USER_PATHS+=(/home/\$name)
        [[ -d /scratch/\$name ]] && USER_PATHS+=(/scratch/\$name)
        if [[ -n "\$gid" && "\$cur_gid" != "\$gid" ]]; then
            sudo groupmod -g "\$gid" "\$name" 2>/dev/null || sudo usermod -g "\$gid" "\$name" 2>/dev/null || true
            [[ \${#USER_PATHS[@]} -gt 0 ]] && sudo find "\${USER_PATHS[@]}" -gid "\$cur_gid" -exec chgrp -h "\$gid" {} + 2>/dev/null || true
        fi
        if [[ -n "\$uid" && "\$cur_uid" != "\$uid" ]]; then
            sudo pkill -KILL -u "\$name" 2>/dev/null || true; sleep 1
            sudo usermod -u "\$uid" "\$name"
            [[ \${#USER_PATHS[@]} -gt 0 ]] && sudo find "\${USER_PATHS[@]}" -uid "\$cur_uid" -exec chown -h "\$uid" {} + 2>/dev/null || true
        fi
        echo "    sync \$name uid=\$(id -u \$name) gid=\$(id -g \$name)"
    else
        local args=(-m -s /bin/bash)
        [[ -n "\$uid" ]] && args+=(-u "\$uid")
        [[ -n "\$gid" ]] && args+=(-g "\$gid")
        [[ -n "\$groups_csv" ]] && args+=(-G "\$groups_csv")
        sudo useradd "\${args[@]}" "\$name"
        if [[ "\$pw_mode" == "set" ]]; then
            echo "\$name:$HASHED_PASSWORD" | sudo chpasswd -e
        else
            sudo passwd -l "\$name" >/dev/null
        fi
        if [[ "\$sudo_flag" == "true" ]]; then
            echo "\$name ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/\$name >/dev/null
            sudo chmod 440 /etc/sudoers.d/\$name
        fi
        echo "    create \$name uid=\$(id -u \$name) gid=\$(id -g \$name)"
    fi
}
# stdin TSV 처리
while IFS=\$'\t' read -r N UID_ GID_ S PM G; do
    [[ -z "\$N" ]] && continue
    sync_user "\$N" "\$UID_" "\$GID_" "\$S" "\$PM" "\$G"
done
echo 'EXTRA_USERS_OK'
EOF
}

run_extra_users_via_stcx() {
    local ip="$1"
    # SSH_OPTS의 -n은 stdin 차단해서 TSV 전달 못 함 → 자체 옵션 사용
    local OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
    # 키 인증 우선 (BatchMode로 prompt 차단)
    if ssh -o BatchMode=yes $OPTS "$TARGET_USER@$ip" "echo OK" &>/dev/null; then
        ssh $OPTS "$TARGET_USER@$ip" "$(extra_users_cmd)" <<< "$EXTRA_USERS_TSV" 2>&1
    elif [[ -n "${TARGET_PASSWORD:-}" ]] && command -v sshpass &>/dev/null; then
        SSHPASS="$TARGET_PASSWORD" sshpass -e ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
            $OPTS "$TARGET_USER@$ip" "$(extra_users_cmd)" <<< "$EXTRA_USERS_TSV" 2>&1
    else
        echo "ERROR: $TARGET_USER 키 인증 실패, sshpass 폴백도 불가"
        return 1
    fi
}

SUCCESS=0; FAILED=0; SKIPPED=0
EXTRA_OK=0; EXTRA_FAIL=0

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
            log_success "[$ip] ✅ stcx 정상"
            SKIPPED=$((SKIPPED + 1))
            # 추가 사용자 sync도 적용
            if [[ -n "$EXTRA_USERS_TSV" ]]; then
                extra_result=$(run_extra_users_via_stcx "$ip")
                if echo "$extra_result" | grep -q "EXTRA_USERS_OK"; then
                    log_success "  [$ip] 추가 사용자 sync OK"
                    EXTRA_OK=$((EXTRA_OK+1))
                else
                    log_warning "  [$ip] 추가 사용자 sync 실패: $(echo "$extra_result" | tail -1)"
                    EXTRA_FAIL=$((EXTRA_FAIL+1))
                fi
            fi
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
                if [[ -n "$EXTRA_USERS_TSV" ]]; then
                    extra_result=$(run_extra_users_via_stcx "$ip")
                    if echo "$extra_result" | grep -q "EXTRA_USERS_OK"; then
                        log_success "  [$ip] 추가 사용자 sync OK"
                        EXTRA_OK=$((EXTRA_OK+1))
                    else
                        log_warning "  [$ip] 추가 사용자 sync 실패"
                        EXTRA_FAIL=$((EXTRA_FAIL+1))
                    fi
                fi
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
        if [[ -n "$EXTRA_USERS_TSV" ]]; then
            extra_result=$(run_extra_users_via_stcx "$ip")
            if echo "$extra_result" | grep -q "EXTRA_USERS_OK"; then
                log_success "  [$ip] 추가 사용자 sync OK"
                EXTRA_OK=$((EXTRA_OK+1))
            else
                log_warning "  [$ip] 추가 사용자 sync 실패: $(echo "$extra_result" | tail -1)"
                EXTRA_FAIL=$((EXTRA_FAIL+1))
            fi
        fi
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
