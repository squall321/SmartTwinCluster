#!/bin/bash
################################################################################
# my_multihead_cluster.yaml 파티션 이름 수정
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
echo "🔧 my_multihead_cluster.yaml 파티션 노드 이름 수정"
echo "================================================================================"
echo ""

echo "❌ 문제: 파티션의 nodes 설정이 잘못됨"
echo "   현재: node[1-2]"
echo "   실제 노드: node001, node002"
echo ""
echo "✅ 수정: node[001-002]"
echo ""

# 백업
BACKUP="my_multihead_cluster.yaml.backup_$(date +%Y%m%d_%H%M%S)"
cp my_multihead_cluster.yaml "$BACKUP"
echo "✅ 백업 생성: $BACKUP"
echo ""

# 수정
sed -i 's/nodes: node\[1-2\]/nodes: node[001-002]/' my_multihead_cluster.yaml
sed -i 's/nodes: node1$/nodes: node001/' my_multihead_cluster.yaml

echo "✅ my_multihead_cluster.yaml 수정 완료"
echo ""

echo "📋 변경 내용:"
echo "--------------------------------------------------------------------------------"
grep -A 5 "partitions:" my_multihead_cluster.yaml | grep "nodes:"
echo "--------------------------------------------------------------------------------"
echo ""

echo "================================================================================"
echo "🔄 다음 단계"
echo "================================================================================"
echo ""
echo "1. slurm.conf 재생성:"
echo "   python3 configure_slurm_from_yaml.py"
echo ""
echo "2. 설정 배포:"
echo "   ./sync_config_to_nodes.sh"
echo ""
echo "3. Slurm 재시작:"
echo "   sudo systemctl restart slurmctld"
echo ""
echo "================================================================================"
