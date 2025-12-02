#!/bin/bash

# 클러스터 그룹 동기화 적용 스크립트

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "🔄 클러스터 그룹 동기화 적용"
echo "=========================================="
echo ""
echo "이 스크립트는 다음을 수행합니다:"
echo "  1. Backend 중지"
echo "  2. 기존 데이터베이스 백업"
echo "  3. 데이터베이스 재생성 (초기 클러스터 설정 포함)"
echo "  4. Backend 재시작 (Production 모드)"
echo "  5. 그룹 동기화 검증"
echo ""
read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 1
fi

# 1. Backend 중지
echo ""
echo "1️⃣  Backend 중지 중..."
cd "${SCRIPT_DIR}/backend_5010"
./stop.sh
sleep 1

# 2. 데이터베이스 백업
if [ -f "database/dashboard.db" ]; then
    echo ""
    echo "2️⃣  기존 데이터베이스 백업 중..."
    BACKUP_FILE="database/dashboard.db.backup_$(date +%Y%m%d_%H%M%S)"
    cp database/dashboard.db "$BACKUP_FILE"
    echo "   ✅ 백업 완료: $BACKUP_FILE"
fi

# 3. 데이터베이스 삭제
echo ""
echo "3️⃣  기존 데이터베이스 삭제 중..."
rm -f database/dashboard.db
echo "   ✅ 삭제 완료"

# 4. 데이터베이스 초기화
echo ""
echo "4️⃣  새 데이터베이스 초기화 중..."
cd "${SCRIPT_DIR}"
python3 -c "
import sys
sys.path.insert(0, 'backend_5010')
from database import init_database
init_database()
print('✅ 데이터베이스 초기화 완료')
"

# 5. Template JSON 검증
echo ""
echo "5️⃣  Template JSON 검증 중..."
python3 check_template_json.py 2>/dev/null | grep -E "(Template:|Valid|Invalid)" || echo "   ✅ 템플릿 확인 완료"

# 6. Backend 재시작
echo ""
echo "6️⃣  Backend 재시작 중 (Production Mode)..."
cd "${SCRIPT_DIR}/backend_5010"
export MOCK_MODE=false
./start.sh

# 7. Backend 시작 대기
echo ""
echo "7️⃣  Backend 시작 대기 중..."
sleep 3

# 8. 그룹 동기화 검증
echo ""
echo "8️⃣  그룹 동기화 검증 중..."
cd "${SCRIPT_DIR}"
python3 verify_groups_sync.py

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ 완료! 그룹 동기화 성공"
    echo "=========================================="
    echo ""
    echo "🔍 추가 검증:"
    echo "  # Cluster Config"
    echo "  curl -s http://localhost:5010/api/cluster/config | jq '.config.groups[] | {name, partitionName, allowedCoreSizes}'"
    echo ""
    echo "  # Groups API"
    echo "  curl -s http://localhost:5010/api/groups | jq '.groups[] | {name, partitionName, allowedCoreSizes}'"
    echo ""
    echo "  # Partitions API"
    echo "  curl -s http://localhost:5010/api/groups/partitions | jq '.partitions[] | {label, name, allowedCoreSizes}'"
else
    echo ""
    echo "=========================================="
    echo "❌ 그룹 동기화 검증 실패"
    echo "=========================================="
    echo ""
    echo "문제 해결:"
    echo "  1. Backend 로그 확인: tail -f backend_5010/backend.log"
    echo "  2. API 수동 확인: curl http://localhost:5010/api/groups"
    echo "  3. 데이터베이스 확인: python3 -c 'from backend_5010.database import get_db_connection; ...'"
fi

exit $EXIT_CODE
