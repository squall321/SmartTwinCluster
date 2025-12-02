#!/bin/bash

echo "=========================================="
echo "🔄 Frontend 재시작"
echo "=========================================="
echo ""

cd "$(dirname "$0")/frontend_3010"

# 1. Stop
echo "1️⃣  Frontend 중지..."
./stop.sh
sleep 1

# 2. Force kill port 3010
PIDS=$(lsof -ti :3010 2>/dev/null)
if [ -n "$PIDS" ]; then
    echo "2️⃣  포트 3010 강제 종료..."
    for PID in $PIDS; do
        kill -9 $PID 2>/dev/null
    done
    sleep 0.5
fi

# 3. Start
echo "3️⃣  Frontend 시작..."
./start.sh

echo ""
echo "=========================================="
echo "✅ Frontend 재시작 완료"
echo "=========================================="
echo ""
echo "🌐 브라우저에서 확인:"
echo "   http://localhost:3010"
echo ""
echo "📝 Apply Configuration 테스트:"
echo "   1. System Management → Cluster Management"
echo "   2. 그룹 설정 변경"
echo "   3. 'Apply Configuration' 클릭"
echo "   4. 성공 메시지 확인"
echo "   5. Job Templates에서 변경사항 확인"
