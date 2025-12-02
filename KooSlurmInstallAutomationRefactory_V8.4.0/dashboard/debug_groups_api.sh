#!/bin/bash

echo "=========================================="
echo "Groups API 연동 디버깅"
echo "=========================================="
echo ""

# 1. 백엔드 프로세스 확인
echo "1. 백엔드 프로세스 확인:"
ps aux | grep "python.*app.py" | grep -v grep
echo ""

# 2. 포트 5010 확인
echo "2. 포트 5010 리스닝 확인:"
netstat -tln | grep 5010 || lsof -i :5010
echo ""

# 3. Health check
echo "3. Health Check:"
curl -s http://localhost:5010/api/health | jq '.'
echo ""

# 4. Groups API 테스트
echo "4. Groups API 테스트:"
echo "   GET /api/groups/partitions"
curl -s http://localhost:5010/api/groups/partitions
echo ""
echo ""

# 5. CORS 헤더 확인
echo "5. CORS 헤더 확인:"
curl -s -I http://localhost:5010/api/groups/partitions | grep -i "access-control"
echo ""

echo "=========================================="
echo "디버깅 완료"
echo "=========================================="
