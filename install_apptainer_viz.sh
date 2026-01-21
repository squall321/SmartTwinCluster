#!/bin/bash
# viz 노드에 apptainer 설치 스크립트

set -euo pipefail

echo "=========================================="
echo "viz 노드 apptainer 설치"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPTAINER_DEB="$SCRIPT_DIR/offline_packages/apt_packages/apptainer_1.4.5-1~jammy_amd64.deb"

# apptainer 패키지 확인
if [[ ! -f "$APPTAINER_DEB" ]]; then
    echo "ERROR: apptainer 패키지를 찾을 수 없습니다: $APPTAINER_DEB"
    exit 1
fi

echo "apptainer 패키지: $APPTAINER_DEB"
echo ""

# viz 노드 찾기
YAML_FILE=""
for file in my_multihead_cluster.yaml my_multihead_cluster_2.yaml cluster_config.yaml; do
    if [[ -f "$file" ]]; then
        YAML_FILE="$file"
        break
    fi
done

if [[ -z "$YAML_FILE" ]]; then
    echo "ERROR: YAML 설정 파일을 찾을 수 없습니다"
    exit 1
fi

echo "YAML 파일: $YAML_FILE"
echo ""

VIZ_NODES=$(python3 << EOPY
import yaml
import sys
try:
    with open('$YAML_FILE', 'r') as f:
        config = yaml.safe_load(f)

    nodes = config.get('nodes', {})
    compute_nodes = nodes.get('compute_nodes', [])
    viz_nodes = [n for n in compute_nodes if n.get('node_type') == 'viz']

    for node in viz_nodes:
        print(node.get('hostname'))
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
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

# 각 viz 노드에 설치
for node in $VIZ_NODES; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Installing apptainer on: $node"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # SSH 연결 테스트
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" "echo SSH OK" &>/dev/null; then
        echo "  ✗ SSH 연결 실패"
        echo ""
        continue
    fi

    echo "  ✓ SSH 연결 성공"
    echo ""

    # apptainer가 이미 설치되어 있는지 확인
    if ssh "$node" "which apptainer" &>/dev/null; then
        CURRENT_VERSION=$(ssh "$node" "apptainer --version" 2>/dev/null || echo "unknown")
        echo "  ℹ apptainer 이미 설치됨: $CURRENT_VERSION"
        echo "  재설치하시겠습니까? (y/N)"
        read -r answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            echo "  건너뜀"
            echo ""
            continue
        fi
    fi

    # 패키지 복사
    echo "  패키지 복사 중..."
    scp -q "$APPTAINER_DEB" "$node:/tmp/" || {
        echo "  ✗ 패키지 복사 실패"
        echo ""
        continue
    }
    echo "  ✓ 패키지 복사 완료"

    # 설치
    echo "  apptainer 설치 중..."
    ssh "$node" << 'EOFREMOTE'
        set -e

        # 의존성 설치 (필요시)
        echo "    의존성 확인 중..."
        sudo apt-get update -qq || true

        # apptainer 설치
        echo "    dpkg로 설치 중..."
        sudo dpkg -i /tmp/apptainer_1.4.5-1~jammy_amd64.deb 2>/dev/null || {
            echo "    의존성 문제 해결 중..."
            sudo apt-get install -f -y -qq
        }

        # 설치 확인
        if which apptainer &>/dev/null; then
            VERSION=$(apptainer --version)
            echo "    ✓ 설치 완료: $VERSION"
        else
            echo "    ✗ 설치 실패"
            exit 1
        fi

        # 임시 파일 삭제
        rm -f /tmp/apptainer_1.4.5-1~jammy_amd64.deb
EOFREMOTE

    if [[ $? -eq 0 ]]; then
        echo "  ✓ $node apptainer 설치 성공"
    else
        echo "  ✗ $node apptainer 설치 실패"
    fi
    echo ""
done

# /scratch/vnc_sandboxes 디렉토리 생성
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VNC sandbox 디렉토리 생성"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for node in $VIZ_NODES; do
    echo "  $node: /scratch/vnc_sandboxes"
    ssh "$node" "sudo mkdir -p /scratch/vnc_sandboxes && sudo chmod 1777 /scratch/vnc_sandboxes" 2>/dev/null || echo "    ✗ 실패"
done
echo ""

echo "=========================================="
echo "완료!"
echo "=========================================="
echo ""
echo "설치 확인:"
for node in $VIZ_NODES; do
    echo "  ssh $node 'apptainer --version'"
done
echo ""
