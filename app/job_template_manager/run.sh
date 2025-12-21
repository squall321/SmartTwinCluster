#!/bin/bash
################################################################################
# Job Template Manager 실행 스크립트
################################################################################

cd "$(dirname "$0")"

# venv 활성화
if [ ! -d "venv" ]; then
    echo "❌ venv가 없습니다. 먼저 설치를 진행하세요:"
    echo "   python3 -m venv venv"
    echo "   source venv/bin/activate"
    echo "   pip install -r requirements.txt"
    exit 1
fi

source venv/bin/activate

# PyQt5 설치 확인
if ! python -c "import PyQt5" 2>/dev/null; then
    echo "⚠️  PyQt5가 설치되지 않았습니다. 설치 중..."
    pip install -q PyQt5 PyYAML requests python-dateutil
fi

# 애플리케이션 실행
echo "🚀 Job Template Manager 시작 중..."
python src/main.py "$@"
