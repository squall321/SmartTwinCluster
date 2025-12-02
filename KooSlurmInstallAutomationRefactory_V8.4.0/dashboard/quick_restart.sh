#!/bin/bash

# Quick Backend restart script

echo "=========================================="
echo "🔄 Backend 빠른 재시작"
echo "=========================================="
echo ""

cd "$(dirname "$0")/backend_5010"

# 1. Stop
echo "1️⃣  Backend 중지..."
./stop.sh
sleep 1

# 2. Force kill port 5010
PIDS=$(lsof -ti :5010 2>/dev/null)
if [ -n "$PIDS" ]; then
    echo "2️⃣  포트 5010 강제 종료..."
    for PID in $PIDS; do
        kill -9 $PID 2>/dev/null
    done
    sleep 0.5
fi

# 3. Start in Production mode
echo "3️⃣  Backend 시작 (Production Mode)..."
export MOCK_MODE=false
./start.sh

echo ""
echo "=========================================="
echo "✅ 재시작 완료"
echo "=========================================="
echo ""
echo "대기 중..."
sleep 3

# 4. Check status
echo "4️⃣  API 상태 확인..."
cd ..
python3 check_api_status.py
