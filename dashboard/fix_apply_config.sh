#!/bin/bash
# Apply Configuration 문제 해결 스크립트

echo "=========================================="
echo "🔧 Apply Configuration 문제 해결"
echo "=========================================="
echo ""
echo "수정 사항:"
echo "  1. Backend: MOCK_MODE 동적 체크"
echo "  2. Backend: 상세 로깅 추가"
echo "  3. Frontend: Slurm API 호출 복원"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Backend 재시작
echo "1️⃣  Backend 재시작 (Production 모드)..."
cd "${SCRIPT_DIR}/backend_5010"
./stop.sh
sleep 1

# Force kill
PIDS=$(lsof -ti :5010 2>/dev/null)
if [ -n "$PIDS" ]; then
    for PID in $PIDS; do
        kill -9 $PID 2>/dev/null
    done
    sleep 0.5
fi

export MOCK_MODE=false
./start.sh
sleep 2

# 2. Frontend 재시작
echo ""
echo "2️⃣  Frontend 재시작..."
cd "${SCRIPT_DIR}/frontend_3010"
./stop.sh
sleep 1

# Force kill
PIDS=$(lsof -ti :3010 2>/dev/null)
if [ -n "$PIDS" ]; then
    for PID in $PIDS; do
        kill -9 $PID 2>/dev/null
    done
    sleep 0.5
fi

./start.sh
sleep 2

echo ""
echo "=========================================="
echo "✅ 재시작 완료"
echo "=========================================="
echo ""
echo "📝 테스트 방법:"
echo ""
echo "1. Cluster Management 접속"
echo "   http://localhost:3010 → System Management"
echo ""
echo "2. 그룹 설정 변경"
echo "   - Group 1 선택"
echo "   - allowedCoreSizes 수정 (예: 8192 추가)"
echo "   - Description 변경"
echo ""
echo "3. Apply Configuration 클릭"
echo "   ✅ 성공 시: \"Configuration applied successfully\" 메시지"
echo "   ❌ 실패 시: Backend 로그 확인"
echo ""
echo "4. Backend 로그 실시간 모니터링"
echo "   tail -f ${SCRIPT_DIR}/backend_5010/backend.log"
echo ""
echo "5. 실패 시 로그 확인:"
echo "   - \"🚀 Production Mode: Applying real configuration...\""
echo "   - \"Calling apply_full_configuration...\""
echo "   - 에러 메시지 및 traceback"
echo ""
echo "6. Job Templates 확인"
echo "   Job Templates → New Template → Partition 드롭다운"
echo "   → 변경사항 반영 확인"
echo ""
echo "=========================================="
echo "🔍 실시간 로그 보기 (별도 터미널)"
echo "=========================================="
echo "tail -f ${SCRIPT_DIR}/backend_5010/backend.log"
echo ""
