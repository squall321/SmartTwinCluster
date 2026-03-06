#!/bin/bash
################################################################################
# 비정상 노드 강제 복구 스크립트
# IDLE, ALLOCATED 외 모든 비정상 상태를 강제로 정상화
#
# 대상: IDLE*, UNKNOWN, DOWN, DRAIN, NOT_RESPONDING, INVALID_REG 등
#
# 복구 순서 (노드별):
#   1. SSH 접속 확인 (불가 시 스킵)
#   2. 실제 하드웨어 스펙 조회 → slurm.conf INVALID_REG 자동 수정
#   3. slurm.conf 동기화 (헤드노드 → 컴퓨트노드)
#   4. munge 재시작
#   5. slurmd 강제 재시작
#   6. scontrol state=resume
#
# Usage: sudo ./fix_all_nodes.sh [--config CONFIG_FILE]
################################################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_TIMEOUT=5

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_fail() { echo -e "  ${RED}✗${NC} $1"; }
log_info() { echo -e "  ${CYAN}→${NC} $1"; }

SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes"
SCP_CMD="scp -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT -q"

# ──────────────────────────────────────
# 인자 파싱
# ──────────────────────────────────────
CONFIG_FILE=""
FIX_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)  CONFIG_FILE="$2"; shift 2 ;;
        --all)     FIX_ALL=true; shift ;;
        --help|-h)
            echo "Usage: sudo $0 [--config CONFIG_FILE] [--all]"
            echo ""
            echo "비정상 노드를 강제로 정상화합니다."
            echo ""
            echo "Options:"
            echo "  --config PATH    YAML 설정 파일"
            echo "  --all            정상 노드 포함 전체 재설정"
            echo "  --help, -h       도움말"
            exit 0
            ;;
        *) shift ;;
    esac
done

# config 자동 탐색
if [[ -z "$CONFIG_FILE" ]]; then
    for candidate in \
        "$SCRIPT_DIR/my_multihead_cluster_2.yaml" \
        "$SCRIPT_DIR/my_multihead_cluster.yaml" \
        "$SCRIPT_DIR/my_cluster.yaml" \
        "$SCRIPT_DIR/dev_cluster.yaml"; do
        if [[ -f "$candidate" ]]; then
            CONFIG_FILE="$candidate"
            break
        fi
    done
fi

