#!/bin/bash
# Groups API 테스트 스크립트

echo "Testing Groups API..."
echo ""

echo "1. Testing GET /api/groups"
curl -s http://localhost:5010/api/groups | jq '.'
echo ""
echo ""

echo "2. Testing GET /api/groups/partitions"
curl -s http://localhost:5010/api/groups/partitions | jq '.'
echo ""
