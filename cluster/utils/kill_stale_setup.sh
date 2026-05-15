#!/bin/bash
################################################################################
# 중단된 클러스터 설치 프로세스 정리
#
# 사용법:
#   sudo bash cluster/utils/kill_stale_setup.sh [--config YAML] [--remote] [--dry-run]
#
# 옵션:
#   --config PATH   YAML 설정 파일 (기본: my_multihead_cluster_2.yaml)
#   --remote        원격 노드의 apt/dpkg/bash 설치 프로세스도 정리
#   --dry-run       실제 kill 없이 대상 프로세스만 출력
################################################################################

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="my_multihead_cluster_2.yaml"
REMOTE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --config)   CONFIG_FILE="$2"; shift 2 ;;
        --remote)   REMOTE=true; shift ;;
        --dry-run)  DRY_RUN=true; shift ;;
        *) shift ;;
    esac
done

do_kill() {
    local pid="$1" name="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[dry-run]${NC} would kill PID $pid ($name)"
    else
        kill -9 "$pid" 2>/dev/null && \
            echo -e "  ${GREEN}killed${NC} PID $pid ($name)" || true
    fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 클러스터 설치 잔여 프로세스 정리"
[[ "$DRY_RUN" == "true" ]] && echo " (dry-run 모드)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 현재 프로세스의 조상 PID 목록 수집 (자기 자신 + 모든 부모)
get_ancestor_pids() {
    local pid=$$
    local ancestors="$pid"
    while true; do
        local ppid
        ppid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null || echo 1)
        [[ "$ppid" -le 1 ]] && break
        ancestors="$ancestors $ppid"
        pid=$ppid
    done
    echo "$ancestors"
}
ANCESTOR_PIDS=$(get_ancestor_pids)

safe_to_kill() {
    local pid="$1"
    for ancestor in $ANCESTOR_PIDS; do
        [[ "$pid" == "$ancestor" ]] && return 1
    done
    return 0
}

# ── 1. 로컬: phase*.sh 백그라운드 프로세스 ────────────────────────────────────
log_info "[로컬] phase 설치 스크립트 프로세스..."
killed=0
while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    cmd=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
    safe_to_kill "$pid" || continue
    do_kill "$pid" "$cmd"
    killed=$((killed+1))
done < <(pgrep -af "phase[0-9].*\.sh|setup_cluster_full|start_multihead" 2>/dev/null | grep -v "kill_stale" || true)
[[ $killed -eq 0 ]] && log_success "없음"

# ── 2. 로컬: sshpass / ssh to cluster nodes ────────────────────────────────────
log_info "[로컬] ssh/sshpass/scp 설치 관련 프로세스..."
killed=0
while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    cmd=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
    do_kill "$pid" "$cmd"
    killed=$((killed+1))
done < <(pgrep -af "sshpass|scp.*offline_packages|ssh.*EOFREMOTE|ssh.*bash -s" 2>/dev/null | grep -v "$$\|kill_stale" || true)
[[ $killed -eq 0 ]] && log_success "없음"

# ── 3. 로컬: /tmp phase10 결과 파일 정리 ────────────────────────────────────────
log_info "[로컬] /tmp 임시 파일 정리..."
tmp_files=$(ls /tmp/phase10_results_*.txt /tmp/munge.key.phase10.* 2>/dev/null || true)
if [[ -n "$tmp_files" ]]; then
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$tmp_files" | xargs rm -f
        log_success "정리됨: $(echo "$tmp_files" | wc -l)개"
    else
        echo "$tmp_files" | while read -r f; do echo "  [dry-run] would remove $f"; done
    fi
else
    log_success "없음"
fi

