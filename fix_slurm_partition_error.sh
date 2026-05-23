#!/bin/bash
################################################################################
# 파티션 이름 문제 즉시 수정 및 재시작
################################################################################


# --config <yaml> 옵션 처리 (기본: my_multihead_cluster.yaml)
CONFIG_FILE="${CONFIG_FILE:-my_multihead_cluster.yaml}"
_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --config=*) CONFIG_FILE="${1#*=}"; shift ;;
        *) _args+=("$1"); shift ;;
    esac
done
set -- "${_args[@]+"${_args[@]}"}"
[[ ! -f "$CONFIG_FILE" ]] && { echo "❌ YAML 없음: $CONFIG_FILE"; echo "사용: $0 [--config <yaml>]"; exit 1; }
echo "📄 Config: $CONFIG_FILE"

echo "================================================================================"
echo "🚨 Slurm 시작 실패 수정 - 파티션 노드 이름"
echo "================================================================================"
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

echo "🔍 문제 진단:"
echo "  오류: fatal: Invalid node names in partition normal"
echo "  원인: YAML의 파티션 설정이 실제 노드 이름과 불일치"
echo ""
echo "  YAML 노드 이름: node001, node002"
echo "  YAML 파티션 설정: node[1-2] ← 잘못됨!"
echo "  올바른 설정: node[001-002]"
echo ""

# 1. YAML 수정
echo "================================================================================"
echo "Step 1/4: my_multihead_cluster.yaml 수정"
echo "================================================================================"
echo ""

BACKUP="my_multihead_cluster.yaml.backup_$(date +%Y%m%d_%H%M%S)"
cp my_multihead_cluster.yaml "$BACKUP"
echo "✅ 백업: $BACKUP"

sed -i 's/nodes: node\[1-2\]/nodes: node[001-002]/' my_multihead_cluster.yaml
sed -i 's/nodes: node1$/nodes: node001/' my_multihead_cluster.yaml

echo "✅ YAML 수정 완료"
echo ""
echo "변경 내용:"
grep -A 1 "name: normal" my_multihead_cluster.yaml | grep "nodes:"
grep -A 1 "name: debug" my_multihead_cluster.yaml | grep "nodes:"
echo ""

# 2. slurm.conf 재생성
echo "================================================================================"
echo "Step 2/4: slurm.conf 재생성"
echo "================================================================================"
echo ""

python3 configure_slurm_from_yaml.py

echo ""

# 3. 검증
echo "================================================================================"
echo "Step 3/4: 생성된 slurm.conf 검증"
echo "================================================================================"
echo ""

echo "NodeName 확인:"
grep "^NodeName" /usr/local/slurm/etc/slurm.conf
echo ""

echo "PartitionName 확인:"
grep "^PartitionName" /usr/local/slurm/etc/slurm.conf
echo ""

# 4. Slurm 재시작
echo "================================================================================"
echo "Step 4/4: Slurm 재시작"
echo "================================================================================"
echo ""

sudo systemctl restart slurmctld

sleep 3

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 시작 성공!"
    echo ""
    
    echo "🔍 상태 확인:"
    sinfo 2>/dev/null || /usr/local/slurm/bin/sinfo
    
else
    echo "❌ slurmctld 시작 실패"
    echo ""
    echo "로그 확인:"
    sudo journalctl -u slurmctld -n 20 --no-pager
fi

echo ""
echo "================================================================================"
echo "✅ 완료!"
echo "================================================================================"
echo ""
