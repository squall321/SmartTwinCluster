#!/bin/bash
# viz 노드에 /shared/logs 디렉토리 생성 (긴급 수정)

echo "=========================================="
echo "viz 노드 /shared/logs 디렉토리 생성"
echo "=========================================="
echo ""

# YAML에서 viz 노드 목록 가져오기
if [[ ! -f my_multihead_cluster_2.yaml ]]; then
    echo "ERROR: my_multihead_cluster_2.yaml 파일이 없습니다"
    exit 1
fi

VIZ_NODES=$(python3 << 'EOPY'
import yaml
try:
    with open('my_multihead_cluster_2.yaml', 'r') as f:
        config = yaml.safe_load(f)

    viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
    for node in viz_nodes:
        print(node.get('hostname'))
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
EOPY
)

if [[ -z "$VIZ_NODES" ]]; then
    echo "ERROR: viz 노드를 찾을 수 없습니다"
    exit 1
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
