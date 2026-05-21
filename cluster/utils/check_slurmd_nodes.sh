#!/bin/bash
################################################################################
# 컴퓨트 노드 slurmd 상태 일괄 점검 (왜 sinfo 가 unk* 인지 진단)
#
# 사용:
#   ./cluster/utils/check_slurmd_nodes.sh my_multihead_cluster.yaml
#   ./cluster/utils/check_slurmd_nodes.sh my_multihead_cluster.yaml --fix   # 자동 복구 시도
################################################################################
set -uo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

YAML="${1:-my_multihead_cluster.yaml}"
FIX=0
[[ "${2:-}" == "--fix" ]] && FIX=1
[[ ! -f "$YAML" ]] && { echo "❌ YAML 없음: $YAML"; exit 1; }

echo -e "${BLUE}═══ 1) 헤드노드 slurmctld 자체 점검 ═══${NC}"
if ! systemctl is-active --quiet slurmctld; then
    echo -e "${RED}✗ slurmctld inactive${NC}"
    [[ $FIX -eq 1 ]] && sudo systemctl restart slurmctld
fi

if ! ss -tln | grep -q ":6817 "; then
    echo -e "${RED}✗ 6817(slurmctld) LISTEN 안 됨${NC}"
fi

echo ""
echo -e "${BLUE}═══ 2) sinfo state 별 노드 분류 ═══${NC}"
if ! command -v sinfo &>/dev/null; then
    echo "sinfo 없음"; exit 1
fi
timeout 10 sinfo -h -N -o "%N %T" 2>/dev/null | awk '{print $2}' | sort | uniq -c | sort -rn

echo ""
echo -e "${BLUE}═══ 3) unk* 노드 표본 5개 진단 ═══${NC}"
UNK_NODES=$(timeout 10 sinfo -h -N -o "%N %T" 2>/dev/null | awk '$2 ~ /unk/{print $1}' | sort -u | head -5)
if [[ -z "$UNK_NODES" ]]; then
    echo -e "${GREEN}✓ unknown 상태 노드 없음${NC}"
else
    # YAML에서 ssh_user 추출 (해당 노드의 ssh_user)
    SSH_USER_DEFAULT=$(python3 -c "
import yaml
c=yaml.safe_load(open('$YAML'))
nodes=(c.get('nodes',{}).get('compute_nodes',[]) or [])
if nodes: print(nodes[0].get('ssh_user','stcx'))
else: print('stcx')
" 2>/dev/null)

    declare -A FAIL_REASONS
    for n in $UNK_NODES; do
        echo -e "${YELLOW}--- $n ---${NC}"
        # 1) ping
        if ! ping -c 1 -W 2 "$n" &>/dev/null; then
            echo -e "  ${RED}✗ ping 실패 (네트워크/노드 다운)${NC}"
            FAIL_REASONS[network]=$((${FAIL_REASONS[network]:-0}+1))
            continue
        fi
        # 2) SSH (stcx 시도)
        if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "$SSH_USER_DEFAULT@$n" 'echo OK' &>/dev/null; then
            echo -e "  ${RED}✗ SSH ($SSH_USER_DEFAULT@$n) 실패${NC}"
            FAIL_REASONS[ssh]=$((${FAIL_REASONS[ssh]:-0}+1))
            continue
        fi
        # 3) slurmd 상태
        SLURMD_STATE=$(ssh -o ConnectTimeout=3 "$SSH_USER_DEFAULT@$n" 'systemctl is-active slurmd 2>/dev/null' 2>/dev/null || echo "inactive")
        if [[ "$SLURMD_STATE" != "active" ]]; then
            echo -e "  ${RED}✗ slurmd $SLURMD_STATE${NC}"
            ssh -o ConnectTimeout=3 "$SSH_USER_DEFAULT@$n" 'sudo journalctl -u slurmd -n 5 --no-pager 2>&1' 2>/dev/null | sed 's/^/    /' | tail -5
            FAIL_REASONS[slurmd_dead]=$((${FAIL_REASONS[slurmd_dead]:-0}+1))
            [[ $FIX -eq 1 ]] && {
                echo -e "  ${BLUE}→ 자동 복구: slurmd 재시작${NC}"
                ssh -o ConnectTimeout=3 "$SSH_USER_DEFAULT@$n" 'sudo systemctl restart slurmd' &
            }
            continue
        fi
        # 4) slurmd 떠 있는데 unk → munge 키 / slurm.conf / 네트워크
        echo -e "  ${YELLOW}? slurmd active 인데 unk — munge 키 또는 conf 불일치 가능성${NC}"
        # munge 인증 테스트
        MUNGE_TEST=$(ssh -o ConnectTimeout=3 "$SSH_USER_DEFAULT@$n" \
            'munge -n 2>/dev/null | unmunge 2>&1 | grep -c SUCCESS' 2>/dev/null || echo 0)
        if [[ "$MUNGE_TEST" == "0" ]]; then
            echo -e "  ${RED}✗ munge 인증 실패 — 키 불일치${NC}"
            FAIL_REASONS[munge]=$((${FAIL_REASONS[munge]:-0}+1))
        fi
        # slurm.conf md5 비교
        LOCAL_HASH=$(md5sum /etc/slurm/slurm.conf 2>/dev/null | awk '{print $1}')
        NODE_HASH=$(ssh -o ConnectTimeout=3 "$SSH_USER_DEFAULT@$n" 'md5sum /etc/slurm/slurm.conf 2>/dev/null' 2>/dev/null | awk '{print $1}')
        if [[ -n "$LOCAL_HASH" && "$LOCAL_HASH" != "$NODE_HASH" ]]; then
            echo -e "  ${RED}✗ slurm.conf 불일치: local=$LOCAL_HASH remote=$NODE_HASH${NC}"
            FAIL_REASONS[conf_mismatch]=$((${FAIL_REASONS[conf_mismatch]:-0}+1))
        fi
    done

    echo ""
    echo -e "${BLUE}═══ 4) 실패 유형 요약 ═══${NC}"
    for k in "${!FAIL_REASONS[@]}"; do
        echo "  $k: ${FAIL_REASONS[$k]} 노드"
    done

    echo ""
    echo -e "${BLUE}═══ 5) 권장 조치 ═══${NC}"
    [[ -n "${FAIL_REASONS[network]:-}" ]] && echo "  • 네트워크 불가 노드: cluster/check_all_nodes.py 로 전체 진단"
    [[ -n "${FAIL_REASONS[ssh]:-}" ]] && echo "  • SSH 실패: 키 또는 ssh_password 확인"
    [[ -n "${FAIL_REASONS[slurmd_dead]:-}" ]] && echo "  • slurmd 죽음: sudo ./restart_slurm.sh --with-compute"
    [[ -n "${FAIL_REASONS[munge]:-}" ]] && echo "  • munge 키 불일치: phase3 재실행 또는 키 수동 sync"
    [[ -n "${FAIL_REASONS[conf_mismatch]:-}" ]] && echo "  • slurm.conf 불일치: phase10 (compute deploy) 재실행"
fi

echo ""
echo -e "${BLUE}═══ 6) 즉시 시도해볼 명령 ═══${NC}"
cat <<EOF
  # Slurm controller 강제 깨우기 (모든 노드 resume)
  sudo scontrol update nodename=ALL state=resume

  # 슬럼 헤드 + 컴퓨트 슬럼d 일괄 재시작
  sudo ./restart_slurm.sh --with-compute --config $YAML

  # 다시 상태 보기
  sinfo
EOF
