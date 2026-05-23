#!/bin/bash
# slurmd 빠른 복구 스크립트
# 노드는 살아있지만 slurmd만 죽어있을 때 사용
# - 죽은 노드는 SSH 타임아웃 후 스킵
# - munge → glusterfs 마운트 확인 → slurmd enable + start
# Usage: sudo ./revive_slurmd.sh [--config CONFIG_FILE] [--node HOSTNAME]

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
SPECIFIC_NODE=""
SSH_TIMEOUT=5

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_fail() { echo -e "  ${RED}✗${NC} $1"; }

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)  CONFIG_FILE="$2"; shift 2 ;;
        --node)    SPECIFIC_NODE="$2"; shift 2 ;;
        *)         shift ;;
    esac
done

# config 파일 자동 탐색
if [[ -z "$CONFIG_FILE" ]]; then
    for candidate in \
        "$SCRIPT_DIR/my_multihead_cluster_2.yaml" \
        "$SCRIPT_DIR/my_multihead_cluster.yaml" \
        "$SCRIPT_DIR/my_multihead_cluster.yaml" \
        "$SCRIPT_DIR/dev_cluster.yaml"; do
        if [[ -f "$candidate" ]]; then
            CONFIG_FILE="$candidate"
            break
        fi
    done
fi

if [[ -z "$CONFIG_FILE" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ config 파일을 찾을 수 없습니다."
    echo "   Usage: sudo $0 --config my_multihead_cluster.yaml"
    exit 1
fi

# YAML에서 노드 목록 + GlusterFS 설정 읽기
NODE_INFO=$(python3 << EOPY
import yaml, json, sys

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

nodes = config.get('nodes', {})
gluster = config.get('shared_storage', {}).get('glusterfs', {})

# controller IP (GlusterFS 서버)
controllers = nodes.get('controllers', [])
gluster_server = controllers[0]['ip_address'] if controllers else ''
controller_hostname = controllers[0].get('hostname', '') if controllers else ''

result = {
    'gluster_server': gluster_server,
    'gluster_volume': gluster.get('volume_name', 'shared_data'),
    'gluster_mount': gluster.get('mount_point', '/mnt/gluster'),
    'controller_hostname': controller_hostname,
    'nodes': []
}

# compute_nodes
for n in nodes.get('compute_nodes', []):
    result['nodes'].append({
        'hostname': n['hostname'],
        'ip': n['ip_address'],
        'user': n.get('ssh_user', 'koopark')
    })

# viz_nodes
for n in nodes.get('viz_nodes', []):
    result['nodes'].append({
        'hostname': n['hostname'],
        'ip': n['ip_address'],
        'user': n.get('ssh_user', 'koopark')
    })

# 중복 제거 (hostname 기준)
seen = set()
unique = []
for n in result['nodes']:
    if n['hostname'] not in seen:
        seen.add(n['hostname'])
        unique.append(n)
result['nodes'] = unique

print(json.dumps(result))
EOPY
)

GLUSTER_SERVER=$(echo "$NODE_INFO"  | python3 -c "import sys,json; print(json.load(sys.stdin)['gluster_server'])")
GLUSTER_VOLUME=$(echo "$NODE_INFO"  | python3 -c "import sys,json; print(json.load(sys.stdin)['gluster_volume'])")
GLUSTER_MOUNT=$(echo "$NODE_INFO"   | python3 -c "import sys,json; print(json.load(sys.stdin)['gluster_mount'])")
CTRL_HOSTNAME=$(echo "$NODE_INFO"   | python3 -c "import sys,json; print(json.load(sys.stdin)['controller_hostname'])")
NODE_COUNT=$(echo "$NODE_INFO"      | python3 -c "import sys,json; print(len(json.load(sys.stdin)['nodes']))")
NODES_JSON=$(echo "$NODE_INFO"      | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f\"{n['hostname']}|{n['ip']}|{n['user']}\") for n in d['nodes']]")

echo "=========================================="
echo "  slurmd 복구 스크립트"
echo "=========================================="
echo ""
echo "  config  : $CONFIG_FILE"
echo "  gluster : $GLUSTER_SERVER:/$GLUSTER_VOLUME → $GLUSTER_MOUNT"
echo "  대상 노드: $NODE_COUNT개"
if [[ -n "$SPECIFIC_NODE" ]]; then
    echo "  지정 노드: $SPECIFIC_NODE"
fi
echo ""

SUCCESS_NODES=""
FAILED_NODES=""
SKIP_NODES=""

while IFS='|' read -r hostname ip user; do
    [[ -z "$hostname" ]] && continue

    # 컨트롤러는 스킵 (slurmd가 아닌 slurmctld를 돌림)
    if [[ "$hostname" == "$CTRL_HOSTNAME" ]]; then
        continue
    fi

    # 특정 노드 지정 시 필터링
    if [[ -n "$SPECIFIC_NODE" ]] && [[ "$hostname" != "$SPECIFIC_NODE" ]]; then
        continue
    fi

    echo "──────────────────────────────────────"
    echo "📡 $hostname ($ip)"

    # 1. SSH 접속 테스트
    if ! ssh -o ConnectTimeout=$SSH_TIMEOUT -o StrictHostKeyChecking=no -o BatchMode=yes "$user@$ip" "echo ok" &>/dev/null; then
        log_fail "SSH 접속 불가 (${SSH_TIMEOUT}초 타임아웃) — 스킵"
        SKIP_NODES="$SKIP_NODES $hostname"
        continue
    fi
    log_ok "SSH 접속 성공"

    # 2~5단계를 원격에서 한번에 실행
    REMOTE_RESULT=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o StrictHostKeyChecking=no "$user@$ip" bash << EOFREMOTE
#!/bin/bash

GLUSTER_SERVER="$GLUSTER_SERVER"
GLUSTER_VOLUME="$GLUSTER_VOLUME"
GLUSTER_MOUNT="$GLUSTER_MOUNT"

# sudo 함수
run_sudo() { sudo "\$@"; }

ERRORS=0

# 2. munge 확인/시작
if systemctl is-active --quiet munge; then
    echo "MUNGE:OK"
else
    run_sudo systemctl enable munge 2>/dev/null
    run_sudo systemctl start munge 2>/dev/null
    sleep 1
    if systemctl is-active --quiet munge; then
        echo "MUNGE:STARTED"
    else
        echo "MUNGE:FAIL"
        ERRORS=\$((ERRORS+1))
    fi
fi

# 3. GlusterFS 마운트 확인
if mountpoint -q "\$GLUSTER_MOUNT" 2>/dev/null; then
    echo "GLUSTER:OK"
else
    # autofs 재시작으로 마운트 시도
    if systemctl is-active --quiet autofs 2>/dev/null; then
        run_sudo systemctl restart autofs
        sleep 2
        # autofs는 접근 시 마운트
        ls "\$GLUSTER_MOUNT/" &>/dev/null
        sleep 1
    fi

    # 그래도 안 되면 직접 마운트
    if ! mountpoint -q "\$GLUSTER_MOUNT" 2>/dev/null; then
        run_sudo mkdir -p "\$GLUSTER_MOUNT"
        run_sudo mount -t glusterfs "\$GLUSTER_SERVER:/\$GLUSTER_VOLUME" "\$GLUSTER_MOUNT" 2>/dev/null
        sleep 1
    fi

    if mountpoint -q "\$GLUSTER_MOUNT" 2>/dev/null; then
        echo "GLUSTER:MOUNTED"
    else
        echo "GLUSTER:FAIL"
        # GlusterFS 실패해도 slurmd 시도는 함
    fi
fi

# 4. slurmd enable + start
run_sudo systemctl unmask slurmd 2>/dev/null
run_sudo systemctl enable slurmd 2>/dev/null
run_sudo systemctl restart slurmd 2>/dev/null
sleep 2

if systemctl is-active --quiet slurmd; then
    echo "SLURMD:OK"
else
    # 실패 원인 표시
    REASON=\$(journalctl -u slurmd -n 3 --no-pager 2>/dev/null | tail -1)
    echo "SLURMD:FAIL:\$REASON"
    ERRORS=\$((ERRORS+1))
fi

echo "ERRORS:\$ERRORS"
EOFREMOTE
)

    # 결과 파싱 및 출력
    MUNGE_STATUS=$(echo "$REMOTE_RESULT" | grep "^MUNGE:" | cut -d: -f2)
    GLUSTER_STATUS=$(echo "$REMOTE_RESULT" | grep "^GLUSTER:" | cut -d: -f2)
    SLURMD_STATUS=$(echo "$REMOTE_RESULT" | grep "^SLURMD:" | cut -d: -f2)
    ERROR_COUNT=$(echo "$REMOTE_RESULT" | grep "^ERRORS:" | cut -d: -f2)

    # munge
    case "$MUNGE_STATUS" in
        OK)      log_ok "munge 실행 중" ;;
        STARTED) log_ok "munge 시작됨" ;;
        *)       log_fail "munge 시작 실패" ;;
    esac

    # glusterfs
    case "$GLUSTER_STATUS" in
        OK)      log_ok "GlusterFS 마운트됨 ($GLUSTER_MOUNT)" ;;
        MOUNTED) log_ok "GlusterFS 마운트 성공" ;;
        *)       log_warn "GlusterFS 마운트 실패 (slurmd는 시도)" ;;
    esac

    # slurmd
    case "$SLURMD_STATUS" in
        OK)
            log_ok "slurmd 실행 중"
            SUCCESS_NODES="$SUCCESS_NODES $hostname"
            ;;
        *)
            SLURMD_REASON=$(echo "$REMOTE_RESULT" | grep "^SLURMD:FAIL:" | cut -d: -f3-)
            log_fail "slurmd 시작 실패"
            [[ -n "$SLURMD_REASON" ]] && echo "       $SLURMD_REASON"
            FAILED_NODES="$FAILED_NODES $hostname"
            ;;
    esac

