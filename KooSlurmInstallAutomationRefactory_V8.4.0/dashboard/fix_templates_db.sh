#!/bin/bash

# 데이터베이스 초기화 및 재시작 스크립트

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "🔄 Database 초기화 및 서비스 재시작"
echo "=========================================="
echo ""

# 1. Backend 중지
echo "1️⃣  Backend 중지 중..."
cd "${SCRIPT_DIR}/backend_5010"
./stop.sh
sleep 1

# 2. 데이터베이스 백업
if [ -f "database/dashboard.db" ]; then
    echo ""
    echo "2️⃣  기존 데이터베이스 백업 중..."
    cp database/dashboard.db database/dashboard.db.backup_$(date +%Y%m%d_%H%M%S)
    echo "   ✅ 백업 완료"
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

# 5. JSON 검증
echo ""
echo "5️⃣  Template JSON 검증 중..."
python3 check_template_json.py

# 6. Backend 재시작
echo ""
echo "6️⃣  Backend 재시작 중 (Production Mode)..."
cd "${SCRIPT_DIR}/backend_5010"
export MOCK_MODE=false
./start.sh

echo ""
echo "=========================================="
echo "✅ 완료!"
echo "=========================================="
echo ""
echo "🔍 검증:"
echo "  curl -s http://localhost:5010/api/jobs/templates | jq '.'"
echo ""
echo "📊 템플릿 개수 확인:"
echo "  curl -s http://localhost:5010/api/jobs/templates | jq '.count'"