if [[ -z "$CONFIG_FILE" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ config 파일을 찾을 수 없습니다."
    echo "   Usage: sudo $0 --config my_cluster.yaml"
    exit 1
fi

# slurm.conf 경로
SLURM_CONF=""
for p in /etc/slurm/slurm.conf /usr/local/slurm/etc/slurm.conf /opt/slurm/etc/slurm.conf; do
    if [[ -f "$p" ]]; then
        SLURM_CONF="$p"
        break
    fi
done

SCONTROL=""
for p in /usr/local/slurm/bin/scontrol /opt/slurm/bin/scontrol /usr/bin/scontrol; do
    if [[ -x "$p" ]]; then
        SCONTROL="$p"
        break
    fi
done

echo "=========================================="
echo "🔧 비정상 노드 강제 복구"
echo "=========================================="
echo "  config    : $CONFIG_FILE"
echo "  slurm.conf: $SLURM_CONF"
echo ""

# ──────────────────────────────────────
# sinfo로 비정상 노드 확인
# ──────────────────────────────────────
echo "──────────────────────────────────────"
echo "📊 현재 노드 상태"
echo "──────────────────────────────────────"

SINFO_BIN=$(which sinfo 2>/dev/null || echo "/usr/local/slurm/bin/sinfo")
$SINFO_BIN -N -l 2>/dev/null || true
echo ""

# 비정상 노드 추출 (IDLE, ALLOCATED, COMPLETING, MIXED 제외)
PROBLEM_NODES=""
PROBLEM_INFO=""

if [[ "$FIX_ALL" == true ]]; then
    echo "  --all 옵션: 전체 노드 대상"
    PROBLEM_INFO=$($SINFO_BIN -N -h -o "%N %T" 2>/dev/null || true)
else
    # 정상 상태 패턴
    PROBLEM_INFO=$($SINFO_BIN -N -h -o "%N %T" 2>/dev/null | grep -ivE "^[^ ]+ (idle|allocated|completing|mixed)$" || true)
fi

if [[ -z "$PROBLEM_INFO" ]] && [[ "$FIX_ALL" != true ]]; then
    echo -e "  ${GREEN}✅ 모든 노드가 정상입니다.${NC}"
    echo ""
    exit 0
fi

echo "  비정상 노드:"
echo "$PROBLEM_INFO" | while read -r name state; do
    echo -e "    ${RED}$name${NC}: $state"
done
echo ""

# ──────────────────────────────────────
# YAML에서 노드 정보 로드
# ──────────────────────────────────────
NODE_MAP=$(python3 << EOPY
import yaml, json

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

nodes = {}
for section in ['controllers', 'compute_nodes', 'viz_nodes']:
    for n in config.get('nodes', {}).get(section, []):
        nodes[n['hostname']] = {
            'ip': n['ip_address'],
            'user': n.get('ssh_user', 'koopark')
        }
print(json.dumps(nodes))
EOPY
)

SLURM_CONF_MODIFIED=false
FIXED_NODES=""
FAILED_NODES=""
SKIPPED_NODES=""

# ──────────────────────────────────────
# 각 비정상 노드 수리
# ──────────────────────────────────────
echo "──────────────────────────────────────"
echo "🔧 노드별 복구 시작"
echo "──────────────────────────────────────"

while read -r NODE_NAME NODE_STATE; do
    [[ -z "$NODE_NAME" ]] && continue

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "📡 ${BOLD}$NODE_NAME${NC} (상태: ${RED}$NODE_STATE${NC})"

    # YAML에서 IP/user 가져오기
    NODE_IP=$(echo "$NODE_MAP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$NODE_NAME',{}).get('ip',''))" 2>/dev/null)
    NODE_USER=$(echo "$NODE_MAP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$NODE_NAME',{}).get('user','koopark'))" 2>/dev/null)

    if [[ -z "$NODE_IP" ]]; then
        # slurm.conf에서 NodeAddr 가져오기
        NODE_IP=$(grep "NodeName=$NODE_NAME " "$SLURM_CONF" 2>/dev/null | grep -oP 'NodeAddr=\K[^ ]+')
    fi

    if [[ -z "$NODE_IP" ]]; then
        log_fail "IP 주소를 찾을 수 없음 — 스킵"
        SKIPPED_NODES="$SKIPPED_NODES $NODE_NAME"
        continue
    fi

    log_info "IP: $NODE_IP, User: $NODE_USER"

    # ── 1. SSH 접속 테스트 ──
    if ! $SSH_CMD "$NODE_USER@$NODE_IP" "echo ok" &>/dev/null; then
        log_fail "SSH 접속 불가 (${SSH_TIMEOUT}초 타임아웃) — 스킵"
        SKIPPED_NODES="$SKIPPED_NODES $NODE_NAME"
        continue
    fi
    log_ok "SSH 접속 성공"

    # ── 1.5a. 시간 동기화 확인 및 수정 ──
    log_info "시간 동기화 확인 중..."
    LOCAL_TIME=$(date +%s)
    REMOTE_TIME=$($SSH_CMD "$NODE_USER@$NODE_IP" "date +%s" 2>/dev/null || echo "0")
    if [[ "$REMOTE_TIME" != "0" ]]; then
        TIME_DIFF=$(( LOCAL_TIME - REMOTE_TIME ))
        [[ $TIME_DIFF -lt 0 ]] && TIME_DIFF=$(( -TIME_DIFF ))
        if [[ $TIME_DIFF -gt 60 ]]; then
            log_warn "시간차 ${TIME_DIFF}초 → 동기화 시도"
            # 헤드노드 시간으로 강제 설정
            CURRENT_DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
            $SSH_CMD "$NODE_USER@$NODE_IP" "
                sudo timedatectl set-ntp false 2>/dev/null
                sudo date -s '$CURRENT_DATETIME' >/dev/null 2>&1
                sudo timedatectl set-ntp true 2>/dev/null
                sudo hwclock --systohc 2>/dev/null
            " 2>/dev/null
            # 재확인
            REMOTE_TIME2=$($SSH_CMD "$NODE_USER@$NODE_IP" "date +%s" 2>/dev/null || echo "0")
            LOCAL_TIME2=$(date +%s)
            NEW_DIFF=$(( LOCAL_TIME2 - REMOTE_TIME2 ))
            [[ $NEW_DIFF -lt 0 ]] && NEW_DIFF=$(( -NEW_DIFF ))
            if [[ $NEW_DIFF -le 5 ]]; then
                log_ok "시간 동기화 완료 (차이: ${NEW_DIFF}초)"
            else
                log_warn "시간 동기화 불완전 (차이: ${NEW_DIFF}초) — NTP 서버 확인 필요"
            fi
        else
            log_ok "시간 동기화 정상 (차이: ${TIME_DIFF}초)"
        fi
    else
        log_warn "원격 시간 조회 실패"
    fi

    # ── 1.5b. 방화벽 확인 및 Slurm 포트 개방 ──
    log_info "방화벽 확인 중..."
    FW_RESULT=$($SSH_CMD "$NODE_USER@$NODE_IP" bash << 'EOFFW'
FIXED=0
# ufw 확인
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1)
    if echo "$UFW_STATUS" | grep -qi "active"; then
        # Slurm 포트 개방 (6817: slurmctld, 6818: slurmd, 6819: slurmdbd)
        sudo ufw allow 6817:6819/tcp >/dev/null 2>&1
        # Munge
        sudo ufw allow 6818/tcp >/dev/null 2>&1
        echo "UFW:OPENED"
        FIXED=1
    else
        echo "UFW:INACTIVE"
    fi
else
    echo "UFW:NONE"
fi
# iptables 확인 (ufw 없을 때)
if [[ $FIXED -eq 0 ]] && command -v iptables &>/dev/null; then
    # Slurm 포트가 DROP/REJECT 되는지 확인
    BLOCKED=$(sudo iptables -L INPUT -n 2>/dev/null | grep -E "DROP|REJECT" | grep -c "681[789]" || echo "0")
    if [[ "$BLOCKED" -gt 0 ]]; then
        sudo iptables -I INPUT -p tcp --dport 6817:6819 -j ACCEPT 2>/dev/null
        echo "IPTABLES:OPENED"
    else
        echo "IPTABLES:OK"
    fi
fi
EOFFW
)
    case "$FW_RESULT" in
        *UFW:OPENED*)    log_ok "UFW 방화벽 — Slurm 포트 개방 완료" ;;
        *UFW:INACTIVE*)  log_ok "UFW 비활성 — 차단 없음" ;;
        *IPTABLES:OPENED*) log_ok "iptables — Slurm 포트 개방 완료" ;;
        *IPTABLES:OK*)   log_ok "iptables — Slurm 포트 차단 없음" ;;
        *)               log_ok "방화벽 없음 또는 차단 없음" ;;
    esac

    # ── 1.5c. /etc/hosts 확인 및 수정 ──
    log_info "/etc/hosts 확인 중..."
    # 헤드노드의 /etc/hosts에서 클러스터 노드 엔트리 수집
    HOSTS_ENTRIES=$(python3 << EOPY2
import yaml, json
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
entries = []
for section in ['controllers', 'compute_nodes', 'viz_nodes']:
    for n in config.get('nodes', {}).get(section, []):
        entries.append(f"{n['ip_address']} {n['hostname']}")
# 중복 제거
seen = set()
for e in entries:
    if e not in seen:
        seen.add(e)
        print(e)
EOPY2
)
    # 노드의 /etc/hosts에 누락된 엔트리 추가
    HOSTS_MISSING=$($SSH_CMD "$NODE_USER@$NODE_IP" bash << EOFHOSTS
MISSING=0
while IFS= read -r entry; do
    IP=\$(echo "\$entry" | awk '{print \$1}')
    HOST=\$(echo "\$entry" | awk '{print \$2}')
    if ! grep -q "\$HOST" /etc/hosts 2>/dev/null; then
        echo "\$entry" | sudo tee -a /etc/hosts >/dev/null
        MISSING=\$((MISSING+1))
    fi
done << 'INNEREOF'
$HOSTS_ENTRIES
INNEREOF
echo "\$MISSING"
EOFHOSTS
)
    HOSTS_MISSING=$(echo "$HOSTS_MISSING" | tail -1)
    if [[ "$HOSTS_MISSING" -gt 0 ]] 2>/dev/null; then
        log_ok "/etc/hosts에 ${HOSTS_MISSING}개 엔트리 추가"
    else
        log_ok "/etc/hosts 정상"
    fi

    # ── 1.5d. slurm 유저 UID/GID 확인 및 수정 ──
    log_info "slurm 유저 UID/GID 확인 중..."
    LOCAL_SLURM_ID=$(id slurm 2>/dev/null || echo "")
    if [[ -n "$LOCAL_SLURM_ID" ]]; then
        LOCAL_UID=$(echo "$LOCAL_SLURM_ID" | grep -oP 'uid=\K[0-9]+')
        LOCAL_GID=$(echo "$LOCAL_SLURM_ID" | grep -oP 'gid=\K[0-9]+')

        REMOTE_SLURM_ID=$($SSH_CMD "$NODE_USER@$NODE_IP" "id slurm 2>/dev/null || echo 'NOUSER'" 2>/dev/null)

        if [[ "$REMOTE_SLURM_ID" == "NOUSER" ]]; then
            log_warn "slurm 유저 없음 → 생성 중 (uid=$LOCAL_UID, gid=$LOCAL_GID)"
            $SSH_CMD "$NODE_USER@$NODE_IP" "
                sudo groupadd -g $LOCAL_GID slurm 2>/dev/null || true
                sudo useradd -u $LOCAL_UID -g $LOCAL_GID -r -s /usr/sbin/nologin slurm 2>/dev/null || true
            " 2>/dev/null
            log_ok "slurm 유저 생성 완료"
        else
            REMOTE_UID=$(echo "$REMOTE_SLURM_ID" | grep -oP 'uid=\K[0-9]+')
            REMOTE_GID=$(echo "$REMOTE_SLURM_ID" | grep -oP 'gid=\K[0-9]+')

            if [[ "$LOCAL_UID" != "$REMOTE_UID" ]] || [[ "$LOCAL_GID" != "$REMOTE_GID" ]]; then
                log_warn "UID/GID 불일치 (로컬: $LOCAL_UID/$LOCAL_GID, 원격: $REMOTE_UID/$REMOTE_GID) → 수정 중"
                $SSH_CMD "$NODE_USER@$NODE_IP" "
                    sudo systemctl stop slurmd 2>/dev/null || true
                    sudo usermod -u $LOCAL_UID slurm 2>/dev/null || true
                    sudo groupmod -g $LOCAL_GID slurm 2>/dev/null || true
                    sudo chown -R slurm:slurm /var/spool/slurm /var/log/slurm /run/slurm 2>/dev/null || true
                    sudo chown -R slurm:slurm /usr/local/slurm/etc 2>/dev/null || true
                " 2>/dev/null
                log_ok "UID/GID 수정 완료 ($LOCAL_UID/$LOCAL_GID)"
            else
                log_ok "slurm UID/GID 일치 ($LOCAL_UID/$LOCAL_GID)"
            fi
        fi
    fi

    # ── 2. INVALID_REG 대응: 실제 하드웨어 스펙 조회 → slurm.conf 자동 수정 ──
    if echo "$NODE_STATE" | grep -qi "INVALID_REG"; then
        log_info "INVALID_REG 감지 → 실제 하드웨어 스펙 조회 중..."

        HW_INFO=$($SSH_CMD "$NODE_USER@$NODE_IP" bash << 'EOFHW'
# CPU 정보
SOCKETS=$(lscpu | awk '/^Socket\(s\):/{print $2}')
CORES=$(lscpu | awk '/^Core\(s\) per socket:/{print $NF}')
THREADS=$(lscpu | awk '/^Thread\(s\) per core:/{print $NF}')
TOTAL_CPUS=$((SOCKETS * CORES * THREADS))

# 메모리 (MB, Slurm용 - 약간 줄여서 안전마진)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
# Slurm은 RealMemory보다 약간 적은 메모리도 허용하므로 95% 사용
SLURM_MEM=$((TOTAL_MEM_MB * 95 / 100))

echo "$TOTAL_CPUS|$SOCKETS|$CORES|$THREADS|$SLURM_MEM|$TOTAL_MEM_MB"
EOFHW
)

        if [[ -n "$HW_INFO" ]]; then
            IFS='|' read -r REAL_CPUS REAL_SOCKETS REAL_CORES REAL_THREADS REAL_MEM TOTAL_MEM <<< "$HW_INFO"
            log_info "실제 스펙: CPUs=$REAL_CPUS Sockets=$REAL_SOCKETS Cores=$REAL_CORES Threads=$REAL_THREADS Mem=${TOTAL_MEM}MB"

            # slurm.conf에서 현재 설정 확인
            CURRENT_LINE=$(grep "^NodeName=$NODE_NAME " "$SLURM_CONF" 2>/dev/null)
            if [[ -n "$CURRENT_LINE" ]]; then
                CONF_CPUS=$(echo "$CURRENT_LINE" | grep -oP 'CPUs=\K[0-9]+')
                CONF_SOCKETS=$(echo "$CURRENT_LINE" | grep -oP 'Sockets=\K[0-9]+')
                CONF_CORES=$(echo "$CURRENT_LINE" | grep -oP 'CoresPerSocket=\K[0-9]+')
                CONF_THREADS=$(echo "$CURRENT_LINE" | grep -oP 'ThreadsPerCore=\K[0-9]+')
                CONF_MEM=$(echo "$CURRENT_LINE" | grep -oP 'RealMemory=\K[0-9]+')

                log_info "설정 스펙: CPUs=$CONF_CPUS Sockets=$CONF_SOCKETS Cores=$CONF_CORES Threads=$CONF_THREADS Mem=${CONF_MEM}MB"

                # 불일치 시 slurm.conf 수정
                if [[ "$REAL_CPUS" != "$CONF_CPUS" ]] || \
                   [[ "$REAL_SOCKETS" != "$CONF_SOCKETS" ]] || \
                   [[ "$REAL_CORES" != "$CONF_CORES" ]] || \
                   [[ "$REAL_THREADS" != "$CONF_THREADS" ]] || \
                   [[ "$REAL_MEM" -ne "$CONF_MEM" && "$TOTAL_MEM" -ne "$CONF_MEM" ]]; then

                    log_warn "스펙 불일치 → slurm.conf 자동 수정"

                    # NodeAddr 보존
                    NODE_ADDR=$(echo "$CURRENT_LINE" | grep -oP 'NodeAddr=\K[^ ]+')
                    # Gres 보존
                    NODE_GRES=$(echo "$CURRENT_LINE" | grep -oP 'Gres=\K[^ ]+' || echo "")

                    NEW_LINE="NodeName=$NODE_NAME NodeAddr=$NODE_ADDR CPUs=$REAL_CPUS Sockets=$REAL_SOCKETS CoresPerSocket=$REAL_CORES ThreadsPerCore=$REAL_THREADS RealMemory=$REAL_MEM State=UNKNOWN"
                    if [[ -n "$NODE_GRES" ]]; then
                        NEW_LINE="NodeName=$NODE_NAME NodeAddr=$NODE_ADDR CPUs=$REAL_CPUS Sockets=$REAL_SOCKETS CoresPerSocket=$REAL_CORES ThreadsPerCore=$REAL_THREADS RealMemory=$REAL_MEM Gres=$NODE_GRES State=UNKNOWN"
                    fi

                    # slurm.conf 수정 (모든 위치)
                    for conf in /etc/slurm/slurm.conf /usr/local/slurm/etc/slurm.conf /opt/slurm/etc/slurm.conf; do
                        if [[ -f "$conf" ]]; then
                            sudo sed -i "s|^NodeName=$NODE_NAME .*|$NEW_LINE|" "$conf"
                        fi
                    done

                    log_ok "slurm.conf 수정 완료: $NEW_LINE"
                    SLURM_CONF_MODIFIED=true
                else
                    log_ok "스펙 일치 — slurm.conf 수정 불필요"
                fi
            fi
        else
            log_warn "하드웨어 스펙 조회 실패"
        fi
    fi

    # ── 3. slurm.conf 동기화 (헤드노드 → 컴퓨트노드) ──
    log_info "slurm.conf 동기화 중..."

    for conf in /etc/slurm/slurm.conf /usr/local/slurm/etc/slurm.conf; do
        if [[ -f "$conf" ]]; then
            $SCP_CMD "$conf" "$NODE_USER@$NODE_IP:/tmp/slurm.conf.new" 2>/dev/null
            $SSH_CMD "$NODE_USER@$NODE_IP" "
                sudo mkdir -p /etc/slurm /usr/local/slurm/etc 2>/dev/null
                sudo cp /tmp/slurm.conf.new /etc/slurm/slurm.conf 2>/dev/null
                sudo cp /tmp/slurm.conf.new /usr/local/slurm/etc/slurm.conf 2>/dev/null
                sudo chown slurm:slurm /etc/slurm/slurm.conf /usr/local/slurm/etc/slurm.conf 2>/dev/null
                sudo chmod 644 /etc/slurm/slurm.conf /usr/local/slurm/etc/slurm.conf 2>/dev/null
                rm -f /tmp/slurm.conf.new
            " 2>/dev/null
            break
        fi
    done

    # gres.conf도 동기화 (있으면)
    for gres_conf in /etc/slurm/gres.conf /usr/local/slurm/etc/gres.conf; do
        if [[ -f "$gres_conf" ]]; then
            $SCP_CMD "$gres_conf" "$NODE_USER@$NODE_IP:/tmp/gres.conf.new" 2>/dev/null
            $SSH_CMD "$NODE_USER@$NODE_IP" "
                sudo cp /tmp/gres.conf.new /etc/slurm/gres.conf 2>/dev/null
                sudo cp /tmp/gres.conf.new /usr/local/slurm/etc/gres.conf 2>/dev/null
                rm -f /tmp/gres.conf.new
            " 2>/dev/null
            break
        fi
    done
    log_ok "slurm.conf 동기화 완료"

    # ── 4. munge 재시작 ──
    log_info "munge 재시작 중..."
    MUNGE_RESULT=$($SSH_CMD "$NODE_USER@$NODE_IP" "
        sudo systemctl restart munge 2>/dev/null
        sleep 1
        systemctl is-active munge 2>/dev/null
    " 2>/dev/null)

    if [[ "$MUNGE_RESULT" == "active" ]]; then
        log_ok "munge 실행 중"
    else
        log_warn "munge 시작 실패 — munge.key 확인 필요"
    fi

    # ── 5. slurmd 강제 재시작 ──
    log_info "slurmd 강제 재시작 중..."
    SLURMD_RESULT=$($SSH_CMD "$NODE_USER@$NODE_IP" "
        sudo systemctl stop slurmd 2>/dev/null
        sudo pkill -9 slurmd 2>/dev/null
        sudo pkill -9 slurmstepd 2>/dev/null
        sleep 1
        sudo systemctl unmask slurmd 2>/dev/null
        sudo systemctl enable slurmd 2>/dev/null
        sudo systemctl start slurmd 2>/dev/null
        sleep 2
        systemctl is-active slurmd 2>/dev/null
    " 2>/dev/null)

    if [[ "$SLURMD_RESULT" == "active" ]]; then
        log_ok "slurmd 실행 중"
        FIXED_NODES="$FIXED_NODES $NODE_NAME"
    else
        log_fail "slurmd 시작 실패"
        # 실패 원인 표시
        $SSH_CMD "$NODE_USER@$NODE_IP" "sudo journalctl -u slurmd -n 5 --no-pager 2>/dev/null" | while read -r line; do
            echo "       $line"
        done
        FAILED_NODES="$FAILED_NODES $NODE_NAME"
    fi

done <<< "$PROBLEM_INFO"

# ──────────────────────────────────────
# slurm.conf 수정 시 slurmctld 재시작
# ──────────────────────────────────────
if [[ "$SLURM_CONF_MODIFIED" == true ]]; then
    echo ""
    echo "──────────────────────────────────────"
    echo "🔄 slurm.conf 변경됨 → slurmctld 재시작"
    echo "──────────────────────────────────────"
    sudo systemctl restart slurmctld 2>/dev/null || true
    sleep 3
    if systemctl is-active --quiet slurmctld 2>/dev/null; then
        log_ok "slurmctld 재시작 완료"
    else
        log_fail "slurmctld 재시작 실패"
    fi
fi

# ──────────────────────────────────────
# 모든 노드 state=resume
# ──────────────────────────────────────
echo ""
echo "──────────────────────────────────────"
echo "🔄 노드 상태 resume"
echo "──────────────────────────────────────"

sleep 2

if [[ -n "$FIXED_NODES" ]]; then
    RESUME_LIST=$(echo "$FIXED_NODES" | xargs | tr ' ' ',')
    sudo $SCONTROL update NodeName="$RESUME_LIST" State=RESUME Reason="fix_all_nodes.sh" 2>/dev/null || true
    log_ok "resume 완료: $RESUME_LIST"
fi

# drain 상태 해제 (undrain)
sleep 2
if [[ -n "$FIXED_NODES" ]]; then
    for node in $FIXED_NODES; do
        # drain 상태인 경우 idle로 강제 전환
        NODE_CUR_STATE=$(sudo $SCONTROL show node "$node" 2>/dev/null | grep -oP 'State=\K\S+' || echo "")
        if echo "$NODE_CUR_STATE" | grep -qi "DRAIN"; then
            sudo $SCONTROL update NodeName="$node" State=IDLE 2>/dev/null || \
            sudo $SCONTROL update NodeName="$node" State=RESUME 2>/dev/null || true
            log_info "$node: DRAIN → IDLE 전환 시도"
        fi
    done
fi

# ──────────────────────────────────────
# 결과 요약
# ──────────────────────────────────────
echo ""
echo "=========================================="
echo "  결과 요약"
echo "=========================================="
[[ -n "$FIXED_NODES" ]]   && echo -e "  ${GREEN}복구 성공:${NC}$FIXED_NODES"
[[ -n "$FAILED_NODES" ]]  && echo -e "  ${RED}복구 실패:${NC}$FAILED_NODES"
[[ -n "$SKIPPED_NODES" ]] && echo -e "  ${YELLOW}스킵 (접속불가/IP없음):${NC}$SKIPPED_NODES"
echo ""

# 최종 상태 확인
echo "──────────────────────────────────────"
echo "📊 최종 노드 상태"
echo "──────────────────────────────────────"
sleep 2
$SINFO_BIN -N -l 2>/dev/null || true
echo ""

# 아직 비정상 노드가 있으면 추가 안내
REMAINING=$($SINFO_BIN -N -h -o "%N %T" 2>/dev/null | grep -ivE "^[^ ]+ (idle|allocated|completing|mixed)$" || true)
if [[ -n "$REMAINING" ]]; then
    echo -e "${YELLOW}⚠  아직 비정상 노드가 있습니다:${NC}"
    echo "$REMAINING" | while read -r name state; do
        echo "    $name: $state"
    done
    echo ""
    echo "  추가 조치:"
    echo "    1. 노드에서 직접 확인: ssh <node> 'journalctl -u slurmd -n 20'"
    echo "    2. 전체 재배포: ./deploy_compute_nodes.sh --config $CONFIG_FILE"
    echo "    3. 수동 resume: sudo scontrol update nodename=<node> state=resume"
fi
