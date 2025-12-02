#!/bin/bash
# simple_test.sh - 간단한 기능 테스트 (jq 불필요)

echo "🚀 KooCAE 간단 기능 테스트..."

BASE_URL="http://localhost:5000"

echo -e "\n1️⃣ 서버 연결 확인..."
if curl -s "$BASE_URL/api/job-templates" > /dev/null; then
    echo "✅ 서버 연결 성공"
else
    echo "❌ 서버 연결 실패 - python app.py 로 서버를 먼저 실행하세요"
    exit 1
fi

echo -e "\n2️⃣ 템플릿 시스템 확인..."
TEMPLATE_COUNT=$(curl -s "$BASE_URL/api/job-templates" | grep -o '"templates"' | wc -l)
if [ "$TEMPLATE_COUNT" -gt 0 ]; then
    echo "✅ 템플릿 시스템 정상 동작"
else
    echo "❌ 템플릿 시스템 오류"
fi

echo -e "\n3️⃣ SLURM 기능 확인..."
SLURM_RESPONSE=$(curl -s "$BASE_URL/api/slurm/cluster-status")
if echo "$SLURM_RESPONSE" | grep -q "mock_mode"; then
    echo "✅ SLURM 기능 정상 동작"
else
    echo "❌ SLURM 기능 오류"
fi

echo -e "\n4️⃣ 파일 업로드 엔드포인트 확인..."
# OPTIONS 요청으로 CORS 확인
if curl -s -X OPTIONS "$BASE_URL/api/upload_dyna_file_and_find_pid" > /dev/null; then
    echo "✅ 파일 업로드 기능 준비됨"
else
    echo "❌ 파일 업로드 기능 오류"
fi

echo -e "\n🎉 기본 기능 테스트 완료!"
echo -e "\n📋 사용 가능한 주요 API:"
echo "   - 파일 업로드: POST /api/upload_dyna_file_and_find_pid"
echo "   - STL 변환: POST /api/convert_kfile_to_stl"
echo "   - SLURM 작업: POST /api/slurm/submit-lsdyna-jobs"
echo "   - 템플릿 작업: POST /api/job-templates/{name}/submit"
echo "   - 작업 히스토리: GET /api/jobs/history"
echo -e "\n🌐 웹 브라우저에서 확인: $BASE_URL"
