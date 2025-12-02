#!/bin/bash

echo "================================================================================"
echo "🔄 Node Management API 재시작"
echo "================================================================================"
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# 기존 프로세스 종료
echo "🛑 Step 1/3: 기존 백엔드 프로세스 종료 중..."
pkill -f 'python.*app.py' && echo "  ✅ 기존 프로세스 종료됨" || echo "  ⚠️  실행 중인 프로세스가 없습니다"
sleep 2
echo ""

# 가상환경 활성화 및 백엔드 시작
echo "🚀 Step 2/3: 백엔드 시작 중..."
if [ ! -d "venv" ]; then
    echo "  ❌ venv가 없습니다. 먼저 가상환경을 생성하세요:"
    echo "     python3 -m venv venv"
    echo "     source venv/bin/activate"
    echo "     pip install -r requirements.txt"
    exit 1
fi

source venv/bin/activate

# 백그라운드로 실행
nohup python app.py > backend.log 2>&1 &
BACKEND_PID=$!

echo "  ✅ 백엔드 시작됨 (PID: $BACKEND_PID)"
echo "  📄 로그: backend.log"
echo ""

# 시작 대기
echo "⏳ Step 3/3: 백엔드 시작 확인 중..."
sleep 3

# Health check
if curl -s http://localhost:5010/api/nodes > /dev/null 2>&1; then
    echo "  ✅ 백엔드가 정상적으로 시작되었습니다!"
    echo ""
    echo "================================================================================
"
    echo "✅ 완료!"
    echo "================================================================================"
    echo ""
    echo "📊 확인 방법:"
    echo "  1. 노드 목록: curl http://localhost:5010/api/nodes | jq ."
    echo "  2. 로그 확인: tail -f backend.log"
    echo "  3. 프론트엔드: http://localhost:3010"
    echo ""
else
    echo "  ❌ 백엔드 시작 실패"
    echo ""
    echo "로그 확인:"
    tail -20 backend.log
    exit 1
fi
