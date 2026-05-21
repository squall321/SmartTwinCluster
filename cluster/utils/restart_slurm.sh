#!/bin/bash
################################################################################
# Slurm 서비스만 재시작 (munge → mariadb → slurmdbd → slurmctld → slurmd 순)
#
# 사용:
#   sudo ./cluster/utils/restart_slurm.sh                  # 헤드노드만
#   sudo ./cluster/utils/restart_slurm.sh --with-compute   # 컴퓨트 노드 slurmd 도 재시작
#   sudo ./cluster/utils/restart_slurm.sh --config my.yaml --with-compute
################################################################################
set -uo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}sudo 필요${NC}"; exit 1; }

CONFIG=""
WITH_COMPUTE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)        CONFIG="$2"; shift 2 ;;
        --with-compute|--compute) WITH_COMPUTE=1; shift ;;
        -h|--help)
            sed -n '/^# 사용/,/^####/p' "$0" | grep -v '^####' | sed 's/^# *//'
            exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

restart_one() {
    local svc="$1"
    if ! systemctl list-unit-files "$svc.service" --no-legend 2>/dev/null | grep -q "$svc"; then
        echo -e "  ${YELLOW}↩ $svc 설치 안됨, 스킵${NC}"
        return
    fi
    echo -ne "  → $svc ... "
    if systemctl restart "$svc" 2>/dev/null; then
        sleep 1
        if systemctl is-active --quiet "$svc"; then
            echo -e "${GREEN}active${NC}"
        else
            echo -e "${RED}fail (${YELLOW}journalctl -u $svc -n 20${RED})${NC}"
        fi
    else
        echo -e "${RED}restart 명령 실패${NC}"
    fi
}

echo -e "${BLUE}═══ 사전 점검 ═══${NC}"
# StateSaveLocation 권한 보정 (헤드만)
if [[ -f /etc/slurm/slurm.conf ]]; then
    STATE_DIR=$(grep -E '^[[:space:]]*StateSaveLocation' /etc/slurm/slurm.conf 2>/dev/null | head -1 | sed 's/.*=//' | tr -d ' ')
    if [[ -n "$STATE_DIR" ]]; then
        echo "  StateSaveLocation=$STATE_DIR"
        if [[ -d "$STATE_DIR" ]] && id slurm &>/dev/null; then
            SLURM_UID=$(id -u slurm)
            DIR_UID=$(stat -c '%u' "$STATE_DIR")
            if [[ "$DIR_UID" != "$SLURM_UID" ]]; then
                echo -e "  ${YELLOW}권한 root → slurm 으로 자동 복구${NC}"
                chown -R slurm:slurm "$(dirname "$STATE_DIR")"
                chmod 755 "$STATE_DIR" "$(dirname "$STATE_DIR")/log" "$(dirname "$STATE_DIR")/spool" 2>/dev/null || true
            fi
        fi
    fi
fi

echo ""
echo -e "${BLUE}═══ 헤드노드 서비스 재시작 ═══${NC}"
# 의존성 순서대로
restart_one munge
sleep 1
restart_one mariadb
sleep 2
restart_one slurmdbd
sleep 3
restart_one slurmctld
sleep 2
# slurmd가 헤드에도 있으면 (소형 클러스터)
restart_one slurmd 2>/dev/null || true

echo ""
echo -e "${BLUE}═══ sinfo ═══${NC}"
if command -v sinfo &>/dev/null; then
    timeout 10 sinfo 2>&1 | head -20 || echo -e "${RED}sinfo 응답 없음${NC}"
else
    echo "sinfo 없음 (Slurm 미설치)"
fi

# 컴퓨트 노드 slurmd 재시작
if [[ "$WITH_COMPUTE" == "1" ]]; then
    echo ""
    echo -e "${BLUE}═══ 컴퓨트 노드 slurmd 재시작 ═══${NC}"
    [[ -z "$CONFIG" ]] && CONFIG=$(ls *.yaml 2>/dev/null | grep -i multihead | head -1)
    [[ ! -f "$CONFIG" ]] && { echo -e "${RED}YAML 못 찾음 (--config 지정)${NC}"; exit 1; }

    NODE_INFO=$(python3 -c "
import yaml; c=yaml.safe_load(open('$CONFIG'))
for n in (c.get('nodes',{}).get('compute_nodes',[]) or []):
    print(n.get('hostname',''), n.get('ip_address',''), n.get('ssh_user','stcx'))
" 2>/dev/null)

    TOTAL=$(echo "$NODE_INFO" | grep -c .)
    OK=0; FAIL=0
    echo "  대상 노드 수: $TOTAL"

    # 병렬 SSH (8개씩) — 줄단위 처리
    RESULT_TMP=$(mktemp)
    echo "$NODE_INFO" | while read host ip user; do
        [ -z "$host" ] && continue
        echo "$host $ip $user"
    done | xargs -P8 -L1 bash -c '
        host="$1"; ip="$2"; user="$3"
        if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
               "$user@$ip" "sudo systemctl restart slurmd && sudo systemctl is-active --quiet slurmd" \
               >/dev/null 2>&1; then
            echo "OK $host"
        else
            echo "FAIL $host"
        fi
    ' _ > "$RESULT_TMP"

    OK_COUNT=$(grep -c "^OK " "$RESULT_TMP" 2>/dev/null || echo 0)
    FAIL_COUNT=$(grep -c "^FAIL " "$RESULT_TMP" 2>/dev/null || echo 0)
    echo -e "  ${GREEN}성공 ${OK_COUNT}${NC} / ${RED}실패 ${FAIL_COUNT}${NC}"
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}실패 노드 (앞 20개):${NC}"
        grep "^FAIL " "$RESULT_TMP" | awk '{print "    ✗ "$2}' | head -20
    fi
    rm -f "$RESULT_TMP"

    echo ""
    echo -e "  ${GREEN}성공${NC} / ${RED}실패${NC}: 진행 중... (위 출력 참고)"

    # 최종 sinfo
    sleep 3
    echo ""
    echo -e "${BLUE}═══ 최종 sinfo ═══${NC}"
    timeout 10 sinfo 2>&1 | head -10
fi

echo ""
echo -e "${GREEN}✅ 완료${NC}"
