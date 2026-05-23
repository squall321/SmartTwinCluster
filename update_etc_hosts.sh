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

# paramiko 보장 (오프라인 apt 우선, 실패 시 휠로 폴백)
if ! python3 -c "import paramiko" 2>/dev/null; then
    echo "⚠️ python3-paramiko 미설치 → 오프라인 패키지로 자동 설치"
    if sudo apt install -y python3-paramiko 2>/dev/null; then
        echo "✓ apt 설치 완료"
    else
        # .deb 직접
        for d in offline_packages_2404/apt_packages offline_packages/apt_packages; do
            f=$(ls "$d"/python3-paramiko_*.deb 2>/dev/null | head -1)
            [ -n "$f" ] && sudo apt install -y "$f" && break
        done
    fi
    # 그래도 안 되면 휠 + --break-system-packages
    if ! python3 -c "import paramiko" 2>/dev/null; then
        for d in offline_packages_2404/python_wheels/python3.12 \
                 offline_packages_2404/python_wheels \
                 offline_packages/python_wheels; do
            [ -d "$d" ] || continue
            sudo python3 -m pip install --no-index --find-links="$d" \
                --break-system-packages paramiko 2>&1 | tail -3 && break
        done
    fi
    python3 -c "import paramiko" 2>/dev/null && echo "✓ paramiko OK" \
        || { echo "❌ paramiko 설치 최종 실패"; exit 1; }
fi

# SSH 키 설정 + /etc/hosts만 업데이트
python3 complete_slurm_setup.py --only-hosts --config "$CONFIG_FILE"

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