# ── 4. 원격 노드 정리 (--remote 옵션) ────────────────────────────────────────
if [[ "$REMOTE" == "true" ]]; then
    echo ""
    log_info "[원격] 노드 apt/dpkg/bash 설치 프로세스 정리..."

    CONFIG_PATH="$PROJECT_ROOT/$CONFIG_FILE"
    [[ ! -f "$CONFIG_PATH" ]] && { log_warn "YAML 없음: $CONFIG_PATH"; exit 0; }

    NODE_IPS=$(python3 -c "
import yaml
with open('$CONFIG_PATH') as f:
    c = yaml.safe_load(f)
nodes = c.get('nodes', {})
ips = set()
for n in nodes.get('compute_nodes', []): ips.add((n['ip_address'], n.get('ssh_user','stcx')))
for n in nodes.get('viz_nodes', []):     ips.add((n['ip_address'], n.get('ssh_user','stcx')))
for ip, user in sorted(ips): print(f'{user}@{ip}')
" 2>/dev/null)

    SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR"

    # ssh_user의 키 탐색
    ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
    ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6 2>/dev/null || echo "")
    SSH_KEY_OPT=""
    for _k in "${ORIGINAL_HOME}/.ssh/id_ed25519" "${ORIGINAL_HOME}/.ssh/id_rsa"; do
        [[ -f "$_k" ]] && { SSH_KEY_OPT="-i $_k"; break; }
    done

    SSH_PASSWORD=$(python3 -c "
import yaml
with open('$CONFIG_PATH') as f:
    c = yaml.safe_load(f)
print(c.get('cluster_info',{}).get('ssh_password',''))
" 2>/dev/null || echo "")

    total=0; cleaned=0
    while IFS= read -r target; do
        [[ -z "$target" ]] && continue
        user="${target%@*}"; ip="${target#*@}"

        # 키 파일이 해당 user 것인지 확인
        user_home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || echo "")
        key_opt="$SSH_KEY_OPT"
        for _k in "${user_home}/.ssh/id_ed25519" "${user_home}/.ssh/id_rsa"; do
            [[ -f "$_k" ]] && { key_opt="-i $_k"; break; }
        done

        # 연결 테스트
        if ! ssh -n $key_opt $SSH_OPTS "$target" "exit" &>/dev/null; then
            # sshpass fallback
            if [[ -n "$SSH_PASSWORD" ]] && command -v sshpass &>/dev/null; then
                export SSHPASS="$SSH_PASSWORD"
                if ! sshpass -e ssh -n -o BatchMode=no $SSH_OPTS "$target" "exit" &>/dev/null; then
                    continue
                fi
                key_opt=""
                SSH_CMD="sshpass -e ssh -n -o BatchMode=no"
            else
                continue
            fi
        else
            SSH_CMD="ssh -n $key_opt"
        fi

        total=$((total+1))
        KILL_CMD='pids=$(pgrep -f "apt-get|apt |dpkg|install_offline_packages|deploy_slurm|deploy_munge|bash -s" 2>/dev/null || true); [[ -n "$pids" ]] && sudo kill -9 $pids 2>/dev/null && echo "killed:$pids" || echo "clean"'

        if [[ "$DRY_RUN" == "true" ]]; then
            result=$($SSH_CMD $SSH_OPTS "$target" 'pgrep -af "apt-get|apt |dpkg|install_offline_packages|deploy_slurm|deploy_munge" 2>/dev/null || echo ""' 2>/dev/null || echo "")
            [[ -n "$result" ]] && echo "  [dry-run] $ip: $result" || echo "  [dry-run] $ip: clean"
        else
            result=$($SSH_CMD $SSH_OPTS "$target" "$KILL_CMD" 2>/dev/null || echo "unreachable")
            if echo "$result" | grep -q "^killed:"; then
                echo -e "  ${GREEN}✓${NC} $ip: 프로세스 정리됨"
                cleaned=$((cleaned+1))
            else
                echo -e "  ${BLUE}·${NC} $ip: 이미 깨끗함"
            fi
        fi
    done <<< "$NODE_IPS"

    echo ""
    log_success "원격 점검: ${total}개 노드, 정리: ${cleaned}개"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "완료. 이제 설치 스크립트를 재실행하세요."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
