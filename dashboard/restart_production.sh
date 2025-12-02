#!/bin/bash

# Production 모드로 서비스 재시작 스크립트

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "🔄 Production 모드로 재시작"
echo "=========================================="
echo ""

# 1. 모든 서비스 중지
echo "1️⃣  모든 서비스 중지 중..."
cd "$SCRIPT_DIR"
./stop_all.sh
sleep 2

# 2. 확실하게 포트 정리
echo ""
echo "2️⃣  포트 정리 중..."
for PORT in 3010 5010 5011 9100 9090; do
    PIDS=$(lsof -ti :$PORT 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo "   포트 $PORT 강제 종료 (PIDs: $PIDS)"
        for PID in $PIDS; do
            kill -9 $PID 2>/dev/null
        done
    fi
done

# 3. PID 파일 정리
echo ""
echo "3️⃣  PID 파일 정리 중..."
find . -name "*.pid" -type f -exec rm -f {} \; 2>/dev/null

sleep 2

# 4. Production 모드로 시작
echo ""
echo "4️⃣  Production 모드로 시작..."
export MOCK_MODE=false
./start_all.sh

echo ""
echo "=========================================="
echo "✅ 재시작 완료!"
echo "=========================================="
echo ""
echo "확인 방법:"
echo "  curl http://localhost:5010/api/jobs/templates | jq '.mode'"
echo ""
echo "로그 확인:"
echo "  tail -f backend_5010/backend.log | grep -i mode"
