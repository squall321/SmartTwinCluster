#!/bin/bash
################################################################################
# YAML 기반 Slurm 설정 파일 생성 래퍼 스크립트
# Python 스크립트를 호출하여 모든 설정을 YAML에서 읽어옵니다.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "🔧 Slurm 설정 파일 생성 (YAML 기반)"
echo "================================================================================"
echo ""
echo "📝 설정 파일: my_cluster.yaml"
echo "📍 위치: $SCRIPT_DIR"
echo ""

# YAML 파일 존재 확인
if [ ! -f "my_cluster.yaml" ]; then
    echo "❌ my_cluster.yaml 파일을 찾을 수 없습니다!"
    echo ""
    echo "💡 다음 중 하나를 실행하세요:"
    echo "  1. 예시 파일 복사:"
    echo "     cp examples/2node_example.yaml my_cluster.yaml"
    echo ""
    echo "  2. 템플릿 생성:"
    echo "     python3 generate_config.py"
    echo ""
    exit 1
fi

# Python 스크립트 존재 확인
if [ ! -f "configure_slurm_from_yaml.py" ]; then
    echo "❌ configure_slurm_from_yaml.py 파일을 찾을 수 없습니다!"
    exit 1
fi

# 가상환경 확인 (선택사항)
if [ -d "venv" ]; then
    echo "🐍 가상환경 활성화 중..."
    source venv/bin/activate
    echo "✅ 가상환경 활성화됨"
    echo ""
fi

# Python으로 설정 파일 생성
echo "🚀 Python 스크립트 실행 중..."
echo ""

python3 configure_slurm_from_yaml.py -c my_cluster.yaml

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ 설정 파일 생성 성공!"
    exit 0
else
    echo ""
    echo "❌ 설정 파일 생성 실패 (종료 코드: $EXIT_CODE)"
    exit 1
fi
