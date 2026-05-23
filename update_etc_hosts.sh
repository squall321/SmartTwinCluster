#!/bin/bash
################################################################################
# /etc/hosts 업데이트 스크립트
# my_multihead_cluster.yaml 기반으로 모든 노드의 /etc/hosts 자동 업데이트
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

set -e

echo "================================================================================"
echo "🌐 /etc/hosts 자동 업데이트 (YAML 기반)"
echo "================================================================================"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ my_multihead_cluster.yaml 파일을 찾을 수 없습니다."
    exit 1
fi

if [ ! -f "complete_slurm_setup.py" ]; then
    echo "❌ complete_slurm_setup.py 파일을 찾을 수 없습니다."
    exit 1
fi

echo "📝 모든 노드의 /etc/hosts를 업데이트합니다..."
echo "   - 컨트롤러: smarttwincluster"
echo "   - 계산 노드: node001, node002, viz-node001"
echo ""

# SSH 키 설정 + /etc/hosts만 업데이트
python3 complete_slurm_setup.py --only-hosts

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ /etc/hosts 업데이트 완료!"
    echo ""
    echo "검증:"
    for node in node001 node002 viz-node001; do
        echo "  📍 $node:"
        ssh koopark@$node "grep -E 'smarttwincluster|node00|viz-node' /etc/hosts | head -5" 2>/dev/null || echo "    ⚠️  연결 실패"
    done
else
    echo "❌ /etc/hosts 업데이트 실패"
    exit 1
fi

echo ""
echo "================================================================================"
