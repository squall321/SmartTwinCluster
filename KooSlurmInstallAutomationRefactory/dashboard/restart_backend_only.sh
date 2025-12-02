#!/bin/bash

# Backend만 빠르게 재시작하는 스크립트

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "🔄 Backend 재시작 (Production Mode)"
echo "=========================================="
echo ""

cd "${SCRIPT_DIR}/backend_5010"

# 1. Backend 중지
echo "1️⃣  Backend 중지 중..."
./stop.sh
sleep 1

# 2. 포트 5010 강제 정리
echo ""
echo "2️⃣  포트 5010 정리 중..."
PIDS=$(lsof -ti :5010 2>/dev/null)
if [ -n "$PIDS" ]; then
    echo "   포트 5010 사용 중 (PIDs: $PIDS) - 강제 종료"
    for PID in $PIDS; do
        kill -9 $PID 2>/dev/null
    done
    sleep 0.5
fi

# 3. PID 파일 정리
rm -f .backend.pid

# 4. Production 모드로 재시작
echo ""
echo "3️⃣  Production 모드로 재시작..."
export MOCK_MODE=false
./start.sh

echo ""
echo "=========================================="
echo "✅ Backend 재시작 완료!"
echo "=========================================="
echo ""
echo "🔍 확인 방법:"
echo "  curl -s http://localhost:5010/api/jobs/templates | jq '.mode'"
echo ""
echo "📝 로그 확인:"
echo "  tail -f backend_5010/backend.log"
