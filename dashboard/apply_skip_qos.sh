#!/bin/bash
# QoS 건너뛰기 설정 스크립트(slurmdbd 미설치 환경)

echo "=========================================="
echo "🔧 QoS 건너뛰기 설정 (slurmdbd 미설치)"
echo "=========================================="
echo ""
echo "변경사항:"
echo "  - apply_full_configuration에 skip_qos 파라미터 추가"
echo "  - 기본값: skip_qos=True (QoS 건너뛰기)"
echo "  - QoS 없이 Partition만 설정"
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
echo "📝 이제 Apply Configuration을 테스트하세요:"
echo ""
echo "예상 동작:"
echo "  Step 1: QoS Management (SKIPPED)"
echo "  ⚠️  QoS creation skipped (slurmdbd not configured)"
echo "  Step 2: Updating Partitions"
echo "  ✅ Partitions updated"
echo "  ✅ Slurm reconfigured successfully"
echo "  ✅ 전체 성공!"
echo ""
echo "🔍 실시간 로그:"
echo "   tail -f backend_5010/backend.log | grep -E '(Step|QoS|Partition|⚠️|✅|❌)'"
echo ""
echo "📚 나중에 QoS를 활성화하려면:"
echo "   1. slurmdbd 설치 및 설정"
echo "      chmod +x setup_slurm_accounting.sh"
echo "      ./setup_slurm_accounting.sh"
echo ""
echo "   2. apply_full_configuration 호출 시 skip_qos=False 설정"
echo ""