done <<< "$NODES_JSON"

# 헤드노드에서 노드 상태 resume
echo ""
echo "──────────────────────────────────────"
echo "🔄 노드 상태 resume 중..."
SCONTROL_BIN=$(which scontrol 2>/dev/null || echo "/usr/local/slurm/bin/scontrol")

if [[ -n "$SUCCESS_NODES" ]]; then
    # 성공한 노드만 resume
    RESUME_LIST=$(echo "$SUCCESS_NODES" | xargs | tr ' ' ',')
    sudo $SCONTROL_BIN update NodeName="$RESUME_LIST" State=RESUME 2>/dev/null || true
    log_ok "resume 완료: $RESUME_LIST"
fi

# 결과 요약
echo ""
echo "=========================================="
echo "  결과 요약"
echo "=========================================="
[[ -n "$SUCCESS_NODES" ]] && echo -e "  ${GREEN}성공:${NC}$SUCCESS_NODES"
[[ -n "$FAILED_NODES" ]]  && echo -e "  ${RED}실패:${NC}$FAILED_NODES"
[[ -n "$SKIP_NODES" ]]    && echo -e "  ${YELLOW}스킵 (접속불가):${NC}$SKIP_NODES"
echo ""

# sinfo 결과 출력
SINFO_BIN=$(which sinfo 2>/dev/null || echo "/usr/local/slurm/bin/sinfo")
$SINFO_BIN -N -l 2>/dev/null || true
