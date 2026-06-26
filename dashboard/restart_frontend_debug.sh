#!/bin/bash
# 프론트엔드 재시작 스크립트(디버깅 모드)

echo "=========================================="
echo "🔄 Frontend 재시작 (디버깅 모드)"
echo "=========================================="

cd "$(dirname "$0")/frontend_3010"

echo "1️⃣  Frontend 중지..."
./stop.sh
sleep 1

# Force kill
PIDS=$(lsof -ti :3010 2>/dev/null)
if [ -n "$PIDS" ]; then
    echo "2️⃣  포트 3010 강제 종료..."
    for PID in $PIDS; do
        kill -9 $PID 2>/dev/null
    done
    sleep 0.5
fi

echo "3️⃣  캐시 삭제..."
rm -rf node_modules/.cache 2>/dev/null || true
rm -rf .next 2>/dev/null || true

echo "4️⃣  Frontend 시작..."
./start.sh

echo ""
echo "=========================================="
echo "✅ Frontend 재시작 완료"
echo "=========================================="
echo ""
echo "📝 다음 단계:"
echo "   1. 브라우저 Hard Reload: Ctrl + Shift + R"
echo "   2. F12 → Console 탭 열기"
echo "   3. Console을 비우기 (Clear)"
echo "   4. Cluster Management 접속"
echo "   5. Apply Configuration 클릭"
echo "   6. Console에서 다음 로그 확인:"
echo "      - slurmResult.success: ?"
echo "      - slurmResult.error: ?"
echo "      - Full response: {...}"
echo ""
