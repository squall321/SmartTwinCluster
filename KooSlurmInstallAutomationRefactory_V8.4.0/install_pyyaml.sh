#!/bin/bash

################################################################################
# PyYAML 설치 스크립트
# 
# Apptainer 동기화에 필요한 Python yaml 모듈을 설치합니다.
################################################################################

echo "🔧 Python yaml 모듈 설치 중..."
echo ""

# Python3 확인
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3가 설치되어 있지 않습니다"
    echo "   설치: sudo apt-get install python3"
    exit 1
fi

echo "✓ Python3 발견: $(python3 --version)"
echo ""

# yaml 모듈 확인
if python3 -c "import yaml" 2>/dev/null; then
    echo "✓ Python yaml 모듈이 이미 설치되어 있습니다"
    python3 -c "import yaml; print(f'   버전: {yaml.__version__}')"
    exit 0
fi

echo "⚠️  Python yaml 모듈이 설치되어 있지 않습니다"
echo ""
echo "설치 방법을 선택하세요:"
echo "  1) pip3로 설치 (권장)"
echo "  2) apt-get으로 설치"
echo ""
read -p "선택 (1 또는 2): " choice

case $choice in
    1)
        echo ""
        echo "→ pip3로 설치 중..."
        
        # pip3 확인
        if ! command -v pip3 &> /dev/null; then
            echo "⚠️  pip3가 없습니다. 먼저 pip3를 설치합니다..."
            sudo apt-get update
            sudo apt-get install -y python3-pip
        fi
        
        # pyyaml 설치
        pip3 install pyyaml
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✅ pyyaml 설치 완료!"
        else
            echo ""
            echo "❌ 설치 실패. 다음 명령을 시도해보세요:"
            echo "   sudo pip3 install pyyaml"
        fi
        ;;
    2)
        echo ""
        echo "→ apt-get으로 설치 중..."
        sudo apt-get update
        sudo apt-get install -y python3-yaml
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✅ python3-yaml 설치 완료!"
        else
            echo ""
            echo "❌ 설치 실패"
        fi
        ;;
    *)
        echo ""
        echo "❌ 잘못된 선택입니다"
        exit 1
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 설치 확인
if python3 -c "import yaml" 2>/dev/null; then
    echo "✨ 설치 확인 완료!"
    python3 -c "import yaml; print(f'   yaml 버전: {yaml.__version__}')"
    echo ""
    echo "다음 명령으로 계속 진행하세요:"
    echo "  ./sync_apptainers_to_nodes.sh"
else
    echo "❌ 설치 확인 실패"
    echo ""
    echo "수동 설치를 시도하세요:"
    echo "  pip3 install pyyaml"
    echo "또는:"
    echo "  sudo apt-get install python3-yaml"
fi

echo ""
