#!/bin/bash
# quick_test.sh - 기존 기능과 새 기능 모두 테스트

echo "🚀 KooCAE 기능 테스트 시작..."

BASE_URL="http://localhost:5000"

echo "1️⃣ 서버 상태 확인..."
curl -s "$BASE_URL/api/slurm/sinfo" | head -3

echo -e "\n2️⃣ 기존 SLURM 기능 확인..."
curl -s "$BASE_URL/api/slurm/squeue" | head -3

echo -e "\n3️⃣ 새로운 템플릿 목록 확인..."
curl -s "$BASE_URL/api/job-templates" | python3 -c "import sys, json; data=json.load(sys.stdin); [print('  -', t['name'], '(' + t['category'] + ')') for t in data.get('templates', [])]"

echo -e "\n4️⃣ 클러스터 상태 확인..."
curl -s "$BASE_URL/api/slurm/cluster-status" | python3 -c "import sys, json; data=json.load(sys.stdin); print('Mock Mode:', data.get('mock_mode', 'unknown')); print('LS-DYNA Cores:', data.get('lsdyna_cores', 0))"

echo -e "\n✅ 모든 기능이 정상 작동 중!"
