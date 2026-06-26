#!/bin/bash
# QoS 실패 무시 패치 적용 스크립트

echo "=========================================="
echo "🔧 QoS 실패 무시 패치 적용"
echo "=========================================="
echo ""
echo "변경사항:"
echo "  - QoS 생성 실패 시에도 Partition 설정 계속 진행"
echo "  - QoS 실패 시 slurm.conf에서 QoS 설정 제외"
echo "  - Partition 업데이트가 성공하면 전체 성공으로 처리"
echo ""

cd "$(dirname "$0")/backend_5010"

echo "1️⃣  Backend 재시작..."
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

echo ""
echo "=========================================="
echo "✅ Backend 재시작 완료"
echo "=========================================="
echo ""
echo "📝 이제 Apply Configuration을 다시 테스트하세요:"
echo ""
echo "예상 동작:"
echo "  1. QoS 생성 시도 (실패할 수 있음)"
echo "  2. ⚠️  경고 출력: \"QoS failed, but continuing...\""
echo "  3. Partition 업데이트 (성공)"
echo "  4. slurm.conf 업데이트 (QoS 설정 없이)"
echo "  5. Slurm reconfigure (성공)"
echo "  6. ✅ 전체 성공!"
echo ""
echo "🔍 로그 확인:"
echo "   tail -f backend_5010/backend.log | grep -E '(QoS|Partition|Step|⚠️|✅|❌)'"
echo ""
