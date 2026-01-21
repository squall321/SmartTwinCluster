#!/bin/bash
# viz 노드에 /shared/logs 디렉토리 생성 (긴급 수정)

echo "=========================================="
echo "viz 노드 /shared/logs 디렉토리 생성"
echo "=========================================="
echo ""

# 인자로 노드 지정 가능
if [[ $# -gt 0 ]]; then
    VIZ_NODES="$@"
    echo "인자로 지정된 viz 노드:"
    for node in $VIZ_NODES; do
        echo "  - $node"
    done
    echo ""
else
    echo "YAML 파일에서 viz 노드 자동 검색..."
    echo ""

# YAML 파일 찾기
YAML_FILE=""
for file in my_multihead_cluster.yaml my_multihead_cluster_2.yaml cluster_config.yaml; do
    if [[ -f "$file" ]]; then
        YAML_FILE="$file"
        break
    fi
done

if [[ -z "$YAML_FILE" ]]; then
    echo "ERROR: YAML 설정 파일을 찾을 수 없습니다"
    echo "현재 디렉토리의 YAML 파일:"
    ls -la *.yaml 2>/dev/null || echo "  YAML 파일 없음"
    exit 1
fi

echo "사용 중인 YAML 파일: $YAML_FILE"
echo ""

VIZ_NODES=$(python3 << EOPY
import yaml
import sys
try:
    with open('$YAML_FILE', 'r') as f:
        config = yaml.safe_load(f)

    nodes = config.get('nodes', {})

    # viz_nodes 섹션 확인 (구 버전)
    viz_nodes = nodes.get('viz_nodes', [])

    # compute_nodes 안에서 node_type=viz 찾기 (신 버전)
    if not viz_nodes:
        compute_nodes = nodes.get('compute_nodes', [])
        viz_nodes = [n for n in compute_nodes if n.get('node_type') == 'viz']

    for node in viz_nodes:
        print(node.get('hostname'))
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
EOPY
)

    if [[ -z "$VIZ_NODES" ]]; then
        echo "ERROR: viz 노드를 찾을 수 없습니다"
        echo ""
        echo "사용법:"
        echo "  $0 <viz-node1> [viz-node2] ..."
        echo ""
        echo "예시:"
        echo "  $0 viz-node001"
        echo "  $0 viz-node001 viz-node002"
        exit 1
    fi
fi

echo "viz 노드 목록:"
for node in $VIZ_NODES; do
    echo "  - $node"
done
echo ""

# 각 viz 노드에 /shared/logs 생성
for node in $VIZ_NODES; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Processing: $node"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # SSH 연결 테스트
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" "echo SSH OK" &>/dev/null; then
        echo "  ✗ SSH 연결 실패"
        echo ""
        continue
    fi

    echo "  ✓ SSH 연결 성공"

    # /shared 상태 확인
    echo ""
    echo "  현재 /shared 상태:"
    ssh "$node" "ls -la / | grep shared" || echo "    /shared 없음"
    echo ""

    # /shared/logs 생성
    echo "  /shared/logs 디렉토리 생성..."
    ssh "$node" << 'EOFREMOTE'
        # /shared가 없으면 생성
        if [[ ! -e /shared ]]; then
            echo "    Creating /shared directory..."
            sudo mkdir -p /shared
        fi

        # /shared/logs가 없으면 생성
        if [[ ! -e /shared/logs ]]; then
            echo "    Creating /shared/logs directory..."
            sudo mkdir -p /shared/logs
            sudo chmod 1777 /shared/logs
            echo "    ✓ Created /shared/logs"
        else
            echo "    /shared/logs already exists"
            ls -ld /shared/logs
        fi

        # /shared/jobs도 생성
        if [[ ! -e /shared/jobs ]]; then
            echo "    Creating /shared/jobs directory..."
            sudo mkdir -p /shared/jobs
            sudo chmod 1777 /shared/jobs
            echo "    ✓ Created /shared/jobs"
        fi

        # 최종 확인
        echo ""
        echo "    Final status:"
        ls -la /shared/
EOFREMOTE

    echo ""
done

echo "=========================================="
echo "완료!"
echo "=========================================="
echo ""
echo "다음 단계:"
echo "  1. VNC 세션 다시 시작 테스트"
echo "  2. 로그 파일 확인: ls -la /shared/logs/"
echo ""
echo "참고:"
echo "  - 이 스크립트는 임시 수정입니다"
echo "  - 나중에 viz 노드 재배포 시 자동으로 생성됩니다"
echo "  - deploy_to_compute_node.sh 업데이트 완료"
echo ""
